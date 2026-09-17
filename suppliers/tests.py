"""Module Fournisseur — approvisionnements (1 produit, N paiements, 1
expédition, Frais + Douane, coût total, coût unitaire).

Scénario obligatoire (§ 21) :

    Produit A, 100 pièces
    Paiement 1 : 1 000 USD × 4 500 = 4 500 000 Ar
    Paiement 2 : 1 000 USD × 4 600 = 4 600 000 Ar
    Total fournisseur : 9 100 000 Ar
    Frais + Douane : 5 000 000 Ar
    Coût total : 14 100 000 Ar
    Coût unitaire : 14 100 000 / 100 = 141 000 Ar

Lancer : python manage.py test suppliers
"""
from decimal import Decimal as D

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant, StockMovement
from users.models import AdminProfile, CaisseMovement, CaisseSession, EmployerProfile, MagasinProfile

from .models import Supplier, SupplierOrder, SupplierPayment

User = get_user_model()
PWD = "Password123!"


class FournisseurTestCase(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(email="owner@test.com", password=PWD, role="admin", is_confirmed=True, full_name="Owner")
        self.profile = AdminProfile.objects.create(user=self.admin, company_name="Boutique Demo")
        self.magasin = MagasinProfile.objects.create(admin=self.admin, shop_name="Boutique Centre")
        self.livreur = User.objects.create_user(email="liv@test.com", password=PWD, role="employer", is_confirmed=True, full_name="Liv")
        EmployerProfile.objects.create(user=self.livreur, magasin=self.magasin, admin=self.admin, commande_role="LIVREUR")
        cat = ProductCategory.objects.create(magasin=self.magasin, nom="Coques", ordre=1)
        typ = ProductType.objects.create(category=cat, nom="iPhone")
        marque = Brand.objects.create(magasin=self.magasin, nom="Apple")
        self.ref_a = ProductReference.objects.create(type=typ, brand=marque, reference_name="Produit A", prix_achat=D("0"), prix_vente=D("200000"))
        self.ref_b = ProductReference.objects.create(type=typ, brand=marque, reference_name="Produit B", prix_achat=D("0"), prix_vente=D("80000"))
        self.var_a = ProductVariant.objects.create(product_reference=self.ref_a, couleur="Noir", stock_actuel=0)
        self.var_b = ProductVariant.objects.create(product_reference=self.ref_b, couleur="Noir", stock_actuel=0)
        self.fournisseur = Supplier.objects.create(admin_profile=self.profile, nom="Fournisseur Chine A", pays="Chine", devise="USD")
        self.client.force_authenticate(user=self.admin)

    # --- helpers ---------------------------------------------------------- #

    def creer(self, **extra):
        data = {
            "supplier": self.fournisseur.id, "product_variant": self.var_a.id, "quantite": 100,
            "devise": "USD", "montant_prevu": "2000", "magasin_id": self.magasin.id, "description": "Envoi #001",
        }
        data.update(extra)
        r = self.client.post("/api/suppliers/orders/", data, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        return r.data

    def url(self, oid, suffix=""):
        return f"/api/suppliers/orders/{oid}/{suffix}"

    def payer(self, oid, montant, devise="USD", taux="4500", **extra):
        r = self.client.post(self.url(oid, "payments/"), {"montant": montant, "devise": devise, "taux_change": taux, **extra}, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        return r.data

    def post(self, oid, action, data=None):
        r = self.client.post(self.url(oid, action + "/"), data or {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        return r.data

    # --- § 21 : scénario de référence ------------------------------------- #

    def test_scenario_reference_complet(self):
        o = self.creer()
        self.assertEqual(o["statut"], "BROUILLON")
        self.assertEqual(o["supplier_nom"], "Fournisseur Chine A")
        self.assertEqual(o["produit"]["reference_name"], "Produit A")
        self.assertEqual(o["quantite"], 100)

        # Paiement 1 — 01/09, taux 4 500
        o = self.payer(o["id"], "1000", taux="4500", date="2026-09-01")
        self.assertEqual(o["statut"], "ACOMPTE_PAYE")
        self.assertEqual(D(o["total_paiements_mga"]), D("4500000"))
        self.assertEqual(D(o["total_paye_devise"]), D("1000"))
        self.assertEqual(D(o["reste_a_payer_devise"]), D("1000"))

        # Préparation par le fournisseur
        o = self.post(o["id"], "preparer")
        self.assertEqual(o["statut"], "PREPARATION")

        # Paiement 2 — 08/09, taux 4 600 (indépendant du premier)
        o = self.payer(o["id"], "1000", taux="4600", date="2026-09-08")
        self.assertEqual(o["statut"], "PAYE")
        self.assertEqual(len(o["payments"]), 2)
        self.assertEqual([D(p["montant_mga"]) for p in o["payments"]], [D("4500000"), D("4600000")])
        self.assertEqual([D(p["taux_change"]) for p in o["payments"]], [D("4500"), D("4600")])  # taux historiques conservés
        self.assertEqual(D(o["total_paiements_mga"]), D("9100000"))
        self.assertEqual(D(o["reste_a_payer_devise"]), D("0"))

        # Départ Chine → transit → arrivée Madagascar
        o = self.post(o["id"], "expedier", {"date_expedition": "2026-09-10", "transporteur": "DHL", "mode_transport": "AERIEN", "tracking": "TRK123", "numero_colis": "COLIS-1"})
        self.assertEqual(o["statut"], "EXPEDIE")
        self.assertEqual(o["tracking"], "TRK123")
        o = self.post(o["id"], "transit")
        self.assertEqual(o["statut"], "EN_TRANSIT")
        o = self.post(o["id"], "arriver", {"date_arrivee": "2026-09-20"})
        self.assertEqual(o["statut"], "ARRIVE")
        self.assertEqual(o["date_arrivee"], "2026-09-20")

        # Frais + Douane : UN seul montant
        o = self.post(o["id"], "frais-douane", {"frais_douane_mga": "5000000"})
        self.assertEqual(D(o["frais_douane_mga"]), D("5000000"))
        self.assertEqual(D(o["cout_total_mga"]), D("14100000"))
        self.assertEqual(D(o["cout_unitaire_mga"]), D("141000"))
        self.assertEqual(D(o["marge_unitaire"]), D("200000") - D("141000"))

        # Finalisation → coût figé + réception dans le stock
        o = self.post(o["id"], "finaliser")
        self.assertEqual(o["statut"], "COUT_FINALISE")
        self.assertEqual(o["quantite_recue"], 100)
        self.var_a.refresh_from_db()
        self.ref_a.refresh_from_db()
        self.assertEqual(self.var_a.stock_actuel, 100)
        self.assertEqual(self.ref_a.prix_achat, D("141000"))
        mvt = StockMovement.objects.get(origine="FOURNISSEUR", reference=o["numero"])
        self.assertEqual(mvt.quantite, 100)
        self.assertIn("141000", mvt.note)

        # Un approvisionnement finalisé ne bouge plus.
        r = self.client.post(self.url(o["id"], "payments/"), {"montant": 10, "devise": "USD", "taux_change": 4700}, format="json")
        self.assertEqual(r.status_code, 400)

    # --- règles ----------------------------------------------------------- #

    def test_un_seul_produit_par_approvisionnement(self):
        """Pas de lignes : le second produit = un second approvisionnement."""
        r = self.client.post("/api/suppliers/orders/", {"product_variant": self.var_a.id, "quantite": 0, "magasin_id": self.magasin.id}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/suppliers/orders/", {"lines": [{"product_variant": self.var_a.id, "quantite": 1}], "magasin_id": self.magasin.id}, format="json")
        self.assertEqual(r.status_code, 400)
        a = self.creer()
        b = self.creer(product_variant=self.var_b.id, quantite=50)
        self.assertNotEqual(a["numero"], b["numero"])
        self.assertEqual(b["produit"]["reference_name"], "Produit B")

    def test_historique_des_envois_independants(self):
        """Le même produit acheté deux fois garde deux coûts distincts (§ 12)."""
        def finaliser(o, montant, taux, frais):
            self.payer(o["id"], montant, taux=taux)
            self.post(o["id"], "expedier")
            self.post(o["id"], "arriver", {"frais_douane_mga": frais})
            return self.post(o["id"], "finaliser")

        premier = finaliser(self.creer(quantite=100), "2000", "4550", "5000000")   # 9 100 000 + 5 000 000 → 141 000
        second = finaliser(self.creer(quantite=200), "5000", "4600", "8000000")   # 23 000 000 + 8 000 000 → 155 000
        self.assertEqual(D(premier["cout_unitaire_mga"]), D("141000"))
        self.assertEqual(D(second["cout_unitaire_mga"]), D("155000"))
        premier_db = SupplierOrder.objects.get(pk=premier["id"])
        self.assertEqual(premier_db.cout_unitaire_mga, D("141000"))  # pas écrasé par le second
        r = self.client.get(f"/api/suppliers/cost-history/?variant={self.var_a.id}")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(D(str(r.data["cout_actuel_mga"])), D("155000"))
        self.assertEqual(len(r.data["historique"]), 2)
        # Coût moyen pondéré : (14 100 000 + 31 000 000) / 300
        self.assertEqual(D(str(r.data["cout_moyen_pondere_mga"])), D("150333.33"))
        self.var_a.refresh_from_db()
        self.assertEqual(self.var_a.stock_actuel, 300)
        # Prix d'achat de référence : moyenne pondérée (100 × 141 000 + 200 × 155 000) / 300
        self.ref_a.refresh_from_db()
        self.assertEqual(self.ref_a.prix_achat, D("150333.33"))

    def test_statut_paiement_derive(self):
        o = self.creer(montant_prevu="2000")
        o = self.payer(o["id"], "500")
        self.assertEqual(o["statut"], "ACOMPTE_PAYE")
        o = self.payer(o["id"], "1500")
        self.assertEqual(o["statut"], "PAYE")
        # Suppression d'un paiement → on redescend.
        pid = o["payments"][1]["id"]
        r = self.client.delete(self.url(o["id"], f"payments/{pid}/"))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["statut"], "ACOMPTE_PAYE")
        self.assertEqual(D(r.data["total_paiements_mga"]), D("2250000"))

    def test_taux_requis_hors_mga_et_mga_sans_taux(self):
        o = self.creer()
        r = self.client.post(self.url(o["id"], "payments/"), {"montant": 100, "devise": "USD"}, format="json")
        self.assertEqual(r.status_code, 400)
        o = self.payer(o["id"], "450000", devise="MGA", taux="1")
        self.assertEqual(D(o["payments"][0]["montant_mga"]), D("450000"))
        self.assertEqual(D(o["payments"][0]["taux_change"]), D("1"))

    def test_finalisation_exige_arrivee_et_reception_partielle(self):
        o = self.creer(quantite=100)
        self.payer(o["id"], "1000")
        r = self.client.post(self.url(o["id"], "finaliser/"), {}, format="json")
        self.assertEqual(r.status_code, 400)  # pas encore arrivé
        self.post(o["id"], "expedier")
        self.post(o["id"], "arriver", {"frais_douane_mga": "500000"})
        o = self.post(o["id"], "finaliser", {"quantite_recue": 90, "mettre_a_jour_prix_achat": False})
        self.assertEqual(o["quantite_recue"], 90)
        self.var_a.refresh_from_db()
        self.ref_a.refresh_from_db()
        self.assertEqual(self.var_a.stock_actuel, 90)
        self.assertEqual(self.ref_a.prix_achat, D("0"))  # non mis à jour
        # Coût unitaire toujours sur la quantité commandée : (4 500 000 + 500 000) / 100
        self.assertEqual(D(o["cout_unitaire_mga"]), D("50000"))

    def test_sorties_de_caisse_identifiables(self):
        """Paiement et Frais + Douane peuvent être enregistrés en caisse
        (origine ACHAT_STOCK, référence APPRO:<n°>:…), une seule fois."""
        session = CaisseSession.objects.create(magasin=self.magasin, opened_by=self.admin, opening_balance=D("20000000"))
        o = self.creer()
        o = self.payer(o["id"], "1000", en_caisse=True)
        pid = o["payments"][0]["id"]
        mvt = CaisseMovement.objects.get(reference=f"APPRO:{o['numero']}:P{pid}")
        self.assertEqual((mvt.movement_type, mvt.origine, mvt.amount), ("out", "ACHAT_STOCK", D("4500000")))
        self.assertEqual(o["caisse"]["paiements"], [pid])
        self.post(o["id"], "expedier")
        self.post(o["id"], "arriver")
        o = self.post(o["id"], "frais-douane", {"frais_douane_mga": "5000000", "en_caisse": True})
        self.post(o["id"], "frais-douane", {"frais_douane_mga": "5000000", "en_caisse": True})  # idempotent
        self.assertEqual(CaisseMovement.objects.filter(reference=f"APPRO:{o['numero']}:FRAIS").count(), 1)
        self.assertTrue(o["caisse"]["frais_douane"])
        self.assertEqual(CaisseMovement.objects.filter(session=session).count(), 2)

    def test_caisse_fermee_refusee(self):
        o = self.creer()
        r = self.client.post(self.url(o["id"], "payments/"), {"montant": 10, "devise": "USD", "taux_change": 4500, "en_caisse": True}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("en_caisse", r.data)

    def test_fiche_fournisseur_et_kpis(self):
        o = self.creer()
        self.payer(o["id"], "1000")
        r = self.client.get(f"/api/suppliers/suppliers/{self.fournisseur.id}/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["nb_approvisionnements"], 1)
        self.assertEqual(D(r.data["total_paye_mga"]), D("4500000"))
        self.assertEqual(len(r.data["approvisionnements"]), 1)
        r = self.client.get("/api/suppliers/orders/kpis/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["nb_approvisionnements"], 1)
        self.assertEqual(D(r.data["total_paye_mga"]), D("4500000"))

    def test_suppression_limitee_au_brouillon(self):
        o = self.creer()
        self.assertEqual(self.client.delete(self.url(o["id"])).status_code, 204)
        o = self.creer()
        self.payer(o["id"], "1")
        self.assertEqual(self.client.delete(self.url(o["id"])).status_code, 405)

    def test_permissions_livreur(self):
        self.client.force_authenticate(user=self.livreur)
        self.assertEqual(self.client.get("/api/suppliers/orders/").status_code, 403)
        self.assertEqual(self.client.get("/api/suppliers/suppliers/").status_code, 403)

    def test_autres_modules_stock_et_tableau_de_bord(self):
        """Le tableau de bord et le KPI bénéfice lisent le nouveau coût."""
        o = self.creer(quantite=10)
        self.payer(o["id"], "100")  # 450 000
        self.post(o["id"], "expedier")
        self.post(o["id"], "arriver", {"frais_douane_mga": "50000"})
        self.post(o["id"], "finaliser")
        r = self.client.get(f"/api/orders/dashboard/?magasin_id={self.magasin.id}")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(SupplierOrder.objects.get(pk=o["id"]).cout_total_mga, D("500000"))
        self.assertEqual(StockMovement.objects.filter(origine="FOURNISSEUR").count(), 1)
        self.assertEqual(SupplierPayment.objects.count(), 1)
