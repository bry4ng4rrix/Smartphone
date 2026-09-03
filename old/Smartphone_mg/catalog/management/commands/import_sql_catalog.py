import ast
import re
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from orders.models import Order
from suppliers.models import SupplierOrder

DEFAULT_FILE = settings.BASE_DIR / "seed catalogue.sql"

# Table SQL -> (modèle, colonnes de l'INSERT dans l'ordre du fichier)
TABLE_MODELS = {
    "ProductCategory": (ProductCategory, ["id", "nom", "ordre"]),
    "ProductType": (ProductType, ["id", "category_id", "nom"]),
    "Brand": (Brand, ["id", "nom"]),
    "ProductReference": (ProductReference, ["id", "type_id", "brand_id", "reference_name", "prix_vente"]),
    "ProductVariant": (
        ProductVariant,
        ["id", "product_reference_id", "couleur", "sku_loyverse", "stock_actuel", "seuil_alerte"],
    ),
}

INSERT_RE = re.compile(
    r"INSERT INTO (\w+)\s*\(([^)]+)\)\s*VALUES\s*(.*?);", re.DOTALL | re.IGNORECASE
)


def _split_top_level_tuples(text):
    """Découpe le texte entre VALUES et ';' en contenus de tuples top-level
    "(...)" séparés par des virgules — en respectant les guillemets, pour
    ne pas se faire piéger par des parenthèses à l'intérieur d'une valeur
    (ex: reference_name = 'Oppo A56 (Oppo)')."""

    tuples, current, depth, in_string = [], [], 0, False
    for ch in text:
        if in_string:
            current.append(ch)
            if ch == "'":
                in_string = False
            continue
        if ch == "'":
            in_string = True
            current.append(ch)
            continue
        if ch == "(":
            depth += 1
            if depth == 1:
                current = []
                continue
        if ch == ")":
            depth -= 1
            if depth == 0:
                tuples.append("".join(current))
                continue
        if depth >= 1:
            current.append(ch)
    return tuples


def _parse_tuples(values_blob):
    """Convertit le texte entre VALUES et ';' en liste de tuples Python.
    La syntaxe SQL (nombres, chaînes 'entre quotes') est un sous-ensemble
    valide de la syntaxe littérale Python, sauf NULL -> None."""

    text = re.sub(r"\bNULL\b", "None", values_blob, flags=re.IGNORECASE)
    return [ast.literal_eval(f"({t})") for t in _split_top_level_tuples(text)]


class Command(BaseCommand):
    help = (
        "Importe le catalogue réel depuis 'seed catalogue.sql' (export Loyverse, §8.1 README) — "
        "remplace le catalogue de test créé par seed_catalog."
    )

    def add_arguments(self, parser):
        parser.add_argument("--file", type=str, default=str(DEFAULT_FILE))

    @transaction.atomic
    def handle(self, *args, **options):
        path = Path(options["file"])
        if not path.exists():
            raise CommandError(f"Fichier introuvable : {path}")

        sql = path.read_text(encoding="utf-8")

        blocks = {}
        for match in INSERT_RE.finditer(sql):
            table = match.group(1)
            values_blob = match.group(3)
            blocks.setdefault(table, []).extend(_parse_tuples(values_blob))

        missing = [t for t in TABLE_MODELS if t not in blocks]
        if missing:
            raise CommandError(f"Tables absentes du fichier : {missing}")

        # Les commandes/commandes fournisseur existantes référencent le
        # catalogue de démo (seed_catalog) qu'on s'apprête à remplacer —
        # elles ne peuvent pas survivre au changement de catalogue
        # (product_variant est PROTECT sur OrderItem/SupplierOrderLine).
        nb_orders = Order.objects.count()
        nb_supplier_orders = SupplierOrder.objects.count()
        if nb_orders or nb_supplier_orders:
            self.stdout.write(self.style.WARNING(
                f"Suppression de {nb_orders} commande(s) et {nb_supplier_orders} commande(s) "
                "fournisseur existantes (elles référencent le catalogue de démo remplacé par cet import)."
            ))
            Order.objects.all().delete()
            SupplierOrder.objects.all().delete()

        # Repart de zéro pour ces 5 tables (ordre inverse des FK).
        ProductVariant.objects.all().delete()
        ProductReference.objects.all().delete()
        ProductType.objects.all().delete()
        Brand.objects.all().delete()
        ProductCategory.objects.all().delete()

        total = 0
        for table, (model, columns) in TABLE_MODELS.items():
            objects = [model(**dict(zip(columns, row))) for row in blocks[table]]
            model.objects.bulk_create(objects)
            total += len(objects)
            self.stdout.write(f"  {table}: {len(objects)} lignes")

        self.stdout.write(self.style.SUCCESS(f"Import terminé : {total} lignes au total depuis {path.name}"))
