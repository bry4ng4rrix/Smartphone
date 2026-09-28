"""Règles métier de la boutique en ligne — réutilise le modèle `Order` et les
services existants (orders/services.py) : aucun système de commande
parallèle, aucun accès direct au stock.

La boutique en ligne ne demande NI compte NI connexion : le visiteur saisit
ses coordonnées au moment de commander. Une commande :

* est créée en "EN_ATTENTE_APPROBATION" — le gérant rappelle la personne au
  téléphone pour vérifier, puis l'approuve, ce qui la fait entrer dans le
  workflow habituel (orders/services.py::approuver_commande_client) ;
* ne touche PAS le stock tant qu'elle n'est pas approuvée (la réservation se
  fait à l'approbation) — mais la disponibilité est vérifiée ici, sous
  verrou, pour ne pas accepter ce qui n'est plus en rayon ;
* prend les prix catalogue du moment (snapshot OrderItem.prix_unitaire) ; le
  client peut envoyer le prix qu'il a vu (`prix_attendu`) pour être averti si
  le prix a changé entre-temps ;
* porte `origine_en_ligne=True`, ce qui la distingue d'une saisie interne.

Elle n'est plus modifiable ni annulable depuis le site : sans compte, rien ne
permettrait d'authentifier la personne qui le demande. La correction passe par
l'appel du gérant.
"""
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction

from catalog.models import ProductVariant
from orders.models import DeliveryZoneOption, Order, OrderItem, OrderStatusHistory
from orders.services import STATUT_ATTENTE_APPROBATION
from users.models import MagasinProfile, Notification

# --------------------------------------------------------------------------- #
# Livraison
# --------------------------------------------------------------------------- #

#: Retrait en boutique — gratuit, pas d'adresse à saisir.
CODE_RECUPERATION = "RECUPERATION"

#: Livraison de la boutique en ligne : un tarif unique pour tous.
CODE_ZONE_EN_LIGNE = "EN_LIGNE"
PRIX_LIVRAISON_EN_LIGNE = Decimal("3000")


def zone_livraison_en_ligne(magasin):
    """La zone de livraison unique du site, créée à la demande.

    Le site n'expose plus le découpage par quartier : une seule livraison, au
    même prix pour tout le monde. Ce prix reste porté par une
    `DeliveryZoneOption` comme les autres, pour deux raisons : c'est
    `Order.save()` qui applique les frais (le champ `frais_livraison` n'est pas
    éditable), et le gérant garde ainsi la main dessus depuis ses paramètres.

    Conséquence voulue : le navigateur n'envoie jamais de montant. Un prix
    venu du client ne fait pas foi.
    """
    try:
        admin_profile = magasin.admin.admin_profile
    except Exception:
        return None
    zone, _ = DeliveryZoneOption.objects.get_or_create(
        admin_profile=admin_profile,
        code=CODE_ZONE_EN_LIGNE,
        defaults={"nom": "Livraison", "prix": PRIX_LIVRAISON_EN_LIGNE, "actif": True},
    )
    return zone


def options_livraison(magasin):
    """Les deux seuls choix proposés en ligne, prix inclus."""
    zone = zone_livraison_en_ligne(magasin)
    return {
        "livraison": {
            "code": CODE_ZONE_EN_LIGNE,
            "nom": zone.nom if zone else "Livraison",
            "prix": zone.prix if zone else PRIX_LIVRAISON_EN_LIGNE,
        },
        "recuperation": {"code": CODE_RECUPERATION, "nom": "Retrait sur place", "prix": Decimal("0")},
    }


def valider_zone(magasin, code):
    if code == CODE_RECUPERATION:
        return code
    if code != CODE_ZONE_EN_LIGNE:
        raise ValidationError({"livraison_zone": "Mode de livraison invalide."})
    if zone_livraison_en_ligne(magasin) is None:
        raise ValidationError({"livraison_zone": "Cette boutique ne peut pas livrer pour le moment."})
    return code


# --------------------------------------------------------------------------- #
# Commande
# --------------------------------------------------------------------------- #


@transaction.atomic
def create_commande_en_ligne(*, magasin, items, livraison_zone, client_nom, telephone,
                             telephone_2="", adresse_livraison="", note=""):
    """`items` : liste de {"variante": id, "quantite": int, "prix_attendu": Decimal|None}.

    Vérifications, sous verrou (`select_for_update`) pour tenir la concurrence :
    variante active de la boutique, quantité ≥ 1, stock suffisant, prix
    inchangé si `prix_attendu` est fourni. Les erreurs sont des
    ValidationError avec un dictionnaire {champ: message} directement
    renvoyable en 400.
    """
    if not isinstance(magasin, MagasinProfile):
        raise ValidationError({"boutique": "Boutique introuvable."})
    if not items:
        raise ValidationError({"items": "Ajoutez au moins un article."})

    nom = (client_nom or "").strip()
    if not nom:
        raise ValidationError({"client_nom": "Indiquez le nom de la personne à contacter."})
    tel = (telephone or "").strip()
    if not tel:
        raise ValidationError({"telephone": "Indiquez un numéro de téléphone."})

    valider_zone(magasin, livraison_zone)
    adresse = (adresse_livraison or "").strip()
    if livraison_zone != CODE_RECUPERATION and not adresse:
        raise ValidationError({"adresse_livraison": "Adresse de livraison requise pour une livraison."})

    # Regroupe les doublons de variante avant de vérifier le stock.
    quantites = {}
    attendus = {}
    for it in items:
        vid = int(it["variante"])
        q = int(it.get("quantite") or 0)
        if q < 1:
            raise ValidationError({"items": "La quantité doit être au moins 1."})
        quantites[vid] = quantites.get(vid, 0) + q
        if it.get("prix_attendu") is not None:
            attendus[vid] = Decimal(str(it["prix_attendu"]))

    variantes = (
        ProductVariant.objects.select_for_update()
        .select_related("product_reference", "product_reference__type__category")
        .filter(id__in=quantites.keys())
    )
    par_id = {v.id: v for v in variantes}
    erreurs = []
    for vid, q in quantites.items():
        v = par_id.get(vid)
        if v is None or not v.product_reference.actif:
            erreurs.append(f"Article {vid} indisponible.")
            continue
        if v.product_reference.type.category.magasin_id != magasin.id:
            erreurs.append(f"L'article « {v.product_reference.reference_name} » n'appartient pas à cette boutique.")
            continue
        if v.stock_actuel < q:
            erreurs.append(
                f"Stock insuffisant pour « {v.product_reference.reference_name} ({v.couleur}) » : "
                f"{max(v.stock_actuel, 0)} disponible(s), {q} demandé(s)."
            )
        attendu = attendus.get(vid)
        if attendu is not None and attendu != v.product_reference.prix_vente:
            erreurs.append(
                f"Le prix de « {v.product_reference.reference_name} » a changé : "
                f"{v.product_reference.prix_vente:.0f} Ar (vous aviez {attendu:.0f} Ar)."
            )
    if erreurs:
        raise ValidationError({"items": erreurs})

    order = Order.objects.create(
        magasin=magasin,
        origine_en_ligne=True,
        client_nom=nom,
        telephone=tel,
        telephone_2=(telephone_2 or "").strip(),
        livraison_zone=livraison_zone,
        adresse_livraison=adresse if livraison_zone != CODE_RECUPERATION else "",
        # Le règlement se fait à la remise : le site n'encaisse rien.
        mode_paiement="LIVRAISON",
        note_livreur=(note or "").strip(),
        statut_courant=STATUT_ATTENTE_APPROBATION,
        created_by=None,
    )
    for vid, q in quantites.items():
        # prix_unitaire None -> prix catalogue du moment (OrderItem.save).
        OrderItem.objects.create(order=order, product_variant=par_id[vid], quantite=q)
    order.recompute_total()

    OrderStatusHistory.objects.create(
        order=order, ancien_statut=None, nouveau_statut=STATUT_ATTENTE_APPROBATION, changed_by=None,
        note="Commande passée depuis la boutique en ligne",
    )
    # Le gérant (groupe du magasin + admin, via le signal post_save) est
    # prévenu qu'une commande attend son appel de confirmation.
    Notification.objects.create(
        notif_type="order",
        message=f"Commande en ligne {order.numero} à confirmer par téléphone — {nom} ({tel})",
        magasin=magasin,
    )
    return order
