"""Tests du module trésorerie — scénario de référence « cache-écran » :

    prix d'achat 6 000, prix de vente 25 000, livraison client 3 000
    (total client 28 000), frais de livraison 4 000 (dépense « LIVRAISON 4K »
    du livreur acceptée par le gérant), boost semaine 20 000 pour
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
    """Une société, un magasin, une zone (3 000 client), un type de dépense
    « LIVRAISON 4K » (frais de livraison, 4 000 par course déclarée par le
    livreur et acceptée), un cache-écran (achat 6 000, vente 25 000) et un
    livreur."""

    def creer_scenario(self):
        self.admin = User.objects.create_user(email="admin@test.mg", password="x", role="admin", is_confirmed=True, full_name="Admin")
        self.admin_profile = AdminProfile.objects.create(user=self.admin, company_name="Test SARL")
        self.gerant = User.objects.create_user(email="gerant@test.mg", password="x", role="magasin", is_confirmed=True, full_name="Gérant")
        self.magasin = MagasinProfile.objects.create(user=self.gerant, admin=self.admin, shop_name="Boutique")
        self.livreur = User.objects.create_user(email="livreur@test.mg", password="x", role="employer", is_confirmed=True, full_name="Rija")
        EmployerProfile.objects.create(user=self.livreur, admin=self.admin, magasin=self.magasin, position="Livreur", commande_role="LIVREUR")
        self.preparateur = User.objects.create_user(email="prep@test.mg", password="x", role="employer", is_confirmed=True, full_name="Fara")
        EmployerProfile.objects.create(user=self.preparateur, admin=self.admin, magasin=self.magasin, position="Préparateur", commande_role="PREPARATEUR")
        self.zone = DeliveryZoneOption.objects.create(admin_profile=self.admin_profile, code="ZONE1", nom="Zone 1", prix=D("3000"))
        from orders.models import ExpenseType

        self.type_livraison = ExpenseType.objects.create(
            admin_profile=self.admin_profile, nom="LIVRAISON 4K", prix_unitaire=D("4000"), par_unite=True, frais_livraison=True
        )
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
        order = order_services.change_order_status(order=order, new_status="LIVRE", user=self.gerant)
        # Le livreur déclare la course (4 000), le gérant l'accepte : c'est
        # ce montant — pas un coût de zone — qui entre dans le gain réel.
        self.declarer_frais_livraison(order, livreur=livreur)
        return order

    def declarer_frais_livraison(self, order, montant=D("4000"), livreur=None, statut="ACCEPTE"):
        expense = LivreurExpense.objects.create(
            magasin=self.magasin, livreur=livreur or self.livreur, type_depense=self.type_livraison, libelle=self.type_livraison.nom,
            prix_unitaire=montant, quantite=1, statut=statut, date=timezone.localtime(order.date_commande).date(),
        )
        services.recalculer_apres_depense(expense, self.gerant)
        return expense

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
        # Carburant 5 000 + les deux courses LIVRAISON 4K acceptées (8 000).
        self.assertEqual(res["depenses"], D("13000"))
        self.assertEqual(services.solde_session(session), D("68000"))
        self.assertEqual(Encaissement.objects.filter(statut="EN_ATTENTE").count(), 0)
        # Une seconde remise ne crée rien
        res2 = services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)
        self.assertEqual(res2["nb"], 0)
        self.assertEqual(CaisseMovement.objects.filter(reference__startswith="VENTE:").count(), 2)
        # Une sortie par dépense remise : carburant + les deux courses.
        self.assertEqual(CaisseMovement.objects.filter(reference__startswith="TOURNEE:").count(), 3)
        self.assertEqual(services.indicateurs([self.magasin])["argent_en_attente"], D("0"))
        # Journal : solde après chaque mouvement cohérent
        lignes = services.journal([self.magasin])
        self.assertEqual(lignes[0]["solde_apres"], D("68000"))
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
        self.declarer_frais_livraison(order)
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


class BoostAutomatiqueTests(ScenarioMixin, APITestCase):
    """Affectation AUTOMATIQUE des commandes aux boosts par période (§ demande) :

        boost du J-9 au J-6, 100 000 Ar — commandes A, B (J-9), C (J-8),
        D (J-7), E (J-6) concernées ; F (J-5) non ; G (J-10) non.

    Les dates sont relatives à aujourd'hui pour que le scénario reste
    valable quel que soit le jour d'exécution (les boosts ne couvrent
    jamais l'avenir : `date_fin_effective` ≤ aujourd'hui)."""

    def setUp(self):
        self.creer_scenario()
        self.client.force_authenticate(user=self.gerant)
        self.j = lambda n: self.aujourd_hui - timedelta(days=n)

    def boost(self, debut, fin, montant="100000", **extra):
        return MarketingCampaign.objects.create(
            magasin=self.magasin, nom=extra.pop("nom", "Boost Facebook"), montant=D(montant), date_debut=debut, date_fin=fin, **extra
        )

    def ids(self, boost, **kw):
        return set(services.commandes_du_boost(boost, **kw).values_list("id", flat=True))

    # 1-5. bornes ---------------------------------------------------------- #

    def test_bornes_de_la_periode(self):
        b = self.boost(self.j(9), self.j(6))
        avant = self.commande(jour=self.j(10))
        debut = self.commande(jour=self.j(9))
        pendant = self.commande(jour=self.j(8))
        fin = self.commande(jour=self.j(6))
        apres = self.commande(jour=self.j(5))
        concernees = self.ids(b)
        self.assertNotIn(avant.id, concernees)  # 1. avant le début
        self.assertIn(debut.id, concernees)  # 2. exactement au début
        self.assertIn(pendant.id, concernees)  # 3. pendant
        self.assertIn(fin.id, concernees)  # 4. exactement à la fin (inclusive)
        self.assertNotIn(apres.id, concernees)  # 5. après la fin

    def test_bornes_heure_locale(self):
        """Une commande à 00:00 le premier jour et à 23:59 le dernier jour
        (heure d'Antananarivo) est incluse : la comparaison se fait sur le
        jour LOCAL, pas sur l'instant UTC."""
        b = self.boost(self.j(3), self.j(2))
        tz = timezone.get_current_timezone()
        minuit = order_services.create_order(
            magasin=self.magasin, client_nom="C", telephone="+261341234567", livraison_zone=self.zone.code,
            items=[{"product_variant": self.variante, "quantite": 1}], created_by=self.gerant,
            date_commande=timezone.make_aware(timezone.datetime.combine(self.j(3), timezone.datetime.min.time()), tz),
        )
        tard = order_services.create_order(
            magasin=self.magasin, client_nom="C", telephone="+261341234567", livraison_zone=self.zone.code,
            items=[{"product_variant": self.variante, "quantite": 1}], created_by=self.gerant,
            date_commande=timezone.make_aware(timezone.datetime.combine(self.j(2), timezone.datetime.min.time().replace(hour=23, minute=59)), tz),
        )
        self.assertEqual(self.ids(b), {minuit.id, tard.id})

    # 6. boost en cours ---------------------------------------------------- #

    def test_boost_en_cours_jusqu_a_maintenant(self):
        b = self.boost(self.j(2), None)
        hier = self.commande(jour=self.j(1))
        aujourd_hui = self.commande()
        demain = self.commande(jour=self.aujourd_hui + timedelta(days=1))
        self.assertEqual(self.ids(b), {hier.id, aujourd_hui.id})
        self.assertNotIn(demain.id, self.ids(b))
        self.assertTrue(services.resume_boost(b)["periode_effective"]["en_cours"])

    # 7-8. recalcul automatique ------------------------------------------- #

    def test_modification_montant_recalcule(self):
        b = self.boost(self.j(3), self.j(1), montant="50000")
        vente = self.livrer(self.commande(jour=self.j(2)))
        r = VenteResultat.objects.get(order=vente)
        self.assertEqual(r.part_boost, D("50000"))
        res = self.client.patch(f"/api/orders/campaigns/{b.id}/", {"montant": 100000}, format="json")
        self.assertEqual(res.status_code, 200, res.data)
        r.refresh_from_db()
        self.assertEqual(r.part_boost, D("100000"))
        self.assertEqual(r.gain_reel, D("28000") - D("6000") - D("4000") - D("100000"))

    def test_modification_dates_recalcule_ancienne_et_nouvelle_periode(self):
        b = self.boost(self.j(5), self.j(4), montant="30000")
        dans_ancienne = self.livrer(self.commande(jour=self.j(5)))
        dans_nouvelle = self.livrer(self.commande(jour=self.j(2)))
        self.assertEqual(VenteResultat.objects.get(order=dans_ancienne).part_boost, D("30000"))
        self.assertEqual(VenteResultat.objects.get(order=dans_nouvelle).part_boost, D("0"))
        res = self.client.patch(f"/api/orders/campaigns/{b.id}/", {"date_debut": str(self.j(3)), "date_fin": str(self.j(1))}, format="json")
        self.assertEqual(res.status_code, 200, res.data)
        # La vente sortie de la période perd sa part, celle entrée la reçoit.
        self.assertEqual(VenteResultat.objects.get(order=dans_ancienne).part_boost, D("0"))
        self.assertEqual(VenteResultat.objects.get(order=dans_nouvelle).part_boost, D("30000"))

    # 9-10. plusieurs boosts ---------------------------------------------- #

    def test_campagnes_successives(self):
        a = self.boost(self.j(9), self.j(6), nom="A")
        b = self.boost(self.j(5), self.j(1), nom="B", montant="150000")
        dans_a = self.commande(jour=self.j(7))
        dans_b = self.commande(jour=self.j(3))
        self.assertEqual(self.ids(a), {dans_a.id})
        self.assertEqual(self.ids(b), {dans_b.id})

    def test_chevauchement_chaque_boost_sur_sa_periode(self):
        """Boost A J-8→J-3 et boost B J-5→J-1 : une vente du J-4 est concernée
        par les deux et supporte une part de CHACUN (règle documentée sur
        MarketingCampaign) ; les totaux du rapport la comptent une fois."""
        a = self.boost(self.j(8), self.j(3), nom="A", montant="10000")
        b = self.boost(self.j(5), self.j(1), nom="B", montant="20000")
        commune = self.livrer(self.commande(jour=self.j(4)))
        seulement_a = self.livrer(self.commande(jour=self.j(7)))
        self.assertEqual(self.ids(a), {commune.id, seulement_a.id})
        self.assertEqual(self.ids(b), {commune.id})
        # A : 10 000 / 2 articles = 5 000 ; B : 20 000 / 1 article = 20 000.
        self.assertEqual(VenteResultat.objects.get(order=commune).part_boost, D("25000"))
        self.assertEqual(VenteResultat.objects.get(order=seulement_a).part_boost, D("5000"))
        res = self.client.get(f"/api/orders/reports/marketing/?date_from={self.j(10)}&date_to={self.aujourd_hui}")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["totaux"]["commandes"], 2)  # dé-doublonné
        par_nom = {l["nom"]: l for l in res.data["campagnes"]}
        self.assertEqual(par_nom["A"]["commandes"], 2)
        self.assertEqual(par_nom["B"]["commandes"], 1)

    # 11-12. sans commande, désactivation / suppression -------------------- #

    def test_aucune_commande_pendant_la_campagne(self):
        b = self.boost(self.j(9), self.j(6))
        self.commande(jour=self.j(2))
        r = services.resume_boost(b)
        self.assertEqual(r["nb_commandes"], 0)
        self.assertIsNone(r["cout_par_commande"])
        self.assertEqual(services.cout_boost_par_article(b), (services.ZERO, 0))

    def test_desactivation_et_suppression_recalculent(self):
        b = self.boost(self.j(3), self.j(1), montant="30000")
        vente = self.livrer(self.commande(jour=self.j(2)))
        self.assertEqual(VenteResultat.objects.get(order=vente).part_boost, D("30000"))
        res = self.client.patch(f"/api/orders/campaigns/{b.id}/", {"actif": False}, format="json")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(VenteResultat.objects.get(order=vente).part_boost, D("0"))
        b.refresh_from_db()
        self.assertEqual(self.ids(b), set())  # boost inactif : plus rien de concerné
        res = self.client.patch(f"/api/orders/campaigns/{b.id}/", {"actif": True}, format="json")
        self.assertEqual(VenteResultat.objects.get(order=vente).part_boost, D("30000"))
        res = self.client.delete(f"/api/orders/campaigns/{b.id}/")
        self.assertEqual(res.status_code, 204)
        self.assertEqual(VenteResultat.objects.get(order=vente).part_boost, D("0"))

    # 13-14. Caisse et Rapports ------------------------------------------- #

    def test_montants_caisse(self):
        b = self.boost(self.j(3), self.j(1), montant="20000")
        self.livrer(self.commande(jour=self.j(2), quantite=2))
        # Une vente livrée SANS résultat de trésorerie (historique d'avant le
        # module) compte quand même dans la part de boost de la période, comme
        # sur la page Boost : 20 000 / 3 articles, période entière → 20 000.
        ancienne = self.livrer(self.commande(jour=self.j(2)))
        VenteResultat.objects.filter(order=ancienne).delete()
        annulee = self.commande(jour=self.j(2))
        order_services.cancel_order(order=annulee, user=self.gerant)
        res = self.client.get(f"/api/finance/dashboard/?date_from={self.j(3)}&date_to={self.j(1)}")
        self.assertEqual(res.status_code, 200)
        boost = next(x for x in res.data["boosts"] if x["id"] == b.id)
        self.assertEqual(boost["nb_commandes"], 2)  # l'annulée n'est pas concernée
        self.assertEqual(boost["nb_livrees"], 2)
        self.assertEqual(boost["articles_vendus"], 3)
        self.assertEqual(D(str(boost["cout_par_article"])), D("6666.67"))
        self.assertEqual(D(str(boost["cout_par_commande"])), D("10000"))
        self.assertEqual(D(str(boost["ca"])), D("81000"))  # 53 000 + 28 000
        # Gain réel de la période : part de boost = montant entier du boost
        # (période couverte), identique à la page Boost — pas 2 × 6 666,67.
        self.assertEqual(D(str(res.data["gain"]["part_boost"])), D("20000"))
        # Période plus courte que le boost : au prorata des articles livrés.
        res2 = self.client.get(f"/api/finance/dashboard/?date_from={self.j(2)}&date_to={self.j(2)}")
        self.assertEqual(D(str(res2.data["gain"]["part_boost"])), D("20000"))
        res3 = self.client.get(f"/api/finance/dashboard/?date_from={self.j(1)}&date_to={self.j(1)}")
        self.assertEqual(D(str(res3.data["gain"]["part_boost"])), D("0"))
        # Même résumé sur l'API des campagnes.
        res = self.client.get(f"/api/orders/campaigns/{b.id}/")
        self.assertEqual(res.data["nb_commandes"], 2)
        self.assertEqual(D(str(res.data["cout_par_commande"])), D("10000"))

    def test_montants_rapports(self):
        b = self.boost(self.j(9), self.j(6), montant="100000")
        for n in (9, 9, 8, 7, 6):
            self.livrer(self.commande(jour=self.j(n)))
        self.commande(jour=self.j(5))  # hors période
        res = self.client.get(f"/api/orders/reports/marketing/?date_from={self.j(10)}&date_to={self.aujourd_hui}")
        self.assertEqual(res.status_code, 200)
        ligne = next(l for l in res.data["campagnes"] if l["id"] == b.id)
        self.assertEqual(ligne["commandes"], 5)
        self.assertEqual(ligne["commandes_livrees"], 5)
        self.assertEqual(D(str(ligne["ca"])), D("28000") * 5)
        self.assertEqual(D(str(ligne["cout_par_commande"])), D("20000"))
        self.assertEqual(D(str(ligne["marge_produits"])), D("19000") * 5)
        self.assertEqual(res.data["totaux"]["commandes_sans_campagne"], 1)
        # Fenêtre plus courte que le boost : seules les commandes de la fenêtre.
        res = self.client.get(f"/api/orders/reports/marketing/?date_from={self.j(8)}&date_to={self.j(7)}")
        ligne = next(l for l in res.data["campagnes"] if l["id"] == b.id)
        self.assertEqual(ligne["commandes"], 2)

    def test_creation_commande_sans_champ_campagne(self):
        """L'API de création ignore `campagne` ; la commande expose ses
        campagnes calculées."""
        b = self.boost(self.j(1), None, nom="Auto")
        res = self.client.post(
            "/api/orders/",
            {
                "client_nom": "X", "telephone": "+261341234567", "livraison_zone": self.zone.code,
                "items": [{"product_variant": self.variante.id, "quantite": 1}], "campagne": 999999,
                "magasin_id": self.magasin.id,
            },
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(res.data["campagne_nom"], "Auto")
        self.assertEqual([c["id"] for c in res.data["campagnes"]], [b.id])


class MargeLivraisonRapportsTests(ScenarioMixin, APITestCase):
    """Rapports Dépenses / Livraisons : le coût réel des livraisons ne compte
    que les dépenses ACCEPTÉES des types marqués « frais de livraison »
    (LIVRAISON 3K / 4K / 5K…) — pas les repas, enveloppes, NAP (§ demande)."""

    def setUp(self):
        self.creer_scenario()
        self.client.force_authenticate(user=self.gerant)
        from orders.models import ExpenseType

        self.t_livraison = ExpenseType.objects.create(admin_profile=self.admin_profile, nom="LIVRAISON 3K", prix_unitaire=D("3000"), par_unite=True, frais_livraison=True)
        self.t_repas = ExpenseType.objects.create(admin_profile=self.admin_profile, nom="REPAS", prix_unitaire=D("5000"))
        self.livrer(self.commande())  # livraison facturée 3 000 au client
        for t, statut in ((self.t_livraison, "ACCEPTE"), (self.t_repas, "ACCEPTE"), (self.t_livraison, "EN_ATTENTE")):
            LivreurExpense.objects.create(
                magasin=self.magasin, livreur=self.livreur, type_depense=t, libelle=t.nom,
                prix_unitaire=t.prix_unitaire, quantite=1, statut=statut, date=self.aujourd_hui,
            )

    def test_marge_livraison_ne_compte_que_les_frais_de_livraison_acceptes(self):
        q = f"?date_from={self.aujourd_hui}&date_to={self.aujourd_hui}"
        res = self.client.get("/api/orders/reports/expenses/" + q)
        self.assertEqual(res.status_code, 200)
        liv = res.data["livraison"]
        # Frais de livraison acceptés : LIVRAISON 4K (course, via livrer) + LIVRAISON 3K
        # = 7 000 ; le repas et la dépense en attente sont exclus.
        self.assertEqual(D(str(liv["frais_factures_client"])), D("3000"))
        self.assertEqual(D(str(liv["cout_reel_livreurs"])), D("7000"))
        self.assertEqual(D(str(liv["marge_livraison"])), D("-4000"))
        # Le total des dépenses livreur, lui, garde le repas (12 000 acceptés).
        self.assertEqual(D(str(res.data["totaux"]["livreur"]["actuel"])), D("12000"))
        res = self.client.get("/api/orders/reports/deliveries/" + q)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(D(str(res.data["totaux"]["cout_total"])), D("7000"))
        self.assertEqual(D(str(res.data["totaux"]["marge_livraison"])), D("-4000"))
        # Même chiffre dans le gain réel de la caisse (§ demande) : 28 000 − 6 000 − 7 000.
        res = self.client.get(f"/api/finance/dashboard/?date_from={self.aujourd_hui}&date_to={self.aujourd_hui}")
        self.assertEqual(D(str(res.data["gain"]["frais_agence"])), D("7000"))
        self.assertEqual(D(str(res.data["gain"]["gain_reel"])), D("15000"))
        self.assertEqual(D(str(res.data["livraison"]["periode"]["agence"])), D("7000"))

    def test_migration_marque_les_types_livraison(self):
        """Le champ est exposé par l'API et modifiable dans Paramètres."""
        res = self.client.patch(f"/api/orders/expense-types/{self.t_repas.id}/", {"frais_livraison": True}, format="json")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertTrue(res.data["frais_livraison"])
class AvanceLivreurTests(ScenarioMixin, TestCase):
    """L'argent envoyé en avance par le livreur (Mvola…) n'est pas une
    dépense : il ne diminue pas le bénéfice, mais il diminue l'espèce qu'il
    doit encore remettre (§ demande)."""

    def setUp(self):
        self.creer_scenario()

    def _avance(self, montant, statut="CONFIRME"):
        from orders.models import AvanceLivreur

        return AvanceLivreur.objects.create(
            magasin=self.magasin, livreur=self.livreur, montant=D(montant), moyen="MVOLA",
            statut=statut, date=self.aujourd_hui,
        )

    def test_avance_deduite_de_la_remise(self):
        session = self.ouvrir_caisse()
        self.livrer(self.commande())  # 28 000 encaissés
        self._avance("20000")
        res = services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)
        self.assertEqual(res["brut"], D("28000"))
        self.assertEqual(res["avances"], D("20000"))
        self.assertEqual(res["net"], D("8000"))
        # La caisse ne reçoit que l'espèce réellement remise.
        self.assertEqual(services.solde_session(session), D("8000"))
        self.assertEqual(CaisseMovement.objects.filter(origine="AVANCE_LIVREUR").count(), 1)
        # Rejouer ne déduit pas deux fois la même avance.
        self.livrer(self.commande())
        res2 = services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)
        self.assertEqual(res2["avances"], D("0"))

    def test_avance_en_attente_ignoree(self):
        self.ouvrir_caisse()
        self.livrer(self.commande())
        self._avance("20000", statut="EN_ATTENTE")
        res = services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)
        self.assertEqual(res["avances"], D("0"))
        self.assertEqual(res["net"], D("28000"))

    def test_avance_nest_pas_une_depense(self):
        """Le rapport Dépenses ne doit pas grossir d'une avance : la sortie
        de caisse qui la déduit contre-passe une entrée de vente."""
        from orders.reporting import q_sorties_doublon
        from users.models import CaisseMovement as CM

        self.ouvrir_caisse()
        self.livrer(self.commande())
        self._avance("20000")
        services.remettre_encaissements(self.magasin, self.gerant, livreur_id=self.livreur.id)
        sorties = CM.objects.filter(movement_type="out")
        self.assertEqual(sorties.count(), 1)
        self.assertEqual(sorties.exclude(q_sorties_doublon()).count(), 0)
