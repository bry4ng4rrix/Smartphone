from django.contrib import admin

from .models import Supplier, SupplierFee, SupplierOrder, SupplierOrderLine, SupplierPayment, VariantCostHistory


class SupplierOrderLineInline(admin.TabularInline):
    model = SupplierOrderLine
    extra = 0
    readonly_fields = ("valeur_achat_mga", "frais_alloues_mga", "cout_unitaire_calcule", "total_ligne")


class SupplierPaymentInline(admin.TabularInline):
    model = SupplierPayment
    extra = 0
    readonly_fields = ("montant_mga",)


class SupplierFeeInline(admin.TabularInline):
    model = SupplierFee
    extra = 0
    readonly_fields = ("montant_mga",)


@admin.register(Supplier)
class SupplierAdmin(admin.ModelAdmin):
    list_display = ("nom", "pays", "contact", "telephone", "email", "devise", "actif")
    list_filter = ("pays", "actif")
    search_fields = ("nom", "contact", "email")


@admin.register(SupplierOrder)
class SupplierOrderAdmin(admin.ModelAdmin):
    list_display = ("numero", "magasin", "supplier", "statut", "devise", "valeur_achat_mga", "total_frais_mga", "cout_total", "cout_unitaire", "date")
    list_filter = ("magasin", "statut", "devise")
    search_fields = ("numero", "tracking", "supplier__nom")
    inlines = [SupplierOrderLineInline, SupplierPaymentInline, SupplierFeeInline]
    readonly_fields = ("numero", "total_qty", "valeur_achat_mga", "total_frais_mga", "cout_total", "cout_unitaire", "received_at", "finalise_at")


@admin.register(VariantCostHistory)
class VariantCostHistoryAdmin(admin.ModelAdmin):
    list_display = ("product_variant", "supplier_order", "date", "quantite", "cout_revient_unitaire_mga")
    list_filter = ("date",)
    search_fields = ("product_variant__product_reference__reference_name", "supplier_order__numero")
