"""Reprise de l'historique : calcule le résultat (gain réel) des commandes
déjà livrées avant l'activation du module trésorerie.

    python manage.py finance_backfill [--depuis YYYY-MM-DD]

Ne crée ni encaissement ni versement d'épargne (l'argent de ces ventes a
déjà été géré à la main) : seuls les tableaux gain / livraison en profitent.
Idempotent : les commandes déjà calculées sont ignorées.
"""

from datetime import date

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from finance import services
from finance.models import VenteResultat
from orders.models import Order


class Command(BaseCommand):
    help = "Calcule le gain réel des commandes livrées avant le module trésorerie (sans épargne ni encaissement)."

    def add_arguments(self, parser):
        parser.add_argument("--depuis", help="Ne reprendre que les commandes livrées à partir de cette date (YYYY-MM-DD).")

    def handle(self, *args, **options):
        qs = Order.objects.filter(statut_courant="LIVRE", resultat__isnull=True).select_related("magasin")
        if options.get("depuis"):
            qs = qs.filter(date_commande__date__gte=date.fromisoformat(options["depuis"]))
        n = 0
        with transaction.atomic():
            for order in qs.order_by("date_commande"):
                settings = services.parametres(order.magasin)
                resultat = VenteResultat(order=order, magasin=order.magasin, epargne_active=False,
                                         date_vente=timezone.localtime(order.date_commande).date())
                services._appliquer(resultat, services.calculer(order), settings)
                resultat.save()
                n += 1
        self.stdout.write(self.style.SUCCESS(f"{n} vente(s) reprise(s)."))
