"""Règles métier du module Fournisseur (approvisionnements).

Cycle (§ demande) :

    Fournisseur → Approvisionnement (1 produit, 1 quantité)
      → Paiement 1 → Préparation → Paiement 2 → Départ Chine → Transit
      → Arrivée Madagascar → Frais + Douane
      → Coût total rendu Madagascar → Coût de revient par pièce

Formules (§ 20), toutes en ariary :

    total fournisseur MGA      = Σ montant_mga de chaque paiement
                                 (montant devise × taux DU JOUR du paiement)
    coût total rendu Madagascar = total fournisseur MGA + Frais + Douane
    coût de revient par pièce   = coût total rendu Madagascar / quantité
    marge                       = prix de vente − coût de revient par pièce

Le stock n'est jamais touché ici directement : la réception passe par
catalog.services.apply_stock_movement (origine FOURNISSEUR), à la
finalisation du coût (§ 13).
"""
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Count, Q, Sum
from django.utils import timezone

from catalog.services import apply_stock_movement

from .models import DEUX_DEC, ZERO, Supplier, SupplierOrder, SupplierPayment, convertir_en_mga

# Statuts « en cours » (ni brouillon ni terminé) pour les indicateurs.
STATUTS_EN_COURS = {"COMMANDE", "ACOMPTE_PAYE", "PREPARATION", "PAYE", "EXPEDIE", "EN_TRANSIT", "ARRIVE"}
# À partir d'ici la marchandise a quitté le fournisseur : le statut de
# paiement ne fait plus reculer l'avancement.
STATUTS_EXPEDIES = {"EXPEDIE", "EN_TRANSIT", "ARRIVE", "COUT_FINALISE"}


def _rang(statut):
    return SupplierOrder.STATUT_ORDER.index(statut) if statut in SupplierOrder.STATUT_ORDER else -1


def _verifier_modifiable(order):
    if order.est_finalise:
        raise ValidationError("Cet approvisionnement est finalisé : son coût de revient ne peut plus changer.")


def _verifier_fournisseur(magasin, supplier):
    if supplier is not None and supplier.admin_profile_id != magasin.admin.admin_profile.id:
        raise ValidationError({"supplier": "Ce fournisseur n'appartient pas à votre société."})


def _verifier_produit(magasin, variant):
    if variant is None:
        raise ValidationError({"product_variant": "Un approvisionnement porte sur un produit."})
    if variant.product_reference.type.category.magasin_id != magasin.id:
        raise ValidationError({"product_variant": "Ce produit n'appartient pas à ce magasin."})


# --------------------------------------------------------------------------- #
# Création / modification
# --------------------------------------------------------------------------- #


@transaction.atomic
def create_supplier_order(*, magasin, created_by, product_variant, quantite, supplier=None, devise="USD",
                          montant_prevu=0, description="", date=None, statut="BROUILLON"):
    """UN produit, UNE quantité (§ 3). `montant_prevu` : total convenu avec
    le fournisseur, dans `devise` (facultatif, sert au « reste à payer »)."""
    _verifier_fournisseur(magasin, supplier)
    _verifier_produit(magasin, product_variant)
    if not quantite or int(quantite) <= 0:
        raise ValidationError({"quantite": "La quantité doit être supérieure à zéro."})
    order = SupplierOrder.objects.create(
        magasin=magasin,
        supplier=supplier,
        product_variant=product_variant,
        quantite=int(quantite),
        devise=devise or (supplier.devise if supplier else "USD"),
        montant_prevu=Decimal(str(montant_prevu or 0)),
        description=description or "",
        statut=statut if statut in ("BROUILLON", "COMMANDE") else "BROUILLON",
        created_by=created_by,
        **({"date": date} if date else {}),
    )
    return recompute_costs(order)


@transaction.atomic
def update_supplier_order(*, order, data):
    """Données générales / produit / quantité / transport / Frais + Douane,
    tant que le coût n'est pas finalisé. La quantité ne peut pas passer sous
    la quantité déjà réceptionnée."""
    _verifier_modifiable(order)
    champs = (
        "description", "supplier", "devise", "montant_prevu", "date", "product_variant", "quantite",
        "date_expedition", "transporteur", "mode_transport", "tracking", "numero_colis", "lieu_depart",
        "destination", "date_arrivee", "commentaire_transport", "frais_douane_mga",
    )
    # `null` explicite accepté pour retirer le fournisseur ou effacer une
    # date ; les autres champs ignorent null.
    effacables = {"supplier", "date_expedition", "date_arrivee"}
    for champ in champs:
        if champ in data and (data[champ] is not None or champ in effacables):
            setattr(order, champ, data[champ])
    if "supplier" in data:
        _verifier_fournisseur(order.magasin, order.supplier)
    if "product_variant" in data:
        _verifier_produit(order.magasin, order.product_variant)
    if order.quantite <= 0:
        raise ValidationError({"quantite": "La quantité doit être supérieure à zéro."})
    if order.quantite < order.quantite_recue:
        raise ValidationError({"quantite": f"{order.quantite_recue} pièce(s) déjà réceptionnée(s) : quantité minimale {order.quantite_recue}."})
    if Decimal(order.frais_douane_mga or 0) < 0:
        raise ValidationError({"frais_douane_mga": "Le montant Frais + Douane ne peut pas être négatif."})
    order.save()
    return recompute_costs(order)


# --------------------------------------------------------------------------- #
# Calcul du coût réel
# --------------------------------------------------------------------------- #


@transaction.atomic
def recompute_costs(order):
    """Applique les formules (§ 10-11) et fige le résultat sur l'appro.
    Sans effet sur un approvisionnement déjà finalisé (coût historique)."""
    order = SupplierOrder.objects.select_for_update().get(pk=order.pk)
    if order.est_finalise:
        return order
    total = order.payments.aggregate(t=Sum("montant_mga"))["t"] or ZERO
    order.total_paiements_mga = Decimal(total).quantize(DEUX_DEC)
    order.cout_total_mga = (order.total_paiements_mga + Decimal(order.frais_douane_mga or 0)).quantize(DEUX_DEC)
    order.cout_unitaire_mga = (order.cout_total_mga / order.quantite).quantize(DEUX_DEC) if order.quantite else ZERO
    _ajuster_statut_paiement(order)
    order.save()
    return order


def _ajuster_statut_paiement(order):
    """COMMANDE / ACOMPTE_PAYE / PAYE suivent les paiements (§ 15) tant que
    la marchandise n'est pas expédiée ; PREPARATION est posé à la main et
    n'est pas remis en cause par un paiement. « Entièrement payé » = total
    payé ≥ montant prévu (quand un montant prévu existe)."""
    if order.statut in STATUTS_EXPEDIES or order.statut == "BROUILLON":
        return
    prevu = Decimal(order.montant_prevu or 0)
    paye = order.total_paye_devise if order.devise != "MGA" else Decimal(order.total_paiements_mga)
    if prevu and paye >= prevu:
        order.statut = "PAYE"
    elif paye > 0:
        order.statut = "PREPARATION" if order.statut == "PREPARATION" else "ACOMPTE_PAYE"
    else:
        order.statut = "PREPARATION" if order.statut == "PREPARATION" else "COMMANDE"


# --------------------------------------------------------------------------- #
# Paiements (§ 4-6)
# --------------------------------------------------------------------------- #


@transaction.atomic
def add_payment(*, order, user, montant, devise, taux_change=None, date=None, type_paiement="ACOMPTE",
                methode="VIREMENT", reference="", commentaire="", justificatif=None):
    """Chaque paiement garde SON taux : montant_mga = montant × taux du jour,
    jamais recalculé ensuite."""
    _verifier_modifiable(order)
    montant = Decimal(str(montant))
    if montant <= 0:
        raise ValidationError({"montant": "Le montant doit être supérieur à zéro."})
    if devise != "MGA" and (not taux_change or Decimal(str(taux_change)) <= 0):
        raise ValidationError({"taux_change": "Le taux de change du jour (Ar pour 1 unité de devise) est requis."})
    if order.statut == "BROUILLON":
        order.statut = "COMMANDE"
        order.save(update_fields=["statut"])
    payment = SupplierPayment.objects.create(
        supplier_order=order, montant=montant, devise=devise, taux_change=Decimal(str(taux_change or 1)),
        type_paiement=type_paiement, methode=methode, reference=reference or "", commentaire=commentaire or "",
        justificatif=justificatif, created_by=user, **({"date": date} if date else {}),
    )
    recompute_costs(order)
    return payment


@transaction.atomic
def delete_payment(*, order, payment_id):
    _verifier_modifiable(order)
    deleted, _ = order.payments.filter(pk=payment_id).delete()
    if not deleted:
        raise ValidationError({"payment": "Paiement introuvable."})
    recompute_costs(order)


# --------------------------------------------------------------------------- #
# Workflow (§ 7-9, 15)
# --------------------------------------------------------------------------- #


def _avancer(order, nouveau, depuis):
    _verifier_modifiable(order)
    if order.statut not in depuis:
        raise ValidationError(
            f"Passage « {order.get_statut_display()} » → « {dict(SupplierOrder.STATUT_CHOICES)[nouveau]} » impossible."
        )
    order.statut = nouveau


@transaction.atomic
def commander(order):
    _avancer(order, "COMMANDE", {"BROUILLON"})
    order.save(update_fields=["statut"])
    return recompute_costs(order)


@transaction.atomic
def preparer(order):
    """Le fournisseur prépare la marchandise (après le premier paiement)."""
    _avancer(order, "PREPARATION", {"COMMANDE", "ACOMPTE_PAYE", "PAYE"})
    order.save(update_fields=["statut"])
    return recompute_costs(order)


@transaction.atomic
def expedier(order, **transport):
    """Départ de Chine : date, transporteur, mode, tracking, n° colis…"""
    _avancer(order, "EXPEDIE", {"COMMANDE", "ACOMPTE_PAYE", "PREPARATION", "PAYE"})
    for champ in ("date_expedition", "transporteur", "mode_transport", "tracking", "numero_colis", "lieu_depart",
                  "destination", "commentaire_transport"):
        if champ in transport and transport[champ] is not None:
            setattr(order, champ, transport[champ])
    if not order.date_expedition:
        order.date_expedition = timezone.localdate()
    order.save()
    return order


@transaction.atomic
def transit(order, **transport):
    _avancer(order, "EN_TRANSIT", {"EXPEDIE"})
    for champ in ("transporteur", "mode_transport", "tracking", "numero_colis", "commentaire_transport"):
        if champ in transport and transport[champ] is not None:
            setattr(order, champ, transport[champ])
    order.save()
    return order


@transaction.atomic
def arriver(order, date_arrivee=None, frais_douane_mga=None):
    """Arrivée à Madagascar. Le montant Frais + Douane peut être saisi ici
    ou plus tard (PATCH), avant la finalisation."""
    _avancer(order, "ARRIVE", {"EXPEDIE", "EN_TRANSIT"})
    order.date_arrivee = date_arrivee or timezone.localdate()
    if frais_douane_mga is not None:
        order.frais_douane_mga = Decimal(str(frais_douane_mga))
    order.save()
    return recompute_costs(order)


@transaction.atomic
def finaliser_cout(order, user, mettre_a_jour_prix_achat=True, quantite_recue=None):
    """Arrivé → Coût finalisé (§ 10-13) : fige le coût total et le coût de
    revient par pièce, RÉCEPTIONNE la marchandise dans le stock (entrée
    référencée par le n° d'appro, coût unitaire dans la note) et, si demandé,
    met à jour le prix d'achat de référence du produit (moyenne pondérée
    avec le stock existant).

    `quantite_recue` : pièces réellement arrivées (défaut : la quantité
    commandée). Le coût de revient reste calculé sur la quantité
    commandée ; le stock, lui, reçoit ce qui est réellement arrivé."""
    if order.statut != "ARRIVE":
        raise ValidationError("Le coût ne se finalise qu'une fois la marchandise arrivée à Madagascar.")
    order = recompute_costs(order)
    a_recevoir = int(quantite_recue) if quantite_recue is not None else order.quantite
    if a_recevoir < 0 or a_recevoir > order.quantite:
        raise ValidationError({"quantite_recue": f"La quantité reçue doit être comprise entre 0 et {order.quantite}."})
    deja = order.quantite_recue
    delta = a_recevoir - deja
    variant = order.product_variant
    if delta < 0:
        raise ValidationError({"quantite_recue": f"{deja} pièce(s) déjà réceptionnée(s)."})
    if delta > 0:
        if mettre_a_jour_prix_achat:
            _mettre_a_jour_prix_achat(variant, delta, order.cout_unitaire_mga)
        apply_stock_movement(
            variant, "ENTREE", delta, origine="FOURNISSEUR", user=user, reference=order.numero,
            note=f"Réception approvisionnement {order.numero} — {delta} pièce(s) à {order.cout_unitaire_mga} Ar",
        )
    order.quantite_recue = a_recevoir
    order.received_at = order.received_at or timezone.now()
    order.statut = "COUT_FINALISE"
    order.finalise_at = timezone.now()
    order.save()
    return order


def _mettre_a_jour_prix_achat(variant, quantite, cout_unitaire):
    """Nouveau prix d'achat de référence = moyenne pondérée (stock actuel au
    prix actuel + pièces reçues au coût de revient). Stock vide → le coût de
    revient devient le prix d'achat."""
    reference = variant.product_reference
    stock = max(int(variant.stock_actuel or 0), 0)
    ancien = Decimal(reference.prix_achat or 0)
    cout = Decimal(cout_unitaire or 0)
    total_qty = stock + int(quantite)
    if total_qty <= 0:
        return
    nouveau = ((ancien * stock + cout * int(quantite)) / total_qty).quantize(DEUX_DEC) if stock and ancien else cout
    if nouveau != ancien:
        reference.prix_achat = nouveau
        reference.save(update_fields=["prix_achat"])


# --------------------------------------------------------------------------- #
# Caisse / trésorerie (§ 14) — sorties identifiables APPRO:<numéro>:…
# --------------------------------------------------------------------------- #


def enregistrer_en_caisse(order, user, montant_mga, libelle, reference):
    """Sortie de caisse automatique (origine ACHAT_STOCK — de la marchandise,
    exclue des charges des rapports), idempotente par référence. Requiert
    une session ouverte sur le magasin de l'appro."""
    from finance import services as finance_services

    session = finance_services.session_ouverte(order.magasin, verrouiller=True)
    if not session:
        raise ValidationError({"en_caisse": "Aucune session de caisse ouverte pour enregistrer la sortie."})
    finance_services.mouvement_caisse(session, "out", montant_mga, libelle, "ACHAT_STOCK", reference, user)


def references_caisse(order):
    from users.models import CaisseMovement

    return set(CaisseMovement.objects.filter(reference__startswith=f"APPRO:{order.numero}:").values_list("reference", flat=True))


# --------------------------------------------------------------------------- #
# Historique et indicateurs (§ 12, page Fournisseur)
# --------------------------------------------------------------------------- #


def historique_couts_variante(variant):
    """Les envois finalisés de ce produit, du plus récent au plus ancien —
    chacun garde son coût (§ 12)."""
    return SupplierOrder.objects.filter(product_variant=variant, statut="COUT_FINALISE").select_related("supplier").order_by("-finalise_at", "-id")


def cout_revient_variante(variant):
    """Dernier coût de revient finalisé, coût moyen pondéré des envois
    finalisés, et prix d'achat de référence actuel."""
    envois = list(historique_couts_variante(variant))
    quantite = sum(e.quantite for e in envois)
    moyen = (sum((e.cout_total_mga for e in envois), ZERO) / quantite).quantize(DEUX_DEC) if quantite else None
    return {
        "dernier": envois[0].cout_unitaire_mga if envois else None,
        "moyen": moyen,
        "prix_achat_reference": variant.product_reference.prix_achat,
        "envois": envois,
    }


def resume_financier(orders):
    """Totaux MGA d'une liste d'approvisionnements (fiche fournisseur, KPIs)."""
    orders = list(orders)
    total_paye = sum((Decimal(o.total_paiements_mga) for o in orders), ZERO)
    frais = sum((Decimal(o.frais_douane_mga) for o in orders), ZERO)
    return {
        "nb_approvisionnements": len(orders),
        "nb_en_cours": sum(1 for o in orders if o.statut in STATUTS_EN_COURS),
        "nb_finalises": sum(1 for o in orders if o.est_finalise),
        "total_paye_mga": total_paye,
        "total_frais_douane_mga": frais,
        "cout_total_mga": sum((Decimal(o.cout_total_mga) for o in orders), ZERO),
        "reste_a_payer_devise": sum((o.reste_a_payer_devise for o in orders if not o.est_finalise), ZERO),
        "quantite_totale": sum(o.quantite for o in orders),
    }


def kpis(orders, suppliers):
    orders = list(orders)
    res = resume_financier(orders)
    en_transit = [o for o in orders if o.statut in ("EXPEDIE", "EN_TRANSIT")]
    finalises = [o for o in orders if o.est_finalise]
    return {
        **res,
        "nb_fournisseurs": len(list(suppliers)),
        "nb_fournisseurs_actifs": sum(1 for s in suppliers if s.actif),
        "en_transit": {"nb": len(en_transit), "valeur_mga": sum((Decimal(o.cout_total_mga) for o in en_transit), ZERO)},
        "a_finaliser": sum(1 for o in orders if o.statut == "ARRIVE"),
        "cout_moyen_par_piece_mga": (
            (sum((Decimal(o.cout_total_mga) for o in finalises), ZERO) / sum(o.quantite for o in finalises)).quantize(DEUX_DEC)
            if finalises and sum(o.quantite for o in finalises) else None
        ),
        "par_statut": [
            {"statut": s, "label": l, "nb": sum(1 for o in orders if o.statut == s)} for s, l in SupplierOrder.STATUT_CHOICES
        ],
    }
