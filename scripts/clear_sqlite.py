#!/usr/bin/env python3
"""Vide une base SQLite sans supprimer les tables.

Usage:
    python scripts/clear_sqlite.py /path/to/db.sqlite3

Si aucun chemin n'est fourni, le script utilise db.sqlite3 à la racine du projet.
"""

import argparse
import sqlite3
import sys


def clear_sqlite_database(db_path: str) -> None:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        cursor = conn.cursor()
        cursor.execute("PRAGMA foreign_keys = OFF;")
        cursor.execute("BEGIN TRANSACTION;")

        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"
        )
        tables = [row[0] for row in cursor.fetchall()]

        if not tables:
            print(f"Aucune table utilisateur trouvée dans {db_path}.")
            return

        for table in tables:
            print(f"Vidage de la table: {table}")
            cursor.execute(f"DELETE FROM \"{table}\";")

        cursor.execute("DELETE FROM sqlite_sequence;")
        conn.commit()
        print(f"Base de données vidée avec succès : {db_path}")
    except sqlite3.Error as exc:
        conn.rollback()
        print(f"Erreur SQLite : {exc}", file=sys.stderr)
        raise
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Vider une base SQLite sans supprimer les tables.")
    parser.add_argument(
        "db_path",
        nargs="?",
        default="db.sqlite3",
        help="Chemin vers le fichier SQLite (par défaut : db.sqlite3)",
    )
    args = parser.parse_args()

    clear_sqlite_database(args.db_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
