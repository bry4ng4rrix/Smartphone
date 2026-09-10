from datetime import datetime, time, timedelta

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
# Heure à laquelle la veille "ouvre" les commandes du lendemain (§ demande).
# La tournée du lendemain se prépare la veille au soir : à partir de 19h00
# (heure de Madagascar), le préparateur et le livreur peuvent déjà agir sur
# les commandes planifiées pour le jour suivant. Exemple : une commande du
# 11/09 devient actionnable le 10/09 à 19h00.
HEURE_OUVERTURE_VEILLE = 19


def ouverture_actions(date_commande):
    """Instant à partir duquel préparateur et livreur peuvent agir sur une
    commande planifiée à `date_commande`.

    Ce n'est PAS minuit le jour de livraison : l'ouverture est fixée à
    `HEURE_OUVERTURE_VEILLE` la veille, dans le fuseau métier
    (Stock/settings.py TIME_ZONE = Indian/Antananarivo). Le web et l'app
    mobile appliquent exactement la même règle, mais c'est bien ce calcul-ci
    qui fait foi — un client ne fait qu'anticiper l'affichage.
    """
    tz = timezone.get_current_timezone()
    jour_livraison = timezone.localtime(date_commande).date()
    veille = jour_livraison - timedelta(days=1)
    return timezone.make_aware(
        datetime.combine(veille, time(HEURE_OUVERTURE_VEILLE, 0)), tz
    )


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


def livreur_has_time_conflict(user, date_commande, exclude_order=None):
    """Un livreur a-t-il déjà une autre commande (pré-assignée ou en cours)
    prévue le même jour, à la même heure — signal indicatif pour le
    sélecteur du gérant à la création (voir assign_livreur_early), sur le
    même principe que is_livreur_busy : n'empêche jamais la sélection, le
    gérant reste juge."""
    if not date_commande:
        return False
    qs = Order.objects.filter(
        livreur=user,
        date_commande__date=date_commande.date(),
        date_commande__hour=date_commande.hour,
    ).exclude(statut_courant__in=["LIVRE", "ANNULEE", "RETOUR"])
    if exclude_order:
        qs = qs.exclude(pk=exclude_order.pk)
    return qs.exists()


def assign_livreur_early(*, order, livreur_id, user):
    """Pré-assigne un livreur à une commande AVANT qu'elle soit Prête —
    indépendant du statut (contrairement à la désignation faite au moment de
    passer "En livraison", voir change_order_status/_resolve_assignee). Ne
    fait PAS progresser le statut de la commande : le passage "En livraison"
    reste une action manuelle distincte une fois Prête — _resolve_assignee
    réutilise alors ce livreur sans le redemander. Réservé au gérant."""
    role = user_commande_role(user)
    if role != "GERANT":
        raise PermissionDenied("Seul le gérant peut assigner un livreur à l'avance.")

    from users.models import CustomUser

    try:
        livreur = CustomUser.objects.get(id=livreur_id, employer_profile__commande_role="LIVREUR")
    except CustomUser.DoesNotExist:
        raise ValidationError("Livreur introuvable.")
    if livreur.employer_profile.magasin_id != order.magasin_id:
        raise ValidationError("Cette personne n'appartient pas à ce magasin.")
    if order.statut_courant in ("LIVRE", "ANNULEE"):
        raise ValidationError("Cette commande est déjà terminée.")

    order.livreur = livreur
    order.save(update_fields=["livreur", "updated_at"])
    return order


def assign_preparateur_early(*, order, preparateur_id, user):
    """Pré-assigne un préparateur à une commande sans la faire progresser —
    la commande reste "Nouvelle" (en attente) tant que ce préparateur n'a pas
    lui-même cliqué "Commencer la préparation" (§ demande — avant, choisir un
    préparateur à la création faisait sauter direct en "En préparation", ce
    qui ne laissait presque aucune fenêtre pour corriger la commande). Miroir
    de assign_livreur_early — réservé au gérant."""
    role = user_commande_role(user)
    if role != "GERANT":
        raise PermissionDenied("Seul le gérant peut assigner un préparateur à l'avance.")

    from users.models import CustomUser

    try:
        preparateur = CustomUser.objects.get(id=preparateur_id, employer_profile__commande_role="PREPARATEUR")
    except CustomUser.DoesNotExist:
        raise ValidationError("Préparateur introuvable.")
    if preparateur.employer_profile.magasin_id != order.magasin_id:
        raise ValidationError("Cette personne n'appartient pas à ce magasin.")
    if order.statut_courant not in ("NOUVELLE", "EN_PREPARATION"):
        raise ValidationError("Cette commande a déjà dépassé l'étape de préparation.")

    order.preparateur = preparateur
    order.save(update_fields=["preparateur", "updated_at"])
    return order


def _broadcast_notification_ws(group_name, *, notif_type, message, magasin, is_read=False):
    """Diffuse une seule fois sur un canal WebSocket donné — factorisé pour
    que _notify_commande_role ne dépende pas du signal post_save (voir plus
    bas, bulk_create ne déclenche aucun signal)."""
    try:
        from channels.layers import get_channel_layer
        from asgiref.sync import async_to_sync

        channel_layer = get_channel_layer()
        if not channel_layer:
            return
        async_to_sync(channel_layer.group_send)(
            group_name,
            {
                "type": "send_notification",
                "notification": {
                    "id": None,
                    "notif_type": notif_type,
                    "message": message,
                    "magasin": magasin.id if magasin else None,
                    "magasin_name": magasin.shop_name if magasin else None,
                    "is_read": is_read,
                    "created_at": timezone.now().isoformat(),
                },
            },
        )
    except Exception as e:
        print("Error broadcasting notification:", e)


def _notify_commande_role(*, magasin, commande_role, notif_type, message, order):
    """Notifie tous les employers du magasin ayant ce commande_role
    (Préparateur ou Livreur) — §9 Smartreadme.md. Une ligne par destinataire
    (pour un statut lu/non lu indépendant de chacun), mais créées en
    bulk_create — qui ne déclenche PAS le signal post_save de
    users/signals.py::notification_created_broadcast — pour ne diffuser
    qu'UNE fois par canal au lieu d'une fois par destinataire : sinon, avec
    plusieurs préparateurs/livreurs, le groupe magasin (donc le gérant)
    recevait le même toast en double/triple, une fois par ligne créée
    (§ bug "doublon à chaque notification")."""
    employer_user_ids = list(
        EmployerProfile.objects.filter(magasin=magasin, commande_role=commande_role).values_list(
            "user_id", flat=True
        )
    )

    if not employer_user_ids:
        # Personne assignée à ce rôle pour l'instant (MVP) : notification
        # visible tout de même côté magasin (le gérant la voit) — un .create()
        # normal ici, son propre broadcast (signal) ne peut pas se dupliquer
        # puisqu'il n'y a qu'une seule ligne.
        Notification.objects.create(notif_type=notif_type, message=message, magasin=magasin)
        return

    Notification.objects.bulk_create(
        [
            Notification(notif_type=notif_type, message=message, magasin=magasin, user_id=user_id)
            for user_id in employer_user_ids
        ]
    )

    # Une diffusion magasin/admin (le gérant la voit une seule fois)...
    _broadcast_notification_ws(f"notifications_magasin_{magasin.id}", notif_type=notif_type, message=message, magasin=magasin)
    _broadcast_notification_ws(f"notifications_admin_{magasin.admin_id}", notif_type=notif_type, message=message, magasin=magasin)
    # ...et une diffusion personnelle à chaque destinataire (chacun reçoit la
    # sienne une seule fois, pas celle des autres).
    for user_id in employer_user_ids:
        _broadcast_notification_ws(f"notifications_user_{user_id}", notif_type=notif_type, message=message, magasin=magasin)


@transaction.atomic
def create_order(*, magasin, client_nom, telephone, livraison_zone, items, note_preparateur="", note_livreur="",
                  created_by, date_commande=None, adresse_livraison="", mode_paiement="LIVRAISON", preparateur=None):
    """items: liste de {"product_variant": ProductVariant, "quantite": int}.
    Prix et frais de livraison sont calculés côté serveur (§6 Smartreadme.md
    — 'Prix' et 'Frais livraison' en lecture seule). `date_commande` est
    optionnelle (auto = maintenant côté modèle, avec l'heure précise) mais
    modifiable par le gérant (§6 : 'Auto = aujourd'hui, modifiable').
    `note_preparateur`/`note_livreur` : deux notes distinctes, chacune
    destinée à un seul rôle (§ demande). `preparateur` : auto-assigné au
    préparateur créateur pour ses propres retraits sur place (§ demande —
    seules les commandes assignées à son nom apparaissent dans sa page)."""

    order = Order.objects.create(
        magasin=magasin,
        client_nom=client_nom,
        telephone=telephone,
        livraison_zone=livraison_zone,
        adresse_livraison=adresse_livraison,
        mode_paiement=mode_paiement,
        note_preparateur=note_preparateur,
        note_livreur=note_livreur,
        created_by=created_by,
        preparateur=preparateur,
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


# Une commande assignée à un préparateur dès sa création part directement en
# "En préparation" (voir change_order_status) — restreindre l'édition à
# "Nouvelle" laissait donc une fenêtre quasi nulle pour la corriger
# (§ demande). Au-delà, la commande est trop engagée (livreur en tournée...).
_EDITABLE_STATUSES = {"NOUVELLE", "EN_PREPARATION"}


@transaction.atomic
def update_order(*, order, user, client_nom=None, telephone=None, livraison_zone=None, adresse_livraison=None,
                  mode_paiement=None, date_commande=None, note_preparateur=None, note_livreur=None, items=None):
    """Modification d'une commande "Nouvelle" ou "En préparation" (gérant
    uniquement, voir views.py::get_permissions). Si les articles changent
    alors que le stock a déjà été déduit (statut "En préparation"), l'ancien
    stock est restitué et le nouveau déduit — mouvement 'AJUSTEMENT', pour ne
    pas se confondre avec une préparation ou un retour normaux."""
    if order.statut_courant not in _EDITABLE_STATUSES:
        raise ValidationError(
            f"Cette commande est '{order.get_statut_courant_display()}' — trop engagée pour être modifiée."
        )

    for field, value in {
        "client_nom": client_nom,
        "telephone": telephone,
        "livraison_zone": livraison_zone,
        "adresse_livraison": adresse_livraison,
        "mode_paiement": mode_paiement,
        "date_commande": date_commande,
        "note_preparateur": note_preparateur,
        "note_livreur": note_livreur,
    }.items():
        if value is not None:
            setattr(order, field, value)
    order.save()

    if items is not None:
        stock_already_deducted = order.statut_courant == "EN_PREPARATION"
        if stock_already_deducted:
            for item in order.items.select_related("product_variant"):
                apply_stock_movement(
                    product_variant=item.product_variant, movement_type="ENTREE", quantite=item.quantite,
                    origine="AJUSTEMENT", user=user, reference=order.numero,
                    note="Modification de commande — article retiré",
                )
        order.items.all().delete()
        for item in items:
            OrderItem.objects.create(
                order=order, product_variant=item["product_variant"], quantite=item.get("quantite", 1),
            )
        if stock_already_deducted:
            for item in order.items.select_related("product_variant"):
                apply_stock_movement(
                    product_variant=item.product_variant, movement_type="SORTIE", quantite=item.quantite,
                    origine="AJUSTEMENT", user=user, reference=order.numero,
                    note="Modification de commande — article ajouté",
                )

    order.recompute_total()
    return order


def _resolve_assignee(*, order, role, requesting_user, requested_role, assignee_id, field_name):
    """Résout qui doit être assigné (préparateur/livreur) pour une
    transition. Le gérant désigne manuellement qui il veut (un préparateur/
    livreur déjà occupé sur une autre commande reste sélectionnable — c'est
    au gérant d'en juger, voir is_preparateur_busy/is_livreur_busy qui
    restent utilisées côté "available-staff" comme simple indication).

    - Gérant : doit désigner explicitement quelqu'un (`assignee_id` requis),
      sauf si un livreur a déjà été pré-assigné plus tôt (voir
      assign_livreur_early) — dans ce cas il n'a pas besoin d'être reprécisé.
    - Le rôle concerné (Préparateur/Livreur) lui-même : auto-affectation si
      `assignee_id` absent, sinon doit correspondre à lui-même.
    """
    from users.models import CustomUser

    if role == "GERANT":
        if not assignee_id:
            already_assigned = getattr(order, field_name)
            if already_assigned:
                setattr(order, field_name, already_assigned)
                return already_assigned
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
def change_order_status(*, order, new_status, user, note="", preparateur_id=None, livreur_id=None, assigned_at=None,
                         photo=None):
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
            order=order, ancien_statut=old_status, nouveau_statut=new_status, changed_by=user, note=note,
            **({"photo": photo} if photo else {}),
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
    # mais ne peut agir dessus qu'à partir de l'ouverture — 19h00 la veille
    # du jour de livraison (voir ouverture_actions). Le gérant, lui, peut
    # toujours forcer une transition en avance.
    if role != "GERANT":
        ouverture = ouverture_actions(order.date_commande)
        if timezone.now() < ouverture:
            raise PermissionDenied(
                f"Cette commande est planifiée pour le "
                f"{timezone.localtime(order.date_commande).strftime('%d/%m/%Y')} — "
                f"l'action sera possible à partir du "
                f"{timezone.localtime(ouverture).strftime('%d/%m/%Y à %Hh%M')}."
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
        **({"photo": photo} if photo else {}),
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
