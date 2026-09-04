from rest_framework.routers import DefaultRouter

from .views import (
    BrandViewSet,
    ColorViewSet,
    ProductCategoryViewSet,
    ProductReferenceViewSet,
    ProductTypeViewSet,
    ProductVariantViewSet,
    StockMovementViewSet,
)

router = DefaultRouter()
router.register(r"categories", ProductCategoryViewSet, basename="product-category")
router.register(r"types", ProductTypeViewSet, basename="product-type")
router.register(r"brands", BrandViewSet, basename="brand")
router.register(r"colors", ColorViewSet, basename="color")
router.register(r"references", ProductReferenceViewSet, basename="product-reference")
router.register(r"variants", ProductVariantViewSet, basename="product-variant")
router.register(r"movements", StockMovementViewSet, basename="stock-movement")

urlpatterns = router.urls
