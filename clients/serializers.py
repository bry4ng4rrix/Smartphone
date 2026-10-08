"""Serializers de la boutique en ligne — couche PUBLIQUE distincte des
serializers internes : n'exposent que ce dont un acheteur a besoin. Jamais de
prix d'achat, de marge, de stock détaillé, de seuil d'alerte ni de données du
personnel."""
from decimal import Decimal

from rest_framework import serializers

from catalog.models import Brand, Color, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order, OrderItem
from users.models import MagasinProfile

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
        # `adresse` / `telephone` : ce qu'il faut à un client venant RETIRER sa
        # commande sur place. Chaînes vides tant que le gérant ne les a pas
        # renseignées — le front n'affiche alors rien plutôt qu'un vide.
        fields = ["id", "nom", "description", "logo", "adresse", "telephone", "telephone_2"]

    def get_logo(self, obj):
        return _absolute(self.context.get("request"), obj.shop_logo)


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
# Prise de commande (sans compte)
# --------------------------------------------------------------------------- #


class CommandeItemInputSerializer(serializers.Serializer):
    variante = serializers.IntegerField(min_value=1)
    quantite = serializers.IntegerField(min_value=1, default=1)
    # Prix affiché au client au moment de l'ajout au panier : s'il diffère du
    # prix catalogue actuel, la commande est refusée avec le nouveau prix.
    prix_attendu = serializers.DecimalField(max_digits=12, decimal_places=2, required=False, allow_null=True)


class CommandeEnLigneCreateSerializer(serializers.Serializer):
    """Ce que le navigateur envoie pour passer commande.

    Aucun montant n'y figure — ni frais de livraison, ni total. Le serveur les
    calcule à partir du catalogue et de la zone (`Order.save()` puis
    `recompute_total()`) : un prix venu du client ne fait jamais foi.
    `prix_attendu` est la seule donnée chiffrée acceptée, et elle ne sert qu'à
    détecter un changement de tarif, jamais à fixer le montant.
    """

    # Plus de source de vérité pour le routage : le serveur déduit la
    # boutique de CHAQUE article (clients/services.py::magasins_des_items).
    # Le champ reste accepté — les anciens clients l'envoient — mais il est
    # ignoré : un panier peut désormais mêler plusieurs boutiques, et sa
    # valeur unique n'aurait aucun sens.
    boutique = serializers.IntegerField(min_value=1, required=False)
    items = CommandeItemInputSerializer(many=True)
    livraison_zone = serializers.CharField(max_length=20)

    client_nom = serializers.CharField(max_length=255)
    telephone = serializers.RegexField(regex=TELEPHONE_REGEX, error_messages={"invalid": TELEPHONE_MESSAGE})
    telephone_2 = serializers.RegexField(
        regex=r"^(\+261\d{9})?$", required=False, allow_blank=True, default="",
        error_messages={"invalid": TELEPHONE_MESSAGE},
    )
    adresse_livraison = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    note = serializers.CharField(required=False, allow_blank=True, default="")

    def validate_items(self, value):
        if not value:
            raise serializers.ValidationError("Ajoutez au moins un article.")
        return value

    def validate_client_nom(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Indiquez le nom de la personne à contacter.")
        return value


class CommandeItemSerializer(serializers.ModelSerializer):
    produit = serializers.SerializerMethodField()
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)
    prix_unitaire = serializers.DecimalField(max_digits=12, decimal_places=2, coerce_to_string=False, read_only=True)
    total = serializers.SerializerMethodField()

    class Meta:
        model = OrderItem
        fields = ["id", "produit", "couleur", "quantite", "prix_unitaire", "total"]
        read_only_fields = fields

    def get_produit(self, obj):
        ref = obj.product_variant.product_reference
        return {"id": ref.id, "nom": ref.reference_name, "nom_complet": f"{ref.brand.nom} {ref.reference_name}".strip()}

    def get_total(self, obj):
        return Decimal("0") if obj.retourne else obj.prix_unitaire * obj.quantite


class CommandeEnLigneSerializer(serializers.ModelSerializer):
    """Accusé de commande renvoyé APRÈS création.

    Sert uniquement à l'écran de confirmation : le client repart avec son
    numéro et le détail de ce qu'il a validé. Il n'existe pas d'endpoint pour
    la relire — sans compte, rien ne permettrait d'authentifier le demandeur.
    """

    statut = serializers.CharField(source="statut_courant", read_only=True)
    statut_label = serializers.CharField(source="get_statut_courant_display", read_only=True)
    boutique = serializers.SerializerMethodField()
    items = CommandeItemSerializer(many=True, read_only=True)
    note = serializers.CharField(source="note_livreur", read_only=True)
    frais_livraison = serializers.DecimalField(max_digits=10, decimal_places=2, coerce_to_string=False, read_only=True)
    total_a_payer = serializers.DecimalField(max_digits=12, decimal_places=2, coerce_to_string=False, read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "numero", "statut", "statut_label", "date_commande", "boutique", "livraison_zone",
            "adresse_livraison", "client_nom", "telephone", "telephone_2", "note",
            "frais_livraison", "total_a_payer", "items", "created_at",
        ]
        read_only_fields = fields

    def get_boutique(self, obj):
        # Les coordonnées accompagnent l'accusé : pour un retrait sur place,
        # c'est la seule fois où le client voit où aller et qui appeler.
        mag = obj.magasin
        return {
            "id": mag.id,
            "nom": mag.shop_name,
            "adresse": mag.adresse or "",
            "telephone": mag.telephone or "",
            "telephone_2": mag.telephone_2 or "",
        }
