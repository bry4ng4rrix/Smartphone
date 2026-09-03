from .broadcast import broadcast_notification
from .models import Notification


def notify(notif_type, message, order=None, target_role=None, target_user=None):
    notification = Notification.objects.create(
        notif_type=notif_type,
        message=message,
        order=order,
        target_role=target_role,
        target_user=target_user,
    )
    broadcast_notification(notification)
    return notification
