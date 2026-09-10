# FLUTTER_MIGRATION.md

Inventaire exhaustif du frontend Next.js (`frontend/`) et etat du projet Flutter (`smartcross/`),
etabli pour porter integralement l'application web vers Flutter.

**Source de verite fonctionnelle et UX : le projet Next.js.** Backend de reference : Django (`Stock/`, `users/`, `catalog/`, `orders/`, `suppliers/`).

## Methode

Audit automatise par 20 agents lisant integralement les fichiers (aucun resume a partir de `grep`) :
15 agents sur le frontend Next.js, 5 sur le projet Flutter.

| Indicateur | Valeur |
| --- | --- |
| Blocs Next.js audites (pages, composants, couches) | 75 |
| Fonctionnalites recensees | 1030 |
| Formulaires recenses | 149 |
| Modales / dialogs / drawers recenses | 127 |
| Recherches, filtres, tris, paginations | 121 |
| Appels API recenses | 328 |
| Etats UI recenses | 314 |
| Details UX recenses | 409 |
| **Total elements inventories** | **2478** |

## 1. Routes

| Route Next.js | Role autorise | Ecran Flutter | Etat |
| --- | --- | --- | --- |
| `/orders` | Page unique servie a TOUS les roles authentifies (aucun guard de route : /orders est dans navigationItems du s… | lib/features/orders/orders_list_screen.dart + order_create_screen.dart + order_detail_screen.dart, lib/features/depot/depot_screen.dart, lib/features/tournee/tournee_screen.dart | PARTIAL |
| `/products` | Gating 100% côté client via `useCurrentUser()` (GET /users/me/). Seul `isGerant` est utilisé dans la page prin… | lib/features/catalog/catalog_screen.dart | PARTIAL |
| `/movements` | AUCUN guard dans la page elle-meme. (1) Guard global: /home/garrix/Dev/Smartphone/frontend/app/(app)/layout.ts… | AUCUN | MISSING |
| `/chats` | AUCUN gating par role dans la page — accessible a TOUS les roles connectes (admin / magasin(GERANT) / employer… | lib/features/chats/chat_list_screen.dart + chat_conversation_screen.dart | PARTIAL |
| `/users (libellé sidebar : "Super Admin", titre page : "Super Administr` | GATING EN 3 COUCHES. (1) Layout /home/garrix/Dev/Smartphone/frontend/app/(app)/layout.tsx : useEffect -> si !d… | lib/features/users/users_screen.dart | PARTIAL |
| `/caisse` | GERANT uniquement en pratique (admin = role 'admin', gerant magasin = role 'magasin'). AUCUN guard explicite d… | lib/features/caisse/caisse_screen.dart | PARTIAL |
| `/bilan` | LIVREUR EXCLUSIVEMENT. useCurrentUser() fournit { isLivreur, loading: userLoading } avec isLivreur = (role ===… | lib/features/tournee/bilan_screen.dart | DONE |
| `/dashboard` | GERANT UNIQUEMENT (admin + magasin). Gating en 2 couches: (1) Sidebar (/home/garrix/Dev/Smartphone/frontend/co… | lib/features/dashboard/dashboard_screen.dart | PARTIAL |
| `/reports` | Réservé au GERANT dans la navigation (sidebar item `Rapports` avec adminOnly:true -> visible seulement si isAd… | AUCUN | MISSING |
| `/settings` | GATING = `const { user, isGerant, loading: userLoading } = useCurrentUser()` (/home/garrix/Dev/Smartphone/fron… | lib/features/settings/settings_screen.dart | PARTIAL |
| `/stores` | GATING = `const { user, isAdmin } = useCurrentUser()` ; `isAdmin === (role === 'admin')`. AUCUN guard/redirect… | lib/features/stores/stores_screen.dart | PARTIAL |
| `/suppliers` | GERANT (= admin OU magasin). ATTENTION: AUCUN gating dans la page elle-meme — pas de useCurrentUser, pas de gu… | lib/features/suppliers/suppliers_screen.dart + supplier_order_*.dart | PARTIAL |
| `/transfers` | ADMIN UNIQUEMENT (superadmin/proprietaire de societe). Gating explicite dans la page: `const { isAdmin, loadin… | lib/features/transfers/transfers_screen.dart | PARTIAL |
| `/transfers (composant partage TransferProductsPanel — coeur fonctionne` | Pas de gating interne au composant: il herite du gating de son hote (page /transfers = isAdmin uniquement; dia… | lib/features/transfers/transfers_screen.dart | PARTIAL |
| `/stores (modal TransferProductsDialog — variante modale du meme flux)` | Aucun gating propre. Utilise par app/(app)/stores/page.tsx (entree sidebar superAdminOnly => role 'admin'). Le… | lib/features/stores/stores_screen.dart | PARTIAL |
| `/alerts` | AUCUN gating dans la page elle-meme : le composant n'importe PAS useCurrentUser, aucun guard, aucun redirect. … | AUCUN | MISSING |
| `/pickup` | GERANT uniquement. Gating explicite : const { isGerant, loading: userLoading } = useCurrentUser(); isGerant ==… | AUCUN | MISSING |
| `/scanner` | AUCUN gating : pas de useCurrentUser, pas de guard, pas de redirect. Accessible a tout utilisateur authentifie… | AUCUN | MISSING |
| `/sales` | Aucun role, aucun gating : la page ne fait que rediriger. Elle n'apparait dans aucun menu de la Sidebar. | AUCUN | MISSING |
| `/superadmin` | SUPERADMIN uniquement, c'est-a-dire isSuperAdmin === (role === 'admin') dans useCurrentUser (attention : dans … | AUCUN | MISSING |
| `/notifications` | AUCUN guard dans la page elle-meme. Le composant est un 'use client' sans useCurrentUser, sans verification de… | lib/features/notifications/notifications_screen.dart | PARTIAL |
| `(global) TopBar — cloche de notifications (dropdown)` | AUCUN gating de role. Le composant <Notifications /> est monte inconditionnellement dans /home/garrix/Dev/Smar… | composant / couche partagee — a porter | PARTIAL |
| `/` | PUBLIC — aucun gating. Server Component pur, aucun appel a useCurrentUser ni a djangoClient. Ne verifie PAS si… | lib/features/auth/splash_screen.dart | DONE |
| `/login` | PUBLIC — aucun guard, aucun useCurrentUser. Le role n'intervient qu'APRES login reussi pour choisir la destina… | lib/features/auth/login_screen.dart | PARTIAL |
| `/register` | PUBLIC — aucun guard. C'est l'utilisateur qui CHOISIT son type de compte via un RadioGroup 3 options : 'admin'… | AUCUN | MISSING |
| `/forgot-password` | PUBLIC (endpoints AllowAny). Gating METIER cote backend : le flux n'est disponible QUE pour les comptes role='… | AUCUN | MISSING |
| `/reset-password` | AUTHENTIFIE REQUIS et, cote backend, RESERVE AU GERANT : ChangePasswordView refuse role not in ['admin','magas… | AUCUN | MISSING |
| `/verify-email` | PUBLIC — Server Component 100% statique, aucun guard, aucun hook, aucun state, aucun appel API. | AUCUN | MISSING |
| `/pending-approval` | PUBLIC — Server Component statique, aucun guard, aucun hook, aucun appel API. N'affiche AUCUNE donnee du compt… | AUCUN | MISSING |
| `/auth/pending-approval` | PUBLIC — Server Component statique, aucun guard, aucun hook, aucun appel API. C'est la page d'arrivee REELLE a… | composant / couche partagee — a porter | PARTIAL |
| `/logout` | Aucun gating. Client Component ('use client'). Accessible meme sans session (l'appel logout est tolerant aux e… | lib/widgets/topbar.dart (action de deconnexion) | PARTIAL |
| `/* (RootLayout — enveloppe TOUTES les pages, y compris /login, /regist` | AUCUN gating. Layout racine serveur (pas de 'use client'), aucun appel a useCurrentUser, aucun guard. Il s'app… | lib/main.dart + lib/core/router.dart (redirect global) | PARTIAL |
| `/(app)/* — shell applicatif protege (couvre /dashboard, /orders, /pick` | Gating d'AUTHENTIFICATION seulement, aucun gating de role a ce niveau. useEffect(() => { if (!djangoClient.isA… | lib/widgets/navigation_shell.dart | PARTIAL |
| `/(app)/* — Sidebar de navigation (rendue sur toutes les routes du grou` | Gating par role via useCurrentUser() qui expose { user, isAdmin, isSuperAdmin, isAdminOrSuperAdmin, isPreparat… | lib/core/nav_items.dart + lib/widgets/navigation_shell.dart | PARTIAL |
| `/(app)/* — TopBar (barre superieure, rendue sur toutes les routes du g` | Aucun gating d'affichage : la TopBar est identique pour tous les roles. useCurrentUser() est utilise uniquemen… | lib/widgets/topbar.dart | PARTIAL |
| `* — GlobalErrorBoundary (composant transverse, actuellement NON monte)` | Aucun role, aucun gating. | composant / couche partagee — a porter | PARTIAL |
| `* — ThemeProvider (wrapper de theme, monte dans app/layout.tsx)` | Aucun role, aucun gating. | composant / couche partagee — a porter | PARTIAL |
| `(aucune route) — components/ui/sidebar.tsx : kit de primitives shadcn/` | Aucun gating de role. Aucun import ailleurs dans le repo (verifie : seul le fichier lui-meme reference Sidebar… | composant / couche partagee — a porter | PARTIAL |
| `(composant partagé) <ImageUpload /> — zone de dépôt + prévisualisation` | AUCUN gating de rôle dans le fichier. Le composant est 100% agnostique : pas de useCurrentUser, pas de guard, … | composant / couche partagee — a porter | PARTIAL |
| `(composant partagé) <ProductImageGallery /> — galerie photos produit +` | AUCUN gating de rôle dans le fichier : pas de useCurrentUser, pas de guard. Les droits d'écriture sont délégué… | composant / couche partagee — a porter | PARTIAL |
| `(composant partagé) <ConfirmDeleteDialog /> — modal de suppression ave` | Le composant lui-même n'a AUCUN gating (pas de useCurrentUser). Le gating est fait par les deux pages appelant… | composant / couche partagee — a porter | PARTIAL |
| `(composant partagé) <AIAnalysis /> — carte « Analyse IA Stratégique ».` | Aucun gating dans le composant. Gating par la page /reports : `const { isAdmin } = useCurrentUser()` — la donn… | composant / couche partagee — a porter | PARTIAL |
| `POST /api/ai/analyze — route API Next.js (Route Handler)` | AUCUNE vérification d'authentification ni de rôle. La route n'inspecte ni cookie, ni header Authorization, ni … | composant / couche partagee — a porter | PARTIAL |
| `POST /api/ai/check-duplicates — route API Next.js (Route Handler)` | AUCUNE vérification d'authentification ni de rôle (ni cookie, ni JWT, ni rate-limit). En pratique elle n'est a… | composant / couche partagee — a porter | PARTIAL |
| `(module partagé) lib/image-service.ts — service de gestion des images` | Aucun rôle, aucun gating : module de fonctions utilitaires pures/réseau, sans notion d'utilisateur. AUCUNE de … | composant / couche partagee — a porter | PARTIAL |
| `(module partagé) lib/qrcode-generator.ts — génération et lecture de QR` | Aucun rôle, aucun gating. Module utilitaire pur. Aucune de ses fonctions n'est importée ailleurs dans le front… | composant / couche partagee — a porter | PARTIAL |
| `(hook partagé) lib/hooks/useDeliveryZones.ts — zones de livraison conf` | Le hook ne fait aucun gating. Règle serveur documentée dans lib/django-client.ts : « Lecture ouverte à tous, é… | composant / couche partagee — a porter | PARTIAL |
| `(hook partagé) lib/hooks/useDebouncedValue.ts — valeur temporisée pour` | Aucun rôle, aucun gating : hook générique sans notion d'utilisateur. | composant / couche partagee — a porter | PARTIAL |
| `(couche transport) DjangoAPIClient — coeur HTTP/JWT` | Aucun gating de role a ce niveau : la classe est agnostique. Le seul gating client est fait ailleurs via useCu… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.auth — authentification, inscription, mot de passe oublie` | register() accepte n'importe quel role et le traduit ; approveUser/rejectUser/getPendingUsers sont des actions… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.passwordResetRequests — moderation des demandes de reinit` | Cote admin/gerant : c'est l'approbateur des demandes emises par les comptes magasin/employer. Aucun garde clie… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.catalog.categories — Categories du catalogue (§8)` | Ecriture reservee au gerant (admin/magasin) cote backend ; lecture pour tous les roles connectes. Le parametre… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.catalog.types — Sous-types rattaches a une categorie` | Ecriture gerant, lecture tous (controle backend). | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.catalog.brands — Marques` | Ecriture gerant, lecture tous. Scope par magasin via magasin_id. | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.catalog.colors — Couleurs (referentiel des variantes)` | Ecriture gerant, lecture tous. Scope magasin. | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.catalog.references — References produit (fiche article) +` | Ecriture gerant. Le commentaire du fichier precise que le formulaire produit utilise directement `catalog.*` (… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.catalog.importBatches — Annulation d'un import Excel` | Gerant (celui qui a lance l'import). | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.catalog.variants — Variantes (couleur) et ajustement de s` | Ecriture gerant (ajustement manuel de stock trace au nom de l'utilisateur : le mouvement genere porte l'origin… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.orders — Module Commandes (coeur metier, §5-§7)` | 3 roles metier : GERANT (admin ou magasin — cree/modifie/supprime/annule, assigne preparateur et livreur, voit… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.zones — Zones de livraison configurables (Parametres)` | Lecture ouverte a TOUS les roles connectes (les formulaires de commande en ont besoin) ; ECRITURE reservee au … | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.movements — Historique des mouvements de stock (§7.4/§10)` | Lecture ; en pratique consultee par le gerant (page Historique/Stock). Chaque ligne porte user_name (auteur du… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.products — Service de compatibilite (lecture seule)` | Lecture, tous roles connectes. Utilise par les pages non prioritaires : alertes, rapports, dashboard, chat, sc… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.sales — Ventes derivees des commandes livrees (compatibil` | Lecture, pages analytics (rapports, dashboard). | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.notifications — Notifications in-app` | Tous les roles connectes ; le contenu est filtre par le backend selon le destinataire. | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.users — Utilisateurs, employes, profil` | Administration des comptes : reserve gerant/admin cote backend. updateProfile concerne l'utilisateur connecte … | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.dashboard — Indicateurs generaux` | Gerant/admin principalement (le backend adapte le perimetre au role et au magasin). | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.transfers — Transfert de stock entre magasins + vue benef` | transfer : gerant multi-magasins. getProfitByMagasins : ADMIN UNIQUEMENT (commentaire explicite 'admin uniquem… | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.caisse — Sessions de caisse, mouvements, categories, synt` | Gerant/magasin (tenue de caisse par magasin). Le parametre magasin_id permet a un admin de cibler un magasin. | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.suppliers — Commandes fournisseur (§7.6)` | Gerant/admin (approvisionnement). Le magasin_id cible le magasin destinataire. | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.backup — Sauvegarde / restauration (admin uniquement)` | ADMIN UNIQUEMENT (commentaire explicite 'admin only'). A gater cote UI avec isAdmin / isSuperAdmin. | composant / couche partagee — a porter | PARTIAL |
| `djangoClient.chat — Messagerie interne` | Tous les roles connectes ; la liste des interlocuteurs est filtree par le backend. | composant / couche partagee — a porter | PARTIAL |
| `lib/types.ts — Modeles TypeScript partages` | UserRole = 'admin' | 'store_manager' | 'employee' — c'est la nomenclature FRONT (traduite depuis admin/magasin… | composant / couche partagee — a porter | PARTIAL |
| `lib/validation.ts — Schemas Zod (heritage, non branches sur l'API actu` | Aucun gating. | composant / couche partagee — a porter | PARTIAL |
| `lib/timezone.ts — Fuseau metier Indian/Antananarivo (regle du 'jour J'` | Impacte directement le gating METIER du PREPARATEUR et du LIVREUR : la date a partir de laquelle ils peuvent a… | composant / couche partagee — a porter | PARTIAL |
| `lib/utils.ts — Helper de classes CSS` | Aucun. | composant / couche partagee — a porter | PARTIAL |

## 2. Detail par page / bloc

### `/orders`

- **Fichier Next.js** : `frontend/app/(app)/orders/page.tsx`
- **Groupe d'audit** : `orders`
- **Cible Flutter** : lib/features/orders/orders_list_screen.dart + order_create_screen.dart + order_detail_screen.dart, lib/features/depot/depot_screen.dart, lib/features/tournee/tournee_screen.dart
- **Etat** : PARTIAL

**Role et gating.** Page unique servie a TOUS les roles authentifies (aucun guard de route : /orders est dans navigationItems du sidebar SANS flag adminOnly/livreurOnly/hidePreparateur, donc visible par tout le monde ; le seul garde est app/(app)/layout.tsx qui redirige vers /login si !djangoClient.isAuthenticated()). Le gating est 100% conditionnel dans le composant via `const { user, isGerant, isPreparateur, isLivreur, loading: userLoading } = useCurrentUser()`. Definitions (lib/auth/useCurrentUser.ts) : isGerant = role==='admin' || role==='magasin' (donc admin/superadmin ET magasin sont tous 'GERANT' cote UI) ; isPreparateur = role==='employer' && commande_role==='PREPARATEUR' ; isLivreur = role==='employer' && commande_role==='LIVREUR'. Un employer sans commande_role n'est ni l'un ni l'autre : il tombe dans la branche 'par defaut' (titre 'Commandes', aucun filtre, aucun bouton de creation, aucune action de ligne, colonne Total visible car !isPreparateur, pas de colonne Assigne a car !isGerant). Le backend re-filtre de toute facon le queryset par role (orders/views.py::OrderViewSet.get_queryset) et choisit un serializer different par role (OrderGerantSerializer / OrderPreparateurSerializer / OrderLivreurSerializer), donc le preparateur ne recoit meme pas les champs financiers.

**Objectif.** Ecran unique de suivi/gestion des commandes clients, decline en 3 experiences par role : (1) GERANT = suivi complet + creation + modification + annulation + suppression + assignation preparateur/livreur + pilotage des transitions de statut ; (2) PREPARATEUR = file 'Depot - Commandes a preparer' avec 3 onglets (A preparer / Recuperations / Historique), creation de retraits sur place uniquement, actions Commencer la preparation -> Commande prete ; (3) LIVREUR = 'Ma tournee' avec 2 onglets (Ma tournee / Historique), actions Recuperer (en livraison) -> Livre, plus Retour. Workflow a 7 statuts NOUVELLE -> EN_PREPARATION -> PRETE -> EN_LIVRAISON -> LIVRE, plus RETOUR et ANNULEE.

**Fonctionnalites** (37)

- En-tete : titre dynamique — 'Historique' si viewMode==='HISTORIQUE', sinon 'Depot — Commandes a preparer' (preparateur), 'Ma tournee' (livreur), 'Commandes' (gerant/defaut)
- En-tete : sous-titre dynamique — HISTORIQUE: 'Vos commandes deja traitees, tous statuts — filtrables par date et heure.' ; preparateur: 'Commandes recues a preparer, puis a marquer "Prete" pour le livreur.' ; livreur: 'Commandes pretes a recuperer, puis "Livre" ou "Retour" une fois la tournee faite.' ; gerant/defaut: 'Suivi complet des commandes clients.'
- Bouton icone Rafraichir (RefreshCw, variant outline, size icon) — appelle fetchOrders() NON silencieux (affiche le skeleton). Visible pour tous les roles
- Bouton principal 'Nouvelle commande' (gerant) / 'Nouvelle recuperation' (preparateur), icone Plus — ouvre CreateOrderDialog. Condition: (isGerant || isPreparateur). INVISIBLE pour le livreur
- Barre d'onglets PREPARATEUR (3 boutons size sm, variant default si actif sinon outline) : 'A preparer' (icone Truck, set viewMode=ACTIF + preparateurTab=A_PREPARER), 'Recuperations' (icone Package, viewMode=ACTIF + preparateurTab=RECUPERATIONS), 'Historique' (icone History, viewMode=HISTORIQUE)
- Barre d'onglets LIVREUR (2 boutons) : 'Ma tournee' (icone Truck, viewMode=ACTIF), 'Historique' (icone History, viewMode=HISTORIQUE)
- Le GERANT n'a AUCUN onglet Historique/vue alternative : viewMode reste toujours 'ACTIF' pour lui
- Barre de filtres rapides GERANT : rangee de boutons toggle 'Toutes' (statutFilter='ALL'), 'Pas encore livree' (statutFilter='NON_LIVREE'), puis un bouton par statut de STATUTS (Nouvelle, En preparation, Prete, En livraison, Livre, Retour, Annulee). Le bouton actif est variant=default, les autres outline
- Le meme statutFilter est aussi expose en Select dans la rangee de filtres gerant (double UI redondante liee au meme state)
- Tableau des commandes (composant Table shadcn) dans une Card, wrapper overflow-x-auto. Aucune pagination, aucun tri cliquable sur les entetes, aucun export
- Colonne 'N° commande' : order.numero, font-medium
- Colonne 'Type' : firstItem?.category_name || '-' (categorie du PREMIER article seulement)
- Colonne 'Sous-type' : firstItem?.type_name || '-' (type du PREMIER article seulement)
- Colonne 'Produit' (max-w 280px) : boucle sur TOUS les order.items — ligne 1 = it.reference_name (fallback 'Article') a gauche + 'x{quantite}' a droite (affiche seulement si it.quantite truthy) ; ligne 2 = 'Marque: {it.brand_name}' si present + pastille arrondie avec it.couleur si presente
- Colonne 'Date' : order.date_commande formate fr-FR en fuseau Indian/Antananarivo au format JJ/MM HH:mm (sans annee), sinon '-'
- Colonne 'Client' : order.client_nom
- Colonne 'Adresse' — UNIQUEMENT si isLivreur : order.adresse_livraison || '-', tronquee (max-w 180px truncate)
- Colonne 'Telephone' — UNIQUEMENT si isLivreur : lien <a href="tel:{telephone}"> bleu souligne au survol avec icone Phone ; onClick stopPropagation pour ne pas ouvrir le detail
- Colonne 'Zone' (si isLivreur) / 'Adresse' (sinon) : pour le livreur = libelle de zone sans le prix (label.split(' (')[0]) ; pour les autres = adresse_livraison sinon libelle de zone sinon le code brut livraison_zone
- Colonne 'Statut' : Badge colore via statutInfo(order.statut_courant)
- Colonne 'Total' — masquee si isPreparateur : si isLivreur && mode_paiement==='AVANT' affiche le texte vert 'Deja paye', sinon fmt(order.total_a_payer) formate 'x xxx Ar'
- Colonne 'Assigne a' — UNIQUEMENT si isGerant : '-' si ni preparateur_name ni livreur_name ; sinon bloc preparateur (icone UserRound + nom + horodatage du passage EN_PREPARATION issu de status_history) et/ou bloc livreur (icone Truck + nom + 'Livre le {date}' si statut LIVRE sinon 'Prevu le {date_commande}')
- Colonne 'Action' (alignee a droite) : contenu conditionnel par role, voir lignes suivantes
- Action GERANT = un Select 'Action' (h-8, w-170px) rendu seulement si gerantActionOptions(order).length>0 ; sur choix, ouvre soit AssignStaffDialog (kind='assign') soit le dialogue de confirmation ActionNote (kind='status')
- Options gerant selon statut : NOUVELLE -> ['Assigner un preparateur' (assign PREPARATEUR, cible EN_PREPARATION), 'Commencer la preparation' (status EN_PREPARATION)] ; EN_PREPARATION -> ['Commande prete' (PRETE)] ; PRETE non-recuperation -> ['Assigner un livreur' (assign LIVREUR, cible EN_LIVRAISON), 'Recuperer / En livraison' (status EN_LIVRAISON)] ; PRETE + zone RECUPERATION -> ['Recuperee par le client' (status LIVRE)] ; EN_LIVRAISON -> ['Livree' (LIVRE), 'Retour' (RETOUR)] ; LIVRE/RETOUR/ANNULEE -> aucune option (le Select disparait)
- Action PREPARATEUR/LIVREUR = un IconAction avec libelle (showLabel) issu de nextAction(order) : preparateur NOUVELLE -> 'Commencer la preparation' (Package), EN_PREPARATION -> 'Commande prete' (Package), sinon rien ; livreur PRETE -> 'Recuperer (en livraison)' (Truck), EN_LIVRAISON -> 'Livre' (Truck), sinon rien
- Bouton secondaire 'Retour' (icone Undo2, outline, texte rouge) sur la ligne : condition ecrite `(isLivreur || isGerant) && statut==='EN_LIVRAISON' && !isGerant` — en pratique LIVREUR SEUL (le `&& !isGerant` neutralise la branche gerant, qui passe par son Select)
- Bouton 'Modifier' (Pencil, outline, showLabel) : canEdit = isGerant && statut ∈ {NOUVELLE, EN_PREPARATION}
- Bouton 'Annuler la commande' (Ban, outline, rouge) : canCancel = isGerant && statut ∉ {LIVRE, RETOUR, ANNULEE}
- Bouton 'Supprimer' (Trash2, outline, rouge) : canDelete = isGerant && statut === 'NOUVELLE' uniquement
- Tout clic sur une ligne (className cursor-pointer) ouvre le dialogue Detail ; chaque bouton d'action fait e.stopPropagation()
- Blocage 'jour J' : notYetDue = (isPreparateur||isLivreur) && !isJourJ(order.date_commande). Quand true, les IconAction sont disabled et leur libelle+tooltip deviennent 'Disponible le {JJ/MM/AAAA}'
- IconAction : composant local = Button (size icon ou sm si showLabel) enveloppe dans un Tooltip shadcn dont le contenu est le label
- Chronologie/timeline dans le detail (OrderTimeline) : lignes 'Commande cree le' (created_at), 'Livraison prevue le' (date_commande), puis jalons atteints uniquement — 'Preparation commencee le' (Wrench), 'Prete le' (Boxes), 'En livraison depuis le' (Truck), 'Livree le' (CheckCircle2), 'Retour le' (Undo2). Chaque jalon prend le PREMIER timestamp du status_history pour ce statut
- Historique detaille dans le detail : liste ul de tous les status_history — '{label statut} — {changed_by_name || "Systeme"} — {date+heure}' + ' (note)' si note + vignette photo 64x64 cliquable + lien 'Voir / telecharger la photo' (target=_blank) si h.photo
- Rafraichissement temps reel : useRealtimeRefresh(['order','order_status_history'], () => fetchOrders(true)) — WebSocket /ws/data/, debounce 400 ms, refetch SILENCIEUX (pas de skeleton)
- Refetch automatique a chaque changement d'un filtre (fetchOrders est un useCallback dont les deps sont tous les filtres, et un useEffect le rappelle quand il change, une fois userLoading=false)

**Formulaires** (13)

- CreateOrderDialog ('Nouvelle commande', description 'Vente Facebook ou sur place — §6 du cahier des charges.') — CHAMPS : (1) bloc OrderItemsEditor (Categorie, Sous-type, Marque, recherche reference, Couleur, Quantite, Prix lecture seule si showPrices, bouton 'Ajouter a la commande') ; (2) 'Type de commande' = 2 boutons toggle 'A livrer' (prend la 1re zone non-RECUPERATION) / 'Recuperation sur place' — MASQUE pour le preparateur qui voit a la place le texte 'Retrait sur place uniquement — la commande apparaitra dans "Recuperations" une fois prete, a valider comme livree au comptoir par le gerant.' ; (3) 'Date et heure de livraison' = DateTimeInput (2 champs date + time), defaut = maintenant a l'heure d'Antananarivo, aide 'Vide = maintenant.' ; (4) Select 'Preparateur' (placeholder 'Assigner plus tard') et Select 'Livreur' (placeholder 'Assigner plus tard') — masques pour le preparateur ; (5) si zone != RECUPERATION : Select 'Zone de livraison' (options = zones actives avec leur prix) + Input 'Adresse de livraison' (placeholder 'Ex: Lot II M 45 Antanimena, Antananarivo') ; (6) si zone != RECUPERATION : Select 'Paiement' (Paye / Paiement a la livraison, defaut LIVRAISON) ; (7) Input 'Nom client' (placeholder 'Rakoto Jean') ; (8) Input 'Telephone' (valeur initiale '+261', placeholder '+261340000000') ; (9) Textarea 'Note pour le preparateur (optionnel)' — libelle 'Note (optionnel)' pour le preparateur ; (10) Textarea 'Note pour le livreur (optionnel)' si !isPreparateur && zone != RECUPERATION ; (11) recap 'Frais de livraison' + 'Total a payer' si showPrices
- CreateOrderDialog — VALIDATIONS cote client, toasts d'erreur bloquants : nom vide -> toast.error 'Nom du client requis' ; telephone ne matchant pas /^\+261\d{9}$/ -> 'Telephone au format +261XXXXXXXXX' ; items vide -> 'Ajoutez au moins un article'. Aucune validation sur adresse/zone/date
- CreateOrderDialog — SOUMISSION : POST /orders/ (date_commande envoyee seulement si renseignee, convertie via appDatetimeLocalToIso ; note_livreur forcee a '' si zone RECUPERATION), puis si preparateurId POST assign-preparateur, puis si livreurId POST assign-livreur. Chaque assignation ratee -> toast.error 'Commande creee, mais l'assignation du preparateur/livreur a echoue : {msg} (a assigner depuis le tableau).' et assignmentFailed=true. Si aucune erreur -> toast.success 'Commande creee et assignee' (si au moins une assignation) sinon 'Commande creee'. Ensuite onCreated() : ferme le dialogue et fetchOrders() NON silencieux. Erreur globale -> toast.error(err.message || 'Erreur lors de la creation'). Bouton 'Creer la commande' devient 'Creation…' et disabled pendant submitting
- CreateOrderDialog — REINITIALISATION a chaque ouverture (useEffect sur `open`) : clientNom='', telephone='+261', zone = 'RECUPERATION' si preparateur sinon '' (puis auto-selection de la 1re zone payante des que zoneOptions arrive), adresse='', modePaiement='LIVRAISON', dateCommande=maintenant, notes='', items=[], preparateurId='', livreurId=''
- EditOrderDialog ('Modifier la commande {numero}', description 'Possible tant que la commande n'est pas encore "Prete".') — CHAMPS : OrderItemsEditor avec showPrices=true (articles existants pre-charges et supprimables, nouveaux ajoutables), 'Type de commande' (2 boutons toggle A livrer / Recuperation sur place), 'Date et heure de livraison' (DateTimeInput, sans texte d'aide), 'Nom client', 'Telephone', si zone != RECUPERATION : 'Zone de livraison' + 'Adresse de livraison' + 'Paiement', Select 'Preparateur', Select 'Livreur' (uniquement si zone != RECUPERATION), Textarea 'Note pour le preparateur (optionnel)', Textarea 'Note pour le livreur (optionnel)' si zone != RECUPERATION
- EditOrderDialog — PRE-REMPLISSAGE (useEffect sur `order`) : tous les champs depuis l'objet commande ; date convertie en datetime-local heure Antananarivo ; items mappes depuis order.items avec key 'existing-{id}', prix_vente=prix_unitaire, variant_id=product_variant, stock_actuel=Infinity (donc plus de controle de stock sur les lignes deja presentes) ; chargement en parallele de availableStaff('PREPARATEUR', order.magasin) et availableStaff('LIVREUR', order.magasin, order.date_commande)
- EditOrderDialog — VALIDATIONS identiques a la creation : 'Nom du client requis', 'Telephone au format +261XXXXXXXXX', 'Ajoutez au moins un article'
- EditOrderDialog — SOUMISSION : PATCH /orders/{id}/ (adresse forcee a '' si zone RECUPERATION, note_livreur forcee a '' si RECUPERATION, date_commande envoyee seulement si renseignee), puis assign-preparateur si preparateurId a change, puis assign-livreur si zone != RECUPERATION et livreurId a change. Echec d'assignation -> toast.error 'Commande mise a jour, mais l'assignation du preparateur/livreur a echoue : {msg}'. Succes -> toast.success 'Commande mise a jour' puis onSaved() = ferme + fetchOrders(true) SILENCIEUX. Erreur -> toast.error(err.message || 'Erreur lors de la modification'). Bouton 'Enregistrer' -> 'Enregistrement...' + disabled pendant submitting
- NoteForm (formulaire de confirmation d'action, integre au dialogue ActionNote) — CHAMPS : Textarea 'Note (optionnel)' ; si showPhoto (uniquement quand la cible est PRETE) : Label avec icone Camera 'Photo de la preparation (optionnel)' + Input type=file accept=image/* + apercu 80x80 (URL.createObjectURL). Boutons 'Annuler' (outline) et 'Confirmer'. Aucune validation : la note peut etre vide
- AssignStaffDialog — CHAMPS : Select 'Choisir un preparateur'/'Choisir un livreur' (liste availableStaff, valeur = id) + 'Date et heure' (DateTimeInput, pre-rempli a maintenant heure Antananarivo) avec aide 'Vide = maintenant.'. Bouton 'Assigner' disabled tant qu'aucune personne selectionnee ; bouton 'Annuler' ferme. Soumission = doChangeStatus(order, EN_PREPARATION|EN_LIVRAISON, note=undefined, {preparateur_id|livreur_id, assigned_at: ISO})
- OrderItemsEditor (sous-formulaire partage Create/Edit) — CHAMPS : Select 'Categorie', Select 'Sous-type' (filtre par categorie choisie), Select 'Marque', Input de recherche 'Rechercher une reference (ex: A15)' avec liste de suggestions en popover absolu, puis quand une reference est selectionnee : Select 'Couleur' (option '{couleur} (stock: {n})', DESACTIVEE si stock_actuel<=0), Input number 'Quantite' (min=1, placeholder 'Ex: 1'), Input 'Prix (Ar)' readOnly+disabled si showPrices, bouton 'Ajouter a la commande'
- OrderItemsEditor — VALIDATIONS a l'ajout : pas de reference ou pas de couleur -> toast.error 'Selectionnez une reference et une couleur' ; quantite vide/0/negative -> 'Quantite invalide' ; quantite > variant.stock_actuel -> 'Stock insuffisant (disponible: {n})'. Apres ajout : reset de query, suggestions, selectedRef, variantId, quantite
- OrderItemsEditor — panier : liste des lignes '{reference_label} ({couleur}) x{quantite}' + montant ligne (prix_vente*quantite) si showPrices + bouton icone poubelle rouge pour retirer la ligne (suppression par index)

**Modales / dialogs / drawers** (11)

- Dialog 'Detail commande' (max-w-lg) — ouvert par clic sur une ligne. Contient : titre 'Commande {numero}' ; bouton 'Modifier' en en-tete si isGerant && statut ∈ {NOUVELLE, EN_PREPARATION} (ferme le detail et ouvre EditOrderDialog) ; section 'Articles' (encadre gris) listant reference_name (+ couleur entre parentheses) et la ligne meta 'type • categorie • marque' ou 'Sans metadonnees' ; grille d'infos Nom client / Numero client / Adresse client / Mode de payment ; 'Total a payer' AFFICHE UNIQUEMENT si mode_paiement !== 'AVANT' ; Preparateur et Livreur si renseignes ; bouton d'action pleine largeur (uniquement si !isGerant et si nextAction existe) desactive et libelle 'Disponible le {date}' si pas jour J ; 'Note pour le preparateur' et 'Note pour le livreur' si presentes ; section 'Chronologie' (OrderTimeline) ; section 'Historique detaille' (liste des status_history avec auteur, date, note et photo)
- Dialog 'Confirmer : {label de l'action}' (actionNote) — description 'Commande {numero} — verifiez le resume avant de confirmer.'. Encadre recapitulatif : Client, Telephone (si present), Zone (libelle sans prix), Adresse (si presente), Paiement (masque si zone RECUPERATION), liste des Articles '{reference_name} ({couleur}) x{quantite}'. Bloc montants : si isLivreur && mode_paiement==='AVANT' -> ligne verte 'A encaisser : Rien — deja paye' ; sinon, si total_a_payer != null : 'Prix de vente' (= total - frais) et 'Frais de livraison' affiches seulement si zone != RECUPERATION et frais_livraison != null, puis 'Total'. Puis NoteForm (note + photo si cible PRETE) avec boutons Annuler / Confirmer
- Dialog 'Assigner un preparateur/livreur' (AssignStaffDialog) — description 'Commande {numero} — choisissez manuellement qui prend cette commande en charge.'. Etat chargement = Skeleton h-10 ; etat vide = 'Aucun {preparateur|livreur} enregistre pour ce magasin.' ; sinon Select du staff + DateTimeInput 'Date et heure' + aide 'Vide = maintenant.'. Footer Annuler / Assigner (disabled si rien de selectionne). Rendu seulement si isGerant
- Dialog 'Annuler la commande {numero} ?' (cancelTarget) — description 'La commande de {client_nom} sera annulee.' + phrase conditionnelle ' Le stock deja deduit pour cette commande sera automatiquement restitue.' si statut ∈ {EN_PREPARATION, PRETE, EN_LIVRAISON}. Footer : 'Retour' (outline) et 'Annuler la commande' (destructive, libelle 'Annulation...' + disabled pendant l'appel)
- Dialog 'Supprimer la commande {numero} ?' (deleteTarget) — description 'Cette action est definitive — la commande de {client_nom} sera supprimee.'. Footer : 'Annuler' (outline) et 'Supprimer' (destructive, libelle 'Suppression...' + disabled pendant l'appel)
- Dialog 'Nouvelle commande' (CreateOrderDialog, max-w-2xl, max-h-90vh scrollable) — rendu seulement si (isGerant || isPreparateur). Titre identique meme pour le preparateur (seul le bouton d'ouverture dit 'Nouvelle recuperation')
- Dialog 'Modifier la commande {numero}' (EditOrderDialog, max-w-2xl, max-h-90vh scrollable) — rendu seulement si isGerant
- Popover/dropdown d'autocomplete catalogue dans OrderItemsEditor : liste absolue z-10 sous l'input, max-h 56, s'ouvre des qu'un filtre OU du texte est saisi et qu'aucune reference n'est encore selectionnee ; etats 'Recherche…' / 'Aucun resultat pour cette selection.' / liste des references cliquables ('{marque} {reference} ({type})' + prix a droite si showPrices)
- Badges-filtres supprimables (chips) dans OrderItemsEditor : un Badge secondary par filtre actif (Categorie / Sous-type / Marque) avec un bouton '×' ; retirer la categorie retire aussi le sous-type
- Select d'action inline dans chaque ligne du tableau (gerant) — se comporte comme un menu contextuel, placeholder 'Action', ne conserve pas de valeur selectionnee
- Tooltips shadcn sur chaque IconAction (le contenu du tooltip est le meme texte que le libelle, y compris 'Disponible le {date}' quand l'action est bloquee)

**Recherche, filtres, tri, pagination** (12)

- Recherche texte GLOBALE cote client (searchQuery) appliquee sur visibleOrders — matche sur numero, client_nom, adresse_livraison, telephone, livraison_zone, preparateur_name, livreur_name, statut_courant, le texte concatene de tous les items (reference_name, product_name, couleur, variant_name) et la date_commande formatee (fmtAppDate ET fmtAppDateTime). Insensible a la casse, trim, includes simple. Placeholder gerant/livreur : 'Code, client, produit, adresse, livreur, preparateur, date...' ; preparateur : 'Code, client, produit, adresse, date...'. AUCUNE barre de recherche n'est rendue pour un utilisateur qui n'est ni gerant ni preparateur ni livreur
- GERANT — barre de boutons statut : Toutes (ALL) / Pas encore livree (NON_LIVREE, filtre CLIENT-side sur statut !== 'LIVRE') / un bouton par statut (envoye au serveur en param `statut`)
- GERANT — Select 'Statut' avec les memes valeurs (Tous, Pas encore livree, + les 7 statuts), lie au meme state statutFilter
- GERANT — Input type=date 'Date' (gerantDate) : envoie date_debut=date_fin=gerantDate (un seul jour, pas de plage)
- GERANT — Select 'Preparateur' (preparateurFilterId) alimente par GET available-staff?role=PREPARATEUR (sans magasin), envoie preparateur_id. ATTENTION : aucune option 'Tous' dans la liste, la seule facon de l'enlever est le bouton Reinitialiser
- GERANT — bouton 'Reinitialiser' (ghost, sm) visible si gerantDate || preparateurFilterId || statutFilter!=='ALL' || searchQuery ; remet les 4 a zero
- PREPARATEUR (vue ACTIF) — Input type=date 'Date' (preparateurDate) : envoie date_debut=date_fin ; + recherche ; + bouton 'Reinitialiser' si l'un des deux est rempli
- PREPARATEUR — segmentation client-side par onglet : 'A preparer' garde les commandes dont livraison_zone !== 'RECUPERATION', 'Recuperations' garde livraison_zone === 'RECUPERATION'
- LIVREUR (vue ACTIF) — Select 'Statut' limite a LIVREUR_STATUT_ACTIF : 'Tous les statuts' (ALL), 'En preparation', 'A recuperer' (= valeur PRETE, libelle metier), 'En livraison' ; envoie `statut`
- LIVREUR (vue ACTIF) — Input type=date 'Date' (livreurDate) : envoie date_debut=date_fin ; + recherche ; + bouton 'Reinitialiser' si statut!=='ALL' || date || recherche
- PREPARATEUR & LIVREUR (vue HISTORIQUE) — DateTimeInput 'Du' (historiqueFrom) et 'Au' (historiqueTo) convertis en ISO via new Date(...).toISOString() et envoyes en date_from/date_to ; Select 'Statut' avec HISTORIQUE_STATUT_FILTERS (Tous les statuts, Livrees, Retours, Annulees, En livraison, A recuperer, En preparation, Nouvelles) ; bouton 'Reinitialiser' si l'un des trois est renseigne. Le param historique=1 est toujours joint
- AUCUNE pagination, AUCUN tri utilisateur, AUCUN export : la liste complete renvoyee par l'API est affichee telle quelle (ordre du serveur ; '-date_commande' cote backend pour l'historique)

**Appels API** (16)

- GET /api/users/me/ — via useCurrentUser, fournit role + commande_role (base de tout le gating)
- GET /api/orders/ (+ params statut, date_debut, date_fin, historique=1, date_from, date_to, preparateur_id) — liste des commandes ; le backend filtre deja par role et renvoie un serializer different par role
- POST /api/orders/ — creation d'une commande (client_nom, telephone, livraison_zone, adresse_livraison, mode_paiement, date_commande, note_preparateur, note_livreur, items[])
- PATCH /api/orders/{id}/ — modification d'une commande (gerant uniquement cote serveur : IsGerant)
- DELETE /api/orders/{id}/ — suppression definitive (gerant, statut NOUVELLE)
- POST /api/orders/{id}/status/ — changement de statut. Corps JSON {statut, note, preparateur_id?, livreur_id?, assigned_at?} ; si une photo est jointe, envoi en multipart/form-data avec les memes champs + photo
- POST /api/orders/{id}/cancel/ — annulation (corps {note}, ici toujours sans note)
- POST /api/orders/{id}/assign-preparateur/ — pre-assignation preparateur sans changer le statut ({preparateur_id})
- POST /api/orders/{id}/assign-livreur/ — pre-assignation livreur sans changer le statut ({livreur_id})
- GET /api/orders/available-staff/?role=PREPARATEUR|LIVREUR[&magasin_id=][&date_commande=ISO] — liste {id, full_name, magasin_id, available} ; date_commande sert a signaler (sans bloquer) un conflit d'horaire livreur
- GET /api/orders/delivery-zones/ — via useDeliveryZones, alimente zoneOptions (code/nom/prix)
- GET /api/catalog/categories/ — selecteur Categorie de OrderItemsEditor
- GET /api/catalog/types/ — selecteur Sous-type (filtre client-side sur t.category === categoryId)
- GET /api/catalog/brands/ — selecteur Marque
- GET /api/catalog/references/autocomplete/?q=&type=&brand=&category= — autocomplete catalogue (debounce 250 ms), renvoie les references avec leur tableau couleurs[{variant_id, couleur, stock_actuel}] et prix_vente
- WS /ws/data/ (DataSyncProvider) — evenements model 'order' et 'order_status_history' declenchent un refetch silencieux

**Etats UI** (13)

- userLoading : le premier fetchOrders n'est declenche qu'une fois useCurrentUser resolu (useEffect sur [userLoading, fetchOrders]) — avant, `loading` vaut true et le skeleton est affiche
- Loading liste : `loading===true` -> <Skeleton className="h-64 w-full" /> dans la Card (padding 6). fetchOrders(true) (temps reel, apres action, apres edition) ne repasse PAS loading a true = refresh silencieux sans clignotement
- Empty : searchableOrders.length===0 -> texte centre 'Aucune commande trouvee pour cette recherche.' (meme message qu'il y ait ou non une recherche active)
- Erreur de chargement : catch -> toast.error(err.message || 'Erreur de chargement des commandes'), la liste garde son contenu precedent, pas d'ecran d'erreur dedie
- Erreur d'action de statut : toast.error(err.message || 'Action impossible') — c'est ainsi que remontent les refus serveur (transition impossible, jour J, commande assignee a quelqu'un d'autre)
- Disabled 'jour J' : IconAction disabled + libelle 'Disponible le {JJ/MM/AAAA}' pour preparateur/livreur sur une commande planifiee plus tard ; meme regle pour le bouton d'action dans le detail
- Disabled soumission : boutons 'Creer la commande'/'Enregistrer'/'Supprimer'/'Annuler la commande' passent en libelle de progression ('Creation…', 'Enregistrement...', 'Suppression...', 'Annulation...') et disabled pendant l'appel
- Disabled 'Assigner' tant qu'aucun membre du staff n'est selectionne
- Disabled option couleur si stock_actuel <= 0 dans le Select Couleur
- Loading AssignStaffDialog : Skeleton h-10 ; Empty : 'Aucun {role} enregistre pour ce magasin.'
- Loading autocomplete : 'Recherche…' ; Empty autocomplete : 'Aucun resultat pour cette selection.'
- Aucun etat 'unauthorized' cote page : pas de guard de role ; un utilisateur non authentifie est redirige vers /login par le layout. Un role non prevu voit simplement une page en lecture seule sans action
- Les listes de staff/zones/categories/types/marques echouent en silence (catch -> tableau vide), sans toast

**Details UX** (14)

- Palette de badges de statut : NOUVELLE bg-slate-100/text-slate-800, EN_PREPARATION bg-amber-100/text-amber-800, PRETE bg-blue-100/text-blue-800, EN_LIVRAISON bg-purple-100/text-purple-800, LIVRE bg-green-100/text-green-800, RETOUR bg-red-100/text-red-800, ANNULEE bg-zinc-200/text-zinc-800. statutInfo() retombe sur NOUVELLE si le statut est inconnu
- Format monetaire : Intl.NumberFormat('fr-MG') sur le nombre arrondi + ' Ar' (ex '1 250 000 Ar'). Toute valeur nulle/undefined donne '0 Ar'
- Formats de date : colonne Date = JJ/MM HH:mm (sans annee) ; colonne Assigne a = JJ/MM HH:mm ; timeline et historique = JJ/MM/AAAA HH:mm ; libelle 'Disponible le' = JJ/MM/AAAA. TOUS en fuseau Indian/Antananarivo, quel que soit le fuseau de l'appareil ; fmtAppDate/fmtAppDateTime renvoient '—' si valeur absente/invalide
- Toasts (sonner) : succes 'Commande {numero} → {libelle du nouveau statut}', 'Commande {numero} supprimee', 'Commande {numero} annulee', 'Commande creee', 'Commande creee et assignee', 'Commande mise a jour' ; erreurs listees dans les formulaires
- Masquage financier livreur : dans le tableau, un mode_paiement 'AVANT' affiche 'Deja paye' en vert emeraude au lieu du montant ; dans le dialogue de confirmation, ligne verte 'A encaisser : Rien — deja paye' ; dans le detail, la ligne 'Total a payer' disparait totalement quand mode_paiement === 'AVANT' (pour tous les roles, pas seulement le livreur)
- Masquage financier preparateur : colonne Total absente du tableau, showPrices=false dans OrderItemsEditor (pas de prix dans les suggestions, pas de champ Prix, pas de montant de ligne) et pas de recap Frais/Total dans le formulaire de creation
- Lien telephone cliquable (tel:) uniquement dans la vue livreur, en bleu avec icone Phone
- Photo de preparation : proposee uniquement au passage a PRETE, apercu 80x80 avant envoi, vignette 64x64 + lien 'Voir / telecharger la photo' dans l'historique detaille
- Le libelle metier 'A recuperer' remplace 'Prete' dans le filtre statut du livreur (meme valeur PRETE cote API)
- Le libelle 'Recuperee par le client' remplace 'Livree' pour une commande de zone RECUPERATION au statut PRETE (gerant)
- Rangee d'entete responsive : flex-col sur mobile, flex-row a partir de sm ; page en p-4 sm:p-6 space-y-6
- Zone de tableau scrollable horizontalement (overflow-x-auto) — indispensable pour le portage mobile ou il faudra probablement une liste de cartes
- Le Select d'action gerant recalcule gerantActionOptions(order) 3 fois par ligne (rendu + onValueChange + map) — comportement identique, simple duplication
- La colonne 'Assigne a' affiche l'heure de preparation issue de status_history (premiere occurrence de EN_PREPARATION) et, pour le livreur, 'Livre le' si LIVRE sinon 'Prevu le' + date_commande

### `/products`

- **Fichier Next.js** : `frontend/app/(app)/products/page.tsx`
- **Groupe d'audit** : `products`
- **Cible Flutter** : lib/features/catalog/catalog_screen.dart
- **Etat** : PARTIAL

**Role et gating.** Gating 100% côté client via `useCurrentUser()` (GET /users/me/). Seul `isGerant` est utilisé dans la page principale (`const { isGerant, loading: userLoading } = useCurrentUser()`), et `isPreparateur` uniquement dans ProductCreateOrderDialog. isGerant = role 'admin' OU role 'magasin' (défini dans lib/auth/useCurrentUser.ts). isPreparateur = role 'employer' && commande_role === 'PREPARATEUR' ; isLivreur = role 'employer' && commande_role === 'LIVREUR'. AUCUNE redirection ni écran 'unauthorized' dans la page : un non-gérant (PREPARATEUR) accède à la page en LECTURE SEULE — les colonnes 'Prix actuel' et 'Marge' sont masquées, la colonne Actions est vide, tous les boutons de la barre d'outils sauf 'Rafraîchir' sont masqués, et le dialog de détail s'ouvre avec `canEdit={false}` (tous les champs `disabled`, aucun bouton Enregistrer/Ajuster/Supprimer/Ajouter couleur). LIVREUR : l'entrée de menu 'Produits' est masquée dans la sidebar (`hideLivreur: true` dans components/layout/sidebar.tsx ligne 60-64) mais l'URL reste accessible en direct (même rendu lecture seule). Le layout app/(app)/layout.tsx redirige vers /login si `djangoClient.isAuthenticated()` est faux. Les dialogs CatalogSettingsDialog et BulkPriceDialog sont montés inconditionnellement (mais leurs boutons d'ouverture sont réservés au gérant) ; ProductCreateOrderDialog et CreateReferenceDialog sont montés seulement si isGerant. Le premier `fetchAll()` n'est déclenché qu'une fois `userLoading === false`.

**Objectif.** Catalogue produits complet (hiérarchie Catégorie -> Sous-type -> Marque -> Référence -> Couleur/variante, §8 du cahier des charges) : liste filtrable des références avec prix, marge, variantes couleur et stock ; CRUD complet des références/variantes ; ajustement manuel de stock (ENTREE/SORTIE) ; import/export Excel avec revue post-import assistée par IA (détection de quasi-doublons) et annulation du batch ; paramétrage du catalogue (marques, catégories + sous-types, couleurs) ; modification groupée des prix par sous-type ; création d'une commande directement depuis le catalogue.

**Fonctionnalites** (56)

- Titre H1 'Catalogue produits' avec icône Package (h-6 w-6)
- Sous-titre 'Catégorie → Sous-type → Marque → Référence → Couleur (§8 du cahier des charges).'
- Bouton Rafraîchir : icône RefreshCw seule, carré 40x40 (h-10 w-10 p-0), variant outline — appelle fetchAll() en mode NON silencieux (affiche le skeleton). Visible pour TOUS les rôles
- Bouton 'Exporter Excel' (icône Download, variant secondary) — isGerant uniquement ; disabled pendant l'export ; libellé devient 'Export...' pendant l'appel ; déclenche le téléchargement du blob via <a download> + URL.createObjectURL/revokeObjectURL ; nom de fichier issu du header Content-Disposition, fallback 'catalogue.xlsx'
- Bouton 'Importer Excel' (icône Upload, variant secondary) — isGerant uniquement ; clique sur un <input type=file accept='.xlsx,.xls'> caché via une ref ; disabled pendant l'import ; libellé 'Import...' pendant ; l'input est vidé (e.target.value = '') dès la sélection pour permettre de re-choisir le même fichier
- Bouton 'Paramètres' (icône Settings, variant outline) — isGerant — ouvre CatalogSettingsDialog
- Bouton 'Modifier prix par sous-type' (icône DollarSign, variant outline) — isGerant — ouvre BulkPriceDialog (pré-rempli avec le filtre sous-type courant si != ALL)
- Bouton 'Nouvelle commande' (icône ShoppingCart, fond slate-900/texte blanc, inversé en dark) — isGerant — ouvre ProductCreateOrderDialog
- Bouton 'Nouvelle référence' (icône Plus, variant default) — isGerant — ouvre CreateReferenceDialog
- Chargement initial parallèle (Promise.all) de 5 listes : références, catégories, sous-types, marques, couleurs
- fetchAll(silent) : si silent=true, ne bascule pas `loading` (pas de skeleton) — utilisé par le rafraîchissement temps réel et par tous les callbacks onChanged/onCatalogChanged
- Rafraîchissement temps réel : useRealtimeRefresh(['product_variant','stock_movement'], () => fetchAll(true)) — WebSocket via DataSyncContext, debounce 400 ms
- TABLEAU — colonne 1 (w-12) : miniature photo 32x32 arrondie object-cover si ref.photo, sinon carré bordé bg-muted avec icône Package grisée
- TABLEAU — colonne 'Sous-type' : ref.type_name
- TABLEAU — colonne 'Marque' : ref.brand_name en font-medium
- TABLEAU — colonne 'Référence' : ref.reference_name
- TABLEAU — colonne 'Prix actuel' : fmt(ref.prix_achat) — AFFICHÉE UNIQUEMENT si isGerant (en-tête ET cellule conditionnés)
- TABLEAU — colonne 'Prix de vente' : fmt(ref.prix_vente) — tous rôles
- TABLEAU — colonne 'Marge' : fmt(prix_vente - (prix_achat||0)), texte vert si >= 0, rouge si < 0 — UNIQUEMENT si isGerant
- TABLEAU — colonne 'Variantes' (max-w-60) : 'Aucune' en petit texte grisé si aucune variante, sinon des Badge outline en flex-wrap au format '<couleur> · <stock_actuel>' avec code couleur par seuil
- TABLEAU — colonne 'Stock total' : somme des stock_actuel de toutes les variantes
- TABLEAU — colonne 'Statut' : Badge calculé par stockInfo() = 'Rupture' (rouge) si UNE variante is_rupture, sinon 'Stock bas' (orange) si UNE variante is_stock_bas, sinon 'OK' (vert)
- TABLEAU — colonne 'Actions' (alignée à droite) : si isGerant, bouton icône Pencil (ghost) qui ouvre le dialog de détail et bouton icône Trash2 rouge (ghost) qui ouvre la confirmation de suppression ; les deux font e.stopPropagation() pour ne pas déclencher le clic de ligne. Cellule VIDE pour un non-gérant
- TABLEAU — ligne entière cliquable (cursor-pointer) : ouvre ProductDetailDialog sur la référence (pour tous les rôles, en lecture seule si non gérant)
- Aucune pagination, aucun tri de colonne, aucune sélection multiple : l'ordre est celui renvoyé par l'API
- Suppression d'une référence : DELETE puis toast 'Référence supprimée' + fetchAll() (non silencieux) ; en erreur toast err.message || 'Suppression impossible'
- Import Excel : le fichier retourné par le serveur (avec colonnes Statut + Date par ligne) est automatiquement retéléchargé, puis fetchAll(), puis ouverture du dialog 'Résumé de l'import'
- Import Excel : si errors_count > 0, toast.error '<n> ligne(s) en erreur — voir la colonne "Statut" du fichier téléchargé.' avec duration 10000 ms
- Vérification IA post-import (best-effort) : si des références ont été créées, POST /api/ai/check-duplicates avec {newNames, existingNames} où existingNames = `${brand_name} ${reference_name}` de toutes les références déjà chargées ; le résultat alimente aiWarnings du dialog de revue ; en cas d'échec (Ollama indisponible) on passe simplement aiStatus à 'done' sans warning
- ProductDetailDialog — Bouton 'Enregistrer les informations' (pleine largeur) : PUT de la référence puis PATCH FormData séparé si une photo a été choisie ; libellé 'Enregistrement…' pendant
- ProductDetailDialog — Toggle Actif/Inactif : un seul bouton dont le libellé est 'Active' (variant default) ou 'Inactive' (variant outline), avec la mention 'Inactive = invisible dans la recherche de commande.' — isGerant uniquement
- ProductDetailDialog — Colonne droite 'Variantes (<n>)' + 'Stock total : <somme>' ; liste scrollable (max-h-64) de cartes couleur affichant 'Stock: X · Seuil: Y'
- ProductDetailDialog — Par variante (si canEdit) : bouton 'Ajuster' (ouvre AdjustStockDialog) et bouton icône Trash2 rouge (ouvre la confirmation de suppression de variante)
- ProductDetailDialog — Bloc 'Ajouter une couleur' (si canEdit) : select Couleur (uniquement les couleurs NON déjà utilisées par cette référence), Stock initial, Seuil d'alerte, bouton 'Ajouter' (disabled tant qu'aucune couleur choisie)
- ProductDetailDialog — Création rapide de couleur : champ 'Nouvelle couleur (ex: Bleu)' + bouton 'Créer' — POST /catalog/colors/, toast 'Couleur créée', vide le champ, rafraîchit le catalogue et présélectionne la couleur créée
- CreateReferenceDialog — Création rapide de sous-type : champ 'Nouveau sous-type (ex: MAGSAFE)' + bouton 'Créer' (visible seulement après choix d'une catégorie) — POST /catalog/types/, présélectionne le sous-type créé
- CreateReferenceDialog — Deux modes de stock selon `avec_couleurs` de la catégorie choisie : liste de variantes couleur, OU un unique bloc 'Stock' (quantité + seuil) qui créera une variante nommée 'Standard'
- CreateReferenceDialog — Chips de variantes ajoutées : '<couleur> · <stock> (seuil <seuil>)' avec bouton × pour retirer ; compteur '<n> couleur(s) · <total> unité(s)'
- AdjustStockDialog — Bascule Entrée/Sortie : deux boutons pleine largeur (ArrowUpCircle 'Entrée' / ArrowDownCircle 'Sortie'), celui actif en variant default
- AdjustStockDialog — Bandeau récapitulatif : Badge couleur + 'Stock actuel : <n> · Seuil d'alerte : <n>'
- CatalogSettingsDialog — 3 onglets : Marques (défaut), Catégories, Couleurs
- CatalogSettingsDialog / Marques — 14 boutons de marques suggérées en un clic (Samsung, iPhone, Huawei, Redmi, Xiaomi, Tecno, Infinix, Itel, Oppo, Realme, Google Pixel, Poco, Vivo, Honor) : si la marque existe déjà (comparaison insensible à la casse) le bouton est variant secondary + icône Check + disabled ; sinon variant outline + icône Plus ; disabled aussi pendant l'ajout en cours
- CatalogSettingsDialog / Marques — Liste scrollable (max-h-64) de CrudRow : renommer en place (Pencil -> Input + OK/Annuler) et supprimer (Trash2)
- CatalogSettingsDialog / Marques — Champ 'Nouvelle marque' + bouton 'Ajouter' (Plus)
- CatalogSettingsDialog / Catégories — Bloc 'Nouvelle catégorie' : nom + bouton 'Ajouter' (FolderPlus) + bascule 'Avec couleurs' (Palette) / 'Sans couleurs' + texte explicatif
- CatalogSettingsDialog / Catégories — Une carte par catégorie : icône Tag, nom, Badge cliquable 'Avec couleurs'/'Sans couleurs' qui bascule immédiatement le flag (PATCH, sans toast de succès), Pencil (renommer en place), Trash2 (supprimer)
- CatalogSettingsDialog / Catégories — Sous-liste indentée des sous-types de la catégorie : renommage en place, suppression, et champ 'Nouveau sous-type' + bouton 'Ajouter' propre à chaque catégorie (état stocké dans un Record<categoryId, string>)
- CatalogSettingsDialog / Couleurs — Liste CrudRow (renommer/supprimer) + champ 'Nouvelle couleur (ex: Bleu)' + bouton 'Ajouter'
- CatalogSettingsDialog — Bouton 'Fermer' en pied de dialog
- BulkPriceDialog — Compteur dynamique '<n> référence(s) concernée(s)' calculé côté client sur les références du sous-type sélectionné
- BulkPriceDialog — Bouton 'Appliquer' disabled si submitting || aucun sous-type || matchCount === 0 ; libellé 'Mise à jour...' pendant
- ProductCreateOrderDialog — Bascule 'Type de commande' : bouton 'À livrer' (Truck, force zone=ZONE1) / 'Récupération sur place' (Package, force zone=RECUPERATION) — masquée pour un préparateur (texte explicatif à la place)
- ProductCreateOrderDialog — Récapitulatif Frais de livraison + Total à payer (masqué pour un préparateur)
- ProductOrderItemsEditor — Panier local : liste des lignes ajoutées avec '<marque référence> (<couleur>) x<qté>', montant de ligne et bouton Trash2 pour retirer
- ProductOrderItemsEditor — Chips de filtres actifs (catégorie/sous-type/marque) avec × pour les retirer individuellement
- ProductOrderItemsEditor — Recherche par autocomplétion de référence avec dropdown de suggestions

**Formulaires** (9)

- FORMULAIRE 'Nouvelle référence produit' (CreateReferenceDialog, max-w-xl, scroll 90vh, gérant seulement). CHAMPS : Catégorie (Select obligatoire pour débloquer le sous-type ; changer la catégorie remet typeId à '') ; Marque (Select) ; Référence (modèle) (Input texte, placeholder 'Ex: A16, S25 Ultra') ; Sous-type (Select filtré sur la catégorie, affiché seulement si une catégorie est choisie) + création rapide (Input 'Nouveau sous-type (ex: MAGSAFE)' + bouton 'Créer' — ne fait rien si pas de catégorie ou nom vide, toast 'Sous-type créé' puis présélection) ; Prix actuel (Ar) (Input number, placeholder '0') ; Prix de vente (Ar) (Input number) ; Photo (optionnel) (Input file accept='image/*' avec aperçu 96x96 via URL.createObjectURL) ; SI catégorie avec couleurs : sous-formulaire de variante = Couleur (Select sur TOUTES les couleurs), Nombre (Input number min 0, placeholder '0'), Seuil d'alerte (Input number min 0, placeholder '1'), bouton 'Ajouter' (disabled tant qu'aucune couleur sélectionnée) qui empile la variante localement ; SI catégorie sans couleurs : Quantité en stock (number min 0, défaut vide -> 0) + Seuil d'alerte (number min 0, valeur initiale '1'). VALIDATIONS : addVariant refuse un doublon de couleur -> toast.error 'Cette couleur est déjà dans la liste' ; submit exige typeId && brandId && referenceName.trim() && prixVente sinon toast.error 'Tous les champs sont requis'. AFFICHAGE CALCULÉ : 'Marge estimée : <fmt(prix_vente - prix_achat)> / unité' en vert si >= 0 sinon rouge, affiché dès que les deux prix sont saisis. SOUMISSION : POST référence -> (si photo) PATCH FormData photo -> boucle séquentielle de POST /catalog/variants/ (soit les variantes saisies, soit une unique variante 'Standard' pour une catégorie sans couleurs) -> toast.success 'Référence créée' -> onCreated() qui ferme le dialog et relance fetchAll() non silencieux. ERREUR : toast.error(err.message || 'Erreur lors de la création'). Bouton 'Créer la référence' -> libellé 'Création…' + disabled pendant. Bouton 'Annuler' ferme sans confirmation. RESET : tous les champs sont réinitialisés à chaque ouverture (useEffect sur `open`).
- FORMULAIRE 'Détail / modification de référence' (ProductDetailDialog, max-w-4xl, 2 colonnes, scroll 90vh, ouvert par clic de ligne ou bouton Pencil). CHAMPS COLONNE GAUCHE : Catégorie (Select, disabled si !canEdit ; changer la catégorie vide le sous-type) ; Sous-type (Select — liste filtrée sur la catégorie si une catégorie est déterminée, sinon tous les types) ; Marque (Select) ; Référence (modèle) (Input texte) ; Prix actuel (Ar) (Input number — AFFICHÉ UNIQUEMENT si canEdit) ; Prix de vente (Ar) (Input number, toujours affiché mais disabled si !canEdit) ; Photo (aperçu 64x64 ou placeholder Package + Input file accept='image/*' seulement si canEdit) ; Toggle Active/Inactive (canEdit). VALIDATION : submit exige referenceName.trim() && prixVente sinon toast.error 'Champs requis manquants' ; prix_achat vide est envoyé comme 0. AFFICHAGE CALCULÉ : 'Marge estimée : <fmt> / unité' vert/rouge (canEdit seulement). SOUMISSION : PUT /catalog/references/{id}/ puis PATCH FormData photo si nouvelle photo -> toast.success 'Référence mise à jour' -> onChanged() (fetchAll silencieux) -> fermeture du dialog. ERREUR : toast.error(err.message || 'Erreur lors de la mise à jour'). PRÉ-REMPLISSAGE : useEffect sur [reference, types] remet tous les champs depuis l'objet référence (catégorie déduite en cherchant le type courant dans la liste des types) et remet à zéro les champs du sous-formulaire variante.
- SOUS-FORMULAIRE 'Ajouter une couleur' (dans ProductDetailDialog, canEdit seulement). CHAMPS : Couleur (Select ne listant QUE les couleurs non déjà utilisées par cette référence) ; Stock initial (number, placeholder '0', défaut 0) ; Seuil d'alerte (number, placeholder '1', défaut 1). VALIDATION : bouton 'Ajouter' disabled sans couleur ; addVariant retoaste 'Choisissez une couleur' si l'id ne correspond à aucune couleur. SOUMISSION : POST /catalog/variants/ avec {product_reference, couleur: <nom de la couleur, pas l'id>, stock_actuel, seuil_alerte} -> toast.success 'Variante ajoutée' -> reset des 3 champs -> onChanged(). ERREUR : toast.error(err.message || 'Erreur').
- SOUS-FORMULAIRE 'Créer une couleur à la volée' (dans ProductDetailDialog). CHAMP : Input 'Nouvelle couleur (ex: Bleu)' (h-8 text-xs) + bouton 'Créer'. VALIDATION : ne fait rien si vide/espaces. SOUMISSION : POST /catalog/colors/ -> toast 'Couleur créée' -> vide le champ -> onCatalogChanged() (fetchAll silencieux) -> présélectionne l'id de la couleur créée dans le Select de variante.
- FORMULAIRE 'Ajuster le stock' (AdjustStockDialog, ouvert depuis une variante). En-tête : 'Ajuster le stock — <brand_name> <reference_name>' + description '§7.4 : entrée/sortie manuelle réservée au gérant'. Bandeau : Badge couleur + 'Stock actuel : <n> · Seuil d'alerte : <n>'. CHAMPS : Type (deux boutons exclusifs Entrée/Sortie, valeur par défaut 'ENTREE') ; Quantité (Input number min=1, placeholder 'Stock actuel : <n>') ; Note (optionnel) (Input texte, placeholder 'Ex: correction inventaire'). VALIDATION : quantité vide ou < 1 -> toast.error 'Quantité requise'. Aucun contrôle client que la sortie ne dépasse pas le stock (laissé au serveur). SOUMISSION : POST /catalog/variants/{id}/adjust/ {type, quantite, note} -> toast.success 'Stock ajusté' -> onAdjusted() qui ferme le dialog et déclenche onChanged(). ERREUR : toast.error(err.message || 'Erreur'). Bouton 'Confirmer' -> 'Enregistrement…' + disabled ; bouton 'Annuler' ferme. RESET : les 3 champs sont réinitialisés à chaque changement de variante (useEffect sur `variant`).
- FORMULAIRE 'Modifier le prix par sous-type' (BulkPriceDialog, max-w-md, gérant). CHAMPS : Sous-type (Select sur TOUS les sous-types, toutes catégories confondues ; pré-rempli avec le filtre sous-type de la page si != ALL) ; Nouveau prix actuel (Input number min 0, placeholder 'Laisser vide = inchangé') ; Nouveau prix de vente (idem). VALIDATIONS : pas de sous-type -> toast.error 'Choisissez un sous-type' ; aucun des deux prix renseigné -> toast.error 'Indiquez au moins un prix à modifier' ; bouton 'Appliquer' disabled si submitting || !typeId || matchCount === 0. SOUMISSION : POST /catalog/references/bulk-update-price/ avec type_id + seulement les prix renseignés -> toast.success '<res.updated> référence(s) mise(s) à jour' -> onDone() qui ferme et relance fetchAll(true). ERREUR : toast.error(err.message || 'Erreur lors de la mise à jour groupée'). RESET à chaque ouverture (useEffect sur [open, defaultTypeId]).
- FORMULAIRE 'Nouvelle commande' (ProductCreateOrderDialog, max-w-2xl, scroll 90vh, monté seulement si isGerant). CHAMPS DANS L'ORDRE : bloc panier ProductOrderItemsEditor ; Type de commande (2 boutons 'À livrer' -> zone ZONE1 / 'Récupération sur place' -> RECUPERATION ; remplacé pour un préparateur par le texte 'Retrait sur place uniquement — la commande apparaîtra dans "Récupérations" une fois prête, à valider comme livrée au comptoir par le gérant.') ; Date et heure de la commande (composant DateTimeInput = input date + input time séparés, valeur format YYYY-MM-DDTHH:mm, initialisée à maintenant, hint 'Vide = maintenant.') ; Préparateur (Select, placeholder 'Assigner plus tard', liste GET available-staff PREPARATEUR — masqué pour un préparateur) ; Livreur (Select, placeholder 'Assigner plus tard', liste rechargée à chaque changement de date) ; SI zone != RECUPERATION : Zone de livraison (Select des zones hors RECUPERATION) + Adresse de livraison (Input, placeholder 'Ex: Lot II M 45 Antanimena, Antananarivo') + Paiement (Select 'Paiement avant la livraison' / 'Paiement à la livraison', défaut LIVRAISON) ; Nom client (Input, placeholder 'Rakoto Jean') ; Téléphone (Input, valeur initiale '+261', placeholder '+261340000000') ; Note pour le préparateur (Textarea, libellé 'Note (optionnel)' pour un préparateur) ; Note pour le livreur (Textarea, affiché seulement si !isPreparateur && zone != RECUPERATION). VALIDATIONS SÉQUENTIELLES : nom client vide -> toast.error 'Nom du client requis' ; téléphone ne matchant pas /^\+261\d{9}$/ -> toast.error 'Téléphone au format +261XXXXXXXXX' ; panier vide -> toast.error 'Ajoutez au moins un article'. SOUMISSION : POST /orders/ (note_livreur forcée à '' si zone RECUPERATION ; date convertie en ISO) puis, si renseignés, POST assign-preparateur et POST assign-livreur SÉPARÉMENT, chacun dans son try/catch : un échec d'assignation produit un toast.error 'Commande créée, mais l'assignation du préparateur/livreur a échoué : <msg> (à assigner depuis le tableau).' ; toast.success 'Commande créée et assignée' ou 'Commande créée' seulement si aucune assignation n'a échoué. Puis onCreated() (ferme + fetchAll()) et fermeture. ERREUR globale : toast.error(err.message || 'Erreur lors de la création'). Bouton 'Créer la commande' -> 'Création…' + disabled. RESET complet à chaque ouverture.
- SOUS-FORMULAIRE 'Ajouter un article' (ProductOrderItemsEditor). CHAMPS : Catégorie (Select — changer la catégorie remet le sous-type à null) ; Sous-type (Select filtré sur la catégorie si choisie) ; Marque (Select) ; Recherche (Input 'Rechercher une référence (ex: A15)' — affiche le libellé de la référence sélectionnée tant qu'elle l'est ; retaper efface la sélection et la couleur) ; puis, une fois une référence choisie : Couleur (Select listant '<couleur> (stock: <n>)', options avec stock <= 0 DISABLED), Quantité (number min 1, placeholder 'Ex: 1'), Prix (Ar) (Input readOnly + disabled affichant fmt(prix_vente), masqué si !showPrices), bouton 'Ajouter à la commande' pleine largeur. VALIDATIONS : pas de référence ou pas de couleur -> toast.error 'Sélectionnez une référence et une couleur' ; quantité vide ou < 1 -> toast.error 'Quantité invalide' ; quantité > stock_actuel -> toast.error 'Stock insuffisant (disponible: <n>)'. APRÈS AJOUT : la ligne est empilée dans le panier local (clé `${variantId}-${Date.now()}`) et tous les champs de saisie (query, suggestions, référence, couleur, quantité) sont vidés — les filtres catégorie/sous-type/marque, eux, sont conservés.
- FORMULAIRES INLINE CRUD (CatalogSettingsDialog). Marque : Input 'Nouvelle marque' + bouton 'Ajouter' (ignore si vide) -> POST -> toast 'Marque ajoutée' + vide le champ ; renommage inline (Input autoFocus + OK/Annuler, ignore si vide) -> PATCH -> toast 'Marque renommée' ; suppression immédiate SANS confirmation -> DELETE -> toast 'Marque supprimée', erreur -> toast err.message || 'Suppression impossible (marque utilisée par des références)'. Couleur : mêmes patrons, toasts 'Couleur ajoutée' / 'Couleur renommée' / 'Couleur supprimée', erreur générique 'Erreur lors de la suppression'. Catégorie : Input 'Ex. Accessoires' + toggle Avec/Sans couleurs + bouton 'Ajouter' -> POST {nom, ordre: categories.length, avec_couleurs} -> toast 'Catégorie ajoutée', reset du champ ET du toggle à 'Avec couleurs' ; renommage inline -> toast 'Catégorie renommée' ; suppression sans confirmation, erreur -> 'Suppression impossible (des sous-types en dépendent encore)' ; bascule du Badge avec_couleurs -> PATCH sans toast de succès. Sous-type : Input 'Nouveau sous-type' par catégorie + bouton 'Ajouter' -> POST {category, nom} -> toast 'Sous-type ajouté' + vide seulement le champ de cette catégorie ; renommage inline -> 'Sous-type renommé' ; suppression sans confirmation, erreur -> 'Suppression impossible (des références en dépendent encore)'. AUCUN de ces formulaires n'affiche d'état de chargement ni ne disable son bouton pendant l'appel (sauf les boutons de marques suggérées).

**Modales / dialogs / drawers** (13)

- ProductDetailDialog (Dialog max-w-4xl, max-h-90vh scrollable) — titre '<brand_name> <reference_name>' ; deux colonnes : identité/prix/photo/statut à gauche, gestion des variantes à droite ; ouvert par clic de ligne OU bouton Pencil ; en lecture seule si canEdit=false
- AdjustStockDialog (Dialog imbriqué dans ProductDetailDialog) — ajustement de stock ENTREE/SORTIE d'une variante
- Dialog de confirmation 'Supprimer la couleur <couleur> ?' (imbriqué) — description 'Cette variante et son historique de stock seront supprimés.' ; boutons Annuler / Supprimer (destructive)
- Dialog de confirmation 'Supprimer <marque> <référence> ?' (niveau page) — description 'Cette référence et toutes ses variantes seront supprimées définitivement.' ; boutons Annuler / Supprimer (destructive)
- Dialog 'Résumé de l'import' (max-w-lg) — deux cartes chiffrées Ajouté (vert) / Mis à jour (bleu) avec nombre de références et de couleurs ; listes 'Nouvelles références :' et 'Références mises à jour :' (line-clamp-3) ; ligne '<n> ligne(s) déjà traitée(s) ignorée(s).' ; ligne rouge '<n> ligne(s) en erreur — voir le fichier téléchargé.' ; encart 'Analyse IA (quasi-doublons)' ; TROIS boutons de pied : 'Annuler l'import' (destructive, appelle l'API cancel), 'Modifier' (outline, ferme et pré-remplit la recherche), 'Enregistrer' (ferme, aucun appel réseau) — tous disabled pendant l'annulation
- CreateReferenceDialog (max-w-xl, scroll 90vh) — formulaire de création de référence + variantes
- ProductCreateOrderDialog (max-w-2xl, scroll 90vh) — création d'une commande complète depuis le catalogue
- CatalogSettingsDialog (max-w-2xl, max-h-85vh scrollable) — Tabs à 3 onglets Marques / Catégories / Couleurs, pied 'Fermer'
- BulkPriceDialog (max-w-md) — modification groupée des prix par sous-type
- Dropdown d'autocomplétion de référence (panneau absolu z-10, bordé, ombré, max-h-56 scrollable) sous le champ de recherche du panier — chaque suggestion est un bouton pleine largeur '<marque> <référence> (<sous-type>)' + prix à droite si showPrices
- Selects (Radix) utilisés partout : filtres catégorie/sous-type/marque, catégorie/sous-type/marque/couleur des formulaires, préparateur, livreur, zone, mode de paiement
- Édition inline (pas un dialog mais un mode) : CrudRow et les lignes catégorie/sous-type basculent en Input + OK/Annuler
- AUCUNE confirmation avant suppression d'une marque, d'une couleur, d'une catégorie ou d'un sous-type — la suppression est immédiate au clic sur la corbeille

**Recherche, filtres, tri, pagination** (9)

- Recherche texte libre (placeholder 'Marque, référence...', icône loupe en overlay, hauteur h-11), débouncée à 250 ms via useDebouncedValue
- Recherche multi-mots : la requête est découpée sur les espaces et CHAQUE mot doit se retrouver dans la concaténation minuscule de reference_name + brand_name + category_name + type_name + toutes les couleurs des variantes (ordre des mots indifférent — ex. 'samsung bleu', 'pixel 6 pro vert')
- Filtre Catégorie (Select, valeur par défaut 'ALL' = 'Toutes les catégories') — le rapprochement se fait indirectement : la référence n'a pas de champ `category`, on passe par typeToCategory[String(ref.type)] reconstruit à partir de la liste des types
- Changer la catégorie REMET automatiquement le filtre sous-type à 'ALL'
- Filtre Sous-type (Select 'Tous les sous-types') — la liste des options est restreinte aux sous-types de la catégorie sélectionnée
- Filtre Marque (Select 'Toutes les marques')
- Tous les filtres et la recherche sont appliqués CÔTÉ CLIENT (useMemo sur le tableau `references` déjà chargé) — aucun paramètre n'est envoyé à l'API de liste
- Aucun tri configurable, aucune pagination, aucun bouton 'Réinitialiser les filtres'
- Autocomplétion serveur SÉPARÉE dans le panier de commande : GET /catalog/references/autocomplete/ avec q + type + brand + category, débouncée 250 ms, déclenchée dès qu'au moins un des quatre est renseigné ; vide les suggestions si tout est vide

**Appels API** (37)

- GET /catalog/references/ — liste complète des références (avec variants, category_name, type_name, brand_name, prix_achat, prix_vente, photo, actif, is_rupture/is_stock_bas par variante) — chargement initial + tous les rafraîchissements
- GET /catalog/categories/ — alimente le filtre catégorie, les selects des formulaires et l'onglet Catégories ; expose `avec_couleurs`
- GET /catalog/types/ — sous-types ; expose `category` (id) utilisé pour reconstruire le lien type -> catégorie côté client
- GET /catalog/brands/ — marques
- GET /catalog/colors/ — couleurs proposées dans les sélecteurs de variante
- DELETE /catalog/references/{id}/ — supprimer une référence et toutes ses variantes
- PUT /catalog/references/{id}/ — mise à jour d'une référence (type, brand, reference_name, prix_achat, prix_vente, actif)
- PATCH /catalog/references/{id}/ (multipart FormData, champ `photo`) — upload de la photo, appel SÉPARÉ après le PUT (djangoClient.patchFormData)
- POST /catalog/references/ — création d'une référence (type, brand, reference_name, prix_achat, prix_vente)
- GET /catalog/references/export-excel/ — export du catalogue en .xlsx (réponse blob, nom via Content-Disposition)
- POST /catalog/references/import-excel/ (multipart, champ `file`) — import ; réponse = blob du fichier annoté + en-têtes X-Import-Batch-Id, X-Import-Created-References, X-Import-Updated-References, X-Import-Created-Variants, X-Import-Updated-Variants, X-Import-Errors-Count, X-Import-Skipped-Count, X-Import-New-Reference-Names (JSON), X-Import-Updated-Reference-Names (JSON)
- POST /catalog/import-batches/{batchId}/cancel/ — annule un import déjà écrit en base (supprime les créations, restaure les valeurs précédentes des mises à jour)
- POST /catalog/references/bulk-update-price/ {type_id, prix_achat?, prix_vente?} — réponse {updated: n} — modification groupée par sous-type
- GET /catalog/references/autocomplete/?q=&type=&brand=&category= — suggestions pour le panier de commande ; chaque suggestion porte id, brand_name, reference_name, type, type_name, prix_vente et un tableau `couleurs` [{variant_id, couleur, stock_actuel}]
- POST /catalog/variants/ {product_reference, couleur, stock_actuel, seuil_alerte} — ajout d'une variante couleur
- DELETE /catalog/variants/{id}/ — suppression d'une variante (et de son historique de stock)
- POST /catalog/variants/{id}/adjust/ {type: 'ENTREE'|'SORTIE', quantite, note} — ajustement manuel de stock
- POST /catalog/categories/ {nom, ordre, avec_couleurs} — création de catégorie (ordre = categories.length)
- PATCH /catalog/categories/{id}/ {nom} ou {avec_couleurs} — renommage / bascule avec-couleurs
- DELETE /catalog/categories/{id}/ — suppression de catégorie
- POST /catalog/types/ {category, nom} — création de sous-type
- PATCH /catalog/types/{id}/ {nom} — renommage de sous-type
- DELETE /catalog/types/{id}/ — suppression de sous-type
- POST /catalog/brands/ {nom} — création de marque (aussi utilisée par les marques suggérées)
- PATCH /catalog/brands/{id}/ {nom} — renommage de marque
- DELETE /catalog/brands/{id}/ — suppression de marque
- POST /catalog/colors/ {nom} — création de couleur
- PATCH /catalog/colors/{id}/ {nom} — renommage de couleur
- DELETE /catalog/colors/{id}/ — suppression de couleur
- POST /orders/ {client_nom, telephone, livraison_zone, adresse_livraison, mode_paiement, date_commande?, note_preparateur, note_livreur, items:[{product_variant, quantite}]} — création d'une commande depuis le catalogue
- GET /orders/available-staff/?role=PREPARATEUR — liste des préparateurs assignables
- GET /orders/available-staff/?role=LIVREUR&date_commande=<ISO> — liste des livreurs, refetchée à chaque changement de date/heure de commande (le champ `available` signale un conflit d'horaire mais N'EST PAS affiché sur cette page)
- POST /orders/{id}/assign-preparateur/ {preparateur_id} — pré-assignation sans faire progresser le statut
- POST /orders/{id}/assign-livreur/ {livreur_id} — pré-assignation du livreur
- POST /api/ai/check-duplicates (route Next.js locale) {newNames, existingNames} -> {warnings:[{nouvelle, ressemble_a, raison}]} — proxy vers Ollama (POST {OLLAMA_BASE_URL}/api/generate, modèle par défaut qwen3:4b, stream:false, think:false, timeout 600 s) ; renvoie [] si la réponse n'est pas du JSON exploitable
- GET /users/me/ — via useCurrentUser(), détermine isGerant/isPreparateur
- WebSocket (DataSyncContext) — événements de modèles 'product_variant' et 'stock_movement' déclenchant fetchAll(true) avec debounce 400 ms

**Etats UI** (10)

- Loading initial : <Skeleton className='h-64 w-full'> dans un padding 24px à la place du tableau (déclenché seulement par fetchAll(false))
- Empty : paragraphe centré 'Aucune référence.' (py-12, texte muted) — même message quand la liste est vide et quand les filtres ne matchent rien (pas de distinction)
- Erreur de chargement : uniquement un toast.error(err.message || 'Erreur de chargement du catalogue') — le tableau reste sur son état précédent (aucun écran d'erreur, aucun bouton Réessayer)
- Unauthorized : aucun écran dédié — dégradation silencieuse en lecture seule (colonnes prix/marge et actions masquées, champs disabled)
- Disabled : boutons Export/Import pendant l'opération ; 'Ajouter' de variante disabled sans couleur ; 'Appliquer' du bulk price disabled si pas de sous-type ou 0 référence concernée ; options de couleur disabled si stock <= 0 dans le panier ; boutons de marques suggérées disabled si déjà présentes ou en cours d'ajout ; champ Prix du panier readOnly+disabled
- Submitting : libellés dynamiques 'Export...', 'Import...', 'Enregistrement…', 'Création…', 'Mise à jour...', 'Annulation...' avec bouton disabled
- Autocomplétion : trois états dans le dropdown — 'Recherche…', 'Aucun résultat pour cette sélection.', ou la liste des suggestions
- Revue IA post-import : 4 états — 'Analyse en cours…' (loading), 'Aucune nouvelle référence à vérifier.' (skipped), 'Aucun doublon suspect détecté.' (done sans warning), liste des correspondances suspectes (done avec warnings)
- Empty states secondaires : 'Aucune couleur pour cette référence.', 'Aucune marque.', 'Aucune couleur.', 'Aucune catégorie.', 'Aucun sous-type.', 'Aucune' (colonne Variantes)
- Aucune gestion d'état hors-ligne, aucun optimistic update : toute mutation est suivie d'un re-fetch complet

**Details UX** (19)

- Format monétaire : Intl.NumberFormat('fr-MG') sur Math.round(Number(n||0)) suivi de ' Ar' — arrondi à l'entier, séparateur de milliers local, jamais de décimales
- Badges de variante (colonne Variantes) — seuils FIXES indépendants du seuil_alerte : stock <= 0 = rouge (border-red-200 text-red-700 bg-red-50/50), stock <= 2 = bleu (blue-200/700/50), stock >= 3 = vert (green-200/700/50) ; variantes dark: red-500 / blue-500 / green-500
- Badge Statut de ligne (calcul stockInfo, basé lui sur les flags serveur is_rupture / is_stock_bas) : 'Rupture' rouge (bg-red-100 text-red-800), 'Stock bas' orange (bg-orange-100 text-orange-800), 'OK' vert (bg-green-100 text-green-800), avec variantes dark
- Colonne Marge colorée : vert si >= 0, rouge si < 0 ; même code couleur pour la ligne 'Marge estimée : … / unité' des formulaires
- Toasts via sonner (toast.success / toast.error / toast.info) — aucun toast de succès sur le rafraîchissement ni sur la bascule 'avec couleurs'
- Toast d'erreur d'import prolongé à 10 secondes (duration: 10000) car il renvoie vers le fichier téléchargé
- Rafraîchissement temps réel : WebSocket sur les modèles product_variant et stock_movement, debounce 400 ms, refetch SILENCIEUX (pas de skeleton, pas de toast)
- Après un import, le fichier annoté (colonnes Statut + Date par ligne) est retéléchargé automatiquement pour permettre de reprendre l'import plus tard : les lignes déjà marquées seront sautées côté serveur
- Le bouton 'Modifier' de la revue d'import pré-remplit le champ de recherche avec LA PREMIÈRE référence touchée (new + updated confondues) et affiche toast.info 'Import conservé — recherche préremplie sur les références touchées, ajustez-la pour voir les autres.'
- Aperçu photo instantané via URL.createObjectURL avant upload (16x16 rem dans le détail, 24x24 dans la création)
- Placeholder photo : carré bordé bg-muted avec icône Package grisée (32px en tableau, 64px dans le détail)
- Ligne de tableau entièrement cliquable avec cursor-pointer ; les boutons d'action stoppent la propagation
- Encart d'avertissement orange (bg-orange-50, border-orange-200) dans BulkPriceDialog : 'Cette action est irréversible et modifiera directement <n> référence(s).' — affiché seulement si un sous-type est choisi, matchCount > 0 et au moins un prix saisi
- Accord au pluriel géré à la main : 'référence(s) concernée(s)' via matchCount > 1
- Barre d'outils responsive : flex-wrap, passage en colonne sous xl ; filtres en grid md:grid-cols-3 ; tableau dans un conteneur overflow-x-auto
- Hauteurs normalisées : boutons de la barre d'outils h-10, champs de filtre h-11, champs inline de création rapide h-8 text-xs
- Icônes lucide-react utilisées : Package, ShoppingCart, Truck, RefreshCw, Plus, Trash2, Pencil, Search, ArrowUpCircle, ArrowDownCircle, Tag, DollarSign, Download, Upload, Settings, Check, FolderPlus, Palette
- Aucun raccourci clavier, aucun drag & drop, aucune animation personnalisée
- Les couleurs sont référencées par leur NOM (string) dans les variantes, pas par leur id — le Select manipule l'id puis résout le nom avant l'appel API

### `/movements`

- **Fichier Next.js** : `frontend/app/(app)/movements/page.tsx`
- **Groupe d'audit** : `movements`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** AUCUN guard dans la page elle-meme. (1) Guard global: /home/garrix/Dev/Smartphone/frontend/app/(app)/layout.tsx fait `useEffect(() => { if (!djangoClient.isAuthenticated()) router.replace('/login') })` — seule protection reelle (auth, pas role). (2) Gating de navigation: dans components/layout/sidebar.tsx l'entree { label: 'Mouvements', href: '/movements', icon: TrendingUp, adminOnly: true } est filtree par `if (item.adminOnly && !isAdminOrSuperAdmin) return false` => le lien n'apparait que pour role 'admin' ou 'magasin' (GERANT). Pendant `loading` du user, tout est affiche sauf superAdminOnly (evite le flash). (3) IMPORTANT: l'URL /movements n'est PAS bloquee — un employer (PREPARATEUR/LIVREUR) qui tape l'URL voit la page entierement, seulement scopee cote serveur a son magasin. (4) Gating INTERNE via `const { user, isAdmin, isManager } = useCurrentUser()`: `isAdmin` (role==='admin') => affiche/masque le bouton 'Exporter XLSX'; `isManager` (role==='admin' || role==='magasin') => affiche/masque la colonne 'Magasin' dans les DEUX tableaux et pilote le colSpan de la ligne vide (8 si manager, 7 sinon). `user` est destructure mais jamais utilise. Aucun etat 'unauthorized' n'est rendu. (5) Scoping serveur: StockMovementViewSet (catalog/views.py:590) permission_classes=[IsAuthenticated] + queryset filtre sur product_variant__product_reference__type__category__magasin__in=get_accessible_magasins(user) — admin: tous les magasins de sa societe (owner ou co-admin), magasin: le sien, employer: celui de son affectation.

**Objectif.** Page d'historique complet des mouvements de stock (§7.4/§10 du cahier des charges): lecture seule. Elle affiche 3 KPI (total sorties / total entrees / nombre de mouvements), un bloc statistiques produits avec sa propre plage de dates (top 5 produits les plus vendus + 5 produits sans mouvement), un tableau chronologique filtrable (recherche texte + plage de dates), et un second bloc 'Mouvements par jour' qui regroupe les memes mouvements par journee avec un selecteur de jour au calendrier. Export Excel reserve a l'admin. Aucune creation/modification/suppression n'est possible depuis cette page.

**Fonctionnalites** (35)

- Titre h1 'Mouvements de stock' (text-2xl sm:text-3xl font-bold tracking-tight) + sous-titre muted 'Historique complet des mouvements de stock'
- Bouton 'Actualiser' (variant=outline, size=sm, icone RefreshCw) => appelle fetchData() en mode NON silencieux (affiche les skeletons). disabled={loading}. L'icone recoit la classe 'animate-spin' tant que loading est true
- Bouton 'Exporter XLSX' (variant=outline, size=sm, icone Download) => visible UNIQUEMENT si isAdmin (role==='admin'; un compte 'magasin' ne le voit pas). disabled={loading || filteredMovements.length === 0}
- KPI Card 1 'Total sorties' — icone ArrowDown text-red-500 — valeur '{fmt(totalExits)} unites'. totalExits = somme des Math.abs(change) pour change<0 sur filteredMovements
- KPI Card 2 'Total entrees' — icone TrendingUp text-green-500 — valeur '{fmt(totalEntries)} unites'. totalEntries = somme des change pour change>0 sur filteredMovements
- KPI Card 3 'Nb mouvements' — icone Package text-blue-500 — valeur = filteredMovements.length (nombre BRUT, sans passer par fmt(), donc sans separateur de milliers contrairement aux deux autres)
- Les 3 KPI sont calcules sur filteredMovements (= filtres du TABLEAU: recherche + startDate/endDate), PAS sur les filtres statistiques
- Carte 'Filtre statistiques produits' avec sa propre plage de dates independante (statsStartDate/statsEndDate) + description dynamique 'Periode analysee : {statsPeriodLabel}'
- Bouton 'Reinitialiser' (outline, sm) dans la carte stats => remet statsStartDate et statsEndDate a ''. disabled={!statsStartDate && !statsEndDate}
- Carte 'Produits les plus vendus' (titre text-lg vert, icone TrendingUp) — description 'Sorties de stock sur la periode ({statsPeriodLabel})' — liste des 5 premiers produits tries par quantite sortie decroissante. Chaque ligne: nom du produit (font-medium text-sm) a gauche, Badge outline vert '{qty} unites' a droite, separateur border-b (retire sur le dernier via last:border-0)
- Carte 'Produits sans mouvement' (titre text-lg orange, icone ArrowDown) — description 'Aucun mouvement sur la periode ({statsPeriodLabel})' — 5 produits du catalogue dont le `name` n'apparait dans aucun product_name des mouvements de la periode stats. Chaque ligne: nom + Badge outline orange '0 mouvement'
- Intertitre 'Filtre mouvements par date' (div avec classes contradictoires: text-sm text-muted-foreground ET text-2xl font-bold — le text-2xl/font-bold gagne visuellement)
- Tableau principal dans une Card: titre 'Historique des mouvements de stock', description '{filteredMovements.length} mouvement(s) affiche(s)'
- Tableau principal enveloppe dans un div overflow-x-auto (scroll horizontal sur mobile)
- Colonne 'Date' : formatDate(m.created_at) => toLocaleDateString('fr-FR', {year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit'}) => 'JJ/MM/AAAA HH:MM'
- Colonne 'Reference' : m.product_reference || '-' (= reference_name cote API)
- Colonne 'Produit' : ligne 1 en font-medium = m.product_name || `Produit #${m.product}` ; ligne 2 optionnelle en text-xs muted = '{brand} · {category}' recuperee via productsById[m.product], affichee seulement si brand OU category existe
- Colonne 'Variante(s)' : parse de m.variant_label. 0 entree => '-' muted ; 1 entree => Badge outline (border-purple-200 text-sky-700 bg-purple-50/50) '{nom} {+}{qty}' ; >1 entree => Badge outline violet '{n} variantes' qui ouvre un HoverCard listant chaque variante dans son propre badge
- Colonne 'Type' : Badge outline colore par getMovementTypeBadgeClass(m.movement_type || 'Mise a jour')
- Colonne 'Quantite' (alignee a droite, font-medium) : Badge outline colore par getChangeBadgeClass(change, movement_type), texte '{signe +}{change}' (le - est deja porte par la valeur negative)
- Colonne 'Fait par' : ligne 1 font-medium = m.changed_by_name || 'Systeme' ; ligne 2 text-xs muted = m.changed_by_username si present
- Colonne 'Magasin' (conditionnelle isManager) : Badge outline bleu (border-blue-200 text-blue-700 bg-blue-50/50) avec m.magasin_name || '-'
- Section 'Mouvements par jour' : h2 text-xl font-bold + un Popover calendrier a droite (flex-wrap)
- Bouton declencheur du calendrier (outline, sm, icone CalendarIcon) : libelle 'Filtrer par jour' par defaut, ou la date selectionnee formatee 'j mois AAAA' en fr-FR quand startDate === endDate et non vide
- Bouton X (variant=ghost, size=icon) affiche UNIQUEMENT quand startDate && startDate===endDate => vide startDate ET endDate (annule le filtre jour)
- Sous-composant DailyMovementsTable : une Card par journee, triees par date decroissante (b.localeCompare(a))
- Titre de chaque carte-jour : libelle 'Hier' si la date correspond a hier, sinon toLocaleDateString('fr-FR', {weekday:'long', day:'numeric', month:'long'}) avec classe capitalize + Badge outline '{n} mouvement(s)' + a droite (ml-auto, text-sm muted) le total '{somme des |change|} unites' formate fr-MG
- Tableau par jour, colonnes : Heure | Produit | Type | Qte (droite) | Note | Utilisateur | Magasin (si isManager). Egalement dans un div overflow-x-auto
- Cellule 'Heure' : toLocaleTimeString('fr-FR', {hour:'2-digit', minute:'2-digit'})
- Cellule 'Produit' du tableau par jour : m.product_name || `Produit #${m.product}` — PAS de sous-ligne marque/categorie ici (contrairement au tableau principal)
- Cellule 'Note' : m.note || '-' — la note n'est affichee QUE dans le tableau par jour, jamais dans le tableau principal
- Export Excel (XLSX via la lib 'xlsx', XLSX.utils.json_to_sheet + book_append_sheet + writeFile) : feuille nommee 'Mouvements', fichier `mouvements_${YYYY-MM-DD}.xlsx` (date du jour en UTC via toISOString)
- Colonnes du fichier Excel (dans cet ordre) : Date (formatee JJ/MM/AAAA HH:MM), Produit, Reference, Type (|| 'Mise a jour'), Quantite (valeur signee brute), 'Stock avant' (m.previous_quantity), 'Stock apres' (m.new_quantity), Note, Utilisateur (|| 'Systeme'), Email (m.changed_by_username), Magasin (m.magasin_name)
- Aucune action d'ecriture : pas de creation, edition, suppression, ni ajustement de stock depuis cette page (lecture seule totale)
- Aucun tri cliquable sur les en-tetes de colonne, aucune pagination, aucune selection de lignes, aucun menu contextuel par ligne

**Formulaires** (3)

- Formulaire 'Filtre statistiques produits' (non soumis, reactif a chaque frappe) — champs: (1) 'Date debut' Input type=date id=stats-start-date, value=statsStartDate, aucune validation, aucune borne min/max, classe w-full sm:max-w-[180px] ; (2) 'Date fin' Input type=date id=stats-end-date, value=statsEndDate, attribut min={statsStartDate || undefined} => le navigateur empeche de choisir une date de fin anterieure a la date de debut (SEULE validation de toute la page, purement native HTML) ; (3) Bouton 'Reinitialiser' disabled tant que les deux champs sont vides. Aucun message d'erreur, aucun toast, aucun appel API : le filtrage est 100% client sur le tableau statsFilteredMovements et se repercute instantanement sur les deux cartes de statistiques et sur le libelle 'Periode analysee'
- Formulaire 'Filtre mouvements par date' (non soumis, reactif) — champs: (1) Input type=date sans Label, attribut title='Date debut', value=startDate, classe w-full sm:max-w-[160px] ; (2) Input type=date sans Label, attribut title='Date fin', value=endDate — AUCUN attribut min ici (contrairement au filtre stats), donc une date de fin < date de debut est acceptee et produit simplement 0 resultat ; (3) Input texte de recherche, placeholder 'Rechercher produit, reference, vendeur...', value=searchTerm, classe w-full sm:max-w-xs, valeur debouncee 250 ms avant filtrage. Aucune validation, aucun message d'erreur, aucun bouton de soumission, aucun bouton 'effacer' sur ces trois champs (le seul reset possible est le X du selecteur de jour, qui ne vide que les deux dates)
- Selecteur de jour (Calendar dans un Popover) — mode='single', captionLayout='dropdown' (menus deroulants mois/annee), showOutsideDays par defaut. selected = new Date(startDate + 'T00:00:00') uniquement si startDate === endDate, sinon undefined. onSelect: si aucune date (deselection) => ne fait rien (early return, impossible de deselectionner par le calendrier) ; sinon convertit via toDateInputValue(d) (YYYY-MM-DD en heure LOCALE, pas UTC) et ecrit la MEME valeur dans startDate ET endDate. Cette action reecrit donc les deux champs date du filtre tableau et bascule DailyMovementsTable en mode hideToday=false

**Modales / dialogs / drawers** (3)

- Popover 'Filtrer par jour' (components/ui/popover) — PopoverContent className='w-auto p-0' align='end', contient un Calendar react-day-picker mode single avec captionLayout='dropdown' (deroulants mois + annee). Selectionner un jour ferme implicitement le popover et fixe startDate=endDate. Pas de bouton valider/annuler
- HoverCard sur la colonne 'Variante(s)' — declenche par le Badge '{n} variantes' (cursor-default) quand un mouvement porte plusieurs variantes. HoverCardContent className='w-auto p-2' affiche un flex column gap-1 avec un Badge violet par variante ('{nom} {+}{qty}'). Uniquement au survol (pas de clic, pas d'equivalent tactile)
- AUCUN Dialog / AlertDialog / Drawer / Sheet / DropdownMenu / menu contextuel / confirmation sur cette page (page en lecture seule, rien a confirmer)

**Recherche, filtres, tri, pagination** (9)

- Recherche plein texte (debouncee 250 ms via useDebouncedValue) : match insensible a la casse (toLowerCase + includes) sur product_name, product_reference, changed_by_name, changed_by_username, magasin_name, note. Un terme vide laisse tout passer
- Filtre plage de dates du tableau (startDate / endDate) : compare `m.created_at.split('T')[0]` (partie date de l'ISO, donc en UTC) au format string >= startDate et <= endDate. Comparaison lexicographique de chaines YYYY-MM-DD. Bornes inclusives des deux cotes. Une borne vide est ignoree
- Filtre plage de dates des statistiques (statsStartDate / statsEndDate) : meme logique, applique a un tableau separe statsFilteredMovements qui n'est PAS impacte par la recherche texte
- Selecteur de jour du calendrier : ecrit la meme date dans startDate et endDate => filtre le tableau principal, les 3 KPI, ET fait apparaitre la journee du jour dans 'Mouvements par jour' (hideToday devient false)
- Regroupement par jour : cle = new Date(m.created_at).toISOString().split('T')[0] (jour UTC), construit a partir de filteredMovements (donc deja filtre par recherche + dates)
- Tri : le tableau principal conserve l'ordre renvoye par l'API (ordering = ['-timestamp'] sur le modele StockMovement => du plus recent au plus ancien). AUCUN controle de tri dans l'UI. Le bloc par jour trie les cles de date en decroissant (b.localeCompare(a)) ; a l'interieur d'une journee l'ordre API est conserve
- Top 5 'les plus vendus' : tri decroissant sur la quantite sortie cumulee puis slice(0,5)
- 'Produits sans mouvement' : slice(0,5) SANS tri prealable (les 5 premiers dans l'ordre de l'API references)
- AUCUNE pagination nulle part : tous les mouvements accessibles sont charges et rendus d'un coup (l'endpoint n'est pas pagine, ReadOnlyModelViewSet sans pagination_class)

**Appels API** (5)

- GET /catalog/movements/ — via djangoClient.movements.list() (lib/django-client.ts:803). Aucun filtre passe ici (le parametre optionnel ?variant= n'est pas utilise par cette page). Retourne TOUT l'historique accessible, ordonne par -timestamp cote modele. Sert a alimenter movements[]
- GET /catalog/references/ — via djangoClient.products.list() (lib/django-client.ts:834) qui appelle catalog.references.list() puis mappe chaque reference via mapReferenceToProduct(). Sert a (a) la carte 'Produits sans mouvement' et (b) la sous-ligne marque·categorie du tableau principal
- GET /users/me/ — via useCurrentUser() (lib/auth/useCurrentUser.ts). Fournit role, commande_role, magasin_id, etc. => derive isAdmin / isManager
- WebSocket /ws/data/?token=<access> — via DataSyncProvider (lib/contexts/DataSyncContext.tsx) monte dans app/(app)/layout.tsx. La page s'y abonne pour les modeles 'stock_movement', 'product_variant' et 'order' et declenche un fetchData(true) silencieux
- (indirect) POST /auth/token/refresh/ — le djangoClient rafraichit le JWT automatiquement sur 401 avant de rejouer la requete

**Etats UI** (11)

- loading initial (loading=true) : les 3 KPI affichent chacun un Skeleton (h-8 w-20 / h-8 w-28 / h-8 w-12), les 2 cartes de statistiques un Skeleton h-24 w-full, et le tableau principal 5 Skeleton h-12 w-full empiles (space-y-2)
- loading : le bouton 'Actualiser' est disabled et son icone RefreshCw tourne (animate-spin) ; le bouton 'Exporter XLSX' est disabled
- refresh silencieux (fetchData(true), declenche par le WebSocket) : loading n'est PAS remis a true, aucun skeleton, aucun spinner — les donnees se remplacent sans clignotement
- empty tableau principal : une seule ligne, colSpan={isManager ? 8 : 7}, texte centre muted py-8 'Aucun mouvement enregistre'
- empty 'Produits les plus vendus' : 'Aucune vente enregistree sur cette periode.'
- empty 'Produits sans mouvement' : 'Tous les produits ont eu au moins un mouvement sur cette periode.'
- empty 'Mouvements par jour' : 'Aucun mouvement pour cette periode.' (text-sm muted, centre, py-8) — s'affiche aussi dans le cas normal ou le seul jour present est aujourd'hui et hideToday=true
- error : AUCUN etat d'erreur UI. Le catch de fetchData fait uniquement console.error('Error fetching data:', err) — pas de toast, pas de banniere, pas de bouton 'Reessayer'. Un echec au premier chargement laisse la page vide avec les messages 'empty' (indistinguable d'un vrai vide)
- unauthorized : AUCUN rendu dedie. Si le token est absent, le layout (app) redirige vers /login. Si l'API renvoie 401 apres echec du refresh, on retombe sur le cas error silencieux
- disabled : 'Actualiser' (loading), 'Exporter XLSX' (loading ou 0 mouvement filtre), 'Reinitialiser' des stats (aucune des deux dates renseignee)
- success : uniquement via toasts sonner sur l'export Excel (pas de toast au chargement ni au refresh)

**Details UX** (15)

- Toast (sonner) succes a l'export : `${filteredMovements.length} mouvement(s) exporte(s)`
- Toast (sonner) erreur a l'export si 0 mouvement filtre : 'Aucun mouvement a exporter pour les filtres selectionnes' (garde-fou redondant, le bouton etant deja disabled dans ce cas)
- Couleurs des badges de TYPE de mouvement (getMovementTypeBadgeClass, toutes en variant=outline + font-normal) : 'Reception fournisseur' => vert (border-green-200 text-green-700 bg-green-50/50) ; 'Retour de commande' => cyan ; 'Annulation de commande' => rouge ; 'Preparation de commande' => ambre ; 'Commande livree' => indigo ; 'Ajustement manuel' => ardoise/slate ; DEFAUT (tout autre libelle) => orange
- Couleurs du badge QUANTITE (getChangeBadgeClass) : movement_type === 'Transfert' => bg-blue-50 text-blue-700 (prioritaire sur le signe) ; change > 0 => bg-green-50 text-green-700 ; change < 0 => bg-red-50 text-red-700 ; change === 0 => bg-orange-50 text-orange-700
- Badge de variante : border-purple-200 bg-purple-50/50, avec une incoherence de couleur de texte — text-sky-700 quand il n'y a qu'UNE variante, text-purple-700 pour le badge '{n} variantes' et pour les badges dans le HoverCard
- Badge magasin : outline border-blue-200 text-blue-700 bg-blue-50/50
- Formatage des nombres : Intl.NumberFormat('fr-MG', { minimumFractionDigits: 0 }) + Math.round — separateur de milliers malgache/francais. Utilise pour totalExits et totalEntries et pour le total d'unites par journee (variante locale sans minimumFractionDigits dans DailyMovementsTable)
- Rafraichissement temps reel : useRealtimeRefresh(['stock_movement','product_variant','order'], () => fetchData(true)) — WebSocket /ws/data/, debounce 400 ms sur les evenements rapproches, refetch SILENCIEUX (pas de skeleton). Le socket se reconnecte automatiquement toutes les 3 s si la fermeture n'est pas propre (code != 1000)
- Le libelle de periode statistique affiche les dates BRUTES au format ISO YYYY-MM-DD ('du 2026-01-01 au 2026-01-31'), non localisees — contraste avec le reste de la page en fr-FR
- Le libelle du bouton calendrier, lui, est localise fr-FR en 'j mois AAAA' (ex: '10 septembre 2026')
- Le titre de carte-jour utilise la classe 'capitalize' pour majusculer le nom de jour retourne en minuscules par toLocaleDateString fr-FR
- Responsive : header flex-col sur mobile / sm:flex-row ; KPI grid-cols-1 md:grid-cols-3 ; cartes stats grid-cols-1 md:grid-cols-2 ; filtres flex-col sm:flex-row flex-wrap ; inputs w-full sur mobile avec sm:max-w-[160px]/[180px]/xs ; les deux tableaux sont dans des conteneurs overflow-x-auto
- Espacement general : conteneur p-6 space-y-6
- Aucun raccourci clavier, aucune animation hors le spin de l'icone RefreshCw et les transitions par defaut de shadcn
- La ligne 'Fait par'/'Utilisateur' retombe sur le libelle 'Systeme' quand aucun utilisateur n'est associe au mouvement (user null suite a on_delete=SET_NULL)

### `/chats`

- **Fichier Next.js** : `frontend/app/(app)/chats/page.tsx`
- **Groupe d'audit** : `chats`
- **Cible Flutter** : lib/features/chats/chat_list_screen.dart + chat_conversation_screen.dart
- **Etat** : PARTIAL

**Role et gating.** AUCUN gating par role dans la page — accessible a TOUS les roles connectes (admin / magasin(GERANT) / employer avec commande_role PREPARATEUR ou LIVREUR). Detail du gating reellement implemente: (1) `AppLayout` (/home/garrix/Dev/Smartphone/frontend/app/(app)/layout.tsx) fait `if (!djangoClient.isAuthenticated()) router.replace('/login')`; (2) la page appelle `useCurrentUser()` et n'utilise QUE `user` + `loading` — aucun `isGerant/isLivreur/isPreparateur/isAdmin` n'est consomme ici; (3) si `authLoading` -> ecran spinner 'Chargement de votre profil...'; (4) si `!currentUser` -> ecran bloquant 'Non Authentifie' (icone AlertCircle, texte 'Vous devez etre connecte pour acceder a la messagerie interne.') et RIEN d'autre n'est rendu; (5) l'entree sidebar 'Chats' (/home/garrix/Dev/Smartphone/frontend/components/layout/sidebar.tsx ligne 74-78, icone MessageCircle) n'a AUCUN flag adminOnly/superAdminOnly/hideLivreur/hidePreparateur/livreurOnly -> visible pour tout le monde. TOUT le vrai controle d'acces est cote backend: ChatUsersListView + ChatMessageHistoryView + ChatConsumer filtrent par 'meme societe' (get_company_magasins) et bloquent LIVREUR<->LIVREUR (users/permissions.py chat_blocked_between). Le sous-role Commande (PREPARATEUR/LIVREUR) n'est JAMAIS affiche dans le chat: `getRoleLabel` ne connait que admin->'Admin', magasin->'Gerant', employer->'Employe'.

**Objectif.** Messagerie interne temps reel (WebSocket) de l'entreprise: un canal 'Discussion Generale' scope societe + des conversations directes 1-a-1 avec les collaborateurs de la meme societe. Titre h1 'Messagerie Interne', sous-titre 'Collaborez en temps reel avec toute l'equipe de l'entreprise et de vos magasins.' Layout master/detail: colonne gauche (onglets + liste), colonne droite (conversation). Inclut presence en ligne, accuses de lecture, edition/suppression de message et un selecteur de produit a partager.

**Fonctionnalites** (33)

- Ecran de chargement plein ecran (min-h-[60vh]) tant que `authLoading`: Loader2 anime + texte pulsant 'Chargement de votre profil...'
- Ecran 'Non Authentifie' si currentUser null (AlertCircle destructive + h3 + paragraphe)
- En-tete de page (masque en mobile quand la conversation est ouverte, classe `hidden md:flex` si mobileShowChat): h1 'Messagerie Interne' + sous-titre
- Micro-carte utilisateur courant en haut a droite: Avatar avec initiales (getInitials = 2 premieres lettres des mots du full_name, majuscules, fallback 'U'), full_name, email tronque (max-w-[150px] truncate), Badge role colore (getRoleBadgeColor)
- Onglet 'General' (icone Hash) — canal de diffusion global de la societe
- Onglet 'Direct' (icone Users) — messagerie 1-a-1
- Changement d'onglet (handleTabChange): remet mobileShowChat a false; si 'general' -> activeRecipient=null; si 'direct' -> selectionne automatiquement filteredUsers[0] s'il y en a (donc depend du filtre de recherche courant)
- Ligne unique 'Discussion Generale' dans la liste quand onglet General: icone Hash dans un carre, titre 'Discussion Generale', sous-titre 'Canal de diffusion global'; etat actif (activeRecipient===null) = fond primary + texte primary-foreground + ombre
- Liste des collaborateurs (onglet Direct): un bouton par utilisateur avec Avatar+initiales, pastille verte 'en ligne' (h-2.5 w-2.5 bg-emerald-500, ring-2 ring-background, ring-primary si selectionne) en bas a droite de l'avatar, nom tronque (max-w-[120px]), Badge role en uppercase (scale-90, text-[8px]), ligne magasin (icone Store + shop_name) OU 'Administration' (icone Shield) si pas de shop_name, ligne de statut 'En ligne' (vert) / 'Vu <formatLastSeen>' / 'Hors ligne'
- Clic sur un collaborateur (handleSelectUser): definit activeRecipient et ouvre la vue conversation en mobile (mobileShowChat=true)
- Clic sur 'Discussion Generale' (handleSelectGeneral): activeRecipient=null + ouvre la vue conversation en mobile
- Bouton retour ArrowLeft (visible uniquement en mobile, classe md:hidden) dans le header de conversation -> setMobileShowChat(false)
- Header de conversation contextuel: mode General = icone Hash + 'Discussion Generale' + 'Tout le personnel de l'entreprise'; mode Direct = Avatar + pastille en ligne + nom + statut presence + separateur '•' + libelle de role en primary
- Indicateur de connexion WebSocket a droite du header (3 etats, voir uxDetails)
- Zone messages avec ScrollArea + auto-scroll fluide (scrollIntoView behavior:'smooth') a chaque changement de `messages` ou de `loadingHistory`
- Bulles de message: alignees a droite (items-end) si expediteur = utilisateur courant, a gauche sinon; largeur max 85% (mobile) / 75% (sm) / 65% (md)
- Groupement par expediteur: le nom de l'expediteur (+ mini-badge de role encadre) n'est affiche que si le message n'est pas de moi ET (premier message OU expediteur different du message precedent)
- Menu contextuel par message (MoreVertical) visible uniquement au survol (opacity-0 group-hover:opacity-100), uniquement sur MES messages non supprimes et non en cours d'edition
- Action 'Modifier' (icone Pencil) -> bascule la bulle en mode edition inline
- Action 'Supprimer' (icone Trash2, texte rouge) -> confirm() natif puis envoi WS
- Edition inline: Input autofocus pre-rempli, bouton valider (Check, fond primary) et bouton annuler (X); Entree = enregistrer, Echap = annuler
- Rendu 'Message supprime' pour is_deleted: bulle transparente, bordure dashed, texte italique muted, icone Trash2
- Carte produit dans la bulle si msg.product: icone Package + nom du produit + 'Ref. <reference> · <unit_price> Ar' (fond adaptatif selon que le message est le mien)
- Contenu texte du message avec whitespace-pre-wrap (retours a la ligne conserves)
- Horodatage sous chaque bulle (format HH:mm fr-FR), suffixe ' · modifie' si is_edited et non supprime
- Accuses de lecture: sur MES messages, non supprimes, UNIQUEMENT dans l'onglet Direct — CheckCheck (couleur primary) si read_at, sinon Check simple
- Suggestions rapides affichees UNIQUEMENT quand messages.length === 0: 5 puces cliquables ('Bonjour !', 'Est-ce que le stock est a jour ?', 'La commande est en cours.', 'Merci pour votre aide !', 'Je m'en occupe tout de suite.') — le clic remplit l'input (ne l'envoie pas)
- Bouton '+' (Plus) a gauche de l'input -> ouvre le Popover selecteur de produit; desactive si socket non connecte
- Champ de saisie du message + bouton Envoyer (icone Send, libelle 'Envoyer' masque en mobile: `hidden sm:inline`), animation active:scale-95
- Rafraichissement automatique de la liste des collaborateurs toutes les 20 s (fetch silencieux: pas de spinner, pas de toast en cas d'erreur)
- Heartbeat de presence: ping WebSocket toutes les 20 s tant que la socket est OPEN
- Reconnexion automatique du WebSocket 3 s apres une fermeture non provoquee par le client
- Card / CardContent sont importes mais JAMAIS utilises dans la page (import mort)

**Formulaires** (4)

- Formulaire d'envoi de message (<form onSubmit=handleSendMessage>) — CHAMPS: 1 seul Input texte 'Redigez votre message...' (state newMessage). VALIDATION: envoi bloque si `!newMessage.trim()` OU `!socketRef.current` OU `socketStatus !== 'connected'` (retour silencieux, AUCUN message d'erreur affiche). Le bouton submit est `disabled` dans les memes conditions, et l'Input lui-meme est `disabled` si socket non connectee. Pas de longueur max, pas de compteur. APRES SOUMISSION: `socket.send(JSON.stringify({content: newMessage.trim()}))` puis `setNewMessage('')` immediatement — AUCUN optimistic update: la bulle n'apparait que lorsque le serveur renvoie le message au groupe (l'expediteur est dans le groupe). Soumission par la touche Entree (comportement natif du form) ou par le bouton.
- Formulaire d'edition inline d'un message — CHAMPS: 1 Input (autoFocus, state editingContent, pre-rempli avec msg.content). VALIDATION: `saveEditMessage` ne fait rien si !editingId, si editingContent.trim() vide, si pas de socket ou socket non 'connected' (silencieux). RACCOURCIS: Entree = enregistrer, Echap = annuler. APRES SOUMISSION: envoie {action:'edit', message_id, content trimme}, puis editingId=null et editingContent='' immediatement (l'UI attend l'evenement 'message_edited' pour refleter le nouveau contenu). Boutons Check (valider) et X (annuler).
- Champ de recherche collaborateur (onglet Direct uniquement) — Input 'Rechercher un collaborateur...' avec icone Search, state searchQuery, filtrage local debounce 250 ms sur full_name / email / shop_name. Pas de validation, pas de soumission.
- Champ de recherche produit (dans le Popover '+') — Input autoFocus 'Rechercher un produit...' avec icone Search, state productSearch, filtrage local debounce 250 ms sur name / reference. Selection d'un produit = envoi WS immediat {content: newMessage.trim(), product_id} puis reset de newMessage, fermeture du popover et reset de productSearch.

**Modales / dialogs / drawers** (5)

- DropdownMenu d'actions de message (declencheur MoreVertical, align='end') — 2 items: 'Modifier' (Pencil) et 'Supprimer' (Trash2, text-red-600 focus:text-red-600). Visible uniquement au survol de la bulle et uniquement sur ses propres messages non supprimes
- confirm() natif du navigateur 'Supprimer ce message ?' avant l'envoi de l'action delete (a remplacer par un AlertDialog en Flutter)
- Popover selecteur de produit (bouton '+', align='start', side='top', largeur w-80, p-0): barre de recherche en haut + liste scrollable max-h-64; chaque ligne = icone Package dans un carre + nom + 'Ref. <reference> · <unit_price> Ar'; clic = envoi immediat du message avec le produit et fermeture
- Tabs 'General' / 'Direct' (composant Tabs shadcn, TabsList en grid 2 colonnes, uniquement TabsList/TabsTrigger — pas de TabsContent, le contenu est rendu conditionnellement)
- Aucun autre modal: pas de Dialog, pas de Drawer, pas de Sheet dans cette page. Le seul 'drawer' present a l'ecran est la sidebar globale (mobile) et le DropdownMenu de notifications de la TopBar (composants partages)

**Recherche, filtres, tri, pagination** (6)

- Recherche collaborateurs: `useDebouncedValue(searchQuery, 250)`, insensible a la casse, match sur full_name OU email OU shop_name. Rendue seulement dans l'onglet Direct mais le state persiste en revenant sur General (et influence la selection auto de filteredUsers[0])
- Recherche produits: `useDebouncedValue(productSearch, 250)`, match sur name OU reference (insensible a la casse), vide = tous les produits
- Limite d'affichage produits: `filteredProducts.slice(0, 30)` — seuls 30 resultats sont rendus, sans pagination ni 'voir plus'
- Aucun tri explicite: l'ordre des collaborateurs est celui renvoye par l'API, l'ordre des messages est chronologique (ordering=['timestamp'] cote modele)
- Aucune pagination des messages: le backend renvoie les 100 derniers, pas de scroll infini ni de 'charger plus'
- Aucun filtre par role / par magasin dans la liste de contacts

**Appels API** (17)

- GET /users/me/ — via useCurrentUser(), fournit id/email/role/full_name/commande_role... (id sert a distinguer mes messages)
- GET /users/chat/users/ — djangoClient.chat.users(); liste des collaborateurs de la meme societe (is_confirmed=True, self exclu, paires livreur/livreur exclues). Appele au montage puis toutes les 20 s en mode silencieux. Renvoie id, full_name, email, role, is_online (calcule serveur: last_seen_at < 40 s), last_seen_at, shop_name (magasin/employer uniquement)
- GET /users/chat/history/?room_name=general — djangoClient.chat.history({room_name:'general'}); historique du canal general. Le serveur remappe vers la room reelle `general_<company_id>` et ne renvoie QUE les 100 derniers messages (recipient null)
- GET /users/chat/history/?recipient_id=<id> — historique de la conversation directe (messages moi->lui ET lui->moi, 100 derniers). 403 'Permission refusee' si pas la meme societe, 403 'Deux livreurs ne peuvent pas se contacter entre eux', 404 'Destinataire introuvable'
- GET /catalog/references/ — via djangoClient.products.list() (compat mapReferenceToProduct); alimente le selecteur de produit du bouton '+'. Charge en lazy au premier ouverture du popover puis mis en cache dans le state (allProducts)
- WS <ws|wss>://<host de NEXT_PUBLIC_DJANGO_API_URL>/ws/chat/?token=<JWT access>&room=general — canal general (le serveur scope en `general_<company_id>`)
- WS <ws|wss>://<host>/ws/chat/?token=<JWT access>&recipient_id=<id> — conversation directe (le serveur calcule la room deterministe `dm_<minId>_<maxId>`)
- WS envoi {content:'...'} — nouveau message texte
- WS envoi {content:'...', product_id:<id>} — message avec produit (ATTENTION: product_id est IGNORE par le backend, voir notes)
- WS envoi {action:'edit', message_id, content} — modification (autorisee seulement pour l'auteur, message non supprime)
- WS envoi {action:'delete', message_id} — suppression logique (autorisee seulement pour l'auteur)
- WS envoi {action:'read'} — marque comme lus tous les messages non lus qui me sont adresses dans la room (DM uniquement)
- WS envoi {action:'ping'} — heartbeat toutes les 20 s; cote serveur cela ne fait que mettre a jour last_seen_at (aucun message cree car content vide)
- WS reception {type:'message', ...ChatMessage} (ou objet brut) — nouveau message a ajouter
- WS reception {type:'message_edited', id, room_name, content, is_edited, edited_at}
- WS reception {type:'message_deleted', id, room_name}
- WS reception {type:'message_read', ids:[...], read_at, room_name}

**Etats UI** (13)

- authLoading: spinner plein ecran + 'Chargement de votre profil...'
- unauthorized: bloc 'Non Authentifie' (AlertCircle destructive) — la messagerie n'est pas rendue du tout
- loadingUsers (liste collaborateurs): Loader2 + 'Chargement des collaborateurs...' centre; NON affiche lors des rafraichissements silencieux toutes les 20 s
- empty collaborateurs (apres filtre): 'Aucun collaborateur trouve'
- loadingHistory: overlay centre Loader2 (h-8) + 'Chargement des messages...'
- empty messages: icone MessageSquare dans un rond, 'Aucun message pour le moment' + 'Envoyez un message pour commencer la conversation en temps reel.' (+ affichage des suggestions rapides)
- socket 'connecting': badge ambre 'Connexion...' avec Loader2 anime
- socket 'connected': badge emeraude 'En ligne' avec pastille animee (ping)
- socket 'disconnected': badge rose 'Hors ligne' avec Circle plein
- disabled: Input message, bouton Envoyer et bouton '+' desactives des que socketStatus !== 'connected'; bouton Envoyer aussi desactive si le message est vide/blanc
- loadingProducts (popover): Loader2 centre
- empty produits: 'Aucun produit trouve'
- error: gere UNIQUEMENT par des toasts (aucun etat d'erreur inline/retry). Pas d'etat d'erreur pour un WebSocket qui ne parvient jamais a se connecter, au-dela du badge 'Hors ligne'

**Details UX** (18)

- Couleurs de badge par role (getRoleBadgeColor): admin = rose (bg-rose-500/10, text-rose-700 / dark:text-rose-400, border-rose-500/20), magasin = bleu (blue-500), employer = emeraude (emerald-500), defaut = muted
- Libelles de role (getRoleLabel): admin -> 'Admin', magasin -> 'Gerant', employer -> 'Employe' (le sous-role Preparateur/Livreur n'apparait jamais)
- Badge socket 'En ligne': double span emeraude avec `animate-ping` (halo pulsant) — effet visuel a reproduire
- Pastille de presence sur avatar: 10 px, emerald-500, anneau 2 px (ring-background, ou ring-primary quand la ligne est selectionnee)
- formatLastSeen: < 1 min -> 'a l'instant'; < 60 min -> 'il y a N min' (Math.floor); sinon 'a HH:mm' (fr-FR). Affiche prefixe par 'Vu ' -> ex. 'Vu il y a 12 min'
- formatTime: `toLocaleTimeString('fr-FR', {hour:'2-digit', minute:'2-digit'})` -> HH:mm; try/catch renvoie '' si date invalide
- getInitials: split sur les espaces, 1ere lettre de chaque mot, 2 max, upper; 'U' si nom vide
- Prix produit affiche suffixe par ' Ar' (ariary malgache), sans formatage de milliers
- Toasts (sonner) — uniquement des erreurs: 'Impossible de charger la liste des collaborateurs.' (non silencieux uniquement), 'Erreur lors du chargement de l'historique.', 'Impossible de charger les produits.'. AUCUN toast de succes (envoi, edition, suppression sont silencieux)
- Temps reel: 3 canaux WS coexistent dans l'app — /ws/chat/ (cette page), /ws/notifications/ (TopBar + page notifications) et /ws/data/ (DataSyncProvider). Un nouveau message chat declenche aussi une Notification cote backend -> toast 'Type : Chat' via la cloche de la TopBar
- Selection de conversation: fond `bg-primary` + `text-primary-foreground` + `shadow-primary/20`; survol = `hover:bg-accent/60`
- Coins: bulles rounded-2xl avec coin 'queue' aplati (rounded-tr-sm pour mes messages, rounded-tl-sm pour les autres); conteneurs rounded-2xl/3xl; boutons rounded-2xl
- Hauteur de page fixe: `h-[calc(100dvh-4rem)]` en mobile, `h-[calc(100vh-100px)]` a partir de sm; la zone messages est la seule a scroller (`flex-1 min-h-0`)
- Mobile: master/detail par bascule de classes (`mobileShowChat`) — la liste occupe tout l'ecran, l'ouverture d'une conversation la masque; sur md+ les deux colonnes sont visibles (sidebar w-80)
- `select-none` sur la sidebar de conversation, le header, la barre de saisie et les horodatages (empeche la selection de texte)
- Classe `safe-area-pb` sur la barre de saisie (encoche/barre gestuelle iOS)
- Les messages recus en double sont ignores par un garde `prev.some(m => m.id === id)`
- Le bouton d'actions du message est `order-first` (a gauche de la bulle) pour mes messages

### `/users (libellé sidebar : "Super Admin", titre page : "Super Administration")`

- **Fichier Next.js** : `frontend/app/(app)/users/page.tsx`
- **Groupe d'audit** : `users`
- **Cible Flutter** : lib/features/users/users_screen.dart
- **Etat** : PARTIAL

**Role et gating.** GATING EN 3 COUCHES. (1) Layout /home/garrix/Dev/Smartphone/frontend/app/(app)/layout.tsx : useEffect -> si !djangoClient.isAuthenticated() alors router.replace('/login'). (2) Sidebar /home/garrix/Dev/Smartphone/frontend/components/layout/sidebar.tsx ligne ~125 : l'entrée { label:'Super Admin', href:'/users', icon: Shield, superAdminOnly: true } est filtrée par `if (item.superAdminOnly && !isSuperAdmin) return false` — isSuperAdmin === (role === 'admin'). Donc SEUL un admin voit le lien dans le menu ; pendant `loading` du user, les items superAdminOnly sont masqués (`if (loading) return !item.superAdminOnly`). (3) Dans la page elle-même : `const { user: currentUser, loading: currentUserLoading, isAdmin, isManager, isCompanyOwner } = useCurrentUser();` puis garde `if (!isManager && !currentUserLoading) return <écran Accès Refusé>`. isManager = (role === 'admin' || role === 'magasin'). => un GÉRANT (role 'magasin') peut donc accéder à la page en tapant l'URL même s'il n'a pas le lien dans le menu. Un employer (PREPARATEUR / LIVREUR / commercial) reçoit l'écran Accès Refusé. Sous-gating interne : isAdmin (role==='admin') débloque l'onglet 'Réinit. mots de passe', l'option de rôle 'Gérant de magasin' à la création, et les boutons Modifier rôle / Supprimer sur les lignes non-admin ; isCompanyOwner (role==='admin' && user.is_company_owner === true, c-à-d le FONDATEUR ayant un AdminProfile, pas un co-admin) débloque l'option 'Administrateur' à la création, l'option 'Administrateur' dans le dialog de changement de rôle, et les boutons Modifier rôle / Supprimer sur une ligne dont role==='admin'. Règle exacte par ligne : `(u.role === 'admin' ? isCompanyOwner : isAdmin) && currentUser && u.id !== currentUser.id`. Conséquence : un gérant (magasin) ne voit AUCUN bouton Modifier rôle / Supprimer dans l'onglet Actifs (isAdmin false), mais voit quand même les boutons Approuver / Rejeter de l'onglet En attente (aucune condition de rôle dessus).

**Objectif.** Console d'administration des comptes de la société : lister tous les utilisateurs actifs (admins, gérants, employés) groupés/annotés par magasin avec leur état de connexion en temps quasi réel, approuver ou rejeter les inscriptions en attente, créer de nouveaux comptes (employé / gérant / administrateur), changer le rôle d'un compte, supprimer un compte avec re-authentification par mot de passe, et (admin uniquement) traiter les demandes de réinitialisation de mot de passe remontées par les gérants et employés.

**Fonctionnalites** (27)

- En-tête : titre H1 'Super Administration' (texte contenant un saut de ligne dans le JSX) + sous-titre 'Gérez les accès de votre équipe.'
- Header responsive : colonne sur mobile (flex-col), ligne avec justify-between sur >=md (md:flex-row)
- Champ de recherche global (Input placeholder 'Rechercher...', className max-w-xs) placé dans le header, à gauche du bouton Ajouter
- Bouton 'Ajouter' (icône Plus, variant par défaut) affiché seulement si isManager — donc visible aussi pour un gérant ; c'est le DialogTrigger du dialog 'Créer un utilisateur'
- Système d'onglets (Tabs, defaultValue='actifs', non contrôlé — l'onglet actif n'est pas persisté)
- Onglet 1 'Utilisateurs actifs' avec Badge variant='secondary' affichant allUsers.length, rendu uniquement si allUsers.length > 0
- Onglet 2 'En attente' avec Badge orange (bg-orange-100 text-orange-800) affichant pendingUsers.length, rendu uniquement si pendingUsers.length > 0
- Onglet 3 'Réinit. mots de passe' rendu UNIQUEMENT si isAdmin, avec Badge orange comptant passwordRequests.filter(r => r.status === 'pending').length, rendu uniquement si ce compte > 0 (attention : ce compteur porte sur la liste déjà filtrée par le Select, donc il tombe à 0 si le filtre est sur 'approved'/'rejected')
- Onglet Actifs : Card titre 'Équipe active', description 'Utilisateurs confirmés groupés par magasin', tableau dans un conteneur overflow-x-auto
- Onglet En attente : Card titre "En attente d'approbation", description 'Comptes créés mais non encore approuvés', tableau dans overflow-x-auto
- Onglet Réinit. : Card avec en-tête en flex-row justify-between, titre 'Réinitialisations de mot de passe' précédé de l'icône KeyRound (h-5 w-5), description 'Demandes de vos gérants de magasin et commerciaux ayant oublié leur mot de passe'
- Onglet Réinit. : Select de filtre de statut (largeur w-40) dans l'en-tête de la Card
- Onglet Réinit. : bouton de rafraîchissement manuel (variant outline, size sm, icône RefreshCw seule, sans libellé), disabled pendant passwordRequestsLoading, l'icône tourne (animate-spin) pendant le chargement, onClick = fetchPasswordRequests
- Onglet Réinit. : rendu en LISTE DE CARTES (div rounded-lg border p-4), pas en tableau ; empilement vertical space-y-3 ; chaque carte est flex-col sur mobile et flex-row sm:items-center justify-between sur >=sm
- Action 'Approuver' sur une inscription en attente (icône Check, variant outline, texte vert : text-green-600 hover:text-green-700 hover:bg-green-50)
- Action 'Rejeter' sur une inscription en attente (icône X, variant outline, texte rouge : text-red-600 hover:text-red-700 hover:bg-red-50) — passe par un window.confirm() natif avant l'appel
- Action 'Modifier rôle' par ligne (variant outline, size sm, bleu : text-blue-600 hover:text-blue-700 hover:bg-blue-50) — pré-remplit le Select avec le rôle actuel et ouvre le dialog
- Action 'Supprimer' par ligne (variant ghost, size sm, rouge : text-red-600 hover:text-red-700 hover:bg-red-50) — ouvre le ConfirmDeleteDialog avec re-saisie du mot de passe
- Action 'Approuver' sur une demande de réinit. de mot de passe (size sm, variant outline, text-green-700 border-green-200, icône Check)
- Action 'Rejeter' sur une demande de réinit. de mot de passe (size sm, variant outline, text-red-700 border-red-200, icône X)
- Rafraîchissement automatique du calcul du temps relatif : setInterval toutes les 10 minutes (10*60*1000 ms) met à jour un state `now` ; nettoyage par clearInterval au démontage. Ça ne refait AUCUN appel réseau — seuls les libellés 'il y a X minutes' sont recalculés.
- Aucun tri de colonne, aucune pagination, aucun export, aucun raccourci clavier, aucune sélection multiple, aucun menu contextuel/dropdown d'actions (les actions sont des boutons inline)
- Aucun bouton de rafraîchissement manuel pour les onglets Actifs / En attente (seul l'onglet Réinit. en a un)
- Rechargement complet de la liste (fetchUsers) après chaque approbation, rejet, suppression et changement de rôle
- COLONNES du tableau 'Utilisateurs actifs' (7 en-têtes) : 1) 'Utilisateur' = avatar (img rond h-8 w-8 object-cover border si u.photo, sinon pastille bg-muted avec la 1re lettre en MAJUSCULE de full_name || email || '?') + nom en font-medium (fallback 'Sans nom') + email en text-xs muted + 3e ligne text-xs muted avec [phone, adresse].filter(Boolean).join(' · ') affichée seulement si phone OU adresse existe. 2) 'Rôle' = icône selon le rôle + libellé traduit. 3) 'Magasin' = u.shop_name || '-' (text-sm muted). 4) 'Poste' = u.position || '-' (text-sm muted). 5) 'Connexion / Déconnexion' (text-xs muted) = si last_login_at : deux lignes 'Connexion : dd MMM yyyy HH:mm' (locale fr) et 'Déconnexion : ' + soit 'En ligne' si actuellement en ligne, soit la date formatée de last_logout_at ; sinon '-'. 6) 'Actif' = pastille + libellé relatif (voir uxDetails). 7) 'Actions' (aligné à droite) = boutons conditionnels.
- COLONNES du tableau 'En attente' (5 en-têtes) : 1) 'Utilisateur' (même bloc avatar/nom/email/phone·adresse que l'onglet Actifs). 2) 'Rôle' (icône + libellé). 3) 'Magasin / Poste' = u.shop_name || u.position || '-'. 4) 'Date inscription' = format(created_at, 'dd MMM yyyy', locale fr) sinon '-'. 5) 'Actions' à droite = Approuver / Rejeter.
- CONTENU d'une carte de demande de réinitialisation : icône KeyRound violette (text-violet-500) ; ligne 1 = `{r.user_name} — {r.user_email}` (l'email en text-blue-700) ; ligne 2 = getRoleLabel(r.user_role) + (r.magasin_name ? ' · Magasin : ' + r.magasin_name : '') ; ligne 3 = new Date(r.created_at).toLocaleString('fr-FR') ; à droite un Badge de statut coloré puis, seulement si status === 'pending', les boutons Approuver / Rejeter

**Formulaires** (4)

- FORMULAIRE 'Créer un utilisateur' (dans le Dialog déclenché par le bouton Ajouter ; DialogContent sm:max-w-lg ; titre 'Créer un utilisateur', description "Le compte sera créé et en attente d'approbation."). CHAMPS DANS L'ORDRE : (1) 'Nom complet *' — Input texte, placeholder 'Jean Dupont', attribut required (validation HTML native), state newUser.full_name. (2) 'Email *' — Input type=email, placeholder 'jean@exemple.com', required (validation de format par le navigateur), state newUser.email ; cette valeur est envoyée À LA FOIS comme email ET comme username. (3) 'Mot de passe *' — Input type=password, placeholder '••••••••', minLength=6 et required ; contrôle JS supplémentaire dans handleAddUser : if (password.length < 6) -> toast.error('Le mot de passe doit contenir au moins 6 caractères') et return (aucun appel réseau). (4) 'Rôle *' — Select (valeur par défaut 'employer') avec options : 'Employé / Commercial' (value 'employer', toujours présente), 'Gérant de magasin' (value 'magasin', rendue seulement si isAdmin), 'Administrateur' (value 'admin', rendue seulement si isCompanyOwner). (5) CONDITIONNEL si role==='employer' : 'Poste / Fonction' — Input texte, placeholder 'Ex: Vendeur', NON requis, state newUser.position. (6) CONDITIONNEL si role==='magasin' : 'Nom du magasin *' — Input texte, placeholder 'Ex: Boutique Ivandry', required, state newUser.shop_name. Le state contient aussi un champ company_name jamais exposé dans l'UI ni envoyé. BOUTON DE SOUMISSION : pleine largeur (w-full), libellé "Créer l'utilisateur", disabled pendant isSubmitting et remplacé par un spinner Loader2 animate-spin + texte 'Création...'. COMPORTEMENT APRÈS SOUMISSION RÉUSSIE : toast.info("Utilisateur créé en attente d'approbation") si role !== 'admin', sinon toast.success('Administrateur créé avec succès') ; si role==='admin' et createdUser.id existe, insertion optimiste en tête de allUsers d'un objet { id, full_name, email, role:'admin', shop_name: currentUser?.company_name || 'Société', magasin_id: null, position: '', is_confirmed: true } ; fermeture du dialog (setIsDialogOpen(false)) ; réinitialisation complète du state newUser aux valeurs par défaut (role revient à 'employer') ; puis await fetchUsers() qui recharge tout. ERREURS : le code tente de lire err?.response?.data.username / .email et affiche "Un utilisateur avec ce nom d'utilisateur ou cet email existe déjà." si l'un contient 'already exists' ; sinon toast.error(err?.message || 'Une erreur est survenue pendant la création du compte.'). Le dialog reste ouvert et les champs conservent leur valeur en cas d'erreur. Aucune erreur inline sous les champs — tout passe par des toasts.
- FORMULAIRE 'Modifier le rôle' (Dialog contrôlé par editRoleDialogOpen, DialogContent sm:max-w-md ; titre 'Modifier le rôle' ; description dynamique 'Changer le rôle de ' + editingUserRole?.full_name || editingUserRole?.email). CHAMP UNIQUE : 'Nouveau rôle' — Select pré-rempli avec le rôle actuel de la cible, options dans cet ordre : 'Administrateur' (value 'admin', rendue seulement si isCompanyOwner), 'Gérant de magasin' (value 'magasin'), 'Employé / Commercial' (value 'employer'). BOUTONS : 'Annuler' (variant outline, ferme simplement le dialog sans reset de editingUserRole ni newRoleValue) et 'Enregistrer' (disabled si !newRoleValue OU newRoleValue === rôle actuel OU editRoleLoading ; affiche un Loader2 animate-spin en préfixe pendant le chargement). APRÈS SUCCÈS : toast.success(`Rôle mis à jour : ${newRoleValue}` — attention, la VALEUR BRUTE anglaise ('magasin', 'employer', 'admin') est affichée, pas le libellé traduit), fermeture du dialog, editingUserRole remis à null, newRoleValue vidé, puis fetchUsers(). EN CAS D'ERREUR : toast.error(err.message), le dialog RESTE OUVERT.
- FORMULAIRE de confirmation de suppression (composant partagé ConfirmDeleteDialog ; DialogContent sm:max-w-md ; titre 'Supprimer cet utilisateur' en rouge avec icône ShieldAlert ; description riche : 'Vous êtes sur le point de supprimer définitivement <nom en font-medium text-foreground>. Cette action est irréversible. Entrez votre mot de passe pour confirmer.'). CHAMP UNIQUE : 'Votre mot de passe' — Input id='confirm-delete-password', type=password, autoComplete='current-password', placeholder '••••••••', autoFocus, required, disabled pendant loading. VALIDATION : si vide à la soumission -> message inline 'Mot de passe requis.' (p text-sm text-red-600 sous le champ) ; l'erreur est effacée à chaque frappe. BOUTONS : 'Annuler' (variant outline, disabled pendant loading) et 'Supprimer définitivement' (variant destructive, disabled si loading OU si le champ est vide ; pendant le chargement : Loader2 animate-spin + 'Suppression...'). Le dialog refuse de se fermer tant que loading est true (handleOpenChange fait un early-return). APRÈS SUCCÈS : le mot de passe est vidé, le dialog se ferme, puis côté page toast.success('Utilisateur supprimé') et fetchUsers(). EN CAS D'ERREUR : le message de l'exception est affiché INLINE dans le dialog (err?.message || 'Erreur lors de la suppression.') et le dialog reste ouvert — c'est le seul formulaire de la page avec une erreur inline plutôt qu'un toast.
- CONFIRMATION NATIVE de rejet : handleReject appelle window.confirm('Rejeter et supprimer cet utilisateur ?') ; si l'utilisateur annule, rien ne se passe. Ce n'est pas un composant React — à porter en AlertDialog Flutter.

**Modales / dialogs / drawers** (8)

- Dialog 'Créer un utilisateur' — modal shadcn contrôlé par isDialogOpen, ouvert par un DialogTrigger asChild sur le bouton 'Ajouter' ; largeur sm:max-w-lg ; contient le formulaire de création. Fermeture par la croix, l'overlay/Esc, ou automatiquement après création réussie.
- Dialog 'Modifier le rôle' — modal contrôlé par editRoleDialogOpen, rendu à la racine de la page (hors des Tabs) ; largeur sm:max-w-md ; ouvert par le bouton 'Modifier rôle' d'une ligne, qui mémorise editingUserRole et pré-remplit newRoleValue avec le rôle courant.
- ConfirmDeleteDialog (composant partagé) — modal de suppression avec re-authentification par mot de passe ; ouvert dès que deleteTarget !== null ; onOpenChange(false) remet deleteTarget à null ; largeur sm:max-w-md.
- window.confirm() natif — 'Rejeter et supprimer cet utilisateur ?' avant l'appel de rejet d'une inscription en attente.
- Dropdown Select 'Rôle *' (création) — popover shadcn avec 1 à 3 options selon isAdmin / isCompanyOwner.
- Dropdown Select 'Nouveau rôle' (modification) — popover shadcn avec 2 ou 3 options selon isCompanyOwner.
- Dropdown Select de filtre de statut des demandes de réinitialisation (w-40) — 4 options.
- AUCUN menu contextuel, AUCUN drawer, AUCUN popover d'information/tooltip sur cette page.

**Recherche, filtres, tri, pagination** (7)

- Recherche unique en haut de page (state searchTerm) appliquée SIMULTANÉMENT aux onglets 'Utilisateurs actifs' et 'En attente' ; elle n'affecte PAS l'onglet 'Réinit. mots de passe'.
- La recherche est debouncée via useDebouncedValue(searchTerm) avec un délai par défaut de 250 ms : la saisie reste instantanée, le filtrage est différé.
- Prédicat de filtrage identique pour les deux listes : (u.full_name || '').toLowerCase().includes(terme.toLowerCase()) || (u.email || '').toLowerCase().includes(terme.toLowerCase()). Donc recherche uniquement sur NOM et EMAIL — pas sur le magasin, le poste, le téléphone ni l'adresse. Insensible à la casse, mais SENSIBLE aux accents (pas de normalisation NFD).
- Filtrage côté client uniquement (aucun paramètre envoyé à l'API).
- Filtre de statut de l'onglet 'Réinit. mots de passe' : Select à 4 options — 'En attente' (value 'pending', valeur par défaut), 'Approuvées' (value 'approved'), 'Rejetées' (value 'rejected'), 'Toutes' (value 'all'). Ce filtre est SERVEUR : il déclenche un nouvel appel GET /users/password-reset-requests/?status=... via un useEffect dépendant de passwordRequestsFilter ; pour 'all' le paramètre status est omis.
- Aucun tri (ni par défaut explicite, ni cliquable) : l'ordre est celui renvoyé par l'API. Pour l'onglet Actifs l'ordre suit la construction : pour chaque magasin, d'abord le manager, puis les employers, puis les company_users, avec déduplication par id (le premier gagne).
- Aucune pagination, aucun scroll infini, aucune limite de nombre de lignes — les tableaux affichent l'intégralité des résultats, avec seulement un défilement horizontal (overflow-x-auto) sur petits écrans.

**Appels API** (13)

- GET /users/me/ — (via useCurrentUser) charge l'utilisateur courant : id, email, role, full_name, is_confirmed, phone, adresse, photo, company_name, logo, shop_name, shop_logo, magasin_id, position, commande_role, is_company_owner. Sert à tout le gating de la page.
- GET /users/magasins/users/ — liste des magasins accessibles avec, pour chacun, magasin_id, shop_name, shop_logo, manager (l'admin propriétaire du magasin), employers[] (id, full_name, email, phone, adresse, photo, is_confirmed, position, role, commande_role, last_login_at, last_logout_at) et company_users[] (tous les comptes de la société, mêmes champs + shop_name/magasin_id). C'est la source de l'onglet 'Utilisateurs actifs'. Backend : users/views.py::UsersByMagasinView (permission IsAuthenticated ; admin voit tous ses magasins, magasin le sien, employer le sien).
- GET /users/pending/ — comptes non confirmés (is_confirmed=False) de la société/du magasin : id, full_name, email, role, created_at, + position et shop_name pour les employers, shop_name pour les magasins. Alimente l'onglet 'En attente'. Appelé avec .catch(() => []) : une erreur renvoie une liste vide SANS toast. Backend : PendingUsersView (403 si role hors admin/magasin).
- PUT /users/approve/<user_id>/ — passe is_confirmed à True. Backend ApproveUserView : 403 si le rôle courant n'est pas admin/magasin, 403 si la cible n'appartient pas à l'entreprise (admin) ou au magasin (gérant, restreint aux employers), 404 si introuvable.
- POST /users/reject/<user_id>/ — REJETTE ET SUPPRIME définitivement le compte (user.delete()). Mêmes contrôles d'appartenance que approve. Backend RejectUserView.
- PUT /users/role/<user_id>/ body { role: 'admin' | 'magasin' | 'employer' } — change le rôle. Backend RoleManagementView (permission IsAuthenticated + IsAdmin) : 400 rôle invalide, 400 si on cible son propre compte, 403 si (cible admin OU nouveau rôle admin) et l'appelant n'est pas le fondateur, 403 si la cible est le fondateur, 403 si la cible n'appartient pas à l'entreprise, 404 si introuvable.
- DELETE /users/delete/<user_id>/ body { password } — supprime un compte après vérification du mot de passe de l'APPELANT. Backend DeleteUserView : 400 'Mot de passe requis pour confirmer la suppression.', 400 'Mot de passe incorrect.', 400 'Vous ne pouvez pas vous supprimer vous-même', 403 si le gérant vise un non-employé de son magasin, 403 'Seul le fondateur de la société peut retirer un administrateur.', 403 si la cible est le fondateur, 404 si introuvable.
- POST /users/register/ body { email, username: email, password, role, full_name, + position & admin_email (role employer) ou shop_name & admin_email (role magasin) } — création d'un compte gérant ou employé. admin_email est TOUJOURS l'email de l'utilisateur courant. Backend RegisterSerializer : pour role='magasin', 400 { admin_email: 'Administrateur introuvable avec cet email.' } si l'email fourni n'est pas celui d'un admin ; auto-confirmé (is_confirmed=True) si c'est justement l'admin authentifié qui crée, sinon en attente. Pour role='employer', l'admin_email est cherché d'abord parmi les admins, sinon parmi les gérants (role='magasin') pour rattacher le magasin.
- POST /users/add-admin/ body { email, username: email, password, role: 'admin', full_name } — crée un co-administrateur, réponse { message, id }. Backend AddAdminView (permission IsAuthenticated + IsCompanyOwner) : supprime l'AdminProfile créé par le serializer (le co-admin n'est pas une nouvelle société) puis l'ajoute au M2M `admins` de tous les magasins de l'appelant.
- GET /users/password-reset-requests/?status=<pending|approved|rejected> (paramètre omis quand le filtre vaut 'all') — demandes de réinitialisation adressées à l'admin courant : id, status, user_name, user_email, user_role, magasin_name, created_at, resolved_at. Backend EmployeePasswordResetListView (IsAuthenticated + IsAdmin, filtrées sur admin=request.user).
- PATCH /users/password-reset-requests/<request_id>/ body { action: 'approve' | 'reject' } — résout une demande. Backend EmployeePasswordResetResolveView : 404 'Demande introuvable', 400 'Action invalide.', 400 'Cette demande a déjà été traitée.' si status !== 'pending' ; positionne status, resolved_by et resolved_at.
- POST /users/refresh/ — rafraîchissement transparent du token JWT sur toute réponse 401 (implémenté dans django-client, rejoue la requête une fois ; si le refresh échoue, lève Error('Authentication failed') ou le detail renvoyé).
- Base URL : process.env.NEXT_PUBLIC_DJANGO_API_URL, défaut 'http://127.0.0.1:8010/api'. Auth par header Authorization: Bearer <access>.

**Etats UI** (14)

- LOADING onglet Actifs : `loading` initial à true ; rendu de 4 Skeleton h-10 w-full empilés (space-y-2) à la place du tableau.
- LOADING onglet En attente : mêmes conditions (partage le state `loading`), 3 Skeleton h-10 w-full.
- LOADING onglet Réinit. : state séparé passwordRequestsLoading (initial true) ; 3 Skeleton h-16 w-full ; le bouton Refresh est disabled et son icône tourne.
- EMPTY onglet Actifs : une TableRow avec une cellule colSpan={8} centrée, py-8, text-muted-foreground, texte 'Aucun utilisateur trouvé' (colSpan=8 alors que le tableau n'a que 7 colonnes).
- EMPTY onglet En attente : bloc centré py-12 muted avec deux lignes — 'Aucune demande en attente' (text-lg font-medium) et 'Tous les utilisateurs ont été traités.' (text-sm mt-1). Ce bloc REMPLACE le tableau entier (pas de header de colonnes affiché).
- EMPTY onglet Réinit. : bloc centré py-12 muted avec le texte dynamique 'Aucune demande ' + libellé du filtre en minuscules ('en attente' / 'approuvée' / 'rejetée'), ou juste 'Aucune demande ' quand le filtre vaut 'all'.
- UNAUTHORIZED : si !isManager && !currentUserLoading, la page entière est remplacée par une Card centrée (py-20) avec l'icône ShieldAlert h-12 w-12 text-red-500, le titre 'Accès Refusé' (text-xl font-bold) et le texte muted "Vous n'avez pas les permissions pour gérer les utilisateurs." — aucun bouton de retour.
- ERROR de chargement de la liste des utilisateurs : toast.error('Erreur de chargement: ' + err.message) ; les tableaux restent avec leurs données précédentes (ou vides) — pas d'état d'erreur dédié ni de bouton 'Réessayer'.
- ERROR de chargement des demandes de réinit. : toast.error('Erreur lors du chargement des demandes: ' + err.message).
- SILENT FAILURE : GET /users/pending/ est appelé avec .catch(() => []) — un échec produit une liste vide sans le moindre message, l'onglet affiche alors l'état vide 'Aucune demande en attente'.
- DISABLED : bouton 'Créer l'utilisateur' pendant isSubmitting ; bouton 'Enregistrer' du dialog rôle si aucun rôle, rôle inchangé, ou chargement ; boutons Approuver/Rejeter d'une demande de réinit. quand resolvingRequestId === r.id (verrou par ligne — les autres lignes restent cliquables) ; bouton Refresh pendant passwordRequestsLoading ; boutons Annuler / Supprimer définitivement du ConfirmDeleteDialog pendant la suppression.
- SUCCESS : uniquement des toasts (sonner) — aucune bannière ni état de succès persistant. La donnée est systématiquement rechargée après l'action.
- PAS d'état 'saving' visuel sur les boutons Approuver / Rejeter de l'onglet En attente : ils ne sont ni désactivés ni mis en spinner pendant l'appel (double-clic possible).
- PENDANT currentUserLoading : la page rend l'UI normale (pas d'écran Accès Refusé prématuré, la garde exige !currentUserLoading), avec les tableaux en skeleton puisque fetchUsers n'est déclenché qu'une fois currentUserLoading passé à false.

**Details UX** (13)

- Toasts via la librairie `sonner` (import { toast } from 'sonner') : toast.success, toast.error et toast.info. Messages exacts : 'Utilisateur approuvé', 'Utilisateur rejeté', 'Utilisateur supprimé', 'Rôle mis à jour : <valeur brute du rôle>', 'Demande approuvée', 'Demande rejetée', "Utilisateur créé en attente d'approbation" (info), 'Administrateur créé avec succès', 'Le mot de passe doit contenir au moins 6 caractères', "Un utilisateur avec ce nom d'utilisateur ou cet email existe déjà.", 'Une erreur est survenue pendant la création du compte.', 'Erreur de chargement: ...', 'Erreur lors du chargement des demandes: ...', 'Erreur lors du traitement'.
- Icônes de rôle (getRoleIcon) : admin -> Shield h-4 w-4 text-purple-500 ; magasin -> Briefcase h-4 w-4 text-blue-500 ; tout le reste (employer) -> Users h-4 w-4 text-green-500.
- Libellés de rôle (getRoleLabel) : admin -> 'Administrateur', magasin -> 'Gérant', employer -> 'Employé' ; toute autre valeur est affichée telle quelle (fallback ?? role). NB : dans les Select on parle de 'Gérant de magasin' et 'Employé / Commercial' alors que le tableau affiche 'Gérant' et 'Employé' — vocabulaire volontairement différent entre listes et formulaires.
- Indicateur d'activité (colonne 'Actif') : si en ligne -> texte text-green-700 avec une pastille pleine h-1.5 w-1.5 rounded-full bg-green-500 et le texte 'Actif ' + temps relatif depuis last_login_at ; si hors ligne -> texte muted avec pastille bg-slate-300 et 'Hors ligne ' + temps relatif depuis last_logout_at ; si jamais de last_login_at -> 'Jamais connecté' en text-xs muted.
- Format du temps relatif (formatRelativeTime, calculé contre le state `now` rafraîchi toutes les 10 min) : < 1 min -> "à l'instant" ; < 60 min -> 'il y a N minute(s)' ; < 24 h -> 'il y a N heure(s)' ; sinon 'il y a N jour(s)'. Pluriel géré ('s' si > 1). Les écarts négatifs sont clampés à 0 via Math.max(0, ...). Les heures/jours sont ARRONDIS (Math.round), pas tronqués — 90 min affichent donc 'il y a 2 heures'.
- Format des dates absolues : date-fns `format` avec locale fr — 'dd MMM yyyy HH:mm' pour les connexions/déconnexions, 'dd MMM yyyy' pour la date d'inscription. Les demandes de réinitialisation utilisent en revanche new Date(...).toLocaleString('fr-FR') (format natif jj/mm/aaaa hh:mm:ss) — incohérence de format à reproduire ou à harmoniser.
- Badges de statut des demandes de réinitialisation (Badge variant='outline' + classe conditionnelle) : approved -> bg-green-50 text-green-800 border-green-200 ; rejected -> bg-red-50 text-red-800 border-red-200 ; défaut/pending -> bg-orange-50 text-orange-800 border-orange-200. Libellés : 'En attente', 'Approuvée', 'Rejetée'.
- Badges de compteur d'onglets : onglet Actifs -> Badge variant='secondary' (gris) ; onglets En attente et Réinit. -> Badge orange bg-orange-100 text-orange-800. Tous en ml-2.
- Avatars : image ronde si photo (URL absolue construite par le backend via build_absolute_uri), sinon monogramme sur fond muted avec bordure ; classes shrink-0 pour ne pas se déformer.
- Séparateur ' · ' (point médian) entre téléphone et adresse dans la cellule utilisateur, et entre le rôle et 'Magasin : X' dans les demandes de réinitialisation.
- Pas de temps réel WebSocket sur cette page : le seul rafraîchissement automatique est le tick de 10 minutes qui ne fait que recalculer les libellés relatifs à partir des données déjà chargées. Les statuts en ligne/hors ligne ne se mettent donc PAS à jour tout seuls sans rechargement.
- Espacement général : conteneur p-6 space-y-6 ; tableaux enveloppés dans overflow-x-auto pour le défilement horizontal mobile ; l'écran Accès Refusé utilise juste p-6.
- Les colonnes d'actions sont alignées à droite (text-right + flex justify-end gap-2).

### `/caisse`

- **Fichier Next.js** : `frontend/app/(app)/caisse/page.tsx`
- **Groupe d'audit** : `caisse-bilan`
- **Cible Flutter** : lib/features/caisse/caisse_screen.dart
- **Etat** : PARTIAL

**Role et gating.** GERANT uniquement en pratique (admin = role 'admin', gerant magasin = role 'magasin'). AUCUN guard explicite dans la page: elle ne rend jamais d'ecran 'Acces refuse'. Le gating reel est en 3 couches: (1) app/(app)/layout.tsx redirige vers /login si !djangoClient.isAuthenticated(); (2) components/layout/sidebar.tsx cache l'entree 'Caisse' (icone Wallet, href /caisse) via les flags hidePreparateur:true et hideLivreur:true -> invisible si isPreparateur ou isLivreur (pendant loading la sidebar affiche tout sauf superAdminOnly); (3) le backend: tous les endpoints /users/caisse/sessions/, /users/caisse/movements/ et /users/caisse/summary/ sont [IsAuthenticated, IsGerant] (is_gerant = user_commande_role(user)=='GERANT' = role admin ou magasin) -> un PREPARATEUR/LIVREUR qui force l'URL voit la page se construire puis des toasts d'erreur 403 en boucle (a corriger/expliciter cote Flutter). La page consomme useCurrentUser(): { user, isAdmin, loading: userLoading }, isAdmin = role==='admin'. Regle centrale: magasinId = isAdmin ? selectedMagasinId : (user?.magasin_id ?? null) — l'admin n'a pas de magasin propre et DOIT en choisir un; le gerant magasin utilise automatiquement le sien. GET /users/caisse/categories/ est le seul appel ouvert a tout authentifie.

**Objectif.** Gestion complete de la caisse d'un magasin: ouvrir une session avec un fond de depart, enregistrer les mouvements d'especes (entrees/sorties avec categorie de depense), fermer la session avec le montant compte et l'ecart, plus un resume financier de periode (entrees/sorties/solde + CA/cout/benefice des produits vendus) et l'historique des sessions fermees.

**Fonctionnalites** (23)

- Titre h1 'Caisse' avec icone Wallet h-8 w-8 text-blue-600 + sous-titre 'Ouverture, mouvements et fermeture de la caisse'
- Bouton 'Actualiser' (variant outline, size sm, icone RefreshCw) en haut a droite: appelle fetchCaisse() UNIQUEMENT (ne rafraichit PAS le resume/periode). disabled={loading}; l'icone RefreshCw prend animate-spin tant que loading est vrai
- Selecteur de magasin (visible SEULEMENT si isAdmin): label 'Magasin :' + une ligne de boutons, un par magasin renvoye par GET /users/magasins/users/. Chaque bouton affiche shop_logo en img h-4 w-4 rounded-full object-cover si present, sinon une icone Store muted, puis shop_name. Le bouton selectionne prend les classes bg-primary/10 border-primary/30 font-medium; les autres border-border. Clic -> setSelectedMagasinId -> re-fetch automatique de la caisse ET du resume (deps des useCallback)
- Si isAdmin et stores.length === 0: texte 'Aucun magasin' a la place des boutons
- Aucun magasin preselectionne au chargement pour un admin -> il tombe d'abord sur l'ecran vide 'Selectionnez un magasin pour gerer sa caisse.'
- CARTE 1 (statut de session) — titre dynamique: si session ouverte icone LockOpen text-green-600 + 'Caisse ouverte', sinon icone Lock muted + 'Caisse fermee'
- CARTE 1 — CardDescription seulement si session: 'Ouverte le {formatDateTime(session.opened_at)}' suivi de ' par {session.opened_by_name}' si opened_by_name existe
- CARTE 1 — Actions si session ouverte: bouton outline 'Mouvement' (icone Plus) -> ouvre le dialog mouvement; bouton destructive 'Fermer la caisse' (icone Lock) -> ouvre le dialog de fermeture
- CARTE 1 — Action si aucune session: bouton primaire 'Ouvrir la caisse' (icone LockOpen) -> ouvre le dialog d'ouverture
- CARTE 1 — 4 tuiles KPI (grid 2 cols mobile / 4 cols sm) affichees seulement si session: 'Fond d'ouverture' = money(session.opening_balance); 'Entrees' = +money(total in) en text-green-600; 'Sorties' = -money(total out) en text-red-600; 'Solde attendu' = money(expectedBalance)
- CARTE 1 — calcul client: movementTotals = reduce sur session.movements (in => acc.in += Number(amount), sinon acc.out += Number(amount)); expectedBalance = Number(opening_balance) + in - out (0 si pas de session)
- CARTE 1 — liste 'Mouvements de la session': conteneur border rounded-lg divide-y max-h-64 overflow-y-auto. Les mouvements sont affiches via [...session.movements].reverse() donc en ordre CHRONOLOGIQUE croissant (l'API les renvoie deja en -created_at, le reverse remet le plus ancien en premier)
- CARTE 1 — ligne de mouvement: icone ArrowUpCircle text-green-600 si movement_type==='in', ArrowDownCircle text-red-600 si 'out'; titre = m.reason (truncate, font-medium); sous-titre xs muted = formatDateTime(m.created_at) + ' · ' + m.created_by_name (le ' · nom' n'apparait que si created_by_name existe); a droite montant '+money' vert ou '-money' rouge en font-semibold
- CARTE 2 (Resume de la caisse) — titre 'Resume de la caisse' + description 'Tous les mouvements et les ventes de la periode, quelle que soit la session.'
- CARTE 2 — 6 tuiles KPI (grid 2/3/6): 'Entrees' +money(summary.total_entrees) vert; 'Sorties' -money(summary.total_sorties) rouge; 'Solde' money(summary.solde); 'CA produits vendus' money(summary.ca_produits_vendus); 'Cout des produits vendus' money(summary.cout_produits_vendus) en text-orange-600; 'Benefice produits vendus' money(summary.benefice_produits_vendus) en text-green-700 avec petite icone PiggyBank h-3.5 dans le label
- CARTE 2 — bloc 'Sorties par categorie' affiche UNIQUEMENT si summary.sorties_par_categorie.length > 0: une Badge variant outline par ligne, texte '{row.categorie} : {money(row.total)}' (le backend remplace une categorie nulle par 'Sans categorie', tri par total decroissant)
- CARTE 2 — liste 'Mouvements de la periode (N)' avec N = periodMovements.length; conteneur border rounded-lg divide-y max-h-72 overflow-y-auto; ordre = ordre API = -created_at (plus recent en premier), PAS de reverse ici (contrairement a la carte 1)
- CARTE 2 — ligne de mouvement de periode: identique a la carte 1 mais le titre est '{m.reason} · {m.category_name}' quand category_name existe
- CARTE 3 (Historique des sessions) — titre 'Historique des sessions', description '{history.length} session(s) fermee(s)'. history = resultat de listSessions filtre cote client sur status === 'closed'
- CARTE 3 — tableau dans un conteneur overflow-x-auto, 6 colonnes (voir filters/uxDetails pour le detail des cellules)
- Pas de recherche, pas de tri cliquable, pas de pagination, pas d'export, pas de raccourci clavier, aucune action ligne (pas d'edition ni de suppression de mouvement dans cette page, bien que djangoClient.caisse.deleteMovement existe et ne soit pas utilise ici)
- Rafraichissement temps reel via useRealtimeRefresh(['caisse_session','caisse_movement'], () => { fetchCaisse(); fetchSummary(); }) — WebSocket /ws/data/, debounce 400 ms
- Chargement initial: 3 useEffect declenches quand !userLoading -> fetchStores() (admin seulement), fetchCaisse(), fetchSummary(); + 1 useEffect au montage qui charge les categories de depense (erreur silencieusement ignoree via .catch(() => {}))

**Formulaires** (4)

- FORMULAIRE 'Ouvrir la caisse' (dans le Dialog d'ouverture). Champs: (1) 'Montant d'ouverture (Ar) *' — Input type=number, min=0, step=0.01, required (validation HTML native), etat openingBalance, pre-rempli automatiquement avec total_stock_value du magasin (helper: 'Pre-rempli avec la valeur de stock actuelle du magasin — modifiable.'), le pre-remplissage arrive APRES l'ouverture du dialog (await asynchrone); (2) 'Heure d'ouverture' — composant DateTimeInput (deux inputs natifs separes: type=date + type=time w-32), initialise a maintenant (heure de l'APPAREIL via toDatetimeLocalValue), max = maintenant (seule la partie DATE de min/max est appliquee par le composant), helper 'Modifiable si la caisse a ete ouverte plus tot dans la journee.'; (3) 'Note (optionnel)' — Textarea, placeholder 'Ex: Fond de caisse du matin'. Validation JS: if (!magasinId) toast.error('Selectionnez un magasin') et abandon. Soumission: POST open avec opening_balance = openingBalance || 0, opening_note = openingNote || undefined, opened_at = ISO (new Date(value).toISOString()) ou undefined si vide. Succes: toast.success('Caisse ouverte'), fermeture du dialog, fetchCaisse(). Echec: toast.error(err.message || 'Erreur lors de l’ouverture'), dialog reste ouvert, champs conserves. Boutons: 'Annuler' (outline, disabled si submitting, ferme sans reset) et 'Ouvrir' (submit, disabled si submitting, icone Loader2 animate-spin pendant l'envoi sinon LockOpen).
- FORMULAIRE 'Fermer la caisse' (Dialog de fermeture). Description du dialog: 'Solde attendu : {money(expectedBalance)} — comptez la caisse et indiquez le montant reel.' Champs: (1) 'Montant compte (Ar) *' — Input type=number min=0 step=0.01 required, etat closingBalance, pre-rempli avec total_stock_value (meme helper que l'ouverture), et sous le champ un indicateur d'ecart en direct affiche des que closingBalance !== '': 'Ecart : {signe}{money(Number(closingBalance) - expectedBalance)}' en text-green-600 si l'ecart vaut exactement 0, sinon text-orange-600, avec un '+' explicite si l'ecart est positif; (2) 'Heure de fermeture' — DateTimeInput, initialise a maintenant, min = session.opened_at (converti en datetime-local, partie date seulement), max = maintenant, helper 'Modifiable si la caisse a ete fermee plus tot.'; (3) 'Note (optionnel)' — Textarea placeholder 'Ex: Compte OK'. Validation JS: if (!session || closingBalance === '') toast.error('Montant compte requis') et abandon. Soumission: POST close(session.id, {closing_balance, closing_note || undefined, closed_at ISO || undefined}). Succes: toast.success('Caisse fermee'), fermeture du dialog, fetchCaisse() SEUL (le resume n'est pas rafraichi). Echec: toast.error(err.message || 'Erreur lors de la fermeture'). Boutons: 'Annuler' outline + 'Fermer la caisse' variant destructive (Loader2 pendant l'envoi sinon Lock).
- FORMULAIRE 'Ajouter un mouvement' (Dialog mouvement). Description: 'Apport ou retrait d'especes dans la caisse.' Champs: (1) 'Type *' — RadioGroup horizontal (flex gap-4) a 2 options: 'Entree' (value 'in', icone ArrowUpCircle verte) et 'Sortie' (value 'out', icone ArrowDownCircle rouge); valeur par defaut 'in'; (2) 'Montant (Ar) *' — Input type=number min=0 step=0.01 required; (3) 'Motif *' — Input texte required, placeholder 'Ex: Achat fournitures'; (4) 'Categorie (optionnel)' — Select AFFICHE UNIQUEMENT si movementType === 'out', options = expenseCategories (value = String(c.id), label = c.nom), placeholder 'Aucune categorie', helper 'Gerez les categories dans Parametres > Depenses.'. Validation JS: if (!movementAmount || !movementReason) toast.error('Montant et motif requis') et abandon (donc un montant '0' est refuse car chaine falsy... '0' est truthy en JS, seule la chaine vide bloque). Soumission: POST movements avec session = session?.id, movement_type, amount, reason, et category = Number(movementCategory) UNIQUEMENT si movementType==='out' ET movementCategory non vide (sinon undefined). Succes: toast.success('Mouvement ajoute'), fermeture du dialog, fetchCaisse() ET fetchSummary(). Echec: toast.error(err.message || 'Erreur lors de l’ajout du mouvement'). Boutons: 'Annuler' outline + 'Ajouter' (Loader2 pendant l'envoi sinon Plus). Reset a l'ouverture du dialog: type='in', montant '', motif '', categorie ''.
- FILTRE DE PERIODE du resume (pas un form, deux Input type=date dans le header de la CARTE 2): 'du' summaryFrom (defaut = premier jour du mois courant, calcule par todayStr.slice(0,8) + '01' a partir de new Date().toISOString() donc en UTC), separateur texte '→', 'au' summaryTo (defaut = aujourd'hui, date UTC ISO). Chaque changement relance fetchSummary() (summary + listMovements) via la dependance du useCallback. Aucun bouton 'Appliquer', aucune validation from <= to.

**Modales / dialogs / drawers** (6)

- Dialog 'Ouvrir la caisse' (shadcn Dialog, etat openDialogOpen) — titre 'Ouvrir la caisse', description 'Renseignez le fond de caisse de depart.', contient le formulaire d'ouverture, ferme via la croix/overlay (onOpenChange) ou le bouton Annuler
- Dialog 'Fermer la caisse' (closeDialogOpen) — titre 'Fermer la caisse', description rappelant le solde attendu en gras, contient le formulaire de fermeture avec l'indicateur d'ecart temps reel
- Dialog 'Ajouter un mouvement' (movementDialogOpen) — titre 'Ajouter un mouvement', description 'Apport ou retrait d'especes dans la caisse.', contient le RadioGroup type / montant / motif / select categorie conditionnel
- Select (popover shadcn) 'Categorie' a l'interieur du dialog mouvement — liste des CaisseCategory (defaut serveur: Salaire, Pub, Commande stock, Autre), placeholder 'Aucune categorie'
- Aucun dialog de confirmation destructive (la fermeture de caisse se fait sans confirmation supplementaire, le formulaire fait office de confirmation)
- Aucun drawer, aucun menu contextuel, aucun popover hors le Select

**Recherche, filtres, tri, pagination** (6)

- Selecteur de magasin (admin uniquement) — boutons-onglets, pilote TOUTES les requetes de la page (caisse courante, sessions, resume, mouvements de periode, valeur de stock)
- Plage de dates du resume: date_from / date_to envoyees a /users/caisse/summary/ et /users/caisse/movements/. Cote backend le filtre porte sur created_at__date__gte / __lte (comparaison sur la DATE, timezone serveur Indian/Antananarivo)
- Filtre client sur l'historique: sessions.filter(s => s.status === 'closed')
- Tri: aucun tri utilisateur. Ordre impose par le backend — sessions: ordering ['-opened_at']; mouvements: ordering ['-created_at']. La liste des mouvements de SESSION est inversee cote client (.reverse()) donc chronologique croissante, celle de la PERIODE reste anti-chronologique
- Pagination: aucune (listes completes, defilement interne max-h-64 / max-h-72 et tableau en overflow-x-auto)
- Aucune barre de recherche

**Appels API** (12)

- GET /users/me/ (via useCurrentUser) — role, magasin_id, commande_role, shop_name/logo; base du gating
- GET /users/magasins/users/ (djangoClient.get) — seulement si isAdmin; alimente la barre de selection de magasin (champs utilises: magasin_id, shop_name, shop_logo). Erreur -> toast 'Erreur de chargement des magasins: ' + message
- GET /users/caisse/sessions/current/?magasin_id={id} (djangoClient.caisse.current) — session ouverte du magasin; le backend renvoie 204 No Content s'il n'y en a pas, normalise en null cote client
- GET /users/caisse/sessions/?magasin_id={id} (djangoClient.caisse.listSessions) — toutes les sessions du magasin (ordering -opened_at), filtrees cote client sur status==='closed' pour l'historique
- GET /users/caisse/summary/?magasin_id&date_from&date_to (djangoClient.caisse.summary) — { date_from, date_to, total_entrees, total_sorties, solde, sorties_par_categorie[{categorie,total}], ca_produits_vendus, cout_produits_vendus, benefice_produits_vendus }
- GET /users/caisse/movements/?magasin_id&date_from&date_to (djangoClient.caisse.listMovements) — mouvements de la periode toutes sessions confondues
- GET /users/caisse/categories/ (djangoClient.caisse.categories.list) — [{id, nom, created_at}] pour le select 'Categorie' des sorties; appele une seule fois au montage, hors magasin
- GET /users/magasins/stats/ (djangoClient.get) — appele a l'ouverture des dialogs Ouvrir/Fermer pour pre-remplir le montant: on cherche l'entree dont magasin_id === magasinId et on prend total_stock_value. Echec -> return null (silencieux, champ laisse vide)
- POST /users/caisse/sessions/open/ {magasin_id, opening_balance, opening_note?, opened_at?} — ouvre la session
- POST /users/caisse/sessions/{sessionId}/close/ {closing_balance, closing_note?, closed_at?} — ferme la session, le backend calcule expected_balance et difference
- POST /users/caisse/movements/ {session, movement_type, amount, reason, category?} — ajoute un mouvement
- (non utilise ici mais present dans le client: DELETE /users/caisse/movements/{id}/)

**Etats UI** (13)

- userLoading: retour anticipe -> page entiere remplacee par 3 Skeleton h-16 w-full dans un conteneur p-6 space-y-4
- loading (fetch caisse): 3 Skeleton h-16 w-full a la place des 3 cartes
- summaryLoading: Skeleton h-40 w-full a la place du contenu de la carte Resume
- Empty 'aucun magasin resolu' (!magasinId): Card avec texte muted centre py-12 — 'Selectionnez un magasin pour gerer sa caisse.' si isAdmin, sinon 'Aucun magasin associe a votre compte.'
- Empty liste magasins (admin): texte 'Aucun magasin'
- Empty mouvements de session: 'Aucun mouvement pour l'instant' (p-4, centre, muted)
- Empty mouvements de periode: 'Aucun mouvement pour cette periode'
- Empty historique: ligne de tableau unique colSpan=6, 'Aucune session fermee', centree py-8 muted
- Etat 'caisse fermee' vs 'caisse ouverte': change le titre, l'icone, la description et le jeu de boutons de la carte 1; le bloc KPI + mouvements n'existe que si session
- Erreurs: uniquement des toasts sonner (chargement magasins, chargement caisse, chargement resume, echec des 3 soumissions). Aucun ecran d'erreur, aucun retry, les donnees precedentes restent affichees
- Unauthorized: AUCUN etat gere dans la page — un preparateur/livreur qui force /caisse verra la coquille de page + des toasts d'erreur 403 (a implementer proprement en Flutter)
- Disabled: bouton Actualiser disabled pendant loading; les 6 boutons des dialogs disabled pendant submitting; le champ Select categorie n'est pas disabled mais purement conditionnel
- Succes: toasts 'Caisse ouverte' / 'Caisse fermee' / 'Mouvement ajoute' + fermeture du dialog + refetch

**Details UX** (12)

- Formatage monetaire money(v): Number(v ?? 0).toLocaleString('fr-FR', {minimumFractionDigits: 0, maximumFractionDigits: 2}) + ' Ar' — separateur d'espace insecable francais, jusqu'a 2 decimales (different du format du bilan qui arrondit)
- Formatage date/heure formatDateTime: date-fns format(new Date(v), 'dd MMM yyyy HH:mm', {locale: fr}) -> ex '10 sept. 2026 14:30'; '-' si null. ATTENTION: utilise le fuseau de l'APPAREIL, pas APP_TIME_ZONE (Indian/Antananarivo) contrairement a la page bilan — incoherence a trancher au portage Flutter
- Code couleur systematique: entrees/positif = green-600 (ArrowUpCircle, prefixe '+'), sorties/negatif = red-600 (ArrowDownCircle, prefixe '-'), cout = orange-600, benefice = green-700, ecart nul = vert, ecart non nul = orange
- Colonne 'Ecart' de l'historique: Badge variant outline dont les classes changent — 'text-green-700 border-green-200' si Number(s.difference) === 0, sinon 'text-orange-700 border-orange-200'; le contenu prefixe '+' si difference > 0 (jamais de '-' explicite, il vient du money())
- Colonnes du tableau Historique: 'Ouverte le' = formatDateTime(opened_at); 'Fermee le' = formatDateTime(closed_at); 'Fond' = money(opening_balance); 'Compte' = money(closing_balance); 'Ecart' = badge decrit ci-dessus; 'Ouvert / Ferme par' = '{opened_by_name || '-'} / {closed_by_name || '-'}' en text-xs muted
- Icone d'etat de caisse: LockOpen vert = ouverte, Lock gris = fermee; le bouton de fermeture est rouge (destructive) pour marquer l'irreversibilite
- Rafraichissement temps reel silencieux (WebSocket) sur les modeles 'caisse_session' et 'caisse_movement', debounce 400 ms — la caisse se met a jour toute seule quand un autre poste enregistre un mouvement
- Le bouton 'Actualiser' ne recharge PAS le resume de periode (asymetrie a reproduire ou corriger)
- Toasts sonner globaux (Toaster monte dans app/layout.tsx); les messages d'erreur backend arrivent sous la forme 'error: <message>' car le backend renvoie {'error': ...} alors que le client cherche d'abord 'detail' puis serialise les paires cle: valeur
- Le pre-remplissage des montants (ouverture ET fermeture) est recalcule a chaque ouverture de dialog a partir de la valeur de stock courante — le stock bougeant avec les ventes, la valeur proposee change pendant la session
- Le DateTimeInput separe volontairement date et heure (Firefox ne propose pas de picker d'heure sur datetime-local); seule la partie date des bornes min/max est appliquee cote client, le serveur reste l'autorite
- Responsive: grilles 2/4 et 2/3/6 colonnes, header du resume qui passe en colonne sur mobile, tableau en overflow-x-auto

### `/bilan`

- **Fichier Next.js** : `frontend/app/(app)/bilan/page.tsx`
- **Groupe d'audit** : `caisse-bilan`
- **Cible Flutter** : lib/features/tournee/bilan_screen.dart
- **Etat** : DONE

**Role et gating.** LIVREUR EXCLUSIVEMENT. useCurrentUser() fournit { isLivreur, loading: userLoading } avec isLivreur = (role === 'employer' && commande_role === 'LIVREUR'). Guard explicite dans le rendu: if (!userLoading && !isLivreur) -> retourne un ecran 'Acces refuse' (Card, icone ShieldAlert h-12 w-12 text-red-500, titre 'Acces refuse', texte 'Cette page est reservee au livreur.'). Pendant userLoading la page normale est rendue (pas le guard) mais le fetch n'est declenche que si !userLoading && isLivreur, donc on voit les skeletons. Sidebar: entree 'Bilan du jour' (icone Receipt) avec le flag livreurOnly:true -> masquee pour tous les autres roles (mais visible pendant le chargement du user, cf. filtre 'if (loading) return !item.superAdminOnly'). Cote backend, le scoping vient de orders/views.py::get_queryset branche `historique`: pour role LIVREUR le queryset est filtre sur livreur=request.user, et le serializer employe est OrderLivreurSerializer (aucun prix unitaire ni donnee de marge exposee). Un GERANT qui appellerait la meme URL n'aurait pas la branche historique.

**Objectif.** Ticket recapitulatif du jour pour le livreur: liste des commandes qu'il a livrees aujourd'hui et de celles retournees, avec les totaux d'argent encaisse (produits + frais de livraison) separes des montants non encaisses (retours).

**Fonctionnalites** (22)

- Titre h1 'Bilan du jour' + sous-titre 'Livraisons effectuees et retours d'aujourd'hui — voir le ticket recapitulatif.'
- Bouton de rafraichissement (Button variant='outline' size='icon', icone RefreshCw h-4 w-4) en haut a droite -> fetchOrders() en mode non silencieux (affiche les skeletons). Pas de libelle texte, pas d'etat disabled, pas de spinner sur l'icone
- CARTE 'Livraisons effectuees (N)' — titre avec icone PackageCheck h-4 w-4 et le compteur livrees.length entre parentheses; contenu = tableau des commandes au statut LIVRE
- CARTE 'Retours (N)' — titre avec icone Undo2 h-4 w-4 text-red-600 et retours.length; CardDescription 'Colis rapportes — rien n'a ete encaisse, ces montants ne sont pas comptes dans le total du ticket.'; contenu = tableau des commandes au statut RETOUR
- TABLEAU (composant interne OrdersTable, reutilise a l'identique pour les deux cartes) enveloppe dans un div overflow-x-auto, 10 colonnes, pas d'en-tete cliquable, pas de selection, pas d'action de ligne, pas de clic sur ligne
- Colonne 'N° commande' = order.numero (font-medium, align-top)
- Colonne 'Type' = premier article uniquement: (order.items||[])[0]?.category_name, sinon '-'
- Colonne 'Sous-type' = premier article uniquement: firstItem?.type_name, sinon '-'
- Colonne 'Produit' = concatenation de TOUS les articles: items.map(it => `${it.reference_name}${it.couleur ? ` (${it.couleur})` : ''} x${it.quantite}`).join(', '), conteneur max-w-[220px]
- Colonne 'Date' = order.date_commande formatee en toLocaleString('fr-FR') avec timeZone Indian/Antananarivo, day/month/hour/minute en 2 chiffres (PAS d'annee), classes whitespace-nowrap text-xs text-muted-foreground; '-' si absente
- Colonne 'Client' = order.client_nom
- Colonne 'Adresse' = order.adresse_livraison || '-', max-w-[180px] truncate
- Colonne 'Prix' (alignee a droite) = fmt(prixProduit(order)) avec prixProduit = Number(total_a_payer||0) - Number(frais_livraison||0) — derive parce que le prix unitaire n'est jamais expose au livreur
- Colonne 'Frais' (droite) = fmt(order.frais_livraison)
- Colonne 'Argent' (droite, font-medium) = fmt(order.total_a_payer)
- TICKET recapitulatif (colonne de droite, largeur fixe 300px en lg, sticky top-6): Card en font-mono, en-tete centre avec icone Receipt, titre 'BILAN DU JOUR' (tracking-wide) et la date du jour au format fr-FR dd/mm/yyyy en fuseau Indian/Antananarivo, bordures en pointilles (border-dashed)
- TICKET — section 'LIVRAISONS EFFECTUEES': lignes 'Nombre' (count), 'Total produits' (somme des prixProduit), 'Total frais livraison' (somme des frais_livraison), puis separateur pointille et 'TOTAL ARGENT' en gras (somme des total_a_payer)
- TICKET — section 'RETOURS (hors total ci-dessus)': memes 4 lignes, la derniere intitulee 'TOTAL NON ENCAISSE' en gras text-red-600
- Separation stricte livrees / retours: sumTotals() est applique independamment aux deux listes, aucun cumul entre elles (regle metier explicite en commentaire)
- Rafraichissement temps reel: useRealtimeRefresh(['order','order_status_history'], () => fetchOrders(true)) — mode SILENCIEUX (silent=true => pas de passage par setLoading, donc pas de skeleton, la table se met a jour en place), debounce 400 ms
- Aucun filtre, aucune recherche, aucun tri, aucune pagination, aucun export, aucun raccourci clavier, aucun onglet, aucun modal
- Layout en grid: 1 colonne mobile, 'lg:grid-cols-[1fr_300px]' desktop; padding p-4 sm:p-6, espacement space-y-6

**Formulaires** (1)

- Aucun formulaire, aucun champ de saisie sur cette page

**Modales / dialogs / drawers** (1)

- Aucun modal, dialog, drawer, dropdown, popover ni menu contextuel sur cette page

**Recherche, filtres, tri, pagination** (4)

- Filtre implicite unique: la journee en cours au fuseau Indian/Antananarivo (appDayBounds), envoyee en date_from/date_to — non modifiable par l'utilisateur (pas de selecteur de date)
- Repartition cote client par statut: livrees = orders.filter(o => o.statut_courant === 'LIVRE'), retours = orders.filter(o => o.statut_courant === 'RETOUR'). Les autres statuts eventuellement renvoyes (ANNULE, EN_LIVRAISON...) sont recuperes mais N'APPARAISSENT NULLE PART
- Tri: aucun tri utilisateur, ordre serveur -date_commande (plus recent en premier)
- Pagination: aucune

**Appels API** (3)

- GET /users/me/ (useCurrentUser) — determine isLivreur (role employer + commande_role LIVREUR)
- GET /orders/?historique=1&date_from={ISO}&date_to={ISO} (djangoClient.orders.list) — historique personnel du livreur borne a la journee. Les bornes viennent de appDayBounds() (lib/timezone.ts): start = `${jour}T00:00:00.000+03:00`.toISOString(), end = `${jour}T23:59:59.999+03:00`.toISOString(), le jour etant la date courante a Antananarivo. Le backend filtre sur livreur=me puis date_commande >= parsed_from et <= parsed_to, tous statuts confondus, order_by('-date_commande'), serialise avec OrderLivreurSerializer (id, numero, date_commande, client_nom, telephone, livraison_zone, adresse_livraison, mode_paiement, frais_livraison, total_a_payer, statut_courant, note_livreur, livreur, livreur_name, items[id, reference_name, brand_name, type_name, category_name, couleur, quantite], status_history, created_at)
- Aucun autre appel: pas de mutation, pas de changement de statut depuis cette page (lecture seule)

**Etats UI** (8)

- Loading initial: chaque carte affiche un Skeleton dans un conteneur p-6 — h-32 w-full pour 'Livraisons effectuees', h-24 w-full pour 'Retours'
- Loading silencieux (declenche par WebSocket): aucun indicateur visuel, les donnees se remplacent
- Empty livraisons: 'Aucune livraison effectuee aujourd'hui.' (text-sm muted, centre, py-10)
- Empty retours: 'Aucun retour aujourd'hui.' (meme style)
- Unauthorized: ecran plein 'Acces refuse' avec ShieldAlert rouge (voir roles) — le seul des deux pages a en avoir un
- Erreur reseau: catch SILENCIEUX -> setOrders([]) sans toast ni message; l'utilisateur voit les deux etats vides et un ticket a 0 Ar, indiscernable d'une journee sans livraison (point a ameliorer au portage Flutter)
- Le ticket est toujours rendu, meme pendant le loading (il affiche alors 0 / 0 Ar puisque orders est vide)
- Aucun bouton disabled, aucun etat de soumission

**Details UX** (8)

- Formatage monetaire fmt(n): new Intl.NumberFormat('fr-MG').format(Math.round(Number(n||0))) + ' Ar' — ARRONDI a l'entier, locale fr-MG (different de money() de la page caisse qui garde 2 decimales et utilise fr-FR)
- Toutes les dates sont affichees en heure d'Antananarivo (APP_TIME_ZONE), pas en heure de l'appareil — regle explicite pour que le 'bilan du jour' ne bascule pas entre 00h et 03h
- Le ticket est stylise comme un vrai ticket de caisse: font-mono, bordures en pointilles (border-dashed) entre sections, titres de section en text-xs font-semibold muted majuscules
- Le TOTAL NON ENCAISSE des retours est en rouge pour marquer visuellement qu'il ne rentre pas en caisse
- Le ticket est sticky (lg:sticky lg:top-6 self-start) — il reste visible pendant le defilement des tableaux
- Le compteur de chaque carte est dans son titre, ex 'Livraisons effectuees (3)'
- Les cellules du tableau sont align-top (les lignes multi-articles peuvent etre hautes), l'adresse est tronquee et le produit contraint a 220px
- Mise a jour temps reel sur les evenements 'order' et 'order_status_history': des que le gerant/livreur change un statut ailleurs, le bilan se recalcule sans clic

### `/dashboard`

- **Fichier Next.js** : `frontend/app/(app)/dashboard/page.tsx`
- **Groupe d'audit** : `dashboard-reports`
- **Cible Flutter** : lib/features/dashboard/dashboard_screen.dart
- **Etat** : PARTIAL

**Role et gating.** GERANT UNIQUEMENT (admin + magasin). Gating en 2 couches: (1) Sidebar (/home/garrix/Dev/Smartphone/frontend/components/layout/sidebar.tsx, item adminOnly:true) masque le lien si !isAdminOrSuperAdmin. (2) Dans la page: `const { user, isGerant, loading: userLoading } = useCurrentUser()`. Si userLoading -> écran de 3 Skeletons (h-16 w-full) dans un `div p-6 space-y-4`. Si `!isGerant` -> écran plein « Accès refusé » (Card + icône ShieldAlert h-12 w-12 text-red-500, titre `Accès refusé` text-xl font-bold, sous-texte `Le tableau de bord est réservé au gérant.`), aucun appel API n'est bloqué pour autant (le fetch part quand même via useEffect, mais l'UI est remplacée). isGerant = role==='admin' || role==='magasin' (lib/auth/useCurrentUser.ts). PREPARATEUR et LIVREUR (role='employer' + commande_role) -> Accès refusé. Un 3e état de rôle existe dans le code (`role === 'employer'` renvoyé par l'API dans le state local `role`) qui affiche un jeu de 3 KPI différent, MAIS il est mort/inatteignable car !isGerant coupe avant. Il n'y a PAS de middleware Next.js ni de guard serveur; le layout (app)/layout.tsx redirige seulement vers /login si `!djangoClient.isAuthenticated()`.

**Objectif.** Tableau de bord gérant: KPIs financiers et stock (masquables), courbe des ventes 7 jours, répartition du stock par catégorie, 8 dernières ventes, alertes de stock (rupture/faible). Rafraîchissement temps réel via WebSocket.

**Fonctionnalites** (21)

- Titre h1 `Tableau de bord` (text-3xl font-bold tracking-tight)
- Sous-titre dynamique: `Magasin : {user.store_name}` si user.store_name existe, sinon fallback littéral `Gestion des stocks cosmétiques`. NB store_name = company_name pour un admin, shop_name pour un magasin/employé (mapping dans useCurrentUser)
- Grille KPI responsive: grid-cols-1 / sm:2 / lg:3 / xl:6, gap-4; chaque KpiCard principal occupe xl:col-span-2
- KPI (branche gérant, role !== 'employer') #1 `CA` — valeur `{fmt(kpis.ca)} Ar`, sous-texte `Valeur du stock + entrées de caisse`, icône Wallet, couleur text-blue-600, metricKey='ca' (masquable)
- KPI #2 `Bénéfice total` — `{fmt(totalProfit)} Ar`, sous-texte `Produits vendus (vente - achat)`, icône CheckCircle2, text-emerald-600, metricKey='totalProfit'
- KPI #3 `Valeur du stock` — `{fmt(totalValue)} Ar`, sous-texte `Valeur totale de l'inventaire`, icône DollarSign, couleur par défaut text-muted-foreground, metricKey='totalValue'
- KPI #4 `Bénéfice estimé` — `{fmt(beneficeEstimeStock)} Ar`, sous-texte `Potentiel si tout le stock est vendu`, icône TrendingUp, text-emerald-600, metricKey='beneficeEstimeStock'
- KPI #5 `Ventes livrées` — `{fmt(totalSalesAllStores)} Ar`, sous-texte `Chiffre d'affaires des commandes livrées`, icône TrendingUp, text-green-600, metricKey='totalSalesAllStores'
- KPI #6 `Produits` — valeur composée `{fmt(totalQuantity)} unité(s) sur {totalProducts} produit(s)` avec pluralisation conditionnelle (`s` ajouté si >1 sur chaque terme), sous-texte `Stock total du catalogue`, icône Package. PAS masquable (aucun metricKey)
- KPI #7 `Admins/Magasins` — affiché UNIQUEMENT si `role === 'admin'` (state local alimenté par la réponse API, pas par useCurrentUser). Valeur kpis.totalEmployees, sous-texte `Personnel enregistré`, icône Users. Pas de col-span (carte simple largeur)
- KPI #8 `Alertes stock` — valeur = lowStockCount + outOfStockCount, sous-texte `{outOfStockCount} rupture(s), {lowStockCount} faible(s)`, icône AlertTriangle text-orange-600. Bordure/fond conditionnels: si total > 0 -> `border-orange-200 bg-orange-50 dark:bg-orange-950/20`, sinon aucun accent. Pas masquable
- KPI branche 'employer' (code présent mais inatteignable): `Mes ventes du jour` (`{mySalesToday} ventes`, sous-texte `Transactions effectuées aujourd'hui`, TrendingUp, text-green-600), `Chiffre d'affaires personnel` (`{fmt(totalAmountSold)} Ar`, `Montant total vendu par vous`, DollarSign, text-blue-600), `Clients servis` (clientsCount, `Nombre total de transactions`, Users). Aucun n'est masquable
- Bouton oeil/oeil-barré (Eye / EyeOff, h-4 w-4) dans l'en-tête de chaque KpiCard qui possède un metricKey — bascule masquage de la valeur; aria-label dynamique `Afficher {titre}` / `Masquer {titre}`; style rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground
- Masquage: valeur remplacée par la chaîne `••••••` (6 puces). État local `hiddenMetrics` initialisé à true (MASQUÉ) pour ca, totalProfit, totalValue, beneficeEstimeStock, totalSalesAllStores — donc TOUS les montants sont cachés au premier rendu; l'état n'est PAS persisté (perdu au rechargement)
- Graphique 1 `Ventes — 7 derniers jours` (CardTitle text-lg) + description `Évolution journalière des sorties` — LineChart recharts, ResponsiveContainer width 100% height 260, CartesianGrid strokeDasharray 3 3, XAxis dataKey='label' (Dim/Lun/Mar/Mer/Jeu/Ven/Sam), YAxis auto, Tooltip, Legend, une seule Line type monotone dataKey='sorties' name='Quantités vendues' stroke #ef4444 strokeWidth 2 dot=false. Le champ `entrées` est calculé (toujours 0) mais JAMAIS tracé (code mort)
- Graphique 2 `Stock par catégorie` + description `Unités par famille de produits` — rendu ADAPTATIF: si categoryChart.length <= 5 -> PieChart (Pie cx 50% cy 50% outerRadius 90, dataKey='value', label inline `{name}: {value}`, labelLine=false, Cell coloré par CHART_COLORS[i % 8], Tooltip). Si > 5 catégories -> BarChart horizontal (layout='vertical', XAxis type number, YAxis type category dataKey='name' width 100 tick fontSize 12, Bar fill #3b82f6 radius [0,4,4,0])
- Palette CHART_COLORS (8 couleurs, cycle modulo): #3b82f6, #8b5cf6, #ec4899, #f59e0b, #10b981, #ef4444, #6366f1, #f97316
- Bloc `Ventes récentes` (CardTitle avec icône TrendingUp h-5 w-5) + description `8 dernières transactions enregistrées`. Liste (pas un tableau) de lignes: pastille ronde bg-red-100 text-red-700 avec ArrowDown, nom produit (font-medium text-sm truncate, fallback `Produit inconnu`), ligne meta date + `· {seller_name}` si présent + `· ({shop_name})` si présent, et à droite quantité `-{quantity}` en text-sm font-semibold text-red-600 + montant `{fmt(total_price||0)} Ar` en text-[10px] font-mono
- Bloc `Alertes de stock` (icône AlertTriangle, colorée text-orange-500 s'il y a des alertes sinon text-muted-foreground) + description `Produits à réapprovisionner`. Bordure de la Card passe à `border-orange-200` si lowStockProducts.length > 0. Chaque ligne: nom produit (font-medium text-sm truncate) + SKU (text-xs font-mono text-muted-foreground), à droite quantité `{quantity} u.` colorée (text-red-600 si rupture, text-orange-600 si faible) + Badge `Rupture` (bg-red-100 text-red-800) ou `Faible` (bg-orange-100 text-orange-800)
- Rafraîchissement temps réel: useRealtimeRefresh(['product_variant','order','stock_movement']) -> refetch SILENCIEUX (silent=true, pas de skeleton) débounce 400 ms via WebSocket /ws/data/
- Aucun bouton d'actualisation manuel, aucun export, aucun filtre, aucune pagination, aucun tri utilisateur, aucun raccourci clavier sur cette page

**Formulaires** (1)

- AUCUN formulaire, aucun champ de saisie, aucune validation sur cette page. La seule interaction utilisateur est le bouton toggle Eye/EyeOff de masquage des KPI.

**Modales / dialogs / drawers** (1)

- AUCUN modal / dialog / drawer / dropdown / popover / menu contextuel / confirmation sur cette page. Le seul overlay du contexte est le Sheet mobile de la Sidebar (hors page).

**Recherche, filtres, tri, pagination** (2)

- Aucune recherche, aucun filtre, aucun tri utilisateur, aucune pagination.
- Tris internes (non pilotables): catégories triées par valeur décroissante (b.value - a.value); ventes récentes prises dans l'ordre renvoyé par l'API (backend: order_by('-updated_at')), tronquées à 8; produits en alerte tronqués à 8 dans l'ordre du catalogue.

**Appels API** (4)

- GET /users/dashboard/ (djangoClient.get) — renvoie { role, kpis, lists }. kpis lues: ca, benefice_estime_stock, total_stock_value | stock_value, total_employers | total_magasins, low_stock_count, my_sales_today | sales_today, total_amount_sold | total_revenue, total_revenue (ventes livrées), clients_count | total_sales, total_profit. lists lue: recent_sales (max 5 côté backend)
- GET /catalog/references/ (via djangoClient.products.list() -> catalog.references.list()) — sert à calculer totalProducts, totalQuantity, categoryMap, et la liste des produits en alerte (rupture/faible). Chaque référence est aplatie par mapReferenceToProduct: initial_quantity = somme des stock_actuel des variantes, alert_threshold = min des seuil_alerte (défaut 1), unit_price = null, expiry_date = null, category = category_name
- GET /users/me/ (via useCurrentUser) — rôle, store_name/store_logo, commande_role
- WS /ws/data/?token=... (DataSyncProvider) — événements {model, action, id, magasin_id} déclenchant le refetch silencieux

**Etats UI** (8)

- userLoading -> 3 Skeleton h-16 w-full (page entière)
- unauthorized (!isGerant) -> Card pleine page « Accès refusé » + ShieldAlert rouge
- loading (fetch initial) -> chaque KpiCard affiche Skeleton h-8 w-32 à la place de la valeur; graphique 1 Skeleton h-64 w-full; graphique 2 Skeleton h-64 w-full; ventes récentes 5 Skeleton h-14 w-full; alertes 4 Skeleton h-12 w-full
- empty catégories -> `Aucune donnée` centré (h-64, text-muted-foreground text-sm)
- empty ventes récentes -> `Aucune vente enregistrée` (text-sm text-muted-foreground text-center py-8)
- empty alertes (cas succès) -> bloc centré CheckCircle2 h-10 w-10 text-green-500 + `Tous les stocks sont OK` (text-sm font-medium text-green-700) + `Aucun produit en alerte` (text-xs)
- error -> AUCUN état d'erreur visible: le catch fait seulement console.error('Dashboard error:', err); l'utilisateur voit une page avec des KPI à 0 et des états vides. Pas de toast, pas de retry
- refetch temps réel -> silencieux, aucun indicateur visuel (pas de spinner, pas de flash de skeleton)

**Details UX** (10)

- Formatage nombres: Intl.NumberFormat('fr-MG', { minimumFractionDigits: 0 }) sur Math.round(n) -> séparateurs de milliers à la française, 0 décimale. Suffixe monétaire ` Ar` concaténé manuellement (jamais via style:'currency')
- Valeur masquée = littéral `••••••`
- Format date des ventes récentes: toLocaleDateString('fr-FR', { day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' }) -> ex. `09/03 14:30` (pas d'année)
- Couleurs sémantiques: CA bleu (text-blue-600), bénéfices vert émeraude (text-emerald-600), ventes livrées vert (text-green-600), alertes orange (text-orange-600), rupture rouge (text-red-600 / bg-red-100 text-red-800), stock faible orange (bg-orange-100 text-orange-800), OK vert (text-green-500/700)
- Carte « Alertes stock » teintée orange (border-orange-200 bg-orange-50, dark: bg-orange-950/20) uniquement quand il y a au moins une alerte
- Carte « Alertes de stock » (liste) prend border-orange-200 quand la liste n'est pas vide, et son icône passe orange
- Sortie de vente symbolisée par une flèche descendante rouge (ArrowDown) dans une pastille bg-red-100
- Pas de toast/sonner sur cette page
- Espacement global: p-6 space-y-8; sections graphiques et listes en grid lg:grid-cols-2 gap-6
- Le libellé « 8 dernières transactions » est trompeur: le backend ne renvoie que 5 recent_sales

### `/reports`

- **Fichier Next.js** : `frontend/app/(app)/reports/page.tsx`
- **Groupe d'audit** : `dashboard-reports`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** Réservé au GERANT dans la navigation (sidebar item `Rapports` avec adminOnly:true -> visible seulement si isAdminOrSuperAdmin = admin || magasin). MAIS la page elle-même N'A AUCUN GUARD: pas de vérif isGerant, pas d'écran « Accès refusé », pas de gestion de `loading` utilisateur. Un employer (PREPARATEUR/LIVREUR) qui tape l'URL /reports directement voit la page (les données restant filtrées côté backend). Seul usage du rôle dans la page: `const { isAdmin } = useCurrentUser()` -> isAdmin === (role === 'admin') gouverne (a) le calcul de l'agrégat par magasin (byShop n'est rempli que si isAdmin), (b) l'affichage de la Card « Performance par magasin », (c) l'envoi de `topMagasins` dans le payload d'analyse IA (undefined sinon). ATTENTION: isAdmin est false pendant le chargement de /users/me/, donc la carte magasins apparaît après coup (pas de skeleton pour ce délai).

**Objectif.** Rapports analytiques: KPI globaux (CA, bénéfice, unités, transactions, stock, alertes), courbe du CA sur 7/30/90 jours, top produits, ventes à crédit, performance vendeurs, performance magasins (admin), répartition des mouvements de stock, et génération d'une analyse IA texte.

**Fonctionnalites** (22)

- Header: h1 `Rapports` (text-3xl font-bold tracking-tight) + sous-titre `Analyse des ventes, du stock et des performances`
- Bouton `Actualiser` (Button variant='outline' size='sm', icône RefreshCw h-4 w-4 mr-2) aligné à droite du header — onClick fetchData() NON silencieux (réaffiche tous les skeletons), `disabled={loading}`, l'icône tourne (`animate-spin`) pendant le chargement
- Grille KPI: grid-cols-2 md:grid-cols-4 gap-4, 6 cartes générées depuis un tableau `kpis`
- KPI `Chiffre d'affaires` — somme de sales[].total_price, `{fmt} Ar`, icône DollarSign, text-green-600
- KPI `Bénéfice net` — somme de sales[].total_profit, `{fmt} Ar`, icône TrendingUp, text-emerald-600
- KPI `Unités vendues` — somme de sales[].quantity, `{fmt}` (sans unité), icône ShoppingBag, text-blue-600
- KPI `Transactions` — sales.length (NB: nombre de LIGNES d'article livrées, pas de commandes), icône ShoppingBag, text-purple-600
- KPI `Produits en stock` — somme de products[].initial_quantity, `{fmt} u.`, icône Package, text-indigo-600
- KPI `Alertes stock` — lowStockCount + expiredCount, icône AlertTriangle, text-amber-600
- Card `Chiffre d'affaires — {period} derniers jours` + description `Évolution journalière du CA`
- Sélecteur de période: 3 boutons `7j` / `30j` / `90j` (Button size='sm', h-7 px-2.5 text-xs), variant='default' pour la période active et 'outline' pour les autres. Défaut = 30. Le changement ne relance AUCUN appel API (recalcul purement client) et impacte aussi le titre du bloc mouvements de stock
- BarChart recharts du CA: ResponsiveContainer 100% x 260, CartesianGrid 3 3, XAxis dataKey='date' tick fontSize 10 avec `interval = Math.max(Math.floor(period/8), 0)` (0 pour 7j -> toutes les dates, 3 pour 30j, 11 pour 90j), YAxis tickFormatter=fmt tick fontSize 11, Tooltip formatter `{fmt(v)} Ar`, Bar dataKey='revenue' fill #3b82f6 radius [2,2,0,0] name='CA'
- Card `Top produits vendus` + description `Classement par chiffre d'affaires`... (en réalité `Classement par quantités vendues`) — Table 5 colonnes: `#` (rang i+1, font-medium text-muted-foreground), `Produit` (font-medium), `Qté vendue` (text-right font-semibold), `CA généré` (text-right, `{fmt} Ar`), `Bénéfice` (text-right text-emerald-600 font-medium, `{fmt} Ar`). Tri par qty décroissante, TOP 10
- Card `Ventes à crédit` (icône AlertTriangle h-5 w-5 text-orange-500) + description `Paiements en attente ou partiels` — Table 4 colonnes: `Client` (customer_name ou fallback `Client anonyme`, font-medium), `Produit` (product_name, text-muted-foreground), `Restant dû` (text-right font-semibold text-red-600, = max(total_price - payment_amount, 0), `{fmt} Ar`), `Statut` (Badge). Max 8 lignes
- Badge statut de la vente à crédit: `En retard` (variant='destructive') si payment_due_date < aujourd'hui, sinon `En attente` (variant='outline'); classe text-[10px]
- Card `Performance des vendeurs` (icône Users h-5 w-5 text-blue-500) + description `Classement par chiffre d'affaires` — Table 4 colonnes: `Vendeur` (seller_name ou `Non attribué`), `Ventes` (nombre de lignes, text-right), `CA` (text-right `{fmt} Ar`), `Bénéfice` (text-right text-emerald-600 font-medium). Tri par revenue décroissant, TOP 8
- Card `Performance par magasin` — AFFICHÉE UNIQUEMENT si isAdmin. Icône Store h-5 w-5 text-violet-500, description `Comparaison du chiffre d'affaires entre magasins`. Table 4 colonnes: `Magasin` (shop_name ou `Magasin inconnu`), `Qté vendue`, `CA` (`{fmt} Ar`), `Bénéfice` (text-emerald-600). Tri par revenue décroissant, PAS de slice (liste complète)
- Card `Mouvements de stock — {period} derniers jours` + description `Entrées, sorties et transferts enregistrés` — 3 tuiles (grid-cols-3 gap-4, chacune rounded-lg border p-4): `Entrées` (ArrowUpRight h-5 w-5 text-green-600, compteur text-xl font-bold text-green-600), `Sorties` (ArrowDownRight text-red-600), `Transferts` (ArrowLeftRight text-cyan-600). Comptage des mouvements dont created_at >= aujourd'hui - period jours
- Composant `AIAnalysis` en bas de page (components/ai-analysis.tsx) — Card dégradée indigo/violet, titre `Analyse IA Stratégique` (Sparkles h-5 w-5, text-indigo-700 / dark:text-indigo-400), description `Générez une analyse basée sur le CA, le bénéfice, le stock et les produits les plus vendus.`
- Bouton `Générer l'analyse` (Sparkles h-4 w-4 mr-2, bg-indigo-600 hover:bg-indigo-700 text-white) visible tant qu'aucune analyse n'est chargée; remplacé par un bouton `Régénérer` (size='sm', variant='outline', Sparkles h-3.5) une fois le texte affiché
- Rafraîchissement temps réel: useRealtimeRefresh(['product_variant','order','stock_movement']) -> fetchData(true) silencieux, débounce 400 ms
- Aucun export CSV/PDF/impression, aucun raccourci clavier, aucune sélection de lignes, aucune action par ligne

**Formulaires** (2)

- AUCUN formulaire classique, aucun champ texte, aucune validation, aucun message d'erreur de champ.
- Seuls contrôles: le groupe de 3 boutons de période (7j/30j/90j, état local `period`, valeur par défaut 30, aucune persistance), le bouton `Actualiser`, et le bouton `Générer l'analyse` / `Régénérer` (soumission d'un POST JSON sans saisie utilisateur; le corps est le payload `aiData` construit automatiquement).

**Modales / dialogs / drawers** (1)

- AUCUN modal / dialog / drawer / popover / dropdown / menu contextuel / confirmation. Aucune action destructive donc aucune confirmation.

**Recherche, filtres, tri, pagination** (5)

- Filtre temporel unique: période 7 / 30 / 90 jours, appliqué CÔTÉ CLIENT à deux blocs seulement (graphique du CA et compteurs de mouvements). Les KPI, le top produits, les ventes à crédit, la performance vendeurs et magasins ignorent la période (ils portent sur TOUTES les données renvoyées).
- Aucune recherche texte, aucun filtre par magasin/vendeur/produit, aucun sélecteur de dates personnalisé.
- Aucune pagination: troncatures fixes — top produits slice(0,10), vendeurs slice(0,8), ventes à crédit slice(0,8), magasins non tronqué; pour l'IA: ruptures slice(0,15), stock bas slice(0,15), produits sans mouvement slice(0,15).
- Tris internes non pilotables par l'utilisateur: produits par qty desc, vendeurs par revenue desc, magasins par revenue desc, ventes à crédit par payment_due_date croissante (les lignes sans échéance sont repoussées en fin via un comparateur qui renvoie 1/-1).
- Buckets du graphique: une clé par jour au format ISO yyyy-mm-dd pour les `period` derniers jours (inclus aujourd'hui); l'étiquette affichée est `date.slice(5)` -> `MM-JJ`. Une vente est rattachée à un jour via new Date(sold_at).toISOString().split('T')[0] (donc en UTC, pas en heure locale de Madagascar).

**Appels API** (8)

- GET /orders/ (via djangoClient.sales.list()) — la « vente » est dérivée des commandes: seules les commandes `statut_courant === 'LIVRE'` sont retenues, puis APLATIES ligne d'article par ligne d'article. Chaque ligne: id `{orderId}-{itemId}`, product_name = reference_name (+ ` (couleur)` si couleur !== 'Standard'), quantity = quantite, sale_price = prix_unitaire, total_price = prix_unitaire * quantite (null si prix nul), customer_name = client_nom, is_paid = true (en dur), total_profit = 0 (en dur), sold_at = updated_at || created_at
- GET /catalog/references/ (via djangoClient.products.list()) — stock total, comptage alertes, listes ruptures/stock bas/produits sans mouvement pour l'IA
- GET /catalog/movements/ (via djangoClient.movements.list()) — mouvements de stock; le client mappe movement_type sur le LIBELLÉ D'ORIGINE (Préparation de commande / Retour de commande / Annulation de commande / Commande livrée / Réception fournisseur / Ajustement manuel), created_at = timestamp. Réponse acceptée en tableau brut ou en {results: []}
- GET /users/dashboard/ — enveloppé dans `.catch(() => ({}))`: en cas d'échec, dashboardKpis = {} sans aucune erreur visible. Ses kpis (ca, total_profit, total_stock_value | stock_value, benefice_estime_stock) alimentent UNIQUEMENT le payload de l'analyse IA (pas les cartes KPI de la page)
- POST /api/ai/analyze (route Next.js locale, app/api/ai/analyze/route.ts) — proxy vers Ollama `POST {OLLAMA_BASE_URL}/api/generate` (modèle par défaut qwen3:4b, stream:false, think:false, timeout 600 000 ms). Réponse { analysis }; les balises <think>...</think> sont supprimées. En erreur: HTTP 500 + { analysis: message d'erreur en français }
- GET /users/me/ (useCurrentUser) pour isAdmin
- WS /ws/data/ pour le rafraîchissement temps réel
- Les 4 GET initiaux partent en parallèle via Promise.all

**Etats UI** (13)

- loading initial et sur clic `Actualiser` -> Skeletons: h-8 w-24 dans chaque carte KPI, h-64 w-full pour le graphique CA, h-48 w-full pour top produits / ventes à crédit / vendeurs / magasins, h-20 w-full pour le bloc mouvements
- empty top produits -> `Aucune vente enregistrée` (text-muted-foreground text-sm text-center py-8)
- empty ventes à crédit -> bloc centré CircleCheck h-8 w-8 text-green-500 + `Aucune vente impayée`
- empty vendeurs -> `Aucune vente enregistrée`
- empty magasins (admin) -> `Aucune vente enregistrée`
- empty mouvements -> pas d'état vide dédié: les 3 tuiles affichent simplement 0
- error de chargement -> AUCUN état visible (catch -> console.error seul); le /users/dashboard/ échoue silencieusement via .catch(() => ({}))
- IA idle -> bouton `Générer l'analyse`
- IA loading -> texte `Génération en cours (modèle IA local — cela peut prendre plusieurs minutes)...` (text-xs text-muted-foreground) + 4 Skeletons h-4 de largeurs 100%/90%/80%/85%
- IA success -> texte brut whitespace-pre-wrap leading-relaxed en text-gray-800 / dark:text-gray-200 + bouton `Régénérer`
- IA error -> même zone de texte mais en text-red-600 / dark:text-red-400; message serveur type `Erreur lors de la génération de l'analyse. Impossible de contacter Ollama sur {URL}...` ou `Le modèle a mis trop de temps à répondre (délai dépassé).`; erreur réseau côté client -> `Erreur réseau lors de l'appel à l'analyse IA.`
- disabled -> bouton Actualiser désactivé pendant loading; bouton Régénérer désactivé pendant loading IA
- unauthorized -> NON GÉRÉ dans la page (pas d'écran d'accès refusé)

**Details UX** (10)

- Formatage nombres: Intl.NumberFormat('fr-MG') sur Math.round(n) (pas de minimumFractionDigits explicite, contrairement au dashboard) + suffixe ` Ar` concaténé
- Couleurs KPI: CA vert (text-green-600), bénéfice émeraude, unités bleu, transactions violet (text-purple-600), stock indigo, alertes ambre (text-amber-600); l'icône de chaque KPI hérite de la couleur du titre
- Couleurs sémantiques tableaux: bénéfices toujours en text-emerald-600 font-medium, restant dû en text-red-600 font-semibold
- Badges de crédit: destructive (rouge plein) pour `En retard`, outline pour `En attente`, taille text-[10px]
- Tuiles mouvements: entrées vertes, sorties rouges, transferts cyan
- Carte IA au fond dégradé (from-indigo-50 to-purple-50, dark: from-indigo-950/20 to-purple-950/20, bordure indigo)
- Pas de toast/sonner, pas de confirmation, pas d'animation hors le spin de RefreshCw et les skeletons
- Le titre du graphique et du bloc mouvements sont dynamiques et reflètent la période sélectionnée
- Rafraîchissement WebSocket silencieux (aucun indicateur), les valeurs changent sous les yeux de l'utilisateur
- Espacement global p-6 space-y-6; les cartes Ventes à crédit / Vendeurs sont côte à côte en grid lg:grid-cols-2 gap-6

### `/settings`

- **Fichier Next.js** : `frontend/app/(app)/settings/page.tsx`
- **Groupe d'audit** : `settings-stores`
- **Cible Flutter** : lib/features/settings/settings_screen.dart
- **Etat** : PARTIAL

**Role et gating.** GATING = `const { user, isGerant, loading: userLoading } = useCurrentUser()` (/home/garrix/Dev/Smartphone/frontend/lib/auth/useCurrentUser.ts). `isGerant = role === 'admin' || role === 'magasin'`. AUCUN redirect/guard dans la page : le seul garde est le layout /home/garrix/Dev/Smartphone/frontend/app/(app)/layout.tsx qui fait `if (!djangoClient.isAuthenticated()) router.replace('/login')`. Dans la sidebar (/home/garrix/Dev/Smartphone/frontend/components/layout/sidebar.tsx) l'entree 'Paramètres' -> /settings est `superAdminOnly: true` et `isSuperAdmin = role === 'admin'` => SEUL l'admin voit le lien menu ; un role 'magasin' (pourtant isGerant) ou un employer (PREPARATEUR/LIVREUR) doit taper l'URL. Consequence Flutter : la page est accessible a tous les authentifies mais degradee. NON-GERANT (employer / PREPARATEUR / LIVREUR) : onglets Dépenses et Zones absents, tous les champs profil `disabled={!isGerant}` (photo, nom, tel, adresse), bouton Enregistrer non rendu, onglet Sécurité rendu SANS formulaire (seulement le titre + message). Textes de degradation : 'Seul le gérant peut modifier ces informations. Contactez votre gérant pour toute correction.' (profil) et 'Seul le gérant peut modifier le mot de passe. Contactez votre gérant.' (securite). Backend re-applique : PATCH /users/me/ renvoie 403 si role not in [admin, magasin] (users/views.py Myprofile.patch) ; POST /users/change-password/ idem 403 ; ecriture zones et categories = permission IsGerant.

**Objectif.** Page 'Paramètres' : profil personnel + photo, changement de mot de passe, CRUD des catégories de dépense de caisse, CRUD des zones de livraison (nom + prix + actif), et édition du nom/logo de l'entreprise (admin) ou du magasin (gérant magasin) via un modal.

**Fonctionnalites** (25)

- En-tête : h1 'Paramètres' + sous-titre 'Gérez votre profil et vos préférences'
- Composant Tabs shadcn, `defaultValue="profile"`, 4 onglets max, pas de persistance de l'onglet actif (pas d'URL, pas de localStorage)
- Onglet 1 'Mon profil' (icône User, value=profile) — toujours visible
- Onglet 2 'Sécurité' (icône Lock, value=security) — toujours visible
- Onglet 3 'Dépenses' (icône Wallet, value=depenses) — rendu UNIQUEMENT si isGerant
- Onglet 4 'Zones de livraison' (icône MapPin, value=zones) — rendu UNIQUEMENT si isGerant
- Card 'Informations personnelles' : description conditionnelle selon isGerant ('Mettez à jour vos informations' vs message de restriction)
- Aperçu photo de profil : <img> 64x64 rounded-full object-cover border si avatarPreview, sinon cercle 64x64 bordé bg-muted avec icône User grise
- Bouton 'Enregistrer' du profil : rendu seulement si isGerant, texte 'Enregistrement...' pendant saving, `disabled={saving}`
- Bloc 'Magasin' (séparateur border-t) affiché si `user.role === 'magasin' && user.shop_name` : icône Building2 + shop_name en gras dans un encadré bg-slate-50/50 + bouton outline size=sm 'Modifier' qui ouvre le Dialog
- Bloc 'Entreprise' affiché si `user.role === 'admin' && user.company_name` : même structure, icône Building2 + company_name + bouton 'Modifier'
- Card 'Changer le mot de passe' (onglet Sécurité) : le CardContent entier (donc le formulaire) est rendu seulement si isGerant
- Card 'Catégories de dépenses' (onglet Dépenses) avec description : 'Catégories proposées lors d'une saisie de sortie de caisse (Salaire, Pub, Commande stock...). Ajoutez-en, renommez ou supprimez-les selon vos besoins.'
- Sous-composant ExpenseCategoriesCrudList : compteur 'Toutes les catégories (N)', liste scrollable max-h-72 overflow-y-auto
- Ligne catégorie (mode lecture) : nom + bouton icône Pencil (passer en édition) + bouton icône Trash2 rouge (suppression IMMÉDIATE, aucune confirmation)
- Ligne catégorie (mode édition inline) : Input h-8 autoFocus + bouton 'OK' (sauver) + bouton ghost 'Annuler' (sort de l'édition sans sauver)
- Barre d'ajout catégorie en bas : Input placeholder 'Nouvelle catégorie (ex: Transport)' + bouton 'Ajouter' avec icône Plus
- Card 'Zones de livraison' (onglet Zones) avec description longue : 'Zones proposées à la création d'une commande (nom + frais de livraison). Le retrait sur place ("Récupération") reste toujours disponible séparément et n'est pas géré ici. Ajoutez-en, renommez ou changez le prix selon vos besoins — pensez à garder au moins une zone gratuite (0 Ar).'
- Sous-composant DeliveryZonesCrudList : compteur 'Toutes les zones (N)', liste scrollable max-h-96 overflow-y-auto
- Ligne zone (mode lecture) : nom (barré + muted si !actif) + Badge secondary avec le prix formaté + Switch actif/inactif (title='Zone active') + Pencil + Trash2 rouge
- Ligne zone (mode édition inline) : Input nom h-8 autoFocus + Input number min=0 w-28 placeholder 'Prix (Ar)' + bouton 'OK' + bouton ghost 'Annuler'
- Barre d'ajout zone en bas : Input nom flex-1 placeholder 'Nouvelle zone (ex: Zone 4)' + Input number min=0 w-32 placeholder 'Prix (Ar)' + bouton 'Ajouter' (icône Plus)
- Toggle du Switch zone : PATCH immédiat de `actif` puis rechargement de la liste, SANS toast de succès (silencieux)
- Aucune recherche, aucun tri, aucun filtre, aucune pagination sur les listes catégories/zones
- Aucun tableau (pas de <table>) : tout est en cartes/listes de lignes flex

**Formulaires** (10)

- FORMULAIRE 1 — 'Informations personnelles' (handleUpdateProfile, onglet Profil). Champs : (a) Photo de profil : <input type=file accept="image/*">, disabled si !isGerant, prévisualisation via URL.createObjectURL, pas de contrainte de taille/format côté client ; (b) Email : input `value={user?.email}` disabled + classe bg-muted + aide 'L'email ne peut pas être modifié' — non soumis ; (c) Rôle : lecture seule, Badge outline, pas un input ; (d) Nom complet (id=fullName, placeholder 'Votre nom', disabled si !isGerant, PAS de required) ; (e) Téléphone (id=phone, placeholder '+261 XX XXX XX XX', disabled si !isGerant, pas de required, pas de masque, pas de validation) ; (f) Adresse (id=adresse, placeholder 'Ex: Lot II A 45, Antanimena, Antananarivo', disabled si !isGerant, pas de required). Validation client : AUCUNE (on peut soumettre des champs vides). Soumission : PATCH JSON {full_name, phone, adresse} puis, si un fichier avatar a été choisi, second appel PATCH multipart {photo} et `setAvatarFile(null)`. Succès : toast.success('Profil mis à jour'), formulaire NON réinitialisé, PAS de reload, l'aperçu reste l'object URL local. Échec : toast.error(err.message || 'Erreur lors de la mise à jour'). Bouton disabled pendant `saving`.
- FORMULAIRE 2 — 'Changer le mot de passe' (handleChangePassword, onglet Sécurité, rendu si isGerant). Champs : (a) 'Mot de passe actuel' id=oldPw type=password placeholder '••••••••' required ; (b) 'Nouveau mot de passe' id=newPw type=password placeholder '••••••••' required minLength=6 ; (c) 'Confirmer le mot de passe' id=confirmPw type=password placeholder '••••••••' required. Validations client (avant appel) : si newPassword !== confirmPassword -> toast.error('Les mots de passe ne correspondent pas') et abandon ; si newPassword.length < 6 -> toast.error('Le mot de passe doit contenir au moins 6 caractères') et abandon. Pas de message d'erreur inline sous les champs : tout passe par des toasts. Soumission : POST /users/change-password/. Succès : toast.success('Mot de passe changé avec succès') + reset des 3 champs à ''. Échec : toast.error(err.message || 'Erreur lors du changement de mot de passe'). Bouton 'Changer le mot de passe' -> 'Changement...' et disabled pendant changingPw. Aucune déconnexion/relogin après changement.
- FORMULAIRE 3 — Modal 'Modifier l'entreprise' / 'Modifier le magasin' (handleUpdateDetails). Champs : (a) Nom (label et placeholder conditionnels : "Nom de l'entreprise" si role=admin sinon 'Nom du magasin' ; bound à companyName ou shopName selon le rôle) avec attribut `required` ; (b) Logo : <input type=file accept="image/*"> (label "Logo de l'entreprise" ou 'Logo du magasin'), optionnel, prévisualisation 80x80 object-contain rounded-md border centrée après sélection. Soumission : FormData -> si role=admin : company_name + logo ; si role=magasin : shop_name + shop_logo ; AUCUN champ envoyé pour les autres rôles (FormData vide -> requête inutile). PATCH multipart /users/me/. Succès : toast.success('Informations mises à jour avec succès'), fermeture du modal, puis `window.location.reload()` (rechargement complet de la page — à traduire en Flutter par un refresh du user courant). Échec : toast.error(err.message || 'Erreur lors de la mise à jour'). Bouton submit : 'Enregistrer' / spinner Loader2 + 'Enregistrement...', disabled pendant updatingDetails ; bouton 'Annuler' outline qui ferme le modal sans reset des champs.
- MINI-FORMULAIRE — Ajout catégorie de dépense (ExpenseCategoriesCrudList.addCategory). 1 champ texte. Validation : `if (!newName.trim()) return;` — abandon SILENCIEUX, aucun toast, aucun message d'erreur. Envoi du nom trimmé. Succès : toast.success('Catégorie ajoutée') + vidage du champ + rechargement de la liste. Échec : toast.error(err.message || 'Erreur').
- MINI-FORMULAIRE — Renommage catégorie (saveEdit). 1 champ inline. Validation : `if (!editingId || !editingName.trim()) return;` silencieux. Succès : toast.success('Catégorie renommée'), sortie du mode édition, reload liste. Échec : toast.error(err.message || 'Erreur').
- ACTION — Suppression catégorie (removeCategory) : DELETE direct au clic sur la corbeille, AUCUNE boîte de confirmation. Succès : toast.success('Catégorie supprimée') + reload. Échec : toast.error(err.message || 'Erreur lors de la suppression').
- MINI-FORMULAIRE — Ajout zone (addZone). Champs : nom (texte) + prix (number, min=0). Validation : `if (!newName.trim()) return;` silencieux (le prix n'est PAS validé). Prix converti par `Number(newPrix) || 0` -> vide ou non numérique = 0 Ar. Succès : toast.success('Zone ajoutée') + vidage des deux champs + reload. Échec : toast.error(err.message || 'Erreur').
- MINI-FORMULAIRE — Édition zone (saveEdit). Champs : nom + prix number min=0. Validation : nom trimmé non vide sinon abandon silencieux ; prix `Number(editingPrix) || 0`. Envoie PATCH {nom, prix} (le champ actif n'est PAS renvoyé ici). Succès : toast.success('Zone mise à jour') + sortie d'édition + reload. Échec : toast.error(err.message || 'Erreur').
- ACTION — Toggle actif d'une zone (toggleActive) : PATCH {actif: !z.actif}, aucun toast de succès, seulement un reload de la liste. Échec : toast.error(err.message || 'Erreur').
- ACTION — Suppression zone (removeZone) : DELETE direct, AUCUNE confirmation. Succès : toast.success('Zone supprimée') + reload. Échec : toast.error(err.message || 'Erreur lors de la suppression'). ATTENTION : côté serveur, une zone déjà utilisée est seulement désactivée -> après le toast 'Zone supprimée' la zone réapparaît barrée/inactive dans la liste.

**Modales / dialogs / drawers** (5)

- Dialog unique (shadcn Dialog, `max-w-md`) piloté par `modalOpen` : titre "Modifier l'entreprise" si role=admin sinon 'Modifier le magasin' ; description "Mettez à jour le nom et le logo de votre entreprise" / "...de votre magasin". Ouvert par les boutons 'Modifier' des blocs Magasin/Entreprise de l'onglet Profil. Contient le formulaire nom + logo + preview, boutons Annuler / Enregistrer.
- Édition inline (PAS un dialog) des catégories : la ligne se transforme en Input + OK + Annuler
- Édition inline (PAS un dialog) des zones : la ligne se transforme en Input nom + Input prix + OK + Annuler
- AUCUN dialog de confirmation de suppression (ni pour les catégories, ni pour les zones) — le clic sur la corbeille supprime directement
- Toasts via `sonner` (composant global <Toaster/>)

**Recherche, filtres, tri, pagination** (3)

- Aucune recherche, aucun filtre, aucun tri, aucune pagination sur cette page
- Les listes sont simplement scrollables : catégories max-h-72, zones max-h-96 (overflow-y-auto)
- Les compteurs 'Toutes les catégories (N)' / 'Toutes les zones (N)' sont dérivés du `.length` local du tableau

**Appels API** (13)

- GET /users/me/ — chargé par useCurrentUser au montage ; fournit id, email, role, full_name, phone, adresse, photo, company_name, logo, shop_name, shop_logo, magasin_id, position, commande_role, is_company_owner
- PATCH /users/me/ (JSON, via djangoClient.users.updateProfile) — met à jour full_name, phone, adresse. Backend: 403 si role hors [admin, magasin]
- PATCH /users/me/ (multipart FormData, via djangoClient.patchFormData) — upload du champ `photo` (avatar) quand un fichier a été sélectionné
- PATCH /users/me/ (multipart FormData) — modal entreprise/magasin : envoie `company_name` (+ `logo`) si role=admin, ou `shop_name` (+ `shop_logo`) si role=magasin
- POST /users/change-password/ — body {old_password, new_password}. Backend valide : champs requis (400 'Champs requis manquants'), ancien mot de passe correct (400 'Mot de passe actuel incorrect'), longueur >= 6 (400), et role in [admin, magasin] (403)
- GET /users/caisse/categories/ — liste des catégories de dépense (djangoClient.caisse.categories.list), appelée seulement si isGerant
- POST /users/caisse/categories/ — body {nom}
- PATCH /users/caisse/categories/{id}/ — body {nom}
- DELETE /users/caisse/categories/{id}/
- GET /orders/delivery-zones/ — liste des zones (djangoClient.zones.list), appelée seulement si isGerant. Retourne {id, code, nom, prix, actif}
- POST /orders/delivery-zones/ — body {nom, prix}
- PATCH /orders/delivery-zones/{id}/ — body partiel {nom?, prix?, actif?}
- DELETE /orders/delivery-zones/{id}/ — côté serveur : si la zone est déjà utilisée par une commande (Order.livraison_zone == zone.code) elle n'est PAS supprimée, elle est passée à actif=False et l'API renvoie l'objet zone (200) au lieu d'un 204

**Etats UI** (11)

- LOADING global : `if (userLoading)` -> conteneur p-6 space-y-4 avec 3 <Skeleton className="h-24 w-full"> (pas de spinner)
- LOADING listes catégories/zones : AUCUN état de chargement — la liste est simplement vide puis se remplit
- ERROR chargement catégories/zones : swallow total `.catch(() => {})` — aucun toast, aucun message, la liste reste vide (indiscernable d'un vrai vide)
- EMPTY catégories : 'Aucune catégorie.' centré, text-sm text-muted-foreground, py-4
- EMPTY zones : 'Aucune zone.' même style
- SUBMITTING profil : bouton 'Enregistrement...' + disabled
- SUBMITTING mot de passe : bouton 'Changement...' + disabled
- SUBMITTING modal : Loader2 animate-spin + 'Enregistrement...' + disabled
- UNAUTHORIZED / non-gérant : pas d'écran 403 — dégradation en lecture seule (champs disabled, onglets masqués, formulaire mot de passe non rendu, bouton Enregistrer non rendu) + textes explicatifs dans les CardDescription
- DISABLED : tous les inputs profil quand !isGerant ; input file avatar disabled ; Input number des quantités non applicable ici
- Pas d'état 'success' persistant : seulement des toasts éphémères

**Details UX** (11)

- Toasts sonner : succès 'Profil mis à jour', 'Mot de passe changé avec succès', 'Informations mises à jour avec succès', 'Catégorie ajoutée/renommée/supprimée', 'Zone ajoutée', 'Zone mise à jour', 'Zone supprimée' ; erreurs génériques 'Erreur', 'Erreur lors de la mise à jour', 'Erreur lors de la suppression', 'Erreur lors du changement de mot de passe'
- Badge outline pour le rôle avec libellés FR : admin -> 'Administrateur', magasin -> 'Gérant de magasin', employer -> 'Commercial' (map `roleLabel`, fallback = valeur brute du rôle)
- Badge secondary pour le prix de zone, format `arFmt` = `new Intl.NumberFormat('fr-MG').format(Math.round(Number(n||0)))` + ' Ar' (arrondi à l'entier, séparateur de milliers FR)
- Zone inactive : nom en `text-muted-foreground line-through` (barré grisé) mais reste dans la liste
- Icône corbeille en `text-red-500` (action destructive), icône crayon en variant ghost neutre
- Bloc Magasin/Entreprise : encadré `bg-slate-50/50` avec icône Building2
- Après édition du nom/logo entreprise-magasin : rechargement complet de la page (`window.location.reload()`) — perte de l'onglet actif, retour sur 'Mon profil'
- Aperçu image via URL.createObjectURL (pas d'upload immédiat : l'image ne part qu'à la soumission du formulaire)
- Pas de temps réel (aucun useRealtimeRefresh sur cette page) : les listes ne se rafraîchissent que sur action locale
- Layout : padding p-6, espacement space-y-6, formulaires contraints en `max-w-md`
- Le Switch de zone a un `title="Zone active"` (tooltip natif navigateur)

### `/stores`

- **Fichier Next.js** : `frontend/app/(app)/stores/page.tsx`
- **Groupe d'audit** : `settings-stores`
- **Cible Flutter** : lib/features/stores/stores_screen.dart
- **Etat** : PARTIAL

**Role et gating.** GATING = `const { user, isAdmin } = useCurrentUser()` ; `isAdmin === (role === 'admin')`. AUCUN guard/redirect dans la page (pas de vérification isAdmin au rendu global, pas d'écran 403) : le seul garde est le layout (`isAuthenticated` sinon /login). Dans la sidebar l'entrée 'Magasins' -> /stores est `superAdminOnly: true` (isSuperAdmin = role admin) => seul l'admin voit le lien. Un gérant magasin ou un employer qui tape l'URL voit la page mais SANS : bouton 'Créer un magasin', boutons Transfert et Édition sur les cartes, et sans l'appel profit (/users/magasins/overview/ est IsAdmin). Il verra tout de même la/les carte(s) de son propre magasin car /users/magasins/users/ et /users/magasins/stats/ filtrent par rôle côté serveur (admin -> tous ses magasins ; magasin -> le sien ; employer -> celui de son EmployerProfile ; autre rôle -> 403 'Role not supported'). Le composant de transfert est lui aussi réservé de fait à l'admin (backend TransferProductsView : seul rôle avec visibilité multi-magasins).

**Objectif.** Page 'Magasins' : grille de cartes, une par magasin de la société, avec le gérant, les KPI (produits/unités, valeur de stock, ventes livrées, profit), les 3 premiers employés ; l'admin peut créer un magasin (+ son compte gérant), éditer nom/logo d'un magasin et transférer des produits d'un magasin vers un autre.

**Fonctionnalites** (21)

- En-tête : h1 'Magasins' (text-2xl sm:text-3xl) + sous-titre dynamique '{stores.length} magasin(s)'
- Bouton 'Créer un magasin' (DialogTrigger) — rendu UNIQUEMENT si isAdmin
- Bouton 'Actualiser' (variant outline, icône RefreshCw) — toujours visible, `onClick={() => fetchData()}` (rechargement NON silencieux : réaffiche les skeletons)
- L'icône RefreshCw tourne (`animate-spin`) tant que `loading` est vrai
- Grille responsive de cartes : 1 colonne / md:2 / lg:3, gap-4 sm:gap-6
- Carte magasin — en-tête : logo (img 20x20 rounded-full object-cover) si `store.shop_logo`, sinon icône Store ; nom `shop_name` tronqué (truncate)
- Carte magasin — bouton icône ArrowLeftRight (transfert de produits depuis ce magasin) : isAdmin uniquement
- Carte magasin — bouton icône Edit (modifier nom/logo) : isAdmin uniquement
- Carte magasin — bloc gérant (rendu seulement si `store.manager` existe) : full_name en font-medium + email en text-sm text-muted-foreground, séparé par border-b. NB : `manager` côté serveur = l'ADMIN de la société (mag.admin), pas le compte role='magasin'
- Carte magasin — 4 tuiles KPI en grid 2 colonnes : 'Produits', 'Stock', 'Ventes', 'Profit'
- Tuile 'Produits' : texte composite '{total_stock_quantity} unité(s) sur {total_products} produits' (deux nombres formatés fr-FR)
- Tuile 'Stock' : `total_stock_value` en Ariary
- Tuile 'Ventes' : `total_sold_value` en Ariary (= somme des `total_a_payer` des commandes au statut LIVRE)
- Tuile 'Profit' : `profit`, fond vert (bg-green-50 / dark:bg-green-950/30) et texte vert (text-green-700 / dark:text-green-400)
- Carte magasin — bloc employés : icône Users + 'Employés ({store.employers?.length || 0})'
- Liste des employés LIMITÉE aux 3 premiers (`employers?.slice(0, 3)`) — aucun 'voir plus', aucune pagination : les employés au-delà du 3e sont invisibles alors que le compteur les inclut
- Chaque employé : nom (full_name) à gauche + Badge outline à droite : 'Actif' si `is_confirmed` sinon 'Attente'
- Rafraîchissement TEMPS RÉEL : `useRealtimeRefresh(['product_variant', 'order'], () => fetchData(true))` — WebSocket DataSyncContext, debounce 400 ms, rechargement silencieux (ni skeleton ni toast)
- Aucun tableau (<table>) : uniquement des cartes
- Aucun tri, aucune recherche, aucun filtre, aucune pagination sur la liste des magasins
- Aucun export

**Formulaires** (3)

- FORMULAIRE 1 — 'Nouveau magasin' (handleRegisterStore, dans le Dialog déclenché par 'Créer un magasin'). Champs, TOUS sans attribut required et SANS aucune validation client : (a) 'Nom du magasin' (texte, state storeName) ; (b) 'Nom du gérant' (texte, state managerName) ; (c) 'Email' (type=email, state managerEmail — sert à la fois d'email ET de username) ; (d) 'Mot de passe' (type=password, state managerPassword, pas de longueur minimale, pas de confirmation). Bouton submit pleine largeur : 'Créer' / (Loader2 animate-spin + 'Création...'), disabled pendant submittingStore. Soumission : register(role 'magasin', extraData {full_name: managerName, shop_name: storeName, admin_email: user?.email}) puis approveUser(response.id). Succès : toast.success('Magasin créé.'), reset des 4 champs à '', fermeture du dialog, fetchData(). Échec : toast.error(err?.message || 'Erreur lors de la création.'). Aucun message d'erreur inline : tout en toast. RISQUE PORTAGE : si le register réussit mais approveUser échoue, l'exception coupe le flux -> toast d'erreur alors que le magasin EXISTE déjà (les champs ne sont pas vidés, le dialog reste ouvert).
- FORMULAIRE 2 — 'Modifier le magasin' (handleUpdateStore, Dialog max-w-md). Pré-rempli par handleStartEditStore : editStoreName = store.shop_name, preview = store.shop_logo. Champs : (a) 'Nom du magasin' (texte, `required`) ; (b) 'Logo du magasin' (<input type=file accept="image/*">, optionnel) avec prévisualisation 80x80 object-contain rounded-md border, centrée — affichée aussi pour le logo EXISTANT à l'ouverture. Soumission : FormData {shop_name, shop_logo?} -> PATCH /users/magasins/{magasin_id}/. Succès : toast.success('Magasin mis à jour avec succès'), fermeture du dialog, fetchData() (rechargement NON silencieux -> skeletons). Échec : toast.error(err.message || 'Erreur lors de la mise à jour'). Bouton pleine largeur 'Enregistrer' / Loader2 + 'Enregistrement...', disabled pendant submittingEditStore. Pas de bouton Annuler explicite (fermeture par la croix/overlay du Dialog).
- FORMULAIRE 3 — Transfert de produits (composant partagé TransferProductsPanel dans TransferProductsDialog). Voir sharedComponents pour le détail complet : recherche produit, quantités clampées, panier, recherche + sélection du magasin de destination, submit 'Transférer N unité(s)'. Validation : (a) si pas de destination OU panier vide -> toast.error('Sélectionnez des produits et un magasin de destination') ; (b) après filtrage, si aucun item n'a de variantId -> toast.error('Sélectionnez au moins une couleur à transférer') (le state submittingTransfer reste bloqué à true jusqu'au finally). Succès : toast.success('Transfert effectué') puis fermeture du dialog + fetchData() de la page Magasins. Échec : toast.error('Erreur lors du transfert').

**Modales / dialogs / drawers** (5)

- Dialog 'Nouveau magasin' (isRegisterDialogOpen) — DialogTrigger = bouton 'Créer un magasin', titre 'Nouveau magasin', description 'Ajouter un magasin', contient le formulaire de création. Rendu seulement si isAdmin.
- Dialog 'Modifier le magasin' (isEditStoreDialogOpen, max-w-md) — titre 'Modifier le magasin', description 'Modifier le nom et le logo du magasin.', ouvert par le bouton icône Edit d'une carte.
- Dialog 'Transfert de produits' (TransferProductsDialog, isTransferDialogOpen) — plein écran quasi total : w-[97vw] max-w-[97vw] h-[95vh] max-h-[95vh], titre 'Transfert de produits', description 'Depuis {shop_name} — sélectionnez des produits (et leurs variantes) et choisissez le magasin de destination.'. Ouvert par le bouton icône ArrowLeftRight. À la fermeture, `transferSourceStore` est remis à null (handleTransferDialogChange) et le panneau est remonté via `key={sourceStore.magasin_id}` -> état interne (panier, destination, recherche) totalement réinitialisé quand on change de magasin source.
- AUCUNE confirmation de suppression (aucune suppression de magasin n'est exposée sur cette page)
- Toasts sonner globaux

**Recherche, filtres, tri, pagination** (4)

- Aucun filtre / tri / recherche / pagination sur la liste des magasins elle-même
- Bouton 'Actualiser' = rechargement manuel complet (loading = true, skeletons réaffichés)
- Rafraîchissement automatique silencieux déclenché par les événements WebSocket 'product_variant' et 'order' (debounce 400 ms)
- Dans le dialog de transfert : recherche produit (Input, filtre client insensible à la casse sur `name` OU `reference`) et recherche magasin de destination (filtre client sur `shop_name`, avec exclusion du magasin source)

**Appels API** (8)

- GET /users/magasins/users/ — liste principale. Retourne pour chaque magasin : {magasin_id, shop_name, shop_logo (URL absolue), manager: {id, full_name, email, phone, adresse, photo, is_confirmed, role, last_login_at, last_logout_at} | null, employers: [{id, full_name, email, phone, adresse, photo, is_confirmed, position, role, commande_role, last_login_at, last_logout_at}], company_users: [...] }. Portée filtrée par rôle côté serveur (admin/magasin/employer, sinon 403).
- GET /users/magasins/stats/ — statistiques par magasin : {magasin_id, shop_name, total_products, total_stock_quantity, total_stock_value, total_sold_value, profit}. Appel enveloppé dans un try/catch : en cas d'échec -> console.error seulement, stats par défaut à 0, AUCUN toast.
- GET /users/magasins/overview/ (via djangoClient.transfers.getProfitByMagasins(), qui remappe `res.magasins` en `profit_by_magasins`) — APPELÉ SEULEMENT SI isAdmin. Retourne par magasin : {magasin_id, shop_name, total_stock_value, total_profit, number_of_products, number_of_sales_week, number_of_employees}. Permission backend : IsAuthenticated + IsAdmin. Échec -> console.error, pas de toast.
- POST /users/register/ (djangoClient.auth.register) — création du compte gérant du nouveau magasin : body {email, username (= email), password, role: 'magasin', full_name, shop_name, admin_email: user?.email}. Le backend crée le CustomUser + le MagasinProfile (user=gérant, admin=admin correspondant à admin_email, shop_name) et partage l'accès à tous les co-admins de la société. Erreur possible : 400 {admin_email: 'Administrateur introuvable avec cet email.'}
- PUT /users/approve/{id}/ (djangoClient.auth.approveUser) — appelé immédiatement après le register si `response?.id`, pour confirmer le compte gérant (is_confirmed=true)
- PATCH /users/magasins/{magasin_id}/ (multipart FormData via patchFormData) — édition du magasin : shop_name (+ shop_logo si un fichier est choisi). Backend MagasinViewSet.partial_update ignore un shop_logo de type string (seul un vrai fichier est accepté).
- POST /users/transfer/products/ (djangoClient.transfers.transfer) — via le dialog de transfert : body {source_magasin_id, destination_magasin_id, items: [{variant_id, quantity}]}
- GET catalogue références (djangoClient.products.list({magasin_id})) — à l'intérieur du panneau de transfert, pour lister les produits du magasin source ; filtrage client supplémentaire `Number(p.magasin) === Number(magasinId)`

**Etats UI** (13)

- LOADING initial / après 'Actualiser' / après édition-création : grille de 3 <Skeleton className="h-48 rounded-xl"> dans la même grille responsive
- LOADING silencieux (WebSocket) : aucun indicateur, les données se remplacent en place
- ERROR chargement principal : toast.error('Erreur lors du chargement.') uniquement si `!silent` ; `stores` reste à sa valeur précédente (souvent []) ; pas d'écran d'erreur ni de bouton Réessayer autre que 'Actualiser'
- ERROR stats (/magasins/stats/) : silencieuse (console.error) -> KPI affichés à 0 Ar / 0 produits
- ERROR profit (/magasins/overview/) : silencieuse -> repli sur `storeStats.profit` puis 0
- EMPTY : AUCUN état vide dédié — si aucun magasin, la grille est vide et le sous-titre affiche '0 magasin(s)'
- SUBMITTING création : bouton Loader2 + 'Création...' disabled
- SUBMITTING édition : bouton Loader2 + 'Enregistrement...' disabled
- SUBMITTING transfert : bouton Loader2 + 'Transfert en cours...' disabled
- DISABLED (transfert) : bouton submit disabled si panier vide OU pas de destination ; Input quantité et bouton 'Sélectionner' disabled si déjà au panier (`inCart`) ou stock <= 0
- UNAUTHORIZED : pas d'écran dédié — les actions admin ne sont simplement pas rendues ; un employer verra la carte de son magasin sans aucun bouton d'action
- Bloc gérant absent si `store.manager` est null (cellule conditionnelle)
- Logo magasin absent -> icône Store en repli (en-tête de carte ET liste des destinations du transfert)

**Details UX** (11)

- formatNumber = `Intl.NumberFormat('fr-FR')` (utilisé pour unités et nb de produits)
- formatCurrency = `Intl.NumberFormat('fr-MG')` + ' Ar' (utilisé pour Stock / Ventes / Profit) — deux locales différentes coexistent dans la même carte
- Tuile Profit visuellement distinguée : fond vert clair + texte vert foncé, adaptée dark mode
- Badges employés : 'Actif' (is_confirmed=true) vs 'Attente' (false), tous deux en variant outline — MÊME couleur, seul le libellé change
- Icône RefreshCw en rotation continue pendant le chargement
- Toasts : 'Magasin créé.', 'Magasin mis à jour avec succès', 'Transfert effectué', 'Erreur lors du chargement.', 'Erreur lors de la création.', 'Erreur lors de la mise à jour', 'Erreur lors du transfert'
- Temps réel : la page se remet à jour toute seule à la moindre création/modif de commande ou de variante de produit dans la société (events 'order' et 'product_variant'), sans feedback visuel
- Layout : container mx-auto px-4 sm:px-6 py-6 sm:py-8 space-y-6, en-tête flex-col en mobile / flex-row en sm+
- Boutons d'action de carte en `size="icon"` variant outline, groupés à droite du titre, `shrink-0`
- Dans le panneau de transfert : ordre de tri des variantes par taille selon SIZE_ORDER ['XS','S','M','L','XL','2XL','3XL','4XL'] (tailles inconnues renvoyées en fin, index 99)
- Dans le panneau de transfert : Badge secondary '{N} unité(s)' comme compteur de panier ; libellé de variante = 'taille / couleur' joint par ' / ', ou 'Standard' si les deux sont vides

### `/suppliers`

- **Fichier Next.js** : `frontend/app/(app)/suppliers/page.tsx`
- **Groupe d'audit** : `suppliers-transfers`
- **Cible Flutter** : lib/features/suppliers/suppliers_screen.dart + supplier_order_*.dart
- **Etat** : PARTIAL

**Role et gating.** GERANT (= admin OU magasin). ATTENTION: AUCUN gating dans la page elle-meme — pas de useCurrentUser, pas de guard, pas d'ecran 'Acces refuse'. Le gating est uniquement (1) cote menu: components/layout/sidebar.tsx, entree { label: 'Fournisseurs', href: '/suppliers', icon: Truck, adminOnly: true } filtree par `if (item.adminOnly && !isAdminOrSuperAdmin) return false` ou isAdminOrSuperAdmin = role==='admin' || role==='magasin' (donc Gerant); pendant `loading` du user la sidebar affiche tout sauf superAdminOnly; (2) cote backend: SupplierOrderViewSet.permission_classes = [IsGerant] (/home/garrix/Dev/Smartphone/suppliers/views.py) — un PREPARATEUR/LIVREUR qui tape l'URL a la main voit la page se rendre puis un toast d'erreur 403. (3) Le layout /app/(app)/layout.tsx redirige vers /login si !djangoClient.isAuthenticated(). En Flutter il FAUT ajouter le guard manquant (role admin|magasin) ou reproduire le comportement (page visible + toast erreur).

**Objectif.** Module Commandes Fournisseur (§7.6 du cahier des charges): lister les commandes fournisseur, en creer de nouvelles avec calcul automatique du cout de revient reel (marchandise + fret/import + douane), consulter le detail d'une commande, et la receptionner (ce qui declenche l'entree en stock par variante).

**Fonctionnalites** (16)

- En-tete: titre h1 'Fournisseurs' avec icone Truck (lucide, h-6 w-6) + sous-titre gris 'Coût de revient réel : marchandise + fret/import + douane (§7.6 du cahier des charges).'
- Bouton icone 'Rafraichir' (variant=outline, size=icon, icone RefreshCw) -> appelle fetchOrders() en mode NON silencieux (affiche le skeleton)
- Bouton principal '+ Commande fournisseur' (icone Plus) -> ouvre le dialog CreateSupplierOrderDialog (setCreateOpen(true))
- Tableau des commandes dans une Card (CardContent p-0), wrapper overflow-x-auto (scroll horizontal sur mobile)
- Colonne 'N°' : o.numero, en font-medium (format backend: SUP-<magasinId>-<YYYYMMDD>-<0001>, unique, non editable)
- Colonne 'Description' : o.description, affiche '-' si vide/null
- Colonne 'Coût total' : fmt(o.cout_total) -> nombre arrondi, format fr-MG, suffixe ' Ar'
- Colonne 'Coût unitaire' : fmt(o.cout_unitaire) -> meme format
- Colonne 'Statut' : Badge avec libelle traduit et couleur selon STATUT_COLOR
- Colonne 'Action' (alignee a droite) : bouton 'Réceptionner' (size=sm, icone PackageCheck) affiche UNIQUEMENT si o.statut !== 'RECU'. Cellule vide si statut RECU.
- Le bouton Réceptionner fait e.stopPropagation() pour ne pas declencher l'ouverture du dialog de detail de la ligne
- Ligne de tableau entiere cliquable (className='cursor-pointer', onClick={() => setDetail(o)}) -> ouvre le dialog de detail
- Aucun tri, aucun filtre, aucune recherche, aucune pagination sur cette liste — l'ordre vient du backend (Meta.ordering = ['-created_at'], donc la plus recente en premier)
- Rafraichissement temps reel: useRealtimeRefresh(['supplier_order'], () => fetchOrders(true)) — refetch SILENCIEUX (sans skeleton) sur evenement WebSocket model='supplier_order', debounce 400 ms (lib/hooks/useRealtimeRefresh.ts + lib/contexts/DataSyncContext.tsx)
- Action receive(order): POST receive -> toast succes -> fetchOrders() (NON silencieux, skeleton) -> setDetail(null) (ferme le detail s'il etait ouvert)
- Aucune action de suppression/edition de commande (le backend n'autorise que get/post/head/options: http_method_names = ['get','post','head','options'])

**Formulaires** (20)

- FORMULAIRE 'Nouvelle commande fournisseur' (composant local CreateSupplierOrderDialog, meme fichier, lignes 170-348). Sous-titre du dialog: '§7.6 — coût de revient réel calculé automatiquement.'
- Champ 'Description' — Textarea, state `description`, placeholder 'Ex: réappro coques Samsung — lot Chine mars'. Optionnel (backend: required=False, allow_blank=True, default=''). Aucune validation front.
- Champ 'Prix fournisseur (Ar)' — Input type=number, state `prixFournisseur`, valeur initiale '0'. Aucun min, aucune validation front. Backend: DecimalField(max_digits=14, decimal_places=2, default=0).
- Champ 'Fret/import (Ar)' — Input type=number, state `fretImport`, valeur initiale '0'. Aucune validation front.
- Champ 'Douane (Ar)' — Input type=number, state `douane`, valeur initiale '0'. Aucune validation front. (les 3 champs prix sont dans une grid-cols-2, donc Douane occupe seule la 3e cellule)
- SOUS-BLOC 'Ajouter une ligne' (encadre, arrondi, fond bg-muted/30) contenant 5 controles:
- - Select 'Marque' (Label xs muted 'Marque', placeholder 'Marque') alimente par GET /catalog/brands/ ; onValueChange remet variantId a '' ; AUCUNE option 'Toutes' -> impossible de deselectionner une marque une fois choisie
- - Select 'Catégorie' (placeholder 'Catégorie') alimente par GET /catalog/categories/ ; onValueChange remet variantId a '' ; AUCUNE option 'Toutes' -> non reinitialisable
- - Input 'Rechercher' (Label xs 'Rechercher', placeholder 'Rechercher une référence ou couleur…'), state `variantSearch` — filtre CLIENT (lowercase, includes) sur le libelle '<brand_name> <reference_name> (<couleur>)'
- - Select 'Couleur' (placeholder 'Couleur'), state `variantId` — liste plate de TOUTES les variantes des references chargees. Si aucun resultat: affiche un texte muted 'Aucun résultat' a la place des items
- - Input 'Quantité' type=number min=1 placeholder 'Ex: 10', state `quantite`
- - Bouton 'Ajouter' (type=button, variant=secondary, size=sm, icone Plus) -> addLine()
- VALIDATIONS de addLine(): si !variantId -> toast.error('Choisissez une couleur') ; si Number(quantite) falsy ou < 1 -> toast.error('Quantité invalide') ; si l'option n'est pas retrouvee -> return silencieux. Succes: ajoute {key: `${variantId}-${Date.now()}`, variant_id, label, quantite} a `lines` puis vide variantId et quantite (les filtres marque/categorie/recherche restent).
- LISTE DES LIGNES AJOUTEES (affichee seulement si lines.length > 0): une ligne par item, encadre arrondi, texte '<label> x<quantite>' a gauche + bouton icone ghost avec Trash2 rouge (text-red-500) a droite -> supprime par INDEX (setLines(prev => prev.filter((_, i) => i !== idx))). Les doublons de la meme variante sont autorises (cle unique via Date.now()).
- RECAPITULATIF (bordure haute): 'Coût total (<totalQty> u.)' -> fmt(coutTotal) en font-medium ; 'Coût unitaire estimé' -> fmt(coutUnitaire) en font-medium. Calculs LOCAUX: totalQty = somme des quantites ; coutTotal = Number(prixFournisseur||0) + Number(fretImport||0) + Number(douane||0) ; coutUnitaire = totalQty > 0 ? coutTotal / totalQty : 0.
- FOOTER: bouton 'Annuler' (variant=outline) -> onOpenChange(false) SANS reset (le reset se fait a la reouverture) ; bouton 'Créer' -> submit(), disabled={submitting}, libelle 'Création…' pendant l'envoi.
- VALIDATION de submit(): si lines.length === 0 -> toast.error('Ajoutez au moins une ligne') et arret. Sinon POST /suppliers/orders/ avec {description, prix_fournisseur, fret_import, douane, lines: [{product_variant, quantite}]}.
- APRES SOUMISSION OK: toast.success('Commande fournisseur créée') puis onCreated() -> setCreateOpen(false) + fetchOrders(). APRES ERREUR: toast.error(err.message || 'Erreur'), le dialog RESTE ouvert et les champs sont conserves.
- RESET a l'ouverture (useEffect sur `open`): description='', prixFournisseur='0', fretImport='0', douane='0', lines=[], variantId='', quantite='', variantSearch='', filterBrandId='', filterCategoryId='' + rechargement des marques et categories.
- ATTENTION: aucun champ 'magasin' n'est envoye. Le backend resolve_magasin_for_request() prend l'unique magasin accessible ; un admin avec PLUSIEURS magasins recoit une 400 'magasin_id: Ce champ est requis (plusieurs magasins accessibles).' affichee en toast. A prevoir en Flutter (selecteur de magasin).

**Modales / dialogs / drawers** (4)

- Dialog 'Detail commande fournisseur' — ouvert au clic sur une ligne du tableau (open={!!detail}), fermeture via onOpenChange -> setDetail(null). Largeur max-w-lg. Titre: 'Commande fournisseur <numero>'. Description: detail.description (peut etre vide). Contenu: grille 2 colonnes avec 'Prix fournisseur' / 'Fret/import' / 'Douane' (chacun fmt()) ; ligne separee par bordure haute 'Coût total (<total_qty> u.)' en font-medium ; ligne 'Coût unitaire' ; section 'Lignes' listant chaque ligne '<reference_name> (<couleur>) x<quantite>' a gauche et 'Marge unitaire: <fmt(marge_unitaire)>' a droite (marge_unitaire = prix_vente de la reference - cout_unitaire_calcule, calcule cote backend). Footer conditionnel: bouton 'Réceptionner (entrée stock)' (icone PackageCheck) affiche UNIQUEMENT si detail.statut !== 'RECU'.
- Dialog 'Nouvelle commande fournisseur' (CreateSupplierOrderDialog) — max-w-lg, max-h-[90vh], overflow-y-auto (scroll interne). Voir la section forms pour le detail complet.
- Dropdowns (Select shadcn/Radix) dans le dialog de creation: 'Marque', 'Catégorie', 'Couleur' — 3 popovers de selection.
- Aucun dialog de confirmation avant la reception: le clic sur 'Réceptionner' declenche immediatement l'appel API (irreversible cote backend: statut passe a RECU, mouvements de stock ENTREE crees).

**Recherche, filtres, tri, pagination** (3)

- Aucun filtre / tri / recherche / pagination sur la liste principale des commandes fournisseur.
- Dans le dialog de creation uniquement: filtre Marque (envoye a l'API en query param `brand`), filtre Categorie (query param `category`), et recherche texte CLIENT sur le libelle des variantes (variantSearch, insensible a la casse, sur '<marque> <reference> (<couleur>)').
- Le refetch des references se declenche a chaque changement de filterBrandId ou filterCategoryId (useEffect avec deps [open, filterBrandId, filterCategoryId]).

**Appels API** (8)

- GET /api/suppliers/orders/ (djangoClient.suppliers.list(), appele sans magasinId donc sans query param) — liste des commandes fournisseur de tous les magasins accessibles ; retourne id, magasin, numero, date, description, statut, prix_fournisseur, fret_import, douane, total_qty, cout_total, cout_unitaire, lines[], created_at, received_at
- POST /api/suppliers/orders/ (djangoClient.suppliers.create()) — cree une commande + ses lignes puis recalcule les couts ; body {description, prix_fournisseur, fret_import, douane, lines:[{product_variant, quantite}]}
- POST /api/suppliers/orders/<id>/receive/ (djangoClient.suppliers.receive()) — receptionne: cree un StockMovement ENTREE/origine FOURNISSEUR par ligne, passe statut a 'RECU', horodate received_at, cree une Notification 'supplier_order'
- GET /api/catalog/brands/ (djangoClient.catalog.brands.list()) — alimente le Select 'Marque' du dialog de creation
- GET /api/catalog/categories/ (djangoClient.catalog.categories.list()) — alimente le Select 'Catégorie'
- GET /api/catalog/references/?brand=<id>&category=<id> (djangoClient.catalog.references.list()) — alimente la liste des variantes (Select 'Couleur'), avec variants[] imbriquees (id, couleur, stock_actuel, seuil_alerte…)
- WebSocket (DataSyncProvider) — evenements {model:'supplier_order', action, id, magasin_id} declenchant le refetch silencieux
- GET /api/users/refresh/ implicite: le client rafraichit automatiquement le JWT sur 401 et redirige vers /login si le refresh echoue

**Etats UI** (10)

- loading: skeleton `<Skeleton className='h-64 w-full' />` dans un padding p-6 tant que loading===true (uniquement au premier chargement et sur fetchOrders() non silencieux)
- empty: texte centre gris 'Aucune commande fournisseur.' (py-12) quand orders.length === 0
- error (chargement): toast.error(err.message || 'Erreur de chargement') — le tableau reste vide, pas d'ecran d'erreur dedie
- error (reception): toast.error(err.message || 'Réception impossible') — ex: 'Cette commande fournisseur a déjà été reçue.'
- error (creation): toast.error(err.message || 'Erreur'), dialog conserve
- success (creation): toast.success('Commande fournisseur créée')
- success (reception): toast.success('Commande <numero> reçue — stock mis à jour')
- disabled: bouton 'Créer' disabled pendant submitting, libelle change en 'Création…'
- unauthorized: NON gere cote page — un non-Gerant voit la page vide + toast d'erreur API (403). Pas d'ecran 'Acces refuse' comme sur /transfers.
- refetch silencieux (temps reel WS): aucun indicateur visuel, la liste se met a jour toute seule

**Details UX** (10)

- Format monetaire: `new Intl.NumberFormat('fr-MG').format(Math.round(Number(n||0))) + ' Ar'` — arrondi a l'entier, separateur de milliers fr-MG, suffixe ' Ar'. null/undefined/'' -> '0 Ar'.
- Libelles de statut (STATUT_LABEL): BROUILLON -> 'Brouillon', COMMANDE -> 'Commandé', RECU -> 'Reçu'
- Couleurs de badge (STATUT_COLOR): BROUILLON -> bg-slate-100 text-slate-800 (gris) ; COMMANDE -> bg-blue-100 text-blue-800 (bleu) ; RECU -> bg-green-100 text-green-800 (vert)
- Statut inconnu -> Badge sans classe de couleur et libelle undefined (pas de fallback)
- Toasts via sonner (bibliotheque `toast` de sonner): success / error uniquement sur cette page
- Icones lucide: Truck (titre), Plus (creer/ajouter), Trash2 rouge (supprimer une ligne), Truck, PackageCheck (receptionner), RefreshCw (rafraichir)
- Layout: p-4 sm:p-6, space-y-6 ; en-tete flex-col sur mobile / flex-row sm:items-center a partir de sm
- Le curseur devient pointer sur chaque ligne du tableau pour signaler qu'elle est cliquable
- Le dialog de detail affiche un snapshot de l'objet ligne (setDetail(o)) : il n'est pas re-fetche, donc il peut afficher des donnees perimees si un evenement WS met la liste a jour pendant qu'il est ouvert
- Mise a jour temps reel debounce 400 ms; plusieurs evenements rapproches ne declenchent qu'un seul refetch

### `/transfers`

- **Fichier Next.js** : `frontend/app/(app)/transfers/page.tsx`
- **Groupe d'audit** : `suppliers-transfers`
- **Cible Flutter** : lib/features/transfers/transfers_screen.dart
- **Etat** : PARTIAL

**Role et gating.** ADMIN UNIQUEMENT (superadmin/proprietaire de societe). Gating explicite dans la page: `const { isAdmin, loading: userLoading } = useCurrentUser()` (lib/auth/useCurrentUser.ts, isAdmin = role === 'admin'). Si !isAdmin -> ecran 'Acces refuse' (Card + icone ShieldAlert rouge h-12 w-12, titre 'Accès refusé', texte 'Cette page est réservée aux administrateurs.'). Le fetch des magasins ne part que `if (isAdmin)`. Cote sidebar l'entree { label:'Transferts', href:'/transfers', icon: ArrowLeftRight, superAdminOnly: true } est filtree par `if (item.superAdminOnly && !isSuperAdmin) return false` (isSuperAdmin = role === 'admin'), et pendant le chargement du user la sidebar masque TOUS les items superAdminOnly. Cote backend TransferProductsView refuse tout role != 'admin' avec 403 {'error':'Permission refusée'} et verifie que les 2 magasins appartiennent bien a l'admin (Q(admin=user)|Q(admins=user)).

**Objectif.** Transfert de stock entre magasins d'une meme societe: choisir un magasin source, selectionner des produits/variantes (couleurs) avec leurs quantites, choisir un magasin de destination et valider le transfert. Le gros de l'UI est delegue au composant partage TransferProductsPanel.

**Fonctionnalites** (8)

- En-tete: h1 'Transfert de produits' (text-3xl, tracking-tight) avec icone ArrowLeftRight h-8 w-8 text-blue-600
- Sous-titre: 'Choisissez un magasin source, puis sélectionnez les produits (et leurs variantes) à transférer vers un autre magasin.'
- Barre 'Magasin source :' — une rangee de boutons (flex-wrap) un par magasin accessible; chaque bouton affiche le logo (img rond h-4 w-4 object-cover) ou l'icone Store si pas de logo, + le shop_name
- Bouton magasin source SELECTIONNE: classes 'bg-primary/10 border-primary/30 font-medium' ; non selectionne: 'border-border' ; hover:bg-muted/50 sur tous
- Selectionner un magasin source monte <TransferProductsPanel key={sourceStore.magasin_id} …> — le `key` force un REMOUNT complet (donc reset du panier, de la recherche, des quantites et de la destination) a chaque changement de source
- onSuccess du panel: setSourceStoreId(null) (deselectionne la source, on revient a l'ecran d'invite) + fetchStores() (rechargement de la liste des magasins)
- Aucun onglet, aucun switch, aucun menu contextuel sur cette page
- Tout le reste des fonctionnalites (recherche produit, panier, destination, submit) est dans TransferProductsPanel — voir l'entree dediee ci-dessous

**Formulaires** (1)

- Cette page ne contient aucun formulaire propre; le formulaire de transfert (<form onSubmit={handleTransferSubmit}>) est integralement dans TransferProductsPanel.

**Modales / dialogs / drawers** (1)

- Aucun dialog/modal sur la page /transfers (la version modale du meme flux existe via TransferProductsDialog, utilisee par /stores).

**Recherche, filtres, tri, pagination** (2)

- Aucun filtre sur la page elle-meme; la selection du magasin source se fait par boutons (pas de dropdown).
- Les recherches (produits, magasin de destination) sont dans TransferProductsPanel.

**Appels API** (3)

- GET /api/users/magasins/users/ (djangoClient.get('/users/magasins/users/')) — retourne un tableau d'objets {magasin_id, shop_name, shop_logo (URL absolue ou null), manager {…}, employers [...], company_users [...]} ; seules magasin_id / shop_name / shop_logo sont utilisees ici (type TransferStore). Backend: UsersByMagasinView, scope par role (admin = tous ses magasins, magasin = le sien, employer = celui de son affectation)
- (via le panel) GET /api/catalog/references/ — liste des produits du magasin source
- (via le panel) POST /api/users/transfer/products/ — execution du transfert

**Etats UI** (6)

- loading: si userLoading || loading -> 3 Skeleton h-16 w-full empiles (p-6 space-y-4)
- unauthorized: Card centree, icone ShieldAlert rouge, titre 'Accès refusé', texte 'Cette page est réservée aux administrateurs.' (py-20, texte centre)
- empty (magasins): si stores.length === 0 -> texte gris 'Aucun magasin' a la place de la rangee de boutons
- empty (aucune source choisie): zone flex-1 min-h-[300px] avec bordure en pointilles (border-dashed) et texte gris centre 'Sélectionnez un magasin source pour commencer.'
- error (chargement magasins): toast.error('Erreur de chargement des magasins: ' + (err.message || err))
- BUG A REPRODUIRE OU CORRIGER: pour un utilisateur NON admin, `loading` reste a true indefiniment (fetchStores n'est appele que si isAdmin, et rien d'autre ne fait setLoading(false)); la condition `if (userLoading || loading)` court-circuite donc l'ecran 'Accès refusé' — un non-admin voit un skeleton infini. En Flutter, prevoir setLoading(false) quand !isAdmin pour afficher reellement l'ecran d'acces refuse.

**Details UX** (4)

- Layout pleine hauteur: h-full flex flex-col gap-4 p-6 — le panel occupe la hauteur restante (flex-1, min-h-0) avec des zones scrollables internes
- Logos de magasin: <img> rond de 16px (h-4 w-4) en object-cover, fallback icone Store grise
- La deselection du magasin source apres un transfert reussi (setSourceStoreId(null)) fait revenir a l'ecran d'invite 'Sélectionnez un magasin source pour commencer.'
- Toasts sonner uniquement (pas d'alertes inline)

### `/transfers (composant partage TransferProductsPanel — coeur fonctionnel)`

- **Fichier Next.js** : `frontend/components/transfer-products-panel.tsx`
- **Groupe d'audit** : `suppliers-transfers`
- **Cible Flutter** : lib/features/transfers/transfers_screen.dart
- **Etat** : PARTIAL

**Role et gating.** Pas de gating interne au composant: il herite du gating de son hote (page /transfers = isAdmin uniquement; dialog TransferProductsDialog appele depuis /stores, page elle aussi superAdminOnly). Le backend refuse le POST si role != 'admin' (403 'Permission refusée') et si les magasins source/destination n'appartiennent pas a l'admin (404 'Magasin source ou destination introuvable ou non autorisé').

**Objectif.** Coeur du flux de transfert: liste des produits du magasin source (avec variantes repliables), panier de transfert editable, selecteur de magasin de destination avec recherche, et bouton de soumission. Concu pour etre remonte via `key={sourceStore.magasin_id}` afin de reinitialiser son etat interne quand la source change. Props: sourceStore, stores, initialCart (defaut []), onSuccess.

**Fonctionnalites** (23)

- Structure: <form> en flex-col; grille responsive grid-cols-1 lg:grid-cols-2 (colonne gauche = produits, colonne droite = panier + destination), puis un bouton submit pleine largeur en bas
- PANNEAU GAUCHE 'Produits du magasin': Label + champ de recherche avec icone Search en overlay (placeholder 'Rechercher un produit...', pl-9), puis une ScrollArea flex-1
- Filtre client des produits: p.name?.toLowerCase().includes(term) || p.reference?.toLowerCase().includes(term) — insensible a la casse, sur le nom OU la reference
- PRODUIT SANS VARIANTE (variants vide): carte flex avec a gauche nom (truncate, text-sm font-medium) et ligne secondaire '<reference> · Stock : <initial_quantity>'; a droite un Input number (min=1, max=stock, largeur w-16 h-8, texte centre) + un bouton 'Sélectionner'
- Le bouton 'Sélectionner' devient 'Sélectionné' avec icone Check et variant=secondary quand l'item est deja au panier; il est disabled si deja au panier OU si stock <= 0; l'Input de quantite est disabled dans les memes conditions
- PRODUIT AVEC VARIANTES: en-tete cliquable (bouton pleine largeur) avec chevron ChevronRight (replie) / ChevronDown (deplie), nom du produit (truncate) et ligne secondaire '<reference> · <n> variante(s) · Stock : <totalStock>' (totalStock = somme des quantity des variantes)
- Toggle d'expansion gere par un Set<number> expandedProductIds (toggleExpand) — plusieurs produits peuvent etre deplies simultanement; etat perdu au remount
- Variantes triees par SIZE_ORDER = ['XS','S','M','L','XL','2XL','3XL','4XL'] (index -1 -> 99, donc inconnues a la fin). NOTE: le mapper backend->front met toujours size:'' donc ce tri est en pratique un no-op (vestige d'une app textile) — la couleur seule est utilisee
- LIGNE DE VARIANTE (fond bg-muted/20, chaque ligne sur bg-background): libelle en font-semibold = formatVariantLabel(size, color) = les parties non vides jointes par ' / ', ou 'Standard' si vide; puis ' · Stock : <vStock>' en muted; a droite Input number (min=1, max=vStock, w-14 h-7, text-xs) + bouton icone (h-7 px-2) affichant Plus (ajouter) ou Check (deja au panier, variant=secondary, disabled)
- Clamp des quantites saisies: getQtyInput/setQtyInput bornent la valeur entre 1 et Math.max(stock, 1) — impossible de descendre sous 1 ou de depasser le stock
- addToTransferCart(product): si stock <= 0 -> toast.error('<nom> : stock insuffisant'); si deja au panier (meme id, variantId null) -> toast.info('<nom> est déjà dans le panier'); sinon ajoute et toast.success('<qty> × <nom> ajouté au panier')
- addVariantToTransferCart(product, variant): si stock <= 0 -> toast.error('<nom> : stock insuffisant pour cette variante'); si deja au panier (meme id + meme variantId) -> toast.info('Cette variante est déjà dans le panier'); sinon ajoute et toast.success('<qty> × <nom> (<libelle variante>) ajouté au panier')
- PANNEAU DROIT HAUT 'Panier de transfert': en-tete avec icone ShoppingCart + Label + Badge variant=secondary affichant '<total> unité(s)' (somme des quantites du panier)
- Chaque item du panier (fond bg-muted/50, arrondi): nom en font-medium truncate, suivi si variante de ' — <variantLabel>' en gris/normal; ligne secondaire '<reference> · max <maxQuantity>'; a droite un Input number (min=1, max=maxQuantity, w-16 h-8) editable et un bouton icone ghost X (h-7 w-7, hover:text-destructive) pour retirer l'item
- updateTransferCartQuantity: clamp entre 1 et item.maxQuantity a chaque frappe
- removeFromTransferCart(productId, variantId): retire l'entree correspondante (comparaison stricte sur id ET variantId)
- Cle d'unicite panier: cartKey(id, variantId) = variantId != null ? `${id}:${variantId}` : `${id}` — un produit et ses variantes peuvent coexister dans le panier
- PANNEAU DROIT BAS 'Magasin de destination': Label + Input de recherche avec icone Search (placeholder 'Rechercher un magasin...')
- Si une destination est choisie, une pastille apparait au-dessus de la liste: bordure border-primary/30 + fond bg-primary/5, icone Store primary, nom du magasin en font-medium, et un bouton icone ghost X (h-6 w-6) pour desélectionner (setDestinationStoreId(''))
- Liste des destinations dans une ScrollArea de hauteur fixe h-40: un bouton par magasin, avec logo rond h-5 w-5 ou icone Store, le nom, et une icone Check a droite (ml-auto, text-primary) si selectionne; selectionne = 'bg-primary/10 border border-primary/30 font-medium'
- Le magasin source est EXCLU de la liste des destinations (s.magasin_id !== sourceStore.magasin_id) et la liste est filtree par la recherche (includes insensible a la casse sur shop_name)
- BOUTON SUBMIT pleine largeur (w-full): libelle 'Transférer <total> unité(s)' avec icone ArrowLeftRight (le nombre n'apparait que si total > 0); disabled si submittingTransfer || panier vide || pas de destination; pendant l'envoi: spinner Loader2 anime + 'Transfert en cours...'
- initialCart (prop): permet de pre-remplir le panier ET les quantites (qtyInputs initialises depuis initialCart via cartKey) — utilise par la version dialog

**Formulaires** (7)

- FORMULAIRE DE TRANSFERT (form onSubmit=handleTransferSubmit). Champs: (1) recherche produit [texte, libre, pas de validation], (2) quantite par produit/variante [number, clamp 1..stock], (3) panier: quantite par item [number, clamp 1..maxQuantity], (4) recherche magasin destination [texte], (5) magasin de destination [selection obligatoire].
- VALIDATION 1: si !destinationStoreId || transferCart.length === 0 -> toast.error('Sélectionnez des produits et un magasin de destination') et arret (le bouton est de toute facon disabled dans ce cas, c'est une double securite).
- VALIDATION 2 (regle metier cachee): seuls les items ayant un variantId sont envoyes (`transferCart.filter(p => p.variantId != null)`). Si apres filtrage il ne reste rien -> toast.error('Sélectionnez au moins une couleur à transférer'). CONSEQUENCE: un produit sans variante peut etre ajoute au panier mais sera SILENCIEUSEMENT IGNORE au moment du transfert.
- Payload envoye: {source_magasin_id, destination_magasin_id, items: [{variant_id, quantity}]}.
- APRES SOUMISSION OK: toast.success('Transfert effectué') puis onSuccess?.() — sur /transfers cela deselectionne la source et recharge les magasins; dans le dialog cela ferme le modal puis rappelle le onSuccess du parent. Le panier n'est PAS vide explicitement: c'est le remount (key) ou la fermeture du dialog qui le reinitialise.
- APRES ERREUR: console.error + toast.error('Erreur lors du transfert') — MESSAGE GENERIQUE, le detail renvoye par le backend (ex: 'Stock insuffisant pour <ref> (<couleur>). Disponible : N.') n'est PAS affiche. A ameliorer en Flutter.
- Dans tous les cas (finally): setSubmittingTransfer(false).

**Modales / dialogs / drawers** (2)

- Le panel lui-meme n'ouvre aucun dialog. Il EST le contenu du dialog TransferProductsDialog quand il est utilise en mode modal.
- Zones repliables (accordeon maison) par produit a variantes — pas un composant Accordion, juste un bouton + rendu conditionnel.

**Recherche, filtres, tri, pagination** (4)

- Recherche produit (client): sur name OU reference, insensible a la casse, sans debounce, appliquee a la volee
- Recherche magasin de destination (client): sur shop_name, insensible a la casse, exclut toujours le magasin source
- Tri des variantes par SIZE_ORDER (voir features) — no-op en pratique
- Aucune pagination: tous les produits du magasin source sont rendus dans une ScrollArea

**Appels API** (2)

- GET /api/catalog/references/ via djangoClient.products.list({ magasin_id }) — ATTENTION: products.list appelle catalog.references.list() SANS query param, recupere TOUTES les references accessibles, puis filtre CLIENT sur Number(r.magasin) === Number(magasinId); le panel refiltre une 2e fois cote client. Chaque reference est mappee par mapReferenceToProduct(): {id, name: reference_name, reference: reference_name, brand: brand_name, category: category_name, description: '<type> — <marque>', shell_price: prix_vente, initial_quantity: somme des stock_actuel, alert_threshold: min des seuil_alerte, magasin, variants: [{id, size:'', color: couleur, quantity: stock_actuel}]}
- POST /api/users/transfer/products/ via djangoClient.transfers.transfer(sourceId, destId, items) — body {source_magasin_id, destination_magasin_id, items:[{variant_id, quantity}]}. Backend TransferProductsView: transaction atomique, verifie l'appartenance de chaque variante au magasin source, refuse quantite <= 0 ou > stock disponible, recree si besoin toute la chaine Categorie->Type->Marque->Reference->Variante (par NOM) dans le magasin destination, puis applique deux mouvements de stock (SORTIE source / ENTREE destination) avec la note 'Transfert du magasin X au magasin Y par <full_name>'.

**Etats UI** (9)

- loading produits: bloc centre h-32 avec Loader2 anime + texte 'Chargement...'
- empty produits (magasin vide): 'Aucun produit dans ce magasin' (p-4, text-sm, centre, muted)
- empty recherche produits: 'Aucun résultat' (meme style) — la distinction se fait sur sourceProducts.length === 0
- empty panier: 'Aucun produit sélectionné'
- empty destinations: 'Aucun magasin trouvé'
- error chargement produits: console.error + toast.error('Erreur de chargement des produits'), la liste reste vide
- disabled: bouton d'ajout et input de quantite desactives si deja au panier ou stock <= 0; bouton submit desactive si envoi en cours / panier vide / pas de destination
- submitting: spinner + libelle 'Transfert en cours...' sur le bouton submit
- Pas d'etat 'unauthorized' interne (herite de l'hote)

**Details UX** (8)

- formatVariantLabel(size, color): joint les parties non vides par ' / ' ; si vide, la ligne affiche 'Standard'
- Badge du panier: variant='secondary', texte '<n> unité(s)'
- Icones lucide: Search, ShoppingCart, Store, ArrowLeftRight, Check, Plus, X, Loader2 (spin), ChevronDown/ChevronRight
- Feedback immediat par toast a CHAQUE ajout au panier (success), doublon (info), stock insuffisant (error) — 3 niveaux de toast distincts
- Aucune synchronisation temps reel ici (pas de useRealtimeRefresh): les stocks affiches sont ceux du chargement initial du magasin source
- Les stocks affiches ne se decrementent PAS quand un item est ajoute au panier (le max reste le stock initial)
- Zones scrollables independantes: liste produits (flex-1), panier (flex-1), destinations (h-40 fixe)
- Sur mobile (grid-cols-1) les 3 panneaux s'empilent verticalement

### `/stores (modal TransferProductsDialog — variante modale du meme flux)`

- **Fichier Next.js** : `frontend/components/transfer-products-dialog.tsx`
- **Groupe d'audit** : `suppliers-transfers`
- **Cible Flutter** : lib/features/stores/stores_screen.dart
- **Etat** : PARTIAL

**Role et gating.** Aucun gating propre. Utilise par app/(app)/stores/page.tsx (entree sidebar superAdminOnly => role 'admin'). Le backend applique la meme regle: role === 'admin' obligatoire.

**Objectif.** Enveloppe modale (Dialog shadcn) autour de TransferProductsPanel: permet de lancer un transfert depuis la page Magasins sans changer de route. Reexporte les types TransferCartItem et TransferStore.

**Fonctionnalites** (7)

- Dialog plein ecran quasi total: w-[97vw] max-w-[97vw] h-[95vh] max-h-[95vh], overflow-hidden, flex flex-col
- Titre: 'Transfert de produits'
- Description: 'Depuis <shop_name du magasin source en gras/foreground> — sélectionnez des produits (et leurs variantes) et choisissez le magasin de destination.'
- Le panel n'est monte que si sourceStore n'est pas null (rendu conditionnel), avec key={sourceStore.magasin_id} pour reinitialiser l'etat au changement de source
- onSuccess du panel: ferme le dialog (onOpenChange(false)) PUIS appelle le onSuccess du parent (sur /stores: fetchData() pour recharger les magasins)
- Props: open, onOpenChange, sourceStore (nullable), stores, initialCart (defaut []), onSuccess
- Fermeture standard du Dialog Radix: bouton X, clic sur l'overlay, touche Echap — aucune confirmation avant fermeture, le panier en cours est perdu

**Formulaires** (1)

- Aucun formulaire propre — delegue integralement a TransferProductsPanel (voir son entree).

**Modales / dialogs / drawers** (1)

- C'EST le dialog. Contenu = TransferProductsPanel. Aucun sous-dialog.

**Recherche, filtres, tri, pagination** (1)

- Aucun — delegue au panel (recherche produit + recherche magasin destination).

**Appels API** (1)

- Aucun appel direct — tous les appels passent par TransferProductsPanel (GET /api/catalog/references/, POST /api/users/transfer/products/).

**Etats UI** (2)

- Aucun etat propre: loading/empty/error sont ceux du panel.
- Si sourceStore est null, le dialog s'affiche avec seulement l'en-tete (description avec un nom de magasin vide) et un corps vide.

**Details UX** (3)

- Modal quasi plein ecran pour laisser de la place aux deux colonnes du panel
- Le nom du magasin source est mis en valeur (font-medium text-foreground) dans la description
- En Flutter, l'equivalent naturel est une page plein ecran (fullscreenDialog) plutot qu'un AlertDialog, vu la taille 97vw/95vh

### `/alerts`

- **Fichier Next.js** : `frontend/app/(app)/alerts/page.tsx`
- **Groupe d'audit** : `petites-pages`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** AUCUN gating dans la page elle-meme : le composant n'importe PAS useCurrentUser, aucun guard, aucun redirect. Seule protection = (a) le layout /home/garrix/Dev/Smartphone/frontend/app/(app)/layout.tsx qui fait router.replace('/login') si !djangoClient.isAuthenticated(), (b) l'entree de menu Sidebar { label:'Alertes', href:'/alerts', icon:AlertCircle, adminOnly:true } donc le lien n'est visible que si isAdminOrSuperAdmin (role 'admin' OU 'magasin'). Consequence : un PREPARATEUR ou un LIVREUR qui tape l'URL a la main voit la page entierement. Le backend GET /catalog/references/ filtre malgre tout par magasin accessible. En Flutter il faut decider : reproduire tel quel (aucun gating) ou ajouter le guard isGerant.

**Objectif.** Tableau de bord des alertes produit du catalogue : ruptures de stock, stocks sous le seuil d'alerte, et (theoriquement) dates de peremption proches/depassees. Page 100% lecture seule, aucune action de correction.

**Fonctionnalites** (19)

- En-tete : h1 'Alertes' (text-3xl font-bold tracking-tight) + sous-titre muted 'Produits necessitant une attention'.
- Bouton 'Actualiser' (Button variant='outline' size='sm', icone RefreshCw h-4 w-4 mr-2) aligne a droite de l'en-tete : appelle fetchData() en mode NON silencieux (donc repasse loading=true et reaffiche tous les skeletons).
- Le bouton Actualiser est disabled={loading} et son icone RefreshCw recoit la classe 'animate-spin' quand loading===true.
- Grille de 4 cartes KPI : grid-cols-2 sur mobile, md:grid-cols-4, gap-4.
- KPI 1 'Rupture de stock' : icone Package, couleur text-red-600, valeur = outOfStock.length.
- KPI 2 'Stock faible' : icone AlertTriangle, couleur text-orange-500, valeur = lowStock.length.
- KPI 3 'Expirent bientot' : icone AlertTriangle, couleur text-yellow-600, valeur = expiringSoon.length.
- KPI 4 'Expires' : icone AlertTriangle, couleur text-red-700, valeur = expired.length.
- Chaque KPI : CardHeader pb-2 avec CardTitle text-sm font-medium flex gap-2 (icone + label colores), CardContent avec la valeur en text-2xl font-bold de la meme couleur.
- Section 1 - Card 'Rupture de stock (N)' : CardTitle text-red-600 + icone Package h-5 w-5, N = outOfStock.length. Pas de CardDescription.
- Section 2 - Card 'Stock faible (N)' : CardTitle text-orange-600 + icone AlertTriangle h-5 w-5, N = lowStock.length, CardDescription "Quantite en dessous du seuil d'alerte".
- Section 3 - Card 'Dates de peremption (N)' : CardTitle text-yellow-600 + icone AlertTriangle, N = expiringSoon.length + expired.length. Cette carte entiere n'est RENDUE que si (expiringSoon.length > 0 || expired.length > 0) — sinon elle disparait totalement du DOM.
- Sous-composant interne AlertTable({ items, emptyMsg, columns }) redefini a chaque render : gere lui-meme les 3 etats loading / vide / tableau.
- Ordre d'affichage de la section peremption : items = [...expired, ...expiringSoon] — les produits DEJA expires sont listes AVANT ceux qui expirent bientot.
- Aucune action par ligne : pas de bouton, pas de lien vers la fiche produit, pas de menu contextuel, pas de selection multiple, pas d'export.
- Aucune barre de recherche, aucun filtre, aucun tri, aucune pagination sur cette page.
- Constante `fmt` (Intl.NumberFormat('fr-MG') sur Math.round) declaree en haut du fichier mais JAMAIS UTILISEE (code mort) — ne pas la porter.
- Rafraichissement temps reel : useRealtimeRefresh(['product_variant','order'], () => fetchData(true)) — refetch SILENCIEUX (pas de skeleton, la table se met a jour en place).
- Chargement initial : useEffect(() => { fetchData(); }, [fetchData]) au montage, en mode non silencieux.

**Recherche, filtres, tri, pagination** (5)

- Aucun filtre/recherche/tri/pagination UI. Le decoupage en 4 sections est un filtrage 100% cote client sur le tableau `products` complet.
- lowStock = products.filter(p => p.initial_quantity > 0 && p.initial_quantity <= p.alert_threshold)
- outOfStock = products.filter(p => p.initial_quantity === 0)
- expiringSoon = products.filter(p => p.expiry_date && new Date(p.expiry_date) <= in30Days && new Date(p.expiry_date) >= today) — in30Days = aujourd'hui + 30 jours
- expired = products.filter(p => p.expiry_date && new Date(p.expiry_date) < today)

**Appels API** (2)

- GET /catalog/references/ — via djangoClient.products.list() (appelee SANS filtre). Renvoie toutes les ProductReference visibles par l'utilisateur; chaque ref est ensuite transformee cote client par mapReferenceToProduct().
- GET /users/me/ — indirectement, uniquement via la Sidebar/TopBar du layout (pas par la page elle-meme).

**Etats UI** (7)

- loading (initial, loading=true par defaut) : chaque KPI affiche <Skeleton className='h-8 w-12' /> a la place du chiffre; chaque AlertTable affiche <Skeleton className='h-24 w-full' />.
- empty par section : <p class='text-sm text-muted-foreground text-center py-6'> avec le message dedie — 'Aucun produit en rupture de stock' / "Tous les stocks sont au-dessus du seuil d'alerte" / 'Aucun produit proche de la peremption' (ce dernier est inatteignable car la carte n'est rendue que si la liste est non vide).
- error : catch { console.error(err) } UNIQUEMENT — pas de toast, pas de bandeau, pas de bouton reessayer. En cas d'echec la page reste sur les donnees precedentes (ou vide) et sort du loading via finally.
- success : pas de toast (page lecture seule).
- unauthorized : AUCUN etat implemente.
- disabled : uniquement le bouton Actualiser pendant loading.
- Pendant un refresh silencieux (websocket) : aucun indicateur visuel, loading reste false.

**Details UX** (8)

- Badge colonne 'status_badge' : si p.initial_quantity === 0 -> Badge className='bg-red-100 text-red-800' libelle 'Rupture'; sinon Badge className='bg-orange-100 text-orange-800' libelle 'Faible'.
- Badge colonne 'expiry_badge' : si new Date(p.expiry_date) < today -> 'bg-red-100 text-red-800', sinon 'bg-orange-100 text-orange-800'; le texte du badge est la date formatee new Date(p.expiry_date).toLocaleDateString('fr-FR') (format JJ/MM/AAAA).
- Colonne 'initial_quantity' : rendue dans un <span className='font-semibold'>.
- Toute autre colonne : rendu brut p[c.key] ?? '-' (donc '-' si null/undefined, mais '' reste vide et 0 s'affiche 0).
- Le compteur entre parentheses dans chaque titre de carte se met a jour en direct.
- Conteneur global : div p-6 space-y-6.
- Le tableau shadcn n'a pas de conteneur overflow-x propre ici : attention au responsive en portage mobile Flutter (preferer une liste de cartes).
- Toasts globaux (sonner) configures dans app/layout.tsx : position top-right, richColors, closeButton, expand, duration 5000 — mais cette page n'en emet aucun.

### `/pickup`

- **Fichier Next.js** : `frontend/app/(app)/pickup/page.tsx`
- **Groupe d'audit** : `petites-pages`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** GERANT uniquement. Gating explicite : const { isGerant, loading: userLoading } = useCurrentUser(); isGerant === (role === 'admin' || role === 'magasin'). (1) Ecran 'Acces refuse' rendu si (!userLoading && !isGerant) — return anticipe avant tout le reste. (2) Le fetch n'est declenche que par useEffect(() => { if (!userLoading && isGerant) fetchOrders(); }). Sidebar : { label:'Recuperation', href:'/pickup', adminOnly:true }. Cote backend, orders/services.py::change_order_status leve PermissionDenied('Seul le gerant peut valider une recuperation sur place.') si role != 'GERANT'. Nuance : tant que userLoading===true, le garde ne s'applique pas et la page principale (skeletons) est affichee brievement a tout le monde.

**Objectif.** File d'attente des commandes prêtes a etre retirees au comptoir (zone de livraison 'RECUPERATION', donc sans livreur). Le gerant confirme le retrait client, ce qui bascule la commande PRETE -> LIVRE.

**Fonctionnalites** (13)

- En-tete : h1 text-2xl font-bold avec icone PackageCheck h-6 w-6 + texte 'Recuperation sur place'; sous-titre text-sm muted : 'Commandes pretes a retirer au comptoir (zone "Recuperation") — pas de livreur assigne.'
- En-tete responsive : flex-col sur mobile, sm:flex-row sm:items-center justify-between gap-3.
- Bouton refresh : Button variant='outline' size='icon' avec seule l'icone RefreshCw h-4 w-4 (pas de libelle). onClick -> fetchOrders() NON silencieux (reaffiche les skeletons). Il n'est ni disabled ni anime pendant le chargement (contrairement a /alerts).
- Liste : grid gap-3, 1 colonne mobile, sm:grid-cols-2. Une Card par commande, key=order.id.
- Carte commande — bloc haut : order.numero en font-semibold, order.client_nom en text-sm muted, et a droite un Badge className='bg-blue-100 text-blue-800' libelle 'Prete' (badge statique, toutes les commandes de cette page sont PRETE).
- Carte commande — lien telephone : <a href={`tel:${order.telephone}`}> avec icone Phone h-3.5 w-3.5, classes text-sm text-blue-600 hover:underline w-fit. Declenche l'appel telephonique natif. (En Flutter : url_launcher tel:).
- Carte commande — liste des articles : (order.items || []).map(it => `${it.reference_name} (${it.couleur}) x${it.quantite}`).join(', ') dans un div text-sm muted. La couleur est TOUJOURS affichee entre parentheses meme quand elle vaut 'Standard'. Aucun prix unitaire affiche.
- Carte commande — pied : bordure haute (border-t pt-3), a gauche le total en text-sm font-semibold, a droite le bouton d'action.
- Bouton d'action par carte : Button size='sm' avec icone PackageCheck h-4 w-4 mr-1, libelle 'Marquer comme recuperee'. Il OUVRE la modale (setPickupTarget(order)) — il ne declenche pas directement l'API.
- Ce bouton est disabled={confirming === order.id} et son libelle devient 'Confirmation...' pendant l'appel API.
- Aucun bouton d'annulation de commande, aucun detail/expansion, aucun lien vers la fiche commande, aucun menu contextuel, aucune selection multiple.
- Aucun onglet, aucun switch, aucun toggle.
- Rafraichissement temps reel : useRealtimeRefresh(['order','order_status_history'], () => fetchOrders(true)) — refetch silencieux quand un evenement WebSocket order/order_status_history arrive (une commande passee PRETE par un preparateur apparait donc automatiquement dans la liste).

**Modales / dialogs / drawers** (6)

- Dialog de confirmation de retrait (shadcn Dialog) : open={!!pickupTarget}, onOpenChange={(o) => !o && setPickupTarget(null)} (fermeture par Echap / clic exterieur autorisee, meme pendant l'envoi).
- DialogTitle dynamique : 'Confirmer la recuperation de {pickupTarget?.numero} ?'
- DialogDescription dynamique : 'La commande de {pickupTarget?.client_nom} sera marquee comme livree (recuperee sur place).'
- DialogFooter — bouton 'Annuler' (variant='outline') : setPickupTarget(null), aucune API appelee.
- DialogFooter — bouton 'Confirmer' (variant par defaut) : appelle confirmPickup(pickupTarget); disabled={confirming === pickupTarget?.id}; libelle 'Confirmation...' pendant l'appel.
- Aucun champ de saisie dans cette modale (pas de note, pas de photo, pas de mot de passe).

**Recherche, filtres, tri, pagination** (3)

- Aucun filtre UI, aucune recherche, aucun tri, aucune pagination.
- Le filtrage est fige cote requete : statut=PRETE ET livraison_zone=RECUPERATION.
- L'ordre d'affichage est celui renvoye par l'API (aucun tri client).

**Appels API** (3)

- GET /orders/?statut=PRETE&livraison_zone=RECUPERATION — via djangoClient.orders.list({ statut:'PRETE', livraison_zone:'RECUPERATION' }). Sert a peupler la file de retrait. Reponse serialisee par OrderGerantSerializer (numero, client_nom, telephone, total_a_payer, items[{reference_name, couleur, quantite, prix_unitaire}], statut_courant, ...).
- POST /orders/{id}/status/ body { statut:'LIVRE', note:undefined } — via djangoClient.orders.changeStatus(order.id, 'LIVRE'). Confirme la recuperation au comptoir.
- GET /users/me/ — via useCurrentUser, pour resoudre isGerant.

**Etats UI** (8)

- loading (initial true) : 3 <Skeleton className='h-24 w-full' /> empiles dans un div space-y-3.
- empty : Card avec CardContent 'py-16 text-center text-sm text-muted-foreground' contenant 'Aucune commande prete a recuperer pour le moment.'
- unauthorized : ecran plein remplacant tout — Card > CardContent flex-col items-center justify-center py-20 text-center, icone ShieldAlert h-12 w-12 text-red-500 mb-4, h2 text-xl font-bold 'Acces refuse', paragraphe muted 'Cette page est reservee au gerant.'
- error de chargement : toast.error(err.message || 'Erreur de chargement des commandes'); la liste conserve son etat precedent.
- error d'action : toast.error(err.message || 'Action impossible'); la modale RESTE OUVERTE (setPickupTarget(null) n'est appele que dans le chemin succes).
- success : toast.success(`Commande ${order.numero} recuperee`), fermeture de la modale, puis fetchOrders(true) silencieux (la carte disparait de la liste puisqu'elle n'est plus PRETE).
- disabled : bouton carte + bouton Confirmer pendant confirming === order.id (state number|null, un seul a la fois).
- Pas d'etat 'refresh en cours' visible sur le bouton icone.

**Details UX** (7)

- Format monetaire local : fmt(n) = new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar' — arrondi a l'entier, separateurs fr-MG, suffixe ' Ar'. Applique a order.total_a_payer.
- Badge statut unique et statique : 'Prete' en bg-blue-100 text-blue-800.
- Toasts sonner globaux : top-right, richColors (succes vert / erreur rouge), closeButton, expand, duree 5000 ms.
- Conteneur : div p-4 sm:p-6 space-y-6 (padding reduit sur mobile — page pensee mobile/comptoir).
- Le numero de telephone est cliquable : usage terrain evident (rappeler le client qui ne vient pas).
- Temps reel : une commande passee 'Prete' par un preparateur apparait sans action de l'utilisateur (WebSocket /ws/data/, debounce 400 ms).
- Aucune photo de preuve n'est demandee pour un retrait sur place (contrairement au flux livreur qui accepte une photo via changeStatus).

### `/scanner`

- **Fichier Next.js** : `frontend/app/(app)/scanner/page.tsx — ATTENTION : ce fichier est SUPPRIME dans le working tree (git status ' D'). Contenu recupere depuis HEAD (commit d7373bb) via `git show HEAD:"frontend/app/(app)/scanner/page.tsx"`. Il n'a plus d'entree dans la Sidebar. A confirmer avec l'equipe avant de le porter en Flutter.`
- **Groupe d'audit** : `petites-pages`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** AUCUN gating : pas de useCurrentUser, pas de guard, pas de redirect. Accessible a tout utilisateur authentifie (seul le layout (app) impose d'etre connecte). Aucune entree de menu ne pointe vers /scanner dans components/layout/sidebar.tsx.

**Objectif.** Recherche rapide (lookup) dans le catalogue produit par nom de reference ou marque. Malgre l'icone QrCode et le nom 'scanner', il n'y a AUCUN scan camera/QR/code-barres : c'est une simple recherche texte. La vente instantanee a ete retiree — chaque resultat renvoie vers 'Creer une commande' (/orders).

**Fonctionnalites** (13)

- En-tete : h1 text-3xl font-bold tracking-tight avec icone QrCode h-8 w-8 text-blue-600 + 'Recherche produit'; sous-titre muted 'Recherchez une reference du catalogue par nom, marque ou modele.'
- Champ de recherche unique : Input max-w-xl, placeholder 'Marque, reference...', icone Search h-4 w-4 en absolute left-3 top-1/2 -translate-y-1/2 (Input en pl-10). Controle par le state `query`.
- Autofocus au montage : useEffect(() => { inputRef.current?.focus(); }, []) — clavier ouvert d'emblee.
- Recherche debouncee : useEffect avec setTimeout(() => search(query), 350) et clearTimeout au cleanup — 350 ms apres la derniere frappe.
- Si la query est vide, search() fait setResults([]) et sort immediatement (aucun appel API).
- Bloc resultats affiche seulement si (query || results.length > 0).
- Grille de resultats : grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4, une Card par produit avec hover:shadow-md transition-shadow.
- Carte resultat — CardHeader pb-2 : CardTitle text-base = p.name, et a droite un Badge de statut de stock; en dessous p.brand en text-xs text-muted-foreground font-mono.
- Carte resultat — CardContent : grille 2 colonnes text-sm. Cellule 'Categorie' (label text-xs muted) -> p.category || '-'. Cellule 'Stock' -> `${p.initial_quantity} u.` en font-semibold. Cellule 'Prix vente' en col-span-2 -> new Intl.NumberFormat('fr-MG').format(p.shell_price || 0) + ' Ar'.
- Carte resultat — Button asChild className='w-full mt-2' size='sm' contenant <Link href='/orders'>Creer une commande</Link> : navigation simple vers la liste des commandes, SANS transmettre le produit selectionne (aucun query param, aucun state) — le produit doit etre re-choisi dans le formulaire de commande.
- Aucun bouton d'ajout au panier, aucune vente directe, aucun scan camera, aucun bouton d'actualisation manuelle.
- Aucun rafraichissement temps reel (pas de useRealtimeRefresh sur cette page).
- Aucun tri, aucune pagination, aucun filtre secondaire (categorie/marque).

**Formulaires** (1)

- Champ de recherche libre (non soumis) : 1 seul champ texte `query`, aucune validation, aucun message d'erreur de saisie, pas de submit (pas de <form>, pas de touche Entree geree). L'unique 'soumission' est le debounce de 350 ms.

**Recherche, filtres, tri, pagination** (3)

- Recherche plein-texte debouncee 350 ms, insensible a la casse, sur reference_name OU brand_name (contains, pas de fuzzy, pas d'accent-folding).
- Aucun filtre par categorie/marque/type malgre le sous-titre qui mentionne 'modele'.
- Aucun tri (ordre API), aucune pagination, aucune limite de resultats.

**Appels API** (1)

- GET /catalog/references/ — via djangoClient.products.search(q). ATTENTION : le client recupere la LISTE COMPLETE des references a chaque recherche puis filtre en JavaScript (r.reference_name.toLowerCase().includes(q) || (r.brand_name||'').toLowerCase().includes(q)). Il existe pourtant un endpoint dedie GET /catalog/references/autocomplete/?q=... (djangoClient.catalog.references.autocomplete) non utilise ici — a privilegier pour le portage Flutter.

**Etats UI** (7)

- loading : simple <p className='text-muted-foreground text-sm'>Recherche...</p> (aucun skeleton, aucun spinner).
- empty / aucun resultat : Card > CardContent flex-col items-center py-12 gap-2 avec icone Package h-10 w-10 et le texte 'Aucun produit trouve pour « {query} »' (guillemets francais).
- idle (aucune query ET aucun resultat) : Card > CardContent flex-col items-center py-16 gap-3, icone QrCode h-16 w-16 opacity-20 + p text-lg font-medium 'Tapez pour rechercher un produit'.
- error : toast.error(err.message || 'Erreur lors de la recherche'); results conserve sa valeur precedente.
- success : pas de toast (affichage direct des cartes).
- unauthorized : AUCUN etat implemente.
- disabled : aucun.

**Details UX** (6)

- Badge de stock calcule par stockStatus(p) : initial_quantity === 0 -> { label:'Rupture', class:'bg-red-100 text-red-800' }; initial_quantity <= alert_threshold -> { label:'Faible', class:'bg-orange-100 text-orange-800' }; sinon { label:'En stock', class:'bg-green-100 text-green-800' }.
- Marque affichee en police mono (font-mono) pour un rendu 'code-barres/reference'.
- Prix formate fr-MG + ' Ar' (fallback 0 si shell_price null).
- Icone QrCode trompeuse : aucune camera n'est ouverte, malgre la presence de @yudiel/react-qr-scanner dans package.json (utilise ailleurs).
- Conteneur : div p-6 space-y-6.
- Les etats 'idle' et 'aucun resultat' peuvent se chevaucher logiquement mais s'excluent grace aux conditions (query || results.length > 0) et (!query && results.length === 0).

### `/sales`

- **Fichier Next.js** : `frontend/app/(app)/sales/page.tsx`
- **Groupe d'audit** : `petites-pages`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** Aucun role, aucun gating : la page ne fait que rediriger. Elle n'apparait dans aucun menu de la Sidebar.

**Objectif.** Page de redirection pure (legacy). Le module Ventes/Ticket (caisse rapide) a ete retire : le seul flux de vente est desormais la Commande a 6 statuts (§5 Smartreadme.md), qui couvre aussi la vente sur place via la zone 'Recuperation'. La page redirige donc systematiquement vers /orders.

**Fonctionnalites** (3)

- useEffect(() => { router.replace('/orders'); }, [router]) — redirection immediate au montage, avec replace (pas de push) : la page ne reste PAS dans l'historique de navigation, le bouton Retour ne la reaffiche pas.
- return null — aucun rendu, aucun ecran de transition, aucun spinner, aucun message.
- Portage Flutter : mapper la route /sales sur une redirection vers l'ecran Commandes (ou simplement ne pas creer l'ecran et rediriger toute deep-link /sales).

**Etats UI** (1)

- Aucun etat UI : ni loading, ni empty, ni error. Rendu = null pendant le tick de redirection.

**Details UX** (2)

- Le commentaire en tete de fichier documente la regle metier : la vente sur place passe desormais par une commande en zone 'Recuperation' finalisee sur /pickup.
- Il existe toujours un service compat djangoClient.sales.list() qui derive des lignes de vente a partir des Commandes au statut LIVRE (pour les analytics/rapports) — pas utilise par cette page.

### `/superadmin`

- **Fichier Next.js** : `frontend/app/(app)/superadmin/page.tsx`
- **Groupe d'audit** : `petites-pages`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** SUPERADMIN uniquement, c'est-a-dire isSuperAdmin === (role === 'admin') dans useCurrentUser (attention : dans ce projet isSuperAdmin et isAdmin sont STRICTEMENT LE MEME test, role==='admin'). Gating : (1) useEffect(() => { if (!userLoading && !isSuperAdmin) router.replace('/dashboard'); }) — redirection silencieuse, sans message; (2) le fetch n'est lance que par useEffect(() => { if (isSuperAdmin) fetchData(); }). AUCUNE entree Sidebar ne pointe vers /superadmin (l'item 'Super Admin' superAdminOnly pointe vers /users) : la page n'est atteignable qu'en tapant l'URL. Cote backend : GET /users/magasins/users/ est [IsAuthenticated] et se scope selon le role (admin -> tous ses magasins, magasin -> le sien, employer -> le sien); PUT /users/role/<id>/ est [IsAuthenticated, IsAdmin]; DELETE /users/delete/<id>/ accepte role in ['admin','magasin'] et exige le mot de passe.

**Objectif.** Console de super-administration : vue globale des magasins (equipes) de la societe et de tous les comptes utilisateurs, avec changement de role inline et suppression de compte protegee par mot de passe.

**Fonctionnalites** (25)

- En-tete : h1 text-3xl font-bold tracking-tight avec icone Shield h-8 w-8 text-blue-600 + 'Super Administration'; sous-titre muted 'Gestion globale des utilisateurs et magasins'.
- Bouton 'Actualiser' (Button variant='outline' size='sm', icone RefreshCw h-4 w-4 mr-2 avec 'animate-spin' quand loading, disabled={loading}) -> fetchData().
- Bandeau statistiques : grid-cols-1 md:grid-cols-3 gap-4.
- Stat 1 'Magasins' : icone Store h-4 w-4 text-blue-500, valeur = stores.length en text-2xl font-bold.
- Stat 2 'Utilisateurs total' : icone Users h-4 w-4 text-green-500, valeur = allUsers.length.
- Stat 3 'En attente' : icone Users h-4 w-4 text-orange-500, valeur = allUsers.filter(u => !u.is_confirmed).length.
- Tableau 1 — Card 'Toutes les equipes', CardDescription '{stores.length} equipe(s) enregistree(s)'.
- Tableau 1 colonne 'Magasin' : s.shop_name, className font-medium.
- Tableau 1 colonne 'Gerant' : s.manager?.full_name || '-', en text-sm text-muted-foreground. ATTENTION : `manager` cote backend est en realite l'ADMIN de la societe (mag.admin), pas le compte role='magasin'.
- Tableau 1 colonne 'Membres' : memberCount = (s.employers?.length || 0) + (s.manager ? 1 : 0), en text-sm. Ne compte PAS mag.user (le vrai gerant) ni les co-admins.
- Tableau 1 colonne 'Statut' : Badge variant='outline'; isActive = !!s.manager?.is_confirmed -> 'Actif' avec classes 'text-green-700 border-green-200', sinon 'Inactif' avec 'text-orange-700 border-orange-200'.
- Tableau 1 : key de ligne = s.magasin_id. Aucune action par ligne (pas d'edition, pas de suppression de magasin, pas de lien vers le detail magasin).
- Tableau 2 — Card 'Tous les utilisateurs', CardDescription '{allUsers.length} compte(s) enregistre(s)'.
- Construction de allUsers : stores.flatMap(s => [ s.manager ? {...s.manager, shop_name: s.shop_name} : null, ...(s.employers||[]).map(e => ({...e, shop_name: s.shop_name})) ]).filter(Boolean) — donc uniquement manager + employers, PAS les co-admins presents dans s.company_users, et sans dedoublonnage.
- Tableau 2 colonne 'Nom' : u.full_name, font-medium.
- Tableau 2 colonne 'Email' : u.email, text-sm text-muted-foreground.
- Tableau 2 colonne 'Magasin' : u.shop_name || '-', text-sm.
- Tableau 2 colonne 'Role' : Select shadcn inline (SelectTrigger className='w-32 h-7 text-xs', SelectValue) — CHANGE LE ROLE IMMEDIATEMENT au onValueChange, sans confirmation.
- Options du Select : value='admin' libelle 'Admin', value='magasin' libelle 'Gerant', value='employer' libelle 'Commercial'.
- Le Select est disabled si changingRole === u.id (appel en cours) OU si u.role === 'admin' (un compte admin liste ici est toujours le fondateur de la societe; l'action ne serait jamais autorisee cote backend, donc le controle est desactive plutot que supprime pour garder la mise en page des colonnes).
- Tableau 2 colonne 'Statut' : Badge variant='outline' — u.is_confirmed -> 'Actif' (text-green-700 border-green-200), sinon 'En attente' (text-orange-700 border-orange-200). NOTE : le libelle 'inactif' du tableau 1 devient 'En attente' ici pour la meme donnee is_confirmed.
- Tableau 2 colonne 'Actions' : bouton Trash2 (Button variant='ghost' size='icon' className='h-7 w-7 text-red-500 hover:text-red-700') affiche UNIQUEMENT si u.role !== 'admin'; il ouvre la modale de suppression via setDeleteTarget({ id: u.id, name: u.full_name }). Pour un admin la cellule est vide.
- Aucune creation d'utilisateur, aucune invitation, aucune approbation de compte en attente, aucune edition d'email/telephone depuis cette page.
- Aucun rafraichissement temps reel (pas de useRealtimeRefresh) — la seule mise a jour est fetchData() apres une action ou via le bouton Actualiser.
- Constante roleLabel = { admin:'Administrateur', magasin:'Gerant', employer:'Commercial' } declaree en haut du fichier mais JAMAIS UTILISEE (code mort) — les libelles reels du Select sont 'Admin' / 'Gerant' / 'Commercial'.

**Formulaires** (2)

- Formulaire inline 'changement de role' (le Select de la colonne Role) : 1 champ (role, valeurs admin|magasin|employer), pas de validation cliente, pas de confirmation. Soumission implicite au changement de valeur -> handleChangeRole(u.id, v). Pendant l'appel : setChangingRole(userId) desactive le Select de cette ligne. Apres succes : toast.success('Role modifie') puis fetchData() (rechargement complet, donc reaffichage des 3 skeletons puisque fetchData fait setLoading(true)). Apres echec : toast.error(err.message || 'Erreur') et la valeur affichee revient a l'ancienne apres le refetch.
- Formulaire de la modale ConfirmDeleteDialog (composant partage) : 1 champ 'Votre mot de passe' (id='confirm-delete-password', type='password', autoComplete='current-password', placeholder '••••••••', autoFocus, required, disabled pendant l'envoi). Validation cliente : si mot de passe vide -> setError('Mot de passe requis.') et pas d'appel API. Le bouton de soumission est disabled tant que le champ est vide ou qu'un envoi est en cours. Le message d'erreur (client ou serveur) s'affiche en <p className='text-sm text-red-600'> sous le champ, et est efface a chaque frappe. Apres succes : le champ est vide, la modale se ferme, toast.success('Utilisateur supprime'), puis fetchData(). Apres echec : la modale RESTE OUVERTE avec l'erreur inline (err.message || 'Erreur lors de la suppression.') — AUCUN toast d'erreur ici.

**Modales / dialogs / drawers** (7)

- ConfirmDeleteDialog (composant partage /home/garrix/Dev/Smartphone/frontend/components/confirm-delete-dialog.tsx) : open={!!deleteTarget}, onOpenChange={(open) => !open && setDeleteTarget(null)}.
- Titre passe : 'Supprimer cet utilisateur' — rendu en DialogTitle flex items-center gap-2 text-red-600 avec icone ShieldAlert h-5 w-5.
- Description riche (ReactNode) : 'Vous etes sur le point de supprimer definitivement <span class="font-medium text-foreground">{deleteTarget?.name}</span>. Cette action est irreversible. Entrez votre mot de passe pour confirmer.'
- DialogContent className='sm:max-w-md'. La fermeture (Echap / clic exterieur / bouton Annuler) est BLOQUEE tant que loading===true (handleOpenChange fait un return anticipe).
- Bouton 'Annuler' : type='button', variant='outline', disabled pendant l'envoi; a la fermeture le mot de passe et l'erreur sont reinitialises.
- Bouton de confirmation : type='submit', variant='destructive', libelle 'Supprimer definitivement'; pendant l'envoi il affiche un Loader2 h-4 w-4 mr-2 animate-spin + 'Suppression...'; disabled={loading || !password}.
- Aucun dropdown/popover/menu contextuel ailleurs sur la page (hormis le SelectContent du Select de role, qui est un popover Radix).

**Recherche, filtres, tri, pagination** (2)

- AUCUNE recherche, AUCUN filtre (ni par role, ni par statut, ni par magasin), AUCUN tri de colonne, AUCUNE pagination — les deux tableaux affichent l'integralite des donnees renvoyees.
- L'ordre des lignes est celui de l'API (magasins puis, dans allUsers, manager avant employers pour chaque magasin).

**Appels API** (4)

- GET /users/magasins/users/ — via djangoClient.get('/users/magasins/users/'). Renvoie un tableau d'objets { magasin_id, shop_name, shop_logo, manager:{id, full_name, email, phone, adresse, photo, is_confirmed, role, last_login_at, last_logout_at}|null, employers:[{id, full_name, email, phone, adresse, photo, is_confirmed, position, role, commande_role, last_login_at, last_logout_at}], company_users:[...] }. Alimente les 3 stats et les 2 tableaux.
- PUT /users/role/{userId}/ body { role: 'admin'|'magasin'|'employer' } — change le role d'un utilisateur. Refus backend possibles : role invalide (400), utilisateur introuvable (404), 'Vous ne pouvez pas modifier votre propre role' (400), 'Seul le fondateur de la societe peut gerer les administrateurs.' (403), 'Action impossible sur le fondateur de la societe.' (403), 'Permission refusee : cet utilisateur n'appartient pas a votre entreprise.' (403).
- DELETE /users/delete/{userId}/ body { password } — supprime definitivement un compte. Refus backend : 'Mot de passe requis pour confirmer la suppression.' (400), 'Mot de passe incorrect.' (400), 'Vous ne pouvez pas vous supprimer vous-meme' (400), 'Utilisateur introuvable' (404), 'Seul le fondateur de la societe peut retirer un administrateur.' (403), 'Permission refusee : cet employe n'appartient pas a votre magasin.' (403).
- GET /users/me/ — via useCurrentUser, pour resoudre isSuperAdmin.

**Etats UI** (9)

- loading (userLoading || loading) : TOUTE la page est remplacee par un div p-6 space-y-4 contenant 3 <Skeleton className='h-16 w-full' /> — l'en-tete et les stats disparaissent aussi.
- Ce meme skeleton plein ecran reapparait apres CHAQUE changement de role et CHAQUE suppression, car fetchData() fait setLoading(true) (pas de mode silencieux ici).
- empty : AUCUN etat vide implemente — si stores est vide, on voit deux tableaux avec un header et zero ligne, et les descriptions '0 equipe(s) enregistree(s)' / '0 compte(s) enregistre(s)'.
- error de chargement : catch { console.error(err) } uniquement — pas de toast, pas de bandeau, pas de retry. stores reste a sa valeur precedente.
- error changement de role : toast.error(err.message || 'Erreur').
- error suppression : message inline rouge dans la modale (pas de toast).
- success : toast.success('Role modifie') / toast.success('Utilisateur supprime').
- unauthorized : pas d'ecran dedie — redirection router.replace('/dashboard') sans aucun message.
- disabled : bouton Actualiser pendant loading; Select de role si changingRole===u.id ou u.role==='admin'; boutons de la modale pendant l'envoi.

**Details UX** (7)

- Codes couleur des badges : Actif / vert (text-green-700 border-green-200) ; Inactif ou En attente / orange (text-orange-700 border-orange-200). Badges en variant='outline' (fond transparent), contrairement aux badges pleins de /alerts et /pickup.
- Deux libelles differents pour la meme donnee is_confirmed : 'Actif'/'Inactif' dans le tableau des equipes, 'Actif'/'En attente' dans le tableau des utilisateurs.
- Le Select de role est tres compact (w-32 h-7 text-xs) : en Flutter, prevoir un DropdownButton dense ou un bottom sheet sur mobile.
- Toasts sonner globaux : top-right, richColors, closeButton, expand, duree 5000 ms.
- Aucun temps reel : contrairement a /alerts et /pickup, aucune souscription WebSocket ici.
- Aucun format numerique special (pas d'Intl) : les compteurs sont affiches bruts.
- Conteneur global : div p-6 space-y-6; tableaux dans des Card sans conteneur overflow-x (6 colonnes -> deborde sur mobile, a repenser en liste de cartes en Flutter).

### `/notifications`

- **Fichier Next.js** : `frontend/app/(app)/notifications/page.tsx`
- **Groupe d'audit** : `notifications`
- **Cible Flutter** : lib/features/notifications/notifications_screen.dart
- **Etat** : PARTIAL

**Role et gating.** AUCUN guard dans la page elle-meme. Le composant est un 'use client' sans useCurrentUser, sans verification de role, sans redirection. Le gating est fait a 2 niveaux exterieurs : (1) /home/garrix/Dev/Smartphone/frontend/app/(app)/layout.tsx : useEffect -> si !djangoClient.isAuthenticated() (= pas de tokens.access en localStorage 'django_tokens') alors router.replace('/login'). C'est un guard client-side apres montage, donc la page flashe une fraction de seconde avant redirection. (2) /home/garrix/Dev/Smartphone/frontend/components/layout/sidebar.tsx : l'entree de menu {label:'Notifications', href:'/notifications', icon:Bell, adminOnly:true} est filtree par `if (item.adminOnly && !isAdminOrSuperAdmin) return false`. isAdminOrSuperAdmin = (role==='admin' || role==='magasin') = GERANT. Donc PREPARATEUR et LIVREUR (role==='employer' + commande_role) ne voient PAS le lien dans la sidebar, mais l'URL reste accessible directement (aucun 403 cote UI). Pendant le chargement du user (loading===true) la sidebar affiche tous les items non-superAdminOnly, donc le lien Notifications apparait brievement meme pour un employer. Le vrai cloisonnement est cote backend (users/views.py::NotificationViewSet.get_queryset) : admin -> Q(magasin__admins=user)|Q(user=user) ; magasin -> Q(magasin=son MagasinProfile)|Q(user=user) ; employer -> Q(magasin=employer.magasin)|Q(user=user), sinon Q(user=user).

**Objectif.** Page 'Historique des notifications' : liste plein ecran de toutes les notifications visibles par l'utilisateur, avec marquage lu/non-lu unitaire et global, suppression unitaire et globale, et indicateur de connexion temps reel WebSocket.

**Fonctionnalites** (18)

- En-tete : titre h1 'Notifications' (text-2xl sm:text-3xl font-bold tracking-tight)
- En-tete : sous-titre muted 'Toutes les alertes et mouvements enregistres de l'application.'
- En-tete : Badge d'etat du socket temps reel (variant outline, text-[10px], rounded-full py-0.5 px-2.5) avec 3 rendus distincts : 'connected' -> pastille verte animee (span animate-ping bg-emerald-400 opacity-75 + point plein bg-emerald-500) + libelle 'Temps reel' ; 'connecting' -> icone Loader2 animate-spin h-3 w-3 + libelle 'Connexion...' ; 'disconnected' -> icone AlertCircle h-3 w-3 + libelle 'Deconnecte'
- Bouton 'Actualiser' (variant outline, size sm) -> relance fetchNotifications(), remet loading=true (les skeletons reapparaissent). disabled si loading || actionLoading
- Bouton 'Marquer tout lu' (variant secondary, size sm) -> markAllRead(). disabled si loading || actionLoading || notifications.length===0
- Bouton 'Supprimer tout' (variant destructive, size sm) -> clearAll(). disabled si loading || actionLoading || notifications.length===0. AUCUNE confirmation : suppression serveur immediate et irreversible
- Card avec CardHeader/CardTitle 'Historique des notifications' englobant toute la liste
- Liste verticale (space-y-3) de cartes notification, une par element, PAS de tableau, PAS de colonnes
- Carte notification : classe conditionnelle via getNotificationCardClass(is_read) -> lue = 'bg-muted/40 border-border' ; non lue = 'bg-primary/5 border-primary/30 shadow-sm'. rounded-xl border p-4 transition-all duration-300
- Carte : pastille ronde 9x9 (bg-primary/10 text-primary, shrink-0) contenant l'icone du type via typeIcon(notif_type)
- Carte : message de la notification (text-sm font-medium, break-words)
- Carte : Badge de type (variant outline + getTypeBadgeClass(notif_type)) affichant typeLabel(notif_type)
- Carte : Badge 'Nouveau' (bg-primary/15 text-primary hover:bg-primary/20) affiche UNIQUEMENT si !is_read
- Carte : ligne meta (text-xs muted, mt-2, break-words) construite par concatenation conditionnelle — voir uxDetails pour la regle exacte
- Carte : bouton icone toggle lu/non-lu (size icon, variant outline) : icone Mail si is_read===true (=> action 'remettre non lu'), icone CheckCheck si is_read===false (=> action 'marquer lu'). disabled si actionLoading
- Carte : bouton icone suppression (size icon, variant destructive, icone Trash2) -> deleteNotification(id) immediatement, SANS confirmation. disabled si actionLoading
- Temps reel : nouvelle notification recue par WebSocket -> ajoutee en tete de liste (prepend) avec deduplication par id ; declenche un toast.info
- Aucun onglet, aucun switch, aucun toggle group, aucun raccourci clavier, aucun export, aucune selection multiple (les endpoints bulk-read / bulk-delete existent dans le client mais ne sont PAS utilises par cette page)

**Formulaires** (1)

- Aucun formulaire sur cette page : pas d'input, pas de textarea, pas de select, pas de validation, pas de soumission. Toutes les interactions sont des boutons d'action directe.

**Modales / dialogs / drawers** (1)

- Aucun Dialog / AlertDialog / Drawer / Sheet / Popover / DropdownMenu / ConfirmDialog dans cette page. Les actions destructives ('Supprimer tout', suppression unitaire) s'executent SANS aucune confirmation. Les seuls elements 'flottants' sont les toasts sonner globaux (Toaster monte dans app/layout.tsx).

**Recherche, filtres, tri, pagination** (4)

- Aucune recherche, aucun champ de filtre, aucun filtre par type/statut lu, aucun selecteur de tri, aucune pagination, aucun infinite scroll, aucun 'charger plus'.
- Tri : impose par le backend (users/models.py::Notification.Meta.ordering = ['-created_at'], plus recent en premier). Le front ne re-trie jamais.
- Les notifications arrivees par WebSocket sont inserees en tete de tableau (index 0), donc avant les elements du fetch, sans re-tri par date.
- Pas de pagination cote serveur non plus : REST_FRAMEWORK n'a pas de DEFAULT_PAGINATION_CLASS, l'endpoint renvoie un tableau brut. Le front gere quand meme les 2 formes : `Array.isArray(data) ? data : data.results || []`.

**Appels API** (9)

- GET /api/users/notifications/ — djangoClient.notifications.list() — charge l'historique complet visible par l'utilisateur (filtre par role cote backend). Reponse : tableau de NotificationSerializer ou objet {results:[...]}
- PATCH /api/users/notifications/{id}/ body {is_read: boolean} — djangoClient.notifications.markRead(id, !is_read) — bascule lu/non-lu d'une notification. Le backend (partial_update) ne modifie QUE is_read et renvoie l'objet serialise
- POST /api/users/notifications/mark-all-read/ — djangoClient.notifications.markAllRead() — marque lues TOUTES les notifications du queryset visible. Reponse {message:'Toutes les notifications marquees comme lues.'}
- POST /api/users/notifications/delete-all/ — djangoClient.notifications.deleteAll() — supprime en base TOUTES les notifications du queryset visible. Reponse 204 No Content
- DELETE /api/users/notifications/{id}/ — djangoClient.notifications.delete(id) — supprime une notification. Le backend applique une regle de permission specifique (voir notes) et peut repondre 403 {'error':'Permission refusee'}
- WS ws(s)://{host}/ws/notifications/?token={access_token} — push temps reel des nouvelles notifications (voir sharedComponents useNotificationsWebSocket). Host derive de NEXT_PUBLIC_DJANGO_API_URL (defaut http://localhost:8010/api) : protocole retire puis split('/')[0]. wss si la page est en https
- POST /api/users/refresh/ body {refresh} — appele automatiquement par djangoClient sur toute reponse 401, puis la requete est rejouee une fois
- GET /api/users/me/ — pas appele par la page mais par useCurrentUser dans Sidebar et TopBar qui l'entourent (fournit role + commande_role)
- NON UTILISES par cette page mais disponibles dans le client : POST /api/users/notifications/bulk-read/ {ids:[]} et POST /api/users/notifications/bulk-delete/ {ids:[]}

**Etats UI** (7)

- loading (initial + a chaque Actualiser / toggleRead / markAllRead) : 5 <Skeleton className='h-20 w-full rounded-lg' /> empiles (space-y-3). Skeleton = div bg-accent animate-pulse rounded-md
- empty : bloc centre 'Aucune notification pour le moment.' (py-16 text-center text-muted-foreground)
- error de chargement : console.error('Notifications error:', error) + toast.error('Impossible de charger les notifications.'). La liste precedente est conservee telle quelle (au 1er chargement -> etat vide affiche). Pas de bloc d'erreur inline, pas de bouton 'Reessayer' dedie (l'utilisateur doit cliquer Actualiser)
- actionLoading : passe a true pendant toggleRead / markAllRead / clearAll / deleteNotification -> desactive les 3 boutons d'en-tete ET les 2 boutons de chaque carte. Aucun spinner visuel sur les boutons, juste l'etat disabled
- success : uniquement via toasts (voir uxDetails), aucun etat de succes persistant a l'ecran
- unauthorized : AUCUN etat gere dans la page. Un 401 declenche le refresh automatique du token dans djangoClient.request ; si le refresh echoue -> window.location.href = '/login' (hard redirect depuis lib/django-client.ts). Un 403 backend (suppression refusee, 'Permission refusee') remonte comme une Error generique et se traduit par le toast 'Impossible de supprimer la notification.'
- socket : 3 etats explicites 'connecting' | 'connected' | 'disconnected' materialises par le badge d'en-tete uniquement (aucun blocage de l'UI)

**Details UX** (18)

- Ligne meta — regle exacte de composition (chaine concatenee, pas de separateur si vide) : premiere partie = `Produit : {product_name}` si product_name, SINON `Vente #{sale_id}` si sale_id, SINON `Utilisateur : {user_name}` si user_name, SINON chaine vide. Puis ` · Magasin : {magasin_name}` si magasin_name. Puis ` · {date formatee}` si created_at
- ATTENTION : product_name et sale_id N'EXISTENT PAS dans NotificationSerializer (champs reels : id, notif_type, message, magasin, magasin_name, caisse_session, user, user_name, is_read, created_at). Ces 2 branches sont donc mortes via l'API REST ; seul `Utilisateur : ...` peut s'afficher
- Format de date (formatNotificationDate) : new Date(value).toLocaleString('fr-FR', {day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) -> ex '10/09/2026 14:32'. Pas de secondes, pas de 'il y a X minutes'
- Couleurs des badges de type (getTypeBadgeClass) : sale=vert (bg-green-500/10 text-green-700 dark:text-green-400 border-green-500/20), product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange, defaut=bg-muted text-muted-foreground border-border
- Icones par type (typeIcon, lucide 4x4) : sale=Package, user=User, product=Mail, chat=MessageSquare, transfer=ArrowLeftRight, movement=ArrowUpDown, defaut=Bell
- Libelles de type (typeLabel) : sale='Vente', product='Produit', user='Utilisateur', chat='Chat', transfer='Transfert', movement='Mouvement', defaut='Autre'
- Couleurs du badge socket (getSocketStatusBadgeClass) : connected=emeraude, connecting=ambre, disconnected=rose
- Toast nouvelle notification temps reel : toast.info(newNotif.message, {description: `Type : ${typeLabel(notif_type)}`, duration: 5000}) — declenche a l'interieur du updater de setNotifications, donc UNIQUEMENT si l'id n'est pas deja present
- Toast toggle lu : toast.success('Notification marquee non lue') si elle etait lue, toast.success('Notification marquee lue') si elle etait non lue
- Toast erreur toggle : toast.error('Impossible de mettre a jour la notification.')
- Toast tout lu : toast.success('Toutes les notifications ont ete marquees comme lues.') / erreur : toast.error('Impossible de marquer toutes les notifications comme lues.')
- Toast tout supprimer : toast.success('Toutes les notifications ont ete supprimees.') / erreur : toast.error('Impossible de supprimer les notifications.')
- Toast suppression unitaire : toast.success('Notification supprimee.') / erreur : toast.error('Impossible de supprimer la notification.')
- Toast erreur chargement : toast.error('Impossible de charger les notifications.')
- Configuration globale du Toaster (app/layout.tsx) : sonner, position='top-right', richColors, closeButton, expand, toastOptions.duration=5000
- Strategie de rafraichissement asymetrique : toggleRead() et markAllRead() font `await fetchNotifications()` (donc setLoading(true) -> les skeletons remplacent la liste, flash visuel a chaque clic). clearAll() fait setNotifications([]) sans refetch. deleteNotification() filtre localement sans refetch
- Layout responsive : conteneur p-4 sm:p-6 space-y-6 ; en-tete flex-col gap-4 md:flex-row md:items-center md:justify-between ; carte flex-col gap-3 md:flex-row md:items-start md:justify-between ; boutons d'action flex-wrap gap-2 shrink-0
- Thematisation : toutes les couleurs passent par les tokens shadcn (primary, muted, destructive, border) + variantes dark: explicites sur les badges de type. Le theme se change depuis la TopBar (next-themes, defaultTheme='system')

### `(global) TopBar — cloche de notifications (dropdown)`

- **Fichier Next.js** : `frontend/components/notifications.tsx`
- **Groupe d'audit** : `notifications`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** AUCUN gating de role. Le composant <Notifications /> est monte inconditionnellement dans /home/garrix/Dev/Smartphone/frontend/components/layout/topbar.tsx (ligne 57), elle-meme montee dans app/(app)/layout.tsx pour TOUTES les pages authentifiees. Donc GERANT (admin/magasin), PREPARATEUR et LIVREUR voient tous la cloche et recoivent tous les toasts temps reel, meme si PREPARATEUR/LIVREUR n'ont pas acces au lien /notifications dans la sidebar. Le filtrage du contenu est purement backend (meme get_queryset que la page).

**Objectif.** Cloche de notifications globale dans la barre du haut : compteur de non-lues, apercu des 8 dernieres notifications, marquage lu (unitaire et global), effacement LOCAL de la liste, lien vers la page complete, et emission des toasts temps reel pour toute l'application.

**Fonctionnalites** (17)

- Declencheur : Button variant='ghost' size='icon' className='relative' contenant l'icone Bell h-5 w-5
- Badge compteur : span absolute -top-0.5 -right-0.5, h-4 min-w-4, rounded-full, bg-destructive, text-[10px] font-bold text-destructive-foreground. Affiche unreadCount, ou '9+' si unreadCount > 9. Masque totalement si unreadCount === 0
- Contenu du dropdown : DropdownMenuContent align='end' className='w-96 p-0'
- DropdownMenuLabel : titre 'Notifications' (font-semibold) + Badge variant='secondary' text-[10px] '{n} non lue' / '{n} non lues' (pluriel si >1), affiche uniquement si unreadCount > 0
- Barre d'actions (visible uniquement si notifications.length > 0, border-b) : 2 boutons ghost sm h-7 flex-1 text-xs
- Bouton 'Tout marquer lu' (icone Check h-3.5 w-3.5) -> markAllAsRead(). disabled si unreadCount === 0 || actionLoading. Garde supplementaire en debut de fonction : `if (unreadCount === 0 || actionLoading) return;`
- Bouton 'Tout effacer' (icone Trash2 h-3.5 w-3.5, hover:text-destructive) -> clearAll(). ATTENTION : ne supprime RIEN en base ; masque seulement localement (voir notes). Garde : `if (notifications.length === 0) return;`. Jamais disabled visuellement
- Liste : ScrollArea max-h-96 contenant AU MAXIMUM les 8 premieres notifications (`notifications.slice(0, 8)`)
- Item : DropdownMenuItem avec onSelect={(e)=>e.preventDefault()} -> cliquer sur un item NE FERME PAS le menu et ne navigue nulle part (cursor-default). rounded-none border-b px-4 py-3, last:border-b-0
- Item : pastille ronde 8x8 avec typeIcon(notif_type) ; fond conditionnel : lue = 'bg-muted text-muted-foreground', non lue = 'bg-primary/10 text-primary'
- Item : message text-sm leading-snug line-clamp-2 (tronque a 2 lignes) ; style conditionnel : lue = 'text-muted-foreground', non lue = 'font-medium'
- Item : point bleu de non-lu (span mt-1 h-2 w-2 rounded-full bg-primary) affiche uniquement si !is_read
- Item : Badge variant='outline' text-[10px] + getTypeBadgeClass(notif_type) avec typeLabel(notif_type)
- Item : date formatee (text-[10px] text-muted-foreground) affichee uniquement si created_at present
- Item : bouton texte 'Marquer lu' (ml-auto text-[10px] font-medium text-primary hover:underline) affiche uniquement si !is_read -> markAsRead(id)
- Pied : DropdownMenuSeparator puis DropdownMenuItem asChild justify-center text-sm font-medium contenant un Link Next vers /notifications, libelle 'Voir toutes les notifications'. Toujours affiche, meme quand la liste est vide
- Temps reel : useNotificationsWebSocket({onNotification: handleNewNotification, showToast: true}) -> c'est CE composant qui emet le toast.info global de toute l'application pour chaque notification poussee

**Formulaires** (1)

- Aucun formulaire, aucun champ de saisie.

**Modales / dialogs / drawers** (3)

- DropdownMenu (Radix, composants ui/dropdown-menu) — le seul overlay : declencheur cloche, contenu w-96 aligne a droite, DropdownMenuLabel d'en-tete, DropdownMenuItem par notification (selection neutralisee), DropdownMenuSeparator, DropdownMenuItem final 'Voir toutes les notifications'.
- ScrollArea Radix (max-h-96) imbriquee dans le dropdown pour le defilement de la liste.
- Aucune confirmation pour 'Tout effacer' (mais l'action n'est que locale, donc non destructive cote donnees).

**Recherche, filtres, tri, pagination** (3)

- Aucun filtre, aucune recherche, aucun tri configurable.
- Troncature fixe a 8 elements affiches (slice(0,8)) — pas de pagination ni de 'voir plus', le lien vers /notifications joue ce role.
- Filtre implicite : toutes les notifications dont l'id est dans localStorage 'stockv2_dismissed_notification_ids' sont retirees, aussi bien au fetch qu'a l'arrivee WebSocket.

**Appels API** (5)

- GET /api/users/notifications/ — chargement initial de la liste (puis filtrage local des ids 'dismissed')
- PATCH /api/users/notifications/{id}/ {is_read:true} — markAsRead(id) : marque UNE notification lue (jamais de retour a non-lu ici, contrairement a la page)
- POST /api/users/notifications/mark-all-read/ — markAllAsRead() : marque tout lu cote serveur puis mise a jour optimiste locale (map is_read:true), SANS refetch
- WS ws(s)://{host}/ws/notifications/?token={access} — reception temps reel + emission du toast global (showToast:true)
- AUCUN appel de suppression : 'Tout effacer' n'appelle ni delete ni delete-all, il ecrit uniquement dans localStorage

**Etats UI** (7)

- loading : spinner Loader2 h-5 w-5 animate-spin centre, py-8, text-muted-foreground. Note : loading n'est jamais remis a true apres le 1er chargement (pas de bouton actualiser ici)
- empty : bloc centre avec icone Bell h-8 w-8 opacity-30 + texte 'Aucune notification' (px-4 py-10 text-sm text-muted-foreground)
- error de chargement : uniquement console.error('Notifications error:', error), AUCUN toast, AUCUN affichage d'erreur — l'utilisateur voit simplement l'etat vide
- error markAsRead : console.error('Mark read error:', error), silencieux pour l'utilisateur
- error markAllAsRead : console.error('Mark all read error:', error), silencieux
- actionLoading : desactive le bouton 'Tout marquer lu' pendant l'appel
- Aucun etat unauthorized gere ; le hook WS ne se connecte simplement pas si djangoClient.isAuthenticated() est faux

**Details UX** (8)

- Persistance locale : cle localStorage 'stockv2_dismissed_notification_ids', valeur = tableau JSON d'ids. Ecriture bornee aux 200 derniers (`ids.slice(-200)`), donc au-dela de 200 ids masques les plus anciens ressortent de l'oubli et reapparaissent dans la cloche
- Lecture defensive : loadDismissed() renvoie [] si window indefini ou si le JSON est invalide (try/catch)
- Compteur unreadCount = notifications.filter(n=>!n.is_read).length calcule sur la liste DEJA filtree des dismissed -> une notification non lue masquee localement ne compte plus dans le badge, alors qu'elle reste non lue en base et comptera sur la page /notifications
- Toast temps reel emis ici pour toute l'app : toast.info(message, {description:`Type : ${typeLabel(notif_type)}`, duration:5000})
- DOUBLON DE TOAST sur /notifications : la cloche (showToast:true) et la page (toast dans son propre handleNewNotification) sont montees simultanement -> 2 toasts identiques pour la meme notification poussee
- Mises a jour optimistes : markAsRead et markAllAsRead modifient l'etat local sans refetch, donc la cloche et la page peuvent diverger jusqu'au prochain rechargement
- Aucun rechargement periodique / polling : la fraicheur depend uniquement du WebSocket et du montage du composant
- La cloche est rendue a gauche du bouton de theme et du menu utilisateur dans la TopBar (flex items-center gap-3), barre sticky top-0 z-10 h-16 px-6 avec border-b

### `/`

- **Fichier Next.js** : `frontend/app/page.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : lib/features/auth/splash_screen.dart
- **Etat** : DONE

**Role et gating.** PUBLIC — aucun gating. Server Component pur, aucun appel a useCurrentUser ni a djangoClient. Ne verifie PAS si un token existe : meme un utilisateur deja connecte est renvoye sur /login (c'est /login qui, lui, ne re-redirige pas automatiquement — voir notes).

**Objectif.** Racine de l'application. Redirection serveur immediate (next/navigation `redirect`) vers /login. Aucun rendu visuel.

**Fonctionnalites** (3)

- `redirect('/login')` execute cote serveur — reponse HTTP 307, jamais de flash de contenu
- metadata.title = 'E-kajy Entana'
- Aucun bouton, aucun etat, aucun contenu rendu (la fonction ne retourne rien apres redirect)

**Etats UI** (1)

- Aucun etat UI — redirection instantanee

**Details UX** (1)

- Equivalent Flutter : route initiale '/' qui fait un `Navigator.pushReplacementNamed('/login')` ou un redirect GoRouter sans splash

### `/login`

- **Fichier Next.js** : `frontend/app/login/page.tsx + frontend/components/auth/login-form.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : lib/features/auth/login_screen.dart
- **Etat** : PARTIAL

**Role et gating.** PUBLIC — aucun guard, aucun useCurrentUser. Le role n'intervient qu'APRES login reussi pour choisir la destination : `rawRole = response.user.raw_role` ; `isGerant = rawRole === 'admin' || rawRole === 'magasin'` -> redirige vers /dashboard ; sinon (employer = PREPARATEUR/LIVREUR) -> /orders. Commentaire du code : le tableau de bord est reserve au gerant, les autres roles demarrent sur Commandes (page qui s'adapte deja a leur role Depot / Ma tournee).

**Objectif.** Ecran de connexion par email + mot de passe. Point d'entree unique de l'app (toutes les redirections non authentifiees y menent).

**Fonctionnalites** (13)

- Page serveur : conteneur plein ecran `min-h-screen flex items-center justify-center bg-gradient-to-br from-background to-muted p-4`
- `<Suspense fallback={null}>` autour de LoginForm (necessaire car LoginForm utilise useSearchParams) — donc AUCUN skeleton pendant l'hydratation
- metadata.title = 'Connexion - E-kajy Entana'
- Carte centree `max-w-md shadow-xl` : titre 'Connexion' (text-2xl font-bold), description 'Accedez a votre espace E-kajy Entana'
- Champ Email avec icone Mail (lucide) positionnee en absolute a gauche (pl-10), pointer-events-none
- Champ Mot de passe avec icone Lock a gauche (pl-10) et bouton oeil a droite (pr-10)
- Bouton toggle visibilite du mot de passe : icone Eye / EyeOff, `type=button`, `tabIndex={-1}`, aria-label dynamique 'Masquer le mot de passe' / 'Afficher le mot de passe' — bascule input type password <-> text
- Lien 'Mot de passe oublie ?' (text-xs, primary, hover:underline) place a droite du label Mot de passe, sur la meme ligne -> /forgot-password
- Bouton submit pleine largeur 'Se connecter' ; en cours de chargement affiche `<Loader2 animate-spin>` + texte 'Connexion…' et devient disabled
- Lien bas de carte : 'Pas encore de compte? Creer un compte' -> /register
- Pre-remplissage automatique de l'email depuis le query param `?email=` (useEffect sur searchParams -> setEmail)
- `noValidate` sur le <form> : la validation HTML native est desactivee, donc les attributs `required` ne bloquent PAS la soumission — on peut soumettre vide et l'erreur vient du backend
- Navigation apres succes via `router.push(destination)` (helper `goTo`)

**Formulaires** (1)

- Formulaire 'Connexion' (handleLogin). CHAMPS : (1) email — id `login-email`, type=email, autoComplete=email, placeholder 'vous@example.com', required (inoperant car noValidate), disabled pendant loading, pre-rempli par ?email= ; (2) password — id `login-password`, type password|text selon showPw, autoComplete=current-password, placeholder '••••••••', required (inoperant), disabled pendant loading. AUCUNE validation cote client (pas de longueur min, pas de regex email) : tout est delegue au backend. SOUMISSION : e.preventDefault() -> setLoading(true) -> djangoClient.auth.login(email, password). SUCCES : si `!response.user.is_confirmed` -> toast.error('Compte en attente d\'approbation. Contactez votre manager.') + setLoading(false) + return (PAS de redirection, mais les tokens restent en localStorage) ; sinon toast.success('Connexion reussie !') puis push vers /dashboard (admin|magasin) ou /orders (autres). ERREUR : toast.error(friendlyError(message)). `finally` remet toujours loading a false.

**Modales / dialogs / drawers** (1)

- Aucun modal / dialog / drawer / popover sur cette page. Les seuls retours utilisateur sont des toasts Sonner (Toaster global monte dans app/layout.tsx)

**Appels API** (3)

- POST /users/login/ — body {email, password}. Retourne {access, refresh}. Les tokens sont IMMEDIATEMENT persistes dans localStorage sous la cle 'django_tokens' ({access, refresh}) par djangoClient.saveTokensToStorage AVANT toute autre verification
- GET /users/me/ — appele automatiquement dans la foulee par djangoClient.auth.login() pour construire l'objet `user` retourne au formulaire (mapping role: admin->admin, magasin->store_manager, employer->employee ; ajoute raw_role, is_approved = is_confirmed, is_confirmed, company_name, shop_name, magasin_id, position, first_name/last_name derives de full_name.split(' '))
- POST /users/refresh/ — body {refresh} : rafraichissement automatique du token sur toute reponse 401 (djangoClient.request). Si le refresh echoue : localStorage vide + `window.location.href = '/login'` (redirection dure, hors router Next)

**Etats UI** (6)

- loading : etat booleen unique — desactive les deux inputs ET le bouton submit, remplace le libelle du bouton par spinner + 'Connexion…'
- error : PAS d'affichage inline — uniquement via toast.error (rouge, richColors)
- success : toast.success('Connexion reussie !') puis navigation
- unauthorized / compte non approuve : toast.error, on reste sur la page
- empty : non applicable
- Aucun skeleton (Suspense fallback = null)

**Details UX** (5)

- TABLE DE TRADUCTION DES ERREURS (`ERRORS`, matching par `msg.includes(key)`, premiere cle qui matche gagne, sinon le message brut backend est affiche tel quel) : 'Invalid login credentials' -> 'Email ou mot de passe incorrect.' ; 'No active account found' -> 'Email ou mot de passe incorrect.' ; 'Email not confirmed' -> 'Compte non confirme. Contactez l\'administrateur.' ; 'Compte non approuve' -> 'Compte en attente d\'approbation. Contactez votre administrateur.' ; 'User not found' -> 'Aucun compte avec cet email.' ; 'Too many requests' -> 'Trop de tentatives. Attendez quelques minutes.' ; 'Account pending approval' -> 'Compte en attente d\'approbation. Contactez votre manager.' ; 'Account rejected' -> 'Compte rejete. Contactez votre manager.' ; 'Authentication failed' -> 'Email ou mot de passe incorrect.'
- Toasts : position top-right, richColors, closeButton, expand, duration 5000ms (config globale du <Toaster> dans app/layout.tsx)
- Fond degrade `bg-gradient-to-br from-background to-muted`, carte `shadow-xl`
- Theme clair/sombre gere par next-themes (attribute='class', defaultTheme='system', enableSystem, disableTransitionOnChange)
- Le libelle de la marque affiche est 'E-kajy Entana' (titre metadata) alors que le titre global du layout est 'StockManager' — incoherence de branding presente dans le code

### `/register`

- **Fichier Next.js** : `frontend/app/register/page.tsx + frontend/components/auth/register-form.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** PUBLIC — aucun guard. C'est l'utilisateur qui CHOISIT son type de compte via un RadioGroup 3 options : 'admin' (libelle Admin), 'store_manager' (libelle Manager), 'employee' (libelle Employe). Valeur par defaut = 'employee'. Le client convertit ces valeurs vers les roles backend dans djangoClient.auth.register : store_manager -> 'magasin', employee -> 'employer', admin -> 'admin'.

**Objectif.** Auto-inscription. Formulaire dont les champs changent dynamiquement selon le type de compte choisi. Aboutit a un compte en attente d'approbation (sauf admin, voir notes).

**Fonctionnalites** (18)

- Page serveur, pas de Suspense (le formulaire n'utilise pas useSearchParams) ; conteneur `min-h-screen flex items-center min-w-fit justify-center bg-linear-to-br from-background to-muted p-4`
- metadata.title = 'Inscription - E-kajy Entana'
- Carte `max-w-md shadow-xl border-t-4 border-t-primary` (liseret colore en haut, distinctif vs login)
- Titre 'Creer un compte', description 'Rejoignez E-kajy Entana'
- RadioGroup 'Type de compte' en grille 3 colonnes (`grid grid-cols-3 gap-2`), chaque option est une carte bordee cliquable p-2 avec RadioGroupItem + Label
- Couleur de selection par role : admin -> `border-blue-500 bg-blue-50 dark:bg-blue-950/30` ; store_manager -> `border-cyan-500 bg-cyan-50 dark:bg-cyan-950/30` ; employee -> `border-green-500 bg-green-50 dark:bg-green-950/30` ; non selectionne -> `hover:bg-muted/50`
- Champs dynamiques apparaissant avec animation `animate-in fade-in duration-200` selon le role choisi
- role=admin : ajoute UN champ 'Nom de l'entreprise' (icone Building2)
- role=store_manager : ajoute DEUX champs — 'Nom du magasin' (Building2) et 'Email de l'administrateur' (Mail)
- role=employee : ajoute DEUX champs — 'Email du responsable (Admin ou Gerant)' (Mail) et 'Poste / Fonction' (User)
- Champ 'Nom d'utilisateur' explicitement marque (Optionnel) en text-muted-foreground text-xs
- Toggle visibilite mot de passe (Eye/EyeOff), meme mecanique que le login (type=button, tabIndex=-1, aria-label dynamique)
- Texte d'aide sous le mot de passe : 'Minimum 6 caracteres' (text-xs muted)
- Asterisque rouge `<span className='text-destructive'>*</span>` sur tous les champs obligatoires
- Bouton submit pleine largeur : "S'inscrire" ; pendant loading -> Loader2 spinner + 'Creation du compte…' et disabled
- Lien bas de carte : 'Deja un compte? Se connecter' -> /login
- `noValidate` sur le form : les `required` / `minLength={6}` HTML ne bloquent pas — toute la validation est faite en JS avant l'appel API
- Tous les inputs sont `disabled={loading}`

**Formulaires** (7)

- Formulaire 'Creer un compte' (handleRegister). CHAMPS COMMUNS : (1) role — RadioGroup, defaut 'employee' ; (2) fullName — id `reg-fullname`, type text, placeholder 'Jean Dupont', OBLIGATOIRE ; (3) username — id `reg-username`, type text, autoComplete=username, placeholder 'jean_dupont', OPTIONNEL (fallback = partie locale de l'email) ; (4) email — id `reg-email`, type email, autoComplete=email, placeholder 'vous@example.com', OBLIGATOIRE (mais pas de validation JS explicite !) ; (5) password — id `reg-password`, type password|text, autoComplete=new-password, placeholder '••••••••', minLength=6, OBLIGATOIRE.
- CHAMPS CONDITIONNELS role=admin : companyName — id `reg-companyname`, type text, placeholder 'Ma Super Entreprise', OBLIGATOIRE.
- CHAMPS CONDITIONNELS role=store_manager : shopName — id `reg-shopname`, type text, placeholder 'Boutique Centre-Ville', OBLIGATOIRE ; adminEmail — id `reg-adminemail`, type email, placeholder 'admin@boutique.com', OBLIGATOIRE.
- CHAMPS CONDITIONNELS role=employee : adminEmail — id `reg-manageremail`, type email, placeholder 'gerant@boutique.com', OBLIGATOIRE (meme state React `adminEmail` que le manager, donc la valeur est conservee si on change de role) ; position — id `reg-position`, type text, placeholder 'Caissier, Vendeur...', OBLIGATOIRE.
- VALIDATIONS CLIENT dans l'ordre exact, chacune fait toast.error + return (arret immediat, un seul message a la fois) : (a) !fullName.trim() -> 'Le nom complet est requis.' ; (b) password.length < 6 -> 'Le mot de passe doit contenir au moins 6 caracteres.' ; (c) role==='admin' && !companyName.trim() -> "Le nom de l'entreprise est requis." ; (d) role==='store_manager' && !shopName.trim() -> 'Le nom du magasin est requis.' ; (e) role==='store_manager' && !adminEmail.trim() -> "L'email de l'administrateur est requis." ; (f) role==='employee' && !adminEmail.trim() -> "L'email du responsable est requis." ; (g) role==='employee' && !position.trim() -> 'Le poste / fonction est requis.' — ATTENTION : l'EMAIL du compte lui-meme n'est JAMAIS valide cote client (ni presence ni format).
- APRES SOUMISSION REUSSIE : toast.success avec un message dependant du role — admin : "Compte cree ! En attente d'approbation." ; store_manager et employee : "Compte cree ! En attente d'approbation par un administrateur." — puis `router.push('/auth/pending-approval')`. Le formulaire n'est PAS reinitialise, aucune connexion automatique, aucun token n'est stocke.
- ERREUR : toast.error(friendlyError(message)) et on reste sur le formulaire (les valeurs saisies sont conservees).

**Modales / dialogs / drawers** (1)

- Aucun modal/dialog. Feedback exclusivement par toasts Sonner.

**Appels API** (1)

- POST /users/register/ — body {email, username (ou email.split('@')[0] si vide), password, role: 'admin'|'magasin'|'employer', full_name, company_name?, shop_name?, admin_email?, position?}. Note : le client fait `full_name: extraData?.full_name || username` PUIS spread `...extraData` — les champs non pertinents pour le role sont envoyes a `undefined` (donc absents du JSON). Reponse succes : {message: 'Inscription reussie', id}. Erreur 400 : dictionnaire de champs -> messages, aplati par djangoClient en 'champ: message | champ2: message2'

**Etats UI** (4)

- loading : tous les inputs + le bouton disabled, bouton = spinner + 'Creation du compte…'
- error : toast rouge uniquement (aucun message d'erreur inline sous les champs, aucun etat 'champ invalide' visuel)
- success : toast vert + navigation vers /auth/pending-approval
- Aucun etat empty / skeleton / unauthorized

**Details UX** (4)

- TABLE DE TRADUCTION DES ERREURS (matching par includes) : 'User already registered' -> 'Un compte existe deja avec cet email.' ; 'Password should be at least' -> 'Le mot de passe doit contenir au moins 6 caracteres.' ; 'Unable to validate email' -> 'Adresse email invalide.' ; 'Too many requests' -> 'Trop de tentatives. Attendez quelques minutes.' — sinon message backend brut (souvent du type 'admin_email: Administrateur introuvable avec cet email.' ou 'email: user with this email already exists.')
- Les erreurs backend metier les plus frequentes a prevoir : 'admin_email: Administrateur introuvable avec cet email.' (role magasin, email admin inconnu) ; 'admin_email: Responsable (administrateur ou gerant) introuvable avec cet email.' (role employer)
- Icones lucide utilisees : Loader2, Mail, Lock, User, Eye, EyeOff, Building2
- Le sous-role Commande (PREPARATEUR / LIVREUR) N'EST PAS choisissable a l'inscription : le serializer accepte `commande_role` mais le formulaire ne l'envoie jamais — il est attribue plus tard par le gerant (endpoint /users/employers/<id>/commande-role/)

### `/forgot-password`

- **Fichier Next.js** : `frontend/app/forgot-password/page.tsx + frontend/components/auth/forgot-password-form.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** PUBLIC (endpoints AllowAny). Gating METIER cote backend : le flux n'est disponible QUE pour les comptes role='magasin' (gerant de magasin) et role='employer' (preparateur/livreur/employe). Un compte role='admin' recoit une erreur 400 : "La reinitialisation automatique n'est pas disponible pour les comptes administrateur. Contactez le support technique directement." La demande est routee vers l'ADMIN de la societe qui doit l'approuver.

**Objectif.** Mot de passe oublie en 3 temps SANS email (aucun backend mail configure) : (1) l'utilisateur envoie une demande, (2) il revient plus tard verifier si son admin l'a approuvee, (3) une fois approuvee il definit lui-meme son nouveau mot de passe.

**Fonctionnalites** (12)

- Page serveur avec `<Suspense fallback={null}>` ; conteneur `min-h-screen ... bg-gradient-to-br from-background to-muted p-4`
- metadata.title = 'Mot de passe oublie - E-kajy Entana'
- Carte `max-w-md shadow-xl` ; titre avec icone KeyRound + 'Mot de passe oublie'
- MACHINE A ETATS a 2 ecrans dans la meme carte : state `step` = 'request' | 'check' (defaut 'request')
- Description de la carte dynamique : step='request' -> 'Entrez votre email : votre demande sera transmise pour validation.' ; step='check' -> 'Verifiez si votre demande a ete validee.'
- ETAPE 'request' : champ Email + bouton 'Envoyer la demande' + lien texte 'Demande deja envoyee ? Verifier le statut' (bouton type=button qui bascule step vers 'check' SANS appel API)
- ETAPE 'check' : champ Email + bouton outline 'Verifier le statut' ; puis bandeau de statut ; puis (si approuve) sous-formulaire de nouveau mot de passe ; puis lien 'Faire une nouvelle demande' (fleche ArrowLeft) qui remet step='request' ET status=null
- BANDEAU DE STATUT (affiche seulement si status non nul ET different de 'none') — 3 variantes : approved -> icone CheckCircle2, `border-green-200 bg-green-50 text-green-700 dark:bg-green-950/20 dark:text-green-400`, texte 'Demande validee : vous pouvez definir votre nouveau mot de passe.' ; pending -> icone Clock, `border-orange-200 bg-orange-50 text-orange-700 dark:bg-orange-950/20 dark:text-orange-400`, texte 'En attente de validation par votre administrateur.' ; rejected -> icone XCircle, `border-red-200 bg-red-50 text-red-700 dark:bg-red-950/20 dark:text-red-400`, texte 'Votre demande a ete rejetee. Contactez votre administrateur.'
- SOUS-FORMULAIRE 'nouveau mot de passe' visible UNIQUEMENT si status === 'approved', separe par `border-t pt-4`
- Lien permanent en bas de carte : 'Retour a la connexion' -> /login
- Les 3 formulaires utilisent la validation HTML native (PAS de noValidate ici) : `required` et `minLength=6` bloquent donc reellement la soumission
- Tous les inputs et boutons sont `disabled={loading}` ; les boutons affichent un Loader2 spinner a gauche du libelle pendant loading (libelle inchange)

**Formulaires** (3)

- FORMULAIRE 1 'Demande' (handleRequest, step='request'). CHAMP : email — id `fp-email`, type=email, placeholder 'vous@example.com', required, disabled pendant loading. Aucune validation JS. SOUMISSION : POST forgotPasswordRequest -> setStatus('pending') + setStep('check') + toast.success(res.message) (message renvoye par le BACKEND, pas en dur). ERREUR : toast.error(err.message || "Erreur lors de l'envoi de la demande"). NOTE : en cas de succes le statut est force a 'pending' localement sans relire le serveur.
- FORMULAIRE 2 'Verification du statut' (handleCheckStatus, step='check'). CHAMP : email — id `fp-check-email`, type=email, placeholder 'vous@example.com', required, disabled pendant loading (meme state React `email`, donc pre-rempli si on vient de l'etape 1). SOUMISSION : GET forgotPasswordStatus -> setStatus(res.status) ; si res.status === 'none' -> toast.error('Aucune demande trouvee pour cet email.') et le bandeau reste masque. ERREUR : toast.error(err.message || 'Erreur lors de la verification'). Bouton `variant='outline'`.
- FORMULAIRE 3 'Definir le mot de passe' (handleSetPassword, visible si status==='approved'). CHAMPS : newPassword — id `fp-new`, type=password, minLength=6, required, disabled pendant loading, PAS de toggle de visibilite ; confirm — id `fp-confirm`, type=password, required, disabled pendant loading, PAS de minLength. VALIDATION JS : `newPassword !== confirm` -> toast.error('Les mots de passe ne correspondent pas') + return. SOUMISSION : POST forgotPasswordConfirm(email, newPassword) -> toast.success('Mot de passe defini avec succes. Vous pouvez vous connecter.') + router.push('/login'). ERREUR : toast.error(err.message || 'Erreur lors de la definition du mot de passe'). Bouton 'Definir le mot de passe'.

**Modales / dialogs / drawers** (1)

- Aucun modal. Le changement d'etape se fait in-place dans la meme carte (pas de drawer ni de stepper visuel).

**Appels API** (4)

- POST /users/public/forgot-password/ — body {email}. Cree un EmployeePasswordResetRequest(status='pending') rattache a l'admin de la societe. Reponse 201 {queue:'admin', message:'Votre demande a ete transmise a votre administrateur pour validation.'}. Erreurs : 400 'Email requis.' ; 404 'Aucun compte avec cet email.' ; 400 message admin (voir roles) ; 404 'Aucun administrateur associe a ce compte.' ; 400 'Une demande est deja en attente.'
- GET /users/public/forgot-password/status/?email=<urlencoded> — reponse {status: 'none'|'pending'|'approved'|'rejected'}. Retourne 'none' si l'email est inconnu, si le compte est admin, ou si aucune demande non consommee n'existe. Prend la demande NON CONSOMMEE la plus recente (consumed_at is null, order by -created_at)
- POST /users/public/forgot-password/confirm/ — body {email, new_password}. Reponse {message:'Mot de passe mis a jour avec succes.'}. Erreurs : 400 'Le mot de passe doit contenir au moins 6 caracteres.' ; 404 'Aucun compte avec cet email.' ; 400 'Aucune demande approuvee trouvee pour cet email.' — marque la demande `consumed_at` (usage unique, non rejouable)
- COTE ADMIN (hors perimetre de cette page mais indispensable au flux) : GET /users/password-reset-requests/?status=<filtre> (liste) et PATCH /users/password-reset-requests/<id>/ body {action:'approve'|'reject'} (resolution)

**Etats UI** (6)

- loading (partage par les 3 formulaires) : inputs + boutons disabled, Loader2 spinner dans le bouton
- status = null : aucun bandeau (etat initial de l'ecran 'check')
- status = 'none' : bandeau MASQUE volontairement + toast d'erreur
- status = 'pending' / 'approved' / 'rejected' : bandeau colore correspondant
- success final : toast + redirection /login
- error : toasts uniquement, aucun message inline

**Details UX** (5)

- Pas d'email envoye du tout — c'est un flux d'approbation manuelle par l'admin, l'utilisateur doit revenir verifier lui-meme (a expliquer clairement dans l'UI Flutter)
- Le message de succes de l'etape 1 vient du serveur (`res.message`), pas d'une constante — a ne pas coder en dur
- Le bouton 'Verifier le statut' de l'ecran 'request' est un simple lien texte stylise (primary, font-medium, hover:underline), pas un Button
- 'Faire une nouvelle demande' remet a zero step + status mais CONSERVE l'email saisi
- Toute erreur backend est affichee brute si `err.message` existe (djangoClient aplati les erreurs DRF en 'cle: valeur | cle2: valeur2'). Le champ backend d'erreur est `error` (et non `detail`) pour ces 3 endpoints : djangoClient produira donc des chaines du type 'error: Une demande est deja en attente.'

### `/reset-password`

- **Fichier Next.js** : `frontend/app/reset-password/page.tsx + frontend/components/auth/reset-password-form.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** AUTHENTIFIE REQUIS et, cote backend, RESERVE AU GERANT : ChangePasswordView refuse role not in ['admin','magasin'] avec 403 {'error': 'Seul le gerant peut modifier ces informations. Contactez votre gerant.'}. AUCUN guard cote frontend : la page est accessible sans etre connecte, l'appel partira alors sans header Authorization et echouera en 401 (le client tentera un refresh, echouera, videra localStorage et fera window.location.href='/login').

**Objectif.** Changer son mot de passe en connaissant l'ancien (ce n'est PAS un reset par token/lien email malgre le nom de la route). Route ORPHELINE : aucun lien de l'application ne pointe dessus.

**Fonctionnalites** (10)

- Page serveur avec `<Suspense>` dont le fallback est un vrai composant `ResetPasswordFallback` : carte `w-full max-w-md p-8 text-center bg-card rounded-lg shadow-xl border` + `<Loader2 className='mx-auto h-8 w-8 animate-spin text-primary mb-4'>` + texte 'Chargement...' (seul ecran de chargement de type skeleton de tout le perimetre auth)
- metadata.title = 'Reinitialiser le mot de passe - E-kajy Entana'
- Conteneur `min-h-screen flex items-center justify-center bg-linear-to-br from-background to-muted p-4`
- Carte `w-full max-w-md` (PAS de shadow-xl, contrairement aux autres cartes auth)
- Titre avec icone Lock : 'Changer le mot de passe' ; description : 'Entrez votre mot de passe actuel et votre nouveau mot de passe'
- 3 champs empiles + bouton pleine largeur
- AUCUN toggle de visibilite des mots de passe (les 3 champs restent type=password)
- Le formulaire n'a PAS `noValidate` : la validation HTML native s'applique (required sur les 3, minLength=6 sur le nouveau)
- Les inputs ne sont PAS disabled pendant le chargement (seul le bouton l'est) — l'utilisateur peut modifier les champs pendant l'appel
- Aucun lien de retour vers /login ni ailleurs sur cette page

**Formulaires** (1)

- Formulaire 'Changer le mot de passe' (handleSubmit). CHAMPS : (1) oldPassword — id `old`, label 'Mot de passe actuel', type=password, required ; (2) newPassword — id `new`, label 'Nouveau mot de passe', type=password, minLength=6, required ; (3) confirm — id `confirm`, label 'Confirmer', type=password, required, PAS de minLength. VALIDATION JS : `newPassword !== confirm` -> toast.error('Les mots de passe ne correspondent pas') + return (le controle de longueur min est laisse au navigateur/backend). SOUMISSION : setLoading(true) -> POST -> toast.success('Mot de passe change avec succes') -> router.push('/login') (l'utilisateur est renvoye a l'ecran de connexion MAIS ses tokens ne sont PAS effaces : il reste techniquement authentifie en localStorage). ERREUR : toast.error(err.message || 'Erreur lors du changement'), on reste sur la page, champs conserves.

**Modales / dialogs / drawers** (1)

- Aucun modal ni confirmation.

**Appels API** (1)

- POST /users/change-password/ — appel direct `djangoClient.post(...)` (pas via l'objet auth), body {old_password, new_password}. Reponse succes {message:'Mot de passe change avec succes'}. Erreurs backend : 403 {'error':'Seul le gerant peut modifier ces informations. Contactez votre gerant.'} ; 400 {'detail':'Champs requis manquants'} ; 400 {'detail':'Mot de passe actuel incorrect'} ; 400 {'detail':'Le mot de passe doit contenir au moins 6 caracteres'}

**Etats UI** (5)

- Suspense fallback : carte 'Chargement...' avec spinner Loader2 (seul vrai etat loading de page du perimetre)
- loading (submit) : le bouton passe de 'Changer le mot de passe' a 'Changement...' et devient disabled ; PAS de spinner icone ici (texte seul)
- error : toast rouge
- success : toast vert + redirection /login
- unauthorized : non gere cote UI — se traduit par une erreur toast avec le message backend, ou par une redirection dure vers /login declenchee par l'intercepteur 401 du client

**Details UX** (3)

- Nom de route trompeur : /reset-password = changement de mot de passe authentifie ; le vrai 'mot de passe oublie' est /forgot-password
- Route morte : elle n'est referencee par aucun Link/router.push du frontend (a confirmer avec le produit avant de la porter en Flutter)
- Message d'erreur du backend porte par la cle `error` pour le 403 (aplati par djangoClient en 'error: Seul le gerant...') et par `detail` pour les 400 (affiche tel quel)

### `/verify-email`

- **Fichier Next.js** : `frontend/app/verify-email/page.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** PUBLIC — Server Component 100% statique, aucun guard, aucun hook, aucun state, aucun appel API.

**Objectif.** Page d'information 'Verifiez votre email' apres une inscription supposant un lien de confirmation. Route ORPHELINE : aucun lien ni redirection de l'app n'y mene (l'inscription renvoie vers /auth/pending-approval), et AUCUN backend d'email n'est configure dans le projet.

**Fonctionnalites** (8)

- Conteneur `min-h-screen flex items-center justify-center bg-muted/30 p-4` (fond uni muted/30, pas de degrade)
- Carte `w-full max-w-md shadow-xl text-center`
- Pastille ronde centree `mx-auto bg-primary/10 w-16 h-16 rounded-full` contenant l'icone Mail `h-8 w-8 text-primary`
- Titre 'Verifiez votre email' (text-2xl font-bold)
- Description : 'Un lien de confirmation vous a ete envoye.'
- Paragraphe explicatif (text-sm muted) : 'Veuillez cliquer sur le lien dans l'email pour activer votre compte. Si vous ne le voyez pas, verifiez vos courriers indesirables.'
- UN SEUL bouton : `variant='outline'`, pleine largeur, `asChild` autour d'un Link -> /login, contenu : icone ArrowLeft (mr-2 h-4 w-4) + 'Retour a la connexion'
- Pas de metadata exportee (herite du title global 'StockManager')

**Etats UI** (1)

- Aucun etat : page purement statique

**Details UX** (2)

- Aucun bouton 'Renvoyer l'email' n'existe
- A NE PROBABLEMENT PAS PORTER en Flutter tel quel : le produit ne verifie pas les emails, il utilise l'approbation manuelle par l'admin

### `/pending-approval`

- **Fichier Next.js** : `frontend/app/pending-approval/page.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : AUCUN
- **Etat** : MISSING

**Role et gating.** PUBLIC — Server Component statique, aucun guard, aucun hook, aucun appel API. N'affiche AUCUNE donnee du compte.

**Objectif.** Page d'attente d'approbation, version courte. Route ORPHELINE en entree (rien ne redirige vers elle — l'inscription pointe sur /auth/pending-approval) mais c'est le SEUL endroit de l'app qui pointe vers /logout.

**Fonctionnalites** (10)

- Conteneur `min-h-screen flex items-center justify-center bg-muted/30 p-4`
- Carte `w-full max-w-md shadow-xl text-center`
- Pastille ronde `mx-auto bg-amber-100 w-16 h-16 rounded-full` avec icone Clock `h-8 w-8 text-amber-600` (couleur ambre = attente ; note : pas de variante dark ici)
- Titre 'Compte en attente' (text-2xl font-bold)
- Description : 'Votre acces doit etre approuve par un administrateur.'
- Paragraphe : 'Merci de votre patience. Un administrateur examine actuellement votre demande. Vous recevrez un acces complet des que votre compte sera approuve.'
- BOUTON 1 (primaire, pleine largeur) libelle 'Actualiser la page' — mais c'est en realite un `<Link href='/login'>` : il NE rafraichit PAS le statut, il renvoie vers la connexion (libelle trompeur, a corriger/adapter en Flutter)
- BOUTON 2 `variant='ghost'` pleine largeur `text-muted-foreground` : icone LogOut + 'Se deconnecter' -> Link vers /logout
- Les deux boutons sont empiles dans un `flex flex-col gap-2`
- Pas de metadata exportee

**Etats UI** (1)

- Aucun etat : page statique, aucun polling du statut d'approbation

**Details UX** (2)

- Code couleur attente : amber-100 / amber-600
- Aucune verification periodique du statut (pas de polling, pas de websocket) — l'utilisateur doit re-tenter une connexion manuellement

### `/auth/pending-approval`

- **Fichier Next.js** : `frontend/app/auth/pending-approval/page.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** PUBLIC — Server Component statique, aucun guard, aucun hook, aucun appel API. C'est la page d'arrivee REELLE apres une inscription reussie (router.push depuis register-form).

**Objectif.** Page d'attente d'approbation, version detaillee avec explication du processus en 3 etapes. Doublon fonctionnel de /pending-approval.

**Fonctionnalites** (10)

- metadata : title "En attente d'approbation", description "Votre compte est en attente d'approbation par un administrateur"
- Conteneur `min-h-screen flex items-center justify-center bg-gradient-to-b from-background to-muted/20 p-4` (degrade vertical, different des autres pages auth)
- Carte `w-full max-w-md shadow-xl`, header `text-center pb-6`
- Pastille `bg-amber-100 dark:bg-amber-950 p-3 rounded-full` avec icone Clock `h-8 w-8 text-amber-600 dark:text-amber-400` (variantes dark gerees, contrairement a /pending-approval)
- Titre 'En attente d'approbation' (text-2xl) ; description 'Votre compte doit etre approuve par un administrateur'
- ENCADRE INFO ambre : `bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-800 rounded-lg p-4` — sous-titre en gras avec icone Mail : "Qu'est-ce qui se passe maintenant?"
- LISTE NUMEROTEE (numeros en gras, texte amber-800/amber-200) : 1. 'Un administrateur examinera votre demande d'inscription' ; 2. 'Vous recevrez une notification par email une fois approuve' ; 3. 'Vous pourrez vous connecter avec vos identifiants'
- Paragraphe muted : "Le processus d'approbation peut prendre quelques minutes a quelques heures selon la disponibilite de l'administrateur."
- UN SEUL bouton : `variant='outline'` pleine largeur 'Retour a la connexion' dans un `<Link href='/login' className='block'>` (le Link enveloppe le Button, pattern different du `asChild` utilise ailleurs)
- PAS de bouton de deconnexion ici (contrairement a /pending-approval)

**Etats UI** (1)

- Aucun etat : page statique, pas de polling

**Details UX** (3)

- Palette ambre complete avec variantes dark (amber-50/100/200/800/950, texte amber-600/800/900/100/200/400)
- Le point 2 promet une notification par email alors qu'AUCUN backend d'email n'est configure — promesse non tenue par le systeme (regle metier a verifier avant portage)
- Deux pages 'pending approval' coexistent avec des contenus differents : a unifier en une seule route Flutter

### `/logout`

- **Fichier Next.js** : `frontend/app/logout/page.tsx`
- **Groupe d'audit** : `auth`
- **Cible Flutter** : lib/widgets/topbar.dart (action de deconnexion)
- **Etat** : PARTIAL

**Role et gating.** Aucun gating. Client Component ('use client'). Accessible meme sans session (l'appel logout est tolerant aux erreurs).

**Objectif.** Route-action de deconnexion : purge la session locale, notifie le backend, puis renvoie sur /login. Referencee uniquement depuis /pending-approval.

**Fonctionnalites** (4)

- useEffect au montage (dependance [router]) : appelle `djangoClient.auth.logout()` PUIS `router.push('/login')` PUIS `router.refresh()`
- BUG A CONNAITRE : `djangoClient.auth.logout()` est async mais n'est PAS await — la navigation demarre avant la fin de la purge (le `localStorage.clear()` peut s'executer apres la redirection)
- Rendu : `<div className='flex items-center justify-center min-h-screen'><p className='text-muted-foreground'>Deconnexion...</p></div>` — un simple texte, sans spinner
- Pas de metadata, pas de bouton, pas d'interaction

**Modales / dialogs / drawers** (1)

- Aucune confirmation de deconnexion (ni sur cette route, ni depuis la sidebar/topbar)

**Appels API** (2)

- POST /users/logout-event/ — enregistre l'horodatage de deconnexion sur le dernier LoginEvent de l'utilisateur (best-effort ; l'echec est seulement `console.warn`, il n'interrompt pas la deconnexion). Reponse {message:'Deconnexion enregistree'}
- POST /users/refresh/ — body {refresh} : appel supplementaire effectue pendant le logout (recupere le refresh depuis this.tokens ou directement depuis localStorage['django_tokens']), echec ignore (console.warn). Ce token n'est pas blackliste cote serveur — appel sans effet utile

**Etats UI** (1)

- Un unique ecran transitoire avec le texte 'Deconnexion...'

**Details UX** (3)

- EFFET DE BORD MAJEUR : `localStorage.clear()` — vide TOUT le localStorage du domaine, pas seulement la cle 'django_tokens' (toute preference/cache stocke par d'autres ecrans est detruit). Puis `this.tokens = null` en memoire
- Il n'y a AUCUNE invalidation serveur du JWT (commentaire explicite du backend) : un token deja emis reste valide jusqu'a expiration
- Le meme `djangoClient.auth.logout()` est aussi declenche par le bouton Deconnexion de la Sidebar (avec await + router.push('/login') + router.refresh()) et de la TopBar (sans await, + router.push('/login'))

### `/* (RootLayout — enveloppe TOUTES les pages, y compris /login, /register, /forgot-password, /reset-password, /verify-email, /pending-approval)`

- **Fichier Next.js** : `frontend/app/layout.tsx`
- **Groupe d'audit** : `layout-nav`
- **Cible Flutter** : lib/main.dart + lib/core/router.dart (redirect global)
- **Etat** : PARTIAL

**Role et gating.** AUCUN gating. Layout racine serveur (pas de 'use client'), aucun appel a useCurrentUser, aucun guard. Il s'applique aux routes publiques ET privees. Le seul gating de l'app se trouve dans app/(app)/layout.tsx.

**Objectif.** Layout racine Next.js : <html lang="fr" suppressHydrationWarning> + <body class="font-sans antialiased">. Installe le ThemeProvider (next-themes), le Toaster global sonner, et Vercel Analytics en production. Definit les metadata et les favicons de l'application.

**Fonctionnalites** (11)

- metadata.title = 'StockManager' (titre d'onglet global, jamais surcharge par les layouts enfants du perimetre)
- metadata.description = 'Gestion de stock intelligente'
- metadata.generator = 'v0.app'
- Favicons : /icon-light-32x32.png avec media '(prefers-color-scheme: light)', /icon-dark-32x32.png avec media '(prefers-color-scheme: dark)', /icon.svg type image/svg+xml, apple = /apple-icon.png (fichiers presents dans /public)
- Polices Google chargees : Geist({subsets:['latin']}) et Geist_Mono({subsets:['latin']}) — assignees a des variables _geist / _geistMono JAMAIS utilisees dans le JSX ; la police est en realite appliquee par le token CSS --font-sans: 'Geist','Geist Fallback' de globals.css (et --font-mono: 'Geist Mono')
- ThemeProvider avec attribute="class" (ajoute la classe .dark sur <html>), defaultTheme="system", enableSystem, disableTransitionOnChange (pas d'animation lors du changement de theme)
- Toaster sonner global rendu a l'interieur du ThemeProvider, apres {children} — commentaire code : 'Toast global — visible sur toutes les pages'
- Toaster: position="top-right", richColors (couleurs semantiques success/error/info/warning), closeButton (croix de fermeture sur chaque toast), expand (toasts empiles deplies), toastOptions.duration = 5000 ms
- Le Toaster (components/ui/sonner.tsx) recupere le theme via useTheme() (defaut 'system') et injecte les variables CSS --normal-bg: var(--popover), --normal-text: var(--popover-foreground), --normal-border: var(--border) + className 'toaster group'
- <Analytics/> de @vercel/analytics/next rendu UNIQUEMENT si process.env.NODE_ENV === 'production'
- import { GlobalErrorBoundary } present ligne 6 mais le composant N'EST JAMAIS RENDU dans le JSX — code mort, l'error boundary n'est actif nulle part dans l'app (verifie par grep sur tout le repo)

**Etats UI** (2)

- Aucun etat React (composant serveur pur, pas de loading/empty/error)
- Etat d'erreur global THEORIQUE via GlobalErrorBoundary — non branche (voir features)

**Details UX** (6)

- Langue du document : fr
- suppressHydrationWarning sur <html> pour eviter le warning d'hydratation du au theme injecte par next-themes
- body: font-sans antialiased
- Palette de tokens definie dans app/globals.css : :root (clair) --background oklch(1 0 0), --foreground oklch(0.145 0 0), --primary oklch(0.205 0 0), --destructive oklch(0.577 0.245 27.325), --radius 0.625rem ; .dark (sombre) --background oklch(0.145 0 0), --foreground oklch(0.985 0 0), --primary oklch(0.985 0 0), --destructive oklch(0.396 0.141 25.723)
- Tokens sidebar dedies : --sidebar / --sidebar-foreground / --sidebar-primary / --sidebar-accent / --sidebar-border / --sidebar-ring (clair et sombre) — utilises seulement par components/ui/sidebar.tsx (non utilise)
- Rayons derives : --radius-sm = radius-4px, --radius-md = radius-2px, --radius-lg = radius, --radius-xl = radius+4px

### `/(app)/* — shell applicatif protege (couvre /dashboard, /orders, /pickup, /bilan, /products, /caisse, /chats, /movements, /alerts, /suppliers, /transfers, /notifications, /reports, /stores, /users, /settings, /sales, /superadmin)`

- **Fichier Next.js** : `frontend/app/(app)/layout.tsx`
- **Groupe d'audit** : `layout-nav`
- **Cible Flutter** : lib/widgets/navigation_shell.dart
- **Etat** : PARTIAL

**Role et gating.** Gating d'AUTHENTIFICATION seulement, aucun gating de role a ce niveau. useEffect(() => { if (!djangoClient.isAuthenticated()) router.replace('/login') }, [router]). djangoClient.isAuthenticated() retourne simplement !!this.tokens?.access (token JWT lu depuis localStorage cle 'django_tokens' au constructeur du client). Aucun controle d'expiration du token, aucune verification de role, aucun appel serveur. Le gating par role est fait exclusivement dans la Sidebar (masquage des liens) et dans chaque page.

**Objectif.** Layout client du groupe (app) : redirige vers /login si non authentifie, monte le DataSyncProvider (WebSocket temps reel), et compose la coque Sidebar + TopBar + zone de contenu scrollable.

**Fonctionnalites** (6)

- 'use client' — layout client
- Redirection /login via router.replace (remplace l'entree d'historique, pas de retour arriere possible)
- DataSyncProvider englobe tout le shell : ouvre un WebSocket /ws/data/?token=<access> et expose { socketStatus, subscribe(listener) } a toutes les pages enfants
- Structure : <div class="flex h-screen bg-background"> [Sidebar] <div class="flex-1 flex flex-col overflow-hidden"> [TopBar] <main class="flex-1 overflow-auto">{children}</main> </div> </div>
- Hauteur fixee a h-screen : seule la zone <main> defile, la TopBar (sticky) et la Sidebar (h-screen) restent fixes
- Aucun ecran de chargement / splash pendant la verification d'auth : les children sont montes immediatement, donc flash possible de contenu protege avant la redirection

**Appels API** (2)

- WebSocket ws(s)://<host de NEXT_PUBLIC_DJANGO_API_URL>/ws/data/?token=<access> — flux de synchronisation temps reel (via DataSyncProvider)
- GET /users/me/ — declenche indirectement par useCurrentUser dans Sidebar et TopBar (deux appels distincts, un par composant, pas de cache partage)

**Etats UI** (3)

- unauthorized : redirection client vers /login (aucun ecran intermediaire, aucun toast)
- Aucun loading/skeleton/empty/error gere a ce niveau
- socketStatus du DataSyncProvider : 'connecting' | 'connected' | 'disconnected' — expose mais NON affiche dans ce layout (aucun indicateur visuel de connexion dans la coque)

**Details UX** (4)

- bg-background sur le conteneur racine (suit le theme clair/sombre)
- overflow-hidden sur la colonne droite + overflow-auto sur <main> : le scroll est interne, la page ne scrolle jamais globalement
- Reconnexion WebSocket automatique du DataSync apres 3000 ms si le code de fermeture != 1000 ; fermeture propre (code 1000) au demontage
- Modeles pousses par /ws/data/ : product_variant, stock_movement, order, order_status_history, supplier_order, caisse_session, caisse_movement ; actions : created | updated | deleted ; payload { model, action, id, magasin_id }

### `/(app)/* — Sidebar de navigation (rendue sur toutes les routes du groupe (app))`

- **Fichier Next.js** : `frontend/components/layout/sidebar.tsx`
- **Groupe d'audit** : `layout-nav`
- **Cible Flutter** : lib/core/nav_items.dart + lib/widgets/navigation_shell.dart
- **Etat** : PARTIAL

**Role et gating.** Gating par role via useCurrentUser() qui expose { user, isAdmin, isSuperAdmin, isAdminOrSuperAdmin, isPreparateur, isLivreur, loading }. Definitions reelles (lib/auth/useCurrentUser.ts) : isAdmin = role==='admin' ; isSuperAdmin = role==='admin' (STRICTEMENT IDENTIQUE a isAdmin) ; isAdminOrSuperAdmin = role==='admin' || role==='magasin' ; isGerant = admin||magasin ; isPreparateur = role==='employer' && commande_role==='PREPARATEUR' ; isLivreur = role==='employer' && commande_role==='LIVREUR'. Le filtre du menu : if (loading) return !item.superAdminOnly ; if (item.superAdminOnly && !isSuperAdmin) return false ; if (item.adminOnly && !isAdminOrSuperAdmin) return false ; if (item.hidePreparateur && isPreparateur) return false ; if (item.hideLivreur && isLivreur) return false ; if (item.livreurOnly && !isLivreur) return false ; return true.

**Objectif.** Navigation principale laterale : logo/nom du magasin ou de la societe, liste de liens filtree par role, bouton de deconnexion. Responsive : tiroir coulissant + overlay en mobile, colonne fixe a partir de lg (1024px).

**Fonctionnalites** (30)

- Bouton bascule mobile : Button variant=ghost size=icon, positionne fixed left-4 top-4 z-40, classe lg:hidden ; icone X (h-5 w-5) si ouvert, sinon Menu (h-5 w-5) ; onClick => setOpen(!open)
- Etat local `open` (useState(false)) : uniquement pour le tiroir mobile, non persiste (pas de cookie/localStorage)
- Overlay mobile : div fixed inset-0 bg-black/50 z-20 lg:hidden backdrop-blur-sm, rendu seulement si open ; clic => setOpen(false)
- Bloc logo (p-6, border-b) : carre 40x40 rounded-lg, degrade from-blue-500 to-cyan-600 (dark: from-blue-400 to-cyan-500), shadow-lg, overflow-hidden, contenant une <img> object-cover alt='Logo'
- Source du logo : user?.store_logo || URL Cloudinary codee en dur 'https://res.cloudinary.com/dxj0d1v3g/image/upload/v1697040915/valheri-wear/logo_2x_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1.png' (fallback marque Valheri Wear)
- Titre h1 : user?.store_name || (isAdmin ? 'Societe' : 'Valheri Wear') — text-lg font-bold tracking-wide, truncate, max-w-[140px]
- Sous-titre fixe : 'Smart kajy' (text-xs, slate-500 / dark slate-400)
- Item de menu 1 : 'Tableau de bord' -> /dashboard, icone BarChart3, flag adminOnly
- Item 2 : 'Commandes' -> /orders, icone ShoppingCart, AUCUN flag (visible par tous les roles)
- Item 3 : 'Recuperation' -> /pickup, icone PackageCheck, flag adminOnly
- Item 4 : 'Bilan du jour' -> /bilan, icone Receipt, flag livreurOnly (invisible meme pour l'admin)
- Item 5 : 'Produits' -> /products, icone Shirt, flag hideLivreur
- Item 6 : 'Caisse' -> /caisse, icone Wallet, flags hidePreparateur + hideLivreur
- Item 7 : 'Chats' -> /chats, icone MessageCircle, AUCUN flag (tous les roles)
- Item 8 : 'Mouvements' -> /movements, icone TrendingUp, flag adminOnly
- Item 9 : 'Alertes' -> /alerts, icone AlertCircle, flag adminOnly
- Item 10 : 'Fournisseurs' -> /suppliers, icone Truck, flag adminOnly
- Item 11 : 'Transferts' -> /transfers, icone ArrowLeftRight, flag superAdminOnly
- Item 12 : 'Notifications' -> /notifications, icone Bell, flag adminOnly
- Item 13 : 'Rapports' -> /reports, icone FileBarChart, flag adminOnly
- Item 14 : 'Magasins' -> /stores, icone Store, flag superAdminOnly
- Item 15 : 'Super Admin' -> /users, icone Shield, flag superAdminOnly (libelle 'Super Admin' mais URL /users)
- Item 16 : 'Parametres' -> /settings, icone Settings, flag superAdminOnly
- Chaque lien : <Link href> avec onClick={() => setOpen(false)} — ferme automatiquement le tiroir mobile a la navigation
- Etat actif calcule par egalite STRICTE : pathname === item.href (une sous-route comme /orders/42 ne surligne PAS 'Commandes')
- Indicateur d'actif supplementaire : pastille ronde h-2 w-2 bg-white rounded-full shadow-lg, positionnee ml-auto a droite du libelle
- Bouton 'Deconnexion' en pied de sidebar : Button variant=ghost, w-full justify-start, icone LogOut h-4 w-4 mr-2, texte slate-500 -> hover slate-900 (dark slate-400 -> white)
- handleLogout : await djangoClient.auth.logout() puis router.push('/login') puis router.refresh()
- Aucun sous-menu, aucun groupe/section, aucun accordeon, aucun badge de compteur, aucune recherche dans la sidebar
- La sidebar n'utilise PAS le kit components/ui/sidebar.tsx (implementation totalement independante)

**Modales / dialogs / drawers** (2)

- Tiroir mobile (drawer) maison : <aside> translate-x-0 / -translate-x-full + overlay bg-black/50 backdrop-blur-sm — pas de composant Sheet/Dialog radix
- Aucune confirmation avant deconnexion (action immediate)

**Recherche, filtres, tri, pagination** (1)

- Filtrage du menu par role (voir roles) — il n'y a aucune recherche, aucun tri, aucune pagination dans la sidebar

**Appels API** (4)

- GET /users/me/ — via useCurrentUser, alimente user.store_logo, user.store_name, role et commande_role qui pilotent tout le filtrage du menu
- POST /users/logout-event/ — enregistre l'evenement de deconnexion cote serveur (echec avale avec console.warn, n'empeche pas la deconnexion)
- POST /users/refresh/ — appel fetch brut avec le refresh token pendant le logout (echec avale avec console.warn)
- Effet de bord du logout : localStorage.clear() (efface TOUT le localStorage, y compris 'django_tokens' et 'stockv2_dismissed_notification_ids') puis this.tokens = null

**Etats UI** (4)

- loading (useCurrentUser.loading = true) : AFFICHE TOUS les items sauf ceux marques superAdminOnly, pour eviter le flash de menu — commentaire code : 'Pendant le chargement on affiche tout pour eviter le flash'. Consequence : un preparateur/livreur voit brievement Tableau de bord, Recuperation, Produits, Caisse, Mouvements, Alertes, Fournisseurs, Notifications, Rapports avant filtrage
- Pas de skeleton, pas d'etat vide, pas d'etat d'erreur : si GET /users/me/ echoue, useCurrentUser met user=null et loading=false => seuls les items sans flag restent (Commandes, Chats) car isSuperAdmin/isAdminOrSuperAdmin/isLivreur sont tous false ; Produits et Caisse restent aussi visibles (leurs flags sont hideXxx, faux quand user est null)
- Etat actif / inactif des liens (voir uxDetails)
- Aucun etat disabled

**Details UX** (12)

- <aside> : fixed left-0 top-0 z-30 h-screen w-64 (256 px), shadow-xl, border-r
- Fond clair : degrade lineaire from-white via-slate-50 to-slate-100, texte slate-900, bordure slate-200
- Fond sombre : degrade from-stone-950 via-stone-900 to-stone-950, texte blanc, bordure stone-800
- Transition : transition-transform duration-300 ; open => translate-x-0, ferme => -translate-x-full ; a partir de lg : lg:relative lg:translate-x-0 (toujours visible, occupe le flux)
- Bandeau logo et pied de page : degrade horizontal from-slate-50/50 to-transparent (dark from-slate-900/50), separes par border-b / border-t
- Nav : flex-1 p-4 space-y-1 overflow-y-auto (scroll interne si trop d'items)
- Lien : flex items-center gap-3 px-4 py-3 rounded-lg transition-all duration-200 group
- Lien ACTIF : degrade horizontal from-blue-600 to-blue-500, texte blanc, shadow-lg shadow-blue-500/20
- Lien INACTIF : texte slate-600, hover bg-slate-100 + texte slate-900 (dark : slate-300, hover bg-slate-800/60 + texte blanc)
- Icone : h-5 w-5, transition-transform 200 ms ; group-hover:scale-110 seulement si NON actif
- Libelle : text-sm font-medium
- Aucun tooltip, aucun mode 'icone seule' / collapse desktop : la sidebar desktop est toujours deployee a 256 px

### `/(app)/* — TopBar (barre superieure, rendue sur toutes les routes du groupe (app))`

- **Fichier Next.js** : `frontend/components/layout/topbar.tsx`
- **Groupe d'audit** : `layout-nav`
- **Cible Flutter** : lib/widgets/topbar.dart
- **Etat** : PARTIAL

**Role et gating.** Aucun gating d'affichage : la TopBar est identique pour tous les roles. useCurrentUser() est utilise uniquement pour afficher full_name, email et le libelle de role. ATTENTION : l'entree 'Mon profil' pointe vers /settings, route que la Sidebar reserve pourtant a superAdminOnly (admin) — un magasin/employer peut donc atteindre /settings par ce menu.

**Objectif.** Barre superieure sticky : cloche de notifications temps reel, bascule de theme clair/sombre, menu utilisateur (identite, role, acces profil, deconnexion).

**Fonctionnalites** (11)

- Conteneur : border-b, bg-background, sticky top-0 z-10 ; ligne interne flex items-center justify-between h-16 px-6
- Zone gauche : <div class="flex-1" /> vide — AUCUN titre de page, AUCUN fil d'Ariane, AUCUNE recherche globale
- Zone droite : flex items-center gap-3 contenant [Notifications] [bascule theme] [menu utilisateur]
- Composant <Notifications /> (voir sharedComponents et details ci-dessous)
- Bascule de theme : Button variant=ghost size=icon ; onClick => setTheme(theme === 'dark' ? 'light' : 'dark')
- Icone de bascule : Sun (h-4 w-4) si mounted && theme === 'dark', sinon Moon (h-4 w-4)
- Garde d'hydratation : useState(mounted=false) + useEffect(() => setMounted(true), []) ; avant montage l'icone est toujours Moon
- Declencheur du menu utilisateur : Button variant=ghost, relative h-8 w-8 rounded-full, contenant un Avatar h-8 w-8 avec AvatarFallback (pas d'AvatarImage : la photo de l'utilisateur n'est jamais affichee)
- Initiales : user.full_name.split(' ').filter(Boolean).map(n => n[0]).join('').toUpperCase().slice(0,2), repli 'U' si pas de full_name
- Style des initiales : bg-blue-600, texte blanc, text-xs font-semibold, cercle 32x32
- Deconnexion : djangoClient.auth.logout() appele SANS await (fire-and-forget) puis router.push('/login') immediat — pas de router.refresh() ici, contrairement a la Sidebar

**Modales / dialogs / drawers** (3)

- DropdownMenu utilisateur (radix) : DropdownMenuContent align="end" w-56 ; contenu = DropdownMenuLabel (identite) / Separator / item 'Mon profil' / Separator / item 'Deconnexion'
- DropdownMenu Notifications (radix) : DropdownMenuContent align="end" w-96 p-0, liste scrollable (voir details Notifications)
- Aucune modale de confirmation (ni pour la deconnexion, ni pour 'Tout effacer' les notifications)

**Appels API** (6)

- GET /users/me/ — via useCurrentUser (2e appel independant de celui de la Sidebar)
- POST /users/logout-event/ puis POST /users/refresh/ + localStorage.clear() — via djangoClient.auth.logout()
- GET /users/notifications/ — via le composant Notifications au montage
- PATCH /users/notifications/{id}/ {is_read:true} — marquer une notification lue
- POST /users/notifications/mark-all-read/ — tout marquer lu
- WebSocket ws(s)://<host>/ws/notifications/?token=<access> — reception temps reel des notifications

**Etats UI** (5)

- mounted / non monte : evite le mismatch d'hydratation de l'icone de theme
- user absent : affiche 'Utilisateur', email vide, aucune ligne de role, initiales 'U'
- Notifications : loading (spinner Loader2 animate-spin, py-8, texte muted), empty ('Aucune notification' + icone Bell h-8 w-8 opacity-30, px-4 py-10, centre), liste (max 8 items)
- Bouton 'Tout marquer lu' : disabled si unreadCount === 0 || actionLoading
- Aucun etat d'erreur visuel pour les notifications : les echecs sont seulement console.error ('Notifications error:', 'Mark read error:', 'Mark all read error:')

**Details UX** (21)

- Ligne d'identite du menu : nom complet (text-sm font-medium truncate) puis email (text-xs text-muted-foreground truncate) puis role en text-xs text-blue-600 font-medium mt-0.5
- Table de libelles de role : admin -> 'Administrateur', magasin -> 'Gerant de magasin', employer -> 'Commercial' ; si le role n'est pas dans la table, la valeur brute est affichee ; la ligne n'apparait que si user?.role est defini
- Le sous-role commande_role (PREPARATEUR / LIVREUR) N'EST PAS affiche dans la TopBar : un livreur est etiquete 'Commercial'
- 'Mon profil' : icone User mr-2 h-4 w-4, Link vers /settings, className cursor-pointer
- 'Deconnexion' : icone LogOut mr-2 h-4 w-4, classes text-red-600 focus:text-red-600
- Badge de notifications non lues : span absolu -top-0.5 -right-0.5, h-4 min-w-4, rounded-full, bg-destructive / text-destructive-foreground, text-[10px] font-bold ; affiche le nombre, ou '9+' si > 9 ; masque si 0
- En-tete du menu notifications : 'Notifications' en font-semibold + Badge variant=secondary text-[10px] '<n> non lue' / 'non lues' (accord au pluriel si > 1)
- Barre d'actions notifications (visible seulement si la liste n'est pas vide) : 2 boutons ghost size=sm h-7 flex-1 text-xs — 'Tout marquer lu' (icone Check h-3.5 w-3.5) et 'Tout effacer' (icone Trash2, hover:text-destructive) ; separes par border-b
- 'Tout effacer' est PUREMENT LOCAL : il ajoute les ids dans localStorage['stockv2_dismissed_notification_ids'] (conserve les 200 derniers) et vide la liste affichee — rien n'est supprime en base (commentaire code explicite)
- Element de notification : DropdownMenuItem avec onSelect preventDefault (le menu ne se ferme pas au clic), border-b, px-4 py-3, cursor-default
- Pastille d'icone 8x8 rounded-full : bg-muted/text-muted-foreground si lue, bg-primary/10 + text-primary si non lue
- Icones par type (typeIcon) : sale->Package, user->User, product->Mail, chat->MessageSquare, transfer->ArrowLeftRight, movement->ArrowUpDown, defaut->Bell (h-4 w-4)
- Libelles de type (typeLabel) : sale->'Vente', product->'Produit', user->'Utilisateur', chat->'Chat', transfer->'Transfert', movement->'Mouvement', defaut->'Autre'
- Couleurs de badge par type (getTypeBadgeClass) : sale=vert (bg-green-500/10 text-green-700 dark:text-green-400 border-green-500/20), product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange, defaut=muted
- Message : text-sm leading-snug line-clamp-2 ; muted si lue, font-medium si non lue ; point bleu 2x2 bg-primary a droite si non lue
- Date : new Date(created_at).toLocaleString('fr-FR', {day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) en text-[10px] muted
- Lien texte 'Marquer lu' (text-[10px] font-medium text-primary hover:underline, ml-auto) affiche uniquement sur les notifications non lues
- Liste limitee a notifications.slice(0, 8) dans une ScrollArea max-h-96
- Pied du menu : DropdownMenuSeparator + item centre 'Voir toutes les notifications' -> Link /notifications
- Temps reel : chaque message WebSocket declenche toast.info(message, { description: 'Type : <libelle>', duration: 5000 }) et insere la notification en tete de liste (dedoublonnage par id, ignore les ids 'dismissed')
- Reconnexion WebSocket notifications automatique apres 3000 ms si code de fermeture != 1000 ; connexion seulement si djangoClient.isAuthenticated()

### `* — GlobalErrorBoundary (composant transverse, actuellement NON monte)`

- **Fichier Next.js** : `frontend/components/global-error-boundary.tsx`
- **Groupe d'audit** : `layout-nav`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun role, aucun gating.

**Objectif.** Class component React qui capture toute erreur de rendu non interceptee dans l'arbre en dessous, declenche un toast d'erreur sonner et affiche un ecran de repli avec bouton 'Reessayer'. Le commentaire du fichier indique de le placer dans app/layout.tsx a l'interieur de <ThemeProvider> — ce n'est PAS fait (import present mais composant jamais rendu).

**Fonctionnalites** (8)

- Props : { children, fallback? } — fallback = UI de repli personnalisee (defaut : ecran de repli interne)
- State : { hasError: boolean, error: Error | null }, initialise a { false, null }
- static getDerivedStateFromError(error) => { hasError: true, error }
- componentDidCatch(error, info) : construit message = error?.message ?? 'Erreur inattendue' et detail = premiere ligne de info.componentStack.trim().split('\n')[0]
- toast.error(message, { description: detail || undefined, duration: 8000 })
- console.error('[GlobalErrorBoundary]', error, info) dans tous les environnements (commentaire : remplacer par Sentry/Datadog en production)
- handleRetry = () => this.setState({ hasError: false, error: null }) — remonte l'arbre enfant sans recharger la page
- Si props.fallback est fourni, il est rendu tel quel et le repli interne est ignore

**Etats UI** (3)

- Normal : rend simplement this.props.children
- Erreur : rend le fallback fourni, sinon l'ecran de repli interne
- Apres 'Reessayer' : retour a l'etat normal (re-render des children)

**Details UX** (5)

- Ecran de repli en styles INLINE (pas de Tailwind) : role='alert', display flex, flexDirection column, alignItems center, justifyContent center, minHeight '100dvh', gap '1rem', fontFamily 'system-ui, sans-serif', color '#ef4444'
- Icone : emoji ⚠️ en fontSize '2rem'
- Message : <p> margin 0, fontWeight 600, texte = this.state.error?.message ?? 'Une erreur est survenue'
- Bouton 'Reessayer' : padding '0.5rem 1.25rem', border '1px solid #ef4444', borderRadius '0.5rem', background transparent, color '#ef4444', cursor pointer, fontSize '0.875rem'
- Le toast d'erreur dure 8000 ms (contre 5000 ms pour les toasts standards du Toaster global)

### `* — ThemeProvider (wrapper de theme, monte dans app/layout.tsx)`

- **Fichier Next.js** : `frontend/components/theme-provider.tsx`
- **Groupe d'audit** : `layout-nav`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun role, aucun gating.

**Objectif.** Enveloppe mince ('use client') autour de NextThemesProvider de next-themes : transmet tous ses props tels quels et rend children. Fournit useTheme() a la TopBar et au Toaster sonner.

**Fonctionnalites** (3)

- export function ThemeProvider({ children, ...props }: ThemeProviderProps) => <NextThemesProvider {...props}>{children}</NextThemesProvider>
- Aucune logique propre : ni valeur par defaut interne, ni persistance custom — tout vient des props passees dans app/layout.tsx (attribute='class', defaultTheme='system', enableSystem, disableTransitionOnChange)
- Persistance geree par next-themes : cle localStorage 'theme' par defaut ; valeurs possibles 'light' | 'dark' | 'system'

**Etats UI** (1)

- theme = 'system' | 'light' | 'dark' ; resolvedTheme calcule par next-themes ; risque de mismatch d'hydratation gere par suppressHydrationWarning + le flag `mounted` dans la TopBar

**Details UX** (2)

- attribute='class' => la classe .dark est posee sur <html>, ce qui active le bloc .dark de globals.css
- disableTransitionOnChange => aucune animation de couleur lors du basculement (evite le flash de transition)

### `(aucune route) — components/ui/sidebar.tsx : kit de primitives shadcn/ui NON UTILISE dans l'application`

- **Fichier Next.js** : `frontend/components/ui/sidebar.tsx`
- **Groupe d'audit** : `layout-nav`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun gating de role. Aucun import ailleurs dans le repo (verifie : seul le fichier lui-meme reference SidebarProvider/useSidebar). C'est du code mort, la vraie sidebar est components/layout/sidebar.tsx. A ne porter en Flutter que si l'on veut reproduire un systeme de sidebar repliable generique.

**Objectif.** Kit complet de primitives de sidebar shadcn/ui : provider avec etat replie/deploye persiste en cookie, raccourci clavier, variantes desktop (offcanvas / icon / none), rendu mobile en Sheet, et ~20 sous-composants de structure (header, footer, groupes, menu, sous-menu, badges, skeleton).

**Fonctionnalites** (35)

- Constantes : SIDEBAR_COOKIE_NAME='sidebar_state', SIDEBAR_COOKIE_MAX_AGE=604800 s (7 jours), SIDEBAR_WIDTH='16rem', SIDEBAR_WIDTH_MOBILE='18rem', SIDEBAR_WIDTH_ICON='3rem', SIDEBAR_KEYBOARD_SHORTCUT='b'
- SidebarProvider : props defaultOpen=true, open (controle), onOpenChange, className, style ; etats internes _open et openMobile ; setOpen ecrit le cookie `sidebar_state=<bool>; path=/; max-age=604800`
- toggleSidebar() : bascule openMobile si isMobile, sinon open
- Raccourci clavier GLOBAL : Ctrl+B ou Cmd+B (event.key === 'b' && (metaKey || ctrlKey)) => preventDefault + toggleSidebar ; listener ajoute/retire sur window
- state derive : 'expanded' si open, sinon 'collapsed' (expose en data-state)
- Le provider enveloppe TooltipProvider delayDuration={0} et pose les variables CSS --sidebar-width et --sidebar-width-icon sur un wrapper flex min-h-svh w-full
- useSidebar() : leve l'erreur 'useSidebar must be used within a SidebarProvider.' hors contexte ; expose { state, open, setOpen, openMobile, setOpenMobile, isMobile, toggleSidebar }
- Sidebar : props side='left'|'right' (defaut left), variant='sidebar'|'floating'|'inset' (defaut sidebar), collapsible='offcanvas'|'icon'|'none' (defaut offcanvas)
- collapsible='none' : simple div bg-sidebar text-sidebar-foreground h-full w-(--sidebar-width) flex-col, non repliable
- Mode mobile (isMobile via useIsMobile, breakpoint 768 px) : rendu dans un <Sheet open={openMobile} onOpenChange={setOpenMobile}> ; SheetContent w-(--sidebar-width) avec --sidebar-width=18rem, p-0, bouton de fermeture natif masque ([&>button]:hidden), side = side
- SheetHeader en sr-only : SheetTitle 'Sidebar', SheetDescription 'Displays the mobile sidebar.' (accessibilite)
- Mode desktop : hidden md:block ; div 'sidebar-gap' qui reserve la largeur (w-0 en offcanvas replie, w-(--sidebar-width-icon) en icon) + div 'sidebar-container' fixed inset-y-0 z-10 h-svh, transition sur [left,right,width] 200 ms ease-linear
- Attributs de donnees exposes pour le style : data-state, data-collapsible, data-variant, data-side, data-slot, data-sidebar
- SidebarTrigger : Button ghost size=icon size-7 avec PanelLeftIcon + <span class='sr-only'>Toggle Sidebar</span> ; appelle onClick puis toggleSidebar
- SidebarRail : <button> invisible de 16 px sur le bord, aria-label='Toggle Sidebar', title='Toggle Sidebar', tabIndex={-1}, curseurs w-resize/e-resize selon cote et etat, onClick toggleSidebar
- SidebarInset : <main> bg-background flex-1 ; en variant=inset ajoute marge, rounded-xl et shadow-sm sur desktop
- SidebarInput : Input bg-background h-8 w-full shadow-none (champ de recherche de sidebar)
- SidebarHeader / SidebarFooter : flex flex-col gap-2 p-2
- SidebarSeparator : Separator bg-sidebar-border mx-2 w-auto
- SidebarContent : flex min-h-0 flex-1 flex-col gap-2 overflow-auto ; overflow-hidden quand collapsible=icon
- SidebarGroup : conteneur relative flex w-full min-w-0 flex-col p-2
- SidebarGroupLabel : titre de section h-8 text-xs font-medium, opacity-0 et -mt-8 quand la sidebar est repliee en mode icone ; supporte asChild
- SidebarGroupAction : bouton d'action carre 20x20 en haut a droite du groupe (top-3.5 right-3), zone de clic elargie sur mobile (after:-inset-2), masque en mode icone
- SidebarGroupContent : div w-full text-sm
- SidebarMenu : <ul> flex flex-col gap-1 ; SidebarMenuItem : <li> group/menu-item relative
- SidebarMenuButton (cva) : variantes variant='default'|'outline', size='default' (h-8 text-sm) | 'sm' (h-7 text-xs) | 'lg' (h-12 text-sm) ; props asChild, isActive (=> data-active=true : bg-sidebar-accent, font-medium, text-sidebar-accent-foreground), tooltip
- Tooltip du MenuButton : accepte une string ou les props de TooltipContent ; TooltipContent side='right' align='center', hidden si state !== 'collapsed' || isMobile (le tooltip n'apparait donc QUE en mode icone sur desktop)
- Etats disabled/aria-disabled du MenuButton : pointer-events-none + opacity-50
- SidebarMenuAction : bouton carre 20x20 a droite de l'item (top ajuste selon la taille du bouton parent : sm->top-1, default->top-1.5, lg->top-2.5) ; prop showOnHover => opacity-0 sur md, visible au hover/focus/ouvert ; masque en mode icone
- SidebarMenuBadge : pastille absolue a droite, h-5 min-w-5, text-xs font-medium tabular-nums, pointer-events-none, select-none ; masquee en mode icone
- SidebarMenuSkeleton : ligne squelette h-8 avec largeur ALEATOIRE entre 50% et 90% (Math.floor(Math.random()*40)+50, memoisee) ; prop showIcon => ajoute un Skeleton size-4 rounded-md
- SidebarMenuSub : <ul> de sous-menu avec bordure gauche (border-l, mx-3.5, px-2.5, py-0.5), masque en mode icone
- SidebarMenuSubItem : <li> group/menu-sub-item relative
- SidebarMenuSubButton : <a> h-7, tailles 'sm' (text-xs) / 'md' (text-sm, defaut), data-active pour l'etat actif, masque en mode icone
- Exports : Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupAction, SidebarGroupContent, SidebarGroupLabel, SidebarHeader, SidebarInput, SidebarInset, SidebarMenu, SidebarMenuAction, SidebarMenuBadge, SidebarMenuButton, SidebarMenuItem, SidebarMenuSkeleton, SidebarMenuSub, SidebarMenuSubButton, SidebarMenuSubItem, SidebarProvider, SidebarRail, SidebarSeparator, SidebarTrigger, useSidebar

**Formulaires** (1)

- SidebarInput : champ de saisie generique (pas de validation, pas de soumission) prevu pour une recherche dans la sidebar

**Modales / dialogs / drawers** (1)

- Sheet (radix Dialog) utilise comme tiroir mobile de la sidebar, largeur 18rem, bouton de fermeture natif masque, titre/description en sr-only

**Etats UI** (5)

- expanded / collapsed (data-state), persiste dans le cookie sidebar_state pendant 7 jours
- openMobile true/false (Sheet)
- isActive sur MenuButton et MenuSubButton (data-active=true)
- disabled / aria-disabled : pointer-events-none + opacity-50
- loading : SidebarMenuSkeleton (squelette de ligne de menu, largeur aleatoire)

**Details UX** (6)

- Largeurs : 16rem deployee, 3rem en mode icone, 18rem en tiroir mobile ; en variant floating/inset le mode icone vaut calc(var(--sidebar-width-icon) + spacing(4))
- Transitions : 200 ms ease-linear sur width et left/right
- variant='floating' : coins arrondis rounded-lg + border + shadow-sm autour du contenu interne
- group-data-[side=right]:rotate-180 sur le div de gap (miroir pour la sidebar droite)
- Raccourci clavier Ctrl/Cmd+B documente uniquement par le code (aucune aide visible a l'ecran)
- Tooltips actifs uniquement en mode icone sur desktop

### `(composant partagé) <ImageUpload /> — zone de dépôt + prévisualisation d'image`

- **Fichier Next.js** : `frontend/components/image-upload.tsx`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** AUCUN gating de rôle dans le fichier. Le composant est 100% agnostique : pas de useCurrentUser, pas de guard, pas de condition isGerant/isPreparateur/isLivreur/isAdmin. Le contrôle d'accès doit être fait par la page appelante. À noter : le composant n'est actuellement importé NULLE PART dans l'app (grep sur tout le frontend hors node_modules : aucune utilisation) — c'est un composant orphelin/prêt à l'emploi.

**Objectif.** Sélecteur d'image unique (1 seul fichier à la fois) avec glisser-déposer OU bouton parcourir, validation taille/format côté client, prévisualisation base64 et bouton pour changer l'image. Rend une Card shadcn avec CardContent pt-6.

**Fonctionnalites** (28)

- Props: onImageSelect: (file: File) => void — OBLIGATOIRE, appelée avec le File validé
- Props: maxSize?: number (en MB) — défaut 5
- Props: acceptedFormats?: string[] — défaut ['image/jpeg','image/png','image/webp']
- Props: onUploadStart?: () => void — DÉCLARÉE MAIS JAMAIS APPELÉE dans le corps du composant (prop morte)
- Props: onUploadEnd?: () => void — DÉCLARÉE MAIS JAMAIS APPELÉE (prop morte)
- 4 états locaux: dragActive (bool), preview (string|null = data URL base64), selectedFile (File|null), error (string|null)
- Rendu à deux branches mutuellement exclusives: si `preview` non nul -> vue prévisualisation ; sinon -> vue dropzone
- VUE DROPZONE — conteneur border-2 border-dashed rounded-lg p-8 text-center transition-all
- VUE DROPZONE — icône Upload (lucide) 12x12 text-slate-400 centrée, mb-3
- VUE DROPZONE — titre h3 'Déposer l’image ici' (font-semibold text-slate-900 mb-1)
- VUE DROPZONE — sous-titre 'ou cliquez pour parcourir' (text-sm text-slate-600 mb-4)
- VUE DROPZONE — bandeau d'erreur conditionnel (affiché seulement si error !== null)
- VUE DROPZONE — <input type=file> caché (className='hidden', id='image-input'), attribut accept = acceptedFormats.join(',')
- VUE DROPZONE — <label htmlFor='image-input'> enveloppant un Button variant='outline' asChild avec <span> contenant icône Upload 4x4 + texte 'Sélectionner une image'
- VUE DROPZONE — bloc d'aide bas de zone, text-xs text-slate-500 : ligne 1 'Format supporté: JPEG, PNG, WebP' (texte EN DUR, ne suit pas la prop acceptedFormats), ligne 2 'Taille maximum: {maxSize}MB' (dynamique)
- GLISSER-DÉPOSER — onDragEnter/onDragOver -> setDragActive(true) ; onDragLeave -> setDragActive(false) ; onDrop -> setDragActive(false) puis handleFile(e.dataTransfer.files[0])
- GLISSER-DÉPOSER — preventDefault + stopPropagation systématiques sur tous les événements drag/drop
- GLISSER-DÉPOSER — SEUL LE PREMIER FICHIER est pris (files[0]), un multi-drop est silencieusement tronqué
- SÉLECTION FICHIER — handleChange sur l'input : prend e.target.files[0] uniquement (l'input n'a pas l'attribut multiple)
- VUE PRÉVISUALISATION — conteneur relative w-full aspect-square bg-slate-100 rounded-lg overflow-hidden border-2 border-blue-200
- VUE PRÉVISUALISATION — next/image `fill` className='object-cover', src = data URL base64, alt='Preview'
- VUE PRÉVISUALISATION — encart infos fichier bg-slate-50 p-3 rounded border border-slate-200 : icône Check verte 4x4 + libellé 'Image sélectionnée' (text-sm font-medium text-slate-700)
- VUE PRÉVISUALISATION — nom du fichier selectedFile?.name (text-xs text-slate-600 break-all)
- VUE PRÉVISUALISATION — taille affichée en MB : (size / 1024 / 1024).toFixed(2) suivi de ' MB' (text-xs text-slate-500)
- VUE PRÉVISUALISATION — Button variant='outline' pleine largeur (w-full gap-2) avec icône X 4x4 + libellé 'Changer l’image' -> clearSelection()
- clearSelection() remet selectedFile=null, preview=null, error=null — mais NE PRÉVIENT PAS le parent (aucun onImageSelect(null) / onClear) : le parent garde l'ancien File en mémoire
- Import de Badge (@/components/ui/badge) présent mais JAMAIS utilisé dans le JSX (import mort)
- useCallback sur handleFile avec deps [onImageSelect, maxSize, acceptedFormats] — acceptedFormats étant un tableau littéral par défaut, la callback est recréée à chaque rendu si le parent ne mémoïse pas

**Formulaires** (6)

- Formulaire implicite « sélection d'image » — 1 seul champ : input type=file, id='image-input', accept={acceptedFormats.join(',')}, caché visuellement, piloté par un <label> et par le drop.
- VALIDATION 1 (taille) — condition file.size > maxSize * 1024 * 1024. Message inline (state error) : `Fichier trop volumineux (max {maxSize}MB)`. Toast : toast.error(`Fichier trop volumineux (max {maxSize}MB)`). Retourne false, le fichier est rejeté (ni selectedFile ni preview ni onImageSelect).
- VALIDATION 2 (format MIME) — condition !acceptedFormats.includes(file.type). Message inline (state error) : `Format d'image non supporté (JPEG, PNG, WebP)`. Toast : toast.error('Format d'image non supporté') — ATTENTION : le message du toast est PLUS COURT que le message inline (les deux textes diffèrent volontairement/par oubli).
- validateFile() commence toujours par setError(null) — l'erreur précédente est effacée à chaque nouvelle tentative.
- COMPORTEMENT APRÈS SUCCÈS — dans l'ordre : setSelectedFile(file) ; onImageSelect(file) appelée IMMÉDIATEMENT (avant que la preview base64 soit prête) ; puis FileReader.readAsDataURL -> onloadend -> setPreview(dataURL) ; puis toast.success(`Image "{file.name}" sélectionnée`).
- Aucun onerror n'est branché sur le FileReader ici : si la lecture échoue, la preview ne s'affiche jamais et aucune erreur n'est signalée (le parent a pourtant déjà reçu le File).

**Modales / dialogs / drawers** (1)

- Aucun modal/dialog/drawer/popover. Le seul overlay est le sélecteur de fichiers natif du navigateur, ouvert via le <label htmlFor='image-input'>.

**Appels API** (1)

- AUCUN appel réseau. Le composant ne fait aucun fetch : il valide, lit le fichier en base64 via FileReader.readAsDataURL et remonte le File brut au parent via onImageSelect(file). L'upload réel est à la charge de l'appelant (cf. lib/image-service.ts).

**Etats UI** (5)

- DROPZONE INACTIVE (état par défaut/vide) : border-slate-300 bg-slate-50, hover:border-slate-400
- DROPZONE ACTIVE (survol pendant un drag) : border-blue-500 bg-blue-50
- ERREUR : bandeau bg-red-50 text-red-700 px-3 py-2 rounded text-sm mb-4 avec icône AlertCircle 4x4 — visible UNIQUEMENT dans la branche dropzone ; si une preview est affichée, aucune erreur ne peut apparaître
- SUCCÈS / IMAGE SÉLECTIONNÉE : bascule complète vers la vue prévisualisation
- AUCUN état loading/spinner (la lecture base64 est considérée instantanée), AUCUN état disabled, AUCUN état unauthorized

**Details UX** (8)

- Toasts via `sonner` : 1 succès (sélection) + 2 erreurs possibles (taille, format)
- Double signalement d'erreur : bandeau inline persistant + toast éphémère
- Ratio d'affichage forcé carré (aspect-square) avec object-cover : les images non carrées sont rognées, pas déformées
- Taille affichée avec 2 décimales fixes (ex. « 1.37 MB »)
- Nom de fichier en break-all pour ne jamais déborder
- Transition CSS sur la bordure du dropzone (transition-all)
- Textes de l'UI en français, formats listés en dur (JPEG, PNG, WebP)
- next.config.mjs a images.unoptimized = true : les <Image> next se comportent comme de simples <img>

### `(composant partagé) <ProductImageGallery /> — galerie photos produit + QR codes`

- **Fichier Next.js** : `frontend/components/product-image-gallery.tsx`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** AUCUN gating de rôle dans le fichier : pas de useCurrentUser, pas de guard. Les droits d'écriture sont délégués par PRÉSENCE/ABSENCE DES CALLBACKS : le bouton 'Principal' n'existe que si la prop onSetPrimary est fournie, le bouton de suppression n'existe que si onDelete est fournie. C'est le seul mécanisme de permission (lecture seule = ne pas passer les callbacks). Composant actuellement importé NULLE PART dans l'app (orphelin).

**Objectif.** Affiche la galerie d'images d'un produit : une image principale sélectionnée en grand avec son QR code d'identification, des actions sur le QR (télécharger / copier les données) et une grille de vignettes cliquables avec actions par image (définir comme principale, supprimer).

**Fonctionnalites** (25)

- Props: images: ProductImage[] (id, image_url, qr_code_image?, size?, color_variant?, is_primary)
- Props: productName: string — affiché dans la description et dans les alt/QR data
- Props: productSku: string — affiché dans l'encart détails et encodé dans les données QR copiées
- Props: onDelete?: (imageId: string) => void — optionnelle, conditionne le bouton supprimer
- Props: onSetPrimary?: (imageId: string) => void — optionnelle, conditionne le bouton 'Principal'
- État local selectedImage initialisé à images.find(is_primary) || images[0] || null — CALCULÉ UNIQUEMENT AU MONTAGE (initialiseur de useState) : si la prop `images` change ensuite, la sélection n'est pas resynchronisée
- État local copiedId (string|null) pour l'animation « copié »
- EN-TÊTE (liste non vide) — CardTitle 'Galerie d’images et QR Codes', CardDescription `{images.length} image(s) - {productName}`
- BLOC PRINCIPAL — grille responsive grid-cols-1 md:grid-cols-2 gap-6, rendue seulement si selectedImage non nul
- COLONNE GAUCHE — image produit : relative w-full aspect-square bg-slate-100 rounded-lg overflow-hidden border border-slate-200, next/image fill object-cover, alt = `{productName} - {color_variant || 'Variante'}`
- COLONNE GAUCHE — Badge 'Principal' bg-blue-500 en absolute top-2 left-2, affiché uniquement si selectedImage.is_primary
- COLONNE GAUCHE — métadonnées conditionnelles text-sm text-slate-600 : ligne 'Taille: <b>{size}</b>' si size présent, ligne 'Couleur: <b>{color_variant}</b>' si color_variant présent
- COLONNE DROITE — titre h4 'Code QR d’identification' (font-semibold text-sm)
- COLONNE DROITE — QR code affiché seulement si selectedImage.qr_code_image existe : encadré bg-white p-4 border border-slate-200 rounded-lg inline-block, next/image width=200 height=200 rendu en w-48 h-48. AUCUN fallback/placeholder si le QR est absent (bloc simplement vide)
- ACTION — Button outline size='sm' 'Télécharger' avec icône Download 4x4
- ACTION — Button outline size='sm' 'Copier données' avec icône Copy 4x4 qui devient Check 4x4 pendant 2 secondes après le clic
- ENCART DÉTAILS — bg-slate-50 p-3 rounded border border-slate-200 text-xs : '<b>SKU:</b> {productSku}', '<b>ID Image:</b> {id.slice(0,8)}...' (8 premiers caractères + points de suspension), '<b>Créée:</b> {new Date().toLocaleDateString()}'
- VIGNETTES — section affichée UNIQUEMENT si images.length > 1 : séparateur border-t pt-4 + h4 'Toutes les images'
- VIGNETTES — grille grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3
- VIGNETTES — chaque vignette est un <button> carré (aspect-square, rounded-lg, overflow-hidden, border-2, transition-all) : sélectionnée -> 'border-blue-500 ring-2 ring-blue-200', non sélectionnée -> 'border-slate-200 hover:border-slate-300'. Clic -> setSelectedImage(image)
- VIGNETTES — légende text-xs text-center sous chaque image : ligne size si présent, ligne color_variant (text-slate-500) si présent
- VIGNETTES — bouton 'Principal' (variant outline, size sm, flex-1 text-xs) rendu SEULEMENT si onSetPrimary fournie ET !image.is_primary -> onSetPrimary(image.id)
- VIGNETTES — bouton suppression (variant ghost, size sm, icône X 3x3, text-red-500 hover:text-red-700) rendu SEULEMENT si onDelete fournie -> onDelete(image.id) SANS AUCUNE CONFIRMATION
- handleCopyQRData(imageId) : retrouve l'image dans le tableau, écrit dans le presse-papiers le JSON {sku: productSku, productName, imageId, timestamp: new Date().toISOString()} — NOTE: le payload copié NE contient PAS size ni color_variant, contrairement au QR généré par lib/qrcode-generator.ts
- handleDownloadQRCode(imageId) : si qr_code_image existe, crée dynamiquement un <a href={qr_code_image} download=`qrcode-{productSku}-{imageId}.png`>, l'ajoute au body, click(), le retire. Si qr_code_image absent : ne fait RIEN et n'affiche AUCUN message

**Modales / dialogs / drawers** (1)

- Aucun modal/dialog/popover/confirmation. La suppression d'une image est IMMÉDIATE au clic (pas de ConfirmDeleteDialog branché ici).

**Recherche, filtres, tri, pagination** (1)

- Aucune recherche, aucun filtre, aucun tri, aucune pagination. Les images sont affichées dans l'ordre exact du tableau reçu.

**Appels API** (1)

- AUCUN appel réseau. Le composant est purement présentationnel : toute persistance (suppression, changement d'image principale) est déléguée au parent via les callbacks onDelete / onSetPrimary.

**Etats UI** (5)

- ÉTAT VIDE — si !images || images.length === 0 : Card avec CardTitle 'Galerie d’images', CardDescription 'Aucune image ajoutée pour ce produit' et CardContent centré (text-center py-8 text-slate-500) 'Ajoutez des images pour visualiser les photos du produit et leurs codes QR'. Retour anticipé, rien d'autre n'est rendu.
- ÉTAT 1 SEULE IMAGE — le bloc principal s'affiche mais la section vignettes est masquée (condition images.length > 1)
- ÉTAT SÉLECTION — vignette active mise en évidence par bordure bleue + ring
- ÉTAT COPIÉ — icône Copy remplacée par Check pendant exactement 2000 ms (setTimeout non nettoyé au démontage)
- AUCUN état loading/skeleton, AUCUN état error, AUCUN état disabled, AUCUN état unauthorized

**Details UX** (9)

- Toast succès copie : 'QR code data copied to clipboard' — EN ANGLAIS alors que toute l'UI est en français
- Toast succès téléchargement : 'QR code downloaded' — EN ANGLAIS également
- Feedback visuel du copier : bascule d'icône Copy -> Check pendant 2 s (le libellé du bouton reste 'Copier données')
- Badge 'Principal' bleu (bg-blue-500) posé en overlay sur l'image principale
- Couleur destructive du bouton supprimer : text-red-500, hover text-red-700
- Nom de fichier de téléchargement normalisé : `qrcode-{SKU}-{imageId}.png`
- BUG/PIÈGE UX : le champ 'Créée:' affiche `new Date().toLocaleDateString()` — c'est la DATE DU JOUR, recalculée à chaque rendu, pas la vraie date de création de l'image (la donnée n'existe pas dans l'interface ProductImage)
- Format de date : toLocaleDateString() sans locale explicite -> dépend de la locale du navigateur/appareil
- ID d'image tronqué à 8 caractères pour l'affichage

### `(composant partagé) <ConfirmDeleteDialog /> — modal de suppression avec ré-authentification par mot de passe. Monté dans /superadmin et /users`

- **Fichier Next.js** : `frontend/components/confirm-delete-dialog.tsx`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Le composant lui-même n'a AUCUN gating (pas de useCurrentUser). Le gating est fait par les deux pages appelantes : (1) /superadmin — `const { isSuperAdmin, loading: userLoading } = useCurrentUser()` + useEffect qui fait router.replace('/dashboard') si !userLoading && !isSuperAdmin ; le bouton poubelle qui ouvre le dialog n'est rendu que si `u.role !== 'admin'`. (2) /users — `const { isAdmin, isManager, isCompanyOwner } = useCurrentUser()` ; la page entière est bloquée si !isManager (ligne 310) ; le bouton supprimer d'une ligne n'apparaît que si `(u.role === 'admin' ? isCompanyOwner : isAdmin) && currentUser && u.id !== currentUser.id` (on ne peut jamais se supprimer soi-même ; seul le propriétaire de la société peut supprimer un autre admin).

**Objectif.** Modal de confirmation d'action destructive qui exige que l'utilisateur COURANT ressaisisse SON PROPRE mot de passe avant de valider — remplace un confirm() navigateur qui n'offrait aucune ré-authentification (cf. commentaire JSDoc du fichier).

**Fonctionnalites** (15)

- Props: open: boolean — contrôlé par le parent (typiquement `open={!!deleteTarget}`)
- Props: onOpenChange: (open: boolean) => void
- Props: title?: string — défaut 'Confirmer la suppression' ; les deux appelants passent 'Supprimer cet utilisateur'
- Props: description?: React.ReactNode — nœud React libre (les appelants y injectent le nom en gras) ; rendu seulement si fourni
- Props: onConfirm: (password: string) => Promise<void> — DOIT throw/reject avec une Error dont le `message` sera affiché tel quel à l'utilisateur en cas d'échec
- 3 états locaux : password (string), loading (bool), error (string|null)
- DialogContent className='sm:max-w-md'
- DialogTitle en flex items-center gap-2 text-red-600 avec icône ShieldAlert h-5 w-5 + le titre
- Formulaire <form onSubmit={handleSubmit} className='space-y-4'>
- Bouton 'Annuler' : type='button', variant='outline', disabled={loading}, onClick -> handleOpenChange(false)
- Bouton 'Supprimer définitivement' : type='submit', variant='destructive', disabled={loading || !password}
- Pendant la soumission le bouton affiche <Loader2 className='h-4 w-4 mr-2 animate-spin' /> + le texte 'Suppression...'
- handleOpenChange(next) : si loading === true la fonction RETOURNE IMMÉDIATEMENT — impossible de fermer le modal (croix, Échap, clic overlay, bouton Annuler) tant que la requête est en cours
- À la fermeture (next === false) : reset password='' et error=null
- Après un succès : setPassword('') puis onOpenChange(false) — le modal se referme tout seul

**Formulaires** (9)

- Formulaire « confirmation par mot de passe » — 1 SEUL CHAMP.
- CHAMP: Label 'Votre mot de passe' (htmlFor='confirm-delete-password') + Input id='confirm-delete-password', type='password', autoComplete='current-password', placeholder='••••••••', autoFocus, required, disabled={loading}, value={password}.
- onChange du champ : setPassword(valeur) ET setError(null) — l'erreur affichée disparaît dès la première frappe.
- VALIDATION CLIENT : si !password au submit -> setError('Mot de passe requis.') et sortie anticipée (aucun appel réseau). Le bouton submit est de toute façon disabled tant que password est vide, donc ce garde-fou ne se déclenche que si le formulaire est soumis par la touche Entrée dans un cas limite.
- SOUMISSION : e.preventDefault() -> setLoading(true) -> setError(null) -> await onConfirm(password).
- SUCCÈS : setPassword('') puis onOpenChange(false) — le modal se ferme ; le message de succès (toast) est émis par la page appelante, pas par le composant.
- ÉCHEC : catch(err) -> setError(err?.message || 'Erreur lors de la suppression.') ; le modal RESTE OUVERT, le mot de passe saisi est CONSERVÉ dans le champ, l'utilisateur peut corriger et resoumettre.
- finally : setLoading(false) dans tous les cas.
- Affichage de l'erreur : <p className='text-sm text-red-600'>{error}</p> juste sous l'input.

**Modales / dialogs / drawers** (3)

- EST lui-même le dialog (Dialog + DialogContent + DialogHeader + DialogTitle + DialogDescription + DialogFooter de @/components/ui/dialog, basé sur Radix).
- Usage /superadmin : description = 'Vous êtes sur le point de supprimer définitivement <b>{deleteTarget.name}</b>. Cette action est irréversible. Entrez votre mot de passe pour confirmer.'
- Usage /users : description IDENTIQUE (même texte, même mise en forme du nom en font-medium text-foreground).

**Appels API** (3)

- Aucun appel direct : le composant ne connaît que la promesse onConfirm.
- Via /superadmin : `djangoClient.delete('/users/delete/{id}/', { password })` -> DELETE /users/delete/<id>/ avec le mot de passe dans le corps, puis toast.success('Utilisateur supprimé') et refetch de la liste.
- Via /users : `djangoClient.users.delete(id, password)` -> même endpoint DELETE /users/delete/<id>/ avec body { password }.

**Etats UI** (5)

- IDLE : bouton submit disabled tant que le champ mot de passe est vide
- LOADING : input disabled, bouton Annuler disabled, bouton submit disabled + spinner Loader2 + libellé 'Suppression...', fermeture du modal verrouillée
- ERROR : message rouge sous le champ, modal maintenu ouvert, saisie conservée
- SUCCESS : fermeture automatique + reset du champ (feedback textuel délégué au parent)
- Pas d'état empty/unauthorized (le composant n'est monté que quand la cible existe)

**Details UX** (6)

- Code couleur destructif : titre text-red-600 + icône bouclier d'alerte ShieldAlert, bouton principal variant='destructive'
- autoFocus sur le champ mot de passe à l'ouverture -> clavier ouvert immédiatement
- Libellé volontairement explicite 'Supprimer définitivement' (et non 'OK'/'Confirmer')
- Le message d'erreur serveur est affiché BRUT (err.message) — c'est le backend Django qui rédige le texte vu par l'utilisateur (ex. mot de passe incorrect)
- Aucun toast émis par le composant : succès et erreurs réseau sont respectivement toastés/affichés par la page appelante ou inline
- Verrouillage anti-double-soumission complet pendant loading

### `(composant partagé) <AIAnalysis /> — carte « Analyse IA Stratégique ». Monté en bas de la route /reports`

- **Fichier Next.js** : `frontend/components/ai-analysis.tsx`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun gating dans le composant. Gating par la page /reports : `const { isAdmin } = useCurrentUser()` — la donnée `topMagasins` n'est incluse dans le payload envoyé à l'IA QUE si isAdmin (sinon `undefined`), donc un gérant de magasin ne fait jamais analyser le classement inter-magasins. La carte elle-même est visible par tous ceux qui accèdent à /reports.

**Objectif.** Génère à la demande une analyse stratégique en texte libre (santé financière, produits, ruptures, conseils) à partir des KPI de la page Rapports, via un modèle Ollama local exposé par la route interne /api/ai/analyze.

**Fonctionnalites** (25)

- Props: data: AIAnalysisData (un seul objet, tous les champs optionnels)
- AIAnalysisData.periode?: string
- AIAnalysisData.ca?: number
- AIAnalysisData.beneficeNet?: number
- AIAnalysisData.valeurStock?: number
- AIAnalysisData.beneficeEstimeStock?: number
- AIAnalysisData.ventesImpayeesCount?: number
- AIAnalysisData.topProduits?: { name, qty, revenue?, profit? }[]
- AIAnalysisData.produitsSansMouvement?: { name }[]
- AIAnalysisData.rupturesStock?: { name, stock? }[]
- AIAnalysisData.stockBas?: { name, stock?, seuil? }[]
- AIAnalysisData.repartitionMouvements?: Record<string, number>
- AIAnalysisData.topVendeurs?: { name, revenue }[]
- AIAnalysisData.topMagasins?: { name, revenue }[]
- 3 états locaux : analysis (string, '' au départ), loading (bool), error (bool)
- Carte à dégradé : bg-gradient-to-br from-indigo-50 to-purple-50, dark:from-indigo-950/20 dark:to-purple-950/20, border-indigo-100 dark:border-indigo-900/50
- CardTitle text-lg flex items-center gap-2, couleur text-indigo-700 dark:text-indigo-400, icône Sparkles h-5 w-5, libellé 'Analyse IA Stratégique'
- CardDescription : 'Générez une analyse basée sur le CA, le bénéfice, le stock et les produits les plus vendus.'
- BOUTON PRIMAIRE 'Générer l'analyse' — rendu uniquement si (!analysis && !loading) ; classes bg-indigo-600 hover:bg-indigo-700 text-white ; icône Sparkles h-4 w-4 mr-2
- BOUTON SECONDAIRE 'Régénérer' — rendu dans l'état résultat ; size='sm', variant='outline', disabled={loading}, icône Sparkles h-3.5 w-3.5 mr-2 ; relance exactement le même appel
- Affichage du résultat : <div className='text-sm whitespace-pre-wrap leading-relaxed'> — les retours à la ligne du modèle sont préservés, aucun rendu markdown
- Couleur du résultat conditionnelle : error ? 'text-red-600 dark:text-red-400' : 'text-gray-800 dark:text-gray-200'
- Aucun bouton copier/exporter/partager le texte généré
- Aucune annulation possible pendant la génération (pas d'AbortController côté client)
- Aucune persistance : l'analyse est perdue au démontage/refresh, et n'est jamais renvoyée au backend

**Formulaires** (1)

- Aucun formulaire, aucun champ saisissable : l'unique interaction est le déclenchement du bouton.

**Modales / dialogs / drawers** (1)

- Aucun modal/dialog/popover : tout est rendu inline dans la Card.

**Appels API** (5)

- POST /api/ai/analyze — headers { 'Content-Type': 'application/json' }, body = JSON.stringify(data) tel quel. Lit `result.analysis` de la réponse. Si !res.ok -> setError(true) MAIS le texte de `result.analysis` est quand même affiché (la route renvoie son message d'erreur dans ce même champ avec un statut 500).
- (Contexte /reports, alimentant `data`) GET /sales/ via djangoClient.sales.list()
- (Contexte /reports) GET produits via djangoClient.products.list()
- (Contexte /reports) GET mouvements via djangoClient.movements.list()
- (Contexte /reports) GET /users/dashboard/ via djangoClient.get('/users/dashboard/') — seule source des chiffres coût d'achat (ca, total_profit, total_stock_value/stock_value, benefice_estime_stock)

**Etats UI** (7)

- IDLE (aucune analyse, pas de chargement) : uniquement le bouton 'Générer l'analyse'
- LOADING (skeleton) : phrase d'attente text-xs text-muted-foreground mb-1 'Génération en cours (modèle IA local — cela peut prendre plusieurs minutes)...' + 4 <Skeleton> h-4 de largeurs w-full, w-[90%], w-[80%], w-[85%]
- SUCCESS : texte de l'analyse en gris foncé + bouton 'Régénérer'
- ERROR HTTP (res.ok === false) : même mise en page que success mais texte en rouge (le contenu affiché est le message d'erreur renvoyé par la route)
- ERROR RÉSEAU (throw du fetch) : console.error + analysis = 'Erreur réseau lors de l'appel à l'analyse IA.' + error = true (affiché en rouge)
- Un nouveau clic sur 'Régénérer' remet error à false et loading à true avant de relancer
- Pas d'état empty distinct (l'état idle joue ce rôle), pas d'état unauthorized

**Details UX** (7)

- Identité visuelle IA : dégradé indigo->violet + icône Sparkles répétée (titre, bouton générer, bouton régénérer)
- Support du thème sombre explicite sur la carte, le titre et le texte de résultat
- Avertissement d'attente longue affiché AVANT les skeletons (le modèle tourne en CPU sur le VPS, plusieurs minutes possibles)
- Le texte du modèle est demandé en français, texte brut sans markdown (contrainte imposée dans le prompt serveur) et rendu en whitespace-pre-wrap
- La carte est le DERNIER élément de la page /reports (après les KPI, graphiques et tableaux)
- La page /reports se rafraîchit en temps réel via useRealtimeRefresh(['product_variant','order','stock_movement']) mais l'analyse IA déjà générée N'EST PAS régénérée automatiquement : elle devient silencieusement obsolète
- Formatage des montants côté /reports : Intl.NumberFormat('fr-MG') + suffixe ' Ar' (les nombres envoyés à l'IA sont en revanche bruts)

### `POST /api/ai/analyze — route API Next.js (Route Handler)`

- **Fichier Next.js** : `frontend/app/api/ai/analyze/route.ts`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** AUCUNE vérification d'authentification ni de rôle. La route n'inspecte ni cookie, ni header Authorization, ni token JWT : n'importe qui pouvant joindre le serveur Next.js peut la POSTer. Aucun rate-limiting. Le seul filtrage métier (topMagasins réservé à isAdmin) est fait côté client dans /reports.

**Objectif.** Proxy serveur vers un modèle Ollama LOCAL (pas d'API cloud, pas de clé à gérer) installé sur le VPS : construit un prompt français d'expert en gestion de commerce/logistique pour un revendeur d'accessoires téléphone à Madagascar, l'envoie à Ollama, nettoie la réponse et la renvoie au front.

**Fonctionnalites** (15)

- Export unique : `export async function POST(req: Request)` — aucune autre méthode HTTP n'est exposée (GET/PUT/DELETE -> 405 par défaut Next.js)
- Configuration par variables d'environnement : OLLAMA_BASE_URL (défaut 'http://localhost:11434') et OLLAMA_MODEL (défaut 'qwen3:4b')
- buildPrompt(data) : fonction pure, seul endroit à éditer pour changer le ton/contenu/longueur (documenté dans l'en-tête du fichier)
- Le prompt insère la période entre parenthèses seulement si data.periode est fourni
- Chiffres clés injectés avec fallback textuel 'non disponible' pour ca, beneficeNet, valeurStock, beneficeEstimeStock ; ventesImpayeesCount tombe à 0 (`?? 0`)
- Toutes les listes sont injectées en JSON.stringify avec fallback [] ou {} : topProduits, produitsSansMouvement, rupturesStock, stockBas, repartitionMouvements, topVendeurs, topMagasins
- Le prompt demande explicitement 4 sections : 1) résumé de la santé financière (CA, bénéfice, marge) 2) observation sur les produits qui se vendent le mieux et ceux qui ne bougent pas 3) alerte ruptures + stocks bas avec priorité de réapprovisionnement 4) conseils actionnables concrets ventes et cash-flow
- Consigne de format imposée au modèle : français, texte brut avec sauts de ligne, SANS markdown (pas de gras, pas d'astérisques, pas de titres #), paragraphes courts, concis et professionnel
- Toutes les valeurs monétaires sont libellées en Ar (Ariary malgache) dans le prompt
- Flag `think: false` envoyé à Ollama : qwen3 est un modèle « hybrid reasoning » qui sinon passe l'essentiel du temps à raisonner en interne ; Ollama ignore silencieusement le flag si le modèle ne le supporte pas
- `stream: false` : réponse en un bloc, pas de streaming vers le client
- Timeout requête : AbortSignal.timeout(600_000) = 10 MINUTES (volontairement large, CPU sur VPS)
- Post-traitement : suppression des blocs de raisonnement via text.replace(/<think>[\s\S]*?<\/think>/gi, '') puis .trim()
- Le corps de requête est parsé sans aucune validation de schéma (pas de zod) : tous les champs sont optionnels et non vérifiés
- Redémarrage du conteneur frontend nécessaire pour prendre en compte un changement de prompt (documenté : docker compose -f docker-compose.prod.yml up -d --build frontend)

**Appels API** (6)

- ENTRÉE — POST /api/ai/analyze, body JSON de type AnalyzePayload { periode?, ca?, beneficeNet?, valeurStock?, beneficeEstimeStock?, ventesImpayeesCount?, topProduits?, produitsSansMouvement?, rupturesStock?, stockBas?, repartitionMouvements?, topVendeurs?, topMagasins? }
- SORTIE 200 — Response.json({ analysis: string })
- SORTIE 500 — Response.json({ analysis: "Erreur lors de la génération de l'analyse. <hint>" }, { status: 500 }) — l'erreur est TOUJOURS transportée dans le même champ `analysis` que le succès
- APPEL SORTANT — POST {OLLAMA_BASE_URL}/api/generate, headers { 'Content-Type': 'application/json' }, body { model: OLLAMA_MODEL, prompt, stream: false, think: false }, signal AbortSignal.timeout(600000)
- Si la réponse Ollama n'est pas ok : lecture du corps en texte (catch -> ''), throw `Ollama a répondu {status} : {detail.slice(0,300)}` (détail tronqué à 300 caractères)
- Lecture de la réponse Ollama : result.response ?? '' (chaîne vide si le champ manque)

**Etats UI** (5)

- SUCCÈS : statut 200 avec le texte nettoyé
- ERREUR TIMEOUT (error.name === 'TimeoutError') : hint = 'Le modèle a mis trop de temps à répondre (délai dépassé).'
- ERREUR AUTRE (Ollama injoignable, 4xx/5xx, JSON invalide...) : hint = `Impossible de contacter Ollama sur {OLLAMA_BASE_URL}. Vérifiez qu'Ollama tourne sur le VPS et que OLLAMA_BASE_URL est bien configuré (voir roadmap.md).` — l'URL interne du VPS FUIT donc dans la réponse envoyée au navigateur
- Toute erreur est aussi console.error("Erreur lors de l'analyse IA (Ollama) :", error) côté serveur
- Le client (<AIAnalysis/>) affiche indistinctement le champ `analysis` dans les deux cas, en rouge quand le statut n'est pas ok

**Details UX** (3)

- Le contrat d'API est volontairement « toujours du texte » : jamais de champ `error` séparé, ce qui permet au composant d'afficher l'erreur au même endroit que l'analyse
- Le délai de 10 minutes doit être répliqué côté client Flutter (timeout Dio/http par défaut bien plus court, sinon l'appel échouera avant Ollama)
- Aucun cache : chaque clic sur Générer/Régénérer relance une inférence complète

### `POST /api/ai/check-duplicates — route API Next.js (Route Handler)`

- **Fichier Next.js** : `frontend/app/api/ai/check-duplicates/route.ts`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** AUCUNE vérification d'authentification ni de rôle (ni cookie, ni JWT, ni rate-limit). En pratique elle n'est appelée que depuis /products après un import Excel, donc par les rôles autorisés à importer, mais la route est ouverte.

**Objectif.** Revue « best-effort » par IA locale (Ollama) des références NOUVELLEMENT créées par un import Excel, pour repérer les QUASI-doublons qu'une comparaison de texte ne voit pas (faute de frappe, variante d'écriture, ex. « Samsung A05S » vs « Samsung A05 » déjà en catalogue). Les doublons stricts / insensibles à la casse sont déjà gérés côté serveur Django (catalog/views.py::import_excel::_match_ci), donc jamais concernés ici.

**Fonctionnalites** (10)

- Export unique : `export async function POST(req: Request)`
- Même configuration Ollama que /api/ai/analyze : OLLAMA_BASE_URL (défaut http://localhost:11434), OLLAMA_MODEL (défaut qwen3:4b), stream:false, think:false, AbortSignal.timeout(600_000) = 10 minutes
- COURT-CIRCUIT : si !data.newNames?.length -> renvoie immédiatement { warnings: [] } SANS appeler Ollama (économise une inférence de plusieurs minutes)
- Le prompt injecte les deux listes en JSON.stringify : d'abord les références existantes du catalogue, puis les nouvelles créées par l'import
- Consigne au modèle : ne signaler QUE les références suspectes (ne pas inclure celles clairement légitimes), ignorer les différences de casse (déjà gérées ailleurs), détecter faute de frappe / variante d'écriture / espace ou tiret en trop / modèle très proche type « A05 » vs « A05S » pouvant être une erreur de saisie
- Format de sortie imposé : tableau JSON STRICT d'objets {"nouvelle", "ressemble_a", "raison"}, ou exactement `[]` si rien de suspect, sans texte avant/après ni balises markdown
- NETTOYAGE 1 : suppression des blocs <think>...</think> (regex /gi) puis trim
- NETTOYAGE 2 : suppression d'un éventuel fence markdown malgré la consigne — replace(/^```(?:json)?\s*/i, '') puis replace(/```\s*$/i, '') puis trim
- PARSING TOLÉRANT : JSON.parse dans un try/catch ; le résultat n'est retenu que si Array.isArray(parsed) ; toute réponse non-JSON -> warnings = [] (on ne casse jamais l'UI d'un import par ailleurs réussi)
- Aucune validation de la forme des objets retournés par le modèle (nouvelle/ressemble_a/raison sont supposés présents et affichés tels quels côté /products)

**Modales / dialogs / drawers** (5)

- Dialog de revue d'import (dans /products, app/(app)/products/page.tsx) piloté par `open={!!importReview}` — c'est là que le résultat de cette route est affiché.
- Contenu du dialog : 2 cartes côte à côte (grid-cols-2) — « Ajouté » (vert) avec created_references référence(s) + created_variants couleur(s), « Mis à jour » (bleu) avec updated_references + updated_variants.
- Puis : liste 'Nouvelles références :' (line-clamp-3, noms joints par ', '), liste 'Références mises à jour :' (line-clamp-3), ligne '{skipped_count} ligne(s) déjà traitée(s) ignorée(s).' si > 0, ligne rouge '{errors_count} ligne(s) en erreur — voir le fichier téléchargé.' si > 0.
- Encadré 'Analyse IA (quasi-doublons)' (rounded-md border p-3) affichant les 4 états ci-dessus.
- Footer du dialog — 3 boutons : « Annuler l'import » (variant destructive, libellé 'Annulation...' pendant cancellingImport) = SEUL bouton qui déclenche un appel réseau ; « Modifier » (variant outline) = ferme la revue et pré-remplit la recherche du tableau sur la 1re référence touchée + toast.info ; « Enregistrer » (primaire) = ne fait qu'un toast.success('Import conservé.') et referme (l'import est DÉJÀ en base).

**Appels API** (7)

- ENTRÉE — POST /api/ai/check-duplicates, body { newNames: string[], existingNames: string[] }
- SORTIE NOMINALE — { warnings: { nouvelle: string; ressemble_a: string; raison: string }[] } (statut 200)
- SORTIE EN CAS D'ERREUR — { warnings: [], error: <message> } avec statut **200** (et non 500) : la revue IA ne doit JAMAIS faire échouer l'import déjà écrit en base
- APPEL SORTANT — POST {OLLAMA_BASE_URL}/api/generate avec { model, prompt, stream:false, think:false } et timeout 600 s ; si !response.ok -> throw `Ollama a répondu {status} : {detail.slice(0,300)}`
- CONSOMMATEUR — /products : après djangoClient d'import Excel, si res.new_reference_names.length > 0, fetch('/api/ai/check-duplicates') avec { newNames: res.new_reference_names, existingNames: references.map(r => `${r.brand_name} ${r.reference_name}`) }
- CONSOMMATEUR — le résultat met à jour l'état importReview seulement si prev.batchId === res.batch_id (garde anti-course entre deux imports successifs)
- CONSOMMATEUR — POST /catalog/import-batches/{batchId}/cancel/ via djangoClient.catalog.importBatches.cancel(batchId), déclenché uniquement par le bouton « Annuler l'import » du dialog de revue

**Etats UI** (6)

- ENTRÉE VIDE : réponse instantanée { warnings: [] } (côté /products cela correspond à aiStatus='skipped' -> texte 'Aucune nouvelle référence à vérifier.')
- EN COURS côté client : aiStatus='loading' -> 'Analyse en cours…' (text-muted-foreground) dans le dialog de revue
- TERMINÉ SANS ALERTE : aiStatus='done' + aiWarnings vide -> 'Aucun doublon suspect détecté.'
- TERMINÉ AVEC ALERTES : liste <ul> d'items « "{nouvelle}" ressemble à "{ressemble_a}" — {raison} » (les noms en font-medium, la raison en suffixe seulement si non vide)
- OLLAMA INDISPONIBLE / .catch() côté client : aiStatus passe quand même à 'done' (avec aiWarnings inchangé/vide) — la vérification est simplement marquée non concluante, l'import reste valide
- Log serveur en cas d'échec : console.error('Erreur lors de la revue IA des doublons (Ollama) :', error)

**Details UX** (5)

- Contrat « best-effort » assumé : statut 200 même en erreur, warnings vide plutôt qu'une exception
- Résultat affiché DANS le dialog de revue plutôt qu'en toast séparé, pour que l'utilisateur voie tout au même endroit avant de décider Enregistrer/Modifier/Annuler
- Toast d'erreur d'import (côté /products) : `{errors_count} ligne(s) en erreur — voir la colonne "Statut" du fichier téléchargé.` avec duration: 10000 ms
- Le champ `existingNames` est construit en concaténant marque + nom de référence : `${brand_name} ${reference_name}`
- Les guillemets typographiques autour des noms dans la liste d'alertes sont des guillemets droits ("...")

### `(module partagé) lib/image-service.ts — service de gestion des images`

- **Fichier Next.js** : `frontend/lib/image-service.ts`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun rôle, aucun gating : module de fonctions utilitaires pures/réseau, sans notion d'utilisateur. AUCUNE de ces fonctions n'est importée ailleurs dans le frontend (module entièrement orphelin aujourd'hui).

**Objectif.** Boîte à outils images : upload (base64 « démo » ou backend), URL optimisée, validation de fichier, lecture des dimensions, suppression et upload en lot. Le commentaire d'en-tête précise que l'upload base64 est un placeholder en attendant un vrai stockage (Vercel Blob, S3...).

**Fonctionnalites** (12)

- Interface ImageUploadResult { url: string; filename: string; size: number }
- uploadImage(file: File): Promise<ImageUploadResult> — lit le fichier via FileReader.readAsDataURL, renvoie url = data URL base64 complète, filename = `${Date.now()}-${file.name}` (préfixe timestamp anti-collision), size = file.size
- uploadImage — reader.onload dans un try/catch qui reject(new Error('Failed to process image')) ; reader.onerror -> reject(new Error('Failed to read image file'))
- uploadImageToBackend(file: File, productId: string): Promise<ImageUploadResult> — construit un FormData avec les champs 'image' (le File) et 'product_id' (l'id), POST /api/upload, renvoie { url: data.url, filename: data.filename, size: file.size }
- uploadImageToBackend — si !response.ok : throw new Error('Failed to upload image') ; le catch global log '[v0] Error uploading image to backend:' puis throw new Error('Failed to upload image to backend storage') (le message d'origine est PERDU)
- getOptimizedImageUrl(url, width?, height?, quality?): string — si url.startsWith('data:') retourne l'URL telle quelle ; sinon construit des query params width/height/quality (seulement ceux fournis) et les concatène avec '&' si l'URL contient déjà '?', sinon '?' ; si aucun paramètre, retourne l'URL inchangée
- validateImageFile(file, maxSizeMB = 5, acceptedFormats = ['image/jpeg','image/png','image/webp']): { valid: boolean; error?: string } — même logique que ImageUpload mais messages EN ANGLAIS
- getImageDimensions(imageUrl: string): Promise<{width, height}> — instancie un `new Image()` du DOM avec crossOrigin = 'anonymous', résout sur onload avec img.width/img.height, reject(new Error('Failed to load image')) sur onerror
- deleteImage(imagePath: string): Promise<void> — DELETE /api/upload?path={imagePath} (le chemin est interpolé BRUT dans l'URL, sans encodeURIComponent) ; throw 'Failed to delete image' si !ok, log '[v0] Error deleting image:'
- batchUploadImages(files: File[], productId: string, onProgress?: (current, total) => void): Promise<ImageUploadResult[]> — boucle SÉQUENTIELLE (for + await, pas de Promise.all), appelle uploadImage(files[i]) (donc la version BASE64, jamais uploadImageToBackend) ; le paramètre productId est reçu mais JAMAIS UTILISÉ
- batchUploadImages — en cas d'erreur sur un fichier : console.error(`[v0] Error uploading file ${i+1}:`) et CONTINUE avec le suivant ; le tableau retourné peut donc être plus court que `files` et le rapprochement index<->fichier est perdu
- batchUploadImages — onProgress?.(i + 1, files.length) appelé UNIQUEMENT après un succès (un échec ne fait pas avancer la barre de progression)

**Appels API** (3)

- POST /api/upload — multipart/form-data avec champs `image` (fichier) et `product_id` (string). PIÈGE MAJEUR : cette route N'EXISTE PAS dans le repo (app/api/ ne contient que ai/analyze et ai/check-duplicates) -> tout appel à uploadImageToBackend renverra un 404 Next.js.
- DELETE /api/upload?path={imagePath} — idem, route inexistante côté frontend.
- Aucun appel à djangoClient : ce module ignore complètement le client Django authentifié (donc aucun header Authorization/JWT ne serait envoyé).

**Etats UI** (2)

- Aucun état UI (module non-React) : uniquement des promesses résolues/rejetées et des booléens de validation.
- Messages d'erreur (tous en anglais) : 'Failed to process image', 'Failed to read image file', 'Failed to upload image', 'Failed to upload image to backend storage', 'Failed to load image', 'Failed to delete image', `File size exceeds ${maxSizeMB}MB limit`, 'File format not supported. Use JPEG, PNG, or WebP'.

**Details UX** (4)

- Tous les logs sont préfixés '[v0]' (héritage du générateur v0.dev) — utile pour repérer le code non retravaillé
- Limite par défaut cohérente avec <ImageUpload/> : 5 MB, JPEG/PNG/WebP
- Stratégie actuelle = data URL base64 : très lourd si stocké en base ou transmis (≈ +33 % par rapport au binaire), à remplacer par un vrai upload multipart en Flutter
- Le nommage `${Date.now()}-${file.name}` conserve le nom d'origine (donc les accents/espaces) — à normaliser côté mobile

### `(module partagé) lib/qrcode-generator.ts — génération et lecture de QR codes`

- **Fichier Next.js** : `frontend/lib/qrcode-generator.ts`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun rôle, aucun gating. Module utilitaire pur. Aucune de ses fonctions n'est importée ailleurs dans le frontend aujourd'hui (module orphelin, à l'image de <ProductImageGallery/> qui affiche pourtant des qr_code_image).

**Objectif.** Produire des QR codes en data URL PNG encodant l'identité d'une image produit (SKU, nom, id image, taille, variante couleur, horodatage), plus un générateur simple à partir d'un texte libre et un parseur tolérant pour la lecture.

**Fonctionnalites** (9)

- Dépendance npm : `qrcode` ^1.5.4 (import QRCode from 'qrcode'). Le projet embarque aussi `qrcode.react` ^4.2.0 (non utilisé ici).
- Interface QRCodeOptions { sku: string; productName: string; imageId: string; size?: string; colorVariant?: string }
- generateQRCode(options): Promise<string> — valeurs par défaut size = 'S' et colorVariant = 'Default'
- generateQRCode — la charge utile encodée est JSON.stringify({ sku, productName, imageId, size, colorVariant, timestamp: new Date().toISOString() })
- generateQRCode — options de rendu : errorCorrectionLevel 'H' (le plus robuste, ~30 % de correction — adapté à une étiquette collée/abîmée), type 'image/png', quality 0.95, margin 1, width 300
- generateQRCode — en cas d'échec : console.error('[v0] Error generating QR code:', error) puis throw new Error('Failed to generate QR code')
- generateSimpleQRCode(text: string): Promise<string> — errorCorrectionLevel 'M' (moyen), type 'image/png', quality 0.95, margin 1, width 200 ; erreur -> log '[v0] Error generating simple QR code:' + throw 'Failed to generate QR code'
- parseQRCodeData(qrData: string) — JSON.parse dans un try ; en cas d'échec renvoie { raw: qrData } (jamais d'exception) : un QR non-JSON scanné reste exploitable via le champ `raw`
- Aucune fonction de scan/décodage caméra ici : le commentaire précise que le décodage réel serait fait par un scanner QR externe

**Appels API** (1)

- Aucun appel réseau : génération 100 % locale (côté navigateur/serveur selon l'endroit d'appel), sortie en data URL base64 PNG.

**Etats UI** (2)

- Promesses résolues (data URL) ou rejetées avec le message 'Failed to generate QR code'.
- parseQRCodeData ne rejette jamais : fallback { raw }.

**Details UX** (4)

- INCOHÉRENCE À CONNAÎTRE : le QR généré ici contient 6 champs (sku, productName, imageId, size, colorVariant, timestamp) alors que le bouton « Copier données » de <ProductImageGallery/> copie un JSON à 4 champs seulement (sku, productName, imageId, timestamp). Les deux payloads ne sont donc pas identiques.
- Le timestamp est régénéré à chaque appel : deux QR successifs pour la même image produisent des images DIFFÉRENTES (non idempotent, non comparable octet à octet).
- Deux niveaux de correction d'erreur volontairement distincts : 'H'/300px pour l'étiquette produit, 'M'/200px pour un QR générique.
- Marge de 1 module (quiet zone minimale) : à surveiller sur certains scanners exigeants.

### `(hook partagé) lib/hooks/useDeliveryZones.ts — zones de livraison configurables`

- **Fichier Next.js** : `frontend/lib/hooks/useDeliveryZones.ts`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Le hook ne fait aucun gating. Règle serveur documentée dans lib/django-client.ts : « Lecture ouverte à tous, écriture réservée au gérant » — la LISTE est donc lisible par GERANT (admin/magasin), PREPARATEUR et LIVREUR, tandis que create/update/delete (exposés dans /settings) sont réservés au gérant côté backend (orders/views.py::DeliveryZoneOptionViewSet).

**Objectif.** Charger la liste des zones de livraison (nom + prix) partagées par toute la société, pour alimenter les formulaires de commande, le tableau des commandes et l'écran Paramètres. Le commentaire du fichier assume le choix : « la liste est petite et change rarement, un fetch par montage reste largement suffisant » — chaque composant appelle le hook indépendamment (pas de cache global, pas de contexte).

**Fonctionnalites** (9)

- Interface exportée DeliveryZoneOption { id: number; code: string; nom: string; prix: number; actif: boolean }
- Retour du hook : { zones: DeliveryZoneOption[], loading: boolean, refetch: () => Promise<void> }
- État initial : zones = [] et loading = TRUE (le hook démarre toujours en chargement)
- refetch est un useCallback(deps: []) — référence stable, donc le useEffect([refetch]) ne déclenche QU'UN SEUL fetch au montage
- refetch() : setLoading(true) -> djangoClient.zones.list() -> .then(setZones) -> .catch(() => setZones([])) -> .finally(() => setLoading(false))
- GESTION D'ERREUR SILENCIEUSE : en cas d'échec réseau, les zones sont vidées, AUCUN état d'erreur n'est exposé, AUCUN toast n'est émis. Le consommateur ne peut PAS distinguer « pas de zones configurées » de « le serveur est tombé »
- Le hook NE FILTRE PAS sur le champ `actif` : il renvoie tel quel ce que l'API retourne
- 3 points d'appel indépendants dans app/(app)/orders/page.tsx (OrdersPage l.248, dialog d'édition l.1993, dialog de création l.2645) — soit potentiellement 3 requêtes GET simultanées pour la même donnée
- La page /settings n'utilise PAS le hook : elle appelle directement djangoClient.zones.list().then(setDeliveryZones).catch(() => {}) et fait le CRUD

**Formulaires** (1)

- Le hook n'a pas de formulaire, mais il alimente ceux de /orders : le champ « zone » des dialogs de création et d'édition de commande, dont la valeur détermine les frais de livraison.

**Recherche, filtres, tri, pagination** (1)

- Aucun filtre/tri/pagination : la liste est renvoyée brute et complète.

**Appels API** (4)

- GET /orders/delivery-zones/ — via djangoClient.zones.list(). Renvoie { id, code, nom, prix, actif }[]
- POST /orders/delivery-zones/ — djangoClient.zones.create({ nom, prix }) — utilisé dans /settings (création d'une zone)
- PATCH /orders/delivery-zones/{id}/ — djangoClient.zones.update(id, { nom?, prix?, actif? }) — utilisé dans /settings pour renommer/retarifer ET pour basculer actif/inactif ({ actif: !z.actif })
- DELETE /orders/delivery-zones/{id}/ — djangoClient.zones.delete(id) — RÈGLE MÉTIER : une zone déjà utilisée par des commandes n'est PAS réellement supprimée côté serveur, elle est DÉSACTIVÉE (soft delete, voir DeliveryZoneOptionViewSet.destroy)

**Etats UI** (4)

- LOADING : true au montage et à chaque refetch (aucun consommateur de /orders n'exploite ce flag — ils ne déstructurent que `{ zones }`)
- SUCCÈS : tableau de zones
- ERREUR : tableau vide, indistinguable de l'état vide
- Aucun état unauthorized géré (un 401/403 tombe dans le même catch silencieux)

**Details UX** (5)

- buildZoneOptions() dans app/(app)/orders/page.tsx transforme la liste en options { value: code, label: `${nom} (${fmt(prix)})`, frais: Number(prix) } et AJOUTE TOUJOURS une option littérale supplémentaire { value: 'RECUPERATION', label: 'Récupération (0 Ar)', frais: 0 } — le retrait sur place est structurellement à part (pas de livreur, pas de frais) et n'est jamais stocké en base comme une zone
- RÈGLE MÉTIER /orders : un PREPARATEUR ne crée QUE des retraits sur place — la zone est forcée à 'RECUPERATION' à l'ouverture du dialog et il ne voit aucune donnée financière (showPrices = !isPreparateur)
- RÈGLE MÉTIER /orders : pour les autres rôles, un useEffect sélectionne automatiquement la PREMIÈRE zone payante (première option dont value !== 'RECUPERATION') dès que les zones arrivent, à condition que le champ zone soit encore vide — nécessaire car le fetch est asynchrone
- Le libellé de zone affiché à l'utilisateur inclut le prix formaté entre parenthèses
- Écran /settings : liste 'Toutes les zones ({zones.length})', message vide 'Aucune zone.' (text-sm text-muted-foreground text-center py-4), édition inline (nom + prix, trim sur le nom, Number(prix) || 0 en repli)

### `(hook partagé) lib/hooks/useDebouncedValue.ts — valeur temporisée pour les recherches`

- **Fichier Next.js** : `frontend/lib/hooks/useDebouncedValue.ts`
- **Groupe d'audit** : `medias-divers`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun rôle, aucun gating : hook générique sans notion d'utilisateur.

**Objectif.** Renvoyer une valeur avec un léger délai pour DÉCOUPLER la saisie (qui doit rester instantanée dans l'input) du filtrage/recalcul déclenché par cette valeur — évite de refiltrer et re-rendre une longue liste à chaque frappe (recherche « saccadée »).

**Fonctionnalites** (10)

- Signature générique : useDebouncedValue<T>(value: T, delayMs = 250): T
- État interne initialisé AVEC la valeur courante : la toute première valeur est renvoyée IMMÉDIATEMENT, sans délai (pas de undefined/flash au montage)
- useEffect([value, delayMs]) : setTimeout(() => setDebounced(value), delayMs) avec cleanup clearTimeout — chaque frappe annule le timer précédent (debounce trailing classique)
- Délai par défaut 250 ms ; TOUS les consommateurs actuels utilisent ce défaut (aucun n'passe de delayMs explicite)
- Pas de flush immédiat, pas d'annulation manuelle, pas de version leading-edge
- CONSOMMATEUR — app/(app)/movements/page.tsx l.146 : debouncedSearchTerm = useDebouncedValue(searchTerm)
- CONSOMMATEUR — app/(app)/chats/page.tsx l.402 : debouncedProductSearch = useDebouncedValue(productSearch)
- CONSOMMATEUR — app/(app)/chats/page.tsx l.482 : debouncedSearchQuery = useDebouncedValue(searchQuery)
- CONSOMMATEUR — app/(app)/products/page.tsx l.164 : debouncedSearch = useDebouncedValue(search)
- CONSOMMATEUR — app/(app)/users/page.tsx l.276 : debouncedSearchTerm = useDebouncedValue(searchTerm)

**Recherche, filtres, tri, pagination** (1)

- C'est l'infrastructure de TOUTES les barres de recherche de l'app : produits, mouvements de stock, utilisateurs, et les deux recherches de la page chats (recherche de produit et recherche de conversation).

**Appels API** (1)

- Aucun appel réseau : le hook est purement local. Chez tous les consommateurs actuels le filtrage est fait CÔTÉ CLIENT sur des données déjà chargées (le hook ne déclenche pas de requête serveur).

**Etats UI** (1)

- Aucun état UI exposé : le hook ne renvoie qu'une valeur. Il n'existe donc AUCUN indicateur visuel « recherche en attente » pendant les 250 ms de latence.

**Details UX** (2)

- Le champ de saisie reste toujours contrôlé par l'état non temporisé (frappe fluide) — c'est la LISTE qui accuse 250 ms de retard
- À porter en Flutter avec un Timer + cancel dans dispose(), ou un debounce sur le TextEditingController ; attention à annuler le timer au démontage pour ne pas setState sur un widget détruit

### `(couche transport) DjangoAPIClient — coeur HTTP/JWT`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.1-361 + l.1120-1135)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun gating de role a ce niveau : la classe est agnostique. Le seul gating client est fait ailleurs via useCurrentUser() (/home/garrix/Dev/Smartphone/frontend/lib/auth/useCurrentUser.ts) qui expose isAdmin/isMagasin/isEmployer/isSuperAdmin(=admin)/isAdminOrSuperAdmin/isManager/isGerant(=admin||magasin)/isPreparateur(=employer && commande_role==='PREPARATEUR')/isLivreur(=employer && commande_role==='LIVREUR')/isCompanyOwner(=admin && is_company_owner). Le backend reste l'autorite : un refus arrive en 401 (=> refresh puis redirect /login) ou en 4xx transforme en Error(message).

**Objectif.** Client API unique (singleton `djangoClient`) vers le backend Django : gestion des tokens JWT, refresh automatique, serialisation JSON, upload multipart, telechargement de blobs, normalisation des erreurs. C'est le contrat integral a reimplementer en Dart (dio/http + interceptor).

**Fonctionnalites** (29)

- const API_BASE_URL = process.env.NEXT_PUBLIC_DJANGO_API_URL ?? 'http://127.0.0.1:8010/api' (fallback en dur 127.0.0.1:8010)
- Etat interne: `tokens: {access, refresh} | null`, `isRefreshing: boolean`, `refreshQueue: Array<(token)=>void>`
- constructor() appelle loadTokensFromStorage() : lit localStorage['django_tokens'], JSON.parse dans try/catch, log '[v0] Failed to parse stored tokens' si echec (pas de crash)
- saveTokensToStorage(tokens) : ecrit localStorage['django_tokens'] = JSON.stringify(tokens) et met a jour le champ memoire
- clearTokensFromStorage() : tokens=null + localStorage.removeItem('django_tokens')
- Toutes les fonctions storage sortent immediatement si typeof window === 'undefined' (SSR-safe) — en Flutter remplacer par SharedPreferences / secure storage
- refreshAccessToken() : si pas de refresh token -> null. Si un refresh est deja en cours (isRefreshing) -> retourne une Promise mise en file dans refreshQueue (aucun double refresh concurrent, tous les appels 401 simultanes attendent le meme resultat)
- refreshAccessToken() succes : conserve le refresh existant, remplace seulement `access`, sauvegarde, puis appelle chaque callback de refreshQueue avec le nouveau token et vide la file
- refreshAccessToken() echec HTTP (response non ok) : clearTokensFromStorage() PUIS redirection dure `window.location.href = '/login'` et retourne null
- refreshAccessToken() exception reseau : console.error('[v0] Token refresh failed:', error) + clearTokens + null (pas de redirection dans ce cas)
- finally: isRefreshing = false dans tous les cas
- getAuthHeaders() : {'Content-Type':'application/json'} + Authorization: `Bearer <access>` seulement si un access existe
- request<T>(endpoint, options) : normalise l'endpoint — si il commence par 'http' il est utilise tel quel, sinon `${API_BASE_URL sans slash final}/${endpoint sans slash initial}`
- request() fusionne les headers : headers d'auth d'abord, puis options.headers qui ECRASENT (extraHeaders.forEach -> requestHeaders.set)
- request() sur status 401 : tente refreshAccessToken(); si null -> lit le JSON d'erreur (catch -> {}) et throw Error(error.detail || 'Authentication failed'); sinon rejoue la requete UNE seule fois avec les nouveaux headers
- request() erreur non-ok : si content-type contient application/json -> message = error.detail || error.non_field_errors[0] (si tableau) || toutes les entrees `${cle}: ${valeur ou valeur[0]}` jointes par ' | ' || `API Error: ${status}`. Sinon -> response.text() tronque a 200 caracteres
- request() succes 204 ou 205 -> retourne undefined (typé T) ; corps vide ('' ) -> undefined ; parse JSON uniquement si content-type contient application/json, sinon undefined
- Verbes exposes : get<T>(endpoint), post<T>(endpoint, data?), put<T>, patch<T>, delete<T>(endpoint, data?) — NOTE: delete accepte un BODY JSON (utilise par users.delete qui envoie {password})
- post/put/patch n'envoient un body que si `data` est truthy (undefined sinon)
- requestFormData<T>(endpoint, method, FormData) : URL = `${API_BASE_URL}${endpoint}` (concatenation brute, pas de normalisation), header Authorization seul (PAS de Content-Type — laisse le navigateur poser le boundary), 401 -> refresh + rejeu, erreur -> toutes les entrees `${cle}: ${valeurs jointes par ', '}` jointes par ' | ', sinon `API Error: ${status}`; retourne response.json()
- postFormData<T>(endpoint, FormData) et patchFormData<T>(endpoint, FormData) publics
- requestBlob(endpoint, method='GET') : Authorization seul, 401 -> refresh + rejeu, erreur -> error.detail sinon `API Error: ${status}`; extrait le nom de fichier depuis Content-Disposition via /filename="?([^"]+)"?/ avec fallback 'backup.zip'; retourne {blob, filename}
- requestFormDataForBlob(endpoint, FormData) : POST multipart dont la reponse est un FICHIER (pas du JSON) accompagne d'un resume porte par des en-tetes personnalisees (CORS_EXPOSE_HEADERS cote Django) ; erreur -> error.error || error.detail ; filename fallback 'export.xlsx' ; retourne {blob, filename, headers}
- isAuthenticated(): boolean -> !!tokens?.access (verifie la simple PRESENCE du token, jamais son expiration)
- getAccessToken(): string | null -> utilise pour construire les URL WebSocket (?token=...)
- export const djangoClient = new DjangoAPIClient() — singleton instancie a l'import (le chargement des tokens se fait donc au premier import cote client)
- export type { AuthResponse, AuthTokens }
- Interface AuthResponse (interne) : {access, refresh, user:{id, email, username, full_name, role:'admin'|'magasin'|'employer', is_confirmed, store_id?, magasin_id?, shop_name?, company_name?, position?}}
- Interface ApiErrorResponse : {detail?: string, [key:string]: any}

**Appels API** (1)

- POST /users/refresh/ — renouvellement du token d'acces (appele automatiquement sur 401, et une seconde fois volontairement pendant le logout)

**Etats UI** (4)

- Loading : aucun (la classe est bas niveau, l'etat de chargement est gere par les hooks/pages appelants)
- Erreur : toujours une Error JS avec un message deja lisible en francais quand le backend le fournit (error.detail) — a mapper sur une exception Dart typee
- Unauthorized : 401 -> refresh transparent ; echec du refresh -> purge des tokens + redirection dure vers /login (en Flutter : navigation vers l'ecran de connexion + purge du storage)
- Succes vide : 204/205 et corps vide normalises en `undefined` (important pour DELETE et pour caisse.current)

**Details UX** (3)

- La redirection /login se fait par window.location.href (rechargement complet de l'app) — en Flutter, prevoir un equivalent global (redirection Navigator + reset des providers)
- Tous les logs de debug sont prefixes '[v0]'
- Le refresh ne renouvelle QUE l'access token ; le refresh token reste celui de la connexion initiale (donc a duree de vie limitee cote Django : prevoir la deconnexion quand il expire)

### `djangoClient.auth — authentification, inscription, mot de passe oublie`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.363-500)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** register() accepte n'importe quel role et le traduit ; approveUser/rejectUser/getPendingUsers sont des actions d'administration (admin/magasin = gerant cote UI) mais aucun garde-fou client n'est present ici — le backend refuse. forgotPassword* est PUBLIC (sans token) et, d'apres le commentaire du code, indisponible pour les comptes admin (pas d'approbateur au-dessus) : le backend renvoie alors un message d'erreur.

**Objectif.** Cycle de vie de la session : inscription, connexion (avec persistance des tokens), deconnexion (avec purge totale), lecture + normalisation du profil courant, moderation des comptes en attente, et parcours complet de mot de passe oublie en 3 etapes (demande -> validation par l'admin -> confirmation).

**Fonctionnalites** (14)

- register(email, username, password, role, extraData?) : traduit role 'store_manager' -> 'magasin' et 'employee' -> 'employer' avant envoi ; full_name par defaut = username si non fourni ; extraData est etale dans le body
- extraData de register : full_name?, company_name?, shop_name?, admin_email?, position?
- login(email, password) : POST puis saveTokensToStorage({access, refresh}) IMMEDIATEMENT, puis un second appel getCurrentUser() pour recuperer le profil ; retourne {access, refresh, user}
- login envoie le champ `email` (pas `username`)
- logout() : 1) POST /users/logout-event/ dans un try/catch (echec ignore, console.warn '[v0] Logout event recording failed:') 2) recupere le refresh token en memoire ou, a defaut, relit localStorage['django_tokens'] 3) POST /users/refresh/ avec ce refresh (fire-and-forget, warn '[v0] Logout refresh request failed:') 4) localStorage.clear() — EFFACE TOUT le localStorage, pas seulement les tokens 5) this.tokens = null
- getCurrentUser() : GET /users/me/ puis mapping role backend->front : 'admin'->'admin', 'magasin'->'store_manager', 'employer'->'employee' (defaut 'employee')
- getCurrentUser() derive first_name = full_name.split(' ')[0] et last_name = le reste joint par des espaces ; full_name '' si absent
- getCurrentUser() expose is_approved ET is_confirmed, tous deux alimentes par response.is_confirmed ; conserve raw_role (valeur backend brute) ; remonte company_name, shop_name, magasin_id, position, phone
- approveUser(userId) : PUT sans body
- rejectUser(userId) : POST sans body
- getPendingUsers() : liste des comptes en attente de validation
- forgotPasswordRequest(email) -> {message}
- forgotPasswordStatus(email) -> {status: 'none' | 'pending' | 'approved' | 'rejected'} — email encode via encodeURIComponent (polling cote UI)
- forgotPasswordConfirm(email, newPassword) -> {message} ; le champ envoye s'appelle `new_password`

**Formulaires** (4)

- Inscription : email, username, password, role (store_manager|employee|admin), full_name (optionnel -> username), company_name (optionnel), shop_name (optionnel), admin_email (optionnel — rattachement a l'admin), position (optionnel). Aucune validation client dans ce fichier : toutes les erreurs viennent du backend et arrivent sous forme 'champ: message | champ2: message'.
- Connexion : email + password. Erreur backend renvoyee telle quelle (ex. identifiants invalides, compte non confirme).
- Mot de passe oublie etape 1 : email seul.
- Mot de passe oublie etape 3 : email + new_password (aucune regle de longueur cote client dans ce fichier).

**Appels API** (10)

- POST /users/register/ — creation de compte (role traduit magasin/employer)
- POST /users/login/ — obtention {access, refresh}
- POST /users/logout-event/ — journalisation de la deconnexion (best effort)
- GET /users/me/ — profil de l'utilisateur connecte
- PUT /users/approve/{userId}/ — approuver un compte en attente
- POST /users/reject/{userId}/ — rejeter un compte en attente
- GET /users/pending/ — comptes en attente de validation
- POST /users/public/forgot-password/ — demande de reinitialisation (public, sans token)
- GET /users/public/forgot-password/status/?email= — etat de la demande (none/pending/approved/rejected)
- POST /users/public/forgot-password/confirm/ — definition du nouveau mot de passe apres approbation

**Etats UI** (4)

- Non authentifie : isAuthenticated() false -> les hooks n'appellent meme pas /users/me/
- Compte non confirme : is_confirmed/is_approved false -> useAuth expose isPendingApproval = !!user && !user.is_approved (ecran 'en attente d'approbation')
- Erreur de connexion : useAuth stocke error = message de l'exception, et remet user a null
- Chargement : useAuth gere isLoading (true au montage, true pendant login/register, false en finally)

**Details UX** (3)

- Le logout vide TOUT le localStorage : en Flutter, purger aussi les preferences applicatives (theme, filtres memorises, brouillons) pour reproduire le comportement
- Le parcours mot de passe oublie est asynchrone et humain : l'utilisateur demande, un admin approuve, puis l'utilisateur revient confirmer — l'UI doit poller forgotPasswordStatus
- Apres login, deux requetes reseau s'enchainent (login puis /users/me/) : prevoir un seul spinner couvrant les deux

### `djangoClient.passwordResetRequests — moderation des demandes de reinitialisation (cote admin)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.502-511)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Cote admin/gerant : c'est l'approbateur des demandes emises par les comptes magasin/employer. Aucun garde client, le backend filtre.

**Objectif.** Lister et resoudre (approuver/rejeter) les demandes de reinitialisation de mot de passe faites par les employes/magasins.

**Fonctionnalites** (2)

- list(statusFilter?) : ajoute ?status=<valeur> uniquement si un filtre est fourni
- resolve(requestId, action) : action strictement typee 'approve' | 'reject', envoyee en PATCH dans {action}

**Modales / dialogs / drawers** (1)

- A prevoir cote UI : confirmation avant approbation/rejet (non implementee dans ce fichier)

**Recherche, filtres, tri, pagination** (1)

- Filtre par statut de la demande via le parametre `status` (chaine libre cote client, generalement pending/approved/rejected)

**Appels API** (2)

- GET /users/password-reset-requests/?status= — liste des demandes
- PATCH /users/password-reset-requests/{requestId}/ — {action: 'approve'|'reject'}

**Etats UI** (1)

- Aucun etat gere ici : liste brute, la page appelante gere loading/empty/erreur

### `djangoClient.catalog.categories — Categories du catalogue (§8)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.515-530)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Ecriture reservee au gerant (admin/magasin) cote backend ; lecture pour tous les roles connectes. Le parametre magasin_id permet a un admin multi-magasins de cibler un magasin precis.

**Objectif.** CRUD du premier niveau de la hierarchie catalogue : Categorie -> Sous-type -> Marque -> Reference -> Variante (couleur).

**Fonctionnalites** (4)

- list(magasinId?) : ?magasin_id=<id> seulement si fourni
- create({nom, ordre?, magasin_id?, avec_couleurs?}) — `ordre` pilote le tri d'affichage, `avec_couleurs` indique si les references de cette categorie se declinent en couleurs
- update(id, {nom?, ordre?, avec_couleurs?}) en PATCH (partiel)
- delete(id) — DELETE, reponse 204 normalisee en undefined

**Formulaires** (1)

- Formulaire Categorie : nom (obligatoire cote backend), ordre (entier, optionnel), avec_couleurs (booleen / switch, optionnel), magasin_id (a la creation seulement, optionnel)

**Appels API** (4)

- GET /catalog/categories/?magasin_id= — liste des categories
- POST /catalog/categories/ — creation
- PATCH /catalog/categories/{id}/ — modification partielle
- DELETE /catalog/categories/{id}/ — suppression

**Details UX** (1)

- `avec_couleurs` est le switch cle : il conditionne l'affichage du choix de couleur dans les formulaires de reference/variante en aval

### `djangoClient.catalog.types — Sous-types rattaches a une categorie`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.531-545)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Ecriture gerant, lecture tous (controle backend).

**Objectif.** CRUD du deuxieme niveau : le sous-type appartient a une categorie et sert de cible aux mises a jour de prix en masse.

**Fonctionnalites** (4)

- list(categoryId?) : ?category=<id> pour filtrer par categorie parente
- create({category, nom}) — la categorie parente est obligatoire
- update(id, {nom?, category?}) — permet de deplacer un type vers une autre categorie
- delete(id)

**Formulaires** (1)

- Formulaire Type : category (selecteur de categorie, obligatoire a la creation), nom (obligatoire)

**Recherche, filtres, tri, pagination** (1)

- Filtre `category` pour n'afficher que les types d'une categorie

**Appels API** (4)

- GET /catalog/types/?category= — liste des sous-types
- POST /catalog/types/ — creation
- PATCH /catalog/types/{id}/ — modification
- DELETE /catalog/types/{id}/ — suppression

**Details UX** (1)

- Le type est l'unite de regroupement utilisee par references.bulkUpdatePrice (mise a jour de prix par type)

### `djangoClient.catalog.brands — Marques`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.546-560)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Ecriture gerant, lecture tous. Scope par magasin via magasin_id.

**Objectif.** CRUD des marques utilisees pour composer une reference produit.

**Fonctionnalites** (4)

- list(magasinId?) : ?magasin_id=
- create({nom, magasin_id?})
- update(id, {nom}) — seul le nom est modifiable
- delete(id)

**Formulaires** (1)

- Formulaire Marque : nom (obligatoire), magasin_id (optionnel a la creation)

**Appels API** (4)

- GET /catalog/brands/?magasin_id= — liste des marques
- POST /catalog/brands/ — creation
- PATCH /catalog/brands/{id}/ — renommage
- DELETE /catalog/brands/{id}/ — suppression

### `djangoClient.catalog.colors — Couleurs (referentiel des variantes)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.561-575)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Ecriture gerant, lecture tous. Scope magasin.

**Objectif.** CRUD du referentiel de couleurs proposees lors de la creation d'une variante.

**Fonctionnalites** (4)

- list(magasinId?) : ?magasin_id=
- create({nom, magasin_id?})
- update(id, {nom})
- delete(id)

**Formulaires** (1)

- Formulaire Couleur : nom (obligatoire), magasin_id (optionnel a la creation)

**Appels API** (4)

- GET /catalog/colors/?magasin_id= — liste des couleurs
- POST /catalog/colors/ — creation
- PATCH /catalog/colors/{id}/ — renommage
- DELETE /catalog/colors/{id}/ — suppression

**Details UX** (1)

- La couleur 'Standard' est traitee comme une absence de couleur ailleurs dans le client (movements et sales n'ajoutent pas le suffixe ' (Standard)' au nom du produit)

### `djangoClient.catalog.references — References produit (fiche article) + import/export Excel`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.576-671)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Ecriture gerant. Le commentaire du fichier precise que le formulaire produit utilise directement `catalog.*` (hierarchie complete) alors que les pages en lecture seule passent par le service `products` de compatibilite.

**Objectif.** CRUD de la fiche produit (reference), recherche autocomplete pour les formulaires de commande, mise a jour de prix en masse par type, et import/export Excel avec resume et annulation.

**Fonctionnalites** (12)

- list({type?, brand?, category?}) : construit une querystring via URLSearchParams, n'ajoute que les filtres truthy (attention : un id 0 serait ignore)
- autocomplete(query, {type?, brand?, category?}) : GET /catalog/references/autocomplete/?q=<query>&... — brique de la recherche produit dans les formulaires de commande
- getById(id)
- create({type, brand, reference_name, prix_achat?, prix_vente, actif?}) — prix_vente OBLIGATOIRE, prix_achat optionnel ; les prix acceptent number ou string
- update(id, data) en PUT (remplacement COMPLET, pas un PATCH : il faut renvoyer tous les champs)
- delete(id)
- bulkUpdatePrice({type_id, prix_achat?, prix_vente?}) -> {updated: number} — applique un prix a toutes les references d'un type, retourne le nombre de lignes modifiees (a afficher dans un toast)
- exportExcel() -> {blob, filename} via requestBlob (filename lu dans Content-Disposition, fallback 'export.xlsx' pour l'import / 'backup.zip' pour requestBlob generique)
- importExcel(file) : POST multipart champ `file`, la reponse est un FICHIER (rapport Excel) + un resume dans les en-tetes
- importExcel retourne : {blob, filename, batch_id, created_references, updated_references, created_variants, updated_variants, errors_count, skipped_count, new_reference_names[], updated_reference_names[]}
- Les compteurs sont lus avec Number(header || 0) ; les listes de noms sont des tableaux JSON parses dans un try/catch qui retombe sur [] en cas de JSON invalide
- batch_id peut etre null — c'est la cle qui permet l'annulation post-import

**Formulaires** (3)

- Formulaire Reference : type (selecteur, obligatoire), brand (selecteur, obligatoire), reference_name (texte, obligatoire), prix_achat (nombre, optionnel), prix_vente (nombre, obligatoire), actif (booleen/switch, optionnel)
- Formulaire Mise a jour de prix en masse : type_id (obligatoire), prix_achat et/ou prix_vente (au moins un attendu) — retour {updated} a afficher
- Formulaire Import Excel : un unique champ fichier (`file`), soumis en multipart

**Modales / dialogs / drawers** (2)

- Dialogue de revue post-import (mentionne explicitement dans le commentaire, implemente dans products/page.tsx) : affiche les compteurs crees/mis a jour/erreurs/ignores, la liste des nouvelles references et des references mises a jour, avec un bouton d'annulation branche sur catalog.importBatches.cancel(batch_id)
- Telechargement du rapport d'import (blob) et de l'export Excel

**Recherche, filtres, tri, pagination** (2)

- references.list : filtres type / brand / category
- references.autocomplete : recherche texte `q` combinable avec les memes filtres type/brand/category

**Appels API** (9)

- GET /catalog/references/?type=&brand=&category= — liste filtree
- GET /catalog/references/autocomplete/?q=&type=&brand=&category= — suggestions pour les formulaires de commande
- GET /catalog/references/{id}/ — detail
- POST /catalog/references/ — creation
- PUT /catalog/references/{id}/ — remplacement complet
- DELETE /catalog/references/{id}/ — suppression
- POST /catalog/references/bulk-update-price/ — {type_id, prix_achat?, prix_vente?} -> {updated}
- GET /catalog/references/export-excel/ — telechargement du catalogue (blob)
- POST /catalog/references/import-excel/ — import multipart, reponse fichier + en-tetes X-Import-*

**Details UX** (2)

- En-tetes personnalisees a exposer cote serveur (CORS_EXPOSE_HEADERS) : X-Import-Batch-Id, X-Import-Created-References, X-Import-Updated-References, X-Import-Created-Variants, X-Import-Updated-Variants, X-Import-Errors-Count, X-Import-Skipped-Count, X-Import-New-Reference-Names, X-Import-Updated-Reference-Names
- En Flutter, le telechargement de blob doit etre remplace par une ecriture fichier + ouverture (share/open_file) — il n'y a pas d'equivalent direct a l'ancre de telechargement du navigateur

### `djangoClient.catalog.importBatches — Annulation d'un import Excel`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.672-680)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Gerant (celui qui a lance l'import).

**Objectif.** Annuler un import Excel apres coup : supprime ce qui a ete cree par le lot et restaure les valeurs precedentes de ce qui a ete mis a jour.

**Fonctionnalites** (2)

- cancel(batchId: string | number) -> {status: string} — POST avec un body vide {}
- Le batchId provient de l'en-tete X-Import-Batch-Id de la reponse d'import

**Modales / dialogs / drawers** (1)

- Confirmation d'annulation attendue cote UI (action destructive : elle supprime des references creees)

**Appels API** (1)

- POST /catalog/import-batches/{batchId}/cancel/ — annulation transactionnelle du lot d'import

**Etats UI** (1)

- Retour {status} a afficher en toast de succes ; l'erreur remonte en Error avec le message backend

### `djangoClient.catalog.variants — Variantes (couleur) et ajustement de stock`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.681-698)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Ecriture gerant (ajustement manuel de stock trace au nom de l'utilisateur : le mouvement genere porte l'origine AJUSTEMENT et user_name).

**Objectif.** Gerer les declinaisons couleur d'une reference, leur stock courant et leur seuil d'alerte, et appliquer un ajustement manuel d'entree ou de sortie.

**Fonctionnalites** (5)

- list(referenceId?) : ?reference=<id>
- create({product_reference, couleur, stock_actuel?, seuil_alerte?})
- delete(id)
- adjust(id, {type: 'ENTREE' | 'SORTIE', quantite: number, note?: string}) — POST /catalog/variants/{id}/adjust/
- Il n'existe PAS de variants.update : pour corriger un stock il faut passer par adjust (tracabilite imposee)

**Formulaires** (2)

- Formulaire Variante : product_reference (id de la reference parente, obligatoire), couleur (texte/selecteur issu de catalog.colors, obligatoire), stock_actuel (entier, optionnel — stock initial), seuil_alerte (entier, optionnel — declenche l'alerte de rupture)
- Formulaire Ajustement de stock : type (radio/segment ENTREE|SORTIE, obligatoire), quantite (entier > 0), note (texte libre, optionnelle — reprise dans l'historique des mouvements)

**Appels API** (4)

- GET /catalog/variants/?reference= — variantes d'une reference
- POST /catalog/variants/ — creation d'une variante
- DELETE /catalog/variants/{id}/ — suppression
- POST /catalog/variants/{id}/adjust/ — ajustement manuel de stock (ENTREE/SORTIE)

**Details UX** (2)

- seuil_alerte par defaut cote mapping = 1 (voir mapReferenceToProduct : min des seuils, retombe a 1 si aucun)
- Un ajustement cree une ligne dans l'historique des mouvements avec movement_type 'Ajustement manuel'

### `djangoClient.orders — Module Commandes (coeur metier, §5-§7)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.700-793)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** 3 roles metier : GERANT (admin ou magasin — cree/modifie/supprime/annule, assigne preparateur et livreur, voit le dashboard), PREPARATEUR (employer avec commande_role='PREPARATEUR' — demarre et termine la preparation), LIVREUR (employer avec commande_role='LIVREUR' — prend en livraison, livre avec photo, declare un retour). Le gating cote UI se fait avec isGerant / isPreparateur / isLivreur de useCurrentUser ; le backend re-verifie chaque transition dans orders/services.py::change_order_status.

**Objectif.** Cycle de vie complet d'une commande a 6 statuts (NOUVELLE, EN_PREPARATION, PRETE, EN_LIVRAISON, LIVRE, + RETOUR et ANNULEE), avec pre-assignation du preparateur et du livreur, preuve photo a la livraison, filtres d'historique et tableau de bord.

**Fonctionnalites** (15)

- list(filters?) : statut, date_debut, date_fin, magasin_id, livraison_zone, historique (envoye comme '1'), date_from, date_to, preparateur_id — tous optionnels, ajoutes seulement si truthy
- getById(id) : detail complet d'une commande
- create(data) : client_nom, telephone, livraison_zone, items[{product_variant, quantite}], note_preparateur?, note_livreur?, adresse_livraison?, mode_paiement ('AVANT' | 'LIVRAISON'), date_commande?, magasin_id?
- livraison_zone attend le `code` d'une zone creee dans Parametres, OU la valeur speciale 'RECUPERATION' (retrait sur place — remplace l'ancien module Vente/Ticket)
- changeStatus(id, statut, note?, assignee?, photo?) : DEUX modes — si `photo` est fourni, envoi multipart (champs statut, note, preparateur_id, livreur_id, assigned_at, photo) ; sinon POST JSON {statut, note, ...assignee}
- assignee = {preparateur_id?, livreur_id?, assigned_at?} — assigned_at permet de dater l'assignation (creneau)
- Les ids d'assignee ne sont ajoutes au FormData que s'ils sont != null (0 reste donc valide, contrairement aux filtres)
- cancel(id, note?) : POST /orders/{id}/cancel/ — annulation distincte d'un changement de statut (restitue le stock cote backend)
- assignLivreur(id, livreurId) : PRE-assignation d'un livreur AVANT que la commande soit Prete, SANS changer le statut ; reutilisee automatiquement au passage 'En livraison' (orders/services.py::assign_livreur_early/_resolve_assignee)
- assignPreparateur(id, preparateurId) : PRE-assignation d'un preparateur SANS faire progresser le statut — la commande reste 'Nouvelle' (en attente) jusqu'a ce que le preparateur clique lui-meme 'Commencer la preparation'
- availableStaff(role, magasinId?, dateCommande?) -> [{id, full_name, magasin_id, available}] — role strictement 'PREPARATEUR' | 'LIVREUR'
- availableStaff avec date_commande (pour LIVREUR) : SIGNALE sans BLOQUER un conflit d'horaire avec une autre commande deja (pre-)assignee a ce livreur le meme jour/heure — le champ `available` sert a afficher un avertissement, pas a desactiver le choix
- update(id, data) : PATCH partiel, uniquement pour une commande encore 'Nouvelle' (verifie cote backend, orders/views.py) — champs client_nom, telephone, livraison_zone, adresse_livraison, mode_paiement, date_commande, note_preparateur, note_livreur, items[]
- delete(id) : DELETE /orders/{id}/ -> void
- dashboard({date_from?, date_to?, magasin_id?}) : indicateurs du module commandes

**Formulaires** (6)

- Formulaire Creation de commande — champs : client_nom (obligatoire), telephone (obligatoire), livraison_zone (obligatoire, selecteur alimente par zones.list() + option 'RECUPERATION'), adresse_livraison (optionnel, pertinent seulement hors RECUPERATION), mode_paiement ('AVANT' = paye d'avance | 'LIVRAISON' = paye a la livraison), date_commande (date/heure planifiee — a composer avec appDatetimeLocalToIso pour rester en heure d'Antananarivo), note_preparateur (texte libre destine au preparateur), note_livreur (texte libre destine au livreur), magasin_id (pour un admin multi-magasins), items[] : liste de lignes {product_variant (id de variante choisi via catalog.references.autocomplete), quantite}
- Formulaire Modification de commande : memes champs, tous optionnels (PATCH), MAIS uniquement tant que le statut est NOUVELLE — sinon le backend refuse
- Formulaire Changement de statut : statut (obligatoire), note (optionnelle), preparateur_id / livreur_id / assigned_at (selon la transition), photo (fichier — preuve de livraison)
- Formulaire Annulation : note (motif, optionnel)
- Formulaire Assignation preparateur : preparateur_id choisi dans availableStaff('PREPARATEUR', magasinId)
- Formulaire Assignation livreur : livreur_id choisi dans availableStaff('LIVREUR', magasinId, dateCommande) avec badge de disponibilite

**Modales / dialogs / drawers** (5)

- Dialogue de changement de statut avec note et, pour la livraison, capture/selection de photo
- Dialogue d'annulation avec motif
- Dialogue/selecteur d'assignation preparateur
- Dialogue/selecteur d'assignation livreur avec indicateur de conflit d'horaire
- Confirmation de suppression de commande

**Recherche, filtres, tri, pagination** (7)

- Par statut (statut)
- Par plage de dates : deux couples coexistent — date_debut/date_fin ET date_from/date_to (le second est utilise avec appDayBounds pour des bornes ISO absolues)
- Par magasin (magasin_id)
- Par zone de livraison (livraison_zone)
- Mode historique (historique=1) — bascule entre commandes actives et archivees
- Par preparateur (preparateur_id)
- Dashboard filtrable par date_from/date_to/magasin_id

**Appels API** (11)

- GET /orders/?statut=&date_debut=&date_fin=&magasin_id=&livraison_zone=&historique=1&date_from=&date_to=&preparateur_id= — liste filtree
- GET /orders/{id}/ — detail
- POST /orders/ — creation
- POST /orders/{id}/status/ — changement de statut (JSON, ou multipart si photo)
- POST /orders/{id}/cancel/ — annulation avec note
- POST /orders/{id}/assign-livreur/ — pre-assignation livreur sans changement de statut
- POST /orders/{id}/assign-preparateur/ — pre-assignation preparateur sans changement de statut
- GET /orders/available-staff/?role=&magasin_id=&date_commande= — personnel disponible avec drapeau `available`
- PATCH /orders/{id}/ — modification (uniquement statut NOUVELLE)
- DELETE /orders/{id}/ — suppression
- GET /orders/dashboard/?date_from=&date_to=&magasin_id= — indicateurs du module

**Etats UI** (4)

- Le champ de statut courant s'appelle `statut_courant` cote objet commande (voir le service sales qui filtre sur statut_courant === 'LIVRE')
- Les 6+2 statuts utilises dans l'app : NOUVELLE, EN_PREPARATION, PRETE, EN_LIVRAISON, LIVRE, RETOUR, ANNULEE
- Une commande a un historique de statuts (modele WebSocket 'order_status_history')
- Un refus de transition arrive en erreur backend avec message lisible (ex. jour J non atteint)

**Details UX** (4)

- La photo de livraison est la seule donnee binaire du module : elle bascule l'appel en multipart (en Flutter : MultipartFile depuis la camera/galerie)
- Le conflit d'horaire livreur est un AVERTISSEMENT visuel (badge/couleur), jamais un blocage
- La zone 'RECUPERATION' est la vente sur place : masquer l'adresse de livraison et le prix de zone
- Les evenements WebSocket 'order' et 'order_status_history' declenchent un rafraichissement automatique de la liste (useRealtimeRefresh, debounce 400 ms)

### `djangoClient.zones — Zones de livraison configurables (Parametres)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.795-820) + frontend/lib/hooks/useDeliveryZones.ts`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Lecture ouverte a TOUS les roles connectes (les formulaires de commande en ont besoin) ; ECRITURE reservee au GERANT (commentaire explicite dans le code, applique cote backend).

**Objectif.** CRUD des zones de livraison (nom + prix), partagees par toute la societe. Elles alimentent le selecteur `livraison_zone` des commandes via leur `code`.

**Fonctionnalites** (5)

- list() -> [{id, code, nom, prix, actif}] — le `code` est la valeur envoyee dans une commande, pas l'id
- create({nom, prix})
- update(id, {nom?, prix?, actif?}) — `actif` permet de desactiver/reactiver une zone
- delete(id) -> void — SUPPRESSION DOUCE : une zone deja utilisee par des commandes n'est pas reellement supprimee cote serveur, elle est desactivee (DeliveryZoneOptionViewSet.destroy)
- Hook useDeliveryZones() : {zones, loading, refetch} — fetch au montage, catch -> liste vide (jamais d'erreur affichee), un fetch par composant monte (liste courte, changeant rarement)

**Formulaires** (1)

- Formulaire Zone : nom (texte, obligatoire), prix (nombre, obligatoire) ; en edition s'ajoute actif (switch)

**Modales / dialogs / drawers** (2)

- Dialogue de creation/edition de zone dans Parametres
- Confirmation de suppression (avec l'avertissement qu'une zone utilisee sera seulement desactivee)

**Appels API** (4)

- GET /orders/delivery-zones/ — liste des zones
- POST /orders/delivery-zones/ — creation
- PATCH /orders/delivery-zones/{id}/ — modification (nom, prix, actif)
- DELETE /orders/delivery-zones/{id}/ — suppression ou desactivation implicite

**Etats UI** (2)

- loading : true pendant le fetch du hook
- erreur : silencieuse — la liste retombe a [] (pas de toast). A reproduire ou ameliorer en Flutter

**Details UX** (2)

- Ne jamais utiliser l'`id` comme valeur de formulaire de commande : c'est le `code` qui est attendu par orders.create/update
- Les zones inactives doivent etre masquees du selecteur de commande mais rester affichees (grisees) dans Parametres

### `djangoClient.movements — Historique des mouvements de stock (§7.4/§10)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.801-828)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Lecture ; en pratique consultee par le gerant (page Historique/Stock). Chaque ligne porte user_name (auteur du mouvement).

**Objectif.** Lire l'historique des entrees/sorties de stock et le remapper vers une forme d'affichage prete a l'emploi (libelle d'origine en francais, delta signe, nom produit complet).

**Fonctionnalites** (12)

- list({variant_id?}) : ?variant=<id> pour l'historique d'une variante precise, sinon tout l'historique
- MAPPING complet applique a chaque ligne (a reproduire tel quel en Dart) :
- - id <- m.id
- - product <- m.product_variant
- - product_name <- m.reference_name + ' (couleur)' UNIQUEMENT si m.couleur existe ET n'est pas 'Standard'
- - product_reference <- m.reference_name
- - variant_label <- m.couleur
- - changed_by_name <- m.user_name
- - change <- SIGNE : -quantite si m.type === 'SORTIE', +quantite sinon
- - movement_type <- libelle francais de m.origine (voir table ci-dessous), avec repli sur la valeur brute si origine inconnue
- - note <- m.note ; created_at <- m.timestamp
- Table des origines : PREPARATION -> 'Preparation de commande', RETOUR -> 'Retour de commande', ANNULATION -> 'Annulation de commande', LIVRE -> 'Commande livree', FOURNISSEUR -> 'Reception fournisseur', AJUSTEMENT -> 'Ajustement manuel'

**Recherche, filtres, tri, pagination** (1)

- Filtre par variante (variant_id)

**Appels API** (1)

- GET /catalog/movements/?variant= — journal des mouvements de stock

**Details UX** (3)

- `change` est deja signe : afficher en vert quand > 0 et en rouge quand < 0, avec un prefixe +/-
- Les 6 origines correspondent aux automatismes metier : une commande genere des mouvements a la preparation, au retour, a l'annulation et a la livraison — plus les receptions fournisseur et les ajustements manuels
- Le suffixe couleur est omis pour 'Standard' : meme regle que dans le service sales

### `djangoClient.products — Service de compatibilite (lecture seule)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.830-861) + mapReferenceToProduct (l.39-63)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Lecture, tous roles connectes. Utilise par les pages non prioritaires : alertes, rapports, dashboard, chat, scanner, transferts.

**Objectif.** Adapter une ProductReference du catalogue (§8) vers l'ancienne forme plate 'Product' (name/brand/category/initial_quantity/variants) pour eviter de reecrire les pages en lecture seule. IMPORTANT : ce service ne fait AUCUN appel dedie, il derive tout de /catalog/references/.

**Fonctionnalites** (5)

- list({store_id?, magasin_id?, category?}) : magasinId = magasin_id ?? store_id ; recupere TOUTES les references puis filtre EN MEMOIRE par Number(r.magasin) === Number(magasinId) puis par r.category_name === filters.category
- getById(id) : catalog.references.getById puis mapReferenceToProduct
- delete(id) : delegue a catalog.references.delete
- search(query) : recupere TOUTES les references puis filtre en memoire sur reference_name.toLowerCase().includes(q) OU brand_name.toLowerCase().includes(q) — recherche client, non paginee
- mapReferenceToProduct : id, name = reference_name, reference = reference_name, brand = brand_name, category = category_name, description = [type_name, brand_name] filtres et joints par ' — ', unit_price = null, purchase_price = null, shell_price = prix_vente, initial_quantity = SOMME des variants.stock_actuel (0 si absent), alert_threshold = MIN des variants.seuil_alerte (defaut 1 par variante, et 1 si aucune variante), expiry_date/image1/image2/image3/qr_code = null, magasin, variants = [{id, size: '' (toujours vide), color: couleur, quantity: stock_actuel}]

**Recherche, filtres, tri, pagination** (3)

- Filtre magasin (magasin_id ou store_id, en memoire)
- Filtre categorie par NOM (category_name, en memoire)
- Recherche texte en memoire sur nom de reference et marque

**Appels API** (3)

- GET /catalog/references/ — source unique (aucun endpoint /products/ n'existe)
- GET /catalog/references/{id}/ — pour getById
- DELETE /catalog/references/{id}/ — pour delete

**Details UX** (3)

- Aucune image ni QR n'est disponible dans ce mapping (tous a null) : les ecrans qui les affichaient sont vides par construction
- unit_price et purchase_price sont TOUJOURS null : seul shell_price (= prix_vente) porte un prix — piege classique lors du portage
- Le filtrage/recherche etant client, prevoir un cout memoire proportionnel a la taille du catalogue (charger une fois puis filtrer localement en Dart)

### `djangoClient.sales — Ventes derivees des commandes livrees (compatibilite)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.863-892)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Lecture, pages analytics (rapports, dashboard).

**Objectif.** Le module Ventes/Ticket (caisse rapide) a ete RETIRE : le seul flux de vente est la Commande a 6 statuts, qui couvre aussi la vente sur place via la zone 'Recuperation'. Ce service reconstitue des lignes de vente a partir des commandes livrees.

**Fonctionnalites** (3)

- list({store_id?}) : appelle orders.list({magasin_id: store_id}) si store_id fourni, sinon orders.list() sans filtre
- Ne garde QUE les commandes dont order.statut_courant === 'LIVRE' (les autres sont ignorees par `continue`)
- Explose chaque commande en une ligne par item : id = `${order.id}-${item.id}`, product = item.product_variant, variant = item.product_variant, product_name = item.reference_name + ' (couleur)' si couleur && couleur !== 'Standard', quantity = item.quantite, sale_price = item.prix_unitaire, total_price = prix_unitaire != null ? Number(prix_unitaire) * quantite : null, customer_name = order.client_nom, is_paid = TOUJOURS true, total_profit = TOUJOURS 0, sold_at = order.updated_at || order.created_at

**Appels API** (1)

- GET /orders/?magasin_id= — source unique (aucun endpoint /sales/)

**Details UX** (2)

- is_paid code en dur a true et total_profit code en dur a 0 : tout ecran qui affiche une marge a partir de ce service affichera 0 — a NE PAS reimplementer tel quel en Flutter sans le signaler
- La date de vente utilise updated_at en priorite : c'est la date de derniere transition (donc approximativement la date de livraison)

### `djangoClient.notifications — Notifications in-app`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.894-903) + frontend/lib/hooks/useNotificationsWebSocket.ts + frontend/lib/notifications-utils.tsx`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Tous les roles connectes ; le contenu est filtre par le backend selon le destinataire.

**Objectif.** Lister, marquer comme lues (unitairement, en masse ou toutes), supprimer (unitairement, en masse ou toutes) les notifications, et les recevoir en temps reel par WebSocket avec toast.

**Fonctionnalites** (11)

- list() : GET /users/notifications/
- markRead(id, isRead) : PATCH {is_read} — le booleen permet aussi de REMETTRE en non-lu
- markAllRead() : POST mark-all-read/
- delete(id) : DELETE -> void
- deleteAll() : POST delete-all/ -> void
- bulkRead(ids: number[]) : POST bulk-read/ {ids} — selection multiple
- bulkDelete(ids: number[]) : POST bulk-delete/ {ids} — selection multiple
- WebSocket : ws(s)://<host de NEXT_PUBLIC_DJANGO_API_URL>/ws/notifications/?token=<access>
- Reconnexion automatique toutes les 3000 ms si la fermeture n'est pas volontaire (code !== 1000)
- Statut de socket expose : 'connecting' | 'connected' | 'disconnected'
- Option showToast : affiche toast.info(message) avec description `Type : <libelle>` et duration 5000 ms

**Modales / dialogs / drawers** (1)

- Confirmation attendue pour 'tout supprimer' (action destructive)

**Appels API** (8)

- GET /users/notifications/ — liste
- PATCH /users/notifications/{id}/ — {is_read: bool}
- POST /users/notifications/mark-all-read/ — tout marquer lu
- DELETE /users/notifications/{id}/ — suppression unitaire
- POST /users/notifications/delete-all/ — tout supprimer
- POST /users/notifications/bulk-read/ — {ids:[...]}
- POST /users/notifications/bulk-delete/ — {ids:[...]}
- WS /ws/notifications/?token= — flux temps reel

**Etats UI** (2)

- Badge de statut socket : connecte (emeraude), connexion en cours (ambre), deconnecte (rose) — classes dans notifications-utils.tsx::getSocketStatusBadgeClass
- Carte de notification : non lue = fond primary/5, bordure primary/30, ombre ; lue = fond muted/40, bordure neutre (getNotificationCardClass)

**Details UX** (4)

- Types de notification et libelles (typeLabel) : sale->'Vente', product->'Produit', user->'Utilisateur', chat->'Chat', transfer->'Transfert', movement->'Mouvement', defaut->'Autre'
- Icones par type (typeIcon, lucide) : sale->Package, user->User, product->Mail, chat->MessageSquare, transfer->ArrowLeftRight, movement->ArrowUpDown, defaut->Bell
- Couleurs de badge par type (getTypeBadgeClass) : sale=vert, product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange, defaut=muted
- Format de date des notifications : fr-FR JJ/MM/AAAA HH:mm — ATTENTION, formatNotificationDate n'applique PAS le fuseau Indian/Antananarivo (incoherence avec timezone.ts)

### `djangoClient.users — Utilisateurs, employes, profil`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.905-935)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Administration des comptes : reserve gerant/admin cote backend. updateProfile concerne l'utilisateur connecte (tous roles). La suppression exige le mot de passe de l'operateur.

**Objectif.** Lister les magasins et leurs employes, modifier le role d'un utilisateur, supprimer un compte avec confirmation par mot de passe, et mettre a jour son propre profil.

**Fonctionnalites** (7)

- list(role?) : le parametre `role` est ACCEPTE MAIS IGNORE — l'appel est toujours GET /users/magasins/users/ sans querystring (piege a signaler)
- getById(id) : appelle en realite GET /users/me/ — l'id est IGNORE (retourne toujours l'utilisateur connecte ; bug de compatibilite a ne pas reproduire)
- update(id, data) : PUT /users/role/{id}/ — endpoint de changement de role
- delete(id, password) : DELETE /users/delete/{id}/ avec un BODY {password} — le mot de passe de l'operateur est exige pour confirmer
- updateProfile(data) : PATCH /users/me/
- getEmployeesByStore(storeId) : GET /users/magasins/users/ puis, en memoire, find(m => m.magasin_id === storeId) et retourne found.employers (tableau vide si magasin introuvable)
- La structure retournee par /users/magasins/users/ est donc une liste de magasins, chacun portant un tableau `employers`

**Formulaires** (3)

- Formulaire Suppression d'utilisateur : password (obligatoire — mot de passe de l'operateur, envoye dans le corps du DELETE)
- Formulaire Role : data libre envoyee en PUT sur /users/role/{id}/ (role, et selon le backend commande_role PREPARATEUR/LIVREUR)
- Formulaire Profil (PATCH /users/me/) : champs correspondant a CurrentUser — full_name, phone, adresse, photo, company_name, logo, shop_name, shop_logo, position

**Modales / dialogs / drawers** (1)

- Dialogue de suppression avec saisie du mot de passe (double confirmation implicite)

**Appels API** (5)

- GET /users/magasins/users/ — magasins avec leurs employes
- GET /users/me/ — profil courant (aussi utilise, a tort, par getById)
- PUT /users/role/{id}/ — modification du role d'un utilisateur
- DELETE /users/delete/{id}/ (body {password}) — suppression d'un compte
- PATCH /users/me/ — mise a jour de son profil

**Details UX** (1)

- commande_role ('PREPARATEUR' | 'LIVREUR' | null) est le sous-role qui n'existe que pour role='employer' : c'est lui qui pilote tout le gating du module Commandes

### `djangoClient.dashboard — Indicateurs generaux`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.937-957)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Gerant/admin principalement (le backend adapte le perimetre au role et au magasin).

**Objectif.** Fournir les KPI et listes de la page d'accueil. Les 4 methodes tapent le MEME endpoint et n'extraient qu'une portion de la reponse.

**Fonctionnalites** (5)

- getStats(storeId?) : GET /users/dashboard/ -> retourne res.kpis (le parametre storeId est IGNORE)
- getTopProducts(storeId?, limit=5) : meme appel -> res.lists?.top_products || [] (storeId ET limit IGNORES — la troncature doit se faire cote client)
- getRevenueChart(storeId?, period='monthly') : meme appel -> res.lists?.recent_sales || [] (storeId et period IGNORES — malgre son nom, retourne les ventes recentes)
- getSalesAnalytics(storeId?) : meme appel -> payload complet
- Structure attendue : {kpis: {...}, lists: {top_products: [...], recent_sales: [...]}}

**Appels API** (1)

- GET /users/dashboard/ — unique endpoint, appele jusqu'a 4 fois si l'on utilise les 4 methodes (a mutualiser en un seul appel en Flutter)

**Etats UI** (2)

- Listes absentes normalisees en [] (|| []) — l'etat vide est donc naturel
- kpis peut etre undefined si la reponse ne le contient pas (aucune protection)

**Details UX** (1)

- Optimisation evidente pour le portage : un seul GET /users/dashboard/ puis distribution locale des trois sous-parties

### `djangoClient.transfers — Transfert de stock entre magasins + vue benefice`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.959-978)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** transfer : gerant multi-magasins. getProfitByMagasins : ADMIN UNIQUEMENT (commentaire explicite 'admin uniquement').

**Objectif.** Deplacer des quantites de variantes d'un magasin source vers un magasin destination, et consulter un resume par magasin (stock, benefice estime, ventes de la semaine).

**Fonctionnalites** (3)

- transfer(sourceId, destinationId, items) : POST {source_magasin_id, destination_magasin_id, items:[{variant_id, quantity}]}
- items est une liste : un transfert peut porter sur plusieurs variantes en une operation
- getProfitByMagasins() : GET /users/magasins/overview/ puis REEMBALLE la reponse : {profit_by_magasins: res.magasins}

**Formulaires** (1)

- Formulaire Transfert : magasin source (selecteur, obligatoire), magasin destination (selecteur, obligatoire, doit differer de la source), lignes items[] : variante (variant_id) + quantite (quantity, entier > 0). Les erreurs de stock insuffisant remontent du backend.

**Modales / dialogs / drawers** (1)

- Confirmation de transfert attendue cote UI (operation qui deplace du stock reel)

**Appels API** (2)

- POST /users/transfer/products/ — transfert multi-lignes entre magasins
- GET /users/magasins/overview/ — resume par magasin (stock, benefice estime, ventes de la semaine)

**Details UX** (2)

- Un transfert genere des mouvements de stock et une notification de type 'transfer' (badge cyan)
- Le WebSocket 'product_variant' / 'stock_movement' rafraichit les ecrans concernes

### `djangoClient.caisse — Sessions de caisse, mouvements, categories, synthese`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.980-1063)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Gerant/magasin (tenue de caisse par magasin). Le parametre magasin_id permet a un admin de cibler un magasin.

**Objectif.** Ouvrir/fermer une session de caisse avec fond de caisse, enregistrer les entrees et sorties d'especes classees par categorie, et produire une synthese chiffree sur une periode (dont le CA, le cout et le benefice des produits vendus).

**Fonctionnalites** (10)

- listSessions({magasinId?, status?}) : status strictement 'open' | 'closed' ; querystring magasin_id / status
- current(magasinId?) : GET /users/caisse/sessions/current/ ; un 204 (aucune session ouverte) est normalise en NULL grace au `data ?? null` combine au traitement des corps vides dans request()
- open({magasin_id?, opening_balance, opening_note?, opened_at?}) : opening_balance accepte number ou string
- close(sessionId, {closing_balance, closing_note?, closed_at?}) : POST /users/caisse/sessions/{id}/close/
- listMovements({sessionId?, magasinId?, dateFrom?, dateTo?}) : querystring session_id / magasin_id / date_from / date_to
- addMovement({session?, movement_type, amount, reason, category?}) : movement_type strictement 'in' | 'out' ; `session` optionnel (la session courante est deduite cote serveur si absent) ; `category` = id d'une categorie de depense
- deleteMovement(id) -> void
- summary({dateFrom?, dateTo?, magasinId?}) -> {date_from, date_to, total_entrees, total_sorties, solde, sorties_par_categorie: [{categorie, total}], ca_produits_vendus, cout_produits_vendus, benefice_produits_vendus}
- categories.list() -> [{id, nom, created_at}]
- categories.create(nom) / categories.update(id, nom) / categories.delete(id)

**Formulaires** (4)

- Formulaire Ouverture de caisse : opening_balance (montant du fond de caisse, obligatoire, number|string), opening_note (texte, optionnel), opened_at (date/heure, optionnel — a composer avec appDatetimeLocalToIso), magasin_id (optionnel)
- Formulaire Fermeture de caisse : closing_balance (montant compte en caisse, obligatoire), closing_note (texte, optionnel — justification d'ecart), closed_at (date/heure, optionnel)
- Formulaire Mouvement de caisse : movement_type (segment Entree/Sortie, obligatoire), amount (montant, obligatoire), reason (motif, OBLIGATOIRE — chaine requise par la signature), category (selecteur de categorie de depense, optionnel), session (id, optionnel)
- Formulaire Categorie de caisse : nom (obligatoire)

**Modales / dialogs / drawers** (5)

- Dialogue Ouvrir la caisse
- Dialogue Fermer la caisse (avec ecart eventuel entre solde theorique et closing_balance)
- Dialogue Ajouter un mouvement (entree/sortie)
- Confirmation de suppression d'un mouvement
- Dialogue CRUD des categories de depense

**Recherche, filtres, tri, pagination** (3)

- Sessions : par magasin et par statut open/closed
- Mouvements : par session, par magasin, par plage de dates (date_from/date_to)
- Synthese : par plage de dates et par magasin

**Appels API** (12)

- GET /users/caisse/sessions/?magasin_id=&status= — historique des sessions
- GET /users/caisse/sessions/current/?magasin_id= — session ouverte ou null (204)
- POST /users/caisse/sessions/open/ — ouverture avec fond de caisse
- POST /users/caisse/sessions/{id}/close/ — fermeture avec solde compte
- GET /users/caisse/movements/?session_id=&magasin_id=&date_from=&date_to= — mouvements
- POST /users/caisse/movements/ — ajout d'un mouvement in/out
- DELETE /users/caisse/movements/{id}/ — suppression d'un mouvement
- GET /users/caisse/summary/?date_from=&date_to=&magasin_id= — synthese chiffree
- GET /users/caisse/categories/ — categories de depense
- POST /users/caisse/categories/ — creation
- PATCH /users/caisse/categories/{id}/ — renommage
- DELETE /users/caisse/categories/{id}/ — suppression

**Etats UI** (3)

- Aucune session ouverte : current() retourne null -> ecran 'caisse fermee' avec bouton Ouvrir
- Session ouverte : afficher solde courant, mouvements du jour et bouton Fermer
- Les evenements WebSocket 'caisse_session' et 'caisse_movement' declenchent un rafraichissement automatique

**Details UX** (3)

- sorties_par_categorie alimente naturellement un graphique en secteurs / barres
- benefice_produits_vendus = ca_produits_vendus - cout_produits_vendus (a verifier cote backend, mais les trois champs sont fournis)
- Les montants acceptent des chaines a l'envoi (number | string) : formatter/parser proprement en Dart (num vs String)

### `djangoClient.suppliers — Commandes fournisseur (§7.6)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.1065-1092)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Gerant/admin (approvisionnement). Le magasin_id cible le magasin destinataire.

**Objectif.** Creer une commande fournisseur avec ses couts d'acquisition (prix fournisseur, fret import, douane) et ses lignes, puis la receptionner pour injecter le stock.

**Fonctionnalites** (4)

- list(magasinId?) : GET /suppliers/orders/?magasin_id=
- getById(id) : detail
- create({description?, prix_fournisseur, fret_import, douane, lines:[{product_variant, quantite}], magasin_id?}) — les trois montants sont OBLIGATOIRES (number | string)
- receive(id) : POST /suppliers/orders/{id}/receive/ — declenche la reception, generant des mouvements de stock d'origine FOURNISSEUR ('Reception fournisseur')

**Formulaires** (1)

- Formulaire Commande fournisseur : description (texte, optionnel), prix_fournisseur (montant, obligatoire), fret_import (montant, obligatoire), douane (montant, obligatoire), magasin_id (optionnel), lines[] : product_variant (variante, obligatoire) + quantite (entier, obligatoire)

**Modales / dialogs / drawers** (1)

- Confirmation de reception (action irreversible qui incremente le stock)

**Appels API** (4)

- GET /suppliers/orders/?magasin_id= — liste des commandes fournisseur
- GET /suppliers/orders/{id}/ — detail
- POST /suppliers/orders/ — creation avec lignes et couts
- POST /suppliers/orders/{id}/receive/ — reception -> entree de stock

**Details UX** (2)

- Le cout de revient d'une variante decoule de prix_fournisseur + fret_import + douane repartis sur les lignes : c'est ce qui alimente cout_produits_vendus dans la synthese de caisse
- L'evenement WebSocket 'supplier_order' rafraichit la liste

### `djangoClient.backup — Sauvegarde / restauration (admin uniquement)`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.1094-1106)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** ADMIN UNIQUEMENT (commentaire explicite 'admin only'). A gater cote UI avec isAdmin / isSuperAdmin.

**Objectif.** Exporter l'integralite des donnees en archive et re-importer une archive de sauvegarde.

**Fonctionnalites** (2)

- export() : requestBlob('/users/backup/export/') -> {blob, filename} ; filename lu dans Content-Disposition, fallback 'backup.zip'
- import(file) : POST multipart champ `file` -> {detail: string} (message a afficher en toast)

**Formulaires** (1)

- Formulaire Restauration : un unique champ fichier (archive), soumis en multipart

**Modales / dialogs / drawers** (1)

- Confirmation forte avant l'import (ecrasement potentiel de toutes les donnees)

**Appels API** (2)

- GET /users/backup/export/ — telechargement de l'archive de sauvegarde
- POST /users/backup/import/ — restauration depuis une archive

**Details UX** (1)

- En Flutter : ecrire le blob dans un fichier local puis proposer un partage/enregistrement ; pour l'import, utiliser un file picker

### `djangoClient.chat — Messagerie interne`

- **Fichier Next.js** : `frontend/lib/django-client.ts (l.1108-1119)`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Tous les roles connectes ; la liste des interlocuteurs est filtree par le backend.

**Objectif.** Lister les utilisateurs joignables et charger l'historique d'une conversation (privee par recipient_id, ou de groupe par room_name).

**Fonctionnalites** (3)

- users() : GET /users/chat/users/
- history({recipient_id?, room_name?}) : querystring construite via URLSearchParams, parametres ajoutes seulement si truthy
- Le temps reel du chat n'est PAS dans ce fichier (WebSocket dedie ailleurs) ; seuls les notifications (/ws/notifications/) et la synchro donnees (/ws/data/) sont definis dans lib/

**Recherche, filtres, tri, pagination** (2)

- Conversation privee : recipient_id
- Salon : room_name

**Appels API** (2)

- GET /users/chat/users/ — interlocuteurs disponibles
- GET /users/chat/history/?recipient_id=&room_name= — historique des messages

**Details UX** (1)

- Une notification de type 'chat' (badge ambre, icone MessageSquare) est emise a la reception d'un message

### `lib/types.ts — Modeles TypeScript partages`

- **Fichier Next.js** : `frontend/lib/types.ts`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** UserRole = 'admin' | 'store_manager' | 'employee' — c'est la nomenclature FRONT (traduite depuis admin/magasin/employer par auth.getCurrentUser). Attention : useCurrentUser expose au contraire les roles BRUTS backend (admin/magasin/employer) : deux conventions coexistent dans le projet.

**Objectif.** Declarations de types utilisees par useAuth et les anciens ecrans. Une grande partie decrit un modele HERITE (Product avec sku/quantity, Sale, Store, Supplier) qui ne correspond plus a l'API catalogue actuelle.

**Fonctionnalites** (12)

- UserRole : 'admin' | 'store_manager' | 'employee'
- User : id, email, username, first_name, last_name, role: UserRole, is_approved, store_id?, created_at
- AuthState : user | null, isAuthenticated, isLoading, error | null
- Product (HERITE, ne correspond PAS a mapReferenceToProduct) : id, name, description, sku, category, quantity, unit_price, unit_cost, store_id, supplier_id?, created_at, updated_at
- Sale (HERITE) : id, product_id, quantity, unit_price, total_price, employee_id, store_id, created_at, notes?
- Store : id, name, address, city, country, phone, email, manager_id, created_at
- Supplier : id, name, contact_person, email, phone, address, city, country, created_at
- DashboardStats : total_revenue, total_sales, total_products, total_stores, pending_approvals, monthly_growth
- RevenueSummary : today, this_week, this_month, all_time
- TopProduct : id, name, quantity_sold, revenue
- RevenueData : date, revenue
- SalesAnalytics : total_sales, average_sale_value, top_products: TopProduct[], sales_by_employee: Record<string, number>

**Details UX** (2)

- Piege de portage : le type `Product` de ce fichier n'a rien a voir avec l'objet reellement produit par mapReferenceToProduct (qui expose reference/brand/shell_price/initial_quantity/alert_threshold/variants). Ne pas s'appuyer sur types.ts pour modeliser le catalogue en Dart — s'appuyer sur mapReferenceToProduct et sur les payloads catalog.*
- DashboardStats/RevenueSummary/SalesAnalytics ne sont branches sur aucun endpoint reel du client (le dashboard renvoie {kpis, lists}) : ce sont des types orphelins

### `lib/validation.ts — Schemas Zod (heritage, non branches sur l'API actuelle)`

- **Fichier Next.js** : `frontend/lib/validation.ts`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun gating.

**Objectif.** Schemas de validation Zod avec messages d'erreur en francais, plus des helpers safeParse et un formateur d'erreurs. ATTENTION : ces schemas decrivent l'ancien modele (SKU, tailles S/M/XL/XXL, fournisseurs) et ne couvrent AUCUN formulaire du module Commandes/Catalogue actuel — a considerer comme une reference de messages, pas comme la validation en vigueur.

**Fonctionnalites** (8)

- productSchema : sku (string, min 2 'SKU minimum 2 caracteres', max 50 'SKU maximum 50 caracteres', regex /^[A-Z0-9\-_]+$/ 'SKU doit contenir seulement des majuscules, chiffres, tirets et underscores'), name (min 3 'Nom minimum 3 caracteres', max 200 'Nom maximum 200 caracteres'), description (max 500 'Description maximum 500 caracteres', optionnel), category_id (uuid 'Categorie invalide', optionnel), supplier_id (uuid 'Fournisseur invalide', optionnel), location (max 100 'Localisation maximum 100 caracteres', optionnel), unit_price (number min 0 'Prix doit etre positif', max 99999 'Prix trop eleve'), color (max 50 'Couleur maximum 50 caracteres', optionnel), material (max 100 'Matiere maximum 100 caracteres', optionnel), status (enum in_stock|low|out_of_stock, optionnel)
- productSizeSchema : size (enum S|M|XL|XXL, message 'Taille invalide'), quantity (min 0 'Quantite doit etre positive', int 'Quantite doit etre un entier'), reorder_level (min 0 'Limite doit etre positive', int 'Limite doit etre un entier')
- stockMovementSchema : product_id (uuid 'Produit invalide'), product_size_id (uuid 'Taille invalide', optionnel), size (enum S|M|XL|XXL, optionnel), type (enum entry|exit, message 'Type de mouvement invalide'), quantity (min 1 'Quantite minimum 1', max 10000 'Quantite maximum 10000', int 'Quantite doit etre un entier'), notes (max 500 'Notes maximum 500 caracteres', optionnel)
- productImageSchema : image_url (url 'URL image invalide'), size (enum S|M|XL|XXL, optionnel), color_variant (max 50 'Variante couleur maximum 50 caracteres', optionnel), is_primary (boolean, optionnel)
- supplierSchema : name (min 2 'Nom minimum 2 caracteres', max 200 'Nom maximum 200 caracteres'), email (email 'Email invalide', optionnel), phone (max 20 'Telephone maximum 20 caracteres', optionnel), address (max 500 'Adresse maximum 500 caracteres', optionnel), city (max 100 'Ville maximum 100 caracteres', optionnel), country (max 100 'Pays maximum 100 caracteres', optionnel), payment_terms (max 200 'Conditions maximum 200 caracteres', optionnel)
- excelImportRowSchema (colonnes en francais, cles exactes) : 'SKU' (min 2 'SKU requis'), 'Nom du produit' (min 3 'Nom requis'), 'Categorie' (optionnel), 'Couleur' (optionnel), 'Matiere' (optionnel), 'Prix unitaire' (number positive 'Prix doit etre positif'), 'Taille S'/'Taille M'/'Taille XL'/'Taille XXL' (number nonnegative 'Quantite non negative', optionnels)
- Helpers safeParse : validateProduct, validateProductSize, validateStockMovement, validateProductImage, validateSupplier, validateExcelImportRow
- formatValidationErrors(errors) : aplatit recursivement l'arbre d'erreurs en tableau de chaines `chemin.pointe: message` (prefixe cumule a chaque niveau)

**Formulaires** (1)

- Aucun formulaire actif du module Commandes/Catalogue n'est valide par ces schemas : les validations en vigueur sont celles du backend (messages renvoyes et concatenes par request())

**Details UX** (2)

- Pour le portage Flutter : reutiliser les LIBELLES d'erreur francais (coherence de ton) mais reconstruire les regles a partir des vrais champs (reference_name, prix_vente, quantite, client_nom, telephone, etc.)
- Les tailles S/M/XL/XXL n'existent plus dans le modele actuel (remplacees par la couleur de variante) — ne pas les porter

### `lib/timezone.ts — Fuseau metier Indian/Antananarivo (regle du 'jour J')`

- **Fichier Next.js** : `frontend/lib/timezone.ts`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Impacte directement le gating METIER du PREPARATEUR et du LIVREUR : la date a partir de laquelle ils peuvent agir sur une commande ('jour J') doit etre identique sur le serveur, le web et le mobile.

**Objectif.** Fixer le fuseau applicatif a Madagascar (UTC+3, sans heure d'ete) independamment du fuseau de l'appareil, pour que le calcul du 'jour J', les bornes de filtre par date et les affichages soient coherents avec le backend (Stock/settings.py TIME_ZONE='Indian/Antananarivo').

**Fonctionnalites** (10)

- APP_TIME_ZONE = 'Indian/Antananarivo'
- APP_UTC_OFFSET = '+03:00' (decalage fixe toute l'annee)
- appDayKey(date = new Date()) -> 'YYYY-MM-DD' a Antananarivo, via Intl.DateTimeFormat('en-CA') ; retourne '' si la date est invalide (NaN)
- Les cles de jour sont comparables directement avec < et <= (ordre lexicographique = ordre chronologique)
- appToday() -> appDayKey(new Date())
- appDayBounds(dayKey = appToday()) -> {start, end} en ISO absolu : `${dayKey}T00:00:00.000+03:00` et `${dayKey}T23:59:59.999+03:00` convertis en toISOString() — a envoyer tels quels en date_from/date_to
- fmtAppDate(value) -> toLocaleDateString('fr-FR', {timeZone: APP_TIME_ZONE}) ; retourne le tiret cadratin '—' si value est absente ou invalide
- fmtAppDateTime(value) -> toLocaleString('fr-FR', {timeZone, day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) — ex. '10/09/2026 09:30' ; '—' si absent/invalide
- appDatetimeLocalValue(date = new Date()) -> 'YYYY-MM-DDTHH:mm' a l'heure d'Antananarivo, pour pre-remplir un champ date/heure ; corrige le cas ou le moteur renvoie '24' pour minuit en le remplacant par '00'
- appDatetimeLocalToIso(value) : lit une saisie 'YYYY-MM-DDTHH:mm' COMME une heure d'Antananarivo (ajoute ':00' si longueur 16, puis suffixe +03:00) et retourne l'instant ISO absolu

**Details UX** (3)

- Toutes les dates affichees dans l'app doivent passer par fmtAppDate / fmtAppDateTime : format francais JJ/MM/AAAA et JJ/MM/AAAA HH:mm
- La valeur vide affichee est '—' (tiret cadratin), pas une chaine vide
- Incoherence a corriger au portage : formatNotificationDate (notifications-utils.tsx) n'applique pas le fuseau applicatif

### `lib/utils.ts — Helper de classes CSS`

- **Fichier Next.js** : `frontend/lib/utils.ts`
- **Groupe d'audit** : `api-client`
- **Cible Flutter** : composant / couche partagee — a porter
- **Etat** : PARTIAL

**Role et gating.** Aucun.

**Objectif.** Fusionner des classes Tailwind conditionnelles sans conflit.

**Fonctionnalites** (1)

- cn(...inputs: ClassValue[]) = twMerge(clsx(inputs)) — combine clsx (classes conditionnelles) et tailwind-merge (derniere classe gagnante en cas de conflit Tailwind)

**Details UX** (1)

- Sans equivalent en Flutter : ce helper disparait au portage, remplace par des ThemeData / styles conditionnels Dart

## 3. Composants partages Next.js

107 composants distincts recenses.

| Composant | Fichier | Comportement |
| --- | --- | --- |
| `useCurrentUser` | `frontend/lib/auth/useCurrentUser.ts` | Hook qui appelle GET /api/users/me/ une fois au montage et derive les flags de role. isGerant = role admin OU magasin ; isPreparateur = employer + commande_role==='PREPARATEUR' ; isLivreur = employer + commande_role==='LIVREUR'. Expose aussi isAdmin/isSuperAdmin (=admin), isMagasin, isEmployer, isManager, isCompanyOwner. Retourne loading pendant la requete ; user=null si non authentifie ou erreur.… |
| `useRealtimeRefresh` | `frontend/lib/hooks/useRealtimeRefresh.ts` | S'abonne au DataSyncContext (WebSocket /ws/data/) et rappelle le callback quand un evenement dont le `model` figure dans la liste arrive. Debounce 400 ms par defaut. Ici : ['order','order_status_history'] -> fetchOrders(true) (silencieux). |
| `DataSyncProvider / useDataSync` | `frontend/lib/contexts/DataSyncContext.tsx` | WebSocket authentifie par token sur /ws/data/, avec reconnexion automatique et socketStatus ('connecting'|'connected'|'disconnected'). Diffuse des evenements {model, action ('created'|'updated'|'deleted'), id, magasin_id}. Modeles connus : product_variant, stock_movement, order, order_status_history, supplier_order, caisse_session, caisse_movement. Monte dans app/(app)/layout.tsx. |
| `useDeliveryZones` | `frontend/lib/hooks/useDeliveryZones.ts` | GET /api/orders/delivery-zones/ au montage ; retourne {zones, loading, refetch}. Echoue en silence (zones=[]). Appele 3 fois independamment sur cette page (page, EditOrderDialog, CreateOrderDialog) — 3 requetes distinctes. |
| `buildZoneOptions (local, a extraire pour Flutter)` | `frontend/app/(app)/orders/page.tsx` | Transforme les zones serveur en options {value: code, label: '{nom} ({prix} Ar)', frais: prix} et ajoute TOUJOURS l'entree litterale {value:'RECUPERATION', label:'Recuperation (0 Ar)', frais:0} qui n'existe pas en base. |
| `DateTimeInput` | `frontend/components/ui/datetime-input.tsx` | Deux inputs natifs separes (type=date + type=time, largeur 128px pour l'heure) exposant une valeur unique au format 'YYYY-MM-DDTHH:mm'. Si la date est vide, rien n'est emis meme si l'heure est saisie ; si l'heure est vide, '00:00' est utilise. min/max n'appliquent que la partie date. |
| `Helpers fuseau applicatif` | `frontend/lib/timezone.ts` | APP_TIME_ZONE='Indian/Antananarivo', APP_UTC_OFFSET='+03:00'. appDayKey/appToday (cle 'YYYY-MM-DD' comparable lexicographiquement), appDayBounds, fmtAppDate ('JJ/MM/AAAA'), fmtAppDateTime ('JJ/MM/AAAA HH:mm'), appDatetimeLocalValue (valeur datetime-local a l'heure du magasin), appDatetimeLocalToIso (lit une saisie comme heure d'Antananarivo et renvoie l'instant ISO). Indispensable a reproduire tel… |
| `djangoClient.orders / .catalog / .zones` | `frontend/lib/django-client.ts` | Client HTTP unique (base NEXT_PUBLIC_DJANGO_API_URL, defaut http://127.0.0.1:8010/api) avec JWT + refresh automatique. orders.changeStatus bascule automatiquement en multipart/form-data quand une photo est fournie. orders.list serialise les filtres en query string ; availableStaff accepte role, magasin_id et date_commande. |
| `IconAction (local)` | `frontend/app/(app)/orders/page.tsx` | Bouton icone (+ libelle optionnel via showLabel) enveloppe dans un Tooltip shadcn dont le contenu est le label. Variants default/outline/ghost/destructive, prop disabled. |
| `OrderItemsEditor (local)` | `frontend/app/(app)/orders/page.tsx` | Selecteur d'articles partage par CreateOrderDialog et EditOrderDialog : filtres Categorie->Sous-type + Marque, recherche autocomplete debouncee 250 ms, choix couleur (variant) avec stock, quantite controlee par le stock, panier avec suppression de ligne. La prop showPrices masque toute donnee financiere (preparateur). |
| `OrderTimeline (local)` | `frontend/app/(app)/orders/page.tsx` | Chronologie derivee de status_history : ne garde que le PREMIER timestamp par statut, n'affiche que les etapes atteintes, et ajoute en tete 'Commande cree le' (created_at) et 'Livraison prevue le' (date_commande). |
| `NoteForm (local)` | `frontend/app/(app)/orders/page.tsx` | Note libre + photo optionnelle (uniquement si showPhoto, c.-a-d. cible PRETE) avec apercu local. Remonte (note, photo?) au parent. Etat reinitialise a chaque ouverture car Radix demonte le contenu du dialogue ferme. |
| `Sidebar (navigation)` | `frontend/components/layout/sidebar.tsx` | L'entree 'Commandes' -> /orders n'a aucun flag de restriction, donc elle est visible pour tous les roles. Les pages voisines 'Recuperation' (/pickup, adminOnly) et 'Bilan du jour' (/bilan, livreurOnly) sont les compagnons metier de cet ecran. |
| `Primitives shadcn/ui utilisees` | `frontend/components/ui/` | Button, Card/CardContent/CardHeader/CardTitle/CardDescription, Input, Label, Textarea, Badge, Skeleton, Table/TableHeader/TableBody/TableRow/TableHead/TableCell, Dialog/DialogContent/DialogHeader/DialogTitle/DialogDescription/DialogFooter, Select/SelectTrigger/SelectContent/SelectItem/SelectValue, Tooltip/TooltipTrigger/TooltipContent. Icones lucide-react : Plus, Trash2, Truck, Package, RefreshCw,… |
| `useDebouncedValue` | `frontend/lib/hooks/useDebouncedValue.ts` | Retourne la valeur avec un retard (250 ms par défaut) pour découpler la frappe du recalcul de la liste filtrée. |
| `djangoClient` | `frontend/lib/django-client.ts` | Client HTTP singleton. Tokens JWT en localStorage sous la clé 'django_tokens' ; en 401 il rafraîchit via POST /users/refresh/ et rejoue la requête, sinon purge les tokens et redirige window.location vers /login. Normalise les erreurs en Error(message) à partir de detail / non_field_errors / concaténation des erreurs de champs. Traite 204/205 et corps vide comme des succès. Sous-services utilisés i… |
| `CrudRow` | `frontend/app/(app)/products/page.tsx` | Composant local partagé par les listes Marques et Couleurs : ligne bordée affichant un libellé + slot `trailing` optionnel + bouton Pencil (bascule en mode édition : Input autoFocus + boutons OK/Annuler) + bouton Trash2 rouge (suppression immédiate, sans confirmation). |
| `ProductOrderItemsEditor` | `frontend/app/(app)/products/page.tsx` | Éditeur de panier réutilisable dans le dialog de commande : charge ses PROPRES listes catégories/types/marques (3 GET indépendants au montage), autocomplétion serveur débouncée 250 ms, sélection couleur/quantité avec contrôle de stock, chips de filtres actifs, et liste des lignes du panier. Prop `showPrices` masque prix unitaire, totaux de ligne et prix des suggestions. |
| `CategoriesTypesCrud / ColorsCrudList` | `frontend/app/(app)/products/page.tsx` | Sous-composants des onglets Catégories et Couleurs du dialog Paramètres du catalogue : CRUD complet catégorie + sous-types imbriqués (avec bascule 'avec couleurs'), et CRUD couleurs. |
| `Route API /api/ai/check-duplicates` | `frontend/app/api/ai/check-duplicates/route.ts` | Route Next.js server-side qui construit un prompt en français et interroge Ollama (POST {OLLAMA_BASE_URL:-http://localhost:11434}/api/generate, modèle {OLLAMA_MODEL:-qwen3:4b}, stream:false, think:false, AbortSignal.timeout 600 s). Nettoie les balises <think> et les fences markdown, parse le JSON attendu [{nouvelle, ressemble_a, raison}] et renvoie {warnings: []} en cas d'échec de parsing. La corr… |
| `Sidebar (entrée 'Produits')` | `frontend/components/layout/sidebar.tsx` | Entrée de menu 'Produits' -> /products, icône Shirt, avec le flag `hideLivreur: true` : la ligne est filtrée pour un LIVREUR (ligne 210 : `if (item.hideLivreur && isLivreur) return false`). Aucun filtre pour le préparateur ni le gérant. |
| `AppLayout (app)` | `frontend/app/(app)/layout.tsx` | Enveloppe toutes les pages du groupe : DataSyncProvider (WebSocket), Sidebar, TopBar, et redirection client vers /login si djangoClient.isAuthenticated() est faux. Aucun contrôle de rôle au niveau du layout. |
| `djangoClient.movements` | `frontend/lib/django-client.ts (l.803-828)` | movements.list({variant_id?}) => GET /catalog/movements/[?variant=<id>] puis REMAPPE chaque ligne: id, product = m.product_variant (ID DE VARIANTE), product_name = reference_name + (couleur && couleur!=='Standard' ? ' (couleur)' : ''), product_reference = reference_name, variant_label = couleur, changed_by_name = user_name, change = (type==='SORTIE' ? -quantite : quantite), movement_type = libelle… |
| `djangoClient.products / mapReferenceToProduct` | `frontend/lib/django-client.ts (l.39-63 et l.834-842)` | products.list() => GET /catalog/references/ puis mapReferenceToProduct: { id: ref.id (ID DE REFERENCE), name: reference_name, reference: reference_name, brand: brand_name, category: category_name, description: 'type — marque', shell_price: prix_vente, initial_quantity = somme des stock_actuel des variantes, alert_threshold = min des seuil_alerte (defaut 1), magasin, variants: [{id, size:'', color:… |
| `DataSyncProvider / useDataSync + useRealtimeRefresh` | `frontend/lib/contexts/DataSyncContext.tsx et frontend/lib/hooks/useRealtimeRefresh.ts` | Provider monte dans app/(app)/layout.tsx. Ouvre un WebSocket sur /ws/data/ avec le token JWT en query, expose socketStatus ('connecting'|'connected'|'disconnected') et subscribe(listener). Chaque message est un DataSyncEvent { model, action ('created'|'updated'|'deleted'), id, magasin_id }. Modeles possibles: product_variant, stock_movement, order, order_status_history, supplier_order, caisse_sess… |
| `AppLayout` | `frontend/app/(app)/layout.tsx` | Layout du groupe (app): redirige vers /login si non authentifie, enveloppe dans DataSyncProvider, et rend Sidebar + TopBar + <main class='flex-1 overflow-auto'>{children}</main> dans un conteneur h-screen. |
| `Sidebar` | `frontend/components/layout/sidebar.tsx` | Navigation laterale (fixe, w-64, toggle burger sous lg avec overlay). L'item 'Mouvements' (icone TrendingUp) est adminOnly => visible seulement pour isAdminOrSuperAdmin (admin ou magasin). Pendant le chargement du user, tous les items sauf superAdminOnly sont affiches. L'item actif prend un degrade bleu + une pastille blanche a droite. Pied de menu: bouton 'Deconnexion'. |
| `UI shadcn utilises` | `frontend/components/ui/{button,card,input,label,table,badge,hover-card,skeleton,calendar,popover,sonner}.tsx` | Button (variants outline/ghost, sizes sm/icon), Card/CardHeader/CardTitle/CardDescription/CardContent, Input (type=date et texte), Label, Table/TableHeader/TableBody/TableRow/TableHead/TableCell, Badge (variant outline), HoverCard/Trigger/Content, Skeleton, Calendar (wrapper react-day-picker avec captionLayout configurable et chevrons lucide), Popover/Trigger/Content, Toaster sonner monte dans app… |
| `StockMovementViewSet / StockMovementSerializer` | `catalog/views.py (l.590) et catalog/serializers.py (l.88)` | ReadOnlyModelViewSet, IsAuthenticated, queryset scope par get_accessible_magasins(user), filtre optionnel ?variant=<id>, non pagine. Champs serialises: id, product_variant, reference_name, couleur, type, quantite, origine, reference, note, user, user_name (user.full_name), timestamp. Toute ecriture passe exclusivement par catalog/services.py::apply_stock_movement. |
| `useNotificationsWebSocket` | `frontend/lib/hooks/useNotificationsWebSocket.ts` | Hook WebSocket notifications (PERIMETRE). Options: {onNotification?: (notif) => void, showToast?: boolean = false}; les deux sont stockes dans des refs mises a jour a chaque render pour eviter de reconnecter la socket quand les callbacks changent. Retourne {socketStatus: 'connecting'|'connected'|'disconnected', connectWebSocket, disconnectWebSocket}. Connexion au montage UNIQUEMENT si djangoClient… |
| `buildWebSocketUrl` | `frontend/lib/ws-utils.ts` | Utilitaire (PERIMETRE, 6 lignes): buildWebSocketUrl(path, token) => `${wsProto}//${host}${path}?token=${token}` avec wsProto='wss:' si window.location.protocol==='https:' sinon 'ws:', et host = NEXT_PUBLIC_DJANGO_API_URL (defaut http://localhost:8010/api) prive du schema et tronque au premier '/'. Utilise UNIQUEMENT par DataSyncContext ('/ws/data/'). La page chats et le hook notifications duplique… |
| `Notifications (cloche TopBar)` | `frontend/components/notifications.tsx` | Consommateur du hook WS (showToast:true) — c'est lui qui fait apparaitre un toast pour chaque message de chat recu (le backend cree une Notification notif_type='chat' a chaque ChatMessage). DropdownMenu w-96: badge compteur non lues sur la cloche (affiche '9+' au-dela de 9), barre d'actions 'Tout marquer lu' (PATCH via markAllRead, desactive si 0 non lue) et 'Tout effacer' (purement LOCAL: enregis… |
| `notifications-utils` | `frontend/lib/notifications-utils.tsx` | Helpers partages: typeIcon/typeLabel/getTypeBadgeClass par notif_type — 'chat' -> icone MessageSquare, libelle 'Chat', badge ambre (amber-500/10). Autres types: sale/Vente/vert, product/Produit/bleu, user/Utilisateur/violet, transfer/Transfert/cyan, movement/Mouvement/orange, defaut 'Autre'/muted. formatNotificationDate = toLocaleString('fr-FR', jj/mm/aaaa HH:mm). getNotificationCardClass(isRead).… |
| `djangoClient.chat` | `frontend/lib/django-client.ts (lignes 1109-1121)` | chat.users() -> GET /users/chat/users/ ; chat.history({recipient_id?, room_name?}) -> GET /users/chat/history/ avec query string construite via URLSearchParams (recipient_id prioritaire cote serveur si present). Le client gere les tokens JWT (localStorage 'django_tokens'), le refresh automatique en 401 et expose getAccessToken()/isAuthenticated() utilises pour construire les URLs WebSocket. |
| `djangoClient.products.list (compat)` | `frontend/lib/django-client.ts (lignes 834-846 + mapReferenceToProduct lignes 39-63)` | products.list() appelle en realite catalog.references.list() (GET /catalog/references/) puis mappe chaque reference: id, name = reference_name, reference = reference_name (le meme champ !), brand, category, description, unit_price = null (!), shell_price = prix_vente, initial_quantity = somme des stock_actuel des variantes, alert_threshold = min des seuil_alerte, magasin, variants[]. C'est cette l… |
| `Sidebar (navigation globale)` | `frontend/components/layout/sidebar.tsx` | Entree 'Chats' -> /chats, icone MessageCircle, SANS aucun flag de restriction => visible pour admin, magasin, preparateur et livreur. Regles de filtrage globales: pendant `loading` on affiche tout sauf superAdminOnly; superAdminOnly exige isSuperAdmin (=admin), adminOnly exige admin OU magasin, hidePreparateur/hideLivreur masquent, livreurOnly reserve au livreur. Element actif = degrade bleu + pas… |
| `Composants shadcn/ui utilises par /chats` | `frontend/components/ui/{button,input,avatar,badge,tabs,scroll-area,dropdown-menu,popover,card}.tsx` | Button (variants ghost/outline/default, size icon), Input, Avatar+AvatarFallback (pas d'AvatarImage: uniquement des initiales, aucune photo de profil n'est chargee dans le chat), Badge (variant outline ou classes custom), Tabs/TabsList/TabsTrigger, ScrollArea, DropdownMenu*, Popover* (+ sonner `toast` pour les erreurs). Card/CardContent importes mais inutilises. |
| `ConfirmDeleteDialog` | `frontend/components/confirm-delete-dialog.tsx` | Modal de confirmation d'action destructive avec re-authentification. Props : open, onOpenChange, title (défaut 'Confirmer la suppression'), description (ReactNode), onConfirm(password) => Promise<void>. Gère son propre state password/loading/error. Bloque toute fermeture pendant loading. Vide password et error à la fermeture. Erreur inline rouge sous le champ, alimentée par err.message de la prome… |
| `AppLayout (Sidebar + TopBar + DataSyncProvider)` | `frontend/app/(app)/layout.tsx` | Coquille de toutes les pages authentifiées : redirection client vers /login si aucun token, Sidebar à gauche, TopBar en haut, main scrollable, le tout enveloppé dans DataSyncProvider. |
| `Primitives shadcn/ui` | `frontend/components/ui/{button,input,card,table,dialog,label,select,badge,skeleton,tabs}.tsx` | Button (variants default/outline/ghost/destructive, sizes sm), Input, Card/CardHeader/CardTitle/CardDescription/CardContent, Table et ses sous-composants, Dialog (overlay modal + fermeture Esc/clic extérieur), Label, Select (trigger + popover d'items), Badge (variants default/secondary/outline), Skeleton (bloc pulsant), Tabs/TabsList/TabsTrigger/TabsContent. Icônes lucide-react utilisées sur la pa… |
| `DataSyncProvider / DataSyncContext` | `frontend/lib/contexts/DataSyncContext.tsx` | Monte dans app/(app)/layout.tsx. Ouvre un WebSocket sur /ws/data/ authentifie par le token d'acces, avec reconnexion automatique et statut 'connecting' | 'connected' | 'disconnected'. Diffuse des evenements { model, action: 'created'|'updated'|'deleted', id, magasin_id }; les modeles possibles sont product_variant, stock_movement, order, order_status_history, supplier_order, caisse_session, caisse… |
| `AppLayout ((app)/layout.tsx)` | `frontend/app/(app)/layout.tsx` | Guard d'authentification unique du groupe de routes: redirige vers /login si aucun token. Monte DataSyncProvider, Sidebar et TopBar autour du contenu; le <main> est le seul conteneur scrollable. |
| `lib/timezone.ts` | `frontend/lib/timezone.ts` | Fuseau metier Indian/Antananarivo (UTC+3 fixe, pas d'heure d'ete). Fournit APP_TIME_ZONE, APP_UTC_OFFSET, appDayKey/appToday, appDayBounds (bornes ISO 00:00:00.000 -> 23:59:59.999 du jour a Antananarivo), fmtAppDate/fmtAppDateTime, appDatetimeLocalValue et appDatetimeLocalToIso. Utilise par /bilan; PAS utilise par /caisse qui a ses propres helpers bases sur l'heure de l'appareil. |
| `UI shadcn (Button, Input, Label, Textarea, Badge, Skeleton, ` | `frontend/components/ui/` | Primitives partagees par les deux pages. Dialog = modal centre avec overlay et fermeture par onOpenChange; Select = popover a liste; Badge variant='outline' sert d'etiquette de statut/ecart; Skeleton = placeholder de chargement. |
| `toast (sonner) + Toaster` | `frontend/app/layout.tsx` | Systeme de notifications global monte a la racine. /caisse en fait un usage intensif (succes + toutes les erreurs), /bilan ne l'utilise pas du tout. |
| `AIAnalysis` | `frontend/components/ai-analysis.tsx` | Card autonome à 3 états (idle / loading / résultat-ou-erreur) avec state local analysis, loading, error. POST /api/ai/analyze avec le payload AIAnalysisData en JSON. Le texte est rendu en whitespace-pre-wrap (l'IA est explicitement priée de répondre sans markdown). Erreur => texte rouge + bouton Régénérer. Aucun état n'est persisté: quitter la page perd l'analyse. |
| `UI shadcn (Card/CardHeader/CardTitle/CardDescription/CardCon` | `frontend/components/ui/` | Primitives shadcn/Tailwind. Badge variants: default (bg-primary), secondary, destructive (bg-destructive text-white), outline (text-foreground, bordure). Button variants utilisés: default et outline, tailles sm. Skeleton = bloc animé de placeholder. Table = <table> HTML stylée sans tri ni pagination intégrés. |
| `Recharts` | `node_modules/recharts (import direct dans les deux pages)` | Librairie de graphiques web. À porter en Flutter (fl_chart ou équivalent): LineChart + Line monotone (dashboard), PieChart + Pie avec labels inline (dashboard <=5 catégories), BarChart horizontal (dashboard >5 catégories), BarChart vertical (reports CA). ResponsiveContainer width 100% / height 260 partout. |
| `AppLayout ((app) group layout)` | `frontend/app/(app)/layout.tsx` | Seul garde d'authentification : `useEffect` -> si !djangoClient.isAuthenticated() alors router.replace('/login'). Enveloppe tout dans <DataSyncProvider> (WebSocket) et rend Sidebar + TopBar + <main> scrollable. Aucun contrôle de rôle : le gating par rôle est fait page par page et dans la Sidebar. |
| `TransferProductsDialog` | `frontend/components/transfer-products-dialog.tsx` | Coquille Dialog quasi plein écran (97vw x 95vh) autour de TransferProductsPanel. Props : open, onOpenChange, sourceStore, stores, initialCart, onSuccess. Titre 'Transfert de produits', description 'Depuis <shop_name> — sélectionnez des produits (et leurs variantes)...'. Le panel n'est monté que si sourceStore est non nul, avec `key={sourceStore.magasin_id}` pour réinitialiser tout l'état interne a… |
| `TransferProductsPanel` | `frontend/components/transfer-products-panel.tsx` | Cœur du flux de transfert, partagé avec la page /transferts. Colonne gauche 'Produits du magasin' : Input de recherche (icône Search, filtre client sur name OU reference), ScrollArea, état 'Chargement...' (Loader2), état vide différencié ('Aucun produit dans ce magasin' vs 'Aucun résultat'). Produit SANS variante : nom + '{reference} · Stock : {n}' + Input number (min 1, max stock, clampé par getQ… |
| `UI kit shadcn (Button, Card, Input, Label, Badge, Switch, Sk` | `frontend/components/ui/` | Primitives réutilisées : Button (variants default/outline/ghost/secondary, sizes sm/icon), Card+CardHeader/Title/Description/Content, Input (texte, password, number min/max, file accept=image/*), Label, Badge (outline/secondary), Switch (checked + onCheckedChange), Skeleton (placeholders de chargement), Tabs/TabsList/TabsTrigger/TabsContent (onglets non persistés), Dialog/DialogTrigger/Content/Hea… |
| `toast (sonner)` | `sonner (npm) — <Toaster/> monté au niveau racine` | Unique canal de feedback des deux pages : toast.success / toast.error / toast.info. AUCUNE des deux pages n'affiche d'erreur inline sous un champ de formulaire — à reproduire en Flutter par des SnackBar. |
| `useRealtimeRefresh + DataSyncContext` | `frontend/lib/hooks/useRealtimeRefresh.ts, frontend/lib/contexts/DataSyncContext.tsx` | Abonnement WebSocket global (DataSyncProvider monte dans app/(app)/layout.tsx). useRealtimeRefresh(models, onRefresh, {debounceMs=400}) rappelle onRefresh quand un evenement {model, action, id, magasin_id} arrive avec un model de la liste. Models possibles: product_variant, stock_movement, order, order_status_history, supplier_order, caisse_session, caisse_movement. La page /suppliers ecoute 'supp… |
| `Sidebar (navigation + gating de menu)` | `frontend/components/layout/sidebar.tsx` | Filtre les entrees selon: pendant loading -> tout sauf superAdminOnly ; superAdminOnly && !isSuperAdmin -> masque ; adminOnly && !isAdminOrSuperAdmin -> masque ; hidePreparateur && isPreparateur -> masque ; hideLivreur && isLivreur -> masque ; livreurOnly && !isLivreur -> masque. 'Fournisseurs' (/suppliers, icone Truck) = adminOnly ; 'Transferts' (/transfers, icone ArrowLeftRight) = superAdminOnly… |
| `AppLayout (garde d'authentification)` | `frontend/app/(app)/layout.tsx` | Redirige vers /login si !djangoClient.isAuthenticated(). Monte DataSyncProvider (WebSocket) + Sidebar + TopBar autour de toutes les pages du groupe (app). |
| `Primitives UI shadcn utilisees` | `frontend/components/ui/*` | suppliers: Button, Card/CardContent, Input, Label, Textarea, Badge, Skeleton, Table/TableHeader/TableBody/TableRow/TableHead/TableCell, Dialog/DialogContent/DialogHeader/DialogTitle/DialogDescription/DialogFooter, Select/SelectTrigger/SelectValue/SelectContent/SelectItem. transfers: Card/CardContent, Skeleton, Button, Input, Label, Badge, ScrollArea, Dialog. Toasts: `toast` de la librairie sonner … |
| `TopBar` | `frontend/components/layout/topbar.tsx` | Barre superieure sticky h-16 : cloche <Notifications />, bouton de bascule de theme (Moon/Sun via next-themes, monte apres `mounted`), et un DropdownMenu d'avatar (initiales calculees sur full_name, 2 lettres max, fallback 'U') avec label role (admin -> 'Administrateur', magasin -> 'Gerant de magasin', employer -> 'Commercial'), lien profil et 'Deconnexion'. |
| `djangoClient (DjangoAPIClient)` | `frontend/lib/django-client.ts` | Client HTTP JWT unique. Base = NEXT_PUBLIC_DJANGO_API_URL ?? 'http://127.0.0.1:8010/api'. Tokens {access, refresh} persistes dans localStorage sous la cle 'django_tokens'. Sur un 401 il tente POST /users/refresh/ puis rejoue la requete; si le refresh echoue il purge les tokens et fait window.location.href='/login'. Les erreurs sont normalisees en Error(message) en prenant, dans l'ordre : error.det… |
| `mapReferenceToProduct (adaptateur catalogue -> 'Product' pla` | `frontend/lib/django-client.ts (fonction en tete de fichier, ~ligne 35)` | Transforme une ProductReference du catalogue en objet 'Product' plat consomme par /alerts et /scanner : name=reference=reference_name, brand=brand_name, category=category_name, description='type_name — brand_name', shell_price=prix_vente, initial_quantity = SOMME des variants.stock_actuel, alert_threshold = MINIMUM des variants.seuil_alerte (1 par defaut si aucun variant), variants=[{id, size:'', … |
| `Toaster (sonner)` | `frontend/app/layout.tsx + frontend/components/ui/sonner.tsx` | Toasts globaux montes une seule fois a la racine : position='top-right', richColors (vert succes / rouge erreur), closeButton, expand, toastOptions.duration = 5000 ms, theme synchronise avec next-themes. Toutes les pages de cet audit y publient via toast.success / toast.error de 'sonner'. |
| `Notifications (cloche du header)` | `frontend/components/notifications.tsx` | Dropdown global monte dans TopBar sur toutes les pages authentifiees. Badge de non-lues, apercu 8 items, marquage lu unitaire/global (API), effacement purement local via localStorage 'stockv2_dismissed_notification_ids' (200 max), lien 'Voir toutes les notifications' -> /notifications. C'est ce composant qui porte showToast:true et emet donc les toasts temps reel de toute l'application. Inventaire… |
| `notifications-utils (helpers de presentation)` | `frontend/lib/notifications-utils.tsx` | 6 helpers purs partages par la page et la cloche. typeIcon(type) -> icone lucide 4x4 : sale=Package, user=User, product=Mail, chat=MessageSquare, transfer=ArrowLeftRight, movement=ArrowUpDown, defaut=Bell. typeLabel(type) -> 'Vente'|'Produit'|'Utilisateur'|'Chat'|'Transfert'|'Mouvement'|'Autre'. formatNotificationDate(value) -> toLocaleString('fr-FR', day/month 2-digit, year numeric, hour/minute 2… |
| `djangoClient.notifications` | `frontend/lib/django-client.ts` | Sous-module du client HTTP (lignes 894-902) : list() GET /users/notifications/ ; markRead(id, isRead) PATCH /users/notifications/{id}/ {is_read} ; markAllRead() POST /users/notifications/mark-all-read/ ; delete(id) DELETE /users/notifications/{id}/ ; deleteAll() POST /users/notifications/delete-all/ ; bulkRead(ids) POST /users/notifications/bulk-read/ {ids} ; bulkDelete(ids) POST /users/notificati… |
| `LoginForm` | `frontend/components/auth/login-form.tsx` | Client Component. States: email, password, showPw, loading. Pre-remplit l'email depuis ?email=. Appelle djangoClient.auth.login, verifie is_confirmed, traduit les erreurs via la map ERRORS + friendlyError (matching par includes), redirige /dashboard (raw_role admin|magasin) ou /orders (autres). Toasts sonner uniquement, pas d'erreur inline. |
| `RegisterForm` | `frontend/components/auth/register-form.tsx` | Client Component. States: fullName, username, email, password, companyName, shopName, adminEmail, position, showPw, loading, role ('admin'|'store_manager'|'employee', defaut employee). Champs conditionnels par role, validations sequentielles par toast, mapping des roles vers le backend fait dans djangoClient. Redirige vers /auth/pending-approval en cas de succes. |
| `ForgotPasswordForm` | `frontend/components/auth/forgot-password-form.tsx` | Client Component avec machine a etats step='request'|'check' et status=null|'none'|'pending'|'approved'|'rejected'. Trois sous-formulaires (demande / verification de statut / definition du mot de passe), bandeau de statut colore, sous-formulaire de mot de passe visible seulement si status==='approved'. Redirige /login apres confirmation. |
| `ResetPasswordForm` | `frontend/components/auth/reset-password-form.tsx` | Client Component. States: oldPassword, newPassword, confirm, loading. POST /users/change-password/ en direct via djangoClient.post. Verifie l'egalite des deux nouveaux mots de passe cote client, laisse le reste au backend. Redirige /login sans purger les tokens. |
| `AdminGuard` | `frontend/components/auth/admin-guard.tsx` | HOC de garde. Utilise useCurrentUser().isAdminOrSuperAdmin (= role admin OU magasin). Pendant loading: <Loader2 h-8 w-8 animate-spin text-muted-foreground> centre plein ecran. Si non autorise: useEffect -> router.push('/dashboard') ET rendu d'une carte 'Acces refuse' (icone ShieldAlert h-12 w-12 text-red-500, texte 'Cette page est reservee aux administrateurs.' + 'Redirection en cours…'). Sinon re… |
| `SuperAdminGuard` | `frontend/components/auth/superadmin-guard.tsx` | Identique a AdminGuard mais teste isSuperAdmin (= role === 'admin' strictement). Message: 'Cette page est reservee au Super Administrateur.'. Egalement DEAD CODE — jamais importe. |
| `useAuth` | `frontend/lib/hooks/useAuth.ts` | Hook alternatif (DEAD CODE — jamais importe). Expose user (type lib/types.ts User avec role 'admin'|'store_manager'|'employee'), isLoading, error, login(email,password), register(email,username,password,role), logout(), isAuthenticated = !!user && user.is_approved, isPendingApproval = !!user && !user.is_approved. Charge l'utilisateur au montage via djangoClient.auth.getCurrentUser() si isAuthentic… |
| `RootLayout + Toaster + ThemeProvider + GlobalErrorBoundary` | `frontend/app/layout.tsx` | lang='fr', suppressHydrationWarning, font Geist/Geist_Mono. ThemeProvider next-themes (attribute='class', defaultTheme='system', enableSystem, disableTransitionOnChange). <Toaster> sonner global: position 'top-right', richColors, closeButton, expand, duration 5000ms, couleurs pilotees par --popover/--popover-foreground/--border. GlobalErrorBoundary importe mais NON MONTE dans le JSX (il n'envelopp… |
| `AppLayout (groupe (app))` | `frontend/app/(app)/layout.tsx` | Hors perimetre mais c'est LE seul garde d'authentification reel de l'app: useEffect -> if (!djangoClient.isAuthenticated()) router.replace('/login'). Aucune verification de role a ce niveau, aucune verification d'expiration du token. Rend Sidebar + TopBar + DataSyncProvider. |
| `proxy.ts (middleware inactif)` | `frontend/proxy.ts` | Exporte une fonction `proxy` avec un matcher, mais le fichier n'est PAS nomme middleware.ts et aucun middleware.ts n'existe: ce code ne s'execute JAMAIS. Il laisse de toute facon passer toutes les routes (commentaire: le controle est fait cote client car le token est en localStorage). publicRoutes declarees: ['/login','/register','/']. |
| `Primitives shadcn/ui utilisees dans le perimetre auth` | `frontend/components/ui/{card,input,button,label,radio-group}.tsx` | Card/CardHeader/CardTitle/CardDescription/CardContent (conteneur d'ecran auth), Input, Button (variants: default, outline, ghost ; prop asChild pour envelopper un Link), Label, RadioGroup/RadioGroupItem (choix du type de compte). Icones lucide-react: Loader2, Mail, Lock, User, Eye, EyeOff, Building2, KeyRound, ArrowLeft, Clock, CheckCircle2, XCircle, LogOut, ShieldAlert. |
| `useCurrentUser (hook d'identite + roles)` | `frontend/lib/auth/useCurrentUser.ts` | Hook client. Au montage : si !djangoClient.isAuthenticated() => user=null, loading=false ; sinon GET /users/me/ puis mapping vers CurrentUser { id, email, role('admin'|'magasin'|'employer'), full_name (full_name || username || ''), is_confirmed, phone, adresse, photo, company_name, logo, shop_name, shop_logo, magasin_id, position, commande_role('PREPARATEUR'|'LIVREUR'|null), store_id = magasin_id,… |
| `djangoClient (client HTTP JWT)` | `frontend/lib/django-client.ts` | Singleton DjangoAPIClient. API_BASE_URL = process.env.NEXT_PUBLIC_DJANGO_API_URL ?? 'http://127.0.0.1:8010/api'. Tokens { access, refresh } charges au constructeur depuis localStorage['django_tokens']. isAuthenticated() = !!tokens?.access. getAccessToken() = tokens?.access || null. Refresh automatique sur 401 via POST /users/refresh/ avec file d'attente (refreshQueue) pour eviter les refresh concu… |
| `Notifications (cloche de la TopBar)` | `frontend/components/notifications.tsx` | DropdownMenu w-96 avec badge de non-lues (9+ au dela de 9), en-tete + badge '<n> non lue(s)', barre d'actions 'Tout marquer lu' / 'Tout effacer', etats loading (Loader2) / vide ('Aucune notification') / liste (8 premiers items dans une ScrollArea max-h-96), pied 'Voir toutes les notifications' -> /notifications. GET /users/notifications/ au montage (accepte un tableau brut ou {results}). PATCH /us… |
| `notifications-utils (typeIcon / typeLabel / getTypeBadgeClas` | `frontend/lib/notifications-utils.tsx` | Mapping type -> icone lucide, type -> libelle FR, type -> classes de badge colorees, date -> format fr-FR 'JJ/MM/AAAA HH:mm'. getNotificationCardClass(isRead) : lue = 'bg-muted/40 border-border', non lue = 'bg-primary/5 border-primary/30 shadow-sm'. getSocketStatusBadgeClass : connected = emeraude, connecting = ambre, disconnected = rose. |
| `Button (shadcn, cva)` | `frontend/components/ui/button.tsx` | Variantes : default (bg-primary), destructive, outline, secondary, ghost (hover:bg-accent), link. Tailles : default h-9 px-4 py-2, sm h-8 px-3, lg h-10 px-6, icon size-9, icon-sm size-8, icon-lg size-10. Icones SVG forcees a size-4. disabled => pointer-events-none + opacity-50. Anneau de focus 3px. Le perimetre utilise ghost + icon (bascule mobile sidebar, theme, cloche, avatar) et ghost + w-full … |
| `Avatar / AvatarFallback (radix)` | `frontend/components/ui/avatar.tsx` | Avatar : size-8 rounded-full overflow-hidden. AvatarFallback : cercle plein centre (bg-muted par defaut, surcharge en bg-blue-600 texte blanc dans la TopBar). AvatarImage existe mais n'est PAS utilise par la TopBar (la photo user.photo n'est jamais affichee). |
| `DropdownMenu (radix) — Trigger / Content / Item / Label / Se` | `frontend/components/ui/dropdown-menu.tsx` | Utilise par la TopBar (menu utilisateur align='end' w-56) et par Notifications (align='end' w-96 p-0). Les items de notification utilisent onSelect={(e) => e.preventDefault()} pour empecher la fermeture du menu au clic. |
| `useIsMobile` | `frontend/hooks/use-mobile.ts` | matchMedia('(max-width: 767px)') ; MOBILE_BREAKPOINT = 768 ; retourne !!isMobile (false pendant le premier rendu SSR/avant effet). Utilise uniquement par components/ui/sidebar.tsx. ATTENTION : la vraie Sidebar (components/layout/sidebar.tsx) n'utilise PAS ce hook, elle se base sur le breakpoint CSS Tailwind lg (1024 px). |
| `Sheet / Tooltip / Skeleton / Separator / Input / ScrollArea ` | `frontend/components/ui/` | Primitives shadcn consommees par le perimetre : Sheet+Tooltip+Skeleton+Separator+Input par components/ui/sidebar.tsx (kit non utilise) ; ScrollArea et Badge par components/notifications.tsx. |
| `ImageUpload` | `frontend/components/image-upload.tsx` | Sélecteur d'image unique (drag & drop + bouton parcourir) dans une Card. Valide taille (défaut 5 MB) et format MIME (JPEG/PNG/WebP), affiche une prévisualisation base64 carrée avec nom + poids en MB, et un bouton 'Changer l'image'. Remonte le File au parent via onImageSelect. Toasts sonner succès/erreur. Props onUploadStart/onUploadEnd déclarées mais jamais appelées. Import Badge inutilisé. Compos… |
| `ProductImageGallery` | `frontend/components/product-image-gallery.tsx` | Galerie produit 2 colonnes (image principale + QR code) avec badge 'Principal', actions Télécharger le QR (<a download>) et Copier données (presse-papiers JSON), encart SKU/ID image/date, plus grille de vignettes cliquables avec boutons 'Principal' et suppression (sans confirmation), tous deux conditionnés par la présence des callbacks. État vide dédié. Sélection initiale figée au montage. Toasts … |
| `image-service` | `frontend/lib/image-service.ts` | Utilitaires images : uploadImage (base64 via FileReader), uploadImageToBackend (POST /api/upload — route inexistante), getOptimizedImageUrl, validateImageFile (messages EN), getImageDimensions, deleteImage (DELETE /api/upload?path=), batchUploadImages (séquentiel, ignore productId, saute les échecs). Module entièrement orphelin, logs préfixés [v0]. |
| `qrcode-generator` | `frontend/lib/qrcode-generator.ts` | generateQRCode (JSON 6 champs, ECC 'H', 300px, PNG data URL), generateSimpleQRCode (ECC 'M', 200px), parseQRCodeData (JSON.parse tolérant -> fallback { raw }). Dépend du paquet npm `qrcode`. Module orphelin. |
| `ui primitives (shadcn/Radix)` | `frontend/components/ui/` | Card/CardHeader/CardTitle/CardDescription/CardContent, Button (variants default|outline|ghost|destructive, sizes sm|icon), Badge, Dialog/DialogContent/DialogHeader/DialogTitle/DialogDescription/DialogFooter, Input, Label, Skeleton, Select, Table. Icônes lucide-react (Upload, X, Check, AlertCircle, Download, Copy, Loader2, ShieldAlert, Sparkles, Trash2). |
| `sonner (toast)` | `package.json — sonner ^1.7.1` | Système de toasts global utilisé par ImageUpload (1 succès, 2 erreurs), ProductImageGallery (2 succès en anglais), /superadmin, /users et /products (toast.error avec duration 10000 pour les erreurs d'import). |
| `djangoClient (singleton DjangoAPIClient)` | `frontend/lib/django-client.ts` | Instance unique exportee et importee partout. Porte les tokens en memoire + localStorage['django_tokens'], le refresh JWT avec file d'attente anti-concurrence, la normalisation des erreurs et 15 services metier (auth, passwordResetRequests, catalog{categories,types,brands,colors,references,importBatches,variants}, orders, zones, movements, products, sales, notifications, users, dashboard, transfer… |
| `mapReferenceToProduct(ref)` | `frontend/lib/django-client.ts (l.39-63)` | Adaptateur ProductReference (catalogue §8) -> ancienne forme plate Product. Somme les stocks des variantes en initial_quantity, prend le MIN des seuil_alerte en alert_threshold (defaut 1), compose description = 'type — marque', force unit_price/purchase_price/expiry_date/images/qr_code a null, et met shell_price = prix_vente. variants[].size est toujours ''. Utilise par products.list/getById/searc… |
| `request / requestFormData / requestBlob / requestFormDataFor` | `frontend/lib/django-client.ts (l.148-361)` | Quatre pipelines HTTP : JSON, multipart -> JSON, GET -> fichier, multipart -> fichier + en-tetes de resume. Tous appliquent le meme protocole 401 -> refresh -> rejeu unique, et la meme extraction de nom de fichier via Content-Disposition. |
| `useCurrentUser()` | `frontend/lib/auth/useCurrentUser.ts` | Source de verite du gating par role. GET /users/me/ au montage (uniquement si djangoClient.isAuthenticated()), expose {user, loading} + les drapeaux isAdmin, isMagasin, isEmployer, isSuperAdmin(=admin), isAdminOrSuperAdmin, isManager, isGerant(=admin||magasin), isPreparateur(=employer && commande_role==='PREPARATEUR'), isLivreur(=employer && commande_role==='LIVREUR'), isCompanyOwner(=admin && is_… |
| `useAuth()` | `frontend/lib/hooks/useAuth.ts` | Etat de session cote UI : {user, isAuthenticated (= user existe ET is_approved), isPendingApproval (= user existe MAIS pas approuve), isLoading, error, login, register, logout}. login/register posent isLoading et error, relancent l'exception apres l'avoir stockee. logout() n'attend PAS la promesse de djangoClient.auth.logout() (appel non await) puis remet user et error a null. |
| `useDeliveryZones()` | `frontend/lib/hooks/useDeliveryZones.ts` | Charge les zones de livraison au montage ({zones, loading, refetch}). Chaque composant qui en a besoin appelle le hook independamment (un fetch par montage, assume car la liste est courte et change rarement). Toute erreur retombe silencieusement sur une liste vide. |
| `DataSyncProvider / useDataSync()` | `frontend/lib/contexts/DataSyncContext.tsx` | WebSocket global /ws/data/?token=<access> diffusant des evenements {model, action, id, magasin_id}. Modeles : product_variant, stock_movement, order, order_status_history, supplier_order, caisse_session, caisse_movement. Actions : created | updated | deleted. Expose socketStatus ('connecting'|'connected'|'disconnected') et subscribe(listener) -> unsubscribe. Reconnexion automatique apres 3000 ms s… |
| `useRealtimeRefresh(models, onRefresh, {debounceMs=400, silen` | `frontend/lib/hooks/useRealtimeRefresh.ts` | S'abonne a DataSync, ignore les evenements dont le model n'est pas dans la liste surveillee, et declenche onRefresh apres un debounce de 400 ms — pour absorber les rafales (vente -> produit -> mouvement) en un seul rechargement. Utilise des refs pour eviter de re-souscrire a chaque rendu. |
| `useNotificationsWebSocket({onNotification, showToast})` | `frontend/lib/hooks/useNotificationsWebSocket.ts` | WebSocket /ws/notifications/?token=<access>. Sur message : toast.info(message) avec description 'Type : <libelle>' et duree 5000 ms si showToast, puis callback onNotification. Reconnexion automatique 3000 ms si fermeture non volontaire. Expose {socketStatus, connectWebSocket, disconnectWebSocket}. |
| `buildWebSocketUrl(path, token)` | `frontend/lib/ws-utils.ts` | Construit l'URL WS : protocole wss si la page est en https sinon ws, host extrait de NEXT_PUBLIC_DJANGO_API_URL (schema retire, premier segment avant le premier '/'), puis `${path}?token=${token}`. Le token JWT circule donc en QUERYSTRING. |
| `useDebouncedValue(value, delayMs=250)` | `frontend/lib/hooks/useDebouncedValue.ts` | Retarde la propagation d'une valeur (saisie de recherche) de 250 ms par defaut pour decoupler la frappe du refiltrage d'une liste. Equivalent Dart : Timer + setState, ou un debounce sur le TextEditingController. |
| `notifications-utils (typeIcon, typeLabel, formatNotification` | `frontend/lib/notifications-utils.tsx` | Table de correspondance type de notification -> icone lucide, libelle francais et classes de badge colore (sale=vert, product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange, autre=muted). Carte non lue = fond primary/5 + bordure primary/30 + ombre ; lue = muted. Badge de socket : connecte=emeraude, connexion=ambre, deconnecte=rose. Date formatee fr-FR JJ/MM/AAAA HH:mm SANS le fuseau… |
| `image-service (uploadImage, uploadImageToBackend, getOptimiz` | `frontend/lib/image-service.ts` | uploadImage convertit en data URL base64 via FileReader (implementation de demonstration, aucun stockage reel). validateImageFile : taille max 5 Mo par defaut ('File size exceeds 5MB limit') et formats acceptes image/jpeg, image/png, image/webp ('File format not supported. Use JPEG, PNG, or WebP'). batchUploadImages continue malgre les echecs et rapporte la progression (current/total). uploadImage… |
| `qrcode-generator (generateQRCode, generateSimpleQRCode, pars` | `frontend/lib/qrcode-generator.ts` | generateQRCode encode un JSON {sku, productName, imageId, size (defaut 'S'), colorVariant (defaut 'Default'), timestamp ISO} en PNG data URL, correction d'erreur 'H', marge 1, largeur 300. generateSimpleQRCode : texte brut, correction 'M', largeur 200. parseQRCodeData : JSON.parse avec repli {raw: qrData}. |
| `cn(...inputs)` | `frontend/lib/utils.ts` | twMerge(clsx(inputs)) — composition de classes Tailwind. Sans equivalent Flutter. |
| `Schemas Zod + formatValidationErrors` | `frontend/lib/validation.ts` | 6 schemas (produit, taille, mouvement, image, fournisseur, ligne d'import Excel) avec messages francais, helpers safeParse, et un aplatisseur d'erreurs recursif produisant des chaines 'chemin.pointe: message'. Modele HERITE non aligne sur l'API catalogue actuelle. |
| `Helpers de fuseau (APP_TIME_ZONE, appDayKey, appToday, appDa` | `frontend/lib/timezone.ts` | Uniformisent toutes les dates de l'app sur Indian/Antananarivo (UTC+3 fixe). A porter en Dart avec un offset fixe de +3 h (aucune heure d'ete a gerer) — c'est la condition pour que le 'jour J' du preparateur/livreur soit identique sur mobile, web et serveur. |

## 4. Surface API consommee par le web

Recensement de tous les appels releves dans les pages et dans `lib/django-client.ts`.

327 appels distincts.

| Appel | Utilise par |
| --- | --- |
| GET /api/users/me/ — via useCurrentUser, fournit role + commande_role (base de tout le gating) | /orders |
| GET /api/orders/ (+ params statut, date_debut, date_fin, historique=1, date_from, date_to, preparateur_id) — liste des commandes ; le backend filtre deja par role et renvoie un serializer different par role | /orders |
| POST /api/orders/ — creation d'une commande (client_nom, telephone, livraison_zone, adresse_livraison, mode_paiement, date_commande, note_preparateur, note_livreur, items[]) | /orders |
| PATCH /api/orders/{id}/ — modification d'une commande (gerant uniquement cote serveur : IsGerant) | /orders |
| DELETE /api/orders/{id}/ — suppression definitive (gerant, statut NOUVELLE) | /orders |
| POST /api/orders/{id}/status/ — changement de statut. Corps JSON {statut, note, preparateur_id?, livreur_id?, assigned_at?} ; si une photo est jointe, envoi en multipart/form-data avec les memes champs + photo | /orders |
| POST /api/orders/{id}/cancel/ — annulation (corps {note}, ici toujours sans note) | /orders |
| POST /api/orders/{id}/assign-preparateur/ — pre-assignation preparateur sans changer le statut ({preparateur_id}) | /orders |
| POST /api/orders/{id}/assign-livreur/ — pre-assignation livreur sans changer le statut ({livreur_id}) | /orders |
| GET /api/orders/available-staff/?role=PREPARATEUR|LIVREUR[&magasin_id=][&date_commande=ISO] — liste {id, full_name, magasin_id, available} ; date_commande sert a signaler (sans bloquer) un conflit d'horaire livreur | /orders |
| GET /api/orders/delivery-zones/ — via useDeliveryZones, alimente zoneOptions (code/nom/prix) | /orders |
| GET /api/catalog/categories/ — selecteur Categorie de OrderItemsEditor | /orders |
| GET /api/catalog/types/ — selecteur Sous-type (filtre client-side sur t.category === categoryId) | /orders |
| GET /api/catalog/brands/ — selecteur Marque | /orders |
| GET /api/catalog/references/autocomplete/?q=&type=&brand=&category= — autocomplete catalogue (debounce 250 ms), renvoie les references avec leur tableau couleurs[{variant_id, couleur, stock_actuel}] et prix_vente | /orders |
| WS /ws/data/ (DataSyncProvider) — evenements model 'order' et 'order_status_history' declenchent un refetch silencieux | /orders |
| GET /catalog/references/ — liste complète des références (avec variants, category_name, type_name, brand_name, prix_achat, prix_vente, photo, actif, is_rupture/is_stock_bas par variante) — chargement initial + tous les rafraîchissements | /products |
| GET /catalog/categories/ — alimente le filtre catégorie, les selects des formulaires et l'onglet Catégories ; expose `avec_couleurs` | /products |
| GET /catalog/types/ — sous-types ; expose `category` (id) utilisé pour reconstruire le lien type -> catégorie côté client | /products |
| GET /catalog/brands/ — marques | /products |
| GET /catalog/colors/ — couleurs proposées dans les sélecteurs de variante | /products |
| DELETE /catalog/references/{id}/ — supprimer une référence et toutes ses variantes | /products |
| PUT /catalog/references/{id}/ — mise à jour d'une référence (type, brand, reference_name, prix_achat, prix_vente, actif) | /products |
| PATCH /catalog/references/{id}/ (multipart FormData, champ `photo`) — upload de la photo, appel SÉPARÉ après le PUT (djangoClient.patchFormData) | /products |
| POST /catalog/references/ — création d'une référence (type, brand, reference_name, prix_achat, prix_vente) | /products |
| GET /catalog/references/export-excel/ — export du catalogue en .xlsx (réponse blob, nom via Content-Disposition) | /products |
| POST /catalog/references/import-excel/ (multipart, champ `file`) — import ; réponse = blob du fichier annoté + en-têtes X-Import-Batch-Id, X-Import-Created-References, X-Import-Updated-References, X-Import-Created-Variants, X-Import-Updated-Variants, X-Import-Errors-Count, X-Import-Skipped-Count, X- | /products |
| POST /catalog/import-batches/{batchId}/cancel/ — annule un import déjà écrit en base (supprime les créations, restaure les valeurs précédentes des mises à jour) | /products |
| POST /catalog/references/bulk-update-price/ {type_id, prix_achat?, prix_vente?} — réponse {updated: n} — modification groupée par sous-type | /products |
| GET /catalog/references/autocomplete/?q=&type=&brand=&category= — suggestions pour le panier de commande ; chaque suggestion porte id, brand_name, reference_name, type, type_name, prix_vente et un tableau `couleurs` [{variant_id, couleur, stock_actuel}] | /products |
| POST /catalog/variants/ {product_reference, couleur, stock_actuel, seuil_alerte} — ajout d'une variante couleur | /products |
| DELETE /catalog/variants/{id}/ — suppression d'une variante (et de son historique de stock) | /products |
| POST /catalog/variants/{id}/adjust/ {type: 'ENTREE'|'SORTIE', quantite, note} — ajustement manuel de stock | /products |
| POST /catalog/categories/ {nom, ordre, avec_couleurs} — création de catégorie (ordre = categories.length) | /products |
| PATCH /catalog/categories/{id}/ {nom} ou {avec_couleurs} — renommage / bascule avec-couleurs | /products |
| DELETE /catalog/categories/{id}/ — suppression de catégorie | /products |
| POST /catalog/types/ {category, nom} — création de sous-type | /products |
| PATCH /catalog/types/{id}/ {nom} — renommage de sous-type | /products |
| DELETE /catalog/types/{id}/ — suppression de sous-type | /products |
| POST /catalog/brands/ {nom} — création de marque (aussi utilisée par les marques suggérées) | /products |
| PATCH /catalog/brands/{id}/ {nom} — renommage de marque | /products |
| DELETE /catalog/brands/{id}/ — suppression de marque | /products |
| POST /catalog/colors/ {nom} — création de couleur | /products |
| PATCH /catalog/colors/{id}/ {nom} — renommage de couleur | /products |
| DELETE /catalog/colors/{id}/ — suppression de couleur | /products |
| POST /orders/ {client_nom, telephone, livraison_zone, adresse_livraison, mode_paiement, date_commande?, note_preparateur, note_livreur, items:[{product_variant, quantite}]} — création d'une commande depuis le catalogue | /products |
| GET /orders/available-staff/?role=PREPARATEUR — liste des préparateurs assignables | /products |
| GET /orders/available-staff/?role=LIVREUR&date_commande=<ISO> — liste des livreurs, refetchée à chaque changement de date/heure de commande (le champ `available` signale un conflit d'horaire mais N'EST PAS affiché sur cette page) | /products |
| POST /orders/{id}/assign-preparateur/ {preparateur_id} — pré-assignation sans faire progresser le statut | /products |
| POST /orders/{id}/assign-livreur/ {livreur_id} — pré-assignation du livreur | /products |
| POST /api/ai/check-duplicates (route Next.js locale) {newNames, existingNames} -> {warnings:[{nouvelle, ressemble_a, raison}]} — proxy vers Ollama (POST {OLLAMA_BASE_URL}/api/generate, modèle par défaut qwen3:4b, stream:false, think:false, timeout 600 s) ; renvoie [] si la réponse n'est pas du JSON  | /products |
| GET /users/me/ — via useCurrentUser(), détermine isGerant/isPreparateur | /products |
| WebSocket (DataSyncContext) — événements de modèles 'product_variant' et 'stock_movement' déclenchant fetchAll(true) avec debounce 400 ms | /products |
| GET /catalog/movements/ — via djangoClient.movements.list() (lib/django-client.ts:803). Aucun filtre passe ici (le parametre optionnel ?variant= n'est pas utilise par cette page). Retourne TOUT l'historique accessible, ordonne par -timestamp cote modele. Sert a alimenter movements[] | /movements |
| GET /catalog/references/ — via djangoClient.products.list() (lib/django-client.ts:834) qui appelle catalog.references.list() puis mappe chaque reference via mapReferenceToProduct(). Sert a (a) la carte 'Produits sans mouvement' et (b) la sous-ligne marque·categorie du tableau principal | /movements |
| GET /users/me/ — via useCurrentUser() (lib/auth/useCurrentUser.ts). Fournit role, commande_role, magasin_id, etc. => derive isAdmin / isManager | /movements |
| WebSocket /ws/data/?token=<access> — via DataSyncProvider (lib/contexts/DataSyncContext.tsx) monte dans app/(app)/layout.tsx. La page s'y abonne pour les modeles 'stock_movement', 'product_variant' et 'order' et declenche un fetchData(true) silencieux | /movements |
| (indirect) POST /auth/token/refresh/ — le djangoClient rafraichit le JWT automatiquement sur 401 avant de rejouer la requete | /movements |
| GET /users/me/ — via useCurrentUser(), fournit id/email/role/full_name/commande_role... (id sert a distinguer mes messages) | /chats |
| GET /users/chat/users/ — djangoClient.chat.users(); liste des collaborateurs de la meme societe (is_confirmed=True, self exclu, paires livreur/livreur exclues). Appele au montage puis toutes les 20 s en mode silencieux. Renvoie id, full_name, email, role, is_online (calcule serveur: last_seen_at < 4 | /chats |
| GET /users/chat/history/?room_name=general — djangoClient.chat.history({room_name:'general'}); historique du canal general. Le serveur remappe vers la room reelle `general_<company_id>` et ne renvoie QUE les 100 derniers messages (recipient null) | /chats |
| GET /users/chat/history/?recipient_id=<id> — historique de la conversation directe (messages moi->lui ET lui->moi, 100 derniers). 403 'Permission refusee' si pas la meme societe, 403 'Deux livreurs ne peuvent pas se contacter entre eux', 404 'Destinataire introuvable' | /chats |
| GET /catalog/references/ — via djangoClient.products.list() (compat mapReferenceToProduct); alimente le selecteur de produit du bouton '+'. Charge en lazy au premier ouverture du popover puis mis en cache dans le state (allProducts) | /chats |
| WS <ws|wss>://<host de NEXT_PUBLIC_DJANGO_API_URL>/ws/chat/?token=<JWT access>&room=general — canal general (le serveur scope en `general_<company_id>`) | /chats |
| WS <ws|wss>://<host>/ws/chat/?token=<JWT access>&recipient_id=<id> — conversation directe (le serveur calcule la room deterministe `dm_<minId>_<maxId>`) | /chats |
| WS envoi {content:'...'} — nouveau message texte | /chats |
| WS envoi {content:'...', product_id:<id>} — message avec produit (ATTENTION: product_id est IGNORE par le backend, voir notes) | /chats |
| WS envoi {action:'edit', message_id, content} — modification (autorisee seulement pour l'auteur, message non supprime) | /chats |
| WS envoi {action:'delete', message_id} — suppression logique (autorisee seulement pour l'auteur) | /chats |
| WS envoi {action:'read'} — marque comme lus tous les messages non lus qui me sont adresses dans la room (DM uniquement) | /chats |
| WS envoi {action:'ping'} — heartbeat toutes les 20 s; cote serveur cela ne fait que mettre a jour last_seen_at (aucun message cree car content vide) | /chats |
| WS reception {type:'message', ...ChatMessage} (ou objet brut) — nouveau message a ajouter | /chats |
| WS reception {type:'message_edited', id, room_name, content, is_edited, edited_at} | /chats |
| WS reception {type:'message_deleted', id, room_name} | /chats |
| WS reception {type:'message_read', ids:[...], read_at, room_name} | /chats |
| GET /users/me/ — (via useCurrentUser) charge l'utilisateur courant : id, email, role, full_name, is_confirmed, phone, adresse, photo, company_name, logo, shop_name, shop_logo, magasin_id, position, commande_role, is_company_owner. Sert à tout le gating de la page. | /users (libellé sidebar : "Super Admin", |
| GET /users/magasins/users/ — liste des magasins accessibles avec, pour chacun, magasin_id, shop_name, shop_logo, manager (l'admin propriétaire du magasin), employers[] (id, full_name, email, phone, adresse, photo, is_confirmed, position, role, commande_role, last_login_at, last_logout_at) et company | /users (libellé sidebar : "Super Admin", |
| GET /users/pending/ — comptes non confirmés (is_confirmed=False) de la société/du magasin : id, full_name, email, role, created_at, + position et shop_name pour les employers, shop_name pour les magasins. Alimente l'onglet 'En attente'. Appelé avec .catch(() => []) : une erreur renvoie une liste vid | /users (libellé sidebar : "Super Admin", |
| PUT /users/approve/<user_id>/ — passe is_confirmed à True. Backend ApproveUserView : 403 si le rôle courant n'est pas admin/magasin, 403 si la cible n'appartient pas à l'entreprise (admin) ou au magasin (gérant, restreint aux employers), 404 si introuvable. | /users (libellé sidebar : "Super Admin", |
| POST /users/reject/<user_id>/ — REJETTE ET SUPPRIME définitivement le compte (user.delete()). Mêmes contrôles d'appartenance que approve. Backend RejectUserView. | /users (libellé sidebar : "Super Admin", |
| PUT /users/role/<user_id>/ body { role: 'admin' | 'magasin' | 'employer' } — change le rôle. Backend RoleManagementView (permission IsAuthenticated + IsAdmin) : 400 rôle invalide, 400 si on cible son propre compte, 403 si (cible admin OU nouveau rôle admin) et l'appelant n'est pas le fondateur, 403  | /users (libellé sidebar : "Super Admin", |
| DELETE /users/delete/<user_id>/ body { password } — supprime un compte après vérification du mot de passe de l'APPELANT. Backend DeleteUserView : 400 'Mot de passe requis pour confirmer la suppression.', 400 'Mot de passe incorrect.', 400 'Vous ne pouvez pas vous supprimer vous-même', 403 si le géra | /users (libellé sidebar : "Super Admin", |
| POST /users/register/ body { email, username: email, password, role, full_name, + position & admin_email (role employer) ou shop_name & admin_email (role magasin) } — création d'un compte gérant ou employé. admin_email est TOUJOURS l'email de l'utilisateur courant. Backend RegisterSerializer : pour  | /users (libellé sidebar : "Super Admin", |
| POST /users/add-admin/ body { email, username: email, password, role: 'admin', full_name } — crée un co-administrateur, réponse { message, id }. Backend AddAdminView (permission IsAuthenticated + IsCompanyOwner) : supprime l'AdminProfile créé par le serializer (le co-admin n'est pas une nouvelle soc | /users (libellé sidebar : "Super Admin", |
| GET /users/password-reset-requests/?status=<pending|approved|rejected> (paramètre omis quand le filtre vaut 'all') — demandes de réinitialisation adressées à l'admin courant : id, status, user_name, user_email, user_role, magasin_name, created_at, resolved_at. Backend EmployeePasswordResetListView ( | /users (libellé sidebar : "Super Admin", |
| PATCH /users/password-reset-requests/<request_id>/ body { action: 'approve' | 'reject' } — résout une demande. Backend EmployeePasswordResetResolveView : 404 'Demande introuvable', 400 'Action invalide.', 400 'Cette demande a déjà été traitée.' si status !== 'pending' ; positionne status, resolved_b | /users (libellé sidebar : "Super Admin", |
| POST /users/refresh/ — rafraîchissement transparent du token JWT sur toute réponse 401 (implémenté dans django-client, rejoue la requête une fois ; si le refresh échoue, lève Error('Authentication failed') ou le detail renvoyé). | /users (libellé sidebar : "Super Admin", |
| Base URL : process.env.NEXT_PUBLIC_DJANGO_API_URL, défaut 'http://127.0.0.1:8010/api'. Auth par header Authorization: Bearer <access>. | /users (libellé sidebar : "Super Admin", |
| GET /users/me/ (via useCurrentUser) — role, magasin_id, commande_role, shop_name/logo; base du gating | /caisse |
| GET /users/magasins/users/ (djangoClient.get) — seulement si isAdmin; alimente la barre de selection de magasin (champs utilises: magasin_id, shop_name, shop_logo). Erreur -> toast 'Erreur de chargement des magasins: ' + message | /caisse |
| GET /users/caisse/sessions/current/?magasin_id={id} (djangoClient.caisse.current) — session ouverte du magasin; le backend renvoie 204 No Content s'il n'y en a pas, normalise en null cote client | /caisse |
| GET /users/caisse/sessions/?magasin_id={id} (djangoClient.caisse.listSessions) — toutes les sessions du magasin (ordering -opened_at), filtrees cote client sur status==='closed' pour l'historique | /caisse |
| GET /users/caisse/summary/?magasin_id&date_from&date_to (djangoClient.caisse.summary) — { date_from, date_to, total_entrees, total_sorties, solde, sorties_par_categorie[{categorie,total}], ca_produits_vendus, cout_produits_vendus, benefice_produits_vendus } | /caisse |
| GET /users/caisse/movements/?magasin_id&date_from&date_to (djangoClient.caisse.listMovements) — mouvements de la periode toutes sessions confondues | /caisse |
| GET /users/caisse/categories/ (djangoClient.caisse.categories.list) — [{id, nom, created_at}] pour le select 'Categorie' des sorties; appele une seule fois au montage, hors magasin | /caisse |
| GET /users/magasins/stats/ (djangoClient.get) — appele a l'ouverture des dialogs Ouvrir/Fermer pour pre-remplir le montant: on cherche l'entree dont magasin_id === magasinId et on prend total_stock_value. Echec -> return null (silencieux, champ laisse vide) | /caisse |
| POST /users/caisse/sessions/open/ {magasin_id, opening_balance, opening_note?, opened_at?} — ouvre la session | /caisse |
| POST /users/caisse/sessions/{sessionId}/close/ {closing_balance, closing_note?, closed_at?} — ferme la session, le backend calcule expected_balance et difference | /caisse |
| POST /users/caisse/movements/ {session, movement_type, amount, reason, category?} — ajoute un mouvement | /caisse |
| (non utilise ici mais present dans le client: DELETE /users/caisse/movements/{id}/) | /caisse |
| GET /users/me/ (useCurrentUser) — determine isLivreur (role employer + commande_role LIVREUR) | /bilan |
| GET /orders/?historique=1&date_from={ISO}&date_to={ISO} (djangoClient.orders.list) — historique personnel du livreur borne a la journee. Les bornes viennent de appDayBounds() (lib/timezone.ts): start = `${jour}T00:00:00.000+03:00`.toISOString(), end = `${jour}T23:59:59.999+03:00`.toISOString(), le j | /bilan |
| Aucun autre appel: pas de mutation, pas de changement de statut depuis cette page (lecture seule) | /bilan |
| GET /users/dashboard/ (djangoClient.get) — renvoie { role, kpis, lists }. kpis lues: ca, benefice_estime_stock, total_stock_value | stock_value, total_employers | total_magasins, low_stock_count, my_sales_today | sales_today, total_amount_sold | total_revenue, total_revenue (ventes livrées), clients | /dashboard |
| GET /catalog/references/ (via djangoClient.products.list() -> catalog.references.list()) — sert à calculer totalProducts, totalQuantity, categoryMap, et la liste des produits en alerte (rupture/faible). Chaque référence est aplatie par mapReferenceToProduct: initial_quantity = somme des stock_actuel | /dashboard |
| GET /users/me/ (via useCurrentUser) — rôle, store_name/store_logo, commande_role | /dashboard |
| WS /ws/data/?token=... (DataSyncProvider) — événements {model, action, id, magasin_id} déclenchant le refetch silencieux | /dashboard |
| GET /orders/ (via djangoClient.sales.list()) — la « vente » est dérivée des commandes: seules les commandes `statut_courant === 'LIVRE'` sont retenues, puis APLATIES ligne d'article par ligne d'article. Chaque ligne: id `{orderId}-{itemId}`, product_name = reference_name (+ ` (couleur)` si couleur ! | /reports |
| GET /catalog/references/ (via djangoClient.products.list()) — stock total, comptage alertes, listes ruptures/stock bas/produits sans mouvement pour l'IA | /reports |
| GET /catalog/movements/ (via djangoClient.movements.list()) — mouvements de stock; le client mappe movement_type sur le LIBELLÉ D'ORIGINE (Préparation de commande / Retour de commande / Annulation de commande / Commande livrée / Réception fournisseur / Ajustement manuel), created_at = timestamp. Rép | /reports |
| GET /users/dashboard/ — enveloppé dans `.catch(() => ({}))`: en cas d'échec, dashboardKpis = {} sans aucune erreur visible. Ses kpis (ca, total_profit, total_stock_value | stock_value, benefice_estime_stock) alimentent UNIQUEMENT le payload de l'analyse IA (pas les cartes KPI de la page) | /reports |
| POST /api/ai/analyze (route Next.js locale, app/api/ai/analyze/route.ts) — proxy vers Ollama `POST {OLLAMA_BASE_URL}/api/generate` (modèle par défaut qwen3:4b, stream:false, think:false, timeout 600 000 ms). Réponse { analysis }; les balises <think>...</think> sont supprimées. En erreur: HTTP 500 +  | /reports |
| GET /users/me/ (useCurrentUser) pour isAdmin | /reports |
| WS /ws/data/ pour le rafraîchissement temps réel | /reports |
| Les 4 GET initiaux partent en parallèle via Promise.all | /reports |
| GET /users/me/ — chargé par useCurrentUser au montage ; fournit id, email, role, full_name, phone, adresse, photo, company_name, logo, shop_name, shop_logo, magasin_id, position, commande_role, is_company_owner | /settings |
| PATCH /users/me/ (JSON, via djangoClient.users.updateProfile) — met à jour full_name, phone, adresse. Backend: 403 si role hors [admin, magasin] | /settings |
| PATCH /users/me/ (multipart FormData, via djangoClient.patchFormData) — upload du champ `photo` (avatar) quand un fichier a été sélectionné | /settings |
| PATCH /users/me/ (multipart FormData) — modal entreprise/magasin : envoie `company_name` (+ `logo`) si role=admin, ou `shop_name` (+ `shop_logo`) si role=magasin | /settings |
| POST /users/change-password/ — body {old_password, new_password}. Backend valide : champs requis (400 'Champs requis manquants'), ancien mot de passe correct (400 'Mot de passe actuel incorrect'), longueur >= 6 (400), et role in [admin, magasin] (403) | /settings |
| GET /users/caisse/categories/ — liste des catégories de dépense (djangoClient.caisse.categories.list), appelée seulement si isGerant | /settings |
| POST /users/caisse/categories/ — body {nom} | /settings |
| PATCH /users/caisse/categories/{id}/ — body {nom} | /settings |
| DELETE /users/caisse/categories/{id}/ | /settings |
| GET /orders/delivery-zones/ — liste des zones (djangoClient.zones.list), appelée seulement si isGerant. Retourne {id, code, nom, prix, actif} | /settings |
| POST /orders/delivery-zones/ — body {nom, prix} | /settings |
| PATCH /orders/delivery-zones/{id}/ — body partiel {nom?, prix?, actif?} | /settings |
| DELETE /orders/delivery-zones/{id}/ — côté serveur : si la zone est déjà utilisée par une commande (Order.livraison_zone == zone.code) elle n'est PAS supprimée, elle est passée à actif=False et l'API renvoie l'objet zone (200) au lieu d'un 204 | /settings |
| GET /users/magasins/users/ — liste principale. Retourne pour chaque magasin : {magasin_id, shop_name, shop_logo (URL absolue), manager: {id, full_name, email, phone, adresse, photo, is_confirmed, role, last_login_at, last_logout_at} | null, employers: [{id, full_name, email, phone, adresse, photo, i | /stores |
| GET /users/magasins/stats/ — statistiques par magasin : {magasin_id, shop_name, total_products, total_stock_quantity, total_stock_value, total_sold_value, profit}. Appel enveloppé dans un try/catch : en cas d'échec -> console.error seulement, stats par défaut à 0, AUCUN toast. | /stores |
| GET /users/magasins/overview/ (via djangoClient.transfers.getProfitByMagasins(), qui remappe `res.magasins` en `profit_by_magasins`) — APPELÉ SEULEMENT SI isAdmin. Retourne par magasin : {magasin_id, shop_name, total_stock_value, total_profit, number_of_products, number_of_sales_week, number_of_empl | /stores |
| POST /users/register/ (djangoClient.auth.register) — création du compte gérant du nouveau magasin : body {email, username (= email), password, role: 'magasin', full_name, shop_name, admin_email: user?.email}. Le backend crée le CustomUser + le MagasinProfile (user=gérant, admin=admin correspondant à | /stores |
| PUT /users/approve/{id}/ (djangoClient.auth.approveUser) — appelé immédiatement après le register si `response?.id`, pour confirmer le compte gérant (is_confirmed=true) | /stores |
| PATCH /users/magasins/{magasin_id}/ (multipart FormData via patchFormData) — édition du magasin : shop_name (+ shop_logo si un fichier est choisi). Backend MagasinViewSet.partial_update ignore un shop_logo de type string (seul un vrai fichier est accepté). | /stores |
| POST /users/transfer/products/ (djangoClient.transfers.transfer) — via le dialog de transfert : body {source_magasin_id, destination_magasin_id, items: [{variant_id, quantity}]} | /stores |
| GET catalogue références (djangoClient.products.list({magasin_id})) — à l'intérieur du panneau de transfert, pour lister les produits du magasin source ; filtrage client supplémentaire `Number(p.magasin) === Number(magasinId)` | /stores |
| GET /api/suppliers/orders/ (djangoClient.suppliers.list(), appele sans magasinId donc sans query param) — liste des commandes fournisseur de tous les magasins accessibles ; retourne id, magasin, numero, date, description, statut, prix_fournisseur, fret_import, douane, total_qty, cout_total, cout_uni | /suppliers |
| POST /api/suppliers/orders/ (djangoClient.suppliers.create()) — cree une commande + ses lignes puis recalcule les couts ; body {description, prix_fournisseur, fret_import, douane, lines:[{product_variant, quantite}]} | /suppliers |
| POST /api/suppliers/orders/<id>/receive/ (djangoClient.suppliers.receive()) — receptionne: cree un StockMovement ENTREE/origine FOURNISSEUR par ligne, passe statut a 'RECU', horodate received_at, cree une Notification 'supplier_order' | /suppliers |
| GET /api/catalog/brands/ (djangoClient.catalog.brands.list()) — alimente le Select 'Marque' du dialog de creation | /suppliers |
| GET /api/catalog/categories/ (djangoClient.catalog.categories.list()) — alimente le Select 'Catégorie' | /suppliers |
| GET /api/catalog/references/?brand=<id>&category=<id> (djangoClient.catalog.references.list()) — alimente la liste des variantes (Select 'Couleur'), avec variants[] imbriquees (id, couleur, stock_actuel, seuil_alerte…) | /suppliers |
| WebSocket (DataSyncProvider) — evenements {model:'supplier_order', action, id, magasin_id} declenchant le refetch silencieux | /suppliers |
| GET /api/users/refresh/ implicite: le client rafraichit automatiquement le JWT sur 401 et redirige vers /login si le refresh echoue | /suppliers |
| GET /api/users/magasins/users/ (djangoClient.get('/users/magasins/users/')) — retourne un tableau d'objets {magasin_id, shop_name, shop_logo (URL absolue ou null), manager {…}, employers [...], company_users [...]} ; seules magasin_id / shop_name / shop_logo sont utilisees ici (type TransferStore).  | /transfers |
| (via le panel) GET /api/catalog/references/ — liste des produits du magasin source | /transfers |
| (via le panel) POST /api/users/transfer/products/ — execution du transfert | /transfers |
| GET /api/catalog/references/ via djangoClient.products.list({ magasin_id }) — ATTENTION: products.list appelle catalog.references.list() SANS query param, recupere TOUTES les references accessibles, puis filtre CLIENT sur Number(r.magasin) === Number(magasinId); le panel refiltre une 2e fois cote cl | /transfers (composant partage TransferPr |
| POST /api/users/transfer/products/ via djangoClient.transfers.transfer(sourceId, destId, items) — body {source_magasin_id, destination_magasin_id, items:[{variant_id, quantity}]}. Backend TransferProductsView: transaction atomique, verifie l'appartenance de chaque variante au magasin source, refuse  | /transfers (composant partage TransferPr |
| Aucun appel direct — tous les appels passent par TransferProductsPanel (GET /api/catalog/references/, POST /api/users/transfer/products/). | /stores (modal TransferProductsDialog —  |
| GET /catalog/references/ — via djangoClient.products.list() (appelee SANS filtre). Renvoie toutes les ProductReference visibles par l'utilisateur; chaque ref est ensuite transformee cote client par mapReferenceToProduct(). | /alerts |
| GET /users/me/ — indirectement, uniquement via la Sidebar/TopBar du layout (pas par la page elle-meme). | /alerts |
| GET /orders/?statut=PRETE&livraison_zone=RECUPERATION — via djangoClient.orders.list({ statut:'PRETE', livraison_zone:'RECUPERATION' }). Sert a peupler la file de retrait. Reponse serialisee par OrderGerantSerializer (numero, client_nom, telephone, total_a_payer, items[{reference_name, couleur, quan | /pickup |
| POST /orders/{id}/status/ body { statut:'LIVRE', note:undefined } — via djangoClient.orders.changeStatus(order.id, 'LIVRE'). Confirme la recuperation au comptoir. | /pickup |
| GET /users/me/ — via useCurrentUser, pour resoudre isGerant. | /pickup |
| GET /catalog/references/ — via djangoClient.products.search(q). ATTENTION : le client recupere la LISTE COMPLETE des references a chaque recherche puis filtre en JavaScript (r.reference_name.toLowerCase().includes(q) || (r.brand_name||'').toLowerCase().includes(q)). Il existe pourtant un endpoint de | /scanner |
| GET /users/magasins/users/ — via djangoClient.get('/users/magasins/users/'). Renvoie un tableau d'objets { magasin_id, shop_name, shop_logo, manager:{id, full_name, email, phone, adresse, photo, is_confirmed, role, last_login_at, last_logout_at}|null, employers:[{id, full_name, email, phone, adresse | /superadmin |
| PUT /users/role/{userId}/ body { role: 'admin'|'magasin'|'employer' } — change le role d'un utilisateur. Refus backend possibles : role invalide (400), utilisateur introuvable (404), 'Vous ne pouvez pas modifier votre propre role' (400), 'Seul le fondateur de la societe peut gerer les administrateur | /superadmin |
| DELETE /users/delete/{userId}/ body { password } — supprime definitivement un compte. Refus backend : 'Mot de passe requis pour confirmer la suppression.' (400), 'Mot de passe incorrect.' (400), 'Vous ne pouvez pas vous supprimer vous-meme' (400), 'Utilisateur introuvable' (404), 'Seul le fondateur  | /superadmin |
| GET /users/me/ — via useCurrentUser, pour resoudre isSuperAdmin. | /superadmin |
| GET /api/users/notifications/ — djangoClient.notifications.list() — charge l'historique complet visible par l'utilisateur (filtre par role cote backend). Reponse : tableau de NotificationSerializer ou objet {results:[...]} | /notifications |
| PATCH /api/users/notifications/{id}/ body {is_read: boolean} — djangoClient.notifications.markRead(id, !is_read) — bascule lu/non-lu d'une notification. Le backend (partial_update) ne modifie QUE is_read et renvoie l'objet serialise | /notifications |
| POST /api/users/notifications/mark-all-read/ — djangoClient.notifications.markAllRead() — marque lues TOUTES les notifications du queryset visible. Reponse {message:'Toutes les notifications marquees comme lues.'} | /notifications |
| POST /api/users/notifications/delete-all/ — djangoClient.notifications.deleteAll() — supprime en base TOUTES les notifications du queryset visible. Reponse 204 No Content | /notifications |
| DELETE /api/users/notifications/{id}/ — djangoClient.notifications.delete(id) — supprime une notification. Le backend applique une regle de permission specifique (voir notes) et peut repondre 403 {'error':'Permission refusee'} | /notifications |
| WS ws(s)://{host}/ws/notifications/?token={access_token} — push temps reel des nouvelles notifications (voir sharedComponents useNotificationsWebSocket). Host derive de NEXT_PUBLIC_DJANGO_API_URL (defaut http://localhost:8010/api) : protocole retire puis split('/')[0]. wss si la page est en https | /notifications |
| POST /api/users/refresh/ body {refresh} — appele automatiquement par djangoClient sur toute reponse 401, puis la requete est rejouee une fois | /notifications |
| GET /api/users/me/ — pas appele par la page mais par useCurrentUser dans Sidebar et TopBar qui l'entourent (fournit role + commande_role) | /notifications |
| NON UTILISES par cette page mais disponibles dans le client : POST /api/users/notifications/bulk-read/ {ids:[]} et POST /api/users/notifications/bulk-delete/ {ids:[]} | /notifications |
| GET /api/users/notifications/ — chargement initial de la liste (puis filtrage local des ids 'dismissed') | (global) TopBar — cloche de notification |
| PATCH /api/users/notifications/{id}/ {is_read:true} — markAsRead(id) : marque UNE notification lue (jamais de retour a non-lu ici, contrairement a la page) | (global) TopBar — cloche de notification |
| POST /api/users/notifications/mark-all-read/ — markAllAsRead() : marque tout lu cote serveur puis mise a jour optimiste locale (map is_read:true), SANS refetch | (global) TopBar — cloche de notification |
| WS ws(s)://{host}/ws/notifications/?token={access} — reception temps reel + emission du toast global (showToast:true) | (global) TopBar — cloche de notification |
| AUCUN appel de suppression : 'Tout effacer' n'appelle ni delete ni delete-all, il ecrit uniquement dans localStorage | (global) TopBar — cloche de notification |
| POST /users/login/ — body {email, password}. Retourne {access, refresh}. Les tokens sont IMMEDIATEMENT persistes dans localStorage sous la cle 'django_tokens' ({access, refresh}) par djangoClient.saveTokensToStorage AVANT toute autre verification | /login |
| GET /users/me/ — appele automatiquement dans la foulee par djangoClient.auth.login() pour construire l'objet `user` retourne au formulaire (mapping role: admin->admin, magasin->store_manager, employer->employee ; ajoute raw_role, is_approved = is_confirmed, is_confirmed, company_name, shop_name, mag | /login |
| POST /users/refresh/ — body {refresh} : rafraichissement automatique du token sur toute reponse 401 (djangoClient.request). Si le refresh echoue : localStorage vide + `window.location.href = '/login'` (redirection dure, hors router Next) | /login |
| POST /users/register/ — body {email, username (ou email.split('@')[0] si vide), password, role: 'admin'|'magasin'|'employer', full_name, company_name?, shop_name?, admin_email?, position?}. Note : le client fait `full_name: extraData?.full_name || username` PUIS spread `...extraData` — les champs no | /register |
| POST /users/public/forgot-password/ — body {email}. Cree un EmployeePasswordResetRequest(status='pending') rattache a l'admin de la societe. Reponse 201 {queue:'admin', message:'Votre demande a ete transmise a votre administrateur pour validation.'}. Erreurs : 400 'Email requis.' ; 404 'Aucun compte | /forgot-password |
| GET /users/public/forgot-password/status/?email=<urlencoded> — reponse {status: 'none'|'pending'|'approved'|'rejected'}. Retourne 'none' si l'email est inconnu, si le compte est admin, ou si aucune demande non consommee n'existe. Prend la demande NON CONSOMMEE la plus recente (consumed_at is null, o | /forgot-password |
| POST /users/public/forgot-password/confirm/ — body {email, new_password}. Reponse {message:'Mot de passe mis a jour avec succes.'}. Erreurs : 400 'Le mot de passe doit contenir au moins 6 caracteres.' ; 404 'Aucun compte avec cet email.' ; 400 'Aucune demande approuvee trouvee pour cet email.' — mar | /forgot-password |
| COTE ADMIN (hors perimetre de cette page mais indispensable au flux) : GET /users/password-reset-requests/?status=<filtre> (liste) et PATCH /users/password-reset-requests/<id>/ body {action:'approve'|'reject'} (resolution) | /forgot-password |
| POST /users/change-password/ — appel direct `djangoClient.post(...)` (pas via l'objet auth), body {old_password, new_password}. Reponse succes {message:'Mot de passe change avec succes'}. Erreurs backend : 403 {'error':'Seul le gerant peut modifier ces informations. Contactez votre gerant.'} ; 400 { | /reset-password |
| POST /users/logout-event/ — enregistre l'horodatage de deconnexion sur le dernier LoginEvent de l'utilisateur (best-effort ; l'echec est seulement `console.warn`, il n'interrompt pas la deconnexion). Reponse {message:'Deconnexion enregistree'} | /logout |
| POST /users/refresh/ — body {refresh} : appel supplementaire effectue pendant le logout (recupere le refresh depuis this.tokens ou directement depuis localStorage['django_tokens']), echec ignore (console.warn). Ce token n'est pas blackliste cote serveur — appel sans effet utile | /logout |
| WebSocket ws(s)://<host de NEXT_PUBLIC_DJANGO_API_URL>/ws/data/?token=<access> — flux de synchronisation temps reel (via DataSyncProvider) | /(app)/* — shell applicatif protege (cou |
| GET /users/me/ — declenche indirectement par useCurrentUser dans Sidebar et TopBar (deux appels distincts, un par composant, pas de cache partage) | /(app)/* — shell applicatif protege (cou |
| GET /users/me/ — via useCurrentUser, alimente user.store_logo, user.store_name, role et commande_role qui pilotent tout le filtrage du menu | /(app)/* — Sidebar de navigation (rendue |
| POST /users/logout-event/ — enregistre l'evenement de deconnexion cote serveur (echec avale avec console.warn, n'empeche pas la deconnexion) | /(app)/* — Sidebar de navigation (rendue |
| POST /users/refresh/ — appel fetch brut avec le refresh token pendant le logout (echec avale avec console.warn) | /(app)/* — Sidebar de navigation (rendue |
| Effet de bord du logout : localStorage.clear() (efface TOUT le localStorage, y compris 'django_tokens' et 'stockv2_dismissed_notification_ids') puis this.tokens = null | /(app)/* — Sidebar de navigation (rendue |
| GET /users/me/ — via useCurrentUser (2e appel independant de celui de la Sidebar) | /(app)/* — TopBar (barre superieure, ren |
| POST /users/logout-event/ puis POST /users/refresh/ + localStorage.clear() — via djangoClient.auth.logout() | /(app)/* — TopBar (barre superieure, ren |
| GET /users/notifications/ — via le composant Notifications au montage | /(app)/* — TopBar (barre superieure, ren |
| PATCH /users/notifications/{id}/ {is_read:true} — marquer une notification lue | /(app)/* — TopBar (barre superieure, ren |
| POST /users/notifications/mark-all-read/ — tout marquer lu | /(app)/* — TopBar (barre superieure, ren, djangoClient.notifications — Notificatio |
| WebSocket ws(s)://<host>/ws/notifications/?token=<access> — reception temps reel des notifications | /(app)/* — TopBar (barre superieure, ren |
| AUCUN appel réseau. Le composant ne fait aucun fetch : il valide, lit le fichier en base64 via FileReader.readAsDataURL et remonte le File brut au parent via onImageSelect(file). L'upload réel est à la charge de l'appelant (cf. lib/image-service.ts). | (composant partagé) <ImageUpload /> — zo |
| AUCUN appel réseau. Le composant est purement présentationnel : toute persistance (suppression, changement d'image principale) est déléguée au parent via les callbacks onDelete / onSetPrimary. | (composant partagé) <ProductImageGallery |
| Aucun appel direct : le composant ne connaît que la promesse onConfirm. | (composant partagé) <ConfirmDeleteDialog |
| Via /superadmin : `djangoClient.delete('/users/delete/{id}/', { password })` -> DELETE /users/delete/<id>/ avec le mot de passe dans le corps, puis toast.success('Utilisateur supprimé') et refetch de la liste. | (composant partagé) <ConfirmDeleteDialog |
| Via /users : `djangoClient.users.delete(id, password)` -> même endpoint DELETE /users/delete/<id>/ avec body { password }. | (composant partagé) <ConfirmDeleteDialog |
| POST /api/ai/analyze — headers { 'Content-Type': 'application/json' }, body = JSON.stringify(data) tel quel. Lit `result.analysis` de la réponse. Si !res.ok -> setError(true) MAIS le texte de `result.analysis` est quand même affiché (la route renvoie son message d'erreur dans ce même champ avec un s | (composant partagé) <AIAnalysis /> — car |
| (Contexte /reports, alimentant `data`) GET /sales/ via djangoClient.sales.list() | (composant partagé) <AIAnalysis /> — car |
| (Contexte /reports) GET produits via djangoClient.products.list() | (composant partagé) <AIAnalysis /> — car |
| (Contexte /reports) GET mouvements via djangoClient.movements.list() | (composant partagé) <AIAnalysis /> — car |
| (Contexte /reports) GET /users/dashboard/ via djangoClient.get('/users/dashboard/') — seule source des chiffres coût d'achat (ca, total_profit, total_stock_value/stock_value, benefice_estime_stock) | (composant partagé) <AIAnalysis /> — car |
| ENTRÉE — POST /api/ai/analyze, body JSON de type AnalyzePayload { periode?, ca?, beneficeNet?, valeurStock?, beneficeEstimeStock?, ventesImpayeesCount?, topProduits?, produitsSansMouvement?, rupturesStock?, stockBas?, repartitionMouvements?, topVendeurs?, topMagasins? } | POST /api/ai/analyze — route API Next.js |
| SORTIE 200 — Response.json({ analysis: string }) | POST /api/ai/analyze — route API Next.js |
| SORTIE 500 — Response.json({ analysis: "Erreur lors de la génération de l'analyse. <hint>" }, { status: 500 }) — l'erreur est TOUJOURS transportée dans le même champ `analysis` que le succès | POST /api/ai/analyze — route API Next.js |
| APPEL SORTANT — POST {OLLAMA_BASE_URL}/api/generate, headers { 'Content-Type': 'application/json' }, body { model: OLLAMA_MODEL, prompt, stream: false, think: false }, signal AbortSignal.timeout(600000) | POST /api/ai/analyze — route API Next.js |
| Si la réponse Ollama n'est pas ok : lecture du corps en texte (catch -> ''), throw `Ollama a répondu {status} : {detail.slice(0,300)}` (détail tronqué à 300 caractères) | POST /api/ai/analyze — route API Next.js |
| Lecture de la réponse Ollama : result.response ?? '' (chaîne vide si le champ manque) | POST /api/ai/analyze — route API Next.js |
| ENTRÉE — POST /api/ai/check-duplicates, body { newNames: string[], existingNames: string[] } | POST /api/ai/check-duplicates — route AP |
| SORTIE NOMINALE — { warnings: { nouvelle: string; ressemble_a: string; raison: string }[] } (statut 200) | POST /api/ai/check-duplicates — route AP |
| SORTIE EN CAS D'ERREUR — { warnings: [], error: <message> } avec statut **200** (et non 500) : la revue IA ne doit JAMAIS faire échouer l'import déjà écrit en base | POST /api/ai/check-duplicates — route AP |
| APPEL SORTANT — POST {OLLAMA_BASE_URL}/api/generate avec { model, prompt, stream:false, think:false } et timeout 600 s ; si !response.ok -> throw `Ollama a répondu {status} : {detail.slice(0,300)}` | POST /api/ai/check-duplicates — route AP |
| CONSOMMATEUR — /products : après djangoClient d'import Excel, si res.new_reference_names.length > 0, fetch('/api/ai/check-duplicates') avec { newNames: res.new_reference_names, existingNames: references.map(r => `${r.brand_name} ${r.reference_name}`) } | POST /api/ai/check-duplicates — route AP |
| CONSOMMATEUR — le résultat met à jour l'état importReview seulement si prev.batchId === res.batch_id (garde anti-course entre deux imports successifs) | POST /api/ai/check-duplicates — route AP |
| CONSOMMATEUR — POST /catalog/import-batches/{batchId}/cancel/ via djangoClient.catalog.importBatches.cancel(batchId), déclenché uniquement par le bouton « Annuler l'import » du dialog de revue | POST /api/ai/check-duplicates — route AP |
| POST /api/upload — multipart/form-data avec champs `image` (fichier) et `product_id` (string). PIÈGE MAJEUR : cette route N'EXISTE PAS dans le repo (app/api/ ne contient que ai/analyze et ai/check-duplicates) -> tout appel à uploadImageToBackend renverra un 404 Next.js. | (module partagé) lib/image-service.ts —  |
| DELETE /api/upload?path={imagePath} — idem, route inexistante côté frontend. | (module partagé) lib/image-service.ts —  |
| Aucun appel à djangoClient : ce module ignore complètement le client Django authentifié (donc aucun header Authorization/JWT ne serait envoyé). | (module partagé) lib/image-service.ts —  |
| Aucun appel réseau : génération 100 % locale (côté navigateur/serveur selon l'endroit d'appel), sortie en data URL base64 PNG. | (module partagé) lib/qrcode-generator.ts |
| GET /orders/delivery-zones/ — via djangoClient.zones.list(). Renvoie { id, code, nom, prix, actif }[] | (hook partagé) lib/hooks/useDeliveryZone |
| POST /orders/delivery-zones/ — djangoClient.zones.create({ nom, prix }) — utilisé dans /settings (création d'une zone) | (hook partagé) lib/hooks/useDeliveryZone |
| PATCH /orders/delivery-zones/{id}/ — djangoClient.zones.update(id, { nom?, prix?, actif? }) — utilisé dans /settings pour renommer/retarifer ET pour basculer actif/inactif ({ actif: !z.actif }) | (hook partagé) lib/hooks/useDeliveryZone |
| DELETE /orders/delivery-zones/{id}/ — djangoClient.zones.delete(id) — RÈGLE MÉTIER : une zone déjà utilisée par des commandes n'est PAS réellement supprimée côté serveur, elle est DÉSACTIVÉE (soft delete, voir DeliveryZoneOptionViewSet.destroy) | (hook partagé) lib/hooks/useDeliveryZone |
| Aucun appel réseau : le hook est purement local. Chez tous les consommateurs actuels le filtrage est fait CÔTÉ CLIENT sur des données déjà chargées (le hook ne déclenche pas de requête serveur). | (hook partagé) lib/hooks/useDebouncedVal |
| POST /users/refresh/ — renouvellement du token d'acces (appele automatiquement sur 401, et une seconde fois volontairement pendant le logout) | (couche transport) DjangoAPIClient — coe |
| POST /users/register/ — creation de compte (role traduit magasin/employer) | djangoClient.auth — authentification, in |
| POST /users/login/ — obtention {access, refresh} | djangoClient.auth — authentification, in |
| POST /users/logout-event/ — journalisation de la deconnexion (best effort) | djangoClient.auth — authentification, in |
| GET /users/me/ — profil de l'utilisateur connecte | djangoClient.auth — authentification, in |
| PUT /users/approve/{userId}/ — approuver un compte en attente | djangoClient.auth — authentification, in |
| POST /users/reject/{userId}/ — rejeter un compte en attente | djangoClient.auth — authentification, in |
| GET /users/pending/ — comptes en attente de validation | djangoClient.auth — authentification, in |
| POST /users/public/forgot-password/ — demande de reinitialisation (public, sans token) | djangoClient.auth — authentification, in |
| GET /users/public/forgot-password/status/?email= — etat de la demande (none/pending/approved/rejected) | djangoClient.auth — authentification, in |
| POST /users/public/forgot-password/confirm/ — definition du nouveau mot de passe apres approbation | djangoClient.auth — authentification, in |
| GET /users/password-reset-requests/?status= — liste des demandes | djangoClient.passwordResetRequests — mod |
| PATCH /users/password-reset-requests/{requestId}/ — {action: 'approve'|'reject'} | djangoClient.passwordResetRequests — mod |
| GET /catalog/categories/?magasin_id= — liste des categories | djangoClient.catalog.categories — Catego |
| POST /catalog/categories/ — creation | djangoClient.catalog.categories — Catego |
| PATCH /catalog/categories/{id}/ — modification partielle | djangoClient.catalog.categories — Catego |
| DELETE /catalog/categories/{id}/ — suppression | djangoClient.catalog.categories — Catego |
| GET /catalog/types/?category= — liste des sous-types | djangoClient.catalog.types — Sous-types  |
| POST /catalog/types/ — creation | djangoClient.catalog.types — Sous-types  |
| PATCH /catalog/types/{id}/ — modification | djangoClient.catalog.types — Sous-types  |
| DELETE /catalog/types/{id}/ — suppression | djangoClient.catalog.types — Sous-types  |
| GET /catalog/brands/?magasin_id= — liste des marques | djangoClient.catalog.brands — Marques |
| POST /catalog/brands/ — creation | djangoClient.catalog.brands — Marques |
| PATCH /catalog/brands/{id}/ — renommage | djangoClient.catalog.brands — Marques |
| DELETE /catalog/brands/{id}/ — suppression | djangoClient.catalog.brands — Marques |
| GET /catalog/colors/?magasin_id= — liste des couleurs | djangoClient.catalog.colors — Couleurs ( |
| POST /catalog/colors/ — creation | djangoClient.catalog.colors — Couleurs ( |
| PATCH /catalog/colors/{id}/ — renommage | djangoClient.catalog.colors — Couleurs ( |
| DELETE /catalog/colors/{id}/ — suppression | djangoClient.catalog.colors — Couleurs ( |
| GET /catalog/references/?type=&brand=&category= — liste filtree | djangoClient.catalog.references — Refere |
| GET /catalog/references/autocomplete/?q=&type=&brand=&category= — suggestions pour les formulaires de commande | djangoClient.catalog.references — Refere |
| GET /catalog/references/{id}/ — detail | djangoClient.catalog.references — Refere |
| POST /catalog/references/ — creation | djangoClient.catalog.references — Refere |
| PUT /catalog/references/{id}/ — remplacement complet | djangoClient.catalog.references — Refere |
| DELETE /catalog/references/{id}/ — suppression | djangoClient.catalog.references — Refere |
| POST /catalog/references/bulk-update-price/ — {type_id, prix_achat?, prix_vente?} -> {updated} | djangoClient.catalog.references — Refere |
| GET /catalog/references/export-excel/ — telechargement du catalogue (blob) | djangoClient.catalog.references — Refere |
| POST /catalog/references/import-excel/ — import multipart, reponse fichier + en-tetes X-Import-* | djangoClient.catalog.references — Refere |
| POST /catalog/import-batches/{batchId}/cancel/ — annulation transactionnelle du lot d'import | djangoClient.catalog.importBatches — Ann |
| GET /catalog/variants/?reference= — variantes d'une reference | djangoClient.catalog.variants — Variante |
| POST /catalog/variants/ — creation d'une variante | djangoClient.catalog.variants — Variante |
| DELETE /catalog/variants/{id}/ — suppression | djangoClient.catalog.variants — Variante |
| POST /catalog/variants/{id}/adjust/ — ajustement manuel de stock (ENTREE/SORTIE) | djangoClient.catalog.variants — Variante |
| GET /orders/?statut=&date_debut=&date_fin=&magasin_id=&livraison_zone=&historique=1&date_from=&date_to=&preparateur_id= — liste filtree | djangoClient.orders — Module Commandes ( |
| GET /orders/{id}/ — detail | djangoClient.orders — Module Commandes ( |
| POST /orders/ — creation | djangoClient.orders — Module Commandes ( |
| POST /orders/{id}/status/ — changement de statut (JSON, ou multipart si photo) | djangoClient.orders — Module Commandes ( |
| POST /orders/{id}/cancel/ — annulation avec note | djangoClient.orders — Module Commandes ( |
| POST /orders/{id}/assign-livreur/ — pre-assignation livreur sans changement de statut | djangoClient.orders — Module Commandes ( |
| POST /orders/{id}/assign-preparateur/ — pre-assignation preparateur sans changement de statut | djangoClient.orders — Module Commandes ( |
| GET /orders/available-staff/?role=&magasin_id=&date_commande= — personnel disponible avec drapeau `available` | djangoClient.orders — Module Commandes ( |
| PATCH /orders/{id}/ — modification (uniquement statut NOUVELLE) | djangoClient.orders — Module Commandes ( |
| DELETE /orders/{id}/ — suppression | djangoClient.orders — Module Commandes ( |
| GET /orders/dashboard/?date_from=&date_to=&magasin_id= — indicateurs du module | djangoClient.orders — Module Commandes ( |
| GET /orders/delivery-zones/ — liste des zones | djangoClient.zones — Zones de livraison  |
| POST /orders/delivery-zones/ — creation | djangoClient.zones — Zones de livraison  |
| PATCH /orders/delivery-zones/{id}/ — modification (nom, prix, actif) | djangoClient.zones — Zones de livraison  |
| DELETE /orders/delivery-zones/{id}/ — suppression ou desactivation implicite | djangoClient.zones — Zones de livraison  |
| GET /catalog/movements/?variant= — journal des mouvements de stock | djangoClient.movements — Historique des  |
| GET /catalog/references/ — source unique (aucun endpoint /products/ n'existe) | djangoClient.products — Service de compa |
| GET /catalog/references/{id}/ — pour getById | djangoClient.products — Service de compa |
| DELETE /catalog/references/{id}/ — pour delete | djangoClient.products — Service de compa |
| GET /orders/?magasin_id= — source unique (aucun endpoint /sales/) | djangoClient.sales — Ventes derivees des |
| GET /users/notifications/ — liste | djangoClient.notifications — Notificatio |
| PATCH /users/notifications/{id}/ — {is_read: bool} | djangoClient.notifications — Notificatio |
| DELETE /users/notifications/{id}/ — suppression unitaire | djangoClient.notifications — Notificatio |
| POST /users/notifications/delete-all/ — tout supprimer | djangoClient.notifications — Notificatio |
| POST /users/notifications/bulk-read/ — {ids:[...]} | djangoClient.notifications — Notificatio |
| POST /users/notifications/bulk-delete/ — {ids:[...]} | djangoClient.notifications — Notificatio |
| WS /ws/notifications/?token= — flux temps reel | djangoClient.notifications — Notificatio |
| GET /users/magasins/users/ — magasins avec leurs employes | djangoClient.users — Utilisateurs, emplo |
| GET /users/me/ — profil courant (aussi utilise, a tort, par getById) | djangoClient.users — Utilisateurs, emplo |
| PUT /users/role/{id}/ — modification du role d'un utilisateur | djangoClient.users — Utilisateurs, emplo |
| DELETE /users/delete/{id}/ (body {password}) — suppression d'un compte | djangoClient.users — Utilisateurs, emplo |
| PATCH /users/me/ — mise a jour de son profil | djangoClient.users — Utilisateurs, emplo |
| GET /users/dashboard/ — unique endpoint, appele jusqu'a 4 fois si l'on utilise les 4 methodes (a mutualiser en un seul appel en Flutter) | djangoClient.dashboard — Indicateurs gen |
| POST /users/transfer/products/ — transfert multi-lignes entre magasins | djangoClient.transfers — Transfert de st |
| GET /users/magasins/overview/ — resume par magasin (stock, benefice estime, ventes de la semaine) | djangoClient.transfers — Transfert de st |
| GET /users/caisse/sessions/?magasin_id=&status= — historique des sessions | djangoClient.caisse — Sessions de caisse |
| GET /users/caisse/sessions/current/?magasin_id= — session ouverte ou null (204) | djangoClient.caisse — Sessions de caisse |
| POST /users/caisse/sessions/open/ — ouverture avec fond de caisse | djangoClient.caisse — Sessions de caisse |
| POST /users/caisse/sessions/{id}/close/ — fermeture avec solde compte | djangoClient.caisse — Sessions de caisse |
| GET /users/caisse/movements/?session_id=&magasin_id=&date_from=&date_to= — mouvements | djangoClient.caisse — Sessions de caisse |
| POST /users/caisse/movements/ — ajout d'un mouvement in/out | djangoClient.caisse — Sessions de caisse |
| DELETE /users/caisse/movements/{id}/ — suppression d'un mouvement | djangoClient.caisse — Sessions de caisse |
| GET /users/caisse/summary/?date_from=&date_to=&magasin_id= — synthese chiffree | djangoClient.caisse — Sessions de caisse |
| GET /users/caisse/categories/ — categories de depense | djangoClient.caisse — Sessions de caisse |
| POST /users/caisse/categories/ — creation | djangoClient.caisse — Sessions de caisse |
| PATCH /users/caisse/categories/{id}/ — renommage | djangoClient.caisse — Sessions de caisse |
| DELETE /users/caisse/categories/{id}/ — suppression | djangoClient.caisse — Sessions de caisse |
| GET /suppliers/orders/?magasin_id= — liste des commandes fournisseur | djangoClient.suppliers — Commandes fourn |
| GET /suppliers/orders/{id}/ — detail | djangoClient.suppliers — Commandes fourn |
| POST /suppliers/orders/ — creation avec lignes et couts | djangoClient.suppliers — Commandes fourn |
| POST /suppliers/orders/{id}/receive/ — reception -> entree de stock | djangoClient.suppliers — Commandes fourn |
| GET /users/backup/export/ — telechargement de l'archive de sauvegarde | djangoClient.backup — Sauvegarde / resta |
| POST /users/backup/import/ — restauration depuis une archive | djangoClient.backup — Sauvegarde / resta |
| GET /users/chat/users/ — interlocuteurs disponibles | djangoClient.chat — Messagerie interne |
| GET /users/chat/history/?recipient_id=&room_name= — historique des messages | djangoClient.chat — Messagerie interne |

## 5. Etats UI recenses

### Groupe `orders`

- `/orders` — userLoading : le premier fetchOrders n'est declenche qu'une fois useCurrentUser resolu (useEffect sur [userLoading, fetchOrders]) — avant, `loading` vaut true et le skeleton est affiche
- `/orders` — Loading liste : `loading===true` -> <Skeleton className="h-64 w-full" /> dans la Card (padding 6). fetchOrders(true) (temps reel, apres action, apres edition) ne repasse PAS loading a true = refresh silencieux sans clignotement
- `/orders` — Empty : searchableOrders.length===0 -> texte centre 'Aucune commande trouvee pour cette recherche.' (meme message qu'il y ait ou non une recherche active)
- `/orders` — Erreur de chargement : catch -> toast.error(err.message || 'Erreur de chargement des commandes'), la liste garde son contenu precedent, pas d'ecran d'erreur dedie
- `/orders` — Erreur d'action de statut : toast.error(err.message || 'Action impossible') — c'est ainsi que remontent les refus serveur (transition impossible, jour J, commande assignee a quelqu'un d'autre)
- `/orders` — Disabled 'jour J' : IconAction disabled + libelle 'Disponible le {JJ/MM/AAAA}' pour preparateur/livreur sur une commande planifiee plus tard ; meme regle pour le bouton d'action dans le detail
- `/orders` — Disabled soumission : boutons 'Creer la commande'/'Enregistrer'/'Supprimer'/'Annuler la commande' passent en libelle de progression ('Creation…', 'Enregistrement...', 'Suppression...', 'Annulation...') et disabled pendant l'appel
- `/orders` — Disabled 'Assigner' tant qu'aucun membre du staff n'est selectionne
- `/orders` — Disabled option couleur si stock_actuel <= 0 dans le Select Couleur
- `/orders` — Loading AssignStaffDialog : Skeleton h-10 ; Empty : 'Aucun {role} enregistre pour ce magasin.'
- `/orders` — Loading autocomplete : 'Recherche…' ; Empty autocomplete : 'Aucun resultat pour cette selection.'
- `/orders` — Aucun etat 'unauthorized' cote page : pas de guard de role ; un utilisateur non authentifie est redirige vers /login par le layout. Un role non prevu voit simplement une page en lecture seule sans action
- `/orders` — Les listes de staff/zones/categories/types/marques echouent en silence (catch -> tableau vide), sans toast

### Groupe `products`

- `/products` — Loading initial : <Skeleton className='h-64 w-full'> dans un padding 24px à la place du tableau (déclenché seulement par fetchAll(false))
- `/products` — Empty : paragraphe centré 'Aucune référence.' (py-12, texte muted) — même message quand la liste est vide et quand les filtres ne matchent rien (pas de distinction)
- `/products` — Erreur de chargement : uniquement un toast.error(err.message || 'Erreur de chargement du catalogue') — le tableau reste sur son état précédent (aucun écran d'erreur, aucun bouton Réessayer)
- `/products` — Unauthorized : aucun écran dédié — dégradation silencieuse en lecture seule (colonnes prix/marge et actions masquées, champs disabled)
- `/products` — Disabled : boutons Export/Import pendant l'opération ; 'Ajouter' de variante disabled sans couleur ; 'Appliquer' du bulk price disabled si pas de sous-type ou 0 référence concernée ; options de couleur disabled si stock <= 0 dans le panier ; boutons de marques suggérées disabled si déjà présentes ou en cours d'ajout ; champ Prix du panier readOnly+disabled
- `/products` — Submitting : libellés dynamiques 'Export...', 'Import...', 'Enregistrement…', 'Création…', 'Mise à jour...', 'Annulation...' avec bouton disabled
- `/products` — Autocomplétion : trois états dans le dropdown — 'Recherche…', 'Aucun résultat pour cette sélection.', ou la liste des suggestions
- `/products` — Revue IA post-import : 4 états — 'Analyse en cours…' (loading), 'Aucune nouvelle référence à vérifier.' (skipped), 'Aucun doublon suspect détecté.' (done sans warning), liste des correspondances suspectes (done avec warnings)
- `/products` — Empty states secondaires : 'Aucune couleur pour cette référence.', 'Aucune marque.', 'Aucune couleur.', 'Aucune catégorie.', 'Aucun sous-type.', 'Aucune' (colonne Variantes)
- `/products` — Aucune gestion d'état hors-ligne, aucun optimistic update : toute mutation est suivie d'un re-fetch complet

### Groupe `movements`

- `/movements` — loading initial (loading=true) : les 3 KPI affichent chacun un Skeleton (h-8 w-20 / h-8 w-28 / h-8 w-12), les 2 cartes de statistiques un Skeleton h-24 w-full, et le tableau principal 5 Skeleton h-12 w-full empiles (space-y-2)
- `/movements` — loading : le bouton 'Actualiser' est disabled et son icone RefreshCw tourne (animate-spin) ; le bouton 'Exporter XLSX' est disabled
- `/movements` — refresh silencieux (fetchData(true), declenche par le WebSocket) : loading n'est PAS remis a true, aucun skeleton, aucun spinner — les donnees se remplacent sans clignotement
- `/movements` — empty tableau principal : une seule ligne, colSpan={isManager ? 8 : 7}, texte centre muted py-8 'Aucun mouvement enregistre'
- `/movements` — empty 'Produits les plus vendus' : 'Aucune vente enregistree sur cette periode.'
- `/movements` — empty 'Produits sans mouvement' : 'Tous les produits ont eu au moins un mouvement sur cette periode.'
- `/movements` — empty 'Mouvements par jour' : 'Aucun mouvement pour cette periode.' (text-sm muted, centre, py-8) — s'affiche aussi dans le cas normal ou le seul jour present est aujourd'hui et hideToday=true
- `/movements` — error : AUCUN etat d'erreur UI. Le catch de fetchData fait uniquement console.error('Error fetching data:', err) — pas de toast, pas de banniere, pas de bouton 'Reessayer'. Un echec au premier chargement laisse la page vide avec les messages 'empty' (indistinguable d'un vrai vide)
- `/movements` — unauthorized : AUCUN rendu dedie. Si le token est absent, le layout (app) redirige vers /login. Si l'API renvoie 401 apres echec du refresh, on retombe sur le cas error silencieux
- `/movements` — disabled : 'Actualiser' (loading), 'Exporter XLSX' (loading ou 0 mouvement filtre), 'Reinitialiser' des stats (aucune des deux dates renseignee)
- `/movements` — success : uniquement via toasts sonner sur l'export Excel (pas de toast au chargement ni au refresh)

### Groupe `chats`

- `/chats` — authLoading: spinner plein ecran + 'Chargement de votre profil...'
- `/chats` — unauthorized: bloc 'Non Authentifie' (AlertCircle destructive) — la messagerie n'est pas rendue du tout
- `/chats` — loadingUsers (liste collaborateurs): Loader2 + 'Chargement des collaborateurs...' centre; NON affiche lors des rafraichissements silencieux toutes les 20 s
- `/chats` — empty collaborateurs (apres filtre): 'Aucun collaborateur trouve'
- `/chats` — loadingHistory: overlay centre Loader2 (h-8) + 'Chargement des messages...'
- `/chats` — empty messages: icone MessageSquare dans un rond, 'Aucun message pour le moment' + 'Envoyez un message pour commencer la conversation en temps reel.' (+ affichage des suggestions rapides)
- `/chats` — socket 'connecting': badge ambre 'Connexion...' avec Loader2 anime
- `/chats` — socket 'connected': badge emeraude 'En ligne' avec pastille animee (ping)
- `/chats` — socket 'disconnected': badge rose 'Hors ligne' avec Circle plein
- `/chats` — disabled: Input message, bouton Envoyer et bouton '+' desactives des que socketStatus !== 'connected'; bouton Envoyer aussi desactive si le message est vide/blanc
- `/chats` — loadingProducts (popover): Loader2 centre
- `/chats` — empty produits: 'Aucun produit trouve'
- `/chats` — error: gere UNIQUEMENT par des toasts (aucun etat d'erreur inline/retry). Pas d'etat d'erreur pour un WebSocket qui ne parvient jamais a se connecter, au-dela du badge 'Hors ligne'

### Groupe `users`

- `/users (libellé sidebar : "Super Admin",` — LOADING onglet Actifs : `loading` initial à true ; rendu de 4 Skeleton h-10 w-full empilés (space-y-2) à la place du tableau.
- `/users (libellé sidebar : "Super Admin",` — LOADING onglet En attente : mêmes conditions (partage le state `loading`), 3 Skeleton h-10 w-full.
- `/users (libellé sidebar : "Super Admin",` — LOADING onglet Réinit. : state séparé passwordRequestsLoading (initial true) ; 3 Skeleton h-16 w-full ; le bouton Refresh est disabled et son icône tourne.
- `/users (libellé sidebar : "Super Admin",` — EMPTY onglet Actifs : une TableRow avec une cellule colSpan={8} centrée, py-8, text-muted-foreground, texte 'Aucun utilisateur trouvé' (colSpan=8 alors que le tableau n'a que 7 colonnes).
- `/users (libellé sidebar : "Super Admin",` — EMPTY onglet En attente : bloc centré py-12 muted avec deux lignes — 'Aucune demande en attente' (text-lg font-medium) et 'Tous les utilisateurs ont été traités.' (text-sm mt-1). Ce bloc REMPLACE le tableau entier (pas de header de colonnes affiché).
- `/users (libellé sidebar : "Super Admin",` — EMPTY onglet Réinit. : bloc centré py-12 muted avec le texte dynamique 'Aucune demande ' + libellé du filtre en minuscules ('en attente' / 'approuvée' / 'rejetée'), ou juste 'Aucune demande ' quand le filtre vaut 'all'.
- `/users (libellé sidebar : "Super Admin",` — UNAUTHORIZED : si !isManager && !currentUserLoading, la page entière est remplacée par une Card centrée (py-20) avec l'icône ShieldAlert h-12 w-12 text-red-500, le titre 'Accès Refusé' (text-xl font-bold) et le texte muted "Vous n'avez pas les permissions pour gérer les utilisateurs." — aucun bouton de retour.
- `/users (libellé sidebar : "Super Admin",` — ERROR de chargement de la liste des utilisateurs : toast.error('Erreur de chargement: ' + err.message) ; les tableaux restent avec leurs données précédentes (ou vides) — pas d'état d'erreur dédié ni de bouton 'Réessayer'.
- `/users (libellé sidebar : "Super Admin",` — ERROR de chargement des demandes de réinit. : toast.error('Erreur lors du chargement des demandes: ' + err.message).
- `/users (libellé sidebar : "Super Admin",` — SILENT FAILURE : GET /users/pending/ est appelé avec .catch(() => []) — un échec produit une liste vide sans le moindre message, l'onglet affiche alors l'état vide 'Aucune demande en attente'.
- `/users (libellé sidebar : "Super Admin",` — DISABLED : bouton 'Créer l'utilisateur' pendant isSubmitting ; bouton 'Enregistrer' du dialog rôle si aucun rôle, rôle inchangé, ou chargement ; boutons Approuver/Rejeter d'une demande de réinit. quand resolvingRequestId === r.id (verrou par ligne — les autres lignes restent cliquables) ; bouton Refresh pendant passwordRequestsLoading ; boutons Annuler / Supprimer définitivement du ConfirmDeleteDialog pendant la suppression.
- `/users (libellé sidebar : "Super Admin",` — SUCCESS : uniquement des toasts (sonner) — aucune bannière ni état de succès persistant. La donnée est systématiquement rechargée après l'action.
- `/users (libellé sidebar : "Super Admin",` — PAS d'état 'saving' visuel sur les boutons Approuver / Rejeter de l'onglet En attente : ils ne sont ni désactivés ni mis en spinner pendant l'appel (double-clic possible).
- `/users (libellé sidebar : "Super Admin",` — PENDANT currentUserLoading : la page rend l'UI normale (pas d'écran Accès Refusé prématuré, la garde exige !currentUserLoading), avec les tableaux en skeleton puisque fetchUsers n'est déclenché qu'une fois currentUserLoading passé à false.

### Groupe `caisse-bilan`

- `/caisse` — userLoading: retour anticipe -> page entiere remplacee par 3 Skeleton h-16 w-full dans un conteneur p-6 space-y-4
- `/caisse` — loading (fetch caisse): 3 Skeleton h-16 w-full a la place des 3 cartes
- `/caisse` — summaryLoading: Skeleton h-40 w-full a la place du contenu de la carte Resume
- `/caisse` — Empty 'aucun magasin resolu' (!magasinId): Card avec texte muted centre py-12 — 'Selectionnez un magasin pour gerer sa caisse.' si isAdmin, sinon 'Aucun magasin associe a votre compte.'
- `/caisse` — Empty liste magasins (admin): texte 'Aucun magasin'
- `/caisse` — Empty mouvements de session: 'Aucun mouvement pour l'instant' (p-4, centre, muted)
- `/caisse` — Empty mouvements de periode: 'Aucun mouvement pour cette periode'
- `/caisse` — Empty historique: ligne de tableau unique colSpan=6, 'Aucune session fermee', centree py-8 muted
- `/caisse` — Etat 'caisse fermee' vs 'caisse ouverte': change le titre, l'icone, la description et le jeu de boutons de la carte 1; le bloc KPI + mouvements n'existe que si session
- `/caisse` — Erreurs: uniquement des toasts sonner (chargement magasins, chargement caisse, chargement resume, echec des 3 soumissions). Aucun ecran d'erreur, aucun retry, les donnees precedentes restent affichees
- `/caisse` — Unauthorized: AUCUN etat gere dans la page — un preparateur/livreur qui force /caisse verra la coquille de page + des toasts d'erreur 403 (a implementer proprement en Flutter)
- `/caisse` — Disabled: bouton Actualiser disabled pendant loading; les 6 boutons des dialogs disabled pendant submitting; le champ Select categorie n'est pas disabled mais purement conditionnel
- `/caisse` — Succes: toasts 'Caisse ouverte' / 'Caisse fermee' / 'Mouvement ajoute' + fermeture du dialog + refetch
- `/bilan` — Loading initial: chaque carte affiche un Skeleton dans un conteneur p-6 — h-32 w-full pour 'Livraisons effectuees', h-24 w-full pour 'Retours'
- `/bilan` — Loading silencieux (declenche par WebSocket): aucun indicateur visuel, les donnees se remplacent
- `/bilan` — Empty livraisons: 'Aucune livraison effectuee aujourd'hui.' (text-sm muted, centre, py-10)
- `/bilan` — Empty retours: 'Aucun retour aujourd'hui.' (meme style)
- `/bilan` — Unauthorized: ecran plein 'Acces refuse' avec ShieldAlert rouge (voir roles) — le seul des deux pages a en avoir un
- `/bilan` — Erreur reseau: catch SILENCIEUX -> setOrders([]) sans toast ni message; l'utilisateur voit les deux etats vides et un ticket a 0 Ar, indiscernable d'une journee sans livraison (point a ameliorer au portage Flutter)
- `/bilan` — Le ticket est toujours rendu, meme pendant le loading (il affiche alors 0 / 0 Ar puisque orders est vide)
- `/bilan` — Aucun bouton disabled, aucun etat de soumission

### Groupe `dashboard-reports`

- `/dashboard` — userLoading -> 3 Skeleton h-16 w-full (page entière)
- `/dashboard` — unauthorized (!isGerant) -> Card pleine page « Accès refusé » + ShieldAlert rouge
- `/dashboard` — loading (fetch initial) -> chaque KpiCard affiche Skeleton h-8 w-32 à la place de la valeur; graphique 1 Skeleton h-64 w-full; graphique 2 Skeleton h-64 w-full; ventes récentes 5 Skeleton h-14 w-full; alertes 4 Skeleton h-12 w-full
- `/dashboard` — empty catégories -> `Aucune donnée` centré (h-64, text-muted-foreground text-sm)
- `/dashboard` — empty ventes récentes -> `Aucune vente enregistrée` (text-sm text-muted-foreground text-center py-8)
- `/dashboard` — empty alertes (cas succès) -> bloc centré CheckCircle2 h-10 w-10 text-green-500 + `Tous les stocks sont OK` (text-sm font-medium text-green-700) + `Aucun produit en alerte` (text-xs)
- `/dashboard` — error -> AUCUN état d'erreur visible: le catch fait seulement console.error('Dashboard error:', err); l'utilisateur voit une page avec des KPI à 0 et des états vides. Pas de toast, pas de retry
- `/dashboard` — refetch temps réel -> silencieux, aucun indicateur visuel (pas de spinner, pas de flash de skeleton)
- `/reports` — loading initial et sur clic `Actualiser` -> Skeletons: h-8 w-24 dans chaque carte KPI, h-64 w-full pour le graphique CA, h-48 w-full pour top produits / ventes à crédit / vendeurs / magasins, h-20 w-full pour le bloc mouvements
- `/reports` — empty top produits -> `Aucune vente enregistrée` (text-muted-foreground text-sm text-center py-8)
- `/reports` — empty ventes à crédit -> bloc centré CircleCheck h-8 w-8 text-green-500 + `Aucune vente impayée`
- `/reports` — empty vendeurs -> `Aucune vente enregistrée`
- `/reports` — empty magasins (admin) -> `Aucune vente enregistrée`
- `/reports` — empty mouvements -> pas d'état vide dédié: les 3 tuiles affichent simplement 0
- `/reports` — error de chargement -> AUCUN état visible (catch -> console.error seul); le /users/dashboard/ échoue silencieusement via .catch(() => ({}))
- `/reports` — IA idle -> bouton `Générer l'analyse`
- `/reports` — IA loading -> texte `Génération en cours (modèle IA local — cela peut prendre plusieurs minutes)...` (text-xs text-muted-foreground) + 4 Skeletons h-4 de largeurs 100%/90%/80%/85%
- `/reports` — IA success -> texte brut whitespace-pre-wrap leading-relaxed en text-gray-800 / dark:text-gray-200 + bouton `Régénérer`
- `/reports` — IA error -> même zone de texte mais en text-red-600 / dark:text-red-400; message serveur type `Erreur lors de la génération de l'analyse. Impossible de contacter Ollama sur {URL}...` ou `Le modèle a mis trop de temps à répondre (délai dépassé).`; erreur réseau côté client -> `Erreur réseau lors de l'appel à l'analyse IA.`
- `/reports` — disabled -> bouton Actualiser désactivé pendant loading; bouton Régénérer désactivé pendant loading IA
- `/reports` — unauthorized -> NON GÉRÉ dans la page (pas d'écran d'accès refusé)

### Groupe `settings-stores`

- `/settings` — LOADING global : `if (userLoading)` -> conteneur p-6 space-y-4 avec 3 <Skeleton className="h-24 w-full"> (pas de spinner)
- `/settings` — LOADING listes catégories/zones : AUCUN état de chargement — la liste est simplement vide puis se remplit
- `/settings` — ERROR chargement catégories/zones : swallow total `.catch(() => {})` — aucun toast, aucun message, la liste reste vide (indiscernable d'un vrai vide)
- `/settings` — EMPTY catégories : 'Aucune catégorie.' centré, text-sm text-muted-foreground, py-4
- `/settings` — EMPTY zones : 'Aucune zone.' même style
- `/settings` — SUBMITTING profil : bouton 'Enregistrement...' + disabled
- `/settings` — SUBMITTING mot de passe : bouton 'Changement...' + disabled
- `/settings` — SUBMITTING modal : Loader2 animate-spin + 'Enregistrement...' + disabled
- `/settings` — UNAUTHORIZED / non-gérant : pas d'écran 403 — dégradation en lecture seule (champs disabled, onglets masqués, formulaire mot de passe non rendu, bouton Enregistrer non rendu) + textes explicatifs dans les CardDescription
- `/settings` — DISABLED : tous les inputs profil quand !isGerant ; input file avatar disabled ; Input number des quantités non applicable ici
- `/settings` — Pas d'état 'success' persistant : seulement des toasts éphémères
- `/stores` — LOADING initial / après 'Actualiser' / après édition-création : grille de 3 <Skeleton className="h-48 rounded-xl"> dans la même grille responsive
- `/stores` — LOADING silencieux (WebSocket) : aucun indicateur, les données se remplacent en place
- `/stores` — ERROR chargement principal : toast.error('Erreur lors du chargement.') uniquement si `!silent` ; `stores` reste à sa valeur précédente (souvent []) ; pas d'écran d'erreur ni de bouton Réessayer autre que 'Actualiser'
- `/stores` — ERROR stats (/magasins/stats/) : silencieuse (console.error) -> KPI affichés à 0 Ar / 0 produits
- `/stores` — ERROR profit (/magasins/overview/) : silencieuse -> repli sur `storeStats.profit` puis 0
- `/stores` — EMPTY : AUCUN état vide dédié — si aucun magasin, la grille est vide et le sous-titre affiche '0 magasin(s)'
- `/stores` — SUBMITTING création : bouton Loader2 + 'Création...' disabled
- `/stores` — SUBMITTING édition : bouton Loader2 + 'Enregistrement...' disabled
- `/stores` — SUBMITTING transfert : bouton Loader2 + 'Transfert en cours...' disabled
- `/stores` — DISABLED (transfert) : bouton submit disabled si panier vide OU pas de destination ; Input quantité et bouton 'Sélectionner' disabled si déjà au panier (`inCart`) ou stock <= 0
- `/stores` — UNAUTHORIZED : pas d'écran dédié — les actions admin ne sont simplement pas rendues ; un employer verra la carte de son magasin sans aucun bouton d'action
- `/stores` — Bloc gérant absent si `store.manager` est null (cellule conditionnelle)
- `/stores` — Logo magasin absent -> icône Store en repli (en-tête de carte ET liste des destinations du transfert)

### Groupe `suppliers-transfers`

- `/suppliers` — loading: skeleton `<Skeleton className='h-64 w-full' />` dans un padding p-6 tant que loading===true (uniquement au premier chargement et sur fetchOrders() non silencieux)
- `/suppliers` — empty: texte centre gris 'Aucune commande fournisseur.' (py-12) quand orders.length === 0
- `/suppliers` — error (chargement): toast.error(err.message || 'Erreur de chargement') — le tableau reste vide, pas d'ecran d'erreur dedie
- `/suppliers` — error (reception): toast.error(err.message || 'Réception impossible') — ex: 'Cette commande fournisseur a déjà été reçue.'
- `/suppliers` — error (creation): toast.error(err.message || 'Erreur'), dialog conserve
- `/suppliers` — success (creation): toast.success('Commande fournisseur créée')
- `/suppliers` — success (reception): toast.success('Commande <numero> reçue — stock mis à jour')
- `/suppliers` — disabled: bouton 'Créer' disabled pendant submitting, libelle change en 'Création…'
- `/suppliers` — unauthorized: NON gere cote page — un non-Gerant voit la page vide + toast d'erreur API (403). Pas d'ecran 'Acces refuse' comme sur /transfers.
- `/suppliers` — refetch silencieux (temps reel WS): aucun indicateur visuel, la liste se met a jour toute seule
- `/transfers` — loading: si userLoading || loading -> 3 Skeleton h-16 w-full empiles (p-6 space-y-4)
- `/transfers` — unauthorized: Card centree, icone ShieldAlert rouge, titre 'Accès refusé', texte 'Cette page est réservée aux administrateurs.' (py-20, texte centre)
- `/transfers` — empty (magasins): si stores.length === 0 -> texte gris 'Aucun magasin' a la place de la rangee de boutons
- `/transfers` — empty (aucune source choisie): zone flex-1 min-h-[300px] avec bordure en pointilles (border-dashed) et texte gris centre 'Sélectionnez un magasin source pour commencer.'
- `/transfers` — error (chargement magasins): toast.error('Erreur de chargement des magasins: ' + (err.message || err))
- `/transfers` — BUG A REPRODUIRE OU CORRIGER: pour un utilisateur NON admin, `loading` reste a true indefiniment (fetchStores n'est appele que si isAdmin, et rien d'autre ne fait setLoading(false)); la condition `if (userLoading || loading)` court-circuite donc l'ecran 'Accès refusé' — un non-admin voit un skeleton infini. En Flutter, prevoir setLoading(false) quand !isAdmin pour afficher reellement l'ecran d'acces refuse.
- `/transfers (composant partage TransferPr` — loading produits: bloc centre h-32 avec Loader2 anime + texte 'Chargement...'
- `/transfers (composant partage TransferPr` — empty produits (magasin vide): 'Aucun produit dans ce magasin' (p-4, text-sm, centre, muted)
- `/transfers (composant partage TransferPr` — empty recherche produits: 'Aucun résultat' (meme style) — la distinction se fait sur sourceProducts.length === 0
- `/transfers (composant partage TransferPr` — empty panier: 'Aucun produit sélectionné'
- `/transfers (composant partage TransferPr` — empty destinations: 'Aucun magasin trouvé'
- `/transfers (composant partage TransferPr` — error chargement produits: console.error + toast.error('Erreur de chargement des produits'), la liste reste vide
- `/transfers (composant partage TransferPr` — disabled: bouton d'ajout et input de quantite desactives si deja au panier ou stock <= 0; bouton submit desactive si envoi en cours / panier vide / pas de destination
- `/transfers (composant partage TransferPr` — submitting: spinner + libelle 'Transfert en cours...' sur le bouton submit
- `/transfers (composant partage TransferPr` — Pas d'etat 'unauthorized' interne (herite de l'hote)
- `/stores (modal TransferProductsDialog — ` — Aucun etat propre: loading/empty/error sont ceux du panel.
- `/stores (modal TransferProductsDialog — ` — Si sourceStore est null, le dialog s'affiche avec seulement l'en-tete (description avec un nom de magasin vide) et un corps vide.

### Groupe `petites-pages`

- `/alerts` — loading (initial, loading=true par defaut) : chaque KPI affiche <Skeleton className='h-8 w-12' /> a la place du chiffre; chaque AlertTable affiche <Skeleton className='h-24 w-full' />.
- `/alerts` — empty par section : <p class='text-sm text-muted-foreground text-center py-6'> avec le message dedie — 'Aucun produit en rupture de stock' / "Tous les stocks sont au-dessus du seuil d'alerte" / 'Aucun produit proche de la peremption' (ce dernier est inatteignable car la carte n'est rendue que si la liste est non vide).
- `/alerts` — error : catch { console.error(err) } UNIQUEMENT — pas de toast, pas de bandeau, pas de bouton reessayer. En cas d'echec la page reste sur les donnees precedentes (ou vide) et sort du loading via finally.
- `/alerts` — success : pas de toast (page lecture seule).
- `/alerts` — unauthorized : AUCUN etat implemente.
- `/alerts` — disabled : uniquement le bouton Actualiser pendant loading.
- `/alerts` — Pendant un refresh silencieux (websocket) : aucun indicateur visuel, loading reste false.
- `/pickup` — loading (initial true) : 3 <Skeleton className='h-24 w-full' /> empiles dans un div space-y-3.
- `/pickup` — empty : Card avec CardContent 'py-16 text-center text-sm text-muted-foreground' contenant 'Aucune commande prete a recuperer pour le moment.'
- `/pickup` — unauthorized : ecran plein remplacant tout — Card > CardContent flex-col items-center justify-center py-20 text-center, icone ShieldAlert h-12 w-12 text-red-500 mb-4, h2 text-xl font-bold 'Acces refuse', paragraphe muted 'Cette page est reservee au gerant.'
- `/pickup` — error de chargement : toast.error(err.message || 'Erreur de chargement des commandes'); la liste conserve son etat precedent.
- `/pickup` — error d'action : toast.error(err.message || 'Action impossible'); la modale RESTE OUVERTE (setPickupTarget(null) n'est appele que dans le chemin succes).
- `/pickup` — success : toast.success(`Commande ${order.numero} recuperee`), fermeture de la modale, puis fetchOrders(true) silencieux (la carte disparait de la liste puisqu'elle n'est plus PRETE).
- `/pickup` — disabled : bouton carte + bouton Confirmer pendant confirming === order.id (state number|null, un seul a la fois).
- `/pickup` — Pas d'etat 'refresh en cours' visible sur le bouton icone.
- `/scanner` — loading : simple <p className='text-muted-foreground text-sm'>Recherche...</p> (aucun skeleton, aucun spinner).
- `/scanner` — empty / aucun resultat : Card > CardContent flex-col items-center py-12 gap-2 avec icone Package h-10 w-10 et le texte 'Aucun produit trouve pour « {query} »' (guillemets francais).
- `/scanner` — idle (aucune query ET aucun resultat) : Card > CardContent flex-col items-center py-16 gap-3, icone QrCode h-16 w-16 opacity-20 + p text-lg font-medium 'Tapez pour rechercher un produit'.
- `/scanner` — error : toast.error(err.message || 'Erreur lors de la recherche'); results conserve sa valeur precedente.
- `/scanner` — success : pas de toast (affichage direct des cartes).
- `/scanner` — unauthorized : AUCUN etat implemente.
- `/scanner` — disabled : aucun.
- `/sales` — Aucun etat UI : ni loading, ni empty, ni error. Rendu = null pendant le tick de redirection.
- `/superadmin` — loading (userLoading || loading) : TOUTE la page est remplacee par un div p-6 space-y-4 contenant 3 <Skeleton className='h-16 w-full' /> — l'en-tete et les stats disparaissent aussi.
- `/superadmin` — Ce meme skeleton plein ecran reapparait apres CHAQUE changement de role et CHAQUE suppression, car fetchData() fait setLoading(true) (pas de mode silencieux ici).
- `/superadmin` — empty : AUCUN etat vide implemente — si stores est vide, on voit deux tableaux avec un header et zero ligne, et les descriptions '0 equipe(s) enregistree(s)' / '0 compte(s) enregistre(s)'.
- `/superadmin` — error de chargement : catch { console.error(err) } uniquement — pas de toast, pas de bandeau, pas de retry. stores reste a sa valeur precedente.
- `/superadmin` — error changement de role : toast.error(err.message || 'Erreur').
- `/superadmin` — error suppression : message inline rouge dans la modale (pas de toast).
- `/superadmin` — success : toast.success('Role modifie') / toast.success('Utilisateur supprime').
- `/superadmin` — unauthorized : pas d'ecran dedie — redirection router.replace('/dashboard') sans aucun message.
- `/superadmin` — disabled : bouton Actualiser pendant loading; Select de role si changingRole===u.id ou u.role==='admin'; boutons de la modale pendant l'envoi.

### Groupe `notifications`

- `/notifications` — loading (initial + a chaque Actualiser / toggleRead / markAllRead) : 5 <Skeleton className='h-20 w-full rounded-lg' /> empiles (space-y-3). Skeleton = div bg-accent animate-pulse rounded-md
- `/notifications` — empty : bloc centre 'Aucune notification pour le moment.' (py-16 text-center text-muted-foreground)
- `/notifications` — error de chargement : console.error('Notifications error:', error) + toast.error('Impossible de charger les notifications.'). La liste precedente est conservee telle quelle (au 1er chargement -> etat vide affiche). Pas de bloc d'erreur inline, pas de bouton 'Reessayer' dedie (l'utilisateur doit cliquer Actualiser)
- `/notifications` — actionLoading : passe a true pendant toggleRead / markAllRead / clearAll / deleteNotification -> desactive les 3 boutons d'en-tete ET les 2 boutons de chaque carte. Aucun spinner visuel sur les boutons, juste l'etat disabled
- `/notifications` — success : uniquement via toasts (voir uxDetails), aucun etat de succes persistant a l'ecran
- `/notifications` — unauthorized : AUCUN etat gere dans la page. Un 401 declenche le refresh automatique du token dans djangoClient.request ; si le refresh echoue -> window.location.href = '/login' (hard redirect depuis lib/django-client.ts). Un 403 backend (suppression refusee, 'Permission refusee') remonte comme une Error generique et se traduit par le toast 'Impossible de supprimer la notification.'
- `/notifications` — socket : 3 etats explicites 'connecting' | 'connected' | 'disconnected' materialises par le badge d'en-tete uniquement (aucun blocage de l'UI)
- `(global) TopBar — cloche de notification` — loading : spinner Loader2 h-5 w-5 animate-spin centre, py-8, text-muted-foreground. Note : loading n'est jamais remis a true apres le 1er chargement (pas de bouton actualiser ici)
- `(global) TopBar — cloche de notification` — empty : bloc centre avec icone Bell h-8 w-8 opacity-30 + texte 'Aucune notification' (px-4 py-10 text-sm text-muted-foreground)
- `(global) TopBar — cloche de notification` — error de chargement : uniquement console.error('Notifications error:', error), AUCUN toast, AUCUN affichage d'erreur — l'utilisateur voit simplement l'etat vide
- `(global) TopBar — cloche de notification` — error markAsRead : console.error('Mark read error:', error), silencieux pour l'utilisateur
- `(global) TopBar — cloche de notification` — error markAllAsRead : console.error('Mark all read error:', error), silencieux
- `(global) TopBar — cloche de notification` — actionLoading : desactive le bouton 'Tout marquer lu' pendant l'appel
- `(global) TopBar — cloche de notification` — Aucun etat unauthorized gere ; le hook WS ne se connecte simplement pas si djangoClient.isAuthenticated() est faux

### Groupe `auth`

- `/` — Aucun etat UI — redirection instantanee
- `/login` — loading : etat booleen unique — desactive les deux inputs ET le bouton submit, remplace le libelle du bouton par spinner + 'Connexion…'
- `/login` — error : PAS d'affichage inline — uniquement via toast.error (rouge, richColors)
- `/login` — success : toast.success('Connexion reussie !') puis navigation
- `/login` — unauthorized / compte non approuve : toast.error, on reste sur la page
- `/login` — empty : non applicable
- `/login` — Aucun skeleton (Suspense fallback = null)
- `/register` — loading : tous les inputs + le bouton disabled, bouton = spinner + 'Creation du compte…'
- `/register` — error : toast rouge uniquement (aucun message d'erreur inline sous les champs, aucun etat 'champ invalide' visuel)
- `/register` — success : toast vert + navigation vers /auth/pending-approval
- `/register` — Aucun etat empty / skeleton / unauthorized
- `/forgot-password` — loading (partage par les 3 formulaires) : inputs + boutons disabled, Loader2 spinner dans le bouton
- `/forgot-password` — status = null : aucun bandeau (etat initial de l'ecran 'check')
- `/forgot-password` — status = 'none' : bandeau MASQUE volontairement + toast d'erreur
- `/forgot-password` — status = 'pending' / 'approved' / 'rejected' : bandeau colore correspondant
- `/forgot-password` — success final : toast + redirection /login
- `/forgot-password` — error : toasts uniquement, aucun message inline
- `/reset-password` — Suspense fallback : carte 'Chargement...' avec spinner Loader2 (seul vrai etat loading de page du perimetre)
- `/reset-password` — loading (submit) : le bouton passe de 'Changer le mot de passe' a 'Changement...' et devient disabled ; PAS de spinner icone ici (texte seul)
- `/reset-password` — error : toast rouge
- `/reset-password` — success : toast vert + redirection /login
- `/reset-password` — unauthorized : non gere cote UI — se traduit par une erreur toast avec le message backend, ou par une redirection dure vers /login declenchee par l'intercepteur 401 du client
- `/verify-email` — Aucun etat : page purement statique
- `/pending-approval` — Aucun etat : page statique, aucun polling du statut d'approbation
- `/auth/pending-approval` — Aucun etat : page statique, pas de polling
- `/logout` — Un unique ecran transitoire avec le texte 'Deconnexion...'

### Groupe `layout-nav`

- `/* (RootLayout — enveloppe TOUTES les pa` — Aucun etat React (composant serveur pur, pas de loading/empty/error)
- `/* (RootLayout — enveloppe TOUTES les pa` — Etat d'erreur global THEORIQUE via GlobalErrorBoundary — non branche (voir features)
- `/(app)/* — shell applicatif protege (cou` — unauthorized : redirection client vers /login (aucun ecran intermediaire, aucun toast)
- `/(app)/* — shell applicatif protege (cou` — Aucun loading/skeleton/empty/error gere a ce niveau
- `/(app)/* — shell applicatif protege (cou` — socketStatus du DataSyncProvider : 'connecting' | 'connected' | 'disconnected' — expose mais NON affiche dans ce layout (aucun indicateur visuel de connexion dans la coque)
- `/(app)/* — Sidebar de navigation (rendue` — loading (useCurrentUser.loading = true) : AFFICHE TOUS les items sauf ceux marques superAdminOnly, pour eviter le flash de menu — commentaire code : 'Pendant le chargement on affiche tout pour eviter le flash'. Consequence : un preparateur/livreur voit brievement Tableau de bord, Recuperation, Produits, Caisse, Mouvements, Alertes, Fournisseurs, Notifications, Rapports avant filtrage
- `/(app)/* — Sidebar de navigation (rendue` — Pas de skeleton, pas d'etat vide, pas d'etat d'erreur : si GET /users/me/ echoue, useCurrentUser met user=null et loading=false => seuls les items sans flag restent (Commandes, Chats) car isSuperAdmin/isAdminOrSuperAdmin/isLivreur sont tous false ; Produits et Caisse restent aussi visibles (leurs flags sont hideXxx, faux quand user est null)
- `/(app)/* — Sidebar de navigation (rendue` — Etat actif / inactif des liens (voir uxDetails)
- `/(app)/* — Sidebar de navigation (rendue` — Aucun etat disabled
- `/(app)/* — TopBar (barre superieure, ren` — mounted / non monte : evite le mismatch d'hydratation de l'icone de theme
- `/(app)/* — TopBar (barre superieure, ren` — user absent : affiche 'Utilisateur', email vide, aucune ligne de role, initiales 'U'
- `/(app)/* — TopBar (barre superieure, ren` — Notifications : loading (spinner Loader2 animate-spin, py-8, texte muted), empty ('Aucune notification' + icone Bell h-8 w-8 opacity-30, px-4 py-10, centre), liste (max 8 items)
- `/(app)/* — TopBar (barre superieure, ren` — Bouton 'Tout marquer lu' : disabled si unreadCount === 0 || actionLoading
- `/(app)/* — TopBar (barre superieure, ren` — Aucun etat d'erreur visuel pour les notifications : les echecs sont seulement console.error ('Notifications error:', 'Mark read error:', 'Mark all read error:')
- `* — GlobalErrorBoundary (composant trans` — Normal : rend simplement this.props.children
- `* — GlobalErrorBoundary (composant trans` — Erreur : rend le fallback fourni, sinon l'ecran de repli interne
- `* — GlobalErrorBoundary (composant trans` — Apres 'Reessayer' : retour a l'etat normal (re-render des children)
- `* — ThemeProvider (wrapper de theme, mon` — theme = 'system' | 'light' | 'dark' ; resolvedTheme calcule par next-themes ; risque de mismatch d'hydratation gere par suppressHydrationWarning + le flag `mounted` dans la TopBar
- `(aucune route) — components/ui/sidebar.t` — expanded / collapsed (data-state), persiste dans le cookie sidebar_state pendant 7 jours
- `(aucune route) — components/ui/sidebar.t` — openMobile true/false (Sheet)
- `(aucune route) — components/ui/sidebar.t` — isActive sur MenuButton et MenuSubButton (data-active=true)
- `(aucune route) — components/ui/sidebar.t` — disabled / aria-disabled : pointer-events-none + opacity-50
- `(aucune route) — components/ui/sidebar.t` — loading : SidebarMenuSkeleton (squelette de ligne de menu, largeur aleatoire)

### Groupe `medias-divers`

- `(composant partagé) <ImageUpload /> — zo` — DROPZONE INACTIVE (état par défaut/vide) : border-slate-300 bg-slate-50, hover:border-slate-400
- `(composant partagé) <ImageUpload /> — zo` — DROPZONE ACTIVE (survol pendant un drag) : border-blue-500 bg-blue-50
- `(composant partagé) <ImageUpload /> — zo` — ERREUR : bandeau bg-red-50 text-red-700 px-3 py-2 rounded text-sm mb-4 avec icône AlertCircle 4x4 — visible UNIQUEMENT dans la branche dropzone ; si une preview est affichée, aucune erreur ne peut apparaître
- `(composant partagé) <ImageUpload /> — zo` — SUCCÈS / IMAGE SÉLECTIONNÉE : bascule complète vers la vue prévisualisation
- `(composant partagé) <ImageUpload /> — zo` — AUCUN état loading/spinner (la lecture base64 est considérée instantanée), AUCUN état disabled, AUCUN état unauthorized
- `(composant partagé) <ProductImageGallery` — ÉTAT VIDE — si !images || images.length === 0 : Card avec CardTitle 'Galerie d’images', CardDescription 'Aucune image ajoutée pour ce produit' et CardContent centré (text-center py-8 text-slate-500) 'Ajoutez des images pour visualiser les photos du produit et leurs codes QR'. Retour anticipé, rien d'autre n'est rendu.
- `(composant partagé) <ProductImageGallery` — ÉTAT 1 SEULE IMAGE — le bloc principal s'affiche mais la section vignettes est masquée (condition images.length > 1)
- `(composant partagé) <ProductImageGallery` — ÉTAT SÉLECTION — vignette active mise en évidence par bordure bleue + ring
- `(composant partagé) <ProductImageGallery` — ÉTAT COPIÉ — icône Copy remplacée par Check pendant exactement 2000 ms (setTimeout non nettoyé au démontage)
- `(composant partagé) <ProductImageGallery` — AUCUN état loading/skeleton, AUCUN état error, AUCUN état disabled, AUCUN état unauthorized
- `(composant partagé) <ConfirmDeleteDialog` — IDLE : bouton submit disabled tant que le champ mot de passe est vide
- `(composant partagé) <ConfirmDeleteDialog` — LOADING : input disabled, bouton Annuler disabled, bouton submit disabled + spinner Loader2 + libellé 'Suppression...', fermeture du modal verrouillée
- `(composant partagé) <ConfirmDeleteDialog` — ERROR : message rouge sous le champ, modal maintenu ouvert, saisie conservée
- `(composant partagé) <ConfirmDeleteDialog` — SUCCESS : fermeture automatique + reset du champ (feedback textuel délégué au parent)
- `(composant partagé) <ConfirmDeleteDialog` — Pas d'état empty/unauthorized (le composant n'est monté que quand la cible existe)
- `(composant partagé) <AIAnalysis /> — car` — IDLE (aucune analyse, pas de chargement) : uniquement le bouton 'Générer l'analyse'
- `(composant partagé) <AIAnalysis /> — car` — LOADING (skeleton) : phrase d'attente text-xs text-muted-foreground mb-1 'Génération en cours (modèle IA local — cela peut prendre plusieurs minutes)...' + 4 <Skeleton> h-4 de largeurs w-full, w-[90%], w-[80%], w-[85%]
- `(composant partagé) <AIAnalysis /> — car` — SUCCESS : texte de l'analyse en gris foncé + bouton 'Régénérer'
- `(composant partagé) <AIAnalysis /> — car` — ERROR HTTP (res.ok === false) : même mise en page que success mais texte en rouge (le contenu affiché est le message d'erreur renvoyé par la route)
- `(composant partagé) <AIAnalysis /> — car` — ERROR RÉSEAU (throw du fetch) : console.error + analysis = 'Erreur réseau lors de l'appel à l'analyse IA.' + error = true (affiché en rouge)
- `(composant partagé) <AIAnalysis /> — car` — Un nouveau clic sur 'Régénérer' remet error à false et loading à true avant de relancer
- `(composant partagé) <AIAnalysis /> — car` — Pas d'état empty distinct (l'état idle joue ce rôle), pas d'état unauthorized
- `POST /api/ai/analyze — route API Next.js` — SUCCÈS : statut 200 avec le texte nettoyé
- `POST /api/ai/analyze — route API Next.js` — ERREUR TIMEOUT (error.name === 'TimeoutError') : hint = 'Le modèle a mis trop de temps à répondre (délai dépassé).'
- `POST /api/ai/analyze — route API Next.js` — ERREUR AUTRE (Ollama injoignable, 4xx/5xx, JSON invalide...) : hint = `Impossible de contacter Ollama sur {OLLAMA_BASE_URL}. Vérifiez qu'Ollama tourne sur le VPS et que OLLAMA_BASE_URL est bien configuré (voir roadmap.md).` — l'URL interne du VPS FUIT donc dans la réponse envoyée au navigateur
- `POST /api/ai/analyze — route API Next.js` — Toute erreur est aussi console.error("Erreur lors de l'analyse IA (Ollama) :", error) côté serveur
- `POST /api/ai/analyze — route API Next.js` — Le client (<AIAnalysis/>) affiche indistinctement le champ `analysis` dans les deux cas, en rouge quand le statut n'est pas ok
- `POST /api/ai/check-duplicates — route AP` — ENTRÉE VIDE : réponse instantanée { warnings: [] } (côté /products cela correspond à aiStatus='skipped' -> texte 'Aucune nouvelle référence à vérifier.')
- `POST /api/ai/check-duplicates — route AP` — EN COURS côté client : aiStatus='loading' -> 'Analyse en cours…' (text-muted-foreground) dans le dialog de revue
- `POST /api/ai/check-duplicates — route AP` — TERMINÉ SANS ALERTE : aiStatus='done' + aiWarnings vide -> 'Aucun doublon suspect détecté.'
- `POST /api/ai/check-duplicates — route AP` — TERMINÉ AVEC ALERTES : liste <ul> d'items « "{nouvelle}" ressemble à "{ressemble_a}" — {raison} » (les noms en font-medium, la raison en suffixe seulement si non vide)
- `POST /api/ai/check-duplicates — route AP` — OLLAMA INDISPONIBLE / .catch() côté client : aiStatus passe quand même à 'done' (avec aiWarnings inchangé/vide) — la vérification est simplement marquée non concluante, l'import reste valide
- `POST /api/ai/check-duplicates — route AP` — Log serveur en cas d'échec : console.error('Erreur lors de la revue IA des doublons (Ollama) :', error)
- `(module partagé) lib/image-service.ts — ` — Aucun état UI (module non-React) : uniquement des promesses résolues/rejetées et des booléens de validation.
- `(module partagé) lib/image-service.ts — ` — Messages d'erreur (tous en anglais) : 'Failed to process image', 'Failed to read image file', 'Failed to upload image', 'Failed to upload image to backend storage', 'Failed to load image', 'Failed to delete image', `File size exceeds ${maxSizeMB}MB limit`, 'File format not supported. Use JPEG, PNG, or WebP'.
- `(module partagé) lib/qrcode-generator.ts` — Promesses résolues (data URL) ou rejetées avec le message 'Failed to generate QR code'.
- `(module partagé) lib/qrcode-generator.ts` — parseQRCodeData ne rejette jamais : fallback { raw }.
- `(hook partagé) lib/hooks/useDeliveryZone` — LOADING : true au montage et à chaque refetch (aucun consommateur de /orders n'exploite ce flag — ils ne déstructurent que `{ zones }`)
- `(hook partagé) lib/hooks/useDeliveryZone` — SUCCÈS : tableau de zones
- `(hook partagé) lib/hooks/useDeliveryZone` — ERREUR : tableau vide, indistinguable de l'état vide
- `(hook partagé) lib/hooks/useDeliveryZone` — Aucun état unauthorized géré (un 401/403 tombe dans le même catch silencieux)
- `(hook partagé) lib/hooks/useDebouncedVal` — Aucun état UI exposé : le hook ne renvoie qu'une valeur. Il n'existe donc AUCUN indicateur visuel « recherche en attente » pendant les 250 ms de latence.

### Groupe `api-client`

- `(couche transport) DjangoAPIClient — coe` — Loading : aucun (la classe est bas niveau, l'etat de chargement est gere par les hooks/pages appelants)
- `(couche transport) DjangoAPIClient — coe` — Erreur : toujours une Error JS avec un message deja lisible en francais quand le backend le fournit (error.detail) — a mapper sur une exception Dart typee
- `(couche transport) DjangoAPIClient — coe` — Unauthorized : 401 -> refresh transparent ; echec du refresh -> purge des tokens + redirection dure vers /login (en Flutter : navigation vers l'ecran de connexion + purge du storage)
- `(couche transport) DjangoAPIClient — coe` — Succes vide : 204/205 et corps vide normalises en `undefined` (important pour DELETE et pour caisse.current)
- `djangoClient.auth — authentification, in` — Non authentifie : isAuthenticated() false -> les hooks n'appellent meme pas /users/me/
- `djangoClient.auth — authentification, in` — Compte non confirme : is_confirmed/is_approved false -> useAuth expose isPendingApproval = !!user && !user.is_approved (ecran 'en attente d'approbation')
- `djangoClient.auth — authentification, in` — Erreur de connexion : useAuth stocke error = message de l'exception, et remet user a null
- `djangoClient.auth — authentification, in` — Chargement : useAuth gere isLoading (true au montage, true pendant login/register, false en finally)
- `djangoClient.passwordResetRequests — mod` — Aucun etat gere ici : liste brute, la page appelante gere loading/empty/erreur
- `djangoClient.catalog.importBatches — Ann` — Retour {status} a afficher en toast de succes ; l'erreur remonte en Error avec le message backend
- `djangoClient.orders — Module Commandes (` — Le champ de statut courant s'appelle `statut_courant` cote objet commande (voir le service sales qui filtre sur statut_courant === 'LIVRE')
- `djangoClient.orders — Module Commandes (` — Les 6+2 statuts utilises dans l'app : NOUVELLE, EN_PREPARATION, PRETE, EN_LIVRAISON, LIVRE, RETOUR, ANNULEE
- `djangoClient.orders — Module Commandes (` — Une commande a un historique de statuts (modele WebSocket 'order_status_history')
- `djangoClient.orders — Module Commandes (` — Un refus de transition arrive en erreur backend avec message lisible (ex. jour J non atteint)
- `djangoClient.zones — Zones de livraison ` — loading : true pendant le fetch du hook
- `djangoClient.zones — Zones de livraison ` — erreur : silencieuse — la liste retombe a [] (pas de toast). A reproduire ou ameliorer en Flutter
- `djangoClient.notifications — Notificatio` — Badge de statut socket : connecte (emeraude), connexion en cours (ambre), deconnecte (rose) — classes dans notifications-utils.tsx::getSocketStatusBadgeClass
- `djangoClient.notifications — Notificatio` — Carte de notification : non lue = fond primary/5, bordure primary/30, ombre ; lue = fond muted/40, bordure neutre (getNotificationCardClass)
- `djangoClient.dashboard — Indicateurs gen` — Listes absentes normalisees en [] (|| []) — l'etat vide est donc naturel
- `djangoClient.dashboard — Indicateurs gen` — kpis peut etre undefined si la reponse ne le contient pas (aucune protection)
- `djangoClient.caisse — Sessions de caisse` — Aucune session ouverte : current() retourne null -> ecran 'caisse fermee' avec bouton Ouvrir
- `djangoClient.caisse — Sessions de caisse` — Session ouverte : afficher solde courant, mouvements du jour et bouton Fermer
- `djangoClient.caisse — Sessions de caisse` — Les evenements WebSocket 'caisse_session' et 'caisse_movement' declenchent un rafraichissement automatique

## 6. Regles metier, permissions et pieges

Notes relevees par les auditeurs — a respecter imperativement dans le portage.

### Groupe `orders`

TRANSITIONS DE STATUT (source de verite backend orders/services.py::TRANSITIONS, reproduite fidelement par gerantActionOptions/nextAction) : EN_PREPARATION vient uniquement de NOUVELLE (role PREPARATEUR) ; PRETE uniquement de EN_PREPARATION (PREPARATEUR) ; EN_LIVRAISON uniquement de PRETE (LIVREUR) ; LIVRE et RETOUR uniquement de EN_LIVRAISON (LIVREUR). Le gerant peut jouer n'importe lequel de ces roles mais JAMAIS sauter une etape ni revenir en arriere. Les statuts LIVRE / RETOUR / ANNULEE sont terminaux : aucune action n'est plus proposee.

CAS SPECIAL RECUPERATION (retrait sur place) : livraison_zone === 'RECUPERATION' est une valeur litterale ajoutee cote client par buildZoneOptions, elle n'existe pas dans la table des zones. Frais = 0, pas de livreur, pas d'adresse, pas de note livreur (les deux sont forcees a '' a l'envoi), pas de choix de paiement affiche. Depuis PRETE, le gerant SEUL peut passer directement a LIVRE ('Recuperee par le client') — le backend court-circuite la table TRANSITIONS pour ce cas et refuse (PermissionDenied) si l'appelant n'est pas gerant.

REGLE 'JOUR J' : date_commande porte la date de LIVRAISON PREVUE (pas la date de creation, qui est created_at). isJourJ(date) = appDayKey(date) <= appToday(), compare en jour calendaire d'Antananarivo. Un preparateur/livreur VOIT ses commandes futures (planning) mais toutes ses actions sont disabled avec le libelle 'Disponible le JJ/MM/AAAA'. Le gerant n'est jamais bloque (le backend ne verifie le jour J que si role != GERANT). Le fuseau est critique : entre 00h et 03h heure Antananarivo, un appareil/serveur en UTC est encore la veille — d'ou lib/timezone.ts qui force Indian/Antananarivo partout, y compris dans les valeurs par defaut des champs datetime.

VISIBILITE DES COMMANDES (backend, invisible dans le code de la page mais determinant pour le portage) : un PREPARATEUR ne voit que les commandes ou preparateur == lui, aux statuts NOUVELLE/EN_PREPARATION, PLUS ses recuperations sur place deja PRETE. Un LIVREUR ne voit que les commandes ou livreur == lui, aux statuts EN_PREPARATION (visibilite planning, non actionnable) / PRETE / EN_LIVRAISON, en excluant les PRETE de zone RECUPERATION. Une commande non encore assignee est donc INVISIBLE pour eux : c'est le gerant qui declenche l'apparition en assignant. En mode historique=1, la restriction de statut saute et ils voient tout leur passe, trie par -date_commande.

VERROU D'ASSIGNATION : une fois assignee, seule la personne designee (ou le gerant) peut faire progresser la commande (PermissionDenied 'Cette commande est assignee a un autre preparateur/livreur'). Cote page, cela ne se manifeste que par un toast d'erreur au clic.

PRE-ASSIGNATION SANS CHANGEMENT DE STATUT : assign-preparateur / assign-livreur sont des endpoints independants du statut. Assigner un preparateur a la creation ou a l'edition NE FAIT PAS passer la commande en EN_PREPARATION : elle reste NOUVELLE jusqu'a ce que le preparateur clique lui-meme 'Commencer la preparation'. Le livreur pre-assigne est reutilise automatiquement au passage EN_LIVRAISON. En revanche, passer par le dialogue 'Assigner un preparateur/livreur' du tableau appelle POST /status/ avec preparateur_id/livreur_id : la, le statut CHANGE immediatement (EN_PREPARATION ou EN_LIVRAISON). Deux chemins d'assignation aux effets differents — piege majeur pour le portage.

assigned_at : le dialogue d'assignation permet de consigner une heure MANUELLE (passee) pour l'entree d'historique ; envoyee en ISO, elle remplace le timestamp de l'OrderStatusHistory. Champ vide = maintenant.

DROITS D'EDITION/SUPPRESSION : canEdit = gerant + statut ∈ {NOUVELLE, EN_PREPARATION} (deliberement elargi a EN_PREPARATION parce qu'une commande assignee des la creation part quasi immediatement en preparation) ; canDelete = gerant + statut === NOUVELLE strictement ; canCancel = gerant + statut ∉ {LIVRE, RETOUR, ANNULEE}. Le texte de description du dialogue d'edition dit encore 'Possible tant que la commande n'est pas encore \"Prete\"' — incoherent avec canEdit, a ne pas prendre pour la regle. Cote serveur, patch/delete sont sous IsGerant.

STOCK : le stock sort du magasin au passage EN_PREPARATION (mouvement SORTIE, origine PREPARATION), pas a la livraison. Un RETOUR le restitue. LIVRE ne touche plus au stock. L'annulation restitue le stock deja deduit — d'ou la phrase conditionnelle du dialogue d'annulation, affichee uniquement pour les statuts EN_PREPARATION/PRETE/EN_LIVRAISON.

DISPONIBILITE DU STAFF : available-staff renvoie un champ `available` (un preparateur ne prepare qu'une commande a la fois, un livreur n'en livre qu'une a la fois ; pour le livreur, `date_commande` signale en plus un conflit d'horaire). MAIS la page ne l'utilise NULLE PART : aucun filtrage, aucun grisage, aucun badge. Tous les membres du staff sont selectionnables meme s'ils sont occupes — le commentaire du code ('seuls ceux libres sont selectionnables') est faux. A decider explicitement lors du portage Flutter.

CALCULS : total affiche a la creation = somme(prix_vente * quantite) + frais de la zone selectionnee. Dans le dialogue de confirmation, le 'Prix de vente' est recalcule par soustraction (total_a_payer - frais_livraison) et n'est affiche que si zone != RECUPERATION et frais_livraison != null. fmt() arrondit systematiquement (Math.round) avant formatage.

PAIEMENT : deux modes seulement, AVANT ('Paye') et LIVRAISON ('Paiement a la livraison'), defaut LIVRAISON. Un mode AVANT masque tout montant au livreur (tableau, confirmation) et fait disparaitre la ligne 'Total a payer' du dialogue de detail POUR TOUS LES ROLES (y compris le gerant) — c'est probablement plus large que voulu, mais c'est le comportement actuel a reproduire ou a corriger sciemment.

TELEPHONE : validation stricte /^\\+261\\d{9}$/ (indicatif Madagascar + 9 chiffres), champ pre-rempli a '+261' a la creation, aucune normalisation automatique (un numero saisi '0340000000' est rejete).

FILTRES SERVEUR vs CLIENT : tous les filtres date/statut/preparateur partent au serveur et declenchent un refetch ; en revanche 'Pas encore livree' (NON_LIVREE), la segmentation A preparer/Recuperations du preparateur et la recherche texte sont purement CLIENT-side sur le resultat deja recu. Consequence : la recherche ne trouve jamais une commande absente du lot renvoye par les filtres serveur en cours.

CODE MORT / INCOHERENCES a ne pas reproduire betement : (1) la condition du bouton 'Retour' de ligne est `(isLivreur || isGerant) && statut==='EN_LIVRAISON' && !isGerant`, donc reservee au livreur ; (2) dans la branche `!isGerant && action`, le handler teste `if (isGerant && action.assign)` — inatteignable ; (3) le Select 'Preparateur' du filtre gerant n'a pas d'option 'Tous' ; (4) le titre du dialogue de creation reste 'Nouvelle commande' meme quand le preparateur cree une recuperation ; (5) useDeliveryZones est appele 3 fois (page + 2 dialogues) = 3 requetes ; (6) dans EditOrderDialog les articles existants sont charges avec stock_actuel=Infinity, donc leur quantite echappe au controle de stock cote client.

FUSEAU DES FILTRES HISTORIQUE : historiqueFrom/To sont convertis avec `new Date(value).toISOString()` (donc interpretes dans le fuseau DE L'APPAREIL), alors que le reste de la page utilise appDatetimeLocalToIso (fuseau Antananarivo). Decalage possible sur un appareil hors UTC+3 — a harmoniser cote Flutter.

ZONES DE LIVRAISON : configurables dans Parametres (CRUD nom+prix, reserve au gerant). Une zone utilisee par des commandes n'est pas supprimee mais desactivee (actif=false) : elle disparait des nouveaux choix mais reste resolue pour les commandes existantes — d'ou les fallbacks `?.label.split(' (')[0] || order.livraison_zone` un peu partout. Une societe sans zone recoit 4 zones par defaut a la premiere lecture (Zone gratuite 0, Zone 1 3000, Zone 2 4000, Zone 3 5000).

### Groupe `products`

RÈGLES MÉTIER ET PIÈGES À REPRODUIRE EN FLUTTER :

1. HIÉRARCHIE CATALOGUE — Catégorie -> Sous-type (Type, porte le champ `category`) -> Marque -> Référence -> Variante (couleur). La ProductReference N'A PAS de champ `category` en écriture : elle ne porte que `type` (id) et `category_name` en lecture. Le filtre par catégorie est donc reconstruit côté client via une map typeToCategory { String(type.id) -> String(type.category) }. À reproduire tel quel.

2. FLAG `avec_couleurs` DE LA CATÉGORIE — Convention `avec_couleurs !== false` (donc undefined/null = true). Si une catégorie est marquée « sans couleurs » (chargeur, écouteur…), le formulaire de création n'affiche PAS la liste de variantes mais un unique couple Quantité/Seuil, et crée automatiquement UNE variante nommée littéralement « Standard ». Ce comportement n'existe QUE dans CreateReferenceDialog : le dialog de détail affiche toujours la gestion multi-couleurs, y compris pour une catégorie sans couleurs.

3. DEUX SYSTÈMES DE SEUIL COEXISTENT — (a) le badge de STATUT de ligne utilise les flags serveur is_rupture / is_stock_bas de chaque variante (donc le seuil_alerte réel) ; (b) les badges de la colonne « Variantes » utilisent des seuils FIXES codés en dur (<=0 rouge, <=2 bleu, >=3 vert) indépendants du seuil_alerte. Une variante peut donc être verte dans la colonne Variantes et la ligne afficher « Stock bas ». C'est intentionnel (commentaire en haut du fichier), mais la « légende dans l'entête du tableau » mentionnée dans le commentaire N'EST PAS implémentée.

4. IMPORT EXCEL EN DEUX TEMPS TROMPEURS — L'import est DÉJÀ écrit en base quand le dialog de revue s'affiche. « Enregistrer » et « Modifier » ne font AUCUN appel réseau (Modifier ne fait que pré-remplir la recherche). Seul « Annuler l'import » appelle POST /catalog/import-batches/{batchId}/cancel/ pour défaire créations et mises à jour. Si batchId est null, « Annuler » ferme simplement le dialog sans rien faire. Le fichier retourné est retéléchargé automatiquement pour permettre une reprise (les lignes portant déjà un Statut sont sautées côté serveur, d'où skipped_count).

5. STATISTIQUES D'IMPORT PAR EN-TÊTES HTTP — Le corps de la réponse d'import est un blob ; toutes les métriques transitent par des en-têtes X-Import-* (dont deux JSON : X-Import-New-Reference-Names et X-Import-Updated-Reference-Names). Il faut que ces en-têtes soient exposés par CORS. En Flutter, lire les headers de la réponse binaire.

6. VÉRIFICATION IA NON BLOQUANTE — L'appel /api/ai/check-duplicates est un fire-and-forget qui met à jour l'état SEULEMENT si le batchId courant correspond toujours (protection contre un second import lancé entre-temps). Un échec réseau n'affiche aucune erreur, il passe juste aiStatus à 'done'. Le timeout Ollama est de 10 minutes.

7. PHOTO EN DEUX APPELS — Créer/modifier une référence se fait en JSON (POST/PUT), puis la photo est envoyée dans un SECOND appel PATCH multipart sur /catalog/references/{id}/. Si le PATCH photo échoue après un PUT réussi, l'utilisateur voit une erreur alors que le reste est enregistré.

8. CRÉATION DE RÉFÉRENCE NON ATOMIQUE — Les variantes sont créées dans une boucle `for … await` après la création de la référence. Si la 2e variante échoue, la référence et la 1re variante restent en base, et l'utilisateur ne voit qu'un toast d'erreur générique.

9. VARIANTE IDENTIFIÉE PAR NOM DE COULEUR — Les selects manipulent l'id de la Color, mais l'API variants attend `couleur` = le NOM (string). La liste des couleurs proposées dans le détail est filtrée pour exclure les noms déjà utilisés par la référence (usedColors) — dans CreateReferenceDialog en revanche TOUTES les couleurs sont proposées, le doublon étant bloqué localement par un toast.

10. ÉTAT PÉRIMÉ DU DIALOG DE DÉTAIL (bug à connaître) — `variantsOf` conserve l'OBJET de référence capturé au clic. Les callbacks onChanged appellent fetchAll(true) qui remplace le tableau `references` par de nouveaux objets, mais `variantsOf` continue de pointer sur l'ancien. Résultat : après avoir ajouté/supprimé une variante ou ajusté un stock, la liste des variantes affichée DANS le dialog ouvert ne se met pas à jour tant qu'on ne le referme/rouvre pas. En Flutter, préférer relire la référence par son id depuis la liste rafraîchie.

11. RESET INTEMPESTIF DU FORMULAIRE DE DÉTAIL — Le useEffect de pré-remplissage dépend de `[reference, types]`. Comme `types` est un NOUVEAU tableau à chaque fetchAll (y compris les refetch temps réel silencieux), une notification WebSocket pendant l'édition réinitialise le formulaire et fait perdre les modifications non enregistrées.

12. GATING PUREMENT COSMÉTIQUE — Aucune garde de route, aucun écran 403. Le préparateur voit la page en lecture seule ; le livreur n'a que l'entrée de menu masquée. La sécurité réelle repose entièrement sur l'API Django. En Flutter, décider s'il faut durcir (redirection) ou reproduire à l'identique.

13. PRIX MASQUÉS PAR RÔLE — `prix_achat` et la marge ne sont JAMAIS affichés à un non-gérant (colonnes ET champ du formulaire retirés du DOM, pas seulement disabled). Dans le panier de commande, `showPrices = !isPreparateur` masque prix unitaire, totaux de ligne, frais de livraison et total à payer.

14. ZONES DE LIVRAISON CODÉES EN DUR ICI — Constante locale ZONES : ZONE1 = 3 000 Ar, ZONE2 = 4 000 Ar, ZONE3 = 5 000 Ar, RECUPERATION = 0 Ar. Le total affiché = somme des lignes + frais de zone. ATTENTION : le commentaire de djangoClient.orders.create indique que `livraison_zone` est le `code` d'une zone paramétrable (orders/models.py::DeliveryZoneOption) — cette page ne consomme donc PAS les zones dynamiques, contrairement au module Commandes. Divergence à trancher lors du portage.

15. RÈGLES DE LA COMMANDE — Choisir « Récupération sur place » (zone RECUPERATION) masque zone/adresse/mode de paiement/note livreur ET force note_livreur à '' à l'envoi. Choisir « À livrer » force la zone à ZONE1. Le téléphone doit strictement matcher /^\+261\d{9}$/ (préfixe +261 pré-rempli, exactement 9 chiffres après). date_commande vide = maintenant côté serveur ; sinon converti en ISO. Les deux assignations (préparateur, livreur) sont des appels SÉPARÉS post-création, tolérants aux erreurs : la commande existe même si l'assignation échoue.

16. PRÉ-ASSIGNATION SANS CHANGEMENT DE STATUT — assign-preparateur et assign-livreur ne font PAS progresser le statut : la commande reste « Nouvelle » jusqu'à ce que le préparateur clique lui-même « Commencer la préparation » ; le livreur pré-assigné est réutilisé automatiquement au passage « En livraison ».

17. CONFLIT D'HORAIRE LIVREUR NON AFFICHÉ — GET /orders/available-staff/?role=LIVREUR&date_commande=<ISO> renvoie un champ `available` signalant un conflit avec une autre commande du même créneau, et la liste est refetchée à chaque changement de date/heure — mais cette page N'AFFICHE PAS l'indicateur (elle ne montre que full_name). À reproduire ou à corriger sciemment.

18. CONTRÔLE DE STOCK DU PANIER PARTIEL — La quantité est validée ligne à ligne contre variant.stock_actuel, mais rien n'empêche d'ajouter DEUX lignes de la même variante ; leur somme peut dépasser le stock disponible. Aucune fusion des lignes identiques (clé unique `${variantId}-${Date.now()}`). Les options de couleur à stock <= 0 sont désactivées dans le select.

19. LE BLOC ProductCreateOrderDialog CONTIENT DU CODE MORT SUR CETTE PAGE — Il gère la branche `isPreparateur` (zone forcée à RECUPERATION, notes simplifiées, pas de préparateur/livreur, prix masqués), or le dialog n'est monté que si isGerant. Ce code est un miroir du module Commandes ; le porter tel quel si le composant doit être réutilisé.

20. SUPPRESSIONS EN CASCADE ET SANS CONFIRMATION — Supprimer une référence supprime toutes ses variantes ; supprimer une variante supprime son historique de stock (ces deux-là ont une confirmation). En revanche marques, couleurs, catégories et sous-types se suppriment SANS confirmation au premier clic — l'échec serveur (dépendances) est simplement traduit par un message par défaut : « Suppression impossible (marque utilisée par des références) », « (des sous-types en dépendent encore) », « (des références en dépendent encore) ».

21. MODIFICATION GROUPÉE IRRÉVERSIBLE — bulk-update-price s'applique à TOUTES les références du sous-type, toutes marques confondues ; un prix laissé vide n'est pas envoyé (donc inchangé) ; le nombre de références impactées est calculé côté client à partir de la liste déjà chargée (peut diverger de la réalité serveur si la liste est périmée).

22. `actif` — Le toggle Active/Inactive n'existe que dans le dialog de détail (pas à la création, où la référence est créée active par défaut côté serveur). Sémantique : « Inactive = invisible dans la recherche de commande » (donc filtrée par l'endpoint autocomplete), mais la référence reste visible dans le tableau du catalogue, sans aucun indicateur visuel de son inactivité dans la liste.

23. AJUSTEMENT DE STOCK — Réservé au gérant (§7.4). Quantité entière >= 1 obligatoire, type ENTREE ou SORTIE, note libre optionnelle. Aucun contrôle client que la SORTIE ne dépasse le stock : c'est le serveur qui refuse. Le mouvement déclenche un événement WebSocket 'stock_movement' qui rafraîchit la page de tous les postes connectés.

24. PERFORMANCE — Le tableau rend toutes les références sans virtualisation ni pagination, avec un Badge par variante. Sur un gros catalogue, prévoir en Flutter une ListView.builder + éventuellement une pagination côté API, en gardant à l'esprit que le filtrage actuel suppose l'intégralité des données en mémoire."

### Groupe `movements`

REGLES METIER ET PIEGES A REPRODUIRE (ou a corriger) EN FLUTTER

1) DEUX SYSTEMES DE FILTRES DE DATE INDEPENDANTS. startDate/endDate pilotent le tableau principal, les 3 KPI et le regroupement par jour. statsStartDate/statsEndDate pilotent UNIQUEMENT les deux cartes de statistiques. La recherche texte n'affecte PAS les statistiques. Le bouton 'Reinitialiser' ne remet a zero que les dates stats.

2) LE CALENDRIER 'Filtrer par jour' EST UN RACCOURCI SUR LE FILTRE TABLEAU. Choisir un jour ecrit la meme valeur dans startDate ET endDate. Consequence en cascade: le tableau principal et les KPI se reduisent a ce jour, ET DailyMovementsTable passe en hideToday=false. Sans selection de jour, hideToday=true et la journee EN COURS est volontairement masquee du bloc 'Mouvements par jour' (elle reste visible dans le tableau principal). C'est la regle 'jour J' cachee de la page.

3) LA JOURNEE 'AUJOURD'HUI' EST CALCULEE EN UTC: today = new Date().toISOString().split('T')[0], et les cles de groupe aussi (new Date(created_at).toISOString().split('T')[0]). Les filtres de plage, eux, comparent la chaine ISO brute (created_at.split('T')[0]) — egalement UTC. MAIS le calendrier ecrit une date LOCALE (toDateInputValue). A Madagascar (UTC+3) un mouvement enregistre entre 00:00 et 03:00 heure locale tombe la veille en UTC => decalage d'un jour possible entre ce qu'on selectionne et ce qu'on voit. La fonction label() de DailyMovementsTable compare, elle, en heure locale (new Date(dateKey) parse la date pure comme minuit UTC puis compare aux composantes locales) => 'Hier' peut se decaler. En Flutter, unifier sur l'heure locale.

4) CHAMPS FANTOMES — le mapper djangoClient.movements.list() NE PRODUIT PAS: magasin_name, changed_by_username, previous_quantity, new_quantity, et le serializer backend ne les expose pas non plus. En consequence, dans l'app actuelle: (a) la colonne 'Magasin' reservee aux managers affiche TOUJOURS '-', (b) la sous-ligne email sous 'Fait par'/'Utilisateur' ne s'affiche JAMAIS, (c) la recherche sur changed_by_username et magasin_name est morte, (d) les colonnes Excel 'Stock avant', 'Stock apres' et 'Email'/'Magasin' sortent vides. Pour le portage Flutter: soit enrichir l'API (ajouter magasin_name, user.email, stock avant/apres), soit supprimer ces colonnes.

5) BUG DE JOINTURE MARQUE/CATEGORIE. productsById est indexe par p.id = ID DE ProductReference, alors que m.product = m.product_variant = ID DE ProductVariant. La sous-ligne '{marque} · {categorie}' du tableau principal ne s'affiche donc que par collision fortuite d'identifiants. Pour Flutter, il faut soit renvoyer brand_name/category_name dans le serializer de mouvement, soit indexer par variant id.

6) COMPARAISON PAR NOM DANS 'Produits sans mouvement'. On compare products[].name (= reference_name pur) a movements[].product_name qui vaut reference_name + ' (couleur)' des que couleur !== 'Standard'. Resultat: presque toutes les references a couleurs apparaissent a tort comme 'sans mouvement'. De plus le slice(0,5) est applique AVANT tout tri, donc ce sont simplement les 5 premieres references renvoyees par l'API, pas les 5 plus dormantes. Le calcul ne prend pas non plus en compte la date de creation du produit.

7) 'Produits les plus vendus' n'est pas 'vendus' au sens strict: c'est la somme de |change| de TOUS les mouvements a change<0 (donc PREPARATION mais aussi tout futur mouvement negatif), groupee par product_name (fallback 'Produit inconnu'), triee desc, top 5. Une commande annulee ou retournee (change>0) ne vient pas deduire ce total.

8) SIGNE DU MOUVEMENT: change = (type === 'SORTIE' ? -quantite : quantite) cote client; quantite est un PositiveIntegerField cote modele. Donc change === 0 est theoriquement impossible (le badge orange 'change === 0' est du code defensif). De meme, movement_type est toujours renseigne (fallback = origine brute), donc le libelle par defaut 'Mise a jour' n'apparait jamais.

9) TYPES DE MOUVEMENT REELS (catalog/models.py ORIGINE_CHOICES): PREPARATION, RETOUR, ANNULATION, FOURNISSEUR, AJUSTEMENT — cinq valeurs seulement. Le libelle 'Commande livree' (origine LIVRE, badge indigo) et la branche 'Transfert' (badge bleu de getChangeBadgeClass) sont du CODE MORT: aucune de ces deux valeurs ne peut arriver du backend actuel. A conserver ou nettoyer selon la roadmap.

10) QUI CREE LES MOUVEMENTS (traçabilite §10): point d'ecriture UNIQUE = catalog/services.py::apply_stock_movement, transactionnel avec select_for_update sur la variante. Producteurs reels: orders/services.py => PREPARATION (sortie a la preparation), RETOUR (entree au retour), ANNULATION (entree a l'annulation), plus deux AJUSTEMENT lies au numero de commande; suppliers/services.py => FOURNISSEUR (reception); catalog/views.py => AJUSTEMENT (ajustement manuel du gerant, et import Excel avec note 'Import Excel'). L'annulation d'un import Excel SUPPRIME physiquement les StockMovement correspondants (revert_import_batch) — l'historique n'est donc pas strictement immuable.

11) SCOPING MULTI-MAGASIN: l'endpoint filtre par product_variant__product_reference__type__category__magasin ∈ get_accessible_magasins(user). Un admin (proprietaire OU co-admin) voit TOUS les magasins de sa societe — c'est precisement pourquoi la colonne 'Magasin' est prevue pour isManager — un compte 'magasin' ne voit que le sien, un 'employer' que celui de son affectation. La distinction isCompanyOwner (admin proprietaire) n'est pas utilisee sur cette page.

12) PERMISSIONS DE LA PAGE, RESUME POUR FLUTTER: acces = tout utilisateur authentifie (aucun blocage serveur ni client par role); lien de menu = GERANT seulement (admin ou magasin); colonne Magasin = GERANT (isManager); export XLSX = ADMIN uniquement (isAdmin — un compte 'magasin' ne l'a PAS, alors qu'il voit la colonne Magasin). Si l'app Flutter doit etre stricte, il faut ajouter un vrai guard de route pour PREPARATEUR/LIVREUR.

13) PERFORMANCE: aucune pagination cote API ni cote UI; la page charge l'integralite de l'historique + l'integralite du catalogue a chaque montage et a chaque evenement WebSocket (stock_movement, product_variant, order — trois modeles tres bavards, debounce 400 ms seulement). En Flutter, prevoir de la pagination serveur (?page=, ?date_from=, ?date_to=) plutot que de porter ce filtrage 100% client.

14) GESTION D'ERREUR ABSENTE: le catch de fetchData n'affiche rien (console.error seulement). Un backend down est visuellement identique a 'aucun mouvement'. A corriger dans le portage (etat error + bouton Reessayer).

15) PARSING DES VARIANTES (parseVariantEntries): variant_label est en realite la couleur simple de la variante ('Noir', 'Standard'...). Le parseur prevoit pourtant une liste separee par des virgules avec un pattern '<nom> x<qte>' (regex /^(.*)\s+x(\d+)$/i, insensible a la casse), et applique le SIGNE du mouvement global a chaque quantite parsee (fallbackChange < 0 => -qty). Si aucun 'xN' n'est trouve, la quantite affichee est le change global du mouvement. En pratique, avec l'API actuelle il n'y a donc toujours qu'UNE entree et le HoverCard '{n} variantes' ne se declenche jamais — c'est une anticipation de mouvements multi-variantes.

16) EXPORT EXCEL: purement client (lib 'xlsx'), il n'exporte QUE filteredMovements (recherche + plage de dates du tableau appliquees), pas l'historique complet. Le nom de fichier utilise la date UTC du jour. En Flutter, prevoir un equivalent (excel/syncfusion + partage de fichier) ou basculer sur un export serveur."

### Groupe `chats`

PIEGES ET REGLES METIER (indispensables pour le portage Flutter)

1) LE PARTAGE DE PRODUIT NE FONCTIONNE PAS COTE BACKEND — piege majeur. Le front definit `ChatProductSnapshot` et rend une carte produit dans la bulle, et `handlePickProduct` envoie {content, product_id}. Or: (a) le modele `ChatMessage` (/home/garrix/Dev/Smartphone/users/models.py:330-349) n'a AUCUN champ produit; (b) `ChatConsumer.save_message` (/home/garrix/Dev/Smartphone/users/consumers.py:194-218) ignore totalement `product_id` et ne renvoie pas de cle `product`; (c) `ChatMessageSerializer` (/home/garrix/Dev/Smartphone/users/serializers.py:246-272) n'expose pas `product`. Donc `msg.product` est TOUJOURS undefined -> la carte produit est du code mort. Pire: si l'utilisateur ouvre le popover et choisit un produit SANS avoir tape de texte, le frontend envoie {content:'', product_id:X}; cote serveur `content = data.get("content") or ""` puis `if not content: return` -> AUCUN message n'est cree, mais l'UI ferme le popover et vide le champ: l'action est silencieusement perdue. En Flutter: soit implementer le champ produit cote backend, soit retirer la fonctionnalite, soit au minimum forcer un texte non vide.

2) Le prix affiche dans le selecteur de produit est vide. `mapReferenceToProduct` met `unit_price: null` (le vrai prix est dans `shell_price` = prix_vente); la ligne du popover affiche `Ref. {p.reference} · {p.unit_price} Ar` -> rend 'Ref. XXX ·  Ar'. De plus `reference` et `name` valent tous les deux `reference_name` (information dupliquee).

3) Presence en ligne — regle exacte: le serveur calcule `is_online = last_seen_at && (now - last_seen_at) < 40 secondes` (users/views.py:1923). `last_seen_at` est rafraichi a chaque connexion WS et a CHAQUE trame recue (`ChatConsumer.receive` appelle `touch_last_seen()` avant tout traitement). Le client entretient donc un ping {action:'ping'} toutes les 20 s (< 40 s) et repolle la liste toutes les 20 s. Consequence: un utilisateur n'est 'En ligne' que s'il a la page /chats ouverte (les sockets notifications et data ne touchent PAS last_seen_at). A reproduire tel quel: intervalle ping 20 s, polling liste 20 s, seuil serveur 40 s.

4) `liveActiveRecipient` — subtilite d'etat: `activeRecipient` est l'objet fige au moment du clic; le polling remplace le tableau `users` mais pas `activeRecipient` (sinon l'effet [currentUser, activeTab, activeRecipient] reconnecterait la socket toutes les 20 s et rechargerait l'historique). Le header re-derive donc la presence via `users.find(u => u.id === activeRecipient.id) || activeRecipient`. En Flutter: garder l'identifiant du destinataire et recalculer l'objet a l'affichage.

5) Rooms — noms deterministes cote serveur, le client ne les connait jamais: canal general = `general_<company_id>` (le client n'envoie que `room=general`), DM = `dm_<minUserId>_<maxUserId>`. L'historique general ne remonte que les messages avec `recipient IS NULL` de la room scopee. Historique limite aux 100 DERNIERS messages, sans pagination.

6) Permissions reelles (toutes cote backend, aucune cote page):
   - Le socket chat REFUSE la connexion (close immediat) si: token absent/invalide, l'utilisateur n'appartient a aucun magasin de societe, le destinataire n'existe pas, le destinataire ne partage aucun magasin de la meme societe, ou la paire est bloquee.
   - REGLE METIER: deux LIVREURS ne peuvent pas se contacter (users/permissions.py `chat_blocked_between`: LIVREUR + LIVREUR). Elle s'applique a 3 endroits: la liste de contacts (ils ne se voient pas), l'historique (403 'Deux livreurs ne peuvent pas se contacter entre eux') et la connexion WS (close). Toutes les autres paires (gerant/preparateur/livreur, admin, magasin) sont autorisees.
   - La liste des contacts n'inclut que les utilisateurs `is_confirmed=True`, exclut soi-meme, et couvre les 4 rattachements magasin (magasins M2M, admin_magasin_profiles, magasin_profile, employer_profile.magasin) — les co-admins de la societe sont donc inclus.
   - Le canal General est ouvert en lecture ET ecriture a TOUS les roles de la societe, y compris preparateur et livreur.

7) Edition / suppression — regles serveur: seul l'AUTEUR peut editer ou supprimer, et uniquement un message appartenant a la MEME room que la socket courante. On ne peut PAS editer un message deja supprime. La suppression est logique: `is_deleted=True` et `content=''` (le contenu est perdu en base). L'edition positionne `is_edited=True` + `edited_at`. Il n'existe AUCUN endpoint REST pour editer/supprimer: tout passe par la socket, donc ces actions sont impossibles quand la socket est deconnectee (le code retourne silencieusement, sans message a l'utilisateur — prevoir un toast en Flutter).

8) Accuses de lecture — DM uniquement. Le serveur refuse de marquer quoi que ce soit si `self.recipient` est nul (un message General a plusieurs destinataires, pas de statut 'vu' unique). Le client envoie {action:'read'} (a) a l'ouverture de la socket en mode direct, (b) a chaque message entrant dont `sender !== currentUser.id`. Le serveur marque TOUS les messages non lus, non supprimes, qui me sont adresses dans la room, et diffuse {ids, read_at} au groupe -> l'expediteur voit ses coches passer de Check a CheckCheck en direct. Aucun indicateur 'X non lus' par conversation dans la liste de gauche (a inventer si besoin en Flutter).

9) Pas d'optimistic UI: un message envoye n'apparait qu'apres l'echo serveur (l'expediteur fait partie du groupe channels). Si la socket coupe entre l'envoi et l'echo, le message est perdu de l'affichage (mais peut exister en base). Le garde anti-doublon est `messages.some(m => m.id === id)`.

10) Cycle de vie socket du chat (different des deux autres sockets de l'app): a chaque changement de `activeTab` ou `activeRecipient`, l'effet fait disconnect -> setMessages([]) -> GET historique -> connect. La reconnexion auto se declenche 3 s apres tout `onclose` tant que `socketRef.current === ws` (le disconnect volontaire met la ref a null avant, ce qui neutralise la reconnexion) — noter que, contrairement au hook notifications et a DataSyncContext, le chat ferme SANS code 1000 et ne teste pas `event.code`. Le ping interval est nettoye dans onclose et dans disconnect.

11) Le JWT est passe en query string de l'URL WebSocket (`?token=`). Il est lu une seule fois a la connexion via `djangoClient.getAccessToken()`; il n'y a AUCUNE gestion de refresh pour la socket: si l'access token expire, le serveur refuse la connexion et le client reboucle toutes les 3 s avec le meme token tant qu'un appel REST n'a pas rafraichi le token en localStorage. Point d'attention pour Flutter (rafraichir le token avant de (re)connecter).

12) Chaque ChatMessage cree declenche un signal `post_save` (/home/garrix/Dev/Smartphone/users/signals.py:140-172) qui cree une Notification `notif_type='chat'`: pour un DM -> ciblee sur le destinataire ('Message prive de <nom> : <60 premiers caracteres>'); pour le General -> ciblee sur le MAGASIN de l'expediteur ('Message de <nom> dans General : <60 caracteres>'). Consequence UX: un message General envoye par un gerant/employe genere une notification pour tout son magasin (y compris potentiellement un toast chez l'expediteur), et un message General envoye par un admin a `magasin=None` (donc pas de diffusion magasin). Ces notifications arrivent par la socket /ws/notifications/ et produisent un toast 'Type : Chat' via la cloche de la TopBar.

13) Selection automatique au changement d'onglet: passer sur 'Direct' selectionne `filteredUsers[0]` — donc le PREMIER de la liste FILTREE par la recherche courante (qui reste memorisee meme si le champ n'est pas visible sur l'onglet General). Si la liste est vide, aucun destinataire n'est selectionne et le panneau de droite affiche un header vide (aucune garde `null` autre que le `: null` du ternaire) avec la zone messages en etat vide et la barre de saisie active si la socket est connectee — mais aucune socket n'est ouverte dans ce cas (l'effet ne connecte que si activeRecipient existe), donc les champs restent desactives.

14) Formats et libelles a respecter au mot pres (interface 100 % en francais): 'Messagerie Interne', 'Discussion Generale', 'Canal de diffusion global', 'Tout le personnel de l'entreprise', 'Rechercher un collaborateur...', 'Rechercher un produit...', 'Redigez votre message...', 'Envoyer', 'Aucun message pour le moment', 'Aucun collaborateur trouve', 'Aucun produit trouve', 'Message supprime', 'modifie', 'En ligne' / 'Hors ligne' / 'Vu il y a N min' / 'Connexion...', 'Supprimer ce message ?', 'Administration'.

15) Le chat n'affiche jamais de photo de profil (Avatar sans AvatarImage, uniquement des initiales) alors que `CurrentUser.photo` existe — coherent a conserver ou a ameliorer sciemment.

### Groupe `users`

HIÉRARCHIE DES RÔLES RÉELLE (3 rôles backend seulement) : 'admin' (= Administrateur, aussi appelé SuperAdmin/Gérant selon les alias du hook), 'magasin' (= Gérant de magasin), 'employer' (= Employé / Commercial). Les sous-rôles PREPARATEUR / LIVREUR sont portés par EmployerProfile.commande_role et ne concernent QUE le module Commande — cette page ne les affiche ni ne les modifie (elle ignore le champ commande_role pourtant renvoyé par /users/magasins/users/ pour les employers). Un 4e niveau existe cependant, non pas comme rôle mais comme drapeau : is_company_owner (le FONDATEUR, celui qui possède un AdminProfile) vs co-admin (ajouté via 'Ajouter un administrateur', partage l'accès aux données mais pas la gestion des admins).

RÈGLE DE PROPRIÉTÉ D'ENTREPRISE (la plus subtile de la page, dupliquée front + back) : gérer un compte de rôle 'admin' est réservé au fondateur. Front : `(u.role === 'admin' ? isCompanyOwner : isAdmin)` gouverne l'affichage de 'Modifier rôle' ET 'Supprimer'. Back (RoleManagementView / DeleteUserView / AddAdminView) : 403 'Seul le fondateur de la société peut gérer les administrateurs.' / 'Seul le fondateur de la société peut retirer un administrateur.', et 403 'Action impossible sur le fondateur de la société.' si la cible est elle-même le fondateur. Promouvoir quelqu'un VERS 'admin' est aussi réservé au fondateur (sinon un co-admin contournerait la restriction d'AddAdminView en passant par le changement de rôle).

ON NE PEUT JAMAIS AGIR SUR SOI-MÊME : front `u.id !== currentUser.id` masque les deux boutons sur sa propre ligne ; back renvoie 400 'Vous ne pouvez pas modifier votre propre rôle' et 400 'Vous ne pouvez pas vous supprimer vous-même'.

UN GÉRANT (role 'magasin') QUI ATTEINT LA PAGE PAR URL : il passe la garde isManager, voit les onglets Actifs et En attente (pas l'onglet Réinit.), voit le bouton Ajouter mais ne peut créer QUE des 'employer' (les options magasin/admin sont conditionnées à isAdmin/isCompanyOwner), et ne voit AUCUN bouton Modifier rôle / Supprimer. En revanche les boutons Approuver / Rejeter de l'onglet En attente lui sont affichés sans condition de rôle — c'est le backend qui restreint sa portée aux seuls employés de son propre magasin (403 sinon).

'REJETER' EST UNE SUPPRESSION DÉFINITIVE, PAS UN SIMPLE REFUS : RejectUserView fait user.delete(). Le libellé UI ('Rejeter') et le confirm natif ('Rejeter et supprimer cet utilisateur ?') sont le seul avertissement. À porter avec un AlertDialog explicite en Flutter.

DEUX CHEMINS DE SUPPRESSION AUX EXIGENCES DIFFÉRENTES : rejeter un compte en attente ne demande qu'un confirm() ; supprimer un compte actif exige la re-saisie du mot de passe de l'opérateur (vérifié serveur par check_password, 400 'Mot de passe incorrect.').

L'EMAIL SERT AUSSI DE USERNAME : à la création, `username: newUser.email`. Le contrôle d'unicité porte donc sur les deux champs et le message d'erreur les mentionne tous les deux.

admin_email EST TOUJOURS L'EMAIL DE L'OPÉRATEUR : pour role 'employer' et 'magasin', extraData.admin_email = currentUser?.email || ''. Conséquences côté RegisterSerializer : pour 'magasin' il faut que ce soit un admin, sinon 400 { admin_email: 'Administrateur introuvable avec cet email.' } (donc un gérant ne peut de toute façon pas créer de gérant, ce que l'UI empêche déjà) ; pour 'employer' le serializer cherche d'abord un admin avec cet email, puis à défaut un compte role='magasin' pour rattacher l'employé à son magasin — c'est ce qui fait fonctionner la création d'employé par un gérant.

AUTO-CONFIRMATION CACHÉE : le serializer confirme automatiquement (is_confirmed=True) un compte 'magasin' créé par l'admin authentifié lui-même (auto_confirm = requester_is_authenticated_admin && requester.id == admin.id). Un compte 'admin' créé via /users/add-admin/ est également is_confirmed=True d'emblée. Le toast du front dit pourtant TOUJOURS \"Utilisateur créé en attente d'approbation\" dès que role !== 'admin' — le message peut donc être faux pour un gérant créé par son admin, qui n'apparaîtra jamais dans l'onglet 'En attente'.

BRANCHE D'ERREUR MORTE : handleAddUser inspecte err?.response?.data (convention axios) alors que djangoClient lève des Error nues. Le message spécifique \"Un utilisateur avec ce nom d'utilisateur ou cet email existe déjà.\" n'est donc JAMAIS déclenché en pratique ; on tombe toujours sur err.message, qui contient malgré tout le détail DRF concaténé ('username: ... | email: ...'). En Flutter, mieux vaut détecter 'already exists' directement dans le message d'erreur.

DÉDUPLICATION OBLIGATOIRE CÔTÉ CLIENT : /users/magasins/users/ renvoie, pour CHAQUE magasin, un tableau company_users qui est en réalité la MÊME liste accumulée progressivement côté serveur (la variable company_users est partagée hors de la boucle) — les entrées se répètent donc d'un magasin à l'autre. Le front aplatit via un Set seenUserIds : le premier enregistrement rencontré gagne (manager du magasin, puis employers, puis company_users), ce qui détermine aussi le shop_name affiché pour un utilisateur présent dans plusieurs magasins. Reproduire impérativement cette déduplication en Flutter.

CHAMPS shop_name / magasin_id RECONSTRUITS CÔTÉ CLIENT : addUser fait `shop_name: shopName || user.shop_name || '-'` et `magasin_id: magasinId ?? user.magasin_id ?? null`. Le '-' est donc stocké dans la donnée elle-même, pas seulement à l'affichage.

DÉTECTION 'EN LIGNE' : isCurrentlyOnline(u) = !!u.last_login_at && (!u.last_logout_at || new Date(u.last_logout_at) < new Date(u.last_login_at)). Ces horodatages proviennent du DERNIER LoginEvent de l'utilisateur (created_at / logged_out_at), mémoïsé côté serveur. Un utilisateur qui ferme son navigateur sans se déconnecter reste donc affiché 'En ligne' indéfiniment — c'est un état déclaratif, pas un heartbeat.

LE COMPTEUR DE L'ONGLET 'RÉINIT.' EST TROMPEUR : il compte les 'pending' dans la liste DÉJÀ FILTRÉE par le Select. Si l'utilisateur bascule le filtre sur 'Approuvées', le badge orange disparaît alors que des demandes en attente existent toujours.

ONGLET 'RÉINIT.' — CONTEXTE MÉTIER : il s'agit du back-office du flux 'mot de passe oublié' public. Un gérant ou un employé demande via /users/public/forgot-password/ ; il n'y a AUCUN service d'email dans ce projet, donc aucun lien n'est envoyé — l'admin approuve ici, et le demandeur revient lui-même consulter le statut (/users/public/forgot-password/status/) puis définit son nouveau mot de passe (/users/public/forgot-password/confirm/). La réinitialisation automatique n'existe PAS pour les comptes 'admin' (le backend renvoie : 'La réinitialisation automatique n'est pas disponible pour les comptes administrateur. Contactez le support technique directement.') — c'est pourquoi cet onglet ne contient jamais de demande d'administrateur.

TRANSITION DE STATUT D'UNE DEMANDE DE RÉINIT. : pending -> approved | rejected uniquement, à sens unique et une seule fois (400 'Cette demande a déjà été traitée.' sinon). L'UI n'affiche les boutons que sur status === 'pending', ce qui reflète correctement la règle. La demande n'est jamais supprimée : l'historique reste consultable via les filtres 'Approuvées' / 'Rejetées' / 'Toutes'. Le verrou d'UI resolvingRequestId ne bloque qu'UNE ligne à la fois.

BUG BACKEND CONNU ET DOCUMENTÉ DANS LE CODE (PendingUsersView) : le commentaire indique que le filtre côté admin n'incluait initialement que les employés ; il a été corrigé pour inclure Q(magasin_profile__admin=user), donc les gérants en attente remontent bien. Pour un gérant, seuls les employés de son propre magasin remontent.

DIVERGENCE DE VOCABULAIRE / DE VALEUR À L'ÉCRAN : le toast de succès du changement de rôle affiche la valeur technique ('Rôle mis à jour : magasin') au lieu du libellé traduit — à corriger ou reproduire sciemment en Flutter.

DÉTAILS TECHNIQUES MINEURS À NE PAS RECOPIER AVEUGLÉMENT : colSpan={8} sur la ligne vide d'un tableau à 7 colonnes ; le champ company_name du state newUser n'est jamais utilisé ; l'insertion optimiste après création d'un admin est immédiatement écrasée par le fetchUsers() qui suit ; le bouton 'Annuler' du dialog de rôle ne réinitialise ni editingUserRole ni newRoleValue (sans conséquence puisque le dialog est fermé) ; l'onglet actif n'est pas persisté (retour sur 'actifs' à chaque montage) ; aucun rechargement automatique périodique des données (seul le libellé de temps relatif se rafraîchit toutes les 10 minutes).

### Groupe `caisse-bilan`

REGLES METIER ET PIEGES A REPRODUIRE EN FLUTTER.

CAISSE — permissions
1) Toute la caisse est reservee au GERANT au sens backend: is_gerant = role 'admin' ou 'magasin'. Les endpoints sessions/movements/summary sont [IsAuthenticated, IsGerant]. Seul /users/caisse/categories/ est lisible par tout authentifie (ecriture reservee au gerant). La page web n'a AUCUN garde-fou visuel: prevoir un ecran 'Acces refuse' cote Flutter, sinon un preparateur/livreur verra une page vide et des toasts 403.
2) Resolution du magasin: role 'magasin' -> son propre MagasinProfile; role 'employer' -> le magasin de son EmployerProfile; role 'admin' -> AUCUN magasin propre, il doit envoyer magasin_id (dans le body pour open, en query pour le reste). Cote UI, l'admin n'a rien de preselectionne: tant qu'il n'a pas clique un magasin, la page reste sur l'ecran vide.
3) Scoping serveur (_accessible_magasins): admin -> magasins ou il est admin ou co-admin; magasin -> le sien; employer -> celui de son profil.

CAISSE — cycle de vie d'une session
4) UNE SEULE session 'open' par magasin: POST open renvoie 400 {'error': 'Une session de caisse est deja ouverte pour ce magasin.'} si une session ouverte existe. L'UI masque deja le bouton Ouvrir quand session != null, mais la course est possible en multi-poste.
5) GET sessions/current/ renvoie 204 No Content quand il n'y a pas de session ouverte (DRF ne sait pas serialiser None) — le client transforme en null. En Flutter, traiter 204 + corps vide comme 'pas de session'.
6) Fermeture: closing_balance obligatoire (400 'Montant de fermeture requis.'), montant invalide -> 400 'Montant de fermeture invalide.', session deja fermee -> 400 'Cette session est deja fermee.', closed_at anterieur a opened_at -> 400 'L'heure de fermeture ne peut pas etre avant l'heure d'ouverture.'.
7) Le SOLDE ATTENDU est calcule DEUX FOIS: cote client pour l'affichage (opening_balance + entrees - sorties, a partir de session.movements) et cote serveur a la fermeture (agregation SQL). C'est le serveur qui persiste expected_balance et difference = closing_balance - expected_balance. L'ecart affiche en direct dans le dialog est donc une estimation locale.
8) Backdating autorise: opened_at et closed_at sont optionnels; s'ils sont absents le serveur prend timezone.now(). _parse_custom_datetime refuse un format non ISO 8601 ('… invalide (format attendu : ISO 8601).') et refuse toute date FUTURE ('… ne peut pas etre dans le futur.'). Une valeur naive est rendue aware avec le fuseau serveur (Indian/Antananarivo).
9) Un mouvement ne peut etre cree que sur une session OUVERTE: si la session est fermee -> ValidationError 'Cette session de caisse est fermee.'; si aucune session ouverte n'est resolue -> 'Aucune session de caisse ouverte.'. Le champ `session` envoye par l'UI est optionnel cote serveur (il retomberait sur la session ouverte du magasin resolu).
10) Une CATEGORIE ne s'applique qu'aux SORTIES: le serializer rejette category + movement_type 'in' ('Une categorie ne s'applique qu'aux sorties.'). L'UI masque le select pour 'in' et n'envoie pas la categorie. Attention: l'etat movementCategory n'est pas remis a vide quand on repasse de 'out' a 'in' pendant la saisie (sans consequence grace au garde a l'envoi).
11) Les categories de depense sont creees automatiquement a la premiere lecture si la societe n'en a aucune: ['Salaire', 'Pub', 'Commande stock', 'Autre']. Elles sont partagees par toute la societe (AdminProfile) et se gerent dans Parametres > Depenses.
12) Le RESUME est independant des sessions: il agrege TOUS les CaisseMovement du magasin sur created_at__date entre date_from et date_to (comparaison sur la date, fuseau serveur), plus les OrderItem des commandes au statut LIVRE dont date_commande__date est dans la periode. ca_produits_vendus = SUM(prix_unitaire * quantite); cout_produits_vendus = SUM(quantite * product_reference.prix_achat); benefice = CA - cout; solde = entrees - sorties. Une sortie sans categorie est regroupee sous 'Sans categorie', tri par total decroissant.
13) Defauts du resume cote serveur si les dates manquent: du 1er du mois courant a aujourd'hui. Cote client, la valeur initiale de summaryFrom est calculee par `new Date().toISOString().split('T')[0].slice(0,8) + '01'` — donc a partir de la date UTC: entre 00h et 03h a Antananarivo (UTC+3) on est encore la veille en UTC, ce qui peut faire basculer le mois le 1er du mois. Meme remarque pour summaryTo = date UTC. A corriger en Flutter en utilisant appToday()/APP_TIME_ZONE.
14) Incoherence de fuseau assumee dans /caisse: toutes les dates affichees (formatDateTime) et les valeurs par defaut des DateTimeInput utilisent l'heure de l'APPAREIL, alors que /bilan et le backend raisonnent en Indian/Antananarivo. En Flutter, aligner sur Indian/Antananarivo.
15) Le montant pre-rempli a l'ouverture ET a la fermeture est la VALEUR DE STOCK du magasin (total_stock_value de /users/magasins/stats/), pas un fond d'especes: c'est un choix metier revendique en commentaire ('recalculee a chaque fois pour rester a jour car le stock bouge avec les ventes'), et la valeur reste modifiable. En cas d'echec de l'appel, le champ reste vide sans message.
16) Ordres d'affichage a respecter: mouvements de SESSION en chronologique croissant (le client inverse la liste API qui est en -created_at), mouvements de PERIODE en anti-chronologique (ordre API brut), sessions en -opened_at.
17) Asymetries de refetch a connaitre: le bouton 'Actualiser' ne recharge que la caisse; la fermeture de caisse ne recharge que la caisse; seul l'ajout de mouvement recharge caisse + resume. Le WebSocket, lui, recharge les deux.
18) Le montant '0' passe le garde JS d'ajout de mouvement (la chaine '0' est truthy), mais un montant vide est bloque par le toast 'Montant et motif requis'. L'attribut min=0 des inputs number empeche seulement la validation HTML des valeurs negatives saisies au clavier dans un navigateur — a reimplementer explicitement en Flutter.

BILAN — regles metier
19) Page STRICTEMENT livreur (isLivreur = employer + commande_role LIVREUR), avec un vrai ecran 'Acces refuse'. Cote serveur, la branche `historique` de orders/views.py filtre sur livreur=request.user (ou preparateur=... pour un preparateur) et n'applique AUCUNE restriction 'jour J' — c'est un journal, pas la file d'attente. La restriction au jour courant vient uniquement des parametres date_from/date_to envoyes par le client.
20) 'Aujourd'hui' = jour calendaire a Indian/Antananarivo via appDayBounds(): [jourT00:00:00.000+03:00, jourT23:59:59.999+03:00] convertis en ISO absolu. Le fuseau du magasin fait foi, pas celui de l'appareil — sinon le bilan bascule 3 h trop tot/tard. Le filtre porte sur date_commande (date planifiee de la commande), PAS sur la date de livraison reelle: une commande datee d'hier mais livree aujourd'hui n'apparait pas dans le bilan du jour.
21) Retours JAMAIS additionnes aux livraisons: regle explicite ('un colis retourne n'a rien fait encaisser au livreur'). Deux tableaux, deux blocs de totaux, jamais de cumul.
22) Le prix produit est DERIVE: total_a_payer - frais_livraison. Le livreur n'a jamais acces au prix unitaire (OrderItemPublicSerializer ne l'expose pas), d'ou ce calcul. Ne pas essayer de sommer les items.
23) Les colonnes 'Type' et 'Sous-type' n'affichent QUE le premier article de la commande (items[0].category_name / type_name) alors que la colonne 'Produit' liste tous les articles: une commande multi-categories est donc mal etiquetee. Comportement a reproduire tel quel ou a corriger sciemment.
24) Les statuts autres que LIVRE et RETOUR (ANNULE, EN_LIVRAISON, PRETE...) sont bien renvoyes par l'API mais ne sont affiches nulle part et n'entrent dans aucun total — ils disparaissent silencieusement.
25) L'echec du chargement des commandes est avale (catch vide -> liste vide): une panne reseau ressemble a une journee sans livraison. Prevoir un etat d'erreur explicite en Flutter.
26) Deux formats monetaires coexistent dans l'app: /bilan arrondit a l'entier avec Intl 'fr-MG', /caisse garde 2 decimales avec 'fr-FR'. Choisir un format unique ou reproduire les deux volontairement.
27) Temps reel: /caisse ecoute caisse_session + caisse_movement, /bilan ecoute order + order_status_history, tous deux avec un debounce de 400 ms sur un WebSocket unique /ws/data/ authentifie par le token d'acces (a porter via un service WebSocket partage cote Flutter). Le rafraichissement du bilan est silencieux (pas de skeleton), celui de la caisse repasse par les etats de chargement (skeletons visibles).

### Groupe `dashboard-reports`

PERMISSIONS ET GATING
1. isGerant = (role === 'admin' || role === 'magasin'). Les rôles « métier commande » PREPARATEUR et LIVREUR sont des SOUS-RÔLES de role='employer' portés par le champ commande_role — ils n'ont accès NI à /dashboard (Accès refusé explicite) NI au lien /reports dans la sidebar.
2. isSuperAdmin est un ALIAS de isAdmin dans useCurrentUser (role === 'admin'); il n'existe pas de vrai 4e niveau. isCompanyOwner distingue l'admin propriétaire (AdminProfile) des co-admins ajoutés — inutilisé sur ces deux pages.
3. /reports N'A AUCUN GUARD DE PAGE — seule la sidebar cache le lien. En Flutter, il faut décider explicitement: soit reproduire l'absence de guard, soit (recommandé) ajouter le même écran « Accès refusé » que /dashboard.
4. Sur /dashboard le gating d'affichage utilise isGerant (issu de /users/me/) tandis que le contenu des KPI utilise le `role` renvoyé par /users/dashboard/. La branche `role === 'employer'` du JSX (3 KPI personnels) est donc du CODE MORT: elle ne peut jamais s'afficher puisque !isGerant coupe avant. À ne PAS porter en Flutter, sauf si on décide d'ouvrir /dashboard aux employers.
5. La carte « Admins/Magasins » du dashboard dépend de `role === 'admin'` (state serveur), pas de isAdmin — même résultat en pratique mais la source diffère.
6. Sur /reports, isAdmin est false pendant le chargement de /users/me/: la carte « Performance par magasin » apparaît en différé, sans skeleton dédié.

PIÈGES DE DONNÉES (très importants pour le portage)
7. « Vente » n'existe plus comme entité: djangoClient.sales.list() dérive les ventes des COMMANDES au statut LIVRE, en aplatissant chaque OrderItem en une ligne. Conséquence: le KPI `Transactions` de /reports compte des LIGNES D'ARTICLE, pas des commandes.
8. total_profit est mis à 0 EN DUR dans sales.list(). Donc sur /reports: le KPI « Bénéfice net » affiche toujours 0 Ar, et les colonnes « Bénéfice » des tables Top produits / Vendeurs / Magasins affichent toujours 0 Ar. Les vrais bénéfices ne sont disponibles que via /users/dashboard/ (kpis.total_profit), utilisé uniquement pour l'IA sur cette page et pour le KPI « Bénéfice total » du dashboard.
9. seller_name et shop_name ne sont PAS renvoyés par sales.list(). Donc la table « Performance des vendeurs » se réduit à une seule ligne « Non attribué » et « Performance par magasin » à une seule ligne « Magasin inconnu ». (En revanche /users/dashboard/ renvoie bien seller_name/shop_name dans recent_sales — d'où l'affichage correct sur le dashboard.)
10. BUG « Ventes à crédit »: le filtre est `!s.is_paid || payment_amount < total_price`. Comme is_paid=true en dur et payment_amount est absent (=> 0), TOUTE vente livrée avec un prix > 0 est classée impayée, avec « Restant dû » = montant total. payment_due_date étant absent, le badge est toujours « En attente » (jamais « En retard ») et le tri par échéance est inopérant. Métier réel: le paiement partiel est HORS PÉRIMÈTRE MVP (le backend renvoie unpaid_sales_count = 0 et unpaid_sales_value = 0). À porter avec prudence: soit reproduire tel quel, soit corriger.
11. BUG « Mouvements de stock »: movementCounts a pour clés 'Entrée', 'Sortie', 'Transfert', mais movements.list() écrase movement_type avec le libellé d'ORIGINE ('Préparation de commande', 'Retour de commande', 'Annulation de commande', 'Commande livrée', 'Réception fournisseur', 'Ajustement manuel'). Aucune clé ne matche => les 3 tuiles affichent TOUJOURS 0. Le vrai sens Entrée/Sortie est porté par le champ `type` (ENTREE/SORTIE) côté backend, mappé en `change` (négatif si SORTIE). Il n'existe pas de type 'Transfert' dans catalog/models.py.
12. mapReferenceToProduct met unit_price = null, purchase_price = null, expiry_date = null, sku absent. Conséquences: (a) le calcul local `totalValue += qty * unit_price` du dashboard vaut toujours 0 — heureusement remplacé par kpis.total_stock_value (admin) / kpis.stock_value (magasin); (b) `expiredCount` de /reports vaut TOUJOURS 0 (catalogue accessoires téléphone sans péremption, cf. commentaire backend §8.1); (c) la ligne SKU de la liste « Alertes de stock » du dashboard est toujours VIDE. Le prix de vente est dans `shell_price` (= prix_vente), jamais utilisé par ces pages.
13. initial_quantity d'un produit = SOMME des stock_actuel de ses variantes (couleurs); alert_threshold = MINIMUM des seuil_alerte (défaut 1 si aucune variante).

RÈGLES DE CALCUL / MÉTIER
14. Classification stock du dashboard: quantité === 0 -> 'out_of_stock' (Rupture, rouge); sinon quantité <= alert_threshold (fallback ?? 5, en pratique jamais utilisé car toujours numérique) -> 'low' (Faible, orange). Les deux catégories alimentent la même liste, tronquée à 8.
15. Le KPI « Alertes stock » du dashboard mélange deux sources: lowStockCount vient de l'API (`kpis.low_stock_count`, avec fallback sur le calcul local) alors que outOfStockCount est TOUJOURS calculé localement. Côté backend, low_stock_count compte les variantes avec stock_actuel <= seuil_alerte (donc les ruptures y sont INCLUSES) -> double comptage possible dans le total affiché.
16. Le KPI « CA » du dashboard n'est PAS un chiffre d'affaires de ventes: backend `ca = valeur du stock + somme des CaisseMovement de type 'in'`. Le vrai CA des ventes est kpis.total_revenue, affiché sous le libellé « Ventes livrées ».
17. « Bénéfice estimé » (backend) = Σ stock_actuel × (prix_vente − prix_achat) sur toutes les variantes du périmètre.
18. « Bénéfice total » (backend total_profit) = calculé sur les commandes LIVRÉES seulement, via une cost_map par variante.
19. Périmètre backend selon le rôle: admin -> tous les magasins dont il est owner (FK admin) OU co-admin (M2M admins); magasin -> son seul MagasinProfile; employer -> ses propres actions dans OrderStatusHistory, avec un statut cible dépendant du sous-rôle (LIVREUR -> 'LIVRE', PREPARATEUR/autre -> 'PRETE'). Un rôle non supporté reçoit HTTP 403 { error: 'Role not supported' }; un profil manquant renvoie 404 ({'error': 'Magasin profile not found'} / 'Employer profile not found').
20. Tendance 7 jours du dashboard: 7 buckets construits en local (new Date() - i jours, clé ISO yyyy-mm-dd, libellé = jour de la semaine en 3 lettres FR). Les ventes sont rattachées par `sale.sold_at.split('T')[0]` — comparaison de chaînes ISO UTC contre une clé générée par toISOString() (donc UTC également). À Madagascar (UTC+3) une vente en début de matinée peut donc tomber sur la veille. Même piège sur le graphique CA de /reports.
21. La source des ventes du graphique dashboard est `lists.recent_sales` du backend, limité à 5 éléments — la « tendance 7 jours » ne porte donc que sur les 5 dernières commandes livrées, pas sur 7 jours réels de données. Idem, la carte « Ventes récentes » annonce « 8 dernières transactions » mais ne peut en afficher que 5.
22. La période 7/30/90 de /reports ne s'applique QU'AU graphique CA et au bloc mouvements. Tous les autres blocs (KPI, top produits, crédits, vendeurs, magasins) portent sur l'intégralité de l'historique — le payload IA le déclare d'ailleurs explicitement: periode = 'toutes périodes confondues'.
23. Filtre des mouvements par période: `new Date(m.created_at) >= (aujourd'hui − period jours)`, borne calculée à l'instant du rendu (heure locale, pas minuit) — recalculée à chaque re-render.
24. Produits « sans mouvement » envoyés à l'IA: produits dont le `name` n'apparaît dans AUCUNE clé de byProduct. Le rapprochement se fait par NOM et byProduct est indexé sur `reference_name (couleur)` alors que products expose `reference_name` seul -> quasiment tous les produits sont donc considérés comme sans mouvement dès qu'une couleur ≠ 'Standard' existe.
25. Masquage des KPI du dashboard: les 5 métriques financières sont MASQUÉES PAR DÉFAUT (hiddenMetrics initialisé à true) et affichent `••••••`. C'est une confidentialité d'écran (épaule), pas une permission: la valeur est déjà chargée côté client. État non persisté (perdu à chaque navigation/rechargement) — pour Flutter, décider s'il faut le persister.
26. Le rendu du graphique « Stock par catégorie » bascule automatiquement Pie -> BarChart horizontal au-delà de 5 catégories (seuil en dur).
27. Analyse IA: appel long (timeout serveur 600 s, message UI « cela peut prendre plusieurs minutes »), modèle local Ollama (qwen3:4b par défaut, `think:false`, balises <think> strippées). Pas de streaming. La réponse est du texte brut sans markdown (le prompt l'exige). Pour Flutter, prévoir un timeout client généreux et un état d'attente explicite.
28. Aucune des deux pages n'affiche d'erreur réseau: tous les catch se contentent d'un console.error. Une API en échec produit une page « vide mais normale » (zéros et états vides). C'est un manque à combler côté Flutter si l'on veut un vrai état d'erreur.
29. Aucun toast, aucune modale, aucune confirmation, aucun formulaire, aucun tri/filtre/pagination utilisateur sur ces deux pages, hormis les 3 boutons de période et le bouton Actualiser de /reports et les toggles Eye du /dashboard.
30. Divergence de formatage à conserver: /dashboard utilise Intl.NumberFormat('fr-MG', { minimumFractionDigits: 0 }), /reports utilise Intl.NumberFormat('fr-MG') — les deux appliquent Math.round() en amont, le résultat visuel est donc identique. La devise ' Ar' est toujours ajoutée à la main (pas de style currency).

### Groupe `settings-stores`

INCOHERENCES DE GATING A TRANCHER POUR FLUTTER
1) /settings et /stores sont marquees `superAdminOnly` dans la sidebar (donc visibles seulement pour role='admin'), alors que le code de /settings est ecrit pour isGerant (admin OU magasin) et degrade proprement pour les employers. Un gerant de magasin ne peut donc PAS atteindre ses onglets Depenses/Zones par le menu, seulement par URL directe. En Flutter il faut decider : soit exposer /settings a isGerant (coherent avec le code de la page et avec le backend IsGerant), soit rester sur admin-only.
2) Aucune des deux pages n'a de guard de redirection par role. Les roles PREPARATEUR/LIVREUR (employer + commande_role) ne sont JAMAIS testes explicitement dans ces deux fichiers : ils tombent dans le `!isGerant` / `!isAdmin`.
3) `isSuperAdmin` est un simple alias de `role === 'admin'` : il n'existe pas de vrai super-admin dans ce hook.

REGLES METIER CACHEES — ZONES DE LIVRAISON
4) Une zone possede un `code` interne jamais affiche dans l'UI ; il reste stable meme si nom/prix changent, pour que les commandes deja passees resolvent toujours leurs frais (Order.save()).
5) DELETE d'une zone deja referencee par une commande NE SUPPRIME PAS : le backend passe `actif=False` et renvoie l'objet zone (200). Le front affiche quand meme 'Zone supprimee' puis la zone reapparait barree/grisee dans la liste. Le portage Flutter doit gerer ce cas (message du type 'Zone desactivee' si la reponse contient un objet).
6) Le backend seede automatiquement les zones a la premiere lecture si la societe n'en a aucune : 'Zone gratuite' (0), 'Zone 1' (3000), 'Zone 2' (4000), 'Zone 3' (5000). Idem pour les categories de depense : ['Salaire', 'Pub', 'Commande stock', 'Autre']. Un GET peut donc creer des donnees.
7) Les zones et les categories de depense sont partagees par TOUTE la societe (rattachees a l'AdminProfile du proprietaire via get_company_owner), pas par magasin. Lecture ouverte a tout authentifie (necessaire pour peupler les selects de creation de commande / sortie de caisse), ecriture reservee a IsGerant.
8) Le prix de zone est converti par `Number(x) || 0` : un champ vide, du texte, ou 'abc' donnent 0 Ar sans aucun avertissement. Le prix est arrondi a l'entier a l'affichage (Math.round).
9) La recuperation sur place ('Recuperation') n'est PAS geree ici : c'est une option separee du formulaire de commande.

REGLES METIER CACHEES — PROFIL / MOT DE PASSE
10) PATCH /users/me/ n'accepte que full_name, phone, adresse, photo (+ company_name/logo pour admin, shop_name/shop_logo pour magasin). Un `photo`/`logo`/`shop_logo` de type string est ignore cote serveur : seul un vrai fichier uploade est pris en compte.
11) Un CO-ADMIN (role='admin' sans AdminProfile propre, ajoute via 'Ajouter un administrateur') voit le nom/logo de la societe du fondateur mais ne peut PAS les modifier : le backend n'ecrit rien car `user.admin_profile` leve DoesNotExist et p reste None -> le PATCH renvoie 200 'Profil mis a jour' SANS effet visible sur company_name/logo. `is_company_owner` (donc `isCompanyOwner`) est false pour lui. Le modal 'Modifier l'entreprise' semble reussir puis reload sans changement.
12) La contrainte de longueur du mot de passe est 6 caracteres, verifiee 2 fois cote front (minLength HTML + check JS) et 1 fois cote backend. Aucune regle de complexite. Aucune deconnexion apres changement.
13) Le champ Email du profil est purement decoratif (disabled, non soumis) : l'email n'est jamais modifiable.
14) Apres le modal entreprise/magasin, le code fait `window.location.reload()` : en Flutter, recharger l'utilisateur courant + revenir a l'onglet par defaut.

REGLES METIER CACHEES — MAGASINS
15) Le champ `manager` renvoye par /users/magasins/users/ est l'ADMIN de la societe (mag.admin), PAS le compte role='magasin' (mag.user). Le vrai gerant n'apparait que dans `company_users`. La carte affiche donc souvent le meme 'gerant' (l'admin) pour tous les magasins.
16) La liste des employes est tronquee a 3 (`slice(0,3)`) alors que le compteur affiche le total : donnee silencieusement masquee, aucun 'voir plus'.
17) Creation d'un magasin = creation d'un COMPTE GERANT (POST /users/register/ role='magasin') ; c'est ce register qui cree le MagasinProfile. `admin_email` = l'email de l'utilisateur courant : si l'utilisateur courant n'est pas un admin existant, le backend renvoie 400 'Administrateur introuvable avec cet email.'. Le magasin est ensuite partage avec TOUS les co-admins de la societe.
18) Le compte gerant est auto-confirme cote backend si l'admin authentifie est bien l'admin cible ; le front appelle QUAND MEME PUT /users/approve/{id}/ juste apres (double confirmation, non idempotente en cas d'erreur : si approve echoue, le magasin est deja cree mais le front affiche 'Erreur lors de la creation.').
19) Aucune validation cote front sur le formulaire de creation : nom vide, email vide, mot de passe vide sont soumis tels quels ; seuls les 400 backend remontent en toast.
20) Le profit affiche prend `profitStats?.total_profit ?? storeStats.profit ?? 0` : la source /users/magasins/overview/ (admin uniquement) prime sur /users/magasins/stats/. Un gerant magasin verra donc le profit issu de stats/, un admin celui d'overview/ — deux calculs differents mais tous deux bases sur les commandes au statut LIVRE.
21) 'Ventes' = somme des `total_a_payer` des commandes `statut_courant == 'LIVRE'` uniquement (aucune commande non livree ne compte). 'Stock' = valorisation du stock via _stock_value_for_magasins. 'Produits' = nombre de ProductReference + somme des `stock_actuel` des ProductVariant.
22) Transfert de stock : reserve de fait a l'admin (seul role multi-magasins). Il travaille AU NIVEAU DE LA VARIANTE (couleur/taille) : seuls les items avec `variant_id` sont envoyes ; un produit sans variante ajoute au panier est silencieusement ignore. Cote serveur, comme le catalogue est scope par magasin, la chaine Categorie -> Type -> Marque -> Reference est retrouvee ou RECREEE par nom dans le magasin destination avant de deplacer le stock.
23) Les quantites du transfert sont clampees en permanence entre 1 et le stock disponible (getQtyInput / setQtyInput / updateTransferCartQuantity) : impossible de saisir 0 ou plus que le stock.
24) Bug a ne pas reproduire : dans handleTransferSubmit, le `return` anticipe du cas 'aucune couleur selectionnee' se produit apres `setSubmittingTransfer(true)` mais le finally remet bien false ; en revanche le bouton reste desactive tant que le panier ne contient que des produits sans variante.

TEMPS REEL
25) /stores se rafraichit automatiquement (silencieusement) sur les evenements WebSocket 'product_variant' et 'order', avec 400 ms de debounce. /settings n'a AUCUN temps reel.

GESTION D'ERREUR
26) /settings avale totalement les erreurs de chargement des categories et des zones (`.catch(() => {})`) : un echec reseau est indiscernable d'une liste vide. /stores avale les erreurs de stats et de profit (console.error) : les KPI tombent a 0 sans avertir l'utilisateur. Seule l'erreur de la liste principale des magasins produit un toast, et uniquement en mode non silencieux.
27) Aucune boite de confirmation destructive sur les deux pages (suppression categorie et suppression zone sont immediates). Prevoir une confirmation en Flutter est un ecart assume, a valider avec le produit.

### Groupe `suppliers-transfers`

REGLES METIER ET PIEGES A REPORTER EN FLUTTER.

1) ROLES — mapping exact du backend. Il n'y a que 3 roles techniques: 'admin', 'magasin', 'employer'. Le vocabulaire metier est derive: GERANT = admin OU magasin (isGerant/isAdminOrSuperAdmin/isManager) ; PREPARATEUR = employer + commande_role==='PREPARATEUR' ; LIVREUR = employer + commande_role==='LIVREUR' ; 'superadmin' dans le code = simplement role==='admin' (isSuperAdmin === isAdmin). /suppliers est reserve au GERANT (admin+magasin). /transfers est reserve a l'ADMIN SEUL (un gerant de magasin n'y a pas acces: il ne voit qu'un magasin, donc aucun transfert possible).

2) BUG /transfers — l'ecran 'Accès refusé' est INATTEIGNABLE. `loading` est initialise a true et n'est remis a false que dans le finally de fetchStores, lui-meme appele uniquement `if (isAdmin)`. Un non-admin reste donc bloque sur les 3 skeletons a vie. En Flutter: gerer explicitement l'etat non-autorise (afficher le message 'Cette page est réservée aux administrateurs.').

3) TROU DE SECURITE UI /suppliers — la page ne fait AUCUN controle de role cote client (pas de useCurrentUser). Seul le menu la cache. Un PREPARATEUR/LIVREUR qui atteint l'URL voit la page se rendre, puis un toast d'erreur venant du 403 backend. Il est recommande d'ajouter le guard en Flutter.

4) MAGASIN IMPLICITE a la creation d'une commande fournisseur. Le formulaire n'envoie pas de magasin_id. Le backend resolve_magasin_for_request() prend l'UNIQUE magasin accessible ; si l'utilisateur (admin multi-magasins) en a plusieurs, il recoit une 400 'magasin_id: Ce champ est requis (plusieurs magasins accessibles).' rendue en toast. La version Flutter devrait exposer un selecteur de magasin.

5) CALCUL DU COUT DE REVIENT (§7.6) — identique cote front (estimation live) et cote backend (source de verite, suppliers/services.py::recompute_costs): cout_total = prix_fournisseur + fret_import + douane ; cout_unitaire = cout_total / total_qty (0 si aucune quantite) ; chaque ligne recoit cout_unitaire_calcule = cout_unitaire et total_ligne = cout_unitaire * quantite. La marge unitaire affichee dans le detail = prix_vente de la reference - cout_unitaire_calcule (propriete calculee cote backend, peut etre NEGATIVE — aucun style particulier n'est applique dans l'UI actuelle).

6) TRANSITIONS DE STATUT commande fournisseur: BROUILLON -> (COMMANDE) -> RECU. La creation produit toujours BROUILLON (default du modele). L'UI n'offre AUCUN moyen de passer a COMMANDE (statut orphelin cote front). Le bouton 'Réceptionner' passe directement a RECU. La reception est IRREVERSIBLE et NON CONFIRMEE (aucun dialog de confirmation): elle cree un StockMovement ENTREE origine FOURNISSEUR par ligne, horodate received_at, et cree une Notification (notif_type='supplier_order') qui declenche l'evenement WebSocket. Une 2e reception renvoie une ValidationError 'Cette commande fournisseur a déjà été reçue.' Le backend n'expose que GET/POST (pas de PUT/PATCH/DELETE): une commande n'est ni modifiable ni supprimable depuis l'app.

7) REGLE CACHEE DU TRANSFERT — seules les VARIANTES (couleurs) sont transferables. handleTransferSubmit filtre `p.variantId != null`: un produit sans variante ajoute au panier est silencieusement supprime du payload. Si le panier ne contient que ce type d'item -> toast 'Sélectionnez au moins une couleur à transférer' sans que rien ne soit envoye. C'est un piege UX a corriger ou a reproduire fidelement.

8) LE TRANSFERT RECREE LE CATALOGUE DANS LA DESTINATION. Le catalogue est scope par magasin (§8.1): la variante n'existe pas dans le magasin cible. TransferProductsView fait get_or_create par NOM sur toute la chaine Categorie -> Type -> Marque -> Reference -> Variante(couleur), en copiant prix_vente et seuil_alerte de la source, puis applique deux mouvements de stock (SORTIE source / ENTREE destination) dans une transaction atomique, avec la note 'Transfert du magasin <src> au magasin <dst> par <full_name>'. Consequence: apres un transfert le magasin destination possede une nouvelle reference/variante identique par le nom mais avec un ID DIFFERENT.

9) VALIDATIONS BACKEND DU TRANSFERT non remontees a l'utilisateur: le front affiche un generique 'Erreur lors du transfert' et perd les messages precis: 'Permission refusée' (403, role != admin), 'Paramètres manquants ou invalides' (400), 'Le magasin source et destination doivent être différents' (400), 'Magasin source ou destination introuvable ou non autorisé' (404), 'Identifiant de variante manquant', 'Certaines variantes n'appartiennent pas au magasin source', 'Quantité invalide pour <ref> (<couleur>)', 'Stock insuffisant pour <ref> (<couleur>). Disponible : N.'. A afficher en Flutter.

10) COURSE AU STOCK — le panel ne s'abonne a aucun evenement temps reel. Les stocks affiches (et les maxQuantity du panier) sont ceux du chargement initial. Le clamp cote client (1..stock) ne protege donc pas d'un stock consomme entre-temps: seul le backend refuse. De plus, les quantites deja placees au panier ne sont PAS deduites du stock affiche.

11) PERFORMANCE — djangoClient.products.list({magasin_id}) recupere TOUTES les references accessibles (GET /catalog/references/ SANS aucun filtre serveur) puis filtre deux fois cote client sur `magasin`. Sur un compte multi-magasins avec un gros catalogue, c'est un chargement complet. En Flutter, preferer GET /catalog/references/?magasin_id=<id> (le backend supporte deja ce query param).

12) MAPPING PRODUIT (mapReferenceToProduct, lib/django-client.ts) — c'est une couche de compatibilite: name et reference valent TOUS LES DEUX reference_name (donc la recherche 'nom OU reference' est redondante) ; initial_quantity = somme des stock_actuel des variantes ; alert_threshold = min des seuil_alerte (1 par defaut) ; variants[].size est TOUJOURS '' (d'ou le tri SIZE_ORDER inoperant et le libelle qui se reduit a la couleur, ou 'Standard' si la couleur est vide) ; variants[].quantity = stock_actuel ; magasin = type.category.magasin_id.

13) FILTRES NON REINITIALISABLES — dans le dialog de creation fournisseur, les Select 'Marque' et 'Catégorie' n'ont pas d'option 'Toutes'. Une fois une marque choisie, impossible de revenir a la liste complete sans fermer/rouvrir le dialog (le useEffect sur `open` remet les filtres a vide). A corriger en Flutter (ajouter une entree de reinitialisation).

14) DOUBLONS AUTORISES dans la commande fournisseur — la cle de ligne est `${variantId}-${Date.now()}`, donc la meme variante peut etre ajoutee plusieurs fois; le backend cree autant de SupplierOrderLine. A l'inverse, le panier de transfert INTERDIT les doublons (test d'existence sur id + variantId avec toast.info).

15) FORMAT MONETAIRE — un seul helper: Intl.NumberFormat('fr-MG') sur Math.round(Number(x||0)) puis suffixe ' Ar'. Pas de decimales affichees (alors que le backend stocke 2 decimales) : un cout unitaire de 12345.67 s'affiche '12 346 Ar'. Equivalent Flutter: NumberFormat.decimalPattern('fr') sur la valeur arrondie + ' Ar'.

16) COULEURS DE STATUT (a reprendre a l'identique): BROUILLON gris (slate-100 / slate-800), COMMANDE bleu (blue-100 / blue-800), RECU vert (green-100 / green-800). Un statut inconnu ne beneficie d'aucun fallback (badge sans couleur, libelle vide).

17) TEMPS REEL /suppliers — le refetch declenche par WebSocket est SILENCIEUX (pas de skeleton, argument silent=true), debounce 400 ms; alors que le bouton RefreshCw et l'apres-reception utilisent le mode NON silencieux (skeleton visible). Reproduire cette distinction evite les clignotements.

18) LE DIALOG DE DETAIL FOURNISSEUR N'EST PAS RE-FETCHE — setDetail(o) stocke l'objet de la ligne. Si un evenement temps reel met la liste a jour pendant que le detail est ouvert, le detail affiche des donnees perimees (l'endpoint GET /suppliers/orders/<id>/ existe pourtant via djangoClient.suppliers.getById mais n'est jamais utilise dans cette page).

19) REMOUNT PAR `key` — le pattern React `key={sourceStore.magasin_id}` sert de reset d'etat sur les deux hotes du panel. En Flutter, il faut soit un ValueKey sur le widget stateful, soit un reset explicite (panier, quantites, recherche, destination, produits deplies) au changement de magasin source.

20) AUTHENTIFICATION — JWT stocke en localStorage sous 'django_tokens'; rafraichissement automatique sur 401 via POST /users/refresh/, et redirection dure vers /login si le refresh echoue. A porter en secure storage cote Flutter avec un interceptor equivalent."

### Groupe `petites-pages`

PIEGES ET REGLES METIER A CONNAITRE AVANT LE PORTAGE FLUTTER

1) /scanner N'EXISTE PLUS dans le working tree. `git status` montre ' D frontend/app/(app)/scanner/page.tsx' (suppression non commitee). Le contenu inventorie ci-dessus vient de `git show HEAD:"frontend/app/(app)/scanner/page.tsx"`. Aucun lien de la Sidebar ne pointe vers /scanner. A arbitrer : est-ce une suppression volontaire (module retire, comme /sales) ? Si oui, ne pas porter l'ecran.

2) /alerts : les sections 'peremption' sont MORTES. mapReferenceToProduct force expiry_date: null pour TOUTES les references. Donc expiringSoon et expired sont TOUJOURS vides, les KPI 'Expirent bientot' et 'Expires' affichent toujours 0, et la Card 'Dates de peremption' n'est JAMAIS rendue (condition expiringSoon.length>0 || expired.length>0). Le rendu 'expiry_badge' et le calcul in30Days sont du code inatteignable. En Flutter : soit on supprime cette partie, soit on ajoute d'abord expiry_date cote backend catalogue.

3) /alerts : initial_quantity n'est PAS un stock de reference mais la SOMME des stock_actuel de tous ses variants (couleurs). alert_threshold est le MINIMUM des seuil_alerte des variants (defaut 1 si la reference n'a aucun variant). Consequence : une reference dont une seule couleur est en rupture n'apparait PAS en 'Rupture' tant que les autres couleurs ont du stock. Une reference sans aucun variant a initial_quantity=0 et tombe donc systematiquement en 'Rupture de stock'.

4) /alerts : les categories sont exclusives par construction (outOfStock exige ===0, lowStock exige >0), donc un produit n'apparait jamais dans les deux premieres sections a la fois. Mais un produit peut apparaitre a la fois dans une section stock et dans la section peremption (si expiry_date existait).

5) /alerts : les colonnes 'Produit' (name) et 'Reference' (reference) affichent EXACTEMENT la meme valeur (reference_name), c'est une duplication liee a l'adaptateur de compatibilite. A signaler au design Flutter.

6) /pickup : regle metier centrale — la zone de livraison 'RECUPERATION' est un litteral special stocke dans Order.livraison_zone (les autres valeurs sont des `code` de DeliveryZoneOption crees dans Parametres). Une commande RECUPERATION ne passe JAMAIS par un livreur.

7) /pickup : transition de statut derogatoire. Le graphe normal (orders/services.py::TRANSITIONS) est NOUVELLE -> EN_PREPARATION (PREPARATEUR) -> PRETE (PREPARATEUR) -> EN_LIVRAISON (LIVREUR) -> LIVRE ou RETOUR (LIVREUR). Pour une commande RECUPERATION, change_order_status court-circuite ce graphe : si new_status==='LIVRE' ET statut_courant==='PRETE' ET livraison_zone==='RECUPERATION', on passe directement PRETE -> LIVRE, reserve au role GERANT ('Seul le gerant peut valider une recuperation sur place.'). Il n'y a donc pas d'etape EN_LIVRAISON pour ce flux.

8) Regle du JOUR J (backend, applicable aux autres ecrans mais utile au contexte) : un preparateur/livreur ne peut agir sur une commande qu'a partir de sa date_commande — sinon PermissionDenied 'Cette commande est planifiee pour le JJ/MM/AAAA — l'action ne sera possible qu'a partir de ce jour.' Le GERANT peut forcer une transition en avance. Cette regle ne bloque donc pas /pickup (gerant), mais peut expliquer qu'une commande soit visible sans etre actionnable ailleurs.

9) Regles d'exclusivite backend : un preparateur ne peut avoir qu'UNE commande EN_PREPARATION a la fois (is_preparateur_busy), un livreur qu'UNE commande EN_LIVRAISON a la fois (is_livreur_busy). Une commande RECUPERATION passee PRETE reste rattachee a son preparateur (elle apparait dans sa liste) jusqu'au retrait valide par le gerant sur /pickup.

10) Notifications backend liees a /pickup : au passage a PRETE, si livraison_zone==='RECUPERATION' une Notification de type 'order' est creee au niveau du MAGASIN ('Commande {numero} prete a recuperer sur place — {client}') au lieu d'etre adressee au role LIVREUR. C'est ce qui alimente la cloche de la TopBar.

11) Impact stock : le stock est deduit a partir de EN_PREPARATION (statuts EN_PREPARATION/PRETE/EN_LIVRAISON = stock deja deduit). La confirmation de recuperation (PRETE -> LIVRE) ne touche donc PAS au stock; seul un RETOUR reinjecte le stock (mouvement ENTREE, origine 'RETOUR'). Statuts terminaux : LIVRE, RETOUR, ANNULEE.

12) /pickup : en cas d'echec de la confirmation, la modale reste ouverte (setPickupTarget(null) n'est fait que dans le chemin succes) — l'utilisateur peut re-tenter. En cas de succes, la carte disparait de la liste au refetch silencieux (elle n'est plus PRETE).

13) /pickup : le garde ne s'applique que quand userLoading===false. Pendant le chargement de /users/me/, la page principale (skeletons) est affichee a n'importe quel role, puis bascule sur 'Acces refuse'. Flash visuel a reproduire ou a corriger cote Flutter.

14) /superadmin : isSuperAdmin et isAdmin sont le MEME test (role === 'admin'). Il n'existe pas de vrai 4e role 'superadmin' dans le modele : les roles backend sont exactement 'admin' | 'magasin' | 'employer', avec un sous-role commande_role ('PREPARATEUR' | 'LIVREUR') porte uniquement par les employers.

15) /superadmin : la page n'est reliee a AUCUN menu (l'item Sidebar 'Super Admin' pointe vers /users). C'est une page orpheline atteignable seulement par URL directe. Verifier si elle doit etre portee, ou si /users la remplace.

16) /superadmin : le champ `manager` renvoye par /users/magasins/users/ est mag.admin (l'ADMIN de la societe), pas le compte role='magasin'. Le vrai gerant (mag.user) est bien ajoute par le backend dans `company_users` mais la page l'IGNORE : allUsers ne prend que manager + employers. Un gerant fraichement cree/approuve, ainsi que les co-admins, n'apparaissent donc PAS dans le tableau 'Tous les utilisateurs' ni dans le KPI 'Utilisateurs total' — bug fonctionnel connu a signaler avant portage (envisager d'utiliser s.company_users a la place).

17) /superadmin : aucun dedoublonnage dans allUsers. Un admin qui est `manager` de plusieurs magasins est liste une fois PAR magasin, avec la meme cle React u.id -> cle dupliquee et gonflement du compteur 'Utilisateurs total'. Idem pour le KPI 'En attente'. En Flutter, dedoublonner par id.

18) /superadmin : le Select de role change le role IMMEDIATEMENT, sans dialogue de confirmation, contrairement a la suppression qui exige le mot de passe. Asymetrie a assumer ou a corriger.

19) /superadmin — regles de permission non evidentes cote backend sur PUT /users/role/<id>/ : (a) on ne peut pas modifier son propre role; (b) toucher un compte admin OU promouvoir quelqu'un vers 'admin' est reserve au FONDATEUR de la societe (is_company_owner) — un co-admin est refuse; (c) le fondateur lui-meme n'est jamais modifiable; (d) l'utilisateur cible doit appartenir a l'entreprise; (e) une promotion vers 'admin' ajoute automatiquement le nouvel admin dans la M2M `admins` de tous les magasins du demandeur, sinon il serait admin sans aucun magasin visible. La page se contente de desactiver le Select quand u.role==='admin' (commentaire explicite dans le code : le controle est desactive plutot que retire pour garder la mise en page des colonnes).

20) /superadmin — regles backend sur DELETE /users/delete/<id>/ : mot de passe du demandeur obligatoire et verifie (check_password); interdiction de se supprimer soi-meme; un role 'magasin' ne peut supprimer que des employers de SON magasin; un admin ne peut retirer un autre admin que s'il est le fondateur, et jamais le fondateur lui-meme. Ces messages remontent tels quels dans l'erreur inline de la modale.

21) /superadmin : chaque action reussie declenche fetchData() qui fait setLoading(true) -> TOUTE la page est remplacee par 3 skeletons puis se reconstruit. UX brutale a ameliorer en Flutter (mise a jour optimiste ou refresh silencieux).

22) Gestion d'erreur incoherente entre les pages, a homogeneiser si souhaite : /alerts et le fetch de /superadmin ne font que console.error (utilisateur non informe); /pickup et le changement de role affichent un toast; la suppression affiche une erreur inline dans la modale.

23) Temps reel : seules /alerts et /pickup s'abonnent au WebSocket. /superadmin et /scanner n'ont aucun rafraichissement automatique.

24) Formats d'affichage a respecter : montants en Intl.NumberFormat('fr-MG') sur une valeur arrondie (Math.round) suivie de ' Ar' (/pickup, /scanner); dates en toLocaleDateString('fr-FR') soit JJ/MM/AAAA (/alerts, code mort); quantites brutes avec le suffixe ' u.' sur /scanner.

25) Perf : djangoClient.products.list() et products.search() rapatrient TOUTES les references du catalogue puis filtrent en JavaScript. Sur /scanner cela signifie un GET /catalog/references/ complet toutes les 350 ms de frappe. En Flutter, utiliser GET /catalog/references/autocomplete/?q=... (deja expose par le client mais inutilise) et paginer.

26) Authentification : tokens JWT dans localStorage ('django_tokens'), refresh transparent via POST /users/refresh/, et redirection dure vers /login si le refresh echoue. En Flutter : stockage securise (flutter_secure_storage) + intercepteur de refresh equivalent, et gestion de la deconnexion forcee."

### Groupe `notifications`

GATING & PERMISSIONS
1) Aucune page du perimetre n'implemente de guard de role en propre. Le seul guard reel est app/(app)/layout.tsx : useEffect -> !djangoClient.isAuthenticated() -> router.replace('/login'). C'est un guard client-side post-montage : en Flutter il faudra un vrai route guard (redirect avant construction de l'ecran) sinon on reproduit le flash.
2) /notifications est marquee adminOnly dans la sidebar => visible seulement pour GERANT (role 'admin' ou 'magasin'). PREPARATEUR et LIVREUR (role 'employer' + commande_role) n'ont pas le lien mais peuvent atteindre l'URL : le backend leur renvoie quand meme leurs notifications (magasin + personnelles). Decision a prendre pour Flutter : soit reproduire (ecran accessible sans lien), soit bloquer explicitement.
3) Pendant useCurrentUser().loading, la sidebar affiche tous les items non-superAdminOnly => le lien Notifications clignote pour un employer avant de disparaitre.
4) La cloche du header n'a AUCUN gating : tous les roles la voient et recoivent les toasts temps reel.
5) Permission de suppression (backend users/views.py::NotificationViewSet.destroy) : role admin -> peut supprimer toute notification visible ; sinon si instance.user_id == moi -> autorise ; sinon si role magasin/employer et instance.magasin == mon magasin -> autorise ; sinon 403 {'error':'Permission refusee'}. Le front ne distingue pas ce 403 : il affiche le toast generique 'Impossible de supprimer la notification.' et la ligne reste affichee (le filtre local n'est applique qu'en cas de succes).
6) Perimetre de lecture (get_queryset) : admin = notifications des magasins dont il est admin + les siennes ; magasin = celles de son magasin + les siennes ; employer = celles du magasin de son EmployerProfile + les siennes. Consequence metier : un preparateur voit les notifications destinees a tout le magasin, pas seulement les siennes.
7) Bug latent backend : get_queryset ne retourne rien (None) si role n'est ni admin, ni magasin, ni employer -> 500. Non atteignable avec les roles actuels.

MODELE DE DONNEES REEL vs CODE FRONT
8) Champs reellement serialises (users/serializers.py::NotificationSerializer) : id, notif_type, message, magasin, magasin_name, caisse_session, user, user_name, is_read, created_at. La page lit aussi notification.product_name et notification.sale_id : CES CHAMPS N'EXISTENT PAS -> les branches 'Produit : ...' et 'Vente #...' sont mortes. Ne pas les porter en Flutter (ou les porter en optionnel nullable).
9) Types backend reels (users/models.py::Notification.NOTIF_TYPES) : 'order', 'supplier_order', 'user', 'chat', 'caisse', 'other'. Types geres par le front (typeLabel/typeIcon/getTypeBadgeClass) : 'sale', 'product', 'user', 'chat', 'transfer', 'movement'. INTERSECTION = seulement 'user' et 'chat'. Donc en pratique les notifications de commande, de commande fournisseur et de caisse s'affichent toutes avec le libelle 'Autre', l'icone Bell et le badge gris. C'est un vrai defaut fonctionnel a corriger ou a reproduire consciemment dans le portage Flutter (recommande : mapper order='Commande', supplier_order='Cmd. fournisseur', caisse='Caisse').
10) Le payload WebSocket n'est PAS le meme que le payload REST. Signal post_save (users/signals.py) envoie {id, notif_type, message, magasin, magasin_name, is_read, created_at} — pas de user_name, pas de caisse_session. Et orders/services.py::_broadcast_notification_ws envoie explicitement "id": None.

CONSEQUENCES DU id=null EN TEMPS REEL (piege majeur)
11) La deduplication de la page et de la cloche est `prev.some(n => n.id === newNotif.id)`. Les notifications poussees par le module Commandes ont id=null : la premiere passe (et declenche son toast), toutes les suivantes sont considerees comme des doublons -> SILENCIEUSEMENT IGNOREES tant que la liste n'a pas ete rechargee. Les elements de liste utilisent aussi key={notification.id} -> cles React nulles/dupliquees.
12) Une notification poussee par WS n'a pas d'id => les boutons 'marquer lu' / 'supprimer' de cette ligne appelleront /notifications/null/ et echoueront. Il faut recharger (Actualiser) pour recuperer les vrais ids.
13) Recommandation Flutter : apres reception d'un event WS sans id, declencher un refetch de la liste plutot que de faire un prepend optimiste.

DOUBLE TOAST
14) Sur /notifications, la cloche (showToast:true, montee dans la TopBar) ET la page (toast.info dans son propre handleNewNotification) emettent chacune un toast pour la meme notification => 2 toasts identiques superposes. A ne PAS reproduire en Flutter : centraliser l'emission dans un seul service.

'TOUT EFFACER' : DEUX SEMANTIQUES OPPOSEES POUR LE MEME LIBELLE
15) Page /notifications, bouton 'Supprimer tout' = POST delete-all = SUPPRESSION DEFINITIVE en base de tout le queryset visible (pour un admin, cela efface aussi les notifications de tous ses magasins). Aucune confirmation.
16) Cloche, bouton 'Tout effacer' = masquage LOCAL uniquement : les ids sont pousses dans localStorage 'stockv2_dismissed_notification_ids' (borne aux 200 derniers via slice(-200)), rien n'est supprime cote serveur et les notifications restent visibles sur la page /notifications. Au-dela de 200 ids, les plus anciens sortent du cache et les notifications correspondantes REAPPARAISSENT dans la cloche.
17) Le compteur de non-lues de la cloche est calcule apres filtrage des 'dismissed' : il peut afficher 0 alors que la page /notifications montre plusieurs 'Nouveau'. Divergence assumee dans le code actuel.

COHERENCE D'ETAT / RAFRAICHISSEMENT
18) Page : toggleRead() et markAllRead() font un refetch complet avec setLoading(true) -> les 5 skeletons remplacent la liste a chaque clic (flash desagreable). En Flutter, preferer une mise a jour optimiste + reconciliation silencieuse.
19) Page : clearAll() et deleteNotification() ne refetchent pas (mutation locale seulement).
20) Cloche : markAsRead / markAllAsRead sont purement optimistes, aucun refetch. Ni la page ni la cloche ne s'ecoutent mutuellement : marquer lu dans l'une ne met pas a jour l'autre tant qu'on ne recharge pas.
21) Aucun polling nulle part. La fraicheur repose entierement sur le socket /ws/notifications/.
22) Le systeme DataSync (/ws/data/) est un CANAL SEPARE qui ne transporte aucun modele 'notification' : useRealtimeRefresh n'a donc aucun effet sur les notifications. Ne pas confondre les deux sockets lors du portage : /ws/notifications/ (push d'objets notification) et /ws/data/ (push d'evenements {model, action, id, magasin_id} pour re-fetcher les listes metier).

WEBSOCKETS — REGLES DE RECONNEXION ET DE ROUTAGE
23) Les deux sockets suivent la meme mecanique : connexion seulement si un access token existe, token passe en query string (?token=), reconnexion automatique apres 3000 ms si le code de fermeture !== 1000, fermeture volontaire avec close(1000) pour ne pas relancer la boucle. Aucun backoff exponentiel, aucun plafond de tentatives, aucun heartbeat/ping.
24) Aucun des deux hooks ne se reconnecte apres un refresh de token : si l'access token expire, le serveur ferme la connexion, le hook retente toutes les 3 s avec l'ANCIEN token capture dans la closure jusqu'a ce que le composant se remonte. En Flutter, relire le token a chaque tentative.
25) Routage des groupes notifications : admin -> 'notifications_admin_{user.id}' ; magasin/employer -> 'notifications_magasin_{magasin_id}' ; PLUS toujours 'notifications_user_{user.id}'. Pour DataSync : admin -> 'data_admin_{id}', autres -> 'data_magasin_{magasin_id}', SANS groupe personnel.
26) Regle metier de diffusion (orders/services.py::_notify_commande_role) : quand une commande change d'etape, une ligne Notification est creee PAR destinataire ayant le commande_role vise (bulk_create, qui ne declenche pas le signal post_save) afin que chaque preparateur/livreur ait son propre statut lu/non-lu ; le broadcast WS est fait UNE seule fois par canal (magasin, admin, puis chaque user) pour eviter les toasts en double cote gerant. Si aucun employer ne porte le role vise, une seule Notification magasin est creee via .create() (donc le signal la diffuse normalement).

DIVERS
27) Ordre d'affichage : backend ordering ['-created_at'] (plus recent en premier) ; le front n'ordonne jamais lui-meme et insere les arrivees WS en tete sans re-tri.
28) Pas de pagination cote serveur (aucun DEFAULT_PAGINATION_CLASS dans REST_FRAMEWORK) : la liste complete est renvoyee d'un bloc. Le front tolere quand meme {results:[]}. Sur un historique volumineux, prevoir une pagination cote Flutter (les endpoints bulk-read / bulk-delete existent deja et ne sont pas utilises).
29) Format de date unique dans tout le module : 'JJ/MM/AAAA HH:mm' locale fr-FR, jamais de temps relatif.
30) Textes exacts a reprendre tels quels (FR) : titres 'Notifications' / 'Historique des notifications' ; sous-titre 'Toutes les alertes et mouvements enregistres de l'application.' ; vides 'Aucune notification pour le moment.' (page) et 'Aucune notification' (cloche) ; boutons 'Actualiser', 'Marquer tout lu', 'Supprimer tout', 'Tout marquer lu', 'Tout effacer', 'Marquer lu', 'Voir toutes les notifications' ; badges 'Nouveau', '{n} non lue(s)', 'Temps reel', 'Connexion...', 'Deconnecte' ; toasts listes dans uxDetails.\n31) La cloche ne remet jamais loading a true apres le premier chargement et n'a aucun bouton d'actualisation : si le premier fetch echoue, elle reste definitivement vide et silencieuse jusqu'au prochain montage."

### Groupe `auth`

ROLES ET VOCABULAIRE (indispensable pour le portage Flutter)
- 3 roles backend stockes en base : 'admin', 'magasin', 'employer'. Le frontend web utilise en plus des alias d'inscription : 'admin' / 'store_manager' (=magasin) / 'employee' (=employer), convertis dans djangoClient.auth.register.
- Vocabulaire module Commande (§4 Smartreadme.md) : GERANT = admin OU magasin ; PREPARATEUR et LIVREUR = sous-roles portes par un employer via le champ `commande_role`. useCurrentUser expose isGerant / isPreparateur / isLivreur.
- GET /users/me/ renvoie DEUX champs de sous-role : `role_commande` (calcule pour tous, valeurs 'GERANT'|'PREPARATEUR'|'LIVREUR'|null — explicitement destine au client Flutter smartcross) et `commande_role` (present uniquement pour role='employer'). useCurrentUser (web) lit `commande_role`. Pour Flutter, `role_commande` est le champ prevu.
- isSuperAdmin === isAdmin (role === 'admin') : il n'existe PAS de vrai super-admin distinct dans le code. La distinction reelle est isCompanyOwner = admin AVEC un AdminProfile (le fondateur) vs co-admin (ajoute via 'Ajouter un administrateur', memes acces aux donnees mais ne peut pas gerer les autres admins).

GATING : ETAT REEL DU CODE
- AUCUNE page du perimetre auth n'a de guard. AdminGuard et SuperAdminGuard existent mais ne sont importes NULLE PART (dead code). useAuth est egalement dead code.
- Le seul controle d'acces frontend est dans app/(app)/layout.tsx : `if (!djangoClient.isAuthenticated()) router.replace('/login')`. Or isAuthenticated() se contente de tester la presence d'un access token en localStorage : un token EXPIRE passe le test, et l'echec reel n'apparait qu'au premier 401 (qui declenche un refresh, puis, s'il echoue, un `window.location.href='/login'` dur).
- Aucune page auth ne redirige un utilisateur DEJA connecte : ouvrir /login avec une session valide affiche quand meme le formulaire.
- Le gating par role est fait ecran par ecran a l'interieur des pages metier (via useCurrentUser), pas par des routes protegees.

REGLE METIER CACHEE #1 — l'admin est auto-approuve
Le RegisterSerializer cree un compte role='admin' avec `is_confirmed=True` immediatement, et lui cree automatiquement un magasin par defaut 'Stock Local' (description 'Magasin pour les stocks locaux'). Pourtant le formulaire web affiche "Compte cree ! En attente d'approbation." et redirige vers /auth/pending-approval. Un admin peut donc se connecter tout de suite : le message et la page d'attente sont TROMPEURS pour ce role. A corriger/adapter en Flutter (rediriger l'admin directement vers /login voire le connecter).
Les roles 'magasin' et 'employer' sont crees avec is_confirmed=False SAUF si c'est un admin deja authentifie qui cree le compte lui-meme et qu'il est bien l'admin reference (requester.id == admin.id) : dans ce cas auto_confirm=True.

REGLE METIER CACHEE #2 — resolution du rattachement a l'inscription
- role='magasin' : l'`admin_email` doit correspondre a un CustomUser role='admin' existant, sinon erreur 400 {admin_email: 'Administrateur introuvable avec cet email.'}. Le magasin cree est ensuite partage avec TOUS les admins de la societe (get_company_admin_ids), pas seulement celui reference.
- role='employer' : l'`admin_email` peut etre celui d'un admin OU d'un gerant (role='magasin'). Si c'est un admin qui possede EXACTEMENT UN magasin, l'employe y est rattache automatiquement ; s'il en a plusieurs, l'employe reste sans magasin (magasin=None) et devient invisible dans les listes filtrees par magasin. Si aucun des deux n'est trouve : 400 {admin_email: 'Responsable (administrateur ou gerant) introuvable avec cet email.'}.
- `commande_role` (PREPARATEUR/LIVREUR) est accepte par l'API d'inscription mais n'est JAMAIS envoye par le formulaire web : il est attribue apres coup par le gerant via PATCH /users/employers/<id>/commande-role/.

REGLE METIER CACHEE #3 — le mot de passe oublie n'envoie aucun email
Aucun backend mail n'est configure. Le flux /forgot-password est un flux d'APPROBATION MANUELLE : la demande cree un EmployeePasswordResetRequest(status='pending') rattache a l'admin de la societe ; l'admin l'approuve ou la rejette depuis son ecran (PATCH /users/password-reset-requests/<id>/ {action}) ; l'utilisateur revient VERIFIER lui-meme le statut puis definit son mot de passe. La demande approuvee est marquee `consumed_at` a la confirmation : usage unique, non rejouable. Une seule demande 'pending' a la fois par utilisateur (400 'Une demande est deja en attente.'). Le statut renvoye correspond a la demande NON CONSOMMEE la plus recente.
Ce flux est INDISPONIBLE pour les comptes role='admin' (pas d'approbateur au-dessus) : POST -> 400 avec le message 'La reinitialisation automatique n'est pas disponible pour les comptes administrateur. Contactez le support technique directement.' et GET status -> {status:'none'}.

REGLE METIER CACHEE #4 — /reset-password est reserve au gerant
POST /users/change-password/ refuse tout role hors ['admin','magasin'] : 403 'Seul le gerant peut modifier ces informations. Contactez votre gerant.' Un preparateur/livreur ne peut donc PAS changer son mot de passe lui-meme (il doit passer par le flux forgot-password ou par son gerant). Meme regle sur PATCH /users/me/ (modification du profil).

REDIRECTION POST-LOGIN
`raw_role === 'admin' || raw_role === 'magasin'` -> /dashboard ; sinon -> /orders. Le commentaire du code precise que le tableau de bord est reserve au gerant et que /orders s'adapte deja au sous-role (vue Depot pour le preparateur, Ma tournee pour le livreur).

CONNEXION : DOUBLE BARRIERE is_confirmed
1) Cote backend, CustomTokenObtainPairSerializer leve AuthenticationFailed('Compte non approuve. Contactez votre administrateur.') AVANT d'emettre le token si !is_confirmed -> le frontend le traduit en 'Compte en attente d'approbation. Contactez votre administrateur.'
2) Cote frontend, LoginForm re-teste `!response.user.is_confirmed` et affiche 'Compte en attente d'approbation. Contactez votre manager.' — code de fait INATTEIGNABLE (le backend a deja bloque). Si jamais il l'etait, les tokens auraient DEJA ete ecrits en localStorage par djangoClient.auth.login (qui sauvegarde avant d'appeler /users/me/) et ne seraient pas purges : l'utilisateur resterait 'authentifie' localement. A ne pas reproduire tel quel en Flutter — purger les tokens dans ce cas.
Effet de bord de la connexion : chaque login reussi cree un LoginEvent (ip + user_agent tronque a 500 caracteres) cote backend.

DECONNEXION
`djangoClient.auth.logout()` : POST /users/logout-event/ (best-effort, echec ignore) -> POST /users/refresh/ avec le refresh token (echec ignore, aucun effet serveur utile, le token n'est pas blackliste) -> `localStorage.clear()` (VIDE TOUT le localStorage du domaine, pas seulement 'django_tokens') -> tokens = null. Aucune invalidation serveur du JWT : un access token deja emis reste valide jusqu'a son expiration naturelle. Aucune boite de confirmation nulle part.

ROUTES ORPHELINES / DOUBLONS A ARBITRER AVANT PORTAGE
- /verify-email : jamais atteinte, promet un lien de confirmation par email qui n'existe pas.
- /pending-approval (racine) : jamais atteinte en entree ; c'est pourtant le SEUL ecran qui pointe vers /logout. Son bouton primaire est libelle 'Actualiser la page' mais pointe en realite vers /login (il ne rafraichit rien).
- /auth/pending-approval : la vraie destination apres inscription ; version detaillee 3 etapes ; pas de bouton de deconnexion ; annonce une notification par email qui n'existe pas.
- /reset-password : aucun lien ne pointe dessus dans toute l'app.
- Aucune de ces pages d'attente ne fait de polling du statut d'approbation (ni websocket) : il faut re-tenter une connexion manuellement.

CONVENTIONS UI TRANSVERSES A REPRODUIRE
- Tous les retours utilisateur passent par des toasts Sonner (top-right, richColors, closeButton, expand, 5000 ms). AUCUN message d'erreur inline sous un champ dans tout le perimetre auth, aucun etat visuel 'champ en erreur'.
- Le pattern de chargement d'un bouton est : `disabled` + `<Loader2 className='mr-2 h-4 w-4 animate-spin' />` + libelle au gerondif ('Connexion…', 'Creation du compte…') — sauf ResetPasswordForm qui change juste le texte en 'Changement...' sans icone, et ForgotPasswordForm qui garde le libelle et ajoute juste le spinner.
- login-form et register-form utilisent `noValidate` (aucune validation navigateur : les `required` sont decoratifs) ; forgot-password-form et reset-password-form ne l'utilisent PAS (validation HTML native active).
- Le toggle de visibilite du mot de passe existe seulement sur /login et /register (Eye/EyeOff, type=button, tabIndex=-1, aria-label dynamique) ; il est ABSENT des champs de /forgot-password et /reset-password.
- Largeur d'ecran auth standard : carte `w-full max-w-md`, generalement `shadow-xl`, centree verticalement sur `min-h-screen`.
- Branding incoherent a trancher : metadata globale 'StockManager' vs titres de pages 'E-kajy Entana' vs description 'Gestion de stock intelligente'.
- Longueur minimale de mot de passe = 6 caracteres partout (client ET backend), jamais plus exigeant (pas de regle de complexite).
- Le champ identifiant de connexion est l'EMAIL (CustomUser.USERNAME_FIELD = 'email'), le `username` n'est qu'un libelle secondaire optionnel.

### Groupe `layout-nav`

POINTS DE VIGILANCE ET REGLES METIER CACHEES POUR LE PORTAGE FLUTTER

1) EQUIVALENCE isAdmin === isSuperAdmin. Dans lib/auth/useCurrentUser.ts, isSuperAdmin et isAdmin valent tous deux role === 'admin'. Il n'existe donc que 2 niveaux effectifs cote sidebar : 'admin' (voit tout sauf Bilan du jour) et 'magasin' (adminOnly seulement). Les flags superAdminOnly de la sidebar = reserve au role 'admin'. Le flag adminOnly = admin OU magasin (isAdminOrSuperAdmin), c'est-a-dire le GERANT au sens metier (isGerant = admin || magasin).

2) SOUS-ROLES DU MODULE COMMANDE. PREPARATEUR et LIVREUR ne sont PAS des roles Django : ce sont des valeurs de user.commande_role portees par un utilisateur de role 'employer'. isPreparateur = role==='employer' && commande_role==='PREPARATEUR' ; isLivreur = role==='employer' && commande_role==='LIVREUR'. Un 'employer' SANS commande_role (null) n'est ni preparateur ni livreur : il voit Commandes, Produits, Caisse, Chats.

3) MENU EFFECTIF PAR ROLE (a reproduire tel quel) :
- admin : Tableau de bord, Commandes, Recuperation, Produits, Caisse, Chats, Mouvements, Alertes, Fournisseurs, Transferts, Notifications, Rapports, Magasins, Super Admin, Parametres (15 items — PAS 'Bilan du jour').
- magasin (gerant) : Tableau de bord, Commandes, Recuperation, Produits, Caisse, Chats, Mouvements, Alertes, Fournisseurs, Notifications, Rapports (11 items).
- employer PREPARATEUR : Commandes, Produits, Chats (3 items — Caisse masquee par hidePreparateur).
- employer LIVREUR : Commandes, Bilan du jour, Chats (3 items — Produits masque par hideLivreur, Caisse masquee par hideLivreur).
- employer sans sous-role : Commandes, Produits, Caisse, Chats (4 items).
- non authentifie / erreur GET /users/me/ : Commandes, Produits, Caisse, Chats (les flags hideXxx sont faux quand user est null) — la coque redirige normalement vers /login avant.

4) FENETRE DE FLASH PENDANT LE CHARGEMENT. Tant que useCurrentUser.loading est true, la sidebar affiche TOUS les items sauf superAdminOnly. Un preparateur ou un livreur voit donc brievement Tableau de bord, Recuperation, Produits, Caisse, Mouvements, Alertes, Fournisseurs, Notifications, Rapports. En Flutter, preferer un skeleton ou n'afficher le menu qu'apres resolution du role (mais si l'on veut la parite exacte, reproduire ce comportement).

5) INCOHERENCE 'Parametres' / 'Mon profil'. Le lien 'Parametres' -> /settings est superAdminOnly dans la sidebar, MAIS le menu utilisateur de la TopBar expose 'Mon profil' -> /settings pour TOUS les roles. La route /settings est donc atteignable par un magasin/employer via la TopBar. Le gating reel doit etre verifie dans app/(app)/settings/page.tsx.

6) 'Bilan du jour' EST EXCLUSIF AU LIVREUR (livreurOnly) : meme l'admin ne le voit pas dans le menu. C'est le seul item avec un flag 'only' positif sur un sous-role.

7) LIBELLE vs URL : l'item 'Super Admin' pointe vers /users (pas /superadmin). Les pages app/(app)/superadmin/page.tsx et app/(app)/sales/page.tsx existent mais NE SONT REFERENCEES PAR AUCUN item de menu (routes orphelines accessibles seulement par URL directe).

8) ACTIF = EGALITE STRICTE. isActive = (pathname === item.href). Une route enfant (/orders/42, /products/12/edit) ne surligne aucun item. En Flutter, ne pas utiliser un startsWith si l'on veut la parite.

9) LIBELLES DE ROLE DE LA TOPBAR : admin -> 'Administrateur', magasin -> 'Gerant de magasin', employer -> 'Commercial'. Le sous-role PREPARATEUR/LIVREUR n'est jamais affiche : un livreur est etiquete 'Commercial'.

10) NOM ET LOGO AFFICHES DANS LA SIDEBAR. useCurrentUser calcule store_name = (role==='admin' ? company_name : shop_name) et store_logo = (role==='admin' ? logo : shop_logo). Repli du titre : store_name || (isAdmin ? 'Societe' : 'Valheri Wear'). Repli du logo : URL Cloudinary Valheri Wear codee en dur. Sous-titre toujours 'Smart kajy'.

11) DECONNEXION : deux implementations differentes. Sidebar : await logout() puis router.push('/login') puis router.refresh(). TopBar : logout() NON attendu puis router.push('/login') immediat (course possible : la navigation peut precede la fin des requetes). Dans les deux cas logout() fait POST /users/logout-event/, POST /users/refresh/, puis localStorage.clear() — ce clear efface AUSSI la liste des notifications masquees ('stockv2_dismissed_notification_ids') et la preference de theme de next-themes (cle 'theme'), donc le theme revient a 'system' apres deconnexion. Aucune confirmation n'est demandee.

12) BASCULE DE THEME NON TERNAIRE. setTheme(theme === 'dark' ? 'light' : 'dark') : depuis 'system', le premier clic force 'dark' meme si le systeme est deja sombre (l'icone affichee est alors Moon). Il n'existe aucun moyen dans l'UI de revenir a 'system'. L'icone est Sun uniquement si mounted && theme === 'dark' (donc jamais pour theme==='system' meme resolu en sombre).

13) ERROR BOUNDARY INACTIF. GlobalErrorBoundary est importe dans app/layout.tsx mais jamais rendu (verifie par grep sur tout le repo) : aujourd'hui aucune erreur de rendu n'est capturee ni toastee. Si le portage Flutter doit reproduire l'INTENTION, prevoir un ErrorWidget global + toast rouge 8 s + bouton 'Reessayer' ; si l'on reproduit le COMPORTEMENT REEL, il n'y a rien.

14) GARDE D'AUTHENTIFICATION FAIBLE. app/(app)/layout.tsx ne verifie que la presence d'un token en localStorage, pas sa validite ni son expiration, et rend les children immediatement (pas d'ecran d'attente) : flash de contenu protege possible. La vraie invalidation vient du client HTTP : sur 401, tentative de refresh via POST /users/refresh/ ; si le refresh echoue -> clear des tokens + window.location.href = '/login' (redirection dure, hors router Next).

15) DOUBLE APPEL /users/me/. useCurrentUser n'a aucun cache ni contexte : Sidebar et TopBar declenchent chacun leur GET /users/me/ a chaque montage du shell. En Flutter, prevoir un provider/singleton unique (Riverpod/Provider) pour eviter le doublon.

16) DEUX WEBSOCKETS SIMULTANES dans le shell : /ws/data/ (DataSyncProvider, monte par le layout) et /ws/notifications/ (hook du composant Notifications dans la TopBar). Les deux passent le JWT en query string ?token=..., se reconnectent apres 3 s si le code de fermeture n'est pas 1000, et ne se connectent que si isAuthenticated(). socketStatus du DataSync n'est affiche nulle part dans la coque.

17) 'TOUT EFFACER' NE SUPPRIME RIEN. Le bouton du menu de notifications ne fait que masquer localement (localStorage 'stockv2_dismissed_notification_ids', tronque aux 200 derniers ids). Les notifications restent en base et reapparaissent sur un autre appareil/navigateur ou apres un localStorage.clear() (donc apres une deconnexion). Un id masque est aussi ignore a l'arrivee par WebSocket.

18) LIMITE D'AFFICHAGE : la cloche n'affiche que les 8 premieres notifications (slice(0,8)) dans une zone max-h-96 ; le compteur de non-lues, lui, porte sur toute la liste chargee. Le badge affiche '9+' au-dela de 9. Aucune pagination, aucun 'charger plus' : le lien '/notifications' est la seule sortie.

19) AUCUN TITRE DE PAGE NI FIL D'ARIANE dans la TopBar : la moitie gauche est un simple <div class='flex-1'/>. Chaque page doit donc porter son propre en-tete.

20) RESPONSIVE : la sidebar reelle bascule au breakpoint Tailwind lg = 1024 px (tiroir + overlay en dessous, colonne fixe 256 px au-dessus). Le kit ui/sidebar (non utilise) utilise, lui, un breakpoint JS de 768 px. Pour Flutter, retenir 1024 px comme seuil de la coque et 256 px de largeur de rail, 64 px de hauteur de TopBar (h-16), padding horizontal 24 px (px-6).

21) FICHIER MORT : components/ui/sidebar.tsx (726 lignes) n'est importe nulle part. Son portage n'est necessaire que si l'on souhaite recuperer ses fonctionnalites absentes de la sidebar reelle : repli en mode icone, persistance en cookie 7 jours, raccourci Ctrl/Cmd+B, tooltips en mode replie, sous-menus, badges de menu, squelettes de menu, rail de redimensionnement.

22) FORMULAIRES : il n'existe AUCUN formulaire, AUCUNE validation, AUCUN message d'erreur de champ dans tout le perimetre audite. Le seul champ de saisie declare est SidebarInput (kit non utilise), sans validation ni soumission.

23) COULEURS DE STATUT A REPRODUIRE : badge de type de notification (vente=vert, produit=bleu, utilisateur=violet, chat=ambre, transfert=cyan, mouvement=orange, autre=muted) ; statut de socket (connecte=emeraude, connexion=ambre, deconnecte=rose) ; carte de notification (lue = bg-muted/40, non lue = bg-primary/5 + border-primary/30 + shadow) ; badge de compteur = --destructive ; lien actif de sidebar = degrade blue-600 -> blue-500 ; action destructive du menu utilisateur = text-red-600.

24) FORMAT DE DATE UNIQUE DU PERIMETRE : toLocaleString('fr-FR', {day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) => 'JJ/MM/AAAA HH:mm'. Locale de l'app : fr.

25) DUREES DE TOAST : 5000 ms par defaut (Toaster global et toasts de notification WebSocket), 8000 ms pour les erreurs de l'error boundary. Position top-right, richColors, bouton de fermeture, empilement deplie (expand).

### Groupe `medias-divers`

GATING / PERMISSIONS
1) AUCUN des 10 fichiers du périmètre ne fait lui-même de gating de rôle. Les 4 composants et les 2 hooks sont agnostiques ; le contrôle est toujours dans la page appelante via useCurrentUser (lib/auth/useCurrentUser.ts). Les drapeaux disponibles : isGerant = (role 'admin' OU 'magasin'), isPreparateur = (role 'employer' ET commande_role === 'PREPARATEUR'), isLivreur = (role 'employer' ET commande_role === 'LIVREUR'), isSuperAdmin === isAdmin === (role 'admin'), isManager === isAdminOrSuperAdmin === (admin|magasin), isCompanyOwner = admin AVEC is_company_owner (un co-admin ajouté via « Ajouter un administrateur » partage l'accès aux données mais PAS les actions de propriété de société).
2) ConfirmDeleteDialog — /superadmin : guard dur `useEffect(() => { if (!userLoading && !isSuperAdmin) router.replace('/dashboard') })`, fetch conditionné à isSuperAdmin, et le bouton poubelle n'est rendu que si `u.role !== 'admin'`. La colonne « rôle » y est un Select (Admin/Gérant/Commercial) disabled si changingRole === u.id OU u.role === 'admin' (commentaire du code : la ligne admin est toujours le fondateur, jamais actionnable ; désactivé plutôt que retiré pour garder l'alignement des colonnes). Changement de rôle = PUT /users/role/<id>/ { role } + toast 'Rôle modifié'.
3) ConfirmDeleteDialog — /users : page bloquée si !isManager ; le bouton supprimer d'une ligne exige `(u.role === 'admin' ? isCompanyOwner : isAdmin) && currentUser && u.id !== currentUser.id` -> on ne peut JAMAIS se supprimer soi-même, et seul le propriétaire de la société peut supprimer un autre administrateur. Dans le formulaire de création, l'option « Gérant de magasin » n'apparaît que si isAdmin et « Administrateur » que si isCompanyOwner. L'onglet des demandes de réinitialisation de mot de passe n'est chargé/affiché que si isAdmin.
4) Les DEUX routes /api/ai/* n'ont AUCUNE authentification, aucune vérification de rôle, aucun rate-limiting : n'importe quelle requête atteignant le serveur Next peut lancer une inférence Ollama de 10 minutes (risque de déni de service par saturation CPU du VPS). À sécuriser avant portage mobile.
5) Zones de livraison : lecture ouverte à tous les rôles, écriture (create/update/delete via /settings) réservée au gérant côté backend (orders/views.py::DeliveryZoneOptionViewSet).

RÈGLES MÉTIER SUBTILES
6) Zone « RECUPERATION » : ce n'est PAS une zone en base. buildZoneOptions() (orders/page.tsx) l'ajoute toujours comme option littérale { value:'RECUPERATION', label:'Récupération (0 Ar)', frais:0 } — retrait sur place, pas de livreur, pas de frais.
7) Un PRÉPARATEUR ne crée QUE des retraits sur place : zone forcée à 'RECUPERATION' à l'ouverture du dialog, et showPrices = !isPreparateur -> aucune donnée financière visible (§4/§7.2 du cahier des charges).
8) Pour les autres rôles, un useEffect présélectionne la PREMIÈRE zone payante dès l'arrivée des zones (fetch async), uniquement si le champ zone est encore vide.
9) Supprimer une zone utilisée par des commandes ne la supprime pas : le serveur la DÉSACTIVE (soft delete). /settings expose aussi une bascule actif/inactif via PATCH { actif: !z.actif }.
10) Import Excel + IA (/products) : l'import est DÉJÀ écrit en base quand le dialog de revue s'ouvre. « Enregistrer » ne fait qu'un toast et referme ; « Modifier » referme et pré-remplit la recherche du tableau sur la 1re référence touchée (toast.info explicatif) ; SEUL « Annuler l'import » déclenche un appel réseau (POST /catalog/import-batches/<id>/cancel/). La revue IA est best-effort : si Ollama est muet, l'import reste valide.
11) Les doublons STRICTS / insensibles à la casse sont déjà bloqués côté Django (catalog/views.py::import_excel::_match_ci). /api/ai/check-duplicates ne cherche QUE les quasi-doublons (faute de frappe, « A05 » vs « A05S »).
12) Garde anti-course dans /products : la réponse IA n'est appliquée que si prev.batchId === res.batch_id (un second import lancé entre-temps invalide la réponse en vol).
13) /api/ai/check-duplicates renvoie TOUJOURS un statut 200, même en erreur ({ warnings: [], error }) — contrat explicite pour ne jamais faire échouer un import.
14) /api/ai/analyze renvoie au contraire un 500 en erreur, MAIS avec le message d'erreur dans le même champ `analysis` que le succès — le client affiche donc toujours ce champ, en rouge si !res.ok.
15) Le message d'erreur « autre » de /api/ai/analyze expose l'URL interne OLLAMA_BASE_URL au navigateur (fuite d'information d'infrastructure).
16) Timeout Ollama = 600 000 ms (10 minutes) sur les DEUX routes, avec think:false pour désactiver le raisonnement interne de qwen3, et nettoyage systématique des balises <think>...</think> (regex /gi). check-duplicates enlève en plus un éventuel fence ```json.
17) Modèle par défaut : qwen3:4b, base http://localhost:11434 (surchargeables par OLLAMA_MODEL / OLLAMA_BASE_URL). Changer un prompt impose de rebuild le conteneur frontend.
18) /reports : topMagasins n'est envoyé à l'IA que si isAdmin ; les chiffres financiers (ca, total_profit, total_stock_value/stock_value, benefice_estime_stock) viennent de GET /users/dashboard/ car c'est la seule source connaissant le coût d'achat, avec repli sur les totaux calculés localement. rupturesStock = produits à initial_quantity === 0 (15 max), stockBas = initial_quantity > 0 ET <= alert_threshold (15 max), produitsSansMouvement = produits absents de byProduct (15 max). La page se rafraîchit en temps réel (useRealtimeRefresh sur 'product_variant','order','stock_movement') mais l'analyse IA générée ne se régénère PAS.

PIÈGES / BUGS À NE PAS REPRODUIRE EN FLUTTER
19) ImageUpload : clearSelection() ne prévient jamais le parent (aucun onImageSelect(null)) — le parent conserve l'ancien File après « Changer l'image ». À corriger côté Flutter avec un callback onCleared.
20) ImageUpload : onUploadStart / onUploadEnd sont des props mortes (jamais invoquées) ; l'import Badge est mort aussi ; le texte « Format supporté: JPEG, PNG, WebP » est en dur et ne suit pas la prop acceptedFormats ; le message inline et le message du toast diffèrent pour l'erreur de format ; aucun handler onerror sur le FileReader.
21) ImageUpload et le drop ne prennent que files[0] (input sans `multiple`).
22) ProductImageGallery : selectedImage est calculé UNIQUEMENT au montage (initialiseur useState) — un changement de la prop images ne resynchronise pas la sélection. Le champ « Créée: » affiche new Date().toLocaleDateString(), c'est-à-dire LA DATE DU JOUR, pas la date de création réelle. Le bouton Télécharger est silencieusement inopérant si qr_code_image est absent. La suppression d'une image se fait SANS confirmation. Le setTimeout de l'état « copié » (2 s) n'est pas nettoyé au démontage. Toasts en anglais dans une UI française.
23) Le JSON copié par « Copier données » (4 champs) diffère du JSON encodé par generateQRCode (6 champs, avec size et colorVariant).
24) generateQRCode n'est pas idempotent : le timestamp ISO change à chaque appel, donc le PNG diffère à chaque génération.
25) lib/image-service.ts cible POST/DELETE /api/upload qui N'EXISTE PAS dans ce repo (app/api ne contient que ai/analyze et ai/check-duplicates) ; il n'utilise pas djangoClient donc n'enverrait aucun JWT ; batchUploadImages ignore productId, appelle la version base64 et saute silencieusement les fichiers en échec (tableau de résultats potentiellement plus court que l'entrée, correspondance d'index perdue) ; deleteImage n'encode pas le paramètre `path`. Tout ce module est aujourd'hui orphelin : à remplacer par un vrai upload multipart authentifié côté Flutter plutôt qu'à porter tel quel.
26) useDeliveryZones avale toutes les erreurs (zones = []) : impossible de distinguer « aucune zone configurée » d'une panne serveur ; le flag `loading` n'est exploité par aucun consommateur de /orders ; 3 fetches concurrents de la même liste sur la page commandes (à remplacer par un provider/cache unique en Flutter).
27) useDebouncedValue n'expose aucun indicateur « recherche en attente » pendant les 250 ms ; en Flutter, penser à annuler le Timer dans dispose().

PORTAGE FLUTTER — POINTS TECHNIQUES
28) FileReader/data URL base64 -> utiliser les bytes du fichier (image_picker/file_picker) et un upload multipart ; ne pas transporter du base64 (+33 % de poids).
29) next/image (images.unoptimized = true dans next.config.mjs, donc simple <img>) -> Image.network / Image.memory ; aspect-square + object-cover -> AspectRatio(1) + BoxFit.cover.
30) navigator.clipboard.writeText -> Clipboard.setData(ClipboardData(text: ...)) ; l'astuce du <a download> pour le QR -> écriture fichier + share_plus ou gal/saver.
31) Le drag & drop n'existe pas sur mobile : ne garder que le bouton « Sélectionner une image » (+ éventuellement l'appareil photo).
32) Timeouts : prévoir 10 minutes côté client pour les appels IA (les défauts de Dio/http sont bien plus courts et échoueraient avant Ollama), et une UI d'attente longue explicite comme la phrase « Génération en cours (modèle IA local — cela peut prendre plusieurs minutes)... ».
33) Le texte de l'IA est du texte BRUT sans markdown, à rendre avec préservation des sauts de ligne (équivalent whitespace-pre-wrap).
34) Formatage des montants dans /reports : Intl.NumberFormat('fr-MG') sur un nombre arrondi + suffixe ' Ar' -> NumberFormat.decimalPattern('fr') en Flutter (intl).

### Groupe `api-client`

PERIMETRE : les 5 fichiers demandes ne contiennent AUCUNE page ni route Next.js — ce sont la couche API, les types, la validation, le fuseau et un helper CSS. J'ai donc inventorie chaque SERVICE de django-client.ts comme une entree (contrat API complet a porter en Dart), et j'ai lu integralement les 1135 lignes de django-client.ts, ainsi que types.ts (108 l.), validation.ts (127 l.), timezone.ts (104 l.) et utils.ts (6 l.). J'ai aussi lu les fichiers voisins qui portent le gating de role et le temps reel (lib/auth/useCurrentUser.ts, lib/hooks/*, lib/contexts/DataSyncContext.tsx, lib/ws-utils.ts, lib/notifications-utils.tsx, lib/image-service.ts, lib/qrcode-generator.ts) car ils sont indispensables pour comprendre roles et rafraichissements ; ils sont classes en sharedComponents.

DEUX NOMENCLATURES DE ROLE COEXISTENT — piege majeur du portage :
- Backend / useCurrentUser : 'admin' | 'magasin' | 'employer' (+ sous-role commande_role 'PREPARATEUR' | 'LIVREUR' | null uniquement pour employer).
- Front historique / types.ts / auth.getCurrentUser : 'admin' | 'store_manager' | 'employee'.
auth.register traduit dans le sens front->backend (store_manager->magasin, employee->employer) et auth.getCurrentUser traduit dans le sens inverse. En Flutter, choisir UNE seule enumeration (recommande : celle du backend) et centraliser la traduction.

CORRESPONDANCE DES ROLES METIER (module Commandes) :
- GERANT = admin OU magasin (isGerant). Cree/modifie/supprime/annule les commandes, assigne preparateur et livreur, gere catalogue, zones, caisse, fournisseurs, utilisateurs.
- PREPARATEUR = employer + commande_role 'PREPARATEUR'. Demarre puis termine la preparation.
- LIVREUR = employer + commande_role 'LIVREUR'. Prend en livraison, livre (avec photo), declare un retour.
- superadmin n'existe pas comme role distinct : isSuperAdmin === isAdmin. La seule nuance au-dessus est isCompanyOwner = admin ayant un AdminProfile (proprietaire reel de la societe) ; un co-admin ajoute via 'Ajouter un administrateur' partage l'acces complet aux donnees mais PAS les actions de propriete (gestion des autres admins).
- backup.export/import et transfers.getProfitByMagasins sont marques 'admin only' dans le code.
- zones : lecture ouverte a tous, ecriture reservee au gerant.
AUCUN de ces controles n'est applique dans django-client.ts : le gating client se fait dans les pages avec les drapeaux de useCurrentUser, le backend re-verifie systematiquement.

REGLE DU 'JOUR J' (la plus subtile) : un preparateur/livreur ne peut agir sur une commande qu'a partir de sa date planifiee. Cette date doit etre calculee dans le fuseau Indian/Antananarivo (UTC+3 fixe, pas d'heure d'ete) partout — sinon, entre 00h00 et 03h00 a Antananarivo, un client en UTC est encore la veille et le serveur refuse la commande du jour. Le backend fixe TIME_ZONE='Indian/Antananarivo' et lib/timezone.ts fait pareil cote navigateur. En Flutter, ne JAMAIS utiliser DateTime.now() local pour ce calcul : appliquer un offset fixe +03:00.

CYCLE DE VIE D'UNE COMMANDE (6 statuts + 2 terminaux) : NOUVELLE -> EN_PREPARATION -> PRETE -> EN_LIVRAISON -> LIVRE, plus RETOUR et ANNULEE. Chaque transition passe par POST /orders/{id}/status/ avec note optionnelle ; la livraison peut porter une PHOTO (bascule l'appel en multipart). L'annulation a son propre endpoint POST /orders/{id}/cancel/. Le statut courant de l'objet s'appelle statut_courant. Une commande n'est MODIFIABLE (PATCH /orders/{id}/) que tant qu'elle est NOUVELLE.

PRE-ASSIGNATION SANS PROGRESSION DE STATUT (regle metier explicite dans les commentaires du code) :
- assignPreparateur : la commande RESTE 'Nouvelle' (en attente) ; c'est le preparateur qui doit cliquer lui-meme 'Commencer la preparation' pour passer EN_PREPARATION.
- assignLivreur : pre-assigne un livreur AVANT que la commande soit Prete, sans changer le statut ; l'assignation est reutilisee automatiquement au passage 'En livraison' (_resolve_assignee cote backend).
- availableStaff(role, magasinId, dateCommande) : pour un LIVREUR, le drapeau `available` SIGNALE un conflit d'horaire avec une autre commande deja (pre-)assignee le meme jour/heure — c'est un AVERTISSEMENT, il ne doit PAS bloquer la selection.

ZONES DE LIVRAISON : la valeur envoyee dans une commande est le `code` de la zone (pas son id), ou la valeur speciale 'RECUPERATION' (retrait sur place). La suppression d'une zone deja utilisee par des commandes est en realite une DESACTIVATION (actif=false) cote serveur. La vente sur place passe donc par une commande en zone 'RECUPERATION' : le module Ventes/Ticket (caisse rapide) a ete supprime.

SERVICES DE COMPATIBILITE A NE PAS PRENDRE POUR ARGENT COMPTANT :
- products.* ne tape aucun endpoint /products/ : il liste TOUTES les references puis filtre et cherche EN MEMOIRE (pas de pagination, pas de recherche serveur, cout memoire proportionnel au catalogue).
- mapReferenceToProduct force unit_price, purchase_price, expiry_date, image1/2/3 et qr_code a null ; seul shell_price (= prix_vente) porte un prix ; initial_quantity = somme des stocks de variantes ; alert_threshold = min des seuils (defaut 1) ; variants[].size est toujours la chaine vide.
- sales.* reconstitue des ventes a partir des seules commandes LIVRE, avec is_paid code en dur a true et total_profit code en dur a 0 : tout indicateur de marge base la-dessus vaut 0. Le vrai benefice vient de caisse.summary (ca_produits_vendus / cout_produits_vendus / benefice_produits_vendus).
- dashboard.* appelle 4 fois le MEME endpoint GET /users/dashboard/ et ignore tous ses parametres (storeId, limit, period) ; a mutualiser en un appel unique en Flutter.
- users.list(role) ignore le parametre role ; users.getById(id) IGNORE l'id et retourne toujours /users/me/ (bug de compatibilite a ne pas reproduire) ; getEmployeesByStore filtre en memoire la liste des magasins et lit .employers.

CONVENTION DE SUFFIXE COULEUR (appliquee dans movements et sales) : le nom affiche est `reference_name (couleur)` SAUF si la couleur vaut 'Standard' ou est absente — dans ce cas, pas de suffixe. A reproduire tel quel.

SIGNE DES MOUVEMENTS : movements.list renvoie un champ `change` DEJA signe (negatif pour type 'SORTIE'). Les 6 origines sont traduites en francais cote client : PREPARATION -> 'Preparation de commande', RETOUR -> 'Retour de commande', ANNULATION -> 'Annulation de commande', LIVRE -> 'Commande livree', FOURNISSEUR -> 'Reception fournisseur', AJUSTEMENT -> 'Ajustement manuel'. Une origine inconnue est affichee brute.

STOCK : il n'existe volontairement PAS de variants.update — toute correction de stock passe par POST /catalog/variants/{id}/adjust/ avec type ENTREE|SORTIE, quantite et note, pour garantir la tracabilite (le mouvement genere porte l'auteur).

IMPORT EXCEL : la reponse est un FICHIER (rapport) et non du JSON ; le resume arrive dans des en-tetes personnalisees X-Import-* (exposees par CORS_EXPOSE_HEADERS). Le X-Import-Batch-Id permet une ANNULATION post-import (POST /catalog/import-batches/{id}/cancel/) qui supprime ce qui a ete cree et restaure les valeurs precedentes de ce qui a ete mis a jour. Les listes de noms sont du JSON dans un en-tete, parsees dans un try/catch avec repli [].

CAISSE : GET /users/caisse/sessions/current/ renvoie 204 quand aucune session n'est ouverte ; grace au traitement des corps vides dans request(), ce cas est normalise en NULL (et non en erreur). C'est le signal 'caisse fermee' de l'UI. Le champ `reason` d'un mouvement est obligatoire dans la signature. Les montants acceptent number OU string a l'envoi.

REFRESH JWT : le premier 401 declenche un refresh ; les appels concurrents ne relancent PAS de refresh, ils attendent dans refreshQueue et recoivent le meme token. La requete n'est rejouee QU'UNE fois. Si le refresh echoue en HTTP, les tokens sont purges ET la page est redirigee en dur vers /login. isAuthenticated() ne verifie que la PRESENCE de l'access token, jamais son expiration.

LOGOUT : appelle POST /users/logout-event/ (echec ignore), puis un POST /users/refresh/ avec le refresh token (fire-and-forget, comportement inhabituel mais present), puis localStorage.clear() qui efface TOUT le stockage local, pas seulement les tokens. En Flutter, purger aussi les preferences applicatives pour rester fidele.

SUPPRESSION D'UTILISATEUR : DELETE /users/delete/{id}/ envoie un BODY {password} — le mot de passe de l'operateur est exige. Peu de clients HTTP Dart envoient un corps sur DELETE par defaut : utiliser dio ou http.Request('DELETE', ...) avec body.

TEMPS REEL : deux WebSockets distincts, tous deux authentifies par un token JWT passe en QUERYSTRING (?token=). /ws/notifications/ pour les notifications (toast 5 s), /ws/data/ pour la synchronisation des donnees (evenements {model, action, id, magasin_id} sur product_variant, stock_movement, order, order_status_history, supplier_order, caisse_session, caisse_movement). Reconnexion automatique apres 3 s si le code de fermeture n'est pas 1000. Les ecrans se rafraichissent via useRealtimeRefresh avec un debounce de 400 ms pour absorber les rafales d'evenements lies (vente -> produit -> mouvement).

FORMATS D'AFFICHAGE : dates en fr-FR (JJ/MM/AAAA et JJ/MM/AAAA HH:mm) toujours converties dans le fuseau Indian/Antananarivo, valeur vide affichee '—' (tiret cadratin). Exception a corriger : formatNotificationDate n'applique pas le fuseau applicatif.

MESSAGES D'ERREUR : aucune validation client sur les formulaires reellement branches (commandes, catalogue, caisse, fournisseurs) — tout vient du backend et est aplati par request() en `champ: message | champ2: message`. En Flutter, prevoir de re-eclater cette chaine pour repositionner les erreurs sous les bons champs, ou consommer directement le JSON d'erreur (il faudrait alors modifier la couche transport).

DETAIL A NE PAS OUBLIER : dans les querystrings, les filtres ne sont ajoutes que si la valeur est TRUTHY — un id valant 0 ou une chaine vide serait donc silencieusement ignore. A l'inverse, dans changeStatus les ids d'assignee sont testes avec `!= null`, donc 0 y est bien transmis. Incoherence a reproduire ou a harmoniser sciemment.

## 7. Etat du projet Flutter existant

### Groupe `infra`

#### `smartcross/lib/features/auth/login_screen.dart`

- **Route** : /login (GoRoute racine, hors ShellRoute, prefixe public)
- **Role** : Tous (ecran pre-authentification) — aucune distinction de role, la redirection post-login est faite par le router via _homeFor(role)

**Implemente** (10)

- ConsumerStatefulWidget + Form(GlobalKey<FormState>) avec validation locale avant appel reseau
- Champ Email : TextEditingController, keyboardType emailAddress, prefixIcon email_outlined, validator = 'Email invalide' si null ou ne contient pas '@'
- Champ Mot de passe : obscureText pilote par _obscure, prefixIcon lock_outline, suffixIcon IconButton visibility/visibility_off qui bascule _obscure, validator 'Mot de passe requis' si vide, onFieldSubmitted declenche _submit()
- Bouton FilledButton 'Se connecter' : desactive pendant _loading, remplace son label par un CircularProgressIndicator(strokeWidth: 2) 18x18
- Appel ref.read(authProvider.notifier).login(email.trim(), password) — pas de context.go() explicite, la navigation est assuree par le redirect go_router sur changement de AuthStatus
- Banniere d'erreur conditionnelle (Container errorContainer/onErrorContainer, radius 10) affichee au-dessus des champs quand _error != null
- Traduction des erreurs serveur via ApiClient.messageFromError + heuristique sur le texte en minuscules : 'désactivé'/'inactive' -> 'Compte désactivé. Contactez le gérant.' ; 'no active account'/'incorrect'/'invalid' -> 'Email ou mot de passe incorrect.' ; sinon message brut
- AppBar sans back (automaticallyImplyLeading: false) avec une seule action : IconButton dns_outlined, tooltip 'Configurer le serveur', context.push('/server-setup')
- Mise en page responsive : Center + SingleChildScrollView + ConstrainedBox(maxWidth: 420), logo carre 72x72 en primary avec Icons.phone_iphone, titre 'Smartphone.Mg' et sous-titre 'Commandes, stock & livraisons'
- dispose() des deux TextEditingController

**Manques constates** (8)

- Aucun lien 'Mot de passe oublié' — le frontend Next.js a /forgot-password + components/auth/forgot-password-form.tsx et un lien depuis le formulaire de login
- Aucun lien / ecran d'inscription — le frontend a /register + components/auth/register-form.tsx et un lien 'Créer un compte' sous le formulaire
- Aucun ecran de reinitialisation (/reset-password), de verification d'email (/verify-email) ni d'attente d'approbation (/pending-approval, /auth/pending-approval) presents cote Next.js
- Pas d'AutofillGroup / autofillHints (email, password) ni de textInputAction next/done explicite
- Validator email tres permissif (simple presence de '@')
- Aucune memorisation du dernier email saisi, pas de case 'se souvenir de moi'
- Aucun traitement specifique du cas 'serveur injoignable' (ApiClient.isConnectivityError existe mais n'est pas utilise ici pour proposer /server-setup)
- Le titre de marque est 'Smartphone.Mg' alors que le frontend Next.js s'intitule 'E-kajy Entana' — divergence de branding a arbitrer

#### `smartcross/lib/features/auth/server_setup_screen.dart`

- **Route** : /server-setup (GoRoute racine, prefixe public)
- **Role** : Tous (ecran pre-authentification). Inaccessible une fois connecte : le redirect renvoie tout utilisateur authentifie de _publicPrefixes vers _homeFor(role)

**Implemente** (7)

- StatefulWidget simple (pas de Riverpod) avec AppBar 'Configuration du serveur'
- TextField unique pre-rempli dans initState avec ApiClient.instance.baseUrl, labelText 'URL du serveur', hintText 'http://192.168.1.10:8010', prefixIcon Icons.link, keyboardType TextInputType.url
- Bouton FilledButton 'Enregistrer' : desactive pendant _saving, spinner 18x18 en remplacement du label
- Enregistrement : ApiClient.instance.setBaseUrl(url) (normalise le slash final et reconstruit baseUrl = <url>/api/) puis AppPrefs.instance.setServerBaseUrl(url) (SharedPreferences)
- Retour : context.pop() si canPop(), sinon context.go('/login')
- Garde no-op si le champ est vide (return avant setState)
- Texte explicatif centre + Icon dns_outlined 40, ConstrainedBox(maxWidth: 480)

**Manques constates** (6)

- Aucun test de connectivite / ping du serveur avant enregistrement (pas d'appel de sante, pas de retour succes/echec)
- Aucune validation de format d'URL (schema http/https, port) — seule la chaine vide est rejetee
- Aucun message d'erreur ni SnackBar de confirmation apres sauvegarde
- Pas d'historique/liste des serveurs recents, pas de bouton 'Réinitialiser à la valeur par défaut' (kDefaultServerUrl)
- Non accessible depuis l'application connectee (aucune entree dans kPrimaryNavItems, aucun acces depuis /settings verifie ici)
- Le changement d'URL ne force pas la deconnexion ni la reconnexion du WebSocket notifications deja etabli

#### `smartcross/lib/features/auth/splash_screen.dart`

- **Route** : /splash (initialLocation du GoRouter, prefixe public)
- **Role** : Tous — ecran affiche tant que AuthStatus == loading

**Implemente** (2)

- StatelessWidget de 26 lignes : Scaffold + Center + Column contenant le logo 72x72 (primary, radius 18, Icons.phone_iphone blanc) et un CircularProgressIndicator
- Aucune logique propre : c'est le redirect du router (case AuthStatus.loading -> force '/splash') combine a AuthNotifier._bootstrap() qui pilote la sortie de cet ecran

**Manques constates** (4)

- Aucun timeout ni etat d'erreur : si _bootstrap reste bloque (serveur injoignable, timeout Dio de 20-30s), l'ecran tourne indefiniment sans issue utilisateur
- Aucun bouton de secours vers /server-setup en cas d'echec de contact du serveur
- Aucun affichage de version d'app / nom de serveur configure
- Pas d'animation ni de branding au-dela du logo

**Infrastructure reutilisable** (21)

- ROUTER — /home/garrix/Dev/Smartphone/smartcross/lib/core/router.dart : `routerProvider` (Provider<GoRouter>), initialLocation '/splash', refreshListenable = _RouterRefresh qui ecoute authProvider et notifie UNIQUEMENT quand `status` change (un changement de role/user sans changement de status ne redeclenche pas le redirect).
- ROUTER — gardes : `_publicPrefixes = ['/login','/server-setup','/splash']`. redirect() switch sur auth.status : loading -> force '/splash' ; unauthenticated -> laisse passer /login et /server-setup, tout le reste (y compris /splash) -> '/login' ; authenticated -> si route publique, redirige vers `_homeFor(role)` (gerant -> /dashboard, preparateur -> /depot, livreur -> /tournee, unknown/null -> /login), sinon laisse passer. IMPORTANT : AUCUNE garde par role sur les routes protegees — un livreur qui fait context.go('/users') ou /dashboard n'est pas bloque par le router ; le filtrage par role n'existe que dans la barre de navigation (kPrimaryNavItems.visibleFor).
- ROUTER — arbre de routes deja declare : 3 routes racines publiques (/splash, /server-setup, /login) puis une ShellRoute unique (builder -> NavigationShell(currentPath: state.matchedLocation)) contenant /dashboard, /caisse, /orders (+ sous-routes 'new' et ':id' avec int.parse du pathParameter), /depot, /tournee, /bilan, /catalog, /suppliers (+ 'new' et ':id'), /users, /stores, /transfers, /chats (+ 'room/:room' et 'dm/:id' avec `state.extra as String?` pour le titre), /notifications, /settings. Modele a copier pour ajouter un ecran : un GoRoute dans la ShellRoute + un NavItem dans kPrimaryNavItems.
- THEME — /home/garrix/Dev/Smartphone/smartcross/lib/core/theme.dart : buildLightTheme()/buildDarkTheme() bases sur ColorScheme.fromSeed(seed 0xFF2563EB), Material 3, AppBarTheme plat (elevation 0, surfaceTintColor transparent), CardThemeData (radius 14, bordure outlineVariant, elevation 0), InputDecorationTheme (OutlineInputBorder radius 10, filled avec surfaceContainerHighest a 30%). Exposes aussi : `kChartPalette` (8 couleurs pour fl_chart) et `statusColor(context, apiStatus)` qui mappe les 7 statuts de commande vers des couleurs fixes. main.dart applique themeMode: ThemeMode.system (aucun selecteur de theme utilisateur).
- AUTH / TOKENS — /home/garrix/Dev/Smartphone/smartcross/lib/core/secure_storage.dart : `TokenStorage` singleton sur FlutterSecureStorage (cles 'access_token'/'refresh_token', methodes save/saveAccess/accessToken/refreshToken/clear) et `AppPrefs` singleton sur SharedPreferences (cle 'server_base_url'). Aucun stockage du user en cache local : /me/ est rappele a chaque bootstrap.
- AUTH — /home/garrix/Dev/Smartphone/smartcross/lib/state/auth_provider.dart : `authProvider` = NotifierProvider<AuthNotifier, AuthState>. AuthState = {AuthStatus loading|unauthenticated|authenticated, AppUser? user}. build() ecoute `authEventProvider` (pont StreamProvider vers AuthEvents.instance, emis par ApiClient sur 401 non rafraichissable) et bascule en unauthenticated, puis lance _bootstrap() en microtask. _bootstrap : ApiClient.ensureInitialized() -> lit accessToken -> si vide unauthenticated, sinon repo.me() (catch -> unauthenticated). login(email,password) : repo.login puis repo.me puis _invalidateDataProviders(ref) puis authenticated. logout() : repo.logout (efface les tokens, PAS d'appel serveur) + invalidation + unauthenticated. refreshUser() : re-appelle me() en gardant l'utilisateur en cache si echec. `_invalidateDataProviders` invalide 19 providers metier a chaque login/logout (orders, orderDetail, categories, types, brands, colors, references, referenceAutocomplete, dashboard, ruptures, movements, supplierOrders, supplierOrderDetail, notifications, currentCaisse, caisseHistory, accounts, pendingUsers, stores) — a etendre pour tout nouveau provider.
- API CLIENT — /home/garrix/Dev/Smartphone/smartcross/lib/core/api_client.dart : singleton `ApiClient.instance` sur Dio (connectTimeout 20s, receiveTimeout 30s, Accept: application/json). baseUrl configurable + normalise, options.baseUrl = '<url>/api/'. `kDefaultServerUrl` sensible a la plateforme (10.0.2.2:8010 sur Android, 127.0.0.1:8010 sinon). Interceptor onRequest : injecte 'Authorization: Bearer <access>' depuis TokenStorage. Interceptor onError : sur 401 non deja rejoue, appelle _tryRefresh() (POST users/refresh/ avec le refresh token, sauvegarde le nouvel access) puis rejoue la requete d'origine avec extra['retried']=true ; si le refresh echoue, emet AuthEvent(sessionExpired) sur le bus AuthEvents. Helpers statiques reutilisables : `ApiClient.isConnectivityError(e)` et `ApiClient.messageFromError(e)` (extrait error/detail/message, sinon aplatit les erreurs de validation DRF {champ: [msgs]}, sinon message reseau lisible). `wsBaseUrl` derive ws://wss:// depuis la base HTTP.
- CONSTANTES METIER — /home/garrix/Dev/Smartphone/smartcross/lib/core/constants.dart : enums + extensions fromApi/apiValue/label pour UserRole (gerant/preparateur/livreur/unknown <-> GERANT/PREPARATEUR/LIVREUR), OrderStatus (7 valeurs : NOUVELLE, EN_PREPARATION, PRETE, EN_LIVRAISON, LIVRE, RETOUR, ANNULEE), PaymentMode (AVANT/LIVRAISON), StockMovementType (ENTREE/SORTIE), SupplierOrderStatus (BROUILLON/COMMANDE/RECU). Plus `kDesktopBreakpoint = 900` et `dialogWidth(available, desired)`. Les zones de livraison ne sont PAS une enum : elles viennent du serveur (models/delivery_zone.dart + deliveryZonesProvider).
- TEMPS — /home/garrix/Dev/Smartphone/smartcross/lib/core/app_time.dart : fuseau metier fige a UTC+3 (Indian/Antananarivo). Fonctions reutilisables appNow(), appLocal(instant), appDay(instant), appToday(), appWallClockToUtc(wallClock) et appDayBounds([day]) -> ({start, end}) en UTC pour les filtres date_from/date_to. A utiliser systematiquement pour tout nouvel ecran manipulant des dates.
- NAVIGATION — /home/garrix/Dev/Smartphone/smartcross/lib/core/nav_items.dart : `NavItem {path, label, icon, Set<UserRole>? roles}` + `visibleFor(role)` (roles null = tous) et la liste const `kPrimaryNavItems` de 14 entrees. Repartition actuelle : gerant -> /dashboard, /orders, /caisse, /catalog, /suppliers, /stores, /transfers, /users ; preparateur -> /depot ; livreur -> /tournee, /bilan ; tous -> /chats, /notifications, /settings.
- SHELL — /home/garrix/Dev/Smartphone/smartcross/lib/widgets/navigation_shell.dart : ConsumerStatefulWidget qui lit authProvider, retourne SizedBox.shrink() si user null, filtre kPrimaryNavItems par role, puis bascule sur MediaQuery.sizeOf(context).width >= kDesktopBreakpoint : sidebar permanente 240px + VerticalDivider en large, Drawer + bouton menu dans la TopBar en etroit. La selection d'un item utilise currentPath.startsWith(item.path) et context.go(item.path) (ferme le Drawer avant).
- TOPBAR — /home/garrix/Dev/Smartphone/smartcross/lib/widgets/topbar.dart : ConsumerWidget implements PreferredSizeWidget (hauteur 64). Contient : bouton menu conditionnel (onMenuTap), logo + libelle 'Smartphone.Mg', pastille verte/orange pilotee par wsConnectionStatusProvider avec Tooltip 'Temps réel connecté'/'Connexion au serveur…', IconButton Notifications avec material.Badge alimente par unreadNotificationsCountProvider (context.push('/notifications')), PopupMenuButton compte affichant fullName/email/role.label (item desactive) + separateur + 'Déconnexion' qui appelle authProvider.notifier.logout() puis context.go('/login'). Aucun acces au profil/parametres depuis ce menu.
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/core/ws_manager.dart : classe abstraite `WsManager` sur web_socket_channel — connect(buildUri) avec builder rappele a chaque tentative (donc token frais), await channel.ready, decodage JSON de chaque trame, reconnexion automatique apres 3s sauf disconnect() explicite, garde _connecting/_closedByUser, hooks onMessage(Map) et onStatusChange(bool), send(String) brut. Base a reutiliser pour toute nouvelle socket.
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/core/notifications_socket_service.dart : singleton `NotificationsSocketService.instance` (WsManager) exposant `incoming` (Stream<Map>) et `connectionStatus` (Stream<bool>), connecte sur ws://<host>/ws/notifications/?token=<access>.
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/core/chat_socket_service.dart : `ChatSocketService` (instance jetable par ecran de conversation) — connectToConversation({recipientId}) vers /ws/chat/?token=..&recipient_id=.., heartbeat de presence ping toutes les 20s quand connecte, actions sendMessage(content), editMessage(id, content), deleteMessage(id), markRead(). Tout l'envoi passe par la socket, pas par REST. disposeService() ferme timer + socket + les 2 StreamController.
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/state/realtime_provider.dart : `realtimeBootstrapProvider` instancie une fois dans main.dart ; il ecoute authProvider (fireImmediately) pour connecter/deconnecter la socket notifications, et bump `realtimeTickProvider` (NotifierProvider<int>) a chaque message recu. Tout provider de donnees peut watcher realtimeTickProvider pour se rafraichir automatiquement. `wsConnectionStatusProvider` (StreamProvider<bool>) alimente la pastille de la TopBar.
- PROVIDERS RIVERPOD EXISTANTS (lib/state/) : authProvider, authEventProvider, authRepositoryProvider | ordersProvider (AsyncNotifier<List<Order>>), ordersFilterProvider (NotifierProvider<OrdersFilter>), orderDetailProvider (FutureProvider.autoDispose.family<Order,int>), deliveryZonesProvider, ordersRepositoryProvider | dashboardProvider + dashboardFilterProvider + dashboardRepositoryProvider | catalog : categoriesProvider, typesProvider, brandsProvider, colorsProvider, referencesProvider, referenceAutocompleteProvider (family<String>), catalogRepositoryProvider | stock : rupturesProvider, movementsProvider (AsyncNotifierProvider.family<int?>), stockRepositoryProvider | suppliers : supplierOrdersProvider, supplierOrderDetailProvider (family<int>), suppliersRepositoryProvider | users : accountsProvider, pendingUsersProvider, usersRepositoryProvider | stores : storesProvider, storesRepositoryProvider | caisse : currentCaisseProvider, caisseHistoryProvider, caisseRepositoryProvider | notifications : notificationsProvider, unreadNotificationsCountProvider, notificationsRepositoryProvider | company : passwordResetRequestsProvider, companyRepositoryProvider | realtime : realtimeTickProvider, realtimeBootstrapProvider, wsConnectionStatusProvider. Convention : un `xxxRepositoryProvider` = Provider((ref) => XxxRepository()), un AsyncNotifier par collection avec une methode refresh().
- REPOSITORIES EXISTANTS (lib/data/repositories/) : AuthRepository (login, logout, me, updateProfile{fullName,phone,adresse}, uploadProfilePhoto(filePath) en FormData, changePassword) | OrdersRepository (list avec filtres, detail, create, changeStatus, cancel, update, delete, availableStaff(role, dateCommande), assignLivreur, assignPreparateur, deliveryZones, + classe StaffOption) | CatalogRepository (CRUD complet categories/types/brands/colors/references/variants, uploadReferencePhoto, autocomplete, bulkUpdatePrice, exportExcelBytes -> Uint8List, importExcel -> ExcelImportResult) | StockRepository (movements, adjust, ruptures, ruptureExportPdfBytes) | SuppliersRepository (list, detail, create, receive) | UsersRepository (list, create, updateCommandeRole, delete(password), pending, approve, reject) | StoresRepository (list, create, rename, delete(password), catalogFor, transfer + TransferItem) | CaisseRepository (current, history, open, close, addMovement) | ChatRepository (users, history{recipientId, roomName}) | NotificationsRepository (list, markRead, markAllRead) | DashboardRepository (fetch{dateDebut,dateFin}) | CompanyRepository (passwordResetRequests, resolvePasswordReset). Tous utilisent ApiClient.instance.dio avec des chemins relatifs a /api/.
- WIDGETS PARTAGES REUTILISABLES (lib/widgets/) : async_state_widgets.dart -> LoadingState, ErrorState(message, onRetry) avec bouton 'Réessayer', EmptyState(message, icon) | kpi_card.dart -> KpiCard(label, value, icon, accentColor, subtitle) et KpiGrid (grille responsive 2/3/4/5 colonnes selon la largeur, mainAxisExtent 128) | status_badge.dart -> StatusChip(label, color), OrderStatusBadge(status) branche sur statusColor(), StockLevelBadge(isRupture, isStockBas) | assign_staff_dialog.dart -> showAssignStaffDialog(...) -> AssignResult{staffId, assignedAt} avec chargement asynchrone du personnel | order_confirm_dialog.dart -> showOrderConfirmDialog(..., showPhoto) -> OrderConfirmResult{note, photoPath}, formats money NumberFormat.decimalPattern('fr_FR') et date DateFormat('dd/MM/yyyy') | order_historique_view.dart -> OrderHistoriqueView(cardBuilder) reutilisable pour les vues historique.
- MODELES (lib/models/) : app_notification, caisse, catalog, chat, company, dashboard, delivery_zone, magasin, order, stock, supplier, user (AppUser avec id, fullName, email, role UserRole, isActive, phone, adresse, photo, createdAt, lastLoginAt, lastLogoutAt, magasinId, shopName, rawRole Django admin/magasin/employer, isCompanyOwner ; + PendingUser) et json_utils.dart (helpers asInt/asString... a reutiliser pour tout nouveau modele).
- DEPENDANCES DEJA DECLAREES dans pubspec.yaml et disponibles pour de nouveaux ecrans : flutter_riverpod 3.4.2, go_router 17.3.0, dio 5.11, web_socket_channel 3.0.3, flutter_secure_storage 10.3.1, shared_preferences 2.5.5, fl_chart 1.2.0 (graphiques dashboard), intl 0.20.3, collection, printing 5.14.3 + pdf 3.13 (impression/PDF), share_plus 13.3, path_provider, url_launcher 6.3.2, image_picker 1.2.0, file_picker 12.2.0. Deux dependances declarees mais JAMAIS utilisees dans lib/ : flutter_local_notifications 22.2.0 (aucune notification systeme cablee) et connectivity_plus 7.3.1 (aucune detection hors-ligne).

**Notes**

NIVEAU DE COMPLETUDE GLOBAL DU PERIMETRE AUDITE : l'infrastructure est solide et complete (router + shell + theme + client HTTP avec refresh JWT + stockage securise + websockets + 12 repositories + ~30 providers Riverpod deja en place). C'est la partie AUTH qui est la plus mince : seulement 3 ecrans (login 136 l., server-setup 92 l., splash 26 l.), soit le strict minimum email/mot de passe.

ECARTS STRUCTURANTS CONSTATES (verifies dans le code) :
1. Aucune garde de role dans le router. redirect() ne teste que AuthStatus ; les 17 routes de la ShellRoute sont accessibles a n'importe quel role authentifie par context.go/push ou deep link. Le cloisonnement par role n'existe que visuellement (kPrimaryNavItems.visibleFor dans NavigationShell) et ponctuellement dans 4 ecrans seulement (settings_screen.dart l.115/153/338, catalog_screen.dart l.222, order_create_screen.dart l.80). Il faudra ajouter une garde `roles` par route pour un portage fidele.
2. Parcours d'authentification incomplet face au frontend Next.js. Le Next a 9 routes d'auth/publiques : /login, /register, /forgot-password, /reset-password, /verify-email, /pending-approval, /auth/pending-approval, /logout, / (racine) — avec les composants components/auth/register-form.tsx, forgot-password-form.tsx, reset-password-form.tsx, admin-guard.tsx, superadmin-guard.tsx. Cote Flutter il n'existe QUE /login. Aucun ecran d'inscription, de mot de passe oublie, de reset, de verification email, ni d'attente d'approbation. A noter : le cote gerant a bien passwordResetRequestsProvider + CompanyRepository.resolvePasswordReset (le gerant peut traiter les demandes) mais l'utilisateur n'a aucun moyen d'EMETTRE une demande depuis l'app.
3. Routes Next.js sans equivalent Flutter (a porter) : /alerts, /movements, /pickup, /products (vs /catalog cote Flutter), /reports, /sales, /superadmin. Routes Flutter sans equivalent Next visible : /depot, /tournee, /orders/new, /orders/:id, /suppliers/new, /suppliers/:id, /chats/room/:room, /chats/dm/:id, /server-setup (specifique mobile). Correspondances directes : /dashboard, /caisse, /orders, /bilan, /chats, /notifications, /settings, /stores, /suppliers, /transfers, /users.
4. Divergence de branding : l'app Flutter s'appelle partout 'Smartphone.Mg' (main.dart title, topbar, login, splash) alors que le frontend Next.js affiche 'E-kajy Entana' (metadata de app/login/page.tsx). A trancher avant le portage.
5. Deux dependances installees mais mortes : flutter_local_notifications (aucune notification systeme malgre la socket /ws/notifications/ deja fonctionnelle — le seul rendu est le badge de la TopBar) et connectivity_plus (aucune gestion hors-ligne, alors que ApiClient.isConnectivityError existe deja et n'est appele nulle part dans lib/).
6. Points de fragilite mineurs releves a la lecture : _RouterRefresh ne notifie que sur changement de `status`, donc un changement de role a status constant ne redeclenche pas de redirection ; AuthState.copyWith ne peut pas remettre `user` a null (`user ?? this.user`) ; logout() est purement local (efface les tokens, aucun appel serveur de revocation/blacklist du refresh) ; SplashScreen n'a ni timeout ni issue de secours si le bootstrap reste bloque ; changer l'URL serveur depuis /server-setup ne reconnecte pas la socket notifications deja ouverte.

CE QUI EST DIRECTEMENT REUTILISABLE POUR PORTER UN NOUVEL ECRAN : ajouter un GoRoute dans la ShellRoute de core/router.dart + un NavItem dans core/nav_items.dart (avec son Set<UserRole>) ; creer un Repository sur ApiClient.instance.dio ; creer un AsyncNotifier + provider dans lib/state/ (avec refresh()) et l'ajouter a _invalidateDataProviders de auth_provider.dart ; consommer realtimeTickProvider si l'ecran doit reagir au temps reel ; utiliser LoadingState/ErrorState/EmptyState, KpiCard/KpiGrid, StatusChip/OrderStatusBadge/StockLevelBadge pour l'UI ; utiliser app_time.dart pour toute date et ApiClient.messageFromError pour tout message d'erreur.

### Groupe `orders`

#### `smartcross/lib/features/orders/orders_list_screen.dart`

- **Route** : /orders (GoRoute dans ShellRoute, core/router.dart:257) + enfants 'new' et ':id'
- **Role** : Gerant uniquement (filtrage via kPrimaryNavItems roles:{gerant}) — AUCUN garde de route cote go_router, la restriction est seulement dans le menu

**Implemente** (9)

- AppBar 'Commandes' avec 3 actions: filtre date (showDatePicker, un seul jour, met dateDebut=dateFin), filtre preparateur (_PreparateurPickerDialog qui charge availableStaff('PREPARATEUR') et propose 'Tous' + chaque preparateur), PopupMenuButton statut (Tous / 'Pas encore livree' (NON_LIVREE, filtre client-side) / les 7 OrderStatus)
- Barre de Chips actifs supprimables: statut, date (format dd/MM/yyyy), 'Preparateur', 'Pas encore livree'
- Liste ListView.builder de _OrderTile + RefreshIndicator (pull-to-refresh -> ordersProvider.refresh())
- Etats AsyncData/AsyncError/loading via EmptyState('Aucune commande.') / ErrorState(ApiClient.messageFromError + Reessayer) / LoadingState
- _OrderTile: tap -> context.push('/orders/:id'); affiche numero, 'client · zone courte' (DeliveryZoneCatalog.shortLabelFor), ligne 'Preparateur : X · date de passage EN_PREPARATION' (derivee de statusHistory), ligne 'Livreur : X · Prevu le / Livre le' (dateCommande si pas livre, sinon horodatage LIVRE), OrderStatusBadge et totalAPayer formate 'n Ar'
- Bouton Modifier sur la carte si statut NOUVELLE ou EN_PREPARATION -> EditOrderDialog
- Bouton Supprimer (rouge) si statut NOUVELLE -> AlertDialog de confirmation puis ordersProvider.delete(id), erreur en SnackBar
- FloatingActionButton.extended 'Nouvelle commande' -> /orders/new
- EditOrderDialog (exporte, reutilise par order_detail_screen): edition articles (liste des CartLine avec suppression + 'Ajouter un article' -> AddOrderLineDialog), Nom client, Telephone (validation regex ^\+261\d{9}$), Date+heure de livraison (showDatePicker + showTimePicker, heure mur Antananarivo via appWallClockToUtc), Dropdown zone (zones actives + 'Recuperation (0 Ar)'), Dropdown Preparateur, si non-recuperation: Adresse, Dropdown Paiement (AVANT/LIVRAISON), Dropdown Livreur, Note preparateur, Note livreur; submit -> updateOrder puis assignPreparateur/assignLivreur si change (echecs signales en SnackBar sans bloquer), etat _submitting + message d'erreur inline

**Manques constates** (9)

- Aucun champ de recherche libre — le web a un Input 'Code, client, produit, adresse, livreur, preparateur, date...' pour les 3 roles (page.tsx:929)
- Aucun selecteur d'action par ligne: le web a un Select 'Action' (gerantActionOptions) sur chaque ligne du tableau pour changer le statut sans ouvrir le detail; ici le changement de statut n'existe QUE dans order_detail_screen
- Pas de bouton 'Annuler la commande' sur la ligne (web: icone Ban par ligne quand statut != LIVRE/RETOUR/ANNULEE); l'annulation n'existe que dans le detail
- Pas de bouton 'Reinitialiser' global des filtres (uniquement suppression Chip par Chip)
- Pas de colonnes Type / Sous-type / Produit detaille (marque + badge couleur + xN par article) comme le tableau web; la tuile n'affiche aucun article
- Pas de pagination ni chargement paresseux: toute la liste est chargee d'un coup
- ordersFilterProvider est global et partage avec /depot et /tournee, jamais reinitialise a l'entree/sortie d'ecran: un statut choisi dans Tournee reste applique en arrivant sur Commandes
- EditOrderDialog reconstruit des CartLine avec un ReferenceOption factice (id:0, typeId:0, brandName:'', stockActuel: 1<<30) a partir des items existants: le stock reel n'est pas verifie pour les lignes deja presentes et la marque/le type ne s'affichent pas
- Aucune verification de role dans l'ecran: n'importe quel utilisateur authentifie qui atteint /orders voit la vue gerant

#### `smartcross/lib/features/orders/order_create_screen.dart`

- **Route** : /orders/new
- **Role** : Gerant (formulaire complet) et Preparateur (mode 'Nouvelle recuperation' force: zone=RECUPERATION, prix masques, pas d'assignation) — detection via authProvider.user.role

**Implemente** (12)

- Titre dynamique 'Nouvelle commande' / 'Nouvelle recuperation' selon le role, bouton fermer
- Bloc articles: bouton 'Ajouter un article' -> AddOrderLineDialog, liste des lignes (marque + reference + couleur, 'q x prix = sous-total' ou 'Quantite : n' si preparateur), suppression d'une ligne
- SegmentedButton 'A livrer' / 'Recuperation sur place' (desactive pour le preparateur)
- Date et heure de livraison via showDatePicker + showTimePicker (mention 'Vide = maintenant.'), rechargement de la disponibilite livreur apres changement de creneau (availableStaff('LIVREUR', dateCommande:))
- Dropdowns Preparateur et Livreur cote a cote (masques pour le preparateur), remplis par availableStaff, valeur nulle = 'Assigner plus tard'
- Si livraison: Dropdown zone (zones actives depuis deliveryZonesProvider) + champ Adresse + Dropdown Paiement (Paiement avant / a la livraison)
- Champs Nom client (requis) et Telephone (validator regex ^\+261\d{9}$) via Form/GlobalKey<FormState>
- Note pour le preparateur (multiline) et, si gerant + livraison, Note pour le livreur
- Recapitulatif 'Frais de livraison' + 'Total estime' (calcul client via DeliveryZoneCatalog.fraisFor), masque pour le preparateur
- Bouton 'Creer la commande' avec spinner, erreurs API en encart errorContainer; apres creation: assignPreparateur puis assignLivreur si choisis (echec non bloquant, SnackBar), puis context.go('/orders/:id')
- Selection automatique de la premiere zone active des que deliveryZonesProvider repond (postFrameCallback)
- AddOrderLineDialog (exporte, reutilise par EditOrderDialog): 3 dropdowns Categorie / Sous-type (filtre par categorie) / Marque, champ de recherche avec debounce 350 ms sur catalogRepository.autocomplete, liste de resultats (marque + reference, type + prix, apercu des 4 premieres couleurs), selection d'une reference + 'Changer', RadioListTile par couleur avec stock affiche et desactive si stockActuel==0, compteur de quantite +/- (min 1), layout compact < 420 px

**Manques constates** (5)

- Impossible de modifier la quantite d'une ligne deja ajoutee au panier (il faut la supprimer et la re-ajouter)
- Le dropdown Livreur n'affiche pas l'indicateur de conflit: availableStaff est bien appele avec dateCommande mais le champ 'available' n'est jamais rendu ('(occupe)' n'existe que dans assign_staff_dialog)
- Aucune sauvegarde de brouillon ni protection contre la perte de saisie si on quitte l'ecran
- Pas d'historique/autocompletion des clients deja saisis
- Le total affiche reste une estimation client (assume: le serveur recalcule), aucune verification apres creation

#### `smartcross/lib/features/orders/order_detail_screen.dart`

- **Route** : /orders/:id (int.parse du path param)
- **Role** : Concu pour le Gerant (_nextActions est explicitement le miroir de page.tsx::nextAction pour isGerant) — aucun test de role dans le code

**Implemente** (12)

- Chargement via orderDetailProvider(id) (autoDispose.family, se rafraichit sur realtimeTickProvider); LoadingState / ErrorState avec retry / corps
- Action AppBar 'Modifier la commande' si statut NOUVELLE ou EN_PREPARATION -> EditOrderDialog puis invalidation du provider
- Carte d'informations: Client, Telephone cliquable (url_launcher tel:), Zone (label long), Adresse, 'Commande creee le' (createdAt), 'Livraison prevue le' (dateCommande), Paiement (masque si recuperation), Preparateur, Livreur, Note preparateur, Note livreur
- Carte Articles: reference — couleur, 'q x prix unitaire' et sous-total quand les prix sont exposes, sinon 'Quantite : n'
- Carte financiere: Frais de livraison et Total a payer (le total est masque quand modePaiement == AVANT)
- Actions de workflow contextuelles (_nextActions): NOUVELLE -> 'Assigner un preparateur' (dialog d'affectation) + 'Commencer la preparation'; EN_PREPARATION -> 'Commande prete' (avec photo); PRETE -> 'Recuperee par le client' si RECUPERATION, sinon 'Assigner un livreur' + 'Recuperer / En livraison'; EN_LIVRAISON -> 'Livre' + 'Retour' (bouton rouge); aucun bouton sur LIVRE/RETOUR/ANNULEE
- Chemin 'assign': showAssignStaffDialog (choix de la personne + date/heure manuelle) puis changeStatus avec preparateurId/livreurId/assignedAt
- Chemin direct: showOrderConfirmDialog (resume + note optionnelle, photo proposee uniquement pour la cible PRETE) puis changeStatus(note, photoPath)
- Bouton 'Annuler la commande' (rouge) tant que le statut n'est pas LIVRE/RETOUR/ANNULEE, avec confirmation qui previent de la restitution de stock si EN_PREPARATION/PRETE/EN_LIVRAISON -> ordersProvider.cancel
- Carte 'Chronologie' (_OrderTimelineCard): Commande creee le, Livraison prevue le, Preparation commencee le, Prete le, En livraison depuis le, Livree le, Retour le — uniquement les jalons atteints
- 'Historique detaille': une ListTile par entree de statusHistory (ancien -> nouveau, auteur, horodatage, note) avec miniature Image.network de la photo, ouvrable via launchUrl
- Etat _changing qui desactive tous les boutons pendant l'appel, erreurs en SnackBar

**Manques constates** (5)

- Cet ecran n'est atteignable que depuis /orders (gerant): ni depot_screen ni tournee_screen ne poussent vers /orders/:id, donc preparateur et livreur n'ont aucune vue detail
- Aucun conditionnement par role: les actions gerant (assignation, annulation) seraient affichees a un preparateur/livreur qui atteindrait l'URL
- Pas d'action 'Supprimer' depuis le detail (elle n'existe que dans la liste)
- Les timestamps de l'Historique detaille sont formates avec h.timestamp brut (sans appLocal) alors que la Chronologie applique appLocal — decalage de 3 h entre les deux blocs de la meme page
- La photo est chargee via Image.network(h.photo) sans prefixage par ApiClient.baseUrl: depend d'une URL absolue renvoyee par l'API

#### `smartcross/lib/features/depot/depot_screen.dart`

- **Route** : /depot (home du role preparateur, _homeFor)
- **Role** : Preparateur (nav item roles:{preparateur})

**Implemente** (8)

- 3 ChoiceChip de vue: 'A preparer', 'Recuperations', 'Historique'
- Filtre date unique (OutlinedButton + showDatePicker, libelle dd/MM/yyyy) avec bouton clear, applique sur ordersFilterProvider (dateDebut=dateFin); masque en vue Historique
- Vues 'A preparer' / 'Recuperations': meme liste ordersProvider partitionnee client-side sur livraisonZone == RECUPERATION, RefreshIndicator, EmptyState specifique ('Aucune recuperation.' / 'Aucune commande a preparer.'), ErrorState avec retry
- _DepotCard: numero + OrderStatusBadge, nom client, telephone cliquable (tel:), liste des articles '• reference — couleur (xN)', zone courte, 'Livreur : X', 'Livraison prevue le dd/MM/yyyy HH:mm' (appLocal)
- Bouton pleine largeur qui avance le statut: NOUVELLE -> EN_PREPARATION ('Commencer la preparation'), sinon -> PRETE ('Commande prete'); passe par showOrderConfirmDialog (note + photo proposee seulement pour PRETE) puis changeStatus(note, photoPath); spinner pendant l'appel, erreur en SnackBar
- Regle jour J: bouton desactive et libelle 'Disponible le JJ/MM/AAAA' quand dateCommande est dans le futur (isJourJ base sur le fuseau Antananarivo)
- Vue Historique deleguee a OrderHistoriqueView avec _DepotHistoriqueCard (numero, badge, client, articles, zone, livreur, 'Livree le' / 'Livraison prevue le')
- FloatingActionButton.extended 'Nouvelle recuperation' -> /orders/new (qui bascule en mode preparateur)

**Manques constates** (7)

- Aucun champ de recherche libre (le web offre 'Code, client, produit, adresse, date...' au preparateur)
- La carte n'affiche PAS note_preparateur alors que OrderPreparateurSerializer l'expose — la note qui lui est destinee est invisible (ni sur la carte, ni dans le dialog de confirmation)
- Tap sur une carte inerte: pas de navigation vers un detail de commande
- _clearDate() appelle set(const OrdersFilter()) et efface donc tous les filtres partages, pas seulement la date
- Le partitionnement 'A preparer' / 'Recuperations' est client-side sur la meme requete; aucun filtre serveur livraison_zone
- Pas de filtre de statut (NOUVELLE vs EN_PREPARATION) dans la vue active
- _DepotHistoriqueCard affiche 'Livree le <dateCommande>' quand le statut est LIVRE, alors qu'il s'agit de la date de livraison prevue (le serializer preparateur n'expose pas status_history, donc l'heure reelle n'est pas disponible)

#### `smartcross/lib/features/tournee/tournee_screen.dart`

- **Route** : /tournee (home du role livreur)
- **Role** : Livreur (nav item roles:{livreur})

**Implemente** (9)

- Bascule 'Ma tournee' <-> 'Tournee — Historique' via une IconButton dans l'AppBar
- Filtre date unique (showDatePicker, bornes appNow +/- 365 j) + bouton clear qui reinitialise tous les filtres
- Rangee horizontale de ChoiceChip de statut: Tous / En preparation / 'A recuperer' (PRETE) / En livraison, appliquee sur ordersFilterProvider.statut (filtrage serveur)
- Liste ordersProvider avec RefreshIndicator, EmptyState 'Aucune commande en tournee.', ErrorState avec retry
- _TourneeCard: numero + OrderStatusBadge, client, telephone cliquable (tel:), articles '• reference — couleur (xN)', zone courte, adresse de livraison, mention verte 'Deja paye — rien a encaisser' si modePaiement==AVANT sinon 'Total a encaisser : n Ar'
- Actions selon le statut: EN_PREPARATION -> mention grise 'En cours de preparation' (non actionnable); PRETE -> bouton 'Recuperer le colis' (-> EN_LIVRAISON); EN_LIVRAISON -> boutons 'Livre' et 'Retour' (rouge)
- Toutes les actions passent par showOrderConfirmDialog avec hideAmounts=true quand la commande est deja payee d'avance
- Regle jour J: boutons desactives et libelle/mention 'Disponible le JJ/MM/AAAA' pour les commandes futures
- Vue Historique deleguee a OrderHistoriqueView avec _TourneeHistoriqueCard (numero, badge, client, telephone, articles, zone, 'Deja paye' ou 'Total : n Ar')

**Manques constates** (8)

- Aucun champ de recherche libre (present cote web pour le livreur)
- note_livreur n'est jamais affiche alors que OrderLivreurSerializer l'expose — la consigne destinee au livreur est invisible sur la carte comme dans le dialog de confirmation
- status_history est expose au livreur (explicitement pour lui montrer la photo de preparation) mais l'ecran ne l'exploite pas: aucune photo ni chronologie visible pour le livreur
- Pas de navigation vers un detail de commande (cartes non cliquables)
- Pas de lien direct vers /bilan depuis la tournee (uniquement via le menu lateral)
- Aucune action de navigation/carte (ex: ouvrir l'adresse dans une app de cartes) — seul le telephone est actionnable
- showOrderConfirmDialog est appele sans showPhoto pour 'Livre': pas de preuve de livraison photo cote livreur
- Le passage PRETE -> EN_LIVRAISON n'envoie pas de livreurId: repose entierement sur l'auto-affectation serveur

#### `smartcross/lib/features/tournee/bilan_screen.dart`

- **Route** : /bilan
- **Role** : Livreur (nav item roles:{livreur}); l'historique renvoye par le serveur est deja limite au livreur connecte

**Implemente** (8)

- bilanDuJourProvider (FutureProvider.autoDispose) qui appelle orders.list(historique:true, dateFrom/dateTo = bornes du jour a Antananarivo via appDayBounds())
- AppBar 'Bilan du jour' + bouton Rafraichir (ref.invalidate)
- _TicketCard: en-tete 'BILAN DU JOUR' + date du jour, bloc LIVRAISONS EFFECTUEES (Nombre, Total produits, Total frais livraison, TOTAL ARGENT en gras) et bloc RETOURS hors total (Nombre, Total produits, Total frais, TOTAL NON ENCAISSE en rouge)
- Separation stricte livrees (LIVRE) / retours (RETOUR), les retours ne sont jamais additionnes
- Sections listees 'Livraisons effectuees (n)' et 'Retours (n)' avec message vide dedie
- _BilanOrderCard: numero + total, ligne 'categorie • sous-type' du premier article, liste des articles, 'client · adresse ou zone', heure (appLocal), pied de carte 'Prix' / 'Frais'
- Prix produit derive (totalAPayer - fraisLivraison) puisque le prix unitaire n'est jamais expose au livreur
- LoadingState / ErrorState avec retry

**Manques constates** (4)

- Pas de rafraichissement temps reel: bilanDuJourProvider ne watch pas realtimeTickProvider (le web utilise useRealtimeRefresh sur order/order_status_history) — seul le bouton Rafraichir met a jour
- Aucun selecteur de date/periode: le bilan est fige sur la journee courante
- Aucune impression ni partage du ticket alors que printing/pdf/share_plus sont deja dans pubspec.yaml (utilises seulement par catalog/stock)
- Pas de detail par mode de paiement (ce qui a ete encaisse en especes vs deja paye d'avance)

#### `smartcross/lib/widgets/order_confirm_dialog.dart`

- **Route** : aucune (widget partage)
- **Role** : Utilise par depot_screen, tournee_screen et order_detail_screen

**Implemente** (6)

- showOrderConfirmDialog(context, title, order, showPhoto, hideAmounts) -> OrderConfirmResult(note, photoPath) ou null si annule
- Resume: 'Commande N — verifiez le resume', Client, Telephone, Zone (shortLabel), Adresse, Paiement (masque si recuperation), une ligne par article 'reference (couleur) xN'
- Bloc montants: si hideAmounts -> 'A encaisser : Rien — deja paye'; sinon Prix de vente + Frais de livraison + Total en gras
- Champ Note (optionnel, 2 lignes, hint 'ex : client absent')
- Si showPhoto: bouton 'Photo de la preparation (optionnel)' via ImagePicker(source: camera, imageQuality: 85) + miniature Image.file et libelle 'Reprendre la photo'
- Helpers exportes reutilisables: isJourJ(dateCommande) (comparaison au jour calendaire Antananarivo), dueDateLabel(date), arFmt(montant)

**Manques constates** (3)

- Source photo limitee a la camera: pas de choix depuis la galerie
- N'affiche ni note_preparateur ni note_livreur alors que ces champs sont dans le modele Order
- Pas d'apercu plein ecran ni de suppression de la photo prise

#### `smartcross/lib/widgets/order_historique_view.dart`

- **Route** : aucune (widget partage)
- **Role** : Vue Historique du preparateur (depot) et du livreur (tournee), via cardBuilder

**Implemente** (6)

- Filtres 'Du…' / 'Au…' en date ET heure (showDatePicker puis showTimePicker; annuler l'heure garde 00:00 / 23:59:59), converties en UTC via appWallClockToUtc
- Bouton clear qui remet from/to/statut a null
- Rangee horizontale de ChoiceChip de statut: Tous, Livrees, Retours, Annulees, En livraison, 'A recuperer' (PRETE), En preparation
- Chargement direct via OrdersRepository().list(historique:true, dateFrom, dateTo, statut) dans un FutureBuilder
- LoadingState, ErrorState('Erreur de chargement.' + retry), EmptyState('Aucune commande dans l'historique.'), RefreshIndicator
- Rendu de chaque commande delegue au cardBuilder fourni par l'ecran appelant

**Manques constates** (4)

- Instancie son propre OrdersRepository() au lieu de passer par ordersRepositoryProvider (hors Riverpod, non invalide au changement de compte par _invalidateDataProviders)
- Pas de rafraichissement temps reel (FutureBuilder isole de realtimeTickProvider)
- Pas de recherche texte, pas de pagination
- Le message d'erreur est generique et n'utilise pas ApiClient.messageFromError

#### `smartcross/lib/widgets/assign_staff_dialog.dart`

- **Route** : aucune (widget partage)
- **Role** : Gerant, depuis order_detail_screen (transitions NOUVELLE->EN_PREPARATION et PRETE->EN_LIVRAISON)

**Implemente** (5)

- showAssignStaffDialog(context, role, orderNumero, loadStaff) -> AssignResult(staffId, assignedAt) ou null
- Chargement asynchrone du staff avec spinner, message d'erreur, et cas 'Aucun preparateur/livreur enregistre pour ce magasin.'
- DropdownButtonFormField 'Choisir un preparateur/livreur' avec suffixe ' (occupe)' quand available == false (indicatif, ne bloque pas)
- Selecteur 'Date et heure' (showDatePicker +/- 60 j puis showTimePicker), valeur par defaut = maintenant
- Bouton 'Assigner' desactive tant qu'aucune personne n'est selectionnee

**Manques constates** (3)

- assignedAt est initialise a DateTime.now() (heure de l'appareil) et transmis tel quel sans passer par appWallClockToUtc — incoherent avec le reste de l'app qui raisonne en heure mur d'Antananarivo
- Pas de champ note (conforme au web, signale comme choix delibere dans le code)
- Pas de recherche/filtre quand la liste de staff est longue

#### `smartcross/lib/widgets/status_badge.dart`

- **Route** : aucune (widget partage)
- **Role** : Tous les ecrans commandes/depot/tournee/bilan

**Implemente** (3)

- StatusChip(label, color): pastille arrondie avec fond color.withValues(alpha:0.14)
- OrderStatusBadge(status): libelle OrderStatus.label + couleur via statusColor(context, apiValue) de core/theme.dart
- StockLevelBadge(isRupture, isStockBas): 'Rupture' rouge / 'Stock bas' orange / 'OK' vert

**Manques constates** (1)

- Aucune variante taille/densite; pas d'icone par statut

**Infrastructure reutilisable** (16)

- ROUTER — /home/garrix/Dev/Smartphone/smartcross/lib/core/router.dart: go_router 17, routerProvider (Riverpod Provider<GoRouter>), initialLocation '/splash', refreshListenable = _RouterRefresh qui ecoute authProvider et notifie sur changement de AuthStatus. Redirect global: loading -> /splash; unauthenticated -> /login sauf prefixes publics ['/login','/server-setup','/splash']; authenticated sur une route publique -> _homeFor(role) = gerant:/dashboard, preparateur:/depot, livreur:/tournee, sinon /login.
- ROUTER — routes existantes: /splash, /server-setup, /login, puis une ShellRoute (NavigationShell) contenant /dashboard, /caisse, /orders (+ 'new', ':id'), /depot, /tournee, /bilan, /catalog, /suppliers (+ 'new', ':id'), /users, /stores, /transfers, /chats (+ 'room/:room', 'dm/:id'), /notifications, /settings. AUCUN garde de role par route: la restriction par role est uniquement declarative dans kPrimaryNavItems (core/nav_items.dart, champ roles + visibleFor) et filtre le menu, pas l'acces direct a l'URL.
- THEME — lib/core/theme.dart: Material 3, seed kSeedColor #2563EB, buildLightTheme()/buildDarkTheme() (AppBar plat sans surfaceTint, CardThemeData elevation 0 + bordure outlineVariant + rayon 14, InputDecorationTheme rempli + rayon 10). main.dart applique theme/darkTheme avec ThemeMode.system. kChartPalette (8 couleurs) pour fl_chart. statusColor(context, apiStatus) mappe les 7 statuts commande sur des couleurs fixes, reutilise par OrderStatusBadge.
- AUTH — lib/state/auth_provider.dart: AuthNotifier (Notifier<AuthState{status, user}>) avec AuthStatus.loading/unauthenticated/authenticated; _bootstrap() attend ApiClient.ensureInitialized(), lit le token puis GET users/me/; login(email,password), logout(), refreshUser(). _invalidateDataProviders(ref) invalide 19 providers metier (dont ordersProvider et orderDetailProvider) a chaque login/logout. authEventProvider (StreamProvider) relaie l'evenement sessionExpired emis par ApiClient sur 401 non rafraichissable et force l'etat unauthenticated.
- AUTH/REPO — lib/data/repositories/auth_repository.dart: POST users/login/ (stocke access+refresh), GET users/me/, PATCH users/me/ (profil + upload photo multipart), POST users/change-password/, logout = purge locale du token.
- STOCKAGE — lib/core/secure_storage.dart: TokenStorage (singleton, FlutterSecureStorage, cles 'access_token'/'refresh_token', save/saveAccess/clear) et AppPrefs (SharedPreferences, cle 'server_base_url' pour l'URL serveur configurable via /server-setup).
- CLIENT HTTP — lib/core/api_client.dart: singleton ApiClient avec Dio (timeouts 20s/30s), baseUrl = <serveur>/api/, interceptor qui injecte 'Authorization: Bearer <access>', refresh transparent sur 401 (POST users/refresh/) avec rejeu de la requete marquee 'retried', emission AuthEvents.sessionExpired si le refresh echoue. Helpers statiques reutilisables: isConnectivityError(error) et messageFromError(error) (extrait error/detail/message, aplatit les erreurs de validation DRF {champ:[msg]}, message reseau dedie). kDefaultServerUrl adapte a la plateforme (10.0.2.2 sur Android). wsBaseUrl derive ws/wss depuis la base HTTP.
- TEMPS — lib/core/app_time.dart: fuseau metier fige Indian/Antananarivo (UTC+3, kAppUtcOffset). appNow(), appLocal(instant), appDay(), appToday(), appWallClockToUtc(saisie utilisateur -> UTC), appDayBounds() (bornes date_from/date_to d'une journee). Utilise par la creation/edition de commande, le filtre historique, isJourJ et le bilan.
- PROVIDERS RIVERPOD (commandes) — lib/state/orders_provider.dart: ordersRepositoryProvider; deliveryZonesProvider (FutureProvider qui remplit aussi le cache statique DeliveryZoneCatalog); OrdersFilter (statut, dateDebut, dateFin, preparateurId, historique, dateFrom, dateTo, nonLivree) + copyWith avec clearStatut/clearPreparateurId; ordersFilterProvider (NotifierProvider, GLOBAL et partage entre /orders, /depot, /tournee); ordersProvider (AsyncNotifier<List<Order>> qui watch realtimeTickProvider + ordersFilterProvider et expose refresh/create/changeStatus/cancel/updateOrder/delete/availableStaff/assignLivreur/assignPreparateur, chaque mutation appelant refresh()); orderDetailProvider (FutureProvider.autoDispose.family<Order,int> qui watch realtimeTickProvider). bilanDuJourProvider est declare dans bilan_screen.dart.
- AUTRES PROVIDERS reutilisables — lib/state/: auth_provider, realtime_provider, notifications_provider (notificationsProvider + unreadNotificationsCountProvider + markRead optimiste), catalog_provider (categories/types/brands/colors/references/autocomplete), dashboard_provider, stock_provider (ruptures, mouvements), suppliers_provider, users_provider (comptes, comptes en attente), stores_provider, caisse_provider, company_provider.
- REPOSITORIES — lib/data/repositories/: orders_repository.dart (list avec statut/date_debut/date_fin/preparateur_id/historique/date_from/date_to, detail, create, changeStatus avec variante FormData quand une photo est jointe, cancel, update PATCH, delete, availableStaff(role, dateCommande) -> StaffOption{id, fullName, available}, assignLivreur, assignPreparateur, deliveryZones), plus auth, catalog, stock, dashboard, suppliers, users, stores, caisse, chat, notifications, company.
- MODELES — lib/models/order.dart (Order, OrderItem avec brand/type/category names et prixUnitaire nullable selon le role, OrderStatusHistoryEntry avec photo, OrderItemDraft), delivery_zone.dart (DeliveryZoneOption + cache statique DeliveryZoneCatalog: labelFor/shortLabelFor/fraisFor et constante kRecuperationCode), constants.dart (enums UserRole, OrderStatus (7 valeurs), PaymentMode, StockMovementType, SupplierOrderStatus avec fromApi/apiValue/label, kDesktopBreakpoint=900, helper dialogWidth), json_utils.dart (asInt/asString/asDouble/asDate tolerants).
- WIDGETS PARTAGES — lib/widgets/: async_state_widgets.dart (LoadingState, ErrorState(message,onRetry), EmptyState(message,icon)) utilises partout; status_badge.dart (StatusChip, OrderStatusBadge, StockLevelBadge); kpi_card.dart (label/valeur/icone/accent/sous-titre); navigation_shell.dart (sidebar permanente 240 px au-dessus de 900 px, Drawer en dessous, items filtres par role, ListTile selectionnee sur startsWith du path); topbar.dart (logo, pastille verte/orange d'etat temps reel, icone Notifications avec Badge du compteur non lus, menu compte avec nom/email/role et Deconnexion); order_confirm_dialog.dart, assign_staff_dialog.dart, order_historique_view.dart. Reutilisables aussi: AddOrderLineDialog + CartLine (exportes par order_create_screen.dart) et EditOrderDialog (exporte par orders_list_screen.dart).
- TEMPS REEL — lib/core/ws_manager.dart: classe abstraite WsManager (connexion via buildUri rappele a chaque tentative pour un token frais, reconnexion automatique apres 3 s, decodage JSON, callbacks onMessage/onStatusChange, send/disconnect). NotificationsSocketService (singleton, /ws/notifications/?token=) expose incoming + connectionStatus. lib/state/realtime_provider.dart: realtimeTickProvider (compteur incremente a chaque message), RealtimeBootstrap instancie une fois dans main.dart (connexion/deconnexion pilotee par authProvider), wsConnectionStatusProvider consomme par la TopBar. Tout provider qui fait ref.watch(realtimeTickProvider) se rafraichit automatiquement (ordersProvider, orderDetailProvider, notificationsProvider le font; bilanDuJourProvider et OrderHistoriqueView ne le font PAS). ChatSocketService (instance par conversation, /ws/chat/ avec recipient_id optionnel, ping de presence toutes les 20 s, actions send/edit/delete).
- DEPENDANCES pubspec.yaml deja disponibles: flutter_riverpod 3.4, go_router 17.3, dio 5.11, web_socket_channel, flutter_secure_storage, shared_preferences, fl_chart, intl, collection, url_launcher, image_picker, file_picker, printing + pdf + share_plus (utilises seulement par catalog_screen/stock_repository), flutter_local_notifications et connectivity_plus DECLARES MAIS JAMAIS IMPORTES dans lib/.
- ECRANS HORS PERIMETRE deja portes et reutilisables comme modeles: dashboard, caisse, catalog (avec import/export CSV et PDF de reapprovisionnement), suppliers (+ create/detail), stores, transfers, users, chats (liste + conversation temps reel), notifications, settings (profil, mot de passe, CRUD marques/categories/sous-types/couleurs), auth (splash, login, server-setup).

**Notes**

Comparaison factuelle avec le frontend Next.js (/home/garrix/Dev/Smartphone/frontend). (1) Le web regroupe les 3 roles dans UNE page app/(app)/orders/page.tsx (3003 lignes) qui bascule sur isGerant/isPreparateur/isLivreur; le portage Flutter a eclate cela en 3 ecrans (orders_list_screen, depot_screen, tournee_screen) — la couverture fonctionnelle est bonne mais 3 elements web manquent partout: la recherche texte libre, le selecteur d'action par ligne du gerant, et l'ouverture du detail (dialog web) pour le preparateur/livreur. (2) app/(app)/bilan/page.tsx est fidelement porte par bilan_screen.dart (memes totaux, meme separation retours), au rafraichissement temps reel pres. (3) app/(app)/pickup/page.tsx (page gerant listant statut=PRETE + livraison_zone=RECUPERATION avec confirmation de retrait -> LIVRE) n'a AUCUN equivalent Flutter: pas de route /pickup; le gerant doit passer par le detail d'une commande ('Recuperee par le client'). (4) Le CRUD des zones de livraison (Parametres web) n'existe pas dans lib/features/settings/settings_screen.dart: les zones ne sont que lues via orders/delivery-zones/. (5) Pages web sans equivalent Flutter (hors perimetre de cet audit mais a planifier): alerts, movements, reports, sales, superadmin. (6) Le backend expose deliberement note_preparateur au preparateur et note_livreur + status_history (avec photo de preparation) au livreur (orders/serializers.py:99-140); ni depot_screen ni tournee_screen n'exploitent ces champs — c'est le manque fonctionnel le plus net du perimetre. (7) Point de coherence a surveiller: ordersFilterProvider est un etat global partage par les trois ecrans et n'est jamais reinitialise a la navigation. (8) Deux incoherences de fuseau reperees dans le code lu: assign_staff_dialog initialise assignedAt avec DateTime.now() sans appWallClockToUtc, et l'Historique detaille de order_detail_screen formate h.timestamp sans appLocal alors que la Chronologie juste au-dessus l'applique.

### Groupe `catalog-stock`

#### `smartcross/lib/features/catalog/catalog_screen.dart`

- **Route** : /catalog (GoRoute dans le ShellRoute, router.dart:99)
- **Role** : Gerant (NavItem '/catalog' roles:{gerant} dans core/nav_items.dart) — mais AUCUNE garde de role dans le routeur : seul le menu d'actions des cartes est conditionne par isGerant (catalog_screen.dart:222)

**Implemente** (21)

- Ecran a 3 onglets (DefaultTabController + TabBar isScrollable) : References / Ruptures / Mouvements, AppBar 'Produits'
- REFERENCES — TextField de recherche multi-mots : chaque token doit apparaitre dans reference_name + brand_name + couleurs des variantes (filtrage 100% client)
- REFERENCES — 3 filtres en PopupMenuButton icone (Categorie, Sous-type dependant de la categorie selectionnee, Marque), icone coloree en primary si actif
- REFERENCES — Chips actives supprimables sous la barre de recherche pour chaque filtre pose (retirer la categorie remet aussi le sous-type a null)
- REFERENCES — ListView de cartes _ReferenceCard + RefreshIndicator (pull-to-refresh -> referencesProvider.refresh()), EmptyState/ErrorState(avec Reessayer)/LoadingState
- REFERENCES — Carte : category_name, 'marque + reference', StockLevelBadge agrege (Rupture/Stock bas/OK), Prix de vente, Marge unitaire (vert si >=0 sinon rouge), une StatusChip par variante 'couleur · stock' coloree par seuils (<=0 rouge, <=2 bleu, >2 vert), 'Aucune variante' sinon
- REFERENCES — Menu '⋮' par carte (gerant seulement) : Gerer les couleurs / Modifier / Supprimer (avec dialog de confirmation _confirm)
- REFERENCES — FAB 'Nouvelle reference' + FAB '⋮' ouvrant un bottom sheet : Exporter Excel, Importer Excel, Modifier prix par sous-type, Parametres
- Export Excel : GET catalog/references/export-excel/ en bytes puis partage via SharePlus (XFile.fromData, mimetype xlsx)
- Import Excel : FilePicker.pickFile(xlsx/xls) -> readAsBytes -> POST multipart import-excel/ ; snackbar de resume chiffre lu dans les en-tetes X-Import-* (references creees/maj, couleurs creees/maj, sautees, erreurs, 6s) ; invalidation de referencesProvider + categoriesProvider + typesProvider + brandsProvider ; repartage du fichier .xlsx annote renvoye par le serveur
- Dialog 'Nouvelle reference produit' : cascade Categorie -> Sous-type -> Marque ; creation inline d'un sous-type (champ + bouton Creer, auto-selection) ; creation inline d'une marque ; champ Reference (modele) ; Prix d'achat + Prix de vente avec marge estimee recalculee en direct ; photo optionnelle (image_picker galerie, qualite 85, apercu Image.file) ; section Variantes : dropdown Couleur + Nombre + Seuil d'alerte, creation inline d'une couleur, bouton Ajouter -> liste de brouillons en Chips supprimables avec compteur 'n couleur(s) · n unite(s)', refus des doublons de couleur ; a la validation : POST reference puis POST de chaque variante puis upload photo
- Dialog 'Modifier la reference' : nom, prix d'achat, prix de vente, marge estimee en direct, photo (apercu Image.file ou Image.network + bouton Changer la photo), SwitchListTile 'Active / Visible dans la recherche de commande', PATCH puis upload photo si changee
- Dialog 'Gerer les couleurs' (relit la reference depuis referencesProvider pour rester a jour) : liste des variantes avec Stock/Seuil + StockLevelBadge, bouton 'Ajuster le stock' (icone tune), bouton supprimer la variante avec confirmation, bouton 'Ajouter une couleur' -> _AddVariantDialog (dropdown couleur + creation inline + Nombre + Seuil)
- Dialog d'ajustement de stock _QuickAdjustDialog : bandeau couleur/stock/seuil, SegmentedButton Entree/Sortie, Quantite, Note optionnelle ; POST catalog/variants/{id}/adjust/ ; invalide referencesProvider, rupturesProvider et movementsProvider(null)
- Dialog 'Modifier le prix par sous-type' (_BulkPriceDialog) : dropdown sous-type, nouveau prix d'achat et/ou de vente (vide = inchange), validation 'au moins un prix', POST bulk-update-price/, snackbar 'N reference(s) mise(s) a jour'
- Bottom sheet 'Parametres du catalogue' (DraggableScrollableSheet 0.85, 3 onglets Marques / Categories+Sous-types / Couleurs) : CRUD complet creation (prompt texte), renommage (prompt pre-rempli) et suppression avec confirmation, pour categories, sous-types (dialog dedie avec dropdown categorie), marques et couleurs
- RUPTURES — Liste derivee cote client (StockRepository.ruptures() refait un GET catalog/references/ et retient les variantes is_rupture/is_stock_bas, tri ruptures d'abord puis alphabetique marque/reference)
- RUPTURES — Tuile : 'marque reference — couleur', 'categorie / sous-type · Stock : n · Seuil : n', StockLevelBadge, bouton d'ajustement rapide (_QuickAdjustDialog)
- RUPTURES — FAB 'Exporter PDF' : PDF genere LOCALEMENT avec le package pdf (colonnes Statut/Marque/Reference/Couleur/Sous-type/Stock/Seuil/A commander, quantite a commander = seuil - stock clampe a >=1) puis partage SharePlus
- MOUVEMENTS — Liste GET catalog/movements/ : avatar entree (vert, fleche bas) / sortie (rouge, fleche haut), libelle variante, 'type de quantite · origine · note' + date formatee dd/MM/yyyy HH:mm + utilisateur, RefreshIndicator
- MOUVEMENTS — FAB 'Ajustement' : dialog de choix du produit avec champ de recherche local sur toutes les variantes (label 'marque reference — couleur' + stock actuel) puis bascule sur _QuickAdjustDialog

**Manques constates** (14)

- Aucune garde de role sur la route /catalog : le routeur ne verifie que le statut d'authentification (router.dart redirect) ; un preparateur/livreur qui atteint l'URL voit les FAB Nouvelle reference, Import/Export Excel, prix en masse et Parametres (seul le menu ⋮ des cartes est masque)
- Le dialog Modifier ne permet PAS de changer la categorie / le sous-type / la marque d'une reference — CatalogRepository.updateReference n'envoie que reference_name, prix_achat, prix_vente, actif (le ProductDetailDialog du web permet de changer type et brand)
- La photo produit n'est jamais affichee dans la liste (uniquement en vignette 56x56 dans le dialog de modification) ; pas de galerie d'images (equivalent de components/product-image-gallery.tsx cote web)
- Recherche : le haystack n'inclut ni category_name ni type_name (le web les inclut) et il n'y a pas de debounce (setState a chaque frappe sur ~360 references)
- Import Excel : pas d'ecran de revue post-import (le web affiche un dialog 'Resume de l'import' avec les noms crees/mis a jour), pas d'annulation d'import (batchId / handleCancelImport), pas de verification IA des quasi-doublons
- Pas de creation de commande client depuis l'ecran Produits (le web a ProductCreateOrderDialog + ProductOrderItemsEditor)
- Pas de 'Stock total' par reference (colonne presente dans le tableau web) ni de tri de colonnes ni de pagination
- Onglet Mouvements tres pauvre par rapport a app/(app)/movements/page.tsx : pas de recherche, pas de filtres de dates, pas de KPI (total entrees / total sorties / nombre de mouvements), pas de regroupement par jour, pas d'export XLSX, pas de statistiques rotation rapide/lente
- Onglet Ruptures : pas de cartes KPI ni de sections separees Rupture / Stock bas / Sous seuil comme app/(app)/alerts/page.tsx ; la liste est recalculee en refaisant un GET complet du catalogue (pas d'endpoint dedie, pas de pagination)
- Les CRUD Categories/Sous-types/Marques/Couleurs sont dupliques : ici (_ConfigSection/_CategoryList/_TypeList/_BrandList/_ColorList) ET dans settings_screen.dart (_CatalogueBrandsCard/_CatalogueTypesCard/_CatalogueColorsCard)
- Le helper _confirm() a un bouton de validation toujours libelle 'Supprimer', il est reutilise pour toutes les confirmations du fichier
- Largeurs de dialogs codees en dur (SizedBox width 380/420) au lieu du helper dialogWidth() de core/constants.dart
- createVariant envoie stock_actuel alors que le backend l'ignore (commentaire explicite dans catalog_repository.dart:187) : le stock saisi a la creation d'une variante n'est donc pas applique
- Pas de gestion du seuil d'alerte apres creation (aucun dialog ne permet de modifier seuil_alerte d'une variante existante)

#### `smartcross/lib/features/stores/stores_screen.dart`

- **Route** : /stores (ShellRoute, router.dart:112)
- **Role** : Gerant (NavItem roles:{gerant}) — pense pour l'admin proprietaire multi-magasins, aucune verification isCompanyOwner/rawRole dans le code

**Implemente** (9)

- AppBar 'Magasins', ListView de cartes + RefreshIndicator, EmptyState/ErrorState(Reessayer)/LoadingState
- Donnees fusionnees par StoresRepository.list() : GET users/magasins/users/ puis GET users/magasins/stats/ (try/catch : si les stats echouent, la liste s'affiche sans stats)
- Carte magasin : CircleAvatar avec l'initiale, nom, 'Gerant : <nom>'
- 3 IconButton par carte : 'Transferer du stock' (desactive s'il n'y a pas d'autre magasin, pousse TransfersScreen(preselectedSourceId:) via MaterialPageRoute), 'Renommer', 'Supprimer'
- Bloc de statistiques : Produits, Stock (quantite), Valeur stock, Ventes, Benefice (vert si > 0) — '—' si la stat est absente
- Section 'Equipe' : chaque employe avec icone check (confirme) ou sablier (en attente) + 'nom · position ou commande_role'
- FAB 'Magasin' -> dialog 'Creer un magasin' avec Form + validators : Nom du magasin (requis), Nom du gerant (requis), Email du gerant (doit contenir @), Mot de passe (>= 6 caracteres) ; POST users/register/ role=magasin puis PUT users/approve/{id} ; affichage d'erreur en haut du dialog
- Dialog 'Renommer le magasin' (PATCH users/magasins/{id}/ shop_name) avec etat _saving
- Suppression protegee par mot de passe : dialog dedie (_DeletePasswordDialog, champ obscure) puis DELETE users/magasins/{id}/ avec {password} en body, erreur en snackbar

**Manques constates** (7)

- Le logo du magasin est parse dans le modele (Magasin.shopLogo) mais jamais affiche ni modifiable — le web propose l'upload du logo dans son dialog 'Modifier le magasin' (patchFormData)
- Aucune garde d'acces : le web affiche les actions seulement si isAdmin, ici tout gerant voit Creer / Renommer / Supprimer / Transferer
- Pas de recherche ni de filtre sur la liste des magasins
- Le bouton Transferer sort du ShellRoute (MaterialPageRoute au lieu d'une route go_router parametree) : pas d'URL, retour uniquement par Navigator.pop
- Aucun indicateur de chargement sur les actions de la carte (renommer/supprimer) et pas de confirmation textuelle du nom a retaper
- L'equipe est affichee integralement sans action possible (pas d'approbation/edition ici, cela se trouve dans users_screen.dart)
- Pas d'appel a l'equivalent de transfers.getProfitByMagasins() du web (le benefice vient uniquement de magasins/stats/)

#### `smartcross/lib/features/transfers/transfers_screen.dart`

- **Route** : /transfers (ShellRoute, router.dart:113) — la route ne transmet pas de source ; le parametre preselectedSourceId n'est utilise que par le push depuis Magasins
- **Role** : Gerant (NavItem roles:{gerant}) — cote backend reserve a l'admin multi-magasins, aucune verification cote Flutter

**Implemente** (9)

- AppBar 'Transfert de stock'
- Deux DropdownButtonFormField 'Depuis' / 'Vers' : la destination exclut la source, auto-selection du premier element, correction automatique si la destination devient invalide
- Changer la source vide le panier (quantites, libelles, stocks disponibles)
- EmptyState explicite si moins de 2 magasins ('Il faut au moins deux magasins pour transferer du stock.')
- Chargement du catalogue du magasin source via StoresRepository.catalogFor(magasinId) = GET catalog/references/?magasin_id= dans un FutureBuilder (rechargement sur changement de source via didUpdateWidget)
- Liste ExpansionTile par reference : titre 'marque reference', sous-titre 'categorie / sous-type — prix de vente formate en Ar'
- Une ligne par variante : libelle 'reference (couleur)', 'Disponible : n', champ quantite numerique de 80px, desactive si stock 0, valeur clampee automatiquement a [0, stock] avec correction visible du champ
- Bouton pleine largeur 'Transferer (n)' affiche des qu'au moins une ligne a une quantite > 0 ; POST users/transfer/products/ {source_magasin_id, destination_magasin_id, items:[{variant_id, quantity}]} ; invalidation de storesProvider, snackbar 'Transfert effectue' puis pop
- Etat _submitting (libelle 'Transfert…', bouton desactive), erreurs via ApiClient.messageFromError en snackbar

**Manques constates** (8)

- Pas de champ de recherche produit dans le selecteur (le panel web a productSearchTerm) ni de recherche de magasin destination
- Pas de recapitulatif du panier : seul le compteur dans le bouton ; impossible de retirer une ligne autrement qu'en vidant son champ, et les lignes selectionnees ne sont pas regroupees a l'ecran
- Le ErrorState du selecteur de produits a onRetry: () {} — le bouton 'Reessayer' n'a aucun effet (transfers_screen.dart:182)
- Aucun historique des transferts effectues
- Aucune garde de role : le web affiche une page 'Acces refuse' si !isAdmin
- Pas de quantite au niveau reference entiere (le panel web permet d'ajouter au niveau produit ET au niveau variante)
- Le panier est stocke dans des Map mutables passees par reference aux sous-widgets (quantities/labels/available) : pas de state object, pas de persistance si l'ecran est reconstruit
- Aucun retour visuel de progression pendant le POST autre que le libelle du bouton

#### `smartcross/lib/features/suppliers/suppliers_screen.dart`

- **Route** : /suppliers (ShellRoute, router.dart:101)
- **Role** : Gerant (NavItem roles:{gerant}) — aucune garde dans le routeur

**Implemente** (5)

- AppBar 'Fournisseurs', RefreshIndicator sur toute la liste, EmptyState 'Aucune commande fournisseur.', ErrorState avec Reessayer, LoadingState
- Tuile par commande : numero en gras, 'description ou Sans description · n article(s)', StatusChip du statut (vert si recu, orange sinon), cout total formate en Ar
- Tap sur une tuile -> context.push('/suppliers/{id}')
- FAB 'Nouvelle commande' -> context.push('/suppliers/new')
- Rafraichissement temps reel : supplierOrdersProvider fait ref.watch(realtimeTickProvider) (rechargement a chaque message WebSocket)

**Manques constates** (6)

- Pas de bouton 'Receptionner' directement dans la liste (present dans le tableau web) : il faut ouvrir le detail
- Pas de recherche ni de filtre par statut (Brouillon/Commande/Recu)
- Cout unitaire non affiche dans la liste (colonne presente cote web)
- Pas de bouton Actualiser explicite (uniquement le pull-to-refresh)
- Aucune modification ni suppression d'une commande fournisseur
- La date de la commande n'est pas affichee dans la liste

#### `smartcross/lib/features/suppliers/supplier_order_create_screen.dart`

- **Route** : /suppliers/new (sous-route de /suppliers, router.dart:104)
- **Role** : Gerant

**Implemente** (7)

- AppBar 'Nouvelle commande fournisseur', formulaire en ListView
- Champs : Description, Prix fournisseur (Ar), Fret / import (Ar), Douane (Ar), Budget pub Meta Ads (Ar) — tous numeriques avec icone, recalcul du total a chaque frappe
- Section Lignes : bouton 'Ajouter' -> SimpleDialog listant TOUTES les variantes du cache referencesProvider (label 'marque reference — couleur'), ajout avec quantite 1
- Par ligne : boutons - / + (le - est desactive a 1) et bouton supprimer la ligne
- Carte de synthese : Quantite totale et Cout total estime (prix fournisseur + fret + douane + meta ads)
- Bouton 'Creer la commande' avec CircularProgressIndicator pendant l'envoi ; POST suppliers/orders/ avec les 4 postes de cout + lines[{product_variant, quantite}] puis context.go('/suppliers/{id}')
- Bloc d'erreur en haut du formulaire (errorContainer) alimente par ApiClient.messageFromError, et validation 'Ajoutez au moins une ligne.'

**Manques constates** (7)

- Le selecteur de produit n'a NI recherche NI filtre marque/categorie (le dialog web propose Select Marque + Select Categorie + champ 'Rechercher une reference ou couleur')
- Les variantes proviennent de ref.read(referencesProvider).value ?? [] : si le catalogue n'est pas encore charge la liste est vide et affiche 'Aucune variante disponible.' sans etat de chargement ni rechargement
- Pas de cout unitaire estime affiche (le web l'affiche : cout total / quantite totale)
- Pas de champ quantite au moment de l'ajout d'une ligne (il faut ajouter puis incrementer un par un)
- Pas de gestion des doublons : la meme variante peut etre ajoutee plusieurs fois en lignes separees
- Description est un TextField simple (le web utilise un Textarea multi-lignes)
- Aucune sauvegarde de brouillon ; quitter l'ecran perd tout

#### `smartcross/lib/features/suppliers/supplier_order_detail_screen.dart`

- **Route** : /suppliers/:id (sous-route, router.dart:105-108, id parse en int)
- **Role** : Gerant

**Implemente** (5)

- AppBar 'Commande fournisseur', chargement via supplierOrderDetailProvider(id) (FutureProvider.autoDispose.family qui watch realtimeTickProvider), ErrorState avec Reessayer, LoadingState
- En-tete : numero en headlineSmall + StatusChip du statut (vert si recu sinon orange), description si presente
- Carte de couts : Date (dd/MM/yyyy), Prix fournisseur, Fret / import, Douane, Pub Meta Ads, separateur, Cout total (en gras) et Cout unitaire moyen
- Liste des lignes : 'reference — couleur', 'quantite × cout unitaire calcule · marge unitaire X', total de la ligne a droite
- Bouton 'Marquer recue (entree stock auto.)' affiche uniquement si la commande n'est pas deja recue, avec dialog de confirmation ('Le stock sera incremente automatiquement pour chaque ligne'), spinner pendant l'appel, POST suppliers/orders/{id}/receive/ puis invalidation du detail ; erreurs en snackbar

**Manques constates** (5)

- Aucune modification ni suppression de la commande ou de ses lignes
- created_at et received_at sont parses dans le modele SupplierOrder mais jamais affiches (pas d'historique de reception)
- Pas d'export PDF/Excel de la commande fournisseur
- Pas de pull-to-refresh (seulement le rafraichissement temps reel et le Reessayer en cas d'erreur)
- Pas de lien vers les produits/variantes concernes depuis les lignes

#### `smartcross/lib/features/caisse/caisse_screen.dart`

- **Route** : /caisse (ShellRoute, router.dart:84)
- **Role** : Gerant (NavItem roles:{gerant})

**Implemente** (12)

- Ecran a 2 onglets : 'Session en cours' et 'Historique' (DefaultTabController)
- SESSION — si aucune session ouverte : vue centree avec icone, message et bouton 'Ouvrir la caisse' (scrollable pour permettre le pull-to-refresh)
- SESSION — si session ouverte : carte 'Session ouverte' avec Fond de depart, Solde actuel estime (calcule cote client : fond + entrees - sorties via CaisseSession.soldeCourant) et 'Ouverte le <date> · <ouvreur>'
- SESSION — deux boutons Entree / Sortie ouvrant _MovementDialog
- SESSION — liste des mouvements de la session (ordre inverse) : avatar vert/rouge, motif, date + auteur, montant signe colore
- SESSION — bouton 'Fermer la caisse' en rouge (couleur error)
- Dialog 'Ouvrir la caisse' : Fond de depart (clavier decimal, refus des valeurs < 0), Note optionnelle, POST users/caisse/sessions/open/ avec le magasin_id de l'utilisateur
- Dialog 'Fermer la caisse' : rappel du solde attendu estime, Montant compte pre-rempli avec le solde courant, Note optionnelle, POST .../close/
- Dialog mouvement (Entree ou Sortie selon le bouton) : Montant (autofocus) + Motif, validation 'Montant et motif requis' (montant > 0, motif non vide), POST users/caisse/movements/
- HISTORIQUE — liste des sessions : icone cadenas ouvert/ferme, date d'ouverture ou 'Session #id', sous-titre 'Ouverte · fond X' ou 'Fermee · attendu X · compte Y (· ecart Z si != 0)' ; RefreshIndicator, EmptyState, ErrorState
- Providers : currentCaisseProvider (AsyncNotifier qui prend le magasinId depuis authProvider.user, watch realtimeTickProvider) et caisseHistoryProvider (FutureProvider.autoDispose), refresh apres chaque open/close/addMovement
- Affichage monetaire homogene (NumberFormat fr_FR + ' Ar') et dates dd/MM/yyyy HH:mm en heure locale

**Manques constates** (7)

- Pas de 'Resume de la caisse' par periode : le web appelle caisse.summary({magasinId, dateFrom, dateTo}) et affiche Entrees, Sorties, Solde, CA produits vendus, Cout des produits vendus, Benefice produits vendus, et 'Sorties par categorie' — rien de tout cela n'existe cote Flutter (CaisseRepository n'a pas de methode summary)
- Pas de filtre de dates ni de liste des mouvements de la periode independamment de la session (web : caisse.listMovements avec dateFrom/dateTo)
- Pas de categorie de depense sur les sorties (le web ajoute un Select 'Categorie' alimente par caisse.categories.list() pour movement_type = out) ; aucun ecran de gestion des categories de depense n'existe dans l'app (rien dans settings_screen.dart)
- Pas de selecteur de magasin : le magasinId vient uniquement de authProvider.user.magasinId ; s'il est null, build() renvoie null et l'ecran affiche 'Aucune session ouverte' sans expliquer pourquoi, et open() leve un StateError
- Les sessions de l'historique ne sont pas cliquables : pas de detail, pas d'affichage des notes d'ouverture/fermeture, du fermeur (closedByName) ni des mouvements de la session passee (tous ces champs sont pourtant parses dans CaisseSession)
- Le solde courant est une estimation client jamais confrontee a expected_balance tant que la session est ouverte
- Pas de bouton Actualiser explicite (le web en a un) ; pas d'export du journal de caisse

**Infrastructure reutilisable** (20)

- ROUTER — lib/core/router.dart : routerProvider (Provider<GoRouter>), initialLocation '/splash', refreshListenable = _RouterRefresh qui ecoute authProvider et notifie a chaque changement de AuthStatus. Redirect global : loading -> /splash ; unauthenticated -> /login sauf prefixes publics ('/login', '/server-setup', '/splash') ; authenticated sur une route publique -> _homeFor(role) (gerant -> /dashboard, preparateur -> /depot, livreur -> /tournee). IMPORTANT : aucune garde par ROLE sur les routes — n'importe quel utilisateur authentifie peut atteindre /catalog, /stores, /transfers, /suppliers, /caisse par URL ; seul kPrimaryNavItems filtre le menu.
- ROUTES EXISTANTES — /splash, /server-setup, /login hors shell ; dans le ShellRoute (NavigationShell) : /dashboard, /caisse, /orders (+ /orders/new, /orders/:id), /depot, /tournee, /bilan, /catalog, /suppliers (+ /suppliers/new, /suppliers/:id), /users, /stores, /transfers, /chats (+ /chats/room/:room, /chats/dm/:id avec titre passe en state.extra), /notifications, /settings. Modele a suivre pour ajouter un ecran : GoRoute dans le ShellRoute + NavItem dans core/nav_items.dart.
- NAVIGATION — lib/core/nav_items.dart : NavItem{path, label, icon, roles} avec visibleFor(role) ; kPrimaryNavItems declare les 14 entrees et leurs roles. lib/widgets/navigation_shell.dart : bascule sidebar permanente 240px (largeur >= kDesktopBreakpoint = 900) vs Drawer sur mobile, item selectionne par currentPath.startsWith(item.path), navigation via context.go().
- TOPBAR — lib/widgets/topbar.dart (PreferredSizeWidget, hauteur 64) : logo + 'Smartphone.Mg', pastille verte/orange d'etat WebSocket (wsConnectionStatusProvider), icone Notifications avec Badge du nombre non lus (unreadNotificationsCountProvider) qui push /notifications, menu Compte (nom/email/role) avec Deconnexion (authProvider.notifier.logout() puis context.go('/login')).
- THEME — lib/core/theme.dart : buildLightTheme()/buildDarkTheme() Material 3 depuis kSeedColor = #2563EB, scaffold = surface, AppBar plate sans surfaceTint, CardThemeData (radius 14, bordure outlineVariant, elevation 0), InputDecorationTheme (OutlineInputBorder radius 10, filled). themeMode: ThemeMode.system dans main.dart. kChartPalette (8 couleurs) et statusColor(context, apiStatus) pour les 7 statuts de commande.
- AUTH — lib/state/auth_provider.dart : AuthNotifier (NotifierProvider) avec AuthStatus{loading, unauthenticated, authenticated} + AppUser ; _bootstrap() = ensureInitialized + lecture du token + GET users/me/ ; login(email,password), logout(), refreshUser() ; _invalidateDataProviders(ref) invalide 19 providers metier a chaque login/logout (ordersProvider, categoriesProvider, typesProvider, brandsProvider, colorsProvider, referencesProvider, dashboardProvider, rupturesProvider, movementsProvider, supplierOrdersProvider, currentCaisseProvider, caisseHistoryProvider, storesProvider, accountsProvider, pendingUsersProvider…) — TOUT NOUVEAU PROVIDER DOIT Y ETRE AJOUTE. authEventProvider (StreamProvider) fait passer la session en unauthenticated sur 401 non rafraichissable.
- STOCKAGE DU TOKEN — lib/core/secure_storage.dart : TokenStorage (singleton, flutter_secure_storage) avec save/saveAccess/accessToken/refreshToken/clear (cles 'access_token' / 'refresh_token') ; AppPrefs (shared_preferences) pour l'URL serveur configurable ('server_base_url'), modifiable via l'ecran /server-setup.
- CLIENT HTTP — lib/core/api_client.dart : ApiClient.instance (singleton Dio, baseUrl '<serveur>/api/', timeouts 20s/30s). Intercepteur onRequest qui pose 'Authorization: Bearer <access>' ; onError qui, sur 401 non deja rejoue, tente POST users/refresh/ avec le refresh token, sauvegarde le nouvel access et rejoue la requete, sinon emet AuthEvent(sessionExpired). ensureInitialized()/setBaseUrl(url) (normalise le slash final), wsBaseUrl (http->ws, https->wss). Deux helpers statiques REUTILISABLES PARTOUT : isConnectivityError(error) et messageFromError(error) (extrait error/detail/message ou aplatit les erreurs de validation DRF 'champ: msg1, msg2').
- TEMPS REEL — lib/core/ws_manager.dart : classe abstraite WsManager (connexion authentifiee par token en query string, reconnexion automatique apres 3s, buildUri rappelee a chaque tentative pour un token frais, decodage JSON, send/disconnect, hooks onMessage/onStatusChange). lib/core/notifications_socket_service.dart : singleton NotificationsSocketService sur ws/notifications/ (streams incoming + connectionStatus). lib/core/chat_socket_service.dart : instance jetable sur ws/chat/ avec heartbeat de presence toutes les 20s et actions send/edit/delete/read.
- TEMPS REEL cote Riverpod — lib/state/realtime_provider.dart : realtimeTickProvider (compteur incremente a chaque message WS), RealtimeBootstrap instancie une seule fois dans main.dart (connecte/deconnecte selon authProvider), wsConnectionStatusProvider (StreamProvider<bool>). PATTERN A REPRENDRE : un provider de donnees fait ref.watch(realtimeTickProvider) dans build() pour se rafraichir automatiquement — deja fait par ordersProvider, orderDetailProvider, dashboardProvider, rupturesProvider, movementsProvider, supplierOrdersProvider, supplierOrderDetailProvider, notificationsProvider, currentCaisseProvider, caisseHistoryProvider. PAS ENCORE FAIT par referencesProvider/categoriesProvider/typesProvider/brandsProvider/colorsProvider ni storesProvider.
- PROVIDERS RIVERPOD EXISTANTS — auth_provider, catalog_provider (categoriesProvider, typesProvider, brandsProvider, colorsProvider, referencesProvider avec CRUD complet + uploadPhoto + bulkUpdatePrice, referenceAutocompleteProvider family), stock_provider (rupturesProvider, movementsProvider family<int?>), stores_provider (storesProvider + create/rename/delete), suppliers_provider (supplierOrdersProvider + create/receive, supplierOrderDetailProvider family), caisse_provider (currentCaisseProvider, caisseHistoryProvider), orders_provider (ordersProvider, ordersFilterProvider, orderDetailProvider, deliveryZonesProvider, assignation livreur/preparateur, changeStatus, cancel, updateOrder, availableStaff), users_provider (accountsProvider, pendingUsersProvider), dashboard_provider (dashboardProvider + dashboardFilterProvider), notifications_provider (notificationsProvider + unreadNotificationsCountProvider), company_provider (passwordResetRequestsProvider). Convention : un Provider<XxxRepository> par module + AsyncNotifier avec refresh()/actions qui rappellent refresh().
- REPOSITORIES — lib/data/repositories/ : auth (login/logout/me/updateProfile/uploadProfilePhoto/changePassword), catalog (CRUD categories/types/brands/colors/references/variants, autocomplete, bulk-update-price, export-excel bytes, import-excel multipart avec ExcelImportResult et en-tetes X-Import-*), stock (movements, adjust, ruptures derivees du catalogue, ruptureExportPdfBytes genere localement), stores (list fusionnee users+stats, create via register+approve, rename, delete avec mot de passe, catalogFor(magasinId), transfer(items)), suppliers (list/detail/create/receive), caisse (current/history/open/close/addMovement), orders, users, dashboard, notifications, chat, company (demandes de reinitialisation de mot de passe).
- MODELES — lib/models/ avec lib/models/json_utils.dart (asInt/asIntOrNull/asDouble/asDoubleOrNull/asBool/asString/asStringOrNull/asDateOrNull, tolerants aux Decimal serialises en string par DRF). Modeles disponibles : catalog.dart (ProductCategory, ProductType, Brand, ProductColor, ProductVariant, ProductReference avec margeUnitaire, ReferenceOption/ColorOption pour l'autocomplete), stock.dart (StockMovement, RuptureItem avec quantiteACommander), magasin.dart (Magasin + withStats(), MagasinEmployer), supplier.dart (SupplierOrder, SupplierOrderLine, SupplierOrderLineDraft), caisse.dart (CaisseSession avec soldeCourant, CaisseMovement), order.dart, user.dart (AppUser avec role_commande, magasinId, rawRole, isCompanyOwner ; PendingUser), dashboard.dart, chat.dart, app_notification.dart, delivery_zone.dart, company.dart.
- WIDGETS PARTAGES REUTILISABLES — lib/widgets/async_state_widgets.dart (LoadingState, ErrorState{message,onRetry}, EmptyState{message,icon}) utilises par tous les ecrans en scope ; status_badge.dart (StatusChip{label,color}, OrderStatusBadge(status), StockLevelBadge{isRupture,isStockBas}) ; kpi_card.dart (KpiCard + KpiGrid responsive 2/3/4/5 colonnes) ; navigation_shell.dart ; topbar.dart ; assign_staff_dialog.dart (choix d'un membre du personnel + date/heure) ; order_confirm_dialog.dart (confirmation avec note + photo) ; order_historique_view.dart (vue historique avec filtres de dates reutilisable via cardBuilder).
- CONSTANTES ET ENUMS — lib/core/constants.dart : UserRole{gerant,preparateur,livreur,unknown} avec fromApi/apiValue/label, OrderStatus (7 valeurs) avec fromApi/apiValue/label, PaymentMode, StockMovementType{entree,sortie}, SupplierOrderStatus{brouillon,commande,recu}, kDesktopBreakpoint = 900, helper dialogWidth(available, desired).
- FUSEAU HORAIRE — lib/core/app_time.dart : appNow(), appLocal(), appDay(), appToday(), appWallClockToUtc(), appDayBounds() ; decalage fixe Indian/Antananarivo UTC+3, a utiliser pour tout filtre date_from/date_to envoye au serveur (utilise par les ecrans depot/tournee/orders, PAS encore par catalog/caisse).
- CONVENTIONS D'AFFICHAGE — chaque ecran redeclare localement `final _moneyFmt = NumberFormat.decimalPattern('fr_FR'); String _ar(num v) => '${_moneyFmt.format(v.round())} Ar';` (duplique dans catalog, stores, transfers, caisse, suppliers x3) et `final _dateFmt = DateFormat('dd/MM/yyyy HH:mm')` — candidat evident a une factorisation dans un helper partage.
- FICHIERS/EXPORT — partage de fichiers via share_plus (SharePlus.instance.share(ShareParams(files:[XFile.fromData(bytes,...)]))) pour l'export Excel du catalogue, le fichier annote d'import et le PDF de reapprovisionnement ; generation PDF locale via le package pdf (pw.MultiPage + pw.TableHelper.fromTextArray) ; selection de fichier via FilePicker.pickFile (API statique file_picker 12.x, PlatformFile.readAsBytes() pour supporter les URI content:// Android) ; photos via ImagePicker().pickImage(source: gallery, imageQuality: 85) ; upload multipart via FormData/MultipartFile (catalog_repository.uploadReferencePhoto, auth_repository.uploadProfilePhoto).
- DEPENDANCES DECLAREES (pubspec.yaml) : flutter_riverpod 3.4.2, go_router 17.3.0, dio 5.11, web_socket_channel 3.0.3, flutter_secure_storage 10.3.1, shared_preferences, intl, collection, share_plus, pdf, image_picker, file_picker, url_launcher. NON UTILISEES actuellement dans lib/ (aucune import) : fl_chart, printing, flutter_local_notifications, connectivity_plus, path_provider, cupertino_icons — fl_chart notamment n'est pas utilise par le dashboard (pas de graphique).
- REFERENCE NEXT.JS pour le portage — /home/garrix/Dev/Smartphone/frontend/app/(app)/ contient 19 pages ; celles NON ENCORE portees en ecrans Flutter dedies : reports/, sales/, superadmin/, pickup/, alerts/ et movements/ (ces deux dernieres sont partiellement couvertes par les onglets Ruptures/Mouvements de catalog_screen). Composants web reutilisables a porter : transfer-products-panel.tsx, product-image-gallery.tsx, image-upload.tsx, ai-analysis.tsx, confirm-delete-dialog.tsx.

**Notes**

Audit factuel realise par lecture integrale de : catalog_screen.dart (2014 l.), stores_screen.dart (354 l.), transfers_screen.dart (283 l.), les 3 fichiers suppliers/ (77 + 219 + 153 l.), caisse_screen.dart (413 l.), plus leurs providers (catalog_provider, stock_provider, stores_provider, suppliers_provider, caisse_provider), repositories (catalog 269 l., stock, stores, suppliers, caisse) et modeles (catalog, stock, magasin, supplier, caisse, user, json_utils), ainsi que toute l'infrastructure (router, api_client, secure_storage, theme, nav_items, ws_manager, chat/notifications socket, app_time, main, auth_provider, realtime_provider, widgets partages).

Les "gaps" ont ete etablis par comparaison ligne a ligne avec les pages Next.js correspondantes : app/(app)/products/page.tsx (3431 l.), stores/page.tsx (589 l.), transfers/page.tsx + components/transfer-products-panel.tsx, suppliers/page.tsx (348 l.), caisse/page.tsx (697 l.), movements/page.tsx (899 l.), alerts/page.tsx (184 l.). Aucune fonctionnalite n'est declaree presente sans avoir ete vue dans le code Dart.

Trois constats transversaux qui conditionnent la suite du portage :
1) Le routeur ne fait AUCUN controle de role — seul le menu lateral filtre. Tout ecran gerant est atteignable par URL par un preparateur/livreur. Une garde par role dans le redirect de router.dart beneficierait a tous les ecrans a porter.
2) Le pattern de rafraichissement temps reel (ref.watch(realtimeTickProvider) dans le build d'un AsyncNotifier) est en place et couvre commandes/dashboard/stock/fournisseurs/caisse/notifications, mais PAS le catalogue (references/categories/types/marques/couleurs) ni les magasins.
3) Le module Caisse est le plus eloigne de la parite web : ni resume par periode (endpoint summary), ni categories de depense, ni mouvements hors session — trois briques absentes aussi bien de l'ecran que du CaisseRepository.

Fichiers cles a reutiliser pour porter un nouvel ecran : /home/garrix/Dev/Smartphone/smartcross/lib/widgets/async_state_widgets.dart, /home/garrix/Dev/Smartphone/smartcross/lib/widgets/status_badge.dart, /home/garrix/Dev/Smartphone/smartcross/lib/widgets/kpi_card.dart, /home/garrix/Dev/Smartphone/smartcross/lib/core/api_client.dart (messageFromError), /home/garrix/Dev/Smartphone/smartcross/lib/models/json_utils.dart, /home/garrix/Dev/Smartphone/smartcross/lib/core/app_time.dart, et l'ajout obligatoire de tout nouveau provider dans _invalidateDataProviders() de /home/garrix/Dev/Smartphone/smartcross/lib/state/auth_provider.dart.

### Groupe `admin`

#### `smartcross/lib/features/dashboard/dashboard_screen.dart`

- **Route** : /dashboard (dans le ShellRoute, builder const DashboardScreen())
- **Role** : Gerant uniquement au niveau de la navigation (kPrimaryNavItems: roles {UserRole.gerant}) et cible de redirection _homeFor(gerant). AUCUN garde de route: un preparateur/livreur qui tape /dashboard obtient l ecran quand meme.

**Implemente** (10)

- Scaffold sans AppBar (la TopBar vient du NavigationShell), corps = ListView scrollable + RefreshIndicator qui appelle dashboardProvider.notifier.refresh()
- Titre texte 'Tableau de bord' (headlineSmall)
- Filtre de periode: 4 ChoiceChip generes depuis DashboardPeriodPreset.values -> Aujourd'hui / Cette semaine / Ce mois / Personnalise; onSelected ecrit dans dashboardFilterProvider (copyWith(preset:)), ce qui re-declenche DashboardNotifier.build()
- Machine a etats complete via switch sur AsyncValue: AsyncData -> _DashboardBody, AsyncError -> ErrorState(message: ApiClient.messageFromError, onRetry: refresh), sinon LoadingState
- Bloc KPI (KpiGrid + 5 KpiCard): Ventes (periode) = nbVentes, CA periode, CA mois en cours, Taux livraison reussie (%, '—' si null), Retours. Montants formates via NumberFormat.decimalPattern('fr_FR') + suffixe ' Ar'
- Bloc 'Suivi commandes en temps reel': Wrap de _StatusCountChip construits depuis data.suiviCommandesTempsReel (map statut->compte), avec libelles FR pour NOUVELLE / EN_PREPARATION / PRETE / EN_LIVRAISON / LIVRE / RETOUR
- Bloc 'Analyse financiere' (Card): 5 lignes _FinanceRow -> CA produits vendus, Frais de livraison encaisses, Total investi fournisseurs (affiche en negatif rouge), Total pub Meta Ads (negatif rouge), Divider, Benefice estime (gras, vert si >=0 sinon rouge)
- Bloc 'Stock rapide' (KpiGrid + 3 KpiCard): Total en stock, Ruptures (rouge), Stock bas (orange)
- Bloc 'TOP 20 produits (periode)': 4 cartes _TopList (Par sous-type, Marques, References, Couleurs) en GridView 2 colonnes si largeur >= 700, sinon Column empilee; chaque carte affiche 'Aucune donnee' si vide sinon au maximum 5 lignes label + quantite
- Rafraichissement temps reel indirect: DashboardNotifier.build() fait ref.watch(realtimeTickProvider), donc chaque message du WebSocket notifications refetch le dashboard

**Manques constates** (9)

- AUCUN graphique: fl_chart est dans pubspec.yaml et kChartPalette est defini dans core/theme.dart mais aucun fichier de lib/ n importe fl_chart ni n utilise kChartPalette. Le web (frontend/app/(app)/dashboard/page.tsx) a recharts: LineChart tendance hebdo, PieChart par categorie, BarChart, Legend, Tooltip.
- Le preset 'Personnalise' est selectionnable mais il n existe AUCUN date picker: DashboardFilter.resolveRange() renvoie (dateDebut, dateFin) qui restent null -> le filtre ne fait rien et l ecran retombe sur la periode complete cote serveur
- Le titre annonce 'TOP 20 produits' mais _TopList tronque a 5 entrees (entries.length > 5 ? 5 : entries.length)
- Probleme de layout probable en mode etroit (<700px): _TopList place un Expanded(ListView) dans une Column non bornee (Column dans ListView) — configuration qui declenche l assertion Flutter 'RenderFlex children have non-zero flex but incoming height constraints are unbounded'. En mode large le GridView.count borne la hauteur donc le cas ne se produit pas.
- Aucun bouton masquer/afficher les montants sensibles (le web a hiddenMetrics + icones Eye/EyeOff sur ca, totalProfit, totalValue, beneficeEstimeStock, totalSalesAllStores)
- Aucune liste 'Mouvements recents' ni 'Produits en stock bas' cliquables (presentes cote web)
- Pas de variante de dashboard par role: le web bascule sur dashboardData.role ('employee'/...); ici un seul rendu gerant
- Endpoint different du web: Flutter appelle orders/dashboard/ (DashboardRepository), le web appelle /users/dashboard/ + products.list() — la parite de donnees n est pas garantie
- Pas d etat 'skeleton' (le web utilise des Skeleton), juste un CircularProgressIndicator centre

#### `smartcross/lib/features/users/users_screen.dart`

- **Route** : /users (ShellRoute, const UsersScreen())
- **Role** : Nav visible pour UserRole.gerant uniquement. Le 3e onglet 'Mots de passe' est conditionne par currentUser?.rawRole == 'admin' (role Django brut). Aucun garde de route: /users est atteignable en tapant l URL avec n importe quel role.

**Implemente** (12)

- DefaultTabController + AppBar 'Utilisateurs' avec TabBar scrollable: 'Equipe', 'En attente (n)' (n = pendingUsersProvider.value.length, affiche seulement si >0), et 'Mots de passe' si admin
- FloatingActionButton.extended 'Ajouter' -> ouvre _CreateUserDialog
- Onglet Equipe (_TeamTab): RefreshIndicator -> accountsProvider.refresh(); switch AsyncData/AsyncError/loading avec EmptyState('Aucun compte preparateur/livreur.'), ErrorState + Reessayer, LoadingState; ListView de _UserTile
- _UserTile: avatar (NetworkImage user.photo sinon initiale), nom, email, ligne 'phone · adresse' si presentes, ligne 'Derniere connexion : dd/MM/yyyy HH:mm' ou 'Jamais connecte'
- _UserTile: DropdownButtonFormField<UserRole> (Preparateur/Livreur) qui appelle accountsProvider.notifier.updateCommandeRole(user.id, role.apiValue) -> PUT users/employers/<id>/commande-role/, avec SnackBar de succes ou d erreur
- _UserTile: PopupMenuButton avec 'Modifier' (-> _EditUserDialog) et 'Supprimer' (-> flux mot de passe)
- _PasswordConfirmDialog: texte de confirmation nominatif + TextField obscureText 'Votre mot de passe' + boutons Annuler / Supprimer (rouge). Le mot de passe est envoye a DELETE users/delete/<id>/
- _EditUserDialog: champs Nom complet, Email (desactive), Telephone, Adresse (2 lignes), Dropdown Role (Preparateur/Livreur), encadre 'Connexion' en lecture seule (derniere connexion, derniere deconnexion, Statut Actif/Inactif), affichage d erreur, bouton Enregistrer avec etat 'Enregistrement...'
- _CreateUserDialog: Form + validators (nom requis, email doit contenir '@', mot de passe >= 6 caracteres), champs Nom complet / Email / Telephone (optionnel) / Mot de passe (obscure) / Dropdown 'Role module Commande' (Preparateur|Livreur); appelle accountsProvider.create() qui poste users/register/ avec role=employer, admin_email = email du gerant connecte, commande_role et position derivee
- Onglet En attente (_PendingTab): RefreshIndicator, EmptyState 'Aucune demande en attente.', liste de Card/ListTile avec nom, 'email · position', et deux IconButton Approuver (vert, PUT users/approve/<id>/) et Rejeter (rouge, POST users/reject/<id>/)
- Onglet Mots de passe (_PasswordResetsTab, admin): SegmentedButton 4 segments (En attente / Approuvees / Rejetees / Toutes) branche sur passwordResetRequestsProvider.notifier.setStatus, RefreshIndicator, EmptyState 'Aucune demande.', ErrorState + retry
- _PasswordResetTile: nom + email, Chip de statut colore (vert approved / rouge rejected / orange pending) avec libelles FR, ligne 'role · Magasin : X', date creation formatee, et si status=='pending' deux OutlinedButton Approuver / Rejeter -> PATCH users/password-reset-requests/<id>/ {action}

**Manques constates** (12)

- BUG dans _UserTile._confirmDelete: le dialogue _PasswordConfirmDialog est ouvert DEUX FOIS. Le premier appel est showDialog<bool> alors que le dialogue fait Navigator.pop(_controller.text) (une String) -> cast String vers bool a l execution; et meme sans le crash l utilisateur devrait saisir son mot de passe deux fois. Le chemin de suppression est donc casse.
- BUG dans _EditUserDialog._save(): seul updateCommandeRole() est appele. Les champs Nom complet, Telephone et Adresse edites dans le dialogue ne sont JAMAIS envoyes au serveur (aucun appel PATCH users/<id>/ ou users/me/). Le dialogue laisse croire a une edition de profil qui n a pas lieu. Il contient aussi un Future.delayed(100ms) arbitraire avant de fermer.
- BUG UI dans _PasswordResetsTab: SegmentedButton a selected: const {'pending'} en dur -> le segment actif ne change jamais visuellement quand on filtre (les donnees, elles, se rechargent bien).
- Aucun champ de recherche (le web a un Input 'Rechercher...' avec debounce filtrant nom+email sur les deux listes)
- UsersRepository.list() ne lit que magasins.first['employers'] -> les managers (store.manager) et les company_users que le web agrege sont absents; la liste ne montre donc que les employes du premier magasin
- Pas d edition du role Django (admin/magasin/employer): le web a un dialog 'Modifier role' qui PUT /users/role/<id>/. Ici seul le sous-role Commande Preparateur/Livreur est modifiable.
- Colonnes du web absentes: Magasin (shop_name), Poste (position), badge en ligne/hors ligne calcule (isCurrentlyOnline: last_login_at > last_logout_at) avec 'Actif il y a X'/'Hors ligne il y a X' et son timer de rafraichissement de 10 min
- Pas de creation de compte 'magasin' (gerant de magasin) ni 'admin' (POST /users/add-admin/) — le web les propose selon isAdmin / isCompanyOwner
- Pas de protection 'on ne peut pas se supprimer/modifier soi-meme' (le web teste u.id !== currentUser.id) ni de regle isCompanyOwner pour agir sur une ligne admin
- Pas d ecran 'Acces refuse' quand le role n est pas gerant (le web rend une carte ShieldAlert)
- Onglet En attente: pas de confirmation avant rejet (le web fait confirm()), pas de date d inscription affichee, pas de photo
- Pas de bouton de rafraichissement manuel dans l onglet mots de passe (le web a un bouton RefreshCw)

#### `smartcross/lib/features/settings/settings_screen.dart`

- **Route** : /settings (ShellRoute, const SettingsScreen())
- **Role** : Visible pour tous les roles (NavItem sans restriction). A l interieur: edition du profil, changement de mot de passe et cartes Catalogue reserves a UserRole.gerant; les non-gerants voient des messages d avertissement en rouge et des champs desactives.

**Implemente** (11)

- Scaffold + AppBar 'Parametres', corps = ListView de Cards (pas de Tabs)
- Carte 'Mon profil': avatar (FileImage du fichier choisi, sinon NetworkImage user.photo, sinon initiale), bouton 'Changer la photo' (gerant seulement) via ImagePicker gallery imageQuality 85
- Champs profil: Email (desactive), Role (desactive, affiche user.role.label), Nom complet, Telephone, Adresse — les trois derniers actifs seulement si gerant
- Bouton Enregistrer (gerant): AuthRepository().updateProfile(full_name/phone/adresse) puis uploadProfilePhoto (multipart PATCH users/me/) si une photo a ete choisie, puis authProvider.refreshUser(), puis SnackBar 'Profil mis a jour'; affichage de _profileError et libelle 'Enregistrement…' pendant l appel
- Carte 'Changer le mot de passe' (gerant seulement, sinon message rouge): Mot de passe actuel / Nouveau / Confirmer, validations locales (>= 6 caracteres, egalite des deux saisies), POST users/change-password/, message de succes vert, message d erreur rouge, vidage des champs apres succes
- Carte 'Marques' (gerant): 14 ActionChip de marques suggerees (Samsung, iPhone, Huawei, Redmi, Xiaomi, Tecno, Infinix, Itel, Oppo, Realme, Google Pixel, Poco, Vivo, Honor) avec icone check si deja presente / spinner pendant l ajout / icone + sinon; liste complete des marques avec compteur, IconButton renommer (dialog TextField) et supprimer (dialog de confirmation)
- Carte 'Sous-types (categories produit)' (gerant): pour chaque categorie un bloc encadre avec nom, renommer, supprimer, la liste de ses sous-types (renommer/supprimer chacun) ou 'Aucun sous-type.', un TextField 'Nouveau sous-type (ex. Chargeur)' + bouton d ajout (onSubmitted supporte); en bas un TextField 'Nouvelle categorie (ex. Accessoires)' + bouton Ajouter (ordre = nombre actuel de categories)
- Carte 'Couleurs' (gerant): liste des couleurs avec renommer/supprimer, 'Aucune couleur.' si vide, TextField 'Nouvelle couleur (ex: Bleu)' + bouton Ajouter avec etat _adding
- Helper _confirmDialog(context, message) reutilise pour les suppressions categories/types/couleurs
- Carte 'Deconnexion' en bas: ListTile rouge qui appelle authProvider.notifier.logout()
- Toutes les erreurs API passent par ApiClient.messageFromError et un SnackBar

**Manques constates** (9)

- Aucun CRUD des ZONES DE LIVRAISON alors que c est un onglet du web (settings/page.tsx -> DeliveryZonesCrudList, nom + prix). Cote Flutter, orders_repository.dart ne fait que GET orders/delivery-zones/ (lecture seule pour le selecteur de commande) — il n existe ni POST/PATCH/DELETE ni provider zones.
- Aucun CRUD des CATEGORIES DE DEPENSES (onglet 'Depenses' du web -> ExpenseCategoriesCrudList / djangoClient.caisse.categories). caisse_repository.dart n a aucune methode categories.
- Aucune edition du nom + logo de l entreprise / du magasin (le web a un Dialog 'Modifier l entreprise'/'Modifier le magasin' qui PATCH /users/me/ en FormData avec company_name+logo ou shop_name+shop_logo)
- Pas de mise en onglets (le web a Tabs: Mon profil / Securite / Depenses / Zones) — ici tout est empile dans un seul ListView, ce qui devient tres long pour un gerant
- Les cartes Marques / Sous-types / Couleurs n ont ni etat de chargement ni etat d erreur: elles font ref.watch(provider).value ?? [] donc affichent 'Aucune marque/categorie/couleur' pendant le chargement et masquent silencieusement une erreur reseau
- Ces trois cartes n existent pas dans le settings web (le CRUD marque/type/couleur y est dans la page Produits) — le commentaire du fichier qui dit 'meme liste que le web (app/(app)/settings/page.tsx)' est faux, la liste de marques suggerees vient de app/(app)/products/page.tsx
- TextEditingController(text: user?.email) et TextEditingController(text: user?.role.label) sont crees dans build() a chaque reconstruction et jamais dispose (fuite mineure)
- Pas de choix de theme clair/sombre ni de reglage de l URL serveur depuis Parametres (l URL serveur n est modifiable que via /server-setup avant connexion)
- Absence de bloc de deconnexion cote web equivalent — ici c est un plus, pas un manque

#### `smartcross/lib/features/chats/chat_list_screen.dart`

- **Route** : /chats (ShellRoute, const ChatListScreen())
- **Role** : Tous les roles (NavItem 'Discussions' sans restriction de role)

**Implemente** (9)

- Scaffold + AppBar 'Discussions'
- chatRepositoryProvider (Provider(ChatRepository())) et chatUsersProvider (FutureProvider.autoDispose -> GET users/chat/users/) declares dans ce fichier et reutilises par l ecran de conversation
- Timer.periodic de 20 s dans initState qui invalide chatUsersProvider pour rafraichir la presence (miroir du setInterval(fetchUsers, 20000) du web); annule dans dispose
- Le rendu utilise async.value (derniere valeur connue) pour eviter un spinner toutes les 20 s; ErrorState + Reessayer et LoadingState seulement quand aucune donnee
- RefreshIndicator -> ref.refresh(chatUsersProvider.future)
- Entree fixe 'General / Toute l equipe' avec avatar groupe -> context.push('/chats/room/general')
- Une ListTile par collegue: PresenceAvatar (initiale + pastille verte si en ligne), nom, libelle de role traduit (_roleLabel: admin/magasin -> 'Gerant', employer -> 'Equipe'), et ligne de presence coloree
- Helpers publics reutilisables presenceLabel(user) et lastSeenLabel(date) qui reproduisent formatLastSeen() du web: 'En ligne' / "Vu a l'instant" / 'Vu il y a X min' / 'Vu a HH:mm' / 'Hors ligne'
- Navigation vers un DM: context.push('/chats/dm/<id>', extra: user.fullName)

**Manques constates** (6)

- Pas de champ de recherche de collaborateur (le web a un Input 'Rechercher un collaborateur...')
- Pas d apercu du dernier message ni de badge de messages non lus par conversation
- Pas de tri (en ligne d abord, ou par activite recente)
- Pas d onglets General / Direct comme le web (activeTab)
- Pas d indicateur d etat du WebSocket sur cet ecran (seule la TopBar globale en a un, et il concerne la socket notifications, pas la socket chat)
- Le timer de 20 s continue de tourner quand une conversation est poussee par-dessus (assume dans les commentaires) mais aussi quand l ecran est simplement en arriere-plan de l app

#### `smartcross/lib/features/chats/chat_conversation_screen.dart`

- **Route** : /chats/room/:room (parametre :room ignore -> toujours le salon general) et /chats/dm/:id (recipientId = id, titre passe via state.extra)
- **Role** : Tous les roles

**Implemente** (12)

- ChatSocketService jetable cree par ecran: connectToConversation(recipientId:) ouvre ws/chat/?token=...&recipient_id=... ; disposeService() en dispose
- Historique REST au montage: ChatRepository.history(recipientId:) -> GET users/chat/history/ (recipient_id ou room_name=general), avec _loading et _error affiches
- Traitement des messages entrants par type: 'message' (ajout + scroll bas), 'message_edited' (remplace le contenu et met isEdited), 'message_deleted' (isDeleted + contenu vide), 'message_read' (applique read_at a la liste d ids)
- Accuses de lecture: markRead() envoye a chaque (re)connexion sur un DM (ecoute de connectionStatus) et a chaque message recu d un autre expediteur pendant que l ecran est ouvert
- Envoi de message par la socket (action 'send'), pas de POST REST
- Edition: appui long sur un de SES messages -> bottom sheet 'Modifier' / 'Supprimer'; le mode edition prefill le champ, change le hintText en 'Modifier le message…', affiche un bouton croix pour annuler, et l envoi emet action 'edit'
- Suppression: action 'delete' via la socket
- AppBar: titre simple pour le salon general; pour un DM, nom + ligne de presence (presenceLabel) derivee de chatUsersProvider, en vert si en ligne
- Bulles _MessageBubble: alignement gauche/droite selon l expediteur, couleurs primaryContainer/surfaceContainerHighest, largeur max 75% de l ecran, nom de l expediteur affiche uniquement dans le salon general pour les messages des autres, 'Message supprime' en italique, heure HH:mm, suffixe '(modifie)', et coche simple/double (done / done_all) uniquement sur SES messages en DM
- Zone de saisie en SafeArea: TextField (textInputAction.send, onSubmitted) + IconButton.filled d envoi
- Auto-scroll anime vers le bas apres chargement et a chaque nouveau message
- Heartbeat de presence: ping toutes les 20 s emis par ChatSocketService tant que la socket est ouverte

**Manques constates** (9)

- La route /chats/room/:room ignore state.pathParameters['room']: le builder est const ChatConversationScreen() -> seul le salon general est atteignable, tout autre nom de salon afficherait quand meme 'General'
- Pas de selecteur de produit a joindre au message (le web a productPickerOpen / handlePickProduct avec recherche produit)
- Pas de suggestions rapides (quickSuggestions du web)
- Pas de confirmation avant suppression d un message
- Pas d indicateur d etat de la socket chat dans l UI (connectionStatus est ecoute uniquement pour declencher markRead)
- Pas de gestion de la pagination de l historique (tout est charge d un coup)
- Pas de saisie multi-lignes, pas d envoi de piece jointe/image
- Aucun etat vide dedie quand la conversation ne contient aucun message
- Le stream _socket.incoming.listen(_handleIncoming) n est pas conserve dans une StreamSubscription annulee explicitement (seul _statusSub l est); disposeService() ferme les controllers, ce qui limite l impact

#### `smartcross/lib/features/notifications/notifications_screen.dart`

- **Route** : /notifications (ShellRoute, const NotificationsScreen()); egalement atteignable via l icone cloche de la TopBar (context.push('/notifications'))
- **Role** : Tous les roles (NavItem sans restriction)

**Implemente** (9)

- Scaffold + AppBar 'Notifications'
- RefreshIndicator -> notificationsProvider.notifier.refresh()
- switch AsyncValue complet: EmptyState('Aucune notification.', icone notifications_none), ErrorState(messageFromError + Reessayer), LoadingState
- ListView de Card _NotificationTile; la carte non lue est teintee (primaryContainer alpha 0.25) et son titre est en gras
- Icone + couleur selon le type derive du texte: camion bleu pour NotifType.commandePrete, recu orange sinon
- Sous-titre: date formatee dd/MM/yyyy HH:mm
- Tap: marque la notification lue (markRead optimiste dans NotificationsNotifier: mise a jour locale immediate puis PATCH users/notifications/<id>/, avec refresh en cas d echec)
- Temps reel: NotificationsNotifier.build() fait ref.watch(realtimeTickProvider), donc la liste se recharge a chaque message pousse par ws/notifications/
- unreadNotificationsCountProvider derive le compteur affiche en Badge sur la TopBar

**Manques constates** (9)

- Deep-link mort: le tap fait context.push('/orders/${notification.orderId}') mais AppNotification.fromJson force orderId: null (commentaire assume: le backend n expose pas de FK order). Le champ orderNumero est extrait par regex CMD-\S+ mais n est ni affiche ni utilise pour naviguer -> le tap ne mene jamais a la commande.
- Pas de bouton 'Marquer tout lu' dans l UI alors que NotificationsRepository.markAllRead() (POST users/notifications/mark-all-read/) existe deja et n est appele nulle part
- Pas de suppression d une notification ni de 'Supprimer tout' (le web a Trash2 par ligne + bouton destructif 'Supprimer tout' -> notifications.delete / deleteAll); aucune methode delete dans le repository
- Pas de bascule lu -> non lu (le web fait markRead(id, !is_read)); ici le marquage est a sens unique
- Pas de badge de type ni de badge 'Nouveau' sur la ligne (le web affiche typeLabel + badge Nouveau)
- Pas de metadonnees contextuelles (produit, vente, utilisateur, magasin) affichees sous le message comme cote web
- Pas de badge d etat du WebSocket sur cet ecran (present cote web: Temps reel / Connexion... / Deconnecte)
- Pas de bouton 'Actualiser' explicite (seulement le pull-to-refresh, invisible sur desktop)
- Aucune notification systeme/locale: flutter_local_notifications est declare dans pubspec.yaml mais n est importe nulle part dans lib/

#### `smartcross/lib/widgets/kpi_card.dart`

- **Route** : aucune
- **Role** : Widget partage sans logique de role

**Implemente** (3)

- KpiCard: Card + Padding 14, label (bodySmall, onSurfaceVariant, 2 lignes max, ellipsis), icone optionnelle dans un carre arrondi teinte a 12% de accentColor (defaut colorScheme.primary), valeur en titleLarge w700 dans un FittedBox scaleDown pour ne jamais deborder, sous-titre optionnel (11px, 1 ligne, ellipsis)
- KpiGrid: GridView.builder shrinkWrap + NeverScrollableScrollPhysics, nombre de colonnes responsive calcule sur MediaQuery.sizeOf(context).width — 5 colonnes >=1200, 4 >=900, 3 >=600, 2 sinon; espacement 12 et mainAxisExtent fixe a 128
- Actuellement consomme par dashboard_screen.dart (bloc KPI et bloc Stock rapide)

**Manques constates** (4)

- Pas de variante cliquable (onTap) pour naviguer vers un ecran de detail
- Pas d etat de chargement/skeleton dedie
- Pas d indicateur de tendance (fleche haut/bas, delta vs periode precedente) alors que le web affiche ArrowUp/ArrowDown
- mainAxisExtent fige a 128 px: un contenu plus long (label 2 lignes + valeur + sous-titre) n a pas de marge de manoeuvre

#### `smartcross/lib/widgets/async_state_widgets.dart`

- **Route** : aucune
- **Role** : Widget partage sans logique de role

**Implemente** (4)

- LoadingState: Center + CircularProgressIndicator
- ErrorState: icone error_outline en colorScheme.error (36px), message centre, et OutlinedButton 'Reessayer' affiche seulement si onRetry != null
- EmptyState: icone parametrable (defaut inbox_outlined) en colorScheme.outline, message centre en onSurfaceVariant
- Reutilises dans dashboard_screen, users_screen, notifications_screen, chat_list_screen et les autres modules (orders, catalog, etc.)

**Manques constates** (3)

- Pas de skeleton/shimmer (le frontend web utilise systematiquement des Skeleton pour les listes et cartes)
- EmptyState n accepte pas d action (bouton 'Creer', 'Ajouter') ni de titre + description separes
- Pas de variante compacte pour un affichage en ligne dans une Card

**Infrastructure reutilisable** (22)

- ROUTER — /home/garrix/Dev/Smartphone/smartcross/lib/core/router.dart: routerProvider (Provider<GoRouter>), initialLocation '/splash', refreshListenable = _RouterRefresh qui notifie a chaque changement de authProvider.status. Routes publiques: /splash, /server-setup, /login. Toutes les autres sont dans un ShellRoute unique dont le builder enveloppe l enfant dans NavigationShell(currentPath: state.matchedLocation).
- ROUTER — liste complete des routes du shell: /dashboard, /caisse, /orders (+ /orders/new, /orders/:id), /depot, /tournee, /bilan, /catalog, /suppliers (+ /suppliers/new, /suppliers/:id), /users, /stores, /transfers, /chats (+ /chats/room/:room, /chats/dm/:id), /notifications, /settings.
- ROUTER — GARDES: le redirect ne gere QUE l etat d authentification (loading -> /splash, unauthenticated -> /login sauf pages publiques, authenticated sur une page publique -> _homeFor(role)). _homeFor: gerant -> /dashboard, preparateur -> /depot, livreur -> /tournee, unknown/null -> /login. IL N EXISTE AUCUN GARDE PAR ROLE SUR LES ROUTES: le filtrage par role est uniquement visuel (masquage des entrees de menu). Un livreur qui tape /users ou /dashboard obtient l ecran.
- NAVIGATION — /home/garrix/Dev/Smartphone/smartcross/lib/core/nav_items.dart: modele NavItem(path, label, icon, roles?) avec visibleFor(role); kPrimaryNavItems declare 14 entrees. Gerant: Tableau de bord, Commandes, Caisse, Produits, Fournisseurs, Magasins, Transferts, Utilisateurs. Preparateur: Depot. Livreur: Tournee, Bilan du jour. Tous roles: Discussions, Notifications, Parametres.
- SHELL — /home/garrix/Dev/Smartphone/smartcross/lib/widgets/navigation_shell.dart: bascule automatique sidebar permanente 240 px (largeur >= kDesktopBreakpoint = 900) vs Drawer mobile, items filtres par role, tuile selectionnee via currentPath.startsWith(item.path), navigation avec context.go().
- TOPBAR — /home/garrix/Dev/Smartphone/smartcross/lib/widgets/topbar.dart (PreferredSizeWidget, 64 px): logo + 'Smartphone.Mg', pastille verte/orange d etat du WebSocket (wsConnectionStatusProvider) avec Tooltip, icone cloche avec material.Badge du nombre de non-lues (unreadNotificationsCountProvider) qui push /notifications, et PopupMenuButton compte affichant nom/email/role + action Deconnexion (logout puis context.go('/login')).
- THEME — /home/garrix/Dev/Smartphone/smartcross/lib/core/theme.dart: buildLightTheme()/buildDarkTheme() Material 3 a partir de kSeedColor = 0xFF2563EB, scaffoldBackgroundColor = scheme.surface, AppBar plat sans surfaceTint, CardThemeData elevation 0 + bord outlineVariant + rayon 14, InputDecorationTheme rempli (surfaceContainerHighest 30%) + rayon 10. main.dart applique themeMode: ThemeMode.system (aucun selecteur clair/sombre dans l app). Egalement exportes: kChartPalette (8 couleurs, JAMAIS utilisee) et statusColor(context, apiStatus) pour les 7 statuts de commande.
- AUTH — /home/garrix/Dev/Smartphone/smartcross/lib/state/auth_provider.dart: AuthState(status: loading|unauthenticated|authenticated, user: AppUser?), AuthNotifier avec _bootstrap() (ensureInitialized, lecture du token, GET users/me/), login(email, password) puis me(), logout(), refreshUser(). _invalidateDataProviders(ref) invalide 20 providers metier a chaque login/logout pour eviter le cache d un compte precedent. authEventProvider relaie AuthEvents.instance.stream: un 401 non rafraichissable force l etat unauthenticated.
- AUTH/STOCKAGE — /home/garrix/Dev/Smartphone/smartcross/lib/core/secure_storage.dart: TokenStorage singleton sur FlutterSecureStorage (cles 'access_token' / 'refresh_token', save/saveAccess/clear); AppPrefs singleton sur SharedPreferences pour l URL serveur configurable (cle 'server_base_url'). logout() efface uniquement les tokens locaux, aucun appel serveur de blacklist.
- HTTP — /home/garrix/Dev/Smartphone/smartcross/lib/core/api_client.dart: ApiClient singleton sur Dio, baseUrl '<serveur>/api/', timeouts 20s/30s, interceptor onRequest qui injecte 'Authorization: Bearer <access>', interceptor onError qui sur 401 tente POST users/refresh/ une seule fois (flag extra['retried']) et rejoue la requete, sinon emet AuthEvent(sessionExpired). kDefaultServerUrl adapte a la plateforme (10.0.2.2:8010 sur Android, 127.0.0.1:8010 ailleurs). wsBaseUrl derive http->ws / https->wss. Deux helpers statiques tres reutilises: isConnectivityError(error) et messageFromError(error) (lit error/detail/message, aplatit les erreurs de validation DRF, message dedie hors-ligne).
- PROVIDERS RIVERPOD — 12 fichiers dans lib/state/: auth_provider, users_provider (accountsProvider, pendingUsersProvider, usersRepositoryProvider), company_provider (passwordResetRequestsProvider avec filtre de statut interne), notifications_provider (notificationsProvider + unreadNotificationsCountProvider), dashboard_provider (dashboardFilterProvider NotifierProvider + dashboardProvider), catalog_provider (categoriesProvider, typesProvider, brandsProvider, colorsProvider, referencesProvider, referenceAutocompleteProvider famille autoDispose), orders_provider, stock_provider, stores_provider, suppliers_provider, caisse_provider, realtime_provider. Motif constant: un Provider de repository + un AsyncNotifierProvider avec build() / refresh() (state = AsyncLoading puis AsyncValue.guard) / methodes d ecriture qui refetchent.
- REPOSITORIES — 12 fichiers dans lib/data/repositories/, tous batis sur `Dio get _dio => ApiClient.instance.dio` et des chemins relatifs a /api/. Dans le perimetre audite: UsersRepository (users/magasins/users/, users/register/, users/employers/<id>/commande-role/, users/delete/<id>/, users/pending/, users/approve/<id>/, users/reject/<id>/), NotificationsRepository (users/notifications/, PATCH <id>/, POST mark-all-read/), DashboardRepository (orders/dashboard/ avec date_debut/date_fin), ChatRepository (users/chat/users/, users/chat/history/), CompanyRepository (users/password-reset-requests/ + PATCH <id>/ {action}), AuthRepository (users/login/, users/me/ GET+PATCH+multipart photo, users/change-password/), CatalogRepository (CRUD categories/types/brands/colors/references/variants + autocomplete + bulk price).
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/core/ws_manager.dart: classe abstraite WsManager (connexion WebSocketChannel, buildUri rappele a chaque tentative pour un token frais, reconnexion automatique apres 3 s, decodage JSON, hooks onMessage/onStatusChange, send/disconnect).
- TEMPS REEL — notifications_socket_service.dart: NotificationsSocketService singleton (ws/notifications/?token=...), streams incoming et connectionStatus. realtime_provider.dart: RealtimeBootstrap instancie une seule fois dans main.dart (ref.watch(realtimeBootstrapProvider)), (dé)connecte la socket selon authProvider.status, et incremente realtimeTickProvider a chaque message. Les providers dashboardProvider et notificationsProvider font ref.watch(realtimeTickProvider) et se rafraichissent donc automatiquement. wsConnectionStatusProvider (StreamProvider<bool>) alimente la pastille de la TopBar.
- TEMPS REEL — chat_socket_service.dart: ChatSocketService NON singleton (une instance par ecran de conversation), connectToConversation({recipientId}) -> ws/chat/?token=...&recipient_id=..., actions emises: send / edit / delete / read / ping; heartbeat de presence toutes les 20 s tant que la socket est ouverte; disposeService() ferme socket et controllers. La presence des collegues n est PAS poussee: elle est recalculee par GET users/chat/users/ et l app la sonde toutes les 20 s.
- WIDGETS PARTAGES REUTILISABLES — lib/widgets/: async_state_widgets.dart (LoadingState / ErrorState(message,onRetry) / EmptyState(message,icon)), kpi_card.dart (KpiCard + KpiGrid responsive), status_badge.dart (StatusChip generique, OrderStatusBadge branche sur statusColor, StockLevelBadge Rupture/Stock bas/OK), navigation_shell.dart, topbar.dart, assign_staff_dialog.dart (showAssignStaffDialog: selection manuelle du preparateur/livreur + heure d affectation, renvoie AssignResult), order_confirm_dialog.dart, order_historique_view.dart.
- MODELES — lib/models/ avec json_utils.dart (asInt/asIntOrNull/asString/asStringOrNull/asBool/asDouble/asDoubleOrNull/asDateOrNull) utilise par toutes les factories fromJson. Dans le perimetre: user.dart (AppUser avec role Commande derive de role_commande||commande_role, rawRole Django, isCompanyOwner, lastLoginAt/lastLogoutAt, magasinId, shopName; PendingUser), chat.dart (ChatUser avec isOnline/lastSeenAt, ChatMessage avec isEdited/isDeleted/readAt + copyWith), app_notification.dart (AppNotification, NotifType derive du TEXTE du message car le backend n a qu un notif_type='order', orderId toujours null), dashboard.dart (DashboardData/DashboardKpis/DashboardFinance/TopEntry/StockRapide), company.dart (PasswordResetRequest).
- CONSTANTES — /home/garrix/Dev/Smartphone/smartcross/lib/core/constants.dart: enums + extensions fromApi/apiValue/label pour UserRole (gerant/preparateur/livreur/unknown), OrderStatus (7 valeurs), PaymentMode, StockMovementType, SupplierOrderStatus; kDesktopBreakpoint = 900; helper dialogWidth(available, desired).
- FUSEAU HORAIRE — /home/garrix/Dev/Smartphone/smartcross/lib/core/app_time.dart: kAppUtcOffset = UTC+3 (Indian/Antananarivo), appNow/appLocal/appDay/appToday/appWallClockToUtc/appDayBounds. A REUTILISER pour tout nouvel ecran manipulant des dates metier — a noter que dashboard_provider.dart utilise DateTime.now() local et non appToday() pour resoudre ses periodes.
- AUTH SCREENS EXISTANTS — lib/features/auth/: splash_screen.dart (logo + spinner pendant _bootstrap), login_screen.dart, server_setup_screen.dart (configuration de l URL du serveur, persistee via AppPrefs).
- DEPENDANCES DECLAREES MAIS INUTILISEES dans lib/: fl_chart (aucun graphique nulle part), flutter_local_notifications (aucune notification systeme), connectivity_plus, path_provider, printing. Utilisees: dio, go_router, flutter_riverpod, web_socket_channel, flutter_secure_storage, shared_preferences, intl, collection, image_picker (settings/catalog/order_confirm), url_launcher (tournee/depot/order_detail), share_plus + file_picker (catalog), pdf (stock_repository).
- QUALITE — `flutter analyze` passe sans erreur ni warning: 59 issues toutes de niveau info (use_null_aware_elements, curly_braces_in_flow_control_structures, deprecated_member_use sur DropdownButtonFormField.value / Radio.groupValue, use_key_in_widget_constructors).

**Notes**

Perimetre lu integralement: users_screen.dart (884 l.), settings_screen.dart (1043 l.), chat_list_screen.dart (154 l.), chat_conversation_screen.dart (300 l.), notifications_screen.dart (70 l.), dashboard_screen.dart (264 l.), kpi_card.dart, async_state_widgets.dart, plus tous les providers (auth, users, company, notifications, dashboard, catalog, realtime), repositories (users, notifications, dashboard, chat, company, auth, caisse) et modeles associes, ainsi que router.dart, nav_items.dart, main.dart, theme.dart, api_client.dart, secure_storage.dart, ws_manager.dart, chat_socket_service.dart, notifications_socket_service.dart, constants.dart, app_time.dart, navigation_shell.dart, topbar.dart, status_badge.dart.

Comparaison faite avec le frontend Next.js: app/(app)/users/page.tsx (770 l.), settings/page.tsx (657 l.), chats/page.tsx (1070 l.), notifications/page.tsx (235 l.), dashboard/page.tsx (656 l.).

NIVEAU DE COMPLETUDE GLOBAL DU PERIMETRE (evaluation factuelle):
- users_screen: ~65% — structure a 3 onglets complete et conforme, mais 3 defauts de code reels (double dialog de suppression avec cast String->bool, edition de profil non envoyee au serveur, SegmentedButton fige) et pas de recherche ni d agregation multi-magasin.
- settings_screen: ~55% par rapport au web — profil + mot de passe complets et conformes, mais les deux onglets metiers du web (Zones de livraison, Categories de depenses) et l edition entreprise/magasin+logo sont totalement absents; en revanche il apporte un CRUD Marques/Sous-types/Couleurs que le web n a pas dans Parametres.
- chats (2 ecrans): ~75% — coeur temps reel complet (envoi/edition/suppression via socket, accuses de lecture, presence, heartbeat), manquent recherche, non-lus, selecteur de produit, suggestions rapides, et la route room/:room ignore son parametre.
- notifications_screen: ~40% — lecture + marquage lu optimiste + temps reel OK, mais aucune des actions de masse/suppression du web, et le deep-link vers la commande est du code mort (orderId toujours null).
- dashboard_screen: ~60% des donnees, ~20% de la richesse visuelle — tous les blocs de donnees de orders/dashboard/ sont rendus, mais zero graphique malgre fl_chart en dependance, le preset 'Personnalise' n a pas de date picker, et le layout etroit des TOP produits utilise un Expanded dans une Column non bornee (assertion Flutter probable).
- kpi_card / async_state_widgets: complets pour leur perimetre actuel, tres reutilisables tels quels pour de nouveaux ecrans.

POINTS D INFRASTRUCTURE LES PLUS REUTILISABLES POUR PORTER DE NOUVEAUX ECRANS: le motif Repository (Dio + ApiClient.instance) + AsyncNotifierProvider avec refresh(), les trois widgets d etat (LoadingState/ErrorState/EmptyState), KpiGrid/KpiCard, StatusChip/OrderStatusBadge/StockLevelBadge, ApiClient.messageFromError, realtimeTickProvider pour le rafraichissement automatique, WsManager pour toute nouvelle socket, app_time.dart pour les dates metier, et NavItem+kPrimaryNavItems pour declarer une nouvelle entree de menu par role.

MANQUE TRANSVERSAL LE PLUS IMPORTANT: aucun garde de route par role dans go_router — le filtrage par role n existe que dans le menu.

### Groupe `data`

#### `smartcross/lib/data/repositories/auth_repository.dart`

- **Route** : aucune (couche data, consommee par state/auth_provider.dart et features/settings/settings_screen.dart)
- **Role** : tous roles (login/profil)

**Implemente** (7)

- login(email, password) -> POST users/login/ ; parse access/refresh/role/full_name et ecrit les 2 tokens dans TokenStorage (flutter_secure_storage)
- logout() -> efface simplement les tokens localement (AUCUN appel serveur)
- me() -> GET users/me/ -> AppUser
- updateProfile({fullName, phone, adresse}) -> PATCH users/me/ (champs envoyes seulement s'ils sont non null)
- uploadProfilePhoto(filePath) -> PATCH users/me/ en multipart FormData champ 'photo'
- changePassword({oldPassword, newPassword}) -> POST users/change-password/
- classe LoginResult (access, refresh, role, fullName)

**Manques constates** (4)

- pas d'inscription (POST users/register/ est appele depuis users_repository et stores_repository, jamais pour un self-signup)
- pas de mot de passe oublie / reset (le frontend Next.js a users/public/forgot-password/, /confirm/ et /status/ + les pages app/forgot-password, app/reset-password, app/verify-email)
- pas d'appel users/logout-event/ (present cote frontend Next.js) : la deconnexion n'est pas tracee serveur
- pas de gestion explicite de l'expiration du refresh token ici (deleguee a ApiClient)

#### `smartcross/lib/data/repositories/orders_repository.dart`

- **Route** : aucune (consommee par state/orders_provider.dart, widgets/order_historique_view.dart)
- **Role** : gerant / preparateur / livreur (le serveur filtre la vue selon le role)

**Implemente** (12)

- list({statut, dateDebut, dateFin, preparateurId, historique, dateFrom, dateTo}) -> GET orders/ avec query params (dates jour en YYYY-MM-DD, dateFrom/dateTo en ISO UTC)
- detail(id) -> GET orders/{id}/
- create({clientNom, telephone, livraisonZone, items, notePreparateur, noteLivreur, adresseLivraison, modePaiement, dateCommande}) -> POST orders/
- changeStatus(id, statut, {note, preparateurId, livreurId, assignedAt, photoPath}) -> POST orders/{id}/status/ ; bascule automatiquement en multipart FormData quand photoPath est fourni (preuve de preparation)
- cancel(id, {note}) -> POST orders/{id}/cancel/
- update(id, {clientNom, telephone, livraisonZone, adresseLivraison, modePaiement, dateCommande, notePreparateur, noteLivreur, items}) -> PATCH orders/{id}/
- delete(id) -> DELETE orders/{id}/
- availableStaff(role, {dateCommande}) -> GET orders/available-staff/ -> List<StaffOption>
- assignLivreur(id, livreurId) -> POST orders/{id}/assign-livreur/ (pre-assignation sans changer le statut)
- assignPreparateur(id, preparateurId) -> POST orders/{id}/assign-preparateur/
- deliveryZones() -> GET orders/delivery-zones/ (lecture seule)
- classe StaffOption (id, fullName, available)

**Manques constates** (3)

- zones de livraison en LECTURE SEULE : pas de POST/PATCH/DELETE sur orders/delivery-zones/{id}/ alors que le frontend Next.js fait le CRUD complet dans Parametres
- pas de pagination ni de recherche texte cote serveur (tout est charge d'un coup puis filtre client)
- pas d'export/impression de bon de commande cote repository

#### `smartcross/lib/data/repositories/catalog_repository.dart`

- **Route** : aucune (consommee par state/catalog_provider.dart, features/catalog, features/settings)
- **Role** : gerant (ecriture), tous (lecture)

**Implemente** (13)

- categories() / createCategory(nom, ordre) / updateCategory(id, nom) / deleteCategory(id)
- types({categoryId}) / createType(categoryId, nom) / updateType(id, nom) / deleteType(id)
- brands() / createBrand / updateBrand / deleteBrand
- colors() / createColor / updateColor / deleteColor
- references({typeId, brandId, categoryId}) -> GET catalog/references/ (variantes imbriquees)
- createReference({typeId, brandId, referenceName, prixAchat, prixVente}) (actif force a true)
- updateReference(id, {referenceName, prixAchat, prixVente, actif}) / deleteReference(id)
- uploadReferencePhoto(id, filePath) -> PATCH multipart champ 'photo'
- autocomplete(query, {typeId, brandId, categoryId}) -> GET catalog/references/autocomplete/ -> List<ReferenceOption> (avec couleurs + variant_id + stock)
- variants({referenceId}) / createVariant({productReferenceId, couleur, seuilAlerte, stockActuel}) / deleteVariant(id)
- bulkUpdatePrice(typeId, {prixAchat, prixVente}) -> POST catalog/references/bulk-update-price/ -> nb references modifiees
- exportExcelBytes() -> GET catalog/references/export-excel/ en ResponseType.bytes
- importExcel(bytes, filename) -> POST multipart catalog/references/import-excel/, reponse en bytes + parsing des entetes X-Import-* et du content-disposition -> ExcelImportResult(bytes, filename, createdReferences, updatedReferences, createdVariants, updatedVariants, errorsCount, skippedCount)

**Manques constates** (4)

- pas de PATCH sur une variante (impossible de modifier couleur/seuil_alerte apres creation ; seuls create/delete existent) alors que le frontend appelle catalog/variants/{id}/
- pas d'annulation d'un lot d'import : catalog/import-batches/{id}/cancel/ existe cote Next.js, absent ici
- createVariant envoie stock_actuel que le backend ignore (commentaire assume dans le code)
- pas d'upload/galerie multi-images produit (le frontend a product-image-gallery + image-upload), une seule photo par reference ici

#### `smartcross/lib/data/repositories/stock_repository.dart`

- **Route** : aucune (consommee par state/stock_provider.dart et features/catalog/catalog_screen.dart)
- **Role** : gerant

**Implemente** (4)

- movements({variantId}) -> GET catalog/movements/ -> List<StockMovement>
- adjust({productVariantId, type ENTREE|SORTIE, quantite, note}) -> POST catalog/variants/{id}/adjust/
- ruptures() : PAS d'endpoint serveur — derive la liste cote client depuis GET catalog/references/ en parcourant les variantes is_rupture/is_stock_bas, puis tri (ruptures d'abord, puis marque, puis reference)
- ruptureExportPdfBytes() : genere un PDF cote client avec package pdf (Header + TableHelper : Statut, Marque, Reference, Couleur, Sous-type, Stock, Seuil, A commander)

**Manques constates** (3)

- ruptures() recharge TOUT le catalogue a chaque appel (aucune pagination/cache), et le filtre magasin n'est pas passe
- pas de filtre par type de mouvement / date / origine sur movements()
- pas d'export Excel/CSV des mouvements

#### `smartcross/lib/data/repositories/suppliers_repository.dart`

- **Route** : aucune (consommee par state/suppliers_provider.dart, features/suppliers/*)
- **Role** : gerant

**Implemente** (4)

- list() -> GET suppliers/orders/
- detail(id) -> GET suppliers/orders/{id}/
- create({description, prixFournisseur, fretImport, douane, metaAds, lines}) -> POST suppliers/orders/
- receive(id) -> POST suppliers/orders/{id}/receive/ (declenche l'entree stock serveur)

**Manques constates** (3)

- pas de PATCH ni DELETE d'une commande fournisseur (impossible de corriger ou supprimer un brouillon)
- pas de gestion d'un referentiel Fournisseurs (nom, contact) : seules les commandes existent
- pas de filtre par statut/date sur list()

#### `smartcross/lib/data/repositories/users_repository.dart`

- **Route** : aucune (consommee par state/users_provider.dart, features/users/users_screen.dart)
- **Role** : gerant

**Implemente** (7)

- list() -> GET users/magasins/users/ puis extrait `employers` du PREMIER magasin uniquement -> List<AppUser>
- create({fullName, email, password, adminEmail, commandeRole PREPARATEUR|LIVREUR, phone}) -> POST users/register/ avec role=employer, position derivee du commandeRole
- updateCommandeRole(userId, commandeRole) -> PUT users/employers/{id}/commande-role/
- delete(userId, password) -> DELETE users/delete/{id}/ avec mot de passe du gerant dans le body
- pending() -> GET users/pending/ -> List<PendingUser>
- approve(userId) -> PUT users/approve/{id}/
- reject(userId) -> POST users/reject/{id}/

**Manques constates** (4)

- list() ne lit que magasins.first : un admin multi-magasins ne voit les employes que du premier magasin
- pas de modification de profil d'un employe (nom, email, telephone) ni de reinitialisation de son mot de passe par le gerant
- pas d'appel users/role/{id}/ (changement de role Django) present cote frontend Next.js
- pas de desactivation/reactivation de compte (seulement suppression definitive)

#### `smartcross/lib/data/repositories/stores_repository.dart`

- **Route** : aucune (consommee par state/stores_provider.dart, features/stores + features/transfers)
- **Role** : gerant/admin proprietaire

**Implemente** (7)

- list() -> GET users/magasins/users/ puis tente GET users/magasins/stats/ et fusionne les stats par magasin_id (try/catch : en cas d'echec renvoie les magasins sans stats)
- create({shopName, managerFullName, managerEmail, managerPassword}) -> POST users/register/ role=magasin, puis auto-approbation PUT users/approve/{id}/
- rename(magasinId, shopName) -> PATCH users/magasins/{id}/
- delete(magasinId, password) -> DELETE users/magasins/{id}/ avec mot de passe dans le body
- catalogFor(magasinId) -> GET catalog/references/?magasin_id= (pour le selecteur produit du transfert)
- transfer({sourceMagasinId, destinationMagasinId, items}) -> POST users/transfer/products/ avec [{variant_id, quantity}]
- classes TransferItem et helper asIntKey

**Manques constates** (3)

- pas d'appel users/magasins/overview/ (utilise par le frontend Next.js pour la vue consolidee)
- pas d'upload/modification du logo magasin (shop_logo est lu dans le modele mais jamais ecrit)
- pas d'historique des transferts (seulement l'envoi, aucune lecture des transferts passes)

#### `smartcross/lib/data/repositories/caisse_repository.dart`

- **Route** : aucune (consommee par state/caisse_provider.dart, features/caisse/caisse_screen.dart)
- **Role** : gerant

**Implemente** (5)

- current(magasinId) -> GET users/caisse/sessions/current/ (gere 204/null -> retourne null)
- history(magasinId) -> GET users/caisse/sessions/
- open({magasinId, openingBalance, openingNote}) -> POST users/caisse/sessions/open/
- close(sessionId, {closingBalance, closingNote}) -> POST users/caisse/sessions/{id}/close/
- addMovement({sessionId, movementType in|out, amount, reason}) -> POST users/caisse/movements/

**Manques constates** (4)

- pas de categories de mouvement de caisse (users/caisse/categories/ CRUD present cote Next.js)
- pas de users/caisse/summary/ (recap chiffre) ni de liste paginee des mouvements users/caisse/movements/?...
- pas d'edition ni de suppression d'un mouvement (PATCH/DELETE users/caisse/movements/{id}/ cote Next.js)
- pas de rapprochement avec les commandes livrees (aucun lien caisse <-> orders)

#### `smartcross/lib/data/repositories/dashboard_repository.dart`

- **Route** : aucune (consommee par state/dashboard_provider.dart, features/dashboard/dashboard_screen.dart)
- **Role** : gerant

**Implemente** (1)

- fetch({dateDebut, dateFin}) -> GET orders/dashboard/ avec date_debut/date_fin formattees YYYY-MM-DD -> DashboardData

**Manques constates** (3)

- 19 lignes : une seule methode, aucun autre endpoint statistique
- pas d'appel a users/dashboard/ (endpoint distinct utilise par le frontend Next.js)
- pas d'export du dashboard (PDF/Excel), pas de comparaison de periodes

#### `smartcross/lib/data/repositories/notifications_repository.dart`

- **Route** : aucune (consommee par state/notifications_provider.dart)
- **Role** : tous

**Implemente** (3)

- list() -> GET users/notifications/
- markRead(id) -> PATCH users/notifications/{id}/ {is_read:true}
- markAllRead() -> POST users/notifications/mark-all-read/

**Manques constates** (3)

- markAllRead() N'EST EXPOSE PAR AUCUN PROVIDER ni ecran : code mort en pratique
- pas de suppression : users/notifications/{id}/ DELETE, bulk-delete/, delete-all/ et bulk-read/ existent cote Next.js, absents ici
- pas de pagination / filtre lu-non lu cote serveur

#### `smartcross/lib/data/repositories/chat_repository.dart`

- **Route** : aucune (consommee par features/chats/chat_list_screen.dart qui declare lui-meme `chatRepositoryProvider`)
- **Role** : tous

**Implemente** (2)

- users() -> GET users/chat/users/ -> List<ChatUser> (avec is_online recalcule serveur a chaque appel)
- history({recipientId, roomName='general'}) -> GET users/chat/history/ (recipient_id OU room_name, exclusifs)

**Manques constates** (4)

- AUCUN provider Riverpod dedie dans lib/state/ (le seul provider chat est declare dans l'ecran chat_list_screen.dart) : incoherent avec le reste de l'architecture
- envoi/edition/suppression de message uniquement via WebSocket (chat_socket_service) : aucun repli REST si la socket est coupee
- pas de pagination de l'historique, pas de compteur de messages non lus par conversation
- pas d'envoi de piece jointe/image

#### `smartcross/lib/data/repositories/company_repository.dart`

- **Route** : aucune (consommee par state/company_provider.dart -> features/users/users_screen.dart onglet reinit. mots de passe)
- **Role** : admin / gerant

**Implemente** (2)

- passwordResetRequests({status}) -> GET users/password-reset-requests/ (le filtre 'all' est traduit en absence de parametre)
- resolvePasswordReset(id, action) -> PATCH users/password-reset-requests/{id}/ {action}

**Manques constates** (2)

- 20 lignes : ne couvre que les demandes de reinitialisation ; rien de l'abonnement, des appareils, du backup (users/backup/export|import/) ni du module Super Admin du frontend Next.js
- aucune creation de demande cote app (l'utilisateur qui a oublie son mot de passe ne peut pas en faire la demande depuis mobile)

#### `smartcross/lib/models/order.dart`

- **Route** : aucune
- **Role** : gerant / preparateur / livreur

**Implemente** (5)

- OrderItem : id, productVariantId, referenceName, couleur, prixUnitaire (nullable selon role), quantite, brandName, typeName, categoryName
- OrderStatusHistoryEntry : ancienStatut, nouveauStatut (enum OrderStatus), changedByName, note, photo (preuve de preparation), timestamp
- Order : id, numero, dateCommande, clientNom, telephone, livraisonZone (code), adresseLivraison, modePaiement (enum PaymentMode), fraisLivraison, totalAPayer, notePreparateur, noteLivreur, statutCourant, items, statusHistory, createdAt, preparateurId/Name, livreurId/Name
- OrderItemDraft (product_variant + quantite) pour la creation/modification
- tous les champs financiers laisses nullable pour absorber les serializers restreints par role

**Manques constates** (3)

- aucun toJson() sur Order (la serialisation est faite a la main dans le repository)
- pas de champ pour un eventuel motif de retour/annulation structure (seulement la note libre de l'historique)
- modele unique pour 3 vues de roles differentes : rien n'indique quels champs sont reellement remplis pour le role courant

#### `smartcross/lib/models/catalog.dart`

- **Route** : aucune
- **Role** : gerant (catalogue)

**Implemente** (7)

- ProductCategory (id, nom, ordre) + toJson
- ProductType (id, categoryId, nom) + toJson
- Brand (id, nom) + toJson
- ProductColor (id, nom) + toJson
- ProductVariant (id, productReferenceId, referenceName, brandName, prixVente, couleur, stockActuel, seuilAlerte, isRupture, isStockBas) + getter label
- ProductReference (id, typeId/typeName, categoryName, brandId/brandName, referenceName, prixAchat, prixVente, photo, actif, variants[]) + getter margeUnitaire + toJson
- ReferenceOption + ColorOption (resultat autocomplete avec variant_id/couleur/stock_actuel)

**Manques constates** (3)

- pas de champ code-barres/SKU/QR (le frontend Next.js a lib/qrcode-generator.ts)
- une seule photo (String?) par reference, pas de galerie
- ProductVariant n'expose pas de prix specifique a la variante ni de date de derniere entree

#### `smartcross/lib/models/user.dart`

- **Route** : aucune
- **Role** : tous

**Implemente** (2)

- AppUser : id, fullName, email, role (enum UserRole derive de role_commande OU commande_role), isActive (depuis is_confirmed), phone, adresse, photo, createdAt, lastLoginAt, lastLogoutAt, magasinId, shopName, rawRole (admin/magasin/employer), isCompanyOwner
- PendingUser : id, fullName, email, role, position, createdAt

**Manques constates** (2)

- pas de toJson (les mises a jour de profil sont ecrites champ par champ dans le repository)
- isCompanyOwner et rawRole sont parses mais peu exploites (aucun ecran Super Admin/abonnement dans l'app)

#### `smartcross/lib/models/dashboard.dart`

- **Route** : aucune
- **Role** : gerant

**Implemente** (4)

- DashboardKpis (nbVentes, caPeriode, caMoisEnCours, tauxLivraisonReussiePct, nbRetours)
- DashboardFinance (caProduitsVendus, fraisLivraisonEncaisses, totalInvestiFournisseurs, totalPubMetaAds, beneficeEstime)
- TopEntry (label, quantiteVendue) et StockRapide (totalEnStock, ruptures, stockBas)
- DashboardData : periode (dateDebut/dateFin), kpis, suiviCommandesTempsReel (Map<String,int>), financiere, topParSousType/topMarques/topReferences/topCouleurs, stockRapide — parsing defensif avec fallback {} sur chaque sous-objet

**Manques constates** (2)

- aucune serie temporelle (pas d'evolution CA jour par jour) : impossible de tracer une courbe
- pas de comparaison periode precedente ni d'objectifs

#### `smartcross/lib/models/caisse.dart`

- **Route** : aucune
- **Role** : gerant

**Implemente** (2)

- CaisseMovement (id, session, movementType in|out, amount, reason, createdByName, createdAt) + getter isIn
- CaisseSession (id, magasinId, status, openedByName, closedByName, openingBalance, closingBalance, expectedBalance, difference, openingNote, closingNote, openedAt, closedAt, movements[]) + getters isOpen et soldeCourant (calcul local fond + entrees - sorties)

**Manques constates** (2)

- pas de categorie sur un mouvement (le backend/frontend Next.js ont users/caisse/categories/)
- pas de lien vers la commande a l'origine d'une entree d'espece

#### `smartcross/lib/models/chat.dart`

- **Route** : aucune
- **Role** : tous

**Implemente** (2)

- ChatUser (id, fullName, email, role Django brut, shopName, isOnline, lastSeenAt) avec commentaire explicite sur la presence recalculee cote serveur (fenetre 40s)
- ChatMessage (id, senderId, senderName, recipientId, recipientName, roomName, content, isEdited, isDeleted, timestamp, readAt) + copyWith(content, isEdited, isDeleted, readAt)

**Manques constates** (3)

- pas de piece jointe / image / reaction
- pas de compteur de non-lus par conversation dans le modele
- readAt uniquement pertinent en DM (le salon general n'a pas d'accuse de lecture)

#### `smartcross/lib/models/app_notification.dart`

- **Route** : aucune
- **Role** : tous

**Implemente** (3)

- AppNotification (id, notifType, message, orderId, orderNumero, isRead, createdAt) + copyWith(isRead)
- enum NotifType {nouvelleCommande, commandePrete, unknown} et NotifTypeX.fromApi qui devine le type en cherchant 'prete'/'nouvelle commande' DANS LE TEXTE du message (le backend ne renvoie qu'un notif_type='order')
- extraction du numero de commande par regex RegExp(r'CMD-\S+') sur le message

**Manques constates** (2)

- orderId est TOUJOURS null (mis en dur) : le deep-link vers une commande depuis une notification n'a que le numero, pas d'id -> navigation directe impossible
- typage par heuristique sur le texte francais : casse/accents/reformulation cote serveur cassent la detection

#### `smartcross/lib/models/delivery_zone.dart`

- **Route** : aucune
- **Role** : gerant (config) / tous (affichage)

**Implemente** (3)

- const kRecuperationCode = 'RECUPERATION' (retrait sur place : pas de livreur, pas de frais)
- DeliveryZoneOption (id, code, nom, prix, actif) + getter label 'nom (prix Ar)'
- DeliveryZoneCatalog : cache STATIQUE en memoire (static List zones) rempli par deliveryZonesProvider, avec byCode(code), labelFor(code), shortLabelFor(code), fraisFor(code) et repli sur le code brut si le cache est vide

**Manques constates** (2)

- cache statique global non reinitialise a la deconnexion : les zones du compte precedent restent en memoire apres un changement d'utilisateur (contrairement aux providers Riverpod qui, eux, sont invalides)
- aucune ecriture : la creation/modification de zone n'existe pas dans l'app

#### `smartcross/lib/models/stock.dart`

- **Route** : aucune
- **Role** : gerant

**Implemente** (2)

- StockMovement (id, productVariantId, variantLabel compose 'reference — couleur', type enum StockMovementType, quantite, origine, reference, note, userName, timestamp)
- RuptureItem (id, referenceName, brandName, typeName, categoryName, couleur, stockActuel, seuilAlerte, statut RUPTURE|STOCK_BAS) + getters isRupture et quantiteACommander = (seuil - stock).clamp(1, ...)

**Manques constates** (2)

- RuptureItem.fromJson existe mais n'est jamais utilise (les ruptures sont construites a la main depuis le catalogue dans StockRepository.ruptures)
- pas de valorisation (valeur du stock) ni de stock par magasin dans ces modeles

#### `smartcross/lib/models/supplier.dart`

- **Route** : aucune
- **Role** : gerant

**Implemente** (3)

- SupplierOrderLine (id, productVariantId, referenceName, couleur, quantite, coutUnitaireCalcule, totalLigne, margeUnitaire)
- SupplierOrder (id, numero, date, description, statut enum SupplierOrderStatus, prixFournisseur, fretImport, douane, metaAds, totalQty, coutTotal, coutUnitaire, lines[], createdAt, receivedAt) + getter isReceived
- SupplierOrderLineDraft (product_variant + quantite) + toJson

**Manques constates** (2)

- aucune entite Fournisseur (nom/contact/pays) : la commande est anonyme
- pas de devise ni de taux de change alors que le cout integre fret/douane (import)

#### `smartcross/lib/models/magasin.dart`

- **Route** : aucune
- **Role** : gerant/admin

**Implemente** (2)

- MagasinEmployer (id, fullName, email, isConfirmed, position, commandeRole)
- Magasin (magasinId, shopName, shopLogo, managerName/managerEmail extraits de l'objet 'manager', employers[]) + champs stats optionnels (totalProducts, totalStockQuantity, totalStockValue, totalSoldValue, profit) + methode withStats(stats) qui fusionne la reponse de magasins/stats/

**Manques constates** (2)

- pas d'adresse / telephone / horaires du magasin
- les stats sont un objet separe fusionne a la main, non typees (Map<String,dynamic> en entree)

#### `smartcross/lib/models/company.dart`

- **Route** : aucune
- **Role** : admin

**Implemente** (1)

- PasswordResetRequest (id, status pending|approved|rejected, userName, userEmail, userRole, magasinName, createdAt, resolvedAt)

**Manques constates** (1)

- 40 lignes, un seul modele : rien pour abonnement, appareils, societe, backup — tout le module Super Admin du frontend Next.js est absent

#### `smartcross/lib/models/json_utils.dart`

- **Route** : aucune
- **Role** : transverse

**Implemente** (2)

- convertisseurs tolerants partages par tous les fromJson : asDoubleOrNull/asDouble, asIntOrNull/asInt, asBool (gere bool, 'true', '1', num), asString/asStringOrNull, asDateOrNull (DateTime.tryParse)
- gere le fait que DRF serialise les DecimalField en String et que certains champs manquent selon le role

**Manques constates** (1)

- asDateOrNull ne normalise pas le fuseau (les dates sans suffixe Z sont lues comme locales) alors que core/app_time.dart impose Indian/Antananarivo ailleurs

#### `smartcross/lib/state/auth_provider.dart`

- **Route** : aucune (pilote le redirect de core/router.dart)
- **Role** : tous

**Implemente** (8)

- enum AuthStatus {loading, unauthenticated, authenticated} + classe AuthState(status, user) + copyWith
- authRepositoryProvider (Provider), authProvider (NotifierProvider<AuthNotifier, AuthState>)
- _bootstrap() : ApiClient.ensureInitialized() puis lecture du token ; sans token -> unauthenticated, sinon me() ; toute exception -> unauthenticated
- login(email, password) : login + me() + invalidation de TOUS les providers de donnees + passage a authenticated
- logout() : efface les tokens + invalide tous les providers de donnees
- refreshUser() : re-appelle me() et garde l'utilisateur en cache en cas d'echec
- _invalidateDataProviders(ref) : invalide explicitement 19 providers (orders, orderDetail, categories, types, brands, colors, references, referenceAutocomplete, dashboard, ruptures, movements, supplierOrders, supplierOrderDetail, notifications, currentCaisse, caisseHistory, accounts, pendingUsers, stores)
- authEventProvider : StreamProvider branche sur AuthEvents.instance.stream (401 non rafraichissable emis par ApiClient) -> force l'etat unauthenticated

**Manques constates** (3)

- _invalidateDataProviders n'invalide PAS deliveryZonesProvider ni passwordResetRequestsProvider, et ne vide pas le cache statique DeliveryZoneCatalog.zones -> residus de la session precedente
- aucune persistance de l'utilisateur en local : chaque demarrage exige un GET users/me/ (pas de mode hors-ligne)
- pas de gestion d'un compte non confirme / en attente d'approbation (pas d'ecran pending-approval comme cote Next.js)

#### `smartcross/lib/state/orders_provider.dart`

- **Route** : aucune (utilise par /orders, /orders/:id, /orders/new, /depot, /tournee, /bilan)
- **Role** : gerant / preparateur / livreur

**Implemente** (7)

- ordersRepositoryProvider
- deliveryZonesProvider (FutureProvider) qui remplit aussi le cache statique DeliveryZoneCatalog.zones
- OrdersFilter (statut, dateDebut, dateFin, preparateurId, historique, dateFrom, dateTo, nonLivree) + copyWith avec drapeaux clearStatut/clearPreparateurId
- ordersFilterProvider (NotifierProvider) : set(filter)
- ordersProvider (AsyncNotifier) : build() watch realtimeTickProvider + ordersFilterProvider -> rafraichissement automatique a chaque evenement WebSocket
- actions du notifier : refresh, create, changeStatus (avec photoPath), cancel, updateOrder, delete, availableStaff, assignLivreur, assignPreparateur — chacune suivie d'un refresh()
- orderDetailProvider : FutureProvider.autoDispose.family<Order,int> qui watch aussi realtimeTickProvider

**Manques constates** (3)

- le champ OrdersFilter.nonLivree est declare et documente mais N'EST PAS applique dans _fetch() : le filtre 'pas encore livree' n'est pas implemente dans le provider (a la charge de chaque ecran)
- chaque mutation declenche un refresh() complet de la liste (pas de mise a jour optimiste, contrairement aux notifications)
- pas de pagination / chargement incremental

#### `smartcross/lib/state/catalog_provider.dart`

- **Route** : aucune (utilise par /catalog, /settings, /suppliers/new)
- **Role** : gerant

**Implemente** (4)

- catalogRepositoryProvider
- categoriesProvider / typesProvider / brandsProvider / colorsProvider : AsyncNotifier avec build + refresh + create + rename + delete (create renvoie l'entite creee pour types/brands/colors)
- referencesProvider (AsyncNotifier) : build (toutes les references avec variantes), refresh, createReference, updateReference, deleteReference, uploadPhoto, createVariant, deleteVariant, bulkUpdatePrice (renvoie le nb modifie)
- referenceAutocompleteProvider : FutureProvider.autoDispose.family<List<ReferenceOption>, String>

**Manques constates** (4)

- referenceAutocompleteProvider N'EST UTILISE PAR AUCUN ECRAN : order_create_screen.dart appelle directement repo.autocomplete(...) — provider mort
- aucun provider ne watch realtimeTickProvider ici : le catalogue ne se rafraichit pas sur evenement temps reel (contrairement a orders/stock/dashboard)
- pas de mise a jour de variante (le repository ne l'expose pas)
- chaque mutation recharge tout le catalogue (refresh integral)

#### `smartcross/lib/state/dashboard_provider.dart`

- **Route** : aucune (utilise par /dashboard)
- **Role** : gerant

**Implemente** (4)

- dashboardRepositoryProvider
- enum DashboardPeriodPreset {jour, semaine, mois, personnalise} + DashboardFilter(preset, dateDebut, dateFin) + copyWith + resolveRange() qui calcule les bornes (jour = aujourd'hui, semaine = depuis lundi, mois = depuis le 1er, personnalise = dates saisies)
- dashboardFilterProvider (NotifierProvider, defaut = mois) avec set(filter)
- dashboardProvider (AsyncNotifier) : build() watch realtimeTickProvider + dashboardFilterProvider ; refresh()

**Manques constates** (2)

- resolveRange() utilise DateTime.now() local et NON appToday()/core/app_time.dart : entre 00h et 03h a Antananarivo la periode calculee peut differer de celle du serveur (le reste de l'app respecte pourtant ce fuseau)
- pas de cache/persistance : chaque tick WebSocket relance un appel dashboard complet

#### `smartcross/lib/state/realtime_provider.dart`

- **Route** : aucune (instancie une fois dans main.dart)
- **Role** : tous

**Implemente** (5)

- realtimeTickProvider (NotifierProvider<int>) + bump() : compteur incremente a chaque message WebSocket, watch par orders, orderDetail, dashboard, ruptures, movements, currentCaisse, caisseHistory, notifications, supplierOrders, supplierOrderDetail
- RealtimeBootstrap : ecoute authProvider (fireImmediately) -> connecte NotificationsSocketService a l'authentification, deconnecte sinon ; s'abonne a incoming et bump() a chaque message ; dispose() annule l'abonnement et ferme la socket
- construction de l'URL WS : {wsBaseUrl}/ws/notifications/?token={access} apres ApiClient.ensureInitialized()
- realtimeBootstrapProvider (Provider avec ref.onDispose)
- wsConnectionStatusProvider (StreamProvider<bool>) branche sur NotificationsSocketService.connectionStatus (consomme par la topbar)

**Manques constates** (4)

- strategie 'tout rafraichir' : chaque message WS relance N appels REST au lieu d'appliquer le payload recu (le contenu du message n'est jamais lu, seul son arrivee compte)
- aucune notification systeme/push locale (flutter_local_notifications est dans pubspec mais n'est importe NULLE PART)
- pas de reconnexion pilotee par l'etat reseau (connectivity_plus est dans pubspec mais jamais importe)
- le token est mis dans la query string de la WS (pas d'en-tete), il apparait donc dans les logs serveur

#### `smartcross/lib/state/notifications_provider.dart`

- **Route** : aucune (utilise par /notifications et widgets/topbar.dart)
- **Role** : tous

**Implemente** (4)

- notificationsRepositoryProvider
- notificationsProvider (AsyncNotifier) : build() watch realtimeTickProvider -> liste rechargee a chaque evenement WS ; refresh()
- markRead(id) avec MISE A JOUR OPTIMISTE (l'element passe lu immediatement, puis refresh() en cas d'echec)
- unreadNotificationsCountProvider (Provider<int>) : compte des non-lues, affiche en badge dans la topbar

**Manques constates** (3)

- markAllRead du repository n'est pas expose par le notifier (donc bouton 'tout marquer comme lu' impossible sans modification)
- pas de suppression de notification
- pas de filtre lu/non lu ni de pagination

#### `smartcross/lib/state/stock_provider.dart`

- **Route** : aucune (utilise par /catalog)
- **Role** : gerant

**Implemente** (3)

- stockRepositoryProvider
- rupturesProvider (AsyncNotifier) : build watch realtimeTickProvider -> repo.ruptures() ; refresh()
- movementsProvider : AsyncNotifier.family<List<StockMovement>, int?> (variantId nullable = tous) avec build watch realtimeTickProvider et refresh()

**Manques constates** (2)

- aucune action d'ajustement de stock exposee par un provider : catalog_screen.dart instancie StockRepository() directement pour appeler adjust() (contournement de la couche state)
- pas de provider pour l'export PDF des ruptures (appele directement depuis l'ecran)

#### `smartcross/lib/state/caisse_provider.dart`

- **Route** : aucune (utilise par /caisse)
- **Role** : gerant

**Implemente** (4)

- caisseRepositoryProvider
- currentCaisseProvider (AsyncNotifier<CaisseSession?>) : build watch realtimeTickProvider, lit magasinId depuis authProvider.user, renvoie null si pas de magasin
- actions : refresh(), open({openingBalance, openingNote}) avec StateError explicite si aucun magasin, close({closingBalance, closingNote}), addMovement({movementType, amount, reason}) avec StateError si aucune session ouverte — toutes suivies de refresh()
- caisseHistoryProvider (FutureProvider.autoDispose) : historique des sessions du magasin, watch realtimeTickProvider

**Manques constates** (2)

- pas de selection de magasin : tout est lie a authProvider.user.magasinId (un admin multi-magasins ne peut pas changer de caisse)
- pas d'edition/suppression de mouvement ni de categories (le repository ne les expose pas)

#### `smartcross/lib/state/users_provider.dart`

- **Route** : aucune (utilise par /users)
- **Role** : gerant

**Implemente** (3)

- usersRepositoryProvider
- accountsProvider (AsyncNotifier<List<AppUser>>) : build/refresh, create({fullName, email, password, commandeRole, phone}) qui recupere adminEmail depuis authProvider (StateError si non connecte), updateCommandeRole(userId, role), delete(userId, password)
- pendingUsersProvider (AsyncNotifier<List<PendingUser>>) : build/refresh, approve(userId), reject(userId)

**Manques constates** (2)

- aucun provider ne watch realtimeTickProvider : une nouvelle demande d'inscription n'apparait qu'apres un refresh manuel
- pas de modification d'un employe existant (nom/email/telephone), pas de reset de son mot de passe

#### `smartcross/lib/state/stores_provider.dart`

- **Route** : aucune (utilise par /stores et /transfers)
- **Role** : gerant/admin

**Implemente** (2)

- storesRepositoryProvider
- storesProvider (AsyncNotifier<List<Magasin>>) : build/refresh, create({shopName, managerFullName, managerEmail, managerPassword}), rename(magasinId, shopName), delete(magasinId, password) — chaque mutation suivie d'un refresh()

**Manques constates** (3)

- le transfert de stock (repo.transfer) et le catalogue par magasin (repo.catalogFor) ne sont PAS exposes par ce provider : transfers_screen.dart appelle le repository directement
- pas de watch du temps reel
- pas de provider 'magasin selectionne' partage entre ecrans

#### `smartcross/lib/state/suppliers_provider.dart`

- **Route** : aucune (utilise par /suppliers, /suppliers/new, /suppliers/:id)
- **Role** : gerant

**Implemente** (3)

- suppliersRepositoryProvider
- supplierOrdersProvider (AsyncNotifier<List<SupplierOrder>>) : build watch realtimeTickProvider, refresh(), create({description, prixFournisseur, fretImport, douane, metaAds, lines}), receive(id)
- supplierOrderDetailProvider : FutureProvider.autoDispose.family<SupplierOrder,int> qui watch realtimeTickProvider

**Manques constates** (2)

- pas d'update ni de delete (absents du repository)
- pas de filtre statut/date

#### `smartcross/lib/state/company_provider.dart`

- **Route** : aucune (utilise par l'onglet reinit. mots de passe de /users)
- **Role** : admin

**Implemente** (2)

- companyRepositoryProvider
- passwordResetRequestsProvider (AsyncNotifier<List<PasswordResetRequest>>) : etat interne _status initialise a 'pending', setStatus(status) puis refresh(), resolve(id, action)

**Manques constates** (2)

- _status est un champ mutable de l'AsyncNotifier (pas un provider de filtre separe) : il est perdu si le provider est reconstruit, et l'UI ne peut pas l'observer directement
- ce provider n'est pas dans la liste _invalidateDataProviders de auth_provider.dart : le filtre et les donnees survivent a un changement de compte

**Infrastructure reutilisable** (26)

- ROUTER — /home/garrix/Dev/Smartphone/smartcross/lib/core/router.dart (134 l.) : routerProvider = Provider<GoRouter>, initialLocation '/splash', refreshListenable = _RouterRefresh qui notifie quand authProvider.status change. Routes publiques (prefixes) : /login, /server-setup, /splash. Toutes les autres sont dans un ShellRoute unique qui enveloppe l'ecran dans NavigationShell(currentPath, child).
- ROUTER — gardes : redirect() lit authProvider ; status loading -> force /splash ; unauthenticated -> autorise seulement les routes publiques hors /splash, sinon /login ; authenticated sur une route publique -> redirige vers _homeFor(role) (gerant -> /dashboard, preparateur -> /depot, livreur -> /tournee, unknown/null -> /login). ATTENTION : AUCUNE garde par role sur les routes elles-memes — un preparateur qui tape /dashboard ou /users y accede (le filtrage par role n'existe que dans le menu, via NavItem.roles).
- ROUTER — routes declarees : /splash, /server-setup, /login, /dashboard, /caisse, /orders (+ /orders/new, /orders/:id), /depot, /tournee, /bilan, /catalog, /suppliers (+ /suppliers/new, /suppliers/:id), /users, /stores, /transfers, /chats (+ /chats/room/:room, /chats/dm/:id avec le titre passe en state.extra), /notifications, /settings.
- NAVIGATION — /home/garrix/Dev/Smartphone/smartcross/lib/core/nav_items.dart : kPrimaryNavItems, liste declarative de 14 NavItem(path, label, icon, roles?) avec visibleFor(role). Gerant : Tableau de bord, Commandes, Caisse, Produits, Fournisseurs, Magasins, Transferts, Utilisateurs. Preparateur : Depot. Livreur : Tournee + Bilan du jour. Tous : Discussions, Notifications, Parametres.
- SHELL — /home/garrix/Dev/Smartphone/smartcross/lib/widgets/navigation_shell.dart : bascule automatique sidebar permanente 240px (largeur >= kDesktopBreakpoint = 900) / Drawer mobile avec GlobalKey<ScaffoldState>, items filtres par role, item selectionne detecte par currentPath.startsWith(item.path), navigation via context.go().
- TOPBAR — /home/garrix/Dev/Smartphone/smartcross/lib/widgets/topbar.dart (PreferredSizeWidget, hauteur 64) : logo + titre Smartphone.Mg, pastille verte/orange d'etat WebSocket (wsConnectionStatusProvider) avec tooltip, icone Notifications avec Badge du nombre de non-lues (unreadNotificationsCountProvider) qui push /notifications, PopupMenuButton compte affichant nom/email/role + action Deconnexion (authProvider.notifier.logout() puis context.go('/login')).
- THEME — /home/garrix/Dev/Smartphone/smartcross/lib/core/theme.dart : Material 3, seed kSeedColor #2563EB, buildLightTheme() et buildDarkTheme() (AppBar plate sans surfaceTint, Card elevation 0 + bord outlineVariant radius 14, InputDecoration remplie radius 10). kChartPalette = 8 couleurs fixes pour les graphiques. statusColor(context, apiStatus) donne la couleur des 7 statuts de commande. main.dart applique themeMode: ThemeMode.system (aucun selecteur clair/sombre dans l'app).
- AUTH & TOKENS — /home/garrix/Dev/Smartphone/smartcross/lib/core/secure_storage.dart : TokenStorage (singleton, flutter_secure_storage) avec save(access, refresh), saveAccess, accessToken, refreshToken, clear. AppPrefs (singleton, shared_preferences) stocke l'URL serveur configurable (cle 'server_base_url').
- CLIENT HTTP — /home/garrix/Dev/Smartphone/smartcross/lib/core/api_client.dart (178 l., singleton ApiClient.instance) : Dio avec connectTimeout 20s / receiveTimeout 30s, baseUrl = '{serveur}/api/', interceptor qui injecte 'Authorization: Bearer <access>' a chaque requete ; sur 401 non deja retentee -> POST users/refresh/ avec le refresh token, sauvegarde du nouvel access et REJEU automatique de la requete d'origine ; si le refresh echoue -> AuthEvents.emit(sessionExpired) que authEventProvider transforme en deconnexion. ensureInitialized() lit l'URL sauvegardee, setBaseUrl() normalise le slash final, wsBaseUrl derive http->ws / https->wss. kDefaultServerUrl : 10.0.2.2:8010 sur Android, 127.0.0.1:8010 ailleurs. Helpers statiques reutilisables : isConnectivityError(error) et messageFromError(error) qui extrait error/detail/message ou aplatit les erreurs de validation DRF {champ: [msgs]}.
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/core/ws_manager.dart : classe abstraite WsManager (connexion via web_socket_channel, token en query string, await channel.ready, reconnexion automatique apres 3s sauf fermeture volontaire, decodage JSON de chaque trame, hooks onMessage/onStatusChange, send(), disconnect(), isConnected).
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/core/notifications_socket_service.dart : singleton NotificationsSocketService (ws/notifications/?token=), expose incoming (Stream<Map>) et connectionStatus (Stream<bool>). Branche par RealtimeBootstrap (state/realtime_provider.dart) sur l'etat d'auth et relaye chaque message vers realtimeTickProvider.
- TEMPS REEL — /home/garrix/Dev/Smartphone/smartcross/lib/core/chat_socket_service.dart : ChatSocketService (instance jetable par conversation, ws/chat/?token=&recipient_id=), heartbeat de presence toutes les 20s via {'action':'ping'}, actions sendMessage / editMessage / deleteMessage / markRead, streams incoming + connectionStatus, disposeService(). C'est le SEUL canal d'envoi de message (aucun POST REST).
- PROVIDERS RIVERPOD — 12 fichiers dans lib/state/. Pattern dominant : un Provider par repository + un AsyncNotifier (ou AsyncNotifierProvider.family / FutureProvider.autoDispose.family pour les details) avec build/refresh + methodes de mutation suivies d'un refresh(). Les providers 'live' (orders, orderDetail, dashboard, ruptures, movements, currentCaisse, caisseHistory, notifications, supplierOrders, supplierOrderDetail) font ref.watch(realtimeTickProvider) pour se recharger a chaque evenement WebSocket.
- PROVIDERS — filtres partages : ordersFilterProvider (OrdersFilter : statut, dates jour, dateFrom/dateTo, preparateurId, historique, nonLivree) et dashboardFilterProvider (presets jour/semaine/mois/personnalise avec resolveRange()). Deux modeles reutilisables pour ajouter des filtres a de nouveaux ecrans.
- REPOSITORIES — 12 fichiers dans lib/data/repositories/, tous batis sur `Dio get _dio => ApiClient.instance.dio` avec des chemins relatifs a /api/ : auth, orders, catalog, stock, suppliers, users, stores, caisse, dashboard, notifications, chat, company. Ils couvrent 4 apps Django : users/ (auth, employes, caisse, chat, notifications, magasins, transferts, reinit. mdp), orders/ (commandes, statuts, staff, dashboard, zones), catalog/ (categories, types, marques, couleurs, references, variantes, mouvements, import/export Excel), suppliers/ (commandes fournisseur).
- MULTIPART / FICHIERS deja en place et reutilisables : upload photo de profil (auth), photo de reference produit (catalog), photo de preuve de preparation jointe au changement de statut (orders), import Excel a partir de bytes (catalog, compatible URI content:// Android), export Excel en ResponseType.bytes, generation PDF cote client avec le package pdf (stock ruptures).
- WIDGETS PARTAGES — /home/garrix/Dev/Smartphone/smartcross/lib/widgets/async_state_widgets.dart : LoadingState, ErrorState(message, onRetry), EmptyState(message, icon) — triptyque a reutiliser sur tout nouvel ecran AsyncValue.
- WIDGETS PARTAGES — kpi_card.dart : KpiCard(label, value, icon, accentColor, subtitle) et KpiGrid responsive (2 colonnes < 600px, 3 < 900, 4 < 1200, 5 au-dela, mainAxisExtent 128).
- WIDGETS PARTAGES — status_badge.dart : StatusChip(label, color) generique, OrderStatusBadge(status) branche sur statusColor(), StockLevelBadge(isRupture, isStockBas) -> Rupture / Stock bas / OK.
- WIDGETS PARTAGES — order_confirm_dialog.dart : showOrderConfirmDialog(context, {title, order, showPhoto, hideAmounts}) -> OrderConfirmResult(note, photoPath). Resume client/telephone/zone/adresse/paiement/articles/prix, champ note optionnel, prise de photo via image_picker (source camera, qualite 85) avec vignette. Exporte aussi les helpers reutilisables arFmt(num) ('12 500 Ar', intl fr_FR), isJourJ(dateCommande) et dueDateLabel(date).
- WIDGETS PARTAGES — assign_staff_dialog.dart : showAssignStaffDialog(context, {role, orderNumero, loadStaff}) -> AssignResult(staffId, assignedAt). Dropdown des StaffOption (suffixe '(occupe)' indicatif), selecteur date + heure (showDatePicker +/- 60 jours puis showTimePicker), etats chargement/erreur/liste vide.
- WIDGETS PARTAGES — order_historique_view.dart : OrderHistoriqueView(cardBuilder) — vue historique complete reutilisable (preparateur et livreur) avec filtres Du.../Au... (date + heure, heure facultative), 7 ChoiceChip de statut (Tous, Livrees, Retours, Annulees, En livraison, A recuperer, En preparation), bouton reset, FutureBuilder + LoadingState/ErrorState/EmptyState et RefreshIndicator. Instancie son propre OrdersRepository (hors Riverpod).
- FUSEAU HORAIRE — /home/garrix/Dev/Smartphone/smartcross/lib/core/app_time.dart : module dedie Indian/Antananarivo (UTC+3 fixe) avec appNow(), appLocal(instant), appDay(instant), appToday(), appWallClockToUtc(wallClock) et appDayBounds(day) -> (start, end) UTC. A utiliser pour tout nouveau filtre de date envoye au serveur (deja utilise par order_historique_view et order_confirm_dialog).
- CONSTANTES/ENUMS — /home/garrix/Dev/Smartphone/smartcross/lib/core/constants.dart : UserRole (gerant/preparateur/livreur/unknown) + fromApi/apiValue/label ; OrderStatus (7 valeurs) + fromApi/apiValue/label ; PaymentMode (avant/livraison) ; StockMovementType (entree/sortie) ; SupplierOrderStatus (brouillon/commande/recu) ; kDesktopBreakpoint = 900 ; helper dialogWidth(available, desired).
- ENTREE DE L'APP — /home/garrix/Dev/Smartphone/smartcross/lib/main.dart (24 l.) : ProviderScope > SmartphoneMgApp (ConsumerWidget) qui ref.watch(realtimeBootstrapProvider) pour instancier le pont WebSocket une seule fois, puis MaterialApp.router(routerConfig: routerProvider, theme/darkTheme, themeMode.system).
- DEPENDANCES (pubspec.yaml) reellement importees : flutter_riverpod 3.4.2, go_router 17.3.0, dio 5.11, web_socket_channel 3.0.3, flutter_secure_storage 10.3.1, shared_preferences 2.5.5, pdf 3.13, intl 0.20.3, image_picker 1.2, file_picker 12.2, share_plus 13.3, url_launcher 6.3, collection. DECLAREES MAIS JAMAIS IMPORTEES dans lib/ : fl_chart (donc aucun graphique de librairie dans le dashboard), flutter_local_notifications (aucune notification systeme), connectivity_plus (aucune detection reseau), printing (aucune impression), path_provider.

**Notes**

PERIMETRE COUVERT INTEGRALEMENT : les 12 fichiers de lib/data/repositories/, les 13 de lib/models/ et les 12 de lib/state/ ont ete lus en entier (2 271 lignes au total), plus lib/core/*.dart, lib/main.dart et lib/widgets/*.dart pour la partie infrastructure. Le champ "screens" ci-dessus decrit donc les fichiers de la couche donnees (aucun n'a de route go_router : la valeur "route" indique quels ecrans les consomment).

ARCHITECTURE REELLE CONSTATEE : ecran -> provider Riverpod (lib/state) -> repository (lib/data/repositories) -> ApiClient (Dio singleton) -> Django REST /api/. Le temps reel n'apporte aucune donnee : NotificationsSocketService incremente un simple compteur (realtimeTickProvider) que 10 providers observent pour se recharger en REST.

ENTORSES A CETTE ARCHITECTURE (repositories appeles directement depuis les ecrans, sans provider) :
- features/settings/settings_screen.dart lignes 92, 98, 135 : AuthRepository().updateProfile / uploadProfilePhoto / changePassword
- features/catalog/catalog_screen.dart ligne 697 : StockRepository().adjust(...)
- features/transfers/transfers_screen.dart : storesRepository.catalogFor(...) et .transfer(...)
- features/orders/order_create_screen.dart ligne 626 : repo.autocomplete(...)
- widgets/order_historique_view.dart ligne 35 : `final _repo = OrdersRepository();`
- features/chats/chat_list_screen.dart ligne 12 : `final chatRepositoryProvider = Provider((ref) => ChatRepository());` — seul provider declare hors de lib/state/, et il n'existe aucun chat_provider.dart.

CODE MORT / NON BRANCHE (verifie par grep sur features/ et widgets/) :
- referenceAutocompleteProvider (state/catalog_provider.dart) : aucun usage.
- NotificationsRepository.markAllRead() : jamais expose par le notifier, jamais appele.
- CatalogRepository.uploadReferencePhoto : appele uniquement via referencesProvider.uploadPhoto (OK), mais RuptureItem.fromJson (models/stock.dart) n'est jamais utilise.
- OrdersFilter.nonLivree est declare et documente mais n'est jamais lu dans OrdersNotifier._fetch().
- fl_chart, flutter_local_notifications, connectivity_plus, printing, path_provider sont dans pubspec.yaml mais absents de tout import de lib/.

INCOHERENCES A CORRIGER AVANT DE PORTER DE NOUVEAUX ECRANS :
1. Aucune garde de route par role dans core/router.dart : le filtrage par role n'existe qu'au niveau du menu (nav_items.dart). Un acces direct par URL a /dashboard ou /users depuis un compte preparateur/livreur n'est pas bloque cote app.
2. auth_provider._invalidateDataProviders n'invalide pas deliveryZonesProvider ni passwordResetRequestsProvider, et le cache STATIQUE DeliveryZoneCatalog.zones (models/delivery_zone.dart) n'est jamais vide : des donnees de la session precedente survivent a un changement de compte.
3. DashboardFilter.resolveRange() (state/dashboard_provider.dart) utilise DateTime.now() local alors que tout le reste passe par core/app_time.dart (Indian/Antananarivo). Ecart possible de periode entre 00h et 03h.
4. AppNotification.orderId est force a null : le deep-link notification -> commande ne dispose que du numero extrait par regex sur le message francais.
5. UsersRepository.list() ne lit que `magasins.first.employers` : casse des qu'un compte possede plusieurs magasins, alors que StoresRepository/Magasin gerent bien le multi-magasin.

ECART FONCTIONNEL AVEC LE FRONTEND NEXT.JS (/home/garrix/Dev/Smartphone/frontend) — endpoints presents dans lib/django-client.ts et ABSENTS de toute la couche data Flutter :
- users/public/forgot-password/, /confirm/, /status/ (pages forgot-password, reset-password, verify-email, pending-approval, register cote web) — aucun equivalent mobile.
- users/backup/export/ et users/backup/import/ ; users/magasins/overview/ ; users/dashboard/ ; users/logout-event/ ; users/role/{id}/.
- notifications : bulk-read/, bulk-delete/, delete-all/ et DELETE unitaire.
- caisse : categories/ (CRUD), summary/, PATCH et DELETE d'un mouvement.
- catalog : PATCH d'une variante, import-batches/{id}/cancel/.
- orders : CRUD des delivery-zones (POST/PATCH/DELETE) — l'app ne fait que lire la liste.
Cote pages, le web a alerts, movements, pickup, reports, sales et superadmin qui n'ont pas de route go_router equivalente (alerts/movements semblent absorbes dans /catalog).

