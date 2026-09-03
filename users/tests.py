from rest_framework.test import APITestCase
from rest_framework import status
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from users.models import AdminProfile, MagasinProfile, EmployerProfile

User = get_user_model()

class AddAdminAPITestCase(APITestCase):

    def test_add_admin_without_company_name_creates_profile(self):
        admin_user = User.objects.create_user(
            email="owner@test.com",
            password="testpassword123",
            role="admin",
            is_confirmed=True,
            full_name="Owner",
        )
        self.client.force_authenticate(user=admin_user)

        response = self.client.post(
            "/api/users/add-admin/",
            {
                "email": "newadmin@test.com",
                "username": "newadmin@test.com",
                "password": "testpassword123",
                "role": "admin",
                "full_name": "New Admin",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        user = User.objects.get(email="newadmin@test.com")
        self.assertEqual(user.role, "admin")
        self.assertTrue(AdminProfile.objects.filter(user=user).exists())
        self.assertTrue(AdminProfile.objects.get(user=user).company_name)


class UsersByMagasinViewAPITestCase(APITestCase):

    def test_add_admin_then_fetch_users_shows_new_admin(self):
        admin_user = User.objects.create_user(
            email="owner@test.com",
            password="testpassword123",
            role="admin",
            is_confirmed=True,
            full_name="Owner",
        )
        store = MagasinProfile.objects.create(admin=admin_user, shop_name="Boutique A")
        store.admins.add(admin_user)

        self.client.force_authenticate(user=admin_user)

        response = self.client.post(
            "/api/users/add-admin/",
            {
                "email": "newadmin@test.com",
                "username": "newadmin@test.com",
                "password": "testpassword123",
                "role": "admin",
                "full_name": "New Admin",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        users_response = self.client.get("/api/users/magasins/users/")
        self.assertEqual(users_response.status_code, status.HTTP_200_OK)

        found = any(
            user["email"] == "newadmin@test.com"
            for store_data in users_response.data
            for user in store_data.get("company_users", [])
        )
        self.assertTrue(found, users_response.data)

    def test_admin_get_company_users_includes_all_society_users(self):
        admin_user = User.objects.create_user(
            email="owner@test.com",
            password="testpassword123",
            role="admin",
            is_confirmed=True,
            full_name="Owner",
        )
        employee_user = User.objects.create_user(
            email="employee@test.com",
            password="testpassword123",
            role="employer",
            is_confirmed=True,
            full_name="Employee",
        )

        store = MagasinProfile.objects.create(admin=admin_user, shop_name="Boutique A")
        store.admins.add(admin_user)
        EmployerProfile.objects.create(user=employee_user, admin=admin_user, magasin=store, position="Vendeur")

        self.client.force_authenticate(user=admin_user)

        response = self.client.get("/api/users/magasins/users/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(any(item["id"] == admin_user.id for item in response.data[0]["company_users"]))
        self.assertTrue(any(item["id"] == employee_user.id for item in response.data[0]["company_users"]))


class ProfileLogoAPITestCase(APITestCase):

    def setUp(self):
        # Create an admin user and their profile
        self.admin_user = User.objects.create_user(
            email="admin@test.com",
            password="testpassword123",
            role="admin",
            is_confirmed=True
        )
        self.admin_profile, _ = AdminProfile.objects.get_or_create(
            user=self.admin_user,
            company_name="Test Enterprise"
        )

        # Create a magasin user and their profile
        self.magasin_user = User.objects.create_user(
            email="magasin@test.com",
            password="testpassword123",
            role="magasin",
            is_confirmed=True
        )
        self.magasin_profile, _ = MagasinProfile.objects.get_or_create(
            user=self.magasin_user,
            admin=self.admin_user,
            shop_name="Test Shop"
        )

    def test_admin_get_profile(self):
        self.client.force_authenticate(user=self.admin_user)
        response = self.client.get("/api/users/me/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("logo", response.data)
        self.assertIn("company_name", response.data)
        self.assertEqual(response.data["company_name"], "Test Enterprise")

    def test_magasin_get_profile(self):
        self.client.force_authenticate(user=self.magasin_user)
        response = self.client.get("/api/users/me/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("shop_logo", response.data)
        self.assertIn("shop_name", response.data)
        self.assertEqual(response.data["shop_name"], "Test Shop")

    def test_admin_patch_profile_logo(self):
        self.client.force_authenticate(user=self.admin_user)
        
        # Mock file upload
        logo_image = SimpleUploadedFile(
            name='test_logo.png',
            content=b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82',
            content_type='image/png'
        )

        data = {
            "company_name": "Updated Enterprise Name",
            "logo": logo_image
        }

        response = self.client.patch("/api/users/me/", data, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        
        # Verify database
        self.admin_profile.refresh_from_db()
        self.assertEqual(self.admin_profile.company_name, "Updated Enterprise Name")
        self.assertTrue(self.admin_profile.logo.name.endswith("test_logo.png"))

    def test_magasin_patch_profile_logo(self):
        self.client.force_authenticate(user=self.magasin_user)

        # Mock file upload
        shop_logo_image = SimpleUploadedFile(
            name='shop_logo.png',
            content=b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82',
            content_type='image/png'
        )

        data = {
            "shop_name": "Updated Shop Name",
            "shop_logo": shop_logo_image
        }

        response = self.client.patch("/api/users/me/", data, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # Verify database
        self.magasin_profile.refresh_from_db()
        self.assertEqual(self.magasin_profile.shop_name, "Updated Shop Name")
        self.assertTrue(self.magasin_profile.shop_logo.name.endswith("shop_logo.png"))

    def test_admin_update_specific_magasin(self):
        self.client.force_authenticate(user=self.admin_user)

        shop_logo_image = SimpleUploadedFile(
            name='new_shop_logo.png',
            content=b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82',
            content_type='image/png'
        )

        data = {
            "shop_name": "Renamed Shop Via Admin",
            "shop_logo": shop_logo_image
        }

        response = self.client.patch(f"/api/users/magasins/{self.magasin_profile.id}/", data, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # Verify database
        self.magasin_profile.refresh_from_db()
        self.assertEqual(self.magasin_profile.shop_name, "Renamed Shop Via Admin")
        self.assertTrue(self.magasin_profile.shop_logo.name.endswith("new_shop_logo.png"))
