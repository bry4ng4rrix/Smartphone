"""Logique de trésorerie — source de vérité de tous les calculs financiers
(le frontend n'affiche que ce qui sort d'ici).

FORMULE OFFICIELLE (§ mission)

    gain réel = (prix de vente + livraison facturée au client)
                − prix d'achat
                − frais payés à l'agence de livraison
                − part de boost de la vente

    part de boost d'un article = montant du boost / nombre d'articles vendus
                                 sur la période exacte du boost
    résultat livraison         = livraison facturée − frais agence

RÉPARTITION du gain réel (paramétrable, défaut 60 / 25 / 15, total = 100) :
réapprovisionnement / épargne / dépenses courantes. La part épargne est
versée automatiquement au compte d'épargne à la vente.

GAIN ≤ 0 : aucune règle métier n'existait pour répartir une perte. Choix
documenté : les trois parts valent 0 et rien n'est versé à l'épargne ; la
perte est affichée telle quelle ("PERTE RÉELLE").

IDEMPOTENCE : chaque écriture automatique porte une référence unique
(VENTE:<numéro>, VERSEMENT:<numéro>, TOURNEE:<id>, ANNUL:<numéro>) protégée
par une contrainte d'unicité — rejouer une opération ne crée jamais de
doublon. Les écritures qui touchent un solde verrouillent la ligne du
magasin (select_for_update) pour sérialiser les opérations concurrentes.
"""

from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.db.models import Count, DecimalField, F, Q, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone

from catalog.models import ProductVariant
from orders.models import LivreurExpense, MarketingCampaign, Order, OrderItem
from users.models import CaisseMovement, CaisseSession, MagasinProfile

from .models import Encaissement, EpargneMouvement, FinanceSettings, VenteResultat

ZERO = Decimal("0")
CENT = Decimal("100")
_DEC = DecimalField(max_digits=14, decimal_places=2)


def q2(value):
    """Arrondi monétaire (2 décimales, demi-supérieur)."""
    return Decimal(value or 0).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _somme(qs, expression):
    return qs.aggregate(t=Coalesce(Sum(expression), 0, output_field=_DEC))["t"]


# --------------------------------------------------------------------------- #
# Paramètres et répartition
# --------------------------------------------------------------------------- #


def admin_profile_de(magasin):
    return magasin.admin.admin_profile


def parametres(magasin):
    settings, _ = FinanceSettings.objects.get_or_create(admin_profile=admin_profile_de(magasin))
    return settings


def valider_pourcentages(reappro, epargne, depenses):
    valeurs = [Decimal(str(v)) for v in (reappro, epargne, depenses)]
    if any(v < 0 for v in valeurs):
        raise ValidationError("Un pourcentage ne peut pas être négatif.")
    if sum(valeurs) != CENT:
        raise ValidationError(
            f"La répartition doit totaliser 100 % (actuellement {sum(valeurs)} %) : "
            f"réapprovisionnement {valeurs[0]} + épargne {valeurs[1]} + dépenses {valeurs[2]}."
        )
    return valeurs


def repartir(gain, pct_reappro, pct_epargne, pct_depenses):
    """Parts du gain réel. La part "dépenses" absorbe l'arrondi pour que la
    somme des trois parts soit exactement le gain. Gain ≤ 0 → 0 partout."""
    gain = q2(gain)
    if gain <= 0:
        return {"reappro": ZERO, "epargne": ZERO, "depenses": ZERO}
    reappro = q2(gain * Decimal(pct_reappro) / CENT)
    epargne = q2(gain * Decimal(pct_epargne) / CENT)
    return {"reappro": reappro, "epargne": epargne, "depenses": gain - reappro - epargne}


# --------------------------------------------------------------------------- #
# Boost
# --------------------------------------------------------------------------- #


def _fin_boost(boost):
    return boost.date_fin_effective


def commandes_du_boost(boost, date_from=None, date_to=None):
    """SOURCE UNIQUE de l'affectation automatique commande ↔ boost (§ demande) :
    les commandes du magasin dont la date de livraison prévue
    (`date_commande`, jour local Antananarivo — la référence de tout le
    reporting) tombe entre `date_debut` et `date_fin` du boost, BORNES
    COMPRISES ; boost en cours (`date_fin` vide) → jusqu'à aujourd'hui. Les
    commandes annulées ne sont pas concernées (rien généré). Aucune
    sélection manuelle : `Order.campagne` n'entre plus en jeu.

    `date_from` / `date_to` restreignent en plus à une fenêtre (rapport sur
    une période plus courte que le boost).

    Chevauchement de deux boosts : chacun retourne SES commandes ; une
    commande dans la zone commune apparaît pour les deux (règle documentée
    sur MarketingCampaign)."""
    qs = Order.objects.filter(magasin=boost.magasin).exclude(statut_courant="ANNULEE")
    if not boost.actif:
        # Boost désactivé : plus aucune commande concernée, plus aucune part
        # de coût (cohérent avec boosts_couvrant / MarketingCampaign.couvre).
        return qs.none()
    d1, d2 = boost.date_debut, _fin_boost(boost)
    if date_from and date_from > d1:
        d1 = date_from
    if date_to and date_to < d2:
        d2 = date_to
    if d1 > d2:
        return qs.none()
    return qs.filter(date_commande__date__gte=d1, date_commande__date__lte=d2)


def resume_boost(boost, date_from=None, date_to=None):
    """Indicateurs d'un boost, calculés par requête (jamais stockés) :
    commandes concernées, livrées, CA généré (commandes livrées), coût du
    boost par commande, période effective. Le coût financier retenu dans le
    gain réel reste le coût PAR ARTICLE (cout_boost_par_article) — le coût
    par commande n'est qu'un indicateur d'affichage."""
    qs = commandes_du_boost(boost, date_from, date_to)
    agg = qs.aggregate(
        nb=Count("id"),
        livrees=Count("id", filter=Q(statut_courant="LIVRE")),
        ca=Coalesce(Sum("total_a_payer", filter=Q(statut_courant="LIVRE")), 0, output_field=_DEC),
    )
    nb = agg["nb"] or 0
    return {
        "nb_commandes": nb,
        "nb_livrees": agg["livrees"] or 0,
        "ca": q2(agg["ca"]),
        "cout_par_commande": q2(Decimal(boost.montant) / nb) if nb else None,
        "periode_effective": {"from": str(boost.date_debut), "to": str(_fin_boost(boost)), "en_cours": boost.date_fin is None},
    }


def boosts_couvrant_commande(order):
    """Boosts actifs du magasin qui couvrent la date de la commande
    (l'inverse de commandes_du_boost) — pour afficher « Campagne » sur une
    commande. Liste vide sans date ou hors de toute période."""
    if order.date_commande is None:
        return MarketingCampaign.objects.none()
    return boosts_couvrant(order.magasin, timezone.localtime(order.date_commande).date())


def articles_vendus(magasin, date_from, date_to):
    """Nombre RÉEL d'articles livrés (pas de commandes) sur la période, en
    date de livraison prévue, articles rapportés exclus."""
    return (
        OrderItem.objects.filter(
            order__magasin=magasin,
            order__statut_courant="LIVRE",
            order__date_commande__date__gte=date_from,
            order__date_commande__date__lte=date_to,
            retourne=False,
        ).aggregate(n=Coalesce(Sum("quantite"), 0))["n"]
    )


def boosts_couvrant(magasin, jour):
    return MarketingCampaign.objects.filter(
        magasin=magasin, actif=True, date_debut__lte=jour
    ).filter(Q(date_fin__isnull=True) | Q(date_fin__gte=jour))


def cout_boost_par_article(boost):
    """montant / articles vendus sur la période exacte du boost ; 0 (et non
    une division par zéro) si aucun article n'a été vendu."""
    n = articles_vendus(boost.magasin, boost.date_debut, _fin_boost(boost))
    return (q2(Decimal(boost.montant) / n) if n else ZERO), n


def part_boost(magasin, jour, nb_articles):
    """Part de boost d'une vente de `nb_articles` articles le `jour` :
    somme, sur tous les boosts couvrant ce jour, du coût par article."""
    total = ZERO
    for boost in boosts_couvrant(magasin, jour):
        par_article, _ = cout_boost_par_article(boost)
        total += par_article * nb_articles
    return q2(total)


# --------------------------------------------------------------------------- #
# Gain réel d'une vente
# --------------------------------------------------------------------------- #


def frais_agence_de(order):
    if order.frais_agence is not None:
        return Decimal(order.frais_agence)
    if order.livraison_zone == "RECUPERATION":
        return ZERO
    try:
        zone = admin_profile_de(order.magasin).delivery_zones.get(code=order.livraison_zone)
    except Exception:
        return ZERO
    return Decimal(zone.cout_agence)


def calculer(order):
    """Les composantes du gain réel d'une commande livrée (sans l'écrire)."""
    items = list(order.items.filter(retourne=False).select_related("product_variant__product_reference"))
    nb_articles = sum(i.quantite for i in items)
    ca_produits = q2(sum((i.prix_unitaire * i.quantite for i in items), ZERO))
    cout_achat = q2(sum((i.product_variant.product_reference.prix_achat * i.quantite for i in items), ZERO))
    livraison_client = q2(order.frais_livraison)
    frais_agence = q2(frais_agence_de(order))
    date_vente = timezone.localtime(order.date_commande).date()
    boost = part_boost(order.magasin, date_vente, nb_articles)
    gain = ca_produits + livraison_client - cout_achat - frais_agence - boost
    return {
        "date_vente": date_vente,
        "nb_articles": nb_articles,
        "ca_produits": ca_produits,
        "livraison_client": livraison_client,
        "cout_achat": cout_achat,
        "frais_agence": frais_agence,
        "part_boost": boost,
        "gain_reel": q2(gain),
    }


def _appliquer(resultat, valeurs, settings):
    parts = repartir(valeurs["gain_reel"], settings.pct_reappro, settings.pct_epargne, settings.pct_depenses)
    for k, v in valeurs.items():
        setattr(resultat, k, v)
    resultat.pct_reappro = settings.pct_reappro
    resultat.pct_epargne = settings.pct_epargne
    resultat.pct_depenses = settings.pct_depenses
    resultat.part_reappro = parts["reappro"]
    resultat.part_epargne = parts["epargne"]
    resultat.part_depenses = parts["depenses"]


# --------------------------------------------------------------------------- #
# Épargne
# --------------------------------------------------------------------------- #


def solde_epargne(magasin):
    dernier = EpargneMouvement.objects.filter(magasin=magasin).order_by("-created_at", "-id").first()
    return dernier.solde_apres if dernier else ZERO


def _ecrire_epargne(magasin, type_, montant, motif, *, order=None, reference=None, user=None):
    """Écriture au journal d'épargne, sous verrou du magasin. `montant`
    signé. Renvoie None si la référence existe déjà (idempotence)."""
    montant = q2(montant)
    if montant == 0:
        return None
    if reference and EpargneMouvement.objects.filter(reference=reference).exists():
        return None
    MagasinProfile.objects.select_for_update().get(id=magasin.id)
    solde = solde_epargne(magasin) + montant
    try:
        return EpargneMouvement.objects.create(
            magasin=magasin, type=type_, montant=montant, solde_apres=solde, motif=motif[:255],
            order=order, reference=reference, created_by=user,
        )
    except IntegrityError:
        return None


def epargne_versee_pour(order):
    return _somme(EpargneMouvement.objects.filter(order=order), F("montant"))


def _aligner_epargne(resultat, user=None):
    """Après (re)calcul : la contribution de la vente à l'épargne doit valoir
    part_epargne (0 si annulée). Versement initial ou correction du delta."""
    if not resultat.epargne_active:
        return
    cible = ZERO if resultat.annule else resultat.part_epargne
    order = resultat.order
    delta = cible - epargne_versee_pour(order)
    if delta == 0:
        return
    reference = f"VERSEMENT:{order.numero}"
    if delta > 0 and not resultat.annule and not EpargneMouvement.objects.filter(reference=reference).exists():
        _ecrire_epargne(
            resultat.magasin, "VERSEMENT", delta, f"Vente {order.numero} — {resultat.pct_epargne} % du gain réel",
            order=order, reference=reference, user=user,
        )
        return
    if resultat.annule:
        motif = f"Annulation vente {order.numero}"
    elif delta > 0 and epargne_versee_pour(order) == 0:
        motif = f"Vente {order.numero} rétablie"
    else:
        motif = f"Recalcul gain vente {order.numero}"
    _ecrire_epargne(resultat.magasin, "CORRECTION", delta, motif, order=order, user=user)


@transaction.atomic
def retirer_epargne(magasin, user, montant, motif=""):
    montant = q2(montant)
    if montant <= 0:
        raise ValidationError("Le montant du retrait doit être positif.")
    MagasinProfile.objects.select_for_update().get(id=magasin.id)
    solde = solde_epargne(magasin)
    if montant > solde:
        raise ValidationError(f"Retrait impossible : l'épargne disponible est de {solde} Ar.")
    return _ecrire_epargne(magasin, "RETRAIT", -montant, motif or "Retrait d'épargne", user=user)


# --------------------------------------------------------------------------- #
# Caisse
# --------------------------------------------------------------------------- #


def session_ouverte(magasin, verrouiller=False):
    qs = CaisseSession.objects.filter(magasin=magasin, status="open").order_by("-opened_at")
    if verrouiller:
        qs = qs.select_for_update()
    return qs.first()


def solde_session(session):
    totaux = session.movements.aggregate(
        i=Coalesce(Sum("amount", filter=Q(movement_type="in")), 0, output_field=_DEC),
        o=Coalesce(Sum("amount", filter=Q(movement_type="out")), 0, output_field=_DEC),
    )
    return session.opening_balance + totaux["i"] - totaux["o"]


def solde_caisse(magasin):
    """Espèces en caisse maintenant : la session ouverte (fond + entrées −
    sorties), sinon le dernier montant compté à la fermeture."""
    session = session_ouverte(magasin)
    if session:
        return solde_session(session), session
    derniere = CaisseSession.objects.filter(magasin=magasin, status="closed").order_by("-closed_at").first()
    return (derniere.closing_balance if derniere and derniere.closing_balance is not None else ZERO), None


def mouvement_caisse(session, movement_type, amount, reason, origine, reference, user, category=None):
    """Mouvement automatique idempotent : (mouvement, créé)."""
    existant = CaisseMovement.objects.filter(reference=reference).first()
    if existant:
        return existant, False
    try:
        with transaction.atomic():
            mvt = CaisseMovement.objects.create(
                session=session, magasin=session.magasin, movement_type=movement_type, amount=q2(amount),
                reason=reason[:255], category=category, origine=origine, reference=reference, created_by=user,
            )
        return mvt, True
    except IntegrityError:
        return CaisseMovement.objects.get(reference=reference), False


# --------------------------------------------------------------------------- #
# Vente livrée → résultat, encaissement, épargne
# --------------------------------------------------------------------------- #


def _source_encaissement(order):
    if order.livraison_zone == "RECUPERATION":
        return "COMPTOIR"
    if order.mode_paiement == "AVANT":
        return "PREPAYE"
    return "LIVREUR"


def _periodes_a_recalculer(magasin, jour):
    """Union des périodes des boosts couvrant `jour` (ou le jour seul)."""
    boosts = list(boosts_couvrant(magasin, jour))
    if not boosts:
        return jour, jour
    return min(b.date_debut for b in boosts), max(_fin_boost(b) for b in boosts)


@transaction.atomic
def recalculer_ventes(magasin, date_from, date_to, user=None):
    """Recalcule gain et répartition de toutes les ventes livrées de la
    plage (la part de boost dépend du nombre total d'articles vendus sur la
    période) et aligne l'épargne de chacune."""
    settings = parametres(magasin)
    modifies = 0
    for resultat in (
        VenteResultat.objects.select_for_update()
        .filter(magasin=magasin, annule=False, date_vente__gte=date_from, date_vente__lte=date_to)
        .select_related("order")
    ):
        avant = (resultat.gain_reel, resultat.part_boost)
        _appliquer(resultat, calculer(resultat.order), settings)
        if (resultat.gain_reel, resultat.part_boost) != avant:
            resultat.save()
            _aligner_epargne(resultat, user)
            modifies += 1
    return modifies


@transaction.atomic
def recalculer_apres_boost(magasin, periodes, user=None):
    """Recalcul automatique après création / modification / désactivation /
    suppression d'un boost (§ demande) : toutes les ventes de l'UNION des
    périodes concernées — l'ancienne ET la nouvelle — sont recalculées, pour
    que les ventes sorties de la période perdent leur part et que celles qui
    y entrent la reçoivent. `periodes` : liste de (date_debut, date_fin)."""
    periodes = [(d1, d2 or timezone.localdate()) for d1, d2 in periodes if d1]
    if not periodes:
        return 0
    return recalculer_ventes(magasin, min(p[0] for p in periodes), max(p[1] for p in periodes), user)


@transaction.atomic
def enregistrer_vente(order, user=None):
    """Appelée quand une commande passe à LIVRE (orders/services.py).
    Idempotente : rejouer ne crée ni doublon ni second versement."""
    if order.statut_courant != "LIVRE":
        raise ValidationError("Seule une commande livrée produit un résultat de vente.")
    magasin = order.magasin
    settings = parametres(magasin)

    resultat, _ = VenteResultat.objects.select_for_update().get_or_create(
        order=order, defaults={"magasin": magasin, "date_vente": timezone.localtime(order.date_commande).date()}
    )
    resultat.annule = False
    resultat.magasin = magasin
    _appliquer(resultat, calculer(order), settings)
    resultat.save()

    encaissement, _ = Encaissement.objects.get_or_create(
        order=order,
        defaults={
            "magasin": magasin, "livreur": order.livreur, "source": _source_encaissement(order),
            "montant": q2(order.total_a_payer),
        },
    )
    if encaissement.statut == "ANNULE":
        encaissement.statut = "EN_ATTENTE"
    if encaissement.statut == "EN_ATTENTE":
        encaissement.montant = q2(order.total_a_payer)
        encaissement.livreur = order.livreur
        encaissement.source = _source_encaissement(order)
        encaissement.save()
        # Argent déjà entre nos mains (comptoir, payé d'avance) : en caisse
        # tout de suite si elle est ouverte, sinon reste "à enregistrer".
        if encaissement.source != "LIVREUR":
            session = session_ouverte(magasin, verrouiller=True)
            if session:
                _remettre(encaissement, session, user)

    # La part de boost des autres ventes de la période change avec ce
    # nouvel article vendu : on recalcule la période (cette vente comprise).
    d1, d2 = _periodes_a_recalculer(magasin, resultat.date_vente)
    recalculer_ventes(magasin, d1, d2, user)
    resultat.refresh_from_db()
    _aligner_epargne(resultat, user)
    return resultat


@transaction.atomic
def annuler_vente(order, user=None):
    """Vente corrigée en retour (corriger_statut LIVRE → RETOUR) : le
    résultat est conservé mais annulé, l'épargne versée est reprise, et si
    l'argent était déjà en caisse une sortie de remboursement est écrite."""
    try:
        resultat = VenteResultat.objects.select_for_update().get(order=order)
    except VenteResultat.DoesNotExist:
        resultat = None
    if resultat and not resultat.annule:
        resultat.annule = True
        resultat.save(update_fields=["annule", "maj_le"])
        _aligner_epargne(resultat, user)

    encaissement = Encaissement.objects.select_for_update().filter(order=order).first()
    if encaissement and encaissement.statut != "ANNULE":
        if encaissement.statut == "REMIS" and encaissement.caisse_movement_id:
            session = session_ouverte(order.magasin, verrouiller=True)
            if not session:
                raise ValidationError(
                    "L'argent de cette vente est déjà en caisse : ouvrez la caisse pour enregistrer le remboursement."
                )
            mouvement_caisse(
                session, "out", encaissement.montant, f"Annulation vente {order.numero} — {order.client_nom}",
                "ANNULATION_VENTE", f"ANNUL:{order.numero}", user,
            )
        encaissement.statut = "ANNULE"
        encaissement.save(update_fields=["statut"])

    if resultat:
        d1, d2 = _periodes_a_recalculer(order.magasin, resultat.date_vente)
        recalculer_ventes(order.magasin, d1, d2, user)


# --------------------------------------------------------------------------- #
# Remise de l'argent en caisse
# --------------------------------------------------------------------------- #


def _remettre(encaissement, session, user):
    mvt, _ = mouvement_caisse(
        session, "in", encaissement.montant,
        f"Vente {encaissement.order.numero} — {encaissement.order.client_nom}",
        "VENTE", f"VENTE:{encaissement.order.numero}", user,
    )
    encaissement.statut = "REMIS"
    encaissement.remis_le = timezone.now()
    encaissement.remis_par = user
    encaissement.caisse_movement = mvt
    encaissement.save()
    return mvt


def depenses_livreur_non_remises(magasin, livreur_id, depuis):
    """Frais de tournée acceptés (à partir de la date `depuis`, celle de la
    plus ancienne tournée remise) que le livreur a gardés sur ses
    encaissements et qui ne sont pas encore passés en sortie de caisse."""
    if depuis is None:
        return []
    deja = set(
        CaisseMovement.objects.filter(magasin=magasin, reference__startswith="TOURNEE:")
        .values_list("reference", flat=True)
    )
    return [
        d for d in LivreurExpense.objects.filter(magasin=magasin, livreur_id=livreur_id, statut="ACCEPTE", date__gte=depuis)
        .select_related("livreur", "type_depense")
        if f"TOURNEE:{d.id}" not in deja
    ]


@transaction.atomic
def remettre_encaissements(magasin, user, livreur_id=None, encaissement_ids=None, inclure_depenses=True):
    """Remise en caisse des encaissements en attente (d'un livreur, ou une
    sélection). Une entrée VENTE par commande, et, pour un livreur, une
    sortie FRAIS_LIVRAISON par frais de tournée accepté non encore déduit —
    l'entrée nette en caisse est donc encaissé − dépenses, comme le bilan."""
    session = session_ouverte(magasin, verrouiller=True)
    if not session:
        raise ValidationError("Aucune session de caisse ouverte : ouvrez la caisse avant d'enregistrer une remise.")
    qs = Encaissement.objects.select_for_update().filter(magasin=magasin, statut="EN_ATTENTE").select_related("order")
    if livreur_id:
        qs = qs.filter(livreur_id=livreur_id)
    if encaissement_ids:
        qs = qs.filter(id__in=encaissement_ids)
    remis = []
    for enc in qs.order_by("created_at"):
        _remettre(enc, session, user)
        remis.append(enc)

    depenses = []
    if livreur_id and inclure_depenses and remis:
        depuis = min(timezone.localtime(e.order.date_commande).date() for e in remis)
        for d in depenses_livreur_non_remises(magasin, livreur_id, depuis):
            mouvement_caisse(
                session, "out", d.montant,
                f"Frais de tournée {d.libelle} — {d.livreur.full_name if d.livreur else ''} ({d.date:%d/%m/%Y})",
                "FRAIS_LIVRAISON", f"TOURNEE:{d.id}", user,
            )
            depenses.append(d)
    brut = sum((e.montant for e in remis), ZERO)
    frais = sum((d.montant for d in depenses), ZERO)
    return {"nb": len(remis), "brut": brut, "depenses": frais, "net": brut - frais, "session_id": session.id}


# --------------------------------------------------------------------------- #
# Lectures : journal, indicateurs, statistiques
# --------------------------------------------------------------------------- #


def valeur_stock(magasins):
    qs = ProductVariant.objects.filter(
        product_reference__type__category__magasin__in=magasins, stock_actuel__gt=0
    )
    return {
        "valeur_achat": _somme(qs, F("stock_actuel") * F("product_reference__prix_achat")),
        "valeur_vente": _somme(qs, F("stock_actuel") * F("product_reference__prix_vente")),
        "quantite": qs.aggregate(q=Coalesce(Sum("stock_actuel"), 0))["q"],
    }


def journal(magasins, date_from=None, date_to=None, origine=None):
    """Mouvements de caisse avec solde après chaque mouvement. Le solde
    repart du fond d'ouverture à chaque session (le montant compté à la
    fermeture précédente est le nouveau point de départ physique)."""
    qs = CaisseMovement.objects.filter(magasin__in=magasins).select_related("session", "category", "created_by")
    if date_from:
        qs = qs.filter(created_at__date__gte=date_from)
    if date_to:
        qs = qs.filter(created_at__date__lte=date_to)
    if origine:
        qs = qs.filter(origine=origine)
    sessions = {s.id: s for s in CaisseSession.objects.filter(movements__in=qs).distinct()}
    # Solde : il faut tous les mouvements des sessions concernées, même
    # hors plage, pour partir du bon point.
    tous = CaisseMovement.objects.filter(session_id__in=sessions.keys()).order_by("session_id", "created_at", "id")
    soldes = {}
    courant = {}
    for m in tous:
        s = sessions[m.session_id]
        solde = courant.get(m.session_id, s.opening_balance)
        solde = solde + m.amount if m.movement_type == "in" else solde - m.amount
        courant[m.session_id] = solde
        soldes[m.id] = solde
    origines = dict(CaisseMovement.ORIGINES)
    return [
        {
            "id": m.id,
            "date": m.created_at.isoformat(),
            "session_id": m.session_id,
            "type": m.movement_type,
            "origine": m.origine,
            "origine_label": origines.get(m.origine, m.origine),
            "entree": m.amount if m.movement_type == "in" else ZERO,
            "sortie": m.amount if m.movement_type == "out" else ZERO,
            "montant": m.amount,
            "libelle": m.reason,
            "categorie": m.category.nom if m.category else "",
            "reference": m.reference or "",
            "solde_apres": soldes.get(m.id, ZERO),
            "auteur": m.created_by.full_name if m.created_by else "",
            "automatique": bool(m.reference),
        }
        for m in qs.order_by("-created_at", "-id")
    ]


def _etat(resultat):
    return "benefice" if resultat > 0 else "perte" if resultat < 0 else "equilibre"


def stats_livraison(magasins, date_from, date_to):
    qs = VenteResultat.objects.filter(magasin__in=magasins, annule=False, date_vente__gte=date_from, date_vente__lte=date_to)
    facturee = _somme(qs, F("livraison_client"))
    agence = _somme(qs, F("frais_agence"))
    return {
        "from": str(date_from), "to": str(date_to), "nb": qs.count(),
        "facturee": facturee, "agence": agence, "resultat": facturee - agence, "etat": _etat(facturee - agence),
    }


def stats_gain(magasins, date_from, date_to):
    qs = VenteResultat.objects.filter(magasin__in=magasins, annule=False, date_vente__gte=date_from, date_vente__lte=date_to)
    agg = qs.aggregate(
        ca=Coalesce(Sum("ca_produits"), 0, output_field=_DEC),
        liv=Coalesce(Sum("livraison_client"), 0, output_field=_DEC),
        cout=Coalesce(Sum("cout_achat"), 0, output_field=_DEC),
        agence=Coalesce(Sum("frais_agence"), 0, output_field=_DEC),
        boost=Coalesce(Sum("part_boost"), 0, output_field=_DEC),
        gain=Coalesce(Sum("gain_reel"), 0, output_field=_DEC),
        reappro=Coalesce(Sum("part_reappro"), 0, output_field=_DEC),
        epargne=Coalesce(Sum("part_epargne"), 0, output_field=_DEC),
        depenses=Coalesce(Sum("part_depenses"), 0, output_field=_DEC),
        articles=Coalesce(Sum("nb_articles"), 0),
    )
    return {
        "nb_ventes": qs.count(),
        "nb_articles": agg["articles"],
        "nb_pertes": qs.filter(gain_reel__lt=0).count(),
        "ca_produits": agg["ca"],
        "livraison_client": agg["liv"],
        "total_encaisse": agg["ca"] + agg["liv"],
        "cout_achat": agg["cout"],
        "frais_agence": agg["agence"],
        "part_boost": agg["boost"],
        "gain_reel": agg["gain"],
        "etat": _etat(agg["gain"]),
        "repartition": {"reappro": agg["reappro"], "epargne": agg["epargne"], "depenses": agg["depenses"]},
    }


def boosts_periode(magasins, date_from, date_to):
    qs = MarketingCampaign.objects.filter(magasin__in=magasins, date_debut__lte=date_to).filter(
        Q(date_fin__isnull=True) | Q(date_fin__gte=date_from)
    ).select_related("magasin")
    en_caisse = set(
        CaisseMovement.objects.filter(reference__startswith="BOOST:").values_list("reference", flat=True)
    )
    out = []
    for b in qs:
        par_article, n = cout_boost_par_article(b)
        out.append(
            {
                "id": b.id, "nom": b.nom, "plateforme": b.plateforme, "plateforme_label": b.get_plateforme_display(),
                "type_periode": b.type_periode, "date_debut": str(b.date_debut), "date_fin": str(b.date_fin) if b.date_fin else None,
                "montant": b.montant, "articles_vendus": n, "cout_par_article": par_article, "actif": b.actif,
                "en_caisse": f"BOOST:{b.id}" in en_caisse,
                # Affectation automatique par période (§ demande).
                **resume_boost(b),
            }
        )
    return out


def encaissements_en_attente(magasins):
    qs = Encaissement.objects.filter(magasin__in=magasins, statut="EN_ATTENTE").select_related("order", "livreur")
    lignes = [
        {
            "id": e.id, "order_id": e.order_id, "numero": e.order.numero, "client": e.order.client_nom,
            "montant": e.montant, "source": e.source, "source_label": e.get_source_display(),
            "livreur_id": e.livreur_id, "livreur": e.livreur.full_name if e.livreur else "",
            "date": e.created_at.isoformat(), "date_commande": timezone.localtime(e.order.date_commande).date().isoformat(),
        }
        for e in qs.order_by("livreur_id", "created_at")
    ]
    par_livreur = {}
    for l in lignes:
        cle = l["livreur_id"] or 0
        p = par_livreur.setdefault(
            cle, {"livreur_id": l["livreur_id"], "nom": l["livreur"] or ("Comptoir / payé d'avance"), "nb": 0, "brut": ZERO, "depenses": ZERO, "net": ZERO}
        )
        p["nb"] += 1
        p["brut"] += l["montant"]
    for cle, p in par_livreur.items():
        if p["livreur_id"]:
            depuis = min(date.fromisoformat(l["date_commande"]) for l in lignes if l["livreur_id"] == p["livreur_id"])
            for magasin in magasins:
                p["depenses"] += sum((d.montant for d in depenses_livreur_non_remises(magasin, p["livreur_id"], depuis)), ZERO)
        p["net"] = p["brut"] - p["depenses"]
    total = sum((l["montant"] for l in lignes), ZERO)
    return {
        "lignes": lignes,
        "par_livreur": list(par_livreur.values()),
        "total": total,
        "chez_livreurs": sum((l["montant"] for l in lignes if l["source"] == "LIVREUR"), ZERO),
        "a_enregistrer": sum((l["montant"] for l in lignes if l["source"] != "LIVREUR"), ZERO),
    }


def indicateurs(magasins):
    """Les 4 indicateurs de tête + leurs composantes."""
    solde = ZERO
    epargne = ZERO
    session_ouverte_ids = []
    for m in magasins:
        s, session = solde_caisse(m)
        solde += s
        epargne += solde_epargne(m)
        if session:
            session_ouverte_ids.append(session.id)
    stock = valeur_stock(magasins)
    attente = encaissements_en_attente(magasins)
    return {
        "espece_disponible": solde - epargne,
        "solde_caisse": solde,
        "session_ouverte": bool(session_ouverte_ids),
        "epargne_couverte": epargne <= solde,
        "valeur_stock": stock["valeur_achat"],
        "valeur_stock_vente": stock["valeur_vente"],
        "quantite_stock": stock["quantite"],
        "argent_en_attente": attente["total"],
        "attente_livreurs": attente["chez_livreurs"],
        "attente_a_enregistrer": attente["a_enregistrer"],
        "epargne": epargne,
    }


def periodes_standard(aujourd_hui=None):
    j = aujourd_hui or timezone.localdate()
    lundi = j - timedelta(days=j.weekday())
    return {"jour": (j, j), "semaine": (lundi, j), "mois": (j.replace(day=1), j)}


def tableau_de_bord(magasins, date_from, date_to):
    settings = parametres(magasins[0]) if magasins else None
    std = periodes_standard()
    return {
        "indicateurs": indicateurs(magasins),
        "periode": {"from": str(date_from), "to": str(date_to)},
        "gain": stats_gain(magasins, date_from, date_to),
        "repartition_pct": {
            "reappro": settings.pct_reappro if settings else 60,
            "epargne": settings.pct_epargne if settings else 25,
            "depenses": settings.pct_depenses if settings else 15,
        },
        "livraison": {
            "periode": stats_livraison(magasins, date_from, date_to),
            "jour": stats_livraison(magasins, *std["jour"]),
            "semaine": stats_livraison(magasins, *std["semaine"]),
            "mois": stats_livraison(magasins, *std["mois"]),
        },
        "boosts": boosts_periode(magasins, date_from, date_to),
        "encaissements": encaissements_en_attente(magasins),
        "epargne": {
            "solde": sum((solde_epargne(m) for m in magasins), ZERO),
            "verse_periode": _somme(
                EpargneMouvement.objects.filter(magasin__in=magasins, type="VERSEMENT", created_at__date__gte=date_from, created_at__date__lte=date_to),
                F("montant"),
            ),
            "retire_periode": -_somme(
                EpargneMouvement.objects.filter(magasin__in=magasins, type="RETRAIT", created_at__date__gte=date_from, created_at__date__lte=date_to),
                F("montant"),
            ),
        },
    }


def ventes(magasins, date_from, date_to):
    qs = (
        VenteResultat.objects.filter(magasin__in=magasins, date_vente__gte=date_from, date_vente__lte=date_to)
        .select_related("order", "order__livreur")
        .order_by("-date_vente", "-id")
    )
    encaisse = {e.order_id: e for e in Encaissement.objects.filter(order__in=[r.order_id for r in qs])}
    return [
        {
            "id": r.id, "order_id": r.order_id, "numero": r.order.numero, "client": r.order.client_nom,
            "date_vente": str(r.date_vente), "livreur": r.order.livreur.full_name if r.order.livreur else "",
            "zone": r.order.livraison_zone, "nb_articles": r.nb_articles,
            "ca_produits": r.ca_produits, "livraison_client": r.livraison_client, "total_client": r.ca_produits + r.livraison_client,
            "cout_achat": r.cout_achat, "frais_agence": r.frais_agence, "resultat_livraison": r.resultat_livraison,
            "part_boost": r.part_boost, "gain_reel": r.gain_reel, "etat": _etat(r.gain_reel),
            "part_reappro": r.part_reappro, "part_epargne": r.part_epargne, "part_depenses": r.part_depenses,
            "annule": r.annule,
            "encaissement": (encaisse[r.order_id].get_statut_display() if r.order_id in encaisse else ""),
            "encaissement_statut": (encaisse[r.order_id].statut if r.order_id in encaisse else ""),
        }
        for r in qs
    ]
