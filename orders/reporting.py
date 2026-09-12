"""Centre de rapports du gérant — 8 sections, une vue par section
(GET /api/orders/reports/<section>/), tout agrégé côté serveur.

Conventions communes à toutes les sections :

* période = `date_from`..`date_to` (YYYY-MM-DD, bornes comprises), en DATE
  DE LIVRAISON PRÉVUE (`Order.date_commande`) — la même référence que la
  page Commandes, les bilans et l'endpoint /reports/ historique, pour que
  les chiffres se recoupent ;
* période précédente = `prev_from`..`prev_to` si fournis (le client les
  calcule pour "mois précédent", "année précédente"…), sinon la fenêtre de
  même longueur juste avant ;
* `granularity` = day | week | month | year pour les séries temporelles ;
* `magasin_id` facultatif, toujours restreint aux magasins accessibles.

Définitions (identiques à orders/reports.py) :
  vente réalisée   = commande LIVRE, articles non rapportés
  CA               = Σ prix_unitaire × quantité (snapshot au moment de la
                     commande) + frais de livraison encaissés
  coût d'achat     = Σ quantité × ProductReference.prix_achat (prix d'achat
                     ACTUEL du catalogue : il n'est pas historisé sur la ligne)
  dépenses         = sorties de caisse HORS achats de stock + frais de tournée
                     des livreurs acceptés. Les sorties « Commande stock »
                     sont de la marchandise, déjà comptée dans le coût
                     d'achat des articles vendus : les compter aussi en
                     dépense ferait apparaître chaque réassort comme une
                     perte (double comptage).
  bénéfice net     = CA − coût d'achat − dépenses

Les dépenses de campagnes marketing (MarketingCampaign.montant) sont
analytiques : elles n'entrent pas dans le bénéfice net, sauf si elles ont
aussi été enregistrées en caisse (catégorie "Pub").
"""

from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal

from django.db.models import Count, DecimalField, F, Max, Q, Sum
from django.db.models.functions import Coalesce, TruncDate
from django.utils import timezone
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import ProductVariant, StockMovement
from users.models import CaisseMovement
from users.permissions import IsGerant, get_accessible_magasins

from .models import LivreurExpense, MarketingCampaign, Order, OrderItem, OrderStatusHistory

_DEC = DecimalField(max_digits=14, decimal_places=2)
ZERO = Decimal("0")

STATUT_LABELS = dict(Order.STATUT_CHOICES)
GRANULARITES = ("day", "week", "month", "year")

# Catégories de caisse qui sont des achats de marchandise, pas des charges
# ("Commande stock" est la catégorie par défaut, voir users/views.py).
CATEGORIES_ACHAT_STOCK = ("commande stock", "achat stock", "achats stock", "achat de stock", "achats de stock")


def q_achat_stock():
    q = Q()
    for nom in CATEGORIES_ACHAT_STOCK:
        q |= Q(category__nom__iexact=nom)
    return q


def _somme(qs, expression):
    return qs.aggregate(t=Coalesce(Sum(expression), 0, output_field=_DEC))["t"]


def _dec(value):
    return Decimal(value or 0)


def _taux(partie, total):
    return round(100 * float(partie) / float(total), 1) if total else 0


def _variation(actuel, precedent):
    """Évolution entre deux valeurs. `variation_pct` vaut None quand la
    valeur précédente est 0 : un pourcentage n'a alors aucun sens (et une
    division par zéro n'en aurait pas plus)."""
    actuel = _dec(actuel) if not isinstance(actuel, (int, float)) else actuel
    precedent = _dec(precedent) if not isinstance(precedent, (int, float)) else precedent
    diff = actuel - precedent
    pct = round(100 * float(diff) / float(precedent), 1) if precedent else None
    return {"actuel": actuel, "precedent": precedent, "variation": diff, "variation_pct": pct}


def _parse_date(value):
    if not value:
        return None
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        return None


# --------------------------------------------------------------------------- #
# Périodes et séries
# --------------------------------------------------------------------------- #


def _debut_bucket(jour, granularity):
    if granularity == "week":
        return jour - timedelta(days=jour.weekday())
    if granularity == "month":
        return jour.replace(day=1)
    if granularity == "year":
        return jour.replace(month=1, day=1)
    return jour


def _bucket_suivant(bucket, granularity):
    if granularity == "week":
        return bucket + timedelta(days=7)
    if granularity == "month":
        return (bucket.replace(day=28) + timedelta(days=4)).replace(day=1)
    if granularity == "year":
        return bucket.replace(year=bucket.year + 1)
    return bucket + timedelta(days=1)


def _buckets(date_from, date_to, granularity):
    """Toutes les périodes de la plage, y compris celles sans activité —
    une courbe à trous se lit mal."""
    out = []
    b = _debut_bucket(date_from, granularity)
    while b <= date_to:
        out.append(b)
        b = _bucket_suivant(b, granularity)
    return out


def _label_bucket(bucket, granularity):
    if granularity == "week":
        return f"S{bucket.isocalendar()[1]} {bucket:%d/%m}"
    if granularity == "month":
        return f"{bucket:%m/%Y}"
    if granularity == "year":
        return f"{bucket:%Y}"
    return f"{bucket:%d/%m}"


def _par_jour(qs, champ_date, **agregats):
    """{jour: {agrégat: valeur}} — on agrège au jour en SQL puis on regroupe
    en Python par granularité : évite les subtilités de fuseau de
    TruncWeek/TruncMonth sur des DateTimeField."""
    return {
        row["jour"]: row
        for row in qs.annotate(jour=TruncDate(champ_date)).values("jour").annotate(**agregats)
    }


def _par_date(qs, champ_date, **agregats):
    """Même chose pour un DateField (pas de TruncDate nécessaire)."""
    return {row[champ_date]: row for row in qs.values(champ_date).annotate(**agregats)}


def _serie(date_from, date_to, granularity, sources):
    """sources : {clé: {jour: valeur}} -> [{periode, label, clé…}] avec
    zéro-remplissage."""
    buckets = _buckets(date_from, date_to, granularity)
    index = {b: i for i, b in enumerate(buckets)}
    lignes = [{"periode": str(b), "label": _label_bucket(b, granularity)} for b in buckets]
    for cle, valeurs in sources.items():
        for l in lignes:
            l[cle] = 0
        for jour, val in valeurs.items():
            if jour is None or jour < date_from or jour > date_to:
                continue
            i = index[_debut_bucket(jour, granularity)]
            lignes[i][cle] = lignes[i][cle] + val
    return lignes


# --------------------------------------------------------------------------- #
# Contexte de requête
# --------------------------------------------------------------------------- #


class _Contexte:
    def __init__(self, request):
        self.magasins = get_accessible_magasins(request.user)
        magasin_id = request.query_params.get("magasin_id")
        if magasin_id:
            self.magasins = self.magasins.filter(id=magasin_id)

        q = request.query_params
        self.date_to = _parse_date(q.get("date_to")) or timezone.localdate()
        self.date_from = _parse_date(q.get("date_from")) or (self.date_to - timedelta(days=29))
        if self.date_from > self.date_to:
            self.date_from, self.date_to = self.date_to, self.date_from
        longueur = (self.date_to - self.date_from).days + 1
        self.prev_to = _parse_date(q.get("prev_to")) or (self.date_from - timedelta(days=1))
        self.prev_from = _parse_date(q.get("prev_from")) or (self.prev_to - timedelta(days=longueur - 1))
        if self.prev_from > self.prev_to:
            self.prev_from, self.prev_to = self.prev_to, self.prev_from

        g = q.get("granularity", "day")
        self.granularity = g if g in GRANULARITES else "day"

    def periode(self):
        return {
            "from": str(self.date_from),
            "to": str(self.date_to),
            "prev_from": str(self.prev_from),
            "prev_to": str(self.prev_to),
            "granularity": self.granularity,
        }

    # -- jeux de données de base ------------------------------------------ #

    def orders(self, date_from=None, date_to=None):
        return Order.objects.filter(
            magasin__in=self.magasins,
            date_commande__date__gte=date_from or self.date_from,
            date_commande__date__lte=date_to or self.date_to,
        )

    def caisse_sorties(self, date_from=None, date_to=None, charges=False):
        """Sorties de caisse de la plage ; `charges=True` exclut les achats de
        stock (voir CATEGORIES_ACHAT_STOCK) — c'est cette version qui entre
        dans le résultat."""
        qs = CaisseMovement.objects.filter(
            magasin__in=self.magasins,
            movement_type="out",
            created_at__date__gte=date_from or self.date_from,
            created_at__date__lte=date_to or self.date_to,
        )
        return qs.exclude(q_achat_stock()) if charges else qs

    def achats_stock(self, date_from=None, date_to=None):
        return self.caisse_sorties(date_from, date_to).filter(q_achat_stock())

    def depenses_livreur(self, date_from=None, date_to=None):
        return LivreurExpense.objects.filter(
            magasin__in=self.magasins,
            statut="ACCEPTE",
            date__gte=date_from or self.date_from,
            date__lte=date_to or self.date_to,
        )

    def mouvements(self, date_from=None, date_to=None):
        return StockMovement.objects.filter(
            product_variant__product_reference__type__category__magasin__in=self.magasins,
            timestamp__date__gte=date_from or self.date_from,
            timestamp__date__lte=date_to or self.date_to,
        )

    def variantes(self):
        return ProductVariant.objects.filter(
            product_reference__type__category__magasin__in=self.magasins
        ).select_related("product_reference", "product_reference__brand", "product_reference__type")

    def bilan(self, date_from=None, date_to=None):
        """Les totaux financiers d'une plage — réutilisés par plusieurs
        sections et pour la période précédente."""
        orders = self.orders(date_from, date_to)
        livrees = orders.filter(statut_courant="LIVRE")
        items = OrderItem.objects.filter(order__in=livrees, retourne=False)
        ca_produits = _somme(items, F("prix_unitaire") * F("quantite"))
        cout = _somme(items, F("quantite") * F("product_variant__product_reference__prix_achat"))
        frais = _somme(livrees, F("frais_livraison"))
        dep_caisse = _somme(self.caisse_sorties(date_from, date_to, charges=True), F("amount"))
        dep_livreur = _somme(self.depenses_livreur(date_from, date_to), F("montant"))
        achats_stock = _somme(self.achats_stock(date_from, date_to), F("amount"))
        nb_livrees = livrees.count()
        ca_total = ca_produits + frais
        depenses = dep_caisse + dep_livreur
        return {
            "orders": orders,
            "livrees": livrees,
            "items": items,
            "nb_commandes": orders.count(),
            "nb_livrees": nb_livrees,
            "nb_retours": orders.filter(statut_courant="RETOUR").count(),
            "nb_annulees": orders.filter(statut_courant="ANNULEE").count(),
            "quantite_vendue": items.aggregate(q=Coalesce(Sum("quantite"), 0))["q"],
            "ca_produits": ca_produits,
            "frais_livraison": frais,
            "ca_total": ca_total,
            "cout_achat": cout,
            "marge_brute": ca_produits - cout,
            "depenses_caisse": dep_caisse,
            "depenses_livreur": dep_livreur,
            "depenses": depenses,
            "achats_stock": achats_stock,
            "benefice_net": ca_total - cout - depenses,
            "panier_moyen": (ca_total / nb_livrees) if nb_livrees else ZERO,
        }

    def series_financieres(self):
        """Par bucket : ventes (CA), coût d'achat, dépenses, bénéfice."""
        livrees = self.orders().filter(statut_courant="LIVRE")
        items = OrderItem.objects.filter(order__in=livrees, retourne=False)
        ventes = {
            j: r["ca"]
            for j, r in _par_jour(
                items, "order__date_commande",
                ca=Coalesce(Sum(F("prix_unitaire") * F("quantite")), 0, output_field=_DEC),
            ).items()
        }
        couts = {
            j: r["c"]
            for j, r in _par_jour(
                items, "order__date_commande",
                c=Coalesce(Sum(F("quantite") * F("product_variant__product_reference__prix_achat")), 0, output_field=_DEC),
            ).items()
        }
        frais = {
            j: r["f"]
            for j, r in _par_jour(livrees, "date_commande", f=Coalesce(Sum("frais_livraison"), 0, output_field=_DEC)).items()
        }
        caisse = {
            j: r["t"]
            for j, r in _par_jour(self.caisse_sorties(charges=True), "created_at", t=Coalesce(Sum("amount"), 0, output_field=_DEC)).items()
        }
        livreur = {
            j: r["t"] for j, r in _par_date(self.depenses_livreur(), "date", t=Coalesce(Sum("montant"), 0, output_field=_DEC)).items()
        }
        ca = defaultdict(Decimal)
        for src in (ventes, frais):
            for j, v in src.items():
                ca[j] += v
        depenses = defaultdict(Decimal)
        for src in (caisse, livreur):
            for j, v in src.items():
                depenses[j] += v
        lignes = _serie(
            self.date_from, self.date_to, self.granularity,
            {"ventes": ca, "cout_achat": couts, "depenses": depenses, "caisse": caisse, "livreur": livreur},
        )
        for l in lignes:
            l["benefices"] = l["ventes"] - l["cout_achat"] - l["depenses"]
        return lignes


class _RapportView(APIView):
    # GÉRANT UNIQUEMENT : la réponse contient coûts d'achat et marges, jamais
    # exposés aux autres rôles. C'est ici que l'accès se refuse, pas dans l'UI.
    permission_classes = [IsGerant]

    def get(self, request):
        ctx = _Contexte(request)
        data = self.calculer(ctx, request)
        data["periode"] = ctx.periode()
        return Response(data)

    def calculer(self, ctx, request):  # pragma: no cover - abstrait
        raise NotImplementedError


# --------------------------------------------------------------------------- #
# 1. Vue générale
# --------------------------------------------------------------------------- #


class OverviewReportView(_RapportView):
    def calculer(self, ctx, request):
        actuel = ctx.bilan()
        precedent = ctx.bilan(ctx.prev_from, ctx.prev_to)
        cles = ("ca_total", "benefice_net", "nb_commandes", "panier_moyen", "nb_livrees", "depenses", "marge_brute")
        kpis = {k: _variation(actuel[k], precedent[k]) for k in cles}
        statuts = {
            r["statut_courant"]: r["nb"]
            for r in actuel["orders"].values("statut_courant").annotate(nb=Count("id"))
        }
        return {
            "kpis": kpis,
            "series": ctx.series_financieres(),
            "repartition_statuts": [
                {"statut": code, "label": label, "nb": statuts.get(code, 0)}
                for code, label in Order.STATUT_CHOICES
            ],
        }


# --------------------------------------------------------------------------- #
# 2. Ventes
# --------------------------------------------------------------------------- #

_DIMENSIONS = {
    # clé API : (champs à grouper, libellé)
    "produit": (("product_variant__product_reference__reference_name", "product_variant__product_reference__brand__nom"), "Produit"),
    "modele": (("product_variant__product_reference__reference_name",), "Modèle"),
    "sous_type": (("product_variant__product_reference__type__nom",), "Sous-type"),
    "categorie": (("product_variant__product_reference__type__category__nom",), "Catégorie"),
    "marque": (("product_variant__product_reference__brand__nom",), "Marque"),
    "couleur": (("product_variant__couleur",), "Couleur"),
}


def _grouper_ventes(items, champs, ordre="-quantite", limite=50):
    rows = (
        items.values(*champs)
        .annotate(
            ca=Coalesce(Sum(F("prix_unitaire") * F("quantite")), 0, output_field=_DEC),
            cout=Coalesce(Sum(F("quantite") * F("product_variant__product_reference__prix_achat")), 0, output_field=_DEC),
            nb_commandes=Count("order", distinct=True),
            # En dernier : ce nom masque le champ `quantite` pour les
            # expressions annotées après lui.
            qte=Coalesce(Sum("quantite"), 0),
        )
        .order_by(ordre.replace("quantite", "qte"), *champs)
    )
    if limite:
        rows = rows[:limite]
    out = []
    for r in rows:
        label = " ".join(str(r[c]) for c in champs if r[c]) or "-"
        marge = r["ca"] - r["cout"]
        out.append(
            {
                "label": label,
                "quantite": r["qte"],
                "nb_commandes": r["nb_commandes"],
                "ca": r["ca"],
                "cout": r["cout"],
                "marge": marge,
                "marge_pct": _taux(marge, r["ca"]),
            }
        )
    return out


class SalesReportView(_RapportView):
    def calculer(self, ctx, request):
        actuel = ctx.bilan()
        precedent = ctx.bilan(ctx.prev_from, ctx.prev_to)
        items = actuel["items"]
        cles = ("ca_total", "ca_produits", "nb_livrees", "quantite_vendue", "panier_moyen")

        par = {
            cle: _grouper_ventes(items, champs)
            for cle, (champs, _label) in _DIMENSIONS.items()
        }
        dimensions = [{"cle": cle, "label": label} for cle, (_c, label) in _DIMENSIONS.items()]

        produit = _DIMENSIONS["produit"][0]
        livraisons = ctx.orders().filter(livreur__isnull=False)
        par_livreur = [
            {
                "id": r["livreur"],
                "nom": r["nom"] or "-",
                "commandes": r["total"],
                "livrees": r["livrees"],
                "retours": r["retours"],
                "en_cours": r["en_cours"],
                "ca": r["ca"],
                "taux_reussite": _taux(r["livrees"], r["livrees"] + r["retours"]),
            }
            for r in livraisons.values("livreur", nom=F("livreur__full_name"))
            .annotate(
                total=Count("id"),
                livrees=Count("id", filter=Q(statut_courant="LIVRE")),
                retours=Count("id", filter=Q(statut_courant="RETOUR")),
                en_cours=Count("id", filter=Q(statut_courant="EN_LIVRAISON")),
                ca=Coalesce(Sum("total_a_payer", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
            )
            .order_by("-livrees")
        ]

        livrees = actuel["livrees"]
        serie = _serie(
            ctx.date_from, ctx.date_to, ctx.granularity,
            {
                "ca": {j: r["ca"] for j, r in _par_jour(items, "order__date_commande", ca=Coalesce(Sum(F("prix_unitaire") * F("quantite")), 0, output_field=_DEC)).items()},
                "quantite": {j: r["q"] for j, r in _par_jour(items, "order__date_commande", q=Coalesce(Sum("quantite"), 0)).items()},
                "ventes": {j: r["n"] for j, r in _par_jour(livrees, "date_commande", n=Count("id")).items()},
            },
        )
        return {
            "kpis": {k: _variation(actuel[k], precedent[k]) for k in cles},
            "dimensions": dimensions,
            "par": par,
            "top_produits": _grouper_ventes(items, produit, "-quantite", 10),
            "moins_vendus": _grouper_ventes(items, produit, "quantite", 10),
            "par_livreur": par_livreur,
            "serie": serie,
        }


# --------------------------------------------------------------------------- #
# 3. Financier
# --------------------------------------------------------------------------- #


class FinancialReportView(_RapportView):
    def calculer(self, ctx, request):
        actuel = ctx.bilan()
        precedent = ctx.bilan(ctx.prev_from, ctx.prev_to)
        items = actuel["items"]
        cles = ("ca_total", "ca_produits", "frais_livraison", "cout_achat", "marge_brute", "depenses_caisse", "depenses_livreur", "depenses", "benefice_net")
        totaux = {k: actuel[k] for k in cles}
        totaux["achats_stock"] = actuel["achats_stock"]
        totaux["taux_marge_brute"] = _taux(actuel["marge_brute"], actuel["ca_produits"])
        totaux["taux_benefice"] = _taux(actuel["benefice_net"], actuel["ca_total"])
        return {
            "totaux": totaux,
            "comparaison": {k: _variation(actuel[k], precedent[k]) for k in cles},
            "par_produit": _grouper_ventes(items, _DIMENSIONS["produit"][0], "-quantite", 200),
            "par_categorie": _grouper_ventes(items, _DIMENSIONS["categorie"][0], "-quantite", 100),
            "par_sous_type": _grouper_ventes(items, _DIMENSIONS["sous_type"][0], "-quantite", 100),
            "series": ctx.series_financieres(),
        }


# --------------------------------------------------------------------------- #
# 4. Dépenses
# --------------------------------------------------------------------------- #


class ExpensesReportView(_RapportView):
    def calculer(self, ctx, request):
        caisse = ctx.caisse_sorties().select_related("category", "created_by")
        livreur = ctx.depenses_livreur().select_related("type_depense", "livreur")
        total_caisse = _somme(caisse, F("amount"))
        total_livreur = _somme(livreur, F("montant"))
        achats_stock = _somme(ctx.achats_stock(), F("amount"))
        prev_caisse = _somme(ctx.caisse_sorties(ctx.prev_from, ctx.prev_to), F("amount"))
        prev_livreur = _somme(ctx.depenses_livreur(ctx.prev_from, ctx.prev_to), F("montant"))
        prev_achats = _somme(ctx.achats_stock(ctx.prev_from, ctx.prev_to), F("amount"))
        noms_achat = set(CATEGORIES_ACHAT_STOCK)

        par_categorie = [
            {
                "label": r["nom"] or "Sans catégorie",
                "source": "caisse",
                "total": r["total"],
                "nb": r["nb"],
                "hors_resultat": (r["nom"] or "").strip().lower() in noms_achat,
            }
            for r in caisse.values(nom=F("category__nom"))
            .annotate(total=Coalesce(Sum("amount"), 0, output_field=_DEC), nb=Count("id"))
            .order_by("-total")
        ] + [
            {"label": f"Tournée livreur : {r['nom'] or 'Autre'}", "source": "livreur", "total": r["total"], "nb": r["nb"], "hors_resultat": False}
            for r in livreur.values(nom=F("type_depense__nom"))
            .annotate(total=Coalesce(Sum("montant"), 0, output_field=_DEC), nb=Count("id"))
            .order_by("-total")
        ]
        par_categorie.sort(key=lambda x: x["total"], reverse=True)

        serie = _serie(
            ctx.date_from, ctx.date_to, ctx.granularity,
            {
                "caisse": {j: r["t"] for j, r in _par_jour(caisse, "created_at", t=Coalesce(Sum("amount"), 0, output_field=_DEC)).items()},
                "livreur": {j: r["t"] for j, r in _par_date(livreur, "date", t=Coalesce(Sum("montant"), 0, output_field=_DEC)).items()},
            },
        )
        for l in serie:
            l["total"] = l["caisse"] + l["livreur"]

        # Livraison : ce que le client paie vs ce que la tournée coûte
        # réellement (frais des livreurs acceptés). L'app n'a pas d'agence
        # de livraison externe : les livreurs sont des employés.
        livrees = ctx.orders().filter(statut_courant="LIVRE")
        frais_client = _somme(livrees, F("frais_livraison"))
        nb_livrees = livrees.count()
        livraison = {
            "frais_factures_client": frais_client,
            "cout_reel_livreurs": total_livreur,
            "marge_livraison": frais_client - total_livreur,
            "nb_livrees": nb_livrees,
            "frais_moyen_client": (frais_client / nb_livrees) if nb_livrees else ZERO,
            "cout_moyen_livraison": (total_livreur / nb_livrees) if nb_livrees else ZERO,
        }

        mouvements = [
            {
                "date": m.created_at.isoformat(),
                "source": "caisse",
                "categorie": m.category.nom if m.category else "Sans catégorie",
                "libelle": m.reason,
                "montant": m.amount,
                "auteur": m.created_by.full_name if m.created_by else "",
            }
            for m in caisse.order_by("-created_at")[:200]
        ] + [
            {
                "date": d.date.isoformat(),
                "source": "livreur",
                "categorie": d.type_depense.nom if d.type_depense else "Tournée",
                "libelle": f"{d.libelle}{' × ' + str(d.quantite) if d.quantite > 1 else ''}",
                "montant": d.montant,
                "auteur": d.livreur.full_name if d.livreur else "",
            }
            for d in livreur.order_by("-date", "-created_at")[:200]
        ]
        mouvements.sort(key=lambda x: x["date"], reverse=True)

        return {
            "totaux": {
                "total": _variation(total_caisse + total_livreur, prev_caisse + prev_livreur),
                "caisse": _variation(total_caisse, prev_caisse),
                "livreur": _variation(total_livreur, prev_livreur),
                # Achats de marchandise : inclus dans le total ci-dessus mais
                # exclus du bénéfice (déjà dans le coût d'achat des ventes).
                "achats_stock": _variation(achats_stock, prev_achats),
                "charges": _variation(total_caisse - achats_stock + total_livreur, prev_caisse - prev_achats + prev_livreur),
                "nb_mouvements": caisse.count() + livreur.count(),
            },
            "par_categorie": par_categorie,
            "serie": serie,
            "livraison": livraison,
            "mouvements": mouvements[:300],
        }


# --------------------------------------------------------------------------- #
# 5. Stock
# --------------------------------------------------------------------------- #


def _libelle_variante(v):
    ref = v.product_reference
    return {
        "variant_id": v.id,
        "produit": f"{ref.type.nom} {ref.brand.nom} {ref.reference_name}".strip(),
        "variante": v.couleur if v.couleur and v.couleur != "Standard" else "",
    }


class StockReportView(_RapportView):
    def calculer(self, ctx, request):
        variantes = ctx.variantes().filter(product_reference__actif=True)
        en_stock = variantes.filter(stock_actuel__gt=0)
        etat = {
            "quantite_totale": en_stock.aggregate(q=Coalesce(Sum("stock_actuel"), 0))["q"],
            "valeur_achat": _somme(en_stock, F("stock_actuel") * F("product_reference__prix_achat")),
            "valeur_vente": _somme(en_stock, F("stock_actuel") * F("product_reference__prix_vente")),
            "nb_variantes": variantes.count(),
            "nb_references": variantes.values("product_reference").distinct().count(),
            "nb_ruptures": variantes.filter(stock_actuel__lte=0).count(),
            "nb_reappro": variantes.filter(stock_actuel__lte=F("seuil_alerte")).count(),
            "nb_stock_bas": variantes.filter(stock_actuel__gt=0, stock_actuel__lte=F("seuil_alerte")).count(),
        }

        def lignes(qs, limite=300):
            return [
                {**_libelle_variante(v), "stock": v.stock_actuel, "seuil": v.seuil_alerte,
                 "prix_achat": v.product_reference.prix_achat, "prix_vente": v.product_reference.prix_vente}
                for v in qs[:limite]
            ]

        ruptures = lignes(variantes.filter(stock_actuel__lte=0).order_by("product_reference__reference_name"))
        reappro = lignes(
            variantes.filter(stock_actuel__lte=F("seuil_alerte")).order_by("stock_actuel", "product_reference__reference_name")
        )

        par_categorie = [
            {"label": r["nom"] or "-", "quantite": r["q"], "valeur_achat": r["v"], "nb_variantes": r["n"]}
            for r in en_stock.values(nom=F("product_reference__type__category__nom"))
            .annotate(
                q=Coalesce(Sum("stock_actuel"), 0),
                v=Coalesce(Sum(F("stock_actuel") * F("product_reference__prix_achat")), 0, output_field=_DEC),
                n=Count("id"),
            )
            .order_by("-v")
        ]

        # Mouvements de la période
        mvts = ctx.mouvements().select_related(
            "product_variant__product_reference__brand",
            "product_variant__product_reference__type",
            "user",
        )
        resume = {
            r["origine"]: {"nb": r["nb"], "entrees": r["e"], "sorties": r["s"]}
            for r in mvts.values("origine").annotate(
                nb=Count("id"),
                e=Coalesce(Sum("quantite", filter=Q(type="ENTREE")), 0),
                s=Coalesce(Sum("quantite", filter=Q(type="SORTIE")), 0),
            )
        }
        origines = dict(StockMovement.ORIGINE_CHOICES)
        mouvements_resume = [
            {"origine": code, "label": label, **resume.get(code, {"nb": 0, "entrees": 0, "sorties": 0})}
            for code, label in StockMovement.ORIGINE_CHOICES
        ]
        mouvements = [
            {
                "id": m.id,
                "date": m.timestamp.isoformat(),
                **_libelle_variante(m.product_variant),
                "quantite": m.quantite,
                "type": m.type,
                "origine": m.origine,
                "origine_label": origines.get(m.origine, m.origine),
                "reference": m.reference or "",
                "note": m.note or "",
                "utilisateur": m.user.full_name if m.user else "",
            }
            for m in mvts.order_by("-timestamp")[:300]
        ]
        serie = _serie(
            ctx.date_from, ctx.date_to, ctx.granularity,
            {
                "entrees": {j: r["e"] for j, r in _par_jour(mvts, "timestamp", e=Coalesce(Sum("quantite", filter=Q(type="ENTREE")), 0)).items()},
                "sorties": {j: r["s"] for j, r in _par_jour(mvts, "timestamp", s=Coalesce(Sum("quantite", filter=Q(type="SORTIE")), 0)).items()},
            },
        )

        # Stock dormant : en stock, sans sortie pour une commande depuis N jours.
        try:
            jours = max(1, int(request.query_params.get("dormant_days", 30)))
        except (TypeError, ValueError):
            jours = 30
        limite = timezone.now() - timedelta(days=jours)
        aujourd_hui = timezone.localdate()
        dernieres_ventes = {
            r["product_variant"]: r["derniere"]
            for r in StockMovement.objects.filter(
                product_variant__in=en_stock, type="SORTIE", origine="PREPARATION"
            ).values("product_variant").annotate(derniere=Max("timestamp"))
        }
        dormants = []
        for v in en_stock:
            derniere = dernieres_ventes.get(v.id)
            if derniere and derniere >= limite:
                continue
            depuis = derniere.date() if derniere else v.product_reference.created_at.date()
            if (aujourd_hui - depuis).days < jours:
                continue
            dormants.append(
                {
                    **_libelle_variante(v),
                    "stock": v.stock_actuel,
                    "derniere_vente": derniere.isoformat() if derniere else None,
                    "jours_sans_vente": (aujourd_hui - depuis).days,
                    "valeur_immobilisee": v.stock_actuel * v.product_reference.prix_achat,
                }
            )
        dormants.sort(key=lambda d: d["valeur_immobilisee"], reverse=True)

        return {
            "etat": etat,
            "ruptures": ruptures,
            "reappro": reappro,
            "par_categorie": par_categorie,
            "mouvements_resume": mouvements_resume,
            "mouvements": mouvements,
            "nb_mouvements": mvts.count(),
            "serie": serie,
            "dormant": {
                "jours": jours,
                "nb": len(dormants),
                "valeur_immobilisee": sum((d["valeur_immobilisee"] for d in dormants), ZERO),
                "lignes": dormants[:300],
            },
        }


# --------------------------------------------------------------------------- #
# 6. Commandes
# --------------------------------------------------------------------------- #


class OrdersReportView(_RapportView):
    def calculer(self, ctx, request):
        orders = ctx.orders()
        prev = ctx.orders(ctx.prev_from, ctx.prev_to)

        def compter(qs):
            counts = {r["statut_courant"]: r["nb"] for r in qs.values("statut_courant").annotate(nb=Count("id"))}
            total = sum(counts.values())
            return {
                "total": total,
                "nouvelles": counts.get("NOUVELLE", 0),
                "en_preparation": counts.get("EN_PREPARATION", 0),
                "pretes": counts.get("PRETE", 0),
                "en_cours": counts.get("EN_PREPARATION", 0) + counts.get("PRETE", 0),
                "en_livraison": counts.get("EN_LIVRAISON", 0),
                "livrees": counts.get("LIVRE", 0),
                "annulees": counts.get("ANNULEE", 0),
                "retournees": counts.get("RETOUR", 0),
                "taux_annulation": _taux(counts.get("ANNULEE", 0), total),
                "taux_livraison": _taux(counts.get("LIVRE", 0), total),
                "taux_retour": _taux(counts.get("RETOUR", 0), counts.get("LIVRE", 0) + counts.get("RETOUR", 0)),
                "_counts": counts,
            }

        actuel = compter(orders)
        precedent = compter(prev)
        counts = actuel.pop("_counts")
        precedent.pop("_counts")
        comparaison = {k: _variation(actuel[k], precedent[k]) for k in ("total", "livrees", "annulees", "retournees", "taux_annulation")}

        repartition = [
            {"statut": code, "label": label, "nb": counts.get(code, 0), "part": _taux(counts.get(code, 0), actuel["total"])}
            for code, label in Order.STATUT_CHOICES
        ]
        par_zone = [
            {"zone": r["livraison_zone"], "nb": r["nb"], "livrees": r["l"], "ca": r["ca"], "frais": r["f"]}
            for r in orders.values("livraison_zone")
            .annotate(
                nb=Count("id"),
                l=Count("id", filter=Q(statut_courant="LIVRE")),
                ca=Coalesce(Sum("total_a_payer", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
                f=Coalesce(Sum("frais_livraison", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
            )
            .order_by("-nb")
        ]
        par_paiement = [
            {"mode": r["mode_paiement"], "label": dict(Order.MODE_PAIEMENT_CHOICES).get(r["mode_paiement"], r["mode_paiement"]), "nb": r["nb"], "ca": r["ca"]}
            for r in orders.values("mode_paiement")
            .annotate(nb=Count("id"), ca=Coalesce(Sum("total_a_payer", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC))
            .order_by("-nb")
        ]
        serie = _serie(
            ctx.date_from, ctx.date_to, ctx.granularity,
            {
                "total": {j: r["n"] for j, r in _par_jour(orders, "date_commande", n=Count("id")).items()},
                "livrees": {j: r["n"] for j, r in _par_jour(orders.filter(statut_courant="LIVRE"), "date_commande", n=Count("id")).items()},
                "annulees": {j: r["n"] for j, r in _par_jour(orders.filter(statut_courant="ANNULEE"), "date_commande", n=Count("id")).items()},
                "retours": {j: r["n"] for j, r in _par_jour(orders.filter(statut_courant="RETOUR"), "date_commande", n=Count("id")).items()},
            },
        )
        return {
            "kpis": actuel,
            "comparaison": comparaison,
            "repartition": repartition,
            "par_zone": par_zone,
            "par_paiement": par_paiement,
            "serie": serie,
            "montant_annule": _somme(orders.filter(statut_courant="ANNULEE"), F("total_a_payer")),
            "montant_retourne": _somme(orders.filter(statut_courant="RETOUR"), F("total_a_payer")),
        }


# --------------------------------------------------------------------------- #
# 7. Livraisons
# --------------------------------------------------------------------------- #


def _delais_livraison(livrees):
    """Délai EN_LIVRAISON -> LIVRE par commande (minutes), d'après
    l'historique des statuts."""
    depart, arrivee = {}, {}
    for h in (
        OrderStatusHistory.objects.filter(order__in=livrees, nouveau_statut__in=["EN_LIVRAISON", "LIVRE"])
        .values("order_id", "nouveau_statut", "timestamp")
        .order_by("timestamp")
    ):
        if h["nouveau_statut"] == "EN_LIVRAISON":
            depart.setdefault(h["order_id"], h["timestamp"])  # premier départ
        else:
            arrivee[h["order_id"]] = h["timestamp"]  # dernière livraison
    delais = {}
    for oid, fin in arrivee.items():
        debut = depart.get(oid)
        if debut and fin > debut:
            delais[oid] = (fin - debut).total_seconds() / 60
    return delais


class DeliveriesReportView(_RapportView):
    def calculer(self, ctx, request):
        orders = ctx.orders().exclude(livraison_zone="RECUPERATION")
        terminees = orders.filter(statut_courant__in=["LIVRE", "RETOUR"])
        livrees = orders.filter(statut_courant="LIVRE")
        delais = _delais_livraison(livrees)
        livreur_par_commande = dict(livrees.filter(livreur__isnull=False).values_list("id", "livreur_id"))
        delais_par_livreur = defaultdict(list)
        for oid, minutes in delais.items():
            liv = livreur_par_commande.get(oid)
            if liv:
                delais_par_livreur[liv].append(minutes)

        couts = {
            r["livreur"]: r["t"]
            for r in ctx.depenses_livreur().values("livreur").annotate(t=Coalesce(Sum("montant"), 0, output_field=_DEC))
        }
        lignes = []
        for r in (
            orders.filter(livreur__isnull=False)
            .values("livreur", nom=F("livreur__full_name"))
            .annotate(
                assignees=Count("id"),
                reussies=Count("id", filter=Q(statut_courant="LIVRE")),
                echouees=Count("id", filter=Q(statut_courant="RETOUR")),
                en_cours=Count("id", filter=Q(statut_courant="EN_LIVRAISON")),
                frais=Coalesce(Sum("frais_livraison", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
                ca=Coalesce(Sum("total_a_payer", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
            )
            .order_by("-reussies")
        ):
            total = r["reussies"] + r["echouees"]
            cout = couts.get(r["livreur"], ZERO)
            d = delais_par_livreur.get(r["livreur"], [])
            lignes.append(
                {
                    "id": r["livreur"],
                    "nom": r["nom"] or "-",
                    "assignees": r["assignees"],
                    "livraisons": total,
                    "reussies": r["reussies"],
                    "echouees": r["echouees"],
                    "en_cours": r["en_cours"],
                    "cout_total": cout,
                    "cout_moyen": (cout / total) if total else ZERO,
                    "frais_factures": r["frais"],
                    "marge_livraison": r["frais"] - cout,
                    "ca": r["ca"],
                    "taux_reussite": _taux(r["reussies"], total),
                    "taux_echec": _taux(r["echouees"], total),
                    "delai_moyen_minutes": round(sum(d) / len(d)) if d else None,
                }
            )

        nb_total = terminees.count()
        nb_reussies = livrees.count()
        cout_total = sum((l["cout_total"] for l in lignes), ZERO)
        frais_total = _somme(livrees, F("frais_livraison"))
        totaux = {
            "livraisons": nb_total,
            "reussies": nb_reussies,
            "echouees": nb_total - nb_reussies,
            "en_cours": orders.filter(statut_courant="EN_LIVRAISON").count(),
            "taux_reussite": _taux(nb_reussies, nb_total),
            "taux_echec": _taux(nb_total - nb_reussies, nb_total),
            "cout_total": cout_total,
            "cout_moyen": (cout_total / nb_total) if nb_total else ZERO,
            "frais_factures": frais_total,
            "marge_livraison": frais_total - cout_total,
            "delai_moyen_minutes": round(sum(delais.values()) / len(delais)) if delais else None,
            "nb_delais_mesures": len(delais),
        }
        par_zone = [
            {
                "zone": r["livraison_zone"],
                "livraisons": r["r"] + r["e"],
                "reussies": r["r"],
                "echouees": r["e"],
                "frais": r["f"],
                "taux_reussite": _taux(r["r"], r["r"] + r["e"]),
            }
            for r in terminees.values("livraison_zone")
            .annotate(
                r=Count("id", filter=Q(statut_courant="LIVRE")),
                e=Count("id", filter=Q(statut_courant="RETOUR")),
                f=Coalesce(Sum("frais_livraison", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
            )
            .order_by("livraison_zone")
        ]
        serie = _serie(
            ctx.date_from, ctx.date_to, ctx.granularity,
            {
                "reussies": {j: r["n"] for j, r in _par_jour(livrees, "date_commande", n=Count("id")).items()},
                "echouees": {j: r["n"] for j, r in _par_jour(orders.filter(statut_courant="RETOUR"), "date_commande", n=Count("id")).items()},
            },
        )
        return {"totaux": totaux, "par_livreur": lignes, "par_zone": par_zone, "serie": serie}


# --------------------------------------------------------------------------- #
# 8. Marketing
# --------------------------------------------------------------------------- #


def _roi(revenu, cout):
    """ROI % = (revenu − coût) / coût × 100 ; None si coût nul."""
    return round(100 * float(revenu - cout) / float(cout), 1) if cout else None


class MarketingReportView(_RapportView):
    def calculer(self, ctx, request):
        campagnes = MarketingCampaign.objects.filter(magasin__in=ctx.magasins).filter(
            Q(date_fin__isnull=True) | Q(date_fin__gte=ctx.date_from), date_debut__lte=ctx.date_to
        )
        plateforme = request.query_params.get("platform")
        if plateforme:
            campagnes = campagnes.filter(plateforme=plateforme)
        campagne_id = request.query_params.get("campaign")
        if campagne_id:
            campagnes = campagnes.filter(id=campagne_id)

        orders = ctx.orders().filter(campagne__in=campagnes)
        livrees = orders.filter(statut_courant="LIVRE")
        items = OrderItem.objects.filter(order__in=livrees, retourne=False)
        stats = {
            r["campagne"]: r
            for r in orders.values("campagne").annotate(
                commandes=Count("id"),
                livrees=Count("id", filter=Q(statut_courant="LIVRE")),
                ca=Coalesce(Sum("total_a_payer", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
            )
        }
        marges = {
            r["order__campagne"]: r["ca"] - r["cout"]
            for r in items.values("order__campagne").annotate(
                ca=Coalesce(Sum(F("prix_unitaire") * F("quantite")), 0, output_field=_DEC),
                cout=Coalesce(Sum(F("quantite") * F("product_variant__product_reference__prix_achat")), 0, output_field=_DEC),
            )
        }
        labels = dict(MarketingCampaign.PLATEFORME_CHOICES)
        lignes = []
        for c in campagnes:
            s = stats.get(c.id, {})
            ca = s.get("ca", ZERO)
            marge = marges.get(c.id, ZERO)
            lignes.append(
                {
                    "id": c.id,
                    "nom": c.nom,
                    "plateforme": c.plateforme,
                    "plateforme_label": labels.get(c.plateforme, c.plateforme),
                    "date_debut": str(c.date_debut),
                    "date_fin": str(c.date_fin) if c.date_fin else None,
                    "actif": c.actif,
                    "depenses": c.montant,
                    "commandes": s.get("commandes", 0),
                    "commandes_livrees": s.get("livrees", 0),
                    "ca": ca,
                    "marge_produits": marge,
                    "benefice": marge - c.montant,
                    "roi_pct": _roi(ca, c.montant),
                    "cout_par_commande": (c.montant / s["commandes"]) if s.get("commandes") else None,
                }
            )
        lignes.sort(key=lambda l: (l["roi_pct"] is None, -(l["roi_pct"] or 0)))

        par_plateforme = {}
        for l in lignes:
            p = par_plateforme.setdefault(
                l["plateforme"],
                {"plateforme": l["plateforme"], "label": l["plateforme_label"], "depenses": ZERO, "commandes": 0, "commandes_livrees": 0, "ca": ZERO, "nb_campagnes": 0},
            )
            p["depenses"] += l["depenses"]
            p["commandes"] += l["commandes"]
            p["commandes_livrees"] += l["commandes_livrees"]
            p["ca"] += l["ca"]
            p["nb_campagnes"] += 1
        for p in par_plateforme.values():
            p["roi_pct"] = _roi(p["ca"], p["depenses"])

        depenses = sum((l["depenses"] for l in lignes), ZERO)
        ca_total = sum((l["ca"] for l in lignes), ZERO)
        pub_caisse = _somme(ctx.caisse_sorties().filter(category__nom__iexact="Pub"), F("amount"))
        avec_roi = [l for l in lignes if l["roi_pct"] is not None]
        return {
            "totaux": {
                "depenses_campagnes": depenses,
                "depenses_pub_caisse": pub_caisse,
                "commandes": sum(l["commandes"] for l in lignes),
                "commandes_livrees": sum(l["commandes_livrees"] for l in lignes),
                "ca": ca_total,
                "marge_produits": sum((l["marge_produits"] for l in lignes), ZERO),
                "roi_pct": _roi(ca_total, depenses),
                "nb_campagnes": len(lignes),
                "commandes_sans_campagne": ctx.orders().filter(campagne__isnull=True).count(),
            },
            "campagnes": lignes,
            "par_plateforme": sorted(par_plateforme.values(), key=lambda p: -float(p["depenses"])),
            "plus_rentables": avec_roi[:3],
            "moins_rentables": list(reversed(avec_roi))[:3] if len(avec_roi) > 1 else [],
            "plateformes": [{"code": c, "label": l} for c, l in MarketingCampaign.PLATEFORME_CHOICES],
        }
