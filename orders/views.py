from django.core.exceptions import PermissionDenied, ValidationError
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied as DRFPermissionDenied
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from users.models import EmployerProfile
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
    OrderUpdateSerializer,
)

# Statuts visibles par rôle sur leur module dédié (§7.2, §7.3 Smartreadme.md).
PREPARATEUR_STATUTS = ["NOUVELLE", "EN_PREPARATION"]
LIVREUR_STATUTS = ["PRETE", "EN_LIVRAISON"]


class OrderViewSet(viewsets.ModelViewSet):
    # patch/delete : uniquement tant que la commande est "Nouvelle" (rien
    # préparé/déduit du stock) — cf. partial_update/destroy ci-dessous.
    # Statut/affectation passent toujours exclusivement par /status/.
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action in ("available_staff", "partial_update", "destroy"):
            return [IsGerant()]
        return super().get_permissions()

    def get_serializer_class(self):
        if self.action == "create":
            return OrderCreateSerializer
        if self.action == "partial_update":
            return OrderUpdateSerializer
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

        if role in ("PREPARATEUR", "LIVREUR"):
            # Ni préparateur ni livreur ne voit une commande prévue pour un
            # jour futur — une commande de demain n'apparaît que demain (les
            # commandes en retard restent visibles, pour ne pas les égarer).
            qs = qs.filter(date_commande__date__lte=timezone.localdate())
            if role == "PREPARATEUR":
                # + les récupérations sur place déjà prêtes (pas de livreur
                # pour ce cas — le préparateur en garde le suivi jusqu'au
                # retrait, validé par le gérant sur la page Récupération).
                return qs.filter(statut_courant__in=PREPARATEUR_STATUTS) | qs.filter(
                    statut_courant="PRETE", livraison_zone="RECUPERATION"
                )
            # Prêtes à récupérer + en livraison (§7.3 Smartreadme.md) — hors
            # retrait sur place, qui ne passe jamais par un livreur.
            return qs.filter(statut_courant__in=LIVREUR_STATUTS).exclude(
                statut_courant="PRETE", livraison_zone="RECUPERATION"
            )

        # Gérant : filtres optionnels date / statut / magasin / zone (§7.1 Smartreadme.md).
        statut = self.request.query_params.get("statut")
        date_debut = self.request.query_params.get("date_debut")
        date_fin = self.request.query_params.get("date_fin")
        magasin_id = self.request.query_params.get("magasin_id")
        livraison_zone = self.request.query_params.get("livraison_zone")
        if statut:
            qs = qs.filter(statut_courant=statut)
        if livraison_zone:
            qs = qs.filter(livraison_zone=livraison_zone)
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
        role = user_commande_role(request.user)
        if role not in ("GERANT", "PREPARATEUR"):
            raise DRFPermissionDenied("Seuls le gérant et le préparateur peuvent créer une commande.")

        serializer = OrderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        if role == "PREPARATEUR" and data["livraison_zone"] != "RECUPERATION":
            raise DRFValidationError(
                "Le préparateur ne peut créer que des commandes 'Récupération sur place'."
            )

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
        response_serializer = OrderPreparateurSerializer if role == "PREPARATEUR" else OrderGerantSerializer
        return Response(response_serializer(order).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        order = self.get_object()
        if order.statut_courant != "NOUVELLE":
            raise DRFValidationError(
                "Seule une commande 'Nouvelle' peut être modifiée — le stock ou une "
                "affectation est déjà engagé sur celle-ci."
            )
        serializer = OrderUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field, value in serializer.validated_data.items():
            setattr(order, field, value)
        order.save()
        order.recompute_total()
        return Response(OrderGerantSerializer(order).data)

    def destroy(self, request, *args, **kwargs):
        order = self.get_object()
        if order.statut_courant != "NOUVELLE":
            raise DRFValidationError(
                "Seule une commande 'Nouvelle' peut être supprimée — le stock ou une "
                "affectation est déjà engagé sur celle-ci."
            )
        order.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

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
                preparateur_id=serializer.validated_data.get("preparateur_id"),
                livreur_id=serializer.validated_data.get("livreur_id"),
            )
        except PermissionDenied as exc:
            raise DRFPermissionDenied(str(exc))
        except ValidationError as exc:
            raise DRFValidationError(str(exc))

        return Response(self.get_serializer(order).data)

    @action(detail=False, methods=["get"], url_path="available-staff")
    def available_staff(self, request):
        """GET /api/orders/available-staff/?role=PREPARATEUR|LIVREUR&magasin_id=
        Liste les préparateurs/livreurs du magasin avec leur disponibilité,
        pour le sélecteur d'affectation du gérant (occupé = déjà en charge
        d'une commande En préparation / En livraison)."""
        requested_role = request.query_params.get("role")
        if requested_role not in ("PREPARATEUR", "LIVREUR"):
            raise DRFValidationError("Paramètre 'role' requis : PREPARATEUR ou LIVREUR.")

        magasins = get_accessible_magasins(request.user)
        magasin_id = request.query_params.get("magasin_id")
        if magasin_id:
            magasins = magasins.filter(id=magasin_id)

        busy_check = services.is_preparateur_busy if requested_role == "PREPARATEUR" else services.is_livreur_busy
        employers = EmployerProfile.objects.filter(
            magasin__in=magasins, commande_role=requested_role
        ).select_related("user")

        return Response([
            {
                "id": ep.user_id,
                "full_name": ep.user.full_name,
                "magasin_id": ep.magasin_id,
                "available": not busy_check(ep.user),
            }
            for ep in employers
        ])
