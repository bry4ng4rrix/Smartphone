from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from stock.models import StockMovement
from users.models import CustomUser

from . import services
from .models import Order


class OrderWorkflowTestCase(TestCase):
    """Couvre la règle critique du §5 README : seul "Livré" déduit le
    stock ; "Retour" (échec de livraison, jamais livré) ne le touche pas."""

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

        self.gerant = CustomUser.objects.create_user(email="g@test.mg", password="x", role="GERANT")
        self.preparateur = CustomUser.objects.create_user(email="p@test.mg", password="x", role="PREPARATEUR")
        self.livreur = CustomUser.objects.create_user(email="l@test.mg", password="x", role="LIVREUR")

    def _create_order(self, quantite=2):
        return services.create_order(
            client_nom="Client Test",
            telephone="+261340000000",
            livraison_zone="ZONE1",
            items=[{"product_variant": self.variant, "quantite": quantite}],
            created_by=self.gerant,
        )

    def _advance_to(self, order, *statuts_users):
        for statut, user in statuts_users:
            order = services.change_order_status(order=order, new_status=statut, user=user)
        return order

    def test_livre_deduit_le_stock_et_cree_un_mouvement(self):
        order = self._create_order(quantite=2)
        order = self._advance_to(
            order,
            ("EN_PREPARATION", self.preparateur),
            ("PRETE", self.preparateur),
            ("EN_LIVRAISON", self.livreur),
            ("LIVRE", self.livreur),
        )

        self.variant.refresh_from_db()
        self.assertEqual(self.variant.stock_actuel, 8)

        movement = StockMovement.objects.get(product_variant=self.variant)
        self.assertEqual(movement.type, "SORTIE")
        self.assertEqual(movement.origine, "LIVRE")
        self.assertEqual(movement.quantite, 2)

    def test_retour_depuis_en_livraison_ne_touche_pas_le_stock(self):
        order = self._create_order(quantite=3)
        self._advance_to(
            order,
            ("EN_PREPARATION", self.preparateur),
            ("PRETE", self.preparateur),
            ("EN_LIVRAISON", self.livreur),
            ("RETOUR", self.livreur),
        )

        self.variant.refresh_from_db()
        self.assertEqual(self.variant.stock_actuel, 10)  # inchangé
        self.assertFalse(StockMovement.objects.filter(product_variant=self.variant).exists())

    def test_impossible_de_sauter_un_statut(self):
        order = self._create_order()
        with self.assertRaises(Exception):
            services.change_order_status(order=order, new_status="PRETE", user=self.preparateur)

    def test_livreur_ne_peut_pas_agir_sur_statut_preparateur(self):
        order = self._create_order()
        with self.assertRaises(Exception):
            services.change_order_status(order=order, new_status="EN_PREPARATION", user=self.livreur)


class OrderFinancialVisibilityTestCase(TestCase):
    """§4, §7.2, §12 README : le préparateur ne doit voir aucune donnée
    financière sur une commande."""

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
        self.gerant = CustomUser.objects.create_user(email="g@test.mg", password="x", role="GERANT")
        self.preparateur = CustomUser.objects.create_user(email="p@test.mg", password="x", role="PREPARATEUR")

        services.create_order(
            client_nom="Client Test",
            telephone="+261340000000",
            livraison_zone="ZONE1",
            items=[{"product_variant": self.variant, "quantite": 1}],
            created_by=self.gerant,
        )

    def test_preparateur_ne_voit_aucun_champ_financier(self):
        client = APIClient()
        client.force_authenticate(self.preparateur)
        response = client.get("/api/orders/")
        self.assertEqual(response.status_code, 200)

        payload = str(response.json())
        for champ_interdit in ["prix_unitaire", "total_a_payer", "frais_livraison"]:
            self.assertNotIn(champ_interdit, payload)
