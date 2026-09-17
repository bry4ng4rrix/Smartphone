"""Page LIVREUR — VISIBILITÉ ≠ AUTORISATION (§ demande).

* Visibilité : `GET /api/orders/` renvoie au livreur TOUTES ses commandes
  actives assignées (Nouvelle / En préparation / Prête / En livraison),
  quelle que soit la date de livraison — aujourd'hui, demain, J+3, en
  retard. Exclues : Livrée, Retour, Annulée, retrait sur place.
* Autorisation : Récupérer / Livré / Retour ne sont acceptés par le serveur
  qu'à partir de minuit le jour de livraison (heure de Madagascar) — l'heure
  exacte de livraison ne bloque pas.

Lancer : python manage.py test orders
"""
from datetime import timedelta
from unittest import mock

from django.utils import timezone
from rest_framework.test import APITestCase

from finance.tests import ScenarioMixin
from orders import services as order_services


class PageLivreurTests(ScenarioMixin, APITestCase):
    def setUp(self):
        self.creer_scenario()
        self.client.force_authenticate(user=self.livreur)
        self.tz = timezone.get_current_timezone()

    def a(self, jour, heure):
        """Instant local Antananarivo `jour` à `heure`h."""
        return timezone.make_aware(timezone.datetime.combine(jour, timezone.datetime.min.time().replace(hour=heure)), self.tz)

    def assignee(self, jour, heure=10, statut="PRETE", zone=None):
        """Commande planifiée à `jour` `heure`h, assignée à self.livreur et
        amenée jusqu'à `statut` par le gérant (qui n'est pas soumis au jour J)."""
        order = order_services.create_order(
            magasin=self.magasin, client_nom="Client", telephone="+261341234567", livraison_zone=zone or self.zone.code,
            items=[{"product_variant": self.variante, "quantite": 1}], created_by=self.gerant, date_commande=self.a(jour, heure),
        )
        if statut == "NOUVELLE":
            order.livreur = self.livreur
            order.save(update_fields=["livreur"])
            return order
        order = order_services.change_order_status(order=order, new_status="EN_PREPARATION", user=self.gerant, preparateur_id=self.preparateur.id)
        if statut == "EN_PREPARATION":
            order.livreur = self.livreur
            order.save(update_fields=["livreur"])
            return order
        order = order_services.change_order_status(order=order, new_status="PRETE", user=self.gerant)
        if zone == "RECUPERATION":
            return order
        order.livreur = self.livreur
        order.save(update_fields=["livreur"])
        if statut == "PRETE":
            return order
        order = order_services.change_order_status(order=order, new_status="EN_LIVRAISON", user=self.gerant, livreur_id=self.livreur.id)
        if statut == "EN_LIVRAISON":
            return order
        return order_services.change_order_status(order=order, new_status=statut, user=self.gerant)

    def ids(self, **params):
        res = self.client.get("/api/orders/", params)
        self.assertEqual(res.status_code, 200, res.content[:200])
        return [o["id"] for o in res.data]

    # -- visibilité -------------------------------------------------------- #

    def test_toutes_les_commandes_actives_sont_visibles_quelle_que_soit_la_date(self):
        j = self.aujourd_hui
        retard = self.assignee(j - timedelta(days=1), 14)  # scénario 5
        aujourdhui = self.assignee(j, 10)  # scénario 1
        demain = self.assignee(j + timedelta(days=1), 9)  # scénario 2
        j3 = self.assignee(j + timedelta(days=3), 11)  # scénario 4 / 12
        nouvelle = self.assignee(j + timedelta(days=2), 8, statut="NOUVELLE")
        en_prep = self.assignee(j + timedelta(days=2), 9, statut="EN_PREPARATION")
        visibles = set(self.ids())
        for o in (retard, aujourdhui, demain, j3, nouvelle, en_prep):
            self.assertIn(o.id, visibles)

    def test_commandes_terminees_et_retraits_exclus(self):
        j = self.aujourd_hui
        livree = self.assignee(j, 9, statut="LIVRE")  # scénario 6
        retour = self.assignee(j, 10, statut="RETOUR")
        annulee = self.assignee(j, 11)
        order_services.cancel_order(order=annulee, user=self.gerant)  # scénario 7
        retrait = self.assignee(j, 12, zone="RECUPERATION")  # scénario 8
        active = self.assignee(j, 13)
        visibles = set(self.ids())
        self.assertEqual(visibles, {active.id})
        for o in (livree, retour, annulee, retrait):
            self.assertNotIn(o.id, visibles)
        # … mais elles restent dans l'historique personnel.
        historique = set(self.ids(historique=1))
        self.assertTrue({livree.id, retour.id, annulee.id} <= historique)

    def test_filtre_date_precise_serveur(self):
        j = self.aujourd_hui
        self.assignee(j, 10)
        demain = self.assignee(j + timedelta(days=1), 9)
        d = str(j + timedelta(days=1))
        self.assertEqual(self.ids(date_debut=d, date_fin=d), [demain.id])

    def test_ordre_chronologique_possible_cote_client(self):
        """Scénario 9 : le serveur fournit `date_commande` ; trié par cette
        date, l'ordre est exactement 17/09 09:00 → 17/09 14:00 → 18/09 08:00
        → 18/09 15:00 → 20/09 10:00."""
        j = self.aujourd_hui
        attendu = [
            self.assignee(j, 9).id,
            self.assignee(j, 14).id,
            self.assignee(j + timedelta(days=1), 8).id,
            self.assignee(j + timedelta(days=1), 15).id,
            self.assignee(j + timedelta(days=3), 10).id,
        ]
        res = self.client.get("/api/orders/")
        tries = sorted(res.data, key=lambda o: o["date_commande"])
        self.assertEqual([o["id"] for o in tries], attendu)

    # -- autorisation ------------------------------------------------------ #

    def test_actions_refusees_avant_minuit_le_jour_j(self):
        """Scénarios 2 et 3 : commande prévue demain 09:00 — refusée la
        veille (même à 23:59), acceptée dès 00:00 le jour J bien avant 09:00."""
        demain = self.aujourd_hui + timedelta(days=1)
        order = self.assignee(demain, 9)
        veille_2359 = self.a(self.aujourd_hui, 23).replace(minute=59)
        with mock.patch("django.utils.timezone.now", return_value=veille_2359):
            res = self.client.post(f"/api/orders/{order.id}/status/", {"statut": "EN_LIVRAISON"}, format="json")
            self.assertEqual(res.status_code, 403, res.content[:200])
            self.assertIn("possible à partir du", str(res.data))
        jourj_0001 = self.a(demain, 0).replace(minute=1)
        with mock.patch("django.utils.timezone.now", return_value=jourj_0001):
            res = self.client.post(f"/api/orders/{order.id}/status/", {"statut": "EN_LIVRAISON"}, format="json")
            self.assertEqual(res.status_code, 200, res.content[:200])
            self.assertEqual(res.data["statut_courant"], "EN_LIVRAISON")
