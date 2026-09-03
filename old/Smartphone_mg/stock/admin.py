from django.contrib import admin

from .models import StockMovement


@admin.register(StockMovement)
class StockMovementAdmin(admin.ModelAdmin):
    list_display = ("product_variant", "type", "quantite", "origine", "user", "timestamp")
    list_filter = ("type", "origine")
    search_fields = ("product_variant__product_reference__reference_name", "reference")
    readonly_fields = [f.name for f in StockMovement._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
