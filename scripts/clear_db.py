#!/usr/bin/env python3
"""
Vide toutes les tables de db.sqlite3 sans les supprimer.
Les tables système Django (migrations, permissions, content types) sont préservées par défaut.
"""

import sqlite3
import os
import sys
import argparse

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "db.sqlite3")

# Tables Django système à préserver par défaut
DJANGO_SYSTEM_TABLES = {
    "django_migrations",
    "django_content_type",
    "auth_permission",
    "auth_group",
    "auth_group_permissions",
    "sqlite_sequence",
}


def get_tables(cursor):
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    return [row[0] for row in cursor.fetchall()]


def count_rows(cursor, table):
    cursor.execute(f"SELECT COUNT(*) FROM \"{table}\"")
    return cursor.fetchone()[0]


def clear_db(include_system=False, dry_run=False):
    if not os.path.exists(DB_PATH):
        print(f"Erreur: base de données introuvable: {DB_PATH}")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    tables = get_tables(cursor)

    tables_to_clear = []
    tables_skipped = []

    for table in tables:
        if not include_system and table in DJANGO_SYSTEM_TABLES:
            tables_skipped.append(table)
        else:
            tables_to_clear.append(table)

    print(f"Base de données: {DB_PATH}")
    print(f"Mode: {'simulation (dry-run)' if dry_run else 'SUPPRESSION RÉELLE'}")
    print()

    if tables_skipped:
        print(f"Tables préservées ({len(tables_skipped)}):")
        for t in tables_skipped:
            print(f"  - {t}")
        print()

    print(f"Tables à vider ({len(tables_to_clear)}):")
    total_rows = 0
    for t in tables_to_clear:
        n = count_rows(cursor, t)
        total_rows += n
        print(f"  - {t:<45} {n:>6} lignes")

    print(f"\n  Total: {total_rows} lignes à supprimer")

    if dry_run:
        print("\nSimulation terminée. Aucune donnée supprimée.")
        conn.close()
        return

    confirm = input("\nConfirmer la suppression ? (oui/non): ").strip().lower()
    if confirm not in ("oui", "o", "yes", "y"):
        print("Annulé.")
        conn.close()
        return

    # Désactiver les foreign keys le temps du nettoyage
    cursor.execute("PRAGMA foreign_keys = OFF")

    deleted_total = 0
    errors = []

    for table in tables_to_clear:
        try:
            cursor.execute(f"DELETE FROM \"{table}\"")
            deleted_total += cursor.rowcount
            print(f"  Vidé: {table}")
        except sqlite3.Error as e:
            errors.append((table, str(e)))
            print(f"  Erreur sur {table}: {e}")

    # Réinitialiser les auto-increments
    cursor.execute("DELETE FROM sqlite_sequence")

    cursor.execute("PRAGMA foreign_keys = ON")

    conn.commit()
    conn.close()

    print(f"\n{deleted_total} lignes supprimées.")
    if errors:
        print(f"{len(errors)} erreur(s) rencontrée(s).")
    else:
        print("Nettoyage terminé avec succès.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Vide les tables de db.sqlite3")
    parser.add_argument(
        "--include-system",
        action="store_true",
        help="Inclure aussi les tables système Django (migrations, permissions, etc.)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Afficher ce qui serait supprimé sans rien effacer",
    )
    args = parser.parse_args()

    clear_db(include_system=args.include_system, dry_run=args.dry_run)
