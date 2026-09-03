# Smartphone.Mg — Madagascar

## Application de gestion Commandes, Stock & Livraisons

Cahier des charges du projet

---

## 1. Contexte & problème à résoudre

**Entreprise :** Smartphone.Mg (Madagascar)
**Canaux de vente actuels :** Facebook (messages) + ventes sur place
**Organisation actuelle :** commandes et livraisons gérées manuellement (notes + tableurs), stock imprécis.

### Douleurs principales

- Gestion de stock manuelle et imprécise.
- Pas de visibilité sur le coût de revient ni les bénéfices réels.
- Suivi des commandes via notes manuscrites envoyées au dépôt.
- Aucune coordination digitale entre gérant, préparateur et livreur.
- Impossible de savoir quels produits se vendent le plus.
- Réapprovisionnement fournisseur non structuré (pas de liste claire, pas d'historique fiable).
- Besoin de gérer aussi des coûts additionnels : import/douane, Meta Ads, salaires.

---

## 2. Objectifs du projet

**Objectif global :** remplacer le processus manuel par une application professionnelle **Web + iOS + Android**, avec traçabilité complète.

### Objectifs fonctionnels

- Saisir et suivre chaque commande de A à Z (Facebook, par appel → livraison ou récupération).
- Gérer le stock en temps réel avec alertes de rupture/stock bas.
- Donner au gérant une vue financière complète (CA, bénéfices, coût de revient).
- Permettre au préparateur de voir et valider ses commandes sur mobile.
- Permettre au livreur de gérer sa tournée et marquer les livraisons/retours.
- Gérer les commandes fournisseurs et calculer le coût de revient réel (marchandise Chine + import/fret + douane) + intégrer Meta Ads + salaires dans le pilotage.

---

## 3. Périmètre (MVP recommandé)

### MVP (version 1)

- [ ] Commandes (création + workflow 6 statuts + historiques)
- [ ] Stock (catalogue + variantes + déduction/réinjection automatique + seuils + mouvements)
- [ ] Dépôt (préparateur) : liste + action « Commande prête »
- [ ] Livreur : tournée + actions « Livré » / « Retour » + note
- [ ] Ruptures & réapprovisionnement : liste auto + quantité à commander + export PDF/partage
- [ ] Dashboard gérant : KPIs + filtres dates + TOP produits
- [ ] Gestion utilisateurs & droits (gérant/préparateur/livreur)
- [ ] Notifications push (nouvelle commande → préparateur, commande prête → livreur)

### Hors périmètre (à discuter / version 2)

- Intégration automatique Facebook/Meta (API) : au départ saisie manuelle
- Paiements en ligne, facturation fiscale, POS complet
- Multi-boutiques, multi-entrepôts
- Comptabilité complète (au-delà du pilotage)

---

## 4. Utilisateurs, rôles & droits

3 profils avec droits stricts :

### 🔑 Gérant

- Accès complet à tous les modules.
- Seul à pouvoir modifier manuellement le stock (entrées après fournisseur, corrections).
- Accès à toutes les données financières (coûts, marges, CA, ads, etc.).

### 📦 Préparateur

- Accès uniquement au module commandes dépôt (lecture des infos nécessaires).
- Peut uniquement changer le statut sur les étapes qui lui appartiennent.
- Ne voit aucune donnée financière.

### 🚚 Livreur

- Accès uniquement à sa tournée (commandes prêtes/en livraison du jour).
- Peut uniquement changer le statut sur les étapes qui lui appartiennent.
- Ne voit aucune donnée financière.

---

## 5. Workflow commande (statuts, responsabilités, règles)

Chaque commande passe par 6 statuts successifs. Chaque acteur ne peut modifier que « son » statut.

| Statut         | Responsable | Action                                  |
| -------------- | ----------- | --------------------------------------- |
| Nouvelle       | Gérant      | Saisit la commande depuis Facebook      |
| En préparation | Préparateur | Commence à préparer                     |
| Prête          | Préparateur | Marque prête, livreur averti            |
| En livraison   | Livreur     | Récupère le colis, démarre la livraison |
| Livré          | Livreur     | Marque livré                            |
| Retour         | Livreur     | Marque retour                           |

### Règle critique stock

- Le stock est mis à jour **automatiquement** uniquement au statut « **Livré** » (déduction).
- En cas de « **Retour** », le stock est réintégré automatiquement.
- Aucun autre statut ne doit impacter le stock.

### Contraintes de transitions

- Impossible de sauter un statut (sauf si le gérant a un droit « admin override » à discuter).
- Toutes les modifications de statut doivent être historisées (date/heure + utilisateur).

---

## 6. Formulaire « Nouvelle commande » (vente Facebook)

| Champ           | Comportement                                                        | Validation           |
| --------------- | ------------------------------------------------------------------- | -------------------- |
| Date commande   | Auto = aujourd'hui, modifiable                                      | Format DD/MM/YYYY    |
| Nom client      | Saisie libre                                                        | Obligatoire          |
| Téléphone       | Pré-rempli « +261 », compléter le reste                             | Format +261XXXXXXXXX |
| Type produit    | Liste : FLIP COVER / Z-FOLD / Z-FLIP / PRIVACY                      | Obligatoire          |
| Marque          | Auto selon type — liste filtrée                                     | Obligatoire          |
| Référence       | Recherche autocomplete dans le catalogue                            | Obligatoire          |
| Couleur         | Auto selon référence choisie — liste des couleurs dispo             | Obligatoire          |
| Prix (Ar)       | Auto depuis le catalogue — non modifiable                           | Lecture seule        |
| Livraison       | Zone 1 (3 000) / Zone 2 (4 000) / Zone 3 (5 000) / Récupération (0) | Obligatoire          |
| Frais livraison | Calcul auto selon zone                                              | Non modifiable       |
| Total à payer   | Prix + Frais livraison                                              | Non modifiable       |
| Note            | Libre                                                               | Optionnel            |

> **Numéro de commande :** généré automatiquement (ex : incrémental + date), affiché partout.

---

## 7. Modules (détaillés)

### 7.1 Module Commandes (Gérant)

- Création commande (formulaire ci-dessus)
- Liste commandes (tableau filtrable par date / statut / produit)
- Détail commande (infos client, produit, statut, historique, notes)
- Suivi temps réel des statuts
- Export (optionnel) : CSV/PDF par période

### 7.2 Module Dépôt — Préparateur (Mobile)

_UX : mobile simplifié, lecture seule sauf statut._

- Liste des commandes avec statut « Nouvelle » ou « En préparation »
- Affiche : N° commande, Client, Produit + Couleur, Zone livraison
- Action unique : bouton « Commande prête »
- Push notification dès qu'une nouvelle commande est créée par le gérant
- Aucune donnée financière visible

### 7.3 Module Livreur (Mobile)

_UX : ultra simplifié, orienté tournée._

- Liste des commandes avec statut « Prête » à récupérer
- Liste des commandes « En livraison » du jour (pour suivi)
- Affiche : N° commande, Client, Téléphone cliquable, Produit, Zone, Total à encaisser
- Actions : « Livré » | « Retour »
- Note livreur possible (ex : « client absent »)
- Push notification quand une commande passe au statut « Prête »

### 7.4 Module Gestion du Stock (Gérant)

- Vue séparée par sous-type : FLIP COVER / Z-FOLD / Z-FLIP / PRIVACY
- Chaque produit affiche : Marque, Référence, Couleur, Stock actuel, Seuil alerte, Statut
- Stock déduit automatiquement à chaque « Livré »
- Stock réintégré automatiquement à chaque « Retour »
- Alerte automatique si stock ≤ seuil (notification + indicateur visuel)
- Modification manuelle du stock possible par le gérant uniquement (entrée de stock après fournisseur + corrections)
- Historique mouvements de stock : entrée/sortie/date/origine (commande client / commande fournisseur / ajustement)

### 7.5 Module Ruptures & Réapprovisionnement (Gérant)

- Liste automatique des produits : Rupture (stock = 0) / Stock bas (stock ≤ seuil)
- Regroupement par catégorie/sous-type et marque
- Colonne « Quantité à commander » éditable
- Bouton « Exporter en PDF / partager » pour envoyer au fournisseur
- Historique des listes/export (optionnel) + lien vers commandes fournisseurs

### 7.6 Module Commandes Fournisseur (Gérant)

**Objectif :** suivre chaque commande fournisseur jusqu'au coût de revient réel.

**Données à saisir par commande fournisseur :**

- N° commande fournisseur, Date
- Type de produit, Description, Quantité
- Prix fournisseur (Ar)
- Frais fret/importation (Ar)
- Droits de douane (Ar)
- Budget pub Meta Ads (Ar) — imputable à la période

**Calculs automatiques :**

- Coût total = fournisseur + Fret + Douane + Pub
- Coût unitaire = Coût total ÷ Quantité
- Marge unitaire = Prix vente − Coût unitaire

**Impact stock :**

- À la réception/validation (statut à définir), le gérant enregistre l'entrée stock par produit/variant.
- Chaque entrée crée des mouvements stock « entrée fournisseur ».

### 7.7 Dashboard Gérant (Web)

Filtrable par date : jour, semaine, mois ou intervalle libre.

**KPIs :**

- Nombre de ventes sur la période
- CA période (Ar) et CA du mois en cours
- Taux de livraison réussie (%)
- Nombre de retours

**Suivi commandes temps réel :**

- Nouvelles / En préparation / Prêtes / En livraison
- Livrées et retours (sur période filtrée)

**Analyse financière :**

- CA produits vendus (Ar)
- Frais de livraison encaissés (Ar)
- Total investi fournisseurs (Ar)
- Total pub Meta Ads (Ar)
- **Bénéfice estimé = CA + Livraisons − Fournisseurs − Pub**

**Analyses produits — TOP 20 :**

- Produit le plus vendu par sous-type
- Marque la plus vendue
- Référence la plus vendue
- Couleur la plus vendue

**Stock rapide :**

- Résumé par type : total en stock, ruptures, stock bas

---

## 8. Catalogue produits & structure de données

### 8.1 Catalogue principal (actuel)

L'application gère 2 catégories principales et 4 sous-types :

- **HOUSSE**
  - FLIP COVER (Samsung, iPhone, Huawei, Redmi, Xiaomi, Tecno, Infinix, Itel, Oppo…)
  - Z-FOLD (Samsung)
  - Z-FLIP (Samsung)
- **CACHE ÉCRAN**
  - PRIVACY (Samsung, iPhone, Redmi, Infinix, Tecno, Oppo, Realme, Google Pixel…)

> **Important — Précision sur les marques et références :** pour chaque marque, il existe un grand nombre de références de téléphones différentes, et chaque marque doit regrouper toutes les références de modèles correspondants. Par exemple, pour la marque Samsung, on retrouve notamment : A15, A16, S21 Ultra, S22, S23, S24, S25 Ultra, Z-Fold, Z-Flip, et bien d'autres modèles. Il en va de même pour chaque autre marque (iPhone, Huawei, Redmi, Xiaomi, Tecno, Infinix, Itel, Oppo, Realme, Google Pixel…) : chaque marque contient l'ensemble des références de tous les téléphones correspondants, et la structure du catalogue doit permettre d'ajouter facilement de nouvelles références à une marque existante sans limite prédéfinie.

**Structure d'un produit (variant) :**

- Catégorie
- Sous-type
- Marque
- Référence
- Couleur
- Prix vente
- Stock
- Seuil alerte

**Volume :** total actuel : ~360 produits catalogués (source : export Loyverse + fichier XLS Cache Écran)

### 8.2 Produits « autres » (ex : chargeur)

D'autres produits (chargeur…) où c'est surtout « référence + couleur + quantité ».

**Recommandation :** prévoir une structure de catalogue flexible avec :

- Catégorie personnalisable (ex : « CHARGEUR », « CÂBLE », etc.)
- Attributs minimum communs : Nom/Référence, Couleur (optionnelle), Prix vente, Stock, Seuil
- Possibilité d'avoir des variantes (couleurs) ou pas

---

## 9. Notifications (push) & évènements

### Évènements

- Quand une commande est créée (statut « Nouvelle ») → notification au **Préparateur**.
- Quand le préparateur marque « Prête » → notification au **Livreur**.

### Contraintes

- Les notifications doivent contenir : N° commande + client + zone + produit (résumé).
- Le clic ouvre directement la commande dans l'app (deep link si possible).

---

## 10. Exigences techniques (attendues par un dev)

### Plateformes

- Web (gérant principalement)
- Mobile iOS + Android (préparateur + livreur)
- Même si « iOS uniquement » a pu être mentionné sur certains écrans, l'objectif initial est iOS + Android, donc le développeur doit prévoir les deux.

### Sécurité / accès

- Authentification (email/téléphone + mot de passe, ou méthode simple à définir)
- RBAC (Role Based Access Control) strict : gérant / préparateur / livreur
- Journalisation : qui a changé quel statut et quand

### Données / traçabilité

- Historique statuts commandes
- Historique mouvements stock (source obligatoire)
- Données financières non visibles par préparateur/livreur

### Exports

- PDF/partage pour liste de réapprovisionnement (format simple lisible fournisseur)

---

## 11. Modèle de données (proposition simple pour cadrer le dev)

| Entité                      | Champs                                                                                                                                                                      |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **User**                    | id, nom, rôle (GERANT / PREPARATEUR / LIVREUR), téléphone, actif                                                                                                            |
| **ProductCategory**         | id, nom (HOUSSE, CACHE ÉCRAN, CHARGEUR…), ordre                                                                                                                             |
| **ProductType** (Sous-type) | id, category_id, nom (FLIP COVER, Z-FOLD, Z-FLIP, PRIVACY…)                                                                                                                 |
| **Brand**                   | id, nom                                                                                                                                                                     |
| **ProductReference**        | id, type_id, brand_id, reference_name (ex : « A15 », « S25 Ultra », « 15 Pro Max »), prix_vente (Ar), actif                                                                 |
| **ProductVariant**          | id, product_reference_id, couleur, stock_actuel, seuil_alerte                                                                                                               |
| **Order**                   | id, numero, date_commande, client_nom, telephone, livraison_zone, frais_livraison, total_a_payer, note, statut_courant                                                      |
| **OrderItem**               | id, order_id, product_variant_id, prix_unitaire (snapshot), quantite (souvent 1)                                                                                            |
| **OrderStatusHistory**      | id, order_id, ancien_statut, nouveau_statut, changed_by_user_id, timestamp, note_eventuelle                                                                                 |
| **StockMovement**           | id, product_variant_id, type (ENTREE/SORTIE), quantite, origine (LIVRE, RETOUR, FOURNISSEUR, AJUSTEMENT), reference (order_id / supplier_order_id), timestamp, user_id      |
| **SupplierOrder**           | id, numero, date, description, statut (Brouillon/Commandé/Reçu…), total_qty, prix_fournisseur (Ar), fret_import (Ar), douane (Ar), meta_ads (Ar), cout_total, cout_unitaire |
| **SupplierOrderLine**       | id, supplier_order_id, product_variant_id, quantite, cout_unitaire_calcule (snapshot), total_ligne                                                                          |

---

## 12. Critères d'acceptation (tests simples à exiger)

- [ ] Si le livreur clique « Livré », le stock du produit est diminué automatiquement (quantité commandée).
- [ ] Si le livreur clique « Retour », le stock est réintégré automatiquement.
- [ ] Si la commande passe « Prête », le livreur reçoit une notification.
- [ ] Le préparateur ne peut pas voir : coût, bénéfice, prix fournisseur, Meta Ads, etc.
- [ ] Le livreur ne peut changer que les statuts « En livraison », « Livré », « Retour ».
- [ ] Le gérant peut filtrer le dashboard par période et voir : CA, retours, taux livraison, TOP produits.
- [ ] Ruptures : un produit avec stock = 0 apparaît en rupture, stock ≤ seuil apparaît en stock bas.
- [ ] Format téléphone forcé +261XXXXXXXXX.
- [ ] Le prix produit (Ar) dans la commande est en lecture seule et vient du catalogue (snapshot recommandé pour conserver l'historique si le prix change plus tard).

---

## 13. Développement (app Flutter)

Frontend Flutter consommant l'API Django de `../Smartphone_mg` (voir `../Smartphone_mg/endpoint.md`). Architecture et conventions reprises de `valhery_wear` (Riverpod, go_router, Dio + refresh JWT auto, stockage sécurisé, WebSocket temps réel), fonctionnalités inspirées de `Stock_v2` (dashboard par rôle, mouvements de stock, ruptures).

### Lancer l'app

```bash
flutter pub get
flutter run -d linux   # ou -d chrome / un device Android connecté
```

Au premier lancement, l'écran de connexion propose « Configurer le serveur » (icône ⚙️) pour pointer vers l'URL du backend (par défaut `http://10.0.2.2:8010` sur émulateur Android, `http://127.0.0.1:8010` ailleurs).

### Lancer le backend (dev)

```bash
cd ../Smartphone_mg
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 0.0.0.0:8010
```

Comptes de test (`python manage.py seed_catalog`) : `gerant@smartphone.mg` / `preparateur@smartphone.mg` / `livreur@smartphone.mg`, mot de passe `test1234`.

### Architecture

```
lib/
  core/        api_client.dart (Dio + refresh JWT), constants.dart (rôles/statuts),
               router.dart (go_router, redirections par rôle), theme.dart, ws_manager.dart
  models/      Order, ProductVariant/Reference, StockMovement, SupplierOrder, AppNotification, DashboardData…
  data/        repositories/ — un repository par domaine, appels Dio purs
  state/       providers/ — Riverpod (Notifier/AsyncNotifier), un par domaine + realtime_provider.dart
               (WebSocket ws/notifications/ → rafraîchit automatiquement commandes/notifications)
  widgets/     navigation_shell.dart (sidebar desktop / drawer mobile), composants partagés
  features/    un dossier par module : auth, dashboard, orders, depot (préparateur),
               tournee (livreur), catalog, stock, suppliers, users, notifications
```

Chaque rôle (GERANT / PREPARATEUR / LIVREUR) a sa propre navigation et ses propres écrans, alignés sur les vues restreintes renvoyées par l'API selon le rôle connecté (§4 README).
