from django.contrib import admin

from .models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant, StockMovement


@admin.register(ProductCategory)
class ProductCategoryAdmin(admin.ModelAdmin):
    list_display = ("nom", "magasin", "ordre")
    list_filter = ("magasin",)


@admin.register(ProductType)
class ProductTypeAdmin(admin.ModelAdmin):
    list_display = ("nom", "category")
    list_filter = ("category__magasin",)


@admin.register(Brand)
class BrandAdmin(admin.ModelAdmin):
    list_display = ("nom", "magasin")
    list_filter = ("magasin",)


@admin.register(ProductReference)
class ProductReferenceAdmin(admin.ModelAdmin):
    list_display = ("reference_name", "brand", "type", "prix_vente", "actif")
    list_filter = ("type__category__magasin", "brand", "type")
    search_fields = ("reference_name",)


@admin.register(ProductVariant)
class ProductVariantAdmin(admin.ModelAdmin):
    list_display = ("product_reference", "couleur", "stock_actuel", "seuil_alerte")
    search_fields = ("product_reference__reference_name", "sku_loyverse")


@admin.register(StockMovement)
class StockMovementAdmin(admin.ModelAdmin):
    list_display = ("product_variant", "type", "quantite", "origine", "timestamp")
    list_filter = ("type", "origine")
    readonly_fields = [f.name for f in StockMovement._meta.fields]
