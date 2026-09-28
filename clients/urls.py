"""Routes de la boutique en ligne — montées sous /api/ (Stock/urls.py), à côté
des routes internes /api/users/, /api/catalog/, /api/orders/, /api/suppliers/
qui restent inchangées.

Tout est public : la boutique ne demande ni compte ni connexion.
"""
from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import (
    CommandeEnLigneView,
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

urlpatterns = [
    # Catalogue
    path("boutiques/", PublicBoutiqueListView.as_view()),
    path("boutiques/<int:pk>/zones/", PublicBoutiqueZonesView.as_view()),
    path("categories/", PublicCategorieListView.as_view()),
    path("type/", PublicCategorieListView.as_view()),  # alias de categories/
    path("sous-type/", PublicSousTypeListView.as_view()),
    path("marque/", PublicMarqueListView.as_view()),
    path("couleurs/", PublicCouleurListView.as_view()),
    # Commande, sans compte : le gérant rappelle pour confirmer.
    path("commandes/", CommandeEnLigneView.as_view()),
] + router.urls
