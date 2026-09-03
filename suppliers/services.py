from django.core.exceptions import ValidationError
from django.db import transaction

from catalog.services import apply_stock_movement


@transaction.atomic
def create_supplier_order(*, magasin, description, prix_fournisseur, fret_import, douane, meta_ads, lines, created_by):
    from .models import SupplierOrder, SupplierOrderLine

    supplier_order = SupplierOrder.objects.create(
        magasin=magasin,
        description=description,
        prix_fournisseur=prix_fournisseur,
        fret_import=fret_import,
        douane=douane,
        meta_ads=meta_ads,
        created_by=created_by,
    )
    for line in lines:
        SupplierOrderLine.objects.create(
            supplier_order=supplier_order,
            product_variant=line["product_variant"],
            quantite=line["quantite"],
        )

    return recompute_costs(supplier_order)


@transaction.atomic
def recompute_costs(supplier_order):
    """Coût total = fournisseur + fret + douane + pub ; coût unitaire =
    coût total / quantité totale ; réparti sur chaque ligne (§7.6 Smartreadme.md)."""

    lines = list(supplier_order.lines.select_related("product_variant").all())
    total_qty = sum(line.quantite for line in lines)

    cout_total = (
        supplier_order.prix_fournisseur
        + supplier_order.fret_import
        + supplier_order.douane
        + supplier_order.meta_ads
    )
    cout_unitaire = (cout_total / total_qty) if total_qty else 0

    for line in lines:
        line.cout_unitaire_calcule = cout_unitaire
        line.total_ligne = cout_unitaire * line.quantite
        line.save(update_fields=["cout_unitaire_calcule", "total_ligne"])

    supplier_order.total_qty = total_qty
    supplier_order.cout_total = cout_total
    supplier_order.cout_unitaire = cout_unitaire
    supplier_order.save(update_fields=["total_qty", "cout_total", "cout_unitaire"])

    return supplier_order


@transaction.atomic
def receive_supplier_order(supplier_order, user):
    """Réception fournisseur : enregistre l'entrée stock par variante et
    passe la commande à 'RECU' (§7.6 Smartreadme.md — 'Chaque entrée crée
    des mouvements stock entrée fournisseur')."""

    from django.utils import timezone

    if supplier_order.statut == "RECU":
        raise ValidationError("Cette commande fournisseur a déjà été reçue.")

    for line in supplier_order.lines.select_related("product_variant"):
        apply_stock_movement(
            product_variant=line.product_variant,
            movement_type="ENTREE",
            quantite=line.quantite,
            origine="FOURNISSEUR",
            user=user,
            reference=supplier_order.numero,
        )

    supplier_order.statut = "RECU"
    supplier_order.received_at = timezone.now()
    supplier_order.save(update_fields=["statut", "received_at"])
    return supplier_order
