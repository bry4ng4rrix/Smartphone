"""La boutique en ligne n'a plus de comptes : `Order.client` disparaît au
profit d'un drapeau explicite `origine_en_ligne`.

L'ordre des opérations compte. On ajoute d'abord le drapeau, on REPORTE
l'information portée par le FK (toute commande rattachée à un compte venait
du site), et seulement ensuite on retire la colonne. Faire l'inverse ferait
perdre le marqueur sur tout l'historique : le gérant ne saurait plus
distinguer une commande passée en ligne d'une saisie au comptoir.
"""
from django.db import migrations, models


def marquer_commandes_en_ligne(apps, schema_editor):
    Order = apps.get_model("orders", "Order")
    Order.objects.filter(client__isnull=False).update(origine_en_ligne=True)


def revenir_en_arriere(apps, schema_editor):
    """Le FK ne peut pas être reconstitué : les comptes sont supprimés par
    clients.0002. On ne fait donc rien plutôt que de mentir sur la réussite
    d'un retour arrière complet."""
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('orders', '0020_merge_20260917_1853'),
    ]

    operations = [
        migrations.AddField(
            model_name='order',
            name='origine_en_ligne',
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(marquer_commandes_en_ligne, revenir_en_arriere),
        migrations.RemoveField(
            model_name='order',
            name='client',
        ),
    ]
