from django.urls import path

from .views import (
    DashboardView,
    EncaissementsView,
    EpargneView,
    JournalView,
    RecalculView,
    RemiseView,
    RetraitEpargneView,
    SettingsView,
    VentesView,
)

urlpatterns = [
    path("dashboard/", DashboardView.as_view()),
    path("journal/", JournalView.as_view()),
    path("ventes/", VentesView.as_view()),
    path("settings/", SettingsView.as_view()),
    path("epargne/", EpargneView.as_view()),
    path("epargne/retrait/", RetraitEpargneView.as_view()),
    path("encaissements/", EncaissementsView.as_view()),
    path("encaissements/remise/", RemiseView.as_view()),
    path("recalculer/", RecalculView.as_view()),
]
