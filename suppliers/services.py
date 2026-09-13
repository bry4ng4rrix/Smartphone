"""Règles métier du module Fournisseur (§7.6 Smartreadme.md, étendu).

Tout le calcul du coût réel se fait ici, en ariary (MGA) :

    valeur d'achat fournisseur (lignes × prix unitaire × taux, ou
    `prix_fournisseur` saisi en MGA sur les anciennes commandes)
  + frais communs (fret_import + douane historiques + tous les SupplierFee)
  = VALEUR RÉELLE DE L'APPROVISIONNEMENT

Les frais communs sont RÉPARTIS entre les lignes selon la méthode choisie
(valeur d'achat / quantité / manuelle), ce qui donne pour chaque ligne un
coût de revient unitaire = (valeur d'achat de la ligne + frais alloués) /
quantité. La quantité retenue est la quantité REÇUE dès qu'une réception a
eu lieu (c'est ce qui est réellement arrivé), la quantité commandée avant.

Le stock n'est jamais touché ici directement : la réception passe par
catalog.services.apply_stock_movement (origine FOURNISSEUR).
"""
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from catalog.services import apply_stock_movement

from .models import (
    DEUX_DEC,
    ZERO,
    Supplier,
    SupplierFee,
    SupplierOrder,
    SupplierOrderLine,
    SupplierPayment,
    VariantCostHistory,
    convertir_en_mga,
)

# Statuts après lesquels la marchandise est considérée arrivée.
STATUTS_ARRIVES = {"ARRIVE", "PARTIELLEMENT_RECU", "RECU", "COUT_FINALISE"}
STATUTS_RECEPTION = {"PARTIELLEMENT_RECU", "RECU", "COUT_FINALISE"}
# Statuts « en cours » (ni brouillon ni terminé) pour les indicateurs.
STATUTS_EN_COURS = {"COMMANDE", "PARTIELLEMENT_PAYE", "PAYE", "PREPARE", "EN_TRANSIT", "ARRIVE", "PARTIELLEMENT_RECU", "RECU"}


def _rang(statut):
    return SupplierOrder.STATUT_ORDER.index(statut) if statut in SupplierOrder.STATUT_ORDER else -1


def _verifier_modifiable(order):
    if order.est_finalise:
        raise ValidationError("Cet approvisionnement est finalisé : son coût de revient ne peut plus changer.")


# --------------------------------------------------------------------------- #
# Création / modification
# --------------------------------------------------------------------------- #


@transaction.atomic
def create_supplier_order(*, magasin, lines, created_by, description="", prix_fournisseur=0, fret_import=0, douane=0,
                          supplier=None, devise="MGA", taux_change=None, methode_allocation="VALEUR", date=None,
                          destination="Madagascar", statut="BROUILLON"):
    """`lines` : liste de {"product_variant": ProductVariant, "quantite": int,
    "prix_unitaire": Decimal (devise de la commande, facultatif)}.
    `prix_fournisseur` / `fret_import` / `douane` : montants MGA de la
    première version, toujours acceptés (compatibilité)."""
    if supplier is not None and supplier.admin_profile_id != getattr(magasin.admin, "admin_profile", None).id:
        raise ValidationError({"supplier": "Ce fournisseur n'appartient pas à votre société."})
    if devise == "MGA":
        taux_change = Decimal("1")
    elif not taux_change or Decimal(str(taux_change)) <= 0:
        raise ValidationError({"taux_change": "Le taux de change (Ar pour 1 unité de devise) est requis."})

    order = SupplierOrder.objects.create(
        magasin=magasin,
        supplier=supplier,
        description=description or "",
        prix_fournisseur=prix_fournisseur or 0,
        fret_import=fret_import or 0,
        douane=douane or 0,
        devise=devise,
        taux_change=Decimal(str(taux_change)),
        methode_allocation=methode_allocation,
        destination=destination or "Madagascar",
        statut=statut if statut in ("BROUILLON", "COMMANDE") else "BROUILLON",
        created_by=created_by,
        **({"date": date} if date else {}),
    )
    for line in lines:
        SupplierOrderLine.objects.create(
            supplier_order=order,
            product_variant=line["product_variant"],
            quantite=line["quantite"],
            prix_unitaire=Decimal(str(line.get("prix_unitaire") or 0)),
        )
    return recompute_costs(order)


@transaction.atomic
def update_supplier_order(*, order, data):
    """Modification des données générales / transport / méthode d'allocation
    / lignes (tant que le coût n'est pas finalisé). Les lignes déjà reçues
    ne peuvent pas être retirées ni réduites sous la quantité reçue."""
    _verifier_modifiable(order)
    champs_simples = (
        "description", "supplier", "devise", "taux_change", "methode_allocation", "date",
        "prix_fournisseur", "fret_import", "douane",
        "date_expedition", "transporteur", "mode_transport", "tracking", "lieu_depart", "destination", "date_arrivee",
    )
    for champ in champs_simples:
        if champ in data and data[champ] is not None:
            setattr(order, champ, data[champ])
    if order.devise == "MGA":
        order.taux_change = Decimal("1")
    elif not order.taux_change or order.taux_change <= 0:
        raise ValidationError({"taux_change": "Le taux de change est requis pour une devise autre que le MGA."})
    if order.supplier is not None and order.supplier.admin_profile_id != order.magasin.admin.admin_profile.id:
        raise ValidationError({"supplier": "Ce fournisseur n'appartient pas à votre société."})
    order.save()

    if data.get("lines") is not None:
        existantes = {l.id: l for l in order.lines.all()}
        vues = set()
        for ld in data["lines"]:
            lid = ld.get("id")
            if lid and lid in existantes:
                ligne = existantes[lid]
                if ld["quantite"] < ligne.quantite_recue:
                    raise ValidationError({"lines": f"Ligne {ligne.product_variant} : {ligne.quantite_recue} déjà reçu(s), quantité minimale {ligne.quantite_recue}."})
                ligne.quantite = ld["quantite"]
                ligne.product_variant = ld["product_variant"]
                if "prix_unitaire" in ld and ld["prix_unitaire"] is not None:
                    ligne.prix_unitaire = Decimal(str(ld["prix_unitaire"]))
                if "allocation_manuelle_mga" in ld:
                    ligne.allocation_manuelle_mga = ld["allocation_manuelle_mga"]
                ligne.save()
                vues.add(lid)
            else:
                nouvelle = SupplierOrderLine.objects.create(
                    supplier_order=order, product_variant=ld["product_variant"], quantite=ld["quantite"],
                    prix_unitaire=Decimal(str(ld.get("prix_unitaire") or 0)),
                    allocation_manuelle_mga=ld.get("allocation_manuelle_mga"),
                )
                vues.add(nouvelle.id)
        for lid, ligne in existantes.items():
            if lid not in vues:
                if ligne.quantite_recue:
                    raise ValidationError({"lines": f"Ligne {ligne.product_variant} : déjà réceptionnée, impossible de la retirer."})
                ligne.delete()
    return recompute_costs(order)


# --------------------------------------------------------------------------- #
# Calcul du coût réel et allocation des frais
# --------------------------------------------------------------------------- #


def _quantite_retenue(order, line):
    """Quantité sur laquelle le coût est calculé : la quantité reçue dès
    qu'une réception a eu lieu, la quantité commandée sinon."""
    if order.statut in STATUTS_RECEPTION:
        return line.quantite_recue
    return line.quantite


@transaction.atomic
def recompute_costs(order):
    """Recalcule, en MGA : valeur d'achat, frais, valeur réelle, coût moyen,
    et pour chaque ligne la valeur d'achat, les frais alloués et le coût de
    revient unitaire. Sans effet sur un approvisionnement finalisé (ses
    snapshots sont figés)."""
    if order.est_finalise:
        return order
    lines = list(order.lines.select_related("product_variant").all())
    qtes = {l.id: _quantite_retenue(order, l) for l in lines}
    total_qty = sum(qtes.values())

    # 1. Valeur d'achat par ligne (MGA).
    valeurs = {}
    if any(l.prix_unitaire for l in lines):
        for l in lines:
            valeurs[l.id] = convertir_en_mga(l.prix_unitaire * qtes[l.id], order.devise, order.taux_change)
        valeur_achat = sum(valeurs.values(), ZERO)
        # `prix_fournisseur` historique en plus (rare : ancien montant global
        # ET prix par ligne) — réparti par quantité.
        extra = Decimal(order.prix_fournisseur or 0)
    else:
        # Première version : un seul montant global, réparti par quantité.
        valeur_achat = Decimal(order.prix_fournisseur or 0)
        extra = ZERO
        for l in lines:
            valeurs[l.id] = (valeur_achat * qtes[l.id] / total_qty).quantize(DEUX_DEC) if total_qty else ZERO
    if extra:
        for l in lines:
            valeurs[l.id] += (extra * qtes[l.id] / total_qty).quantize(DEUX_DEC) if total_qty else ZERO
        valeur_achat += extra

    # 2. Frais communs à répartir.
    frais_typés = order.fees.aggregate(t=Sum("montant_mga"))["t"] or ZERO
    total_frais = Decimal(order.fret_import or 0) + Decimal(order.douane or 0) + frais_typés

    # 3. Allocation.
    alloues = {l.id: ZERO for l in lines}
    if lines and total_frais:
        if order.methode_allocation == "MANUEL":
            for l in lines:
                alloues[l.id] = Decimal(l.allocation_manuelle_mga or 0)
        elif order.methode_allocation == "QUANTITE" or not valeur_achat:
            if total_qty:
                for l in lines:
                    alloues[l.id] = (total_frais * qtes[l.id] / total_qty).quantize(DEUX_DEC)
        else:  # VALEUR (défaut)
            for l in lines:
                alloues[l.id] = (total_frais * valeurs[l.id] / valeur_achat).quantize(DEUX_DEC)
        # Arrondis : la dernière ligne absorbe l'écart pour que la somme des
        # frais alloués soit exactement le total (hors MANUEL).
        if order.methode_allocation != "MANUEL" and (total_qty if order.methode_allocation == "QUANTITE" or not valeur_achat else valeur_achat):
            ecart = total_frais - sum(alloues.values(), ZERO)
            if ecart and lines:
                alloues[lines[-1].id] += ecart

    # 4. Snapshots.
    for l in lines:
        q = qtes[l.id]
        l.valeur_achat_mga = valeurs[l.id]
        l.frais_alloues_mga = alloues[l.id]
        l.total_ligne = (valeurs[l.id] + alloues[l.id]).quantize(DEUX_DEC)
        l.cout_unitaire_calcule = (l.total_ligne / q).quantize(DEUX_DEC) if q else ZERO
        l.save(update_fields=["valeur_achat_mga", "frais_alloues_mga", "total_ligne", "cout_unitaire_calcule"])

    order.total_qty = total_qty
    order.valeur_achat_mga = valeur_achat.quantize(DEUX_DEC)
    order.total_frais_mga = total_frais.quantize(DEUX_DEC)
    order.cout_total = (valeur_achat + total_frais).quantize(DEUX_DEC)
    order.cout_unitaire = (order.cout_total / total_qty).quantize(DEUX_DEC) if total_qty else ZERO
    order.save(update_fields=["total_qty", "valeur_achat_mga", "total_frais_mga", "cout_total", "cout_unitaire"])
    _ajuster_statut_paiement(order)
    return order


def _ajuster_statut_paiement(order):
    """PARTIELLEMENT_PAYE / PAYE dérivés des paiements, tant que la
    marchandise n'est pas plus avancée (préparée, en transit…)."""
    if order.statut not in ("COMMANDE", "PARTIELLEMENT_PAYE", "PAYE"):
        return
    # Requête fraîche : l'instance peut porter un cache `prefetch_related`
    # antérieur à l'ajout / la suppression du paiement.
    paye = SupplierPayment.objects.filter(supplier_order=order).aggregate(t=Sum("montant_mga"))["t"] or ZERO
    if paye <= 0:
        nouveau = "COMMANDE"
    elif order.valeur_achat_mga and paye >= order.valeur_achat_mga:
        nouveau = "PAYE"
    else:
        nouveau = "PARTIELLEMENT_PAYE"
    if nouveau != order.statut:
        order.statut = nouveau
        order.save(update_fields=["statut"])


# --------------------------------------------------------------------------- #
# Paiements et frais
# --------------------------------------------------------------------------- #


@transaction.atomic
def add_payment(*, order, user, montant, devise, taux_change=None, date=None, type_paiement="ACOMPTE",
                methode="VIREMENT", reference="", commentaire="", justificatif=None):
    _verifier_modifiable(order)
    montant = Decimal(str(montant))
    if montant <= 0:
        raise ValidationError({"montant": "Le montant doit être supérieur à 0."})
    if devise != "MGA" and (not taux_change or Decimal(str(taux_change)) <= 0):
        # Repli : taux de la commande si même devise.
        if devise == order.devise and order.taux_change:
            taux_change = order.taux_change
        else:
            raise ValidationError({"taux_change": "Le taux de change (Ar pour 1 unité) est requis."})
    if order.statut == "BROUILLON":
        order.statut = "COMMANDE"
        order.save(update_fields=["statut"])
    paiement = SupplierPayment.objects.create(
        supplier_order=order, montant=montant, devise=devise, taux_change=Decimal(str(taux_change or 1)),
        date=date or timezone.localdate(), type_paiement=type_paiement, methode=methode,
        reference=reference or "", commentaire=commentaire or "", justificatif=justificatif, created_by=user,
    )
    _ajuster_statut_paiement(order)
    return paiement


@transaction.atomic
def delete_payment(*, order, payment_id):
    _verifier_modifiable(order)
    deleted, _ = order.payments.filter(id=payment_id).delete()
    if not deleted:
        raise ValidationError("Paiement introuvable.")
    _ajuster_statut_paiement(order)


@transaction.atomic
def add_fee(*, order, user, type_frais, montant, devise, taux_change=None, date=None, description="",
            prestataire="", justificatif=None):
    _verifier_modifiable(order)
    montant = Decimal(str(montant))
    if montant <= 0:
        raise ValidationError({"montant": "Le montant doit être supérieur à 0."})
    if devise != "MGA" and (not taux_change or Decimal(str(taux_change)) <= 0):
        if devise == order.devise and order.taux_change:
            taux_change = order.taux_change
        else:
            raise ValidationError({"taux_change": "Le taux de change (Ar pour 1 unité) est requis."})
    frais = SupplierFee.objects.create(
        supplier_order=order, type_frais=type_frais, montant=montant, devise=devise,
        taux_change=Decimal(str(taux_change or 1)), date=date or timezone.localdate(),
        description=description or "", prestataire=prestataire or "", justificatif=justificatif, created_by=user,
    )
    recompute_costs(order)
    return frais


@transaction.atomic
def delete_fee(*, order, fee_id):
    _verifier_modifiable(order)
    deleted, _ = order.fees.filter(id=fee_id).delete()
    if not deleted:
        raise ValidationError("Frais introuvable.")
    recompute_costs(order)


# --------------------------------------------------------------------------- #
# Workflow : commander -> préparé -> en transit -> arrivé -> réception -> finalisé
# --------------------------------------------------------------------------- #


def _avancer(order, nouveau, depuis):
    _verifier_modifiable(order)
    if order.statut not in depuis:
        raise ValidationError(
            f"Transition impossible : l'approvisionnement est '{order.get_statut_display()}'."
        )
    order.statut = nouveau
    order.save(update_fields=["statut"])
    return order


def commander(order):
    """Brouillon -> Commandé (la commande est passée au fournisseur)."""
    _avancer(order, "COMMANDE", {"BROUILLON"})
    _ajuster_statut_paiement(order)
    return order


def preparer(order):
    """Le fournisseur a terminé la préparation (marchandise prête, pas encore partie)."""
    return _avancer(order, "PREPARE", {"COMMANDE", "PARTIELLEMENT_PAYE", "PAYE"})


@transaction.atomic
def expedier(order, **transport):
    """Départ de la marchandise : informations logistiques + statut En transit."""
    for champ in ("date_expedition", "transporteur", "mode_transport", "tracking", "lieu_depart", "destination"):
        if transport.get(champ) is not None:
            setattr(order, champ, transport[champ])
    if not order.date_expedition:
        order.date_expedition = timezone.localdate()
    order.save()
    return _avancer(order, "EN_TRANSIT", {"COMMANDE", "PARTIELLEMENT_PAYE", "PAYE", "PREPARE"})


@transaction.atomic
def arriver(order, date_arrivee=None):
    """Arrivée à Madagascar : les frais (douane…) peuvent maintenant être saisis."""
    order.date_arrivee = date_arrivee or timezone.localdate()
    order.save(update_fields=["date_arrivee"])
    return _avancer(order, "ARRIVE", {"COMMANDE", "PARTIELLEMENT_PAYE", "PAYE", "PREPARE", "EN_TRANSIT"})


@transaction.atomic
def receive_supplier_order(order, user, quantites=None):
    """Réception (totale ou partielle) : entrée en stock par variante via
    apply_stock_movement (origine FOURNISSEUR), puis recalcul des coûts sur
    les quantités reçues.

    `quantites` : {line_id: quantité reçue MAINTENANT} — None = tout ce qui
    reste à recevoir sur chaque ligne (comportement de la première version).
    Le statut passe à RECU quand toutes les lignes sont complètes, sinon à
    PARTIELLEMENT_RECU."""
    _verifier_modifiable(order)
    if order.statut == "RECU":
        raise ValidationError("Cette commande fournisseur a déjà été reçue.")
    if order.statut == "BROUILLON":
        # Première version : création puis réception directe — on passe
        # simplement la commande en « Commandé » au passage.
        order.statut = "COMMANDE"
        order.save(update_fields=["statut"])
    lines = list(order.lines.select_related("product_variant"))
    if quantites is None:
        quantites = {l.id: l.quantite - l.quantite_recue for l in lines}
    total_maintenant = 0
    for l in lines:
        q = int(quantites.get(l.id, 0) or 0)
        if q < 0:
            raise ValidationError({"lines": "Quantité reçue négative."})
        restant = l.quantite - l.quantite_recue
        if q > restant:
            raise ValidationError({"lines": f"{l.product_variant} : {q} reçu(s) pour {restant} restant(s) à recevoir."})
        if q == 0:
            continue
        apply_stock_movement(
            product_variant=l.product_variant, movement_type="ENTREE", quantite=q,
            origine="FOURNISSEUR", user=user, reference=order.numero,
        )
        l.quantite_recue += q
        l.save(update_fields=["quantite_recue"])
        total_maintenant += q
    if total_maintenant == 0:
        raise ValidationError("Aucune quantité reçue.")
    complet = all(l.quantite_recue >= l.quantite for l in lines)
    order.statut = "RECU" if complet else "PARTIELLEMENT_RECU"
    if complet:
        order.received_at = timezone.now()
    if not order.date_arrivee:
        order.date_arrivee = timezone.localdate()
    order.save(update_fields=["statut", "received_at", "date_arrivee"])
    return recompute_costs(order)


@transaction.atomic
def finaliser_cout(order, mettre_a_jour_prix_achat=True):
    """Coût finalisé : tous les frais sont connus, la marchandise est reçue.
    Fige les snapshots, écrit l'historique du coût de revient de chaque
    variante (jamais écrasé) et, si demandé, met à jour le prix d'achat de
    la référence (base des marges des rapports) avec le coût de revient
    — moyenne pondérée si plusieurs couleurs d'une même référence."""
    if order.est_finalise:
        raise ValidationError("Cet approvisionnement est déjà finalisé.")
    if order.statut not in ("RECU", "PARTIELLEMENT_RECU"):
        raise ValidationError("Réceptionnez la marchandise avant de finaliser le coût.")
    recompute_costs(order)
    order.refresh_from_db()
    lines = list(order.lines.select_related("product_variant__product_reference"))
    par_reference = {}
    for l in lines:
        if not l.quantite_recue:
            continue
        VariantCostHistory.objects.update_or_create(
            product_variant=l.product_variant, supplier_order=order,
            defaults={
                "quantite": l.quantite_recue,
                "valeur_achat_unitaire_mga": (l.valeur_achat_mga / l.quantite_recue).quantize(DEUX_DEC),
                "frais_unitaire_mga": (l.frais_alloues_mga / l.quantite_recue).quantize(DEUX_DEC),
                "cout_revient_unitaire_mga": l.cout_unitaire_calcule,
                "date": order.date_arrivee or timezone.localdate(),
            },
        )
        ref = l.product_variant.product_reference
        cum = par_reference.setdefault(ref.id, {"ref": ref, "valeur": ZERO, "qte": 0})
        cum["valeur"] += l.total_ligne
        cum["qte"] += l.quantite_recue
    if mettre_a_jour_prix_achat:
        for cum in par_reference.values():
            if cum["qte"]:
                cum["ref"].prix_achat = (cum["valeur"] / cum["qte"]).quantize(DEUX_DEC)
                cum["ref"].save(update_fields=["prix_achat", "updated_at"])
    order.statut = "COUT_FINALISE"
    order.finalise_at = timezone.now()
    order.save(update_fields=["statut", "finalise_at"])
    return order


# --------------------------------------------------------------------------- #
# Coût de revient actuel / historique d'une variante
# --------------------------------------------------------------------------- #


def cout_revient_variante(variant):
    """{dernier, moyen_pondere, historique} — `dernier` = dernier
    approvisionnement finalisé (coût actuel / masonkarena), `moyen_pondere`
    sur tout l'historique. None si aucun approvisionnement finalisé."""
    hist = list(VariantCostHistory.objects.filter(product_variant=variant).select_related("supplier_order").order_by("-date", "-id"))
    if not hist:
        return {"dernier": None, "moyen_pondere": None, "historique": []}
    qte = sum(h.quantite for h in hist)
    total = sum((h.cout_revient_unitaire_mga * h.quantite for h in hist), ZERO)
    return {
        "dernier": hist[0].cout_revient_unitaire_mga,
        "moyen_pondere": (total / qte).quantize(DEUX_DEC) if qte else None,
        "historique": hist,
    }


# --------------------------------------------------------------------------- #
# Indicateurs (page Gérant -> Fournisseurs) et résumé par fournisseur
# --------------------------------------------------------------------------- #


def resume_financier(orders):
    """Totaux MGA sur un ensemble d'approvisionnements."""
    orders = list(orders)
    total_achats = sum((o.valeur_achat_mga for o in orders), ZERO)
    total_paye = sum((o.total_paye_mga for o in orders), ZERO)
    total_frais = sum((o.total_frais_mga for o in orders), ZERO)
    valeur_recue = sum((o.cout_total for o in orders if o.statut in STATUTS_RECEPTION), ZERO)
    return {
        "nb_approvisionnements": len(orders),
        "total_achats_mga": total_achats,
        "total_paye_mga": total_paye,
        "reste_a_payer_mga": max(total_achats - total_paye, ZERO),
        "total_frais_mga": total_frais,
        "valeur_recue_mga": valeur_recue,
    }


def kpis(orders, suppliers):
    orders = list(orders)
    base = resume_financier(orders)
    return {
        "nb_fournisseurs": suppliers.count(),
        "en_cours": sum(1 for o in orders if o.statut in STATUTS_EN_COURS),
        "en_transit": sum(1 for o in orders if o.statut == "EN_TRANSIT"),
        "arrives": sum(1 for o in orders if o.statut in STATUTS_ARRIVES),
        "finalises": sum(1 for o in orders if o.statut == "COUT_FINALISE"),
        **base,
    }
