"""Gestion des magasins et des comptes par l'admin global.

Couvre les demandes : supprimer un magasin (avec garde-fous), créer un magasin
sans gérant puis l'affecter, modifier toutes les informations d'un magasin,
transférer un employé d'un magasin à l'autre, et éditer n'importe quel compte.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order, OrderItem
from users.models import AdminProfile, CustomUser, EmployerProfile, MagasinProfile

MDP = "motdepasse-admin"


class GestionMagasinsTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password=MDP, role="admin",
            full_name="Admin", is_confirmed=True,
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.magasinA = MagasinProfile.objects.create(admin=self.admin, shop_name="Magasin A")
        self.magasinB = MagasinProfile.objects.create(admin=self.admin, shop_name="Magasin B")

        # Un gérant appartient à la société par la boutique qu'il tient :
        # c'est ainsi que RegisterSerializer le crée. Sans cela il
        # n'appartiendrait à aucune société et serait introuvable.
        self.gerant = CustomUser.objects.create_user(
            email="gerant@test.mg", password="x", role="magasin",
            full_name="Gérant", is_confirmed=True,
        )
        self.magasinB.user = self.gerant
        self.magasinB.save()
        self.employe = CustomUser.objects.create_user(
            email="prep@test.mg", password="x", role="employer",
            full_name="Préparateur", is_confirmed=True,
        )
        self.profil = EmployerProfile.objects.create(
            user=self.employe, admin=self.admin, magasin=self.magasinA,
            position="Préparateur", commande_role="PREPARATEUR",
        )
        self.api.force_authenticate(user=self.admin)

    def _remplir(self, magasin):
        """Donne un peu d'historique à un magasin."""
        cat = ProductCategory.objects.create(magasin=magasin, nom="HOUSSE")
        typ = ProductType.objects.create(category=cat, nom="FLIP")
        marque = Brand.objects.create(magasin=magasin, nom="Samsung")
        ref = ProductReference.objects.create(
            type=typ, brand=marque, reference_name="A15", prix_vente=Decimal("30000")
        )
        var = ProductVariant.objects.create(product_reference=ref, couleur="Noir", stock_actuel=5)
        order = Order.objects.create(
            magasin=magasin, client_nom="Client", telephone="+261340000000",
            livraison_zone="RECUPERATION", statut_courant="NOUVELLE",
        )
        OrderItem.objects.create(order=order, product_variant=var, quantite=1)
        return order

    # ------------------------------------------------------------------ #
    # Créer un magasin sans gérant, l'affecter ensuite
    # ------------------------------------------------------------------ #

    def test_creer_un_magasin_sans_gerant(self):
        r = self.api.post("/api/users/magasins/", {"shop_name": "Magasin C"}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        cree = MagasinProfile.objects.get(id=r.data["id"])
        self.assertIsNone(cree.user, "le magasin doit pouvoir naître sans gérant")
        self.assertEqual(cree.admin, self.admin)

    def test_affecter_puis_detacher_le_gerant(self):
        url = f"/api/users/magasins/{self.magasinA.id}/"

        r = self.api.patch(url, {"manager_id": self.gerant.id}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.magasinA.refresh_from_db()
        self.assertEqual(self.magasinA.user, self.gerant)

        # Détacher : le magasin repasse sans gérant.
        r = self.api.patch(url, {"manager_id": None}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.magasinA.refresh_from_db()
        self.assertIsNone(self.magasinA.user)

    def test_on_ne_s_approprie_pas_le_gerant_d_une_autre_societe(self):
        """Cloisonnement : `manager_id` est cherché dans la société, pas dans
        toute la base — sinon un admin s'attribuait le gérant du voisin en
        devinant son identifiant."""
        autre = CustomUser.objects.create_user(
            email="autre-admin@test.mg", password="x", role="admin", full_name="Autre"
        )
        AdminProfile.objects.create(user=autre, company_name="Autre société")
        etranger = CustomUser.objects.create_user(
            email="etranger@test.mg", password="x", role="magasin", full_name="Étranger"
        )

        r = self.api.patch(f"/api/users/magasins/{self.magasinA.id}/",
                           {"manager_id": etranger.id}, format="json")
        self.assertEqual(r.status_code, 404, r.data)
        self.magasinA.refresh_from_db()
        self.assertIsNone(self.magasinA.user)

    def test_affecter_un_gerant_deja_en_poste_le_deplace(self):
        """Un compte ne tient qu'une boutique : l'affecter ailleurs le DÉPLACE,
        au lieu de refuser. Refuser obligerait à le détacher d'abord, et un
        gérant détaché n'appartient plus à aucune société — il deviendrait
        introuvable, donc impossible à réaffecter."""
        self.assertEqual(self.magasinB.user, self.gerant)

        r = self.api.patch(f"/api/users/magasins/{self.magasinA.id}/",
                           {"manager_id": self.gerant.id}, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        self.magasinA.refresh_from_db()
        self.magasinB.refresh_from_db()
        self.assertEqual(self.magasinA.user, self.gerant)
        self.assertIsNone(self.magasinB.user, "l'ancienne boutique est libérée")

    # ------------------------------------------------------------------ #
    # Modifier toutes les informations d'un magasin
    # ------------------------------------------------------------------ #

    def test_modifier_nom_et_description(self):
        r = self.api.patch(f"/api/users/magasins/{self.magasinA.id}/", {
            "shop_name": "Magasin A — Analakely",
            "description": "Boutique du centre-ville",
        }, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.magasinA.refresh_from_db()
        self.assertEqual(self.magasinA.shop_name, "Magasin A — Analakely")
        self.assertEqual(self.magasinA.description, "Boutique du centre-ville")

    def test_nom_vide_refuse(self):
        r = self.api.patch(f"/api/users/magasins/{self.magasinA.id}/",
                           {"shop_name": "   "}, format="json")
        self.assertEqual(r.status_code, 400)

    # ------------------------------------------------------------------ #
    # Supprimer un magasin — trois barrières
    # ------------------------------------------------------------------ #

    def test_inventaire_avant_suppression(self):
        """L'interface doit pouvoir annoncer le coût AVANT de demander."""
        self._remplir(self.magasinA)
        r = self.api.get(f"/api/users/magasins/{self.magasinA.id}/contenu/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["contenu"]["commandes"], 1)
        self.assertEqual(r.data["contenu"]["categories"], 1)
        self.assertEqual(r.data["contenu"]["references"], 1)
        self.assertEqual(r.data["contenu"]["employes"], 1)
        self.assertTrue(r.data["contient_des_donnees"])

    def test_suppression_exige_le_nom_exact(self):
        r = self.api.delete(f"/api/users/magasins/{self.magasinA.id}/",
                            {"confirmation_nom": "Magasin", "password": MDP}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("confirmation_nom", r.data)
        self.assertTrue(MagasinProfile.objects.filter(id=self.magasinA.id).exists())

    def test_suppression_exige_le_mot_de_passe(self):
        r = self.api.delete(f"/api/users/magasins/{self.magasinA.id}/",
                            {"confirmation_nom": "Magasin A"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertTrue(MagasinProfile.objects.filter(id=self.magasinA.id).exists())

    def test_mot_de_passe_incorrect_refuse(self):
        r = self.api.delete(f"/api/users/magasins/{self.magasinA.id}/",
                            {"confirmation_nom": "Magasin A", "password": "faux"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertTrue(MagasinProfile.objects.filter(id=self.magasinA.id).exists())

    def test_un_magasin_qui_a_vendu_ne_se_supprime_pas(self):
        """`OrderItem.product_variant` est en PROTECT : l'historique de ventes
        est protégé par la base elle-même. On vérifie que c'est annoncé
        proprement, et pas découvert par une erreur serveur."""
        order = self._remplir(self.magasinA)

        contenu = self.api.get(f"/api/users/magasins/{self.magasinA.id}/contenu/").data
        self.assertFalse(contenu["suppression_possible"])
        self.assertIn("commandes", contenu["raison_blocage"])

        r = self.api.delete(f"/api/users/magasins/{self.magasinA.id}/",
                            {"confirmation_nom": "Magasin A", "password": MDP}, format="json")
        self.assertEqual(r.status_code, 409, getattr(r, "data", None))
        self.assertIn("historique", r.data["error"])

        # Rien n'a bougé.
        self.assertTrue(MagasinProfile.objects.filter(id=self.magasinA.id).exists())
        self.assertTrue(Order.objects.filter(id=order.id).exists())

    def test_suppression_d_un_magasin_sans_vente(self):
        """Le cas qui marche : une boutique créée par erreur, jamais utilisée."""
        cat = ProductCategory.objects.create(magasin=self.magasinA, nom="HOUSSE")
        contenu = self.api.get(f"/api/users/magasins/{self.magasinA.id}/contenu/").data
        self.assertTrue(contenu["suppression_possible"])

        r = self.api.delete(f"/api/users/magasins/{self.magasinA.id}/",
                            {"confirmation_nom": "Magasin A", "password": MDP}, format="json")
        self.assertEqual(r.status_code, 204, getattr(r, "data", None))

        self.assertFalse(MagasinProfile.objects.filter(id=self.magasinA.id).exists())
        self.assertFalse(ProductCategory.objects.filter(id=cat.id).exists())
        # Le COMPTE de l'employé survit, seul son profil d'affectation part.
        self.assertTrue(CustomUser.objects.filter(id=self.employe.id).exists())
        self.assertFalse(EmployerProfile.objects.filter(id=self.profil.id).exists())
        # L'autre magasin est intact.
        self.assertTrue(MagasinProfile.objects.filter(id=self.magasinB.id).exists())

    def test_un_gerant_ne_supprime_pas_son_propre_magasin(self):
        """Avant, `destroy` ne vérifiait que le mot de passe : un gérant
        pouvait effacer sa propre boutique."""
        self.api.force_authenticate(user=self.gerant)
        r = self.api.delete(f"/api/users/magasins/{self.magasinB.id}/",
                            {"confirmation_nom": "Magasin B", "password": "x"}, format="json")
        self.assertEqual(r.status_code, 403)
        self.assertTrue(MagasinProfile.objects.filter(id=self.magasinB.id).exists())

    def test_supprimer_le_compte_du_gerant_ne_detruit_pas_le_magasin(self):
        """Garde-fou contre une perte de données totale.

        `MagasinProfile.user` était en CASCADE : supprimer le compte d'un
        gérant depuis la page des comptes effaçait le magasin, et avec lui le
        catalogue, le stock et les commandes. Le magasin doit survivre, sans
        gérant.
        """
        # `self.gerant` tient déjà magasinB (voir setUp).
        cat = ProductCategory.objects.create(magasin=self.magasinB, nom="HOUSSE")

        self.gerant.delete()

        self.magasinB.refresh_from_db()
        self.assertIsNone(self.magasinB.user, "le magasin repasse sans gérant")
        self.assertTrue(MagasinProfile.objects.filter(id=self.magasinB.id).exists())
        self.assertTrue(ProductCategory.objects.filter(id=cat.id).exists())

    # ------------------------------------------------------------------ #
    # Transférer un employé
    # ------------------------------------------------------------------ #

    def test_transferer_un_employe(self):
        r = self.api.put(f"/api/users/employers/{self.employe.id}/magasin/",
                         {"magasin_id": self.magasinB.id}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.profil.refresh_from_db()
        self.assertEqual(self.profil.magasin, self.magasinB)
        # Son sous-rôle le suit.
        self.assertEqual(self.profil.commande_role, "PREPARATEUR")
        self.assertEqual(r.data["ancien_magasin"]["nom"], "Magasin A")
        self.assertEqual(r.data["nouveau_magasin"]["nom"], "Magasin B")

    def test_transfert_vers_le_meme_magasin_refuse(self):
        r = self.api.put(f"/api/users/employers/{self.employe.id}/magasin/",
                         {"magasin_id": self.magasinA.id}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_transfert_vers_une_autre_societe_refuse(self):
        autre = CustomUser.objects.create_user(
            email="autre@test.mg", password="x", role="admin", full_name="Autre"
        )
        AdminProfile.objects.create(user=autre, company_name="Autre société")
        etranger = MagasinProfile.objects.create(admin=autre, shop_name="Ailleurs")

        r = self.api.put(f"/api/users/employers/{self.employe.id}/magasin/",
                         {"magasin_id": etranger.id}, format="json")
        self.assertEqual(r.status_code, 404)
        self.profil.refresh_from_db()
        self.assertEqual(self.profil.magasin, self.magasinA)

    def test_l_historique_ne_suit_pas_l_employe(self):
        """Les commandes restent au magasin où le travail a eu lieu."""
        order = self._remplir(self.magasinA)
        self.api.put(f"/api/users/employers/{self.employe.id}/magasin/",
                     {"magasin_id": self.magasinB.id}, format="json")
        order.refresh_from_db()
        self.assertEqual(order.magasin, self.magasinA)

    # ------------------------------------------------------------------ #
    # Modifier les informations d'un compte
    # ------------------------------------------------------------------ #

    def test_modifier_toutes_les_informations_d_un_employe(self):
        r = self.api.patch(f"/api/users/comptes/{self.employe.id}/", {
            "full_name": "Rakoto Jean",
            "email": "rakoto@test.mg",
            "phone": "+261340000001",
            "adresse": "Antananarivo",
            "position": "Chef de dépôt",
            "commande_role": "LIVREUR",
            "magasin_id": self.magasinB.id,
        }, format="json")
        self.assertEqual(r.status_code, 200, r.data)

        self.employe.refresh_from_db()
        self.profil.refresh_from_db()
        self.assertEqual(self.employe.full_name, "Rakoto Jean")
        self.assertEqual(self.employe.email, "rakoto@test.mg")
        self.assertEqual(self.employe.username, "rakoto@test.mg", "l'identifiant suit l'e-mail")
        self.assertEqual(self.employe.phone, "+261340000001")
        self.assertEqual(self.profil.position, "Chef de dépôt")
        self.assertEqual(self.profil.commande_role, "LIVREUR")
        self.assertEqual(self.profil.magasin, self.magasinB)

    def test_le_mot_de_passe_reste_intact(self):
        self.api.patch(f"/api/users/comptes/{self.employe.id}/",
                       {"full_name": "Nouveau Nom"}, format="json")
        self.employe.refresh_from_db()
        self.assertTrue(self.employe.check_password("x"))

    def test_email_en_doublon_refuse(self):
        r = self.api.patch(f"/api/users/comptes/{self.employe.id}/",
                           {"email": "gerant@test.mg"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("email", r.data)

    def test_un_compte_d_une_autre_societe_est_refuse(self):
        autre = CustomUser.objects.create_user(
            email="ailleurs@test.mg", password="x", role="employer", full_name="Ailleurs"
        )
        r = self.api.patch(f"/api/users/comptes/{autre.id}/",
                           {"full_name": "Piraté"}, format="json")
        self.assertEqual(r.status_code, 403)

    def test_le_gerant_ne_modifie_aucun_compte(self):
        self.api.force_authenticate(user=self.gerant)
        r = self.api.patch(f"/api/users/comptes/{self.employe.id}/",
                           {"full_name": "Piraté"}, format="json")
        self.assertEqual(r.status_code, 403)
