"""Trésorerie (§ mission Caisse) — ce que la caisse seule ne sait pas dire :

* FinanceSettings  : la clé de répartition du gain réel (60/25/15) par société ;
* VenteResultat    : le gain réel de CHAQUE vente livrée, figé côté serveur
                     (prix, coût d'achat, livraison client, frais agence,
                     part de boost) avec sa répartition ;
* Encaissement     : l'argent d'une vente — chez le livreur, à enregistrer au
                     comptoir, ou remis en caisse — et le mouvement de caisse
                     créé à la remise (une seule fois, par référence unique) ;
* EpargneMouvement : le journal du compte d'épargne (versements automatiques,
                     retraits confirmés, corrections), avec solde après opération.

Tous les montants sont des Decimal (jamais de float).
"""

from decimal import Decimal

from django.db import models
from django.utils import timezone

ZERO = Decimal("0")


class FinanceSettings(models.Model):
    """Paramètres financiers d'une société. La somme des trois pourcentages
    doit faire exactement 100 (validée dans clean() et dans le serializer)."""

    admin_profile = models.OneToOneField(
        "users.AdminProfile", on_delete=models.CASCADE, related_name="finance_settings"
    )
    pct_reappro = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("60"))
    pct_epargne = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("25"))
    pct_depenses = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("15"))
    updated_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Paramètres financiers"
        verbose_name_plural = "Paramètres financiers"

    def total_pct(self):
        return self.pct_reappro + self.pct_epargne + self.pct_depenses

    def __str__(self):
        return f"Répartition {self.pct_reappro}/{self.pct_epargne}/{self.pct_depenses}"


class VenteResultat(models.Model):
    """Gain réel d'une vente livrée :

        gain_reel = (ca_produits + livraison_client)
                    − cout_achat − frais_agence − part_boost

    `part_boost` (et donc `gain_reel`) est recalculé pour toutes les ventes
    d'une période de boost à chaque changement (boost créé/modifié, nouvelle
    vente dans la période) : la part par article ne se connaît qu'avec le
    nombre total d'articles vendus sur la période."""

    order = models.OneToOneField("orders.Order", on_delete=models.CASCADE, related_name="resultat")
    magasin = models.ForeignKey("users.MagasinProfile", on_delete=models.CASCADE, related_name="ventes_resultats")
    date_vente = models.DateField()
    nb_articles = models.PositiveIntegerField(default=0)
    ca_produits = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    livraison_client = models.DecimalField(max_digits=10, decimal_places=2, default=ZERO)
    cout_achat = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    frais_agence = models.DecimalField(max_digits=10, decimal_places=2, default=ZERO)
    part_boost = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    gain_reel = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    # Clé de répartition appliquée (figée : un changement de paramètres ne
    # réécrit pas le passé) et parts calculées. Gain ≤ 0 → parts à 0.
    pct_reappro = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    pct_epargne = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    pct_depenses = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    part_reappro = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    part_epargne = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    part_depenses = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    # Vente corrigée en retour après coup : conservée pour l'audit, exclue des totaux.
    annule = models.BooleanField(default=False)
    # False pour les ventes reprises de l'historique (avant le module) : le
    # gain est calculé, mais aucun versement d'épargne n'est généré.
    epargne_active = models.BooleanField(default=True)
    calcule_le = models.DateTimeField(default=timezone.now)
    maj_le = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Résultat de vente"
        verbose_name_plural = "Résultats de vente"
        ordering = ["-date_vente", "-id"]

    @property
    def resultat_livraison(self):
        return self.livraison_client - self.frais_agence

    def __str__(self):
        return f"{self.order.numero} : gain {self.gain_reel}"


class Encaissement(models.Model):
    """Argent d'une vente livrée, du client jusqu'à la caisse."""

    SOURCES = (
        ("LIVREUR", "Encaissé par le livreur"),
        ("COMPTOIR", "Encaissé au comptoir"),
        ("PREPAYE", "Payé d'avance"),
    )
    STATUTS = (
        ("EN_ATTENTE", "En attente"),
        ("REMIS", "Remis en caisse"),
        ("ANNULE", "Annulé"),
    )

    order = models.OneToOneField("orders.Order", on_delete=models.CASCADE, related_name="encaissement")
    magasin = models.ForeignKey("users.MagasinProfile", on_delete=models.CASCADE, related_name="encaissements")
    livreur = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="encaissements"
    )
    source = models.CharField(max_length=10, choices=SOURCES)
    montant = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    statut = models.CharField(max_length=12, choices=STATUTS, default="EN_ATTENTE")
    remis_le = models.DateTimeField(null=True, blank=True)
    remis_par = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="remises_validees"
    )
    caisse_movement = models.OneToOneField(
        "users.CaisseMovement", on_delete=models.SET_NULL, null=True, blank=True, related_name="encaissement"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Encaissement"
        verbose_name_plural = "Encaissements"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.order.numero} {self.montant} ({self.get_statut_display()})"


class EpargneMouvement(models.Model):
    """Journal du compte d'épargne. `montant` est signé : + versement,
    − retrait, ± correction. `solde_apres` est figé à l'écriture."""

    TYPES = (
        ("VERSEMENT", "Versement automatique"),
        ("RETRAIT", "Retrait"),
        ("CORRECTION", "Correction"),
    )

    magasin = models.ForeignKey("users.MagasinProfile", on_delete=models.CASCADE, related_name="epargne_mouvements")
    type = models.CharField(max_length=12, choices=TYPES)
    montant = models.DecimalField(max_digits=12, decimal_places=2)
    solde_apres = models.DecimalField(max_digits=12, decimal_places=2)
    motif = models.CharField(max_length=255, blank=True)
    order = models.ForeignKey(
        "orders.Order", on_delete=models.SET_NULL, null=True, blank=True, related_name="epargne_mouvements"
    )
    # Idempotence des versements automatiques ("VERSEMENT:<numéro de commande>").
    reference = models.CharField(max_length=80, unique=True, null=True, blank=True)
    created_by = models.ForeignKey(
        "users.CustomUser", on_delete=models.SET_NULL, null=True, blank=True, related_name="epargne_mouvements"
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        verbose_name = "Mouvement d'épargne"
        verbose_name_plural = "Mouvements d'épargne"
        ordering = ["-created_at", "-id"]

    def __str__(self):
        return f"{self.get_type_display()} {self.montant} → {self.solde_apres}"
