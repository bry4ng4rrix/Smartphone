from django.contrib import admin

from .models import Brand, ProductCategory, ProductReference, ProductType, ProductVariant


class ProductVariantInline(admin.TabularInline):
    model = ProductVariant
    extra = 1


@admin.register(ProductCategory)
class ProductCategoryAdmin(admin.ModelAdmin):
    list_display = ("nom", "ordre")


@admin.register(ProductType)
class ProductTypeAdmin(admin.ModelAdmin):
    list_display = ("nom", "category")
    list_filter = ("category",)


@admin.register(Brand)
class BrandAdmin(admin.ModelAdmin):
    list_display = ("nom",)
    search_fields = ("nom",)


@admin.register(ProductReference)
class ProductReferenceAdmin(admin.ModelAdmin):
    list_display = ("reference_name", "brand", "type", "prix_vente", "actif")
    list_filter = ("type__category", "type", "brand", "actif")
    search_fields = ("reference_name", "brand__nom")
    inlines = [ProductVariantInline]


@admin.register(ProductVariant)
class ProductVariantAdmin(admin.ModelAdmin):
    list_display = ("product_reference", "couleur", "stock_actuel", "seuil_alerte")
    list_filter = ("product_reference__type",)
    search_fields = ("product_reference__reference_name", "couleur")
