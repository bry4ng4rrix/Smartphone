from django.contrib import admin

from .models import Order, OrderItem, OrderStatusHistory


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0


class OrderStatusHistoryInline(admin.TabularInline):
    model = OrderStatusHistory
    extra = 0


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ("numero", "magasin", "client_nom", "statut_courant", "total_a_payer", "date_commande")
    list_filter = ("magasin", "statut_courant", "livraison_zone")
    search_fields = ("numero", "client_nom", "telephone")
    inlines = [OrderItemInline, OrderStatusHistoryInline]
