"""Tests de l'espace client (app `clients`) : catalogue public, compte
client, commandes client et étanchéité avec l'application interne.

Exécution : `python manage.py test clients` (SQLite de test par défaut).
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.cache import cache
from rest_framework import status
from rest_framework.test import APITestCase

from catalog.models import Brand, Color, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import DeliveryZoneOption, Order, OrderStatusHistory
from users.models import AdminProfile, EmployerProfile, MagasinProfile

from .models import Client

User = get_user_model()

PWD = "MotDePasse123"


class EspaceClientTestCase(APITestCase):
    """Jeu de données minimal : une société, une boutique, un catalogue
    (catégorie > sous-type > marque > référence > 2 couleurs), une zone de
    livraison, un gérant, un préparateur, et deux clients."""

    def setUp(self):
        cache.clear()  # limitation de débit : repartir à zéro à chaque test
        self.admin = User.objects.create_user(
            email="owner@test.com", password=PWD, role="admin", is_confirmed=True, full_name="Owner",
        )
        self.admin_profile = AdminProfile.objects.create(user=self.admin, company_name="Boutique Demo")
        self.magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique Centre")
        self.autre_magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique Nord")
        self.preparateur = User.objects.create_user(
            email="prep@test.com", password=PWD, role="employer", is_confirmed=True, full_name="Hery",
        )
        EmployerProfile.objects.create(user=self.preparateur, magasin=self.magasin, admin=self.admin, commande_role="PREPARATEUR")
        self.zone = DeliveryZoneOption.objects.create(admin_profile=self.admin_profile, nom="Centre-ville", prix=Decimal("3000"))

        self.categorie = ProductCategory.objects.create(magasin=self.magasin, nom="Coques", ordre=1)
        self.sous_type = ProductType.objects.create(category=self.categorie, nom="iPhone")
        self.marque = Brand.objects.create(magasin=self.magasin, nom="Apple")
        Color.objects.create(magasin=self.magasin, nom="Noir")
        self.ref = ProductReference.objects.create(
            type=self.sous_type, brand=self.marque, reference_name="Coque iPhone 15",
            prix_achat=Decimal("10000"), prix_vente=Decimal("25000"),
        )
        self.noir = ProductVariant.objects.create(product_reference=self.ref, couleur="Noir", stock_actuel=5)
        self.rouge = ProductVariant.objects.create(product_reference=self.ref, couleur="Rouge", stock_actuel=0)
        self.ref_inactive = ProductReference.objects.create(
            type=self.sous_type, brand=self.marque, reference_name="Ancienne coque", prix_vente=Decimal("5000"), actif=False,
        )
        ProductVariant.objects.create(product_reference=self.ref_inactive, couleur="Noir", stock_actuel=3)
        # Catalogue d'une autre boutique (ne doit jamais se mélanger)
        cat2 = ProductCategory.objects.create(magasin=self.autre_magasin, nom="Chargeurs", ordre=1)
        type2 = ProductType.objects.create(category=cat2, nom="USB-C")
        marque2 = Brand.objects.create(magasin=self.autre_magasin, nom="Samsung")
        ref2 = ProductReference.objects.create(type=type2, brand=marque2, reference_name="Chargeur 25W", prix_vente=Decimal("40000"))
        self.variante_autre_boutique = ProductVariant.objects.create(product_reference=ref2, couleur="Standard", stock_actuel=2)

        self.client_a = Client(email="alice@test.com", nom="Alice", telephone="+261340000001", adresse="Lot II A Antananarivo")
        self.client_a.set_password(PWD)
        self.client_a.save()
        self.client_b = Client(email="bob@test.com", nom="Bob", telephone="+261340000002")
        self.client_b.set_password(PWD)
        self.client_b.save()

    # --- helpers ---------------------------------------------------------- #

    def login_client(self, email=None):
        r = self.client.post("/api/client/login/", {"email": email or "alice@test.com", "password": PWD}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
        return r.data

    def commande_valide(self, **extra):
        data = {
            "boutique": self.magasin.id,
            "livraison_zone": self.zone.code,
            "adresse_livraison": "Lot II A Antananarivo",
            "items": [{"variante": self.noir.id, "quantite": 2, "prix_attendu": "25000.00"}],
        }
        data.update(extra)
        return data

    def creer_commande(self):
        self.login_client()
        r = self.client.post("/api/client/orders/", self.commande_valide(), format="json")
        self.assertEqual(r.status_code, 201, r.content)
        return r.data


# =========================================================================== #
# Catalogue public
# =========================================================================== #


class CataloguePublicTests(EspaceClientTestCase):
    def test_liste_produits_sans_authentification(self):
        r = self.client.get("/api/produit/")
        self.assertEqual(r.status_code, 200)
        noms = [p["nom"] for p in r.data["results"]]
        self.assertIn("Coque iPhone 15", noms)
        self.assertIn("Chargeur 25W", noms)
        self.assertNotIn("Ancienne coque", noms, "une référence inactive n'est pas publique")

    def test_detail_produit_structure_et_disponibilite(self):
        r = self.client.get(f"/api/produit/{self.ref.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["nom"], "Coque iPhone 15")
        self.assertEqual(r.data["prix_vente"], 25000)
        self.assertEqual(r.data["categorie"]["nom"], "Coques")
        self.assertEqual(r.data["sous_type"]["nom"], "iPhone")
        self.assertEqual(r.data["marque"]["nom"], "Apple")
        self.assertEqual(r.data["boutique"]["id"], self.magasin.id)
        self.assertTrue(r.data["disponible"])
        dispo = {v["couleur"]: v["disponible"] for v in r.data["variantes"]}
        self.assertEqual(dispo, {"Noir": True, "Rouge": False})

    def test_prix_achat_et_stock_jamais_exposes(self):
        r = self.client.get(f"/api/produit/{self.ref.id}/")
        brut = r.content.decode()
        for interdit in ("prix_achat", "stock_actuel", "seuil_alerte", "sku", "marge"):
            self.assertNotIn(interdit, brut, f"« {interdit} » ne doit pas sortir sur l'API publique")
        for v in r.data["variantes"]:
            self.assertEqual(set(v.keys()), {"id", "couleur", "disponible"})

    def test_produit_inactif_introuvable(self):
        r = self.client.get(f"/api/produit/{self.ref_inactive.id}/")
        self.assertEqual(r.status_code, 404)

    def test_filtres(self):
        def noms(qs):
            r = self.client.get("/api/produit/" + qs)
            self.assertEqual(r.status_code, 200, r.content)
            return [p["nom"] for p in r.data["results"]]

        self.assertEqual(noms("?search=coque"), ["Coque iPhone 15"])
        self.assertEqual(noms(f"?category={self.categorie.id}"), ["Coque iPhone 15"])
        self.assertEqual(noms(f"?type={self.categorie.id}"), ["Coque iPhone 15"])
        self.assertEqual(noms(f"?sous_type={self.sous_type.id}"), ["Coque iPhone 15"])
        self.assertEqual(noms(f"?brand={self.marque.id}"), ["Coque iPhone 15"])
        self.assertEqual(noms("?couleur=rouge"), ["Coque iPhone 15"])
        self.assertEqual(noms("?couleur=bleu"), [])
        self.assertEqual(noms("?min_price=30000"), ["Chargeur 25W"])
        self.assertEqual(noms("?max_price=30000"), ["Coque iPhone 15"])
        self.assertEqual(noms(f"?boutique={self.autre_magasin.id}"), ["Chargeur 25W"])
        self.assertEqual(noms("?available=true"), ["Chargeur 25W", "Coque iPhone 15"])
        self.rouge.stock_actuel = 0
        self.noir.stock_actuel = 0
        self.noir.save()
        self.assertEqual(noms("?available=true"), ["Chargeur 25W"])

    def test_referentiels_publics(self):
        r = self.client.get(f"/api/categories/?boutique={self.magasin.id}")
        self.assertEqual([c["nom"] for c in r.data], ["Coques"])
        self.assertEqual(self.client.get(f"/api/type/?boutique={self.magasin.id}").data, r.data, "type/ est un alias de categories/")
        r = self.client.get(f"/api/sous-type/?category={self.categorie.id}")
        self.assertEqual([t["nom"] for t in r.data], ["iPhone"])
        r = self.client.get(f"/api/marque/?boutique={self.magasin.id}")
        self.assertEqual([m["nom"] for m in r.data], ["Apple"])
        r = self.client.get(f"/api/couleurs/?boutique={self.magasin.id}")
        self.assertEqual([c["nom"] for c in r.data], ["Noir"])
        r = self.client.get("/api/boutiques/")
        self.assertEqual([b["nom"] for b in r.data], ["Boutique Centre", "Boutique Nord"])
        r = self.client.get(f"/api/boutiques/{self.magasin.id}/zones/")
        self.assertEqual(r.data["zones"][0]["code"], self.zone.code)
        self.assertEqual(r.data["recuperation"]["code"], "RECUPERATION")


# =========================================================================== #
# Compte client
# =========================================================================== #


class CompteClientTests(EspaceClientTestCase):
    def test_inscription_puis_profil(self):
        r = self.client.post(
            "/api/client/register/",
            {"email": "Nouveau@Test.com", "password": PWD, "nom": "Nouveau", "telephone": "+261340000009"},
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.content)
        self.assertIn("access", r.data)
        self.assertEqual(r.data["client"]["email"], "nouveau@test.com")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
        me = self.client.get("/api/client/me/")
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.data["nom"], "Nouveau")
        self.assertNotIn("password", me.data)

    def test_inscription_email_deja_pris_et_validations(self):
        r = self.client.post(
            "/api/client/register/",
            {"email": "ALICE@test.com", "password": PWD, "nom": "X", "telephone": "+261340000009"},
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("email", r.data)
        r = self.client.post(
            "/api/client/register/",
            {"email": "c@test.com", "password": "court", "nom": "X", "telephone": "0340000009"},
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("password", r.data)
        self.assertIn("telephone", r.data)

    def test_connexion_et_mauvais_mot_de_passe(self):
        r = self.client.post("/api/client/login/", {"email": "alice@test.com", "password": "faux"}, format="json")
        self.assertEqual(r.status_code, 401)
        data = self.login_client()
        self.assertEqual(data["client"]["nom"], "Alice")
        self.assertIsNotNone(Client.objects.get(pk=self.client_a.pk).last_login)

    def test_refresh(self):
        data = self.login_client()
        r = self.client.post("/api/client/refresh/", {"refresh": data["refresh"]}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertIn("access", r.data)
        r = self.client.post("/api/client/refresh/", {"refresh": "n-importe-quoi"}, format="json")
        self.assertEqual(r.status_code, 401)

    def test_modification_profil_et_mot_de_passe(self):
        self.login_client()
        r = self.client.patch("/api/client/me/", {"adresse": "Nouvelle adresse", "email": "pirate@test.com"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["adresse"], "Nouvelle adresse")
        self.assertEqual(r.data["email"], "alice@test.com", "l'e-mail n'est pas modifiable")
        r = self.client.post(
            "/api/client/change-password/", {"ancien_mot_de_passe": PWD, "nouveau_mot_de_passe": "NouveauPass456"}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.assertTrue(Client.objects.get(pk=self.client_a.pk).check_password("NouveauPass456"))

    def test_sans_jeton_refuse(self):
        self.assertEqual(self.client.get("/api/client/me/").status_code, 401)
        self.assertEqual(self.client.get("/api/client/orders/").status_code, 401)

    def test_jeton_interne_refuse_sur_espace_client(self):
        self.client.force_authenticate(user=None)
        r = self.client.post("/api/users/login/", {"email": "owner@test.com", "password": PWD}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
        self.assertEqual(self.client.get("/api/client/me/").status_code, 401)

    def test_jeton_client_refuse_sur_api_interne(self):
        self.login_client()
        for url in ("/api/users/me/", "/api/orders/", "/api/catalog/references/", "/api/users/caisse/summary/", "/api/orders/reports/overview/"):
            r = self.client.get(url)
            self.assertIn(r.status_code, (401, 403), f"{url} -> {r.status_code}")


# =========================================================================== #
# Commandes client
# =========================================================================== #


class CommandesClientTests(EspaceClientTestCase):
    def test_creation_en_attente_d_approbation_sans_toucher_le_stock(self):
        data = self.creer_commande()
        self.assertEqual(data["statut"], "EN_ATTENTE_APPROBATION")
        self.assertEqual(data["boutique"]["id"], self.magasin.id)
        self.assertEqual(data["frais_livraison"], 3000)
        self.assertEqual(data["total_a_payer"], 53000)  # 2 × 25 000 + 3 000
        self.assertEqual(data["items"][0]["prix_unitaire"], 25000)
        self.assertTrue(data["peut_modifier"] and data["peut_annuler"])
        self.noir.refresh_from_db()
        self.assertEqual(self.noir.stock_actuel, 5, "le stock ne bouge qu'à la préparation")
        order = Order.objects.get(pk=data["id"])
        self.assertEqual(order.client, self.client_a)
        self.assertEqual(order.client_nom, "Alice")
        self.assertEqual(order.telephone, "+261340000001")
        self.assertIsNone(order.created_by)
        self.assertEqual(OrderStatusHistory.objects.filter(order=order, nouveau_statut="EN_ATTENTE_APPROBATION").count(), 1)

    def test_stock_insuffisant(self):
        self.login_client()
        r = self.client.post("/api/client/orders/", self.commande_valide(items=[{"variante": self.noir.id, "quantite": 6}]), format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("Stock insuffisant", r.data["items"][0])
        r = self.client.post("/api/client/orders/", self.commande_valide(items=[{"variante": self.rouge.id, "quantite": 1}]), format="json")
        self.assertEqual(r.status_code, 400)

    def test_prix_change(self):
        self.login_client()
        r = self.client.post(
            "/api/client/orders/",
            self.commande_valide(items=[{"variante": self.noir.id, "quantite": 1, "prix_attendu": "20000"}]),
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("a changé", r.data["items"][0])

    def test_article_inactif_ou_autre_boutique(self):
        self.login_client()
        r = self.client.post(
            "/api/client/orders/", self.commande_valide(items=[{"variante": self.variante_autre_boutique.id, "quantite": 1}]), format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("n'appartient pas", r.data["items"][0])
        inactive = ProductVariant.objects.get(product_reference=self.ref_inactive)
        r = self.client.post("/api/client/orders/", self.commande_valide(items=[{"variante": inactive.id, "quantite": 1}]), format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("indisponible", r.data["items"][0])

    def test_zone_invalide_et_recuperation(self):
        self.login_client()
        r = self.client.post("/api/client/orders/", self.commande_valide(livraison_zone="INCONNUE"), format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("livraison_zone", r.data)
        r = self.client.post("/api/client/orders/", self.commande_valide(livraison_zone="RECUPERATION", adresse_livraison=""), format="json")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(r.data["frais_livraison"], 0)
        self.assertEqual(r.data["total_a_payer"], 50000)

    def test_consultation_et_isolation_entre_clients(self):
        data = self.creer_commande()
        r = self.client.get("/api/client/orders/")
        self.assertEqual([o["id"] for o in r.data], [data["id"]])
        self.assertEqual(self.client.get(f"/api/client/orders/{data['id']}/").status_code, 200)
        # Bob ne voit ni ne touche la commande d'Alice
        self.login_client("bob@test.com")
        self.assertEqual(self.client.get("/api/client/orders/").data, [])
        self.assertEqual(self.client.get(f"/api/client/orders/{data['id']}/").status_code, 404)
        self.assertEqual(self.client.patch(f"/api/client/orders/{data['id']}/", {"note": "x"}, format="json").status_code, 404)
        self.assertEqual(self.client.post(f"/api/client/orders/{data['id']}/cancel/", {}, format="json").status_code, 404)

    def test_modification_en_attente_puis_bloquee(self):
        data = self.creer_commande()
        r = self.client.patch(
            f"/api/client/orders/{data['id']}/",
            {"adresse_livraison": "Nouvelle adresse", "note": "Sonner deux fois", "livraison_zone": "RECUPERATION"},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["note"], "Sonner deux fois")
        self.assertEqual(r.data["livraison_zone"], "RECUPERATION")
        self.assertEqual(r.data["frais_livraison"], 0)
        self.assertEqual(r.data["total_a_payer"], 50000)
        # Une fois approuvée, plus de modification depuis l'espace client
        Order.objects.filter(pk=data["id"]).update(statut_courant="NOUVELLE")
        r = self.client.patch(f"/api/client/orders/{data['id']}/", {"note": "trop tard"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_annulation_par_le_client(self):
        data = self.creer_commande()
        r = self.client.post(f"/api/client/orders/{data['id']}/cancel/", {"note": "Changement d'avis"}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["statut"], "ANNULEE")
        self.assertFalse(r.data["peut_annuler"])
        Order.objects.filter(pk=data["id"]).update(statut_courant="EN_PREPARATION")
        r = self.client.post(f"/api/client/orders/{data['id']}/cancel/", {}, format="json")
        self.assertEqual(r.status_code, 400)


# =========================================================================== #
# Approbation par le gérant (API interne) et isolation
# =========================================================================== #


class ApprobationGerantTests(EspaceClientTestCase):
    def test_gerant_approuve_puis_workflow_habituel(self):
        data = self.creer_commande()
        self.client.credentials()
        self.client.force_authenticate(user=self.admin)
        r = self.client.get(f"/api/orders/{data['id']}/")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data["est_commande_client"])
        self.assertEqual(r.data["client_email"], "alice@test.com")
        # Impossible de préparer avant approbation
        r = self.client.post(f"/api/orders/{data['id']}/status/", {"statut": "EN_PREPARATION", "preparateur_id": self.preparateur.id}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post(f"/api/orders/{data['id']}/approuver/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["statut_courant"], "NOUVELLE")
        # Puis le circuit existant fonctionne (préparation = sortie de stock)
        r = self.client.post(f"/api/orders/{data['id']}/status/", {"statut": "EN_PREPARATION", "preparateur_id": self.preparateur.id}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.noir.refresh_from_db()
        self.assertEqual(self.noir.stock_actuel, 3)
        # Une commande déjà approuvée ne peut pas l'être deux fois
        r = self.client.post(f"/api/orders/{data['id']}/approuver/", {}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_gerant_refuse(self):
        data = self.creer_commande()
        self.client.credentials()
        self.client.force_authenticate(user=self.admin)
        r = self.client.post(f"/api/orders/{data['id']}/refuser/", {"note": "Rupture fournisseur"}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["statut_courant"], "ANNULEE")
        self.noir.refresh_from_db()
        self.assertEqual(self.noir.stock_actuel, 5)

    def test_preparateur_ne_peut_pas_approuver_ni_voir_avant_assignation(self):
        data = self.creer_commande()
        self.client.credentials()
        self.client.force_authenticate(user=self.preparateur)
        self.assertEqual(self.client.post(f"/api/orders/{data['id']}/approuver/", {}, format="json").status_code, 403)
        ids = [o["id"] for o in self.client.get("/api/orders/").data]
        self.assertNotIn(data["id"], ids)

    def test_commandes_internes_inchangees(self):
        """Régression : une commande saisie par le gérant suit toujours le
        circuit existant (Nouvelle -> préparation -> stock déduit)."""
        self.client.force_authenticate(user=self.admin)
        r = self.client.post(
            "/api/orders/",
            {
                "client_nom": "Comptoir", "telephone": "+261340000003", "livraison_zone": "RECUPERATION",
                "magasin_id": self.magasin.id,
                "items": [{"product_variant": self.noir.id, "quantite": 1}],
            },
            format="json",
        )
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(r.data["statut_courant"], "NOUVELLE")
        self.assertFalse(r.data["est_commande_client"])
        self.assertIsNone(r.data["client"])
        r = self.client.post(f"/api/orders/{r.data['id']}/status/", {"statut": "EN_PREPARATION", "preparateur_id": self.preparateur.id}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.noir.refresh_from_db()
        self.assertEqual(self.noir.stock_actuel, 4)
