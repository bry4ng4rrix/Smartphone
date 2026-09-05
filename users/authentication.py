from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.exceptions import AuthenticationFailed

from .models import LoginEvent
from .subscriptions import get_client_ip


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):

    def validate(self, attrs):
        data = super().validate(attrs)

        if not self.user.is_confirmed:
            raise AuthenticationFailed(
                "Compte non approuvé. Contactez votre administrateur.",
                code="account_not_approved",
            )

        request = self.context.get("request")
        ip_address = get_client_ip(request) if request else None
        user_agent = request.META.get("HTTP_USER_AGENT", "")[:500] if request else ""

        if request is not None:
            try:
                LoginEvent.objects.create(
                    user=self.user,
                    ip_address=ip_address,
                    user_agent=user_agent,
                )
            except Exception:
                pass

        return data


class CustomTokenRefreshSerializer(TokenRefreshSerializer):
    pass
