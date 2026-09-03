from django.contrib import admin

from .models import SupplierOrder, SupplierOrderLine


class SupplierOrderLineInline(admin.TabularInline):
    model = SupplierOrderLine
    extra = 0
    readonly_fields = ("cout_unitaire_calcule", "total_ligne")


@admin.register(SupplierOrder)
class SupplierOrderAdmin(admin.ModelAdmin):
    list_display = ("numero", "magasin", "statut", "cout_total", "cout_unitaire", "date")
    list_filter = ("magasin", "statut")
    inlines = [SupplierOrderLineInline]
