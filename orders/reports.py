"""Rapports du gérant (§ demande) — une seule vue qui agrège TOUT côté
serveur.

Tout calculer ici plutôt que dans le navigateur n'est pas un détail :

* le bénéfice a besoin de `prix_achat`, qui n'est jamais exposé au livreur ni
  au préparateur (voir orders/serializers.py) — il ne doit pas transiter ;
* rapatrier toutes les commandes, tous les mouvements et toutes les dépenses
  d'une période pour les additionner côté client ne tient pas à l'échelle ;
* les agrégats par jour, par livreur et par préparateur se font en quelques
  requêtes groupées, là où le client en ferait des milliers d'additions.
"""

from datetime import timedelta

from django.db.models import Count, DecimalField, F, Q, Sum
from django.db.models.functions import Coalesce, TruncDate
from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import StockMovement
from users.models import CaisseMovement
from users.permissions import get_accessible_magasins

from .models import LivreurExpense, Order, OrderItem

_DEC = DecimalField(max_digits=14, decimal_places=2)


def _somme(qs, expression):
    """Somme robuste : 0 plutôt que None sur un ensemble vide."""
    return qs.aggregate(t=Coalesce(Sum(expression), 0, output_field=_DEC))["t"]


class ReportsView(APIView):
    """GET /api/orders/reports/?date_from=&date_to=

    Renvoie l'ensemble des bilans de la période. Par défaut : les 30 derniers
    jours, bornes comprises, en date de livraison prévue (`date_commande`) —
    la même référence que la page Commandes et les bilans, pour que les
    chiffres se recoupent.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        magasins = get_accessible_magasins(request.user)
        magasin_id = request.query_params.get("magasin_id")
        if magasin_id:
            magasins = magasins.filter(id=magasin_id)

        date_to = self._date(request.query_params.get("date_to")) or timezone.localdate()
        date_from = self._date(request.query_params.get("date_from")) or (
            date_to - timedelta(days=29)
        )

        orders = Order.objects.filter(
            magasin__in=magasins,
            date_commande__date__gte=date_from,
            date_commande__date__lte=date_to,
        )
        livrees = orders.filter(statut_courant="LIVRE")
        retours = orders.filter(statut_courant="RETOUR")

        # Articles réellement vendus : ceux des commandes livrées, hors
        # articles rapportés lors d'une livraison partielle (OrderItem.retourne).
        items_vendus = OrderItem.objects.filter(order__in=livrees, retourne=False)

        ca_produits = _somme(items_vendus, F("prix_unitaire") * F("quantite"))
        cout_produits = _somme(
            items_vendus,
            F("quantite") * F("product_variant__product_reference__prix_achat"),
        )
        frais_livraison = _somme(livrees, F("frais_livraison"))

        # Dépenses : sorties de caisse + frais de tournée validés.
        depenses_caisse = _somme(
            CaisseMovement.objects.filter(
                magasin__in=magasins,
                movement_type="out",
                created_at__date__gte=date_from,
                created_at__date__lte=date_to,
            ),
            F("amount"),
        )
        depenses_livreur_qs = LivreurExpense.objects.filter(
            magasin__in=magasins,
            statut="ACCEPTE",
            date__gte=date_from,
            date__lte=date_to,
        )
        depenses_livreur = _somme(depenses_livreur_qs, F("montant"))

        chiffre_affaires = ca_produits + frais_livraison
        marge_produits = ca_produits - cout_produits
        depenses_totales = depenses_caisse + depenses_livreur
        resultat = marge_produits + frais_livraison - depenses_totales

        return Response(
            {
                "periode": {"from": str(date_from), "to": str(date_to)},
                "totaux": {
                    "chiffre_affaires": chiffre_affaires,
                    "ca_produits": ca_produits,
                    "cout_produits": cout_produits,
                    "marge_produits": marge_produits,
                    "frais_livraison": frais_livraison,
                    "depenses_caisse": depenses_caisse,
                    "depenses_livreur": depenses_livreur,
                    "depenses_totales": depenses_totales,
                    "resultat": resultat,
                    "nb_commandes": orders.count(),
                    "nb_livrees": livrees.count(),
                    "nb_retours": retours.count(),
                    "montant_retours": _somme(retours, F("total_a_payer")),
                    "taux_livraison": self._taux(livrees.count(), orders.count()),
                },
                "par_jour": self._par_jour(
                    orders, livrees, retours, magasins, date_from, date_to
                ),
                "top_produits": self._produits(items_vendus, "-vendu"),
                "produits_moins_vendus": self._produits(items_vendus, "vendu"),
                "livreurs": self._livreurs(orders, depenses_livreur_qs),
                "preparateurs": self._preparateurs(orders),
                "mouvements_par_jour": self._mouvements(magasins, date_from, date_to),
            }
        )

    # ------------------------------------------------------------------ #

    @staticmethod
    def _date(value):
        if not value:
            return None
        try:
            return timezone.datetime.strptime(value, "%Y-%m-%d").date()
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _taux(partie, total):
        return round(100 * partie / total, 1) if total else 0

    def _par_jour(self, orders, livrees, retours, magasins, date_from, date_to):
        """Une ligne par jour de la période, y compris les jours sans activité
        — un graphique à trous se lit mal."""

        def grouper(qs, champ_date, **agregats):
            return {
                row["jour"]: row
                for row in qs.annotate(jour=TruncDate(champ_date))
                .values("jour")
                .annotate(**agregats)
            }

        cmd = grouper(orders, "date_commande", nb=Count("id"))
        liv = grouper(
            livrees,
            "date_commande",
            nb=Count("id"),
            frais=Coalesce(Sum("frais_livraison"), 0, output_field=_DEC),
        )
        ret = grouper(retours, "date_commande", nb=Count("id"))

        ca_par_jour = {
            row["jour"]: row["ca"]
            for row in OrderItem.objects.filter(order__in=livrees, retourne=False)
            .annotate(jour=TruncDate("order__date_commande"))
            .values("jour")
            .annotate(ca=Coalesce(Sum(F("prix_unitaire") * F("quantite")), 0, output_field=_DEC))
        }
        dep_caisse = {
            row["jour"]: row["total"]
            for row in CaisseMovement.objects.filter(
                magasin__in=magasins,
                movement_type="out",
                created_at__date__gte=date_from,
                created_at__date__lte=date_to,
            )
            .annotate(jour=TruncDate("created_at"))
            .values("jour")
            .annotate(total=Coalesce(Sum("amount"), 0, output_field=_DEC))
        }
        dep_livreur = {
            row["date"]: row["total"]
            for row in LivreurExpense.objects.filter(
                magasin__in=magasins, statut="ACCEPTE",
                date__gte=date_from, date__lte=date_to,
            )
            .values("date")
            .annotate(total=Coalesce(Sum("montant"), 0, output_field=_DEC))
        }
        mouvements = {
            row["jour"]: row["nb"]
            for row in StockMovement.objects.filter(
                product_variant__product_reference__type__category__magasin__in=magasins,
                timestamp__date__gte=date_from,
                timestamp__date__lte=date_to,
            )
            .annotate(jour=TruncDate("timestamp"))
            .values("jour")
            .annotate(nb=Count("id"))
        }

        total_mouvements = sum(mouvements.values())
        lignes = []
        jour = date_from
        while jour <= date_to:
            ca = ca_par_jour.get(jour, 0)
            frais = liv.get(jour, {}).get("frais", 0)
            depenses = dep_caisse.get(jour, 0) + dep_livreur.get(jour, 0)
            nb_mvt = mouvements.get(jour, 0)
            lignes.append(
                {
                    "date": str(jour),
                    "commandes": cmd.get(jour, {}).get("nb", 0),
                    "livrees": liv.get(jour, {}).get("nb", 0),
                    "retours": ret.get(jour, {}).get("nb", 0),
                    "ca": ca + frais,
                    "frais_livraison": frais,
                    "depenses": depenses,
                    # Ce que la journée a réellement laissé : recettes moins
                    # dépenses. C'est l'écart demandé, jour par jour.
                    "difference": ca + frais - depenses,
                    "mouvements": nb_mvt,
                    "part_mouvements": self._taux(nb_mvt, total_mouvements),
                }
            )
            jour += timedelta(days=1)
        return lignes

    @staticmethod
    def _produits(items_vendus, sens):
        """Classement des références par quantité vendue. `sens` = "-vendu"
        pour les meilleures, "vendu" pour les moins bonnes."""
        rows = (
            items_vendus.values(
                nom=F("product_variant__product_reference__reference_name"),
                marque=F("product_variant__product_reference__brand__nom"),
            )
            .annotate(
                vendu=Coalesce(Sum("quantite"), 0),
                ca=Coalesce(Sum(F("prix_unitaire") * F("quantite")), 0, output_field=_DEC),
            )
            .order_by(sens)[:10]
        )
        return [
            {
                "label": r["nom"] or "-",
                "marque": r["marque"] or "",
                "quantite": r["vendu"],
                "ca": r["ca"],
            }
            for r in rows
        ]

    def _livreurs(self, orders, depenses_qs):
        """Performance par livreur : livraisons, retours, argent rapporté et
        frais de tournée validés."""
        depenses = {
            r["livreur"]: r["total"]
            for r in depenses_qs.values("livreur").annotate(
                total=Coalesce(Sum("montant"), 0, output_field=_DEC)
            )
        }
        rows = (
            orders.filter(livreur__isnull=False)
            .values("livreur", nom=F("livreur__full_name"))
            .annotate(
                livrees=Count("id", filter=Q(statut_courant="LIVRE")),
                retours=Count("id", filter=Q(statut_courant="RETOUR")),
                total=Count("id"),
                ca=Coalesce(
                    Sum("total_a_payer", filter=Q(statut_courant="LIVRE")),
                    0,
                    output_field=_DEC,
                ),
                frais=Coalesce(
                    Sum("frais_livraison", filter=Q(statut_courant="LIVRE")),
                    0,
                    output_field=_DEC,
                ),
            )
            .order_by("-livrees")
        )
        return [
            {
                "id": r["livreur"],
                "nom": r["nom"] or "-",
                "livrees": r["livrees"],
                "retours": r["retours"],
                "assignees": r["total"],
                "ca": r["ca"],
                "frais_livraison": r["frais"],
                "depenses": depenses.get(r["livreur"], 0),
                "taux_reussite": self._taux(r["livrees"], r["livrees"] + r["retours"]),
            }
            for r in rows
        ]

    def _preparateurs(self, orders):
        """Commandes préparées par préparateur, avec le détail par jour."""
        preparees = orders.filter(
            preparateur__isnull=False,
            statut_courant__in=["PRETE", "EN_LIVRAISON", "LIVRE", "RETOUR"],
        )
        par_jour = {}
        for r in (
            preparees.annotate(jour=TruncDate("date_commande"))
            .values("preparateur", "jour")
            .annotate(nb=Count("id"))
        ):
            par_jour.setdefault(r["preparateur"], []).append(
                {"date": str(r["jour"]), "nb": r["nb"]}
            )

        rows = (
            preparees.values("preparateur", nom=F("preparateur__full_name"))
            .annotate(total=Count("id"))
            .order_by("-total")
        )
        return [
            {
                "id": r["preparateur"],
                "nom": r["nom"] or "-",
                "total": r["total"],
                "par_jour": sorted(
                    par_jour.get(r["preparateur"], []), key=lambda x: x["date"]
                ),
            }
            for r in rows
        ]

    @staticmethod
    def _mouvements(magasins, date_from, date_to):
        """Entrées et sorties de stock par jour."""
        rows = (
            StockMovement.objects.filter(
                product_variant__product_reference__type__category__magasin__in=magasins,
                timestamp__date__gte=date_from,
                timestamp__date__lte=date_to,
            )
            .annotate(jour=TruncDate("timestamp"))
            .values("jour")
            .annotate(
                entrees=Count("id", filter=Q(type="ENTREE")),
                sorties=Count("id", filter=Q(type="SORTIE")),
            )
            .order_by("jour")
        )
        return [
            {
                "date": str(r["jour"]),
                "entrees": r["entrees"],
                "sorties": r["sorties"],
            }
            for r in rows
        ]
