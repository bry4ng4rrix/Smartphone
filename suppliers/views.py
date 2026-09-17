from django.core.exceptions import ValidationError
from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import ProductVariant
from users.permissions import IsGerant, get_accessible_magasins, resolve_magasin_for_request
from users.subscriptions import get_company_owner

from . import services
from .models import Supplier, SupplierOrder
from .serializers import (
    ArriverSerializer,
    ExpedierSerializer,
    FinaliserSerializer,
    FraisDouaneSerializer,
    HistoriqueCoutSerializer,
    SupplierOrderCreateSerializer,
    SupplierOrderSerializer,
    SupplierOrderUpdateSerializer,
    SupplierPaymentInputSerializer,
    SupplierPaymentSerializer,
    SupplierSerializer,
    TransitSerializer,
)


def _erreur(exc):
    """ValidationError Django (services) -> 400 DRF, dictionnaire conservé."""
    if hasattr(exc, "message_dict"):
        raise DRFValidationError(exc.message_dict)
    raise DRFValidationError(exc.messages if hasattr(exc, "messages") else str(exc))


def _admin_profile(user):
    owner = get_company_owner(user)
    return getattr(owner, "admin_profile", None) if owner else None


def _orders_qs(user):
    return (
        SupplierOrder.objects.filter(magasin__in=get_accessible_magasins(user))
        .select_related("magasin", "supplier", "created_by", "product_variant__product_reference__brand", "product_variant__product_reference__type")
        .prefetch_related("payments__created_by")
    )


# --------------------------------------------------------------------------- #
# Fournisseurs
# --------------------------------------------------------------------------- #


class SupplierViewSet(viewsets.ModelViewSet):
    """Fiches fournisseur de la société (gérant). La liste et le détail
    portent le résumé financier calculé sur les approvisionnements visibles."""

    serializer_class = SupplierSerializer
    permission_classes = [IsGerant]
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_queryset(self):
        profile = _admin_profile(self.request.user)
        if profile is None:
            return Supplier.objects.none()
        qs = Supplier.objects.filter(admin_profile=profile)
        search = (self.request.query_params.get("search") or "").strip()
        if search:
            qs = qs.filter(Q(nom__icontains=search) | Q(pays__icontains=search) | Q(contact__icontains=search) | Q(email__icontains=search))
        if self.request.query_params.get("actif") == "1":
            qs = qs.filter(actif=True)
        return qs

    def _annoter(self, suppliers):
        """Ajoute le résumé financier et le dernier approvisionnement à chaque fiche."""
        orders = _orders_qs(self.request.user).filter(supplier__in=[s.id for s in suppliers]).order_by("-created_at")
        par_supplier = {}
        for o in orders:
            par_supplier.setdefault(o.supplier_id, []).append(o)
        for s in suppliers:
            lst = par_supplier.get(s.id, [])
            for k, v in services.resume_financier(lst).items():
                setattr(s, k, v)
            s._dernier = lst[0] if lst else None
        return suppliers

    def list(self, request, *args, **kwargs):
        suppliers = self._annoter(list(self.get_queryset()))
        return Response(SupplierSerializer(suppliers, many=True).data)

    def retrieve(self, request, *args, **kwargs):
        supplier = self.get_object()
        self._annoter([supplier])
        data = SupplierSerializer(supplier).data
        orders = _orders_qs(request.user).filter(supplier=supplier).order_by("-created_at")
        data["approvisionnements"] = SupplierOrderSerializer(orders, many=True).data
        return Response(data)

    def perform_create(self, serializer):
        profile = _admin_profile(self.request.user)
        if profile is None:
            raise DRFValidationError("Aucune société rattachée à ce compte.")
        serializer.save(admin_profile=profile)

    def perform_destroy(self, instance):
        # Un fournisseur déjà utilisé n'est pas supprimé : il est désactivé
        # (les approvisionnements gardent leur historique).
        if instance.orders.exists():
            instance.actif = False
            instance.save(update_fields=["actif"])
        else:
            instance.delete()


# --------------------------------------------------------------------------- #
# Approvisionnements
# --------------------------------------------------------------------------- #


class SupplierOrderViewSet(viewsets.ModelViewSet):
    """Approvisionnements fournisseur (1 produit, N paiements, 1 expédition,
    Frais + Douane, coût total, coût unitaire) — réservé au gérant."""

    # DELETE n'est ouvert que pour les paiements (sous-route) : un
    # approvisionnement ne se supprime pas (historique de coût), sauf
    # brouillon sans paiement.
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]
    serializer_class = SupplierOrderSerializer
    permission_classes = [IsGerant]
    parser_classes = [JSONParser, FormParser, MultiPartParser]

    def get_queryset(self):
        qs = _orders_qs(self.request.user)
        p = self.request.query_params
        if p.get("magasin_id"):
            qs = qs.filter(magasin_id=p["magasin_id"])
        if p.get("supplier"):
            qs = qs.filter(supplier_id=p["supplier"])
        if p.get("product_variant"):
            qs = qs.filter(product_variant_id=p["product_variant"])
        if p.get("statut"):
            qs = qs.filter(statut__in=[s for s in p["statut"].split(",") if s])
        search = (p.get("search") or "").strip()
        if search:
            qs = qs.filter(
                Q(numero__icontains=search) | Q(description__icontains=search) | Q(supplier__nom__icontains=search)
                | Q(tracking__icontains=search) | Q(numero_colis__icontains=search)
                | Q(product_variant__product_reference__reference_name__icontains=search)
                | Q(product_variant__product_reference__brand__nom__icontains=search)
            )
        return qs

    def destroy(self, request, *args, **kwargs):
        order = self.get_object()
        if order.statut != "BROUILLON" or order.payments.exists():
            return Response(
                {"detail": "Seul un brouillon sans paiement peut être supprimé (historique comptable)."},
                status=status.HTTP_405_METHOD_NOT_ALLOWED,
            )
        order.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    def _reponse(self, order, code=status.HTTP_200_OK):
        return Response(SupplierOrderSerializer(self.get_queryset().get(pk=order.pk)).data, status=code)

    def create(self, request, *args, **kwargs):
        serializer = SupplierOrderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        magasin = resolve_magasin_for_request(request)
        try:
            order = services.create_supplier_order(magasin=magasin, created_by=request.user, **serializer.validated_data)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order, status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        order = self.get_object()
        serializer = SupplierOrderUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        try:
            services.update_supplier_order(order=order, data=serializer.validated_data)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    # --- workflow ------------------------------------------------------------ #

    def _transition(self, fn, **kw):
        try:
            order = fn(self.get_object(), **kw)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    @action(detail=True, methods=["post"])
    def commander(self, request, pk=None):
        return self._transition(services.commander)

    @action(detail=True, methods=["post"])
    def preparer(self, request, pk=None):
        return self._transition(services.preparer)

    @action(detail=True, methods=["post"])
    def expedier(self, request, pk=None):
        s = ExpedierSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        return self._transition(services.expedier, **s.validated_data)

    @action(detail=True, methods=["post"])
    def transit(self, request, pk=None):
        s = TransitSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        return self._transition(services.transit, **s.validated_data)

    @action(detail=True, methods=["post"])
    def arriver(self, request, pk=None):
        s = ArriverSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        return self._transition(services.arriver, **s.validated_data)

    @action(detail=True, methods=["post"], url_path="frais-douane")
    def frais_douane(self, request, pk=None):
        """Saisie / modification du montant unique Frais + Douane (MGA).
        `en_caisse: true` enregistre aussi la sortie de caisse (référence
        APPRO:<n°>:FRAIS, une seule fois)."""
        order = self.get_object()
        s = FraisDouaneSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            order = services.update_supplier_order(order=order, data={"frais_douane_mga": s.validated_data["frais_douane_mga"]})
            if s.validated_data.get("en_caisse"):
                services.enregistrer_en_caisse(
                    order, request.user, order.frais_douane_mga, f"Frais + Douane — approvisionnement {order.numero}",
                    f"APPRO:{order.numero}:FRAIS",
                )
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    @action(detail=True, methods=["post"])
    def finaliser(self, request, pk=None):
        s = FinaliserSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        return self._transition(services.finaliser_cout, user=request.user, **s.validated_data)

    # --- paiements ------------------------------------------------------------ #

    @action(detail=True, methods=["get", "post"])
    def payments(self, request, pk=None):
        order = self.get_object()
        if request.method == "GET":
            return Response(SupplierPaymentSerializer(order.payments.all(), many=True).data)
        s = SupplierPaymentInputSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data = dict(s.validated_data)
        en_caisse = data.pop("en_caisse", False)
        try:
            payment = services.add_payment(order=order, user=request.user, **data)
            if en_caisse:
                services.enregistrer_en_caisse(
                    order, request.user, payment.montant_mga,
                    f"Paiement fournisseur {payment.montant} {payment.devise} — approvisionnement {order.numero}",
                    f"APPRO:{order.numero}:P{payment.id}",
                )
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order, status.HTTP_201_CREATED)

    @action(detail=True, methods=["delete"], url_path=r"payments/(?P<payment_id>\d+)")
    def delete_payment(self, request, pk=None, payment_id=None):
        order = self.get_object()
        try:
            services.delete_payment(order=order, payment_id=int(payment_id))
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    # --- indicateurs -------------------------------------------------------- #

    @action(detail=False, methods=["get"])
    def kpis(self, request):
        """GET /api/suppliers/orders/kpis/ — indicateurs de la page Fournisseurs."""
        profile = _admin_profile(request.user)
        suppliers = Supplier.objects.filter(admin_profile=profile) if profile else Supplier.objects.none()
        return Response(services.kpis(self.get_queryset(), suppliers))


# --------------------------------------------------------------------------- #
# Coût de revient par produit (historique des envois — § 12)
# --------------------------------------------------------------------------- #


class VariantCostHistoryView(APIView):
    """GET /api/suppliers/cost-history/?variant=<id> — dernier coût de revient
    finalisé, coût moyen pondéré et liste des envois finalisés d'un produit ;
    sans `variant`, les 200 derniers envois finalisés de la société."""

    permission_classes = [IsGerant]

    def get(self, request):
        magasins = get_accessible_magasins(request.user)
        variant_id = request.query_params.get("variant")
        if variant_id:
            try:
                variant = ProductVariant.objects.select_related("product_reference").get(
                    id=variant_id, product_reference__type__category__magasin__in=magasins
                )
            except ProductVariant.DoesNotExist:
                return Response({"detail": "Variante introuvable."}, status=status.HTTP_404_NOT_FOUND)
            info = services.cout_revient_variante(variant)
            return Response({
                "variant": variant.id,
                "reference_name": variant.product_reference.reference_name,
                "couleur": variant.couleur,
                "prix_achat_reference": info["prix_achat_reference"],
                "prix_vente": variant.product_reference.prix_vente,
                "cout_actuel_mga": info["dernier"],
                "cout_moyen_pondere_mga": info["moyen"],
                "historique": HistoriqueCoutSerializer(info["envois"], many=True).data,
            })
        envois = SupplierOrder.objects.filter(magasin__in=magasins, statut="COUT_FINALISE").select_related("supplier").order_by("-finalise_at", "-id")[:200]
        return Response(HistoriqueCoutSerializer(envois, many=True).data)
