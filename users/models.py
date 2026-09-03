from django.db import models
from django.contrib.auth.models import AbstractUser
from django.contrib.auth.base_user import BaseUserManager
from django.utils import timezone


# =====================================================
# CUSTOM USER MANAGER
# =====================================================

class CustomUserManager(BaseUserManager):

    def create_user(self,email,password=None,**extra_fields):
        if not email:
            raise ValueError("L'email est obligatoire")
        email = self.normalize_email(email)

        user = self.model(
            email=email,
            username=email,
            **extra_fields
        )

        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self,email,password=None,**extra_fields):

        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("is_active", True)
        extra_fields.setdefault("is_confirmed", True)
        extra_fields.setdefault("role", "admin")

        user = self.create_user(
            email,
            password,
            **extra_fields
        )

        return user


# =====================================================
# CUSTOM USER
# =====================================================

class CustomUser(AbstractUser):

    ROLE_CHOICES = (
        ("admin", "Admin"),
        ("magasin", "Magasin"),
        ("employer", "Employer"),
        ("platform_admin", "Platform Admin"),
    )

    full_name = models.CharField(max_length=255)
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20,blank=True,null=True)
    role = models.CharField(max_length=20,choices=ROLE_CHOICES,default="employer")
    is_confirmed = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True )
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []
    objects = CustomUserManager()
    def save(self, *args, **kwargs):

        # Admin accès Django Admin
        if self.role == "admin":
            self.is_staff = True

        # Magasin / Employer
        else:
            self.is_staff = False

        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.full_name} ({self.role})"


# =====================================================
# ADMIN PROFILE
# =====================================================

class AdminProfile(models.Model):

    user = models.OneToOneField(CustomUser,on_delete=models.CASCADE,related_name="admin_profile",limit_choices_to={"role": "admin"})
    company_name = models.CharField(max_length=255)
    logo = models.ImageField(upload_to="company_logo/",blank=True,null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    class Meta:
        verbose_name = "Admin Profile"
        verbose_name_plural = "Admin Profiles"

    def __str__(self):
        return self.company_name


# =====================================================
# SUBSCRIPTION OFFER (Label Technology plan catalog)
# =====================================================

class SubscriptionOffer(models.Model):

    name = models.CharField(max_length=255)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    max_devices = models.PositiveIntegerField(default=1)
    duration_months = models.PositiveIntegerField(default=1, help_text="Durée de l'offre en mois (1, 2, 3...)")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Offre d'abonnement"
        verbose_name_plural = "Offres d'abonnement"
        ordering = ["price"]

    def __str__(self):
        return f"{self.name} ({self.price})"


# =====================================================
# SUBSCRIPTION (Label Technology billing/status)
# =====================================================

class Subscription(models.Model):

    STATUS_CHOICES = (
        ("active", "Actif"),
        ("disabled", "Désactivé"),
        ("pending", "En attente"),
        ("trial", "Essai (1 mois)"),
        ("demo", "Démo"),
    )

    DEFAULT_DEVICE_LIMIT = 3

    admin_profile = models.OneToOneField(AdminProfile, on_delete=models.CASCADE, related_name="subscription")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="pending")
    offer = models.ForeignKey(SubscriptionOffer, on_delete=models.SET_NULL, null=True, blank=True, related_name="subscriptions")
    trial_ends_at = models.DateTimeField(null=True, blank=True)
    updated_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="subscription_updates")
    notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Subscription"
        verbose_name_plural = "Subscriptions"

    def __str__(self):
        return f"{self.admin_profile.company_name} - {self.status}"

    @property
    def is_currently_active(self):
        if self.status in ("active", "demo"):
            return True
        if self.status == "trial":
            return bool(self.trial_ends_at and self.trial_ends_at > timezone.now())
        return False

    @property
    def days_left_in_trial(self):
        if self.status != "trial" or not self.trial_ends_at:
            return None
        return max(0, (self.trial_ends_at - timezone.now()).days)

    @property
    def max_devices(self):
        if self.offer:
            return self.offer.max_devices
        return self.DEFAULT_DEVICE_LIMIT


# =====================================================
# LOGIN EVENT (IP / device tracking for Label Technology)
# =====================================================

class LoginEvent(models.Model):

    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="login_events")
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.CharField(max_length=500, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    # Set when the frontend explicitly calls the logout endpoint (best-effort:
    # JWT sessions have no server-side invalidation, so this only reflects an
    # actual click on "Déconnexion", not token expiry or closing the tab).
    logged_out_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.user.email} - {self.ip_address} - {self.created_at}"


# =====================================================
# PLATFORM REQUEST (tenant -> Label Technology)
# =====================================================

class PlatformRequest(models.Model):

    REQUEST_TYPES = (
        ("device_deletion", "Suppression d'appareil"),
        ("activation", "Activation d'abonnement"),
        ("payment", "Paiement direct"),
        ("password_reset", "Réinitialisation de mot de passe"),
    )
    STATUS_CHOICES = (
        ("pending", "En attente"),
        ("approved", "Approuvée"),
        ("rejected", "Rejetée"),
    )
    PAYMENT_METHOD_CHOICES = (
        ("mvola", "MVola"),
        ("paypal", "PayPal"),
        ("visa", "Visa"),
        ("mastercard", "Mastercard"),
    )

    request_type = models.CharField(max_length=20, choices=REQUEST_TYPES)
    admin_profile = models.ForeignKey(AdminProfile, on_delete=models.CASCADE, related_name="requests")
    requested_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, related_name="platform_requests")
    login_event = models.ForeignKey(LoginEvent, on_delete=models.SET_NULL, null=True, blank=True, related_name="deletion_requests")
    device = models.ForeignKey("Device", on_delete=models.SET_NULL, null=True, blank=True, related_name="deletion_requests")
    offer = models.ForeignKey(SubscriptionOffer, on_delete=models.SET_NULL, null=True, blank=True, related_name="payment_requests")
    payment_method = models.CharField(max_length=20, choices=PAYMENT_METHOD_CHOICES, blank=True, null=True)
    # Meaning depends on payment_method: MVola phone number, PayPal account
    # email, or cardholder name for Visa/Mastercard (raw card number/CVV are
    # never collected here — there is no PCI-compliant gateway behind this
    # yet, see PublicPaymentRequestView).
    payment_reference = models.CharField(max_length=255, blank=True, null=True)
    contact_email = models.EmailField(blank=True, null=True)
    note = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="pending")
    resolved_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="resolved_requests")
    resolved_at = models.DateTimeField(null=True, blank=True)
    # Set once the requester has actually used an approved password_reset
    # request to set a new password, so it can't be replayed.
    consumed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"[{self.get_request_type_display()}] {self.admin_profile.company_name} - {self.status}"


# =====================================================
# EMPLOYEE PASSWORD RESET REQUEST (magasin/employer -> admin)
# =====================================================

class EmployeePasswordResetRequest(models.Model):
    """Forgot-password request from a magasin or employer account, routed to
    the admin(s) of their société for approval (as opposed to admin accounts
    themselves, whose forgot-password requests go to Label Technology via
    PlatformRequest)."""

    STATUS_CHOICES = (
        ("pending", "En attente"),
        ("approved", "Approuvée"),
        ("rejected", "Rejetée"),
    )

    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="password_reset_requests")
    admin = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="employee_password_reset_requests", limit_choices_to={"role": "admin"})
    magasin = models.ForeignKey("MagasinProfile", on_delete=models.SET_NULL, null=True, blank=True, related_name="password_reset_requests")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="pending")
    resolved_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="resolved_employee_password_resets")
    resolved_at = models.DateTimeField(null=True, blank=True)
    consumed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Réinitialisation - {self.user.email} - {self.status}"


# =====================================================
# DEVICE (registered device slot, counted against the
# subscription's offer device limit)
# =====================================================

class Device(models.Model):

    admin_profile = models.ForeignKey(AdminProfile, on_delete=models.CASCADE, related_name="devices")
    user = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="devices")
    device_id = models.CharField(max_length=100)
    label = models.CharField(max_length=255, blank=True, null=True)
    user_agent = models.CharField(max_length=500, blank=True, null=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    # Exact (GPS/browser-provided) location captured at login time, via the
    # browser's Geolocation API — best-effort, only present if the user
    # granted permission. Kept from the last login where it was provided
    # (not cleared by a later login that didn't supply one).
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    first_seen = models.DateTimeField(auto_now_add=True)
    last_seen = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Appareil connecté"
        verbose_name_plural = "Appareils connectés"
        unique_together = ("admin_profile", "device_id")
        ordering = ["-last_seen"]

    def __str__(self):
        return f"{self.label or self.device_id} - {self.admin_profile.company_name}"


# =====================================================
# MAGASIN PROFILE
# =====================================================

class MagasinProfile(models.Model):

    user = models.OneToOneField(CustomUser, on_delete=models.CASCADE, related_name="magasin_profile", limit_choices_to={"role": "magasin"}, null=True, blank=True)
    admins = models.ManyToManyField(CustomUser, related_name="admin_magasin_profiles", blank=True, limit_choices_to={"role": "admin"})
    # Keep existing primary admin for backward compatibility
    admin = models.ForeignKey(CustomUser,on_delete=models.CASCADE,related_name="magasins",limit_choices_to={"role": "admin"})
    shop_name = models.CharField(max_length=255)
    description = models.CharField(max_length=255, blank=True, null=True)
    shop_logo = models.ImageField(upload_to="shop_logo/",blank=True,null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Magasin Profile"
        verbose_name_plural = "Magasin Profiles"

    def __str__(self):
        return self.shop_name


# =====================================================
# EMPLOYER PROFILE
# =====================================================

class EmployerProfile(models.Model):

    user = models.OneToOneField(CustomUser,on_delete=models.CASCADE,related_name="employer_profile",limit_choices_to={"role": "employer"})
    magasin = models.ForeignKey(MagasinProfile,on_delete=models.CASCADE,related_name="employers",null=True,blank=True)
    admin = models.ForeignKey(CustomUser,on_delete=models.CASCADE,related_name="admin_employers",limit_choices_to={"role": "admin"},null=True,blank=True)
    position = models.CharField(max_length=255)
    # Sous-rôle dans le module Commande (Smartreadme.md §4/§5) : Préparateur
    # ou Livreur. Séparé de `position` (texte libre déjà utilisé pour
    # d'autres intitulés de poste) pour ne rien casser côté usages existants
    # — ce champ pilote uniquement les permissions du module Commande.
    COMMANDE_ROLE_CHOICES = (
        ("PREPARATEUR", "Préparateur"),
        ("LIVREUR", "Livreur"),
    )
    commande_role = models.CharField(max_length=20, choices=COMMANDE_ROLE_CHOICES, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Employer Profile"
        verbose_name_plural = "Employer Profiles"

    def __str__(self):
        return f"{self.user.full_name} - {self.position}"




class Notification(models.Model):
    NOTIF_TYPES = (
        ("order", "Commande"),
        ("supplier_order", "Commande fournisseur"),
        ("user", "User"),
        ("chat", "Chat"),
        ("caisse", "Caisse"),
        ("other", "Other"),
    )

    notif_type = models.CharField(max_length=20, choices=NOTIF_TYPES, default="other")
    message = models.TextField()
    # optional relations
    magasin = models.ForeignKey(MagasinProfile, on_delete=models.CASCADE, null=True, blank=True, related_name="notifications")
    caisse_session = models.ForeignKey('CaisseSession', on_delete=models.CASCADE, null=True, blank=True, related_name="notifications")
    user = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="notifications")

    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"[{self.get_notif_type_display()}] {self.message[:60]}"


class CaisseSession(models.Model):
    """Session de caisse pour un magasin : ouverte avec un fond de départ,
    fermée avec un montant compté. Un magasin ne peut avoir qu'une session
    `open` à la fois (contrainte applicative, voir CaisseSessionViewSet.open)."""

    STATUS_CHOICES = (
        ("open", "Ouverte"),
        ("closed", "Fermée"),
    )

    magasin = models.ForeignKey(MagasinProfile, on_delete=models.CASCADE, related_name="caisse_sessions")
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default="open")
    opened_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="caisse_sessions_opened")
    closed_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="caisse_sessions_closed")
    opening_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    closing_balance = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    # Calculés à la fermeture : opening_balance + mouvements entrée - mouvements sortie,
    # puis écart avec le montant réellement compté (closing_balance).
    expected_balance = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    difference = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    opening_note = models.CharField(max_length=255, blank=True, null=True)
    closing_note = models.CharField(max_length=255, blank=True, null=True)
    # Not auto_now_add: the gérant can backdate the real opening/closing time
    # (e.g. the caisse physically opened at 8h but was only recorded in the
    # app at 10h) — see CaisseSessionViewSet.open()/close(). Still defaults
    # to "now" when not provided explicitly.
    opened_at = models.DateTimeField(default=timezone.now)
    closed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "Session de caisse"
        verbose_name_plural = "Sessions de caisse"
        ordering = ["-opened_at"]

    def __str__(self):
        return f"Caisse {self.magasin.shop_name} - {self.opened_at:%d/%m/%Y %H:%M}"


class CaisseMovement(models.Model):
    """Mouvement d'espèces (apport, retrait, dépense...) au sein d'une
    session de caisse — distinct de `catalog.StockMovement` qui suit le stock produit."""

    MOVEMENT_TYPES = (
        ("in", "Entrée"),
        ("out", "Sortie"),
    )

    session = models.ForeignKey(CaisseSession, on_delete=models.CASCADE, related_name="movements")
    magasin = models.ForeignKey(MagasinProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name="caisse_movements")
    movement_type = models.CharField(max_length=10, choices=MOVEMENT_TYPES)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reason = models.CharField(max_length=255)
    created_by = models.ForeignKey(CustomUser, on_delete=models.SET_NULL, null=True, blank=True, related_name="caisse_movements")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Mouvement de caisse"
        verbose_name_plural = "Mouvements de caisse"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.get_movement_type_display()} {self.amount} - session #{self.session_id}"


class ChatMessage(models.Model):
    sender = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="sent_chat_messages")
    recipient = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="received_chat_messages", null=True, blank=True)
    room_name = models.CharField(max_length=100, default="general")
    content = models.TextField()
    is_edited = models.BooleanField(default=False)
    edited_at = models.DateTimeField(null=True, blank=True)
    is_deleted = models.BooleanField(default=False)
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["timestamp"]

    def __str__(self):
        recipient_str = self.recipient.email if self.recipient else "General"
        return f"{self.sender.email} -> {recipient_str}: {self.content[:30]}"

