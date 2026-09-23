"""Vérifie que `visible_client` gouverne réellement la vitrine publique."""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from users.models import CustomUser, MagasinProfile


class VisibiliteVitrineTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        admin = CustomUser.objects.create_user(
            email="gerant@test.mg", password="x", role="MAGASIN", full_name="Gérant"
        )
        self.magasin = MagasinProfile.objects.create(admin=admin, shop_name="Boutique")

        self.marque = Brand.objects.create(magasin=self.magasin, nom="Samsung")

        def reference(nom_cat, nom_type, nom_ref):
            cat = ProductCategory.objects.create(magasin=self.magasin, nom=nom_cat)
            typ = ProductType.objects.create(category=cat, nom=nom_type)
            ref = ProductReference.objects.create(
                type=typ, brand=self.marque, reference_name=nom_ref, prix_vente=Decimal("30000")
            )
            ProductVariant.objects.create(product_reference=ref, couleur="Noir", stock_actuel=5)
            return cat, typ, ref

        self.cat_housse, self.type_housse, self.ref_housse = reference("HOUSSE", "FLIP COVER", "Galaxy A15")
        self.cat_sante, self.type_sante, self.ref_sante = reference("SANTE", "DIVERS", "Kit")

    def noms_categories(self):
        return {c["nom"] for c in self.api.get("/api/categories/").json()}

    def noms_produits(self):
        return {p["nom"] for p in self.api.get("/api/produit/").json()["results"]}

    def test_tout_visible_par_defaut(self):
        """Le champ vaut True par défaut : rien ne disparaît à la migration."""
        self.assertEqual(self.noms_categories(), {"HOUSSE", "SANTE"})
        self.assertEqual(self.noms_produits(), {"Galaxy A15", "Kit"})

    def test_categorie_masquee_disparait_de_la_vitrine(self):
        self.cat_sante.visible_client = False
        self.cat_sante.save()

        self.assertEqual(self.noms_categories(), {"HOUSSE"})
        self.assertEqual(self.noms_produits(), {"Galaxy A15"})
        self.assertEqual(
            {s["nom"] for s in self.api.get("/api/sous-type/").json()}, {"FLIP COVER"}
        )

    def test_sous_type_masque_sans_toucher_a_la_categorie(self):
        self.type_housse.visible_client = False
        self.type_housse.save()

        # La catégorie reste affichée, seul son sous-type sort de la vitrine.
        self.assertEqual(self.noms_categories(), {"HOUSSE", "SANTE"})
        self.assertEqual(self.noms_produits(), {"Kit"})

    def test_detail_produit_masque_renvoie_404(self):
        """La fiche ne doit pas rester accessible par URL directe."""
        self.cat_housse.visible_client = False
        self.cat_housse.save()
        self.assertEqual(self.api.get(f"/api/produit/{self.ref_housse.id}/").status_code, 404)

    def test_gerant_bascule_le_drapeau_par_l_api(self):
        """Le serializer d'administration accepte bien le champ en écriture."""
        from catalog.serializers import ProductCategorySerializer

        ser = ProductCategorySerializer(self.cat_sante, data={"visible_client": False}, partial=True)
        self.assertTrue(ser.is_valid(), ser.errors)
        ser.save()
        self.cat_sante.refresh_from_db()
        self.assertFalse(self.cat_sante.visible_client)
        self.assertEqual(self.noms_categories(), {"HOUSSE"})
