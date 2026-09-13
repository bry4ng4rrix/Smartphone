"""Données existantes : les approvisionnements de la première version
reçoivent leurs nouveaux snapshots (valeur d'achat / frais en MGA, répartis
par quantité comme le faisait l'ancien calcul) et les commandes déjà reçues
ont `quantite_recue = quantite`. Aucune valeur métier n'est modifiée :
cout_total / cout_unitaire restent identiques."""
from decimal import Decimal

from django.db import migrations


def remplir(apps, schema_editor):
    SupplierOrder = apps.get_model("suppliers", "SupplierOrder")
    deux = Decimal("0.01")
    for order in SupplierOrder.objects.all().prefetch_related("lines"):
        lines = list(order.lines.all())
        total_qty = sum(l.quantite for l in lines)
        valeur = Decimal(order.prix_fournisseur or 0)
        frais = Decimal(order.fret_import or 0) + Decimal(order.douane or 0)
        for l in lines:
            if order.statut == "RECU":
                l.quantite_recue = l.quantite
            if total_qty:
                l.valeur_achat_mga = (valeur * l.quantite / total_qty).quantize(deux)
                l.frais_alloues_mga = (frais * l.quantite / total_qty).quantize(deux)
            l.save()
        order.valeur_achat_mga = valeur.quantize(deux)
        order.total_frais_mga = frais.quantize(deux)
        order.save(update_fields=["valeur_achat_mga", "total_frais_mga"])


class Migration(migrations.Migration):
    dependencies = [("suppliers", "0003_alter_supplierorder_options_and_more")]
    operations = [migrations.RunPython(remplir, migrations.RunPython.noop)]
