from django.db import models
from django.utils import timezone

from catalog.models import ProductVariant


class SupplierOrder(models.Model):
    """Commande fournisseur (§7.6 Smartreadme.md) — permet de calculer le
    coût de revient réel : marchandise + fret/import + douane + pub Meta Ads."""

    STATUT_CHOICES = (
        ("BROUILLON", "Brouillon"),
        ("COMMANDE", "Commandé"),
        ("RECU", "Reçu"),
    )

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="supplier_orders"
    )
    numero = models.CharField(max_length=30, unique=True, editable=False)
    date = models.DateField(default=timezone.localdate)
    description = models.CharField(max_length=255, blank=True, null=True)
    statut = models.CharField(max_length=20, choices=STATUT_CHOICES, default="BROUILLON")

    prix_fournisseur = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    fret_import = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    douane = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    meta_ads = models.DecimalField(max_digits=14, decimal_places=2, default=0)

    # Calculés automatiquement (§7.6) via suppliers/services.py::recompute_costs.
    total_qty = models.PositiveIntegerField(default=0, editable=False)
    cout_total = models.DecimalField(max_digits=14, decimal_places=2, default=0, editable=False)
    cout_unitaire = models.DecimalField(max_digits=14, decimal_places=2, default=0, editable=False)

    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="supplier_orders"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    received_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "Commande fournisseur"
        verbose_name_plural = "Commandes fournisseur"
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


class SupplierOrderLine(models.Model):
    supplier_order = models.ForeignKey(SupplierOrder, on_delete=models.CASCADE, related_name="lines")
    product_variant = models.ForeignKey(ProductVariant, on_delete=models.PROTECT, related_name="supplier_order_lines")
    quantite = models.PositiveIntegerField()

    # Snapshot rempli par SupplierOrder.recompute_costs() (§7.6 : coût
    # unitaire calculé au niveau de la commande, réparti sur chaque ligne).
    cout_unitaire_calcule = models.DecimalField(max_digits=14, decimal_places=2, default=0, editable=False)
    total_ligne = models.DecimalField(max_digits=14, decimal_places=2, default=0, editable=False)

    class Meta:
        verbose_name = "Ligne de commande fournisseur"
        verbose_name_plural = "Lignes de commande fournisseur"

    @property
    def marge_unitaire(self):
        prix_vente = self.product_variant.product_reference.prix_vente
        return prix_vente - self.cout_unitaire_calcule

    def __str__(self):
        return f"{self.product_variant} x{self.quantite} ({self.supplier_order.numero})"
