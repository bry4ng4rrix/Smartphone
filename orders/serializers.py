from django.utils import timezone
from rest_framework import serializers

from catalog.models import ProductVariant
from users.subscriptions import get_company_owner

from .models import (
    DeliveryZoneOption,
    MarketingCampaign,
    ExpenseType,
    LivreurExpense,
    Order,
    OrderItem,
    OrderStatusHistory,
)


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


class DeliveryZoneOptionSerializer(serializers.ModelSerializer):
    """Zone de livraison (nom + prix) — CRUD dans Paramètres (§ demande).
    `code` est généré une seule fois à la création (voir DeliveryZoneOption.save)
    et ne change plus jamais — les commandes déjà passées avec cette zone y
    restent attachées même si le nom/prix est modifié plus tard."""

    class Meta:
        model = DeliveryZoneOption
        fields = ["id", "code", "nom", "prix", "cout_agence", "actif", "created_at"]
        read_only_fields = ["id", "code", "created_at"]


class OrderItemSerializer(serializers.ModelSerializer):
    """Vue complète d'un article — gérant uniquement (inclut le prix)."""

    reference_name = serializers.CharField(source="product_variant.product_reference.reference_name", read_only=True)
    # Référence du produit : sert à proposer ses autres couleurs quand le
    # gérant change la couleur d'un article (voir changer_couleur_item).
    product_reference = serializers.IntegerField(source="product_variant.product_reference_id", read_only=True)
    couleur = serializers.CharField(source="product_variant.couleur", read_only=True)
    brand_name = serializers.CharField(source="product_variant.product_reference.brand.nom", read_only=True)
    type_name = serializers.CharField(source="product_variant.product_reference.type.nom", read_only=True)
    category_name = serializers.CharField(source="product_variant.product_reference.type.category.nom", read_only=True)

    # Prix catalogue à la commande et remise unitaire accordée par le gérant
    # (0 sans remise) — voir OrderItem.prix_catalogue.
    remise_unitaire = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model = OrderItem
        fields = [
            "id", "product_variant", "product_reference", "reference_name", "brand_name", "type_name",
            "category_name", "couleur", "prix_unitaire", "prix_catalogue", "remise_unitaire", "quantite",
            "retourne",
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
            "retourne",
        ]


class OrderItemPreparateurSerializer(OrderItemPublicSerializer):
    """Articles vus par le PRÉPARATEUR : comme la vue publique, plus le prix
    de l'article (§ demande). Il annonce le prix au client au comptoir et
    vérifie ce qu'il prépare ; en revanche les frais de livraison et le
    total à payer ne le concernent pas (voir OrderPreparateurSerializer) —
    c'est le livreur qui encaisse."""

    remise_unitaire = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta(OrderItemPublicSerializer.Meta):
        fields = OrderItemPublicSerializer.Meta.fields + [
            "prix_unitaire", "prix_catalogue", "remise_unitaire",
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
    # Campagne(s) — AUTOMATIQUE par période (§ demande) : les boosts actifs
    # dont la période couvre la date de livraison prévue, séparés par
    # « , » s'il y en a plusieurs (chevauchement). `campagne` (FK manuelle
    # historique) reste exposé en lecture, jamais renseigné.
    campagne_nom = serializers.SerializerMethodField()
    campagnes = serializers.SerializerMethodField()
    # Espace client : compte à l'origine de la commande (null en interne) et
    # drapeau pratique pour l'interface du gérant (additif, lecture seule).
    client_email = serializers.EmailField(source="client.email", read_only=True, default=None)
    est_commande_client = serializers.BooleanField(read_only=True)

    # Remise totale accordée sur la commande (0 sans remise) — visible par
    # tous les rôles pour l'annoncer au client, sans exposer les prix
    # unitaires aux préparateurs / livreurs.
    remise_total = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    def _boosts_de(self, obj):
        """Boosts couvrant la commande — une seule requête par magasin et par
        sérialisation (cache sur l'instance), puis test en mémoire."""
        cache = getattr(self, "_cache_boosts", None)
        if cache is None:
            cache = self._cache_boosts = {}
        boosts = cache.get(obj.magasin_id)
        if boosts is None:
            boosts = cache[obj.magasin_id] = list(
                MarketingCampaign.objects.filter(magasin_id=obj.magasin_id, actif=True).order_by("date_debut", "id")
            )
        if obj.date_commande is None:
            return []
        jour = timezone.localtime(obj.date_commande).date()
        return [b for b in boosts if b.couvre(jour)]

    def get_campagnes(self, obj):
        return [{"id": b.id, "nom": b.nom, "plateforme": b.plateforme} for b in self._boosts_de(obj)]

    def get_campagne_nom(self, obj):
        return ", ".join(b.nom for b in self._boosts_de(obj))

    class Meta:
        model = Order
        fields = [
            "id", "magasin", "numero", "date_commande", "client_nom", "telephone", "telephone_2", "livraison_zone",
            "adresse_livraison", "mode_paiement", "frais_livraison", "total_a_payer", "remise_total",
            "note_preparateur", "note_livreur", "statut_courant",
            "preparateur", "preparateur_name", "livreur", "livreur_name", "campagne", "campagne_nom", "campagnes",
            "client", "client_email", "est_commande_client", "items",
            "status_history", "created_at", "updated_at",
        ]
        read_only_fields = fields


class OrderPreparateurSerializer(serializers.ModelSerializer):
    """Module Dépôt — Préparateur (§7.2) : N° commande, Client, Téléphone,
    Produit + Couleur, Zone.

    Il voit le PRIX DE CHAQUE ARTICLE (§ demande) — ce qu'il prépare et
    annonce au comptoir — mais ni les frais de livraison ni le total à
    payer : l'encaissement est l'affaire du livreur, et ces montants
    brouillaient sa fiche. Toujours aucune donnée de coût ni de marge.
    """

    items = OrderItemPreparateurSerializer(many=True, read_only=True)
    preparateur_name = serializers.CharField(source="preparateur.full_name", read_only=True)
    # Qui livrera cette commande : le préparateur a besoin de le savoir pour
    # préparer/remettre le colis à la bonne personne (§ demande).
    livreur_name = serializers.CharField(source="livreur.full_name", read_only=True)

    # Remise totale accordée sur la commande (0 sans remise) — visible par
    # tous les rôles pour l'annoncer au client, sans exposer les prix
    # unitaires aux préparateurs / livreurs.
    remise_total = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "numero", "date_commande", "client_nom", "telephone", "telephone_2", "livraison_zone", "adresse_livraison",
            "mode_paiement", "remise_total", "statut_courant", "note_preparateur",
            "preparateur", "preparateur_name", "livreur", "livreur_name", "items", "created_at",
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

    # Remise totale accordée sur la commande (0 sans remise) — visible par
    # tous les rôles pour l'annoncer au client, sans exposer les prix
    # unitaires aux préparateurs / livreurs.
    remise_total = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "numero", "date_commande", "client_nom", "telephone", "telephone_2", "livraison_zone", "adresse_livraison",
            "mode_paiement", "frais_livraison", "total_a_payer", "remise_total", "statut_courant", "note_livreur",
            "livreur", "livreur_name", "items", "status_history", "created_at",
        ]
        read_only_fields = fields


class OrderCreateItemSerializer(serializers.Serializer):
    product_variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all())
    quantite = serializers.IntegerField(min_value=1, default=1)
    # Prix remisé (facultatif) : prix de vente appliqué à CETTE commande,
    # au plus égal au prix catalogue. Le catalogue et le stock ne changent
    # pas ; c'est ce prix que voient préparateur/livreur et qui entre dans le
    # total et le bilan du livreur (§ demande). Absent = prix catalogue.
    prix_unitaire = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=0, required=False, allow_null=True)

    def validate(self, attrs):
        prix = attrs.get("prix_unitaire")
        if prix is not None:
            catalogue = attrs["product_variant"].product_reference.prix_vente
            if prix > catalogue:
                raise serializers.ValidationError(
                    {"prix_unitaire": f"Le prix remisé ne peut pas dépasser le prix catalogue ({catalogue:.0f} Ar)."}
                )
        return attrs


class OrderCreateSerializer(serializers.Serializer):
    """Formulaire Nouvelle commande (§6 Smartreadme.md) — le gérant saisit la
    commande, prix/frais/total sont calculés côté serveur."""

    client_nom = serializers.CharField(max_length=255)
    telephone = serializers.RegexField(regex=r"^\+261\d{9}$", error_messages={
        "invalid": "Format attendu : +261XXXXXXXXX"
    })
    # Second numéro facultatif (§ demande) — même format s'il est renseigné,
    # mais une chaîne vide est acceptée : la plupart des commandes n'en ont pas.
    telephone_2 = serializers.RegexField(
        regex=r"^(\+261\d{9})?$", required=False, allow_blank=True, default="",
        error_messages={"invalid": "Format attendu : +261XXXXXXXXX"},
    )
    livraison_zone = serializers.CharField(max_length=20)
    adresse_livraison = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    mode_paiement = serializers.ChoiceField(choices=Order.MODE_PAIEMENT_CHOICES, required=False, default="LIVRAISON")
    # DateTime précis (pas juste une date) — vide -> maintenant (§6 Smartreadme.md).
    date_commande = serializers.DateTimeField(required=False)
    # Deux notes distinctes, chacune destinée à un seul rôle (§ demande).
    note_preparateur = serializers.CharField(required=False, allow_blank=True, default="")
    note_livreur = serializers.CharField(required=False, allow_blank=True, default="")
    items = OrderCreateItemSerializer(many=True)
    # Plus de champ `campagne` : l'affectation à un boost est automatique
    # par période (finance/services.py::commandes_du_boost). Une valeur
    # envoyée par un ancien client est simplement ignorée.

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
    telephone_2 = serializers.RegexField(
        regex=r"^(\+261\d{9})?$", required=False, allow_blank=True,
        error_messages={"invalid": "Format attendu : +261XXXXXXXXX"},
    )
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
    # Livraison partielle (§ demande) : identifiants des OrderItem réellement
    # remis au client. Absent = tout est remis. Liste vide = rien n'a été
    # livré, la commande bascule en "Retour" (voir change_order_status).
    items_livres = serializers.ListField(
        child=serializers.IntegerField(), required=False, allow_empty=True
    )


class ExpenseTypeSerializer(serializers.ModelSerializer):
    """Type de dépense configurable — CRUD dans Paramètres (§ demande)."""

    class Meta:
        model = ExpenseType
        fields = ["id", "nom", "prix_unitaire", "par_unite", "frais_livraison", "actif", "created_at"]
        read_only_fields = ["id", "created_at"]


class LivreurExpenseSerializer(serializers.ModelSerializer):
    """Dépense déclarée par un livreur. Lecture seule sur les champs décidés
    par le serveur : montant calculé, statut, et qui a tranché."""

    livreur_name = serializers.CharField(source="livreur.full_name", read_only=True)
    resolved_by_name = serializers.CharField(source="resolved_by.full_name", read_only=True)
    type_nom = serializers.CharField(source="type_depense.nom", read_only=True)

    class Meta:
        model = LivreurExpense
        fields = [
            "id", "livreur", "livreur_name", "type_depense", "type_nom",
            "libelle", "prix_unitaire", "quantite", "montant", "motif",
            "date", "statut", "motif_rejet",
            "resolved_by", "resolved_by_name", "resolved_at", "created_at",
        ]
        read_only_fields = [
            "id", "livreur", "livreur_name", "type_nom", "montant", "statut",
            "motif_rejet", "resolved_by", "resolved_by_name", "resolved_at",
            "created_at",
        ]

    def validate(self, attrs):
        """Le montant doit être positif : une dépense à 0 Ar n'a rien à faire
        dans un bilan, et un montant négatif viendrait l'augmenter."""
        prix = attrs.get("prix_unitaire", getattr(self.instance, "prix_unitaire", 0))
        quantite = attrs.get("quantite", getattr(self.instance, "quantite", 1))
        if prix is None or prix <= 0:
            raise serializers.ValidationError(
                {"prix_unitaire": "Le montant doit être supérieur à 0."}
            )
        if quantite < 1:
            raise serializers.ValidationError({"quantite": "Quantité minimale : 1."})
        return attrs


class MarketingCampaignSerializer(serializers.ModelSerializer):
    """Campagne / boost. Les commandes concernées ne se choisissent pas :
    elles sont déduites de la période (finance/services.py::commandes_du_boost)
    et résumées ici — `nb_commandes`, `nb_livrees`, `ca`, `cout_par_commande`,
    `periode_effective` — en plus du coût financier par article."""

    plateforme_label = serializers.CharField(source="get_plateforme_display", read_only=True)
    articles_vendus = serializers.SerializerMethodField()
    cout_par_article = serializers.SerializerMethodField()
    en_caisse = serializers.SerializerMethodField()
    nb_commandes = serializers.SerializerMethodField()
    nb_livrees = serializers.SerializerMethodField()
    ca = serializers.SerializerMethodField()
    cout_par_commande = serializers.SerializerMethodField()
    periode_effective = serializers.SerializerMethodField()

    def _resume(self, obj):
        # Un seul calcul par campagne et par sérialisation.
        cache = getattr(self, "_cache_resume", None)
        if cache is None:
            cache = self._cache_resume = {}
        if obj.pk not in cache:
            from finance.services import resume_boost

            cache[obj.pk] = resume_boost(obj)
        return cache[obj.pk]

    def get_nb_commandes(self, obj):
        return self._resume(obj)["nb_commandes"]

    def get_nb_livrees(self, obj):
        return self._resume(obj)["nb_livrees"]

    def get_ca(self, obj):
        return self._resume(obj)["ca"]

    def get_cout_par_commande(self, obj):
        return self._resume(obj)["cout_par_commande"]

    def get_periode_effective(self, obj):
        return self._resume(obj)["periode_effective"]

    def get_articles_vendus(self, obj):
        from finance.services import cout_boost_par_article
        return cout_boost_par_article(obj)[1]

    def get_cout_par_article(self, obj):
        from finance.services import cout_boost_par_article
        return cout_boost_par_article(obj)[0]

    def get_en_caisse(self, obj):
        from users.models import CaisseMovement
        return CaisseMovement.objects.filter(reference=f"BOOST:{obj.id}").exists()

    class Meta:
        model = MarketingCampaign
        fields = [
            "id", "magasin", "nom", "plateforme", "plateforme_label", "montant", "type_periode",
            "date_debut", "date_fin", "note", "actif", "created_at",
            "articles_vendus", "cout_par_article", "en_caisse",
            "nb_commandes", "nb_livrees", "ca", "cout_par_commande", "periode_effective",
        ]
        read_only_fields = ["magasin", "created_at"]

    def validate(self, attrs):
        debut = attrs.get("date_debut", getattr(self.instance, "date_debut", None))
        fin = attrs.get("date_fin", getattr(self.instance, "date_fin", None))
        if debut and fin and fin < debut:
            raise serializers.ValidationError({"date_fin": "La date de fin précède la date de début."})
        return attrs
