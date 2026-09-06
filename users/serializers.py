from django.db.models import Q
from rest_framework import serializers
from .models import (
    CustomUser,
    AdminProfile,
    MagasinProfile,
    EmployerProfile,
    Notification,
    CaisseSession,
    CaisseMovement,
    CaisseCategory,
    ChatMessage,
    LoginEvent,
    EmployeePasswordResetRequest,
)

class RegisterSerializer(serializers.ModelSerializer):
    company_name = serializers.CharField(required=False)
    shop_name = serializers.CharField(required=False)
    position = serializers.CharField(required=False)
    admin_email = serializers.EmailField(required=False)
    # Sous-rôle module Commande (Smartreadme.md §4/§5) — Préparateur ou
    # Livreur, uniquement pertinent pour role="employer".
    commande_role = serializers.ChoiceField(choices=EmployerProfile.COMMANDE_ROLE_CHOICES, required=False, allow_null=True)

    class Meta:
        model = CustomUser
        fields = [
            "id",
            "username",
            "full_name",
            "email",
            "password",
            "phone",
            "role",
            "company_name",
            "shop_name",
            "position",
            "admin_email",
            "commande_role",
        ]
        extra_kwargs = {"password": {"write_only": True}}

    def create(self, validated_data):
        role = validated_data.get("role")
        username = validated_data.pop("username", validated_data.get("email"))
        admin_email = validated_data.pop("admin_email", None)
        company_name = validated_data.pop("company_name", None)
        shop_name = validated_data.pop("shop_name", None)
        position = validated_data.pop("position", None)
        commande_role = validated_data.pop("commande_role", None)
        password = validated_data.pop("password")

        # Si un admin déjà authentifié crée lui-même ce compte (depuis l'app,
        # pas l'auto-inscription publique), on l'active directement — pas
        # besoin d'une étape d'approbation manuelle séparée pour un compte
        # que l'admin vient de créer de ses propres mains.
        request = self.context.get("request")
        requester = getattr(request, "user", None)
        requester_is_authenticated_admin = bool(
            requester and requester.is_authenticated and requester.role == "admin"
        )

        if role == "admin":
            company_name = company_name or validated_data.get("full_name") or "Entreprise"
            user = CustomUser.objects.create(username=username, is_confirmed=True, **validated_data)
            user.set_password(password)
            user.save()
            AdminProfile.objects.create(user=user, company_name=company_name)
            return user
        elif role == "magasin":
            try:
                admin = CustomUser.objects.get(email=admin_email, role="admin")
            except CustomUser.DoesNotExist:
                raise serializers.ValidationError({"admin_email": "Administrateur introuvable avec cet email."})
            auto_confirm = requester_is_authenticated_admin and requester.id == admin.id
            user = CustomUser.objects.create(username=username, is_confirmed=auto_confirm, **validated_data)
            user.set_password(password)
            user.save()
            magasin = MagasinProfile.objects.create(user=user, admin=admin, shop_name=shop_name)
            # `admin` peut être un simple co-admin (pas le fondateur) : il faut
            # donner accès à TOUS les admins de la société (fondateur inclus),
            # sinon ce magasin/gérant reste invisible pour eux (cf. get_company_admin_ids).
            from .subscriptions import get_company_admin_ids
            magasin.admins.set(CustomUser.objects.filter(id__in=get_company_admin_ids(admin)))
            return user
        elif role == "employer":
            admin = CustomUser.objects.filter(email=admin_email, role="admin").first()
            magasin = None
            if not admin:
                magasin_user = CustomUser.objects.filter(email=admin_email, role="magasin").first()
                if magasin_user:
                    magasin = MagasinProfile.objects.get(user=magasin_user)
            elif admin:
                # L'employé a donné l'email de l'ADMIN (pas d'un gérant
                # précis) — sans magasin explicite, il restait `magasin=None`
                # pour toujours, donc invisible dans la liste de tout magasin
                # (UsersByMagasinView filtre par magasin exact). Si cet admin
                # n'a qu'un seul magasin (cas très courant : société avec
                # juste "Stock Local"), on l'y assigne directement. S'il en a
                # plusieurs, impossible de deviner lequel : reste non assigné.
                admin_magasins = MagasinProfile.objects.filter(Q(admin=admin) | Q(admins=admin)).distinct()
                if admin_magasins.count() == 1:
                    magasin = admin_magasins.first()
            if not admin and not magasin:
                raise serializers.ValidationError({"admin_email": "Responsable (administrateur ou gérant) introuvable avec cet email."})
            auto_confirm = requester_is_authenticated_admin and admin is not None and requester.id == admin.id
            user = CustomUser.objects.create(username=username, is_confirmed=auto_confirm, **validated_data)
            user.set_password(password)
            user.save()
            EmployerProfile.objects.create(
                user=user, admin=admin, magasin=magasin, position=position, commande_role=commande_role
            )
            return user
        raise serializers.ValidationError("Role invalide")

class CaisseCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = CaisseCategory
        fields = ["id", "nom", "created_at"]
        read_only_fields = ["id", "created_at"]


class CaisseMovementSerializer(serializers.ModelSerializer):
    magasin_name = serializers.CharField(source="magasin.shop_name", read_only=True)
    created_by_name = serializers.CharField(source="created_by.full_name", read_only=True)
    category_name = serializers.CharField(source="category.nom", read_only=True)

    class Meta:
        model = CaisseMovement
        fields = [
            "id",
            "session",
            "magasin",
            "magasin_name",
            "movement_type",
            "amount",
            "reason",
            "category",
            "category_name",
            "created_by",
            "created_by_name",
            "created_at",
        ]
        read_only_fields = ["id", "session", "magasin", "created_by", "created_at"]

    def validate(self, attrs):
        category = attrs.get("category")
        movement_type = attrs.get("movement_type")
        if category and movement_type == "in":
            raise serializers.ValidationError("Une catégorie ne s'applique qu'aux sorties.")
        return attrs


class CaisseSessionSerializer(serializers.ModelSerializer):
    magasin_name = serializers.CharField(source="magasin.shop_name", read_only=True)
    opened_by_name = serializers.CharField(source="opened_by.full_name", read_only=True)
    closed_by_name = serializers.CharField(source="closed_by.full_name", read_only=True)
    movements = CaisseMovementSerializer(many=True, read_only=True)

    class Meta:
        model = CaisseSession
        fields = [
            "id",
            "magasin",
            "magasin_name",
            "status",
            "opened_by",
            "opened_by_name",
            "closed_by",
            "closed_by_name",
            "opening_balance",
            "closing_balance",
            "expected_balance",
            "difference",
            "opening_note",
            "closing_note",
            "opened_at",
            "closed_at",
            "movements",
        ]
        read_only_fields = [
            "id",
            "magasin",
            "status",
            "opened_by",
            "closed_by",
            "expected_balance",
            "difference",
            "opened_at",
            "closed_at",
            "movements",
        ]


class NotificationSerializer(serializers.ModelSerializer):
    magasin_name = serializers.CharField(source="magasin.shop_name", read_only=True)
    user_name = serializers.CharField(source="user.full_name", read_only=True)

    class Meta:
        model = Notification
        fields = ["id", "notif_type", "message", "magasin", "magasin_name", "caisse_session", "user", "user_name", "is_read", "created_at"]
        read_only_fields = ["id", "created_at"]


class MagasinProfileSerializer(serializers.ModelSerializer):
    shop_logo = serializers.SerializerMethodField()

    class Meta:
        model = MagasinProfile
        fields = ["id", "shop_name", "description", "shop_logo", "admin", "user"]
        read_only_fields = ["id", "admin", "user"]

    def get_shop_logo(self, obj):
        request = self.context.get('request')
        if obj.shop_logo and request:
            return request.build_absolute_uri(obj.shop_logo.url)
        return None


class LoginEventSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source="user.full_name", read_only=True)
    user_email = serializers.CharField(source="user.email", read_only=True)
    user_role = serializers.CharField(source="user.role", read_only=True)

    class Meta:
        model = LoginEvent
        fields = ["id", "user_name", "user_email", "user_role", "ip_address", "user_agent", "created_at"]


class EmployeePasswordResetRequestSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source="user.full_name", read_only=True)
    user_email = serializers.CharField(source="user.email", read_only=True)
    user_role = serializers.CharField(source="user.role", read_only=True)
    magasin_name = serializers.CharField(source="magasin.shop_name", read_only=True)

    class Meta:
        model = EmployeePasswordResetRequest
        fields = [
            "id", "status", "user_name", "user_email", "user_role", "magasin_name",
            "created_at", "resolved_at",
        ]
        read_only_fields = fields


class ChatMessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.CharField(source="sender.full_name", read_only=True)
    sender_email = serializers.CharField(source="sender.email", read_only=True)
    sender_role = serializers.CharField(source="sender.role", read_only=True)
    recipient_name = serializers.CharField(source="recipient.full_name", read_only=True)
    recipient_email = serializers.CharField(source="recipient.email", read_only=True)

    class Meta:
        model = ChatMessage
        fields = [
            "id",
            "sender",
            "sender_name",
            "sender_email",
            "sender_role",
            "recipient",
            "recipient_name",
            "recipient_email",
            "room_name",
            "content",
            "is_edited",
            "edited_at",
            "is_deleted",
            "timestamp",
        ]
        read_only_fields = ["id", "timestamp"]
