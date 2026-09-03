# Historique des modifications backend (pour la version Flutter)

Ce fichier liste les changements d'API backend qui **changent le contrat**
attendu par un client (endpoint, requête, réponse) et qui doivent donc être
répercutés dans l'app mobile Flutter (`valhery_wear`). Contrairement à
`memory.md` (journal complet de toutes les sessions), ce fichier ne
contient que ce qui impacte concrètement le client mobile — une entrée par
changement d'API, la plus récente en haut.

---

## 2026-08-06 — Heures d'ouverture/fermeture de caisse personnalisables

Migration `0018_alter_caissesession_opened_at` : `CaisseSession.opened_at`
n'est plus `auto_now_add` (défaut `timezone.now`, mais overridable).

### `POST /api/users/caisse/sessions/open/` (contrat étendu, pas cassant)
Nouveau champ optionnel `opened_at` (ISO 8601). Absent → comportement
inchangé (`now()`). Présent → utilisé tel quel, avec validation :
- `400 { "error": "Heure d'ouverture invalide (format attendu : ISO 8601)." }`
- `400 { "error": "Heure d'ouverture ne peut pas être dans le futur." }`

### `POST /api/users/caisse/sessions/<id>/close/` (contrat étendu, pas cassant)
Même principe avec `closed_at` (optionnel, ISO 8601) :
- Mêmes erreurs de format/futur que ci-dessus (avec "Heure de fermeture").
- `400 { "error": "L'heure de fermeture ne peut pas être avant l'heure d'ouverture." }`

### Côté Flutter — ✅ fait (2026-08-06, `valhery_wear`)
`open_caisse_dialog.dart`/`close_caisse_dialog.dart` ont un champ date/heure
(`showDatePicker`+`showTimePicker`, pré-rempli à "maintenant", modifiable) ;
`caisse_repository.dart`/`caisse_provider.dart` envoient toujours
`opened_at`/`closed_at` (ISO 8601 via `DateTime.toIso8601String()` — envoyer
la valeur même égale à "maintenant" est sans effet, le backend l'accepte).
Garde-fou client en plus de la validation serveur : fermeture refusée si
antérieure à l'ouverture de la session.

## 2026-08-05 — Gestion de caisse (ouverture/fermeture + mouvements d'espèces)

Nouveaux modèles `CaisseSession` et `CaisseMovement` (migration
`0017_alter_notification_notif_type_caissesession_and_more`) et nouveaux
endpoints. Distinct de `Movement` (qui suit le stock produit) — ceci suit
l'argent en caisse : fond d'ouverture, apports/retraits pendant la session,
montant compté à la fermeture, écart calculé automatiquement.

Un magasin ne peut avoir qu'**une session ouverte à la fois** (contrainte
applicative, `400` sinon). Scoping identique aux autres ressources
(`Product`, `Sale`, `Movement`) : un admin voit toutes les sessions/mouvements
des magasins de sa société, un compte `magasin` ou `employer` uniquement
ceux de son propre magasin.

### `GET /api/users/caisse/sessions/`
Historique des sessions de caisse (plus récente en premier), avec
`movements` imbriqués. Filtres query : `magasin_id` (ou `store_id`),
`status` (`open`/`closed`).

### `GET /api/users/caisse/sessions/current/`
Session actuellement ouverte pour le magasin de l'utilisateur (`magasin_id`
en query pour un admin, obligatoire pour lui puisqu'il n'a pas de magasin
propre). **`204 No Content`** si aucune session ouverte — ne pas s'attendre
à un body `null` (DRF ne sérialise pas `Response(None)` en JSON `null`, le
body est vide dans ce cas).

### `POST /api/users/caisse/sessions/open/`
Ouvre une nouvelle session pour le magasin de l'utilisateur connecté
(`magasin`/`magasin_id` dans le body, obligatoire pour un admin, ignoré
pour `magasin`/`employer` qui ont un magasin implicite).
```json
{ "opening_balance": "10000", "opening_note": "Fond de caisse du matin" }
```
- `400 { "error": "Une session de caisse est déjà ouverte pour ce magasin." }`
- `400 { "error": "Magasin introuvable ou non spécifié." }`

### `POST /api/users/caisse/sessions/<id>/close/`
Ferme une session ouverte. Calcule `expected_balance` (fond d'ouverture +
Σ mouvements entrée − Σ mouvements sortie) et `difference` (`closing_balance
− expected_balance`, positif = excédent, négatif = manque).
```json
{ "closing_balance": "13500", "closing_note": "Compte OK" }
```
- `400 { "error": "Cette session est déjà fermée." }`
- `400 { "error": "Montant de fermeture requis." }`

### `GET /api/users/caisse/movements/`
Mouvements d'espèces (entrée/sortie) — hors ouverture/fermeture elles-mêmes.
Filtres query : `session_id`, `magasin_id`.

### `POST /api/users/caisse/movements/`
Ajoute un mouvement à la session ouverte du magasin de l'utilisateur
(ou à `session` si fourni explicitement — doit appartenir à un magasin
accessible à l'utilisateur, sinon rejeté).
```json
{ "movement_type": "in", "amount": "5000", "reason": "Apport" }
```
`movement_type` : `in` (entrée) ou `out` (sortie). `session` peut être omis
si l'utilisateur (`magasin`/`employer`) a une session ouverte — sinon requis.
- `400 { "session": ["Aucune session de caisse ouverte."] }` (ou message
  similaire porté par le champ non-field selon le point d'entrée)

### `POST /api/users/sales/` et `POST /api/users/sales/bulk/` (contrat étendu, cassant pour magasin/employer)
Refusent désormais la vente si la caisse du magasin du produit est fermée
(aucune `CaisseSession` `status="open"`) — **sauf pour un admin**, qui peut
toujours vendre. `400` :
```json
{ "caisse": "La caisse doit être ouverte pour enregistrer une vente." }
```
Impact direct sur le POS : avant d'encaisser, vérifier `GET
/caisse/sessions/current/` (ou l'état déjà chargé) pour un compte
magasin/employer, et inviter à ouvrir la caisse si fermée plutôt que de
laisser échouer l'encaissement.

### `Notification` (contrat étendu, pas cassant)
Nouveau `notif_type` : `"caisse"` (ouverture, fermeture, mouvement), et
nouveau champ `caisse_session` (id, nullable) sur `GET
/api/users/notifications/`.

### WebSocket `ws/data/` (contrat étendu)
Nouveaux `model` possibles dans le payload : `"caisse_session"` et
`"caisse_movement"` (mêmes `action` que les autres : `created`/`updated`/
`deleted`), groupes `data_admin_<id>`/`data_magasin_<id>` identiques aux
autres modèles.

### Côté Next.js à faire
- Nouvel écran "Caisse" (visible admin, et magasin/employer pour l'usage
  quotidien) : bouton ouverture (montant + note) si aucune session ouverte
  (`GET current` → `204`), sinon état "session ouverte" avec solde en cours,
  formulaire d'ajout de mouvement (entrée/sortie + motif), et bouton
  fermeture (montant compté + note) affichant l'écart calculé par l'API.
  Historique des sessions passées avec leur détail (mouvements, écart) sur
  `GET /caisse/sessions/`.
- Écouter `caisse_session`/`caisse_movement` sur `ws/data/` pour
  rafraîchir en temps réel si un autre poste ouvre/ferme/alimente la caisse.
- Écran de vente (POS) : pour un compte magasin/employer, désactiver le
  bouton d'encaissement (avec message explicite) quand aucune session de
  caisse n'est ouverte pour le magasin — l'API la refuse de toute façon
  désormais, mais mieux vaut l'empêcher côté UI que laisser échouer la
  requête. Un admin n'est jamais bloqué.
- Référence d'implémentation côté Flutter (une fois portée) :
  `lib/features/caisse/` dans `valhery_wear`.

## 2026-07-31 (suite) — Heures de connexion/déconnexion + statut "actif il y a ..."

Nouveau champ sur `LoginEvent` (`logged_out_at`, migration
`0015_loginevent_logged_out_at`) et nouvel endpoint pour l'enregistrer.

### `POST /api/users/logout-event/` (nouveau)
Authentifié. Marque `logged_out_at = now()` sur le `LoginEvent` le plus
récent de l'utilisateur connecté. **À appeler juste avant de supprimer les
tokens locaux**, sinon la requête part sans en-tête d'authentification et
échoue silencieusement (voir `django-client.ts` : appelé en tout premier
dans `auth.logout()`, avant `localStorage.clear()`).
- Best-effort uniquement : un JWT n'a pas d'invalidation serveur, donc ceci
  ne capture qu'un clic explicite sur "Déconnexion", pas l'expiration du
  token ni la fermeture de l'onglet/l'app.

### `GET /api/users/magasins/users/` (contrat étendu, pas cassant)
Chaque utilisateur retourné (`manager`, `employers[]`, `company_users[]`)
gagne deux champs :
```json
{
  "last_login_at": "2026-07-31T14:32:00Z",
  "last_logout_at": null
}
```
- `last_login_at` : date du dernier `LoginEvent` (`null` si jamais connecté).
- `last_logout_at` : date de la dernière déconnexion explicite enregistrée
  via `POST /logout-event/` (`null` si aucune, ou si l'utilisateur s'est
  reconnecté depuis sans se redéconnecter — comparer les deux dates pour
  savoir s'il est actuellement "en ligne" : en ligne si
  `last_logout_at` est `null` OU antérieur à `last_login_at`).

### À faire côté Flutter
- Appeler `POST /users/logout-event/` avant de vider le token stocké, au
  moment de la déconnexion (comme côté web).
- Sur l'écran équivalent à "Super Admin" / liste des utilisateurs, afficher
  `last_login_at`/`last_logout_at` formatés, et un statut "Actif il y a X
  minutes" (en ligne) ou "Hors ligne depuis X" calculé côté client à partir
  de ces deux dates — recalculé périodiquement (ex. toutes les 10 minutes)
  pour rester à jour sans recharger la page.
- Référence d'implémentation côté web : [`app/(app)/users/page.tsx`](frontend/app/(app)/users/page.tsx)
  (`formatRelativeTime`, `isCurrentlyOnline`, `setInterval` de 10 minutes).

## 2026-07-31 — Confirmation par mot de passe avant suppression (utilisateur, produit, magasin)

Les 3 endpoints de suppression suivants exigent désormais le mot de passe
de l'utilisateur connecté dans le corps de la requête `DELETE`, en plus des
permissions déjà en place. C'est une **re-authentification**, pas un
changement de qui a le droit de supprimer.

### `DELETE /api/users/delete/<user_id>/`
Suppression d'un utilisateur (gérant, employé, ou co-admin par le
fondateur).

### `DELETE /api/users/products/<product_id>/`
Suppression d'un produit.

### `DELETE /api/users/magasins/<magasin_id>/`
Suppression d'un magasin.
> Aucune UI de suppression de magasin n'existe dans le frontend web
> actuellement — si l'app Flutter a une telle fonctionnalité, c'est le seul
> endroit où ce changement s'applique concrètement pour l'instant.

### Contrat commun aux 3 endpoints

**Requête** — corps JSON obligatoire :
```json
{ "password": "le mot de passe de l'utilisateur connecté" }
```

**Réponses d'erreur** (nouvelles, à gérer côté Flutter) :
- `400 { "error": "Mot de passe requis pour confirmer la suppression." }` — champ absent/vide.
- `400 { "error": "Mot de passe incorrect." }` — mot de passe ne correspondant pas au compte connecté.

Les autres réponses (403 permission refusée, 404 introuvable, 200/204
succès) sont inchangées.

### À faire côté Flutter
- Avant chaque appel de suppression (utilisateur/produit/magasin), afficher
  un dialogue de confirmation avec un champ mot de passe (masqué), et
  l'envoyer dans le corps de la requête `DELETE`.
- Afficher l'erreur retournée (`error`) si le mot de passe est vide ou
  incorrect, sans fermer le dialogue, pour permettre une nouvelle tentative.
- Référence d'implémentation côté web :
  [`components/confirm-delete-dialog.tsx`](frontend/components/confirm-delete-dialog.tsx)
  (composant réutilisé sur les pages Super Admin, Produits) et
  [`lib/django-client.ts`](frontend/lib/django-client.ts) (méthodes
  `users.delete(id, password)`, `products.delete(id, password)`).

## 2026-07-30 — Co-admin : accès partagé aux données mais plus aux actions de fondateur

*(Rétroactif : fait avant la création de ce fichier, ajouté ici a posteriori
pour que rien ne manque. Déjà porté côté Flutter d'après `memory.md`.)*

Un admin ajouté par `POST /users/add-admin/` ("co-admin") garde l'accès à
tous les magasins/produits de la société, mais n'est plus l'égal du
fondateur sur les actions suivantes.

### `GET /api/users/me/` (contrat étendu)
Nouveau champ `is_company_owner` (bool) : `true` uniquement pour le
fondateur (celui qui a un `AdminProfile`). Un co-admin reçoit aussi
`company_name`/`logo` désormais (hérités du fondateur, avant : absents).

### `POST /api/users/add-admin/`
Réservé au fondateur désormais (`403` sinon : *"Seul le fondateur de la
société peut gérer les administrateurs."*). Avant : accessible à tout admin,
y compris un co-admin.

### `PUT /api/users/role/<user_id>/`
- Promouvoir quelqu'un au rôle `admin`, ou modifier/rétrograder un compte
  déjà `admin` : réservé au fondateur (`403` sinon), et jamais permis sur le
  fondateur lui-même (`403` : *"Action impossible sur le fondateur de la
  société."*).
- Inchangé pour les rôles `magasin`/`employer` : tout admin peut toujours.

### `DELETE /api/users/delete/<user_id>/`
Même règle que ci-dessus appliquée à la suppression : supprimer un compte
`admin` est réservé au fondateur, jamais possible sur le fondateur
lui-même. Avant : impossible pour quiconque de supprimer un compte admin
(bug — bouton visible mais toujours en échec).

### `GET/POST /api/users/my-company/{devices,subscription,requests}/`
Réservés au fondateur désormais (`403` pour un co-admin, avant : accessible
à tout admin).

### À faire côté Flutter
*(déjà fait d'après `memory.md` — section conservée pour référence si besoin
de revérifier)* : lire `is_company_owner` sur `/me/` ; masquer/désactiver
pour un non-fondateur les actions ci-dessus (ajouter/modifier/supprimer un
admin, onglets abonnement/appareils) ; afficher `company_name`/`logo` hérité
pour un co-admin.
