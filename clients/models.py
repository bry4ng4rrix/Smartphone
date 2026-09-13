from django.contrib.auth.hashers import check_password, make_password
from django.db import models
from django.utils import timezone


class Client(models.Model):
    """Compte client de l'espace en ligne (extension du backend, § demande).

    Volontairement DISTINCT de `users.CustomUser` : un client n'a aucun rôle
    interne (gérant / préparateur / livreur), ne passe jamais par les
    permissions et le scoping magasin de l'application de gestion, et ses
    jetons JWT portent une revendication `client_id` que l'authentification
    interne ignore (voir clients/authentication.py). L'existant n'est donc
    pas touché : aucune nouvelle valeur de `CustomUser.role`.
    """

    email = models.EmailField(unique=True)
    password = models.CharField(max_length=128)
    nom = models.CharField(max_length=255)
    # Même format que les commandes internes : +261XXXXXXXXX.
    telephone = models.CharField(max_length=20)
    adresse = models.CharField(max_length=255, blank=True)
    is_active = models.BooleanField(default=True)
    last_login = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Client (espace en ligne)"
        verbose_name_plural = "Clients (espace en ligne)"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.nom} <{self.email}>"

    # --- mot de passe (hachage Django, jamais en clair) ------------------- #

    def set_password(self, raw_password):
        self.password = make_password(raw_password)

    def check_password(self, raw_password):
        return check_password(raw_password, self.password)

    def marquer_connexion(self):
        self.last_login = timezone.now()
        self.save(update_fields=["last_login"])

    # --- compatibilité DRF (request.user) --------------------------------- #

    @property
    def is_authenticated(self):
        return True

    @property
    def is_anonymous(self):
        return False

    def save(self, *args, **kwargs):
        self.email = (self.email or "").strip().lower()
        super().save(*args, **kwargs)
