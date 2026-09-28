"""Vues de la boutique en ligne : catalogue public et prise de commande.

TOUT est public ici — il n'y a ni compte, ni connexion, ni jeton. Le visiteur
saisit ses coordonnées au moment de commander, et le gérant le rappelle pour
confirmer avant d'approuver. Aucune vue de ce module n'accepte ni n'exige
d'authentification ; les vues internes, elles, restent protégées comme avant.
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from catalog.models import Brand, Color, ProductCategory, ProductReference, ProductType
from users.models import MagasinProfile

from .serializers import (
    CommandeEnLigneCreateSerializer,
    CommandeEnLigneSerializer,
    PublicBoutiqueSerializer,
    PublicCategorieSerializer,
    PublicCouleurSerializer,
    PublicMarqueSerializer,
    PublicProduitSerializer,
    PublicSousTypeSerializer,
)
from .services import create_commande_en_ligne, options_livraison


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
    """GET /api/boutiques/ — boutiques auprès desquelles on peut commander."""

    def get(self, request):
        qs = MagasinProfile.objects.order_by("shop_name")
        return Response(PublicBoutiqueSerializer(qs, many=True, context={"request": request}).data)


class PublicBoutiqueZonesView(PublicMixin, APIView):
    """GET /api/boutiques/{id}/zones/ — les deux modes de remise proposés en
    ligne : livraison à tarif unique, ou retrait sur place gratuit.

    Le prix vient du serveur et n'est jamais accepté depuis le navigateur.
    """

    def get(self, request, pk):
        magasin = get_object_or_404(MagasinProfile, pk=pk)
        options = options_livraison(magasin)
        return Response(
            {
                "boutique": magasin.id,
                "recuperation": {
                    "code": options["recuperation"]["code"],
                    "nom": options["recuperation"]["nom"],
                    "prix": float(options["recuperation"]["prix"]),
                },
                "zones": [
                    {
                        "code": options["livraison"]["code"],
                        "nom": options["livraison"]["nom"],
                        "prix": float(options["livraison"]["prix"]),
                    }
                ],
            }
        )


class PublicCategorieListView(PublicMixin, APIView):
    """GET /api/categories/ (alias : GET /api/type/) — ?boutique=."""

    def get(self, request):
        # `visible_client` : la vitrine en ligne n'expose que ce que le gérant
        # y a mis (voir ProductCategory.visible_client).
        qs = _filtre_boutique(request, ProductCategory.objects.filter(visible_client=True))
        return Response(PublicCategorieSerializer(qs.order_by("ordre", "nom"), many=True).data)


class PublicSousTypeListView(PublicMixin, APIView):
    """GET /api/sous-type/ — ?category= (ou ?categorie=), ?boutique=."""

    def get(self, request):
        # Un sous-type masqué, ou dont la catégorie l'est, reste hors vitrine.
        qs = ProductType.objects.select_related("category").filter(
            visible_client=True, category__visible_client=True
        )
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
            ProductReference.objects.filter(
                actif=True,
                # Vitrine en ligne : un produit suit la visibilité de son
                # sous-type ET de sa catégorie. Vaut aussi pour le détail
                # (`/api/produit/{id}/`), qui partage ce queryset.
                type__visible_client=True,
                type__category__visible_client=True,
            )
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
# Prise de commande
# --------------------------------------------------------------------------- #


class CommandeEnLigneView(PublicMixin, APIView):
    """POST /api/commandes/ — passer commande sans compte.

    La commande naît « en attente d'approbation » : le gérant rappelle la
    personne au numéro fourni pour vérifier avant de l'approuver. Rien n'est
    encaissé ici, et aucun stock n'est réservé avant cette approbation.

    Volontairement en écriture seule : sans compte, rien ne permettrait
    d'authentifier quelqu'un qui viendrait relire ou modifier une commande.
    La réponse ne contient donc que le nécessaire pour l'écran de
    confirmation (numéro, montants, coordonnées saisies).
    """

    # Débit propre à l'écriture : plus strict que la lecture du catalogue,
    # puisque l'endpoint est ouvert et crée des enregistrements.
    throttle_scope = "commande_en_ligne"

    def post(self, request):
        ser = CommandeEnLigneCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        d = ser.validated_data

        magasin = MagasinProfile.objects.filter(pk=d["boutique"]).first()
        if magasin is None:
            return Response({"boutique": ["Boutique introuvable."]}, status=status.HTTP_400_BAD_REQUEST)

        try:
            order = create_commande_en_ligne(
                magasin=magasin,
                items=d["items"],
                livraison_zone=d["livraison_zone"],
                client_nom=d["client_nom"],
                telephone=d["telephone"],
                telephone_2=d.get("telephone_2", ""),
                adresse_livraison=d.get("adresse_livraison", ""),
                note=d.get("note", ""),
            )
        except DjangoValidationError as e:
            return Response(_erreurs(e), status=status.HTTP_400_BAD_REQUEST)

        return Response(CommandeEnLigneSerializer(order).data, status=status.HTTP_201_CREATED)
