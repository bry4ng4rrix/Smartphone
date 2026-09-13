from decimal import Decimal

from django.db import models
from django.utils import timezone

from catalog.models import ProductVariant

# --------------------------------------------------------------------------- #
# Devises — la devise de référence comptable est l'ariary (MGA) : chaque
# montant saisi dans une autre devise est converti avec le taux du moment et
# conservé avec son montant / sa devise / son taux d'origine.
# --------------------------------------------------------------------------- #

DEVISE_CHOICES = (
    ("MGA", "Ariary (MGA)"),
    ("USD", "Dollar US (USD)"),
    ("EUR", "Euro (EUR)"),
    ("CNY", "Yuan (CNY)"),
)
DEVISE_REFERENCE = "MGA"
ZERO = Decimal("0")
DEUX_DEC = Decimal("0.01")


def convertir_en_mga(montant, devise, taux_change):
    """montant × taux (1 pour le MGA), arrondi au centime."""
    montant = Decimal(str(montant or 0))
    taux = Decimal("1") if devise == DEVISE_REFERENCE else Decimal(str(taux_change or 0))
    return (montant * taux).quantize(DEUX_DEC)


class Supplier(models.Model):
    """Fournisseur (fiche) — partagé par toute la société, comme les zones de
    livraison et les catégories de caisse (les approvisionnements, eux,
    restent rattachés à un magasin)."""

    admin_profile = models.ForeignKey(
        "users.AdminProfile", on_delete=models.CASCADE, related_name="suppliers"
    )
    nom = models.CharField(max_length=150)
    pays = models.CharField(max_length=100, blank=True)
    contact = models.CharField(max_length=150, blank=True)
    telephone = models.CharField(max_length=40, blank=True)
    email = models.EmailField(blank=True)
    adresse = models.CharField(max_length=255, blank=True)
    notes = models.TextField(blank=True)
    # Devise habituelle de ce fournisseur (préremplie sur ses approvisionnements).
    devise = models.CharField(max_length=3, choices=DEVISE_CHOICES, default="USD")
    actif = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Fournisseur"
        verbose_name_plural = "Fournisseurs"
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class SupplierOrder(models.Model):
    """Approvisionnement / commande fournisseur (§7.6 Smartreadme.md) : suit
    le coût RÉEL d'une importation jusqu'à l'arrivée à Madagascar —
    paiements fournisseur (historisés, multi-devises) + transport + douane +
    taxes + autres frais — puis le coût de revient par pièce.

    Les champs `prix_fournisseur`, `fret_import` et `douane` de la première
    version sont conservés (montants saisis directement en MGA) : ils
    entrent toujours dans le calcul, les anciens approvisionnements gardent
    donc exactement leur coût. Les nouveaux passent par les lignes (prix
    unitaire fournisseur), les paiements et les frais typés.
    """

    STATUT_CHOICES = (
        ("BROUILLON", "Brouillon"),
        ("COMMANDE", "Commandé"),
        ("PARTIELLEMENT_PAYE", "Partiellement payé"),
        ("PAYE", "Payé"),
        ("PREPARE", "Préparé par le fournisseur"),
        ("EN_TRANSIT", "En transit"),
        ("ARRIVE", "Arrivé à Madagascar"),
        ("PARTIELLEMENT_RECU", "Partiellement réceptionné"),
        ("RECU", "Réceptionné"),
        ("COUT_FINALISE", "Coût finalisé"),
    )
    # Ordre logique du workflow (les paiements peuvent survenir à tout moment
    # avant la finalisation ; PARTIELLEMENT_PAYE / PAYE sont dérivés des
    # paiements tant que la marchandise n'est pas plus avancée).
    STATUT_ORDER = [s for s, _ in STATUT_CHOICES]

    ALLOCATION_CHOICES = (
        ("VALEUR", "Proportionnelle à la valeur d'achat"),
        ("QUANTITE", "Proportionnelle à la quantité"),
        ("MANUEL", "Manuelle (par ligne)"),
    )

    MODE_TRANSPORT_CHOICES = (
        ("AERIEN", "Aérien"),
        ("MARITIME", "Maritime"),
        ("ROUTIER", "Routier"),
        ("EXPRESS", "Express / colis"),
        ("AUTRE", "Autre"),
    )

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="supplier_orders"
    )
    supplier = models.ForeignKey(
        Supplier, on_delete=models.SET_NULL, null=True, blank=True, related_name="orders"
    )
    numero = models.CharField(max_length=30, unique=True, editable=False)
    date = models.DateField(default=timezone.localdate)
    description = models.CharField(max_length=255, blank=True, null=True)
    statut = models.CharField(max_length=20, choices=STATUT_CHOICES, default="BROUILLON")

    # Devise de la commande (prix unitaires des lignes) et taux MGA retenu.
    devise = models.CharField(max_length=3, choices=DEVISE_CHOICES, default="MGA")
    taux_change = models.DecimalField(max_digits=14, decimal_places=4, default=Decimal("1"))
    methode_allocation = models.CharField(max_length=10, choices=ALLOCATION_CHOICES, default="VALEUR")

    # Première version (montants MGA saisis directement) — toujours pris en compte.
    prix_fournisseur = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    fret_import = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    douane = models.DecimalField(max_digits=14, decimal_places=2, default=0)

    # Transport (phase 4)
    date_expedition = models.DateField(null=True, blank=True)
    transporteur = models.CharField(max_length=150, blank=True)
    mode_transport = models.CharField(max_length=10, choices=MODE_TRANSPORT_CHOICES, blank=True)
    tracking = models.CharField(max_length=150, blank=True)
    lieu_depart = models.CharField(max_length=150, blank=True)
    destination = models.CharField(max_length=150, blank=True, default="Madagascar")
    date_arrivee = models.DateField(null=True, blank=True)

    # Calculés (suppliers/services.py::recompute_costs) — en MGA.
    total_qty = models.PositiveIntegerField(default=0, editable=False)
    valeur_achat_mga = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)
    total_frais_mga = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)
    cout_total = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)
    cout_unitaire = models.DecimalField(max_digits=14, decimal_places=2, default=0, editable=False)

    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="supplier_orders"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    received_at = models.DateTimeField(null=True, blank=True)
    finalise_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "Approvisionnement fournisseur"
        verbose_name_plural = "Approvisionnements fournisseur"
        ordering = ["-created_at"]

    def generate_numero(self):
        today = timezone.localdate()
        prefix = f"SUP-{self.magasin_id}-{today:%Y%m%d}-"
        last = SupplierOrder.objects.filter(magasin=self.magasin, numero__startswith=prefix).order_by("-numero").first()
        seq = int(last.numero[-4:]) + 1 if last else 1
        return f"{prefix}{seq:04d}"

    def save(self, *args, **kwargs):
        if not self.numero:
            self.numero = self.generate_numero()
        super().save(*args, **kwargs)

    def __str__(self):
        return self.numero

    # --- montants dérivés (MGA) --------------------------------------------- #

    @property
    def total_paye_mga(self):
        # Somme en base (pas via un éventuel cache prefetch obsolète).
        from django.db.models import Sum

        return self.payments.aggregate(t=Sum("montant_mga"))["t"] or ZERO

    @property
    def total_paye_devise(self):
        """Total payé exprimé dans la devise de la commande (paiements de la
        même devise seulement — les autres sont comptés via le MGA)."""
        return sum((p.montant for p in self.payments.all() if p.devise == self.devise), ZERO)

    @property
    def reste_a_payer_mga(self):
        return max(self.valeur_achat_mga - self.total_paye_mga, ZERO)

    @property
    def pourcentage_paye(self):
        if not self.valeur_achat_mga:
            return Decimal("0")
        return min((self.total_paye_mga / self.valeur_achat_mga * 100).quantize(Decimal("0.1")), Decimal("100"))

    @property
    def total_recu(self):
        from django.db.models import Sum

        return self.lines.aggregate(t=Sum("quantite_recue"))["t"] or 0

    @property
    def est_finalise(self):
        return self.statut == "COUT_FINALISE"

    @property
    def cout_moyen_unitaire(self):
        """Coût moyen par pièce arrivée (valeur réelle / quantité retenue)."""
        return self.cout_unitaire


class SupplierOrderLine(models.Model):
    supplier_order = models.ForeignKey(SupplierOrder, on_delete=models.CASCADE, related_name="lines")
    product_variant = models.ForeignKey(ProductVariant, on_delete=models.PROTECT, related_name="supplier_order_lines")
    quantite = models.PositiveIntegerField()
    # Réception (partielle possible) — ce qui est réellement entré en stock.
    quantite_recue = models.PositiveIntegerField(default=0)
    # Prix fournisseur unitaire dans la devise de la commande (0 sur les
    # anciennes commandes : la valeur d'achat vient alors de `prix_fournisseur`).
    prix_unitaire = models.DecimalField(max_digits=14, decimal_places=4, default=0)
    # Allocation manuelle des frais (méthode MANUEL), en MGA.
    allocation_manuelle_mga = models.DecimalField(max_digits=16, decimal_places=2, null=True, blank=True)

    # Snapshots remplis par services.recompute_costs (MGA) : valeur d'achat
    # de la ligne, frais qui lui sont attribués, coût de revient unitaire et
    # total de la ligne (valeur + frais).
    valeur_achat_mga = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)
    frais_alloues_mga = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)
    cout_unitaire_calcule = models.DecimalField(max_digits=14, decimal_places=2, default=0, editable=False)
    total_ligne = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)

    class Meta:
        verbose_name = "Ligne d'approvisionnement"
        verbose_name_plural = "Lignes d'approvisionnement"

    @property
    def total_fournisseur_devise(self):
        return (self.prix_unitaire * self.quantite).quantize(DEUX_DEC)

    @property
    def marge_unitaire(self):
        prix_vente = self.product_variant.product_reference.prix_vente
        return prix_vente - self.cout_unitaire_calcule

    def __str__(self):
        return f"{self.product_variant} x{self.quantite} ({self.supplier_order.numero})"


class _MontantDeviseMixin(models.Model):
    """Montant saisi + devise + taux + montant converti en MGA (trace comptable)."""

    montant = models.DecimalField(max_digits=16, decimal_places=2)
    devise = models.CharField(max_length=3, choices=DEVISE_CHOICES, default="MGA")
    taux_change = models.DecimalField(max_digits=14, decimal_places=4, default=Decimal("1"))
    montant_mga = models.DecimalField(max_digits=16, decimal_places=2, editable=False, default=0)

    class Meta:
        abstract = True

    def save(self, *args, **kwargs):
        if self.devise == DEVISE_REFERENCE:
            self.taux_change = Decimal("1")
        self.montant_mga = convertir_en_mga(self.montant, self.devise, self.taux_change)
        super().save(*args, **kwargs)


class SupplierPayment(_MontantDeviseMixin):
    """Un versement au fournisseur (acompte, solde…) — un approvisionnement
    en compte autant que nécessaire, l'historique est conservé."""

    TYPE_CHOICES = (
        ("ACOMPTE", "Acompte"),
        ("SOLDE", "Solde"),
        ("PARTIEL", "Paiement partiel"),
        ("AUTRE", "Autre"),
    )
    METHODE_CHOICES = (
        ("VIREMENT", "Virement bancaire"),
        ("MOBILE_MONEY", "Mobile money"),
        ("ESPECES", "Espèces"),
        ("CARTE", "Carte"),
        ("AUTRE", "Autre"),
    )

    supplier_order = models.ForeignKey(SupplierOrder, on_delete=models.CASCADE, related_name="payments")
    date = models.DateField(default=timezone.localdate)
    type_paiement = models.CharField(max_length=10, choices=TYPE_CHOICES, default="ACOMPTE")
    methode = models.CharField(max_length=15, choices=METHODE_CHOICES, default="VIREMENT")
    reference = models.CharField(max_length=150, blank=True)
    commentaire = models.CharField(max_length=255, blank=True)
    justificatif = models.FileField(upload_to="supplier_payments/", blank=True, null=True)
    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="supplier_payments"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Paiement fournisseur"
        verbose_name_plural = "Paiements fournisseur"
        ordering = ["date", "id"]

    def __str__(self):
        return f"{self.get_type_paiement_display()} {self.montant} {self.devise} ({self.supplier_order.numero})"


class SupplierFee(_MontantDeviseMixin):
    """Frais lié à l'importation (transport, douane, taxes…) — typé, daté,
    multi-devises, réparti entre les lignes par services.recompute_costs."""

    TYPE_CHOICES = (
        ("TRANSPORT", "Transport / expédition"),
        ("DOUANE", "Douane"),
        ("TAXES", "Taxes"),
        ("TRANSIT", "Frais de transit"),
        ("TRANSPORT_LOCAL", "Transport local"),
        ("PORTUAIRE", "Frais portuaires"),
        ("DOSSIER", "Frais de dossier"),
        ("AGENCE", "Frais d'agence"),
        ("ASSURANCE", "Assurance"),
        ("MANUTENTION", "Manutention"),
        ("AUTRE", "Autres frais"),
    )

    supplier_order = models.ForeignKey(SupplierOrder, on_delete=models.CASCADE, related_name="fees")
    type_frais = models.CharField(max_length=20, choices=TYPE_CHOICES, default="AUTRE")
    date = models.DateField(default=timezone.localdate)
    description = models.CharField(max_length=255, blank=True)
    prestataire = models.CharField(max_length=150, blank=True)
    justificatif = models.FileField(upload_to="supplier_fees/", blank=True, null=True)
    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="supplier_fees"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Frais d'importation"
        verbose_name_plural = "Frais d'importation"
        ordering = ["date", "id"]

    def __str__(self):
        return f"{self.get_type_frais_display()} {self.montant} {self.devise} ({self.supplier_order.numero})"


class VariantCostHistory(models.Model):
    """Historique du coût de revient (« masonkarena ») d'une variante : une
    entrée par approvisionnement finalisé. Jamais écrasé — le coût ACTUEL est
    la dernière entrée, le coût moyen pondéré se calcule sur l'ensemble."""

    product_variant = models.ForeignKey(ProductVariant, on_delete=models.CASCADE, related_name="cost_history")
    supplier_order = models.ForeignKey(SupplierOrder, on_delete=models.CASCADE, related_name="cost_history")
    quantite = models.PositiveIntegerField()
    valeur_achat_unitaire_mga = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    frais_unitaire_mga = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    cout_revient_unitaire_mga = models.DecimalField(max_digits=14, decimal_places=2)
    date = models.DateField(default=timezone.localdate)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Historique de coût de revient"
        verbose_name_plural = "Historique des coûts de revient"
        ordering = ["-date", "-id"]
        unique_together = ("product_variant", "supplier_order")

    def __str__(self):
        return f"{self.product_variant} — {self.cout_revient_unitaire_mga} Ar ({self.supplier_order.numero})"
