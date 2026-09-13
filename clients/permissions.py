from rest_framework.permissions import BasePermission

from .models import Client


class IsClient(BasePermission):
    """L'appelant est un compte client actif (authentifié par
    ClientJWTAuthentication). Un utilisateur interne, même authentifié, n'est
    jamais un Client : il est refusé ici."""

    message = "Réservé aux comptes clients."

    def has_permission(self, request, view):
        return isinstance(request.user, Client) and request.user.is_active
