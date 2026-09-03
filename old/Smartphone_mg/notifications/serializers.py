from rest_framework import serializers

from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    order_numero = serializers.CharField(source="order.numero", read_only=True)

    class Meta:
        model = Notification
        fields = [
            "id", "notif_type", "message", "order", "order_numero",
            "target_role", "target_user", "is_read", "created_at",
        ]
        read_only_fields = fields
