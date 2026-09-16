from decimal import Decimal

from django.db import models
from django.utils import timezone
from django.utils.text import slugify

from catalog.models import ProductVariant


class DeliveryZoneOption(models.Model):
    """Zone de livraison configurable (nom + prix) — CRUD dans Paramètres
    (§ demande), partagée par toute la société comme CaisseCategory (les
    frais ne varient pas d'un magasin à l'autre aujourd'hui). Distincte du
    retrait sur place ("Récupération"), qui reste un cas structurellement
    différent (pas de livreur, pas de frais) plutôt qu'une simple zone à prix
    0 — voir Order.livraison_zone, qui stocke soit `code`, soit le littéral
    "RECUPERATION". `code` (stable, jamais réutilisé pour une autre zone)
    est ce qui est effectivement enregistré sur les commandes, pas l'id
    numérique ni le nom — modifier le nom/prix d'une zone ne change donc rien
    aux commandes déjà passées avec cette zone."""

    admin_profile = models.ForeignKey(
        "users.AdminProfile", on_delete=models.CASCADE, related_name="delivery_zones"
    )
    code = models.SlugField(max_length=20)
    nom = models.CharField(max_length=100)
    prix = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    # Ce que la livraison de cette zone COÛTE réellement (agence, coursier,
    # livreur) — distinct de `prix`, facturé au client. Sert au gain réel
    # (finance/services.py) : livraison client − coût agence = résultat livraison.
    cout_agence = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    actif = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Zone de livraison"
        verbose_name_plural = "Zones de livraison"
        unique_together = ("admin_profile", "code")
        ordering = ["prix", "nom"]

    def save(self, *args, **kwargs):
        if not self.code:
            base = slugify(self.nom).upper().replace("-", "")[:16] or "ZONE"
            code = base
            suffix = 2
            qs = DeliveryZoneOption.objects.filter(admin_profile=self.admin_profile)
            while qs.filter(code=code).exclude(pk=self.pk).exists():
                code = f"{base}{suffix}"
                suffix += 1
            self.code = code
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.nom} ({self.prix} Ar)"


class Order(models.Model):
    """Commande client (§6, §11 Smartreadme.md). Le workflow des 6 statuts et
    son impact sur le stock sont gérés exclusivement par orders/services.py —
    jamais directement ici ni dans les vues."""

    STATUT_CHOICES = (
        # Commande passée depuis l'espace client (app `clients`) : elle attend
        # la validation du gérant avant d'entrer dans le workflow habituel
        # (approbation -> "Nouvelle"). Aucun stock n'est touché à ce stade.
        ("EN_ATTENTE_APPROBATION", "En attente d'approbation"),
        ("NOUVELLE", "Nouvelle"),
        ("EN_PREPARATION", "En préparation"),
        ("PRETE", "Prête"),
        ("EN_LIVRAISON", "En livraison"),
        ("LIVRE", "Livré"),
        ("RETOUR", "Retour"),
        ("ANNULEE", "Annulée"),
    )

    MODE_PAIEMENT_CHOICES = (
        ("AVANT", "Paiement avant la livraison"),
        ("LIVRAISON", "Paiement à la livraison"),
    )

    # Ordre strict des statuts : une transition ne peut sauter d'étape, sauf
    # override gérant (voir TRANSITIONS dans services.py — §5 Smartreadme.md).
    STATUT_ORDER = ["NOUVELLE", "EN_PREPARATION", "PRETE", "EN_LIVRAISON", "LIVRE"]

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="orders"
    )
    numero = models.CharField(max_length=30, unique=True, editable=False)
    # DateTime (pas juste Date) pour capter l'heure précise de la commande —
    # auto = maintenant si non fourni, modifiable par le gérant (§6 Smartreadme.md).
    date_commande = models.DateTimeField(default=timezone.now)
    client_nom = models.CharField(max_length=255)
    telephone = models.CharField(max_length=20)
    # Second numéro, facultatif (§ demande) : un client donne souvent un
    # numéro de secours, ou celui de la personne qui réceptionne à sa place.
    # Le livreur voit les deux et peut appeler l'un ou l'autre.
    telephone_2 = models.CharField(max_length=20, blank=True)
    # Stocke soit le `code` d'une DeliveryZoneOption (CRUD Paramètres),
    # soit le littéral "RECUPERATION" — voir DeliveryZoneOption ci-dessus.
    livraison_zone = models.CharField(max_length=20)
    # Adresse texte libre en complément de la zone (qui ne sert qu'au calcul
    # des frais) — nécessaire au livreur pour trouver le client.
    adresse_livraison = models.CharField(max_length=255, blank=True, null=True)
    # Le client paie avant (à la commande) ou à la livraison (contre
    # remboursement) — sans effet sur le stock/statut, juste indicatif pour
    # le livreur/gérant (§ demande). Sans objet pour un retrait sur place.
    mode_paiement = models.CharField(max_length=20, choices=MODE_PAIEMENT_CHOICES, default="LIVRAISON")
    frais_livraison = models.DecimalField(max_digits=10, decimal_places=2, editable=False, default=0)
    total_a_payer = models.DecimalField(max_digits=12, decimal_places=2, editable=False, default=0)
    # Coût réel de livraison de CETTE commande (surcharge du cout_agence de la
    # zone, ex : course exceptionnelle). Vide = coût de la zone.
    frais_agence = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    # Deux notes distinctes, chacune destinée à un seul rôle (§ demande) — le
    # préparateur ne voit jamais la note du livreur, et inversement.
    note_preparateur = models.TextField(blank=True, null=True)
    note_livreur = models.TextField(blank=True, null=True)
    # max_length 30 : "EN_ATTENTE_APPROBATION" (espace client) dépasse 20.
    statut_courant = models.CharField(max_length=30, choices=STATUT_CHOICES, default="NOUVELLE")

    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="orders_created"
    )
    # Préparateur/livreur désigné pour CETTE commande (un seul à la fois par
    # personne — voir orders/services.py::is_preparateur_busy/is_livreur_busy)
    # — assigné par le gérant (ou en auto-affectation) au moment de passer la
    # commande à "En préparation"/"En livraison".
    preparateur = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="orders_prepared"
    )
    livreur = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="orders_delivered"
    )
    # HISTORIQUE — l'affectation d'une commande à une campagne est désormais
    # AUTOMATIQUE, par période (finance/services.py::commandes_du_boost :
    # date_commande entre date_debut et date_fin du boost). Ce champ n'est
    # plus jamais renseigné ; il est conservé pour ne perdre aucune donnée
    # ancienne (audit) et n'entre plus dans aucun calcul.
    campagne = models.ForeignKey(
        "orders.MarketingCampaign", on_delete=models.SET_NULL, null=True, blank=True, related_name="orders"
    )
    # Compte client de l'espace en ligne à l'origine de la commande (app
    # `clients`) — null pour toute commande saisie en interne. Additif :
    # rien ne change pour les commandes existantes.
    client = models.ForeignKey(
        "clients.Client", on_delete=models.SET_NULL, null=True, blank=True, related_name="orders"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Commande"
        verbose_name_plural = "Commandes"
        ordering = ["-created_at"]
        # Toutes les recherches par période (boosts, rapports, jour J du
        # livreur) filtrent sur magasin + date_commande.
        indexes = [models.Index(fields=["magasin", "date_commande"], name="orders_order_mag_date_idx")]

    def generate_numero(self):
        today = timezone.localdate()
        prefix = f"CMD-{self.magasin_id}-{today:%Y%m%d}-"
        last = (
            Order.objects.filter(magasin=self.magasin, numero__startswith=prefix)
            .order_by("-numero")
            .first()
        )
        seq = int(last.numero[-4:]) + 1 if last else 1
        return f"{prefix}{seq:04d}"

    def save(self, *args, **kwargs):
        if not self.numero:
            self.numero = self.generate_numero()
        if self.livraison_zone and self.livraison_zone != "RECUPERATION":
            try:
                admin_profile = self.magasin.admin.admin_profile
            except Exception:
                admin_profile = None
            zone = (
                DeliveryZoneOption.objects.filter(admin_profile=admin_profile, code=self.livraison_zone).first()
                if admin_profile
                else None
            )
            self.frais_livraison = zone.prix if zone else 0
        else:
            self.frais_livraison = 0
        super().save(*args, **kwargs)

    @property
    def est_commande_client(self):
        """Vrai pour une commande passée depuis l'espace client."""
        return self.client_id is not None

    @property
    def remise_total(self):
        """Somme des remises accordées sur les articles effectivement remis
        (les articles rapportés ne sont pas facturés, leur remise non plus)."""
        return sum(
            (item.remise_unitaire * item.quantite for item in self.items.all() if not item.retourne),
            Decimal("0"),
        )

    def recompute_total(self):
        """Total à encaisser = articles effectivement remis + frais.

        Un article rapporté par le livreur (`OrderItem.retourne`) n'est pas
        facturé : le client ne paie que ce qu'il a reçu (§ demande). Les frais
        de livraison, eux, restent dus — le déplacement a bien eu lieu.
        """
        items_total = sum(
            (
                item.prix_unitaire * item.quantite
                for item in self.items.all()
                if not item.retourne
            ),
            start=0,
        )
        self.total_a_payer = items_total + self.frais_livraison
        self.save(update_fields=["total_a_payer"])

    def __str__(self):
        return self.numero


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="items")
    product_variant = models.ForeignKey(ProductVariant, on_delete=models.PROTECT, related_name="order_items")
    # Snapshot du prix au moment de la commande — l'historique reste correct
    # même si le prix catalogue change ensuite (§11 Smartreadme.md).
    prix_unitaire = models.DecimalField(max_digits=12, decimal_places=2, editable=False)
    # Prix catalogue au moment de la commande — quand le gérant accorde une
    # remise sur un article, `prix_unitaire` est le prix remisé (celui que
    # voient le préparateur et le livreur, et qui entre dans le total et le
    # bilan) et `prix_catalogue` garde le prix de vente d'origine : le stock
    # et le catalogue ne changent pas (§ demande). Null sur les commandes
    # antérieures à cette fonctionnalité.
    prix_catalogue = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True, editable=False)
    quantite = models.PositiveIntegerField(default=1)
    # Article rapporté par le livreur lors d'une livraison partielle
    # (§ demande) : le client n'en a pas voulu, il repart en stock et sort du
    # total à payer. Voir Order.recompute_total et
    # services.change_order_status.
    retourne = models.BooleanField(default=False)

    class Meta:
        verbose_name = "Article de commande"
        verbose_name_plural = "Articles de commande"

    def save(self, *args, **kwargs):
        if self.prix_catalogue is None:
            self.prix_catalogue = self.product_variant.product_reference.prix_vente
        if self.prix_unitaire is None:
            self.prix_unitaire = self.prix_catalogue
        super().save(*args, **kwargs)

    @property
    def remise_unitaire(self):
        """Remise accordée par article (prix catalogue − prix remisé), 0 sans
        remise ou sur une commande antérieure au prix catalogue."""
        if self.prix_catalogue is None:
            return Decimal("0")
        return max(self.prix_catalogue - self.prix_unitaire, Decimal("0"))

    def __str__(self):
        return f"{self.product_variant} x{self.quantite} ({self.order.numero})"


class OrderStatusHistory(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="status_history")
    ancien_statut = models.CharField(max_length=30, choices=Order.STATUT_CHOICES, blank=True, null=True)
    nouveau_statut = models.CharField(max_length=30, choices=Order.STATUT_CHOICES)
    changed_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="order_status_changes"
    )
    note = models.CharField(max_length=255, blank=True, null=True)
    # Photo justificative optionnelle (ex : preuve que la préparation est
    # faite, jointe par le préparateur/gérant au passage "Prête" — § demande).
    photo = models.ImageField(upload_to="order_status_photos/", blank=True, null=True)
    # Pas `auto_now_add` : le gérant peut renseigner une heure manuelle pour
    # l'affectation préparateur/livreur (ex: consigner une heure passée) —
    # voir orders/services.py::change_order_status(assigned_at=...). Sans
    # valeur fournie, se comporte comme auto_now_add (= maintenant).
    timestamp = models.DateTimeField(default=timezone.now)

    class Meta:
        verbose_name = "Historique statut commande"
        verbose_name_plural = "Historiques statut commande"
        ordering = ["timestamp"]

    def __str__(self):
        return f"{self.order.numero}: {self.ancien_statut} -> {self.nouveau_statut}"


class ExpenseType(models.Model):
    """Type de dépense du livreur, configurable dans Paramètres (§ demande) —
    repas, carburant, enveloppe… Même principe que DeliveryZoneOption : le
    catalogue appartient à la société, pas à un magasin.

    `prix_unitaire` n'est qu'une valeur par défaut proposée à la saisie : le
    montant réellement retenu est figé sur la dépense (voir
    LivreurExpense.prix_unitaire), pour qu'une révision de tarif ne réécrive
    pas les bilans déjà validés.
    """

    admin_profile = models.ForeignKey(
        "users.AdminProfile", on_delete=models.CASCADE, related_name="expense_types"
    )
    nom = models.CharField(max_length=100)
    prix_unitaire = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    # Vrai pour une dépense qui se compte (enveloppes…) : la saisie propose
    # alors une quantité, et le montant vaut prix_unitaire x quantite.
    par_unite = models.BooleanField(default=False)
    actif = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Type de dépense"
        verbose_name_plural = "Types de dépense"
        unique_together = ("admin_profile", "nom")
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class LivreurExpense(models.Model):
    """Dépense déclarée par un livreur sur sa journée (§ demande).

    Elle n'entre dans aucun bilan tant que le gérant ne l'a pas acceptée :
    une dépense en attente ou refusée ne doit pas venir diminuer l'argent
    remis. Une fois acceptée, elle est déduite du bilan du jour de CE
    livreur.

    Le libellé et le prix unitaire sont recopiés depuis le type au moment de
    la déclaration : modifier ou supprimer un type plus tard ne réécrit pas
    les dépenses passées.
    """

    STATUT_CHOICES = (
        ("EN_ATTENTE", "En attente"),
        ("ACCEPTE", "Acceptée"),
        ("REJETE", "Rejetée"),
    )

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="livreur_expenses"
    )
    livreur = models.ForeignKey(
        "users.CustomUser", on_delete=models.CASCADE, related_name="expenses"
    )
    # Null pour une dépense libre, saisie hors catalogue ("ou autre").
    type_depense = models.ForeignKey(
        ExpenseType, on_delete=models.SET_NULL, null=True, blank=True, related_name="expenses"
    )
    libelle = models.CharField(max_length=100)
    prix_unitaire = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    quantite = models.PositiveIntegerField(default=1)
    montant = models.DecimalField(max_digits=12, decimal_places=2, default=0, editable=False)
    motif = models.TextField(blank=True)

    # Jour auquel la dépense se rattache — c'est ce champ qui la fait entrer
    # dans un bilan, pas created_at : une dépense saisie tard le soir reste
    # celle de sa journée de travail.
    date = models.DateField(default=timezone.localdate)

    statut = models.CharField(max_length=12, choices=STATUT_CHOICES, default="EN_ATTENTE")
    motif_rejet = models.TextField(blank=True)
    resolved_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="resolved_expenses",
    )
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Dépense livreur"
        verbose_name_plural = "Dépenses livreur"
        ordering = ["-created_at"]

    def save(self, *args, **kwargs):
        self.montant = self.prix_unitaire * self.quantite
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.libelle} — {self.montant} Ar ({self.get_statut_display()})"


class MarketingCampaign(models.Model):
    """Campagne publicitaire (boost Facebook, TikTok…) : ce qu'elle a coûté et,
    via les commandes de sa PÉRIODE (affectation automatique), ce qu'elle a
    rapporté. Une dépense de campagne ne passe pas par la caisse (sauf
    `en_caisse`) : ne pas la compter deux fois dans le résultat."""

    PLATEFORME_CHOICES = (
        ("FACEBOOK", "Facebook"),
        ("INSTAGRAM", "Instagram"),
        ("TIKTOK", "TikTok"),
        ("GOOGLE", "Google"),
        ("AUTRE", "Autre"),
    )

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="marketing_campaigns"
    )
    nom = models.CharField(max_length=150)
    plateforme = models.CharField(max_length=20, choices=PLATEFORME_CHOICES, default="FACEBOOK")
    TYPE_PERIODE_CHOICES = (
        ("JOUR", "Jour"),
        ("SEMAINE", "Semaine"),
        ("MOIS", "Mois"),
        ("PERSONNALISE", "Personnalisée"),
    )
    montant = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # Boost par période (finance) : le montant est réparti sur les articles
    # vendus entre date_debut et date_fin (bornes comprises, jour local du
    # magasin — même référence `date_commande` que tout le reporting).
    # `date_fin` vide = boost EN COURS : couvre jusqu'à aujourd'hui.
    #
    # AFFECTATION AUTOMATIQUE : une commande est « concernée » par un boost
    # dès que sa date de livraison prévue tombe dans la période — aucune
    # sélection manuelle (voir finance/services.py::commandes_du_boost).
    # CHEVAUCHEMENT : deux boosts peuvent couvrir le même jour (deux
    # plateformes en parallèle) ; chacun est réparti sur SA période et une
    # commande de la zone commune est concernée par les deux, avec une part de
    # chacun — pas de priorité arbitraire, pas d'interdiction.
    type_periode = models.CharField(max_length=15, choices=TYPE_PERIODE_CHOICES, default="PERSONNALISE")
    date_debut = models.DateField(default=timezone.localdate)
    date_fin = models.DateField(null=True, blank=True)
    note = models.TextField(blank=True)
    actif = models.BooleanField(default=True)
    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Campagne marketing"
        verbose_name_plural = "Campagnes marketing"
        ordering = ["-date_debut", "-created_at"]
        indexes = [models.Index(fields=["magasin", "date_debut", "date_fin"], name="orders_campaign_periode_idx")]

    def __str__(self):
        return f"{self.nom} ({self.get_plateforme_display()})"

    @property
    def date_fin_effective(self):
        """Dernier jour couvert : `date_fin`, ou aujourd'hui (jour local du
        magasin) tant que le boost est en cours — jamais au-delà du présent."""
        return self.date_fin or timezone.localdate()

    def couvre(self, jour):
        """Le jour (date locale) est-il dans la période, bornes comprises ?"""
        return self.actif and self.date_debut <= jour <= self.date_fin_effective
