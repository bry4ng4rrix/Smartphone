from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import (
    CustomUser,
    AdminProfile,
    MagasinProfile,
    EmployerProfile,
    Device,
    SubscriptionOffer,
)


# =========================================
# CUSTOM USER ADMIN
# =========================================

@admin.register(CustomUser)
class CustomUserAdmin(UserAdmin):

    list_display = (
        "id",
        "full_name",
        "email",
        "role",
        "is_confirmed",
        "is_staff",
        "is_active",
        "date_joined",
    )

    list_filter = (
        "role",
        "is_confirmed",
        "is_staff",
        "is_active",
    )

    search_fields = (
        "full_name",
        "email",
        "phone",
    )

    ordering = ("-date_joined",)

    fieldsets = (

        ("Authentication", {
            "fields": (
                "username",
                "password",
            )
        }),

        ("Personal Info", {
            "fields": (
                "full_name",
                "email",
                "phone",
            )
        }),

        ("Role & Status", {
            "fields": (
                "role",
                "is_confirmed",
                "is_active",
                "is_staff",
                "is_superuser",
            )
        }),

        ("Permissions", {
            "fields": (
                "groups",
                "user_permissions",
            )
        }),

        ("Important Dates", {
            "fields": (
                "last_login",
                "date_joined",
            )
        }),
    )

    add_fieldsets = (

        (None, {
            "classes": ("wide",),
            "fields": (
                "username",
                "full_name",
                "email",
                "phone",
                "role",
                "password1",
                "password2",
            ),
        }),
    )


# =========================================
# ADMIN PROFILE
# =========================================

@admin.register(AdminProfile)
class AdminProfileAdmin(admin.ModelAdmin):

    list_display = (
        "id",
        "user",
        "company_name",
    )

    search_fields = (
        "company_name",
        "user__email",
        "user__full_name",
    )


# =========================================
# MAGASIN PROFILE
# =========================================

@admin.register(MagasinProfile)
class MagasinProfileAdmin(admin.ModelAdmin):

    list_display = (
        "id",
        "shop_name",
        "admin",
        "created_at",
    )

    list_filter = (
        "created_at",
    )

    search_fields = (
        "shop_name",
        "user__email",
        "admin__email",
    )

    ordering = ("-created_at",)


# =========================================
# EMPLOYER PROFILE
# =========================================

@admin.register(EmployerProfile)
class EmployerProfileAdmin(admin.ModelAdmin):

    list_display = (
        "id",
        "user",
        "position",
        "admin",
        "magasin",
        "created_at",
    )

    list_filter = (
        "created_at",
    )

    search_fields = (
        "user__full_name",
        "user__email",
        "position",
    )

    ordering = ("-created_at",)


# =========================================
# DEVICE
# =========================================

@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):

    list_display = (
        "id",
        "admin_profile",
        "user",
        "label",
        "ip_address",
        "last_seen",
    )

    search_fields = (
        "admin_profile__company_name",
        "user__email",
        "device_id",
    )

    list_filter = ("last_seen",)
    ordering = ("-last_seen",)


# =========================================
# SUBSCRIPTION OFFER
# =========================================

@admin.register(SubscriptionOffer)
class SubscriptionOfferAdmin(admin.ModelAdmin):

    list_display = (
        "id",
        "name",
        "price",
        "max_devices",
        "duration_months",
        "is_active",
    )

    search_fields = ("name",)
    ordering = ("price",)