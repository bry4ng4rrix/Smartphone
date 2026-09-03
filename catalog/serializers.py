from rest_framework import serializers

from .models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant, StockMovement


class ProductCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductCategory
        fields = ["id", "magasin", "nom", "ordre"]
        read_only_fields = ["magasin"]


class ProductTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductType
        fields = ["id", "category", "nom"]


class BrandSerializer(serializers.ModelSerializer):
    class Meta:
        model = Brand
        fields = ["id", "magasin", "nom"]
        read_only_fields = ["magasin"]


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
        # Le stock ne se modifie jamais directement ici : uniquement via un
        # mouvement (catalog.services.apply_stock_movement), pour garantir la
        # traçabilité obligatoire (§10 Smartreadme.md).
        read_only_fields = ["stock_actuel"]


class ProductReferenceSerializer(serializers.ModelSerializer):
    variants = ProductVariantSerializer(many=True, read_only=True)
    brand_name = serializers.CharField(source="brand.nom", read_only=True)
    type_name = serializers.CharField(source="type.nom", read_only=True)
    category_name = serializers.CharField(source="type.category.nom", read_only=True)
    magasin = serializers.IntegerField(source="type.category.magasin_id", read_only=True)

    class Meta:
        model = ProductReference
        fields = [
            "id", "type", "type_name", "category_name", "brand", "brand_name",
            "reference_name", "prix_vente", "actif", "variants", "magasin",
        ]


class ProductReferenceAutocompleteSerializer(serializers.ModelSerializer):
    """Utilisé par le formulaire Nouvelle commande (§6 Smartreadme.md) :
    recherche autocomplete dans le catalogue, avec les couleurs disponibles."""

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


class StockMovementSerializer(serializers.ModelSerializer):
    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)
    user_name = serializers.CharField(source="user.full_name", read_only=True)

    class Meta:
        model = StockMovement
        fields = [
            "id", "product_variant", "reference_name", "couleur", "type", "quantite",
            "origine", "reference", "note", "user", "user_name", "timestamp",
        ]
        read_only_fields = fields


class StockAdjustmentSerializer(serializers.Serializer):
    """Ajustement manuel du stock par le gérant (§7.4 Smartreadme.md :
    entrée après fournisseur hors module fournisseur formel, ou correction)."""

    type = serializers.ChoiceField(choices=StockMovement.TYPE_CHOICES)
    quantite = serializers.IntegerField(min_value=1)
    note = serializers.CharField(required=False, allow_blank=True, default="")
