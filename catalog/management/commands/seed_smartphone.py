"""Charge le vrai catalogue Smartphone.Mg (housses/cache-écran, ~300
références et ~530 variantes couleur, avec stock et SKU Loyverse réels)
depuis le fichier `data/seed_catalogue.sql` livré avec cette commande, et
crée le tenant (magasin) + comptes de test des 3 rôles du cahier des charges.

Idempotent (get_or_create) : peut être relancée sans dupliquer les données.
Fonctionne aussi bien en local (SQLite) qu'en production (Postgres, VPS) —
voir roadmap.md à la racine du projet pour le déploiement complet.

Usage : python manage.py seed_smartphone
"""

import re
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from users.models import AdminProfile, CustomUser, EmployerProfile, MagasinProfile

SEED_FILE = Path(__file__).resolve().parent / "data" / "seed_catalogue.sql"

# Comptes de test des 3 rôles du module Commande (§4 Smartreadme.md) — mêmes
# identifiants que l'implémentation de référence (old/Smartphone_mg/catalog/
# management/commands/seed_catalog.py), adaptés au modèle multi-tenant
# (magasin/employer) de ce projet plutôt qu'à un rôle direct sur CustomUser.
GERANT_EMAIL = "gerant@smartphone.mg"
# Plusieurs comptes par rôle pour pouvoir tester l'affectation nominative
# (un préparateur/livreur à la fois par commande — voir orders/services.py).
PREPARATEUR_EMAILS = ["preparateur@smartphone.mg", "preparateur2@smartphone.mg"]
LIVREUR_EMAILS = ["livreur@smartphone.mg", "livreur2@smartphone.mg", "livreur3@smartphone.mg"]
DEFAULT_PASSWORD = "smartphone2026"

INSERT_RE = re.compile(r"INSERT INTO (\w+) \([^)]*\) VALUES\s*(.*?);", re.DOTALL)


def _split_tuples(values_blob):
    """Découpe le texte entre VALUES et ';' en tuples `(a, b, 'c, d', ...)`,
    en respectant les guillemets simples (avec échappement SQL `''`) pour ne
    pas couper sur une virgule à l'intérieur d'une chaîne."""
    tuples = []
    depth = 0
    in_string = False
    current = []
    i = 0
    n = len(values_blob)
    while i < n:
        ch = values_blob[i]
        if in_string:
            if ch == "'" and i + 1 < n and values_blob[i + 1] == "'":
                current.append("''")
                i += 2
                continue
            if ch == "'":
                in_string = False
            current.append(ch)
        else:
            if ch == "'":
                in_string = True
                current.append(ch)
            elif ch == "(":
                depth += 1
                if depth > 1:
                    current.append(ch)
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    tuples.append("".join(current))
                    current = []
                else:
                    current.append(ch)
            elif depth > 0:
                current.append(ch)
        i += 1
    return tuples


def _split_fields(tuple_text):
    """Découpe le contenu d'un tuple en champs, respectant les guillemets."""
    fields = []
    in_string = False
    current = []
    i = 0
    n = len(tuple_text)
    while i < n:
        ch = tuple_text[i]
        if in_string:
            if ch == "'" and i + 1 < n and tuple_text[i + 1] == "'":
                current.append("'")
                i += 2
                continue
            if ch == "'":
                in_string = False
                i += 1
                continue
            current.append(ch)
        else:
            if ch == "'":
                in_string = True
                i += 1
                continue
            if ch == ",":
                fields.append("".join(current).strip())
                current = []
                i += 1
                continue
            current.append(ch)
        i += 1
    fields.append("".join(current).strip())
    return fields


def _to_python(value):
    if value.upper() == "NULL":
        return None
    return value


def parse_seed_sql(path):
    text = path.read_text(encoding="utf-8")
    tables = {}
    for match in INSERT_RE.finditer(text):
        table = match.group(1)
        rows = [
            [_to_python(f) for f in _split_fields(t)]
            for t in _split_tuples(match.group(2))
        ]
        tables.setdefault(table, []).extend(rows)
    return tables


class Command(BaseCommand):
    help = "Charge le catalogue Smartphone.Mg réel (data/seed_catalogue.sql) + les comptes de test des 3 rôles."

    def handle(self, *args, **options):
        if not SEED_FILE.exists():
            raise CommandError(f"Fichier introuvable : {SEED_FILE}")

        tables = parse_seed_sql(SEED_FILE)
        for name in ("ProductCategory", "ProductType", "Brand", "ProductReference", "ProductVariant"):
            if not tables.get(name):
                raise CommandError(f"Aucune ligne trouvée pour {name} dans {SEED_FILE}")

        with transaction.atomic():
            magasin = self._ensure_tenant()
            self._seed_catalog(magasin, tables)

        self.stdout.write(self.style.SUCCESS(
            f"Catalogue Smartphone.Mg chargé : "
            f"{ProductReference.objects.filter(type__category__magasin=magasin).count()} références, "
            f"{ProductVariant.objects.filter(product_reference__type__category__magasin=magasin).count()} variantes."
        ))
        demo_emails = ", ".join([GERANT_EMAIL] + PREPARATEUR_EMAILS + LIVREUR_EMAILS)
        self.stdout.write(self.style.WARNING(
            "⚠ Comptes de démo (re)créés avec le mot de passe par défaut "
            f"'{DEFAULT_PASSWORD}' : {demo_emails}. "
            "En production, changez ces mots de passe avant d'ouvrir l'accès au public "
            "(voir roadmap.md § Sécurité)."
        ))

    def _ensure_tenant(self):
        gerant_user, created = CustomUser.objects.get_or_create(
            email=GERANT_EMAIL,
            defaults={
                "username": GERANT_EMAIL,
                "full_name": "Gérant Smartphone.Mg",
                "role": "admin",
                "is_confirmed": True,
            },
        )
        # Toujours réaligné sur le mot de passe de test documenté, même si le
        # compte existait déjà — évite que ce tenant de démo devienne
        # inutilisable après une dérive locale (ex: session interrompue en
        # plein test d'une fonctionnalité "changer le mot de passe").
        gerant_user.set_password(DEFAULT_PASSWORD)
        gerant_user.save()

        admin_profile, _ = AdminProfile.objects.get_or_create(
            user=gerant_user, defaults={"company_name": "Smartphone.Mg"}
        )

        magasin, _ = MagasinProfile.objects.get_or_create(
            admin=gerant_user, shop_name="Smartphone.Mg",
            defaults={"description": "Housses, cache-écrans & accessoires téléphone — Madagascar"},
        )
        magasin.admins.add(gerant_user)

        for i, email in enumerate(PREPARATEUR_EMAILS, start=1):
            full_name = "Préparateur Smartphone.Mg" if i == 1 else f"Préparateur {i} Smartphone.Mg"
            self._ensure_employee(email, full_name, "PREPARATEUR", gerant_user, magasin)
        for i, email in enumerate(LIVREUR_EMAILS, start=1):
            full_name = "Livreur Smartphone.Mg" if i == 1 else f"Livreur {i} Smartphone.Mg"
            self._ensure_employee(email, full_name, "LIVREUR", gerant_user, magasin)

        return magasin

    def _ensure_employee(self, email, full_name, commande_role, admin_user, magasin):
        user, created = CustomUser.objects.get_or_create(
            email=email,
            defaults={
                "username": email,
                "full_name": full_name,
                "role": "employer",
                "is_confirmed": True,
            },
        )
        user.set_password(DEFAULT_PASSWORD)
        user.save()

        EmployerProfile.objects.get_or_create(
            user=user,
            defaults={
                "admin": admin_user,
                "magasin": magasin,
                "position": commande_role.title(),
                "commande_role": commande_role,
            },
        )

    def _seed_catalog(self, magasin, tables):
        categories = {}
        for row in tables["ProductCategory"]:
            sql_id, nom, ordre = row
            obj, _ = ProductCategory.objects.get_or_create(
                magasin=magasin, nom=nom, defaults={"ordre": int(ordre)}
            )
            categories[sql_id] = obj

        types_ = {}
        for row in tables["ProductType"]:
            sql_id, category_id, nom = row
            obj, _ = ProductType.objects.get_or_create(category=categories[category_id], nom=nom)
            types_[sql_id] = obj

        brands = {}
        for row in tables["Brand"]:
            sql_id, nom = row
            obj, _ = Brand.objects.get_or_create(magasin=magasin, nom=nom)
            brands[sql_id] = obj

        references = {}
        for row in tables["ProductReference"]:
            sql_id, type_id, brand_id, reference_name, prix_vente = row
            obj, _ = ProductReference.objects.get_or_create(
                type=types_[type_id], brand=brands[brand_id], reference_name=reference_name,
                defaults={"prix_vente": prix_vente},
            )
            references[sql_id] = obj

        for row in tables["ProductVariant"]:
            _sql_id, reference_id, couleur, sku_loyverse, stock_actuel, seuil_alerte = row
            ProductVariant.objects.get_or_create(
                product_reference=references[reference_id], couleur=couleur,
                defaults={
                    "sku_loyverse": sku_loyverse,
                    "stock_actuel": int(stock_actuel),
                    "seuil_alerte": int(seuil_alerte),
                },
            )
