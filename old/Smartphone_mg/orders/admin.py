from django.contrib import admin

from .models import Order, OrderItem, OrderStatusHistory


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0
    readonly_fields = ("prix_unitaire",)


class OrderStatusHistoryInline(admin.TabularInline):
    model = OrderStatusHistory
    extra = 0
    readonly_fields = ("ancien_statut", "nouveau_statut", "changed_by", "note", "timestamp")
    can_delete = False


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ("numero", "client_nom", "livraison_zone", "statut_courant", "total_a_payer", "date_commande")
    list_filter = ("statut_courant", "livraison_zone")
    search_fields = ("numero", "client_nom", "telephone")
    readonly_fields = ("numero", "frais_livraison", "total_a_payer")
    inlines = [OrderItemInline, OrderStatusHistoryInline]
