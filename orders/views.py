from django.core.exceptions import PermissionDenied, ValidationError
from django.utils.dateparse import parse_datetime
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied as DRFPermissionDenied
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from users.models import EmployerProfile
from users.permissions import (
    IsGerant,
    get_accessible_magasins,
    resolve_magasin_for_request,
    user_commande_role,
)
from users.subscriptions import get_company_owner

from . import services
from .models import DeliveryZoneOption, Order
from .serializers import (
    DeliveryZoneOptionSerializer,
    OrderCreateSerializer,
    OrderGerantSerializer,
    OrderLivreurSerializer,
    OrderPreparateurSerializer,
    OrderStatusChangeSerializer,
    OrderUpdateSerializer,
)

# Statuts visibles par rôle sur leur module dédié (§7.2, §7.3 Smartreadme.md) —
# uniquement parmi les commandes déjà assignées à SON nom (voir get_queryset,
# § demande). Le livreur voit aussi "En préparation" (visibilité/planning —
# pas encore actionnable pour lui, § demande), en plus de ses statuts habituels.
PREPARATEUR_STATUTS = ["NOUVELLE", "EN_PREPARATION"]
LIVREUR_STATUTS = ["EN_PREPARATION", "PRETE", "EN_LIVRAISON"]


# Défauts pour une société qui n'a encore aucune zone (nouvelle société —
# les sociétés déjà existantes au moment de l'introduction du CRUD ont été
# seedées une fois pour toutes avec leurs 3 zones historiques, voir migration
# 0010_seed_legacy_delivery_zones ; on ne leur ajoute pas la zone gratuite
# ci-dessous automatiquement pour ne pas modifier leurs données sans le leur
# demander — § demande, "ne pas toucher aux données existantes"). Toujours
# au moins une zone à prix 0 pour les nouvelles sociétés (§ demande).
DEFAULT_DELIVERY_ZONES = [
    ("Zone gratuite", 0),
    ("Zone 1", 3000),
    ("Zone 2", 4000),
    ("Zone 3", 5000),
]


class DeliveryZoneOptionViewSet(viewsets.ModelViewSet):
    """Zones de livraison (nom + prix) — CRUD dans Paramètres (§ demande),
    partagées par toute la société comme CaisseCategory (voir users/views.py::
    CaisseCategoryViewSet, même schéma). Lecture ouverte à tous (nécessaire
    pour peupler le select à la création d'une commande), écriture réservée
    au gérant."""

    serializer_class = DeliveryZoneOptionSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_permissions(self):
        if self.action in ("create", "partial_update", "update", "destroy"):
            return [IsGerant()]
        return super().get_permissions()

    def get_queryset(self):
        owner = get_company_owner(self.request.user)
        admin_profile = getattr(owner, "admin_profile", None) if owner else None
        if not admin_profile:
            return DeliveryZoneOption.objects.none()

        if not admin_profile.delivery_zones.exists():
            for nom, prix in DEFAULT_DELIVERY_ZONES:
                DeliveryZoneOption.objects.create(admin_profile=admin_profile, nom=nom, prix=prix)
        return admin_profile.delivery_zones.all()

    def perform_create(self, serializer):
        owner = get_company_owner(self.request.user)
        admin_profile = getattr(owner, "admin_profile", None) if owner else None
        if not admin_profile:
            raise DRFValidationError("Société introuvable.")
        serializer.save(admin_profile=admin_profile)

    def destroy(self, request, *args, **kwargs):
        zone = self.get_object()
        in_use = Order.objects.filter(
            magasin__admin__admin_profile=zone.admin_profile, livraison_zone=zone.code
        ).exists()
        if in_use:
            # Une zone déjà utilisée par des commandes n'est pas supprimée —
            # ça casserait la résolution de leurs frais de livraison (voir
            # Order.save()). On la désactive à la place : elle disparaît des
            # nouveaux choix mais reste résolue pour les commandes existantes.
            zone.actif = False
            zone.save(update_fields=["actif"])
            return Response(self.get_serializer(zone).data)
        return super().destroy(request, *args, **kwargs)


class OrderViewSet(viewsets.ModelViewSet):
    # patch/delete : uniquement tant que la commande est "Nouvelle" (rien
    # préparé/déduit du stock) — cf. partial_update/destroy ci-dessous.
    # Statut/affectation passent toujours exclusivement par /status/.
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action in ("available_staff", "partial_update", "destroy"):
            return [IsGerant()]
        return super().get_permissions()

    def get_serializer_class(self):
        if self.action == "create":
            return OrderCreateSerializer
        if self.action == "partial_update":
            return OrderUpdateSerializer
        role = user_commande_role(self.request.user)
        if role == "PREPARATEUR":
            return OrderPreparateurSerializer
        if role == "LIVREUR":
            return OrderLivreurSerializer
        return OrderGerantSerializer

    def get_queryset(self):
        qs = Order.objects.filter(magasin__in=get_accessible_magasins(self.request.user)).prefetch_related(
            "items", "items__product_variant__product_reference", "status_history"
        )
        role = user_commande_role(self.request.user)

        if role in ("PREPARATEUR", "LIVREUR"):
            if self.request.query_params.get("historique"):
                # Historique personnel : toutes les commandes déjà désignées
                # à cet utilisateur, tous statuts confondus, filtrables par
                # date ET heure (§ demande) — pas de restriction "jour J" ici,
                # c'est un journal, pas la file d'attente du jour.
                qs = qs.filter(preparateur=self.request.user) if role == "PREPARATEUR" else qs.filter(livreur=self.request.user)
                date_from = self.request.query_params.get("date_from")
                date_to = self.request.query_params.get("date_to")
                parsed_from = parse_datetime(date_from) if date_from else None
                parsed_to = parse_datetime(date_to) if date_to else None
                if parsed_from:
                    qs = qs.filter(date_commande__gte=parsed_from)
                if parsed_to:
                    qs = qs.filter(date_commande__lte=parsed_to)
                return qs.order_by("-date_commande")

            # Ni préparateur ni livreur ne voit une action bloquée par le
            # "jour J" comme un problème de visibilité : la commande reste
            # affichée à l'avance (planning), seule l'action est retardée
            # côté services.change_order_status. Seules les commandes déjà
            # assignées à SON nom apparaissent ici (§ demande) — une commande
            # pas encore assignée reste invisible tant que le gérant ne l'a
            # pas confiée explicitement à ce préparateur/livreur.
            if role == "PREPARATEUR":
                # + les récupérations sur place déjà prêtes (pas de livreur
                # pour ce cas — le préparateur en garde le suivi jusqu'au
                # retrait, validé par le gérant sur la page Récupération).
                base = qs.filter(
                    preparateur=self.request.user, statut_courant__in=PREPARATEUR_STATUTS
                ) | qs.filter(
                    preparateur=self.request.user, statut_courant="PRETE", livraison_zone="RECUPERATION"
                )
            else:
                # Prêtes à récupérer + en livraison (§7.3 Smartreadme.md) — hors
                # retrait sur place, qui ne passe jamais par un livreur.
                base = qs.filter(livreur=self.request.user, statut_courant__in=LIVREUR_STATUTS).exclude(
                    statut_courant="PRETE", livraison_zone="RECUPERATION"
                )

            # Filtres optionnels statut/date (§ demande — page livreur), sans
            # sortir de l'ensemble de statuts déjà autorisé pour ce rôle.
            statut = self.request.query_params.get("statut")
            date_debut = self.request.query_params.get("date_debut")
            date_fin = self.request.query_params.get("date_fin")
            if statut:
                base = base.filter(statut_courant=statut)
            if date_debut:
                base = base.filter(date_commande__date__gte=date_debut)
            if date_fin:
                base = base.filter(date_commande__date__lte=date_fin)
            return base

        # Gérant : filtres optionnels date / statut / magasin / zone / préparateur (§7.1 Smartreadme.md).
        statut = self.request.query_params.get("statut")
        date_debut = self.request.query_params.get("date_debut")
        date_fin = self.request.query_params.get("date_fin")
        magasin_id = self.request.query_params.get("magasin_id")
        livraison_zone = self.request.query_params.get("livraison_zone")
        preparateur_id = self.request.query_params.get("preparateur_id")
        if statut:
            qs = qs.filter(statut_courant=statut)
        if livraison_zone:
            qs = qs.filter(livraison_zone=livraison_zone)
        if date_debut:
            # `__date` : date_commande est un datetime — comparer uniquement
            # la date pour que date_fin inclue toute la journée (pas juste minuit).
            qs = qs.filter(date_commande__date__gte=date_debut)
        if date_fin:
            qs = qs.filter(date_commande__date__lte=date_fin)
        if magasin_id:
            qs = qs.filter(magasin_id=magasin_id)
        if preparateur_id:
            qs = qs.filter(preparateur_id=preparateur_id)
        return qs

    def create(self, request, *args, **kwargs):
        role = user_commande_role(request.user)
        if role not in ("GERANT", "PREPARATEUR"):
            raise DRFPermissionDenied("Seuls le gérant et le préparateur peuvent créer une commande.")

        serializer = OrderCreateSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        if role == "PREPARATEUR" and data["livraison_zone"] != "RECUPERATION":
            raise DRFValidationError(
                "Le préparateur ne peut créer que des commandes 'Récupération sur place'."
            )

        magasin = resolve_magasin_for_request(request)

        order = services.create_order(
            magasin=magasin,
            client_nom=data["client_nom"],
            telephone=data["telephone"],
            livraison_zone=data["livraison_zone"],
            adresse_livraison=data.get("adresse_livraison", ""),
            mode_paiement=data.get("mode_paiement", "LIVRAISON"),
            items=data["items"],
            note_preparateur=data.get("note_preparateur", ""),
            note_livreur=data.get("note_livreur", ""),
            date_commande=data.get("date_commande"),
            created_by=request.user,
            preparateur=request.user if role == "PREPARATEUR" else None,
        )
        response_serializer = OrderPreparateurSerializer if role == "PREPARATEUR" else OrderGerantSerializer
        return Response(response_serializer(order).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        order = self.get_object()
        serializer = OrderUpdateSerializer(data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        data = dict(serializer.validated_data)
        try:
            order = services.update_order(order=order, user=request.user, **data)
        except ValidationError as exc:
            raise DRFValidationError(str(exc))
        return Response(OrderGerantSerializer(order).data)

    def destroy(self, request, *args, **kwargs):
        order = self.get_object()
        if order.statut_courant != "NOUVELLE":
            raise DRFValidationError(
                "Seule une commande 'Nouvelle' peut être supprimée — le stock ou une "
                "affectation est déjà engagé sur celle-ci."
            )
        order.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="status")
    def change_status(self, request, pk=None):
        order = self.get_object()
        serializer = OrderStatusChangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        try:
            order = services.change_order_status(
                order=order,
                new_status=serializer.validated_data["statut"],
                user=request.user,
                note=serializer.validated_data.get("note", ""),
                preparateur_id=serializer.validated_data.get("preparateur_id"),
                livreur_id=serializer.validated_data.get("livreur_id"),
                assigned_at=serializer.validated_data.get("assigned_at"),
                photo=serializer.validated_data.get("photo"),
            )
        except PermissionDenied as exc:
            raise DRFPermissionDenied(str(exc))
        except ValidationError as exc:
            raise DRFValidationError(str(exc))

        return Response(self.get_serializer(order).data)

    @action(detail=True, methods=["post"], url_path="assign-livreur")
    def assign_livreur(self, request, pk=None):
        """POST /api/orders/{id}/assign-livreur/ {livreur_id} — pré-assigne
        un livreur avant que la commande soit Prête (gérant uniquement), sans
        changer son statut. Voir services.assign_livreur_early."""
        order = self.get_object()
        livreur_id = request.data.get("livreur_id")
        if not livreur_id:
            raise DRFValidationError("livreur_id requis.")
        try:
            order = services.assign_livreur_early(order=order, livreur_id=livreur_id, user=request.user)
        except PermissionDenied as exc:
            raise DRFPermissionDenied(str(exc))
        except ValidationError as exc:
            raise DRFValidationError(str(exc))

        return Response(self.get_serializer(order).data)

    @action(detail=True, methods=["post"], url_path="assign-preparateur")
    def assign_preparateur(self, request, pk=None):
        """POST /api/orders/{id}/assign-preparateur/ {preparateur_id} —
        pré-assigne un préparateur sans faire progresser le statut (gérant
        uniquement) : la commande reste "Nouvelle" jusqu'à ce que le
        préparateur clique lui-même "Commencer la préparation" (§ demande).
        Voir services.assign_preparateur_early."""
        order = self.get_object()
        preparateur_id = request.data.get("preparateur_id")
        if not preparateur_id:
            raise DRFValidationError("preparateur_id requis.")
        try:
            order = services.assign_preparateur_early(order=order, preparateur_id=preparateur_id, user=request.user)
        except PermissionDenied as exc:
            raise DRFPermissionDenied(str(exc))
        except ValidationError as exc:
            raise DRFValidationError(str(exc))

        return Response(self.get_serializer(order).data)

    @action(detail=True, methods=["post"], url_path="cancel")
    def cancel(self, request, pk=None):
        """POST /api/orders/{id}/cancel/ — annulation gérant (restitue le
        stock si déjà déduit). Voir services.cancel_order."""
        order = self.get_object()
        try:
            order = services.cancel_order(
                order=order, user=request.user, note=request.data.get("note", ""),
            )
        except PermissionDenied as exc:
            raise DRFPermissionDenied(str(exc))
        except ValidationError as exc:
            raise DRFValidationError(str(exc))

        return Response(self.get_serializer(order).data)

    @action(detail=False, methods=["get"], url_path="available-staff")
    def available_staff(self, request):
        """GET /api/orders/available-staff/?role=PREPARATEUR|LIVREUR&magasin_id=&date_commande=
        Liste les préparateurs/livreurs du magasin avec leur disponibilité,
        pour le sélecteur d'affectation du gérant (occupé = déjà en charge
        d'une commande En préparation / En livraison). Pour LIVREUR, un
        `date_commande` (ISO datetime) optionnel signale aussi un conflit
        d'horaire avec une autre commande déjà (pré-)assignée à ce livreur le
        même jour, à la même heure — voir services.livreur_has_time_conflict.
        Purement indicatif : `available=False` n'empêche pas la sélection."""
        requested_role = request.query_params.get("role")
        if requested_role not in ("PREPARATEUR", "LIVREUR"):
            raise DRFValidationError("Paramètre 'role' requis : PREPARATEUR ou LIVREUR.")

        magasins = get_accessible_magasins(request.user)
        magasin_id = request.query_params.get("magasin_id")
        if magasin_id:
            magasins = magasins.filter(id=magasin_id)

        busy_check = services.is_preparateur_busy if requested_role == "PREPARATEUR" else services.is_livreur_busy
        employers = EmployerProfile.objects.filter(
            magasin__in=magasins, commande_role=requested_role
        ).select_related("user")

        date_commande = None
        if requested_role == "LIVREUR":
            date_commande = parse_datetime(request.query_params.get("date_commande") or "")

        return Response([
            {
                "id": ep.user_id,
                "full_name": ep.user.full_name,
                "magasin_id": ep.magasin_id,
                "available": not (
                    busy_check(ep.user)
                    or (date_commande and services.livreur_has_time_conflict(ep.user, date_commande))
                ),
            }
            for ep in employers
        ])
