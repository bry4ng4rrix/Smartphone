from rest_framework import serializers

from .models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant


class ProductCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductCategory
        fields = ["id", "nom", "ordre"]


class ProductTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductType
        fields = ["id", "category", "nom"]


class BrandSerializer(serializers.ModelSerializer):
    class Meta:
        model = Brand
        fields = ["id", "nom"]


class ProductVariantSerializer(serializers.ModelSerializer):
    reference_name = serializers.CharField(source="product_reference.reference_name", read_only=True)
    brand_name = serializers.CharField(source="product_reference.brand.nom", read_only=True)
    prix_vente = serializers.DecimalField(
        source="product_reference.prix_vente", max_digits=12, decimal_places=2, read_only=True
    )
    is_rupture = serializers.BooleanField(read_only=True)
    is_stock_bas = serializers.BooleanField(read_only=True)

    class Meta:
        model = ProductVariant
        fields = [
            "id", "product_reference", "reference_name", "brand_name", "prix_vente",
            "couleur", "sku_loyverse", "stock_actuel", "seuil_alerte", "is_rupture", "is_stock_bas",
        ]
        read_only_fields = ["stock_actuel"]  # modifié uniquement via mouvements de stock (app stock)


class ProductReferenceSerializer(serializers.ModelSerializer):
    variants = ProductVariantSerializer(many=True, read_only=True)
    brand_name = serializers.CharField(source="brand.nom", read_only=True)
    type_name = serializers.CharField(source="type.nom", read_only=True)
    category_name = serializers.CharField(source="type.category.nom", read_only=True)

    class Meta:
        model = ProductReference
        fields = [
            "id", "type", "type_name", "category_name", "brand", "brand_name",
            "reference_name", "prix_vente", "actif", "variants",
        ]


class ProductReferenceAutocompleteSerializer(serializers.ModelSerializer):
    """Utilisé par le formulaire Nouvelle Commande (§6) : recherche
    autocomplete dans le catalogue, avec les couleurs disponibles."""

    brand_name = serializers.CharField(source="brand.nom", read_only=True)
    type_name = serializers.CharField(source="type.nom", read_only=True)
    couleurs = serializers.SerializerMethodField()

    class Meta:
        model = ProductReference
        fields = ["id", "type", "type_name", "brand", "brand_name", "reference_name", "prix_vente", "couleurs"]

    def get_couleurs(self, obj):
        return [
            {"variant_id": v.id, "couleur": v.couleur, "stock_actuel": v.stock_actuel}
            for v in obj.variants.all()
        ]
