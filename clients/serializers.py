"""Serializers de l'espace client — couche PUBLIQUE distincte des serializers
internes : n'exposent que ce dont un client a besoin. Jamais de prix
d'achat, de marge, de stock détaillé, de seuil d'alerte ni de données du
personnel."""
from decimal import Decimal

from rest_framework import serializers

from catalog.models import Brand, Color, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import DeliveryZoneOption, Order, OrderItem
from users.models import MagasinProfile

from .models import Client

TELEPHONE_REGEX = r"^\+261\d{9}$"
TELEPHONE_MESSAGE = "Format attendu : +261XXXXXXXXX"


def _absolute(request, fichier):
    if not fichier:
        return None
    url = fichier.url
    return request.build_absolute_uri(url) if request else url


# --------------------------------------------------------------------------- #
# Catalogue public
# --------------------------------------------------------------------------- #


class PublicBoutiqueSerializer(serializers.ModelSerializer):
    nom = serializers.CharField(source="shop_name", read_only=True)
    logo = serializers.SerializerMethodField()

    class Meta:
        model = MagasinProfile
        fields = ["id", "nom", "description", "logo"]

    def get_logo(self, obj):
        return _absolute(self.context.get("request"), obj.shop_logo)


class PublicZoneSerializer(serializers.ModelSerializer):
    """Zone de livraison choisissable à la commande (code à renvoyer dans
    `livraison_zone`)."""

    prix = serializers.DecimalField(max_digits=10, decimal_places=2, coerce_to_string=False, read_only=True)

    class Meta:
        model = DeliveryZoneOption
        fields = ["code", "nom", "prix"]


class PublicCategorieSerializer(serializers.ModelSerializer):
    boutique = serializers.IntegerField(source="magasin_id", read_only=True)

    class Meta:
        model = ProductCategory
        fields = ["id", "nom", "avec_couleurs", "boutique"]


class PublicSousTypeSerializer(serializers.ModelSerializer):
    categorie = serializers.IntegerField(source="category_id", read_only=True)
    categorie_nom = serializers.CharField(source="category.nom", read_only=True)

    class Meta:
        model = ProductType
        fields = ["id", "nom", "categorie", "categorie_nom"]


class PublicMarqueSerializer(serializers.ModelSerializer):
    boutique = serializers.IntegerField(source="magasin_id", read_only=True)

    class Meta:
        model = Brand
        fields = ["id", "nom", "boutique"]


class PublicCouleurSerializer(serializers.ModelSerializer):
    boutique = serializers.IntegerField(source="magasin_id", read_only=True)

    class Meta:
        model = Color
        fields = ["id", "nom", "boutique"]


class PublicVarianteSerializer(serializers.ModelSerializer):
    """Une couleur du produit : seulement « disponible ou non » — jamais la
    quantité en stock ni le seuil d'alerte (données internes)."""

    disponible = serializers.SerializerMethodField()

    class Meta:
        model = ProductVariant
        fields = ["id", "couleur", "disponible"]

    def get_disponible(self, obj):
        return obj.stock_actuel > 0


class PublicProduitSerializer(serializers.ModelSerializer):
    nom = serializers.CharField(source="reference_name", read_only=True)
    # « Marque + référence », le libellé affiché par l'application de gestion.
    nom_complet = serializers.SerializerMethodField()
    prix_vente = serializers.DecimalField(max_digits=12, decimal_places=2, coerce_to_string=False, read_only=True)
    photo = serializers.SerializerMethodField()
    categorie = serializers.SerializerMethodField()
    sous_type = serializers.SerializerMethodField()
    marque = serializers.SerializerMethodField()
    boutique = serializers.SerializerMethodField()
    disponible = serializers.SerializerMethodField()
    variantes = PublicVarianteSerializer(source="variants", many=True, read_only=True)

    class Meta:
        model = ProductReference
        # Volontairement SANS prix_achat, marge, sku, seuils, stock chiffré.
        fields = [
            "id", "nom", "nom_complet", "prix_vente", "photo", "categorie", "sous_type", "marque", "boutique",
            "disponible", "variantes",
        ]

    def get_nom_complet(self, obj):
        return f"{obj.brand.nom} {obj.reference_name}".strip()

    def get_photo(self, obj):
        return _absolute(self.context.get("request"), obj.photo)

    def get_categorie(self, obj):
        cat = obj.type.category
        return {"id": cat.id, "nom": cat.nom}

    def get_sous_type(self, obj):
        return {"id": obj.type_id, "nom": obj.type.nom}

    def get_marque(self, obj):
        return {"id": obj.brand_id, "nom": obj.brand.nom}

    def get_boutique(self, obj):
        mag = obj.type.category.magasin
        return {"id": mag.id, "nom": mag.shop_name}

    def get_disponible(self, obj):
        return any(v.stock_actuel > 0 for v in obj.variants.all())


# --------------------------------------------------------------------------- #
# Compte client
# --------------------------------------------------------------------------- #


class ClientSerializer(serializers.ModelSerializer):
    """Profil du client connecté (GET/PATCH /api/client/me/)."""

    telephone = serializers.RegexField(regex=TELEPHONE_REGEX, error_messages={"invalid": TELEPHONE_MESSAGE})

    class Meta:
        model = Client
        fields = ["id", "email", "nom", "telephone", "adresse", "created_at", "last_login"]
        read_only_fields = ["id", "email", "created_at", "last_login"]


class ClientRegisterSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(min_length=8, write_only=True)
    nom = serializers.CharField(max_length=255)
    telephone = serializers.RegexField(regex=TELEPHONE_REGEX, error_messages={"invalid": TELEPHONE_MESSAGE})
    adresse = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")

    def validate_email(self, value):
        value = value.strip().lower()
        if Client.objects.filter(email=value).exists():
            raise serializers.ValidationError("Un compte existe déjà avec cet e-mail.")
        return value

    def validate_nom(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Le nom est requis.")
        return value

    def create(self, validated_data):
        client = Client(
            email=validated_data["email"],
            nom=validated_data["nom"],
            telephone=validated_data["telephone"],
            adresse=validated_data.get("adresse", ""),
        )
        client.set_password(validated_data["password"])
        client.save()
        return client


class ClientLoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)


class ClientRefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class ClientChangePasswordSerializer(serializers.Serializer):
    ancien_mot_de_passe = serializers.CharField(write_only=True)
    nouveau_mot_de_passe = serializers.CharField(min_length=8, write_only=True)


# --------------------------------------------------------------------------- #
# Commandes client
# --------------------------------------------------------------------------- #


class ClientOrderItemSerializer(serializers.ModelSerializer):
    produit = serializers.SerializerMethodField()
    variante = serializers.SerializerMethodField()
    prix_unitaire = serializers.DecimalField(max_digits=12, decimal_places=2, coerce_to_string=False, read_only=True)
    total = serializers.SerializerMethodField()

    class Meta:
        model = OrderItem
        fields = ["id", "produit", "variante", "quantite", "prix_unitaire", "total", "retourne"]

    def get_produit(self, obj):
        ref = obj.product_variant.product_reference
        return {"id": ref.id, "nom": ref.reference_name, "nom_complet": f"{ref.brand.nom} {ref.reference_name}".strip()}

    def get_variante(self, obj):
        return {"id": obj.product_variant_id, "couleur": obj.product_variant.couleur}

    def get_total(self, obj):
        return Decimal("0") if obj.retourne else obj.prix_unitaire * obj.quantite


class ClientOrderSerializer(serializers.ModelSerializer):
    """Vue CLIENT d'une commande : son suivi, ses articles au prix payé, les
    montants à régler. Aucune donnée interne (préparateur, livreur, notes du
    gérant, photos, marges)."""

    statut = serializers.CharField(source="statut_courant", read_only=True)
    statut_label = serializers.CharField(source="get_statut_courant_display", read_only=True)
    boutique = serializers.SerializerMethodField()
    items = ClientOrderItemSerializer(many=True, read_only=True)
    note = serializers.CharField(source="note_livreur", read_only=True)
    frais_livraison = serializers.DecimalField(max_digits=10, decimal_places=2, coerce_to_string=False, read_only=True)
    total_a_payer = serializers.DecimalField(max_digits=12, decimal_places=2, coerce_to_string=False, read_only=True)
    peut_modifier = serializers.SerializerMethodField()
    peut_annuler = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = [
            "id", "numero", "statut", "statut_label", "date_commande", "boutique", "livraison_zone",
            "adresse_livraison", "telephone", "telephone_2", "mode_paiement", "note", "frais_livraison",
            "total_a_payer", "items", "peut_modifier", "peut_annuler", "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_boutique(self, obj):
        return {"id": obj.magasin_id, "nom": obj.magasin.shop_name}

    def get_peut_modifier(self, obj):
        return obj.statut_courant == "EN_ATTENTE_APPROBATION"

    def get_peut_annuler(self, obj):
        return obj.statut_courant in ("EN_ATTENTE_APPROBATION", "NOUVELLE")


class ClientOrderItemInputSerializer(serializers.Serializer):
    variante = serializers.IntegerField(min_value=1)
    quantite = serializers.IntegerField(min_value=1, default=1)
    # Prix affiché au client au moment de l'ajout au panier : s'il diffère du
    # prix catalogue actuel, la commande est refusée avec le nouveau prix.
    prix_attendu = serializers.DecimalField(max_digits=12, decimal_places=2, required=False, allow_null=True)


class ClientOrderCreateSerializer(serializers.Serializer):
    boutique = serializers.IntegerField(min_value=1)
    items = ClientOrderItemInputSerializer(many=True)
    livraison_zone = serializers.CharField(max_length=20)
    adresse_livraison = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    telephone = serializers.RegexField(regex=TELEPHONE_REGEX, required=False, error_messages={"invalid": TELEPHONE_MESSAGE})
    telephone_2 = serializers.RegexField(
        regex=r"^(\+261\d{9})?$", required=False, allow_blank=True, default="",
        error_messages={"invalid": TELEPHONE_MESSAGE},
    )
    mode_paiement = serializers.ChoiceField(choices=Order.MODE_PAIEMENT_CHOICES, default="LIVRAISON")
    note = serializers.CharField(required=False, allow_blank=True, default="")

    def validate_items(self, value):
        if not value:
            raise serializers.ValidationError("Ajoutez au moins un article.")
        return value


class ClientOrderUpdateSerializer(serializers.Serializer):
    adresse_livraison = serializers.CharField(max_length=255, required=False, allow_blank=True)
    telephone = serializers.RegexField(regex=TELEPHONE_REGEX, required=False, error_messages={"invalid": TELEPHONE_MESSAGE})
    telephone_2 = serializers.RegexField(
        regex=r"^(\+261\d{9})?$", required=False, allow_blank=True, error_messages={"invalid": TELEPHONE_MESSAGE},
    )
    livraison_zone = serializers.CharField(max_length=20, required=False)
    mode_paiement = serializers.ChoiceField(choices=Order.MODE_PAIEMENT_CHOICES, required=False)
    note = serializers.CharField(required=False, allow_blank=True)


class ClientOrderCancelSerializer(serializers.Serializer):
    note = serializers.CharField(required=False, allow_blank=True, default="")
