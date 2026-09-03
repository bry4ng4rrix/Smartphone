from django.db.models.signals import post_save
from django.dispatch import receiver

from users.broadcast import broadcast_data_event

from .models import ProductVariant, StockMovement


@receiver(post_save, sender=ProductVariant)
def product_variant_saved(sender, instance: ProductVariant, created, **kwargs):
    broadcast_data_event("product_variant", "created" if created else "updated", instance)


@receiver(post_save, sender=StockMovement)
def stock_movement_saved(sender, instance: StockMovement, created, **kwargs):
    if not created:
        return
    broadcast_data_event("stock_movement", "created", instance)
