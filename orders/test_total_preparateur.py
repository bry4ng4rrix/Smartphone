"""Le préparateur reçoit le total à payer, sans gagner d'accès au coût."""
from decimal import Decimal

from django.test import TestCase

from orders.serializers import (
    OrderGerantSerializer,
    OrderLivreurSerializer,
    OrderPreparateurSerializer,
)


class TotalPreparateurTests(TestCase):
    def test_total_a_payer_expose_au_preparateur(self):
        champs = OrderPreparateurSerializer().fields
        self.assertIn("total_a_payer", champs, "le préparateur doit voir le total")

    def test_frais_livraison_restent_hors_de_sa_fiche(self):
        """L'encaissement reste l'affaire du livreur : pas de frais ici."""
        self.assertNotIn("frais_livraison", OrderPreparateurSerializer().fields)

    def test_aucune_donnee_de_cout_ni_de_marge(self):
        """Garde-fou de la règle métier : le préparateur ne voit ni coût ni marge."""
        champs = set(OrderPreparateurSerializer().fields)
        interdits = {"prix_achat", "marge", "cout", "benefice", "total_achat"}
        self.assertEqual(champs & interdits, set())

    def test_les_autres_roles_sont_inchanges(self):
        for serializer in (OrderGerantSerializer, OrderLivreurSerializer):
            with self.subTest(serializer=serializer.__name__):
                champs = serializer().fields
                self.assertIn("total_a_payer", champs)
                self.assertIn("frais_livraison", champs)
