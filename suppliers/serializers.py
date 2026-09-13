from rest_framework import serializers

from catalog.models import ProductVariant

from .models import (
    DEVISE_CHOICES,
    Supplier,
    SupplierFee,
    SupplierOrder,
    SupplierOrderLine,
    SupplierPayment,
    VariantCostHistory,
)


def _mga(max_digits=16):
    return serializers.DecimalField(max_digits=max_digits, decimal_places=2, read_only=True)


# --------------------------------------------------------------------------- #
# Fournisseurs
# --------------------------------------------------------------------------- #


class SupplierSerializer(serializers.ModelSerializer):
    """Fiche fournisseur + résumé financier (calculé par la vue)."""

    nb_approvisionnements = serializers.IntegerField(read_only=True, default=0)
    total_achats_mga = _mga()
    total_paye_mga = _mga()
    reste_a_payer_mga = _mga()
    total_frais_mga = _mga()
    valeur_recue_mga = _mga()
    dernier_approvisionnement = serializers.SerializerMethodField()

    class Meta:
        model = Supplier
        fields = [
            "id", "nom", "pays", "contact", "telephone", "email", "adresse", "notes", "devise", "actif",
            "nb_approvisionnements", "total_achats_mga", "total_paye_mga", "reste_a_payer_mga",
            "total_frais_mga", "valeur_recue_mga", "dernier_approvisionnement", "created_at",
        ]
        read_only_fields = ["created_at"]

    def get_dernier_approvisionnement(self, obj):
        d = getattr(obj, "_dernier", None)
        if d is None:
            return None
        return {"id": d.id, "numero": d.numero, "statut": d.statut, "statut_label": d.get_statut_display(), "date": d.date}


# --------------------------------------------------------------------------- #
# Paiements / frais / historique de coût
# --------------------------------------------------------------------------- #


class SupplierPaymentSerializer(serializers.ModelSerializer):
    type_label = serializers.CharField(source="get_type_paiement_display", read_only=True)
    methode_label = serializers.CharField(source="get_methode_display", read_only=True)
    created_by_name = serializers.CharField(source="created_by.full_name", read_only=True, default="")

    class Meta:
        model = SupplierPayment
        fields = [
            "id", "date", "type_paiement", "type_label", "methode", "methode_label", "montant", "devise",
            "taux_change", "montant_mga", "reference", "commentaire", "justificatif", "created_by_name", "created_at",
        ]
        read_only_fields = ["montant_mga", "created_at"]


class SupplierPaymentInputSerializer(serializers.Serializer):
    montant = serializers.DecimalField(max_digits=16, decimal_places=2)
    devise = serializers.ChoiceField(choices=DEVISE_CHOICES, default="MGA")
    taux_change = serializers.DecimalField(max_digits=14, decimal_places=4, required=False, allow_null=True)
    date = serializers.DateField(required=False)
    type_paiement = serializers.ChoiceField(choices=SupplierPayment.TYPE_CHOICES, default="ACOMPTE")
    methode = serializers.ChoiceField(choices=SupplierPayment.METHODE_CHOICES, default="VIREMENT")
    reference = serializers.CharField(max_length=150, required=False, allow_blank=True, default="")
    commentaire = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    justificatif = serializers.FileField(required=False, allow_null=True)


class SupplierFeeSerializer(serializers.ModelSerializer):
    type_label = serializers.CharField(source="get_type_frais_display", read_only=True)
    created_by_name = serializers.CharField(source="created_by.full_name", read_only=True, default="")

    class Meta:
        model = SupplierFee
        fields = [
            "id", "type_frais", "type_label", "date", "montant", "devise", "taux_change", "montant_mga",
            "description", "prestataire", "justificatif", "created_by_name", "created_at",
        ]
        read_only_fields = ["montant_mga", "created_at"]


class SupplierFeeInputSerializer(serializers.Serializer):
    type_frais = serializers.ChoiceField(choices=SupplierFee.TYPE_CHOICES, default="AUTRE")
    montant = serializers.DecimalField(max_digits=16, decimal_places=2)
    devise = serializers.ChoiceField(choices=DEVISE_CHOICES, default="MGA")
    taux_change = serializers.DecimalField(max_digits=14, decimal_places=4, required=False, allow_null=True)
    date = serializers.DateField(required=False)
    description = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    prestataire = serializers.CharField(max_length=150, required=False, allow_blank=True, default="")
    justificatif = serializers.FileField(required=False, allow_null=True)


class VariantCostHistorySerializer(serializers.ModelSerializer):
    numero = serializers.CharField(source="supplier_order.numero", read_only=True)
    supplier_nom = serializers.CharField(source="supplier_order.supplier.nom", read_only=True, default="")
    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)

    class Meta:
        model = VariantCostHistory
        fields = [
            "id", "product_variant", "reference_name", "couleur", "supplier_order", "numero", "supplier_nom",
            "date", "quantite", "valeur_achat_unitaire_mga", "frais_unitaire_mga", "cout_revient_unitaire_mga",
        ]


# --------------------------------------------------------------------------- #
# Approvisionnement
# --------------------------------------------------------------------------- #


class SupplierOrderLineSerializer(serializers.ModelSerializer):
    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    brand_name = serializers.CharField(source="product_variant.product_reference.brand.nom", read_only=True, default="")
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)
    prix_vente = serializers.DecimalField(
        source="product_variant.product_reference.prix_vente", max_digits=12, decimal_places=2, read_only=True,
    )
    marge_unitaire = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    total_fournisseur_devise = serializers.DecimalField(max_digits=16, decimal_places=2, read_only=True)
    reste_a_recevoir = serializers.SerializerMethodField()

    class Meta:
        model = SupplierOrderLine
        fields = [
            "id", "product_variant", "reference_name", "brand_name", "couleur", "prix_vente",
            "quantite", "quantite_recue", "reste_a_recevoir", "prix_unitaire", "total_fournisseur_devise",
            "allocation_manuelle_mga", "valeur_achat_mga", "frais_alloues_mga",
            "cout_unitaire_calcule", "total_ligne", "marge_unitaire",
        ]
        read_only_fields = ["quantite_recue", "valeur_achat_mga", "frais_alloues_mga", "cout_unitaire_calcule", "total_ligne"]

    def get_reste_a_recevoir(self, obj):
        return max(obj.quantite - obj.quantite_recue, 0)


class SupplierOrderSerializer(serializers.ModelSerializer):
    """Vue complète d'un approvisionnement : lignes, paiements, frais, montants
    dérivés (MGA) — tous les champs de la première version sont conservés."""

    lines = SupplierOrderLineSerializer(many=True, read_only=True)
    payments = SupplierPaymentSerializer(many=True, read_only=True)
    fees = SupplierFeeSerializer(many=True, read_only=True)
    statut_label = serializers.CharField(source="get_statut_display", read_only=True)
    supplier_nom = serializers.CharField(source="supplier.nom", read_only=True, default="")
    magasin_name = serializers.CharField(source="magasin.shop_name", read_only=True)
    total_paye_mga = _mga()
    total_paye_devise = _mga()
    reste_a_payer_mga = _mga()
    pourcentage_paye = serializers.DecimalField(max_digits=5, decimal_places=1, read_only=True)
    total_recu = serializers.IntegerField(read_only=True)
    frais_par_type = serializers.SerializerMethodField()

    class Meta:
        model = SupplierOrder
        fields = [
            "id", "magasin", "magasin_name", "supplier", "supplier_nom", "numero", "date", "description",
            "statut", "statut_label", "devise", "taux_change", "methode_allocation",
            "prix_fournisseur", "fret_import", "douane",
            "date_expedition", "transporteur", "mode_transport", "tracking", "lieu_depart", "destination", "date_arrivee",
            "total_qty", "total_recu", "valeur_achat_mga", "total_frais_mga", "cout_total", "cout_unitaire",
            "total_paye_mga", "total_paye_devise", "reste_a_payer_mga", "pourcentage_paye", "frais_par_type",
            "lines", "payments", "fees", "created_at", "received_at", "finalise_at",
        ]
        read_only_fields = [
            "magasin", "numero", "statut", "total_qty", "valeur_achat_mga", "total_frais_mga", "cout_total",
            "cout_unitaire", "created_at", "received_at", "finalise_at",
        ]

    def get_frais_par_type(self, obj):
        """Synthèse des frais (MGA) par type, y compris les montants fret /
        douane de la première version."""
        totaux = {}
        if obj.fret_import:
            totaux["TRANSPORT"] = totaux.get("TRANSPORT", 0) + obj.fret_import
        if obj.douane:
            totaux["DOUANE"] = totaux.get("DOUANE", 0) + obj.douane
        for f in obj.fees.all():
            totaux[f.type_frais] = totaux.get(f.type_frais, 0) + f.montant_mga
        labels = dict(SupplierFee.TYPE_CHOICES)
        return [
            {"type": t, "label": labels.get(t, t), "montant_mga": m}
            for t, m in sorted(totaux.items(), key=lambda kv: -kv[1])
        ]


class SupplierOrderLineInputSerializer(serializers.Serializer):
    id = serializers.IntegerField(required=False)
    product_variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all())
    quantite = serializers.IntegerField(min_value=1)
    prix_unitaire = serializers.DecimalField(max_digits=14, decimal_places=4, required=False, allow_null=True, min_value=0)
    allocation_manuelle_mga = serializers.DecimalField(max_digits=16, decimal_places=2, required=False, allow_null=True, min_value=0)


class SupplierOrderCreateSerializer(serializers.Serializer):
    description = serializers.CharField(required=False, allow_blank=True, default="")
    supplier = serializers.PrimaryKeyRelatedField(queryset=Supplier.objects.all(), required=False, allow_null=True)
    devise = serializers.ChoiceField(choices=DEVISE_CHOICES, default="MGA")
    taux_change = serializers.DecimalField(max_digits=14, decimal_places=4, required=False, allow_null=True)
    methode_allocation = serializers.ChoiceField(choices=SupplierOrder.ALLOCATION_CHOICES, default="VALEUR")
    date = serializers.DateField(required=False)
    destination = serializers.CharField(max_length=150, required=False, allow_blank=True, default="Madagascar")
    statut = serializers.ChoiceField(choices=(("BROUILLON", "Brouillon"), ("COMMANDE", "Commandé")), default="BROUILLON")
    # Première version (montants MGA) — toujours acceptés.
    prix_fournisseur = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    fret_import = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    douane = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    lines = SupplierOrderLineInputSerializer(many=True)

    def validate_lines(self, value):
        if not value:
            raise serializers.ValidationError("Au moins une ligne est requise.")
        return value


class SupplierOrderUpdateSerializer(serializers.Serializer):
    description = serializers.CharField(required=False, allow_blank=True)
    supplier = serializers.PrimaryKeyRelatedField(queryset=Supplier.objects.all(), required=False, allow_null=True)
    devise = serializers.ChoiceField(choices=DEVISE_CHOICES, required=False)
    taux_change = serializers.DecimalField(max_digits=14, decimal_places=4, required=False, allow_null=True)
    methode_allocation = serializers.ChoiceField(choices=SupplierOrder.ALLOCATION_CHOICES, required=False)
    date = serializers.DateField(required=False)
    prix_fournisseur = serializers.DecimalField(max_digits=14, decimal_places=2, required=False)
    fret_import = serializers.DecimalField(max_digits=14, decimal_places=2, required=False)
    douane = serializers.DecimalField(max_digits=14, decimal_places=2, required=False)
    date_expedition = serializers.DateField(required=False, allow_null=True)
    transporteur = serializers.CharField(max_length=150, required=False, allow_blank=True)
    mode_transport = serializers.ChoiceField(choices=SupplierOrder.MODE_TRANSPORT_CHOICES, required=False, allow_blank=True)
    tracking = serializers.CharField(max_length=150, required=False, allow_blank=True)
    lieu_depart = serializers.CharField(max_length=150, required=False, allow_blank=True)
    destination = serializers.CharField(max_length=150, required=False, allow_blank=True)
    date_arrivee = serializers.DateField(required=False, allow_null=True)
    lines = SupplierOrderLineInputSerializer(many=True, required=False)


class ExpedierSerializer(serializers.Serializer):
    date_expedition = serializers.DateField(required=False, allow_null=True)
    transporteur = serializers.CharField(max_length=150, required=False, allow_blank=True)
    mode_transport = serializers.ChoiceField(choices=SupplierOrder.MODE_TRANSPORT_CHOICES, required=False, allow_blank=True)
    tracking = serializers.CharField(max_length=150, required=False, allow_blank=True)
    lieu_depart = serializers.CharField(max_length=150, required=False, allow_blank=True)
    destination = serializers.CharField(max_length=150, required=False, allow_blank=True)


class ReceptionLineSerializer(serializers.Serializer):
    line_id = serializers.IntegerField()
    quantite_recue = serializers.IntegerField(min_value=0)


class ReceptionSerializer(serializers.Serializer):
    """Sans `lines` : réception complète de tout ce qui reste (comportement
    de la première version)."""

    lines = ReceptionLineSerializer(many=True, required=False)


class FinaliserSerializer(serializers.Serializer):
    mettre_a_jour_prix_achat = serializers.BooleanField(default=True)
