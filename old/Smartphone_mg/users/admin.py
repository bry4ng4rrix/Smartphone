from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import CustomUser


@admin.register(CustomUser)
class CustomUserAdmin(UserAdmin):
    model = CustomUser
    list_display = ("email", "full_name", "role", "is_active", "is_staff")
    list_filter = ("role", "is_active")
    search_fields = ("email", "full_name", "phone")
    ordering = ("full_name",)

    fieldsets = (
        (None, {"fields": ("email", "password")}),
        ("Informations", {"fields": ("full_name", "phone", "role")}),
        ("Droits", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Dates", {"fields": ("last_login", "created_at", "updated_at")}),
    )
    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("email", "full_name", "phone", "role", "password1", "password2"),
        }),
    )
    readonly_fields = ("created_at", "updated_at", "last_login")
