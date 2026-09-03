from datetime import datetime

from django.db.models import Count, Sum, F
from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import ProductVariant
from users.permissions import get_accessible_magasins

from .models import Order, OrderItem


class DashboardView(APIView):
    """Dashboard Gérant (§7.7 Smartreadme.md) : KPIs période, suivi commandes
    temps réel, analyse financière, TOP produits, résumé stock. Filtrable par
    date via `date_from`/`date_to` (YYYY-MM-DD) ; par défaut le mois en cours.
    Scope : magasins accessibles à l'utilisateur connecté (admin: tous les
    siens, magasin/employer: le leur)."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        magasins = get_accessible_magasins(request.user)
        magasin_id = request.query_params.get("magasin_id")
        if magasin_id:
            magasins = magasins.filter(id=magasin_id)

        date_from = self._parse_date(request.query_params.get("date_from"))
        date_to = self._parse_date(request.query_params.get("date_to"))
        if not date_from and not date_to:
            today = timezone.localdate()
            date_from = today.replace(day=1)
            date_to = today

        orders_qs = Order.objects.filter(magasin__in=magasins)
        if date_from:
            orders_qs = orders_qs.filter(date_commande__date__gte=date_from)
        if date_to:
            orders_qs = orders_qs.filter(date_commande__date__lte=date_to)

        livrees = orders_qs.filter(statut_courant="LIVRE")
        retours = orders_qs.filter(statut_courant="RETOUR")
        total_commandes = orders_qs.count()
        nb_livrees = livrees.count()
        nb_retours = retours.count()
        taux_livraison = round(100 * nb_livrees / total_commandes, 1) if total_commandes else 0

        ca_produits = livrees.aggregate(total=Sum("total_a_payer") - Sum("frais_livraison"))["total"] or 0
        frais_livraison_total = livrees.aggregate(total=Sum("frais_livraison"))["total"] or 0

        suivi_statuts = {
            statut: orders_qs.filter(statut_courant=statut).count()
            for statut, _label in Order.STATUT_CHOICES
        }

        top_references = (
            OrderItem.objects.filter(order__in=livrees)
            .values("product_variant__product_reference__reference_name")
            .annotate(total=Sum("quantite"))
            .order_by("-total")[:20]
        )
        top_marques = (
            OrderItem.objects.filter(order__in=livrees)
            .values("product_variant__product_reference__brand__nom")
            .annotate(total=Sum("quantite"))
            .order_by("-total")[:20]
        )
        top_couleurs = (
            OrderItem.objects.filter(order__in=livrees)
            .values("product_variant__couleur")
            .annotate(total=Sum("quantite"))
            .order_by("-total")[:20]
        )

        variants = ProductVariant.objects.filter(product_reference__type__category__magasin__in=magasins)
        stock_total = variants.aggregate(total=Sum("stock_actuel"))["total"] or 0
        ruptures = variants.filter(stock_actuel__lte=0).count()
        stock_bas = variants.filter(stock_actuel__gt=0, stock_actuel__lte=F("seuil_alerte")).count()

        return Response({
            "periode": {"date_from": date_from, "date_to": date_to},
            "kpis": {
                "nombre_ventes": nb_livrees,
                "ca_periode": ca_produits + frais_livraison_total,
                "taux_livraison": taux_livraison,
                "nombre_retours": nb_retours,
            },
            "suivi_commandes": suivi_statuts,
            "analyse_financiere": {
                "ca_produits": ca_produits,
                "frais_livraison": frais_livraison_total,
            },
            "top_produits": {
                "references": list(top_references),
                "marques": list(top_marques),
                "couleurs": list(top_couleurs),
            },
            "stock_rapide": {
                "total_stock": stock_total,
                "ruptures": ruptures,
                "stock_bas": stock_bas,
            },
        })

    @staticmethod
    def _parse_date(raw):
        if not raw:
            return None
        try:
            return datetime.strptime(raw, "%Y-%m-%d").date()
        except ValueError:
            return None
