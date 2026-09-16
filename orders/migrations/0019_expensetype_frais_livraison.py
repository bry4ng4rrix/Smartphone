from django.db import migrations, models


def marquer_types_livraison(apps, schema_editor):
    """Reprise de l'existant : les types dont le nom contient « livraison »
    (LIVRAISON 3K / 4K / 5K…) sont marqués frais de livraison, pour que la
    marge livraison des rapports ne change pas de sens sans intervention."""
    ExpenseType = apps.get_model("orders", "ExpenseType")
    ExpenseType.objects.filter(nom__icontains="livraison").update(frais_livraison=True)


class Migration(migrations.Migration):

    dependencies = [
        ("orders", "0018_boost_periode_indexes"),
    ]

    operations = [
        migrations.AddField(
            model_name="expensetype",
            name="frais_livraison",
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(marquer_types_livraison, migrations.RunPython.noop),
    ]
