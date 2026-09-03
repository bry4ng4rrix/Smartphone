from django.db import models

from catalog.models import ProductVariant


class StockMovement(models.Model):
    """Historique obligatoire de tout mouvement de stock (§10 README —
    traçabilité). Seul le statut Livré d'une commande (le Retour ne touche
    pas le stock — voir orders/services.py), une entrée fournisseur, ou un
    ajustement manuel du gérant, créent un mouvement — jamais un autre
    événement."""

    TYPE_CHOICES = (
        ("ENTREE", "Entrée"),
        ("SORTIE", "Sortie"),
    )
    ORIGINE_CHOICES = (
        ("LIVRE", "Commande livrée"),
        ("FOURNISSEUR", "Réception fournisseur"),
        ("AJUSTEMENT", "Ajustement manuel"),
    )

    product_variant = models.ForeignKey(ProductVariant, on_delete=models.CASCADE, related_name="movements")
    type = models.CharField(max_length=10, choices=TYPE_CHOICES)
    quantite = models.PositiveIntegerField()
    origine = models.CharField(max_length=20, choices=ORIGINE_CHOICES)

    # Référence libre vers l'objet source (numéro de commande, de commande
    # fournisseur...) — évite un couplage dur entre apps.
    reference = models.CharField(max_length=100, blank=True, null=True)
    note = models.CharField(max_length=255, blank=True, null=True)

    user = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="stock_movements"
    )
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Mouvement de stock"
        verbose_name_plural = "Mouvements de stock"
        ordering = ["-timestamp"]

    def __str__(self):
        return f"{self.get_type_display()} {self.quantite} - {self.product_variant} ({self.origine})"
