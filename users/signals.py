from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from .models import CustomUser, Notification, EmployerProfile, ChatMessage, CaisseSession, CaisseMovement
from .broadcast import broadcast_data_event


@receiver(post_save, sender=CaisseSession)
def caisse_session_saved(sender, instance: CaisseSession, created, **kwargs):
    broadcast_data_event("caisse_session", "created" if created else "updated", instance)
    try:
        if created:
            who = instance.opened_by.full_name if instance.opened_by else "Système"
            msg = f"Caisse ouverte ({instance.magasin.shop_name}) par {who} — fond: {instance.opening_balance}"
        elif instance.status == "closed":
            who = instance.closed_by.full_name if instance.closed_by else "Système"
            msg = f"Caisse fermée ({instance.magasin.shop_name}) par {who} — écart: {instance.difference}"
        else:
            return
        Notification.objects.create(notif_type="caisse", message=msg, magasin=instance.magasin, caisse_session=instance)
    except Exception:
        pass


@receiver(post_save, sender=CaisseMovement)
def caisse_movement_saved(sender, instance: CaisseMovement, created, **kwargs):
    if not created:
        return
    broadcast_data_event("caisse_movement", "created", instance)
    try:
        who = instance.created_by.full_name if instance.created_by else "Système"
        sign = "+" if instance.movement_type == "in" else "-"
        msg = f"Mouvement de caisse {sign}{instance.amount} ({instance.reason}) — {who}"
        Notification.objects.create(notif_type="caisse", message=msg, magasin=instance.magasin, caisse_session=instance.session)
    except Exception:
        pass


@receiver(post_delete, sender=CaisseMovement)
def caisse_movement_deleted(sender, instance: CaisseMovement, **kwargs):
    broadcast_data_event("caisse_movement", "deleted", instance)


@receiver(post_save, sender=CustomUser)
def user_created(sender, instance: CustomUser, created, **kwargs):
    if not created:
        return
    try:
        msg = f"Nouvel utilisateur: {instance.full_name} ({instance.email}) — rôle: {instance.role}"
        magasin = None
        # try to find magasin for employer
        if instance.role == 'employer':
            try:
                emp = EmployerProfile.objects.filter(user=instance).first()
                if emp:
                    magasin = emp.magasin
            except Exception:
                magasin = None
        Notification.objects.create(notif_type="user", message=msg, magasin=magasin, user=instance)
    except Exception:
        pass


@receiver(post_save, sender=Notification)
def notification_created_broadcast(sender, instance: Notification, created, **kwargs):
    if not created:
        return
    try:
        from channels.layers import get_channel_layer
        from asgiref.sync import async_to_sync
        
        channel_layer = get_channel_layer()
        if not channel_layer:
            return
            
        notif_data = {
            "id": instance.id,
            "notif_type": instance.notif_type,
            "message": instance.message,
            "magasin": instance.magasin.id if instance.magasin else None,
            "magasin_name": instance.magasin.shop_name if instance.magasin else None,
            "is_read": instance.is_read,
            "created_at": instance.created_at.isoformat()
        }
        
        # Broadcast to admins
        admin_id = None
        if instance.magasin:
            admin_id = instance.magasin.admin.id
        elif instance.user:
            u = instance.user
            if u.role == 'admin':
                admin_id = u.id
            elif u.role == 'magasin':
                try:
                    admin_id = u.magasin_profile.admin.id
                except Exception:
                    pass
            elif u.role == 'employer':
                try:
                    ep = u.employer_profile
                    if ep.admin:
                        admin_id = ep.admin.id
                    elif ep.magasin:
                        admin_id = ep.magasin.admin.id
                except Exception:
                    pass

        if admin_id:
            async_to_sync(channel_layer.group_send)(
                f"notifications_admin_{admin_id}",
                {
                    "type": "send_notification",
                    "notification": notif_data
                }
            )
        
        # Broadcast to specific magasin group if applicable
        if instance.magasin:
            async_to_sync(channel_layer.group_send)(
                f"notifications_magasin_{instance.magasin.id}",
                {
                    "type": "send_notification",
                    "notification": notif_data
                }
            )
            
        # Broadcast to specific user group if targeted
        if instance.user:
            async_to_sync(channel_layer.group_send)(
                f"notifications_user_{instance.user.id}",
                {
                    "type": "send_notification",
                    "notification": notif_data
                }
            )
    except Exception as e:
        print("Error broadcasting notification:", e)


@receiver(post_save, sender=ChatMessage)
def chat_message_created(sender, instance: ChatMessage, created, **kwargs):
    if not created:
        return
    try:
        sender_name = instance.sender.full_name or instance.sender.username
        
        if instance.recipient:
            # Direct Message: targeted notification
            Notification.objects.create(
                notif_type="chat",
                message=f"Message privé de {sender_name} : {instance.content[:60]}",
                user=instance.recipient
            )
        else:
            # General Message: targeted to sender's magasin
            magasin = None
            if instance.sender.role == 'magasin':
                try:
                    magasin = instance.sender.magasin_profile
                except Exception:
                    pass
            elif instance.sender.role == 'employer':
                try:
                    magasin = instance.sender.employer_profile.magasin
                except Exception:
                    pass
            
            Notification.objects.create(
                notif_type="chat",
                message=f"Message de {sender_name} dans Général : {instance.content[:60]}",
                magasin=magasin
            )
    except Exception as e:
        print("Error creating chat notification:", e)


