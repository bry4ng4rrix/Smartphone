"""API trésorerie — GET /api/finance/… (gérant uniquement : ces réponses
contiennent coûts d'achat, marges et soldes)."""

from datetime import date, timedelta

from django.core.exceptions import ValidationError
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from users.models import MagasinProfile
from users.permissions import IsGerant, get_accessible_magasins

from . import services
from .models import EpargneMouvement
from .serializers import (
    EpargneMouvementSerializer,
    FinanceSettingsSerializer,
    RemiseSerializer,
    RetraitEpargneSerializer,
)


def _date(value, defaut):
    try:
        return date.fromisoformat(value) if value else defaut
    except ValueError:
        return defaut


class _FinanceView(APIView):
    permission_classes = [IsGerant]

    def magasins(self, request):
        qs = get_accessible_magasins(request.user)
        magasin_id = request.query_params.get("magasin_id")
        if not magasin_id and isinstance(getattr(request, "data", None), dict):
            magasin_id = request.data.get("magasin_id")
        if magasin_id:
            qs = qs.filter(id=magasin_id)
        return list(qs)

    def magasin_unique(self, request):
        """Le magasin visé par une écriture (retrait, remise…)."""
        magasins = self.magasins(request)
        if len(magasins) != 1:
            raise DRFValidationError({"magasin_id": "Précisez le magasin (magasin_id)."})
        return magasins[0]

    def periode(self, request):
        aujourd_hui = timezone.localdate()
        date_to = _date(request.query_params.get("date_to"), aujourd_hui)
        date_from = _date(request.query_params.get("date_from"), date_to.replace(day=1))
        if date_from > date_to:
            date_from, date_to = date_to, date_from
        return date_from, date_to


class DashboardView(_FinanceView):
    """GET /api/finance/dashboard/?magasin_id&date_from&date_to"""

    def get(self, request):
        magasins = self.magasins(request)
        if not magasins:
            return Response({"error": "Aucun magasin accessible."}, status=400)
        date_from, date_to = self.periode(request)
        return Response(services.tableau_de_bord(magasins, date_from, date_to))


class JournalView(_FinanceView):
    """GET /api/finance/journal/?magasin_id&date_from&date_to&origine"""

    def get(self, request):
        magasins = self.magasins(request)
        date_from, date_to = self.periode(request)
        lignes = services.journal(magasins, date_from, date_to, request.query_params.get("origine") or None)
        return Response({"periode": {"from": str(date_from), "to": str(date_to)}, "lignes": lignes})


class VentesView(_FinanceView):
    """GET /api/finance/ventes/?magasin_id&date_from&date_to — gain réel par vente."""

    def get(self, request):
        magasins = self.magasins(request)
        date_from, date_to = self.periode(request)
        return Response({"periode": {"from": str(date_from), "to": str(date_to)}, "ventes": services.ventes(magasins, date_from, date_to)})


class SettingsView(_FinanceView):
    """GET / PATCH /api/finance/settings/?magasin_id — clé de répartition."""

    def get(self, request):
        magasin = self.magasin_unique(request)
        return Response(FinanceSettingsSerializer(services.parametres(magasin)).data)

    def patch(self, request):
        magasin = self.magasin_unique(request)
        settings = services.parametres(magasin)
        serializer = FinanceSettingsSerializer(settings, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save(updated_by=request.user)
        return Response(serializer.data)


class EpargneView(_FinanceView):
    """GET /api/finance/epargne/?magasin_id — solde + historique."""

    def get(self, request):
        magasins = self.magasins(request)
        qs = EpargneMouvement.objects.filter(magasin__in=magasins).select_related("order", "created_by")[:500]
        return Response({
            "solde": sum((services.solde_epargne(m) for m in magasins), services.ZERO),
            "historique": EpargneMouvementSerializer(qs, many=True).data,
        })


class RetraitEpargneView(_FinanceView):
    """POST /api/finance/epargne/retrait/ {montant, motif, confirmation: true, magasin_id?}"""

    def post(self, request):
        magasin = self.magasin_unique(request)
        serializer = RetraitEpargneSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            mvt = services.retirer_epargne(magasin, request.user, serializer.validated_data["montant"], serializer.validated_data.get("motif", ""))
        except ValidationError as exc:
            raise DRFValidationError(exc.messages)
        return Response(EpargneMouvementSerializer(mvt).data, status=status.HTTP_201_CREATED)


class RemiseView(_FinanceView):
    """POST /api/finance/encaissements/remise/ {livreur_id | encaissement_ids, inclure_depenses}"""

    def post(self, request):
        magasin = self.magasin_unique(request)
        serializer = RemiseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        d = serializer.validated_data
        try:
            res = services.remettre_encaissements(
                magasin, request.user, livreur_id=d.get("livreur_id"), encaissement_ids=d.get("encaissement_ids"),
                inclure_depenses=d.get("inclure_depenses", True),
            )
        except ValidationError as exc:
            raise DRFValidationError(exc.messages)
        return Response(res)


class EncaissementsView(_FinanceView):
    """GET /api/finance/encaissements/?magasin_id — en attente."""

    def get(self, request):
        return Response(services.encaissements_en_attente(self.magasins(request)))


class RecalculView(_FinanceView):
    """POST /api/finance/recalculer/ {magasin_id?, date_from, date_to} —
    recalcule les gains d'une plage (après modification d'un coût de zone,
    d'un prix d'achat…) et aligne l'épargne."""

    def post(self, request):
        magasin = self.magasin_unique(request)
        aujourd_hui = timezone.localdate()
        date_to = _date(request.data.get("date_to"), aujourd_hui)
        date_from = _date(request.data.get("date_from"), aujourd_hui - timedelta(days=30))
        n = services.recalculer_ventes(magasin, date_from, date_to, request.user)
        return Response({"recalculees": n, "from": str(date_from), "to": str(date_to)})
