from rest_framework import serializers

from catalog.models import ProductVariant
from users.subscriptions import get_company_owner

from .models import DeliveryZoneOption, Order, OrderItem, OrderStatusHistory


def _validate_zone_code(value, user):
    """Une zone valide est soit le littéral "RECUPERATION", soit le `code`
    d'une DeliveryZoneOption active de la société de l'utilisateur (CRUD
    Paramètres, § demande)."""
    if value == "RECUPERATION":
        return value
    owner = get_company_owner(user)
    admin_profile = getattr(owner, "admin_profile", None) if owner else None
    if not admin_profile or not DeliveryZoneOption.objects.filter(
        admin_profile=admin_profile, code=value, actif=True
    ).exists():
        raise serializers.ValidationError("Zone de livraison invalide.")
    return value


class OrderItemSerializer(serializers.ModelSerializer):
    """Vue complète d'un article — gérant uniquement (inclut le prix)."""

    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)
    brand_name = serializers.CharField(source="product_variant.product_reference.brand.nom", read_only=True)
    type_name = serializers.CharField(source="product_variant.product_reference.type.nom", read_only=True)
    category_name = serializers.CharField(source="product_variant.product_reference.type.category.nom", read_only=True)

    class Meta:
        model = OrderItem
        fields = [
            "id", "product_variant", "reference_name", "brand_name", "type_name", "category_name",
            "couleur", "prix_unitaire", "quantite",
        ]


class OrderItemPublicSerializer(serializers.ModelSerializer):
    """Vue restreinte — préparateur/livreur : pas de prix (§4, §7.2, §7.3 Smartreadme.md)."""

    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)
    brand_name = serializers.CharField(source="product_variant.product_reference.brand.nom", read_only=True)
    type_name = serializers.CharField(source="product_variant.product_reference.type.nom", read_only=True)
    category_name = serializers.CharField(source="product_variant.product_reference.type.category.nom", read_only=True)

    class Meta:
        model = OrderItem
        fields = [
            "id", "reference_name", "brand_name", "type_name", "category_name", "couleur", "quantite",
        ]


class OrderStatusHistorySerializer(serializers.ModelSerializer):
    changed_by_name = serializers.CharField(source="changed_by.full_name", read_only=True)

    class Meta:
        model = OrderStatusHistory
        fields = [
            "id", "ancien_statut", "nouveau_statut", "changed_by", "changed_by_name", "note", "photo", "timestamp",
        ]


class OrderGerantSerializer(serializers.ModelSerializer):
    """Vue complète — module Commandes du gérant (§7.1)."""

    items = OrderItemSerializer(many=True, read_only=True)
    status_history = OrderStatusHistorySerializer(many=True, read_only=True)
    preparateur_name = serializers.CharField(source="preparateur.full_name", read_only=True)
    livreur_name = serializers.CharField(source="livreur.full_name", read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "magasin", "numero", "date_commande", "client_nom", "telephone", "livraison_zone",
            "adresse_livraison", "mode_paiement", "frais_livraison", "total_a_payer",
            "note_preparateur", "note_livreur", "statut_courant",
            "preparateur", "preparateur_name", "livreur", "livreur_name", "items",
            "status_history", "created_at", "updated_at",
        ]
        read_only_fields = fields


class OrderPreparateurSerializer(serializers.ModelSerializer):
    """Module Dépôt — Préparateur (§7.2) : N° commande, Client, Téléphone,
    Produit + Couleur, Zone. Pas de détail des prix unitaires ni de données de
    coût/marge — seuls le sous-total (prix de vente), les frais de livraison
    et le total sont exposés, pour le résumé affiché avant confirmation
    d'une action (§ demande)."""

    items = OrderItemPublicSerializer(many=True, read_only=True)
    preparateur_name = serializers.CharField(source="preparateur.full_name", read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "numero", "date_commande", "client_nom", "telephone", "livraison_zone", "adresse_livraison",
            "mode_paiement", "frais_livraison", "total_a_payer", "statut_courant", "note_preparateur",
            "preparateur", "preparateur_name", "items", "created_at",
        ]
        read_only_fields = fields


class OrderLivreurSerializer(serializers.ModelSerializer):
    """Module Livreur (§7.3) : N° commande, Client, Téléphone, Produit, Zone,
    Frais de livraison, Total à encaisser. Pas de détail des prix unitaires
    ni de données de coût/marge. `status_history` expose aussi la photo de
    préparation jointe par le préparateur (§ demande — visible et
    téléchargeable par le livreur)."""

    items = OrderItemPublicSerializer(many=True, read_only=True)
    livreur_name = serializers.CharField(source="livreur.full_name", read_only=True)
    status_history = OrderStatusHistorySerializer(many=True, read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "numero", "date_commande", "client_nom", "telephone", "livraison_zone", "adresse_livraison",
            "mode_paiement", "frais_livraison", "total_a_payer", "statut_courant", "note_livreur",
            "livreur", "livreur_name", "items", "status_history", "created_at",
        ]
        read_only_fields = fields


class OrderCreateItemSerializer(serializers.Serializer):
    product_variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all())
    quantite = serializers.IntegerField(min_value=1, default=1)


class OrderCreateSerializer(serializers.Serializer):
    """Formulaire Nouvelle commande (§6 Smartreadme.md) — le gérant saisit la
    commande, prix/frais/total sont calculés côté serveur."""

    client_nom = serializers.CharField(max_length=255)
    telephone = serializers.RegexField(regex=r"^\+261\d{9}$", error_messages={
        "invalid": "Format attendu : +261XXXXXXXXX"
    })
    livraison_zone = serializers.CharField(max_length=20)
    adresse_livraison = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    mode_paiement = serializers.ChoiceField(choices=Order.MODE_PAIEMENT_CHOICES, required=False, default="LIVRAISON")
    # DateTime précis (pas juste une date) — vide -> maintenant (§6 Smartreadme.md).
    date_commande = serializers.DateTimeField(required=False)
    # Deux notes distinctes, chacune destinée à un seul rôle (§ demande).
    note_preparateur = serializers.CharField(required=False, allow_blank=True, default="")
    note_livreur = serializers.CharField(required=False, allow_blank=True, default="")
    items = OrderCreateItemSerializer(many=True)

    def validate_livraison_zone(self, value):
        return _validate_zone_code(value, self.context["request"].user)

    def validate_items(self, value):
        if not value:
            raise serializers.ValidationError("Au moins un article est requis.")
        return value


class OrderUpdateSerializer(serializers.Serializer):
    """Modification d'une commande — uniquement tant qu'elle est 'Nouvelle'
    (rien n'a encore été préparé/déduit du stock, donc les articles restent
    librement modifiables à ce stade — voir orders/views.py::partial_update)."""

    client_nom = serializers.CharField(max_length=255, required=False)
    telephone = serializers.RegexField(regex=r"^\+261\d{9}$", required=False, error_messages={
        "invalid": "Format attendu : +261XXXXXXXXX"
    })
    livraison_zone = serializers.CharField(max_length=20, required=False)
    adresse_livraison = serializers.CharField(max_length=255, required=False, allow_blank=True)
    mode_paiement = serializers.ChoiceField(choices=Order.MODE_PAIEMENT_CHOICES, required=False)
    date_commande = serializers.DateTimeField(required=False)
    note_preparateur = serializers.CharField(required=False, allow_blank=True)
    note_livreur = serializers.CharField(required=False, allow_blank=True)
    items = OrderCreateItemSerializer(many=True, required=False)

    def validate_livraison_zone(self, value):
        return _validate_zone_code(value, self.context["request"].user)

    def validate_items(self, value):
        if value is not None and not value:
            raise serializers.ValidationError("Au moins un article est requis.")
        return value


class OrderStatusChangeSerializer(serializers.Serializer):
    statut = serializers.ChoiceField(choices=Order.STATUT_CHOICES)
    note = serializers.CharField(required=False, allow_blank=True, default="")
    # Photo justificative optionnelle (ex : preuve de préparation au passage
    # "Prête") — voir OrderStatusHistory.photo.
    photo = serializers.ImageField(required=False, allow_null=True)
    # Requis quand le gérant désigne lui-même qui prend la commande en charge
    # (Nouvelle -> En préparation / Prête -> En livraison) ; optionnel pour
    # une auto-affectation par le préparateur/livreur concerné.
    preparateur_id = serializers.IntegerField(required=False, allow_null=True)
    livreur_id = serializers.IntegerField(required=False, allow_null=True)
    # Heure manuelle optionnelle pour l'affectation (voir services.change_order_status).
    assigned_at = serializers.DateTimeField(required=False, allow_null=True)
