"""Règles métier de l'espace client — réutilise le modèle `Order` et les
services existants (orders/services.py) : aucun système de commande
parallèle, aucun accès direct au stock.

Une commande client :

* est créée en "EN_ATTENTE_APPROBATION" (le gérant l'approuve ensuite, ce
  qui la fait entrer dans le workflow habituel — voir
  orders/services.py::approuver_commande_client) ;
* ne touche PAS le stock (la déduction se fait, comme pour toute commande,
  au passage "En préparation" via apply_stock_movement) — mais la
  disponibilité est vérifiée ici, sous verrou, pour ne pas accepter ce qui
  n'est plus en rayon ;
* prend les prix catalogue du moment (snapshot OrderItem.prix_unitaire) ;
  le client peut envoyer le prix qu'il a vu (`prix_attendu`) pour être
  averti si le prix a changé entre-temps.
"""
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction

from catalog.models import ProductVariant
from orders.models import DeliveryZoneOption, Order, OrderItem, OrderStatusHistory
from orders.services import STATUT_ATTENTE_APPROBATION
from users.models import MagasinProfile, Notification


def zones_de_la_boutique(magasin):
    """Zones de livraison actives proposées par une boutique (celles de sa
    société, comme pour les commandes internes)."""
    try:
        admin_profile = magasin.admin.admin_profile
    except Exception:
        return DeliveryZoneOption.objects.none()
    return DeliveryZoneOption.objects.filter(admin_profile=admin_profile, actif=True)


def valider_zone(magasin, code):
    if code == "RECUPERATION":
        return code
    if not zones_de_la_boutique(magasin).filter(code=code).exists():
        raise ValidationError({"livraison_zone": "Zone de livraison invalide pour cette boutique."})
    return code


@transaction.atomic
def create_client_order(*, client, magasin, items, livraison_zone, adresse_livraison="", telephone=None,
                        telephone_2="", mode_paiement="LIVRAISON", note=""):
    """`items` : liste de {"variante": id, "quantite": int, "prix_attendu": Decimal|None}.

    Vérifications, sous verrou (`select_for_update`) pour tenir la concurrence :
    variante active de la boutique, quantité ≥ 1, stock suffisant, prix
    inchangé si `prix_attendu` est fourni. Les erreurs sont des
    ValidationError avec un dictionnaire {champ: message} directement
    renvoyable en 400."""
    if not isinstance(magasin, MagasinProfile):
        raise ValidationError({"boutique": "Boutique introuvable."})
    if not items:
        raise ValidationError({"items": "Ajoutez au moins un article."})
    valider_zone(magasin, livraison_zone)
    if livraison_zone != "RECUPERATION" and not (adresse_livraison or "").strip() and not (client.adresse or "").strip():
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
        client=client,
        client_nom=client.nom,
        telephone=(telephone or client.telephone),
        telephone_2=telephone_2 or "",
        livraison_zone=livraison_zone,
        adresse_livraison=(adresse_livraison or client.adresse or "") if livraison_zone != "RECUPERATION" else "",
        mode_paiement=mode_paiement,
        note_livreur=note or "",
        statut_courant=STATUT_ATTENTE_APPROBATION,
        created_by=None,
    )
    for vid, q in quantites.items():
        # prix_unitaire None -> prix catalogue du moment (OrderItem.save).
        OrderItem.objects.create(order=order, product_variant=par_id[vid], quantite=q)
    order.recompute_total()

    OrderStatusHistory.objects.create(
        order=order, ancien_statut=None, nouveau_statut=STATUT_ATTENTE_APPROBATION, changed_by=None,
        note="Commande passée depuis l'espace client",
    )
    # Le gérant (groupe du magasin + admin, via le signal post_save) est
    # prévenu qu'une commande attend son approbation.
    Notification.objects.create(
        notif_type="order",
        message=f"Commande client {order.numero} en attente d'approbation — {client.nom} ({livraison_zone})",
        magasin=magasin,
    )
    return order


_CLIENT_EDITABLE = {"adresse_livraison", "telephone", "telephone_2", "note", "livraison_zone", "mode_paiement"}


@transaction.atomic
def update_client_order(*, order, data):
    """Modification par le client, uniquement tant que la commande attend
    l'approbation du gérant : coordonnées de livraison, zone, paiement, note.
    Les articles ne se modifient pas : annuler et repasser commande."""
    if order.statut_courant != STATUT_ATTENTE_APPROBATION:
        raise ValidationError(
            f"Cette commande est '{order.get_statut_courant_display()}' — elle ne peut plus être modifiée "
            "depuis l'espace client."
        )
    champs = {k: v for k, v in data.items() if k in _CLIENT_EDITABLE and v is not None}
    if not champs:
        raise ValidationError("Aucune modification demandée.")
    if "livraison_zone" in champs:
        valider_zone(order.magasin, champs["livraison_zone"])
    if "note" in champs:
        order.note_livreur = champs.pop("note")
    for champ, valeur in champs.items():
        setattr(order, champ, valeur)
    if order.livraison_zone == "RECUPERATION":
        order.adresse_livraison = ""
    # save() recalcule les frais depuis la zone, recompute_total le total.
    order.save()
    order.recompute_total()
    return order
