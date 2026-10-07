"""`magasin_id` et les sociétés à plusieurs magasins.

Tant qu'un compte n'a qu'un magasin, le serveur le devine (voir
users/permissions.py::resolve_magasin_for_request). Dès le deuxième, deviner
reviendrait à créer la catégorie dans la mauvaise boutique : le serveur exige
alors `magasin_id`. Ces tests figent ce contrat — c'est à l'interface de
proposer le choix, pas au serveur de trancher au hasard.
"""
from django.test import TestCase
from rest_framework.test import APIClient

from users.models import AdminProfile, CustomUser, MagasinProfile

CREATIONS = [
    ("/api/catalog/categories/", {"nom": "HOUSSE"}),
    ("/api/catalog/brands/", {"nom": "Samsung"}),
    ("/api/catalog/colors/", {"nom": "Noir"}),
]


class MagasinRequisTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin"
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.m1 = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique 1")
        self.api.force_authenticate(user=self.admin)

    def test_un_seul_magasin_le_serveur_le_devine(self):
        for chemin, corps in CREATIONS:
            with self.subTest(chemin=chemin):
                r = self.api.post(chemin, corps, format="json")
                self.assertEqual(r.status_code, 201, r.data)

    def test_deux_magasins_magasin_id_devient_obligatoire(self):
        """Sans précision, le serveur refuse plutôt que de choisir pour vous."""
        MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique 2")
        for chemin, corps in CREATIONS:
            with self.subTest(chemin=chemin):
                r = self.api.post(chemin, corps, format="json")
                self.assertEqual(r.status_code, 400, r.data)
                self.assertIn("magasin_id", r.data)

    def test_deux_magasins_avec_magasin_id_tout_passe(self):
        m2 = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique 2")
        for chemin, corps in CREATIONS:
            with self.subTest(chemin=chemin):
                r = self.api.post(chemin, {**corps, "magasin_id": m2.id}, format="json")
                self.assertEqual(r.status_code, 201, r.data)

    def test_un_magasin_d_une_autre_societe_est_refuse(self):
        autre = CustomUser.objects.create_user(
            email="autre@test.mg", password="x", role="admin", full_name="Autre"
        )
        AdminProfile.objects.create(user=autre, company_name="Autre société")
        etranger = MagasinProfile.objects.create(admin=autre, shop_name="Ailleurs")

        r = self.api.post(
            "/api/catalog/categories/", {"nom": "HOUSSE", "magasin_id": etranger.id}, format="json"
        )
        self.assertEqual(r.status_code, 403, r.data)


class FiltreMagasinListesTests(TestCase):
    """`magasin_id` sur les listes : le sélecteur « Magasin » des pages
    Produits, Commandes et Nouvelle commande s'appuie dessus."""

    def setUp(self):
        from decimal import Decimal

        from catalog.models import Brand, ProductCategory, ProductReference, ProductType

        self.api = APIClient()
        admin = CustomUser.objects.create_user(
            email="a@test.mg", password="x", role="admin", full_name="A"
        )
        AdminProfile.objects.create(user=admin, company_name="Société")
        self.m1 = MagasinProfile.objects.create(admin=admin, shop_name="Boutique 1")
        self.m2 = MagasinProfile.objects.create(admin=admin, shop_name="Boutique 2")

        for magasin, nom in ((self.m1, "HOUSSE"), (self.m2, "CHARGEUR")):
            cat = ProductCategory.objects.create(magasin=magasin, nom=nom)
            typ = ProductType.objects.create(category=cat, nom=f"TYPE {nom}")
            marque = Brand.objects.create(magasin=magasin, nom=f"Marque {nom}")
            ProductReference.objects.create(
                type=typ, brand=marque, reference_name=f"Ref {nom}", prix_vente=Decimal("1000")
            )
        self.api.force_authenticate(user=admin)

    def test_sans_filtre_on_voit_les_deux_magasins(self):
        for chemin in ("/api/catalog/categories/", "/api/catalog/types/", "/api/catalog/references/"):
            with self.subTest(chemin=chemin):
                self.assertEqual(len(self.api.get(chemin).data), 2)

    def test_avec_filtre_on_ne_voit_qu_un_magasin(self):
        for chemin in ("/api/catalog/categories/", "/api/catalog/types/", "/api/catalog/references/"):
            with self.subTest(chemin=chemin):
                r = self.api.get(f"{chemin}?magasin_id={self.m2.id}")
                self.assertEqual(len(r.data), 1, r.data)

    def test_l_autocomplete_suit_le_meme_filtre(self):
        tous = self.api.get("/api/catalog/references/autocomplete/?q=Ref").data
        self.assertEqual(len(tous), 2)
        un = self.api.get(f"/api/catalog/references/autocomplete/?q=Ref&magasin_id={self.m1.id}").data
        self.assertEqual(len(un), 1)
        self.assertEqual(un[0]["magasin"], self.m1.id)
