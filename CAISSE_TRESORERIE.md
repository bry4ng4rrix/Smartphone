# Caisse / Trésorerie — documentation technique

Module ajouté le 12/09/2026 autour de la page **Caisse** existante (`/caisse`).
Backend : app Django `finance/` (+ champs sur `users.CaisseMovement`,
`orders.DeliveryZoneOption`, `orders.Order`, `orders.MarketingCampaign`).
Frontend : `frontend/app/(app)/caisse/page.tsx` + `frontend/components/caisse/*`.

## Architecture

```
Vente livrée (orders/services.py::change_order_status → LIVRE)
   └─ finance.services.enregistrer_vente(order)            [même transaction]
        ├─ VenteResultat   : gain réel + répartition (figés, recalculés si boost)
        ├─ Encaissement    : argent de la vente (livreur / comptoir / prépayé)
        │     └─ comptoir & prépayé : entrée en caisse immédiate si session ouverte
        ├─ EpargneMouvement VERSEMENT (part épargne) — référence unique
        └─ recalcul des ventes de la période des boosts couvrant la date

Remise (POST /api/finance/encaissements/remise/)
   ├─ 1 CaisseMovement "in" VENTE:<numéro> par vente (idempotent)
   └─ 1 CaisseMovement "out" TOURNEE:<id> par frais de tournée accepté du livreur

Correction Livré → Retour (orders/services.py::corriger_statut)
   └─ finance.services.annuler_vente : VenteResultat.annule, épargne reprise
      (CORRECTION), remboursement ANNUL:<numéro> si l'argent était en caisse
```

## Modèles

| Modèle | Rôle | Champs clés |
|---|---|---|
| `finance.FinanceSettings` | clé de répartition par société (`AdminProfile`) | `pct_reappro` 60, `pct_epargne` 25, `pct_depenses` 15 — somme = 100 validée |
| `finance.VenteResultat` | gain réel d'une commande livrée (OneToOne `Order`) | `nb_articles`, `ca_produits`, `livraison_client`, `cout_achat`, `frais_agence`, `part_boost`, `gain_reel`, `pct_*` (snapshot), `part_reappro/epargne/depenses`, `annule`, `epargne_active` |
| `finance.Encaissement` | argent d'une vente, du client à la caisse | `source` LIVREUR/COMPTOIR/PREPAYE, `montant`, `statut` EN_ATTENTE/REMIS/ANNULE, `caisse_movement` |
| `finance.EpargneMouvement` | journal du compte d'épargne | `type` VERSEMENT/RETRAIT/CORRECTION, `montant` signé, `solde_apres`, `motif`, `order`, `reference` unique |
| `users.CaisseMovement` (+) | mouvement d'espèces | `origine` (VENTE, FRAIS_LIVRAISON, BOOST, DEPENSE…), `reference` unique (idempotence) |
| `orders.DeliveryZoneOption` (+) | zone | `cout_agence` : conservé en base, **plus utilisé** (ni saisi dans Paramètres) |
| `orders.ExpenseType` (+) | type de dépense | `frais_livraison` : type « frais de livraison » (LIVRAISON 3K / 4K / 5K…) — seules ces dépenses acceptées entrent dans le gain réel et la marge livraison |
| `orders.Order` (+) | commande | `frais_agence` : coût de livraison saisi explicitement pour cette commande (prioritaire) |
| `orders.MarketingCampaign` (+) | boost / publicité par période | `type_periode` JOUR/SEMAINE/MOIS/PERSONNALISE, `montant`, `date_debut`, `date_fin` |

Tous les montants sont des `Decimal` (2 décimales, arrondi demi-supérieur).

## Formules (backend = source de vérité, `finance/services.py`)

```
gain réel = (prix de vente + livraison facturée au client)
            − prix d'achat − frais de livraison acceptés − part de boost

frais de livraison acceptés = dépenses des livreurs ACCEPTÉES par le gérant,
                              des seuls types marqués « frais de livraison »
                              dans Paramètres (LIVRAISON 3K / 4K / 5K…) —
                              repas, enveloppes, NAP exclus. Même chiffre que
                              le rapport Dépenses « Livraison : facturé au
                              client vs coût réel ». Par vente : le total du
                              jour du livreur est réparti à parts égales entre
                              ses commandes livrées ce jour-là (VenteResultat
                              .frais_agence) ; sur une période, le bloc
                              « gain » affiche la Σ exacte des dépenses.
                              `Order.frais_agence` (coût saisi sur une
                              commande) garde la priorité ; le `cout_agence`
                              des zones n'est plus utilisé.

part de boost d'un article = montant du boost / nombre RÉEL d'articles vendus
                             (commandes livrées, articles rapportés exclus)
                             sur la période exacte du boost ; 0 si aucun article
part de boost d'une vente  = Σ (coût/article de chaque boost couvrant la date) × nb articles

résultat livraison = livraison facturée − frais de livraison acceptés   (négatif = perte affichée)

répartition (gain > 0) : réappro = gain × 60 % ; épargne = gain × 25 % ;
                         dépenses = gain − réappro − épargne (absorbe l'arrondi)
gain ≤ 0               : aucune part, aucun versement d'épargne, "PERTE RÉELLE" affichée
```

Scénario de référence (testé) : achat 6 000, vente 25 000, livraison client
3 000, agence 4 000, boost 20 000 / 20 articles → gain 17 000 → 10 200 / 4 250 / 2 550.

**Pourquoi la part de boost est recalculée** : tant que la période du boost
court, le nombre d'articles vendus augmente ; une part figée à la première
vente serait fausse. À chaque vente ou modification de boost, toutes les
ventes de la période sont recalculées et l'épargne est alignée par une
écriture CORRECTION (traçable dans l'historique).

## Indicateurs (GET /api/finance/dashboard/)

| Indicateur | Calcul |
|---|---|
| Espèces disponibles | solde de caisse − épargne accumulée |
| Solde de caisse | session ouverte : fond + entrées − sorties ; sinon dernier montant compté |
| Valeur du stock | Σ stock actuel × prix d'achat (variantes en stock > 0) |
| Argent en attente | Σ `Encaissement` EN_ATTENTE (chez les livreurs + à enregistrer au comptoir) |
| Épargne accumulée | dernier `solde_apres` du journal d'épargne |

L'épargne est un compte **réservé** à l'intérieur de la trésorerie : un
versement ne crée pas de sortie de caisse (l'argent reste physiquement dans
la caisse mais n'est plus « disponible ») ; un retrait libère la réserve. Si
l'argent est physiquement sorti, enregistrer en plus une sortie de caisse
« Retrait ». `epargne_couverte = false` signale une épargne supérieure aux
espèces en caisse.

## Endpoints (`/api/finance/`, gérant uniquement — `IsGerant`)

| Méthode | URL | Rôle |
|---|---|---|
| GET | `dashboard/?magasin_id&date_from&date_to` | indicateurs, gain + répartition de la période, livraison (jour/semaine/mois/période), boosts, encaissements en attente, épargne |
| GET | `journal/?…&origine` | mouvements de caisse avec `solde_apres` |
| GET | `ventes/?…` | gain réel par vente |
| GET / PATCH | `settings/?magasin_id` | pourcentages (refus si ≠ 100 %) |
| GET | `epargne/?magasin_id` | solde + historique |
| POST | `epargne/retrait/` `{montant, motif, confirmation: true}` | retrait (≤ solde, confirmation obligatoire) |
| GET | `encaissements/?magasin_id` | en attente, groupés par livreur (brut, frais, net) |
| POST | `encaissements/remise/` `{livreur_id \| encaissement_ids}` | remise en caisse (session ouverte requise) |
| POST | `recalculer/` `{date_from, date_to}` | recalcul d'une plage (après changement de coût de zone / prix d'achat) |

Existant réutilisé : `/api/users/caisse/*` (sessions, mouvements, catégories),
`/api/orders/campaigns/` (boosts — champs calculés `articles_vendus`,
`cout_par_article`, `en_caisse`, et, depuis l'affectation automatique par
période, `nb_commandes`, `nb_livrees`, `ca`, `cout_par_commande`,
`periode_effective` ; option `en_caisse: true` à la création),
`/api/orders/delivery-zones/`, `/api/orders/expense-types/` (`frais_livraison`). L'acceptation d'une dépense « frais de livraison » (`expenses/{id}/resoudre/`) et le changement du marqueur sur un type recalculent les ventes des jours concernés.

Affectation commande ↔ boost : AUTOMATIQUE par période
(`finance/services.py::commandes_du_boost`, source unique pour la caisse, le
rapport Marketing et les commandes) — `date_commande` (jour local) entre
`date_debut` et `date_fin` bornes comprises, boost en cours = jusqu'à
aujourd'hui, annulées exclues, boost inactif = rien. Chevauchement : chaque
boost est réparti sur sa propre période, une vente de la zone commune
supporte une part de chacun. Création / modification (montant, dates,
`actif`) / suppression → `recalculer_apres_boost` recalcule l'union ancienne
+ nouvelle période. `dashboard/ → boosts[]` porte les mêmes champs.

Durcissements : ouverture de session et création de mouvement sous verrou
(`select_for_update`) ; un mouvement automatique (avec `reference`) ou d'une
session fermée ne peut pas être supprimé ; montant d'un mouvement > 0 ;
une saisie manuelle ne peut pas porter une origine réservée (VENTE…).

## Permissions

Tout `/api/finance/` et la caisse : gérant (`admin`/`magasin`). Le livreur ne
voit ni coûts, ni gains, ni soldes (403). Les valeurs calculées ne sont jamais
acceptées en entrée : le frontend n'envoie que des intentions (retrait,
remise, paramètres, boost).

## Cas limites

| Cas | Comportement |
|---|---|
| Rejeu / double clic / retry | références uniques (`VENTE:`, `VERSEMENT:`, `TOURNEE:`, `ANNUL:`, `BOOST:`), OneToOne sur la commande → aucun doublon |
| Vente corrigée en retour | résultat annulé, épargne reprise, remboursement en caisse si déjà remis (caisse ouverte requise), encaissement ANNULE |
| Retour → Livré | ré-enregistrement sans doublon (correction d'épargne « vente rétablie ») |
| Commande annulée (non terminale) | aucun impact trésorerie (rien n'avait été vendu) |
| Livraison partielle | seuls les articles remis comptent (`retourne=False`), montant = total recalculé |
| Plusieurs articles / quantité > 1 | `nb_articles` = Σ quantités, coût et part de boost proportionnels |
| Aucun boost | part de boost 0 |
| Boost sans article vendu | coût/article 0, pas de division par zéro, état affiché |
| Boost > CA | gain négatif possible → « PERTE RÉELLE », pas de répartition |
| Retrait > épargne | refusé (400) |
| Paramètres ≠ 100 % | refusé (400) avec message explicite |
| Remise sans caisse ouverte | refusée (400) |
| Ventes antérieures au module | `manage.py finance_backfill` calcule le gain (`epargne_active=False`, pas d'encaissement) |
| Concurrence | verrous magasin / session dans les transactions |

Double comptage évité dans les rapports (`orders/reporting.py`,
`orders/reports.py`) : les sorties `TOURNEE:` (frais de tournée déjà comptés
via `LivreurExpense`) et `ANNUL:` sont exclues des sorties de caisse.

## Tests

`python manage.py test finance` — 20 tests (`finance/tests.py`) : gain réel de
référence, coût boost/article, perte livraison, répartition et somme,
paramètres 100 %, idempotence des mouvements, retrait d'épargne, périodes
jour/semaine/mois, boost sans vente, gain négatif, recalcul de période,
remise avec frais de tournée, remise sans caisse, annulation après remise,
livraison partielle, API (settings, dashboard, journal, retrait, suppression
interdite, livreur 403).
