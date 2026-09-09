from django.urls import path
from rest_framework.routers import DefaultRouter

from .dashboard import DashboardView
from .views import DeliveryZoneOptionViewSet, OrderViewSet

router = DefaultRouter()
router.register(r"delivery-zones", DeliveryZoneOptionViewSet, basename="delivery-zone")
router.register(r"", OrderViewSet, basename="order")

urlpatterns = [
    path("dashboard/", DashboardView.as_view()),
] + router.urls
