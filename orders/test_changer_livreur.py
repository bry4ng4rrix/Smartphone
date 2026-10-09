"""Changer le livreur d'une commande, y compris une fois qu'elle est « Prête ».

Celui qui devait la prendre peut être indisponible au dernier moment. La
réassignation passe par `POST /api/orders/{id}/assign-livreur/`, indépendant
du statut — `update_order` n'y touche pas et refuserait de toute façon
l'essentiel sur une commande engagée.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order, OrderItem
from users.models import AdminProfile, CustomUser, EmployerProfile, MagasinProfile


class ChangerLivreurTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        self.admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin", is_confirmed=True,
        )
        AdminProfile.objects.create(user=self.admin, company_name="Société")
        self.magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique")

        categorie = ProductCategory.objects.create(magasin=self.magasin, nom="HOUSSE")
        sous_type = ProductType.objects.create(category=categorie, nom="FLIP")
        marque = Brand.objects.create(magasin=self.magasin, nom="Samsung")
        reference = ProductReference.objects.create(
            type=sous_type, brand=marque, reference_name="A15", prix_vente=Decimal("30000"),
        )
        self.variante = ProductVariant.objects.create(
            product_reference=reference, couleur="Noir", stock_actuel=10,
        )

        self.livreur1 = self._livreur("livreur1@test.mg", "Rakoto")
        self.livreur2 = self._livreur("livreur2@test.mg", "Rabe")

        self.commande = Order.objects.create(
            magasin=self.magasin, client_nom="Rasoa", telephone="+261341111111",
            livraison_zone="ZONE1", adresse_livraison="Ambohipo",
            livreur=self.livreur1, statut_courant="PRETE",
        )
        OrderItem.objects.create(
            order=self.commande, product_variant=self.variante,
            quantite=1, prix_unitaire=Decimal("30000"),
        )
        self.api.force_authenticate(user=self.admin)

    def _livreur(self, email, nom, magasin=None):
        user = CustomUser.objects.create_user(
            email=email, password="x", role="employer", full_name=nom, is_confirmed=True,
        )
        EmployerProfile.objects.create(
            user=user, admin=self.admin, magasin=magasin or self.magasin,
            position="Livreur", commande_role="LIVREUR",
        )
        return user

    def _assigner(self, livreur, commande=None):
        commande = commande or self.commande
        return self.api.post(
            f"/api/orders/{commande.id}/assign-livreur/",
            {"livreur_id": livreur.id}, format="json",
        )

    # ------------------------------------------------------------------ #
    # Le cas demandé
    # ------------------------------------------------------------------ #

    def test_on_change_le_livreur_d_une_commande_prete(self):
        r = self._assigner(self.livreur2)
        self.assertEqual(r.status_code, 200, r.data)

        self.commande.refresh_from_db()
        self.assertEqual(self.commande.livreur, self.livreur2)
        self.assertEqual(self.commande.statut_courant, "PRETE",
                         "réassigner ne fait pas avancer la commande")

    def test_l_ancien_livreur_perd_la_commande_de_vue(self):
        """Son périmètre est filtré sur `livreur=lui` : après le changement,
        elle doit sortir de sa liste et entrer dans celle du nouveau."""
        self._assigner(self.livreur2)

        self.api.force_authenticate(user=self.livreur1)
        r = self.api.get("/api/orders/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertNotIn(self.commande.id, [o["id"] for o in r.data])

        self.api.force_authenticate(user=self.livreur2)
        r = self.api.get("/api/orders/")
        self.assertIn(self.commande.id, [o["id"] for o in r.data])

    def test_on_change_aussi_en_cours_de_livraison(self):
        self.commande.statut_courant = "EN_LIVRAISON"
        self.commande.save(update_fields=["statut_courant"])

        r = self._assigner(self.livreur2)
        self.assertEqual(r.status_code, 200, r.data)
        self.commande.refresh_from_db()
        self.assertEqual(self.commande.livreur, self.livreur2)

    # ------------------------------------------------------------------ #
    # Ce que ça ne doit pas ouvrir
    # ------------------------------------------------------------------ #

    def test_une_commande_terminee_reste_intouchable(self):
        """Y compris un RETOUR : le colis est revenu et le bilan attribue
        déjà cette tournée à quelqu'un."""
        for statut in ("LIVRE", "RETOUR", "ANNULEE"):
            with self.subTest(statut=statut):
                self.commande.statut_courant = statut
                self.commande.livreur = self.livreur1
                self.commande.save(update_fields=["statut_courant", "livreur"])

                r = self._assigner(self.livreur2)
                self.assertEqual(r.status_code, 400, r.data)
                self.commande.refresh_from_db()
                self.assertEqual(self.commande.livreur, self.livreur1)

    def test_un_livreur_d_un_autre_magasin_est_refuse(self):
        autre_magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Ailleurs")
        etranger = self._livreur("etranger@test.mg", "Étranger", magasin=autre_magasin)

        r = self._assigner(etranger)
        self.assertEqual(r.status_code, 400, r.data)
        self.commande.refresh_from_db()
        self.assertEqual(self.commande.livreur, self.livreur1)

    def test_un_preparateur_ne_peut_pas_etre_designe_livreur(self):
        prep = CustomUser.objects.create_user(
            email="prep@test.mg", password="x", role="employer", full_name="Prép", is_confirmed=True,
        )
        EmployerProfile.objects.create(
            user=prep, admin=self.admin, magasin=self.magasin,
            position="Préparateur", commande_role="PREPARATEUR",
        )
        r = self._assigner(prep)
        self.assertEqual(r.status_code, 400, r.data)

    def test_seul_le_gerant_reassigne(self):
        self.api.force_authenticate(user=self.livreur1)
        r = self._assigner(self.livreur2)
        self.assertEqual(r.status_code, 403, r.data)
        self.commande.refresh_from_db()
        self.assertEqual(self.commande.livreur, self.livreur1)

    def test_le_gerant_de_magasin_le_peut_aussi(self):
        gerant = CustomUser.objects.create_user(
            email="gerant@test.mg", password="x", role="magasin", full_name="Gérant", is_confirmed=True,
        )
        self.magasin.user = gerant
        self.magasin.save()

        self.api.force_authenticate(user=gerant)
        r = self._assigner(self.livreur2)
        self.assertEqual(r.status_code, 200, r.data)

    # ------------------------------------------------------------------ #
    # L'autre voie reste fermée
    # ------------------------------------------------------------------ #

    def test_update_order_refuse_toujours_le_reste_sur_une_commande_prete(self):
        """La réassignation ne rouvre pas l'édition complète."""
        r = self.api.patch(f"/api/orders/{self.commande.id}/",
                           {"client_nom": "Autre"}, format="json")
        self.assertEqual(r.status_code, 400, r.data)
        self.commande.refresh_from_db()
        self.assertEqual(self.commande.client_nom, "Rasoa")

    def test_le_preparateur_lui_n_est_plus_changeable_une_fois_prete(self):
        """Son travail est déjà fait à ce stade — contrairement au livreur."""
        prep = CustomUser.objects.create_user(
            email="prep2@test.mg", password="x", role="employer", full_name="Prép", is_confirmed=True,
        )
        EmployerProfile.objects.create(
            user=prep, admin=self.admin, magasin=self.magasin,
            position="Préparateur", commande_role="PREPARATEUR",
        )
        r = self.api.post(f"/api/orders/{self.commande.id}/assign-preparateur/",
                          {"preparateur_id": prep.id}, format="json")
        self.assertEqual(r.status_code, 400, r.data)


class FiltreLivreurTests(ChangerLivreurTests):
    """Filtrer la liste des commandes par livreur — pendant de
    `preparateur_id`, pour répondre à « que livre Untel ? »."""

    def setUp(self):
        super().setUp()
        # Une seconde commande, confiée à l'autre livreur.
        self.autre = Order.objects.create(
            magasin=self.magasin, client_nom="Naivo", telephone="+261342222222",
            livraison_zone="ZONE1", adresse_livraison="Ankorondrano",
            livreur=self.livreur2, statut_courant="PRETE",
        )
        OrderItem.objects.create(
            order=self.autre, product_variant=self.variante,
            quantite=1, prix_unitaire=Decimal("30000"),
        )

    def _ids(self, **params):
        r = self.api.get("/api/orders/", params)
        self.assertEqual(r.status_code, 200, r.data)
        return {o["id"] for o in r.data}

    def test_sans_filtre_les_deux_commandes_sortent(self):
        self.assertEqual(self._ids(), {self.commande.id, self.autre.id})

    def test_filtrer_par_livreur(self):
        self.assertEqual(self._ids(livreur_id=self.livreur1.id), {self.commande.id})
        self.assertEqual(self._ids(livreur_id=self.livreur2.id), {self.autre.id})

    def test_un_livreur_sans_commande_ne_renvoie_rien(self):
        libre = self._livreur("libre@test.mg", "Libre")
        self.assertEqual(self._ids(livreur_id=libre.id), set())

    def test_les_deux_filtres_se_croisent(self):
        """Préparateur ET livreur : deux questions distinctes, combinables."""
        prep = CustomUser.objects.create_user(
            email="prep3@test.mg", password="x", role="employer",
            full_name="Prép", is_confirmed=True,
        )
        EmployerProfile.objects.create(
            user=prep, admin=self.admin, magasin=self.magasin,
            position="Préparateur", commande_role="PREPARATEUR",
        )
        self.commande.preparateur = prep
        self.commande.save(update_fields=["preparateur"])

        self.assertEqual(
            self._ids(preparateur_id=prep.id, livreur_id=self.livreur1.id),
            {self.commande.id},
        )
        self.assertEqual(
            self._ids(preparateur_id=prep.id, livreur_id=self.livreur2.id),
            set(),
            "la commande de livreur2 n'a pas ce préparateur",
        )

    def test_le_filtre_respecte_le_perimetre_du_magasin(self):
        """Un livreur d'un autre magasin ne fait pas sortir ses commandes
        du périmètre accessible."""
        autre_magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Ailleurs")
        etranger = self._livreur("etranger2@test.mg", "Étranger", magasin=autre_magasin)
        self.assertEqual(self._ids(livreur_id=etranger.id), set())
