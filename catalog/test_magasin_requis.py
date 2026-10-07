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
