import json
from urllib.parse import parse_qs
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.tokens import AccessToken

User = get_user_model()

class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        # 1. Parse token from query string
        query_string = self.scope.get("query_string", b"").decode("utf-8")
        query_params = parse_qs(query_string)
        token_list = query_params.get("token")
        
        self.user = None
        if token_list:
            token = token_list[0]
            self.user = await self.get_user_from_token(token)
            
        if not self.user or self.user.is_anonymous:
            # Reject connection if not authenticated
            await self.close()
            return
            
        my_magasin_ids = await self.get_company_magasin_ids_async(self.user)
        if not my_magasin_ids:
            await self.close()
            return
        self.my_magasin_ids = my_magasin_ids

        # 2. Get room name: could be 'general' or 'dm_<user1_id>_<user2_id>'
        room_list = query_params.get("room")
        raw_room = room_list[0] if room_list else "general"

        recipient_id_list = query_params.get("recipient_id")
        if recipient_id_list:
            try:
                recipient_id = int(recipient_id_list[0])
                self.recipient = await self.get_user_by_id(recipient_id)
                if not self.recipient:
                    await self.close()
                    return
                # Verify that the recipient belongs to the same company (shares a magasin)
                recipient_magasin_ids = await self.get_company_magasin_ids_async(self.recipient)
                if not recipient_magasin_ids or not (my_magasin_ids & recipient_magasin_ids):
                    await self.close()
                    return
                # Create a deterministic room name for the DM
                user_ids = sorted([self.user.id, recipient_id])
                self.room_name = f"dm_{user_ids[0]}_{user_ids[1]}"
            except Exception:
                await self.close()
                return
        else:
            self.recipient = None
            if raw_room == "general":
                company_id = await self.get_company_id_async(self.user)
                if not company_id:
                    await self.close()
                    return
                self.room_name = f"general_{company_id}"
            else:
                self.room_name = raw_room

        self.room_group_name = f"chat_{self.room_name}"
        
        # 3. Join the room group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )
        await self.accept()
        
    async def disconnect(self, close_code):
        if hasattr(self, 'room_group_name'):
            await self.channel_layer.group_discard(
                self.room_group_name,
                self.channel_name
            )
            
    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return

        action = data.get("action", "send")

        if action == "edit":
            message_id = data.get("message_id")
            content = data.get("content")
            if not message_id or not content:
                return
            updated = await self.edit_message(message_id, content)
            if updated is None:
                return
            await self.channel_layer.group_send(
                self.room_group_name,
                {"type": "chat_message_edited", "message": updated}
            )
            return

        if action == "delete":
            message_id = data.get("message_id")
            if not message_id:
                return
            deleted = await self.remove_message(message_id)
            if deleted is None:
                return
            await self.channel_layer.group_send(
                self.room_group_name,
                {"type": "chat_message_deleted", "message": deleted}
            )
            return

        # Default action: send a new message.
        content = data.get("content") or ""
        if not content:
            return

        saved_msg = await self.save_message(self.user, self.recipient, self.room_name, content)

        await self.channel_layer.group_send(
            self.room_group_name,
            {
                "type": "chat_message",
                "message": saved_msg
            }
        )

    async def chat_message(self, event):
        await self.send(text_data=json.dumps({"type": "message", **event["message"]}))

    async def chat_message_edited(self, event):
        await self.send(text_data=json.dumps({"type": "message_edited", **event["message"]}))

    async def chat_message_deleted(self, event):
        await self.send(text_data=json.dumps({"type": "message_deleted", **event["message"]}))

    @database_sync_to_async
    def get_user_from_token(self, token_str):
        try:
            access_token = AccessToken(token_str)
            user_id = access_token["user_id"]
            return User.objects.get(id=user_id)
        except Exception:
            return None
            
    @database_sync_to_async
    def get_user_by_id(self, user_id):
        try:
            return User.objects.get(id=user_id)
        except User.DoesNotExist:
            return None

    @database_sync_to_async
    def get_company_magasin_ids_async(self, user):
        from users.views import get_company_magasins
        return set(get_company_magasins(user).values_list("id", flat=True))

    @database_sync_to_async
    def get_company_id_async(self, user):
        from users.views import get_company_id
        return get_company_id(user)

    @database_sync_to_async
    def save_message(self, sender, recipient, room_name, content):
        from users.models import ChatMessage
        msg = ChatMessage.objects.create(
            sender=sender,
            recipient=recipient,
            room_name=room_name,
            content=content,
        )
        return {
            "id": msg.id,
            "sender": sender.id,
            "sender_name": sender.full_name,
            "sender_email": sender.email,
            "sender_role": sender.role,
            "recipient": recipient.id if recipient else None,
            "recipient_name": recipient.full_name if recipient else None,
            "recipient_email": recipient.email if recipient else None,
            "room_name": room_name,
            "content": content,
            "is_edited": False,
            "is_deleted": False,
            "timestamp": msg.timestamp.isoformat()
        }

    @database_sync_to_async
    def edit_message(self, message_id, content):
        from django.utils import timezone
        from users.models import ChatMessage
        try:
            msg = ChatMessage.objects.get(id=message_id, room_name=self.room_name)
        except ChatMessage.DoesNotExist:
            return None
        if msg.sender_id != self.user.id or msg.is_deleted:
            return None
        msg.content = content
        msg.is_edited = True
        msg.edited_at = timezone.now()
        msg.save(update_fields=["content", "is_edited", "edited_at"])
        return {
            "id": msg.id,
            "room_name": msg.room_name,
            "content": msg.content,
            "is_edited": True,
            "edited_at": msg.edited_at.isoformat(),
        }

    @database_sync_to_async
    def remove_message(self, message_id):
        from users.models import ChatMessage
        try:
            msg = ChatMessage.objects.get(id=message_id, room_name=self.room_name)
        except ChatMessage.DoesNotExist:
            return None
        if msg.sender_id != self.user.id:
            return None
        msg.is_deleted = True
        msg.content = ""
        msg.save(update_fields=["is_deleted", "content"])
        return {
            "id": msg.id,
            "room_name": msg.room_name,
        }


class NotificationConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.groups_joined = []
        # 1. Parse token from query string
        query_string = self.scope.get("query_string", b"").decode("utf-8")
        query_params = parse_qs(query_string)
        token_list = query_params.get("token")

        self.user = None
        if token_list:
            token = token_list[0]
            self.user = await self.get_user_from_token(token)

        if not self.user or self.user.is_anonymous:
            await self.close()
            return
        
        # 2. Join groups based on role
        if self.user.role == "admin":
            group_name = f"notifications_admin_{self.user.id}"
            await self.channel_layer.group_add(group_name, self.channel_name)
            self.groups_joined.append(group_name)
        else:
            magasin_id = await self.get_user_magasin_id(self.user)
            if magasin_id:
                group_name = f"notifications_magasin_{magasin_id}"
                await self.channel_layer.group_add(group_name, self.channel_name)
                self.groups_joined.append(group_name)
                
        # 3. Always join personal group for direct notifications
        personal_group = f"notifications_user_{self.user.id}"
        await self.channel_layer.group_add(personal_group, self.channel_name)
        self.groups_joined.append(personal_group)
                
        await self.accept()
        
    async def disconnect(self, close_code):
        for group_name in self.groups_joined:
            await self.channel_layer.group_discard(group_name, self.channel_name)
            
    async def send_notification(self, event):
        # Send notification to WebSocket
        await self.send(text_data=json.dumps(event["notification"]))
        
    @database_sync_to_async
    def get_user_from_token(self, token_str):
        try:
            access_token = AccessToken(token_str)
            user_id = access_token["user_id"]
            return User.objects.get(id=user_id)
        except Exception:
            return None

    @database_sync_to_async
    def get_user_magasin_id(self, user):
        if user.role == "magasin":
            try:
                return user.magasin_profile.id
            except Exception:
                return None
        elif user.role == "employer":
            try:
                return user.employer_profile.magasin.id
            except Exception:
                return None
        return None


class DataSyncConsumer(AsyncWebsocketConsumer):
    """Broadcasts real-time updates for products, sales, movements and stats."""

    async def connect(self):
        self.groups_joined = []
        query_string = self.scope.get("query_string", b"").decode("utf-8")
        query_params = parse_qs(query_string)
        token_list = query_params.get("token")

        self.user = None
        if token_list:
            self.user = await self.get_user_from_token(token_list[0])

        if not self.user or self.user.is_anonymous:
            await self.close()
            return

        if self.user.role == "admin":
            group_name = f"data_admin_{self.user.id}"
            await self.channel_layer.group_add(group_name, self.channel_name)
            self.groups_joined.append(group_name)
        else:
            magasin_id = await self.get_user_magasin_id(self.user)
            if magasin_id:
                group_name = f"data_magasin_{magasin_id}"
                await self.channel_layer.group_add(group_name, self.channel_name)
                self.groups_joined.append(group_name)

        await self.accept()

    async def disconnect(self, close_code):
        for group_name in self.groups_joined:
            await self.channel_layer.group_discard(group_name, self.channel_name)

    async def data_update(self, event):
        await self.send(text_data=json.dumps(event["payload"]))

    @database_sync_to_async
    def get_user_from_token(self, token_str):
        try:
            access_token = AccessToken(token_str)
            user_id = access_token["user_id"]
            return User.objects.get(id=user_id)
        except Exception:
            return None

    @database_sync_to_async
    def get_user_magasin_id(self, user):
        if user.role == "magasin":
            try:
                return user.magasin_profile.id
            except Exception:
                return None
        elif user.role == "employer":
            try:
                return user.employer_profile.magasin.id
            except Exception:
                return None
        return None

