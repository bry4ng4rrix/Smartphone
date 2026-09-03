from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def broadcast_notification(notification):
    """Pousse une notification sur le(s) groupe(s) WebSocket concernés
    (pattern repris de Stock_v2/users/broadcast.py, adapté aux groupes par
    rôle plutôt que par magasin)."""

    try:
        channel_layer = get_channel_layer()
        if not channel_layer:
            return

        payload = {
            "id": notification.id,
            "notif_type": notification.notif_type,
            "message": notification.message,
            "order_id": notification.order_id,
            "order_numero": notification.order.numero if notification.order_id else None,
            "created_at": notification.created_at.isoformat(),
        }
        event = {"type": "send_notification", "notification": payload}

        if notification.target_role:
            async_to_sync(channel_layer.group_send)(
                f"notifications_role_{notification.target_role}", event
            )
        if notification.target_user_id:
            async_to_sync(channel_layer.group_send)(
                f"notifications_user_{notification.target_user_id}", event
            )
    except Exception as e:
        print(f"Error broadcasting notification {notification.id}:", e)
