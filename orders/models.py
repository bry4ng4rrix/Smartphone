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
    # Deux notes distinctes, chacune destinée à un seul rôle (§ demande) — le
    # préparateur ne voit jamais la note du livreur, et inversement.
    note_preparateur = models.TextField(blank=True, null=True)
    note_livreur = models.TextField(blank=True, null=True)
    statut_courant = models.CharField(max_length=20, choices=STATUT_CHOICES, default="NOUVELLE")

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
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Commande"
        verbose_name_plural = "Commandes"
        ordering = ["-created_at"]

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
        if self.prix_unitaire is None:
            self.prix_unitaire = self.product_variant.product_reference.prix_vente
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.product_variant} x{self.quantite} ({self.order.numero})"


class OrderStatusHistory(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="status_history")
    ancien_statut = models.CharField(max_length=20, choices=Order.STATUT_CHOICES, blank=True, null=True)
    nouveau_statut = models.CharField(max_length=20, choices=Order.STATUT_CHOICES)
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
