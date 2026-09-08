from django.db import models


class ProductCategory(models.Model):
    """HOUSSE, CACHE ÉCRAN, CHARGEUR… — catégorie personnalisable par magasin
    (§8.2 Smartreadme.md). Porte le scoping multi-tenant : Type/Brand/
    Reference/Variant en héritent via la chaîne de FK, pas de duplication."""

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="product_categories"
    )
    nom = models.CharField(max_length=100)
    ordre = models.PositiveIntegerField(default=0)
    # Certaines catégories (chargeur, écouteur…) n'ont pas de déclinaison
    # couleur : la référence n'a alors qu'une seule variante ("Standard") et
    # le formulaire de création saisit directement une quantité, sans passer
    # par la gestion multi-couleurs (housse, cache écran…).
    avec_couleurs = models.BooleanField(default=True)

    class Meta:
        verbose_name = "Catégorie de produit"
        verbose_name_plural = "Catégories de produit"
        unique_together = ("magasin", "nom")
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
    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="brands"
    )
    nom = models.CharField(max_length=100)

    class Meta:
        verbose_name = "Marque"
        verbose_name_plural = "Marques"
        unique_together = ("magasin", "nom")
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class Color(models.Model):
    """Couleur suggérée dans le sélecteur de variante — liste gérée par
    magasin (menu Paramètres). Ne contraint pas `ProductVariant.couleur`,
    qui reste un simple texte : cette table alimente juste le Select pour
    éviter de retaper/typo une couleur déjà utilisée."""

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="colors"
    )
    nom = models.CharField(max_length=100)

    class Meta:
        verbose_name = "Couleur"
        verbose_name_plural = "Couleurs"
        unique_together = ("magasin", "nom")
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class ProductReference(models.Model):
    """Une référence de téléphone pour une marque donnée (ex: Samsung A15,
    S25 Ultra…). La structure permet d'ajouter librement de nouvelles
    références à une marque existante, sans limite (§8.1 Smartreadme.md)."""

    type = models.ForeignKey(ProductType, on_delete=models.CASCADE, related_name="references")
    brand = models.ForeignKey(Brand, on_delete=models.CASCADE, related_name="references")
    reference_name = models.CharField(max_length=150)
    # Coût d'achat unitaire, saisi librement par le gérant pour visualiser la
    # marge (prix_vente - prix_achat) — distinct du coût calculé par le
    # module Fournisseurs (frais/fret/douane répartis sur une commande).
    prix_achat = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    prix_vente = models.DecimalField(max_digits=12, decimal_places=2)
    photo = models.ImageField(upload_to="products/", blank=True, null=True)
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
    couleur = models.CharField(max_length=100, default="Standard")
    # Référence à l'article d'origine dans Loyverse (source du catalogue de
    # migration, §8.1 Smartreadme.md) — utile pour tracer/rapprocher l'import.
    sku_loyverse = models.CharField(max_length=30, blank=True, null=True)
    stock_actuel = models.IntegerField(default=0)
    seuil_alerte = models.IntegerField(default=1)

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


class StockMovement(models.Model):
    """Historique obligatoire de tout mouvement de stock (§10 Smartreadme.md
    — traçabilité). Seule la préparation d'une commande (sortie), son retour
    ou son annulation (entrée — voir orders/services.py), une entrée
    fournisseur, ou un ajustement manuel du gérant, créent un mouvement —
    jamais un autre événement. Point d'écriture unique :
    catalog/services.py::apply_stock_movement."""

    TYPE_CHOICES = (
        ("ENTREE", "Entrée"),
        ("SORTIE", "Sortie"),
    )
    ORIGINE_CHOICES = (
        ("PREPARATION", "Préparation de commande"),
        ("RETOUR", "Retour de commande"),
        ("ANNULATION", "Annulation de commande"),
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


class ImportBatch(models.Model):
    """Trace les objets créés/modifiés par un import Excel (voir
    ProductReferenceViewSet.import_excel) pour permettre à l'utilisateur
    d'annuler l'import après avoir vu le résumé côté frontend —
    catalog/services.py::revert_import_batch défait exactement chaque entrée
    de `items`, dans l'ordre inverse de leur création."""

    magasin = models.ForeignKey(
        "users.MagasinProfile", on_delete=models.CASCADE, related_name="import_batches"
    )
    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True
    )
    created_at = models.DateTimeField(auto_now_add=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    # Liste de dicts {action, id, label, previous?, movement_id?, reference_id?}
    # dans l'ordre de traitement des lignes du fichier importé.
    items = models.JSONField(default=list)

    class Meta:
        verbose_name = "Import de catalogue"
        verbose_name_plural = "Imports de catalogue"
        ordering = ["-created_at"]

    def __str__(self):
        return f"Import #{self.pk} ({self.created_at:%d/%m/%Y %H:%M})"
