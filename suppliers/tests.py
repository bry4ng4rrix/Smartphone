"""Tests du module Fournisseur (approvisionnements, paiements multi-devises,
frais d'importation, allocation, réception partielle, coût de revient et
son historique). Exécution : `python manage.py test suppliers`."""
from decimal import Decimal

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant, StockMovement
from users.models import AdminProfile, EmployerProfile, MagasinProfile

from .models import Supplier, SupplierOrder, VariantCostHistory
from .services import cout_revient_variante

User = get_user_model()
PWD = "MotDePasse123"


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
        self.ref_a = ProductReference.objects.create(type=typ, brand=marque, reference_name="Coque A", prix_achat=Decimal("0"), prix_vente=Decimal("150000"))
        self.ref_b = ProductReference.objects.create(type=typ, brand=marque, reference_name="Coque B", prix_achat=Decimal("0"), prix_vente=Decimal("80000"))
        self.var_a = ProductVariant.objects.create(product_reference=self.ref_a, couleur="Noir", stock_actuel=0)
        self.var_b = ProductVariant.objects.create(product_reference=self.ref_b, couleur="Noir", stock_actuel=0)
        self.fournisseur = Supplier.objects.create(admin_profile=self.profile, nom="Shenzhen Cases Co", pays="Chine", devise="USD")
        self.client.force_authenticate(user=self.admin)

    # --- helpers ---------------------------------------------------------- #

    def creer(self, **extra):
        """Cas de l'énoncé : A 100 × 20 USD, B 50 × 10 USD, taux 4 500 Ar."""
        data = {
            "supplier": self.fournisseur.id, "devise": "USD", "taux_change": "4500", "magasin_id": self.magasin.id,
            "description": "Import Chine",
            "lines": [
                {"product_variant": self.var_a.id, "quantite": 100, "prix_unitaire": "20"},
                {"product_variant": self.var_b.id, "quantite": 50, "prix_unitaire": "10"},
            ],
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

    def frais(self, oid, type_frais, montant, devise="MGA", taux=None):
        data = {"type_frais": type_frais, "montant": montant, "devise": devise}
        if taux:
            data["taux_change"] = taux
        r = self.client.post(self.url(oid, "fees/"), data, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        return r.data

    # --- cas 1 / 2 : paiements ------------------------------------------- #

    def test_cas1_un_fournisseur_un_paiement(self):
        o = self.creer()
        self.assertEqual(Decimal(o["valeur_achat_mga"]), Decimal("11250000.00"))  # 2 500 USD × 4 500
        self.assertEqual(o["statut"], "BROUILLON")
        o = self.payer(o["id"], "2500", type_paiement="SOLDE")
        self.assertEqual(o["statut"], "PAYE")
        self.assertEqual(Decimal(o["total_paye_mga"]), Decimal("11250000.00"))
        self.assertEqual(Decimal(o["reste_a_payer_mga"]), Decimal("0"))
        self.assertEqual(Decimal(o["pourcentage_paye"]), Decimal("100"))
        self.assertEqual(len(o["payments"]), 1)
        self.assertEqual(Decimal(o["payments"][0]["montant_mga"]), Decimal("11250000.00"))

    def test_cas2_plusieurs_paiements_historises(self):
        o = self.creer()
        o = self.payer(o["id"], "1000", date="2026-09-01", type_paiement="ACOMPTE", reference="TT-001")
        self.assertEqual(o["statut"], "PARTIELLEMENT_PAYE")
        self.assertEqual(Decimal(o["pourcentage_paye"]), Decimal("40.0"))
        o = self.payer(o["id"], "1000", date="2026-09-08", type_paiement="PARTIEL")
        self.assertEqual(len(o["payments"]), 2)
        self.assertEqual([p["date"] for p in o["payments"]], ["2026-09-01", "2026-09-08"])
        self.assertEqual(Decimal(o["total_paye_devise"]), Decimal("2000.00"))
        self.assertEqual(Decimal(o["total_paye_mga"]), Decimal("9000000.00"))
        self.assertEqual(Decimal(o["reste_a_payer_mga"]), Decimal("2250000.00"))
        self.assertEqual(o["statut"], "PARTIELLEMENT_PAYE")
        # Suppression d'un paiement -> retour à l'état précédent, historique cohérent
        r = self.client.delete(self.url(o["id"], f"payments/{o['payments'][0]['id']}/"))
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(len(r.data["payments"]), 1)

    # --- cas 3 : devises --------------------------------------------------- #

    def test_cas3_paiement_usd_et_frais_mga(self):
        o = self.creer()
        self.payer(o["id"], "2000")
        o = self.frais(o["id"], "DOUANE", "5000000")
        # 2 000 USD (9 000 000 Ar) payés ; achat 11 250 000 ; douane 5 000 000 Ar
        self.assertEqual(Decimal(o["total_frais_mga"]), Decimal("5000000.00"))
        self.assertEqual(Decimal(o["cout_total"]), Decimal("16250000.00"))
        self.assertEqual(o["fees"][0]["devise"], "MGA")
        self.assertEqual(Decimal(o["fees"][0]["taux_change"]), Decimal("1"))
        # Frais en USD converti avec son propre taux
        o = self.frais(o["id"], "TRANSPORT", "100", devise="USD", taux="4600")
        self.assertEqual(Decimal(o["fees"][1]["montant_mga"]), Decimal("460000.00"))
        self.assertEqual(Decimal(o["total_frais_mga"]), Decimal("5460000.00"))
        # Taux manquant pour une devise étrangère -> refus
        r = self.client.post(self.url(o["id"], "fees/"), {"type_frais": "TAXES", "montant": "10", "devise": "EUR"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertIn("taux_change", r.data)

    # --- cas 4 / 5 : plusieurs produits, allocation par valeur ------------ #

    def test_cas4_5_allocation_proportionnelle_a_la_valeur(self):
        o = self.creer()
        # 500 USD de frais (2 250 000 Ar) : A = 400 USD, B = 100 USD (exemple de l'énoncé)
        o = self.frais(o["id"], "TRANSPORT", "500", devise="USD", taux="4500")
        lignes = {l["reference_name"]: l for l in o["lines"]}
        self.assertEqual(Decimal(lignes["Coque A"]["frais_alloues_mga"]), Decimal("1800000.00"))  # 400 USD
        self.assertEqual(Decimal(lignes["Coque B"]["frais_alloues_mga"]), Decimal("450000.00"))  # 100 USD
        self.assertEqual(Decimal(lignes["Coque A"]["cout_unitaire_calcule"]), Decimal("108000.00"))  # 24 USD
        self.assertEqual(Decimal(lignes["Coque B"]["cout_unitaire_calcule"]), Decimal("54000.00"))  # 12 USD
        self.assertEqual(Decimal(o["cout_total"]), Decimal("13500000.00"))  # 3 000 USD
        self.assertEqual(Decimal(o["cout_unitaire"]), Decimal("90000.00"))  # 3 000 USD / 150 pièces

    def test_allocation_par_quantite_et_manuelle(self):
        o = self.creer(methode_allocation="QUANTITE")
        o = self.frais(o["id"], "DOUANE", "3000000")
        lignes = {l["reference_name"]: l for l in o["lines"]}
        self.assertEqual(Decimal(lignes["Coque A"]["frais_alloues_mga"]), Decimal("2000000.00"))  # 100/150
        self.assertEqual(Decimal(lignes["Coque B"]["frais_alloues_mga"]), Decimal("1000000.00"))  # 50/150
        # Manuel : le gérant fixe lui-même la répartition
        r = self.client.patch(self.url(o["id"]), {
            "methode_allocation": "MANUEL",
            "lines": [
                {"id": lignes["Coque A"]["id"], "product_variant": self.var_a.id, "quantite": 100, "allocation_manuelle_mga": "2500000"},
                {"id": lignes["Coque B"]["id"], "product_variant": self.var_b.id, "quantite": 50, "allocation_manuelle_mga": "500000"},
            ],
        }, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        lignes = {l["reference_name"]: l for l in r.data["lines"]}
        self.assertEqual(Decimal(lignes["Coque A"]["frais_alloues_mga"]), Decimal("2500000.00"))
        self.assertEqual(Decimal(lignes["Coque B"]["frais_alloues_mga"]), Decimal("500000.00"))

    # --- cas 6 / 7 : réception partielle puis complète -------------------- #

    def test_cas6_7_reception_partielle_puis_complete(self):
        o = self.creer()
        self.client.post(self.url(o["id"], "commander/"))
        self.client.post(self.url(o["id"], "preparer/"))
        r = self.client.post(self.url(o["id"], "expedier/"), {"transporteur": "DHL", "mode_transport": "AERIEN", "tracking": "DHL123", "lieu_depart": "Shenzhen"}, format="json")
        self.assertEqual(r.data["statut"], "EN_TRANSIT")
        r = self.client.post(self.url(o["id"], "arriver/"), {"date_arrivee": "2026-09-20"}, format="json")
        self.assertEqual(r.data["statut"], "ARRIVE")
        lignes = {l["reference_name"]: l for l in r.data["lines"]}
        # Réception partielle : 60 A sur 100, rien pour B
        r = self.client.post(self.url(o["id"], "receive/"), {"lines": [{"line_id": lignes["Coque A"]["id"], "quantite_recue": 60}]}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["statut"], "PARTIELLEMENT_RECU")
        self.assertEqual(r.data["total_recu"], 60)
        self.var_a.refresh_from_db()
        self.assertEqual(self.var_a.stock_actuel, 60)
        self.assertEqual(StockMovement.objects.filter(product_variant=self.var_a, origine="FOURNISSEUR", type="ENTREE").count(), 1)
        # Trop : refus
        r = self.client.post(self.url(o["id"], "receive/"), {"lines": [{"line_id": lignes["Coque A"]["id"], "quantite_recue": 50}]}, format="json")
        self.assertEqual(r.status_code, 400)
        # Le reste, sans détail = tout ce qui manque
        r = self.client.post(self.url(o["id"], "receive/"), {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["statut"], "RECU")
        self.assertEqual(r.data["total_recu"], 150)
        self.var_a.refresh_from_db()
        self.var_b.refresh_from_db()
        self.assertEqual((self.var_a.stock_actuel, self.var_b.stock_actuel), (100, 50))
        self.assertIsNotNone(r.data["received_at"])
        # Une commande reçue ne se reçoit pas deux fois
        self.assertEqual(self.client.post(self.url(o["id"], "receive/"), {}, format="json").status_code, 400)

    def test_reception_partielle_recalcule_sur_la_quantite_recue(self):
        o = self.creer()
        o = self.frais(o["id"], "DOUANE", "1500000")
        lignes = {l["reference_name"]: l for l in o["lines"]}
        r = self.client.post(self.url(o["id"], "receive/"), {"lines": [
            {"line_id": lignes["Coque A"]["id"], "quantite_recue": 50},
            {"line_id": lignes["Coque B"]["id"], "quantite_recue": 50},
        ]}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        # Valeur d'achat sur ce qui est arrivé : 50×20 + 50×10 = 1 500 USD = 6 750 000 Ar ; frais 1 500 000 Ar
        self.assertEqual(Decimal(r.data["valeur_achat_mga"]), Decimal("6750000.00"))
        self.assertEqual(Decimal(r.data["cout_total"]), Decimal("8250000.00"))
        self.assertEqual(r.data["total_qty"], 100)

    # --- cas 8 : frais ajoutés après l'arrivée ---------------------------- #

    def test_cas8_frais_apres_arrivee(self):
        o = self.creer()
        self.client.post(self.url(o["id"], "arriver/"), {}, format="json")
        r = self.client.post(self.url(o["id"], "receive/"), {}, format="json")
        self.assertEqual(Decimal(r.data["total_frais_mga"]), Decimal("0"))
        o = self.frais(o["id"], "DOUANE", "5000000")
        o = self.frais(o["id"], "TRANSPORT_LOCAL", "200000")
        self.assertEqual(Decimal(o["total_frais_mga"]), Decimal("5200000.00"))
        self.assertEqual(Decimal(o["cout_total"]), Decimal("16450000.00"))
        types = {f["type"]: Decimal(f["montant_mga"]) for f in o["frais_par_type"]}
        self.assertEqual(types, {"DOUANE": Decimal("5000000.00"), "TRANSPORT_LOCAL": Decimal("200000.00")})

    # --- cas 9 / 10 : coût de revient par variante et historique ---------- #

    def test_cas9_10_finalisation_et_historique(self):
        o = self.creer()
        self.frais(o["id"], "TRANSPORT", "500", devise="USD", taux="4500")
        self.client.post(self.url(o["id"], "receive/"), {}, format="json")
        # Pas finalisable tant que… si : reçu. Finalisation avec mise à jour du prix d'achat.
        r = self.client.post(self.url(o["id"], "finaliser/"), {"mettre_a_jour_prix_achat": True}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["statut"], "COUT_FINALISE")
        self.ref_a.refresh_from_db()
        self.ref_b.refresh_from_db()
        self.assertEqual(self.ref_a.prix_achat, Decimal("108000.00"))
        self.assertEqual(self.ref_b.prix_achat, Decimal("54000.00"))
        hist_a = VariantCostHistory.objects.filter(product_variant=self.var_a)
        self.assertEqual(hist_a.count(), 1)
        self.assertEqual(hist_a.first().cout_revient_unitaire_mga, Decimal("108000.00"))
        # Finalisé = figé
        self.assertEqual(self.client.post(self.url(o["id"], "fees/"), {"type_frais": "AUTRE", "montant": "1", "devise": "MGA"}, format="json").status_code, 400)
        self.assertEqual(self.client.post(self.url(o["id"], "finaliser/"), {}, format="json").status_code, 400)

        # Deuxième importation du même produit, moins chère -> nouveau coût actuel, historique conservé
        o2 = self.creer(lines=[{"product_variant": self.var_a.id, "quantite": 100, "prix_unitaire": "15"}], taux_change="4200")
        self.client.post(self.url(o2["id"], "receive/"), {}, format="json")
        r = self.client.post(self.url(o2["id"], "finaliser/"), {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        info = cout_revient_variante(self.var_a)
        self.assertEqual(info["dernier"], Decimal("63000.00"))  # 15 × 4 200
        self.assertEqual(len(info["historique"]), 2)
        self.assertEqual(info["moyen_pondere"], Decimal("85500.00"))  # (108 000×100 + 63 000×100) / 200
        r = self.client.get(f"/api/suppliers/cost-history/?variant={self.var_a.id}")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(Decimal(r.data["cout_actuel_mga"]), Decimal("63000.00"))
        self.assertEqual(Decimal(r.data["cout_moyen_pondere_mga"]), Decimal("85500.00"))
        self.assertEqual([h["numero"] for h in r.data["historique"]], [o2["numero"], o["numero"]])
        self.ref_a.refresh_from_db()
        self.assertEqual(self.ref_a.prix_achat, Decimal("63000.00"))

    def test_finaliser_exige_la_reception(self):
        o = self.creer()
        r = self.client.post(self.url(o["id"], "finaliser/"), {}, format="json")
        self.assertEqual(r.status_code, 400)

    # --- fiche fournisseur, KPI, permissions, compatibilité ---------------- #

    def test_fiche_fournisseur_et_kpis(self):
        o = self.creer()
        self.payer(o["id"], "1000")
        self.frais(o["id"], "DOUANE", "5000000")
        r = self.client.get("/api/suppliers/suppliers/")
        self.assertEqual(r.status_code, 200)
        f = r.data[0]
        self.assertEqual(f["nb_approvisionnements"], 1)
        self.assertEqual(Decimal(f["total_achats_mga"]), Decimal("11250000.00"))
        self.assertEqual(Decimal(f["total_paye_mga"]), Decimal("4500000.00"))
        self.assertEqual(Decimal(f["reste_a_payer_mga"]), Decimal("6750000.00"))
        self.assertEqual(f["dernier_approvisionnement"]["numero"], o["numero"])
        r = self.client.get(f"/api/suppliers/suppliers/{self.fournisseur.id}/")
        self.assertEqual(len(r.data["approvisionnements"]), 1)
        r = self.client.get("/api/suppliers/orders/kpis/")
        self.assertEqual(r.data["nb_fournisseurs"], 1)
        self.assertEqual(r.data["en_cours"], 1)
        self.assertEqual(Decimal(r.data["reste_a_payer_mga"]), Decimal("6750000.00"))
        self.assertEqual(Decimal(r.data["total_frais_mga"]), Decimal("5000000.00"))
        # CRUD fournisseur
        r = self.client.post("/api/suppliers/suppliers/", {"nom": "Guangzhou Tech", "pays": "Chine", "email": "gz@ex.com"}, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        r = self.client.patch(f"/api/suppliers/suppliers/{r.data['id']}/", {"telephone": "+86 10"}, format="json")
        self.assertEqual(r.status_code, 200)
        # Un fournisseur utilisé est désactivé, pas supprimé
        r = self.client.delete(f"/api/suppliers/suppliers/{self.fournisseur.id}/")
        self.assertEqual(r.status_code, 204)
        self.fournisseur.refresh_from_db()
        self.assertFalse(self.fournisseur.actif)

    def test_permissions_livreur_refuse(self):
        self.client.force_authenticate(user=self.livreur)
        for url in ("/api/suppliers/orders/", "/api/suppliers/suppliers/", "/api/suppliers/orders/kpis/", "/api/suppliers/cost-history/"):
            self.assertEqual(self.client.get(url).status_code, 403, url)

    def test_compatibilite_premiere_version(self):
        """Ancien payload (montants MGA globaux, lignes sans prix) puis
        réception directe : même coût unitaire qu'avant."""
        r = self.client.post("/api/suppliers/orders/", {
            "magasin_id": self.magasin.id, "description": "ancien", "prix_fournisseur": "1000000", "fret_import": "200000", "douane": "300000",
            "lines": [{"product_variant": self.var_a.id, "quantite": 10}, {"product_variant": self.var_b.id, "quantite": 5}],
        }, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(Decimal(r.data["cout_total"]), Decimal("1500000.00"))
        self.assertEqual(Decimal(r.data["cout_unitaire"]), Decimal("100000.00"))
        for l in r.data["lines"]:
            self.assertEqual(Decimal(l["cout_unitaire_calcule"]), Decimal("100000.00"))
        r = self.client.post(f"/api/suppliers/orders/{r.data['id']}/receive/")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.data["statut"], "RECU")
        self.var_a.refresh_from_db()
        self.assertEqual(self.var_a.stock_actuel, 10)
