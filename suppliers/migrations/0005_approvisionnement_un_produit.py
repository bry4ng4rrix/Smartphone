"""Remplacement du module Fournisseur : 1 approvisionnement = 1 produit,
plusieurs paiements, UN montant Frais + Douane, coût total et coût unitaire.

Conversion des données existantes AVANT toute suppression (rien n'est perdu
en valeur) :

* produit / quantité  ← la ligne de l'approvisionnement (s'il en avait
  plusieurs, la première devient le produit de l'appro et les autres sont
  recopiées dans `description` — un tel appro ne peut plus exister dans le
  nouveau modèle et reste consultable) ;
* `prix_fournisseur` (première version, saisi en MGA) ← devient un paiement
  MGA daté de l'appro, pour que le total payé soit inchangé ;
* Frais + Douane ← `fret_import + douane` + Σ des frais typés (en MGA) ;
* statuts : PARTIELLEMENT_PAYE → ACOMPTE_PAYE, PREPARE → PREPARATION,
  ARRIVE / PARTIELLEMENT_RECU / RECU → ARRIVE (RECU marque en plus la
  quantité déjà reçue pour ne pas la réceptionner deux fois),
  COUT_FINALISE inchangé ;
* coût total / coût unitaire recalculés avec les nouvelles formules
  (identiques à l'ancien calcul pour un appro à un seul produit).

Puis suppression des tables SupplierOrderLine, SupplierFee et
VariantCostHistory (leur contenu est désormais porté par l'approvisionnement
lui-même) et des champs de répartition devenus sans objet.
"""
from decimal import Decimal

import django.db.models.deletion
from django.db import migrations, models


STATUTS = {
    "BROUILLON": "BROUILLON",
    "COMMANDE": "COMMANDE",
    "PARTIELLEMENT_PAYE": "ACOMPTE_PAYE",
    "PAYE": "PAYE",
    "PREPARE": "PREPARATION",
    "EN_TRANSIT": "EN_TRANSIT",
    "ARRIVE": "ARRIVE",
    "PARTIELLEMENT_RECU": "ARRIVE",
    "RECU": "ARRIVE",
    "COUT_FINALISE": "COUT_FINALISE",
}


def convertir(apps, schema_editor):
    SupplierOrder = apps.get_model("suppliers", "SupplierOrder")
    SupplierPayment = apps.get_model("suppliers", "SupplierPayment")
    deux = Decimal("0.01")
    for order in SupplierOrder.objects.all():
        lines = list(order.lines.all().order_by("id"))
        if lines:
            premiere = lines[0]
            order.product_variant_id = premiere.product_variant_id
            order.quantite = premiere.quantite
            order.quantite_recue = premiere.quantite_recue
            if len(lines) > 1:
                autres = ", ".join(f"{l.product_variant} x{l.quantite}" for l in lines[1:])
                order.description = ((order.description or "") + f" [autres lignes de l'ancien module : {autres}]")[:255]
        # Valeur d'achat de l'ancien module : prix unitaire × quantité (devise
        # de l'appro) = montant prévu ; le `prix_fournisseur` MGA saisi
        # directement devient un paiement pour conserver le total payé.
        prevu = sum((Decimal(l.prix_unitaire or 0) * l.quantite for l in lines), Decimal("0"))
        order.montant_prevu = prevu.quantize(deux)
        if Decimal(order.prix_fournisseur or 0) > 0:
            SupplierPayment.objects.create(
                supplier_order=order, montant=order.prix_fournisseur, devise="MGA", taux_change=Decimal("1"),
                montant_mga=order.prix_fournisseur, date=order.date, type_paiement="AUTRE", methode="AUTRE",
                commentaire="Prix fournisseur saisi dans l'ancien module (converti)",
            )
        frais = Decimal(order.fret_import or 0) + Decimal(order.douane or 0)
        frais += sum((Decimal(f.montant_mga or 0) for f in order.fees.all()), Decimal("0"))
        order.frais_douane_mga = frais.quantize(deux)
        total_paiements = sum((Decimal(p.montant_mga or 0) for p in order.payments.all()), Decimal("0"))
        order.total_paiements_mga = total_paiements.quantize(deux)
        order.cout_total_mga = (order.total_paiements_mga + order.frais_douane_mga).quantize(deux)
        order.cout_unitaire_mga = (order.cout_total_mga / order.quantite).quantize(deux) if order.quantite else Decimal("0")
        order.statut = STATUTS.get(order.statut, "BROUILLON")
        if order.devise == "MGA" and order.supplier_id is None:
            order.devise = "USD"
        order.save()


class Migration(migrations.Migration):

    dependencies = [
        ("catalog", "0001_initial"),
        ("suppliers", "0004_snapshots_existants"),
    ]

    operations = [
        # 1. Nouveaux champs (additifs).
        migrations.AddField(
            model_name="supplierorder",
            name="product_variant",
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name="supplier_orders", to="catalog.productvariant"),
        ),
        migrations.AddField(model_name="supplierorder", name="quantite", field=models.PositiveIntegerField(default=0)),
        migrations.AddField(model_name="supplierorder", name="quantite_recue", field=models.PositiveIntegerField(default=0)),
        migrations.AddField(model_name="supplierorder", name="montant_prevu", field=models.DecimalField(decimal_places=2, default=0, max_digits=16)),
        migrations.AddField(model_name="supplierorder", name="frais_douane_mga", field=models.DecimalField(decimal_places=2, default=0, max_digits=16)),
        migrations.AddField(model_name="supplierorder", name="total_paiements_mga", field=models.DecimalField(decimal_places=2, default=0, editable=False, max_digits=16)),
        migrations.AddField(model_name="supplierorder", name="cout_total_mga", field=models.DecimalField(decimal_places=2, default=0, editable=False, max_digits=16)),
        migrations.AddField(model_name="supplierorder", name="cout_unitaire_mga", field=models.DecimalField(decimal_places=2, default=0, editable=False, max_digits=14)),
        migrations.AddField(model_name="supplierorder", name="numero_colis", field=models.CharField(blank=True, max_length=150)),
        migrations.AddField(model_name="supplierorder", name="commentaire_transport", field=models.CharField(blank=True, max_length=255)),
        migrations.AlterField(model_name="supplierorder", name="lieu_depart", field=models.CharField(blank=True, default="Chine", max_length=150)),
        migrations.AlterField(model_name="supplierorder", name="devise", field=models.CharField(choices=[("MGA", "Ariary (MGA)"), ("USD", "Dollar US (USD)"), ("EUR", "Euro (EUR)"), ("CNY", "Yuan (CNY)")], default="USD", max_length=3)),
        migrations.AlterField(
            model_name="supplierorder",
            name="statut",
            field=models.CharField(choices=[("BROUILLON", "Brouillon"), ("COMMANDE", "Commande"), ("ACOMPTE_PAYE", "Acompte payé"), ("PREPARATION", "Préparation"), ("PAYE", "Entièrement payé"), ("EXPEDIE", "Expédié"), ("EN_TRANSIT", "En transit"), ("ARRIVE", "Arrivé à Madagascar"), ("COUT_FINALISE", "Coût finalisé")], default="BROUILLON", max_length=20),
        ),
        # 2. Conversion des données existantes.
        migrations.RunPython(convertir, migrations.RunPython.noop),
        # 3. Suppression de ce qui est remplacé.
        migrations.DeleteModel(name="VariantCostHistory"),
        migrations.DeleteModel(name="SupplierFee"),
        migrations.DeleteModel(name="SupplierOrderLine"),
        migrations.RemoveField(model_name="supplierorder", name="prix_fournisseur"),
        migrations.RemoveField(model_name="supplierorder", name="fret_import"),
        migrations.RemoveField(model_name="supplierorder", name="douane"),
        migrations.RemoveField(model_name="supplierorder", name="taux_change"),
        migrations.RemoveField(model_name="supplierorder", name="methode_allocation"),
        migrations.RemoveField(model_name="supplierorder", name="total_qty"),
        migrations.RemoveField(model_name="supplierorder", name="valeur_achat_mga"),
        migrations.RemoveField(model_name="supplierorder", name="total_frais_mga"),
        migrations.RemoveField(model_name="supplierorder", name="cout_total"),
        migrations.RemoveField(model_name="supplierorder", name="cout_unitaire"),
        migrations.AlterField(
            model_name="supplierorder",
            name="supplier",
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name="orders", to="suppliers.supplier"),
        ),
        migrations.AddIndex(model_name="supplierorder", index=models.Index(fields=["magasin", "statut"], name="suppliers_order_mag_stat_idx")),
    ]
