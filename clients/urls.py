"""Routes de l'espace client — montées sous /api/ (Stock/urls.py), à côté
des routes internes /api/users/, /api/catalog/, /api/orders/, /api/suppliers/
qui restent inchangées."""
from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import (
    ClientChangePasswordView,
    ClientLoginView,
    ClientMeView,
    ClientOrderViewSet,
    ClientRefreshView,
    ClientRegisterView,
    PublicBoutiqueListView,
    PublicBoutiqueZonesView,
    PublicCategorieListView,
    PublicCouleurListView,
    PublicMarqueListView,
    PublicProduitViewSet,
    PublicSousTypeListView,
)

router = DefaultRouter()
router.register(r"produit", PublicProduitViewSet, basename="public-produit")
router.register(r"client/orders", ClientOrderViewSet, basename="client-order")

urlpatterns = [
    # Catalogue public (sans authentification)
    path("boutiques/", PublicBoutiqueListView.as_view()),
    path("boutiques/<int:pk>/zones/", PublicBoutiqueZonesView.as_view()),
    path("categories/", PublicCategorieListView.as_view()),
    path("type/", PublicCategorieListView.as_view()),  # alias de categories/
    path("sous-type/", PublicSousTypeListView.as_view()),
    path("marque/", PublicMarqueListView.as_view()),
    path("couleurs/", PublicCouleurListView.as_view()),
    # Compte client
    path("client/register/", ClientRegisterView.as_view()),
    path("client/login/", ClientLoginView.as_view()),
    path("client/refresh/", ClientRefreshView.as_view()),
    path("client/me/", ClientMeView.as_view()),
    path("client/change-password/", ClientChangePasswordView.as_view()),
] + router.urls
