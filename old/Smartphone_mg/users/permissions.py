from rest_framework.permissions import BasePermission


class IsGerant(BasePermission):

    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == "GERANT"


class IsPreparateur(BasePermission):

    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == "PREPARATEUR"


class IsLivreur(BasePermission):

    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == "LIVREUR"


class IsGerantOrReadOnly(BasePermission):
    """Lecture pour tout utilisateur authentifié, écriture réservée au gérant."""

    SAFE_METHODS = ("GET", "HEAD", "OPTIONS")

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        if request.method in self.SAFE_METHODS:
            return True
        return request.user.role == "GERANT"
