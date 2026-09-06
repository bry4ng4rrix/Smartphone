from rest_framework import serializers

from catalog.models import ProductVariant

from .models import Order, OrderItem, OrderStatusHistory


class OrderItemSerializer(serializers.ModelSerializer):
    """Vue complète d'un article — gérant uniquement (inclut le prix)."""

    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)

    class Meta:
        model = OrderItem
        fields = ["id", "product_variant", "reference_name", "couleur", "prix_unitaire", "quantite"]


class OrderItemPublicSerializer(serializers.ModelSerializer):
    """Vue restreinte — préparateur/livreur : pas de prix (§4, §7.2, §7.3 Smartreadme.md)."""

    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)

    class Meta:
        model = OrderItem
        fields = ["id", "reference_name", "couleur", "quantite"]


class OrderStatusHistorySerializer(serializers.ModelSerializer):
    changed_by_name = serializers.CharField(source="changed_by.full_name", read_only=True)

    class Meta:
        model = OrderStatusHistory
        fields = ["id", "ancien_statut", "nouveau_statut", "changed_by", "changed_by_name", "note", "timestamp"]


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
            "adresse_livraison", "frais_livraison", "total_a_payer", "note", "statut_courant",
            "preparateur", "preparateur_name", "livreur", "livreur_name", "items",
            "status_history", "created_at", "updated_at",
        ]
        read_only_fields = fields


class OrderPreparateurSerializer(serializers.ModelSerializer):
    """Module Dépôt — Préparateur (§7.2) : N° commande, Client, Produit +
    Couleur, Zone. Aucune donnée financière."""

    items = OrderItemPublicSerializer(many=True, read_only=True)
    preparateur_name = serializers.CharField(source="preparateur.full_name", read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "numero", "date_commande", "client_nom", "livraison_zone", "adresse_livraison",
            "statut_courant", "preparateur", "preparateur_name", "items", "created_at",
        ]
        read_only_fields = fields


class OrderLivreurSerializer(serializers.ModelSerializer):
    """Module Livreur (§7.3) : N° commande, Client, Téléphone, Produit, Zone,
    Total à encaisser. Pas de détail des prix unitaires ni de données de
    coût/marge."""

    items = OrderItemPublicSerializer(many=True, read_only=True)
    livreur_name = serializers.CharField(source="livreur.full_name", read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "numero", "date_commande", "client_nom", "telephone", "livraison_zone", "adresse_livraison",
            "total_a_payer", "statut_courant", "note", "livreur", "livreur_name", "items", "created_at",
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
    livraison_zone = serializers.ChoiceField(choices=Order.ZONE_CHOICES)
    adresse_livraison = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    # DateTime précis (pas juste une date) — vide -> maintenant (§6 Smartreadme.md).
    date_commande = serializers.DateTimeField(required=False)
    note = serializers.CharField(required=False, allow_blank=True, default="")
    items = OrderCreateItemSerializer(many=True)

    def validate_items(self, value):
        if not value:
            raise serializers.ValidationError("Au moins un article est requis.")
        return value


class OrderStatusChangeSerializer(serializers.Serializer):
    statut = serializers.ChoiceField(choices=Order.STATUT_CHOICES)
    note = serializers.CharField(required=False, allow_blank=True, default="")
    # Requis quand le gérant désigne lui-même qui prend la commande en charge
    # (Nouvelle -> En préparation / Prête -> En livraison) ; optionnel pour
    # une auto-affectation par le préparateur/livreur concerné.
    preparateur_id = serializers.IntegerField(required=False, allow_null=True)
    livreur_id = serializers.IntegerField(required=False, allow_null=True)
