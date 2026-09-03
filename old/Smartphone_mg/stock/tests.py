from django.test import TestCase

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant

from .models import StockMovement
from .services import apply_stock_movement


class StockServiceTestCase(TestCase):
    def setUp(self):
        category = ProductCategory.objects.create(nom="HOUSSE")
        product_type = ProductType.objects.create(category=category, nom="FLIP COVER")
        brand = Brand.objects.create(nom="Samsung")
        reference = ProductReference.objects.create(
            type=product_type, brand=brand, reference_name="A15", prix_vente=15000
        )
        self.variant = ProductVariant.objects.create(
            product_reference=reference, couleur="Noir", stock_actuel=10, seuil_alerte=3
        )

    def test_sortie_decremente_et_trace(self):
        apply_stock_movement(self.variant, "SORTIE", 4, "AJUSTEMENT")
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.stock_actuel, 6)
        self.assertEqual(StockMovement.objects.count(), 1)

    def test_entree_incremente_et_trace(self):
        apply_stock_movement(self.variant, "ENTREE", 5, "FOURNISSEUR")
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.stock_actuel, 15)
        self.assertEqual(StockMovement.objects.count(), 1)
