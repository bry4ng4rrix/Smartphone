# Matrice des droits — ADMIN GLOBAL / GÉRANT / PRÉPARATEUR / LIVREUR

Référence du modèle d'autorisation. Complète `fonctionalite.txt`.

## Les deux axes à ne pas confondre

Le projet a **deux notions distinctes**, et les confondre casse les workflows :

| Axe | Où | Valeurs |
| --- | --- | --- |
| **Niveau d'autorisation** | `CustomUser.role` | `admin` · `magasin` · `employer` |
| **Rôle du module Commande** | `user_commande_role()` | `GERANT` · `PREPARATEUR` · `LIVREUR` |

`user_commande_role()` répond `"GERANT"` pour **`admin` ET `magasin`** : c'est
voulu, il décrit qui pilote le workflow d'une commande, pas qui a le droit de
voir la trésorerie.

Conséquence pratique :

- `IsGerant` → admin **+** gérant de magasin. Commandes, dépenses livreur.
- `IsAdmin` → admin global **seul**. Caisse, finance, fournisseurs, transferts,
  marketing, rapports chiffrés, comptes.

## Comptes

| | |
| --- | --- |
| Propriétaire | `admin@smartphone.mg` (`role="admin"`, porte l'`AdminProfile`) |
| Co-admin | `role="admin"` sans `AdminProfile` — mêmes données, pas la propriété |
| Gérant de magasin | `role="magasin"`, `MagasinProfile.user` |
| Préparateur / Livreur | `role="employer"` + `EmployerProfile.commande_role` |

## Matrice

| Module | ADMIN | GÉRANT | PRÉPARATEUR | LIVREUR |
| --- | :---: | :---: | :---: | :---: |
| Tableau de bord | ✅ rapports complets | ✅ exploitation, son magasin | ❌ | ❌ |
| Commandes | ✅ toutes | ✅ son magasin | ✅ à préparer | ✅ sa tournée |
| Produits (CRUD) | ✅ tous | ✅ son magasin | lecture | ❌ |
| Prix de vente | ✅ | ✅ | ✅ par article | ❌ |
| **Prix d'achat / marge / bénéfice** | ✅ | ❌ | ❌ | ❌ |
| Mouvements de stock | ✅ tous | ✅ son magasin | ❌ | ❌ |
| Alertes de stock | ✅ | ✅ son magasin | ❌ | ❌ |
| Bilan du jour | ✅ global | ✅ son magasin | ❌ | ✅ le sien |
| Dépenses / avances livreur | ✅ | ✅ son magasin | ❌ | ✅ déclare |
| Récupération | ✅ | ✅ son magasin | ✅ crée | ❌ |
| Notifications / Chats | ✅ | ✅ | ✅ | ✅ |
| Paramètres (profil, sécurité) | ✅ | ✅ | ✅ | ✅ |
| Zones de livraison / types de dépense | ✅ | ❌ | ❌ | ❌ |
| **Caisse / trésorerie** | ✅ | ❌ | ❌ | ❌ |
| **Finance, épargne, gain réel** | ✅ | ❌ | ❌ | ❌ |
| **Fournisseurs, coûts** | ✅ | ❌ | ❌ | ❌ |
| **Transferts entre magasins** | ✅ | ❌ | ❌ | ❌ |
| **Marketing / boosts** | ✅ | ❌ | ❌ | ❌ |
| Demandes clients (approuver / refuser) | ✅ | ✅ son magasin | ❌ | ❌ |
| **Magasins, comptes** | ✅ | ❌ | ❌ | ❌ |

Les zones de livraison et les types de dépense sont rattachés à
l'`AdminProfile` : ils sont **partagés par tous les magasins**. Les modifier
depuis une boutique changerait les tarifs des autres — d'où la réserve à
l'admin.

**Les demandes venues de la boutique en ligne sont traitées par le gérant**
(page « Clients », `POST /api/orders/{id}/approuver/` et `/refuser/`,
permission `IsGerant`). C'est lui qui rappelle la personne au numéro laissé
sur le site avant de lancer la préparation : faire passer chaque commande par
l'admin aurait bloqué le circuit. Son périmètre reste tenu par le serveur —
`get_accessible_magasins` ne lui montre que les commandes de **sa** boutique.

Un panier en ligne peut mêler plusieurs boutiques ; le serveur l'éclate en une
commande par magasin propriétaire des articles
(`clients/services.py::magasins_des_items`). Chaque gérant n'approuve donc que
sa part, sans voir celle de l'autre.

Le gérant garde les coordonnées client portées par chaque commande (nom,
téléphone, adresse, zone). Il n'a pas de **module** de gestion d'un fichier
clients — il n'en existe plus : la boutique en ligne ne crée pas de comptes.

## Endpoints réservés à l'admin global

```
/api/finance/*                      trésorerie, gain réel, épargne
/api/suppliers/*                    approvisionnements, coûts
/api/users/caisse/*                 sessions, mouvements, résumé
/api/users/transfer/products/       transfert inter-magasins
/api/orders/campaigns/              campagnes marketing (lecture comprise)
/api/orders/dashboard/              dashboard chiffré
/api/orders/reports/*               les 8 rapports
/api/catalog/references/bulk-update-price/   modifie le prix d'achat
/api/catalog/references/export-excel/        colonne prix d'achat
/api/catalog/references/import-excel/        renseigne le prix d'achat
/api/orders/delivery-zones/   (écriture)     réglage de société
/api/orders/expense-types/    (écriture)     réglage de société
/api/users/employers/<id>/commande-role/     administration des comptes
```

Le gérant dispose de `/api/orders/dashboard-gerant/`, qui ne lit jamais
`prix_achat`.

## Cloisonnement entre magasins

Le périmètre vient de `get_accessible_magasins()` :

| Rôle | Magasins |
| --- | --- |
| `admin` | ceux dont il est `admin` (FK) ou `admins` (M2M) |
| `magasin` | le sien |
| `employer` | celui de son affectation |

Forcer `?magasin_id=` ne contourne rien : les querysets filtrent d'abord sur
cet ensemble, et `resolve_magasin_for_request()` refuse un id hors périmètre.
Accéder à un objet d'un autre magasin par son identifiant renvoie `404` — pas
`403`, pour ne pas révéler son existence.

## Les quatre niveaux d'interdiction

Une fonctionnalité fermée au gérant l'est à quatre endroits (mission § 39) :

1. **Menu** — `sidebar.tsx` (`superAdminOnly`), `nav_items.dart`
2. **Routage** — garde dans la page Next.js, `canAccessPath()` en Flutter
3. **API** — `permission_classes = [IsAdmin]`
4. **Données** — `ProductReferenceGerantSerializer` sans `prix_achat`, KPI de
   bénéfice retirés du dashboard

Les niveaux 1 et 2 sont du confort : ils évitent d'arriver sur un écran
d'erreur. **Seuls les niveaux 3 et 4 protègent réellement** — c'est pour ça
que les tests tapent l'API directement.

## Tests

```
users/test_droits_gerant.py          14 tests — deux magasins, deux gérants
finance/tests.py::test_gerant_de_magasin_interdit
users/test_renommer_proprietaire.py   6 tests — renommage du propriétaire
```

`users/test_droits_gerant.py::champs_sensibles` parcourt **récursivement**
chaque réponse API et échoue si un champ de coût apparaît, même imbriqué sous
`order → items → product`.
