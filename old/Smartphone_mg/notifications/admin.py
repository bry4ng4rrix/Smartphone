from django.contrib import admin

from .models import Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("notif_type", "message", "target_role", "target_user", "is_read", "created_at")
    list_filter = ("notif_type", "target_role", "is_read")
