from django.contrib import admin

from .models import SupplierOrder, SupplierOrderLine


class SupplierOrderLineInline(admin.TabularInline):
    model = SupplierOrderLine
    extra = 0
    readonly_fields = ("cout_unitaire_calcule", "total_ligne")


@admin.register(SupplierOrder)
class SupplierOrderAdmin(admin.ModelAdmin):
    list_display = ("numero", "date", "statut", "cout_total", "cout_unitaire", "total_qty")
    list_filter = ("statut",)
    search_fields = ("numero", "description")
    readonly_fields = ("numero", "total_qty", "cout_total", "cout_unitaire")
    inlines = [SupplierOrderLineInline]
