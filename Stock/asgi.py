import os
import django
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'Stock.settings')

# Initialize Django ASGI application early
django.setup()

# NOW Django is fully initialized, safe to import consumers
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack
from django.urls import path
from users.consumers import ChatConsumer, NotificationConsumer, DataSyncConsumer

django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": AuthMiddlewareStack(
        URLRouter([
            path("ws/chat/", ChatConsumer.as_asgi()),
            path("ws/notifications/", NotificationConsumer.as_asgi()),
            path("ws/data/", DataSyncConsumer.as_asgi()),
        ])
    ),
})

