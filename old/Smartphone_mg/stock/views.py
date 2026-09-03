from django.db.models import F, Q
from django.http import HttpResponse
from rest_framework import viewsets
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import ProductVariant
from users.permissions import IsGerant

from .models import StockMovement
from .serializers import RuptureSerializer, StockAdjustmentSerializer, StockMovementSerializer
from .services import apply_stock_movement


class StockMovementViewSet(viewsets.ReadOnlyModelViewSet):
    """Historique des mouvements de stock — module Gérant uniquement (§7.4)."""

    queryset = StockMovement.objects.select_related("product_variant", "user").all()
    serializer_class = StockMovementSerializer
    permission_classes = [IsGerant]

    def get_queryset(self):
        qs = super().get_queryset()
        variant_id = self.request.query_params.get("variant")
        if variant_id:
            qs = qs.filter(product_variant_id=variant_id)
        return qs


class StockAdjustmentView(APIView):
    """POST : entrée/sortie manuelle de stock (corrections, entrée après
    fournisseur) — réservé au gérant."""

    permission_classes = [IsGerant]

    def post(self, request):
        serializer = StockAdjustmentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        movement = apply_stock_movement(
            product_variant=data["product_variant"],
            movement_type=data["type"],
            quantite=data["quantite"],
            origine="AJUSTEMENT",
            user=request.user,
            note=data.get("note", ""),
        )
        return Response(StockMovementSerializer(movement).data, status=201)


class RuptureListView(APIView):
    """GET : liste auto des ruptures (stock=0) et stock bas (stock<=seuil),
    groupée par catégorie/sous-type/marque (§7.5)."""

    permission_classes = [IsGerant]

    def get(self, request):
        qs = (
            ProductVariant.objects.select_related(
                "product_reference", "product_reference__brand", "product_reference__type",
                "product_reference__type__category",
            )
            .filter(Q(stock_actuel__lte=0) | Q(stock_actuel__lte=F("seuil_alerte")))
            .order_by(
                "product_reference__type__category__nom",
                "product_reference__type__nom",
                "product_reference__brand__nom",
            )
        )
        return Response(RuptureSerializer(qs, many=True).data)


class RuptureExportPDFView(APIView):
    """GET : export PDF de la liste de réapprovisionnement, à partager au
    fournisseur (§7.5 README)."""

    permission_classes = [IsGerant]

    def get(self, request):
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import A4
        from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph
        from reportlab.lib.styles import getSampleStyleSheet
        from django.utils import timezone
        from io import BytesIO

        qs = (
            ProductVariant.objects.select_related(
                "product_reference", "product_reference__brand", "product_reference__type",
            )
            .filter(Q(stock_actuel__lte=0) | Q(stock_actuel__lte=F("seuil_alerte")))
            .order_by("product_reference__type__nom", "product_reference__brand__nom")
        )

        buffer = BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=A4)
        styles = getSampleStyleSheet()
        elements = [Paragraph(
            f"Liste de réapprovisionnement — {timezone.now():%d/%m/%Y}", styles["Title"]
        )]

        data = [["Sous-type", "Marque", "Référence", "Couleur", "Stock", "Seuil", "Qté à commander"]]
        for v in qs:
            manque = max(v.seuil_alerte - v.stock_actuel, 1)
            data.append([
                v.product_reference.type.nom,
                v.product_reference.brand.nom,
                v.product_reference.reference_name,
                v.couleur,
                str(v.stock_actuel),
                str(v.seuil_alerte),
                str(manque),
            ])

        table = Table(data, repeatRows=1)
        table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1f2937")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
        ]))
        elements.append(table)
        doc.build(elements)

        buffer.seek(0)
        response = HttpResponse(buffer.read(), content_type="application/pdf")
        response["Content-Disposition"] = 'attachment; filename="reapprovisionnement.pdf"'
        return response
