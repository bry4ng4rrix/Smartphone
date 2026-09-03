from django.db.models.signals import post_save
from django.dispatch import receiver

from users.broadcast import broadcast_data_event

from .models import SupplierOrder


@receiver(post_save, sender=SupplierOrder)
def supplier_order_saved(sender, instance: SupplierOrder, created, **kwargs):
    broadcast_data_event("supplier_order", "created" if created else "updated", instance)
