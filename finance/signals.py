from django.db.models.signals import post_save
from django.dispatch import receiver

from users.broadcast import broadcast_data_event

from .models import Encaissement, EpargneMouvement, VenteResultat


# Le frontend Caisse s'abonne au modèle "tresorerie" (voir
# frontend/lib/contexts/DataSyncContext.tsx) pour se rafraîchir.
@receiver(post_save, sender=VenteResultat)
@receiver(post_save, sender=Encaissement)
@receiver(post_save, sender=EpargneMouvement)
def tresorerie_saved(sender, instance, created, **kwargs):
    broadcast_data_event("tresorerie", "created" if created else "updated", instance)
