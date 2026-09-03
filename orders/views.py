from django.core.exceptions import PermissionDenied, ValidationError
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied as DRFPermissionDenied
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from users.permissions import (
    IsGerant,
    get_accessible_magasins,
    resolve_magasin_for_request,
    user_commande_role,
)

from . import services
from .models import Order
from .serializers import (
    OrderCreateSerializer,
    OrderGerantSerializer,
    OrderLivreurSerializer,
    OrderPreparateurSerializer,
    OrderStatusChangeSerializer,
)

# Statuts visibles par rôle sur leur module dédié (§7.2, §7.3 Smartreadme.md).
PREPARATEUR_STATUTS = ["NOUVELLE", "EN_PREPARATION"]
LIVREUR_STATUTS = ["PRETE", "EN_LIVRAISON"]


class OrderViewSet(viewsets.ModelViewSet):
    http_method_names = ["get", "post", "head", "options"]  # pas d'update/delete direct : tout passe par /status/
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action == "create":
            return [IsGerant()]
        return super().get_permissions()

    def get_serializer_class(self):
        if self.action == "create":
            return OrderCreateSerializer
        role = user_commande_role(self.request.user)
        if role == "PREPARATEUR":
            return OrderPreparateurSerializer
        if role == "LIVREUR":
            return OrderLivreurSerializer
        return OrderGerantSerializer

    def get_queryset(self):
        qs = Order.objects.filter(magasin__in=get_accessible_magasins(self.request.user)).prefetch_related(
            "items", "items__product_variant__product_reference", "status_history"
        )
        role = user_commande_role(self.request.user)

        if role == "PREPARATEUR":
            return qs.filter(statut_courant__in=PREPARATEUR_STATUTS)
        if role == "LIVREUR":
            # Prêtes à récupérer + en livraison du jour (§7.3 Smartreadme.md).
            return qs.filter(statut_courant__in=LIVREUR_STATUTS)

        # Gérant : filtres optionnels date / statut / magasin (§7.1 Smartreadme.md).
        statut = self.request.query_params.get("statut")
        date_debut = self.request.query_params.get("date_debut")
        date_fin = self.request.query_params.get("date_fin")
        magasin_id = self.request.query_params.get("magasin_id")
        if statut:
            qs = qs.filter(statut_courant=statut)
        if date_debut:
            # `__date` : date_commande est un datetime — comparer uniquement
            # la date pour que date_fin inclue toute la journée (pas juste minuit).
            qs = qs.filter(date_commande__date__gte=date_debut)
        if date_fin:
            qs = qs.filter(date_commande__date__lte=date_fin)
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = OrderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        magasin = resolve_magasin_for_request(request)

        order = services.create_order(
            magasin=magasin,
            client_nom=data["client_nom"],
            telephone=data["telephone"],
            livraison_zone=data["livraison_zone"],
            adresse_livraison=data.get("adresse_livraison", ""),
            items=data["items"],
            note=data.get("note", ""),
            date_commande=data.get("date_commande"),
            created_by=request.user,
        )
        return Response(OrderGerantSerializer(order).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="status")
    def change_status(self, request, pk=None):
        order = self.get_object()
        serializer = OrderStatusChangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        try:
            order = services.change_order_status(
                order=order,
                new_status=serializer.validated_data["statut"],
                user=request.user,
                note=serializer.validated_data.get("note", ""),
            )
        except PermissionDenied as exc:
            raise DRFPermissionDenied(str(exc))
        except ValidationError as exc:
            raise DRFValidationError(str(exc))

        return Response(self.get_serializer(order).data)
