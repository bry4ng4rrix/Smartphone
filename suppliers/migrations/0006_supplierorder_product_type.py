"""L'approvisionnement porte sur un SOUS-TYPE de produit (comme le filtre
« sous-type » de la page Produits), plus sur une variante / couleur.
Additif : `product_type` ajouté et rempli depuis la variante des
approvisionnements existants ; `product_variant` conservé (historique)."""
import django.db.models.deletion
from django.db import migrations, models


def remplir(apps, schema_editor):
    SupplierOrder = apps.get_model("suppliers", "SupplierOrder")
    for o in SupplierOrder.objects.filter(product_type__isnull=True, product_variant__isnull=False).select_related("product_variant__product_reference"):
        o.product_type_id = o.product_variant.product_reference.type_id
        o.save(update_fields=["product_type"])


class Migration(migrations.Migration):

    dependencies = [
        ("catalog", "0001_initial"),
        ("suppliers", "0005_approvisionnement_un_produit"),
    ]

    operations = [
        migrations.AddField(
            model_name="supplierorder",
            name="product_type",
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name="supplier_orders", to="catalog.producttype"),
        ),
        migrations.RunPython(remplir, migrations.RunPython.noop),
    ]
