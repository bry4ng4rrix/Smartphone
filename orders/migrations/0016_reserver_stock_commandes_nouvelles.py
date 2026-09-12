"""Changement de règle : le stock sort dès la création de la commande (et
non plus au passage "En préparation"). Les commandes encore "Nouvelle" au
moment de la migration n'avaient pas encore touché le stock : on applique
leur sortie maintenant, tracée comme n'importe quel mouvement."""

from django.db import migrations


def reserver_stock(apps, schema_editor):
    Order = apps.get_model("orders", "Order")
    ProductVariant = apps.get_model("catalog", "ProductVariant")
    StockMovement = apps.get_model("catalog", "StockMovement")
    for order in Order.objects.filter(statut_courant="NOUVELLE"):
        for item in order.items.all():
            variant = ProductVariant.objects.select_for_update().get(pk=item.product_variant_id)
            variant.stock_actuel -= item.quantite
            variant.save(update_fields=["stock_actuel"])
            StockMovement.objects.create(
                product_variant=variant, type="SORTIE", quantite=item.quantite, origine="COMMANDE",
                reference=order.numero, note="Réservation rétroactive : le stock sort désormais à la création",
                user_id=order.created_by_id,
            )


def restituer_stock(apps, schema_editor):
    Order = apps.get_model("orders", "Order")
    ProductVariant = apps.get_model("catalog", "ProductVariant")
    StockMovement = apps.get_model("catalog", "StockMovement")
    for order in Order.objects.filter(statut_courant="NOUVELLE"):
        for item in order.items.all():
            variant = ProductVariant.objects.select_for_update().get(pk=item.product_variant_id)
            variant.stock_actuel += item.quantite
            variant.save(update_fields=["stock_actuel"])
            StockMovement.objects.create(
                product_variant=variant, type="ENTREE", quantite=item.quantite, origine="ANNULATION",
                reference=order.numero, note="Annulation de la réservation rétroactive",
            )


class Migration(migrations.Migration):
    dependencies = [
        ("orders", "0015_finance_fields"),
        ("catalog", "0009_stockmovement_origine_commande"),
    ]
    operations = [migrations.RunPython(reserver_stock, restituer_stock)]
