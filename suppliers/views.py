from django.core.exceptions import ValidationError
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.response import Response

from users.models import Notification
from users.permissions import IsGerant, get_accessible_magasins, resolve_magasin_for_request

from . import services
from .models import SupplierOrder
from .serializers import SupplierOrderCreateSerializer, SupplierOrderSerializer


class SupplierOrderViewSet(viewsets.ModelViewSet):
    """Module Commandes Fournisseur (§7.6 Smartreadme.md) — réservé au gérant."""

    http_method_names = ["get", "post", "head", "options"]
    serializer_class = SupplierOrderSerializer
    permission_classes = [IsGerant]

    def get_queryset(self):
        qs = SupplierOrder.objects.filter(
            magasin__in=get_accessible_magasins(self.request.user)
        ).prefetch_related("lines", "lines__product_variant__product_reference")
        magasin_id = self.request.query_params.get("magasin_id")
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = SupplierOrderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        magasin = resolve_magasin_for_request(request)

        supplier_order = services.create_supplier_order(
            magasin=magasin,
            description=data.get("description", ""),
            prix_fournisseur=data["prix_fournisseur"],
            fret_import=data["fret_import"],
            douane=data["douane"],
            meta_ads=data["meta_ads"],
            lines=data["lines"],
            created_by=request.user,
        )
        return Response(SupplierOrderSerializer(supplier_order).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def receive(self, request, pk=None):
        """POST : réception de la commande -> entrée stock automatique par variante."""
        supplier_order = self.get_object()
        try:
            supplier_order = services.receive_supplier_order(supplier_order, request.user)
        except ValidationError as exc:
            raise DRFValidationError(str(exc))

        Notification.objects.create(
            notif_type="supplier_order",
            message=f"Commande fournisseur {supplier_order.numero} reçue — stock mis à jour",
            magasin=supplier_order.magasin,
        )
        return Response(SupplierOrderSerializer(supplier_order).data)
