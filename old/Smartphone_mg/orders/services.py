from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction

from notifications.services import notify
from stock.services import apply_stock_movement

from .models import Order, OrderStatusHistory

# Règle stricte du workflow (§5 README) : chaque transition a un statut de
# départ obligatoire et un rôle responsable. Le gérant peut forcer n'importe
# quelle transition valide (bypass du rôle) mais ne peut pas sauter d'étape
# (le "droit admin override" pour sauter une étape reste "à discuter").
TRANSITIONS = {
    "EN_PREPARATION": {"from": "NOUVELLE", "role": "PREPARATEUR"},
    "PRETE": {"from": "EN_PREPARATION", "role": "PREPARATEUR"},
    "EN_LIVRAISON": {"from": "PRETE", "role": "LIVREUR"},
    "LIVRE": {"from": "EN_LIVRAISON", "role": "LIVREUR"},
    "RETOUR": {"from": "EN_LIVRAISON", "role": "LIVREUR"},
}


@transaction.atomic
def create_order(*, client_nom, telephone, livraison_zone, items, note="", created_by):
    """items: liste de {"product_variant": ProductVariant, "quantite": int}.
    Prix et frais de livraison sont calculés côté serveur (§6 README —
    'Prix' et 'Frais livraison' en lecture seule)."""

    from .models import OrderItem

    order = Order.objects.create(
        client_nom=client_nom,
        telephone=telephone,
        livraison_zone=livraison_zone,
        note=note,
        created_by=created_by,
    )

    for item in items:
        OrderItem.objects.create(
            order=order,
            product_variant=item["product_variant"],
            quantite=item.get("quantite", 1),
        )

    order.recompute_total()

    OrderStatusHistory.objects.create(
        order=order, ancien_statut=None, nouveau_statut="NOUVELLE", changed_by=created_by
    )

    notify(
        notif_type="NOUVELLE_COMMANDE",
        message=f"Nouvelle commande {order.numero} — {order.client_nom} ({order.livraison_zone})",
        order=order,
        target_role="PREPARATEUR",
    )

    return order


@transaction.atomic
def change_order_status(*, order, new_status, user, note=""):
    if new_status not in TRANSITIONS:
        raise ValidationError(f"Statut cible invalide : {new_status}")

    rule = TRANSITIONS[new_status]

    if order.statut_courant != rule["from"]:
        raise ValidationError(
            f"Transition impossible : la commande est '{order.statut_courant}', "
            f"'{new_status}' nécessite '{rule['from']}'."
        )

    if user.role != rule["role"] and user.role != "GERANT":
        raise PermissionDenied(
            f"Seul le rôle {rule['role']} (ou le gérant) peut passer une commande à '{new_status}'."
        )

    old_status = order.statut_courant
    order.statut_courant = new_status
    order.save(update_fields=["statut_courant", "updated_at"])

    OrderStatusHistory.objects.create(
        order=order, ancien_statut=old_status, nouveau_statut=new_status, changed_by=user, note=note
    )

    # Règle critique (§5 README) : seul "Livré" déduit le stock. "Retour"
    # signifie que la livraison a échoué (client absent/refuse) — le colis
    # n'a jamais quitté l'inventaire, donc "Retour" ne touche PAS le stock
    # (aucune déduction n'a eu lieu à "En livraison", rien à réintégrer).
    if new_status == "LIVRE":
        for item in order.items.select_related("product_variant"):
            apply_stock_movement(
                product_variant=item.product_variant,
                movement_type="SORTIE",
                quantite=item.quantite,
                origine="LIVRE",
                user=user,
                reference=order.numero,
            )

    if new_status == "PRETE":
        notify(
            notif_type="COMMANDE_PRETE",
            message=f"Commande {order.numero} prête — {order.client_nom} ({order.livraison_zone})",
            order=order,
            target_role="LIVREUR",
        )

    return order
