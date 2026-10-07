"""La commande de renommage du propriétaire (mission § 1, § 32)."""
from io import StringIO

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from users.models import AdminProfile, CustomUser, MagasinProfile


class RenommerProprietaireTests(TestCase):
    def setUp(self):
        self.proprio = CustomUser.objects.create_user(
            email="gerant@smartphone.mg", password="motdepasse", role="admin",
            full_name="Propriétaire", is_confirmed=True,
        )
        AdminProfile.objects.create(user=self.proprio, company_name="Smartphone.Mg")
        MagasinProfile.objects.create(admin=self.proprio, shop_name="Boutique")

    def lancer(self, **kwargs):
        sortie = StringIO()
        call_command("renommer_proprietaire", stdout=sortie, **kwargs)
        return sortie.getvalue()

    def test_apercu_n_ecrit_rien(self):
        sortie = self.lancer()
        self.assertIn("APERÇU", sortie)
        self.proprio.refresh_from_db()
        self.assertEqual(self.proprio.email, "gerant@smartphone.mg")

    def test_apply_renomme_et_conserve_tout_le_reste(self):
        self.lancer(apply=True)
        self.proprio.refresh_from_db()

        self.assertEqual(self.proprio.email, "admin@smartphone.mg")
        self.assertEqual(self.proprio.username, "admin@smartphone.mg")
        # Les quatre contrôles exigés par la mission § 32.
        self.assertEqual(self.proprio.role, "admin")
        self.assertTrue(self.proprio.is_staff)
        self.assertTrue(AdminProfile.objects.filter(user=self.proprio).exists())
        self.assertEqual(self.proprio.magasins.count(), 1)

    def test_le_mot_de_passe_est_inchange(self):
        """Le propriétaire se reconnecte avec SES identifiants habituels."""
        self.lancer(apply=True)
        self.proprio.refresh_from_db()
        self.assertTrue(self.proprio.check_password("motdepasse"))

    def test_rejouable_sans_effet(self):
        self.lancer(apply=True)
        sortie = self.lancer(apply=True)
        self.assertIn("Rien à faire", sortie)
        self.assertEqual(CustomUser.objects.filter(email="admin@smartphone.mg").count(), 1)

    def test_refuse_d_ecraser_une_adresse_existante(self):
        CustomUser.objects.create_user(
            email="admin@smartphone.mg", password="x", role="employer", full_name="Autre"
        )
        with self.assertRaises(CommandError) as ctx:
            self.lancer(apply=True)
        self.assertIn("déjà utilisé", str(ctx.exception))
        self.proprio.refresh_from_db()
        self.assertEqual(self.proprio.email, "gerant@smartphone.mg")

    def test_echoue_si_le_compte_n_existe_pas(self):
        CustomUser.objects.filter(email="gerant@smartphone.mg").delete()
        with self.assertRaises(CommandError):
            self.lancer(apply=True)
