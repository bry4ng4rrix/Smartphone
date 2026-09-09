#!/usr/bin/env python3
import argparse
import os
import re
import sys
import unicodedata

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "Stock.settings")

import django

django.setup()

from django.db import transaction
from users.models import CustomUser


TARGET_ROLE = "employer"
TARGET_COMMANDE_ROLES = {"PREPARATEUR", "LIVREUR"}


def normalize_name(value: str) -> str:
    cleaned = unicodedata.normalize("NFKD", value or "")
    cleaned = "".join(ch for ch in cleaned if not unicodedata.combining(ch))
    cleaned = cleaned.lower().strip()
    cleaned = re.sub(r"[^a-z0-9]+", "-", cleaned)
    cleaned = cleaned.strip("-")
    return cleaned or "employe"


def build_candidate_email(full_name: str, domain: str) -> str:
    local_part = normalize_name(full_name)
    return f"{local_part}@{domain.strip().lower()}"


def ensure_unique_email(candidate: str, user_id: int, domain: str) -> str:
    if not CustomUser.objects.filter(email=candidate).exclude(id=user_id).exists():
        return candidate

    local_part, _, suffix = candidate.partition("@")
    index = 2
    while True:
        new_candidate = f"{local_part}-{index}@{suffix or domain}"
        if not CustomUser.objects.filter(email=new_candidate).exclude(id=user_id).exists():
            return new_candidate
        index += 1


def iter_candidates():
    qs = (
        CustomUser.objects.filter(role=TARGET_ROLE)
        .select_related("employer_profile")
        .order_by("full_name", "id")
    )

    for user in qs:
        commande_role = getattr(getattr(user, "employer_profile", None), "commande_role", None)
        if commande_role in TARGET_COMMANDE_ROLES:
            yield user


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Met à jour les emails des employés (préparateurs et livreurs) selon leur nom, "
            "ex: 'Lili' -> 'lili@smartphone.mg'."
        )
    )
    parser.add_argument("--domain", default="smartphone.mg", help="Domaine à utiliser pour le mail. Default: smartphone.mg")
    parser.add_argument("--apply", action="store_true", help="Applique les changements en base. Par défaut, script en mode dry-run.")
    args = parser.parse_args()

    domain = args.domain.strip().lower().lstrip("@")
    if not domain:
        print("Erreur: le domaine ne peut pas être vide.", file=sys.stderr)
        return 2

    planned_updates = []
    total = 0

    for user in iter_candidates():
        current_email = (user.email or "").strip()
        target_email = ensure_unique_email(
            build_candidate_email(user.full_name, domain),
            user.id,
            domain,
        )
        if current_email.lower() == target_email.lower():
            continue

        total += 1
        planned_updates.append((user, current_email, target_email))

    if not planned_updates:
        print(f"Aucune modification nécessaire pour les employés {', '.join(sorted(TARGET_COMMANDE_ROLES))}.")
        return 0

    print(f"{len(planned_updates)} mise(s) à prévoir pour {len(planned_updates)} employé(s).")
    for user, old_email, new_email in planned_updates:
        print(f"- {user.full_name}: {old_email or '(vide)'} -> {new_email}")

    if not args.apply:
        print("\nMode dry-run: aucune modification n'a été enregistrée.")
        print("Pour appliquer: python3 scripts/update_employee_emails.py --apply")
        return 0

    with transaction.atomic():
        for user, _, new_email in planned_updates:
            user.email = new_email
            user.username = new_email
            user.save(update_fields=["email", "username"])

    print("\nMises à jour appliquées avec succès.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
