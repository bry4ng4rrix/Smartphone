from django.db import models


class Notification(models.Model):
    """Événements §9 README : nouvelle commande -> Préparateur,
    commande prête -> Livreur. Diffusée en temps réel via WebSocket
    (notifications/consumers.py) et consultable via l'API REST."""

    NOTIF_TYPES = (
        ("NOUVELLE_COMMANDE", "Nouvelle commande"),
        ("COMMANDE_PRETE", "Commande prête"),
    )
    ROLE_CHOICES = (
        ("PREPARATEUR", "Préparateur"),
        ("LIVREUR", "Livreur"),
    )

    notif_type = models.CharField(max_length=30, choices=NOTIF_TYPES)
    message = models.CharField(max_length=255)
    order = models.ForeignKey(
        "orders.Order", on_delete=models.CASCADE, null=True, blank=True, related_name="notifications"
    )
    # Diffusée à tout le rôle (personne assignée non requise pour le MVP —
    # un seul préparateur/livreur suffit à démarrer).
    target_role = models.CharField(max_length=20, choices=ROLE_CHOICES, blank=True, null=True)
    target_user = models.ForeignKey(
        "users.CustomUser", on_delete=models.CASCADE, null=True, blank=True, related_name="notifications"
    )

    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"[{self.get_notif_type_display()}] {self.message}"
