from django.contrib import admin
from django.urls import include, path, re_path
from django.conf import settings
from django.views.static import serve


urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/users/', include('users.urls')),
    path('api/catalog/', include('catalog.urls')),
    path('api/orders/', include('orders.urls')),
    path('api/suppliers/', include('suppliers.urls')),
    # Espace client (catalogue public, comptes et commandes client) — app `clients`.
    path('api/', include('clients.urls')),
    path('api/finance/', include('finance.urls')),
]

# Fichiers uploadés (photos produit, captures de préparation, logos...).
#
# On ne passe PAS par django.conf.urls.static.static() : ce raccourci ne monte
# la route qu'en DEBUG, or le déploiement tourne avec DEBUG=False et aucun
# reverse-proxy ne sert /media/ devant Daphne (voir docker-compose.prod.yml).
# WhiteNoise ne couvre que STATIC_ROOT, pas MEDIA_ROOT : sans cette route,
# TOUTES les images uploadées répondent 404 en production.
#
# `django.views.static.serve` refuse les chemins qui sortent de MEDIA_ROOT
# (safe_join), mais sert le fichier depuis le process applicatif. Le jour où un
# nginx est ajouté devant, lui confier /media/ et supprimer ce bloc.
urlpatterns += [
    re_path(
        r"^%s(?P<path>.*)$" % settings.MEDIA_URL.lstrip("/"),
        serve,
        {"document_root": settings.MEDIA_ROOT},
    ),
]
