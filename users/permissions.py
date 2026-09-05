from rest_framework.permissions import BasePermission


class IsAdmin(BasePermission):

    def has_permission(self, request, view):

        return (
            request.user.is_authenticated
            and request.user.role == "admin"
        )


class IsCompanyOwner(BasePermission):
    """Like IsAdmin, but excludes co-admins added via AddAdminView: only the
    admin who actually owns the company (has an AdminProfile) passes. Used to
    gate company-level actions (adding/removing admins, subscription,
    devices) that co-admins share full data access but no ownership over."""

    def has_permission(self, request, view):
        from .models import AdminProfile

        return (
            request.user.is_authenticated
            and request.user.role == "admin"
            and AdminProfile.objects.filter(user=request.user).exists()
        )


class IsMagasin(BasePermission):

    def has_permission(self, request, view):

        return (
            request.user.is_authenticated
            and request.user.role == "magasin"
        )


class IsEmployer(BasePermission):

    def has_permission(self, request, view):

        return (
            request.user.is_authenticated
            and request.user.role == "employer"
        )


# =====================================================
# MODULE COMMANDE (Smartreadme.md) — Gérant/Préparateur/Livreur
#
# Pas de nouvelles valeurs sur CustomUser.role : magasin=Gérant, admin=Gérant
# sur tous ses magasins, et Préparateur/Livreur sont des sous-rôles portés
# par EmployerProfile.commande_role (voir users/models.py).
# =====================================================

def user_commande_role(user):
    """Rôle de `user` au sens du module Commande : "GERANT", "PREPARATEUR",
    "LIVREUR", ou None (utilisateur sans rôle dans ce module, ex: un employer
    sans commande_role assigné)."""
    if not user or not user.is_authenticated:
        return None
    if user.role in ("admin", "magasin"):
        return "GERANT"
    if user.role == "employer":
        try:
            return user.employer_profile.commande_role or None
        except Exception:
            return None
    return None


def is_gerant(user):
    return user_commande_role(user) == "GERANT"


def is_preparateur(user):
    return user_commande_role(user) == "PREPARATEUR"


def is_livreur(user):
    return user_commande_role(user) == "LIVREUR"


class IsGerant(BasePermission):

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated) and is_gerant(request.user)


class IsGerantOrReadOnly(BasePermission):
    """Lecture ouverte à tout utilisateur authentifié (magasin-scopée au
    niveau du queryset), écriture réservée au Gérant — catalogue produit
    (§4 Smartreadme.md : Préparateur/Livreur ne modifient jamais le
    catalogue, seulement les statuts de commande)."""

    SAFE_METHODS = ("GET", "HEAD", "OPTIONS")

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        if request.method in self.SAFE_METHODS:
            return True
        return is_gerant(request.user)


def get_accessible_magasins(user):
    """MagasinProfile queryset visible à `user` selon son rôle — admin: tous
    les magasins de sa société (y compris comme co-admin), magasin: le sien,
    employer: celui de son affectation. Même règle de scoping que le reste de
    l'app (voir users/views.py::get_company_magasins / _accessible_magasins),
    factorisée ici pour être réutilisée par les apps catalog/orders/suppliers."""
    from django.db.models import Q

    from .models import MagasinProfile

    if not user or not user.is_authenticated:
        return MagasinProfile.objects.none()
    if user.role == "admin":
        return MagasinProfile.objects.filter(Q(admin=user) | Q(admins=user)).distinct()
    if user.role == "magasin":
        return MagasinProfile.objects.filter(user=user)
    if user.role == "employer":
        return MagasinProfile.objects.filter(employers__user=user)
    return MagasinProfile.objects.none()


def resolve_magasin_for_request(request):
    """Magasin cible pour une création (catalog/orders/suppliers) :
    `magasin_id` explicite dans le payload (doit être accessible à
    l'utilisateur), ou à défaut l'unique magasin accessible (cas courant :
    un compte magasin/employer n'en a qu'un). Lève DRF ValidationError /
    PermissionDenied sinon — appelant doit avoir importé ces exceptions."""
    from rest_framework.exceptions import PermissionDenied as DRFPermissionDenied
    from rest_framework.exceptions import ValidationError as DRFValidationError

    from .models import MagasinProfile

    accessible = get_accessible_magasins(request.user)
    magasin_id = request.data.get("magasin_id") or request.data.get("magasin")
    if magasin_id:
        try:
            return accessible.get(id=magasin_id)
        except MagasinProfile.DoesNotExist:
            raise DRFPermissionDenied("Magasin non autorisé.")
    if accessible.count() == 1:
        return accessible.first()
    raise DRFValidationError({"magasin_id": "Ce champ est requis (plusieurs magasins accessibles)."})