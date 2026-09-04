from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from users.permissions import IsGerantOrReadOnly, get_accessible_magasins, resolve_magasin_for_request

from . import services
from .models import Brand, Color, ProductCategory, ProductReference, ProductType, ProductVariant, StockMovement
from .serializers import (
    BrandSerializer,
    ColorSerializer,
    ProductCategorySerializer,
    ProductReferenceAutocompleteSerializer,
    ProductReferenceSerializer,
    ProductTypeSerializer,
    ProductVariantSerializer,
    StockAdjustmentSerializer,
    StockMovementSerializer,
)


class ProductCategoryViewSet(viewsets.ModelViewSet):
    serializer_class = ProductCategorySerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = ProductCategory.objects.filter(magasin__in=get_accessible_magasins(self.request.user))
        magasin_id = self.request.query_params.get("magasin_id")
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def perform_create(self, serializer):
        serializer.save(magasin=resolve_magasin_for_request(self.request))

    def destroy(self, request, *args, **kwargs):
        category = self.get_object()
        if category.types.exists():
            raise ValidationError(
                "Impossible de supprimer une catégorie qui a des sous-types — "
                "supprimez ou déplacez d'abord ses sous-types."
            )
        return super().destroy(request, *args, **kwargs)


class ProductTypeViewSet(viewsets.ModelViewSet):
    serializer_class = ProductTypeSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = ProductType.objects.select_related("category").filter(
            category__magasin__in=get_accessible_magasins(self.request.user)
        )
        category_id = self.request.query_params.get("category")
        if category_id:
            qs = qs.filter(category_id=category_id)
        return qs

    def destroy(self, request, *args, **kwargs):
        type_obj = self.get_object()
        if type_obj.references.exists():
            raise ValidationError(
                "Impossible de supprimer un sous-type qui a des références produit — "
                "supprimez ou déplacez d'abord ses références."
            )
        return super().destroy(request, *args, **kwargs)


class BrandViewSet(viewsets.ModelViewSet):
    serializer_class = BrandSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = Brand.objects.filter(magasin__in=get_accessible_magasins(self.request.user))
        magasin_id = self.request.query_params.get("magasin_id")
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def perform_create(self, serializer):
        serializer.save(magasin=resolve_magasin_for_request(self.request))

    def destroy(self, request, *args, **kwargs):
        brand = self.get_object()
        if brand.references.exists():
            raise ValidationError(
                "Impossible de supprimer une marque qui a des références produit — "
                "supprimez ou déplacez d'abord ses références."
            )
        return super().destroy(request, *args, **kwargs)


class ColorViewSet(viewsets.ModelViewSet):
    serializer_class = ColorSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = Color.objects.filter(magasin__in=get_accessible_magasins(self.request.user))
        magasin_id = self.request.query_params.get("magasin_id")
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        return qs

    def perform_create(self, serializer):
        serializer.save(magasin=resolve_magasin_for_request(self.request))


class ProductReferenceViewSet(viewsets.ModelViewSet):
    serializer_class = ProductReferenceSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = ProductReference.objects.select_related("type", "brand", "type__category").prefetch_related(
            "variants"
        ).filter(type__category__magasin__in=get_accessible_magasins(self.request.user))
        type_id = self.request.query_params.get("type")
        brand_id = self.request.query_params.get("brand")
        category_id = self.request.query_params.get("category")
        magasin_id = self.request.query_params.get("magasin_id")
        if type_id:
            qs = qs.filter(type_id=type_id)
        if brand_id:
            qs = qs.filter(brand_id=brand_id)
        if category_id:
            qs = qs.filter(type__category_id=category_id)
        if magasin_id:
            qs = qs.filter(type__category__magasin_id=magasin_id)
        return qs

    @action(detail=False, methods=["get"])
    def autocomplete(self, request):
        """GET /api/catalog/references/autocomplete/?q=...&type=<id>
        Recherche pour le formulaire Nouvelle commande (§6 Smartreadme.md)."""
        qs = self.get_queryset().filter(actif=True)
        q = request.query_params.get("q")
        if q:
            qs = qs.filter(reference_name__icontains=q)
        qs = qs[:20]
        return Response(ProductReferenceAutocompleteSerializer(qs, many=True).data)


class ProductVariantViewSet(viewsets.ModelViewSet):
    serializer_class = ProductVariantSerializer
    permission_classes = [IsGerantOrReadOnly]
    http_method_names = ["get", "post", "delete", "head", "options"]  # stock modifiable via /adjust/, pas ici

    def get_queryset(self):
        qs = ProductVariant.objects.select_related("product_reference", "product_reference__brand").filter(
            product_reference__type__category__magasin__in=get_accessible_magasins(self.request.user)
        )
        reference_id = self.request.query_params.get("reference")
        if reference_id:
            qs = qs.filter(product_reference_id=reference_id)
        return qs

    @action(detail=True, methods=["post"])
    def adjust(self, request, pk=None):
        """Ajustement manuel du stock — réservé au Gérant (§7.4 Smartreadme.md :
        'Modification manuelle du stock possible par le gérant uniquement')."""
        variant = self.get_object()
        serializer = StockAdjustmentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.apply_stock_movement(
            product_variant=variant,
            movement_type=data["type"],
            quantite=data["quantite"],
            origine="AJUSTEMENT",
            user=request.user,
            note=data.get("note") or None,
        )
        variant.refresh_from_db()
        return Response(self.get_serializer(variant).data)


class StockMovementViewSet(viewsets.ReadOnlyModelViewSet):
    """Historique des mouvements de stock (§7.4/§10 Smartreadme.md) — lecture
    seule, toute écriture passe par catalog.services.apply_stock_movement."""

    serializer_class = StockMovementSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = StockMovement.objects.select_related(
            "product_variant", "product_variant__product_reference", "user"
        ).filter(
            product_variant__product_reference__type__category__magasin__in=get_accessible_magasins(
                self.request.user
            )
        )
        variant_id = self.request.query_params.get("variant")
        if variant_id:
            qs = qs.filter(product_variant_id=variant_id)
        return qs
