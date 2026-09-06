from datetime import datetime

from django.db.models import DecimalField, Sum, F
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import ProductVariant
from users.models import CaisseMovement
from users.permissions import get_accessible_magasins

from .models import Order, OrderItem


def _top_entries(items_qs, group_field, limit=20):
    """(label, quantite_vendue) triés décroissant — forme stable
    {label, quantite_vendue} indépendante du nom de champ Django groupé."""
    rows = (
        items_qs.values(group_field)
        .annotate(total=Sum("quantite"))
        .order_by("-total")[:limit]
    )
    return [{"label": row[group_field] or "-", "quantite_vendue": row["total"]} for row in rows]


class DashboardView(APIView):
    """Dashboard Gérant (§7.7 Smartreadme.md) : KPIs période, suivi commandes
    temps réel, analyse financière (incl. bénéfice estimé §7.7), TOP
    produits, résumé stock. Filtrable par date via `date_from`/`date_to`
    (YYYY-MM-DD) ; par défaut le mois en cours. Scope : magasins accessibles
    à l'utilisateur connecté (admin: tous les siens, magasin/employer: le sien)."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        magasins = get_accessible_magasins(request.user)
        magasin_id = request.query_params.get("magasin_id")
        if magasin_id:
            magasins = magasins.filter(id=magasin_id)

        date_from = self._parse_date(request.query_params.get("date_from"))
        date_to = self._parse_date(request.query_params.get("date_to"))
        today = timezone.localdate()
        if not date_from and not date_to:
            date_from = today.replace(day=1)
            date_to = today

        orders_qs = Order.objects.filter(magasin__in=magasins)
        if date_from:
            orders_qs = orders_qs.filter(date_commande__date__gte=date_from)
        if date_to:
            orders_qs = orders_qs.filter(date_commande__date__lte=date_to)

        livrees = orders_qs.filter(statut_courant="LIVRE")
        total_commandes = orders_qs.count()
        nb_livrees = livrees.count()
        nb_retours = orders_qs.filter(statut_courant="RETOUR").count()
        taux_livraison = round(100 * nb_livrees / total_commandes, 1) if total_commandes else 0

        ca_produits = livrees.aggregate(total=Sum("total_a_payer") - Sum("frais_livraison"))["total"] or 0
        frais_livraison_total = livrees.aggregate(total=Sum("frais_livraison"))["total"] or 0

        # CA du mois en cours (indépendant du filtre période, §7.7 : "CA
        # période (Ar) ET CA du mois en cours" — les deux sont toujours affichés).
        mois_debut = today.replace(day=1)
        ca_mois_en_cours = Order.objects.filter(
            magasin__in=magasins, statut_courant="LIVRE", date_commande__date__gte=mois_debut,
        ).aggregate(total=Sum("total_a_payer"))["total"] or 0

        suivi_statuts = {
            statut: orders_qs.filter(statut_courant=statut).count()
            for statut, _label in Order.STATUT_CHOICES
        }

        # Coût de revient réel (§7.6/§7.7) — commandes fournisseur de la
        # période, imputées au pilotage qu'elles soient reçues ou non
        # (le budget pub Meta Ads notamment est engagé dès la commande).
        from suppliers.models import SupplierOrder

        supplier_qs = SupplierOrder.objects.filter(magasin__in=magasins)
        if date_from:
            supplier_qs = supplier_qs.filter(date__gte=date_from)
        if date_to:
            supplier_qs = supplier_qs.filter(date__lte=date_to)
        total_meta_ads = supplier_qs.aggregate(total=Sum("meta_ads"))["total"] or 0
        total_fournisseurs = supplier_qs.aggregate(
            total=Sum("prix_fournisseur") + Sum("fret_import") + Sum("douane")
        )["total"] or 0

        # Bénéfice estimé = CA + Livraisons − Fournisseurs − Pub (§7.7 Smartreadme.md).
        benefice_estime = (ca_produits + frais_livraison_total) - total_fournisseurs - total_meta_ads

        items_livres = OrderItem.objects.filter(order__in=livrees)
        top_par_sous_type = _top_entries(items_livres, "product_variant__product_reference__type__nom")
        top_marques = _top_entries(items_livres, "product_variant__product_reference__brand__nom")
        top_references = _top_entries(items_livres, "product_variant__product_reference__reference_name")
        top_couleurs = _top_entries(items_livres, "product_variant__couleur")

        variants = ProductVariant.objects.filter(product_reference__type__category__magasin__in=magasins)
        stock_total = variants.aggregate(total=Sum("stock_actuel"))["total"] or 0
        ruptures = variants.filter(stock_actuel__lte=0).count()
        stock_bas = variants.filter(stock_actuel__gt=0, stock_actuel__lte=F("seuil_alerte")).count()

        # --- Résumé principal (haut du dashboard) ---
        # Bénéfice réel des produits vendus sur la période (prix de vente -
        # coût actuel, sur les commandes Livré) — distinct de
        # analyse_financiere.benefice_estime (qui lui vient du coût
        # fournisseur/pub, §7.7).
        items_vendus_periode = OrderItem.objects.filter(order__in=livrees)
        ca_produits_vendus = items_vendus_periode.aggregate(
            t=Coalesce(Sum(F("prix_unitaire") * F("quantite")), 0, output_field=DecimalField())
        )["t"]
        cout_produits_vendus = items_vendus_periode.aggregate(
            t=Coalesce(
                Sum(F("quantite") * F("product_variant__product_reference__prix_achat")),
                0,
                output_field=DecimalField(),
            )
        )["t"]
        total_benefices_produits_vendus = ca_produits_vendus - cout_produits_vendus

        # Valeur de stock actuelle, au prix de vente catalogue (snapshot,
        # indépendant de la période — cohérent avec
        # users/views.py::_stock_value_for_magasins).
        valeur_stock = variants.aggregate(
            t=Coalesce(
                Sum(F("stock_actuel") * F("product_reference__prix_vente")),
                0,
                output_field=DecimalField(),
            )
        )["t"]

        # Bénéfice potentiel si tout le stock actuel était vendu (snapshot,
        # indépendant de la période) — prix de vente - prix actuel (coût).
        benefice_estime_stock = variants.aggregate(
            t=Coalesce(
                Sum(
                    F("stock_actuel")
                    * (F("product_reference__prix_vente") - F("product_reference__prix_achat"))
                ),
                0,
                output_field=DecimalField(),
            )
        )["t"]

        # CA (snapshot) = valeur du stock actuel + tout ce qui a été
        # enregistré en Entrée de caisse (ventes encaissées + apports
        # manuels), toutes périodes confondues.
        total_entrees_caisse = CaisseMovement.objects.filter(
            magasin__in=magasins, movement_type="in"
        ).aggregate(t=Coalesce(Sum("amount"), 0, output_field=DecimalField()))["t"]
        ca_snapshot = valeur_stock + total_entrees_caisse

        return Response({
            "resume": {
                "ca": ca_snapshot,
                "total_benefices_produits_vendus": total_benefices_produits_vendus,
                "valeur_stock": valeur_stock,
                "benefice_estime_stock": benefice_estime_stock,
            },
            "periode": {"date_debut": date_from, "date_fin": date_to},
            "kpis": {
                "nb_ventes": nb_livrees,
                "ca_periode": ca_produits + frais_livraison_total,
                "ca_mois_en_cours": ca_mois_en_cours,
                "taux_livraison_reussie_pct": taux_livraison,
                "nb_retours": nb_retours,
            },
            "suivi_commandes_temps_reel": suivi_statuts,
            "analyse_financiere": {
                "ca_produits_vendus": ca_produits,
                "frais_livraison_encaisses": frais_livraison_total,
                "total_investi_fournisseurs": total_fournisseurs,
                "total_pub_meta_ads": total_meta_ads,
                "benefice_estime": benefice_estime,
            },
            "top_produits": {
                "par_sous_type": top_par_sous_type,
                "marques": top_marques,
                "references": top_references,
                "couleurs": top_couleurs,
            },
            "stock_rapide": {
                "total_en_stock": stock_total,
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
