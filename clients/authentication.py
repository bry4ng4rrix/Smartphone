"""Authentification JWT des clients de l'espace en ligne.

Les jetons sont émis par SimpleJWT (mêmes clés, mêmes durées que les jetons
internes) mais portent une revendication `client_id` au lieu de `user_id` :

* un jeton client présenté à une vue INTERNE (JWTAuthentication) est refusé
  (« Token contained no recognizable user identification ») ;
* un jeton interne présenté à une vue CLIENT est refusé ici (pas de
  `client_id`).

Les deux mondes sont donc étanches sans modifier l'authentification
existante.
"""
from rest_framework import exceptions
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from .models import Client

CLIENT_ID_CLAIM = "client_id"


def tokens_for_client(client):
    """Paire refresh/access pour un client (équivalent de `RefreshToken.for_user`)."""
    refresh = RefreshToken()
    refresh[CLIENT_ID_CLAIM] = client.id
    return {"refresh": str(refresh), "access": str(refresh.access_token)}


def refresh_access_for_client(raw_refresh):
    """Nouvel access à partir d'un refresh client. Lève TokenError si le
    jeton est invalide, expiré ou n'est pas un jeton client."""
    refresh = RefreshToken(raw_refresh)
    client_id = refresh.get(CLIENT_ID_CLAIM)
    if not client_id:
        raise TokenError("Ce jeton n'est pas un jeton client.")
    if not Client.objects.filter(id=client_id, is_active=True).exists():
        raise TokenError("Compte client introuvable ou désactivé.")
    return str(refresh.access_token)


class ClientJWTAuthentication(BaseAuthentication):
    """`Authorization: Bearer <access>` dont l'access porte `client_id`."""

    keyword = b"bearer"

    def authenticate(self, request):
        header = get_authorization_header(request).split()
        if not header or header[0].lower() != self.keyword:
            return None
        if len(header) != 2:
            raise exceptions.AuthenticationFailed("En-tête Authorization invalide.")
        try:
            token = AccessToken(header[1].decode("utf-8"))
        except TokenError as e:
            raise exceptions.AuthenticationFailed(f"Jeton invalide ou expiré : {e}")
        client_id = token.get(CLIENT_ID_CLAIM)
        if not client_id:
            raise exceptions.AuthenticationFailed("Ce jeton n'est pas un jeton client.")
        try:
            client = Client.objects.get(id=client_id)
        except Client.DoesNotExist:
            raise exceptions.AuthenticationFailed("Compte client introuvable.")
        if not client.is_active:
            raise exceptions.AuthenticationFailed("Compte client désactivé.")
        return (client, token)

    def authenticate_header(self, request):
        return 'Bearer realm="client"'
