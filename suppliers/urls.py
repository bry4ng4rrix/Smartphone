from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import SupplierOrderViewSet, SupplierViewSet, VariantCostHistoryView

router = DefaultRouter()
router.register(r"orders", SupplierOrderViewSet, basename="supplier-order")
# Fiches fournisseur (nouveau) — à côté des approvisionnements existants.
router.register(r"suppliers", SupplierViewSet, basename="supplier")

urlpatterns = [
    # Coût de revient actuel / historique d'une variante.
    path("cost-history/", VariantCostHistoryView.as_view()),
] + router.urls
