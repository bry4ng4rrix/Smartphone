from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction

from catalog.services import apply_stock_movement
from users.models import EmployerProfile, Notification
from users.permissions import user_commande_role

from .models import Order, OrderItem, OrderStatusHistory

# Règle stricte du workflow (§5 Smartreadme.md) : chaque transition a un
# statut de départ obligatoire et un rôle responsable. Le gérant peut forcer
# n'importe quelle transition valide (bypass du rôle) mais ne peut pas sauter
# d'étape (le "droit admin override" pour sauter une étape reste "à discuter").
TRANSITIONS = {
    "EN_PREPARATION": {"from": "NOUVELLE", "role": "PREPARATEUR"},
    "PRETE": {"from": "EN_PREPARATION", "role": "PREPARATEUR"},
    "EN_LIVRAISON": {"from": "PRETE", "role": "LIVREUR"},
    "LIVRE": {"from": "EN_LIVRAISON", "role": "LIVREUR"},
    "RETOUR": {"from": "EN_LIVRAISON", "role": "LIVREUR"},
}


def _notify_commande_role(*, magasin, commande_role, notif_type, message, order):
    """Notifie tous les employers du magasin ayant ce commande_role
    (Préparateur ou Livreur) — §9 Smartreadme.md. Un mouvement par
    Notification.objects.create() déclenche déjà le broadcast WebSocket
    existant (voir users/signals.py::notification_created_broadcast)."""
    employer_user_ids = EmployerProfile.objects.filter(
        magasin=magasin, commande_role=commande_role
    ).values_list("user_id", flat=True)
    for user_id in employer_user_ids:
        Notification.objects.create(
            notif_type=notif_type, message=message, magasin=magasin, user_id=user_id
        )
    if not employer_user_ids:
        # Personne assignée à ce rôle pour l'instant (MVP) : notification
        # visible tout de même côté magasin (le gérant la voit).
        Notification.objects.create(notif_type=notif_type, message=message, magasin=magasin)


@transaction.atomic
def create_order(*, magasin, client_nom, telephone, livraison_zone, items, note="", created_by,
                  date_commande=None, adresse_livraison=""):
    """items: liste de {"product_variant": ProductVariant, "quantite": int}.
    Prix et frais de livraison sont calculés côté serveur (§6 Smartreadme.md
    — 'Prix' et 'Frais livraison' en lecture seule). `date_commande` est
    optionnelle (auto = maintenant côté modèle, avec l'heure précise) mais
    modifiable par le gérant (§6 : 'Auto = aujourd'hui, modifiable')."""

    order = Order.objects.create(
        magasin=magasin,
        client_nom=client_nom,
        telephone=telephone,
        livraison_zone=livraison_zone,
        adresse_livraison=adresse_livraison,
        note=note,
        created_by=created_by,
        **({"date_commande": date_commande} if date_commande else {}),
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

    _notify_commande_role(
        magasin=magasin,
        commande_role="PREPARATEUR",
        notif_type="order",
        message=f"Nouvelle commande {order.numero} — {order.client_nom} ({order.livraison_zone})",
        order=order,
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

    role = user_commande_role(user)
    if role != rule["role"] and role != "GERANT":
        raise PermissionDenied(
            f"Seul le rôle {rule['role']} (ou le gérant) peut passer une commande à '{new_status}'."
        )

    old_status = order.statut_courant
    order.statut_courant = new_status
    order.save(update_fields=["statut_courant", "updated_at"])

    OrderStatusHistory.objects.create(
        order=order, ancien_statut=old_status, nouveau_statut=new_status, changed_by=user, note=note
    )

    # Règle critique (§5 Smartreadme.md) : seul "Livré" déduit le stock.
    # "Retour" signifie que la livraison a échoué (client absent/refuse) — le
    # colis n'a jamais quitté l'inventaire, donc "Retour" ne touche PAS le
    # stock (aucune déduction n'a eu lieu à "En livraison", rien à réintégrer).
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
        _notify_commande_role(
            magasin=order.magasin,
            commande_role="LIVREUR",
            notif_type="order",
            message=f"Commande {order.numero} prête — {order.client_nom} ({order.livraison_zone})",
            order=order,
        )

    return order
