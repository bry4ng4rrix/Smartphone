from django.contrib import admin

from .models import Supplier, SupplierOrder, SupplierPayment


class SupplierPaymentInline(admin.TabularInline):
    model = SupplierPayment
    extra = 0
    readonly_fields = ("montant_mga",)


@admin.register(Supplier)
class SupplierAdmin(admin.ModelAdmin):
    list_display = ("nom", "pays", "contact", "telephone", "email", "devise", "actif")
    list_filter = ("pays", "actif")
    search_fields = ("nom", "contact", "email")


@admin.register(SupplierOrder)
class SupplierOrderAdmin(admin.ModelAdmin):
    list_display = ("numero", "magasin", "supplier", "product_variant", "quantite", "statut", "total_paiements_mga", "frais_douane_mga", "cout_total_mga", "cout_unitaire_mga", "date")
    list_filter = ("magasin", "statut", "devise")
    search_fields = ("numero", "tracking", "numero_colis", "supplier__nom", "product_variant__product_reference__reference_name")
    inlines = [SupplierPaymentInline]
    readonly_fields = ("numero", "total_paiements_mga", "cout_total_mga", "cout_unitaire_mga", "received_at", "finalise_at")
