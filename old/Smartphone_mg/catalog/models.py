from django.db import models


class ProductCategory(models.Model):
    """HOUSSE, CACHE ÉCRAN, CHARGEUR… — catégorie personnalisable (§8.2 README)."""

    nom = models.CharField(max_length=100, unique=True)
    ordre = models.PositiveIntegerField(default=0)

    class Meta:
        verbose_name = "Catégorie de produit"
        verbose_name_plural = "Catégories de produit"
        ordering = ["ordre", "nom"]

    def __str__(self):
        return self.nom


class ProductType(models.Model):
    """Sous-type : FLIP COVER, Z-FOLD, Z-FLIP, PRIVACY…"""

    category = models.ForeignKey(ProductCategory, on_delete=models.CASCADE, related_name="types")
    nom = models.CharField(max_length=100)

    class Meta:
        verbose_name = "Sous-type de produit"
        verbose_name_plural = "Sous-types de produit"
        unique_together = ("category", "nom")
        ordering = ["category", "nom"]

    def __str__(self):
        return f"{self.category.nom} / {self.nom}"


class Brand(models.Model):
    nom = models.CharField(max_length=100, unique=True)

    class Meta:
        verbose_name = "Marque"
        verbose_name_plural = "Marques"
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class ProductReference(models.Model):
    """Une référence de téléphone pour une marque donnée (ex: Samsung A15,
    S25 Ultra…). La structure permet d'ajouter librement de nouvelles
    références à une marque existante, sans limite (§8.1 README)."""

    type = models.ForeignKey(ProductType, on_delete=models.CASCADE, related_name="references")
    brand = models.ForeignKey(Brand, on_delete=models.CASCADE, related_name="references")
    reference_name = models.CharField(max_length=150)
    prix_vente = models.DecimalField(max_digits=12, decimal_places=2)
    actif = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Référence produit"
        verbose_name_plural = "Références produit"
        unique_together = ("type", "brand", "reference_name")
        ordering = ["brand", "reference_name"]

    def __str__(self):
        return f"{self.brand.nom} {self.reference_name} ({self.type.nom})"


class ProductVariant(models.Model):
    """Déclinaison couleur d'une référence — c'est le niveau où le stock est
    réellement suivi."""

    product_reference = models.ForeignKey(
        ProductReference, on_delete=models.CASCADE, related_name="variants"
    )
    couleur = models.CharField(max_length=100)
    # Référence à l'article d'origine dans Loyverse (source actuelle du
    # catalogue, §8.1 README) — utile pour tracer/rapprocher la migration.
    sku_loyverse = models.CharField(max_length=30, blank=True, null=True)
    stock_actuel = models.IntegerField(default=0)
    seuil_alerte = models.IntegerField(default=0)

    class Meta:
        verbose_name = "Variante de produit"
        verbose_name_plural = "Variantes de produit"
        unique_together = ("product_reference", "couleur")
        ordering = ["product_reference", "couleur"]

    @property
    def is_rupture(self):
        return self.stock_actuel <= 0

    @property
    def is_stock_bas(self):
        return 0 < self.stock_actuel <= self.seuil_alerte

    def __str__(self):
        return f"{self.product_reference} - {self.couleur} ({self.stock_actuel})"
