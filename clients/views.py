"""Vues de l'espace client : catalogue public (lecture seule, sans
authentification), compte client (JWT client) et commandes du client.

Toutes ces vues déclarent explicitement leurs classes d'authentification :
un jeton d'utilisateur interne n'y est jamais accepté, et un jeton client
n'est jamais accepté par les vues internes (voir clients/authentication.py).
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError

from catalog.models import Brand, Color, ProductCategory, ProductReference, ProductType
from orders.models import Order
from orders.services import annuler_commande_par_client
from users.models import MagasinProfile

from .authentication import ClientJWTAuthentication, refresh_access_for_client, tokens_for_client
from .models import Client
from .permissions import IsClient
from .serializers import (
    ClientChangePasswordSerializer,
    ClientLoginSerializer,
    ClientOrderCancelSerializer,
    ClientOrderCreateSerializer,
    ClientOrderSerializer,
    ClientOrderUpdateSerializer,
    ClientRefreshSerializer,
    ClientRegisterSerializer,
    ClientSerializer,
    PublicBoutiqueSerializer,
    PublicCategorieSerializer,
    PublicCouleurSerializer,
    PublicMarqueSerializer,
    PublicProduitSerializer,
    PublicSousTypeSerializer,
    PublicZoneSerializer,
)
from .services import create_client_order, update_client_order, zones_de_la_boutique


def _erreurs(exc):
    """ValidationError Django (services) -> corps 400 DRF."""
    if hasattr(exc, "message_dict"):
        return exc.message_dict
    return {"detail": exc.messages if hasattr(exc, "messages") else str(exc)}


# --------------------------------------------------------------------------- #
# Catalogue public
# --------------------------------------------------------------------------- #


class ProduitPagination(PageNumberPagination):
    page_size = 24
    page_size_query_param = "page_size"
    max_page_size = 100


class PublicMixin:
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "client_public"


def _filtre_boutique(request, qs, champ="magasin_id"):
    boutique = request.query_params.get("boutique")
    if boutique:
        qs = qs.filter(**{champ: boutique})
    return qs


class PublicBoutiqueListView(PublicMixin, APIView):
    """GET /api/boutiques/ — boutiques auprès desquelles un client peut commander."""

    def get(self, request):
        qs = MagasinProfile.objects.order_by("shop_name")
        return Response(PublicBoutiqueSerializer(qs, many=True, context={"request": request}).data)


class PublicBoutiqueZonesView(PublicMixin, APIView):
    """GET /api/boutiques/{id}/zones/ — zones de livraison actives (+ retrait
    sur place, code RECUPERATION) d'une boutique."""

    def get(self, request, pk):
        magasin = get_object_or_404(MagasinProfile, pk=pk)
        zones = PublicZoneSerializer(zones_de_la_boutique(magasin), many=True).data
        return Response({"boutique": magasin.id, "recuperation": {"code": "RECUPERATION", "nom": "Retrait sur place", "prix": 0}, "zones": zones})


class PublicCategorieListView(PublicMixin, APIView):
    """GET /api/categories/ (alias : GET /api/type/) — ?boutique=."""

    def get(self, request):
        qs = _filtre_boutique(request, ProductCategory.objects.all()).order_by("ordre", "nom")
        return Response(PublicCategorieSerializer(qs, many=True).data)


class PublicSousTypeListView(PublicMixin, APIView):
    """GET /api/sous-type/ — ?category= (ou ?categorie=), ?boutique=."""

    def get(self, request):
        qs = ProductType.objects.select_related("category")
        qs = _filtre_boutique(request, qs, "category__magasin_id")
        categorie = request.query_params.get("category") or request.query_params.get("categorie")
        if categorie:
            qs = qs.filter(category_id=categorie)
        return Response(PublicSousTypeSerializer(qs.order_by("nom"), many=True).data)


class PublicMarqueListView(PublicMixin, APIView):
    """GET /api/marque/ — ?boutique=."""

    def get(self, request):
        qs = _filtre_boutique(request, Brand.objects.all()).order_by("nom")
        return Response(PublicMarqueSerializer(qs, many=True).data)


class PublicCouleurListView(PublicMixin, APIView):
    """GET /api/couleurs/ — ?boutique=."""

    def get(self, request):
        qs = _filtre_boutique(request, Color.objects.all()).order_by("nom")
        return Response(PublicCouleurSerializer(qs, many=True).data)


class PublicProduitViewSet(PublicMixin, viewsets.ReadOnlyModelViewSet):
    """GET /api/produit/ et GET /api/produit/{id}/ — références ACTIVES du
    catalogue existant (source de vérité unique, aucun catalogue dupliqué),
    avec leurs couleurs et leur disponibilité. Filtres : search, category,
    type (= catégorie), sous_type, brand, couleur, available, min_price,
    max_price, boutique. Réponse paginée (page, page_size ≤ 100)."""

    serializer_class = PublicProduitSerializer
    pagination_class = ProduitPagination

    def get_queryset(self):
        p = self.request.query_params
        qs = (
            ProductReference.objects.filter(actif=True)
            .select_related("type__category__magasin", "brand")
            .prefetch_related("variants")
        )
        qs = _filtre_boutique(self.request, qs, "type__category__magasin_id")
        search = (p.get("search") or "").strip()
        if search:
            qs = qs.filter(
                Q(reference_name__icontains=search)
                | Q(brand__nom__icontains=search)
                | Q(type__nom__icontains=search)
                | Q(type__category__nom__icontains=search)
            )
        categorie = p.get("category") or p.get("categorie") or p.get("type")
        if categorie:
            qs = qs.filter(type__category_id=categorie)
        sous_type = p.get("sous_type")
        if sous_type:
            qs = qs.filter(type_id=sous_type)
        brand = p.get("brand") or p.get("marque")
        if brand:
            qs = qs.filter(brand_id=brand)
        couleur = (p.get("couleur") or "").strip()
        if couleur:
            qs = qs.filter(variants__couleur__iexact=couleur)
        if (p.get("available") or "").lower() in ("1", "true", "oui"):
            qs = qs.filter(variants__stock_actuel__gt=0)
        try:
            if p.get("min_price"):
                qs = qs.filter(prix_vente__gte=float(p["min_price"]))
            if p.get("max_price"):
                qs = qs.filter(prix_vente__lte=float(p["max_price"]))
        except ValueError:
            raise ValidationError({"detail": "min_price / max_price doivent être des nombres."})
        return qs.distinct().order_by("reference_name", "id")


# --------------------------------------------------------------------------- #
# Compte client
# --------------------------------------------------------------------------- #


class ClientAuthMixin:
    authentication_classes = [ClientJWTAuthentication]
    permission_classes = [IsClient]


class ClientRegisterView(APIView):
    """POST /api/client/register/ — crée le compte et renvoie les jetons."""

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "client_auth"

    def post(self, request):
        ser = ClientRegisterSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        client = ser.save()
        client.marquer_connexion()
        return Response(
            {"client": ClientSerializer(client).data, **tokens_for_client(client)},
            status=status.HTTP_201_CREATED,
        )


class ClientLoginView(APIView):
    """POST /api/client/login/ — e-mail + mot de passe -> jetons."""

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "client_auth"

    def post(self, request):
        ser = ClientLoginSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        email = ser.validated_data["email"].strip().lower()
        client = Client.objects.filter(email=email).first()
        # Même message dans tous les cas : ne révèle pas si l'e-mail existe.
        if client is None or not client.check_password(ser.validated_data["password"]):
            return Response({"detail": "E-mail ou mot de passe incorrect."}, status=status.HTTP_401_UNAUTHORIZED)
        if not client.is_active:
            return Response({"detail": "Compte désactivé."}, status=status.HTTP_403_FORBIDDEN)
        client.marquer_connexion()
        return Response({"client": ClientSerializer(client).data, **tokens_for_client(client)})


class ClientRefreshView(APIView):
    """POST /api/client/refresh/ — {refresh} -> {access}."""

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "client_auth"

    def post(self, request):
        ser = ClientRefreshSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            access = refresh_access_for_client(ser.validated_data["refresh"])
        except TokenError as e:
            return Response({"detail": f"Jeton invalide ou expiré : {e}"}, status=status.HTTP_401_UNAUTHORIZED)
        return Response({"access": access})


class ClientMeView(ClientAuthMixin, APIView):
    """GET / PATCH /api/client/me/ — profil du client connecté."""

    def get(self, request):
        return Response(ClientSerializer(request.user).data)

    def patch(self, request):
        ser = ClientSerializer(request.user, data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        ser.save()
        return Response(ser.data)


class ClientChangePasswordView(ClientAuthMixin, APIView):
    """POST /api/client/change-password/ — {ancien_mot_de_passe, nouveau_mot_de_passe}."""

    def post(self, request):
        ser = ClientChangePasswordSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        client = request.user
        if not client.check_password(ser.validated_data["ancien_mot_de_passe"]):
            return Response({"ancien_mot_de_passe": ["Mot de passe actuel incorrect."]}, status=status.HTTP_400_BAD_REQUEST)
        client.set_password(ser.validated_data["nouveau_mot_de_passe"])
        client.save(update_fields=["password", "updated_at"])
        return Response({"detail": "Mot de passe modifié."})


# --------------------------------------------------------------------------- #
# Commandes du client
# --------------------------------------------------------------------------- #


class ClientOrderViewSet(ClientAuthMixin, viewsets.GenericViewSet):
    """/api/client/orders/ — uniquement les commandes du client connecté
    (Order.client = lui). Création en attente d'approbation, modification
    et annulation tant que la boutique n'a pas commencé la préparation."""

    serializer_class = ClientOrderSerializer
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "client_orders"

    def get_queryset(self):
        qs = (
            Order.objects.filter(client=self.request.user)
            .select_related("magasin")
            .prefetch_related("items__product_variant__product_reference")
            .order_by("-created_at")
        )
        statut = self.request.query_params.get("statut")
        if statut:
            qs = qs.filter(statut_courant__in=[s for s in statut.split(",") if s])
        return qs

    def list(self, request):
        return Response(self.get_serializer(self.get_queryset(), many=True).data)

    def retrieve(self, request, pk=None):
        order = get_object_or_404(self.get_queryset(), pk=pk)
        return Response(self.get_serializer(order).data)

    def create(self, request):
        ser = ClientOrderCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        d = ser.validated_data
        magasin = MagasinProfile.objects.filter(pk=d["boutique"]).first()
        if magasin is None:
            return Response({"boutique": ["Boutique introuvable."]}, status=status.HTTP_400_BAD_REQUEST)
        try:
            order = create_client_order(
                client=request.user,
                magasin=magasin,
                items=d["items"],
                livraison_zone=d["livraison_zone"],
                adresse_livraison=d.get("adresse_livraison", ""),
                telephone=d.get("telephone"),
                telephone_2=d.get("telephone_2", ""),
                mode_paiement=d.get("mode_paiement", "LIVRAISON"),
                note=d.get("note", ""),
                date_livraison=d.get("date_livraison_souhaitee"),
            )
        except DjangoValidationError as e:
            return Response(_erreurs(e), status=status.HTTP_400_BAD_REQUEST)
        order = self.get_queryset().get(pk=order.pk)
        return Response(self.get_serializer(order).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        order = get_object_or_404(self.get_queryset(), pk=pk)
        ser = ClientOrderUpdateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            update_client_order(order=order, data=ser.validated_data)
        except DjangoValidationError as e:
            return Response(_erreurs(e), status=status.HTTP_400_BAD_REQUEST)
        order = self.get_queryset().get(pk=order.pk)
        return Response(self.get_serializer(order).data)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        order = get_object_or_404(self.get_queryset(), pk=pk)
        ser = ClientOrderCancelSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            annuler_commande_par_client(order=order, note=ser.validated_data.get("note", ""))
        except DjangoValidationError as e:
            return Response(_erreurs(e), status=status.HTTP_400_BAD_REQUEST)
        order = self.get_queryset().get(pk=order.pk)
        return Response(self.get_serializer(order).data)
