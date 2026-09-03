from rest_framework.routers import DefaultRouter

from .views import SupplierOrderViewSet

router = DefaultRouter()
router.register(r"orders", SupplierOrderViewSet, basename="supplier-order")

urlpatterns = router.urls
