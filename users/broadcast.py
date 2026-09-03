from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def _get_magasin_and_admin(instance):
    magasin_id = None
    admin_id = None

    magasin = getattr(instance, "magasin", None)
    if magasin is not None:
        magasin_id = magasin.id
        admin_id = magasin.admin_id
    elif getattr(instance, "magasin_id", None):
        magasin_id = instance.magasin_id
        try:
            from users.models import MagasinProfile
            magasin = MagasinProfile.objects.select_related("admin").get(id=magasin_id)
            admin_id = magasin.admin_id
        except Exception:
            pass

    if magasin_id is None and hasattr(instance, "product"):
        product = instance.product
        if product and product.magasin_id:
            magasin_id = product.magasin_id
            try:
                from users.models import MagasinProfile
                magasin = MagasinProfile.objects.select_related("admin").get(id=magasin_id)
                admin_id = magasin.admin_id
            except Exception:
                pass

    # Fallback pour les modèles rattachés à une Order sans magasin direct
    # (ex: OrderStatusHistory) — même principe que le fallback `product` ci-dessus.
    if magasin_id is None and hasattr(instance, "order"):
        order = instance.order
        if order and order.magasin_id:
            magasin_id = order.magasin_id
            try:
                from users.models import MagasinProfile
                magasin = MagasinProfile.objects.select_related("admin").get(id=magasin_id)
                admin_id = magasin.admin_id
            except Exception:
                pass

    # Fallback pour les modèles catalogue/fournisseur rattachés indirectement
    # à un magasin via une chaîne de FK (ex: StockMovement -> ProductVariant
    # -> ProductReference -> ProductType -> ProductCategory -> magasin).
    if magasin_id is None:
        for path in (
            ("product_variant", "product_reference", "type", "category", "magasin"),
            ("product_reference", "type", "category", "magasin"),
            ("type", "category", "magasin"),
            ("category", "magasin"),
        ):
            obj = instance
            for attr in path:
                obj = getattr(obj, attr, None)
                if obj is None:
                    break
            if obj is not None:
                magasin_id = obj.id
                admin_id = obj.admin_id
                break

    return magasin_id, admin_id


def broadcast_data_event(model, action, instance):
    """Broadcast a data sync event to WebSocket groups."""
    try:
        channel_layer = get_channel_layer()
        if not channel_layer:
            return

        magasin_id, admin_id = _get_magasin_and_admin(instance)

        payload = {
            "model": model,
            "action": action,
            "id": getattr(instance, "id", None),
            "magasin_id": magasin_id,
        }

        event = {"type": "data_update", "payload": payload}

        if admin_id:
            async_to_sync(channel_layer.group_send)(f"data_admin_{admin_id}", event)
        if magasin_id:
            async_to_sync(channel_layer.group_send)(f"data_magasin_{magasin_id}", event)
    except Exception as e:
        print(f"Error broadcasting data event ({model}/{action}):", e)
