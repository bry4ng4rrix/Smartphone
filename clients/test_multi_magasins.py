"""Boutique en ligne multi-magasins.

Le site présente le catalogue de TOUTES les boutiques de la société, sans
dédoublonnage : le même modèle tenu par deux magasins y figure deux fois, une
fois par boutique. Le client compose son panier sans se soucier de l'origine
des articles, et chaque commande part automatiquement vers le magasin qui
détient le produit.
"""
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order
from users.models import AdminProfile, CustomUser, MagasinProfile


def catalogue_de(magasin, *, reference="Galaxy A15", prix="30000", stock=5):
    """Donne au magasin une référence à lui — catégorie, sous-type et marque
    sont rattachés à la boutique, c'est par là que passe le routage."""
    categorie = ProductCategory.objects.create(magasin=magasin, nom="HOUSSE", visible_client=True)
    sous_type = ProductType.objects.create(category=categorie, nom="FLIP COVER", visible_client=True)
    marque = Brand.objects.create(magasin=magasin, nom="Samsung")
    ref = ProductReference.objects.create(
        type=sous_type, brand=marque, reference_name=reference, prix_vente=Decimal(prix),
    )
    return ProductVariant.objects.create(product_reference=ref, couleur="Noir", stock_actuel=stock)


class CatalogueDesDeuxMagasinsTests(TestCase):
    def setUp(self):
        cache.clear()
        self.api = APIClient()
        admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin",
        )
        AdminProfile.objects.create(user=admin, company_name="Société")
        self.magasinA = MagasinProfile.objects.create(admin=admin, shop_name="Analakely")
        self.magasinB = MagasinProfile.objects.create(admin=admin, shop_name="Behoririka")
        # Même modèle, même prix, dans les deux boutiques.
        self.varianteA = catalogue_de(self.magasinA)
        self.varianteB = catalogue_de(self.magasinB)

    def test_le_meme_modele_apparait_une_fois_par_boutique(self):
        """Pas de dédoublonnage : deux exemplaires, deux boutiques (§ demande)."""
        r = self.api.get("/api/produit/")
        self.assertEqual(r.status_code, 200, r.data)
        lignes = [p for p in r.data["results"] if p["nom"] == "Galaxy A15"]
        self.assertEqual(len(lignes), 2, "le modèle doit figurer deux fois")
        self.assertEqual(
            sorted(p["boutique"]["nom"] for p in lignes),
            ["Analakely", "Behoririka"],
            "chaque exemplaire porte la boutique qui le détient",
        )

    def test_le_catalogue_complet_est_servi_sans_filtre(self):
        r = self.api.get("/api/produit/")
        self.assertEqual(r.data["count"], 2, "aucune boutique n'est imposée au visiteur")

    def test_un_filtre_boutique_reste_possible(self):
        """Utile pour une page de boutique ; jamais imposé au catalogue."""
        r = self.api.get("/api/produit/", {"boutique": self.magasinB.id})
        self.assertEqual(r.data["count"], 1)
        self.assertEqual(r.data["results"][0]["boutique"]["nom"], "Behoririka")


class RoutageAutomatiqueTests(TestCase):
    def setUp(self):
        cache.clear()
        self.api = APIClient()
        admin = CustomUser.objects.create_user(
            email="admin@test.mg", password="x", role="admin", full_name="Admin",
        )
        AdminProfile.objects.create(user=admin, company_name="Société")
        self.magasinA = MagasinProfile.objects.create(admin=admin, shop_name="Analakely")
        self.magasinB = MagasinProfile.objects.create(admin=admin, shop_name="Behoririka")
        self.varianteA = catalogue_de(self.magasinA)
        self.varianteB = catalogue_de(self.magasinB, reference="Galaxy A25", prix="40000")

    def corps(self, items, **extra):
        donnees = {
            "items": items,
            "livraison_zone": "EN_LIGNE",
            "client_nom": "Rakoto Jean",
            "telephone": "+261340000000",
            "adresse_livraison": "Lot II A 15 Antananarivo",
        }
        donnees.update(extra)
        return donnees

    def test_un_panier_d_une_boutique_donne_une_commande(self):
        """Le cas courant ne change pas de forme."""
        r = self.api.post("/api/commandes/", self.corps(
            [{"variante": self.varianteA.id, "quantite": 2}],
        ), format="json")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(len(r.data["commandes"]), 1)
        self.assertEqual(r.data["commandes"][0]["boutique"]["nom"], "Analakely")

    def test_un_panier_melange_donne_une_commande_par_boutique(self):
        r = self.api.post("/api/commandes/", self.corps([
            {"variante": self.varianteA.id, "quantite": 2},
            {"variante": self.varianteB.id, "quantite": 1},
        ]), format="json")
        self.assertEqual(r.status_code, 201, r.data)

        commandes = r.data["commandes"]
        self.assertEqual(len(commandes), 2)
        self.assertEqual(
            [c["boutique"]["nom"] for c in commandes],
            ["Analakely", "Behoririka"],
            "ordre stable, par nom de boutique",
        )
        # Chaque commande ne porte QUE les articles de sa boutique.
        self.assertEqual([i["produit"]["nom"] for i in commandes[0]["items"]], ["Galaxy A15"])
        self.assertEqual([i["produit"]["nom"] for i in commandes[1]["items"]], ["Galaxy A25"])
        # Deux boutiques = deux commandes distinctes en base.
        self.assertEqual(Order.objects.filter(magasin=self.magasinA).count(), 1)
        self.assertEqual(Order.objects.filter(magasin=self.magasinB).count(), 1)

    def test_la_boutique_envoyee_par_le_navigateur_est_ignoree(self):
        """Le routage ne dépend pas du client : il suit le produit (§ demande).
        Désigner la mauvaise boutique ne détourne rien."""
        r = self.api.post("/api/commandes/", self.corps(
            [{"variante": self.varianteB.id, "quantite": 1}],
            boutique=self.magasinA.id,
        ), format="json")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(r.data["commandes"][0]["boutique"]["nom"], "Behoririka")
        self.assertFalse(Order.objects.filter(magasin=self.magasinA).exists())

    def test_chaque_commande_porte_ses_propres_montants(self):
        """Deux boutiques = deux remises distinctes, donc deux fois les frais."""
        r = self.api.post("/api/commandes/", self.corps([
            {"variante": self.varianteA.id, "quantite": 1},
            {"variante": self.varianteB.id, "quantite": 1},
        ]), format="json")
        a, b = r.data["commandes"]
        self.assertEqual(a["frais_livraison"], 3000)
        self.assertEqual(a["total_a_payer"], 33000)
        self.assertEqual(b["frais_livraison"], 3000)
        self.assertEqual(b["total_a_payer"], 43000)

    def test_le_retrait_sur_place_indique_chaque_boutique(self):
        """Deux boutiques, deux endroits où aller : chaque accusé porte le sien."""
        self.magasinA.adresse, self.magasinA.telephone = "Analakely, face à la poste", "+261340000001"
        self.magasinA.save()
        self.magasinB.adresse, self.magasinB.telephone = "Behoririka, près du marché", "+261340000002"
        self.magasinB.save()

        r = self.api.post("/api/commandes/", self.corps([
            {"variante": self.varianteA.id, "quantite": 1},
            {"variante": self.varianteB.id, "quantite": 1},
        ], livraison_zone="RECUPERATION", adresse_livraison=""), format="json")
        self.assertEqual(r.status_code, 201, r.data)

        a, b = r.data["commandes"]
        self.assertEqual(a["boutique"]["adresse"], "Analakely, face à la poste")
        self.assertEqual(a["boutique"]["telephone"], "+261340000001")
        self.assertEqual(b["boutique"]["adresse"], "Behoririka, près du marché")
        self.assertEqual(b["boutique"]["telephone"], "+261340000002")

    def test_chaque_boutique_est_prevenue_de_sa_part(self):
        """Le gérant de chaque magasin doit voir SA commande à confirmer."""
        from users.models import Notification

        self.api.post("/api/commandes/", self.corps([
            {"variante": self.varianteA.id, "quantite": 1},
            {"variante": self.varianteB.id, "quantite": 1},
        ]), format="json")
        self.assertEqual(Notification.objects.filter(magasin=self.magasinA).count(), 1)
        self.assertEqual(Notification.objects.filter(magasin=self.magasinB).count(), 1)

    def test_un_refus_annule_tout_le_panier(self):
        """Rupture de stock chez l'une : le client ne doit pas repartir avec la
        moitié de sa commande passée et l'autre perdue."""
        self.varianteB.stock_actuel = 0
        self.varianteB.save(update_fields=["stock_actuel"])

        r = self.api.post("/api/commandes/", self.corps([
            {"variante": self.varianteA.id, "quantite": 1},
            {"variante": self.varianteB.id, "quantite": 1},
        ]), format="json")
        self.assertEqual(r.status_code, 400, r.data)
        self.assertEqual(Order.objects.count(), 0, "aucune commande ne doit subsister")

    def test_un_article_inconnu_est_refuse_avant_tout_routage(self):
        r = self.api.post("/api/commandes/", self.corps(
            [{"variante": 999999, "quantite": 1}],
        ), format="json")
        self.assertEqual(r.status_code, 400, r.data)
        self.assertIn("items", r.data)
        self.assertEqual(Order.objects.count(), 0)
