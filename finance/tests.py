"""Tests du module trésorerie — scénario de référence « cache-écran » :

    prix d'achat 6 000, prix de vente 25 000, livraison client 3 000
    (total client 28 000), frais agence 4 000, boost semaine 20 000 pour
    20 articles vendus → 1 000 / article

    gain réel = 28 000 − 6 000 − 4 000 − 1 000 = 17 000
    répartition 60/25/15 → 10 200 / 4 250 / 2 550 (somme = 17 000)

Lancer : python manage.py test finance
"""

from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APITestCase

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders import services as order_services
from orders.models import DeliveryZoneOption, LivreurExpense, MarketingCampaign, Order, OrderItem
from users.models import AdminProfile, CaisseMovement, CaisseSession, EmployerProfile, MagasinProfile

from . import services
from .models import Encaissement, EpargneMouvement, FinanceSettings, VenteResultat

User = get_user_model()
D = Decimal


class ScenarioMixin:
    """Une société, un magasin, une zone (3 000 client / 4 000 agence), un
    cache-écran (achat 6 000, vente 25 000) et un livreur."""

    def creer_scenario(self):
        self.admin = User.objects.create_user(email="admin@test.mg", password="x", role="admin", is_confirmed=True, full_name="Admin")
        self.admin_profile = AdminProfile.objects.create(user=self.admin, company_name="Test SARL")
        self.gerant = User.objects.create_user(email="gerant@test.mg", password="x", role="magasin", is_confirmed=True, full_name="Gérant")
        self.magasin = MagasinProfile.objects.create(user=self.gerant, admin=self.admin, shop_name="Boutique")
        self.livreur = User.objects.create_user(email="livreur@test.mg", password="x", role="employer", is_confirmed=True, full_name="Rija")
        EmployerProfile.objects.create(user=self.livreur, admin=self.admin, magasin=self.magasin, position="Livreur", commande_role="LIVREUR")
        self.preparateur = User.objects.create_user(email="prep@test.mg", password="x", role="employer", is_confirmed=True, full_name="Fara")
        EmployerProfile.objects.create(user=self.preparateur, admin=self.admin, magasin=self.magasin, position="Préparateur", commande_role="PREPARATEUR")
        self.zone = DeliveryZoneOption.objects.create(admin_profile=self.admin_profile, code="ZONE1", nom="Zone 1", prix=D("3000"), cout_agence=D("4000"))
        cat = ProductCategory.objects.create(magasin=self.magasin, nom="CACHE ÉCRAN", avec_couleurs=False)
        typ = ProductType.objects.create(category=cat, nom="PRIVACY")
        brand = Brand.objects.create(magasin=self.magasin, nom="Samsung")
        self.reference = ProductReference.objects.create(type=typ, brand=brand, reference_name="A16", prix_achat=D("6000"), prix_vente=D("25000"))
        self.variante = ProductVariant.objects.create(product_reference=self.reference, couleur="Standard", stock_actuel=100)
        self.aujourd_hui = timezone.localdate()

    def commande(self, quantite=1, mode_paiement="LIVRAISON", zone=None, jour=None):
        order = order_services.create_order(
            magasin=self.magasin, client_nom="Client", telephone="+261341234567", livraison_zone=zone or self.zone.code,
            items=[{"product_variant": self.variante, "quantite": quantite}], created_by=self.gerant, mode_paiement=mode_paiement,
            date_commande=timezone.now() if jour is None else timezone.make_aware(timezone.datetime.combine(jour, timezone.datetime.min.time().replace(hour=10))),
        )
        return order

    def livrer(self, order, livreur=None):
        """NOUVELLE → … → LIVRE en forçant les transitions comme le gérant."""
        order = order_services.change_order_status(order=order, new_status="EN_PREPARATION", user=self.gerant, preparateur_id=self.preparateur.id)
        order = order_services.change_order_status(order=order, new_status="PRETE", user=self.gerant)
        if order.livraison_zone == "RECUPERATION":
            return order_services.change_order_status(order=order, new_status="LIVRE", user=self.gerant)
        order = order_services.change_order_status(order=order, new_status="EN_LIVRAISON", user=self.gerant, livreur_id=(livreur or self.livreur).id)
        return order_services.change_order_status(order=order, new_status="LIVRE", user=self.gerant)

    def ouvrir_caisse(self, fond=D("0")):
        return CaisseSession.objects.create(magasin=self.magasin, opened_by=self.gerant, opening_balance=fond)


class CalculsTests(ScenarioMixin, TestCase):
    def setUp(self):
        self.creer_scenario()

    def test_1_gain_reel_scenario_reference(self):
        """25 000 + 3 000 − 6 000 − 4 000 − 1 000 = 17 000 (boost 20 000 / 20 articles)."""
        MarketingCampaign.objects.create(magasin=self.magasin, nom="Boost semaine", montant=D("20000"), date_debut=self.aujourd_hui - timedelta(days=6), date_fin=self.aujourd_hui, type_periode="SEMAINE")
        # 19 autres articles vendus sur la semaine + celui-ci = 20
        autres = self.commande(quantite=19)
        self.livrer(autres)
        order = self.livrer(self.commande())
        r = VenteResultat.objects.get(order=order)
        self.assertEqual(r.ca_produits, D("25000"))
        self.assertEqual(r.livraison_client, D("3000"))
        self.assertEqual(r.cout_achat, D("6000"))
        self.assertEqual(r.frais_agence, D("4000"))
        self.assertEqual(r.part_boost, D("1000"))
        self.assertEqual(r.gain_reel, D("17000"))
        self.assertEqual(r.resultat_livraison, D("-1000"))

    def test_2_cout_boost_par_article(self):
        boost = MarketingCampaign.objects.create(magasin=self.magasin, nom="B", montant=D("20000"), date_debut=self.aujourd_hui - timedelta(days=6), date_fin=self.aujourd_hui)
        self.livrer(self.commande(quantite=20))
        par_article, n = services.cout_boost_par_article(boost)
        self.assertEqual(n, 20)
        self.assertEqual(par_article, D("1000"))

    def test_3_resultat_livraison_perte(self):
        order = self.livrer(self.commande())
        r = VenteResultat.objects.get(order=order)
        self.assertEqual(r.livraison_client - r.frais_agence, D("-1000"))
        self.assertEqual(services.stats_livraison([self.magasin], self.aujourd_hui, self.aujourd_hui)["etat"], "perte")

    def test_4_et_5_repartition(self):
        parts = services.repartir(D("17000"), 60, 25, 15)
        self.assertEqual(parts, {"reappro": D("10200"), "epargne": D("4250"), "depenses": D("2550")})
        self.assertEqual(parts["reappro"] + parts["epargne"] + parts["depenses"], D("17000"))

    def test_6_parametres_total_100(self):
        self.assertEqual(sum(services.valider_pourcentages(60, 25, 15)), D("100"))
        with self.assertRaises(ValidationError):
            services.valider_pourcentages(60, 20, 10)
        s = services.parametres(self.magasin)
        self.assertEqual((s.pct_reappro, s.pct_epargne, s.pct_depenses), (D("60"), D("25"), D("15")))

    def test_7_pas_de_doublon_de_mouvement(self):
        session = self.ouvrir_caisse()
        order = self.livrer(self.commande(zone="RECUPERATION"))  # comptoir : entrée immédiate
        self.assertEqual(CaisseMovement.objects.filter(reference=f"VENTE:{order.numero}").count(), 1)
        # Rejeu (retry API, double clic…) : rien de nouveau.
        services.enregistrer_vente(order, self.gerant)
        services.enregistrer_vente(order, self.gerant)
        self.assertEqual(CaisseMovement.objects.filter(reference=f"VENTE:{order.numero}").count(), 1)
        self.assertEqual(EpargneMouvement.objects.filter(reference=f"VERSEMENT:{order.numero}").count(), 1)
        self.assertEqual(VenteResultat.objects.filter(order=order).count(), 1)
        self.assertEqual(services.solde_session(session), D("25000"))

    def test_8_retrait_epargne(self):
        self.ouvrir_caisse(D("100000"))
        order = self.livrer(self.commande())
        # gain sans boost : 25 000 + 3 000 − 6 000 − 4 000 = 18 000 → épargne 4 500
        self.assertEqual(services.solde_epargne(self.magasin), D("4500"))
        mvt = services.retirer_epargne(self.magasin, self.gerant, D("1500"), "Urgence")
        self.assertEqual(mvt.type, "RETRAIT")
        self.assertEqual(mvt.montant, D("-1500"))
        self.assertEqual(mvt.solde_apres, D("3000"))
        self.assertEqual(services.solde_epargne(self.magasin), D("3000"))
        with self.assertRaises(ValidationError):
            services.retirer_epargne(self.magasin, self.gerant, D("999999"))
        ind = services.indicateurs([self.magasin])
        # L'épargne est réservée : elle sort de l'argent disponible.
        self.assertEqual(ind["solde_caisse"], D("100000"))
        self.assertEqual(ind["espece_disponible"], D("97000"))
        self.assertEqual(ind["argent_en_attente"], D("28000"))

    def test_9_periodes_jour_semaine_mois(self):
        lundi = self.aujourd_hui - timedelta(days=self.aujourd_hui.weekday())
        self.livrer(self.commande())
        std = services.periodes_standard(self.aujourd_hui)
        self.assertEqual(std["jour"], (self.aujourd_hui, self.aujourd_hui))
        self.assertEqual(std["semaine"], (lundi, self.aujourd_hui))
        self.assertEqual(std["mois"], (self.aujourd_hui.replace(day=1), self.aujourd_hui))
        for cle in ("jour", "semaine", "mois"):
            s = services.stats_livraison([self.magasin], *std[cle])
            self.assertEqual(s["facturee"], D("3000"))
            self.assertEqual(s["agence"], D("4000"))
            self.assertEqual(s["resultat"], D("-1000"))
        hier = self.aujourd_hui - timedelta(days=1)
        self.assertEqual(services.stats_livraison([self.magasin], hier, hier)["nb"], 0)

    def test_10_boost_sans_article_vendu(self):
        boost = MarketingCampaign.objects.create(magasin=self.magasin, nom="B", montant=D("20000"), date_debut=self.aujourd_hui - timedelta(days=30), date_fin=self.aujourd_hui - timedelta(days=24))
        par_article, n = services.cout_boost_par_article(boost)
        self.assertEqual((par_article, n), (D("0"), 0))
        lignes = services.boosts_periode([self.magasin], self.aujourd_hui - timedelta(days=60), self.aujourd_hui)
        self.assertEqual(lignes[0]["articles_vendus"], 0)
        self.assertEqual(lignes[0]["cout_par_article"], D("0"))

    def test_gain_negatif_sans_repartition(self):
        self.reference.prix_achat = D("30000")
        self.reference.save()
        order = self.livrer(self.commande())
        r = VenteResultat.objects.get(order=order)
        self.assertEqual(r.gain_reel, D("-6000"))
        self.assertEqual((r.part_reappro, r.part_epargne, r.part_depenses), (D("0"), D("0"), D("0")))
        self.assertEqual(services.solde_epargne(self.magasin), D("0"))

    def test_boost_recalcule_les_ventes_de_la_periode(self):
        """Une part de boost figée à la vente serait fausse : elle est
        recalculée quand d'autres articles sont vendus dans la période, et
        l'épargne est corrigée d'autant."""
        MarketingCampaign.objects.create(magasin=self.magasin, nom="B", montant=D("20000"), date_debut=self.aujourd_hui, date_fin=self.aujourd_hui)
        premiere = self.livrer(self.commande())
        r1 = VenteResultat.objects.get(order=premiere)
        self.assertEqual(r1.part_boost, D("20000"))  # seul article vendu
        self.assertEqual(r1.gain_reel, D("-2000"))
        self.livrer(self.commande(quantite=19))
        r1.refresh_from_db()
        self.assertEqual(r1.part_boost, D("1000"))
        self.assertEqual(r1.gain_reel, D("17000"))
        self.assertEqual(r1.part_epargne, D("4250"))
        # Épargne alignée : versement (ou correction) = part finale de chaque vente
        self.assertEqual(services.epargne_versee_pour(premiere), D("4250"))
        total = sum(v.part_epargne for v in VenteResultat.objects.all())
        self.assertEqual(services.solde_epargne(self.magasin), total)

    def test_remise_livreur_avec_frais_de_tournee(self):
        session = self.ouvrir_caisse(D("0"))
        o1 = self.livrer(self.commande())
        o2 = self.livrer(self.commande(quantite=2))
        self.assertEqual(Encaissement.objects.filter(statut="EN_ATTENTE").count(), 2)
        LivreurExpense.objects.create(magasin=self.magasin, livreur=self.livreur, libelle="Carburant", prix_unitaire=D("5000"), statut="ACCEPTE")
        res = services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)
        self.assertEqual(res["nb"], 2)
        self.assertEqual(res["brut"], D("28000") + D("53000"))
        self.assertEqual(res["depenses"], D("5000"))
        self.assertEqual(services.solde_session(session), D("76000"))
        self.assertEqual(Encaissement.objects.filter(statut="EN_ATTENTE").count(), 0)
        # Une seconde remise ne crée rien
        res2 = services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)
        self.assertEqual(res2["nb"], 0)
        self.assertEqual(CaisseMovement.objects.filter(reference__startswith="VENTE:").count(), 2)
        self.assertEqual(CaisseMovement.objects.filter(reference__startswith="TOURNEE:").count(), 1)
        self.assertEqual(services.indicateurs([self.magasin])["argent_en_attente"], D("0"))
        # Journal : solde après chaque mouvement cohérent
        lignes = services.journal([self.magasin])
        self.assertEqual(lignes[0]["solde_apres"], D("76000"))
        self.assertEqual({l["origine"] for l in lignes}, {"VENTE", "FRAIS_LIVRAISON"})
        _ = (o1, o2)

    def test_remise_sans_caisse_ouverte_refusee(self):
        self.livrer(self.commande())
        with self.assertRaises(ValidationError):
            services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)

    def test_annulation_vente_apres_remise(self):
        session = self.ouvrir_caisse()
        order = self.livrer(self.commande(zone="RECUPERATION"))
        self.assertEqual(services.solde_session(session), D("25000"))
        epargne_avant = services.solde_epargne(self.magasin)
        self.assertEqual(epargne_avant, D("4750"))  # gain 19 000 (pas de livraison) × 25 %
        order_services.corriger_statut(order=order, user=self.gerant, nouveau_statut="RETOUR")
        r = VenteResultat.objects.get(order=order)
        self.assertTrue(r.annule)
        self.assertEqual(services.solde_epargne(self.magasin), D("0"))
        self.assertEqual(services.solde_session(session), D("0"))  # remboursement contre-passé
        self.assertEqual(CaisseMovement.objects.filter(reference=f"ANNUL:{order.numero}").count(), 1)
        self.assertEqual(Encaissement.objects.get(order=order).statut, "ANNULE")
        self.assertEqual(services.stats_gain([self.magasin], self.aujourd_hui, self.aujourd_hui)["nb_ventes"], 0)
        # Retour en LIVRE : tout est ré-enregistré sans doublon
        order_services.corriger_statut(order=order, user=self.gerant, nouveau_statut="LIVRE")
        self.assertFalse(VenteResultat.objects.get(order=order).annule)
        self.assertEqual(services.solde_epargne(self.magasin), D("4750"))
        self.assertEqual(CaisseMovement.objects.filter(reference=f"VENTE:{order.numero}").count(), 1)

    def test_livraison_partielle_et_multi_articles(self):
        order = self.commande(quantite=3)
        order = order_services.change_order_status(order=order, new_status="EN_PREPARATION", user=self.gerant, preparateur_id=self.preparateur.id)
        order = order_services.change_order_status(order=order, new_status="PRETE", user=self.gerant)
        order = order_services.change_order_status(order=order, new_status="EN_LIVRAISON", user=self.gerant, livreur_id=self.livreur.id)
        item = order.items.first()
        # Tout est sur une seule ligne x3 : on la garde -> pas de partiel possible sur la ligne ; on ajoute une 2e ligne
        OrderItem.objects.create(order=order, product_variant=self.variante, quantite=1)
        order.recompute_total()
        order = order_services.change_order_status(order=order, new_status="LIVRE", user=self.gerant, items_livres=[item.id])
        r = VenteResultat.objects.get(order=order)
        self.assertEqual(r.nb_articles, 3)
        self.assertEqual(r.ca_produits, D("75000"))
        self.assertEqual(r.cout_achat, D("18000"))
        self.assertEqual(r.gain_reel, D("75000") + D("3000") - D("18000") - D("4000"))
        self.assertEqual(Encaissement.objects.get(order=order).montant, D("78000"))


class ApiTests(ScenarioMixin, APITestCase):
    def setUp(self):
        self.creer_scenario()
        self.client.force_authenticate(user=self.gerant)

    def test_settings_refuse_total_different_de_100(self):
        res = self.client.patch("/api/finance/settings/", {"pct_reappro": 60, "pct_epargne": 20, "pct_depenses": 10}, format="json")
        self.assertEqual(res.status_code, 400)
        self.assertIn("100", str(res.data))
        res = self.client.patch("/api/finance/settings/", {"pct_reappro": 50, "pct_epargne": 30, "pct_depenses": 20}, format="json")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(FinanceSettings.objects.get().pct_epargne, D("30"))

    def test_dashboard_et_journal(self):
        self.ouvrir_caisse(D("10000"))
        self.livrer(self.commande(zone="RECUPERATION"))
        res = self.client.get("/api/finance/dashboard/")
        self.assertEqual(res.status_code, 200)
        ind = res.data["indicateurs"]
        self.assertEqual(D(str(ind["solde_caisse"])), D("35000"))
        self.assertEqual(D(str(ind["epargne"])), D("4750"))
        self.assertEqual(D(str(ind["espece_disponible"])), D("30250"))
        self.assertEqual(D(str(ind["valeur_stock"])), D("99") * D("6000"))
        self.assertEqual(res.data["gain"]["nb_ventes"], 1)
        res = self.client.get("/api/finance/journal/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(len(res.data["lignes"]), 1)
        self.assertEqual(D(str(res.data["lignes"][0]["solde_apres"])), D("35000"))

    def test_retrait_epargne_exige_confirmation(self):
        self.livrer(self.commande(zone="RECUPERATION"))
        res = self.client.post("/api/finance/epargne/retrait/", {"montant": 1000, "confirmation": False}, format="json")
        self.assertEqual(res.status_code, 400)
        res = self.client.post("/api/finance/epargne/retrait/", {"montant": 1000, "confirmation": True, "motif": "Test"}, format="json")
        self.assertEqual(res.status_code, 201)
        self.assertEqual(D(str(res.data["solde_apres"])), D("3750"))
        res = self.client.post("/api/finance/epargne/retrait/", {"montant": 999999, "confirmation": True}, format="json")
        self.assertEqual(res.status_code, 400)

    def test_mouvement_automatique_non_supprimable(self):
        self.ouvrir_caisse()
        order = self.livrer(self.commande(zone="RECUPERATION"))
        mvt = CaisseMovement.objects.get(reference=f"VENTE:{order.numero}")
        res = self.client.delete(f"/api/users/caisse/movements/{mvt.id}/")
        self.assertEqual(res.status_code, 400)
        self.assertTrue(CaisseMovement.objects.filter(id=mvt.id).exists())

    def test_livreur_interdit(self):
        self.client.force_authenticate(user=self.livreur)
        self.assertEqual(self.client.get("/api/finance/dashboard/").status_code, 403)
        self.assertEqual(self.client.post("/api/finance/epargne/retrait/", {"montant": 1, "confirmation": True}, format="json").status_code, 403)
