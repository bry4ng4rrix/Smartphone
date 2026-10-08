"""Coordonnées d'un magasin : adresse, numéro, numéro 2.

Elles existent pour une seule raison : dire au client venant RETIRER sa
commande où aller et qui appeler. Les tests suivent ce chemin de bout en
bout — saisie par l'admin, lecture par le personnel, affichage au client.

Règle portée par l'API : l'adresse et le premier numéro sont obligatoires dès
qu'on y touche, le second est facultatif.
"""
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order, OrderItem
from users.models import AdminProfile, CustomUser, EmployerProfile, MagasinProfile

MDP = "motdepasse-admin"

ADRESSE = "Lot II M 12 bis Analakely, face à la pharmacie"
TEL = "+261340000001"
TEL2 = "+261320000002"


class CoordonneesMagasinAPITests(TestCase):
    """Saisie et validation côté gestion."""

    def setUp(self):
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password=MDP, role="admin",
            full_name="Admin", is_confirmed=True,
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Magasin A")
        self.api.force_authenticate(user=self.admin)

    def test_un_magasin_existant_demarre_sans_coordonnees(self):
        """La migration ne doit rien exiger des magasins déjà en base."""
        self.assertEqual(self.magasin.adresse, "")
        self.assertEqual(self.magasin.telephone, "")
        self.assertEqual(self.magasin.telephone_2, "")

    def test_l_admin_renseigne_les_trois_champs(self):
        r = self.api.patch(f"/api/users/magasins/{self.magasin.id}/", {
            "adresse": ADRESSE, "telephone": TEL, "telephone_2": TEL2,
        }, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        self.magasin.refresh_from_db()
        self.assertEqual(self.magasin.adresse, ADRESSE)
        self.assertEqual(self.magasin.telephone, TEL)
        self.assertEqual(self.magasin.telephone_2, TEL2)

    def test_le_second_numero_reste_facultatif(self):
        r = self.api.patch(f"/api/users/magasins/{self.magasin.id}/", {
            "adresse": ADRESSE, "telephone": TEL, "telephone_2": "",
        }, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.magasin.refresh_from_db()
        self.assertEqual(self.magasin.telephone_2, "")

    def test_une_adresse_vide_est_refusee(self):
        self.magasin.adresse = ADRESSE
        self.magasin.save()

        r = self.api.patch(f"/api/users/magasins/{self.magasin.id}/",
                           {"adresse": "   "}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("adresse", r.data)

        self.magasin.refresh_from_db()
        self.assertEqual(self.magasin.adresse, ADRESSE, "le refus ne doit rien effacer")

    def test_un_numero_vide_est_refuse(self):
        self.magasin.telephone = TEL
        self.magasin.save()

        r = self.api.patch(f"/api/users/magasins/{self.magasin.id}/",
                           {"telephone": ""}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("telephone", r.data)

        self.magasin.refresh_from_db()
        self.assertEqual(self.magasin.telephone, TEL)

    def test_les_champs_absents_ne_sont_pas_effaces(self):
        """Renommer un magasin (ou n'envoyer que le logo) ne doit pas perdre
        ses coordonnées : seul un champ PRÉSENT dans la requête est touché."""
        self.magasin.adresse, self.magasin.telephone, self.magasin.telephone_2 = ADRESSE, TEL, TEL2
        self.magasin.save()

        r = self.api.patch(f"/api/users/magasins/{self.magasin.id}/",
                           {"shop_name": "Magasin renommé"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        self.magasin.refresh_from_db()
        self.assertEqual(self.magasin.shop_name, "Magasin renommé")
        self.assertEqual(self.magasin.adresse, ADRESSE)
        self.assertEqual(self.magasin.telephone, TEL)
        self.assertEqual(self.magasin.telephone_2, TEL2)

    def test_creation_d_un_magasin_sans_gerant_avec_ses_coordonnees(self):
        r = self.api.post("/api/users/magasins/", {
            "shop_name": "Magasin C", "adresse": ADRESSE, "telephone": TEL,
        }, format="json")
        self.assertEqual(r.status_code, 201, r.data)

        cree = MagasinProfile.objects.get(shop_name="Magasin C")
        self.assertEqual(cree.adresse, ADRESSE)
        self.assertEqual(cree.telephone, TEL)

    def test_creation_du_magasin_avec_son_gerant(self):
        """Voie « magasin + compte gérant » : les coordonnées du MAGASIN sont
        préfixées `shop_` pour ne pas se confondre avec `phone`, qui est le
        numéro de la personne."""
        r = self.api.post("/api/users/register/", {
            "email": "nouveau@test.mg", "username": "nouveau@test.mg",
            "password": "motdepasse-long", "role": "magasin",
            "full_name": "Nouveau Gérant", "phone": "+261339999999",
            "shop_name": "Magasin D", "admin_email": self.admin.email,
            "shop_adresse": ADRESSE, "shop_telephone": TEL, "shop_telephone_2": TEL2,
        }, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        cree = MagasinProfile.objects.get(shop_name="Magasin D")
        self.assertEqual(cree.adresse, ADRESSE)
        self.assertEqual(cree.telephone, TEL)
        self.assertEqual(cree.telephone_2, TEL2)
        self.assertEqual(cree.user.phone, "+261339999999",
                         "le numéro de la personne reste distinct de celui du magasin")

    def test_le_gerant_renseigne_les_coordonnees_de_sa_boutique(self):
        """Il connaît son adresse mieux que l'admin — mais seulement la sienne."""
        gerant = CustomUser.objects.create_user(
            email="gerant@test.mg", password="x", role="magasin",
            full_name="Gérant", is_confirmed=True,
        )
        self.magasin.user = gerant
        self.magasin.save()
        autre = MagasinProfile.objects.create(admin=self.admin, shop_name="Magasin B")

        self.api.force_authenticate(user=gerant)
        r = self.api.patch(f"/api/users/magasins/{self.magasin.id}/",
                           {"adresse": ADRESSE, "telephone": TEL}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        r = self.api.patch(f"/api/users/magasins/{autre.id}/",
                           {"adresse": "Chez le voisin"}, format="json")
        self.assertEqual(r.status_code, 404, "un gérant ne touche pas une autre boutique")
        autre.refresh_from_db()
        self.assertEqual(autre.adresse, "")

    def test_la_liste_du_personnel_expose_les_coordonnees(self):
        """`/magasins/users/` alimente les cartes de la page Magasins."""
        self.magasin.adresse, self.magasin.telephone, self.magasin.telephone_2 = ADRESSE, TEL, TEL2
        self.magasin.save()

        r = self.api.get("/api/users/magasins/users/")
        self.assertEqual(r.status_code, 200, r.data)
        carte = next(m for m in r.data if m["magasin_id"] == self.magasin.id)
        self.assertEqual(carte["adresse"], ADRESSE)
        self.assertEqual(carte["telephone"], TEL)
        self.assertEqual(carte["telephone_2"], TEL2)


class CoordonneesRecuperationTests(TestCase):
    """Ce que le personnel et le client voient sur une commande à retirer."""

    def setUp(self):
        cache.clear()  # les débits DRF fuiraient d'un test à l'autre (429)
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password=MDP, role="admin",
            full_name="Admin", is_confirmed=True,
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.magasin = MagasinProfile.objects.create(
            admin=self.admin, shop_name="Magasin A",
            adresse=ADRESSE, telephone=TEL, telephone_2=TEL2,
        )

        cat = ProductCategory.objects.create(magasin=self.magasin, nom="HOUSSE", visible_client=True)
        typ = ProductType.objects.create(category=cat, nom="FLIP", visible_client=True)
        marque = Brand.objects.create(magasin=self.magasin, nom="Samsung")
        ref = ProductReference.objects.create(
            type=typ, brand=marque, reference_name="A15", prix_vente=Decimal("30000"),
        )
        self.variante = ProductVariant.objects.create(
            product_reference=ref, couleur="Noir", stock_actuel=5,
        )
        self.commande = Order.objects.create(
            magasin=self.magasin, client_nom="Rasoa", telephone="+261341111111",
            livraison_zone="RECUPERATION",
        )
        OrderItem.objects.create(
            order=self.commande, product_variant=self.variante,
            quantite=1, prix_unitaire=Decimal("30000"),
        )

    def _coordonnees(self, bloc):
        return (bloc["magasin_nom"], bloc["magasin_adresse"],
                bloc["magasin_telephone"], bloc["magasin_telephone_2"])

    def test_le_gerant_voit_le_point_de_retrait_sur_la_commande(self):
        self.api.force_authenticate(user=self.admin)
        r = self.api.get("/api/orders/", {"livraison_zone": "RECUPERATION"})
        self.assertEqual(r.status_code, 200, r.data)
        ligne = next(o for o in r.data if o["id"] == self.commande.id)
        self.assertEqual(self._coordonnees(ligne), ("Magasin A", ADRESSE, TEL, TEL2))

    def test_le_preparateur_aussi(self):
        """Il annonce le retrait au comptoir — sans voir pour autant de coût."""
        prep = CustomUser.objects.create_user(
            email="prep@test.mg", password="x", role="employer",
            full_name="Préparateur", is_confirmed=True,
        )
        EmployerProfile.objects.create(
            user=prep, admin=self.admin, magasin=self.magasin,
            position="Préparateur", commande_role="PREPARATEUR",
        )
        # Un préparateur ne voit que ce qui lui est confié ; une récupération
        # déjà prête reste dans son périmètre jusqu'au retrait (il n'y a pas
        # de livreur pour ce cas).
        self.commande.preparateur = prep
        self.commande.statut_courant = "PRETE"
        self.commande.save(update_fields=["preparateur", "statut_courant"])

        self.api.force_authenticate(user=prep)
        r = self.api.get(f"/api/orders/{self.commande.id}/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(self._coordonnees(r.data), ("Magasin A", ADRESSE, TEL, TEL2))
        self.assertNotIn("prix_achat", str(r.data))

    def test_la_boutique_publique_publie_ses_coordonnees(self):
        r = self.api.get("/api/boutiques/")
        self.assertEqual(r.status_code, 200, r.data)
        boutique = next(b for b in r.data if b["id"] == self.magasin.id)
        self.assertEqual(boutique["adresse"], ADRESSE)
        self.assertEqual(boutique["telephone"], TEL)
        self.assertEqual(boutique["telephone_2"], TEL2)

    def test_le_mode_retrait_porte_l_endroit_ou_venir(self):
        """Le client doit lire l'adresse AVANT de valider, pas seulement après."""
        r = self.api.get(f"/api/boutiques/{self.magasin.id}/zones/")
        self.assertEqual(r.status_code, 200, r.data)
        retrait = r.data["recuperation"]
        self.assertEqual(retrait["boutique"], "Magasin A")
        self.assertEqual(retrait["adresse"], ADRESSE)
        self.assertEqual(retrait["telephone"], TEL)
        self.assertEqual(retrait["telephone_2"], TEL2)
        self.assertEqual(retrait["prix"], 0, "le retrait reste gratuit")

    def test_l_accuse_de_commande_rappelle_ou_retirer(self):
        """Seule trace que le client emporte : il n'existe pas de page de suivi."""
        r = self.api.post("/api/commandes/", {
            "boutique": self.magasin.id,
            "items": [{"variante": self.variante.id, "quantite": 1}],
            "livraison_zone": "RECUPERATION",
            "client_nom": "Rasoa",
            "telephone": "+261341111111",
        }, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        boutique = r.data["boutique"]
        self.assertEqual(boutique["nom"], "Magasin A")
        self.assertEqual(boutique["adresse"], ADRESSE)
        self.assertEqual(boutique["telephone"], TEL)
        self.assertEqual(boutique["telephone_2"], TEL2)

    def test_une_boutique_sans_coordonnees_renvoie_des_chaines_vides(self):
        """Pas de `null` ni de KeyError : le front teste « vide » et n'affiche
        alors rien plutôt qu'un cadre à trous."""
        nue = MagasinProfile.objects.create(admin=self.admin, shop_name="Magasin nu")
        r = self.api.get(f"/api/boutiques/{nue.id}/zones/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["recuperation"]["adresse"], "")
        self.assertEqual(r.data["recuperation"]["telephone"], "")
        self.assertEqual(r.data["recuperation"]["telephone_2"], "")
