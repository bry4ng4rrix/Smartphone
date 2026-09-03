from django.db import transaction

from .models import StockMovement


@transaction.atomic
def apply_stock_movement(product_variant, movement_type, quantite, origine, user=None, reference=None, note=None):
    """Point d'entrée unique pour toute modification de stock — garantit
    qu'un mouvement de stock ne peut jamais être appliqué sans laisser de
    trace dans StockMovement (§10 README — historique obligatoire)."""

    variant = type(product_variant).objects.select_for_update().get(pk=product_variant.pk)

    if movement_type == "SORTIE":
        variant.stock_actuel -= quantite
    else:
        variant.stock_actuel += quantite
    variant.save(update_fields=["stock_actuel"])

    return StockMovement.objects.create(
        product_variant=variant,
        type=movement_type,
        quantite=quantite,
        origine=origine,
        reference=reference,
        note=note,
        user=user,
    )
