from django.urls import path
from rest_framework.routers import DefaultRouter

from .dashboard import DashboardView
from .reporting import (
    DeliveriesReportView,
    ExpensesReportView,
    FinancialReportView,
    MarketingReportView,
    OrdersReportView,
    OverviewReportView,
    SalesReportView,
    StockReportView,
)
from .reports import ReportsView
from .views import (
    DeliveryZoneOptionViewSet,
    ExpenseTypeViewSet,
    LivreurExpenseViewSet,
    MarketingCampaignViewSet,
    OrderViewSet,
)

router = DefaultRouter()
router.register(r"delivery-zones", DeliveryZoneOptionViewSet, basename="delivery-zone")
# Types de dépense (Paramètres) et dépenses déclarées par les livreurs.
router.register(r"expense-types", ExpenseTypeViewSet, basename="expense-type")
router.register(r"expenses", LivreurExpenseViewSet, basename="livreur-expense")
router.register(r"campaigns", MarketingCampaignViewSet, basename="marketing-campaign")
# En dernier : la route vide capture tout le reste.
router.register(r"", OrderViewSet, basename="order")

urlpatterns = [
    path("dashboard/", DashboardView.as_view()),
    # Rapports du gérant — tous les bilans de la période, agrégés côté serveur.
    path("reports/", ReportsView.as_view()),
    # Centre de rapports — une section par vue (voir orders/reporting.py).
    path("reports/overview/", OverviewReportView.as_view()),
    path("reports/sales/", SalesReportView.as_view()),
    path("reports/financial/", FinancialReportView.as_view()),
    path("reports/expenses/", ExpensesReportView.as_view()),
    path("reports/stock/", StockReportView.as_view()),
    path("reports/orders/", OrdersReportView.as_view()),
    path("reports/deliveries/", DeliveriesReportView.as_view()),
    path("reports/marketing/", MarketingReportView.as_view()),
] + router.urls
