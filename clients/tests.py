"""Boutique en ligne : commander sans compte, et rien d'autre."""
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import DeliveryZoneOption, Order
from users.models import AdminProfile, CustomUser, MagasinProfile


class BoutiqueEnLigneTests(TestCase):
    def setUp(self):
        # DRF garde l'historique de débit dans le cache, partagé par toute la
        # suite : sans ce nettoyage, le 11e appel d'affilée part en 429 et
        # fait échouer un test qui n'a rien à voir avec la limitation.
        cache.clear()
        self.api = APIClient()
        admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin"
        )
        self.admin_profile = AdminProfile.objects.create(user=admin, company_name="Société")
        self.magasin = MagasinProfile.objects.create(admin=admin, shop_name="Boutique")

        categorie = ProductCategory.objects.create(magasin=self.magasin, nom="HOUSSE")
        sous_type = ProductType.objects.create(category=categorie, nom="FLIP COVER")
        marque = Brand.objects.create(magasin=self.magasin, nom="Samsung")
        self.reference = ProductReference.objects.create(
            type=sous_type, brand=marque, reference_name="Galaxy A15", prix_vente=Decimal("30000")
        )
        self.variante = ProductVariant.objects.create(
            product_reference=self.reference, couleur="Noir", stock_actuel=5
        )

    def corps(self, **extra):
        donnees = {
            "boutique": self.magasin.id,
            "items": [{"variante": self.variante.id, "quantite": 2}],
            "livraison_zone": "EN_LIGNE",
            "client_nom": "Rakoto Jean",
            "telephone": "+261340000000",
            "adresse_livraison": "Lot II A 15 Antananarivo",
        }
        donnees.update(extra)
        return donnees

    @staticmethod
    def accuse(reponse, index=0):
        """L'accusé d'une commande dans la réponse.

        `POST /api/commandes/` renvoie une LISTE : le panier est éclaté en une
        commande par magasin propriétaire des articles. Un panier d'une seule
        boutique — le cas de ces tests — donne une liste d'un élément.
        """
        return reponse.data["commandes"][index]

    # ------------------------------------------------------------------ #
    # Commander sans compte
    # ------------------------------------------------------------------ #

    def test_commande_sans_aucune_authentification(self):
        r = self.api.post("/api/commandes/", self.corps(), format="json")
        self.assertEqual(r.status_code, 201, r.data)

        order = Order.objects.get(numero=self.accuse(r)["numero"])
        self.assertTrue(order.origine_en_ligne)
        self.assertEqual(order.client_nom, "Rakoto Jean")
        self.assertEqual(order.telephone, "+261340000000")

    def test_la_commande_attend_l_appel_du_gerant(self):
        """Elle n'entre pas dans le circuit avant que le gérant n'approuve."""
        r = self.api.post("/api/commandes/", self.corps(), format="json")
        self.assertEqual(self.accuse(r)["statut"], "EN_ATTENTE_APPROBATION")

    def test_aucun_stock_reserve_avant_approbation(self):
        self.api.post("/api/commandes/", self.corps(), format="json")
        self.variante.refresh_from_db()
        self.assertEqual(self.variante.stock_actuel, 5)

    # ------------------------------------------------------------------ #
    # Frais de livraison : fixés par le serveur
    # ------------------------------------------------------------------ #

    def test_livraison_facturee_3000_ar(self):
        r = self.api.post("/api/commandes/", self.corps(), format="json")
        self.assertEqual(self.accuse(r)["frais_livraison"], 3000)
        # 2 × 30 000 + 3 000
        self.assertEqual(self.accuse(r)["total_a_payer"], 63000)

    def test_retrait_sur_place_gratuit_et_sans_adresse(self):
        r = self.api.post(
            "/api/commandes/",
            self.corps(livraison_zone="RECUPERATION", adresse_livraison=""),
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(self.accuse(r)["frais_livraison"], 0)
        self.assertEqual(self.accuse(r)["total_a_payer"], 60000)

    def test_un_montant_envoye_par_le_client_est_ignore(self):
        """Le navigateur n'est jamais la source de vérité d'un montant."""
        r = self.api.post(
            "/api/commandes/",
            self.corps(frais_livraison=0, total_a_payer=1),
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(self.accuse(r)["frais_livraison"], 3000)
        self.assertEqual(self.accuse(r)["total_a_payer"], 63000)

    def test_les_deux_modes_de_remise_sont_annonces(self):
        r = self.api.get(f"/api/boutiques/{self.magasin.id}/zones/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["recuperation"]["prix"], 0)
        self.assertEqual(len(r.data["zones"]), 1)
        self.assertEqual(r.data["zones"][0]["prix"], 3000)

    def test_le_gerant_garde_la_main_sur_le_tarif(self):
        """Changer le prix de la zone change ce que paie le client."""
        self.api.get(f"/api/boutiques/{self.magasin.id}/zones/")  # crée la zone
        DeliveryZoneOption.objects.filter(
            admin_profile=self.admin_profile, code="EN_LIGNE"
        ).update(prix=Decimal("5000"))

        r = self.api.post("/api/commandes/", self.corps(), format="json")
        self.assertEqual(self.accuse(r)["frais_livraison"], 5000)

    # ------------------------------------------------------------------ #
    # Validation des coordonnées
    # ------------------------------------------------------------------ #

    def test_nom_obligatoire(self):
        r = self.api.post("/api/commandes/", self.corps(client_nom="  "), format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("client_nom", r.data)

    def test_telephone_au_format_malgache(self):
        r = self.api.post("/api/commandes/", self.corps(telephone="0340000000"), format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("telephone", r.data)

    def test_second_numero_facultatif(self):
        r = self.api.post("/api/commandes/", self.corps(telephone_2=""), format="json")
        self.assertEqual(r.status_code, 201, r.data)

    def test_adresse_exigee_pour_une_livraison(self):
        r = self.api.post("/api/commandes/", self.corps(adresse_livraison=""), format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("adresse_livraison", r.data)

    def test_stock_insuffisant_refuse(self):
        r = self.api.post(
            "/api/commandes/",
            self.corps(items=[{"variante": self.variante.id, "quantite": 99}]),
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("items", r.data)

    def test_prix_change_entre_temps(self):
        r = self.api.post(
            "/api/commandes/",
            self.corps(items=[{"variante": self.variante.id, "quantite": 1, "prix_attendu": "25000"}]),
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("items", r.data)

    # ------------------------------------------------------------------ #
    # Ce que le site n'expose plus
    # ------------------------------------------------------------------ #

    def test_plus_aucune_route_de_compte(self):
        for chemin in (
            "/api/client/register/",
            "/api/client/login/",
            "/api/client/me/",
            "/api/client/orders/",
            "/api/client/change-password/",
        ):
            with self.subTest(chemin=chemin):
                self.assertEqual(self.api.get(chemin).status_code, 404)
                self.assertEqual(self.api.post(chemin, {}, format="json").status_code, 404)

    def test_la_commande_ne_se_relit_pas(self):
        """Sans compte, rien n'authentifierait celui qui la demande."""
        r = self.api.post("/api/commandes/", self.corps(), format="json")
        self.assertEqual(self.api.get(f"/api/commandes/{self.accuse(r)['id']}/").status_code, 404)

    def test_le_catalogue_reste_lisible_sans_jeton(self):
        self.assertEqual(self.api.get("/api/produit/").status_code, 200)
        self.assertEqual(self.api.get("/api/categories/").status_code, 200)
