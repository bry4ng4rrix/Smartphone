"""Renomme l'email des préparateurs/livreurs en <nom>@smartphone.mg
(§ demande) — ex: "Lili" -> "lili@smartphone.mg". Ne touche à AUCUN autre
champ (magasin, mot de passe, historique, statut...).

Mode "aperçu" (dry-run) par défaut — rien n'est écrit tant que --apply n'est
pas passé. Indispensable avant de lancer ça sur le VPS où les données sont
réelles : toujours relire l'aperçu d'abord.

Usage :
  python manage.py rename_staff_emails              # aperçu seul, rien n'est écrit
  python manage.py rename_staff_emails --apply       # applique réellement
  python manage.py rename_staff_emails --domain autredomaine.mg --apply
"""

import re
import unicodedata

from django.core.management.base import BaseCommand
from django.db import transaction

from users.models import CustomUser


def local_part_from_name(full_name: str) -> str:
    """"Lili Rasoa" -> "lilirasoa" — accents et caractères non alphanumériques retirés."""
    normalized = unicodedata.normalize("NFKD", full_name)
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]", "", ascii_only.lower())


class Command(BaseCommand):
    help = "Renomme l'email des préparateurs/livreurs en <nom>@<domaine> (aperçu par défaut, voir --apply)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Applique réellement les changements. Sans cette option : aperçu seul, aucune écriture.",
        )
        parser.add_argument(
            "--domain",
            default="smartphone.mg",
            help="Domaine à utiliser pour le nouvel email (par défaut smartphone.mg).",
        )

    def handle(self, *args, **options):
        apply_changes = options["apply"]
        domain = options["domain"]

        staff = (
            CustomUser.objects.filter(
                role="employer",
                employer_profile__commande_role__in=["PREPARATEUR", "LIVREUR"],
            )
            .select_related("employer_profile")
            .order_by("id")
        )

        if not staff.exists():
            self.stdout.write("Aucun préparateur/livreur trouvé.")
            return

        # Emails déjà pris par des comptes HORS du lot à modifier — pour ne
        # jamais créer de collision avec un compte existant non concerné
        # (gérant, autre employé sans commande_role, etc.).
        taken_emails = set(
            CustomUser.objects.exclude(pk__in=staff.values_list("pk", flat=True)).values_list(
                "email", flat=True
            )
        )
        reserved_this_run = set()

        changes = []
        skipped = []
        for user in staff:
            if not user.full_name.strip():
                skipped.append((user, "nom vide"))
                continue

            base = local_part_from_name(user.full_name)
            if not base:
                skipped.append((user, "nom sans caractère alphanumérique"))
                continue

            new_email = f"{base}@{domain}"
            suffix = 2
            while new_email in taken_emails or new_email in reserved_this_run:
                new_email = f"{base}{suffix}@{domain}"
                suffix += 1
            reserved_this_run.add(new_email)

            if user.email == new_email:
                continue  # déjà à jour — idempotent, rien à faire

            changes.append((user, new_email))

        self.stdout.write(f"{len(changes)} compte(s) à modifier, {len(skipped)} ignoré(s).\n")
        for user, new_email in changes:
            role = user.employer_profile.commande_role
            self.stdout.write(f"  [{role}] {user.full_name!r} : {user.email} -> {new_email}")
        for user, reason in skipped:
            role = user.employer_profile.commande_role
            self.stdout.write(
                self.style.WARNING(f"  IGNORÉ [{role}] {user.full_name!r} ({user.email}) — {reason}")
            )

        if not changes:
            self.stdout.write("\nRien à faire.")
            return

        if not apply_changes:
            self.stdout.write(
                self.style.NOTICE(
                    "\nAperçu seul, rien n'a été écrit — relire la liste ci-dessus puis "
                    "relancer avec --apply pour appliquer réellement."
                )
            )
            return

        with transaction.atomic():
            for user, new_email in changes:
                user.email = new_email
                user.save(update_fields=["email"])

        self.stdout.write(self.style.SUCCESS(f"\n{len(changes)} email(s) mis à jour."))
