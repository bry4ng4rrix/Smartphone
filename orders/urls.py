from django.urls import path
from rest_framework.routers import DefaultRouter

from .dashboard import DashboardView
from .reports import ReportsView
from .views import (
    DeliveryZoneOptionViewSet,
    ExpenseTypeViewSet,
    LivreurExpenseViewSet,
    OrderViewSet,
)

router = DefaultRouter()
router.register(r"delivery-zones", DeliveryZoneOptionViewSet, basename="delivery-zone")
# Types de dépense (Paramètres) et dépenses déclarées par les livreurs.
router.register(r"expense-types", ExpenseTypeViewSet, basename="expense-type")
router.register(r"expenses", LivreurExpenseViewSet, basename="livreur-expense")
# En dernier : la route vide capture tout le reste.
router.register(r"", OrderViewSet, basename="order")

urlpatterns = [
    path("dashboard/", DashboardView.as_view()),
    # Rapports du gérant — tous les bilans de la période, agrégés côté serveur.
    path("reports/", ReportsView.as_view()),
] + router.urls
