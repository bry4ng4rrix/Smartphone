from decimal import Decimal

from django.db import models
from django.utils import timezone

from catalog.models import ProductVariant

# --------------------------------------------------------------------------- #
# Module Fournisseur — approvisionnements (§ demande « remplacement »).
#
#   Fournisseur → Approvisionnement (1 produit, 1 quantité)
#                  → Paiement 1, Paiement 2, … (taux du jour figé, MGA)
#                  → Expédition (départ Chine, transit, arrivée Madagascar)
#                  → Frais + Douane (UN seul montant, MGA)
#                  → Coût total rendu Madagascar = Σ paiements MGA + Frais + Douane
#                  → Coût de revient par pièce = coût total / quantité
#
# Un approvisionnement ne porte qu'UN SEUL produit : pas de lignes, pas de
# répartition entre produits. Le même produit acheté plusieurs fois = autant
# d'approvisionnements, chacun avec son coût historique.
#
# La devise de référence comptable est l'ariary (MGA) : chaque montant saisi
# dans une autre devise est converti avec le taux du jour et conservé avec
# son montant / sa devise / son taux d'origine — jamais recalculé ensuite.
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
    """Approvisionnement / envoi fournisseur : UN produit, UNE quantité,
    plusieurs paiements, UNE expédition, UN montant Frais + Douane, UN coût
    total rendu Madagascar, UN coût de revient par pièce.

    Les montants calculés (`total_paiements_mga`, `cout_total_mga`,
    `cout_unitaire_mga`) sont recalculés par suppliers/services.py à chaque
    paiement / frais / finalisation et figés en base : un approvisionnement
    finalisé garde son coût historique quoi qu'il arrive ensuite (autre
    envoi du même produit, changement de taux…).
    """

    STATUT_CHOICES = (
        ("BROUILLON", "Brouillon"),
        ("COMMANDE", "Commande"),
        ("ACOMPTE_PAYE", "Acompte payé"),
        ("PREPARATION", "Préparation"),
        ("PAYE", "Entièrement payé"),
        ("EXPEDIE", "Expédié"),
        ("EN_TRANSIT", "En transit"),
        ("ARRIVE", "Arrivé à Madagascar"),
        ("COUT_FINALISE", "Coût finalisé"),
    )
    # Ordre logique du workflow (§ 15). Les statuts de paiement
    # (ACOMPTE_PAYE / PAYE) sont dérivés des paiements enregistrés tant que
    # la marchandise n'est pas plus avancée.
    STATUT_ORDER = [s for s, _ in STATUT_CHOICES]

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
        Supplier, on_delete=models.PROTECT, null=True, blank=True, related_name="orders"
    )
    numero = models.CharField(max_length=30, unique=True, editable=False)
    date = models.DateField(default=timezone.localdate)
    description = models.CharField(max_length=255, blank=True, null=True)
    statut = models.CharField(max_length=20, choices=STATUT_CHOICES, default="BROUILLON")

    # LE produit et LA quantité de cet envoi (§ 3). `null` uniquement pour un
    # ancien approvisionnement multi-lignes converti (voir migration 0005).
    product_variant = models.ForeignKey(
        ProductVariant, on_delete=models.PROTECT, null=True, blank=True, related_name="supplier_orders"
    )
    quantite = models.PositiveIntegerField(default=0)

    # Montant total convenu avec le fournisseur, dans sa devise (facultatif) :
    # sert à afficher « prévu / payé / reste » (§ 4). Le coût réel, lui, ne
    # vient que des paiements réellement effectués.
    devise = models.CharField(max_length=3, choices=DEVISE_CHOICES, default="USD")
    montant_prevu = models.DecimalField(max_digits=16, decimal_places=2, default=0)

    # Expédition (§ 7-8-9)
    date_expedition = models.DateField(null=True, blank=True)
    transporteur = models.CharField(max_length=150, blank=True)
    mode_transport = models.CharField(max_length=10, choices=MODE_TRANSPORT_CHOICES, blank=True)
    tracking = models.CharField(max_length=150, blank=True)
    numero_colis = models.CharField(max_length=150, blank=True)
    lieu_depart = models.CharField(max_length=150, blank=True, default="Chine")
    destination = models.CharField(max_length=150, blank=True, default="Madagascar")
    date_arrivee = models.DateField(null=True, blank=True)
    commentaire_transport = models.CharField(max_length=255, blank=True)

    # Frais + Douane : UN seul montant, en MGA (§ 9).
    frais_douane_mga = models.DecimalField(max_digits=16, decimal_places=2, default=0)

    # Calculés (suppliers/services.py::recompute_costs) — en MGA (§ 10-11).
    total_paiements_mga = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)
    cout_total_mga = models.DecimalField(max_digits=16, decimal_places=2, default=0, editable=False)
    cout_unitaire_mga = models.DecimalField(max_digits=14, decimal_places=2, default=0, editable=False)

    # Réception dans le stock (à la finalisation) — § 13.
    quantite_recue = models.PositiveIntegerField(default=0)
    received_at = models.DateTimeField(null=True, blank=True)
    finalise_at = models.DateTimeField(null=True, blank=True)

    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="supplier_orders"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Approvisionnement fournisseur"
        verbose_name_plural = "Approvisionnements fournisseur"
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["magasin", "statut"], name="suppliers_order_mag_stat_idx")]

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

    # --- dérivés ------------------------------------------------------------ #

    @property
    def est_finalise(self):
        return self.statut == "COUT_FINALISE"

    @property
    def total_paye_devise(self):
        """Total payé dans la devise de l'approvisionnement (paiements de
        cette devise seulement ; les autres sont comptés via le MGA)."""
        return sum((p.montant for p in self.payments.all() if p.devise == self.devise), ZERO)

    @property
    def reste_a_payer_devise(self):
        return max(Decimal(self.montant_prevu or 0) - self.total_paye_devise, ZERO)

    @property
    def pourcentage_paye(self):
        prevu = Decimal(self.montant_prevu or 0)
        if not prevu:
            return Decimal("0")
        return min((self.total_paye_devise / prevu * 100).quantize(Decimal("0.1")), Decimal("100"))

    @property
    def prix_vente_unitaire(self):
        return self.product_variant.product_reference.prix_vente if self.product_variant_id else ZERO

    @property
    def marge_unitaire(self):
        """Prix de vente − coût de revient unitaire (§ 20)."""
        return Decimal(self.prix_vente_unitaire) - Decimal(self.cout_unitaire_mga)


class SupplierPayment(models.Model):
    """Un versement au fournisseur (acompte, solde…) — un approvisionnement
    en compte autant que nécessaire, l'historique est conservé. Le montant
    MGA est figé avec le taux du jour du paiement (§ 5-6) : les anciens
    paiements ne sont jamais recalculés avec le taux actuel."""

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
    montant = models.DecimalField(max_digits=16, decimal_places=2)
    devise = models.CharField(max_length=3, choices=DEVISE_CHOICES, default="MGA")
    taux_change = models.DecimalField(max_digits=14, decimal_places=4, default=Decimal("1"))
    montant_mga = models.DecimalField(max_digits=16, decimal_places=2, editable=False, default=0)
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

    def save(self, *args, **kwargs):
        if self.devise == DEVISE_REFERENCE:
            self.taux_change = Decimal("1")
        self.montant_mga = convertir_en_mga(self.montant, self.devise, self.taux_change)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.montant} {self.devise} ({self.supplier_order.numero})"
