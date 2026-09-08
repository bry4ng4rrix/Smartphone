from django.db import transaction

from .models import StockMovement


@transaction.atomic
def revert_import_batch(batch):
    """Défait un import Excel (voir ProductReferenceViewSet.import_excel /
    ImportBatchViewSet.cancel) : supprime les objets créés et restaure les
    valeurs précédentes des objets mis à jour, dans l'ordre inverse de
    `batch.items`. Best-effort sur Catégorie/Sous-type/Marque : supprimés
    seulement s'il ne leur reste plus aucun enfant (pour ne jamais entraîner
    en cascade des données d'un autre import ou saisies manuellement)."""
    from .models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant

    items = batch.items or []
    deleted_reference_ids = {it["id"] for it in items if it["action"] == "created_reference"}

    for it in reversed(items):
        if it["action"] == "created_variant":
            if it.get("reference_id") in deleted_reference_ids:
                continue  # supprimée en cascade avec sa référence ci-dessous
            ProductVariant.objects.filter(pk=it["id"]).delete()
        elif it["action"] == "updated_variant":
            variant = ProductVariant.objects.select_for_update().filter(pk=it["id"]).first()
            if variant is None:
                continue
            previous = it.get("previous") or {}
            update_fields = []
            if "seuil_alerte" in previous:
                variant.seuil_alerte = previous["seuil_alerte"]
                update_fields.append("seuil_alerte")
            if "stock_actuel" in previous:
                variant.stock_actuel = previous["stock_actuel"]
                update_fields.append("stock_actuel")
            if update_fields:
                variant.save(update_fields=update_fields)
            if it.get("movement_id"):
                StockMovement.objects.filter(pk=it["movement_id"]).delete()

    for it in reversed(items):
        if it["action"] == "created_reference":
            ProductReference.objects.filter(pk=it["id"]).delete()
        elif it["action"] == "updated_reference":
            ref = ProductReference.objects.filter(pk=it["id"]).first()
            if ref is None:
                continue
            previous = it.get("previous") or {}
            update_fields = [f for f in ("prix_achat", "prix_vente", "actif") if f in previous]
            for field in update_fields:
                setattr(ref, field, previous[field])
            if update_fields:
                ref.save(update_fields=update_fields)

    for it in reversed(items):
        if it["action"] == "created_type":
            ProductType.objects.filter(pk=it["id"], references__isnull=True).delete()
        elif it["action"] == "created_category":
            ProductCategory.objects.filter(pk=it["id"], types__isnull=True).delete()
        elif it["action"] == "created_brand":
            Brand.objects.filter(pk=it["id"], references__isnull=True).delete()


@transaction.atomic
def apply_stock_movement(product_variant, movement_type, quantite, origine, user=None, reference=None, note=None):
    """Point d'entrée unique pour toute modification de stock — garantit
    qu'un mouvement de stock ne peut jamais être appliqué sans laisser de
    trace dans StockMovement (§10 Smartreadme.md — historique obligatoire)."""

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
