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
    )

    full_name = models.CharField(max_length=255)
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20,blank=True,null=True)
    adresse = models.CharField(max_length=255, blank=True, null=True)
    photo = models.ImageField(upload_to="user_photos/", blank=True, null=True)
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
# LOGIN EVENT (audit trail: IP / user-agent per login, used for the
# "Actif il y a ..." online-status display)
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
# EMPLOYEE PASSWORD RESET REQUEST (magasin/employer -> admin)
# =====================================================

class EmployeePasswordResetRequest(models.Model):
    """Forgot-password request from a magasin or employer account, routed to
    the admin(s) of their société for approval."""

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


class CaisseCategory(models.Model):
    """Catégorie de dépense pour les mouvements de caisse "Sortie" (Salaire,
    Pub, Commande stock, Autre...) — gérée en CRUD dans Paramètres, partagée
    par toute la société (pas par magasin) puisqu'il s'agit d'une
    classification comptable, pas d'un réglage propre à un point de vente."""

    admin_profile = models.ForeignKey("AdminProfile", on_delete=models.CASCADE, related_name="caisse_categories")
    nom = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Catégorie de dépense"
        verbose_name_plural = "Catégories de dépense"
        ordering = ["nom"]
        unique_together = ("admin_profile", "nom")

    def __str__(self):
        return self.nom


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
    # Uniquement pour les sorties (dépenses) — voir CaisseCategory.
    category = models.ForeignKey(CaisseCategory, on_delete=models.SET_NULL, null=True, blank=True, related_name="movements")
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

