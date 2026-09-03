from django.urls import path
from rest_framework.routers import DefaultRouter

from .dashboard import DashboardView
from .views import OrderViewSet

router = DefaultRouter()
router.register(r"", OrderViewSet, basename="order")

urlpatterns = [
    path("dashboard/", DashboardView.as_view()),
] + router.urls
