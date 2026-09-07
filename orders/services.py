from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.utils import timezone

from catalog.services import apply_stock_movement
from users.models import EmployerProfile, Notification
from users.permissions import user_commande_role

from .models import Order, OrderItem, OrderStatusHistory

# Règle stricte du workflow (§5 Smartreadme.md) : chaque transition a un
# statut de départ obligatoire et un rôle responsable. Le gérant peut forcer
# n'importe quelle transition valide (bypass du rôle) mais ne peut pas sauter
# d'étape (le "droit admin override" pour sauter une étape reste "à discuter"),
# sauf le cas spécial "Récupération sur place" (voir change_order_status).
TRANSITIONS = {
    "EN_PREPARATION": {"from": "NOUVELLE", "role": "PREPARATEUR"},
    "PRETE": {"from": "EN_PREPARATION", "role": "PREPARATEUR"},
    "EN_LIVRAISON": {"from": "PRETE", "role": "LIVREUR"},
    "LIVRE": {"from": "EN_LIVRAISON", "role": "LIVREUR"},
    "RETOUR": {"from": "EN_LIVRAISON", "role": "LIVREUR"},
}


def is_preparateur_busy(user, exclude_order=None):
    """Un préparateur ne prépare qu'une commande à la fois."""
    qs = Order.objects.filter(preparateur=user, statut_courant="EN_PREPARATION")
    if exclude_order:
        qs = qs.exclude(pk=exclude_order.pk)
    return qs.exists()


def is_livreur_busy(user, exclude_order=None):
    """Un livreur ne livre qu'une commande à la fois."""
    qs = Order.objects.filter(livreur=user, statut_courant="EN_LIVRAISON")
    if exclude_order:
        qs = qs.exclude(pk=exclude_order.pk)
    return qs.exists()


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


def _resolve_assignee(*, order, role, requesting_user, requested_role, assignee_id, field_name):
    """Résout qui doit être assigné (préparateur/livreur) pour une
    transition. Le gérant désigne manuellement qui il veut (un préparateur/
    livreur déjà occupé sur une autre commande reste sélectionnable — c'est
    au gérant d'en juger, voir is_preparateur_busy/is_livreur_busy qui
    restent utilisées côté "available-staff" comme simple indication).

    - Gérant : doit désigner explicitement quelqu'un (`assignee_id` requis).
    - Le rôle concerné (Préparateur/Livreur) lui-même : auto-affectation si
      `assignee_id` absent, sinon doit correspondre à lui-même.
    """
    from users.models import CustomUser

    if role == "GERANT":
        if not assignee_id:
            raise ValidationError(f"Choisissez un {requested_role.lower()} pour cette commande.")
        try:
            user = CustomUser.objects.get(id=assignee_id, employer_profile__commande_role=requested_role)
        except CustomUser.DoesNotExist:
            raise ValidationError("Utilisateur introuvable pour ce rôle.")
        if user.employer_profile.magasin_id != order.magasin_id:
            raise ValidationError("Cette personne n'appartient pas à ce magasin.")
    else:
        user = requesting_user
        if assignee_id and int(assignee_id) != user.id:
            raise PermissionDenied("Vous ne pouvez vous assigner que vous-même cette commande.")

    setattr(order, field_name, user)
    return user


@transaction.atomic
def change_order_status(*, order, new_status, user, note="", preparateur_id=None, livreur_id=None, assigned_at=None):
    """`assigned_at` : heure manuelle optionnelle (le gérant peut consigner
    une heure passée pour l'affectation préparateur/livreur) — sans valeur,
    l'historique prend l'heure réelle (maintenant), comme avant."""
    role = user_commande_role(user)

    # Cas spécial : retrait sur place ("Récupération") — aucun livreur
    # n'intervient, le gérant clôture directement Prête -> Livré au comptoir.
    if new_status == "LIVRE" and order.statut_courant == "PRETE" and order.livraison_zone == "RECUPERATION":
        if role != "GERANT":
            raise PermissionDenied("Seul le gérant peut valider une récupération sur place.")
        old_status = order.statut_courant
        order.statut_courant = new_status
        order.save(update_fields=["statut_courant", "updated_at"])
        OrderStatusHistory.objects.create(
            order=order, ancien_statut=old_status, nouveau_statut=new_status, changed_by=user, note=note
        )
        return order

    if new_status not in TRANSITIONS:
        raise ValidationError(f"Statut cible invalide : {new_status}")

    rule = TRANSITIONS[new_status]

    if order.statut_courant != rule["from"]:
        raise ValidationError(
            f"Transition impossible : la commande est '{order.statut_courant}', "
            f"'{new_status}' nécessite '{rule['from']}'."
        )

    if role != rule["role"] and role != "GERANT":
        raise PermissionDenied(
            f"Seul le rôle {rule['role']} (ou le gérant) peut passer une commande à '{new_status}'."
        )

    # Le préparateur/livreur voit toutes ses commandes à venir (planning),
    # mais ne peut agir dessus qu'à partir du jour J (date_commande) — le
    # gérant, lui, peut toujours forcer une transition en avance.
    if role != "GERANT" and timezone.localtime(order.date_commande).date() > timezone.localdate():
        raise PermissionDenied(
            f"Cette commande est planifiée pour le "
            f"{timezone.localtime(order.date_commande).strftime('%d/%m/%Y')} — "
            "l'action ne sera possible qu'à partir de ce jour."
        )

    # Une fois assignée, seule la personne désignée (ou le gérant) peut faire
    # progresser la commande — évite qu'un autre préparateur/livreur
    # n'interfère sur le travail de quelqu'un d'autre.
    if role == "PREPARATEUR" and order.preparateur_id and order.preparateur_id != user.id:
        raise PermissionDenied("Cette commande est assignée à un autre préparateur.")
    if role == "LIVREUR" and order.livreur_id and order.livreur_id != user.id:
        raise PermissionDenied("Cette commande est assignée à un autre livreur.")

    old_status = order.statut_courant

    if new_status == "EN_PREPARATION":
        _resolve_assignee(
            order=order, role=role, requesting_user=user, requested_role="PREPARATEUR",
            assignee_id=preparateur_id, field_name="preparateur",
        )
    if new_status == "EN_LIVRAISON":
        _resolve_assignee(
            order=order, role=role, requesting_user=user, requested_role="LIVREUR",
            assignee_id=livreur_id, field_name="livreur",
        )

    order.statut_courant = new_status
    order.save()

    OrderStatusHistory.objects.create(
        order=order, ancien_statut=old_status, nouveau_statut=new_status, changed_by=user, note=note,
        **({"timestamp": assigned_at} if assigned_at else {}),
    )

    # Le stock quitte physiquement le magasin au moment où le préparateur
    # prend la commande en charge (il sort l'article du rayon pour la
    # préparer) — et y revient si la livraison échoue et que le colis est
    # rapporté (Retour). "Livré" ne touche plus le stock : il est déjà sorti.
    if new_status == "EN_PREPARATION":
        for item in order.items.select_related("product_variant"):
            apply_stock_movement(
                product_variant=item.product_variant,
                movement_type="SORTIE",
                quantite=item.quantite,
                origine="PREPARATION",
                user=user,
                reference=order.numero,
            )
    elif new_status == "RETOUR":
        for item in order.items.select_related("product_variant"):
            apply_stock_movement(
                product_variant=item.product_variant,
                movement_type="ENTREE",
                quantite=item.quantite,
                origine="RETOUR",
                user=user,
                reference=order.numero,
            )

    if new_status == "PRETE":
        if order.livraison_zone == "RECUPERATION":
            # Pas de livreur pour un retrait sur place : notification
            # magasin (visible du gérant/comptoir), pas d'un rôle particulier.
            Notification.objects.create(
                notif_type="order", magasin=order.magasin,
                message=f"Commande {order.numero} prête à récupérer sur place — {order.client_nom}",
            )
        else:
            _notify_commande_role(
                magasin=order.magasin,
                commande_role="LIVREUR",
                notif_type="order",
                message=f"Commande {order.numero} prête — {order.client_nom} ({order.livraison_zone})",
                order=order,
            )

    return order


# Une commande déjà "Livré"/"Retour"/"Annulée" est terminale — rien à annuler.
_TERMINAL_STATUSES = {"LIVRE", "RETOUR", "ANNULEE"}
# Le stock n'a été déduit qu'à partir de "En préparation" (voir plus haut) —
# une commande encore "Nouvelle" n'a jamais touché le stock.
_STOCK_DEDUCTED_STATUSES = {"EN_PREPARATION", "PRETE", "EN_LIVRAISON"}


@transaction.atomic
def cancel_order(*, order, user, note=""):
    """Annulation d'une commande par le gérant — possible à n'importe quelle
    étape non terminale. Si le stock avait déjà été déduit (préparation en
    cours ou plus loin), il est intégralement restitué."""
    role = user_commande_role(user)
    if role != "GERANT":
        raise PermissionDenied("Seul le gérant peut annuler une commande.")

    if order.statut_courant in _TERMINAL_STATUSES:
        raise ValidationError(
            f"Cette commande est déjà '{order.get_statut_courant_display()}' — impossible de l'annuler."
        )

    old_status = order.statut_courant

    if old_status in _STOCK_DEDUCTED_STATUSES:
        for item in order.items.select_related("product_variant"):
            apply_stock_movement(
                product_variant=item.product_variant,
                movement_type="ENTREE",
                quantite=item.quantite,
                origine="ANNULATION",
                user=user,
                reference=order.numero,
            )

    order.statut_courant = "ANNULEE"
    order.save(update_fields=["statut_courant", "updated_at"])

    OrderStatusHistory.objects.create(
        order=order, ancien_statut=old_status, nouveau_statut="ANNULEE", changed_by=user, note=note,
    )

    return order
