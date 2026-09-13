from django.core.exceptions import ValidationError
from django.db.models import Prefetch
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import ProductVariant
from users.models import Notification
from users.permissions import IsGerant, get_accessible_magasins, resolve_magasin_for_request
from users.subscriptions import get_company_owner

from . import services
from .models import Supplier, SupplierOrder, VariantCostHistory
from .serializers import (
    ExpedierSerializer,
    FinaliserSerializer,
    ReceptionSerializer,
    SupplierFeeInputSerializer,
    SupplierFeeSerializer,
    SupplierOrderCreateSerializer,
    SupplierOrderSerializer,
    SupplierOrderUpdateSerializer,
    SupplierPaymentInputSerializer,
    SupplierPaymentSerializer,
    SupplierSerializer,
    VariantCostHistorySerializer,
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
        .select_related("magasin", "supplier")
        .prefetch_related(
            Prefetch("lines", queryset=SupplierOrderLine_qs()),
            "payments", "fees",
        )
    )


def SupplierOrderLine_qs():
    from .models import SupplierOrderLine

    return SupplierOrderLine.objects.select_related(
        "product_variant__product_reference__brand"
    ).order_by("id")


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
            from django.db.models import Q

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
    """Module Approvisionnements fournisseur (§7.6 Smartreadme.md, étendu) — réservé au gérant."""

    # DELETE n'est ouvert que pour les sous-ressources paiements / frais
    # (actions ci-dessous) : un approvisionnement ne se supprime pas.
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
        if p.get("statut"):
            qs = qs.filter(statut__in=[s for s in p["statut"].split(",") if s])
        search = (p.get("search") or "").strip()
        if search:
            from django.db.models import Q

            qs = qs.filter(Q(numero__icontains=search) | Q(description__icontains=search) | Q(supplier__nom__icontains=search) | Q(tracking__icontains=search))
        return qs

    def destroy(self, request, *args, **kwargs):
        return Response({"detail": "Un approvisionnement ne se supprime pas (historique comptable)."}, status=status.HTTP_405_METHOD_NOT_ALLOWED)

    def _reponse(self, order, code=status.HTTP_200_OK):
        return Response(SupplierOrderSerializer(self.get_queryset().get(pk=order.pk)).data, status=code)

    def create(self, request, *args, **kwargs):
        serializer = SupplierOrderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        magasin = resolve_magasin_for_request(request)
        try:
            order = services.create_supplier_order(magasin=magasin, created_by=request.user, **data)
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

    @action(detail=True, methods=["post"])
    def commander(self, request, pk=None):
        order = self.get_object()
        try:
            services.commander(order)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    @action(detail=True, methods=["post"])
    def preparer(self, request, pk=None):
        order = self.get_object()
        try:
            services.preparer(order)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    @action(detail=True, methods=["post"])
    def expedier(self, request, pk=None):
        order = self.get_object()
        ser = ExpedierSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            services.expedier(order, **ser.validated_data)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    @action(detail=True, methods=["post"])
    def arriver(self, request, pk=None):
        order = self.get_object()
        date_arrivee = request.data.get("date_arrivee") or None
        try:
            services.arriver(order, date_arrivee=date_arrivee)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    @action(detail=True, methods=["post"])
    def receive(self, request, pk=None):
        """POST : réception (totale sans corps, ou partielle avec
        `lines: [{line_id, quantite_recue}]`) -> entrée stock par variante."""
        order = self.get_object()
        ser = ReceptionSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        quantites = None
        if ser.validated_data.get("lines"):
            quantites = {l["line_id"]: l["quantite_recue"] for l in ser.validated_data["lines"]}
        try:
            order = services.receive_supplier_order(order, request.user, quantites=quantites)
        except ValidationError as exc:
            _erreur(exc)
        Notification.objects.create(
            notif_type="supplier_order",
            message=(
                f"Commande fournisseur {order.numero} reçue — stock mis à jour"
                if order.statut == "RECU"
                else f"Commande fournisseur {order.numero} partiellement reçue ({order.total_recu}/{sum(l.quantite for l in order.lines.all())}) — stock mis à jour"
            ),
            magasin=order.magasin,
        )
        return self._reponse(order)

    @action(detail=True, methods=["post"])
    def finaliser(self, request, pk=None):
        order = self.get_object()
        ser = FinaliserSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            services.finaliser_cout(order, mettre_a_jour_prix_achat=ser.validated_data["mettre_a_jour_prix_achat"])
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    # --- paiements ----------------------------------------------------------- #

    @action(detail=True, methods=["get", "post"])
    def payments(self, request, pk=None):
        order = self.get_object()
        if request.method == "GET":
            return Response(SupplierPaymentSerializer(order.payments.all(), many=True).data)
        ser = SupplierPaymentInputSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            services.add_payment(order=order, user=request.user, **ser.validated_data)
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

    # --- frais d'importation ------------------------------------------------- #

    @action(detail=True, methods=["get", "post"])
    def fees(self, request, pk=None):
        order = self.get_object()
        if request.method == "GET":
            return Response(SupplierFeeSerializer(order.fees.all(), many=True).data)
        ser = SupplierFeeInputSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            services.add_fee(order=order, user=request.user, **ser.validated_data)
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order, status.HTTP_201_CREATED)

    @action(detail=True, methods=["delete"], url_path=r"fees/(?P<fee_id>\d+)")
    def delete_fee(self, request, pk=None, fee_id=None):
        order = self.get_object()
        try:
            services.delete_fee(order=order, fee_id=int(fee_id))
        except ValidationError as exc:
            _erreur(exc)
        return self._reponse(order)

    # --- indicateurs -------------------------------------------------------- #

    @action(detail=False, methods=["get"])
    def kpis(self, request):
        """GET /api/suppliers/orders/kpis/ — indicateurs de la page Fournisseurs."""
        profile = _admin_profile(request.user)
        suppliers = Supplier.objects.filter(admin_profile=profile, actif=True) if profile else Supplier.objects.none()
        return Response(services.kpis(self.get_queryset(), suppliers))


# --------------------------------------------------------------------------- #
# Coût de revient par variante
# --------------------------------------------------------------------------- #


class VariantCostHistoryView(APIView):
    """GET /api/suppliers/cost-history/?variant=<id> — coût de revient actuel
    (dernier approvisionnement finalisé), moyen pondéré et historique d'une
    variante ; sans `variant`, les 200 dernières entrées de la société."""

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
                "prix_achat_reference": variant.product_reference.prix_achat,
                "prix_vente": variant.product_reference.prix_vente,
                "cout_actuel_mga": info["dernier"],
                "cout_moyen_pondere_mga": info["moyen_pondere"],
                "historique": VariantCostHistorySerializer(info["historique"], many=True).data,
            })
        hist = VariantCostHistory.objects.filter(supplier_order__magasin__in=magasins).select_related(
            "supplier_order__supplier", "product_variant__product_reference"
        )[:200]
        return Response(VariantCostHistorySerializer(hist, many=True).data)
