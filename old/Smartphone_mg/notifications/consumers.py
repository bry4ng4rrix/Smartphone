import json
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.tokens import AccessToken

User = get_user_model()


class NotificationConsumer(AsyncWebsocketConsumer):
    """ws://.../ws/notifications/?token=<jwt access token>
    Rejoint le groupe de son rôle (préparateur/livreur reçoivent les
    événements §9 README) + un groupe personnel pour un ciblage futur."""

    async def connect(self):
        self.groups_joined = []

        query_string = self.scope.get("query_string", b"").decode("utf-8")
        query_params = parse_qs(query_string)
        token_list = query_params.get("token")

        self.user = await self.get_user_from_token(token_list[0]) if token_list else None

        if not self.user or self.user.is_anonymous:
            await self.close()
            return

        role_group = f"notifications_role_{self.user.role}"
        await self.channel_layer.group_add(role_group, self.channel_name)
        self.groups_joined.append(role_group)

        personal_group = f"notifications_user_{self.user.id}"
        await self.channel_layer.group_add(personal_group, self.channel_name)
        self.groups_joined.append(personal_group)

        await self.accept()

    async def disconnect(self, close_code):
        for group_name in self.groups_joined:
            await self.channel_layer.group_discard(group_name, self.channel_name)

    async def send_notification(self, event):
        await self.send(text_data=json.dumps(event["notification"]))

    @database_sync_to_async
    def get_user_from_token(self, token_str):
        try:
            access_token = AccessToken(token_str)
            user_id = access_token["user_id"]
            return User.objects.get(id=user_id)
        except Exception:
            return None
