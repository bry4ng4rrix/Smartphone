from rest_framework import serializers

from catalog.models import ProductVariant

from .models import SupplierOrder, SupplierOrderLine


class SupplierOrderLineSerializer(serializers.ModelSerializer):
    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)
    marge_unitaire = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)

    class Meta:
        model = SupplierOrderLine
        fields = [
            "id", "product_variant", "reference_name", "couleur", "quantite",
            "cout_unitaire_calcule", "total_ligne", "marge_unitaire",
        ]
        read_only_fields = ["cout_unitaire_calcule", "total_ligne"]


class SupplierOrderSerializer(serializers.ModelSerializer):
    lines = SupplierOrderLineSerializer(many=True, read_only=True)

    class Meta:
        model = SupplierOrder
        fields = [
            "id", "numero", "date", "description", "statut",
            "prix_fournisseur", "fret_import", "douane", "meta_ads",
            "total_qty", "cout_total", "cout_unitaire", "lines",
            "created_at", "received_at",
        ]
        read_only_fields = ["numero", "statut", "total_qty", "cout_total", "cout_unitaire", "created_at", "received_at"]


class SupplierOrderLineInputSerializer(serializers.Serializer):
    product_variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all())
    quantite = serializers.IntegerField(min_value=1)


class SupplierOrderCreateSerializer(serializers.Serializer):
    description = serializers.CharField(required=False, allow_blank=True, default="")
    prix_fournisseur = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    fret_import = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    douane = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    meta_ads = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    lines = SupplierOrderLineInputSerializer(many=True)

    def validate_lines(self, value):
        if not value:
            raise serializers.ValidationError("Au moins une ligne est requise.")
        return value
