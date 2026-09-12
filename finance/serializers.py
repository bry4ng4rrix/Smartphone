from rest_framework import serializers

from .models import EpargneMouvement, FinanceSettings
from .services import valider_pourcentages


class FinanceSettingsSerializer(serializers.ModelSerializer):
    updated_by_name = serializers.CharField(source="updated_by.full_name", read_only=True, default="")

    class Meta:
        model = FinanceSettings
        fields = ["pct_reappro", "pct_epargne", "pct_depenses", "updated_at", "updated_by_name"]
        read_only_fields = ["updated_at"]

    def validate(self, attrs):
        current = self.instance
        reappro = attrs.get("pct_reappro", current.pct_reappro if current else 60)
        epargne = attrs.get("pct_epargne", current.pct_epargne if current else 25)
        depenses = attrs.get("pct_depenses", current.pct_depenses if current else 15)
        try:
            valider_pourcentages(reappro, epargne, depenses)
        except Exception as exc:  # django ValidationError -> DRF
            raise serializers.ValidationError(str(getattr(exc, "message", exc)))
        return attrs


class EpargneMouvementSerializer(serializers.ModelSerializer):
    type_label = serializers.CharField(source="get_type_display", read_only=True)
    order_numero = serializers.CharField(source="order.numero", read_only=True, default="")
    created_by_name = serializers.CharField(source="created_by.full_name", read_only=True, default="")

    class Meta:
        model = EpargneMouvement
        fields = [
            "id", "type", "type_label", "montant", "solde_apres", "motif", "order", "order_numero",
            "reference", "created_by_name", "created_at",
        ]
        read_only_fields = fields


class RetraitEpargneSerializer(serializers.Serializer):
    montant = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=0)
    motif = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    # Garde-fou : le client doit affirmer que l'utilisateur a confirmé.
    confirmation = serializers.BooleanField()

    def validate_confirmation(self, value):
        if not value:
            raise serializers.ValidationError("Le retrait doit être confirmé explicitement.")
        return value


class RemiseSerializer(serializers.Serializer):
    livreur_id = serializers.IntegerField(required=False, allow_null=True)
    encaissement_ids = serializers.ListField(child=serializers.IntegerField(), required=False)
    inclure_depenses = serializers.BooleanField(required=False, default=True)
    magasin_id = serializers.IntegerField(required=False, allow_null=True)

    def validate(self, attrs):
        if not attrs.get("livreur_id") and not attrs.get("encaissement_ids"):
            raise serializers.ValidationError("Indiquez un livreur ou une liste d'encaissements.")
        return attrs
