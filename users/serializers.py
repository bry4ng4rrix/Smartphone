from datetime import timedelta

from django.db.models import Q, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import serializers
from .models import (
    CustomUser,
    AdminProfile,
    MagasinProfile,
    EmployerProfile,
    Notification,
    CaisseSession,
    CaisseMovement,
    ChatMessage,
    Subscription,
    SubscriptionOffer,
    LoginEvent,
    PlatformRequest,
    Device,
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
            admin_profile = AdminProfile.objects.create(user=user, company_name=company_name)
            Subscription.objects.create(
                admin_profile=admin_profile,
                status="trial",
                trial_ends_at=timezone.now() + timedelta(days=30),
            )
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

class CaisseMovementSerializer(serializers.ModelSerializer):
    magasin_name = serializers.CharField(source="magasin.shop_name", read_only=True)
    created_by_name = serializers.CharField(source="created_by.full_name", read_only=True)

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
            "created_by",
            "created_by_name",
            "created_at",
        ]
        read_only_fields = ["id", "session", "magasin", "created_by", "created_at"]


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


class SubscriptionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Subscription
        fields = ["id", "status", "trial_ends_at", "notes", "updated_at", "is_currently_active", "days_left_in_trial"]
        read_only_fields = ["id", "updated_at", "is_currently_active", "days_left_in_trial"]


class CompanySubscriptionSerializer(serializers.ModelSerializer):
    admin_id = serializers.IntegerField(source="user.id", read_only=True)
    admin_email = serializers.CharField(source="user.email", read_only=True)
    admin_full_name = serializers.CharField(source="user.full_name", read_only=True)
    admin_phone = serializers.CharField(source="user.phone", read_only=True)
    logo = serializers.SerializerMethodField()
    status = serializers.SerializerMethodField()
    trial_ends_at = serializers.SerializerMethodField()
    is_currently_active = serializers.SerializerMethodField()
    days_left_in_trial = serializers.SerializerMethodField()
    store_count = serializers.SerializerMethodField()
    user_count = serializers.SerializerMethodField()
    admin_count = serializers.SerializerMethodField()
    total_stock = serializers.SerializerMethodField()
    offer_id = serializers.SerializerMethodField()
    offer_name = serializers.SerializerMethodField()
    max_devices = serializers.SerializerMethodField()
    device_count = serializers.SerializerMethodField()

    class Meta:
        model = AdminProfile
        fields = [
            "id", "company_name", "admin_id", "admin_email", "admin_full_name", "admin_phone",
            "logo", "created_at", "status", "trial_ends_at", "is_currently_active",
            "days_left_in_trial", "store_count", "user_count", "admin_count", "total_stock",
            "offer_id", "offer_name", "max_devices", "device_count",
        ]

    def get_logo(self, obj):
        request = self.context.get("request")
        if obj.logo and request:
            return request.build_absolute_uri(obj.logo.url)
        return None

    def _subscription(self, obj):
        return getattr(obj, "subscription", None)

    def get_status(self, obj):
        sub = self._subscription(obj)
        return sub.status if sub else "pending"

    def get_trial_ends_at(self, obj):
        sub = self._subscription(obj)
        return sub.trial_ends_at if sub else None

    def get_is_currently_active(self, obj):
        sub = self._subscription(obj)
        return sub.is_currently_active if sub else False

    def get_days_left_in_trial(self, obj):
        sub = self._subscription(obj)
        return sub.days_left_in_trial if sub else None

    def get_store_count(self, obj):
        from .subscriptions import get_company_magasins
        return get_company_magasins(obj.user).count()

    def get_user_count(self, obj):
        from .subscriptions import get_company_user_ids
        return len(get_company_user_ids(obj.user))

    def get_admin_count(self, obj):
        from .subscriptions import get_company_admin_ids
        return len(get_company_admin_ids(obj.user))

    def get_total_stock(self, obj):
        from catalog.models import ProductVariant
        from .subscriptions import get_company_magasins
        magasins = get_company_magasins(obj.user)
        return ProductVariant.objects.filter(
            product_reference__type__category__magasin__in=magasins
        ).aggregate(total=Coalesce(Sum('stock_actuel'), 0))['total']

    def get_offer_id(self, obj):
        sub = self._subscription(obj)
        return sub.offer_id if sub else None

    def get_offer_name(self, obj):
        sub = self._subscription(obj)
        return sub.offer.name if sub and sub.offer else None

    def get_max_devices(self, obj):
        sub = self._subscription(obj)
        return sub.max_devices if sub else Subscription.DEFAULT_DEVICE_LIMIT

    def get_device_count(self, obj):
        return Device.objects.filter(admin_profile=obj).count()


class LoginEventSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source="user.full_name", read_only=True)
    user_email = serializers.CharField(source="user.email", read_only=True)
    user_role = serializers.CharField(source="user.role", read_only=True)

    class Meta:
        model = LoginEvent
        fields = ["id", "user_name", "user_email", "user_role", "ip_address", "user_agent", "created_at"]


class DeviceSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source="user.full_name", read_only=True)
    user_email = serializers.CharField(source="user.email", read_only=True)
    user_role = serializers.CharField(source="user.role", read_only=True)

    class Meta:
        model = Device
        fields = [
            "id", "user_name", "user_email", "user_role", "label",
            "ip_address", "user_agent", "first_seen", "last_seen",
        ]


class SubscriptionOfferSerializer(serializers.ModelSerializer):
    subscriptions_count = serializers.SerializerMethodField()

    class Meta:
        model = SubscriptionOffer
        fields = ["id", "name", "price", "max_devices", "duration_months", "is_active", "subscriptions_count", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]

    def get_subscriptions_count(self, obj):
        return obj.subscriptions.count()

    def validate_name(self, value):
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("Le nom de l'offre est obligatoire.")
        return value

    def validate_price(self, value):
        if value is None or value < 0:
            raise serializers.ValidationError("Le prix doit être un nombre positif.")
        return value

    def validate_max_devices(self, value):
        if value is None or value < 1:
            raise serializers.ValidationError("Le nombre d'appareils connectés doit être au moins 1.")
        return value


class PlatformRequestSerializer(serializers.ModelSerializer):
    company_name = serializers.CharField(source="admin_profile.company_name", read_only=True)
    admin_profile_id = serializers.IntegerField(source="admin_profile.id", read_only=True)
    requested_by_name = serializers.CharField(source="requested_by.full_name", read_only=True)
    requested_by_email = serializers.CharField(source="requested_by.email", read_only=True)
    device_info = serializers.SerializerMethodField()
    offer_name = serializers.SerializerMethodField()
    payment_method_label = serializers.CharField(source="get_payment_method_display", read_only=True)

    class Meta:
        model = PlatformRequest
        fields = [
            "id", "request_type", "status", "note", "admin_profile_id", "company_name",
            "requested_by_name", "requested_by_email", "device_info", "offer_name",
            "payment_method", "payment_method_label", "payment_reference", "contact_email",
            "created_at", "resolved_at",
        ]
        read_only_fields = ["id", "status", "created_at", "resolved_at"]

    def get_offer_name(self, obj):
        return obj.offer.name if obj.offer else None

    def get_device_info(self, obj):
        if obj.device:
            return {
                "device_id": obj.device_id,
                "ip_address": obj.device.ip_address,
                "user_agent": obj.device.user_agent,
            }
        if obj.login_event:
            return {
                "login_event_id": obj.login_event_id,
                "ip_address": obj.login_event.ip_address,
                "user_agent": obj.login_event.user_agent,
            }
        return None


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
