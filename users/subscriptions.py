import re

from django.db.models import Q

from .models import MagasinProfile, EmployerProfile, LoginEvent, Device, Subscription

BLOCKED_MESSAGE = "Abonnement inactif, contactez Label Technology."


def get_client_ip(request):
    forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR")


def parse_device_name(user_agent):
    """Best-effort, dependency-free "Browser sur OS" label from a raw
    User-Agent string (e.g. "Chrome sur Windows", "Safari sur iPhone")."""
    if not user_agent:
        return "Appareil inconnu"
    ua = user_agent

    if "iPhone" in ua:
        os_name = "iPhone"
    elif "iPad" in ua:
        os_name = "iPad"
    elif "Android" in ua:
        m = re.search(r"Android\s([0-9.]+)", ua)
        os_name = f"Android {m.group(1)}" if m else "Android"
    elif "Windows NT" in ua:
        os_name = "Windows"
    elif "Mac OS X" in ua:
        os_name = "macOS"
    elif "Linux" in ua:
        os_name = "Linux"
    else:
        os_name = None

    if "Edg/" in ua or "Edge/" in ua:
        browser = "Edge"
    elif "OPR/" in ua or "Opera" in ua:
        browser = "Opera"
    elif "Chrome/" in ua and "Chromium" not in ua:
        browser = "Chrome"
    elif "Firefox/" in ua:
        browser = "Firefox"
    elif "Safari/" in ua and "Chrome" not in ua:
        browser = "Safari"
    else:
        browser = None

    if browser and os_name:
        return f"{browser} sur {os_name}"
    return browser or os_name or "Appareil inconnu"


def get_subscription_owner(user):
    """Resolve the CustomUser (role=admin) whose AdminProfile.subscription
    governs this user's login, for admin/magasin/employer roles."""
    if not user or not user.is_authenticated:
        return None

    if user.role == "admin":
        magasin = (
            MagasinProfile.objects.filter(Q(admin=user) | Q(admins=user))
            .order_by("created_at")
            .first()
        )
        return magasin.admin if magasin else user

    if user.role == "magasin":
        mp = getattr(user, "magasin_profile", None)
        return mp.admin if mp else None

    if user.role == "employer":
        ep = getattr(user, "employer_profile", None)
        if not ep:
            return None
        if ep.admin:
            return ep.admin
        if ep.magasin:
            return ep.magasin.admin
        return None

    return None


def get_subscription(user):
    owner = get_subscription_owner(user)
    if not owner:
        return None
    try:
        return owner.admin_profile.subscription
    except Exception:
        return None


def is_login_allowed(user):
    if user.role not in ("admin", "magasin", "employer"):
        return True
    sub = get_subscription(user)
    if sub is None:
        return False
    return sub.is_currently_active


def get_company_magasins(admin_user):
    """All MagasinProfile queryset owned or co-managed by admin_user."""
    return MagasinProfile.objects.filter(Q(admin=admin_user) | Q(admins=admin_user)).distinct()


def get_company_user_ids(admin_user):
    """All CustomUser ids belonging to the company owned by admin_user:
    the admin, co-admins, magasin users, and employers under those magasins."""
    ids = {admin_user.id}

    magasins = get_company_magasins(admin_user)
    for mp in magasins:
        ids.update(mp.admins.values_list("id", flat=True))
        if mp.user_id:
            ids.add(mp.user_id)

    magasin_ids = list(magasins.values_list("id", flat=True))
    employer_ids = EmployerProfile.objects.filter(
        Q(admin=admin_user) | Q(magasin_id__in=magasin_ids)
    ).values_list("user_id", flat=True)
    ids.update(employer_ids)

    return ids


def get_company_admin_ids(admin_user):
    """All CustomUser ids (role=admin) managing this company: the primary
    admin plus every co-admin on any of its magasins."""
    ids = {admin_user.id}
    for mp in get_company_magasins(admin_user):
        ids.add(mp.admin_id)
        ids.update(mp.admins.values_list("id", flat=True))
    return ids


def get_company_devices(admin_user, limit=20):
    """Most recent LoginEvent rows for every user of this company."""
    user_ids = get_company_user_ids(admin_user)
    return LoginEvent.objects.filter(user_id__in=user_ids).select_related("user")[:limit]


def get_or_register_device(user, device_id, ip_address, user_agent, latitude=None, longitude=None):
    """Resolve the registered-device slot for this login.

    latitude/longitude are the browser's Geolocation-API coordinates, sent
    by the frontend on a best-effort basis (only if the user granted
    permission). When absent, the device's last known location is kept
    as-is rather than being cleared.

    Returns (device, created, limit_exceeded):
    - device_id unknown/blank -> (None, False, False), device tracking skipped
      (e.g. platform_admin logins, or a client that hasn't sent an id yet).
    - already registered -> refreshes last_seen/ip/user_agent, (device, False, False)
    - new device, under the plan's limit -> registers it, (device, True, False)
    - new device, limit reached -> nothing is created, (None, False, True)
    """
    if not device_id:
        return None, False, False

    owner = get_subscription_owner(user)
    if not owner:
        return None, False, False

    admin_profile = getattr(owner, "admin_profile", None)
    if not admin_profile:
        return None, False, False

    device = Device.objects.filter(admin_profile=admin_profile, device_id=device_id).first()
    if device:
        device.user = user
        device.ip_address = ip_address
        device.user_agent = (user_agent or "")[:500]
        if latitude is not None and longitude is not None:
            device.latitude = latitude
            device.longitude = longitude
        device.save()
        return device, False, False

    sub = get_subscription(user)
    limit = sub.max_devices if sub else Subscription.DEFAULT_DEVICE_LIMIT
    current_count = Device.objects.filter(admin_profile=admin_profile).count()
    if current_count >= limit:
        return None, False, True

    device = Device.objects.create(
        admin_profile=admin_profile,
        user=user,
        device_id=device_id,
        user_agent=(user_agent or "")[:500],
        ip_address=ip_address,
        latitude=latitude,
        longitude=longitude,
    )
    return device, True, False


def get_device_limit_info(user):
    """Returns (current_count, limit) for the company owning `user`'s subscription."""
    owner = get_subscription_owner(user)
    if not owner:
        return 0, Subscription.DEFAULT_DEVICE_LIMIT
    admin_profile = getattr(owner, "admin_profile", None)
    if not admin_profile:
        return 0, Subscription.DEFAULT_DEVICE_LIMIT
    sub = get_subscription(user)
    limit = sub.max_devices if sub else Subscription.DEFAULT_DEVICE_LIMIT
    count = Device.objects.filter(admin_profile=admin_profile).count()
    return count, limit
