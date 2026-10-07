"""L'autocomplétion expose le magasin de chaque article.

C'est lui qui détermine le magasin de la commande créée depuis le formulaire
« Nouvelle commande » : sans cette information, le front ne peut pas envoyer
`magasin_id`, obligatoire dès qu'une société a plusieurs boutiques.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from users.models import AdminProfile, CustomUser, MagasinProfile


class AutocompleteMagasinTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin"
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.m1 = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique 1")
        self.m2 = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique 2")

        self.ref1 = self.creer_reference(self.m1, "A17")
        self.ref2 = self.creer_reference(self.m2, "A17")
        self.api.force_authenticate(user=self.admin)

    def creer_reference(self, magasin, nom):
        # get_or_create : la catégorie, le sous-type et la marque sont uniques
        # par magasin — plusieurs références les partagent.
        categorie, _ = ProductCategory.objects.get_or_create(magasin=magasin, nom="HOUSSE")
        sous_type, _ = ProductType.objects.get_or_create(category=categorie, nom="PRIVACY")
        marque, _ = Brand.objects.get_or_create(magasin=magasin, nom="Samsung")
        ref = ProductReference.objects.create(
            type=sous_type, brand=marque, reference_name=nom, prix_vente=Decimal("40000")
        )
        ProductVariant.objects.create(product_reference=ref, couleur="Standard", stock_actuel=5)
        return ref

    def test_chaque_suggestion_porte_son_magasin(self):
        r = self.api.get("/api/catalog/references/autocomplete/?q=A17")
        self.assertEqual(r.status_code, 200, r.data)
        par_id = {s["id"]: s for s in r.data}

        self.assertEqual(par_id[self.ref1.id]["magasin"], self.m1.id)
        self.assertEqual(par_id[self.ref1.id]["magasin_nom"], "Boutique 1")
        self.assertEqual(par_id[self.ref2.id]["magasin"], self.m2.id)
        self.assertEqual(par_id[self.ref2.id]["magasin_nom"], "Boutique 2")

    def test_une_commande_sur_le_second_magasin_passe(self):
        """Le scénario exact signalé : commander sur le nouveau magasin."""
        variante = self.ref2.variants.first()
        r = self.api.post(
            "/api/orders/",
            {
                "magasin_id": self.ref2.type.category.magasin_id,
                "client_nom": "Seheno",
                "telephone": "+261341253639",
                "livraison_zone": "RECUPERATION",
                "items": [{"product_variant": variante.id, "quantite": 1}],
            },
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(r.data["magasin"], self.m2.id)

    def test_sans_magasin_id_le_serveur_refuse_toujours(self):
        """Contrat inchangé : c'est au front de préciser, pas au serveur de deviner."""
        variante = self.ref2.variants.first()
        r = self.api.post(
            "/api/orders/",
            {
                "client_nom": "Seheno",
                "telephone": "+261341253639",
                "livraison_zone": "RECUPERATION",
                "items": [{"product_variant": variante.id, "quantite": 1}],
            },
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("magasin_id", r.data)

    def test_pas_de_requete_par_suggestion(self):
        """select_related : le nom du magasin ne doit pas coûter une requête par ligne."""
        for i in range(8):
            self.creer_reference(self.m1, f"Modele {i}")
        with self.assertNumQueries(2):  # la liste + le prefetch des variantes
            self.api.get("/api/catalog/references/autocomplete/?q=")
