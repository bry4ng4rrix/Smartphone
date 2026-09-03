from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from users.permissions import IsGerantOrReadOnly

from .models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from .serializers import (
    BrandSerializer,
    ProductCategorySerializer,
    ProductReferenceAutocompleteSerializer,
    ProductReferenceSerializer,
    ProductTypeSerializer,
    ProductVariantSerializer,
)


class ProductCategoryViewSet(viewsets.ModelViewSet):
    queryset = ProductCategory.objects.all()
    serializer_class = ProductCategorySerializer
    permission_classes = [IsGerantOrReadOnly]


class ProductTypeViewSet(viewsets.ModelViewSet):
    queryset = ProductType.objects.select_related("category").all()
    serializer_class = ProductTypeSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        category_id = self.request.query_params.get("category")
        if category_id:
            qs = qs.filter(category_id=category_id)
        return qs


class BrandViewSet(viewsets.ModelViewSet):
    queryset = Brand.objects.all()
    serializer_class = BrandSerializer
    permission_classes = [IsGerantOrReadOnly]


class ProductReferenceViewSet(viewsets.ModelViewSet):
    queryset = ProductReference.objects.select_related("type", "brand", "type__category").prefetch_related("variants")
    serializer_class = ProductReferenceSerializer
    permission_classes = [IsGerantOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        type_id = self.request.query_params.get("type")
        brand_id = self.request.query_params.get("brand")
        if type_id:
            qs = qs.filter(type_id=type_id)
        if brand_id:
            qs = qs.filter(brand_id=brand_id)
        return qs

    @action(detail=False, methods=["get"])
    def autocomplete(self, request):
        """GET /api/catalog/references/autocomplete/?q=...&type=<id>
        Recherche pour le formulaire Nouvelle commande (§6 README)."""
        qs = self.get_queryset().filter(actif=True)
        q = request.query_params.get("q")
        if q:
            qs = qs.filter(reference_name__icontains=q)
        qs = qs[:20]
        return Response(ProductReferenceAutocompleteSerializer(qs, many=True).data)


class ProductVariantViewSet(viewsets.ModelViewSet):
    queryset = ProductVariant.objects.select_related("product_reference", "product_reference__brand").all()
    serializer_class = ProductVariantSerializer
    permission_classes = [IsGerantOrReadOnly]
    http_method_names = ["get", "post", "delete", "head", "options"]  # stock modifiable via l'app stock, pas ici

    def get_queryset(self):
        qs = super().get_queryset()
        reference_id = self.request.query_params.get("reference")
        if reference_id:
            qs = qs.filter(product_reference_id=reference_id)
        return qs
