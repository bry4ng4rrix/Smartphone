from django.db.models.signals import post_save
from django.dispatch import receiver

from users.broadcast import broadcast_data_event

from .models import Order, OrderStatusHistory


@receiver(post_save, sender=Order)
def order_saved(sender, instance: Order, created, **kwargs):
    broadcast_data_event("order", "created" if created else "updated", instance)


@receiver(post_save, sender=OrderStatusHistory)
def order_status_history_saved(sender, instance: OrderStatusHistory, created, **kwargs):
    if not created:
        return
    broadcast_data_event("order_status_history", "created", instance)
