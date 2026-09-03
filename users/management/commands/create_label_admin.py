import os

from django.core.management.base import BaseCommand, CommandError

from users.models import CustomUser


class Command(BaseCommand):
    help = "Crée ou met à jour le compte plateforme 'Label Technology' (role=platform_admin)."

    def handle(self, *args, **options):
        email = os.environ.get("LABEL_ADMIN_EMAIL")
        password = os.environ.get("LABEL_ADMIN_PASSWORD")

        if not email or not password:
            raise CommandError(
                "LABEL_ADMIN_EMAIL et LABEL_ADMIN_PASSWORD doivent être définis dans l'environnement."
            )

        user = CustomUser.objects.filter(email=email).first()

        if user is None:
            user = CustomUser.objects.create(
                username=email,
                email=email,
                full_name="Label Technology",
                role="platform_admin",
                is_confirmed=True,
                is_staff=False,
                is_superuser=False,
            )
            user.set_password(password)
            user.save()
            self.stdout.write(self.style.SUCCESS(f"Compte Label Technology créé ({email})."))
        else:
            user.role = "platform_admin"
            user.is_confirmed = True
            user.is_staff = False
            user.is_superuser = False
            user.set_password(password)
            user.save()
            self.stdout.write(self.style.SUCCESS(f"Compte Label Technology mis à jour ({email})."))
