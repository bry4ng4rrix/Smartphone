from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import RuptureExportPDFView, RuptureListView, StockAdjustmentView, StockMovementViewSet

router = DefaultRouter()
router.register(r"movements", StockMovementViewSet, basename="stock-movement")

urlpatterns = [
    path("adjustments/", StockAdjustmentView.as_view()),
    path("ruptures/", RuptureListView.as_view()),
    path("ruptures/export-pdf/", RuptureExportPDFView.as_view()),
] + router.urls
