from rest_framework import serializers

from catalog.models import ProductVariant

from .models import StockMovement


class StockMovementSerializer(serializers.ModelSerializer):
    variant_label = serializers.SerializerMethodField()
    user_name = serializers.CharField(source="user.full_name", read_only=True)

    class Meta:
        model = StockMovement
        fields = [
            "id", "product_variant", "variant_label", "type", "quantite", "origine",
            "reference", "note", "user", "user_name", "timestamp",
        ]
        read_only_fields = fields

    def get_variant_label(self, obj):
        return str(obj.product_variant)


class StockAdjustmentSerializer(serializers.Serializer):
    """Ajustement manuel de stock — réservé au gérant (§7.4 README :
    'Modification manuelle du stock possible par le gérant uniquement')."""

    product_variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all())
    type = serializers.ChoiceField(choices=StockMovement.TYPE_CHOICES)
    quantite = serializers.IntegerField(min_value=1)
    note = serializers.CharField(required=False, allow_blank=True)


class RuptureSerializer(serializers.ModelSerializer):
    reference_name = serializers.CharField(source="product_reference.reference_name", read_only=True)
    brand_name = serializers.CharField(source="product_reference.brand.nom", read_only=True)
    type_name = serializers.CharField(source="product_reference.type.nom", read_only=True)
    category_name = serializers.CharField(source="product_reference.type.category.nom", read_only=True)
    statut = serializers.SerializerMethodField()

    class Meta:
        model = ProductVariant
        fields = [
            "id", "reference_name", "brand_name", "type_name", "category_name",
            "couleur", "stock_actuel", "seuil_alerte", "statut",
        ]

    def get_statut(self, obj):
        return "RUPTURE" if obj.is_rupture else "STOCK_BAS"
