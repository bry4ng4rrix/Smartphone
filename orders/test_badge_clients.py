"""Badge « Clients » du menu : le compteur des commandes à examiner."""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order
from users.models import AdminProfile, CustomUser, MagasinProfile


class BadgeCommandesAExaminerTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin"
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique")

        categorie = ProductCategory.objects.create(magasin=self.magasin, nom="HOUSSE")
        sous_type = ProductType.objects.create(category=categorie, nom="FLIP")
        marque = Brand.objects.create(magasin=self.magasin, nom="Samsung")
        self.reference = ProductReference.objects.create(
            type=sous_type, brand=marque, reference_name="A15", prix_vente=Decimal("30000")
        )
        self.variante = ProductVariant.objects.create(
            product_reference=self.reference, couleur="Noir", stock_actuel=10
        )

    def commander(self, n=1):
        for _ in range(n):
            self.api.post(
                "/api/commandes/",
                {
                    "boutique": self.magasin.id,
                    "items": [{"variante": self.variante.id, "quantite": 1}],
                    "livraison_zone": "RECUPERATION",
                    "client_nom": "Rakoto",
                    "telephone": "+261340000000",
                },
                format="json",
            )

    def compter(self):
        self.api.force_authenticate(user=self.admin)
        r = self.api.get("/api/orders/a-examiner/")
        self.assertEqual(r.status_code, 200, r.data)
        return r.data["count"]

    def test_zero_quand_rien_a_examiner(self):
        self.assertEqual(self.compter(), 0)

    def test_compte_les_commandes_en_attente(self):
        self.commander(3)
        self.assertEqual(self.compter(), 3)

    def test_le_compteur_retombe_apres_approbation(self):
        self.commander(2)
        order = Order.objects.filter(statut_courant="EN_ATTENTE_APPROBATION").first()
        self.api.force_authenticate(user=self.admin)
        r = self.api.post(f"/api/orders/{order.id}/approuver/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(self.compter(), 1)

    def test_le_chiffre_colle_a_la_page_clients(self):
        """Badge et liste doivent montrer le même nombre, toujours."""
        self.commander(4)
        self.api.force_authenticate(user=self.admin)
        liste = self.api.get("/api/orders/?statut=EN_ATTENTE_APPROBATION").data
        self.assertEqual(self.compter(), len(liste))

    def test_une_autre_societe_ne_voit_pas_ces_commandes(self):
        """Le compteur est borné aux magasins accessibles."""
        autre = CustomUser.objects.create_user(
            email="autre@test.mg", password="x", role="admin", full_name="Autre"
        )
        AdminProfile.objects.create(user=autre, company_name="Autre société")
        MagasinProfile.objects.create(admin=autre, shop_name="Autre boutique")

        self.commander(2)
        self.api.force_authenticate(user=autre)
        r = self.api.get("/api/orders/a-examiner/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["count"], 0)

    def test_endpoint_refuse_sans_authentification(self):
        self.api.force_authenticate(user=None)
        self.assertIn(self.api.get("/api/orders/a-examiner/").status_code, (401, 403))
