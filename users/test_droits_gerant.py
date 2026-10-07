"""Modèle d'autorisation ADMIN GLOBAL vs GÉRANT DE MAGASIN (mission § 33-34).

Deux magasins, deux gérants, un admin. On vérifie trois choses :

1. le gérant garde ce dont il a besoin pour tenir sa boutique ;
2. il ne peut atteindre AUCUN module qui lui est fermé, en tapant l'API
   directement — sans passer par Next.js ni Flutter ;
3. aucune donnée de coût, de marge ou de bénéfice ne figure dans ce qu'il
   reçoit, y compris dans les champs imbriqués.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order, OrderItem
from users.models import AdminProfile, CustomUser, MagasinProfile

#: Tout ce qu'un gérant ne doit jamais recevoir, à quelque profondeur que ce soit.
CHAMPS_INTERDITS = {
    "prix_achat", "cout_achat", "cout_revient", "cout_total_mga", "cout_unitaire_mga",
    "marge", "marge_unitaire", "marge_pourcentage", "marge_produits",
    "benefice", "benefice_estime", "benefice_estime_stock", "benefice_produits_vendus",
    "gain_reel", "profit_today", "total_profit", "epargne", "part_boost",
}


def champs_sensibles(donnees, chemin=""):
    """Parcourt récursivement une réponse API et renvoie les chemins des
    champs interdits rencontrés — y compris imbriqués (mission § 34)."""
    trouves = []
    if isinstance(donnees, dict):
        for cle, valeur in donnees.items():
            ici = f"{chemin}.{cle}" if chemin else cle
            if cle in CHAMPS_INTERDITS:
                trouves.append(ici)
            trouves.extend(champs_sensibles(valeur, ici))
    elif isinstance(donnees, list):
        for i, element in enumerate(donnees):
            trouves.extend(champs_sensibles(element, f"{chemin}[{i}]"))
    return trouves


class DroitsGerantTests(TestCase):
    def setUp(self):
        self.api = APIClient()

        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin",
            full_name="Admin", is_confirmed=True,
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")

        self.magasinA = MagasinProfile.objects.create(admin=self.admin, shop_name="Magasin A")
        self.magasinB = MagasinProfile.objects.create(admin=self.admin, shop_name="Magasin B")

        self.gerantA = CustomUser.objects.create_user(
            email="gerantA@test.mg", password="x", role="magasin",
            full_name="Gérant A", is_confirmed=True,
        )
        self.magasinA.user = self.gerantA
        self.magasinA.save()

        self.gerantB = CustomUser.objects.create_user(
            email="gerantB@test.mg", password="x", role="magasin",
            full_name="Gérant B", is_confirmed=True,
        )
        self.magasinB.user = self.gerantB
        self.magasinB.save()

        self.refA, self.varA = self._catalogue(self.magasinA, "Galaxy A15")
        self.refB, self.varB = self._catalogue(self.magasinB, "Redmi Note 13")
        self.commandeA = self._commande(self.magasinA, self.varA, "Client A")
        self.commandeB = self._commande(self.magasinB, self.varB, "Client B")

    def _catalogue(self, magasin, modele):
        cat = ProductCategory.objects.create(magasin=magasin, nom="HOUSSE")
        typ = ProductType.objects.create(category=cat, nom="FLIP")
        marque = Brand.objects.create(magasin=magasin, nom="Samsung")
        ref = ProductReference.objects.create(
            type=typ, brand=marque, reference_name=modele,
            prix_achat=Decimal("12000"), prix_vente=Decimal("30000"),
        )
        var = ProductVariant.objects.create(product_reference=ref, couleur="Noir", stock_actuel=10)
        return ref, var

    def _commande(self, magasin, variante, nom):
        order = Order.objects.create(
            magasin=magasin, client_nom=nom, telephone="+261340000000",
            livraison_zone="RECUPERATION", statut_courant="NOUVELLE",
        )
        OrderItem.objects.create(order=order, product_variant=variante, quantite=1)
        order.recompute_total()
        return order

    def gerant(self, user=None):
        self.api.force_authenticate(user=user or self.gerantA)
        return self.api

    # ------------------------------------------------------------------ #
    # 1. Ce que le gérant garde
    # ------------------------------------------------------------------ #

    def test_le_gerant_garde_son_perimetre_de_travail(self):
        api = self.gerant()
        for nom, url in [
            ("dashboard magasin", "/api/orders/dashboard-gerant/"),
            ("produits", "/api/catalog/references/"),
            ("commandes", "/api/orders/"),
            ("catégories", "/api/catalog/categories/"),
            ("mouvements de stock", "/api/catalog/movements/"),
            ("dépenses livreur", "/api/orders/expenses/"),
            ("avances livreur", "/api/orders/avances/"),
            ("commandes à examiner", "/api/orders/a-examiner/"),
            ("notifications", "/api/users/notifications/"),
        ]:
            with self.subTest(module=nom):
                self.assertLess(api.get(url).status_code, 400, f"{nom} doit rester accessible")

    def test_le_gerant_garde_le_crud_produit(self):
        """Mission § 7 : CRUD produits = OUI, mais sans le coût."""
        api = self.gerant()
        r = api.post("/api/catalog/references/", {
            "type": self.refA.type_id, "brand": self.refA.brand_id,
            "reference_name": "Galaxy A25", "prix_vente": "35000",
        }, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertNotIn("prix_achat", r.data)

        cree = r.data["id"]
        self.assertEqual(
            api.patch(f"/api/catalog/references/{cree}/", {"prix_vente": "36000"}, format="json").status_code,
            200,
        )
        self.assertEqual(api.delete(f"/api/catalog/references/{cree}/").status_code, 204)

    def test_le_gerant_ne_peut_pas_renseigner_un_prix_achat(self):
        """Champ absent du serializer : il n'est pas non plus accepté en entrée."""
        api = self.gerant()
        r = api.post("/api/catalog/references/", {
            "type": self.refA.type_id, "brand": self.refA.brand_id,
            "reference_name": "Galaxy A35", "prix_vente": "40000", "prix_achat": "1",
        }, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        cree = ProductReference.objects.get(id=r.data["id"])
        self.assertEqual(cree.prix_achat, Decimal("0"), "le prix d'achat envoyé doit être ignoré")

    # ------------------------------------------------------------------ #
    # 2. Modules fermés — testés directement sur l'API
    # ------------------------------------------------------------------ #

    def test_modules_interdits_au_gerant(self):
        api = self.gerant()
        for nom, url in [
            ("trésorerie", "/api/finance/dashboard/"),
            ("ventes avec gain", "/api/finance/ventes/"),
            ("épargne", "/api/finance/epargne/"),
            ("journal financier", "/api/finance/journal/"),
            ("encaissements", "/api/finance/encaissements/"),
            ("caisse sessions", "/api/users/caisse/sessions/"),
            ("caisse résumé", "/api/users/caisse/summary/"),
            ("caisse mouvements", "/api/users/caisse/movements/"),
            ("fournisseurs", "/api/suppliers/orders/"),
            ("fiches fournisseur", "/api/suppliers/suppliers/"),
            ("historique des coûts", "/api/suppliers/cost-history/"),
            ("campagnes marketing", "/api/orders/campaigns/"),
            ("dashboard admin", "/api/orders/dashboard/"),
            ("rapports chiffrés", "/api/orders/reports/"),
            ("rapport financier", "/api/orders/reports/financial/"),
            ("rapport marketing", "/api/orders/reports/marketing/"),
            ("rapport stock", "/api/orders/reports/stock/"),
        ]:
            with self.subTest(module=nom):
                self.assertEqual(api.get(url).status_code, 403, f"{nom} doit être refusé")

    def test_le_gerant_ne_transfere_pas_entre_magasins(self):
        r = self.gerant().post("/api/users/transfer/products/", {
            "source_magasin_id": self.magasinA.id,
            "destination_magasin_id": self.magasinB.id,
            "variant_ids": [self.varA.id],
        }, format="json")
        self.assertEqual(r.status_code, 403)

    def test_le_gerant_ne_modifie_pas_les_reglages_de_societe(self):
        """Zones de livraison et types de dépense sont partagés par tous les
        magasins : les toucher changerait les règles des autres boutiques."""
        api = self.gerant()
        self.assertEqual(
            api.post("/api/orders/delivery-zones/", {"nom": "Zone X", "prix": "9999"}, format="json").status_code,
            403,
        )
        self.assertEqual(
            api.post("/api/orders/expense-types/", {"nom": "Type X", "prix_unitaire": "1"}, format="json").status_code,
            403,
        )

    # ------------------------------------------------------------------ #
    # 3. Cloisonnement entre magasins
    # ------------------------------------------------------------------ #

    def test_le_gerant_A_ne_voit_pas_le_magasin_B(self):
        api = self.gerant()
        self.assertEqual(
            [p["reference_name"] for p in api.get("/api/catalog/references/").data],
            ["Galaxy A15"],
        )
        numeros = [o["numero"] for o in api.get("/api/orders/").data]
        self.assertEqual(numeros, [self.commandeA.numero])

    def test_forcer_magasin_id_ne_donne_rien(self):
        api = self.gerant()
        self.assertEqual(len(api.get(f"/api/catalog/references/?magasin_id={self.magasinB.id}").data), 0)
        self.assertEqual(len(api.get(f"/api/orders/?magasin_id={self.magasinB.id}").data), 0)
        self.assertEqual(
            len(api.get(f"/api/orders/dashboard-gerant/?magasin_id={self.magasinB.id}").data["magasins"]), 0
        )

    def test_acceder_a_un_objet_du_magasin_B_par_son_id(self):
        """L'attaque la plus simple : deviner un identifiant."""
        api = self.gerant()
        self.assertEqual(api.get(f"/api/orders/{self.commandeB.id}/").status_code, 404)
        self.assertEqual(api.get(f"/api/catalog/references/{self.refB.id}/").status_code, 404)
        self.assertEqual(api.patch(f"/api/orders/{self.commandeB.id}/", {"note_preparateur": "x"}, format="json").status_code, 404)
        self.assertEqual(api.delete(f"/api/catalog/references/{self.refB.id}/").status_code, 404)

    def test_le_badge_ne_compte_que_son_magasin(self):
        """Mission § 10 : jamais les commandes d'un autre magasin."""
        Order.objects.filter(id=self.commandeB.id).update(statut_courant="EN_ATTENTE_APPROBATION")
        Order.objects.filter(id=self.commandeA.id).update(statut_courant="EN_ATTENTE_APPROBATION")
        self.assertEqual(self.gerant().get("/api/orders/a-examiner/").data["count"], 1)
        self.assertEqual(self.gerant(self.gerantB).get("/api/orders/a-examiner/").data["count"], 1)

    # ------------------------------------------------------------------ #
    # 4. Non-divulgation, champs imbriqués compris
    # ------------------------------------------------------------------ #

    def test_aucune_donnee_de_cout_dans_ce_que_recoit_le_gerant(self):
        api = self.gerant()
        for nom, url in [
            ("dashboard magasin", "/api/orders/dashboard-gerant/"),
            ("produits", "/api/catalog/references/"),
            ("fiche produit", f"/api/catalog/references/{self.refA.id}/"),
            ("commandes", "/api/orders/"),
            ("fiche commande", f"/api/orders/{self.commandeA.id}/"),
            ("dashboard utilisateur", "/api/users/dashboard/"),
            ("mouvements", "/api/catalog/movements/"),
            ("variantes", "/api/catalog/variants/"),
        ]:
            with self.subTest(reponse=nom):
                r = api.get(url)
                self.assertLess(r.status_code, 400, f"{nom} : {r.status_code}")
                fuites = champs_sensibles(r.data)
                self.assertEqual(fuites, [], f"{nom} laisse fuiter {fuites}")

    def test_le_gerant_voit_bien_les_montants_de_vente(self):
        """Mission § 35 : il lui faut le prix de vente et le total à payer."""
        r = self.gerant().get(f"/api/orders/{self.commandeA.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertIn("total_a_payer", r.data)
        self.assertIn("prix_unitaire", r.data["items"][0])

        produits = self.gerant().get("/api/catalog/references/").data
        self.assertIn("prix_vente", produits[0])

    # ------------------------------------------------------------------ #
    # 5. L'admin, lui, garde tout
    # ------------------------------------------------------------------ #

    def test_l_admin_conserve_tous_les_modules(self):
        self.api.force_authenticate(user=self.admin)
        for nom, url in [
            ("trésorerie", "/api/finance/dashboard/"),
            ("fournisseurs", "/api/suppliers/orders/"),
            ("caisse", "/api/users/caisse/sessions/"),
            ("campagnes", "/api/orders/campaigns/"),
            ("dashboard global", "/api/orders/dashboard/"),
            ("rapports", "/api/orders/reports/"),
        ]:
            with self.subTest(module=nom):
                self.assertLess(self.api.get(url).status_code, 400, f"{nom} doit rester ouvert à l'admin")

    def test_l_admin_voit_le_prix_achat_et_les_deux_magasins(self):
        self.api.force_authenticate(user=self.admin)
        produits = self.api.get("/api/catalog/references/").data
        self.assertEqual(len(produits), 2, "l'admin voit les deux magasins")
        self.assertIn("prix_achat", produits[0])
