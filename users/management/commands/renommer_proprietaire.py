"""Renomme le compte PROPRIÉTAIRE de l'application.

`gerant@smartphone.mg` → `admin@smartphone.mg` (mission § 1 et § 32).

Ce compte n'a jamais été un gérant de magasin : il porte `role="admin"` et
l'`AdminProfile` de la société. Son ancienne adresse prêtait à confusion
maintenant que « gérant » désigne un rôle distinct, limité à un magasin.

CE QUI EST MODIFIÉ : `email` et `username` du compte, rien d'autre. Ni le mot
de passe, ni le rôle, ni l'AdminProfile, ni les magasins, ni l'historique.

Mode APERÇU par défaut : rien n'est écrit tant que `--apply` n'est pas passé.
Sur le VPS, toujours lire l'aperçu avant d'appliquer.

Usage :
  python manage.py renommer_proprietaire                     # aperçu seul
  python manage.py renommer_proprietaire --apply             # applique
  python manage.py renommer_proprietaire --ancien x@y --nouveau z@y --apply
"""

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from users.models import AdminProfile, CustomUser

ANCIEN_DEFAUT = "gerant@smartphone.mg"
NOUVEAU_DEFAUT = "admin@smartphone.mg"


class Command(BaseCommand):
    help = "Renomme le compte propriétaire (gerant@smartphone.mg -> admin@smartphone.mg)."

    def add_arguments(self, parser):
        parser.add_argument("--ancien", default=ANCIEN_DEFAUT)
        parser.add_argument("--nouveau", default=NOUVEAU_DEFAUT)
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Écrit réellement. Sans ce drapeau, la commande se contente d'afficher.",
        )

    def handle(self, *args, **options):
        ancien = options["ancien"].strip().lower()
        nouveau = options["nouveau"].strip().lower()
        appliquer = options["apply"]

        compte = CustomUser.objects.filter(email__iexact=ancien).first()
        deja = CustomUser.objects.filter(email__iexact=nouveau).first()

        # --- Cas déjà traité : la commande est rejouable sans risque --------
        if compte is None and deja is not None:
            self._etat(deja)
            self.stdout.write(self.style.SUCCESS(
                f"Rien à faire : « {nouveau} » existe déjà et « {ancien} » n'existe plus."
            ))
            return

        if compte is None:
            raise CommandError(
                f"Aucun compte avec l'adresse « {ancien} ». "
                "Vérifiez l'adresse réelle du propriétaire (--ancien)."
            )

        # --- Collision : deux comptes distincts ----------------------------
        if deja is not None and deja.pk != compte.pk:
            raise CommandError(
                f"« {nouveau} » est déjà utilisé par le compte #{deja.pk} "
                f"({deja.full_name}, rôle {deja.role}). Renommer écraserait une "
                "adresse existante : résolvez le conflit à la main d'abord."
            )

        # --- Ce que l'on s'apprête à toucher -------------------------------
        self.stdout.write(self.style.MIGRATE_HEADING("\nCompte trouvé"))
        self._etat(compte)

        if compte.role != "admin":
            self.stdout.write(self.style.WARNING(
                f"  ATTENTION : rôle « {compte.role} » et non « admin ». "
                "Ce n'est peut-être pas le compte propriétaire."
            ))

        self.stdout.write(self.style.MIGRATE_HEADING("\nModification prévue"))
        self.stdout.write(f"  email    : {compte.email}  ->  {nouveau}")
        self.stdout.write(f"  username : {compte.username}  ->  {nouveau}")
        self.stdout.write("  (rôle, mot de passe, AdminProfile, magasins : inchangés)")

        if not appliquer:
            self.stdout.write(self.style.WARNING(
                "\nAPERÇU — rien n'a été écrit. Relancez avec --apply pour appliquer."
            ))
            return

        with transaction.atomic():
            compte.email = nouveau
            compte.username = nouveau
            compte.save(update_fields=["email", "username", "updated_at"])

        compte.refresh_from_db()
        self.stdout.write(self.style.MIGRATE_HEADING("\nAprès modification"))
        self._etat(compte)
        self.stdout.write(self.style.SUCCESS(
            f"\nTerminé. Le propriétaire se connecte désormais avec « {nouveau} » "
            "et SON MOT DE PASSE INCHANGÉ."
        ))

    def _etat(self, compte):
        """Les quatre contrôles demandés par la mission § 32."""
        profil = AdminProfile.objects.filter(user=compte).first()
        magasins = compte.magasins.count()
        self.stdout.write(f"  id            : {compte.pk}")
        self.stdout.write(f"  email         : {compte.email}")
        self.stdout.write(f"  nom           : {compte.full_name}")
        self.stdout.write(f"  role          : {compte.role}")
        self.stdout.write(f"  is_staff      : {compte.is_staff}")
        self.stdout.write(f"  is_confirmed  : {compte.is_confirmed}")
        self.stdout.write(
            f"  AdminProfile  : {'oui — ' + profil.company_name if profil else 'NON'}"
        )
        self.stdout.write(f"  magasins      : {magasins}")
