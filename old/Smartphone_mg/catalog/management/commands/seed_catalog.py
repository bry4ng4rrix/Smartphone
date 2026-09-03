from django.core.management.base import BaseCommand
from django.db import transaction

from catalog.models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant
from users.models import CustomUser


class Command(BaseCommand):
    help = "Seed minimal : catégories/sous-types/marques/références de test + 1 utilisateur par rôle."

    @transaction.atomic
    def handle(self, *args, **options):
        housse, _ = ProductCategory.objects.get_or_create(nom="HOUSSE", defaults={"ordre": 1})
        cache_ecran, _ = ProductCategory.objects.get_or_create(nom="CACHE ÉCRAN", defaults={"ordre": 2})

        flip_cover, _ = ProductType.objects.get_or_create(category=housse, nom="FLIP COVER")
        z_fold, _ = ProductType.objects.get_or_create(category=housse, nom="Z-FOLD")
        z_flip, _ = ProductType.objects.get_or_create(category=housse, nom="Z-FLIP")
        privacy, _ = ProductType.objects.get_or_create(category=cache_ecran, nom="PRIVACY")

        brand_names = ["Samsung", "iPhone", "Huawei", "Redmi", "Xiaomi", "Tecno", "Infinix", "Itel", "Oppo", "Realme", "Google Pixel"]
        brands = {name: Brand.objects.get_or_create(nom=name)[0] for name in brand_names}

        references = [
            (flip_cover, brands["Samsung"], "A15", 15000, ["Noir", "Bleu", "Rose"]),
            (flip_cover, brands["Samsung"], "S23", 18000, ["Noir", "Blanc"]),
            (flip_cover, brands["iPhone"], "15 Pro Max", 22000, ["Noir", "Transparent"]),
            (flip_cover, brands["Redmi"], "Note 13", 14000, ["Noir", "Vert"]),
            (z_fold, brands["Samsung"], "Z-Fold 5", 35000, ["Noir"]),
            (z_flip, brands["Samsung"], "Z-Flip 5", 32000, ["Violet", "Crème"]),
            (privacy, brands["Samsung"], "A15", 8000, ["Standard"]),
            (privacy, brands["iPhone"], "15 Pro Max", 9000, ["Standard"]),
        ]

        for product_type, brand, ref_name, prix, couleurs in references:
            reference, _ = ProductReference.objects.get_or_create(
                type=product_type, brand=brand, reference_name=ref_name,
                defaults={"prix_vente": prix},
            )
            for couleur in couleurs:
                ProductVariant.objects.get_or_create(
                    product_reference=reference, couleur=couleur,
                    defaults={"stock_actuel": 10, "seuil_alerte": 3},
                )

        test_accounts = [
            ("gerant@smartphone.mg", "Gérant Test", "GERANT"),
            ("preparateur@smartphone.mg", "Préparateur Test", "PREPARATEUR"),
            ("livreur@smartphone.mg", "Livreur Test", "LIVREUR"),
        ]
        for email, full_name, role in test_accounts:
            if not CustomUser.objects.filter(email=email).exists():
                CustomUser.objects.create_user(
                    email=email, password="test1234", full_name=full_name, role=role,
                )

        self.stdout.write(self.style.SUCCESS(
            "Seed terminé : catalogue de test + gerant@smartphone.mg / preparateur@smartphone.mg / "
            "livreur@smartphone.mg (mot de passe: test1234)"
        ))
