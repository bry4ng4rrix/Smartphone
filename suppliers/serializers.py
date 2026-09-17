from rest_framework import serializers

from catalog.models import ProductVariant

from .models import DEVISE_CHOICES, Supplier, SupplierOrder, SupplierPayment


def _mga(**kw):
    return serializers.DecimalField(max_digits=16, decimal_places=2, read_only=True, **kw)


# --------------------------------------------------------------------------- #
# Fournisseurs
# --------------------------------------------------------------------------- #


class SupplierSerializer(serializers.ModelSerializer):
    """Fiche fournisseur + résumé financier (calculé par la vue)."""

    nb_approvisionnements = serializers.IntegerField(read_only=True, default=0)
    nb_en_cours = serializers.IntegerField(read_only=True, default=0)
    nb_finalises = serializers.IntegerField(read_only=True, default=0)
    total_paye_mga = _mga()
    total_frais_douane_mga = _mga()
    cout_total_mga = _mga()
    reste_a_payer_devise = _mga()
    quantite_totale = serializers.IntegerField(read_only=True, default=0)
    dernier_approvisionnement = serializers.SerializerMethodField()

    class Meta:
        model = Supplier
        fields = [
            "id", "nom", "pays", "contact", "telephone", "email", "adresse", "notes", "devise", "actif",
            "nb_approvisionnements", "nb_en_cours", "nb_finalises", "total_paye_mga", "total_frais_douane_mga",
            "cout_total_mga", "reste_a_payer_devise", "quantite_totale", "dernier_approvisionnement", "created_at",
        ]
        read_only_fields = ["created_at"]

    def get_dernier_approvisionnement(self, obj):
        d = getattr(obj, "_dernier", None)
        if d is None:
            return None
        return {"id": d.id, "numero": d.numero, "statut": d.statut, "statut_label": d.get_statut_display(), "date": d.date}


# --------------------------------------------------------------------------- #
# Paiements
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
    montant = serializers.DecimalField(max_digits=16, decimal_places=2, min_value=0)
    devise = serializers.ChoiceField(choices=DEVISE_CHOICES, default="USD")
    # Taux du jour : nombre d'ariary pour 1 unité de devise (1 pour le MGA).
    taux_change = serializers.DecimalField(max_digits=14, decimal_places=4, required=False, allow_null=True)
    date = serializers.DateField(required=False)
    type_paiement = serializers.ChoiceField(choices=SupplierPayment.TYPE_CHOICES, default="ACOMPTE")
    methode = serializers.ChoiceField(choices=SupplierPayment.METHODE_CHOICES, default="VIREMENT")
    reference = serializers.CharField(max_length=150, required=False, allow_blank=True, default="")
    commentaire = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    justificatif = serializers.FileField(required=False, allow_null=True)
    # Enregistre aussi la sortie en caisse (session ouverte requise).
    en_caisse = serializers.BooleanField(required=False, default=False)


# --------------------------------------------------------------------------- #
# Approvisionnements
# --------------------------------------------------------------------------- #


class ProduitSerializer(serializers.ModelSerializer):
    """LE produit de l'approvisionnement (variante + référence)."""

    reference_name = serializers.CharField(source="product_reference.reference_name", read_only=True)
    brand_name = serializers.CharField(source="product_reference.brand.nom", read_only=True, default="")
    type_name = serializers.CharField(source="product_reference.type.nom", read_only=True, default="")
    prix_vente = serializers.DecimalField(source="product_reference.prix_vente", max_digits=12, decimal_places=2, read_only=True)
    prix_achat = serializers.DecimalField(source="product_reference.prix_achat", max_digits=12, decimal_places=2, read_only=True)
    libelle = serializers.SerializerMethodField()

    class Meta:
        model = ProductVariant
        fields = ["id", "libelle", "reference_name", "brand_name", "type_name", "couleur", "stock_actuel", "prix_vente", "prix_achat"]

    def get_libelle(self, obj):
        ref = obj.product_reference
        return f"{ref.brand.nom} {ref.reference_name} — {obj.couleur}"


class SupplierOrderSerializer(serializers.ModelSerializer):
    statut_label = serializers.CharField(source="get_statut_display", read_only=True)
    mode_transport_label = serializers.CharField(source="get_mode_transport_display", read_only=True)
    supplier_nom = serializers.CharField(source="supplier.nom", read_only=True, default="")
    supplier_pays = serializers.CharField(source="supplier.pays", read_only=True, default="")
    magasin_name = serializers.CharField(source="magasin.shop_name", read_only=True)
    created_by_name = serializers.CharField(source="created_by.full_name", read_only=True, default="")
    produit = ProduitSerializer(source="product_variant", read_only=True)
    payments = SupplierPaymentSerializer(many=True, read_only=True)
    # Résumé « prévu / payé / reste » (§ 4) dans la devise de l'appro.
    total_paye_devise = _mga()
    reste_a_payer_devise = _mga()
    pourcentage_paye = serializers.DecimalField(max_digits=5, decimal_places=1, read_only=True)
    # Marge (§ 20) : prix de vente − coût de revient unitaire.
    prix_vente_unitaire = _mga()
    marge_unitaire = _mga()
    caisse = serializers.SerializerMethodField()

    class Meta:
        model = SupplierOrder
        fields = [
            "id", "numero", "date", "description", "statut", "statut_label",
            "magasin", "magasin_name", "supplier", "supplier_nom", "supplier_pays",
            "product_variant", "produit", "quantite", "quantite_recue",
            "devise", "montant_prevu", "total_paye_devise", "reste_a_payer_devise", "pourcentage_paye",
            "date_expedition", "transporteur", "mode_transport", "mode_transport_label", "tracking", "numero_colis",
            "lieu_depart", "destination", "date_arrivee", "commentaire_transport",
            "frais_douane_mga", "total_paiements_mga", "cout_total_mga", "cout_unitaire_mga",
            "prix_vente_unitaire", "marge_unitaire",
            "payments", "caisse", "received_at", "finalise_at", "created_by_name", "created_at",
        ]
        read_only_fields = fields

    def get_caisse(self, obj):
        """Références des sorties de caisse déjà enregistrées pour cet appro
        (paiements `APPRO:<n°>:P<id>`, frais `APPRO:<n°>:FRAIS`)."""
        from .services import references_caisse

        refs = references_caisse(obj)
        return {
            "paiements": [p.id for p in obj.payments.all() if f"APPRO:{obj.numero}:P{p.id}" in refs],
            "frais_douane": f"APPRO:{obj.numero}:FRAIS" in refs,
        }


class SupplierOrderCreateSerializer(serializers.Serializer):
    supplier = serializers.PrimaryKeyRelatedField(queryset=Supplier.objects.all(), required=False, allow_null=True)
    product_variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all())
    quantite = serializers.IntegerField(min_value=1)
    devise = serializers.ChoiceField(choices=DEVISE_CHOICES, required=False)
    montant_prevu = serializers.DecimalField(max_digits=16, decimal_places=2, required=False, default=0, min_value=0)
    description = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    date = serializers.DateField(required=False)
    statut = serializers.ChoiceField(choices=[("BROUILLON", "Brouillon"), ("COMMANDE", "Commande")], required=False, default="BROUILLON")


class SupplierOrderUpdateSerializer(serializers.Serializer):
    supplier = serializers.PrimaryKeyRelatedField(queryset=Supplier.objects.all(), required=False, allow_null=True)
    product_variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all(), required=False)
    quantite = serializers.IntegerField(min_value=1, required=False)
    devise = serializers.ChoiceField(choices=DEVISE_CHOICES, required=False)
    montant_prevu = serializers.DecimalField(max_digits=16, decimal_places=2, required=False, min_value=0)
    description = serializers.CharField(max_length=255, required=False, allow_blank=True)
    date = serializers.DateField(required=False)
    date_expedition = serializers.DateField(required=False, allow_null=True)
    transporteur = serializers.CharField(max_length=150, required=False, allow_blank=True)
    mode_transport = serializers.ChoiceField(choices=SupplierOrder.MODE_TRANSPORT_CHOICES, required=False, allow_blank=True)
    tracking = serializers.CharField(max_length=150, required=False, allow_blank=True)
    numero_colis = serializers.CharField(max_length=150, required=False, allow_blank=True)
    lieu_depart = serializers.CharField(max_length=150, required=False, allow_blank=True)
    destination = serializers.CharField(max_length=150, required=False, allow_blank=True)
    date_arrivee = serializers.DateField(required=False, allow_null=True)
    commentaire_transport = serializers.CharField(max_length=255, required=False, allow_blank=True)
    frais_douane_mga = serializers.DecimalField(max_digits=16, decimal_places=2, required=False, min_value=0)


class ExpedierSerializer(serializers.Serializer):
    date_expedition = serializers.DateField(required=False)
    transporteur = serializers.CharField(max_length=150, required=False, allow_blank=True)
    mode_transport = serializers.ChoiceField(choices=SupplierOrder.MODE_TRANSPORT_CHOICES, required=False, allow_blank=True)
    tracking = serializers.CharField(max_length=150, required=False, allow_blank=True)
    numero_colis = serializers.CharField(max_length=150, required=False, allow_blank=True)
    lieu_depart = serializers.CharField(max_length=150, required=False, allow_blank=True)
    destination = serializers.CharField(max_length=150, required=False, allow_blank=True)
    commentaire_transport = serializers.CharField(max_length=255, required=False, allow_blank=True)


class TransitSerializer(serializers.Serializer):
    transporteur = serializers.CharField(max_length=150, required=False, allow_blank=True)
    mode_transport = serializers.ChoiceField(choices=SupplierOrder.MODE_TRANSPORT_CHOICES, required=False, allow_blank=True)
    tracking = serializers.CharField(max_length=150, required=False, allow_blank=True)
    numero_colis = serializers.CharField(max_length=150, required=False, allow_blank=True)
    commentaire_transport = serializers.CharField(max_length=255, required=False, allow_blank=True)


class ArriverSerializer(serializers.Serializer):
    date_arrivee = serializers.DateField(required=False)
    frais_douane_mga = serializers.DecimalField(max_digits=16, decimal_places=2, required=False, allow_null=True, min_value=0)


class FraisDouaneSerializer(serializers.Serializer):
    frais_douane_mga = serializers.DecimalField(max_digits=16, decimal_places=2, min_value=0)
    en_caisse = serializers.BooleanField(required=False, default=False)


class FinaliserSerializer(serializers.Serializer):
    mettre_a_jour_prix_achat = serializers.BooleanField(required=False, default=True)
    quantite_recue = serializers.IntegerField(required=False, allow_null=True, min_value=0)


class HistoriqueCoutSerializer(serializers.Serializer):
    """Un envoi finalisé d'un produit (§ 12)."""

    id = serializers.IntegerField()
    numero = serializers.CharField()
    supplier_nom = serializers.CharField(source="supplier.nom", default="")
    date = serializers.DateField()
    finalise_at = serializers.DateTimeField()
    quantite = serializers.IntegerField()
    total_paiements_mga = _mga()
    frais_douane_mga = _mga()
    cout_total_mga = _mga()
    cout_unitaire_mga = _mga()
