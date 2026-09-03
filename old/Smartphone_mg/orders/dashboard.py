import calendar

from django.db.models import DecimalField, ExpressionWrapper, F, Q, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import ProductVariant
from suppliers.models import SupplierOrder
from users.permissions import IsGerant

from .models import Order, OrderItem

MONEY = DecimalField(max_digits=14, decimal_places=2)


def _decimal_sum(qs, field_expr):
    if not hasattr(field_expr, "as_sql"):
        # simple field name (string) — pas besoin de wrapper.
        return qs.aggregate(total=Coalesce(Sum(field_expr), 0, output_field=MONEY))["total"]
    expr = ExpressionWrapper(field_expr, output_field=MONEY)
    return qs.aggregate(total=Coalesce(Sum(expr), 0, output_field=MONEY))["total"]


class DashboardView(APIView):
    """§7.7 README — Dashboard Gérant, filtrable par période (jour/semaine/
    mois/intervalle libre via date_debut/date_fin, défaut = mois en cours)."""

    permission_classes = [IsGerant]

    def get(self, request):
        today = timezone.localdate()
        date_debut = request.query_params.get("date_debut") or today.replace(day=1)
        date_fin = request.query_params.get("date_fin") or today

        mois_debut = today.replace(day=1)
        mois_fin = today.replace(day=calendar.monthrange(today.year, today.month)[1])

        livrees = Order.objects.filter(statut_courant="LIVRE", date_commande__range=(date_debut, date_fin))
        retours = Order.objects.filter(statut_courant="RETOUR", date_commande__range=(date_debut, date_fin))
        livrees_mois = Order.objects.filter(statut_courant="LIVRE", date_commande__range=(mois_debut, mois_fin))

        items_livrees = OrderItem.objects.filter(order__in=livrees)
        items_livrees_mois = OrderItem.objects.filter(order__in=livrees_mois)

        ca_produits = _decimal_sum(items_livrees, F("prix_unitaire") * F("quantite"))
        ca_livraison = _decimal_sum(livrees, "frais_livraison")
        ca_produits_mois = _decimal_sum(items_livrees_mois, F("prix_unitaire") * F("quantite"))
        ca_livraison_mois = _decimal_sum(livrees_mois, "frais_livraison")

        nb_ventes = livrees.count()
        nb_retours = retours.count()
        denom = nb_ventes + nb_retours
        taux_livraison = round(nb_ventes / denom * 100, 1) if denom else None

        supplier_orders = SupplierOrder.objects.filter(date__range=(date_debut, date_fin))
        total_fournisseurs = _decimal_sum(
            supplier_orders, F("prix_fournisseur") + F("fret_import") + F("douane")
        )
        total_meta_ads = _decimal_sum(supplier_orders, "meta_ads")

        ca_periode = ca_produits + ca_livraison
        benefice_estime = ca_periode - total_fournisseurs - total_meta_ads

        statuts_temps_reel = {
            statut: Order.objects.filter(statut_courant=statut).count()
            for statut in ["NOUVELLE", "EN_PREPARATION", "PRETE", "EN_LIVRAISON"]
        }

        def top(group_field, label):
            rows = (
                items_livrees.values(group_field)
                .annotate(total_quantite=Sum("quantite"))
                .order_by("-total_quantite")[:20]
            )
            return [{"label": r[group_field], "quantite_vendue": r["total_quantite"]} for r in rows if r[group_field]]

        top_produits_par_sous_type = top("product_variant__product_reference__type__nom", "sous_type")
        top_marques = top("product_variant__product_reference__brand__nom", "marque")
        top_references = top("product_variant__product_reference__reference_name", "reference")
        top_couleurs = top("product_variant__couleur", "couleur")

        stock_total = _decimal_sum(ProductVariant.objects.all(), "stock_actuel")
        stock_ruptures = ProductVariant.objects.filter(stock_actuel__lte=0).count()
        stock_bas = ProductVariant.objects.filter(stock_actuel__gt=0, stock_actuel__lte=F("seuil_alerte")).count()

        return Response({
            "periode": {"date_debut": date_debut, "date_fin": date_fin},
            "kpis": {
                "nb_ventes": nb_ventes,
                "ca_periode": ca_periode,
                "ca_mois_en_cours": ca_produits_mois + ca_livraison_mois,
                "taux_livraison_reussie_pct": taux_livraison,
                "nb_retours": nb_retours,
            },
            "suivi_commandes_temps_reel": statuts_temps_reel | {"LIVRE": nb_ventes, "RETOUR": nb_retours},
            "analyse_financiere": {
                "ca_produits_vendus": ca_produits,
                "frais_livraison_encaisses": ca_livraison,
                "total_investi_fournisseurs": total_fournisseurs,
                "total_pub_meta_ads": total_meta_ads,
                "benefice_estime": benefice_estime,
            },
            "top_produits": {
                "par_sous_type": top_produits_par_sous_type,
                "marques": top_marques,
                "references": top_references,
                "couleurs": top_couleurs,
            },
            "stock_rapide": {
                "total_en_stock": stock_total,
                "ruptures": stock_ruptures,
                "stock_bas": stock_bas,
            },
        })
