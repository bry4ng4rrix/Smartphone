from django.contrib import admin

from .models import Client


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ("id", "nom", "email", "telephone", "is_active", "created_at", "last_login")
    search_fields = ("nom", "email", "telephone")
    list_filter = ("is_active",)
    readonly_fields = ("password", "created_at", "updated_at", "last_login")
