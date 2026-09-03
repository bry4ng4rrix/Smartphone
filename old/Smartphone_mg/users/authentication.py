from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.exceptions import AuthenticationFailed


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Login par email + mot de passe (email = USERNAME_FIELD). Ajoute le
    rôle et le nom complet dans la réponse pour éviter un aller-retour
    supplémentaire sur /me/ juste après la connexion."""

    def validate(self, attrs):
        data = super().validate(attrs)

        if not self.user.is_active:
            raise AuthenticationFailed(
                "Compte désactivé. Contactez le gérant.",
                code="account_inactive",
            )

        data["role"] = self.user.role
        data["full_name"] = self.user.full_name
        data["user_id"] = self.user.id
        return data
