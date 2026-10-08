"""Qui accepte ou refuse une commande venue de la boutique en ligne.

Réponse : l'administrateur global **et** le gérant de magasin. C'est le gérant
qui rappelle le client au numéro laissé sur le site ; lui retirer ce geste
l'obligerait à passer par l'admin pour chaque commande.

Chaque gérant reste cantonné à sa boutique : un panier éclaté en deux
commandes est approuvé par deux gérants, chacun pour sa part.
"""
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order
from users.models import AdminProfile, CustomUser, EmployerProfile, MagasinProfile


def catalogue_de(magasin, nom="A15", prix="30000"):
    categorie = ProductCategory.objects.create(magasin=magasin, nom="HOUSSE", visible_client=True)
    sous_type = ProductType.objects.create(category=categorie, nom="FLIP", visible_client=True)
    marque = Brand.objects.create(magasin=magasin, nom="Samsung")
    ref = ProductReference.objects.create(
        type=sous_type, brand=marque, reference_name=nom, prix_vente=Decimal(prix),
    )
    return ProductVariant.objects.create(product_reference=ref, couleur="Noir", stock_actuel=10)


class ApprobationParLeGerantTests(TestCase):
    def setUp(self):
        cache.clear()
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin", is_confirmed=True,
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.magasinA = MagasinProfile.objects.create(admin=self.admin, shop_name="Analakely")
        self.magasinB = MagasinProfile.objects.create(admin=self.admin, shop_name="Behoririka")

        self.gerantA = CustomUser.objects.create_user(
            email="gerantA@test.mg", password="x", role="magasin", full_name="Gérant A", is_confirmed=True,
        )
        self.magasinA.user = self.gerantA
        self.magasinA.save()
        self.gerantB = CustomUser.objects.create_user(
            email="gerantB@test.mg", password="x", role="magasin", full_name="Gérant B", is_confirmed=True,
        )
        self.magasinB.user = self.gerantB
        self.magasinB.save()

        self.varianteA = catalogue_de(self.magasinA)
        self.varianteB = catalogue_de(self.magasinB, nom="A25", prix="40000")

    def commander(self, variantes):
        r = self.api.post("/api/commandes/", {
            "items": [{"variante": v.id, "quantite": 1} for v in variantes],
            "livraison_zone": "RECUPERATION",
            "client_nom": "Rakoto",
            "telephone": "+261340000000",
        }, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        return r.data["commandes"]

    # ------------------------------------------------------------------ #
    # Le gérant approuve et refuse
    # ------------------------------------------------------------------ #

    def test_le_gerant_approuve_une_commande_de_sa_boutique(self):
        commande = self.commander([self.varianteA])[0]

        self.api.force_authenticate(user=self.gerantA)
        r = self.api.post(f"/api/orders/{commande['id']}/approuver/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        order = Order.objects.get(pk=commande["id"])
        self.assertEqual(order.statut_courant, "NOUVELLE")
        # L'approbation réserve le stock, comme une saisie interne.
        self.varianteA.refresh_from_db()
        self.assertEqual(self.varianteA.stock_actuel, 9)

    def test_le_gerant_refuse_une_commande_de_sa_boutique(self):
        commande = self.commander([self.varianteA])[0]

        self.api.force_authenticate(user=self.gerantA)
        r = self.api.post(f"/api/orders/{commande['id']}/refuser/",
                          {"note": "Client injoignable"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        order = Order.objects.get(pk=commande["id"])
        self.assertEqual(order.statut_courant, "ANNULEE")
        # Un refus ne touche pas au stock : rien n'avait été réservé.
        self.varianteA.refresh_from_db()
        self.assertEqual(self.varianteA.stock_actuel, 10)

    def test_le_gerant_voit_le_compteur_de_sa_boutique(self):
        self.commander([self.varianteA, self.varianteB])

        self.api.force_authenticate(user=self.gerantA)
        r = self.api.get("/api/orders/a-examiner/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["count"], 1, "seulement la commande de SA boutique")

    def test_l_admin_voit_les_deux(self):
        self.commander([self.varianteA, self.varianteB])

        self.api.force_authenticate(user=self.admin)
        r = self.api.get("/api/orders/a-examiner/")
        self.assertEqual(r.data["count"], 2)

    # ------------------------------------------------------------------ #
    # Chacun chez soi
    # ------------------------------------------------------------------ #

    def test_un_gerant_ne_touche_pas_la_commande_de_l_autre_boutique(self):
        """Un panier éclaté donne deux commandes : chaque gérant n'a la main
        que sur la sienne."""
        a, b = self.commander([self.varianteA, self.varianteB])

        self.api.force_authenticate(user=self.gerantA)
        r = self.api.post(f"/api/orders/{b['id']}/approuver/", {}, format="json")
        self.assertEqual(r.status_code, 404)
        self.assertEqual(Order.objects.get(pk=b["id"]).statut_courant, "EN_ATTENTE_APPROBATION")

        # Et son homologue approuve bien la sienne.
        self.api.force_authenticate(user=self.gerantB)
        r = self.api.post(f"/api/orders/{b['id']}/approuver/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(Order.objects.get(pk=b["id"]).statut_courant, "NOUVELLE")
        self.assertEqual(Order.objects.get(pk=a["id"]).statut_courant, "EN_ATTENTE_APPROBATION")

    def test_un_preparateur_n_approuve_pas(self):
        commande = self.commander([self.varianteA])[0]
        prep = CustomUser.objects.create_user(
            email="prep@test.mg", password="x", role="employer",
            full_name="Préparateur", is_confirmed=True,
        )
        EmployerProfile.objects.create(
            user=prep, admin=self.admin, magasin=self.magasinA,
            position="Préparateur", commande_role="PREPARATEUR",
        )

        self.api.force_authenticate(user=prep)
        r = self.api.post(f"/api/orders/{commande['id']}/approuver/", {}, format="json")
        self.assertEqual(r.status_code, 403)
        self.assertEqual(
            Order.objects.get(pk=commande["id"]).statut_courant, "EN_ATTENTE_APPROBATION"
        )

    def test_sans_authentification_rien_ne_passe(self):
        commande = self.commander([self.varianteA])[0]
        self.api.force_authenticate(user=None)
        self.assertEqual(
            self.api.post(f"/api/orders/{commande['id']}/approuver/", {}, format="json").status_code,
            401,
        )
