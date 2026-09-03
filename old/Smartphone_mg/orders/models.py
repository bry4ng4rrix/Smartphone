from django.db import models
from django.utils import timezone

from catalog.models import ProductVariant


class Order(models.Model):
    """Commande client (§6, §11 README). Le workflow des 6 statuts et son
    impact sur le stock sont gérés exclusivement par orders/services.py —
    jamais directement ici ni dans les vues."""

    STATUT_CHOICES = (
        ("NOUVELLE", "Nouvelle"),
        ("EN_PREPARATION", "En préparation"),
        ("PRETE", "Prête"),
        ("EN_LIVRAISON", "En livraison"),
        ("LIVRE", "Livré"),
        ("RETOUR", "Retour"),
    )

    ZONE_CHOICES = (
        ("ZONE1", "Zone 1"),
        ("ZONE2", "Zone 2"),
        ("ZONE3", "Zone 3"),
        ("RECUPERATION", "Récupération"),
    )

    FRAIS_PAR_ZONE = {
        "ZONE1": 3000,
        "ZONE2": 4000,
        "ZONE3": 5000,
        "RECUPERATION": 0,
    }

    # Ordre strict des statuts : une transition ne peut sauter d'étape,
    # sauf via l'override gérant (non activé pour le MVP — voir §5 README).
    STATUT_ORDER = ["NOUVELLE", "EN_PREPARATION", "PRETE", "EN_LIVRAISON", "LIVRE"]

    numero = models.CharField(max_length=30, unique=True, editable=False)
    date_commande = models.DateField(default=timezone.localdate)
    client_nom = models.CharField(max_length=255)
    telephone = models.CharField(max_length=20)
    livraison_zone = models.CharField(max_length=20, choices=ZONE_CHOICES)
    frais_livraison = models.DecimalField(max_digits=10, decimal_places=2, editable=False, default=0)
    total_a_payer = models.DecimalField(max_digits=12, decimal_places=2, editable=False, default=0)
    note = models.TextField(blank=True, null=True)
    statut_courant = models.CharField(max_length=20, choices=STATUT_CHOICES, default="NOUVELLE")

    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="orders_created"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Commande"
        verbose_name_plural = "Commandes"
        ordering = ["-created_at"]

    def generate_numero(self):
        today = timezone.localdate()
        prefix = f"CMD-{today:%Y%m%d}-"
        last = (
            Order.objects.filter(numero__startswith=prefix).order_by("-numero").first()
        )
        seq = int(last.numero[-4:]) + 1 if last else 1
        return f"{prefix}{seq:04d}"

    def save(self, *args, **kwargs):
        if not self.numero:
            self.numero = self.generate_numero()
        self.frais_livraison = self.FRAIS_PAR_ZONE.get(self.livraison_zone, 0)
        super().save(*args, **kwargs)

    def recompute_total(self):
        items_total = sum((item.prix_unitaire * item.quantite for item in self.items.all()), start=0)
        self.total_a_payer = items_total + self.frais_livraison
        self.save(update_fields=["total_a_payer"])

    def __str__(self):
        return self.numero


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="items")
    product_variant = models.ForeignKey(ProductVariant, on_delete=models.PROTECT, related_name="order_items")
    # Snapshot du prix au moment de la commande — l'historique reste correct
    # même si le prix catalogue change ensuite (§11 README).
    prix_unitaire = models.DecimalField(max_digits=12, decimal_places=2, editable=False)
    quantite = models.PositiveIntegerField(default=1)

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
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Historique statut commande"
        verbose_name_plural = "Historiques statut commande"
        ordering = ["timestamp"]

    def __str__(self):
        return f"{self.order.numero}: {self.ancien_statut} -> {self.nouveau_statut}"
