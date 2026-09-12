# FLUTTER_FEATURE_PARITY.md

Checklist de parité **Next.js → Flutter**. Le frontend Next.js est la référence fonctionnelle ;
l'application Flutter doit reproduire tout ce que l'utilisateur peut y faire, sur le même backend Django.

Une case n'est cochée que lorsque la fonctionnalité **fonctionne réellement dans Flutter**.

Statuts de route : `MISSING` (aucun écran) · `PARTIAL` (écran présent, fonctionnalités incomplètes) ·
`IMPLEMENTED` (écran complet, non encore vérifié écran contre écran) · `VERIFIED` (comparé et conforme).

## COMMANDES

### `/orders`  —  VERIFIED

Écran Flutter : `features/orders/*, features/depot/depot_screen.dart, features/tournee/tournee_screen.dart`  
Fonctionnalités à garantir : 100

- [x] En-tete : titre dynamique — 'Historique' si viewMode==='HISTORIQUE', sinon 'Depot — Commandes a preparer' (preparateur), 'Ma tournee' (livreur), 'Commandes' (gerant/defaut)
- [x] En-tete : sous-titre dynamique — HISTORIQUE: 'Vos commandes deja traitees, tous statuts — filtrables par date et heure.' ; preparateur: 'Commandes recues a preparer, puis a marquer "Prete" pour le livreur.' ; livreur: 'Commandes pretes a recuperer, puis "Livre" ou "Retour" une fois la tournee faite.' ; gerant/defaut: 'Suivi complet des commandes clients.'
- [x] Bouton icone Rafraichir (RefreshCw, variant outline, size icon) — appelle fetchOrders() NON silencieux (affiche le skeleton). Visible pour tous les roles
- [x] Bouton principal 'Nouvelle commande' (gerant) / 'Nouvelle recuperation' (preparateur), icone Plus — ouvre CreateOrderDialog. Condition: (isGerant || isPreparateur). INVISIBLE pour le livreur
- [x] Barre d'onglets PREPARATEUR (3 boutons size sm, variant default si actif sinon outline) : 'A preparer' (icone Truck, set viewMode=ACTIF + preparateurTab=A_PREPARER), 'Recuperations' (icone Package, viewMode=ACTIF + preparateurTab=RECUPERATIONS), 'Historique' (icone History, viewMode=HISTORIQUE)
- [x] Barre d'onglets LIVREUR (2 boutons) : 'Ma tournee' (icone Truck, viewMode=ACTIF), 'Historique' (icone History, viewMode=HISTORIQUE)
- [x] Le GERANT n'a AUCUN onglet Historique/vue alternative : viewMode reste toujours 'ACTIF' pour lui
- [x] Barre de filtres rapides GERANT : rangee de boutons toggle 'Toutes' (statutFilter='ALL'), 'Pas encore livree' (statutFilter='NON_LIVREE'), puis un bouton par statut de STATUTS (Nouvelle, En preparation, Prete, En livraison, Livre, Retour, Annulee). Le bouton actif est variant=default, les autres outline
- [x] Le meme statutFilter est aussi expose en Select dans la rangee de filtres gerant (double UI redondante liee au meme state)
- [x] Tableau des commandes (composant Table shadcn) dans une Card, wrapper overflow-x-auto. Aucune pagination, aucun tri cliquable sur les entetes, aucun export
- [x] Colonne 'N° commande' : order.numero, font-medium
- [x] Colonne 'Type' : firstItem?.category_name || '-' (categorie du PREMIER article seulement)
- [x] Colonne 'Sous-type' : firstItem?.type_name || '-' (type du PREMIER article seulement)
- [x] Colonne 'Produit' (max-w 280px) : boucle sur TOUS les order.items — ligne 1 = it.reference_name (fallback 'Article') a gauche + 'x{quantite}' a droite (affiche seulement si it.quantite truthy) ; ligne 2 = 'Marque: {it.brand_name}' si present + pastille arrondie avec it.couleur si presente
- [x] Colonne 'Date' : order.date_commande formate fr-FR en fuseau Indian/Antananarivo au format JJ/MM HH:mm (sans annee), sinon '-'
- [x] Colonne 'Client' : order.client_nom
- [x] Colonne 'Adresse' — UNIQUEMENT si isLivreur : order.adresse_livraison || '-', tronquee (max-w 180px truncate)
- [x] Colonne 'Telephone' — UNIQUEMENT si isLivreur : lien <a href="tel:{telephone}"> bleu souligne au survol avec icone Phone ; onClick stopPropagation pour ne pas ouvrir le detail
- [x] Colonne 'Zone' (si isLivreur) / 'Adresse' (sinon) : pour le livreur = libelle de zone sans le prix (label.split(' (')[0]) ; pour les autres = adresse_livraison sinon libelle de zone sinon le code brut livraison_zone
- [x] Colonne 'Statut' : Badge colore via statutInfo(order.statut_courant)
- [x] Colonne 'Total' — masquee si isPreparateur : si isLivreur && mode_paiement==='AVANT' affiche le texte vert 'Deja paye', sinon fmt(order.total_a_payer) formate 'x xxx Ar'
- [x] Colonne 'Assigne a' — UNIQUEMENT si isGerant : '-' si ni preparateur_name ni livreur_name ; sinon bloc preparateur (icone UserRound + nom + horodatage du passage EN_PREPARATION issu de status_history) et/ou bloc livreur (icone Truck + nom + 'Livre le {date}' si statut LIVRE sinon 'Prevu le {date_commande}')
- [x] Colonne 'Action' (alignee a droite) : contenu conditionnel par role, voir lignes suivantes
- [x] Action GERANT = un Select 'Action' (h-8, w-170px) rendu seulement si gerantActionOptions(order).length>0 ; sur choix, ouvre soit AssignStaffDialog (kind='assign') soit le dialogue de confirmation ActionNote (kind='status')
- [x] Options gerant selon statut : NOUVELLE -> ['Assigner un preparateur' (assign PREPARATEUR, cible EN_PREPARATION), 'Commencer la preparation' (status EN_PREPARATION)] ; EN_PREPARATION -> ['Commande prete' (PRETE)] ; PRETE non-recuperation -> ['Assigner un livreur' (assign LIVREUR, cible EN_LIVRAISON), 'Recuperer / En livraison' (status EN_LIVRAISON)] ; PRETE + zone RECUPERATION -> ['Recuperee par le client' (status LIVRE)] ; EN_LIVRAISON -> ['Livree' (LIVRE), 'Retour' (RETOUR)] ; LIVRE/RETOUR/ANNULEE -> aucune option (le Select disparait)
- [x] Action PREPARATEUR/LIVREUR = un IconAction avec libelle (showLabel) issu de nextAction(order) : preparateur NOUVELLE -> 'Commencer la preparation' (Package), EN_PREPARATION -> 'Commande prete' (Package), sinon rien ; livreur PRETE -> 'Recuperer (en livraison)' (Truck), EN_LIVRAISON -> 'Livre' (Truck), sinon rien
- [x] Bouton secondaire 'Retour' (icone Undo2, outline, texte rouge) sur la ligne : condition ecrite `(isLivreur || isGerant) && statut==='EN_LIVRAISON' && !isGerant` — en pratique LIVREUR SEUL (le `&& !isGerant` neutralise la branche gerant, qui passe par son Select)
- [x] Bouton 'Modifier' (Pencil, outline, showLabel) : canEdit = isGerant && statut ∈ {NOUVELLE, EN_PREPARATION}
- [x] Bouton 'Annuler la commande' (Ban, outline, rouge) : canCancel = isGerant && statut ∉ {LIVRE, RETOUR, ANNULEE}
- [x] Bouton 'Supprimer' (Trash2, outline, rouge) : canDelete = isGerant && statut === 'NOUVELLE' uniquement
- [x] Tout clic sur une ligne (className cursor-pointer) ouvre le dialogue Detail ; chaque bouton d'action fait e.stopPropagation()
- [x] Blocage 'jour J' : notYetDue = (isPreparateur||isLivreur) && !isJourJ(order.date_commande). Quand true, les IconAction sont disabled et leur libelle+tooltip deviennent 'Disponible le {JJ/MM/AAAA}'
- [x] IconAction : composant local = Button (size icon ou sm si showLabel) enveloppe dans un Tooltip shadcn dont le contenu est le label
- [x] Chronologie/timeline dans le detail (OrderTimeline) : lignes 'Commande cree le' (created_at), 'Livraison prevue le' (date_commande), puis jalons atteints uniquement — 'Preparation commencee le' (Wrench), 'Prete le' (Boxes), 'En livraison depuis le' (Truck), 'Livree le' (CheckCircle2), 'Retour le' (Undo2). Chaque jalon prend le PREMIER timestamp du status_history pour ce statut
- [x] Historique detaille dans le detail : liste ul de tous les status_history — '{label statut} — {changed_by_name || "Systeme"} — {date+heure}' + ' (note)' si note + vignette photo 64x64 cliquable + lien 'Voir / telecharger la photo' (target=_blank) si h.photo
- [x] Rafraichissement temps reel : useRealtimeRefresh(['order','order_status_history'], () => fetchOrders(true)) — WebSocket /ws/data/, debounce 400 ms, refetch SILENCIEUX (pas de skeleton)
- [x] Refetch automatique a chaque changement d'un filtre (fetchOrders est un useCallback dont les deps sont tous les filtres, et un useEffect le rappelle quand il change, une fois userLoading=false)
- [x] CreateOrderDialog ('Nouvelle commande', description 'Vente Facebook ou sur place — §6 du cahier des charges.') — CHAMPS : (1) bloc OrderItemsEditor (Categorie, Sous-type, Marque, recherche reference, Couleur, Quantite, Prix lecture seule si showPrices, bouton 'Ajouter a la commande') ; (2) 'Type de commande' = 2 boutons toggle 'A livrer' (prend la 1re zone non-RECUPERATION) / 'Recuperation sur place' — MASQUE pour le preparateur qui voit a la place le texte 'Retrait sur place uniquement — la commande apparaitra dans "Recuperations" une fois prete, a valider comme livree au comptoir par le gerant.' ; (3) 'Date et heure de livraison' = DateTimeInput (2 champs date + time), defaut = maintenant a l'heure d'Antananarivo, aide 'Vide = maintenant.' ; (4) Select 'Preparateur' (placeholder 'Assigner plus tard') et Select 'Livreur' (placeholder 'Assigner plus tard') — masques pour le preparateur ; (5) si zone != RECUPERATION : Select 'Zone de livraison' (options = zones actives avec leur prix) + Input 'Adresse de livraison' (placeholder 'Ex: Lot II M 45 Antanimena, Antananarivo') ; (6) si zone != RECUPERATION : Select 'Paiement' (Paye / Paiement a la livraison, defaut LIVRAISON) ; (7) Input 'Nom client' (placeholder 'Rakoto Jean') ; (8) Input 'Telephone' (valeur initiale '+261', placeholder '+261340000000') ; (9) Textarea 'Note pour le preparateur (optionnel)' — libelle 'Note (optionnel)' pour le preparateur ; (10) Textarea 'Note pour le livreur (optionnel)' si !isPreparateur && zone != RECUPERATION ; (11) recap 'Frais de livraison' + 'Total a payer' si showPrices
- [x] CreateOrderDialog — VALIDATIONS cote client, toasts d'erreur bloquants : nom vide -> toast.error 'Nom du client requis' ; telephone ne matchant pas /^\+261\d{9}$/ -> 'Telephone au format +261XXXXXXXXX' ; items vide -> 'Ajoutez au moins un article'. Aucune validation sur adresse/zone/date
- [x] CreateOrderDialog — SOUMISSION : POST /orders/ (date_commande envoyee seulement si renseignee, convertie via appDatetimeLocalToIso ; note_livreur forcee a '' si zone RECUPERATION), puis si preparateurId POST assign-preparateur, puis si livreurId POST assign-livreur. Chaque assignation ratee -> toast.error 'Commande creee, mais l'assignation du preparateur/livreur a echoue : {msg} (a assigner depuis le tableau).' et assignmentFailed=true. Si aucune erreur -> toast.success 'Commande creee et assignee' (si au moins une assignation) sinon 'Commande creee'. Ensuite onCreated() : ferme le dialogue et fetchOrders() NON silencieux. Erreur globale -> toast.error(err.message || 'Erreur lors de la creation'). Bouton 'Creer la commande' devient 'Creation…' et disabled pendant submitting
- [x] CreateOrderDialog — REINITIALISATION a chaque ouverture (useEffect sur `open`) : clientNom='', telephone='+261', zone = 'RECUPERATION' si preparateur sinon '' (puis auto-selection de la 1re zone payante des que zoneOptions arrive), adresse='', modePaiement='LIVRAISON', dateCommande=maintenant, notes='', items=[], preparateurId='', livreurId=''
- [x] EditOrderDialog ('Modifier la commande {numero}', description 'Possible tant que la commande n'est pas encore "Prete".') — CHAMPS : OrderItemsEditor avec showPrices=true (articles existants pre-charges et supprimables, nouveaux ajoutables), 'Type de commande' (2 boutons toggle A livrer / Recuperation sur place), 'Date et heure de livraison' (DateTimeInput, sans texte d'aide), 'Nom client', 'Telephone', si zone != RECUPERATION : 'Zone de livraison' + 'Adresse de livraison' + 'Paiement', Select 'Preparateur', Select 'Livreur' (uniquement si zone != RECUPERATION), Textarea 'Note pour le preparateur (optionnel)', Textarea 'Note pour le livreur (optionnel)' si zone != RECUPERATION
- [x] EditOrderDialog — PRE-REMPLISSAGE (useEffect sur `order`) : tous les champs depuis l'objet commande ; date convertie en datetime-local heure Antananarivo ; items mappes depuis order.items avec key 'existing-{id}', prix_vente=prix_unitaire, variant_id=product_variant, stock_actuel=Infinity (donc plus de controle de stock sur les lignes deja presentes) ; chargement en parallele de availableStaff('PREPARATEUR', order.magasin) et availableStaff('LIVREUR', order.magasin, order.date_commande)
- [x] EditOrderDialog — VALIDATIONS identiques a la creation : 'Nom du client requis', 'Telephone au format +261XXXXXXXXX', 'Ajoutez au moins un article'
- [x] EditOrderDialog — SOUMISSION : PATCH /orders/{id}/ (adresse forcee a '' si zone RECUPERATION, note_livreur forcee a '' si RECUPERATION, date_commande envoyee seulement si renseignee), puis assign-preparateur si preparateurId a change, puis assign-livreur si zone != RECUPERATION et livreurId a change. Echec d'assignation -> toast.error 'Commande mise a jour, mais l'assignation du preparateur/livreur a echoue : {msg}'. Succes -> toast.success 'Commande mise a jour' puis onSaved() = ferme + fetchOrders(true) SILENCIEUX. Erreur -> toast.error(err.message || 'Erreur lors de la modification'). Bouton 'Enregistrer' -> 'Enregistrement...' + disabled pendant submitting
- [x] NoteForm (formulaire de confirmation d'action, integre au dialogue ActionNote) — CHAMPS : Textarea 'Note (optionnel)' ; si showPhoto (uniquement quand la cible est PRETE) : Label avec icone Camera 'Photo de la preparation (optionnel)' + Input type=file accept=image/* + apercu 80x80 (URL.createObjectURL). Boutons 'Annuler' (outline) et 'Confirmer'. Aucune validation : la note peut etre vide
- [x] AssignStaffDialog — CHAMPS : Select 'Choisir un preparateur'/'Choisir un livreur' (liste availableStaff, valeur = id) + 'Date et heure' (DateTimeInput, pre-rempli a maintenant heure Antananarivo) avec aide 'Vide = maintenant.'. Bouton 'Assigner' disabled tant qu'aucune personne selectionnee ; bouton 'Annuler' ferme. Soumission = doChangeStatus(order, EN_PREPARATION|EN_LIVRAISON, note=undefined, {preparateur_id|livreur_id, assigned_at: ISO})
- [x] OrderItemsEditor (sous-formulaire partage Create/Edit) — CHAMPS : Select 'Categorie', Select 'Sous-type' (filtre par categorie choisie), Select 'Marque', Input de recherche 'Rechercher une reference (ex: A15)' avec liste de suggestions en popover absolu, puis quand une reference est selectionnee : Select 'Couleur' (option '{couleur} (stock: {n})', DESACTIVEE si stock_actuel<=0), Input number 'Quantite' (min=1, placeholder 'Ex: 1'), Input 'Prix (Ar)' readOnly+disabled si showPrices, bouton 'Ajouter a la commande'
- [x] OrderItemsEditor — VALIDATIONS a l'ajout : pas de reference ou pas de couleur -> toast.error 'Selectionnez une reference et une couleur' ; quantite vide/0/negative -> 'Quantite invalide' ; quantite > variant.stock_actuel -> 'Stock insuffisant (disponible: {n})'. Apres ajout : reset de query, suggestions, selectedRef, variantId, quantite
- [x] OrderItemsEditor — panier : liste des lignes '{reference_label} ({couleur}) x{quantite}' + montant ligne (prix_vente*quantite) si showPrices + bouton icone poubelle rouge pour retirer la ligne (suppression par index)
- [x] Dialog 'Detail commande' (max-w-lg) — ouvert par clic sur une ligne. Contient : titre 'Commande {numero}' ; bouton 'Modifier' en en-tete si isGerant && statut ∈ {NOUVELLE, EN_PREPARATION} (ferme le detail et ouvre EditOrderDialog) ; section 'Articles' (encadre gris) listant reference_name (+ couleur entre parentheses) et la ligne meta 'type • categorie • marque' ou 'Sans metadonnees' ; grille d'infos Nom client / Numero client / Adresse client / Mode de payment ; 'Total a payer' AFFICHE UNIQUEMENT si mode_paiement !== 'AVANT' ; Preparateur et Livreur si renseignes ; bouton d'action pleine largeur (uniquement si !isGerant et si nextAction existe) desactive et libelle 'Disponible le {date}' si pas jour J ; 'Note pour le preparateur' et 'Note pour le livreur' si presentes ; section 'Chronologie' (OrderTimeline) ; section 'Historique detaille' (liste des status_history avec auteur, date, note et photo)
- [x] Dialog 'Confirmer : {label de l'action}' (actionNote) — description 'Commande {numero} — verifiez le resume avant de confirmer.'. Encadre recapitulatif : Client, Telephone (si present), Zone (libelle sans prix), Adresse (si presente), Paiement (masque si zone RECUPERATION), liste des Articles '{reference_name} ({couleur}) x{quantite}'. Bloc montants : si isLivreur && mode_paiement==='AVANT' -> ligne verte 'A encaisser : Rien — deja paye' ; sinon, si total_a_payer != null : 'Prix de vente' (= total - frais) et 'Frais de livraison' affiches seulement si zone != RECUPERATION et frais_livraison != null, puis 'Total'. Puis NoteForm (note + photo si cible PRETE) avec boutons Annuler / Confirmer
- [x] Dialog 'Assigner un preparateur/livreur' (AssignStaffDialog) — description 'Commande {numero} — choisissez manuellement qui prend cette commande en charge.'. Etat chargement = Skeleton h-10 ; etat vide = 'Aucun {preparateur|livreur} enregistre pour ce magasin.' ; sinon Select du staff + DateTimeInput 'Date et heure' + aide 'Vide = maintenant.'. Footer Annuler / Assigner (disabled si rien de selectionne). Rendu seulement si isGerant
- [x] Dialog 'Annuler la commande {numero} ?' (cancelTarget) — description 'La commande de {client_nom} sera annulee.' + phrase conditionnelle ' Le stock deja deduit pour cette commande sera automatiquement restitue.' si statut ∈ {EN_PREPARATION, PRETE, EN_LIVRAISON}. Footer : 'Retour' (outline) et 'Annuler la commande' (destructive, libelle 'Annulation...' + disabled pendant l'appel)
- [x] Dialog 'Supprimer la commande {numero} ?' (deleteTarget) — description 'Cette action est definitive — la commande de {client_nom} sera supprimee.'. Footer : 'Annuler' (outline) et 'Supprimer' (destructive, libelle 'Suppression...' + disabled pendant l'appel)
- [x] Dialog 'Nouvelle commande' (CreateOrderDialog, max-w-2xl, max-h-90vh scrollable) — rendu seulement si (isGerant || isPreparateur). Titre identique meme pour le preparateur (seul le bouton d'ouverture dit 'Nouvelle recuperation')
- [x] Dialog 'Modifier la commande {numero}' (EditOrderDialog, max-w-2xl, max-h-90vh scrollable) — rendu seulement si isGerant
- [x] Popover/dropdown d'autocomplete catalogue dans OrderItemsEditor : liste absolue z-10 sous l'input, max-h 56, s'ouvre des qu'un filtre OU du texte est saisi et qu'aucune reference n'est encore selectionnee ; etats 'Recherche…' / 'Aucun resultat pour cette selection.' / liste des references cliquables ('{marque} {reference} ({type})' + prix a droite si showPrices)
- [x] Badges-filtres supprimables (chips) dans OrderItemsEditor : un Badge secondary par filtre actif (Categorie / Sous-type / Marque) avec un bouton '×' ; retirer la categorie retire aussi le sous-type
- [x] Select d'action inline dans chaque ligne du tableau (gerant) — se comporte comme un menu contextuel, placeholder 'Action', ne conserve pas de valeur selectionnee
- [x] Tooltips shadcn sur chaque IconAction (le contenu du tooltip est le meme texte que le libelle, y compris 'Disponible le {date}' quand l'action est bloquee)
- [x] Recherche texte GLOBALE cote client (searchQuery) appliquee sur visibleOrders — matche sur numero, client_nom, adresse_livraison, telephone, livraison_zone, preparateur_name, livreur_name, statut_courant, le texte concatene de tous les items (reference_name, product_name, couleur, variant_name) et la date_commande formatee (fmtAppDate ET fmtAppDateTime). Insensible a la casse, trim, includes simple. Placeholder gerant/livreur : 'Code, client, produit, adresse, livreur, preparateur, date...' ; preparateur : 'Code, client, produit, adresse, date...'. AUCUNE barre de recherche n'est rendue pour un utilisateur qui n'est ni gerant ni preparateur ni livreur
- [x] GERANT — barre de boutons statut : Toutes (ALL) / Pas encore livree (NON_LIVREE, filtre CLIENT-side sur statut !== 'LIVRE') / un bouton par statut (envoye au serveur en param `statut`)
- [x] GERANT — Select 'Statut' avec les memes valeurs (Tous, Pas encore livree, + les 7 statuts), lie au meme state statutFilter
- [x] GERANT — Input type=date 'Date' (gerantDate) : envoie date_debut=date_fin=gerantDate (un seul jour, pas de plage)
- [x] GERANT — Select 'Preparateur' (preparateurFilterId) alimente par GET available-staff?role=PREPARATEUR (sans magasin), envoie preparateur_id. ATTENTION : aucune option 'Tous' dans la liste, la seule facon de l'enlever est le bouton Reinitialiser
- [x] GERANT — bouton 'Reinitialiser' (ghost, sm) visible si gerantDate || preparateurFilterId || statutFilter!=='ALL' || searchQuery ; remet les 4 a zero
- [x] PREPARATEUR (vue ACTIF) — Input type=date 'Date' (preparateurDate) : envoie date_debut=date_fin ; + recherche ; + bouton 'Reinitialiser' si l'un des deux est rempli
- [x] PREPARATEUR — segmentation client-side par onglet : 'A preparer' garde les commandes dont livraison_zone !== 'RECUPERATION', 'Recuperations' garde livraison_zone === 'RECUPERATION'
- [x] LIVREUR (vue ACTIF) — Select 'Statut' limite a LIVREUR_STATUT_ACTIF : 'Tous les statuts' (ALL), 'En preparation', 'A recuperer' (= valeur PRETE, libelle metier), 'En livraison' ; envoie `statut`
- [x] LIVREUR (vue ACTIF) — Input type=date 'Date' (livreurDate) : envoie date_debut=date_fin ; + recherche ; + bouton 'Reinitialiser' si statut!=='ALL' || date || recherche
- [x] PREPARATEUR & LIVREUR (vue HISTORIQUE) — DateTimeInput 'Du' (historiqueFrom) et 'Au' (historiqueTo) convertis en ISO via new Date(...).toISOString() et envoyes en date_from/date_to ; Select 'Statut' avec HISTORIQUE_STATUT_FILTERS (Tous les statuts, Livrees, Retours, Annulees, En livraison, A recuperer, En preparation, Nouvelles) ; bouton 'Reinitialiser' si l'un des trois est renseigne. Le param historique=1 est toujours joint
- [x] AUCUNE pagination, AUCUN tri utilisateur, AUCUN export : la liste complete renvoyee par l'API est affichee telle quelle (ordre du serveur ; '-date_commande' cote backend pour l'historique)
- [x] userLoading : le premier fetchOrders n'est declenche qu'une fois useCurrentUser resolu (useEffect sur [userLoading, fetchOrders]) — avant, `loading` vaut true et le skeleton est affiche
- [x] Loading liste : `loading===true` -> <Skeleton className="h-64 w-full" /> dans la Card (padding 6). fetchOrders(true) (temps reel, apres action, apres edition) ne repasse PAS loading a true = refresh silencieux sans clignotement
- [x] Empty : searchableOrders.length===0 -> texte centre 'Aucune commande trouvee pour cette recherche.' (meme message qu'il y ait ou non une recherche active)
- [x] Erreur de chargement : catch -> toast.error(err.message || 'Erreur de chargement des commandes'), la liste garde son contenu precedent, pas d'ecran d'erreur dedie
- [x] Erreur d'action de statut : toast.error(err.message || 'Action impossible') — c'est ainsi que remontent les refus serveur (transition impossible, jour J, commande assignee a quelqu'un d'autre)
- [x] Disabled 'jour J' : IconAction disabled + libelle 'Disponible le {JJ/MM/AAAA}' pour preparateur/livreur sur une commande planifiee plus tard ; meme regle pour le bouton d'action dans le detail
- [x] Disabled soumission : boutons 'Creer la commande'/'Enregistrer'/'Supprimer'/'Annuler la commande' passent en libelle de progression ('Creation…', 'Enregistrement...', 'Suppression...', 'Annulation...') et disabled pendant l'appel
- [x] Disabled 'Assigner' tant qu'aucun membre du staff n'est selectionne
- [x] Disabled option couleur si stock_actuel <= 0 dans le Select Couleur
- [x] Loading AssignStaffDialog : Skeleton h-10 ; Empty : 'Aucun {role} enregistre pour ce magasin.'
- [x] Loading autocomplete : 'Recherche…' ; Empty autocomplete : 'Aucun resultat pour cette selection.'
- [x] Aucun etat 'unauthorized' cote page : pas de guard de role ; un utilisateur non authentifie est redirige vers /login par le layout. Un role non prevu voit simplement une page en lecture seule sans action
- [x] Les listes de staff/zones/categories/types/marques echouent en silence (catch -> tableau vide), sans toast
- [x] Palette de badges de statut : NOUVELLE bg-slate-100/text-slate-800, EN_PREPARATION bg-amber-100/text-amber-800, PRETE bg-blue-100/text-blue-800, EN_LIVRAISON bg-purple-100/text-purple-800, LIVRE bg-green-100/text-green-800, RETOUR bg-red-100/text-red-800, ANNULEE bg-zinc-200/text-zinc-800. statutInfo() retombe sur NOUVELLE si le statut est inconnu
- [x] Format monetaire : Intl.NumberFormat('fr-MG') sur le nombre arrondi + ' Ar' (ex '1 250 000 Ar'). Toute valeur nulle/undefined donne '0 Ar'
- [x] Formats de date : colonne Date = JJ/MM HH:mm (sans annee) ; colonne Assigne a = JJ/MM HH:mm ; timeline et historique = JJ/MM/AAAA HH:mm ; libelle 'Disponible le' = JJ/MM/AAAA. TOUS en fuseau Indian/Antananarivo, quel que soit le fuseau de l'appareil ; fmtAppDate/fmtAppDateTime renvoient '—' si valeur absente/invalide
- [x] Toasts (sonner) : succes 'Commande {numero} → {libelle du nouveau statut}', 'Commande {numero} supprimee', 'Commande {numero} annulee', 'Commande creee', 'Commande creee et assignee', 'Commande mise a jour' ; erreurs listees dans les formulaires
- [x] Masquage financier livreur : dans le tableau, un mode_paiement 'AVANT' affiche 'Deja paye' en vert emeraude au lieu du montant ; dans le dialogue de confirmation, ligne verte 'A encaisser : Rien — deja paye' ; dans le detail, la ligne 'Total a payer' disparait totalement quand mode_paiement === 'AVANT' (pour tous les roles, pas seulement le livreur)
- [x] Masquage financier preparateur : colonne Total absente du tableau, showPrices=false dans OrderItemsEditor (pas de prix dans les suggestions, pas de champ Prix, pas de montant de ligne) et pas de recap Frais/Total dans le formulaire de creation
- [x] Lien telephone cliquable (tel:) uniquement dans la vue livreur, en bleu avec icone Phone
- [x] Photo de preparation : proposee uniquement au passage a PRETE, apercu 80x80 avant envoi, vignette 64x64 + lien 'Voir / telecharger la photo' dans l'historique detaille
- [x] Le libelle metier 'A recuperer' remplace 'Prete' dans le filtre statut du livreur (meme valeur PRETE cote API)
- [x] Le libelle 'Recuperee par le client' remplace 'Livree' pour une commande de zone RECUPERATION au statut PRETE (gerant)
- [x] Rangee d'entete responsive : flex-col sur mobile, flex-row a partir de sm ; page en p-4 sm:p-6 space-y-6
- [x] Zone de tableau scrollable horizontalement (overflow-x-auto) — indispensable pour le portage mobile ou il faudra probablement une liste de cartes
- [x] Le Select d'action gerant recalcule gerantActionOptions(order) 3 fois par ligne (rendu + onValueChange + map) — comportement identique, simple duplication
- [x] La colonne 'Assigne a' affiche l'heure de preparation issue de status_history (premiere occurrence de EN_PREPARATION) et, pour le livreur, 'Livre le' si LIVRE sinon 'Prevu le' + date_commande

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Temps réel : les providers commandes relancent le rechargement silencieux à chaque événement WebSocket sans le débounce de 400 ms du web (même résultat, quelques requêtes de plus en rafale).

### `/bilan`  —  VERIFIED

Écran Flutter : `features/tournee/bilan_screen.dart`  
Fonctionnalités à garantir : 44

- [x] Titre h1 'Bilan du jour' + sous-titre 'Livraisons effectuees et retours d'aujourd'hui — voir le ticket recapitulatif.'
- [x] Bouton de rafraichissement (Button variant='outline' size='icon', icone RefreshCw h-4 w-4) en haut a droite -> fetchOrders() en mode non silencieux (affiche les skeletons). Pas de libelle texte, pas d'etat disabled, pas de spinner sur l'icone
- [x] CARTE 'Livraisons effectuees (N)' — titre avec icone PackageCheck h-4 w-4 et le compteur livrees.length entre parentheses; contenu = tableau des commandes au statut LIVRE
- [x] CARTE 'Retours (N)' — titre avec icone Undo2 h-4 w-4 text-red-600 et retours.length; CardDescription 'Colis rapportes — rien n'a ete encaisse, ces montants ne sont pas comptes dans le total du ticket.'; contenu = tableau des commandes au statut RETOUR
- [x] TABLEAU (composant interne OrdersTable, reutilise a l'identique pour les deux cartes) enveloppe dans un div overflow-x-auto, 10 colonnes, pas d'en-tete cliquable, pas de selection, pas d'action de ligne, pas de clic sur ligne
- [x] Colonne 'N° commande' = order.numero (font-medium, align-top)
- [x] Colonne 'Type' = premier article uniquement: (order.items||[])[0]?.category_name, sinon '-'
- [x] Colonne 'Sous-type' = premier article uniquement: firstItem?.type_name, sinon '-'
- [x] Colonne 'Produit' = concatenation de TOUS les articles: items.map(it => `${it.reference_name}${it.couleur ? ` (${it.couleur})` : ''} x${it.quantite}`).join(', '), conteneur max-w-[220px]
- [x] Colonne 'Date' = order.date_commande formatee en toLocaleString('fr-FR') avec timeZone Indian/Antananarivo, day/month/hour/minute en 2 chiffres (PAS d'annee), classes whitespace-nowrap text-xs text-muted-foreground; '-' si absente
- [x] Colonne 'Client' = order.client_nom
- [x] Colonne 'Adresse' = order.adresse_livraison || '-', max-w-[180px] truncate
- [x] Colonne 'Prix' (alignee a droite) = fmt(prixProduit(order)) avec prixProduit = Number(total_a_payer||0) - Number(frais_livraison||0) — derive parce que le prix unitaire n'est jamais expose au livreur
- [x] Colonne 'Frais' (droite) = fmt(order.frais_livraison)
- [x] Colonne 'Argent' (droite, font-medium) = fmt(order.total_a_payer)
- [x] TICKET recapitulatif (colonne de droite, largeur fixe 300px en lg, sticky top-6): Card en font-mono, en-tete centre avec icone Receipt, titre 'BILAN DU JOUR' (tracking-wide) et la date du jour au format fr-FR dd/mm/yyyy en fuseau Indian/Antananarivo, bordures en pointilles (border-dashed)
- [x] TICKET — section 'LIVRAISONS EFFECTUEES': lignes 'Nombre' (count), 'Total produits' (somme des prixProduit), 'Total frais livraison' (somme des frais_livraison), puis separateur pointille et 'TOTAL ARGENT' en gras (somme des total_a_payer)
- [x] TICKET — section 'RETOURS (hors total ci-dessus)': memes 4 lignes, la derniere intitulee 'TOTAL NON ENCAISSE' en gras text-red-600
- [x] Separation stricte livrees / retours: sumTotals() est applique independamment aux deux listes, aucun cumul entre elles (regle metier explicite en commentaire)
- [x] Rafraichissement temps reel: useRealtimeRefresh(['order','order_status_history'], () => fetchOrders(true)) — mode SILENCIEUX (silent=true => pas de passage par setLoading, donc pas de skeleton, la table se met a jour en place), debounce 400 ms
- [x] Aucun filtre, aucune recherche, aucun tri, aucune pagination, aucun export, aucun raccourci clavier, aucun onglet, aucun modal
- [x] Layout en grid: 1 colonne mobile, 'lg:grid-cols-[1fr_300px]' desktop; padding p-4 sm:p-6, espacement space-y-6
- [x] Aucun formulaire, aucun champ de saisie sur cette page
- [x] Aucun modal, dialog, drawer, dropdown, popover ni menu contextuel sur cette page
- [x] Filtre implicite unique: la journee en cours au fuseau Indian/Antananarivo (appDayBounds), envoyee en date_from/date_to — non modifiable par l'utilisateur (pas de selecteur de date)
- [x] Repartition cote client par statut: livrees = orders.filter(o => o.statut_courant === 'LIVRE'), retours = orders.filter(o => o.statut_courant === 'RETOUR'). Les autres statuts eventuellement renvoyes (ANNULE, EN_LIVRAISON...) sont recuperes mais N'APPARAISSENT NULLE PART
- [x] Tri: aucun tri utilisateur, ordre serveur -date_commande (plus recent en premier)
- [x] Pagination: aucune
- [x] Loading initial: chaque carte affiche un Skeleton dans un conteneur p-6 — h-32 w-full pour 'Livraisons effectuees', h-24 w-full pour 'Retours'
- [x] Loading silencieux (declenche par WebSocket): aucun indicateur visuel, les donnees se remplacent
- [x] Empty livraisons: 'Aucune livraison effectuee aujourd'hui.' (text-sm muted, centre, py-10)
- [x] Empty retours: 'Aucun retour aujourd'hui.' (meme style)
- [x] Unauthorized: ecran plein 'Acces refuse' avec ShieldAlert rouge (voir roles) — le seul des deux pages a en avoir un
- [x] Erreur reseau: catch SILENCIEUX -> setOrders([]) sans toast ni message; l'utilisateur voit les deux etats vides et un ticket a 0 Ar, indiscernable d'une journee sans livraison (point a ameliorer au portage Flutter)
- [x] Le ticket est toujours rendu, meme pendant le loading (il affiche alors 0 / 0 Ar puisque orders est vide)
- [x] Aucun bouton disabled, aucun etat de soumission
- [x] Formatage monetaire fmt(n): new Intl.NumberFormat('fr-MG').format(Math.round(Number(n||0))) + ' Ar' — ARRONDI a l'entier, locale fr-MG (different de money() de la page caisse qui garde 2 decimales et utilise fr-FR)
- [x] Toutes les dates sont affichees en heure d'Antananarivo (APP_TIME_ZONE), pas en heure de l'appareil — regle explicite pour que le 'bilan du jour' ne bascule pas entre 00h et 03h
- [x] Le ticket est stylise comme un vrai ticket de caisse: font-mono, bordures en pointilles (border-dashed) entre sections, titres de section en text-xs font-semibold muted majuscules
- [x] Le TOTAL NON ENCAISSE des retours est en rouge pour marquer visuellement qu'il ne rentre pas en caisse
- [x] Le ticket est sticky (lg:sticky lg:top-6 self-start) — il reste visible pendant le defilement des tableaux
- [x] Le compteur de chaque carte est dans son titre, ex 'Livraisons effectuees (3)'
- [x] Les cellules du tableau sont align-top (les lignes multi-articles peuvent etre hautes), l'adresse est tronquee et le produit contraint a 220px
- [x] Mise a jour temps reel sur les evenements 'order' et 'order_status_history': des que le gerant/livreur change un statut ailleurs, le bilan se recalcule sans clic

### `/pickup`  —  VERIFIED

Écran Flutter : `features/pickup/pickup_screen.dart`  
Fonctionnalités à garantir : 37

- [x] En-tete : h1 text-2xl font-bold avec icone PackageCheck h-6 w-6 + texte 'Recuperation sur place'; sous-titre text-sm muted : 'Commandes pretes a retirer au comptoir (zone "Recuperation") — pas de livreur assigne.'
- [x] En-tete responsive : flex-col sur mobile, sm:flex-row sm:items-center justify-between gap-3.
- [x] Bouton refresh : Button variant='outline' size='icon' avec seule l'icone RefreshCw h-4 w-4 (pas de libelle). onClick -> fetchOrders() NON silencieux (reaffiche les skeletons). Il n'est ni disabled ni anime pendant le chargement (contrairement a /alerts).
- [x] Liste : grid gap-3, 1 colonne mobile, sm:grid-cols-2. Une Card par commande, key=order.id.
- [x] Carte commande — bloc haut : order.numero en font-semibold, order.client_nom en text-sm muted, et a droite un Badge className='bg-blue-100 text-blue-800' libelle 'Prete' (badge statique, toutes les commandes de cette page sont PRETE).
- [x] Carte commande — lien telephone : <a href={`tel:${order.telephone}`}> avec icone Phone h-3.5 w-3.5, classes text-sm text-blue-600 hover:underline w-fit. Declenche l'appel telephonique natif. (En Flutter : url_launcher tel:).
- [x] Carte commande — liste des articles : (order.items || []).map(it => `${it.reference_name} (${it.couleur}) x${it.quantite}`).join(', ') dans un div text-sm muted. La couleur est TOUJOURS affichee entre parentheses meme quand elle vaut 'Standard'. Aucun prix unitaire affiche.
- [x] Carte commande — pied : bordure haute (border-t pt-3), a gauche le total en text-sm font-semibold, a droite le bouton d'action.
- [x] Bouton d'action par carte : Button size='sm' avec icone PackageCheck h-4 w-4 mr-1, libelle 'Marquer comme recuperee'. Il OUVRE la modale (setPickupTarget(order)) — il ne declenche pas directement l'API.
- [x] Ce bouton est disabled={confirming === order.id} et son libelle devient 'Confirmation...' pendant l'appel API.
- [x] Aucun bouton d'annulation de commande, aucun detail/expansion, aucun lien vers la fiche commande, aucun menu contextuel, aucune selection multiple.
- [x] Aucun onglet, aucun switch, aucun toggle.
- [x] Rafraichissement temps reel : useRealtimeRefresh(['order','order_status_history'], () => fetchOrders(true)) — refetch silencieux quand un evenement WebSocket order/order_status_history arrive (une commande passee PRETE par un preparateur apparait donc automatiquement dans la liste).
- [x] Dialog de confirmation de retrait (shadcn Dialog) : open={!!pickupTarget}, onOpenChange={(o) => !o && setPickupTarget(null)} (fermeture par Echap / clic exterieur autorisee, meme pendant l'envoi).
- [x] DialogTitle dynamique : 'Confirmer la recuperation de {pickupTarget?.numero} ?'
- [x] DialogDescription dynamique : 'La commande de {pickupTarget?.client_nom} sera marquee comme livree (recuperee sur place).'
- [x] DialogFooter — bouton 'Annuler' (variant='outline') : setPickupTarget(null), aucune API appelee.
- [x] DialogFooter — bouton 'Confirmer' (variant par defaut) : appelle confirmPickup(pickupTarget); disabled={confirming === pickupTarget?.id}; libelle 'Confirmation...' pendant l'appel.
- [x] Aucun champ de saisie dans cette modale (pas de note, pas de photo, pas de mot de passe).
- [x] Aucun filtre UI, aucune recherche, aucun tri, aucune pagination.
- [x] Le filtrage est fige cote requete : statut=PRETE ET livraison_zone=RECUPERATION.
- [x] L'ordre d'affichage est celui renvoye par l'API (aucun tri client).
- [x] loading (initial true) : 3 <Skeleton className='h-24 w-full' /> empiles dans un div space-y-3.
- [x] empty : Card avec CardContent 'py-16 text-center text-sm text-muted-foreground' contenant 'Aucune commande prete a recuperer pour le moment.'
- [x] unauthorized : ecran plein remplacant tout — Card > CardContent flex-col items-center justify-center py-20 text-center, icone ShieldAlert h-12 w-12 text-red-500 mb-4, h2 text-xl font-bold 'Acces refuse', paragraphe muted 'Cette page est reservee au gerant.'
- [x] error de chargement : toast.error(err.message || 'Erreur de chargement des commandes'); la liste conserve son etat precedent.
- [x] error d'action : toast.error(err.message || 'Action impossible'); la modale RESTE OUVERTE (setPickupTarget(null) n'est appele que dans le chemin succes).
- [x] success : toast.success(`Commande ${order.numero} recuperee`), fermeture de la modale, puis fetchOrders(true) silencieux (la carte disparait de la liste puisqu'elle n'est plus PRETE).
- [x] disabled : bouton carte + bouton Confirmer pendant confirming === order.id (state number|null, un seul a la fois).
- [x] Pas d'etat 'refresh en cours' visible sur le bouton icone.
- [x] Format monetaire local : fmt(n) = new Intl.NumberFormat('fr-MG').format(Math.round(Number(n || 0))) + ' Ar' — arrondi a l'entier, separateurs fr-MG, suffixe ' Ar'. Applique a order.total_a_payer.
- [x] Badge statut unique et statique : 'Prete' en bg-blue-100 text-blue-800.
- [x] Toasts sonner globaux : top-right, richColors (succes vert / erreur rouge), closeButton, expand, duree 5000 ms.
- [x] Conteneur : div p-4 sm:p-6 space-y-6 (padding reduit sur mobile — page pensee mobile/comptoir).
- [x] Le numero de telephone est cliquable : usage terrain evident (rappeler le client qui ne vient pas).
- [x] Temps reel : une commande passee 'Prete' par un preparateur apparait sans action de l'utilisateur (WebSocket /ws/data/, debounce 400 ms).
- [x] Aucune photo de preuve n'est demandee pour un retrait sur place (contrairement au flux livreur qui accepte une photo via changeStatus).

### `/sales`  —  VERIFIED

Écran Flutter : `router.dart (redirection vers /orders)`  
Fonctionnalités à garantir : 6

- [x] useEffect(() => { router.replace('/orders'); }, [router]) — redirection immediate au montage, avec replace (pas de push) : la page ne reste PAS dans l'historique de navigation, le bouton Retour ne la reaffiche pas.
- [x] return null — aucun rendu, aucun ecran de transition, aucun spinner, aucun message.
- [x] Portage Flutter : mapper la route /sales sur une redirection vers l'ecran Commandes (ou simplement ne pas creer l'ecran et rediriger toute deep-link /sales).
- [x] Aucun etat UI : ni loading, ni empty, ni error. Rendu = null pendant le tick de redirection.
- [x] Le commentaire en tete de fichier documente la regle metier : la vente sur place passe desormais par une commande en zone 'Recuperation' finalisee sur /pickup.
- [x] Il existe toujours un service compat djangoClient.sales.list() qui derive des lignes de vente a partir des Commandes au statut LIVRE (pour les analytics/rapports) — pas utilise par cette page.

## CATALOGUE & STOCK

### `/products`  —  VERIFIED

Écran Flutter : `features/catalog/catalog_screen.dart`  
Fonctionnalités à garantir : 116

- [x] Titre H1 'Catalogue produits' avec icône Package (h-6 w-6)
- [x] Sous-titre 'Catégorie → Sous-type → Marque → Référence → Couleur (§8 du cahier des charges).'
- [x] Bouton Rafraîchir : icône RefreshCw seule, carré 40x40 (h-10 w-10 p-0), variant outline — appelle fetchAll() en mode NON silencieux (affiche le skeleton). Visible pour TOUS les rôles
- [x] Bouton 'Exporter Excel' (icône Download, variant secondary) — isGerant uniquement ; disabled pendant l'export ; libellé devient 'Export...' pendant l'appel ; déclenche le téléchargement du blob via <a download> + URL.createObjectURL/revokeObjectURL ; nom de fichier issu du header Content-Disposition, fallback 'catalogue.xlsx'
- [x] Bouton 'Importer Excel' (icône Upload, variant secondary) — isGerant uniquement ; clique sur un <input type=file accept='.xlsx,.xls'> caché via une ref ; disabled pendant l'import ; libellé 'Import...' pendant ; l'input est vidé (e.target.value = '') dès la sélection pour permettre de re-choisir le même fichier
- [x] Bouton 'Paramètres' (icône Settings, variant outline) — isGerant — ouvre CatalogSettingsDialog
- [x] Bouton 'Modifier prix par sous-type' (icône DollarSign, variant outline) — isGerant — ouvre BulkPriceDialog (pré-rempli avec le filtre sous-type courant si != ALL)
- [x] Bouton 'Nouvelle commande' (icône ShoppingCart, fond slate-900/texte blanc, inversé en dark) — isGerant — ouvre ProductCreateOrderDialog
- [x] Bouton 'Nouvelle référence' (icône Plus, variant default) — isGerant — ouvre CreateReferenceDialog
- [x] Chargement initial parallèle (Promise.all) de 5 listes : références, catégories, sous-types, marques, couleurs
- [x] fetchAll(silent) : si silent=true, ne bascule pas `loading` (pas de skeleton) — utilisé par le rafraîchissement temps réel et par tous les callbacks onChanged/onCatalogChanged
- [x] Rafraîchissement temps réel : useRealtimeRefresh(['product_variant','stock_movement'], () => fetchAll(true)) — WebSocket via DataSyncContext, debounce 400 ms
- [x] TABLEAU — colonne 1 (w-12) : miniature photo 32x32 arrondie object-cover si ref.photo, sinon carré bordé bg-muted avec icône Package grisée
- [x] TABLEAU — colonne 'Sous-type' : ref.type_name
- [x] TABLEAU — colonne 'Marque' : ref.brand_name en font-medium
- [x] TABLEAU — colonne 'Référence' : ref.reference_name
- [x] TABLEAU — colonne 'Prix actuel' : fmt(ref.prix_achat) — AFFICHÉE UNIQUEMENT si isGerant (en-tête ET cellule conditionnés)
- [x] TABLEAU — colonne 'Prix de vente' : fmt(ref.prix_vente) — tous rôles
- [x] TABLEAU — colonne 'Marge' : fmt(prix_vente - (prix_achat||0)), texte vert si >= 0, rouge si < 0 — UNIQUEMENT si isGerant
- [x] TABLEAU — colonne 'Variantes' (max-w-60) : 'Aucune' en petit texte grisé si aucune variante, sinon des Badge outline en flex-wrap au format '<couleur> · <stock_actuel>' avec code couleur par seuil
- [x] TABLEAU — colonne 'Stock total' : somme des stock_actuel de toutes les variantes
- [x] TABLEAU — colonne 'Statut' : Badge calculé par stockInfo() = 'Rupture' (rouge) si UNE variante is_rupture, sinon 'Stock bas' (orange) si UNE variante is_stock_bas, sinon 'OK' (vert)
- [x] TABLEAU — colonne 'Actions' (alignée à droite) : si isGerant, bouton icône Pencil (ghost) qui ouvre le dialog de détail et bouton icône Trash2 rouge (ghost) qui ouvre la confirmation de suppression ; les deux font e.stopPropagation() pour ne pas déclencher le clic de ligne. Cellule VIDE pour un non-gérant
- [x] TABLEAU — ligne entière cliquable (cursor-pointer) : ouvre ProductDetailDialog sur la référence (pour tous les rôles, en lecture seule si non gérant)
- [x] Aucune pagination, aucun tri de colonne, aucune sélection multiple : l'ordre est celui renvoyé par l'API
- [x] Suppression d'une référence : DELETE puis toast 'Référence supprimée' + fetchAll() (non silencieux) ; en erreur toast err.message || 'Suppression impossible'
- [x] Import Excel : le fichier retourné par le serveur (avec colonnes Statut + Date par ligne) est automatiquement retéléchargé, puis fetchAll(), puis ouverture du dialog 'Résumé de l'import'
- [x] Import Excel : si errors_count > 0, toast.error '<n> ligne(s) en erreur — voir la colonne "Statut" du fichier téléchargé.' avec duration 10000 ms
- [x] Vérification IA post-import (best-effort) : si des références ont été créées, POST /api/ai/check-duplicates avec {newNames, existingNames} où existingNames = `${brand_name} ${reference_name}` de toutes les références déjà chargées ; le résultat alimente aiWarnings du dialog de revue ; en cas d'échec (Ollama indisponible) on passe simplement aiStatus à 'done' sans warning
- [x] ProductDetailDialog — Bouton 'Enregistrer les informations' (pleine largeur) : PUT de la référence puis PATCH FormData séparé si une photo a été choisie ; libellé 'Enregistrement…' pendant
- [x] ProductDetailDialog — Toggle Actif/Inactif : un seul bouton dont le libellé est 'Active' (variant default) ou 'Inactive' (variant outline), avec la mention 'Inactive = invisible dans la recherche de commande.' — isGerant uniquement
- [x] ProductDetailDialog — Colonne droite 'Variantes (<n>)' + 'Stock total : <somme>' ; liste scrollable (max-h-64) de cartes couleur affichant 'Stock: X · Seuil: Y'
- [x] ProductDetailDialog — Par variante (si canEdit) : bouton 'Ajuster' (ouvre AdjustStockDialog) et bouton icône Trash2 rouge (ouvre la confirmation de suppression de variante)
- [x] ProductDetailDialog — Bloc 'Ajouter une couleur' (si canEdit) : select Couleur (uniquement les couleurs NON déjà utilisées par cette référence), Stock initial, Seuil d'alerte, bouton 'Ajouter' (disabled tant qu'aucune couleur choisie)
- [x] ProductDetailDialog — Création rapide de couleur : champ 'Nouvelle couleur (ex: Bleu)' + bouton 'Créer' — POST /catalog/colors/, toast 'Couleur créée', vide le champ, rafraîchit le catalogue et présélectionne la couleur créée
- [x] CreateReferenceDialog — Création rapide de sous-type : champ 'Nouveau sous-type (ex: MAGSAFE)' + bouton 'Créer' (visible seulement après choix d'une catégorie) — POST /catalog/types/, présélectionne le sous-type créé
- [x] CreateReferenceDialog — Deux modes de stock selon `avec_couleurs` de la catégorie choisie : liste de variantes couleur, OU un unique bloc 'Stock' (quantité + seuil) qui créera une variante nommée 'Standard'
- [x] CreateReferenceDialog — Chips de variantes ajoutées : '<couleur> · <stock> (seuil <seuil>)' avec bouton × pour retirer ; compteur '<n> couleur(s) · <total> unité(s)'
- [x] AdjustStockDialog — Bascule Entrée/Sortie : deux boutons pleine largeur (ArrowUpCircle 'Entrée' / ArrowDownCircle 'Sortie'), celui actif en variant default
- [x] AdjustStockDialog — Bandeau récapitulatif : Badge couleur + 'Stock actuel : <n> · Seuil d'alerte : <n>'
- [x] CatalogSettingsDialog — 3 onglets : Marques (défaut), Catégories, Couleurs
- [x] CatalogSettingsDialog / Marques — 14 boutons de marques suggérées en un clic (Samsung, iPhone, Huawei, Redmi, Xiaomi, Tecno, Infinix, Itel, Oppo, Realme, Google Pixel, Poco, Vivo, Honor) : si la marque existe déjà (comparaison insensible à la casse) le bouton est variant secondary + icône Check + disabled ; sinon variant outline + icône Plus ; disabled aussi pendant l'ajout en cours
- [x] CatalogSettingsDialog / Marques — Liste scrollable (max-h-64) de CrudRow : renommer en place (Pencil -> Input + OK/Annuler) et supprimer (Trash2)
- [x] CatalogSettingsDialog / Marques — Champ 'Nouvelle marque' + bouton 'Ajouter' (Plus)
- [x] CatalogSettingsDialog / Catégories — Bloc 'Nouvelle catégorie' : nom + bouton 'Ajouter' (FolderPlus) + bascule 'Avec couleurs' (Palette) / 'Sans couleurs' + texte explicatif
- [x] CatalogSettingsDialog / Catégories — Une carte par catégorie : icône Tag, nom, Badge cliquable 'Avec couleurs'/'Sans couleurs' qui bascule immédiatement le flag (PATCH, sans toast de succès), Pencil (renommer en place), Trash2 (supprimer)
- [x] CatalogSettingsDialog / Catégories — Sous-liste indentée des sous-types de la catégorie : renommage en place, suppression, et champ 'Nouveau sous-type' + bouton 'Ajouter' propre à chaque catégorie (état stocké dans un Record<categoryId, string>)
- [x] CatalogSettingsDialog / Couleurs — Liste CrudRow (renommer/supprimer) + champ 'Nouvelle couleur (ex: Bleu)' + bouton 'Ajouter'
- [x] CatalogSettingsDialog — Bouton 'Fermer' en pied de dialog
- [x] BulkPriceDialog — Compteur dynamique '<n> référence(s) concernée(s)' calculé côté client sur les références du sous-type sélectionné
- [x] BulkPriceDialog — Bouton 'Appliquer' disabled si submitting || aucun sous-type || matchCount === 0 ; libellé 'Mise à jour...' pendant
- [x] ProductCreateOrderDialog — Bascule 'Type de commande' : bouton 'À livrer' (Truck, force zone=ZONE1) / 'Récupération sur place' (Package, force zone=RECUPERATION) — masquée pour un préparateur (texte explicatif à la place)
- [x] ProductCreateOrderDialog — Récapitulatif Frais de livraison + Total à payer (masqué pour un préparateur)
- [x] ProductOrderItemsEditor — Panier local : liste des lignes ajoutées avec '<marque référence> (<couleur>) x<qté>', montant de ligne et bouton Trash2 pour retirer
- [x] ProductOrderItemsEditor — Chips de filtres actifs (catégorie/sous-type/marque) avec × pour les retirer individuellement
- [x] ProductOrderItemsEditor — Recherche par autocomplétion de référence avec dropdown de suggestions
- [x] FORMULAIRE 'Nouvelle référence produit' (CreateReferenceDialog, max-w-xl, scroll 90vh, gérant seulement). CHAMPS : Catégorie (Select obligatoire pour débloquer le sous-type ; changer la catégorie remet typeId à '') ; Marque (Select) ; Référence (modèle) (Input texte, placeholder 'Ex: A16, S25 Ultra') ; Sous-type (Select filtré sur la catégorie, affiché seulement si une catégorie est choisie) + création rapide (Input 'Nouveau sous-type (ex: MAGSAFE)' + bouton 'Créer' — ne fait rien si pas de catégorie ou nom vide, toast 'Sous-type créé' puis présélection) ; Prix actuel (Ar) (Input number, placeholder '0') ; Prix de vente (Ar) (Input number) ; Photo (optionnel) (Input file accept='image/*' avec aperçu 96x96 via URL.createObjectURL) ; SI catégorie avec couleurs : sous-formulaire de variante = Couleur (Select sur TOUTES les couleurs), Nombre (Input number min 0, placeholder '0'), Seuil d'alerte (Input number min 0, placeholder '1'), bouton 'Ajouter' (disabled tant qu'aucune couleur sélectionnée) qui empile la variante localement ; SI catégorie sans couleurs : Quantité en stock (number min 0, défaut vide -> 0) + Seuil d'alerte (number min 0, valeur initiale '1'). VALIDATIONS : addVariant refuse un doublon de couleur -> toast.error 'Cette couleur est déjà dans la liste' ; submit exige typeId && brandId && referenceName.trim() && prixVente sinon toast.error 'Tous les champs sont requis'. AFFICHAGE CALCULÉ : 'Marge estimée : <fmt(prix_vente - prix_achat)> / unité' en vert si >= 0 sinon rouge, affiché dès que les deux prix sont saisis. SOUMISSION : POST référence -> (si photo) PATCH FormData photo -> boucle séquentielle de POST /catalog/variants/ (soit les variantes saisies, soit une unique variante 'Standard' pour une catégorie sans couleurs) -> toast.success 'Référence créée' -> onCreated() qui ferme le dialog et relance fetchAll() non silencieux. ERREUR : toast.error(err.message || 'Erreur lors de la création'). Bouton 'Créer la référence' -> libellé 'Création…' + disabled pendant. Bouton 'Annuler' ferme sans confirmation. RESET : tous les champs sont réinitialisés à chaque ouverture (useEffect sur `open`).
- [x] FORMULAIRE 'Détail / modification de référence' (ProductDetailDialog, max-w-4xl, 2 colonnes, scroll 90vh, ouvert par clic de ligne ou bouton Pencil). CHAMPS COLONNE GAUCHE : Catégorie (Select, disabled si !canEdit ; changer la catégorie vide le sous-type) ; Sous-type (Select — liste filtrée sur la catégorie si une catégorie est déterminée, sinon tous les types) ; Marque (Select) ; Référence (modèle) (Input texte) ; Prix actuel (Ar) (Input number — AFFICHÉ UNIQUEMENT si canEdit) ; Prix de vente (Ar) (Input number, toujours affiché mais disabled si !canEdit) ; Photo (aperçu 64x64 ou placeholder Package + Input file accept='image/*' seulement si canEdit) ; Toggle Active/Inactive (canEdit). VALIDATION : submit exige referenceName.trim() && prixVente sinon toast.error 'Champs requis manquants' ; prix_achat vide est envoyé comme 0. AFFICHAGE CALCULÉ : 'Marge estimée : <fmt> / unité' vert/rouge (canEdit seulement). SOUMISSION : PUT /catalog/references/{id}/ puis PATCH FormData photo si nouvelle photo -> toast.success 'Référence mise à jour' -> onChanged() (fetchAll silencieux) -> fermeture du dialog. ERREUR : toast.error(err.message || 'Erreur lors de la mise à jour'). PRÉ-REMPLISSAGE : useEffect sur [reference, types] remet tous les champs depuis l'objet référence (catégorie déduite en cherchant le type courant dans la liste des types) et remet à zéro les champs du sous-formulaire variante.
- [x] SOUS-FORMULAIRE 'Ajouter une couleur' (dans ProductDetailDialog, canEdit seulement). CHAMPS : Couleur (Select ne listant QUE les couleurs non déjà utilisées par cette référence) ; Stock initial (number, placeholder '0', défaut 0) ; Seuil d'alerte (number, placeholder '1', défaut 1). VALIDATION : bouton 'Ajouter' disabled sans couleur ; addVariant retoaste 'Choisissez une couleur' si l'id ne correspond à aucune couleur. SOUMISSION : POST /catalog/variants/ avec {product_reference, couleur: <nom de la couleur, pas l'id>, stock_actuel, seuil_alerte} -> toast.success 'Variante ajoutée' -> reset des 3 champs -> onChanged(). ERREUR : toast.error(err.message || 'Erreur').
- [x] SOUS-FORMULAIRE 'Créer une couleur à la volée' (dans ProductDetailDialog). CHAMP : Input 'Nouvelle couleur (ex: Bleu)' (h-8 text-xs) + bouton 'Créer'. VALIDATION : ne fait rien si vide/espaces. SOUMISSION : POST /catalog/colors/ -> toast 'Couleur créée' -> vide le champ -> onCatalogChanged() (fetchAll silencieux) -> présélectionne l'id de la couleur créée dans le Select de variante.
- [x] FORMULAIRE 'Ajuster le stock' (AdjustStockDialog, ouvert depuis une variante). En-tête : 'Ajuster le stock — <brand_name> <reference_name>' + description '§7.4 : entrée/sortie manuelle réservée au gérant'. Bandeau : Badge couleur + 'Stock actuel : <n> · Seuil d'alerte : <n>'. CHAMPS : Type (deux boutons exclusifs Entrée/Sortie, valeur par défaut 'ENTREE') ; Quantité (Input number min=1, placeholder 'Stock actuel : <n>') ; Note (optionnel) (Input texte, placeholder 'Ex: correction inventaire'). VALIDATION : quantité vide ou < 1 -> toast.error 'Quantité requise'. Aucun contrôle client que la sortie ne dépasse pas le stock (laissé au serveur). SOUMISSION : POST /catalog/variants/{id}/adjust/ {type, quantite, note} -> toast.success 'Stock ajusté' -> onAdjusted() qui ferme le dialog et déclenche onChanged(). ERREUR : toast.error(err.message || 'Erreur'). Bouton 'Confirmer' -> 'Enregistrement…' + disabled ; bouton 'Annuler' ferme. RESET : les 3 champs sont réinitialisés à chaque changement de variante (useEffect sur `variant`).
- [x] FORMULAIRE 'Modifier le prix par sous-type' (BulkPriceDialog, max-w-md, gérant). CHAMPS : Sous-type (Select sur TOUS les sous-types, toutes catégories confondues ; pré-rempli avec le filtre sous-type de la page si != ALL) ; Nouveau prix actuel (Input number min 0, placeholder 'Laisser vide = inchangé') ; Nouveau prix de vente (idem). VALIDATIONS : pas de sous-type -> toast.error 'Choisissez un sous-type' ; aucun des deux prix renseigné -> toast.error 'Indiquez au moins un prix à modifier' ; bouton 'Appliquer' disabled si submitting || !typeId || matchCount === 0. SOUMISSION : POST /catalog/references/bulk-update-price/ avec type_id + seulement les prix renseignés -> toast.success '<res.updated> référence(s) mise(s) à jour' -> onDone() qui ferme et relance fetchAll(true). ERREUR : toast.error(err.message || 'Erreur lors de la mise à jour groupée'). RESET à chaque ouverture (useEffect sur [open, defaultTypeId]).
- [x] FORMULAIRE 'Nouvelle commande' (ProductCreateOrderDialog, max-w-2xl, scroll 90vh, monté seulement si isGerant). CHAMPS DANS L'ORDRE : bloc panier ProductOrderItemsEditor ; Type de commande (2 boutons 'À livrer' -> zone ZONE1 / 'Récupération sur place' -> RECUPERATION ; remplacé pour un préparateur par le texte 'Retrait sur place uniquement — la commande apparaîtra dans "Récupérations" une fois prête, à valider comme livrée au comptoir par le gérant.') ; Date et heure de la commande (composant DateTimeInput = input date + input time séparés, valeur format YYYY-MM-DDTHH:mm, initialisée à maintenant, hint 'Vide = maintenant.') ; Préparateur (Select, placeholder 'Assigner plus tard', liste GET available-staff PREPARATEUR — masqué pour un préparateur) ; Livreur (Select, placeholder 'Assigner plus tard', liste rechargée à chaque changement de date) ; SI zone != RECUPERATION : Zone de livraison (Select des zones hors RECUPERATION) + Adresse de livraison (Input, placeholder 'Ex: Lot II M 45 Antanimena, Antananarivo') + Paiement (Select 'Paiement avant la livraison' / 'Paiement à la livraison', défaut LIVRAISON) ; Nom client (Input, placeholder 'Rakoto Jean') ; Téléphone (Input, valeur initiale '+261', placeholder '+261340000000') ; Note pour le préparateur (Textarea, libellé 'Note (optionnel)' pour un préparateur) ; Note pour le livreur (Textarea, affiché seulement si !isPreparateur && zone != RECUPERATION). VALIDATIONS SÉQUENTIELLES : nom client vide -> toast.error 'Nom du client requis' ; téléphone ne matchant pas /^\+261\d{9}$/ -> toast.error 'Téléphone au format +261XXXXXXXXX' ; panier vide -> toast.error 'Ajoutez au moins un article'. SOUMISSION : POST /orders/ (note_livreur forcée à '' si zone RECUPERATION ; date convertie en ISO) puis, si renseignés, POST assign-preparateur et POST assign-livreur SÉPARÉMENT, chacun dans son try/catch : un échec d'assignation produit un toast.error 'Commande créée, mais l'assignation du préparateur/livreur a échoué : <msg> (à assigner depuis le tableau).' ; toast.success 'Commande créée et assignée' ou 'Commande créée' seulement si aucune assignation n'a échoué. Puis onCreated() (ferme + fetchAll()) et fermeture. ERREUR globale : toast.error(err.message || 'Erreur lors de la création'). Bouton 'Créer la commande' -> 'Création…' + disabled. RESET complet à chaque ouverture.
- [x] SOUS-FORMULAIRE 'Ajouter un article' (ProductOrderItemsEditor). CHAMPS : Catégorie (Select — changer la catégorie remet le sous-type à null) ; Sous-type (Select filtré sur la catégorie si choisie) ; Marque (Select) ; Recherche (Input 'Rechercher une référence (ex: A15)' — affiche le libellé de la référence sélectionnée tant qu'elle l'est ; retaper efface la sélection et la couleur) ; puis, une fois une référence choisie : Couleur (Select listant '<couleur> (stock: <n>)', options avec stock <= 0 DISABLED), Quantité (number min 1, placeholder 'Ex: 1'), Prix (Ar) (Input readOnly + disabled affichant fmt(prix_vente), masqué si !showPrices), bouton 'Ajouter à la commande' pleine largeur. VALIDATIONS : pas de référence ou pas de couleur -> toast.error 'Sélectionnez une référence et une couleur' ; quantité vide ou < 1 -> toast.error 'Quantité invalide' ; quantité > stock_actuel -> toast.error 'Stock insuffisant (disponible: <n>)'. APRÈS AJOUT : la ligne est empilée dans le panier local (clé `${variantId}-${Date.now()}`) et tous les champs de saisie (query, suggestions, référence, couleur, quantité) sont vidés — les filtres catégorie/sous-type/marque, eux, sont conservés.
- [x] FORMULAIRES INLINE CRUD (CatalogSettingsDialog). Marque : Input 'Nouvelle marque' + bouton 'Ajouter' (ignore si vide) -> POST -> toast 'Marque ajoutée' + vide le champ ; renommage inline (Input autoFocus + OK/Annuler, ignore si vide) -> PATCH -> toast 'Marque renommée' ; suppression immédiate SANS confirmation -> DELETE -> toast 'Marque supprimée', erreur -> toast err.message || 'Suppression impossible (marque utilisée par des références)'. Couleur : mêmes patrons, toasts 'Couleur ajoutée' / 'Couleur renommée' / 'Couleur supprimée', erreur générique 'Erreur lors de la suppression'. Catégorie : Input 'Ex. Accessoires' + toggle Avec/Sans couleurs + bouton 'Ajouter' -> POST {nom, ordre: categories.length, avec_couleurs} -> toast 'Catégorie ajoutée', reset du champ ET du toggle à 'Avec couleurs' ; renommage inline -> toast 'Catégorie renommée' ; suppression sans confirmation, erreur -> 'Suppression impossible (des sous-types en dépendent encore)' ; bascule du Badge avec_couleurs -> PATCH sans toast de succès. Sous-type : Input 'Nouveau sous-type' par catégorie + bouton 'Ajouter' -> POST {category, nom} -> toast 'Sous-type ajouté' + vide seulement le champ de cette catégorie ; renommage inline -> 'Sous-type renommé' ; suppression sans confirmation, erreur -> 'Suppression impossible (des références en dépendent encore)'. AUCUN de ces formulaires n'affiche d'état de chargement ni ne disable son bouton pendant l'appel (sauf les boutons de marques suggérées).
- [x] ProductDetailDialog (Dialog max-w-4xl, max-h-90vh scrollable) — titre '<brand_name> <reference_name>' ; deux colonnes : identité/prix/photo/statut à gauche, gestion des variantes à droite ; ouvert par clic de ligne OU bouton Pencil ; en lecture seule si canEdit=false
- [x] AdjustStockDialog (Dialog imbriqué dans ProductDetailDialog) — ajustement de stock ENTREE/SORTIE d'une variante
- [x] Dialog de confirmation 'Supprimer la couleur <couleur> ?' (imbriqué) — description 'Cette variante et son historique de stock seront supprimés.' ; boutons Annuler / Supprimer (destructive)
- [x] Dialog de confirmation 'Supprimer <marque> <référence> ?' (niveau page) — description 'Cette référence et toutes ses variantes seront supprimées définitivement.' ; boutons Annuler / Supprimer (destructive)
- [x] Dialog 'Résumé de l'import' (max-w-lg) — deux cartes chiffrées Ajouté (vert) / Mis à jour (bleu) avec nombre de références et de couleurs ; listes 'Nouvelles références :' et 'Références mises à jour :' (line-clamp-3) ; ligne '<n> ligne(s) déjà traitée(s) ignorée(s).' ; ligne rouge '<n> ligne(s) en erreur — voir le fichier téléchargé.' ; encart 'Analyse IA (quasi-doublons)' ; TROIS boutons de pied : 'Annuler l'import' (destructive, appelle l'API cancel), 'Modifier' (outline, ferme et pré-remplit la recherche), 'Enregistrer' (ferme, aucun appel réseau) — tous disabled pendant l'annulation
- [x] CreateReferenceDialog (max-w-xl, scroll 90vh) — formulaire de création de référence + variantes
- [x] ProductCreateOrderDialog (max-w-2xl, scroll 90vh) — création d'une commande complète depuis le catalogue
- [x] CatalogSettingsDialog (max-w-2xl, max-h-85vh scrollable) — Tabs à 3 onglets Marques / Catégories / Couleurs, pied 'Fermer'
- [x] BulkPriceDialog (max-w-md) — modification groupée des prix par sous-type
- [x] Dropdown d'autocomplétion de référence (panneau absolu z-10, bordé, ombré, max-h-56 scrollable) sous le champ de recherche du panier — chaque suggestion est un bouton pleine largeur '<marque> <référence> (<sous-type>)' + prix à droite si showPrices
- [x] Selects (Radix) utilisés partout : filtres catégorie/sous-type/marque, catégorie/sous-type/marque/couleur des formulaires, préparateur, livreur, zone, mode de paiement
- [x] Édition inline (pas un dialog mais un mode) : CrudRow et les lignes catégorie/sous-type basculent en Input + OK/Annuler
- [x] AUCUNE confirmation avant suppression d'une marque, d'une couleur, d'une catégorie ou d'un sous-type — la suppression est immédiate au clic sur la corbeille
- [x] Recherche texte libre (placeholder 'Marque, référence...', icône loupe en overlay, hauteur h-11), débouncée à 250 ms via useDebouncedValue
- [x] Recherche multi-mots : la requête est découpée sur les espaces et CHAQUE mot doit se retrouver dans la concaténation minuscule de reference_name + brand_name + category_name + type_name + toutes les couleurs des variantes (ordre des mots indifférent — ex. 'samsung bleu', 'pixel 6 pro vert')
- [x] Filtre Catégorie (Select, valeur par défaut 'ALL' = 'Toutes les catégories') — le rapprochement se fait indirectement : la référence n'a pas de champ `category`, on passe par typeToCategory[String(ref.type)] reconstruit à partir de la liste des types
- [x] Changer la catégorie REMET automatiquement le filtre sous-type à 'ALL'
- [x] Filtre Sous-type (Select 'Tous les sous-types') — la liste des options est restreinte aux sous-types de la catégorie sélectionnée
- [x] Filtre Marque (Select 'Toutes les marques')
- [x] Tous les filtres et la recherche sont appliqués CÔTÉ CLIENT (useMemo sur le tableau `references` déjà chargé) — aucun paramètre n'est envoyé à l'API de liste
- [x] Aucun tri configurable, aucune pagination, aucun bouton 'Réinitialiser les filtres'
- [x] Autocomplétion serveur SÉPARÉE dans le panier de commande : GET /catalog/references/autocomplete/ avec q + type + brand + category, débouncée 250 ms, déclenchée dès qu'au moins un des quatre est renseigné ; vide les suggestions si tout est vide
- [x] Loading initial : <Skeleton className='h-64 w-full'> dans un padding 24px à la place du tableau (déclenché seulement par fetchAll(false))
- [x] Empty : paragraphe centré 'Aucune référence.' (py-12, texte muted) — même message quand la liste est vide et quand les filtres ne matchent rien (pas de distinction)
- [x] Erreur de chargement : uniquement un toast.error(err.message || 'Erreur de chargement du catalogue') — le tableau reste sur son état précédent (aucun écran d'erreur, aucun bouton Réessayer)
- [x] Unauthorized : aucun écran dédié — dégradation silencieuse en lecture seule (colonnes prix/marge et actions masquées, champs disabled)
- [x] Disabled : boutons Export/Import pendant l'opération ; 'Ajouter' de variante disabled sans couleur ; 'Appliquer' du bulk price disabled si pas de sous-type ou 0 référence concernée ; options de couleur disabled si stock <= 0 dans le panier ; boutons de marques suggérées disabled si déjà présentes ou en cours d'ajout ; champ Prix du panier readOnly+disabled
- [x] Submitting : libellés dynamiques 'Export...', 'Import...', 'Enregistrement…', 'Création…', 'Mise à jour...', 'Annulation...' avec bouton disabled
- [x] Autocomplétion : trois états dans le dropdown — 'Recherche…', 'Aucun résultat pour cette sélection.', ou la liste des suggestions
- [x] Revue IA post-import : 4 états — 'Analyse en cours…' (loading), 'Aucune nouvelle référence à vérifier.' (skipped), 'Aucun doublon suspect détecté.' (done sans warning), liste des correspondances suspectes (done avec warnings)
- [x] Empty states secondaires : 'Aucune couleur pour cette référence.', 'Aucune marque.', 'Aucune couleur.', 'Aucune catégorie.', 'Aucun sous-type.', 'Aucune' (colonne Variantes)
- [x] Aucune gestion d'état hors-ligne, aucun optimistic update : toute mutation est suivie d'un re-fetch complet
- [x] Format monétaire : Intl.NumberFormat('fr-MG') sur Math.round(Number(n||0)) suivi de ' Ar' — arrondi à l'entier, séparateur de milliers local, jamais de décimales
- [x] Badges de variante (colonne Variantes) — seuils FIXES indépendants du seuil_alerte : stock <= 0 = rouge (border-red-200 text-red-700 bg-red-50/50), stock <= 2 = bleu (blue-200/700/50), stock >= 3 = vert (green-200/700/50) ; variantes dark: red-500 / blue-500 / green-500
- [x] Badge Statut de ligne (calcul stockInfo, basé lui sur les flags serveur is_rupture / is_stock_bas) : 'Rupture' rouge (bg-red-100 text-red-800), 'Stock bas' orange (bg-orange-100 text-orange-800), 'OK' vert (bg-green-100 text-green-800), avec variantes dark
- [x] Colonne Marge colorée : vert si >= 0, rouge si < 0 ; même code couleur pour la ligne 'Marge estimée : … / unité' des formulaires
- [x] Toasts via sonner (toast.success / toast.error / toast.info) — aucun toast de succès sur le rafraîchissement ni sur la bascule 'avec couleurs'
- [x] Toast d'erreur d'import prolongé à 10 secondes (duration: 10000) car il renvoie vers le fichier téléchargé
- [x] Rafraîchissement temps réel : WebSocket sur les modèles product_variant et stock_movement, debounce 400 ms, refetch SILENCIEUX (pas de skeleton, pas de toast)
- [x] Après un import, le fichier annoté (colonnes Statut + Date par ligne) est retéléchargé automatiquement pour permettre de reprendre l'import plus tard : les lignes déjà marquées seront sautées côté serveur
- [x] Le bouton 'Modifier' de la revue d'import pré-remplit le champ de recherche avec LA PREMIÈRE référence touchée (new + updated confondues) et affiche toast.info 'Import conservé — recherche préremplie sur les références touchées, ajustez-la pour voir les autres.'
- [x] Aperçu photo instantané via URL.createObjectURL avant upload (16x16 rem dans le détail, 24x24 dans la création)
- [x] Placeholder photo : carré bordé bg-muted avec icône Package grisée (32px en tableau, 64px dans le détail)
- [x] Ligne de tableau entièrement cliquable avec cursor-pointer ; les boutons d'action stoppent la propagation
- [x] Encart d'avertissement orange (bg-orange-50, border-orange-200) dans BulkPriceDialog : 'Cette action est irréversible et modifiera directement <n> référence(s).' — affiché seulement si un sous-type est choisi, matchCount > 0 et au moins un prix saisi
- [x] Accord au pluriel géré à la main : 'référence(s) concernée(s)' via matchCount > 1
- [x] Barre d'outils responsive : flex-wrap, passage en colonne sous xl ; filtres en grid md:grid-cols-3 ; tableau dans un conteneur overflow-x-auto
- [x] Hauteurs normalisées : boutons de la barre d'outils h-10, champs de filtre h-11, champs inline de création rapide h-8 text-xs
- [x] Icônes lucide-react utilisées : Package, ShoppingCart, Truck, RefreshCw, Plus, Trash2, Pencil, Search, ArrowUpCircle, ArrowDownCircle, Tag, DollarSign, Download, Upload, Settings, Check, FolderPlus, Palette
- [x] Aucun raccourci clavier, aucun drag & drop, aucune animation personnalisée
- [x] Les couleurs sont référencées par leur NOM (string) dans les variantes, pas par leur id — le Select manipule l'id puis résout le nom avant l'appel API

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Vérification IA des quasi-doublons après import (route Next.js /api/ai/check-duplicates, Ollama côté serveur Next) : remplacée par une analyse locale équivalente (normalisation + distance d'édition), mêmes 4 états ; encart titré « Analyse des quasi-doublons ».
- « Nouvelle commande » ouvre l'écran partagé /orders/new (mêmes champs et validations) au lieu d'une fenêtre dans la page.
- Rafraîchissement temps réel branché sur ws/notifications/ (l'app n'a pas de client ws/data/) : une modification de stock sans notification ne recharge pas la liste d'elle-même (tirer pour rafraîchir / Actualiser).

### `/movements`  —  VERIFIED

Écran Flutter : `features/movements/movements_screen.dart`  
Fonctionnalités à garantir : 76

- [x] Titre h1 'Mouvements de stock' (text-2xl sm:text-3xl font-bold tracking-tight) + sous-titre muted 'Historique complet des mouvements de stock'
- [x] Bouton 'Actualiser' (variant=outline, size=sm, icone RefreshCw) => appelle fetchData() en mode NON silencieux (affiche les skeletons). disabled={loading}. L'icone recoit la classe 'animate-spin' tant que loading est true
- [x] Bouton 'Exporter XLSX' (variant=outline, size=sm, icone Download) => visible UNIQUEMENT si isAdmin (role==='admin'; un compte 'magasin' ne le voit pas). disabled={loading || filteredMovements.length === 0}
- [x] KPI Card 1 'Total sorties' — icone ArrowDown text-red-500 — valeur '{fmt(totalExits)} unites'. totalExits = somme des Math.abs(change) pour change<0 sur filteredMovements
- [x] KPI Card 2 'Total entrees' — icone TrendingUp text-green-500 — valeur '{fmt(totalEntries)} unites'. totalEntries = somme des change pour change>0 sur filteredMovements
- [x] KPI Card 3 'Nb mouvements' — icone Package text-blue-500 — valeur = filteredMovements.length (nombre BRUT, sans passer par fmt(), donc sans separateur de milliers contrairement aux deux autres)
- [x] Les 3 KPI sont calcules sur filteredMovements (= filtres du TABLEAU: recherche + startDate/endDate), PAS sur les filtres statistiques
- [x] Carte 'Filtre statistiques produits' avec sa propre plage de dates independante (statsStartDate/statsEndDate) + description dynamique 'Periode analysee : {statsPeriodLabel}'
- [x] Bouton 'Reinitialiser' (outline, sm) dans la carte stats => remet statsStartDate et statsEndDate a ''. disabled={!statsStartDate && !statsEndDate}
- [x] Carte 'Produits les plus vendus' (titre text-lg vert, icone TrendingUp) — description 'Sorties de stock sur la periode ({statsPeriodLabel})' — liste des 5 premiers produits tries par quantite sortie decroissante. Chaque ligne: nom du produit (font-medium text-sm) a gauche, Badge outline vert '{qty} unites' a droite, separateur border-b (retire sur le dernier via last:border-0)
- [x] Carte 'Produits sans mouvement' (titre text-lg orange, icone ArrowDown) — description 'Aucun mouvement sur la periode ({statsPeriodLabel})' — 5 produits du catalogue dont le `name` n'apparait dans aucun product_name des mouvements de la periode stats. Chaque ligne: nom + Badge outline orange '0 mouvement'
- [x] Intertitre 'Filtre mouvements par date' (div avec classes contradictoires: text-sm text-muted-foreground ET text-2xl font-bold — le text-2xl/font-bold gagne visuellement)
- [x] Tableau principal dans une Card: titre 'Historique des mouvements de stock', description '{filteredMovements.length} mouvement(s) affiche(s)'
- [x] Tableau principal enveloppe dans un div overflow-x-auto (scroll horizontal sur mobile)
- [x] Colonne 'Date' : formatDate(m.created_at) => toLocaleDateString('fr-FR', {year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit'}) => 'JJ/MM/AAAA HH:MM'
- [x] Colonne 'Reference' : m.product_reference || '-' (= reference_name cote API)
- [x] Colonne 'Produit' : ligne 1 en font-medium = m.product_name || `Produit #${m.product}` ; ligne 2 optionnelle en text-xs muted = '{brand} · {category}' recuperee via productsById[m.product], affichee seulement si brand OU category existe
- [x] Colonne 'Variante(s)' : parse de m.variant_label. 0 entree => '-' muted ; 1 entree => Badge outline (border-purple-200 text-sky-700 bg-purple-50/50) '{nom} {+}{qty}' ; >1 entree => Badge outline violet '{n} variantes' qui ouvre un HoverCard listant chaque variante dans son propre badge
- [x] Colonne 'Type' : Badge outline colore par getMovementTypeBadgeClass(m.movement_type || 'Mise a jour')
- [x] Colonne 'Quantite' (alignee a droite, font-medium) : Badge outline colore par getChangeBadgeClass(change, movement_type), texte '{signe +}{change}' (le - est deja porte par la valeur negative)
- [x] Colonne 'Fait par' : ligne 1 font-medium = m.changed_by_name || 'Systeme' ; ligne 2 text-xs muted = m.changed_by_username si present
- [x] Colonne 'Magasin' (conditionnelle isManager) : Badge outline bleu (border-blue-200 text-blue-700 bg-blue-50/50) avec m.magasin_name || '-'
- [x] Section 'Mouvements par jour' : h2 text-xl font-bold + un Popover calendrier a droite (flex-wrap)
- [x] Bouton declencheur du calendrier (outline, sm, icone CalendarIcon) : libelle 'Filtrer par jour' par defaut, ou la date selectionnee formatee 'j mois AAAA' en fr-FR quand startDate === endDate et non vide
- [x] Bouton X (variant=ghost, size=icon) affiche UNIQUEMENT quand startDate && startDate===endDate => vide startDate ET endDate (annule le filtre jour)
- [x] Sous-composant DailyMovementsTable : une Card par journee, triees par date decroissante (b.localeCompare(a))
- [x] Titre de chaque carte-jour : libelle 'Hier' si la date correspond a hier, sinon toLocaleDateString('fr-FR', {weekday:'long', day:'numeric', month:'long'}) avec classe capitalize + Badge outline '{n} mouvement(s)' + a droite (ml-auto, text-sm muted) le total '{somme des |change|} unites' formate fr-MG
- [x] Tableau par jour, colonnes : Heure | Produit | Type | Qte (droite) | Note | Utilisateur | Magasin (si isManager). Egalement dans un div overflow-x-auto
- [x] Cellule 'Heure' : toLocaleTimeString('fr-FR', {hour:'2-digit', minute:'2-digit'})
- [x] Cellule 'Produit' du tableau par jour : m.product_name || `Produit #${m.product}` — PAS de sous-ligne marque/categorie ici (contrairement au tableau principal)
- [x] Cellule 'Note' : m.note || '-' — la note n'est affichee QUE dans le tableau par jour, jamais dans le tableau principal
- [x] Export Excel (XLSX via la lib 'xlsx', XLSX.utils.json_to_sheet + book_append_sheet + writeFile) : feuille nommee 'Mouvements', fichier `mouvements_${YYYY-MM-DD}.xlsx` (date du jour en UTC via toISOString)
- [x] Colonnes du fichier Excel (dans cet ordre) : Date (formatee JJ/MM/AAAA HH:MM), Produit, Reference, Type (|| 'Mise a jour'), Quantite (valeur signee brute), 'Stock avant' (m.previous_quantity), 'Stock apres' (m.new_quantity), Note, Utilisateur (|| 'Systeme'), Email (m.changed_by_username), Magasin (m.magasin_name)
- [x] Aucune action d'ecriture : pas de creation, edition, suppression, ni ajustement de stock depuis cette page (lecture seule totale)
- [x] Aucun tri cliquable sur les en-tetes de colonne, aucune pagination, aucune selection de lignes, aucun menu contextuel par ligne
- [x] Formulaire 'Filtre statistiques produits' (non soumis, reactif a chaque frappe) — champs: (1) 'Date debut' Input type=date id=stats-start-date, value=statsStartDate, aucune validation, aucune borne min/max, classe w-full sm:max-w-[180px] ; (2) 'Date fin' Input type=date id=stats-end-date, value=statsEndDate, attribut min={statsStartDate || undefined} => le navigateur empeche de choisir une date de fin anterieure a la date de debut (SEULE validation de toute la page, purement native HTML) ; (3) Bouton 'Reinitialiser' disabled tant que les deux champs sont vides. Aucun message d'erreur, aucun toast, aucun appel API : le filtrage est 100% client sur le tableau statsFilteredMovements et se repercute instantanement sur les deux cartes de statistiques et sur le libelle 'Periode analysee'
- [x] Formulaire 'Filtre mouvements par date' (non soumis, reactif) — champs: (1) Input type=date sans Label, attribut title='Date debut', value=startDate, classe w-full sm:max-w-[160px] ; (2) Input type=date sans Label, attribut title='Date fin', value=endDate — AUCUN attribut min ici (contrairement au filtre stats), donc une date de fin < date de debut est acceptee et produit simplement 0 resultat ; (3) Input texte de recherche, placeholder 'Rechercher produit, reference, vendeur...', value=searchTerm, classe w-full sm:max-w-xs, valeur debouncee 250 ms avant filtrage. Aucune validation, aucun message d'erreur, aucun bouton de soumission, aucun bouton 'effacer' sur ces trois champs (le seul reset possible est le X du selecteur de jour, qui ne vide que les deux dates)
- [x] Selecteur de jour (Calendar dans un Popover) — mode='single', captionLayout='dropdown' (menus deroulants mois/annee), showOutsideDays par defaut. selected = new Date(startDate + 'T00:00:00') uniquement si startDate === endDate, sinon undefined. onSelect: si aucune date (deselection) => ne fait rien (early return, impossible de deselectionner par le calendrier) ; sinon convertit via toDateInputValue(d) (YYYY-MM-DD en heure LOCALE, pas UTC) et ecrit la MEME valeur dans startDate ET endDate. Cette action reecrit donc les deux champs date du filtre tableau et bascule DailyMovementsTable en mode hideToday=false
- [x] Popover 'Filtrer par jour' (components/ui/popover) — PopoverContent className='w-auto p-0' align='end', contient un Calendar react-day-picker mode single avec captionLayout='dropdown' (deroulants mois + annee). Selectionner un jour ferme implicitement le popover et fixe startDate=endDate. Pas de bouton valider/annuler
- [x] HoverCard sur la colonne 'Variante(s)' — declenche par le Badge '{n} variantes' (cursor-default) quand un mouvement porte plusieurs variantes. HoverCardContent className='w-auto p-2' affiche un flex column gap-1 avec un Badge violet par variante ('{nom} {+}{qty}'). Uniquement au survol (pas de clic, pas d'equivalent tactile)
- [x] AUCUN Dialog / AlertDialog / Drawer / Sheet / DropdownMenu / menu contextuel / confirmation sur cette page (page en lecture seule, rien a confirmer)
- [x] Recherche plein texte (debouncee 250 ms via useDebouncedValue) : match insensible a la casse (toLowerCase + includes) sur product_name, product_reference, changed_by_name, changed_by_username, magasin_name, note. Un terme vide laisse tout passer
- [x] Filtre plage de dates du tableau (startDate / endDate) : compare `m.created_at.split('T')[0]` (partie date de l'ISO, donc en UTC) au format string >= startDate et <= endDate. Comparaison lexicographique de chaines YYYY-MM-DD. Bornes inclusives des deux cotes. Une borne vide est ignoree
- [x] Filtre plage de dates des statistiques (statsStartDate / statsEndDate) : meme logique, applique a un tableau separe statsFilteredMovements qui n'est PAS impacte par la recherche texte
- [x] Selecteur de jour du calendrier : ecrit la meme date dans startDate et endDate => filtre le tableau principal, les 3 KPI, ET fait apparaitre la journee du jour dans 'Mouvements par jour' (hideToday devient false)
- [x] Regroupement par jour : cle = new Date(m.created_at).toISOString().split('T')[0] (jour UTC), construit a partir de filteredMovements (donc deja filtre par recherche + dates)
- [x] Tri : le tableau principal conserve l'ordre renvoye par l'API (ordering = ['-timestamp'] sur le modele StockMovement => du plus recent au plus ancien). AUCUN controle de tri dans l'UI. Le bloc par jour trie les cles de date en decroissant (b.localeCompare(a)) ; a l'interieur d'une journee l'ordre API est conserve
- [x] Top 5 'les plus vendus' : tri decroissant sur la quantite sortie cumulee puis slice(0,5)
- [x] 'Produits sans mouvement' : slice(0,5) SANS tri prealable (les 5 premiers dans l'ordre de l'API references)
- [x] AUCUNE pagination nulle part : tous les mouvements accessibles sont charges et rendus d'un coup (l'endpoint n'est pas pagine, ReadOnlyModelViewSet sans pagination_class)
- [x] loading initial (loading=true) : les 3 KPI affichent chacun un Skeleton (h-8 w-20 / h-8 w-28 / h-8 w-12), les 2 cartes de statistiques un Skeleton h-24 w-full, et le tableau principal 5 Skeleton h-12 w-full empiles (space-y-2)
- [x] loading : le bouton 'Actualiser' est disabled et son icone RefreshCw tourne (animate-spin) ; le bouton 'Exporter XLSX' est disabled
- [x] refresh silencieux (fetchData(true), declenche par le WebSocket) : loading n'est PAS remis a true, aucun skeleton, aucun spinner — les donnees se remplacent sans clignotement
- [x] empty tableau principal : une seule ligne, colSpan={isManager ? 8 : 7}, texte centre muted py-8 'Aucun mouvement enregistre'
- [x] empty 'Produits les plus vendus' : 'Aucune vente enregistree sur cette periode.'
- [x] empty 'Produits sans mouvement' : 'Tous les produits ont eu au moins un mouvement sur cette periode.'
- [x] empty 'Mouvements par jour' : 'Aucun mouvement pour cette periode.' (text-sm muted, centre, py-8) — s'affiche aussi dans le cas normal ou le seul jour present est aujourd'hui et hideToday=true
- [x] error : AUCUN etat d'erreur UI. Le catch de fetchData fait uniquement console.error('Error fetching data:', err) — pas de toast, pas de banniere, pas de bouton 'Reessayer'. Un echec au premier chargement laisse la page vide avec les messages 'empty' (indistinguable d'un vrai vide)
- [x] unauthorized : AUCUN rendu dedie. Si le token est absent, le layout (app) redirige vers /login. Si l'API renvoie 401 apres echec du refresh, on retombe sur le cas error silencieux
- [x] disabled : 'Actualiser' (loading), 'Exporter XLSX' (loading ou 0 mouvement filtre), 'Reinitialiser' des stats (aucune des deux dates renseignee)
- [x] success : uniquement via toasts sonner sur l'export Excel (pas de toast au chargement ni au refresh)
- [x] Toast (sonner) succes a l'export : `${filteredMovements.length} mouvement(s) exporte(s)`
- [x] Toast (sonner) erreur a l'export si 0 mouvement filtre : 'Aucun mouvement a exporter pour les filtres selectionnes' (garde-fou redondant, le bouton etant deja disabled dans ce cas)
- [x] Couleurs des badges de TYPE de mouvement (getMovementTypeBadgeClass, toutes en variant=outline + font-normal) : 'Reception fournisseur' => vert (border-green-200 text-green-700 bg-green-50/50) ; 'Retour de commande' => cyan ; 'Annulation de commande' => rouge ; 'Preparation de commande' => ambre ; 'Commande livree' => indigo ; 'Ajustement manuel' => ardoise/slate ; DEFAUT (tout autre libelle) => orange
- [x] Couleurs du badge QUANTITE (getChangeBadgeClass) : movement_type === 'Transfert' => bg-blue-50 text-blue-700 (prioritaire sur le signe) ; change > 0 => bg-green-50 text-green-700 ; change < 0 => bg-red-50 text-red-700 ; change === 0 => bg-orange-50 text-orange-700
- [x] Badge de variante : border-purple-200 bg-purple-50/50, avec une incoherence de couleur de texte — text-sky-700 quand il n'y a qu'UNE variante, text-purple-700 pour le badge '{n} variantes' et pour les badges dans le HoverCard
- [x] Badge magasin : outline border-blue-200 text-blue-700 bg-blue-50/50
- [x] Formatage des nombres : Intl.NumberFormat('fr-MG', { minimumFractionDigits: 0 }) + Math.round — separateur de milliers malgache/francais. Utilise pour totalExits et totalEntries et pour le total d'unites par journee (variante locale sans minimumFractionDigits dans DailyMovementsTable)
- [x] Rafraichissement temps reel : useRealtimeRefresh(['stock_movement','product_variant','order'], () => fetchData(true)) — WebSocket /ws/data/, debounce 400 ms sur les evenements rapproches, refetch SILENCIEUX (pas de skeleton). Le socket se reconnecte automatiquement toutes les 3 s si la fermeture n'est pas propre (code != 1000)
- [x] Le libelle de periode statistique affiche les dates BRUTES au format ISO YYYY-MM-DD ('du 2026-01-01 au 2026-01-31'), non localisees — contraste avec le reste de la page en fr-FR
- [x] Le libelle du bouton calendrier, lui, est localise fr-FR en 'j mois AAAA' (ex: '10 septembre 2026')
- [x] Le titre de carte-jour utilise la classe 'capitalize' pour majusculer le nom de jour retourne en minuscules par toLocaleDateString fr-FR
- [x] Responsive : header flex-col sur mobile / sm:flex-row ; KPI grid-cols-1 md:grid-cols-3 ; cartes stats grid-cols-1 md:grid-cols-2 ; filtres flex-col sm:flex-row flex-wrap ; inputs w-full sur mobile avec sm:max-w-[160px]/[180px]/xs ; les deux tableaux sont dans des conteneurs overflow-x-auto
- [x] Espacement general : conteneur p-6 space-y-6
- [x] Aucun raccourci clavier, aucune animation hors le spin de l'icone RefreshCw et les transitions par defaut de shadcn
- [x] La ligne 'Fait par'/'Utilisateur' retombe sur le libelle 'Systeme' quand aucun utilisateur n'est associe au mouvement (user null suite a on_delete=SET_NULL)

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Regroupement et filtre par jour métier d'Antananarivo (core/app_time) plutôt que par jour UTC du web.

### `/suppliers`  —  VERIFIED

Écran Flutter : `features/suppliers/*`  
Fonctionnalités à garantir : 64

- [x] En-tete: titre h1 'Fournisseurs' avec icone Truck (lucide, h-6 w-6) + sous-titre gris 'Coût de revient réel : marchandise + fret/import + douane (§7.6 du cahier des charges).'
- [x] Bouton icone 'Rafraichir' (variant=outline, size=icon, icone RefreshCw) -> appelle fetchOrders() en mode NON silencieux (affiche le skeleton)
- [x] Bouton principal '+ Commande fournisseur' (icone Plus) -> ouvre le dialog CreateSupplierOrderDialog (setCreateOpen(true))
- [x] Tableau des commandes dans une Card (CardContent p-0), wrapper overflow-x-auto (scroll horizontal sur mobile)
- [x] Colonne 'N°' : o.numero, en font-medium (format backend: SUP-<magasinId>-<YYYYMMDD>-<0001>, unique, non editable)
- [x] Colonne 'Description' : o.description, affiche '-' si vide/null
- [x] Colonne 'Coût total' : fmt(o.cout_total) -> nombre arrondi, format fr-MG, suffixe ' Ar'
- [x] Colonne 'Coût unitaire' : fmt(o.cout_unitaire) -> meme format
- [x] Colonne 'Statut' : Badge avec libelle traduit et couleur selon STATUT_COLOR
- [x] Colonne 'Action' (alignee a droite) : bouton 'Réceptionner' (size=sm, icone PackageCheck) affiche UNIQUEMENT si o.statut !== 'RECU'. Cellule vide si statut RECU.
- [x] Le bouton Réceptionner fait e.stopPropagation() pour ne pas declencher l'ouverture du dialog de detail de la ligne
- [x] Ligne de tableau entiere cliquable (className='cursor-pointer', onClick={() => setDetail(o)}) -> ouvre le dialog de detail
- [x] Aucun tri, aucun filtre, aucune recherche, aucune pagination sur cette liste — l'ordre vient du backend (Meta.ordering = ['-created_at'], donc la plus recente en premier)
- [x] Rafraichissement temps reel: useRealtimeRefresh(['supplier_order'], () => fetchOrders(true)) — refetch SILENCIEUX (sans skeleton) sur evenement WebSocket model='supplier_order', debounce 400 ms (lib/hooks/useRealtimeRefresh.ts + lib/contexts/DataSyncContext.tsx)
- [x] Action receive(order): POST receive -> toast succes -> fetchOrders() (NON silencieux, skeleton) -> setDetail(null) (ferme le detail s'il etait ouvert)
- [x] Aucune action de suppression/edition de commande (le backend n'autorise que get/post/head/options: http_method_names = ['get','post','head','options'])
- [x] FORMULAIRE 'Nouvelle commande fournisseur' (composant local CreateSupplierOrderDialog, meme fichier, lignes 170-348). Sous-titre du dialog: '§7.6 — coût de revient réel calculé automatiquement.'
- [x] Champ 'Description' — Textarea, state `description`, placeholder 'Ex: réappro coques Samsung — lot Chine mars'. Optionnel (backend: required=False, allow_blank=True, default=''). Aucune validation front.
- [x] Champ 'Prix fournisseur (Ar)' — Input type=number, state `prixFournisseur`, valeur initiale '0'. Aucun min, aucune validation front. Backend: DecimalField(max_digits=14, decimal_places=2, default=0).
- [x] Champ 'Fret/import (Ar)' — Input type=number, state `fretImport`, valeur initiale '0'. Aucune validation front.
- [x] Champ 'Douane (Ar)' — Input type=number, state `douane`, valeur initiale '0'. Aucune validation front. (les 3 champs prix sont dans une grid-cols-2, donc Douane occupe seule la 3e cellule)
- [x] SOUS-BLOC 'Ajouter une ligne' (encadre, arrondi, fond bg-muted/30) contenant 5 controles:
- [x] - Select 'Marque' (Label xs muted 'Marque', placeholder 'Marque') alimente par GET /catalog/brands/ ; onValueChange remet variantId a '' ; AUCUNE option 'Toutes' -> impossible de deselectionner une marque une fois choisie
- [x] - Select 'Catégorie' (placeholder 'Catégorie') alimente par GET /catalog/categories/ ; onValueChange remet variantId a '' ; AUCUNE option 'Toutes' -> non reinitialisable
- [x] - Input 'Rechercher' (Label xs 'Rechercher', placeholder 'Rechercher une référence ou couleur…'), state `variantSearch` — filtre CLIENT (lowercase, includes) sur le libelle '<brand_name> <reference_name> (<couleur>)'
- [x] - Select 'Couleur' (placeholder 'Couleur'), state `variantId` — liste plate de TOUTES les variantes des references chargees. Si aucun resultat: affiche un texte muted 'Aucun résultat' a la place des items
- [x] - Input 'Quantité' type=number min=1 placeholder 'Ex: 10', state `quantite`
- [x] - Bouton 'Ajouter' (type=button, variant=secondary, size=sm, icone Plus) -> addLine()
- [x] VALIDATIONS de addLine(): si !variantId -> toast.error('Choisissez une couleur') ; si Number(quantite) falsy ou < 1 -> toast.error('Quantité invalide') ; si l'option n'est pas retrouvee -> return silencieux. Succes: ajoute {key: `${variantId}-${Date.now()}`, variant_id, label, quantite} a `lines` puis vide variantId et quantite (les filtres marque/categorie/recherche restent).
- [x] LISTE DES LIGNES AJOUTEES (affichee seulement si lines.length > 0): une ligne par item, encadre arrondi, texte '<label> x<quantite>' a gauche + bouton icone ghost avec Trash2 rouge (text-red-500) a droite -> supprime par INDEX (setLines(prev => prev.filter((_, i) => i !== idx))). Les doublons de la meme variante sont autorises (cle unique via Date.now()).
- [x] RECAPITULATIF (bordure haute): 'Coût total (<totalQty> u.)' -> fmt(coutTotal) en font-medium ; 'Coût unitaire estimé' -> fmt(coutUnitaire) en font-medium. Calculs LOCAUX: totalQty = somme des quantites ; coutTotal = Number(prixFournisseur||0) + Number(fretImport||0) + Number(douane||0) ; coutUnitaire = totalQty > 0 ? coutTotal / totalQty : 0.
- [x] FOOTER: bouton 'Annuler' (variant=outline) -> onOpenChange(false) SANS reset (le reset se fait a la reouverture) ; bouton 'Créer' -> submit(), disabled={submitting}, libelle 'Création…' pendant l'envoi.
- [x] VALIDATION de submit(): si lines.length === 0 -> toast.error('Ajoutez au moins une ligne') et arret. Sinon POST /suppliers/orders/ avec {description, prix_fournisseur, fret_import, douane, lines: [{product_variant, quantite}]}.
- [x] APRES SOUMISSION OK: toast.success('Commande fournisseur créée') puis onCreated() -> setCreateOpen(false) + fetchOrders(). APRES ERREUR: toast.error(err.message || 'Erreur'), le dialog RESTE ouvert et les champs sont conserves.
- [x] RESET a l'ouverture (useEffect sur `open`): description='', prixFournisseur='0', fretImport='0', douane='0', lines=[], variantId='', quantite='', variantSearch='', filterBrandId='', filterCategoryId='' + rechargement des marques et categories.
- [x] ATTENTION: aucun champ 'magasin' n'est envoye. Le backend resolve_magasin_for_request() prend l'unique magasin accessible ; un admin avec PLUSIEURS magasins recoit une 400 'magasin_id: Ce champ est requis (plusieurs magasins accessibles).' affichee en toast. A prevoir en Flutter (selecteur de magasin).
- [x] Dialog 'Detail commande fournisseur' — ouvert au clic sur une ligne du tableau (open={!!detail}), fermeture via onOpenChange -> setDetail(null). Largeur max-w-lg. Titre: 'Commande fournisseur <numero>'. Description: detail.description (peut etre vide). Contenu: grille 2 colonnes avec 'Prix fournisseur' / 'Fret/import' / 'Douane' (chacun fmt()) ; ligne separee par bordure haute 'Coût total (<total_qty> u.)' en font-medium ; ligne 'Coût unitaire' ; section 'Lignes' listant chaque ligne '<reference_name> (<couleur>) x<quantite>' a gauche et 'Marge unitaire: <fmt(marge_unitaire)>' a droite (marge_unitaire = prix_vente de la reference - cout_unitaire_calcule, calcule cote backend). Footer conditionnel: bouton 'Réceptionner (entrée stock)' (icone PackageCheck) affiche UNIQUEMENT si detail.statut !== 'RECU'.
- [x] Dialog 'Nouvelle commande fournisseur' (CreateSupplierOrderDialog) — max-w-lg, max-h-[90vh], overflow-y-auto (scroll interne). Voir la section forms pour le detail complet.
- [x] Dropdowns (Select shadcn/Radix) dans le dialog de creation: 'Marque', 'Catégorie', 'Couleur' — 3 popovers de selection.
- [x] Aucun dialog de confirmation avant la reception: le clic sur 'Réceptionner' declenche immediatement l'appel API (irreversible cote backend: statut passe a RECU, mouvements de stock ENTREE crees).
- [x] Aucun filtre / tri / recherche / pagination sur la liste principale des commandes fournisseur.
- [x] Dans le dialog de creation uniquement: filtre Marque (envoye a l'API en query param `brand`), filtre Categorie (query param `category`), et recherche texte CLIENT sur le libelle des variantes (variantSearch, insensible a la casse, sur '<marque> <reference> (<couleur>)').
- [x] Le refetch des references se declenche a chaque changement de filterBrandId ou filterCategoryId (useEffect avec deps [open, filterBrandId, filterCategoryId]).
- [x] loading: skeleton `<Skeleton className='h-64 w-full' />` dans un padding p-6 tant que loading===true (uniquement au premier chargement et sur fetchOrders() non silencieux)
- [x] empty: texte centre gris 'Aucune commande fournisseur.' (py-12) quand orders.length === 0
- [x] error (chargement): toast.error(err.message || 'Erreur de chargement') — le tableau reste vide, pas d'ecran d'erreur dedie
- [x] error (reception): toast.error(err.message || 'Réception impossible') — ex: 'Cette commande fournisseur a déjà été reçue.'
- [x] error (creation): toast.error(err.message || 'Erreur'), dialog conserve
- [x] success (creation): toast.success('Commande fournisseur créée')
- [x] success (reception): toast.success('Commande <numero> reçue — stock mis à jour')
- [x] disabled: bouton 'Créer' disabled pendant submitting, libelle change en 'Création…'
- [x] unauthorized: NON gere cote page — un non-Gerant voit la page vide + toast d'erreur API (403). Pas d'ecran 'Acces refuse' comme sur /transfers.
- [x] refetch silencieux (temps reel WS): aucun indicateur visuel, la liste se met a jour toute seule
- [x] Format monetaire: `new Intl.NumberFormat('fr-MG').format(Math.round(Number(n||0))) + ' Ar'` — arrondi a l'entier, separateur de milliers fr-MG, suffixe ' Ar'. null/undefined/'' -> '0 Ar'.
- [x] Libelles de statut (STATUT_LABEL): BROUILLON -> 'Brouillon', COMMANDE -> 'Commandé', RECU -> 'Reçu'
- [x] Couleurs de badge (STATUT_COLOR): BROUILLON -> bg-slate-100 text-slate-800 (gris) ; COMMANDE -> bg-blue-100 text-blue-800 (bleu) ; RECU -> bg-green-100 text-green-800 (vert)
- [x] Statut inconnu -> Badge sans classe de couleur et libelle undefined (pas de fallback)
- [x] Toasts via sonner (bibliotheque `toast` de sonner): success / error uniquement sur cette page
- [x] Icones lucide: Truck (titre), Plus (creer/ajouter), Trash2 rouge (supprimer une ligne), Truck, PackageCheck (receptionner), RefreshCw (rafraichir)
- [x] Layout: p-4 sm:p-6, space-y-6 ; en-tete flex-col sur mobile / flex-row sm:items-center a partir de sm
- [x] Le curseur devient pointer sur chaque ligne du tableau pour signaler qu'elle est cliquable
- [x] Le dialog de detail affiche un snapshot de l'objet ligne (setDetail(o)) : il n'est pas re-fetche, donc il peut afficher des donnees perimees si un evenement WS met la liste a jour pendant qu'il est ouvert
- [x] Mise a jour temps reel debounce 400 ms; plusieurs evenements rapproches ne declenchent qu'un seul refetch

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Réception d'une commande fournisseur : confirmation « Réceptionner {numéro} ? » ajoutée avant l'appel (le web réceptionne dès le clic) — action irréversible sur mobile.

### `/transfers`  —  VERIFIED

Écran Flutter : `features/transfers/transfers_screen.dart`  
Fonctionnalités à garantir : 22

- [x] En-tete: h1 'Transfert de produits' (text-3xl, tracking-tight) avec icone ArrowLeftRight h-8 w-8 text-blue-600
- [x] Sous-titre: 'Choisissez un magasin source, puis sélectionnez les produits (et leurs variantes) à transférer vers un autre magasin.'
- [x] Barre 'Magasin source :' — une rangee de boutons (flex-wrap) un par magasin accessible; chaque bouton affiche le logo (img rond h-4 w-4 object-cover) ou l'icone Store si pas de logo, + le shop_name
- [x] Bouton magasin source SELECTIONNE: classes 'bg-primary/10 border-primary/30 font-medium' ; non selectionne: 'border-border' ; hover:bg-muted/50 sur tous
- [x] Selectionner un magasin source monte <TransferProductsPanel key={sourceStore.magasin_id} …> — le `key` force un REMOUNT complet (donc reset du panier, de la recherche, des quantites et de la destination) a chaque changement de source
- [x] onSuccess du panel: setSourceStoreId(null) (deselectionne la source, on revient a l'ecran d'invite) + fetchStores() (rechargement de la liste des magasins)
- [x] Aucun onglet, aucun switch, aucun menu contextuel sur cette page
- [x] Tout le reste des fonctionnalites (recherche produit, panier, destination, submit) est dans TransferProductsPanel — voir l'entree dediee ci-dessous
- [x] Cette page ne contient aucun formulaire propre; le formulaire de transfert (<form onSubmit={handleTransferSubmit}>) est integralement dans TransferProductsPanel.
- [x] Aucun dialog/modal sur la page /transfers (la version modale du meme flux existe via TransferProductsDialog, utilisee par /stores).
- [x] Aucun filtre sur la page elle-meme; la selection du magasin source se fait par boutons (pas de dropdown).
- [x] Les recherches (produits, magasin de destination) sont dans TransferProductsPanel.
- [x] loading: si userLoading || loading -> 3 Skeleton h-16 w-full empiles (p-6 space-y-4)
- [x] unauthorized: Card centree, icone ShieldAlert rouge, titre 'Accès refusé', texte 'Cette page est réservée aux administrateurs.' (py-20, texte centre)
- [x] empty (magasins): si stores.length === 0 -> texte gris 'Aucun magasin' a la place de la rangee de boutons
- [x] empty (aucune source choisie): zone flex-1 min-h-[300px] avec bordure en pointilles (border-dashed) et texte gris centre 'Sélectionnez un magasin source pour commencer.'
- [x] error (chargement magasins): toast.error('Erreur de chargement des magasins: ' + (err.message || err))
- [x] BUG A REPRODUIRE OU CORRIGER: pour un utilisateur NON admin, `loading` reste a true indefiniment (fetchStores n'est appele que si isAdmin, et rien d'autre ne fait setLoading(false)); la condition `if (userLoading || loading)` court-circuite donc l'ecran 'Accès refusé' — un non-admin voit un skeleton infini. En Flutter, prevoir setLoading(false) quand !isAdmin pour afficher reellement l'ecran d'acces refuse.
- [x] Layout pleine hauteur: h-full flex flex-col gap-4 p-6 — le panel occupe la hauteur restante (flex-1, min-h-0) avec des zones scrollables internes
- [x] Logos de magasin: <img> rond de 16px (h-4 w-4) en object-cover, fallback icone Store grise
- [x] La deselection du magasin source apres un transfert reussi (setSourceStoreId(null)) fait revenir a l'ecran d'invite 'Sélectionnez un magasin source pour commencer.'
- [x] Toasts sonner uniquement (pas d'alertes inline)

### `/transfers (composant partage TransferProductsPanel — coeur fonctionnel)`  —  VERIFIED

Écran Flutter : `features/transfers/transfers_screen.dart`  
Fonctionnalités à garantir : 53

- [x] Structure: <form> en flex-col; grille responsive grid-cols-1 lg:grid-cols-2 (colonne gauche = produits, colonne droite = panier + destination), puis un bouton submit pleine largeur en bas
- [x] PANNEAU GAUCHE 'Produits du magasin': Label + champ de recherche avec icone Search en overlay (placeholder 'Rechercher un produit...', pl-9), puis une ScrollArea flex-1
- [x] Filtre client des produits: p.name?.toLowerCase().includes(term) || p.reference?.toLowerCase().includes(term) — insensible a la casse, sur le nom OU la reference
- [x] PRODUIT SANS VARIANTE (variants vide): carte flex avec a gauche nom (truncate, text-sm font-medium) et ligne secondaire '<reference> · Stock : <initial_quantity>'; a droite un Input number (min=1, max=stock, largeur w-16 h-8, texte centre) + un bouton 'Sélectionner'
- [x] Le bouton 'Sélectionner' devient 'Sélectionné' avec icone Check et variant=secondary quand l'item est deja au panier; il est disabled si deja au panier OU si stock <= 0; l'Input de quantite est disabled dans les memes conditions
- [x] PRODUIT AVEC VARIANTES: en-tete cliquable (bouton pleine largeur) avec chevron ChevronRight (replie) / ChevronDown (deplie), nom du produit (truncate) et ligne secondaire '<reference> · <n> variante(s) · Stock : <totalStock>' (totalStock = somme des quantity des variantes)
- [x] Toggle d'expansion gere par un Set<number> expandedProductIds (toggleExpand) — plusieurs produits peuvent etre deplies simultanement; etat perdu au remount
- [x] Variantes triees par SIZE_ORDER = ['XS','S','M','L','XL','2XL','3XL','4XL'] (index -1 -> 99, donc inconnues a la fin). NOTE: le mapper backend->front met toujours size:'' donc ce tri est en pratique un no-op (vestige d'une app textile) — la couleur seule est utilisee
- [x] LIGNE DE VARIANTE (fond bg-muted/20, chaque ligne sur bg-background): libelle en font-semibold = formatVariantLabel(size, color) = les parties non vides jointes par ' / ', ou 'Standard' si vide; puis ' · Stock : <vStock>' en muted; a droite Input number (min=1, max=vStock, w-14 h-7, text-xs) + bouton icone (h-7 px-2) affichant Plus (ajouter) ou Check (deja au panier, variant=secondary, disabled)
- [x] Clamp des quantites saisies: getQtyInput/setQtyInput bornent la valeur entre 1 et Math.max(stock, 1) — impossible de descendre sous 1 ou de depasser le stock
- [x] addToTransferCart(product): si stock <= 0 -> toast.error('<nom> : stock insuffisant'); si deja au panier (meme id, variantId null) -> toast.info('<nom> est déjà dans le panier'); sinon ajoute et toast.success('<qty> × <nom> ajouté au panier')
- [x] addVariantToTransferCart(product, variant): si stock <= 0 -> toast.error('<nom> : stock insuffisant pour cette variante'); si deja au panier (meme id + meme variantId) -> toast.info('Cette variante est déjà dans le panier'); sinon ajoute et toast.success('<qty> × <nom> (<libelle variante>) ajouté au panier')
- [x] PANNEAU DROIT HAUT 'Panier de transfert': en-tete avec icone ShoppingCart + Label + Badge variant=secondary affichant '<total> unité(s)' (somme des quantites du panier)
- [x] Chaque item du panier (fond bg-muted/50, arrondi): nom en font-medium truncate, suivi si variante de ' — <variantLabel>' en gris/normal; ligne secondaire '<reference> · max <maxQuantity>'; a droite un Input number (min=1, max=maxQuantity, w-16 h-8) editable et un bouton icone ghost X (h-7 w-7, hover:text-destructive) pour retirer l'item
- [x] updateTransferCartQuantity: clamp entre 1 et item.maxQuantity a chaque frappe
- [x] removeFromTransferCart(productId, variantId): retire l'entree correspondante (comparaison stricte sur id ET variantId)
- [x] Cle d'unicite panier: cartKey(id, variantId) = variantId != null ? `${id}:${variantId}` : `${id}` — un produit et ses variantes peuvent coexister dans le panier
- [x] PANNEAU DROIT BAS 'Magasin de destination': Label + Input de recherche avec icone Search (placeholder 'Rechercher un magasin...')
- [x] Si une destination est choisie, une pastille apparait au-dessus de la liste: bordure border-primary/30 + fond bg-primary/5, icone Store primary, nom du magasin en font-medium, et un bouton icone ghost X (h-6 w-6) pour desélectionner (setDestinationStoreId(''))
- [x] Liste des destinations dans une ScrollArea de hauteur fixe h-40: un bouton par magasin, avec logo rond h-5 w-5 ou icone Store, le nom, et une icone Check a droite (ml-auto, text-primary) si selectionne; selectionne = 'bg-primary/10 border border-primary/30 font-medium'
- [x] Le magasin source est EXCLU de la liste des destinations (s.magasin_id !== sourceStore.magasin_id) et la liste est filtree par la recherche (includes insensible a la casse sur shop_name)
- [x] BOUTON SUBMIT pleine largeur (w-full): libelle 'Transférer <total> unité(s)' avec icone ArrowLeftRight (le nombre n'apparait que si total > 0); disabled si submittingTransfer || panier vide || pas de destination; pendant l'envoi: spinner Loader2 anime + 'Transfert en cours...'
- [x] initialCart (prop): permet de pre-remplir le panier ET les quantites (qtyInputs initialises depuis initialCart via cartKey) — utilise par la version dialog
- [x] FORMULAIRE DE TRANSFERT (form onSubmit=handleTransferSubmit). Champs: (1) recherche produit [texte, libre, pas de validation], (2) quantite par produit/variante [number, clamp 1..stock], (3) panier: quantite par item [number, clamp 1..maxQuantity], (4) recherche magasin destination [texte], (5) magasin de destination [selection obligatoire].
- [x] VALIDATION 1: si !destinationStoreId || transferCart.length === 0 -> toast.error('Sélectionnez des produits et un magasin de destination') et arret (le bouton est de toute facon disabled dans ce cas, c'est une double securite).
- [x] VALIDATION 2 (regle metier cachee): seuls les items ayant un variantId sont envoyes (`transferCart.filter(p => p.variantId != null)`). Si apres filtrage il ne reste rien -> toast.error('Sélectionnez au moins une couleur à transférer'). CONSEQUENCE: un produit sans variante peut etre ajoute au panier mais sera SILENCIEUSEMENT IGNORE au moment du transfert.
- [x] Payload envoye: {source_magasin_id, destination_magasin_id, items: [{variant_id, quantity}]}.
- [x] APRES SOUMISSION OK: toast.success('Transfert effectué') puis onSuccess?.() — sur /transfers cela deselectionne la source et recharge les magasins; dans le dialog cela ferme le modal puis rappelle le onSuccess du parent. Le panier n'est PAS vide explicitement: c'est le remount (key) ou la fermeture du dialog qui le reinitialise.
- [x] APRES ERREUR: console.error + toast.error('Erreur lors du transfert') — MESSAGE GENERIQUE, le detail renvoye par le backend (ex: 'Stock insuffisant pour <ref> (<couleur>). Disponible : N.') n'est PAS affiche. A ameliorer en Flutter.
- [x] Dans tous les cas (finally): setSubmittingTransfer(false).
- [x] Le panel lui-meme n'ouvre aucun dialog. Il EST le contenu du dialog TransferProductsDialog quand il est utilise en mode modal.
- [x] Zones repliables (accordeon maison) par produit a variantes — pas un composant Accordion, juste un bouton + rendu conditionnel.
- [x] Recherche produit (client): sur name OU reference, insensible a la casse, sans debounce, appliquee a la volee
- [x] Recherche magasin de destination (client): sur shop_name, insensible a la casse, exclut toujours le magasin source
- [x] Tri des variantes par SIZE_ORDER (voir features) — no-op en pratique
- [x] Aucune pagination: tous les produits du magasin source sont rendus dans une ScrollArea
- [x] loading produits: bloc centre h-32 avec Loader2 anime + texte 'Chargement...'
- [x] empty produits (magasin vide): 'Aucun produit dans ce magasin' (p-4, text-sm, centre, muted)
- [x] empty recherche produits: 'Aucun résultat' (meme style) — la distinction se fait sur sourceProducts.length === 0
- [x] empty panier: 'Aucun produit sélectionné'
- [x] empty destinations: 'Aucun magasin trouvé'
- [x] error chargement produits: console.error + toast.error('Erreur de chargement des produits'), la liste reste vide
- [x] disabled: bouton d'ajout et input de quantite desactives si deja au panier ou stock <= 0; bouton submit desactive si envoi en cours / panier vide / pas de destination
- [x] submitting: spinner + libelle 'Transfert en cours...' sur le bouton submit
- [x] Pas d'etat 'unauthorized' interne (herite de l'hote)
- [x] formatVariantLabel(size, color): joint les parties non vides par ' / ' ; si vide, la ligne affiche 'Standard'
- [x] Badge du panier: variant='secondary', texte '<n> unité(s)'
- [x] Icones lucide: Search, ShoppingCart, Store, ArrowLeftRight, Check, Plus, X, Loader2 (spin), ChevronDown/ChevronRight
- [x] Feedback immediat par toast a CHAQUE ajout au panier (success), doublon (info), stock insuffisant (error) — 3 niveaux de toast distincts
- [x] Aucune synchronisation temps reel ici (pas de useRealtimeRefresh): les stocks affiches sont ceux du chargement initial du magasin source
- [x] Les stocks affiches ne se decrementent PAS quand un item est ajoute au panier (le max reste le stock initial)
- [x] Zones scrollables independantes: liste produits (flex-1), panier (flex-1), destinations (h-40 fixe)
- [x] Sur mobile (grid-cols-1) les 3 panneaux s'empilent verticalement

### `/alerts`  —  VERIFIED

Écran Flutter : `features/alerts/alerts_screen.dart`  
Fonctionnalités à garantir : 39

- [x] En-tete : h1 'Alertes' (text-3xl font-bold tracking-tight) + sous-titre muted 'Produits necessitant une attention'.
- [x] Bouton 'Actualiser' (Button variant='outline' size='sm', icone RefreshCw h-4 w-4 mr-2) aligne a droite de l'en-tete : appelle fetchData() en mode NON silencieux (donc repasse loading=true et reaffiche tous les skeletons).
- [x] Le bouton Actualiser est disabled={loading} et son icone RefreshCw recoit la classe 'animate-spin' quand loading===true.
- [x] Grille de 4 cartes KPI : grid-cols-2 sur mobile, md:grid-cols-4, gap-4.
- [x] KPI 1 'Rupture de stock' : icone Package, couleur text-red-600, valeur = outOfStock.length.
- [x] KPI 2 'Stock faible' : icone AlertTriangle, couleur text-orange-500, valeur = lowStock.length.
- [x] KPI 3 'Expirent bientot' : icone AlertTriangle, couleur text-yellow-600, valeur = expiringSoon.length.
- [x] KPI 4 'Expires' : icone AlertTriangle, couleur text-red-700, valeur = expired.length.
- [x] Chaque KPI : CardHeader pb-2 avec CardTitle text-sm font-medium flex gap-2 (icone + label colores), CardContent avec la valeur en text-2xl font-bold de la meme couleur.
- [x] Section 1 - Card 'Rupture de stock (N)' : CardTitle text-red-600 + icone Package h-5 w-5, N = outOfStock.length. Pas de CardDescription.
- [x] Section 2 - Card 'Stock faible (N)' : CardTitle text-orange-600 + icone AlertTriangle h-5 w-5, N = lowStock.length, CardDescription "Quantite en dessous du seuil d'alerte".
- [x] Section 3 - Card 'Dates de peremption (N)' : CardTitle text-yellow-600 + icone AlertTriangle, N = expiringSoon.length + expired.length. Cette carte entiere n'est RENDUE que si (expiringSoon.length > 0 || expired.length > 0) — sinon elle disparait totalement du DOM.
- [x] Sous-composant interne AlertTable({ items, emptyMsg, columns }) redefini a chaque render : gere lui-meme les 3 etats loading / vide / tableau.
- [x] Ordre d'affichage de la section peremption : items = [...expired, ...expiringSoon] — les produits DEJA expires sont listes AVANT ceux qui expirent bientot.
- [x] Aucune action par ligne : pas de bouton, pas de lien vers la fiche produit, pas de menu contextuel, pas de selection multiple, pas d'export.
- [x] Aucune barre de recherche, aucun filtre, aucun tri, aucune pagination sur cette page.
- [x] Constante `fmt` (Intl.NumberFormat('fr-MG') sur Math.round) declaree en haut du fichier mais JAMAIS UTILISEE (code mort) — ne pas la porter.
- [x] Rafraichissement temps reel : useRealtimeRefresh(['product_variant','order'], () => fetchData(true)) — refetch SILENCIEUX (pas de skeleton, la table se met a jour en place).
- [x] Chargement initial : useEffect(() => { fetchData(); }, [fetchData]) au montage, en mode non silencieux.
- [x] Aucun filtre/recherche/tri/pagination UI. Le decoupage en 4 sections est un filtrage 100% cote client sur le tableau `products` complet.
- [x] lowStock = products.filter(p => p.initial_quantity > 0 && p.initial_quantity <= p.alert_threshold)
- [x] outOfStock = products.filter(p => p.initial_quantity === 0)
- [x] expiringSoon = products.filter(p => p.expiry_date && new Date(p.expiry_date) <= in30Days && new Date(p.expiry_date) >= today) — in30Days = aujourd'hui + 30 jours
- [x] expired = products.filter(p => p.expiry_date && new Date(p.expiry_date) < today)
- [x] loading (initial, loading=true par defaut) : chaque KPI affiche <Skeleton className='h-8 w-12' /> a la place du chiffre; chaque AlertTable affiche <Skeleton className='h-24 w-full' />.
- [x] empty par section : <p class='text-sm text-muted-foreground text-center py-6'> avec le message dedie — 'Aucun produit en rupture de stock' / "Tous les stocks sont au-dessus du seuil d'alerte" / 'Aucun produit proche de la peremption' (ce dernier est inatteignable car la carte n'est rendue que si la liste est non vide).
- [x] error : catch { console.error(err) } UNIQUEMENT — pas de toast, pas de bandeau, pas de bouton reessayer. En cas d'echec la page reste sur les donnees precedentes (ou vide) et sort du loading via finally.
- [x] success : pas de toast (page lecture seule).
- [x] unauthorized : AUCUN etat implemente.
- [x] disabled : uniquement le bouton Actualiser pendant loading.
- [x] Pendant un refresh silencieux (websocket) : aucun indicateur visuel, loading reste false.
- [x] Badge colonne 'status_badge' : si p.initial_quantity === 0 -> Badge className='bg-red-100 text-red-800' libelle 'Rupture'; sinon Badge className='bg-orange-100 text-orange-800' libelle 'Faible'.
- [x] Badge colonne 'expiry_badge' : si new Date(p.expiry_date) < today -> 'bg-red-100 text-red-800', sinon 'bg-orange-100 text-orange-800'; le texte du badge est la date formatee new Date(p.expiry_date).toLocaleDateString('fr-FR') (format JJ/MM/AAAA).
- [x] Colonne 'initial_quantity' : rendue dans un <span className='font-semibold'>.
- [x] Toute autre colonne : rendu brut p[c.key] ?? '-' (donc '-' si null/undefined, mais '' reste vide et 0 s'affiche 0).
- [x] Le compteur entre parentheses dans chaque titre de carte se met a jour en direct.
- [x] Conteneur global : div p-6 space-y-6.
- [x] Le tableau shadcn n'a pas de conteneur overflow-x propre ici : attention au responsive en portage mobile Flutter (preferer une liste de cartes).
- [x] Toasts globaux (sonner) configures dans app/layout.tsx : position top-right, richColors, closeButton, expand, duration 5000 — mais cette page n'en emet aucun.

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Groupes Rupture / Stock faible listés par variante (couleur) avec les drapeaux serveur is_rupture / is_stock_bas, là où le web agrège par référence ; export PDF de réapprovisionnement ajouté.

### `/scanner`  —  RETIRÉE DE L'APP

Écran Flutter : `features/scanner/scanner_screen.dart`  
Fonctionnalités à garantir : 30

- [ ] En-tete : h1 text-3xl font-bold tracking-tight avec icone QrCode h-8 w-8 text-blue-600 + 'Recherche produit'; sous-titre muted 'Recherchez une reference du catalogue par nom, marque ou modele.'
- [ ] Champ de recherche unique : Input max-w-xl, placeholder 'Marque, reference...', icone Search h-4 w-4 en absolute left-3 top-1/2 -translate-y-1/2 (Input en pl-10). Controle par le state `query`.
- [ ] Autofocus au montage : useEffect(() => { inputRef.current?.focus(); }, []) — clavier ouvert d'emblee.
- [ ] Recherche debouncee : useEffect avec setTimeout(() => search(query), 350) et clearTimeout au cleanup — 350 ms apres la derniere frappe.
- [ ] Si la query est vide, search() fait setResults([]) et sort immediatement (aucun appel API).
- [ ] Bloc resultats affiche seulement si (query || results.length > 0).
- [ ] Grille de resultats : grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4, une Card par produit avec hover:shadow-md transition-shadow.
- [ ] Carte resultat — CardHeader pb-2 : CardTitle text-base = p.name, et a droite un Badge de statut de stock; en dessous p.brand en text-xs text-muted-foreground font-mono.
- [ ] Carte resultat — CardContent : grille 2 colonnes text-sm. Cellule 'Categorie' (label text-xs muted) -> p.category || '-'. Cellule 'Stock' -> `${p.initial_quantity} u.` en font-semibold. Cellule 'Prix vente' en col-span-2 -> new Intl.NumberFormat('fr-MG').format(p.shell_price || 0) + ' Ar'.
- [ ] Carte resultat — Button asChild className='w-full mt-2' size='sm' contenant <Link href='/orders'>Creer une commande</Link> : navigation simple vers la liste des commandes, SANS transmettre le produit selectionne (aucun query param, aucun state) — le produit doit etre re-choisi dans le formulaire de commande.
- [ ] Aucun bouton d'ajout au panier, aucune vente directe, aucun scan camera, aucun bouton d'actualisation manuelle.
- [ ] Aucun rafraichissement temps reel (pas de useRealtimeRefresh sur cette page).
- [ ] Aucun tri, aucune pagination, aucun filtre secondaire (categorie/marque).
- [ ] Champ de recherche libre (non soumis) : 1 seul champ texte `query`, aucune validation, aucun message d'erreur de saisie, pas de submit (pas de <form>, pas de touche Entree geree). L'unique 'soumission' est le debounce de 350 ms.
- [ ] Recherche plein-texte debouncee 350 ms, insensible a la casse, sur reference_name OU brand_name (contains, pas de fuzzy, pas d'accent-folding).
- [ ] Aucun filtre par categorie/marque/type malgre le sous-titre qui mentionne 'modele'.
- [ ] Aucun tri (ordre API), aucune pagination, aucune limite de resultats.
- [ ] loading : simple <p className='text-muted-foreground text-sm'>Recherche...</p> (aucun skeleton, aucun spinner).
- [ ] empty / aucun resultat : Card > CardContent flex-col items-center py-12 gap-2 avec icone Package h-10 w-10 et le texte 'Aucun produit trouve pour « {query} »' (guillemets francais).
- [ ] idle (aucune query ET aucun resultat) : Card > CardContent flex-col items-center py-16 gap-3, icone QrCode h-16 w-16 opacity-20 + p text-lg font-medium 'Tapez pour rechercher un produit'.
- [ ] error : toast.error(err.message || 'Erreur lors de la recherche'); results conserve sa valeur precedente.
- [ ] success : pas de toast (affichage direct des cartes).
- [ ] unauthorized : AUCUN etat implemente.
- [ ] disabled : aucun.
- [ ] Badge de stock calcule par stockStatus(p) : initial_quantity === 0 -> { label:'Rupture', class:'bg-red-100 text-red-800' }; initial_quantity <= alert_threshold -> { label:'Faible', class:'bg-orange-100 text-orange-800' }; sinon { label:'En stock', class:'bg-green-100 text-green-800' }.
- [ ] Marque affichee en police mono (font-mono) pour un rendu 'code-barres/reference'.
- [ ] Prix formate fr-MG + ' Ar' (fallback 0 si shell_price null).
- [ ] Icone QrCode trompeuse : aucune camera n'est ouverte, malgre la presence de @yudiel/react-qr-scanner dans package.json (utilise ailleurs).
- [ ] Conteneur : div p-6 space-y-6.
- [ ] Les etats 'idle' et 'aucun resultat' peuvent se chevaucher logiquement mais s'excluent grace aux conditions (query || results.length > 0) et (!query && results.length === 0).

**Retirée de l'app :** page web accessible uniquement par l'URL (aucun lien dans le menu web) ; l'écran Flutter, sa route et son entrée de menu ont été supprimés à la demande (12/09/2026). La recherche produit reste disponible dans l'écran Catalogue.

## COMMUNICATION

### `/chats`  —  VERIFIED

Écran Flutter : `features/chats/*`  
Fonctionnalités à garantir : 79

- [x] Ecran de chargement plein ecran (min-h-[60vh]) tant que `authLoading`: Loader2 anime + texte pulsant 'Chargement de votre profil...'
- [x] Ecran 'Non Authentifie' si currentUser null (AlertCircle destructive + h3 + paragraphe)
- [x] En-tete de page (masque en mobile quand la conversation est ouverte, classe `hidden md:flex` si mobileShowChat): h1 'Messagerie Interne' + sous-titre
- [x] Micro-carte utilisateur courant en haut a droite: Avatar avec initiales (getInitials = 2 premieres lettres des mots du full_name, majuscules, fallback 'U'), full_name, email tronque (max-w-[150px] truncate), Badge role colore (getRoleBadgeColor)
- [x] Onglet 'General' (icone Hash) — canal de diffusion global de la societe
- [x] Onglet 'Direct' (icone Users) — messagerie 1-a-1
- [x] Changement d'onglet (handleTabChange): remet mobileShowChat a false; si 'general' -> activeRecipient=null; si 'direct' -> selectionne automatiquement filteredUsers[0] s'il y en a (donc depend du filtre de recherche courant)
- [x] Ligne unique 'Discussion Generale' dans la liste quand onglet General: icone Hash dans un carre, titre 'Discussion Generale', sous-titre 'Canal de diffusion global'; etat actif (activeRecipient===null) = fond primary + texte primary-foreground + ombre
- [x] Liste des collaborateurs (onglet Direct): un bouton par utilisateur avec Avatar+initiales, pastille verte 'en ligne' (h-2.5 w-2.5 bg-emerald-500, ring-2 ring-background, ring-primary si selectionne) en bas a droite de l'avatar, nom tronque (max-w-[120px]), Badge role en uppercase (scale-90, text-[8px]), ligne magasin (icone Store + shop_name) OU 'Administration' (icone Shield) si pas de shop_name, ligne de statut 'En ligne' (vert) / 'Vu <formatLastSeen>' / 'Hors ligne'
- [x] Clic sur un collaborateur (handleSelectUser): definit activeRecipient et ouvre la vue conversation en mobile (mobileShowChat=true)
- [x] Clic sur 'Discussion Generale' (handleSelectGeneral): activeRecipient=null + ouvre la vue conversation en mobile
- [x] Bouton retour ArrowLeft (visible uniquement en mobile, classe md:hidden) dans le header de conversation -> setMobileShowChat(false)
- [x] Header de conversation contextuel: mode General = icone Hash + 'Discussion Generale' + 'Tout le personnel de l'entreprise'; mode Direct = Avatar + pastille en ligne + nom + statut presence + separateur '•' + libelle de role en primary
- [x] Indicateur de connexion WebSocket a droite du header (3 etats, voir uxDetails)
- [x] Zone messages avec ScrollArea + auto-scroll fluide (scrollIntoView behavior:'smooth') a chaque changement de `messages` ou de `loadingHistory`
- [x] Bulles de message: alignees a droite (items-end) si expediteur = utilisateur courant, a gauche sinon; largeur max 85% (mobile) / 75% (sm) / 65% (md)
- [x] Groupement par expediteur: le nom de l'expediteur (+ mini-badge de role encadre) n'est affiche que si le message n'est pas de moi ET (premier message OU expediteur different du message precedent)
- [x] Menu contextuel par message (MoreVertical) visible uniquement au survol (opacity-0 group-hover:opacity-100), uniquement sur MES messages non supprimes et non en cours d'edition
- [x] Action 'Modifier' (icone Pencil) -> bascule la bulle en mode edition inline
- [x] Action 'Supprimer' (icone Trash2, texte rouge) -> confirm() natif puis envoi WS
- [x] Edition inline: Input autofocus pre-rempli, bouton valider (Check, fond primary) et bouton annuler (X); Entree = enregistrer, Echap = annuler
- [x] Rendu 'Message supprime' pour is_deleted: bulle transparente, bordure dashed, texte italique muted, icone Trash2
- [x] Carte produit dans la bulle si msg.product: icone Package + nom du produit + 'Ref. <reference> · <unit_price> Ar' (fond adaptatif selon que le message est le mien)
- [x] Contenu texte du message avec whitespace-pre-wrap (retours a la ligne conserves)
- [x] Horodatage sous chaque bulle (format HH:mm fr-FR), suffixe ' · modifie' si is_edited et non supprime
- [x] Accuses de lecture: sur MES messages, non supprimes, UNIQUEMENT dans l'onglet Direct — CheckCheck (couleur primary) si read_at, sinon Check simple
- [x] Suggestions rapides affichees UNIQUEMENT quand messages.length === 0: 5 puces cliquables ('Bonjour !', 'Est-ce que le stock est a jour ?', 'La commande est en cours.', 'Merci pour votre aide !', 'Je m'en occupe tout de suite.') — le clic remplit l'input (ne l'envoie pas)
- [x] Bouton '+' (Plus) a gauche de l'input -> ouvre le Popover selecteur de produit; desactive si socket non connecte
- [x] Champ de saisie du message + bouton Envoyer (icone Send, libelle 'Envoyer' masque en mobile: `hidden sm:inline`), animation active:scale-95
- [x] Rafraichissement automatique de la liste des collaborateurs toutes les 20 s (fetch silencieux: pas de spinner, pas de toast en cas d'erreur)
- [x] Heartbeat de presence: ping WebSocket toutes les 20 s tant que la socket est OPEN
- [x] Reconnexion automatique du WebSocket 3 s apres une fermeture non provoquee par le client
- [x] Card / CardContent sont importes mais JAMAIS utilises dans la page (import mort)
- [x] Formulaire d'envoi de message (<form onSubmit=handleSendMessage>) — CHAMPS: 1 seul Input texte 'Redigez votre message...' (state newMessage). VALIDATION: envoi bloque si `!newMessage.trim()` OU `!socketRef.current` OU `socketStatus !== 'connected'` (retour silencieux, AUCUN message d'erreur affiche). Le bouton submit est `disabled` dans les memes conditions, et l'Input lui-meme est `disabled` si socket non connectee. Pas de longueur max, pas de compteur. APRES SOUMISSION: `socket.send(JSON.stringify({content: newMessage.trim()}))` puis `setNewMessage('')` immediatement — AUCUN optimistic update: la bulle n'apparait que lorsque le serveur renvoie le message au groupe (l'expediteur est dans le groupe). Soumission par la touche Entree (comportement natif du form) ou par le bouton.
- [x] Formulaire d'edition inline d'un message — CHAMPS: 1 Input (autoFocus, state editingContent, pre-rempli avec msg.content). VALIDATION: `saveEditMessage` ne fait rien si !editingId, si editingContent.trim() vide, si pas de socket ou socket non 'connected' (silencieux). RACCOURCIS: Entree = enregistrer, Echap = annuler. APRES SOUMISSION: envoie {action:'edit', message_id, content trimme}, puis editingId=null et editingContent='' immediatement (l'UI attend l'evenement 'message_edited' pour refleter le nouveau contenu). Boutons Check (valider) et X (annuler).
- [x] Champ de recherche collaborateur (onglet Direct uniquement) — Input 'Rechercher un collaborateur...' avec icone Search, state searchQuery, filtrage local debounce 250 ms sur full_name / email / shop_name. Pas de validation, pas de soumission.
- [x] Champ de recherche produit (dans le Popover '+') — Input autoFocus 'Rechercher un produit...' avec icone Search, state productSearch, filtrage local debounce 250 ms sur name / reference. Selection d'un produit = envoi WS immediat {content: newMessage.trim(), product_id} puis reset de newMessage, fermeture du popover et reset de productSearch.
- [x] DropdownMenu d'actions de message (declencheur MoreVertical, align='end') — 2 items: 'Modifier' (Pencil) et 'Supprimer' (Trash2, text-red-600 focus:text-red-600). Visible uniquement au survol de la bulle et uniquement sur ses propres messages non supprimes
- [x] confirm() natif du navigateur 'Supprimer ce message ?' avant l'envoi de l'action delete (a remplacer par un AlertDialog en Flutter)
- [x] Popover selecteur de produit (bouton '+', align='start', side='top', largeur w-80, p-0): barre de recherche en haut + liste scrollable max-h-64; chaque ligne = icone Package dans un carre + nom + 'Ref. <reference> · <unit_price> Ar'; clic = envoi immediat du message avec le produit et fermeture
- [x] Tabs 'General' / 'Direct' (composant Tabs shadcn, TabsList en grid 2 colonnes, uniquement TabsList/TabsTrigger — pas de TabsContent, le contenu est rendu conditionnellement)
- [x] Aucun autre modal: pas de Dialog, pas de Drawer, pas de Sheet dans cette page. Le seul 'drawer' present a l'ecran est la sidebar globale (mobile) et le DropdownMenu de notifications de la TopBar (composants partages)
- [x] Recherche collaborateurs: `useDebouncedValue(searchQuery, 250)`, insensible a la casse, match sur full_name OU email OU shop_name. Rendue seulement dans l'onglet Direct mais le state persiste en revenant sur General (et influence la selection auto de filteredUsers[0])
- [x] Recherche produits: `useDebouncedValue(productSearch, 250)`, match sur name OU reference (insensible a la casse), vide = tous les produits
- [x] Limite d'affichage produits: `filteredProducts.slice(0, 30)` — seuls 30 resultats sont rendus, sans pagination ni 'voir plus'
- [x] Aucun tri explicite: l'ordre des collaborateurs est celui renvoye par l'API, l'ordre des messages est chronologique (ordering=['timestamp'] cote modele)
- [x] Aucune pagination des messages: le backend renvoie les 100 derniers, pas de scroll infini ni de 'charger plus'
- [x] Aucun filtre par role / par magasin dans la liste de contacts
- [x] authLoading: spinner plein ecran + 'Chargement de votre profil...'
- [x] unauthorized: bloc 'Non Authentifie' (AlertCircle destructive) — la messagerie n'est pas rendue du tout
- [x] loadingUsers (liste collaborateurs): Loader2 + 'Chargement des collaborateurs...' centre; NON affiche lors des rafraichissements silencieux toutes les 20 s
- [x] empty collaborateurs (apres filtre): 'Aucun collaborateur trouve'
- [x] loadingHistory: overlay centre Loader2 (h-8) + 'Chargement des messages...'
- [x] empty messages: icone MessageSquare dans un rond, 'Aucun message pour le moment' + 'Envoyez un message pour commencer la conversation en temps reel.' (+ affichage des suggestions rapides)
- [x] socket 'connecting': badge ambre 'Connexion...' avec Loader2 anime
- [x] socket 'connected': badge emeraude 'En ligne' avec pastille animee (ping)
- [x] socket 'disconnected': badge rose 'Hors ligne' avec Circle plein
- [x] disabled: Input message, bouton Envoyer et bouton '+' desactives des que socketStatus !== 'connected'; bouton Envoyer aussi desactive si le message est vide/blanc
- [x] loadingProducts (popover): Loader2 centre
- [x] empty produits: 'Aucun produit trouve'
- [x] error: gere UNIQUEMENT par des toasts (aucun etat d'erreur inline/retry). Pas d'etat d'erreur pour un WebSocket qui ne parvient jamais a se connecter, au-dela du badge 'Hors ligne'
- [x] Couleurs de badge par role (getRoleBadgeColor): admin = rose (bg-rose-500/10, text-rose-700 / dark:text-rose-400, border-rose-500/20), magasin = bleu (blue-500), employer = emeraude (emerald-500), defaut = muted
- [x] Libelles de role (getRoleLabel): admin -> 'Admin', magasin -> 'Gerant', employer -> 'Employe' (le sous-role Preparateur/Livreur n'apparait jamais)
- [x] Badge socket 'En ligne': double span emeraude avec `animate-ping` (halo pulsant) — effet visuel a reproduire
- [x] Pastille de presence sur avatar: 10 px, emerald-500, anneau 2 px (ring-background, ou ring-primary quand la ligne est selectionnee)
- [x] formatLastSeen: < 1 min -> 'a l'instant'; < 60 min -> 'il y a N min' (Math.floor); sinon 'a HH:mm' (fr-FR). Affiche prefixe par 'Vu ' -> ex. 'Vu il y a 12 min'
- [x] formatTime: `toLocaleTimeString('fr-FR', {hour:'2-digit', minute:'2-digit'})` -> HH:mm; try/catch renvoie '' si date invalide
- [x] getInitials: split sur les espaces, 1ere lettre de chaque mot, 2 max, upper; 'U' si nom vide
- [x] Prix produit affiche suffixe par ' Ar' (ariary malgache), sans formatage de milliers
- [x] Toasts (sonner) — uniquement des erreurs: 'Impossible de charger la liste des collaborateurs.' (non silencieux uniquement), 'Erreur lors du chargement de l'historique.', 'Impossible de charger les produits.'. AUCUN toast de succes (envoi, edition, suppression sont silencieux)
- [x] Temps reel: 3 canaux WS coexistent dans l'app — /ws/chat/ (cette page), /ws/notifications/ (TopBar + page notifications) et /ws/data/ (DataSyncProvider). Un nouveau message chat declenche aussi une Notification cote backend -> toast 'Type : Chat' via la cloche de la TopBar
- [x] Selection de conversation: fond `bg-primary` + `text-primary-foreground` + `shadow-primary/20`; survol = `hover:bg-accent/60`
- [x] Coins: bulles rounded-2xl avec coin 'queue' aplati (rounded-tr-sm pour mes messages, rounded-tl-sm pour les autres); conteneurs rounded-2xl/3xl; boutons rounded-2xl
- [x] Hauteur de page fixe: `h-[calc(100dvh-4rem)]` en mobile, `h-[calc(100vh-100px)]` a partir de sm; la zone messages est la seule a scroller (`flex-1 min-h-0`)
- [x] Mobile: master/detail par bascule de classes (`mobileShowChat`) — la liste occupe tout l'ecran, l'ouverture d'une conversation la masque; sur md+ les deux colonnes sont visibles (sidebar w-80)
- [x] `select-none` sur la sidebar de conversation, le header, la barre de saisie et les horodatages (empeche la selection de texte)
- [x] Classe `safe-area-pb` sur la barre de saisie (encoche/barre gestuelle iOS)
- [x] Les messages recus en double sont ignores par un garde `prev.some(m => m.id === id)`
- [x] Le bouton d'actions du message est `order-first` (a gauche de la bulle) pour mes messages

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Erreur de chargement de l'historique affichée en ligne avec « Réessayer » (le web n'a qu'un toast).
- Carte « produit » dans la bulle : jamais renvoyée par le backend (champ absent du sérialiseur) — branche morte du web, non portée.

### `/notifications`  —  VERIFIED

Écran Flutter : `features/notifications/notifications_screen.dart`  
Fonctionnalités à garantir : 49

- [x] En-tete : titre h1 'Notifications' (text-2xl sm:text-3xl font-bold tracking-tight)
- [x] En-tete : sous-titre muted 'Toutes les alertes et mouvements enregistres de l'application.'
- [x] En-tete : Badge d'etat du socket temps reel (variant outline, text-[10px], rounded-full py-0.5 px-2.5) avec 3 rendus distincts : 'connected' -> pastille verte animee (span animate-ping bg-emerald-400 opacity-75 + point plein bg-emerald-500) + libelle 'Temps reel' ; 'connecting' -> icone Loader2 animate-spin h-3 w-3 + libelle 'Connexion...' ; 'disconnected' -> icone AlertCircle h-3 w-3 + libelle 'Deconnecte'
- [x] Bouton 'Actualiser' (variant outline, size sm) -> relance fetchNotifications(), remet loading=true (les skeletons reapparaissent). disabled si loading || actionLoading
- [x] Bouton 'Marquer tout lu' (variant secondary, size sm) -> markAllRead(). disabled si loading || actionLoading || notifications.length===0
- [x] Bouton 'Supprimer tout' (variant destructive, size sm) -> clearAll(). disabled si loading || actionLoading || notifications.length===0. AUCUNE confirmation : suppression serveur immediate et irreversible
- [x] Card avec CardHeader/CardTitle 'Historique des notifications' englobant toute la liste
- [x] Liste verticale (space-y-3) de cartes notification, une par element, PAS de tableau, PAS de colonnes
- [x] Carte notification : classe conditionnelle via getNotificationCardClass(is_read) -> lue = 'bg-muted/40 border-border' ; non lue = 'bg-primary/5 border-primary/30 shadow-sm'. rounded-xl border p-4 transition-all duration-300
- [x] Carte : pastille ronde 9x9 (bg-primary/10 text-primary, shrink-0) contenant l'icone du type via typeIcon(notif_type)
- [x] Carte : message de la notification (text-sm font-medium, break-words)
- [x] Carte : Badge de type (variant outline + getTypeBadgeClass(notif_type)) affichant typeLabel(notif_type)
- [x] Carte : Badge 'Nouveau' (bg-primary/15 text-primary hover:bg-primary/20) affiche UNIQUEMENT si !is_read
- [x] Carte : ligne meta (text-xs muted, mt-2, break-words) construite par concatenation conditionnelle — voir uxDetails pour la regle exacte
- [x] Carte : bouton icone toggle lu/non-lu (size icon, variant outline) : icone Mail si is_read===true (=> action 'remettre non lu'), icone CheckCheck si is_read===false (=> action 'marquer lu'). disabled si actionLoading
- [x] Carte : bouton icone suppression (size icon, variant destructive, icone Trash2) -> deleteNotification(id) immediatement, SANS confirmation. disabled si actionLoading
- [x] Temps reel : nouvelle notification recue par WebSocket -> ajoutee en tete de liste (prepend) avec deduplication par id ; declenche un toast.info
- [x] Aucun onglet, aucun switch, aucun toggle group, aucun raccourci clavier, aucun export, aucune selection multiple (les endpoints bulk-read / bulk-delete existent dans le client mais ne sont PAS utilises par cette page)
- [x] Aucun formulaire sur cette page : pas d'input, pas de textarea, pas de select, pas de validation, pas de soumission. Toutes les interactions sont des boutons d'action directe.
- [x] Aucun Dialog / AlertDialog / Drawer / Sheet / Popover / DropdownMenu / ConfirmDialog dans cette page. Les actions destructives ('Supprimer tout', suppression unitaire) s'executent SANS aucune confirmation. Les seuls elements 'flottants' sont les toasts sonner globaux (Toaster monte dans app/layout.tsx).
- [x] Aucune recherche, aucun champ de filtre, aucun filtre par type/statut lu, aucun selecteur de tri, aucune pagination, aucun infinite scroll, aucun 'charger plus'.
- [x] Tri : impose par le backend (users/models.py::Notification.Meta.ordering = ['-created_at'], plus recent en premier). Le front ne re-trie jamais.
- [x] Les notifications arrivees par WebSocket sont inserees en tete de tableau (index 0), donc avant les elements du fetch, sans re-tri par date.
- [x] Pas de pagination cote serveur non plus : REST_FRAMEWORK n'a pas de DEFAULT_PAGINATION_CLASS, l'endpoint renvoie un tableau brut. Le front gere quand meme les 2 formes : `Array.isArray(data) ? data : data.results || []`.
- [x] loading (initial + a chaque Actualiser / toggleRead / markAllRead) : 5 <Skeleton className='h-20 w-full rounded-lg' /> empiles (space-y-3). Skeleton = div bg-accent animate-pulse rounded-md
- [x] empty : bloc centre 'Aucune notification pour le moment.' (py-16 text-center text-muted-foreground)
- [x] error de chargement : console.error('Notifications error:', error) + toast.error('Impossible de charger les notifications.'). La liste precedente est conservee telle quelle (au 1er chargement -> etat vide affiche). Pas de bloc d'erreur inline, pas de bouton 'Reessayer' dedie (l'utilisateur doit cliquer Actualiser)
- [x] actionLoading : passe a true pendant toggleRead / markAllRead / clearAll / deleteNotification -> desactive les 3 boutons d'en-tete ET les 2 boutons de chaque carte. Aucun spinner visuel sur les boutons, juste l'etat disabled
- [x] success : uniquement via toasts (voir uxDetails), aucun etat de succes persistant a l'ecran
- [x] unauthorized : AUCUN etat gere dans la page. Un 401 declenche le refresh automatique du token dans djangoClient.request ; si le refresh echoue -> window.location.href = '/login' (hard redirect depuis lib/django-client.ts). Un 403 backend (suppression refusee, 'Permission refusee') remonte comme une Error generique et se traduit par le toast 'Impossible de supprimer la notification.'
- [x] socket : 3 etats explicites 'connecting' | 'connected' | 'disconnected' materialises par le badge d'en-tete uniquement (aucun blocage de l'UI)
- [x] Ligne meta — regle exacte de composition (chaine concatenee, pas de separateur si vide) : premiere partie = `Produit : {product_name}` si product_name, SINON `Vente #{sale_id}` si sale_id, SINON `Utilisateur : {user_name}` si user_name, SINON chaine vide. Puis ` · Magasin : {magasin_name}` si magasin_name. Puis ` · {date formatee}` si created_at
- [x] ATTENTION : product_name et sale_id N'EXISTENT PAS dans NotificationSerializer (champs reels : id, notif_type, message, magasin, magasin_name, caisse_session, user, user_name, is_read, created_at). Ces 2 branches sont donc mortes via l'API REST ; seul `Utilisateur : ...` peut s'afficher
- [x] Format de date (formatNotificationDate) : new Date(value).toLocaleString('fr-FR', {day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) -> ex '10/09/2026 14:32'. Pas de secondes, pas de 'il y a X minutes'
- [x] Couleurs des badges de type (getTypeBadgeClass) : sale=vert (bg-green-500/10 text-green-700 dark:text-green-400 border-green-500/20), product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange, defaut=bg-muted text-muted-foreground border-border
- [x] Icones par type (typeIcon, lucide 4x4) : sale=Package, user=User, product=Mail, chat=MessageSquare, transfer=ArrowLeftRight, movement=ArrowUpDown, defaut=Bell
- [x] Libelles de type (typeLabel) : sale='Vente', product='Produit', user='Utilisateur', chat='Chat', transfer='Transfert', movement='Mouvement', defaut='Autre'
- [x] Couleurs du badge socket (getSocketStatusBadgeClass) : connected=emeraude, connecting=ambre, disconnected=rose
- [x] Toast nouvelle notification temps reel : toast.info(newNotif.message, {description: `Type : ${typeLabel(notif_type)}`, duration: 5000}) — declenche a l'interieur du updater de setNotifications, donc UNIQUEMENT si l'id n'est pas deja present
- [x] Toast toggle lu : toast.success('Notification marquee non lue') si elle etait lue, toast.success('Notification marquee lue') si elle etait non lue
- [x] Toast erreur toggle : toast.error('Impossible de mettre a jour la notification.')
- [x] Toast tout lu : toast.success('Toutes les notifications ont ete marquees comme lues.') / erreur : toast.error('Impossible de marquer toutes les notifications comme lues.')
- [x] Toast tout supprimer : toast.success('Toutes les notifications ont ete supprimees.') / erreur : toast.error('Impossible de supprimer les notifications.')
- [x] Toast suppression unitaire : toast.success('Notification supprimee.') / erreur : toast.error('Impossible de supprimer la notification.')
- [x] Toast erreur chargement : toast.error('Impossible de charger les notifications.')
- [x] Configuration globale du Toaster (app/layout.tsx) : sonner, position='top-right', richColors, closeButton, expand, toastOptions.duration=5000
- [x] Strategie de rafraichissement asymetrique : toggleRead() et markAllRead() font `await fetchNotifications()` (donc setLoading(true) -> les skeletons remplacent la liste, flash visuel a chaque clic). clearAll() fait setNotifications([]) sans refetch. deleteNotification() filtre localement sans refetch
- [x] Layout responsive : conteneur p-4 sm:p-6 space-y-6 ; en-tete flex-col gap-4 md:flex-row md:items-center md:justify-between ; carte flex-col gap-3 md:flex-row md:items-start md:justify-between ; boutons d'action flex-wrap gap-2 shrink-0
- [x] Thematisation : toutes les couleurs passent par les tokens shadcn (primary, muted, destructive, border) + variantes dark: explicites sur les badges de type. Le theme se change depuis la TopBar (next-themes, defaultTheme='system')

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- « Supprimer tout » demande une confirmation (le web supprime immédiatement) — choix de sécurité mobile.

## ADMINISTRATION

### `/users (libellé sidebar : "Super Admin", titre page : "Super Administration")`  —  VERIFIED

Écran Flutter : `features/users/users_screen.dart`  
Fonctionnalités à garantir : 73

- [x] En-tête : titre H1 'Super Administration' (texte contenant un saut de ligne dans le JSX) + sous-titre 'Gérez les accès de votre équipe.'
- [x] Header responsive : colonne sur mobile (flex-col), ligne avec justify-between sur >=md (md:flex-row)
- [x] Champ de recherche global (Input placeholder 'Rechercher...', className max-w-xs) placé dans le header, à gauche du bouton Ajouter
- [x] Bouton 'Ajouter' (icône Plus, variant par défaut) affiché seulement si isManager — donc visible aussi pour un gérant ; c'est le DialogTrigger du dialog 'Créer un utilisateur'
- [x] Système d'onglets (Tabs, defaultValue='actifs', non contrôlé — l'onglet actif n'est pas persisté)
- [x] Onglet 1 'Utilisateurs actifs' avec Badge variant='secondary' affichant allUsers.length, rendu uniquement si allUsers.length > 0
- [x] Onglet 2 'En attente' avec Badge orange (bg-orange-100 text-orange-800) affichant pendingUsers.length, rendu uniquement si pendingUsers.length > 0
- [x] Onglet 3 'Réinit. mots de passe' rendu UNIQUEMENT si isAdmin, avec Badge orange comptant passwordRequests.filter(r => r.status === 'pending').length, rendu uniquement si ce compte > 0 (attention : ce compteur porte sur la liste déjà filtrée par le Select, donc il tombe à 0 si le filtre est sur 'approved'/'rejected')
- [x] Onglet Actifs : Card titre 'Équipe active', description 'Utilisateurs confirmés groupés par magasin', tableau dans un conteneur overflow-x-auto
- [x] Onglet En attente : Card titre "En attente d'approbation", description 'Comptes créés mais non encore approuvés', tableau dans overflow-x-auto
- [x] Onglet Réinit. : Card avec en-tête en flex-row justify-between, titre 'Réinitialisations de mot de passe' précédé de l'icône KeyRound (h-5 w-5), description 'Demandes de vos gérants de magasin et commerciaux ayant oublié leur mot de passe'
- [x] Onglet Réinit. : Select de filtre de statut (largeur w-40) dans l'en-tête de la Card
- [x] Onglet Réinit. : bouton de rafraîchissement manuel (variant outline, size sm, icône RefreshCw seule, sans libellé), disabled pendant passwordRequestsLoading, l'icône tourne (animate-spin) pendant le chargement, onClick = fetchPasswordRequests
- [x] Onglet Réinit. : rendu en LISTE DE CARTES (div rounded-lg border p-4), pas en tableau ; empilement vertical space-y-3 ; chaque carte est flex-col sur mobile et flex-row sm:items-center justify-between sur >=sm
- [x] Action 'Approuver' sur une inscription en attente (icône Check, variant outline, texte vert : text-green-600 hover:text-green-700 hover:bg-green-50)
- [x] Action 'Rejeter' sur une inscription en attente (icône X, variant outline, texte rouge : text-red-600 hover:text-red-700 hover:bg-red-50) — passe par un window.confirm() natif avant l'appel
- [x] Action 'Modifier rôle' par ligne (variant outline, size sm, bleu : text-blue-600 hover:text-blue-700 hover:bg-blue-50) — pré-remplit le Select avec le rôle actuel et ouvre le dialog
- [x] Action 'Supprimer' par ligne (variant ghost, size sm, rouge : text-red-600 hover:text-red-700 hover:bg-red-50) — ouvre le ConfirmDeleteDialog avec re-saisie du mot de passe
- [x] Action 'Approuver' sur une demande de réinit. de mot de passe (size sm, variant outline, text-green-700 border-green-200, icône Check)
- [x] Action 'Rejeter' sur une demande de réinit. de mot de passe (size sm, variant outline, text-red-700 border-red-200, icône X)
- [x] Rafraîchissement automatique du calcul du temps relatif : setInterval toutes les 10 minutes (10*60*1000 ms) met à jour un state `now` ; nettoyage par clearInterval au démontage. Ça ne refait AUCUN appel réseau — seuls les libellés 'il y a X minutes' sont recalculés.
- [x] Aucun tri de colonne, aucune pagination, aucun export, aucun raccourci clavier, aucune sélection multiple, aucun menu contextuel/dropdown d'actions (les actions sont des boutons inline)
- [x] Aucun bouton de rafraîchissement manuel pour les onglets Actifs / En attente (seul l'onglet Réinit. en a un)
- [x] Rechargement complet de la liste (fetchUsers) après chaque approbation, rejet, suppression et changement de rôle
- [x] COLONNES du tableau 'Utilisateurs actifs' (7 en-têtes) : 1) 'Utilisateur' = avatar (img rond h-8 w-8 object-cover border si u.photo, sinon pastille bg-muted avec la 1re lettre en MAJUSCULE de full_name || email || '?') + nom en font-medium (fallback 'Sans nom') + email en text-xs muted + 3e ligne text-xs muted avec [phone, adresse].filter(Boolean).join(' · ') affichée seulement si phone OU adresse existe. 2) 'Rôle' = icône selon le rôle + libellé traduit. 3) 'Magasin' = u.shop_name || '-' (text-sm muted). 4) 'Poste' = u.position || '-' (text-sm muted). 5) 'Connexion / Déconnexion' (text-xs muted) = si last_login_at : deux lignes 'Connexion : dd MMM yyyy HH:mm' (locale fr) et 'Déconnexion : ' + soit 'En ligne' si actuellement en ligne, soit la date formatée de last_logout_at ; sinon '-'. 6) 'Actif' = pastille + libellé relatif (voir uxDetails). 7) 'Actions' (aligné à droite) = boutons conditionnels.
- [x] COLONNES du tableau 'En attente' (5 en-têtes) : 1) 'Utilisateur' (même bloc avatar/nom/email/phone·adresse que l'onglet Actifs). 2) 'Rôle' (icône + libellé). 3) 'Magasin / Poste' = u.shop_name || u.position || '-'. 4) 'Date inscription' = format(created_at, 'dd MMM yyyy', locale fr) sinon '-'. 5) 'Actions' à droite = Approuver / Rejeter.
- [x] CONTENU d'une carte de demande de réinitialisation : icône KeyRound violette (text-violet-500) ; ligne 1 = `{r.user_name} — {r.user_email}` (l'email en text-blue-700) ; ligne 2 = getRoleLabel(r.user_role) + (r.magasin_name ? ' · Magasin : ' + r.magasin_name : '') ; ligne 3 = new Date(r.created_at).toLocaleString('fr-FR') ; à droite un Badge de statut coloré puis, seulement si status === 'pending', les boutons Approuver / Rejeter
- [x] FORMULAIRE 'Créer un utilisateur' (dans le Dialog déclenché par le bouton Ajouter ; DialogContent sm:max-w-lg ; titre 'Créer un utilisateur', description "Le compte sera créé et en attente d'approbation."). CHAMPS DANS L'ORDRE : (1) 'Nom complet *' — Input texte, placeholder 'Jean Dupont', attribut required (validation HTML native), state newUser.full_name. (2) 'Email *' — Input type=email, placeholder 'jean@exemple.com', required (validation de format par le navigateur), state newUser.email ; cette valeur est envoyée À LA FOIS comme email ET comme username. (3) 'Mot de passe *' — Input type=password, placeholder '••••••••', minLength=6 et required ; contrôle JS supplémentaire dans handleAddUser : if (password.length < 6) -> toast.error('Le mot de passe doit contenir au moins 6 caractères') et return (aucun appel réseau). (4) 'Rôle *' — Select (valeur par défaut 'employer') avec options : 'Employé / Commercial' (value 'employer', toujours présente), 'Gérant de magasin' (value 'magasin', rendue seulement si isAdmin), 'Administrateur' (value 'admin', rendue seulement si isCompanyOwner). (5) CONDITIONNEL si role==='employer' : 'Poste / Fonction' — Input texte, placeholder 'Ex: Vendeur', NON requis, state newUser.position. (6) CONDITIONNEL si role==='magasin' : 'Nom du magasin *' — Input texte, placeholder 'Ex: Boutique Ivandry', required, state newUser.shop_name. Le state contient aussi un champ company_name jamais exposé dans l'UI ni envoyé. BOUTON DE SOUMISSION : pleine largeur (w-full), libellé "Créer l'utilisateur", disabled pendant isSubmitting et remplacé par un spinner Loader2 animate-spin + texte 'Création...'. COMPORTEMENT APRÈS SOUMISSION RÉUSSIE : toast.info("Utilisateur créé en attente d'approbation") si role !== 'admin', sinon toast.success('Administrateur créé avec succès') ; si role==='admin' et createdUser.id existe, insertion optimiste en tête de allUsers d'un objet { id, full_name, email, role:'admin', shop_name: currentUser?.company_name || 'Société', magasin_id: null, position: '', is_confirmed: true } ; fermeture du dialog (setIsDialogOpen(false)) ; réinitialisation complète du state newUser aux valeurs par défaut (role revient à 'employer') ; puis await fetchUsers() qui recharge tout. ERREURS : le code tente de lire err?.response?.data.username / .email et affiche "Un utilisateur avec ce nom d'utilisateur ou cet email existe déjà." si l'un contient 'already exists' ; sinon toast.error(err?.message || 'Une erreur est survenue pendant la création du compte.'). Le dialog reste ouvert et les champs conservent leur valeur en cas d'erreur. Aucune erreur inline sous les champs — tout passe par des toasts.
- [x] FORMULAIRE 'Modifier le rôle' (Dialog contrôlé par editRoleDialogOpen, DialogContent sm:max-w-md ; titre 'Modifier le rôle' ; description dynamique 'Changer le rôle de ' + editingUserRole?.full_name || editingUserRole?.email). CHAMP UNIQUE : 'Nouveau rôle' — Select pré-rempli avec le rôle actuel de la cible, options dans cet ordre : 'Administrateur' (value 'admin', rendue seulement si isCompanyOwner), 'Gérant de magasin' (value 'magasin'), 'Employé / Commercial' (value 'employer'). BOUTONS : 'Annuler' (variant outline, ferme simplement le dialog sans reset de editingUserRole ni newRoleValue) et 'Enregistrer' (disabled si !newRoleValue OU newRoleValue === rôle actuel OU editRoleLoading ; affiche un Loader2 animate-spin en préfixe pendant le chargement). APRÈS SUCCÈS : toast.success(`Rôle mis à jour : ${newRoleValue}` — attention, la VALEUR BRUTE anglaise ('magasin', 'employer', 'admin') est affichée, pas le libellé traduit), fermeture du dialog, editingUserRole remis à null, newRoleValue vidé, puis fetchUsers(). EN CAS D'ERREUR : toast.error(err.message), le dialog RESTE OUVERT.
- [x] FORMULAIRE de confirmation de suppression (composant partagé ConfirmDeleteDialog ; DialogContent sm:max-w-md ; titre 'Supprimer cet utilisateur' en rouge avec icône ShieldAlert ; description riche : 'Vous êtes sur le point de supprimer définitivement <nom en font-medium text-foreground>. Cette action est irréversible. Entrez votre mot de passe pour confirmer.'). CHAMP UNIQUE : 'Votre mot de passe' — Input id='confirm-delete-password', type=password, autoComplete='current-password', placeholder '••••••••', autoFocus, required, disabled pendant loading. VALIDATION : si vide à la soumission -> message inline 'Mot de passe requis.' (p text-sm text-red-600 sous le champ) ; l'erreur est effacée à chaque frappe. BOUTONS : 'Annuler' (variant outline, disabled pendant loading) et 'Supprimer définitivement' (variant destructive, disabled si loading OU si le champ est vide ; pendant le chargement : Loader2 animate-spin + 'Suppression...'). Le dialog refuse de se fermer tant que loading est true (handleOpenChange fait un early-return). APRÈS SUCCÈS : le mot de passe est vidé, le dialog se ferme, puis côté page toast.success('Utilisateur supprimé') et fetchUsers(). EN CAS D'ERREUR : le message de l'exception est affiché INLINE dans le dialog (err?.message || 'Erreur lors de la suppression.') et le dialog reste ouvert — c'est le seul formulaire de la page avec une erreur inline plutôt qu'un toast.
- [x] CONFIRMATION NATIVE de rejet : handleReject appelle window.confirm('Rejeter et supprimer cet utilisateur ?') ; si l'utilisateur annule, rien ne se passe. Ce n'est pas un composant React — à porter en AlertDialog Flutter.
- [x] Dialog 'Créer un utilisateur' — modal shadcn contrôlé par isDialogOpen, ouvert par un DialogTrigger asChild sur le bouton 'Ajouter' ; largeur sm:max-w-lg ; contient le formulaire de création. Fermeture par la croix, l'overlay/Esc, ou automatiquement après création réussie.
- [x] Dialog 'Modifier le rôle' — modal contrôlé par editRoleDialogOpen, rendu à la racine de la page (hors des Tabs) ; largeur sm:max-w-md ; ouvert par le bouton 'Modifier rôle' d'une ligne, qui mémorise editingUserRole et pré-remplit newRoleValue avec le rôle courant.
- [x] ConfirmDeleteDialog (composant partagé) — modal de suppression avec re-authentification par mot de passe ; ouvert dès que deleteTarget !== null ; onOpenChange(false) remet deleteTarget à null ; largeur sm:max-w-md.
- [x] window.confirm() natif — 'Rejeter et supprimer cet utilisateur ?' avant l'appel de rejet d'une inscription en attente.
- [x] Dropdown Select 'Rôle *' (création) — popover shadcn avec 1 à 3 options selon isAdmin / isCompanyOwner.
- [x] Dropdown Select 'Nouveau rôle' (modification) — popover shadcn avec 2 ou 3 options selon isCompanyOwner.
- [x] Dropdown Select de filtre de statut des demandes de réinitialisation (w-40) — 4 options.
- [x] AUCUN menu contextuel, AUCUN drawer, AUCUN popover d'information/tooltip sur cette page.
- [x] Recherche unique en haut de page (state searchTerm) appliquée SIMULTANÉMENT aux onglets 'Utilisateurs actifs' et 'En attente' ; elle n'affecte PAS l'onglet 'Réinit. mots de passe'.
- [x] La recherche est debouncée via useDebouncedValue(searchTerm) avec un délai par défaut de 250 ms : la saisie reste instantanée, le filtrage est différé.
- [x] Prédicat de filtrage identique pour les deux listes : (u.full_name || '').toLowerCase().includes(terme.toLowerCase()) || (u.email || '').toLowerCase().includes(terme.toLowerCase()). Donc recherche uniquement sur NOM et EMAIL — pas sur le magasin, le poste, le téléphone ni l'adresse. Insensible à la casse, mais SENSIBLE aux accents (pas de normalisation NFD).
- [x] Filtrage côté client uniquement (aucun paramètre envoyé à l'API).
- [x] Filtre de statut de l'onglet 'Réinit. mots de passe' : Select à 4 options — 'En attente' (value 'pending', valeur par défaut), 'Approuvées' (value 'approved'), 'Rejetées' (value 'rejected'), 'Toutes' (value 'all'). Ce filtre est SERVEUR : il déclenche un nouvel appel GET /users/password-reset-requests/?status=... via un useEffect dépendant de passwordRequestsFilter ; pour 'all' le paramètre status est omis.
- [x] Aucun tri (ni par défaut explicite, ni cliquable) : l'ordre est celui renvoyé par l'API. Pour l'onglet Actifs l'ordre suit la construction : pour chaque magasin, d'abord le manager, puis les employers, puis les company_users, avec déduplication par id (le premier gagne).
- [x] Aucune pagination, aucun scroll infini, aucune limite de nombre de lignes — les tableaux affichent l'intégralité des résultats, avec seulement un défilement horizontal (overflow-x-auto) sur petits écrans.
- [x] LOADING onglet Actifs : `loading` initial à true ; rendu de 4 Skeleton h-10 w-full empilés (space-y-2) à la place du tableau.
- [x] LOADING onglet En attente : mêmes conditions (partage le state `loading`), 3 Skeleton h-10 w-full.
- [x] LOADING onglet Réinit. : state séparé passwordRequestsLoading (initial true) ; 3 Skeleton h-16 w-full ; le bouton Refresh est disabled et son icône tourne.
- [x] EMPTY onglet Actifs : une TableRow avec une cellule colSpan={8} centrée, py-8, text-muted-foreground, texte 'Aucun utilisateur trouvé' (colSpan=8 alors que le tableau n'a que 7 colonnes).
- [x] EMPTY onglet En attente : bloc centré py-12 muted avec deux lignes — 'Aucune demande en attente' (text-lg font-medium) et 'Tous les utilisateurs ont été traités.' (text-sm mt-1). Ce bloc REMPLACE le tableau entier (pas de header de colonnes affiché).
- [x] EMPTY onglet Réinit. : bloc centré py-12 muted avec le texte dynamique 'Aucune demande ' + libellé du filtre en minuscules ('en attente' / 'approuvée' / 'rejetée'), ou juste 'Aucune demande ' quand le filtre vaut 'all'.
- [x] UNAUTHORIZED : si !isManager && !currentUserLoading, la page entière est remplacée par une Card centrée (py-20) avec l'icône ShieldAlert h-12 w-12 text-red-500, le titre 'Accès Refusé' (text-xl font-bold) et le texte muted "Vous n'avez pas les permissions pour gérer les utilisateurs." — aucun bouton de retour.
- [x] ERROR de chargement de la liste des utilisateurs : toast.error('Erreur de chargement: ' + err.message) ; les tableaux restent avec leurs données précédentes (ou vides) — pas d'état d'erreur dédié ni de bouton 'Réessayer'.
- [x] ERROR de chargement des demandes de réinit. : toast.error('Erreur lors du chargement des demandes: ' + err.message).
- [x] SILENT FAILURE : GET /users/pending/ est appelé avec .catch(() => []) — un échec produit une liste vide sans le moindre message, l'onglet affiche alors l'état vide 'Aucune demande en attente'.
- [x] DISABLED : bouton 'Créer l'utilisateur' pendant isSubmitting ; bouton 'Enregistrer' du dialog rôle si aucun rôle, rôle inchangé, ou chargement ; boutons Approuver/Rejeter d'une demande de réinit. quand resolvingRequestId === r.id (verrou par ligne — les autres lignes restent cliquables) ; bouton Refresh pendant passwordRequestsLoading ; boutons Annuler / Supprimer définitivement du ConfirmDeleteDialog pendant la suppression.
- [x] SUCCESS : uniquement des toasts (sonner) — aucune bannière ni état de succès persistant. La donnée est systématiquement rechargée après l'action.
- [x] PAS d'état 'saving' visuel sur les boutons Approuver / Rejeter de l'onglet En attente : ils ne sont ni désactivés ni mis en spinner pendant l'appel (double-clic possible).
- [x] PENDANT currentUserLoading : la page rend l'UI normale (pas d'écran Accès Refusé prématuré, la garde exige !currentUserLoading), avec les tableaux en skeleton puisque fetchUsers n'est déclenché qu'une fois currentUserLoading passé à false.
- [x] Toasts via la librairie `sonner` (import { toast } from 'sonner') : toast.success, toast.error et toast.info. Messages exacts : 'Utilisateur approuvé', 'Utilisateur rejeté', 'Utilisateur supprimé', 'Rôle mis à jour : <valeur brute du rôle>', 'Demande approuvée', 'Demande rejetée', "Utilisateur créé en attente d'approbation" (info), 'Administrateur créé avec succès', 'Le mot de passe doit contenir au moins 6 caractères', "Un utilisateur avec ce nom d'utilisateur ou cet email existe déjà.", 'Une erreur est survenue pendant la création du compte.', 'Erreur de chargement: ...', 'Erreur lors du chargement des demandes: ...', 'Erreur lors du traitement'.
- [x] Icônes de rôle (getRoleIcon) : admin -> Shield h-4 w-4 text-purple-500 ; magasin -> Briefcase h-4 w-4 text-blue-500 ; tout le reste (employer) -> Users h-4 w-4 text-green-500.
- [x] Libellés de rôle (getRoleLabel) : admin -> 'Administrateur', magasin -> 'Gérant', employer -> 'Employé' ; toute autre valeur est affichée telle quelle (fallback ?? role). NB : dans les Select on parle de 'Gérant de magasin' et 'Employé / Commercial' alors que le tableau affiche 'Gérant' et 'Employé' — vocabulaire volontairement différent entre listes et formulaires.
- [x] Indicateur d'activité (colonne 'Actif') : si en ligne -> texte text-green-700 avec une pastille pleine h-1.5 w-1.5 rounded-full bg-green-500 et le texte 'Actif ' + temps relatif depuis last_login_at ; si hors ligne -> texte muted avec pastille bg-slate-300 et 'Hors ligne ' + temps relatif depuis last_logout_at ; si jamais de last_login_at -> 'Jamais connecté' en text-xs muted.
- [x] Format du temps relatif (formatRelativeTime, calculé contre le state `now` rafraîchi toutes les 10 min) : < 1 min -> "à l'instant" ; < 60 min -> 'il y a N minute(s)' ; < 24 h -> 'il y a N heure(s)' ; sinon 'il y a N jour(s)'. Pluriel géré ('s' si > 1). Les écarts négatifs sont clampés à 0 via Math.max(0, ...). Les heures/jours sont ARRONDIS (Math.round), pas tronqués — 90 min affichent donc 'il y a 2 heures'.
- [x] Format des dates absolues : date-fns `format` avec locale fr — 'dd MMM yyyy HH:mm' pour les connexions/déconnexions, 'dd MMM yyyy' pour la date d'inscription. Les demandes de réinitialisation utilisent en revanche new Date(...).toLocaleString('fr-FR') (format natif jj/mm/aaaa hh:mm:ss) — incohérence de format à reproduire ou à harmoniser.
- [x] Badges de statut des demandes de réinitialisation (Badge variant='outline' + classe conditionnelle) : approved -> bg-green-50 text-green-800 border-green-200 ; rejected -> bg-red-50 text-red-800 border-red-200 ; défaut/pending -> bg-orange-50 text-orange-800 border-orange-200. Libellés : 'En attente', 'Approuvée', 'Rejetée'.
- [x] Badges de compteur d'onglets : onglet Actifs -> Badge variant='secondary' (gris) ; onglets En attente et Réinit. -> Badge orange bg-orange-100 text-orange-800. Tous en ml-2.
- [x] Avatars : image ronde si photo (URL absolue construite par le backend via build_absolute_uri), sinon monogramme sur fond muted avec bordure ; classes shrink-0 pour ne pas se déformer.
- [x] Séparateur ' · ' (point médian) entre téléphone et adresse dans la cellule utilisateur, et entre le rôle et 'Magasin : X' dans les demandes de réinitialisation.
- [x] Pas de temps réel WebSocket sur cette page : le seul rafraîchissement automatique est le tick de 10 minutes qui ne fait que recalculer les libellés relatifs à partir des données déjà chargées. Les statuts en ligne/hors ligne ne se mettent donc PAS à jour tout seuls sans rechargement.
- [x] Espacement général : conteneur p-6 space-y-6 ; tableaux enveloppés dans overflow-x-auto pour le défilement horizontal mobile ; l'écran Accès Refusé utilise juste p-6.
- [x] Les colonnes d'actions sont alignées à droite (text-right + flex justify-end gap-2).

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Entrée de menu réservée à l'admin comme le sidebar web ; la route accepte tout gérant (isManager) comme la page web, mais un gérant de magasin n'a pas d'autre point d'entrée sur mobile (pas d'URL).

### `/settings`  —  VERIFIED

Écran Flutter : `features/settings/settings_screen.dart`  
Fonctionnalités à garantir : 65

- [x] En-tête : h1 'Paramètres' + sous-titre 'Gérez votre profil et vos préférences'
- [x] Composant Tabs shadcn, `defaultValue="profile"`, 4 onglets max, pas de persistance de l'onglet actif (pas d'URL, pas de localStorage)
- [x] Onglet 1 'Mon profil' (icône User, value=profile) — toujours visible
- [x] Onglet 2 'Sécurité' (icône Lock, value=security) — toujours visible
- [x] Onglet 3 'Dépenses' (icône Wallet, value=depenses) — rendu UNIQUEMENT si isGerant
- [x] Onglet 4 'Zones de livraison' (icône MapPin, value=zones) — rendu UNIQUEMENT si isGerant
- [x] Card 'Informations personnelles' : description conditionnelle selon isGerant ('Mettez à jour vos informations' vs message de restriction)
- [x] Aperçu photo de profil : <img> 64x64 rounded-full object-cover border si avatarPreview, sinon cercle 64x64 bordé bg-muted avec icône User grise
- [x] Bouton 'Enregistrer' du profil : rendu seulement si isGerant, texte 'Enregistrement...' pendant saving, `disabled={saving}`
- [x] Bloc 'Magasin' (séparateur border-t) affiché si `user.role === 'magasin' && user.shop_name` : icône Building2 + shop_name en gras dans un encadré bg-slate-50/50 + bouton outline size=sm 'Modifier' qui ouvre le Dialog
- [x] Bloc 'Entreprise' affiché si `user.role === 'admin' && user.company_name` : même structure, icône Building2 + company_name + bouton 'Modifier'
- [x] Card 'Changer le mot de passe' (onglet Sécurité) : le CardContent entier (donc le formulaire) est rendu seulement si isGerant
- [x] Card 'Catégories de dépenses' (onglet Dépenses) avec description : 'Catégories proposées lors d'une saisie de sortie de caisse (Salaire, Pub, Commande stock...). Ajoutez-en, renommez ou supprimez-les selon vos besoins.'
- [x] Sous-composant ExpenseCategoriesCrudList : compteur 'Toutes les catégories (N)', liste scrollable max-h-72 overflow-y-auto
- [x] Ligne catégorie (mode lecture) : nom + bouton icône Pencil (passer en édition) + bouton icône Trash2 rouge (suppression IMMÉDIATE, aucune confirmation)
- [x] Ligne catégorie (mode édition inline) : Input h-8 autoFocus + bouton 'OK' (sauver) + bouton ghost 'Annuler' (sort de l'édition sans sauver)
- [x] Barre d'ajout catégorie en bas : Input placeholder 'Nouvelle catégorie (ex: Transport)' + bouton 'Ajouter' avec icône Plus
- [x] Card 'Zones de livraison' (onglet Zones) avec description longue : 'Zones proposées à la création d'une commande (nom + frais de livraison). Le retrait sur place ("Récupération") reste toujours disponible séparément et n'est pas géré ici. Ajoutez-en, renommez ou changez le prix selon vos besoins — pensez à garder au moins une zone gratuite (0 Ar).'
- [x] Sous-composant DeliveryZonesCrudList : compteur 'Toutes les zones (N)', liste scrollable max-h-96 overflow-y-auto
- [x] Ligne zone (mode lecture) : nom (barré + muted si !actif) + Badge secondary avec le prix formaté + Switch actif/inactif (title='Zone active') + Pencil + Trash2 rouge
- [x] Ligne zone (mode édition inline) : Input nom h-8 autoFocus + Input number min=0 w-28 placeholder 'Prix (Ar)' + bouton 'OK' + bouton ghost 'Annuler'
- [x] Barre d'ajout zone en bas : Input nom flex-1 placeholder 'Nouvelle zone (ex: Zone 4)' + Input number min=0 w-32 placeholder 'Prix (Ar)' + bouton 'Ajouter' (icône Plus)
- [x] Toggle du Switch zone : PATCH immédiat de `actif` puis rechargement de la liste, SANS toast de succès (silencieux)
- [x] Aucune recherche, aucun tri, aucun filtre, aucune pagination sur les listes catégories/zones
- [x] Aucun tableau (pas de <table>) : tout est en cartes/listes de lignes flex
- [x] FORMULAIRE 1 — 'Informations personnelles' (handleUpdateProfile, onglet Profil). Champs : (a) Photo de profil : <input type=file accept="image/*">, disabled si !isGerant, prévisualisation via URL.createObjectURL, pas de contrainte de taille/format côté client ; (b) Email : input `value={user?.email}` disabled + classe bg-muted + aide 'L'email ne peut pas être modifié' — non soumis ; (c) Rôle : lecture seule, Badge outline, pas un input ; (d) Nom complet (id=fullName, placeholder 'Votre nom', disabled si !isGerant, PAS de required) ; (e) Téléphone (id=phone, placeholder '+261 XX XXX XX XX', disabled si !isGerant, pas de required, pas de masque, pas de validation) ; (f) Adresse (id=adresse, placeholder 'Ex: Lot II A 45, Antanimena, Antananarivo', disabled si !isGerant, pas de required). Validation client : AUCUNE (on peut soumettre des champs vides). Soumission : PATCH JSON {full_name, phone, adresse} puis, si un fichier avatar a été choisi, second appel PATCH multipart {photo} et `setAvatarFile(null)`. Succès : toast.success('Profil mis à jour'), formulaire NON réinitialisé, PAS de reload, l'aperçu reste l'object URL local. Échec : toast.error(err.message || 'Erreur lors de la mise à jour'). Bouton disabled pendant `saving`.
- [x] FORMULAIRE 2 — 'Changer le mot de passe' (handleChangePassword, onglet Sécurité, rendu si isGerant). Champs : (a) 'Mot de passe actuel' id=oldPw type=password placeholder '••••••••' required ; (b) 'Nouveau mot de passe' id=newPw type=password placeholder '••••••••' required minLength=6 ; (c) 'Confirmer le mot de passe' id=confirmPw type=password placeholder '••••••••' required. Validations client (avant appel) : si newPassword !== confirmPassword -> toast.error('Les mots de passe ne correspondent pas') et abandon ; si newPassword.length < 6 -> toast.error('Le mot de passe doit contenir au moins 6 caractères') et abandon. Pas de message d'erreur inline sous les champs : tout passe par des toasts. Soumission : POST /users/change-password/. Succès : toast.success('Mot de passe changé avec succès') + reset des 3 champs à ''. Échec : toast.error(err.message || 'Erreur lors du changement de mot de passe'). Bouton 'Changer le mot de passe' -> 'Changement...' et disabled pendant changingPw. Aucune déconnexion/relogin après changement.
- [x] FORMULAIRE 3 — Modal 'Modifier l'entreprise' / 'Modifier le magasin' (handleUpdateDetails). Champs : (a) Nom (label et placeholder conditionnels : "Nom de l'entreprise" si role=admin sinon 'Nom du magasin' ; bound à companyName ou shopName selon le rôle) avec attribut `required` ; (b) Logo : <input type=file accept="image/*"> (label "Logo de l'entreprise" ou 'Logo du magasin'), optionnel, prévisualisation 80x80 object-contain rounded-md border centrée après sélection. Soumission : FormData -> si role=admin : company_name + logo ; si role=magasin : shop_name + shop_logo ; AUCUN champ envoyé pour les autres rôles (FormData vide -> requête inutile). PATCH multipart /users/me/. Succès : toast.success('Informations mises à jour avec succès'), fermeture du modal, puis `window.location.reload()` (rechargement complet de la page — à traduire en Flutter par un refresh du user courant). Échec : toast.error(err.message || 'Erreur lors de la mise à jour'). Bouton submit : 'Enregistrer' / spinner Loader2 + 'Enregistrement...', disabled pendant updatingDetails ; bouton 'Annuler' outline qui ferme le modal sans reset des champs.
- [x] MINI-FORMULAIRE — Ajout catégorie de dépense (ExpenseCategoriesCrudList.addCategory). 1 champ texte. Validation : `if (!newName.trim()) return;` — abandon SILENCIEUX, aucun toast, aucun message d'erreur. Envoi du nom trimmé. Succès : toast.success('Catégorie ajoutée') + vidage du champ + rechargement de la liste. Échec : toast.error(err.message || 'Erreur').
- [x] MINI-FORMULAIRE — Renommage catégorie (saveEdit). 1 champ inline. Validation : `if (!editingId || !editingName.trim()) return;` silencieux. Succès : toast.success('Catégorie renommée'), sortie du mode édition, reload liste. Échec : toast.error(err.message || 'Erreur').
- [x] ACTION — Suppression catégorie (removeCategory) : DELETE direct au clic sur la corbeille, AUCUNE boîte de confirmation. Succès : toast.success('Catégorie supprimée') + reload. Échec : toast.error(err.message || 'Erreur lors de la suppression').
- [x] MINI-FORMULAIRE — Ajout zone (addZone). Champs : nom (texte) + prix (number, min=0). Validation : `if (!newName.trim()) return;` silencieux (le prix n'est PAS validé). Prix converti par `Number(newPrix) || 0` -> vide ou non numérique = 0 Ar. Succès : toast.success('Zone ajoutée') + vidage des deux champs + reload. Échec : toast.error(err.message || 'Erreur').
- [x] MINI-FORMULAIRE — Édition zone (saveEdit). Champs : nom + prix number min=0. Validation : nom trimmé non vide sinon abandon silencieux ; prix `Number(editingPrix) || 0`. Envoie PATCH {nom, prix} (le champ actif n'est PAS renvoyé ici). Succès : toast.success('Zone mise à jour') + sortie d'édition + reload. Échec : toast.error(err.message || 'Erreur').
- [x] ACTION — Toggle actif d'une zone (toggleActive) : PATCH {actif: !z.actif}, aucun toast de succès, seulement un reload de la liste. Échec : toast.error(err.message || 'Erreur').
- [x] ACTION — Suppression zone (removeZone) : DELETE direct, AUCUNE confirmation. Succès : toast.success('Zone supprimée') + reload. Échec : toast.error(err.message || 'Erreur lors de la suppression'). ATTENTION : côté serveur, une zone déjà utilisée est seulement désactivée -> après le toast 'Zone supprimée' la zone réapparaît barrée/inactive dans la liste.
- [x] Dialog unique (shadcn Dialog, `max-w-md`) piloté par `modalOpen` : titre "Modifier l'entreprise" si role=admin sinon 'Modifier le magasin' ; description "Mettez à jour le nom et le logo de votre entreprise" / "...de votre magasin". Ouvert par les boutons 'Modifier' des blocs Magasin/Entreprise de l'onglet Profil. Contient le formulaire nom + logo + preview, boutons Annuler / Enregistrer.
- [x] Édition inline (PAS un dialog) des catégories : la ligne se transforme en Input + OK + Annuler
- [x] Édition inline (PAS un dialog) des zones : la ligne se transforme en Input nom + Input prix + OK + Annuler
- [x] AUCUN dialog de confirmation de suppression (ni pour les catégories, ni pour les zones) — le clic sur la corbeille supprime directement
- [x] Toasts via `sonner` (composant global <Toaster/>)
- [x] Aucune recherche, aucun filtre, aucun tri, aucune pagination sur cette page
- [x] Les listes sont simplement scrollables : catégories max-h-72, zones max-h-96 (overflow-y-auto)
- [x] Les compteurs 'Toutes les catégories (N)' / 'Toutes les zones (N)' sont dérivés du `.length` local du tableau
- [x] LOADING global : `if (userLoading)` -> conteneur p-6 space-y-4 avec 3 <Skeleton className="h-24 w-full"> (pas de spinner)
- [x] LOADING listes catégories/zones : AUCUN état de chargement — la liste est simplement vide puis se remplit
- [x] ERROR chargement catégories/zones : swallow total `.catch(() => {})` — aucun toast, aucun message, la liste reste vide (indiscernable d'un vrai vide)
- [x] EMPTY catégories : 'Aucune catégorie.' centré, text-sm text-muted-foreground, py-4
- [x] EMPTY zones : 'Aucune zone.' même style
- [x] SUBMITTING profil : bouton 'Enregistrement...' + disabled
- [x] SUBMITTING mot de passe : bouton 'Changement...' + disabled
- [x] SUBMITTING modal : Loader2 animate-spin + 'Enregistrement...' + disabled
- [x] UNAUTHORIZED / non-gérant : pas d'écran 403 — dégradation en lecture seule (champs disabled, onglets masqués, formulaire mot de passe non rendu, bouton Enregistrer non rendu) + textes explicatifs dans les CardDescription
- [x] DISABLED : tous les inputs profil quand !isGerant ; input file avatar disabled ; Input number des quantités non applicable ici
- [x] Pas d'état 'success' persistant : seulement des toasts éphémères
- [x] Toasts sonner : succès 'Profil mis à jour', 'Mot de passe changé avec succès', 'Informations mises à jour avec succès', 'Catégorie ajoutée/renommée/supprimée', 'Zone ajoutée', 'Zone mise à jour', 'Zone supprimée' ; erreurs génériques 'Erreur', 'Erreur lors de la mise à jour', 'Erreur lors de la suppression', 'Erreur lors du changement de mot de passe'
- [x] Badge outline pour le rôle avec libellés FR : admin -> 'Administrateur', magasin -> 'Gérant de magasin', employer -> 'Commercial' (map `roleLabel`, fallback = valeur brute du rôle)
- [x] Badge secondary pour le prix de zone, format `arFmt` = `new Intl.NumberFormat('fr-MG').format(Math.round(Number(n||0)))` + ' Ar' (arrondi à l'entier, séparateur de milliers FR)
- [x] Zone inactive : nom en `text-muted-foreground line-through` (barré grisé) mais reste dans la liste
- [x] Icône corbeille en `text-red-500` (action destructive), icône crayon en variant ghost neutre
- [x] Bloc Magasin/Entreprise : encadré `bg-slate-50/50` avec icône Building2
- [x] Après édition du nom/logo entreprise-magasin : rechargement complet de la page (`window.location.reload()`) — perte de l'onglet actif, retour sur 'Mon profil'
- [x] Aperçu image via URL.createObjectURL (pas d'upload immédiat : l'image ne part qu'à la soumission du formulaire)
- [x] Pas de temps réel (aucun useRealtimeRefresh sur cette page) : les listes ne se rafraîchissent que sur action locale
- [x] Layout : padding p-6, espacement space-y-6, formulaires contraints en `max-w-md`
- [x] Le Switch de zone a un `title="Zone active"` (tooltip natif navigateur)

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Le bloc « Entreprise » ne propose « Modifier » qu'au propriétaire de la société (le serveur ignore ces champs pour un co-administrateur) ; le web affiche le bouton à tous les admins.

### `/stores`  —  VERIFIED

Écran Flutter : `features/stores/stores_screen.dart`  
Fonctionnalités à garantir : 57

- [x] En-tête : h1 'Magasins' (text-2xl sm:text-3xl) + sous-titre dynamique '{stores.length} magasin(s)'
- [x] Bouton 'Créer un magasin' (DialogTrigger) — rendu UNIQUEMENT si isAdmin
- [x] Bouton 'Actualiser' (variant outline, icône RefreshCw) — toujours visible, `onClick={() => fetchData()}` (rechargement NON silencieux : réaffiche les skeletons)
- [x] L'icône RefreshCw tourne (`animate-spin`) tant que `loading` est vrai
- [x] Grille responsive de cartes : 1 colonne / md:2 / lg:3, gap-4 sm:gap-6
- [x] Carte magasin — en-tête : logo (img 20x20 rounded-full object-cover) si `store.shop_logo`, sinon icône Store ; nom `shop_name` tronqué (truncate)
- [x] Carte magasin — bouton icône ArrowLeftRight (transfert de produits depuis ce magasin) : isAdmin uniquement
- [x] Carte magasin — bouton icône Edit (modifier nom/logo) : isAdmin uniquement
- [x] Carte magasin — bloc gérant (rendu seulement si `store.manager` existe) : full_name en font-medium + email en text-sm text-muted-foreground, séparé par border-b. NB : `manager` côté serveur = l'ADMIN de la société (mag.admin), pas le compte role='magasin'
- [x] Carte magasin — 4 tuiles KPI en grid 2 colonnes : 'Produits', 'Stock', 'Ventes', 'Profit'
- [x] Tuile 'Produits' : texte composite '{total_stock_quantity} unité(s) sur {total_products} produits' (deux nombres formatés fr-FR)
- [x] Tuile 'Stock' : `total_stock_value` en Ariary
- [x] Tuile 'Ventes' : `total_sold_value` en Ariary (= somme des `total_a_payer` des commandes au statut LIVRE)
- [x] Tuile 'Profit' : `profit`, fond vert (bg-green-50 / dark:bg-green-950/30) et texte vert (text-green-700 / dark:text-green-400)
- [x] Carte magasin — bloc employés : icône Users + 'Employés ({store.employers?.length || 0})'
- [x] Liste des employés LIMITÉE aux 3 premiers (`employers?.slice(0, 3)`) — aucun 'voir plus', aucune pagination : les employés au-delà du 3e sont invisibles alors que le compteur les inclut
- [x] Chaque employé : nom (full_name) à gauche + Badge outline à droite : 'Actif' si `is_confirmed` sinon 'Attente'
- [x] Rafraîchissement TEMPS RÉEL : `useRealtimeRefresh(['product_variant', 'order'], () => fetchData(true))` — WebSocket DataSyncContext, debounce 400 ms, rechargement silencieux (ni skeleton ni toast)
- [x] Aucun tableau (<table>) : uniquement des cartes
- [x] Aucun tri, aucune recherche, aucun filtre, aucune pagination sur la liste des magasins
- [x] Aucun export
- [x] FORMULAIRE 1 — 'Nouveau magasin' (handleRegisterStore, dans le Dialog déclenché par 'Créer un magasin'). Champs, TOUS sans attribut required et SANS aucune validation client : (a) 'Nom du magasin' (texte, state storeName) ; (b) 'Nom du gérant' (texte, state managerName) ; (c) 'Email' (type=email, state managerEmail — sert à la fois d'email ET de username) ; (d) 'Mot de passe' (type=password, state managerPassword, pas de longueur minimale, pas de confirmation). Bouton submit pleine largeur : 'Créer' / (Loader2 animate-spin + 'Création...'), disabled pendant submittingStore. Soumission : register(role 'magasin', extraData {full_name: managerName, shop_name: storeName, admin_email: user?.email}) puis approveUser(response.id). Succès : toast.success('Magasin créé.'), reset des 4 champs à '', fermeture du dialog, fetchData(). Échec : toast.error(err?.message || 'Erreur lors de la création.'). Aucun message d'erreur inline : tout en toast. RISQUE PORTAGE : si le register réussit mais approveUser échoue, l'exception coupe le flux -> toast d'erreur alors que le magasin EXISTE déjà (les champs ne sont pas vidés, le dialog reste ouvert).
- [x] FORMULAIRE 2 — 'Modifier le magasin' (handleUpdateStore, Dialog max-w-md). Pré-rempli par handleStartEditStore : editStoreName = store.shop_name, preview = store.shop_logo. Champs : (a) 'Nom du magasin' (texte, `required`) ; (b) 'Logo du magasin' (<input type=file accept="image/*">, optionnel) avec prévisualisation 80x80 object-contain rounded-md border, centrée — affichée aussi pour le logo EXISTANT à l'ouverture. Soumission : FormData {shop_name, shop_logo?} -> PATCH /users/magasins/{magasin_id}/. Succès : toast.success('Magasin mis à jour avec succès'), fermeture du dialog, fetchData() (rechargement NON silencieux -> skeletons). Échec : toast.error(err.message || 'Erreur lors de la mise à jour'). Bouton pleine largeur 'Enregistrer' / Loader2 + 'Enregistrement...', disabled pendant submittingEditStore. Pas de bouton Annuler explicite (fermeture par la croix/overlay du Dialog).
- [x] FORMULAIRE 3 — Transfert de produits (composant partagé TransferProductsPanel dans TransferProductsDialog). Voir sharedComponents pour le détail complet : recherche produit, quantités clampées, panier, recherche + sélection du magasin de destination, submit 'Transférer N unité(s)'. Validation : (a) si pas de destination OU panier vide -> toast.error('Sélectionnez des produits et un magasin de destination') ; (b) après filtrage, si aucun item n'a de variantId -> toast.error('Sélectionnez au moins une couleur à transférer') (le state submittingTransfer reste bloqué à true jusqu'au finally). Succès : toast.success('Transfert effectué') puis fermeture du dialog + fetchData() de la page Magasins. Échec : toast.error('Erreur lors du transfert').
- [x] Dialog 'Nouveau magasin' (isRegisterDialogOpen) — DialogTrigger = bouton 'Créer un magasin', titre 'Nouveau magasin', description 'Ajouter un magasin', contient le formulaire de création. Rendu seulement si isAdmin.
- [x] Dialog 'Modifier le magasin' (isEditStoreDialogOpen, max-w-md) — titre 'Modifier le magasin', description 'Modifier le nom et le logo du magasin.', ouvert par le bouton icône Edit d'une carte.
- [x] Dialog 'Transfert de produits' (TransferProductsDialog, isTransferDialogOpen) — plein écran quasi total : w-[97vw] max-w-[97vw] h-[95vh] max-h-[95vh], titre 'Transfert de produits', description 'Depuis {shop_name} — sélectionnez des produits (et leurs variantes) et choisissez le magasin de destination.'. Ouvert par le bouton icône ArrowLeftRight. À la fermeture, `transferSourceStore` est remis à null (handleTransferDialogChange) et le panneau est remonté via `key={sourceStore.magasin_id}` -> état interne (panier, destination, recherche) totalement réinitialisé quand on change de magasin source.
- [x] AUCUNE confirmation de suppression (aucune suppression de magasin n'est exposée sur cette page)
- [x] Toasts sonner globaux
- [x] Aucun filtre / tri / recherche / pagination sur la liste des magasins elle-même
- [x] Bouton 'Actualiser' = rechargement manuel complet (loading = true, skeletons réaffichés)
- [x] Rafraîchissement automatique silencieux déclenché par les événements WebSocket 'product_variant' et 'order' (debounce 400 ms)
- [x] Dans le dialog de transfert : recherche produit (Input, filtre client insensible à la casse sur `name` OU `reference`) et recherche magasin de destination (filtre client sur `shop_name`, avec exclusion du magasin source)
- [x] LOADING initial / après 'Actualiser' / après édition-création : grille de 3 <Skeleton className="h-48 rounded-xl"> dans la même grille responsive
- [x] LOADING silencieux (WebSocket) : aucun indicateur, les données se remplacent en place
- [x] ERROR chargement principal : toast.error('Erreur lors du chargement.') uniquement si `!silent` ; `stores` reste à sa valeur précédente (souvent []) ; pas d'écran d'erreur ni de bouton Réessayer autre que 'Actualiser'
- [x] ERROR stats (/magasins/stats/) : silencieuse (console.error) -> KPI affichés à 0 Ar / 0 produits
- [x] ERROR profit (/magasins/overview/) : silencieuse -> repli sur `storeStats.profit` puis 0
- [x] EMPTY : AUCUN état vide dédié — si aucun magasin, la grille est vide et le sous-titre affiche '0 magasin(s)'
- [x] SUBMITTING création : bouton Loader2 + 'Création...' disabled
- [x] SUBMITTING édition : bouton Loader2 + 'Enregistrement...' disabled
- [x] SUBMITTING transfert : bouton Loader2 + 'Transfert en cours...' disabled
- [x] DISABLED (transfert) : bouton submit disabled si panier vide OU pas de destination ; Input quantité et bouton 'Sélectionner' disabled si déjà au panier (`inCart`) ou stock <= 0
- [x] UNAUTHORIZED : pas d'écran dédié — les actions admin ne sont simplement pas rendues ; un employer verra la carte de son magasin sans aucun bouton d'action
- [x] Bloc gérant absent si `store.manager` est null (cellule conditionnelle)
- [x] Logo magasin absent -> icône Store en repli (en-tête de carte ET liste des destinations du transfert)
- [x] formatNumber = `Intl.NumberFormat('fr-FR')` (utilisé pour unités et nb de produits)
- [x] formatCurrency = `Intl.NumberFormat('fr-MG')` + ' Ar' (utilisé pour Stock / Ventes / Profit) — deux locales différentes coexistent dans la même carte
- [x] Tuile Profit visuellement distinguée : fond vert clair + texte vert foncé, adaptée dark mode
- [x] Badges employés : 'Actif' (is_confirmed=true) vs 'Attente' (false), tous deux en variant outline — MÊME couleur, seul le libellé change
- [x] Icône RefreshCw en rotation continue pendant le chargement
- [x] Toasts : 'Magasin créé.', 'Magasin mis à jour avec succès', 'Transfert effectué', 'Erreur lors du chargement.', 'Erreur lors de la création.', 'Erreur lors de la mise à jour', 'Erreur lors du transfert'
- [x] Temps réel : la page se remet à jour toute seule à la moindre création/modif de commande ou de variante de produit dans la société (events 'order' et 'product_variant'), sans feedback visuel
- [x] Layout : container mx-auto px-4 sm:px-6 py-6 sm:py-8 space-y-6, en-tête flex-col en mobile / flex-row en sm+
- [x] Boutons d'action de carte en `size="icon"` variant outline, groupés à droite du titre, `shrink-0`
- [x] Dans le panneau de transfert : ordre de tri des variantes par taille selon SIZE_ORDER ['XS','S','M','L','XL','2XL','3XL','4XL'] (tailles inconnues renvoyées en fin, index 99)
- [x] Dans le panneau de transfert : Badge secondary '{N} unité(s)' comme compteur de panier ; libellé de variante = 'taille / couleur' joint par ' / ', ou 'Standard' si les deux sont vides

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Rafraîchissement temps réel sur ws/notifications/ (pas de client ws/data/) — même débounce 400 ms, mais une modification de variante sans notification ne recharge pas les KPI d'elle-même.

### `/stores (modal TransferProductsDialog — variante modale du meme flux)`  —  VERIFIED

Écran Flutter : `features/stores/stores_screen.dart`  
Fonctionnalités à garantir : 15

- [x] Dialog plein ecran quasi total: w-[97vw] max-w-[97vw] h-[95vh] max-h-[95vh], overflow-hidden, flex flex-col
- [x] Titre: 'Transfert de produits'
- [x] Description: 'Depuis <shop_name du magasin source en gras/foreground> — sélectionnez des produits (et leurs variantes) et choisissez le magasin de destination.'
- [x] Le panel n'est monte que si sourceStore n'est pas null (rendu conditionnel), avec key={sourceStore.magasin_id} pour reinitialiser l'etat au changement de source
- [x] onSuccess du panel: ferme le dialog (onOpenChange(false)) PUIS appelle le onSuccess du parent (sur /stores: fetchData() pour recharger les magasins)
- [x] Props: open, onOpenChange, sourceStore (nullable), stores, initialCart (defaut []), onSuccess
- [x] Fermeture standard du Dialog Radix: bouton X, clic sur l'overlay, touche Echap — aucune confirmation avant fermeture, le panier en cours est perdu
- [x] Aucun formulaire propre — delegue integralement a TransferProductsPanel (voir son entree).
- [x] C'EST le dialog. Contenu = TransferProductsPanel. Aucun sous-dialog.
- [x] Aucun — delegue au panel (recherche produit + recherche magasin destination).
- [x] Aucun etat propre: loading/empty/error sont ceux du panel.
- [x] Si sourceStore est null, le dialog s'affiche avec seulement l'en-tete (description avec un nom de magasin vide) et un corps vide.
- [x] Modal quasi plein ecran pour laisser de la place aux deux colonnes du panel
- [x] Le nom du magasin source est mis en valeur (font-medium text-foreground) dans la description
- [x] En Flutter, l'equivalent naturel est une page plein ecran (fullscreenDialog) plutot qu'un AlertDialog, vu la taille 97vw/95vh

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Le transfert depuis la carte d'un magasin ouvre l'écran Transferts pré-rempli (source) au lieu d'une fenêtre modale.

### `/superadmin`  —  RETIRÉE DE L'APP

Écran Flutter : `features/superadmin/superadmin_screen.dart`  
Fonctionnalités à garantir : 52

- [ ] En-tete : h1 text-3xl font-bold tracking-tight avec icone Shield h-8 w-8 text-blue-600 + 'Super Administration'; sous-titre muted 'Gestion globale des utilisateurs et magasins'.
- [ ] Bouton 'Actualiser' (Button variant='outline' size='sm', icone RefreshCw h-4 w-4 mr-2 avec 'animate-spin' quand loading, disabled={loading}) -> fetchData().
- [ ] Bandeau statistiques : grid-cols-1 md:grid-cols-3 gap-4.
- [ ] Stat 1 'Magasins' : icone Store h-4 w-4 text-blue-500, valeur = stores.length en text-2xl font-bold.
- [ ] Stat 2 'Utilisateurs total' : icone Users h-4 w-4 text-green-500, valeur = allUsers.length.
- [ ] Stat 3 'En attente' : icone Users h-4 w-4 text-orange-500, valeur = allUsers.filter(u => !u.is_confirmed).length.
- [ ] Tableau 1 — Card 'Toutes les equipes', CardDescription '{stores.length} equipe(s) enregistree(s)'.
- [ ] Tableau 1 colonne 'Magasin' : s.shop_name, className font-medium.
- [ ] Tableau 1 colonne 'Gerant' : s.manager?.full_name || '-', en text-sm text-muted-foreground. ATTENTION : `manager` cote backend est en realite l'ADMIN de la societe (mag.admin), pas le compte role='magasin'.
- [ ] Tableau 1 colonne 'Membres' : memberCount = (s.employers?.length || 0) + (s.manager ? 1 : 0), en text-sm. Ne compte PAS mag.user (le vrai gerant) ni les co-admins.
- [ ] Tableau 1 colonne 'Statut' : Badge variant='outline'; isActive = !!s.manager?.is_confirmed -> 'Actif' avec classes 'text-green-700 border-green-200', sinon 'Inactif' avec 'text-orange-700 border-orange-200'.
- [ ] Tableau 1 : key de ligne = s.magasin_id. Aucune action par ligne (pas d'edition, pas de suppression de magasin, pas de lien vers le detail magasin).
- [ ] Tableau 2 — Card 'Tous les utilisateurs', CardDescription '{allUsers.length} compte(s) enregistre(s)'.
- [ ] Construction de allUsers : stores.flatMap(s => [ s.manager ? {...s.manager, shop_name: s.shop_name} : null, ...(s.employers||[]).map(e => ({...e, shop_name: s.shop_name})) ]).filter(Boolean) — donc uniquement manager + employers, PAS les co-admins presents dans s.company_users, et sans dedoublonnage.
- [ ] Tableau 2 colonne 'Nom' : u.full_name, font-medium.
- [ ] Tableau 2 colonne 'Email' : u.email, text-sm text-muted-foreground.
- [ ] Tableau 2 colonne 'Magasin' : u.shop_name || '-', text-sm.
- [ ] Tableau 2 colonne 'Role' : Select shadcn inline (SelectTrigger className='w-32 h-7 text-xs', SelectValue) — CHANGE LE ROLE IMMEDIATEMENT au onValueChange, sans confirmation.
- [ ] Options du Select : value='admin' libelle 'Admin', value='magasin' libelle 'Gerant', value='employer' libelle 'Commercial'.
- [ ] Le Select est disabled si changingRole === u.id (appel en cours) OU si u.role === 'admin' (un compte admin liste ici est toujours le fondateur de la societe; l'action ne serait jamais autorisee cote backend, donc le controle est desactive plutot que supprime pour garder la mise en page des colonnes).
- [ ] Tableau 2 colonne 'Statut' : Badge variant='outline' — u.is_confirmed -> 'Actif' (text-green-700 border-green-200), sinon 'En attente' (text-orange-700 border-orange-200). NOTE : le libelle 'inactif' du tableau 1 devient 'En attente' ici pour la meme donnee is_confirmed.
- [ ] Tableau 2 colonne 'Actions' : bouton Trash2 (Button variant='ghost' size='icon' className='h-7 w-7 text-red-500 hover:text-red-700') affiche UNIQUEMENT si u.role !== 'admin'; il ouvre la modale de suppression via setDeleteTarget({ id: u.id, name: u.full_name }). Pour un admin la cellule est vide.
- [ ] Aucune creation d'utilisateur, aucune invitation, aucune approbation de compte en attente, aucune edition d'email/telephone depuis cette page.
- [ ] Aucun rafraichissement temps reel (pas de useRealtimeRefresh) — la seule mise a jour est fetchData() apres une action ou via le bouton Actualiser.
- [ ] Constante roleLabel = { admin:'Administrateur', magasin:'Gerant', employer:'Commercial' } declaree en haut du fichier mais JAMAIS UTILISEE (code mort) — les libelles reels du Select sont 'Admin' / 'Gerant' / 'Commercial'.
- [ ] Formulaire inline 'changement de role' (le Select de la colonne Role) : 1 champ (role, valeurs admin|magasin|employer), pas de validation cliente, pas de confirmation. Soumission implicite au changement de valeur -> handleChangeRole(u.id, v). Pendant l'appel : setChangingRole(userId) desactive le Select de cette ligne. Apres succes : toast.success('Role modifie') puis fetchData() (rechargement complet, donc reaffichage des 3 skeletons puisque fetchData fait setLoading(true)). Apres echec : toast.error(err.message || 'Erreur') et la valeur affichee revient a l'ancienne apres le refetch.
- [ ] Formulaire de la modale ConfirmDeleteDialog (composant partage) : 1 champ 'Votre mot de passe' (id='confirm-delete-password', type='password', autoComplete='current-password', placeholder '••••••••', autoFocus, required, disabled pendant l'envoi). Validation cliente : si mot de passe vide -> setError('Mot de passe requis.') et pas d'appel API. Le bouton de soumission est disabled tant que le champ est vide ou qu'un envoi est en cours. Le message d'erreur (client ou serveur) s'affiche en <p className='text-sm text-red-600'> sous le champ, et est efface a chaque frappe. Apres succes : le champ est vide, la modale se ferme, toast.success('Utilisateur supprime'), puis fetchData(). Apres echec : la modale RESTE OUVERTE avec l'erreur inline (err.message || 'Erreur lors de la suppression.') — AUCUN toast d'erreur ici.
- [ ] ConfirmDeleteDialog (composant partage /home/garrix/Dev/Smartphone/frontend/components/confirm-delete-dialog.tsx) : open={!!deleteTarget}, onOpenChange={(open) => !open && setDeleteTarget(null)}.
- [ ] Titre passe : 'Supprimer cet utilisateur' — rendu en DialogTitle flex items-center gap-2 text-red-600 avec icone ShieldAlert h-5 w-5.
- [ ] Description riche (ReactNode) : 'Vous etes sur le point de supprimer definitivement <span class="font-medium text-foreground">{deleteTarget?.name}</span>. Cette action est irreversible. Entrez votre mot de passe pour confirmer.'
- [ ] DialogContent className='sm:max-w-md'. La fermeture (Echap / clic exterieur / bouton Annuler) est BLOQUEE tant que loading===true (handleOpenChange fait un return anticipe).
- [ ] Bouton 'Annuler' : type='button', variant='outline', disabled pendant l'envoi; a la fermeture le mot de passe et l'erreur sont reinitialises.
- [ ] Bouton de confirmation : type='submit', variant='destructive', libelle 'Supprimer definitivement'; pendant l'envoi il affiche un Loader2 h-4 w-4 mr-2 animate-spin + 'Suppression...'; disabled={loading || !password}.
- [ ] Aucun dropdown/popover/menu contextuel ailleurs sur la page (hormis le SelectContent du Select de role, qui est un popover Radix).
- [ ] AUCUNE recherche, AUCUN filtre (ni par role, ni par statut, ni par magasin), AUCUN tri de colonne, AUCUNE pagination — les deux tableaux affichent l'integralite des donnees renvoyees.
- [ ] L'ordre des lignes est celui de l'API (magasins puis, dans allUsers, manager avant employers pour chaque magasin).
- [ ] loading (userLoading || loading) : TOUTE la page est remplacee par un div p-6 space-y-4 contenant 3 <Skeleton className='h-16 w-full' /> — l'en-tete et les stats disparaissent aussi.
- [ ] Ce meme skeleton plein ecran reapparait apres CHAQUE changement de role et CHAQUE suppression, car fetchData() fait setLoading(true) (pas de mode silencieux ici).
- [ ] empty : AUCUN etat vide implemente — si stores est vide, on voit deux tableaux avec un header et zero ligne, et les descriptions '0 equipe(s) enregistree(s)' / '0 compte(s) enregistre(s)'.
- [ ] error de chargement : catch { console.error(err) } uniquement — pas de toast, pas de bandeau, pas de retry. stores reste a sa valeur precedente.
- [ ] error changement de role : toast.error(err.message || 'Erreur').
- [ ] error suppression : message inline rouge dans la modale (pas de toast).
- [ ] success : toast.success('Role modifie') / toast.success('Utilisateur supprime').
- [ ] unauthorized : pas d'ecran dedie — redirection router.replace('/dashboard') sans aucun message.
- [ ] disabled : bouton Actualiser pendant loading; Select de role si changingRole===u.id ou u.role==='admin'; boutons de la modale pendant l'envoi.
- [ ] Codes couleur des badges : Actif / vert (text-green-700 border-green-200) ; Inactif ou En attente / orange (text-orange-700 border-orange-200). Badges en variant='outline' (fond transparent), contrairement aux badges pleins de /alerts et /pickup.
- [ ] Deux libelles differents pour la meme donnee is_confirmed : 'Actif'/'Inactif' dans le tableau des equipes, 'Actif'/'En attente' dans le tableau des utilisateurs.
- [ ] Le Select de role est tres compact (w-32 h-7 text-xs) : en Flutter, prevoir un DropdownButton dense ou un bottom sheet sur mobile.
- [ ] Toasts sonner globaux : top-right, richColors, closeButton, expand, duree 5000 ms.
- [ ] Aucun temps reel : contrairement a /alerts et /pickup, aucune souscription WebSocket ici.
- [ ] Aucun format numerique special (pas d'Intl) : les compteurs sont affiches bruts.
- [ ] Conteneur global : div p-6 space-y-6; tableaux dans des Card sans conteneur overflow-x (6 colonnes -> deborde sur mobile, a repenser en liste de cartes en Flutter).

**Retirée de l'app :** page web accessible uniquement par l'URL (aucun lien dans le menu web) ; l'écran Flutter, sa route et son entrée de menu ont été supprimés à la demande (12/09/2026). La gestion des comptes reste disponible dans `/users`.

## PILOTAGE

### `/caisse`  —  VERIFIED

Écran Flutter : `features/caisse/caisse_screen.dart`  
Fonctionnalités à garantir : 64

- [x] Titre h1 'Caisse' avec icone Wallet h-8 w-8 text-blue-600 + sous-titre 'Ouverture, mouvements et fermeture de la caisse'
- [x] Bouton 'Actualiser' (variant outline, size sm, icone RefreshCw) en haut a droite: appelle fetchCaisse() UNIQUEMENT (ne rafraichit PAS le resume/periode). disabled={loading}; l'icone RefreshCw prend animate-spin tant que loading est vrai
- [x] Selecteur de magasin (visible SEULEMENT si isAdmin): label 'Magasin :' + une ligne de boutons, un par magasin renvoye par GET /users/magasins/users/. Chaque bouton affiche shop_logo en img h-4 w-4 rounded-full object-cover si present, sinon une icone Store muted, puis shop_name. Le bouton selectionne prend les classes bg-primary/10 border-primary/30 font-medium; les autres border-border. Clic -> setSelectedMagasinId -> re-fetch automatique de la caisse ET du resume (deps des useCallback)
- [x] Si isAdmin et stores.length === 0: texte 'Aucun magasin' a la place des boutons
- [x] Aucun magasin preselectionne au chargement pour un admin -> il tombe d'abord sur l'ecran vide 'Selectionnez un magasin pour gerer sa caisse.'
- [x] CARTE 1 (statut de session) — titre dynamique: si session ouverte icone LockOpen text-green-600 + 'Caisse ouverte', sinon icone Lock muted + 'Caisse fermee'
- [x] CARTE 1 — CardDescription seulement si session: 'Ouverte le {formatDateTime(session.opened_at)}' suivi de ' par {session.opened_by_name}' si opened_by_name existe
- [x] CARTE 1 — Actions si session ouverte: bouton outline 'Mouvement' (icone Plus) -> ouvre le dialog mouvement; bouton destructive 'Fermer la caisse' (icone Lock) -> ouvre le dialog de fermeture
- [x] CARTE 1 — Action si aucune session: bouton primaire 'Ouvrir la caisse' (icone LockOpen) -> ouvre le dialog d'ouverture
- [x] CARTE 1 — 4 tuiles KPI (grid 2 cols mobile / 4 cols sm) affichees seulement si session: 'Fond d'ouverture' = money(session.opening_balance); 'Entrees' = +money(total in) en text-green-600; 'Sorties' = -money(total out) en text-red-600; 'Solde attendu' = money(expectedBalance)
- [x] CARTE 1 — calcul client: movementTotals = reduce sur session.movements (in => acc.in += Number(amount), sinon acc.out += Number(amount)); expectedBalance = Number(opening_balance) + in - out (0 si pas de session)
- [x] CARTE 1 — liste 'Mouvements de la session': conteneur border rounded-lg divide-y max-h-64 overflow-y-auto. Les mouvements sont affiches via [...session.movements].reverse() donc en ordre CHRONOLOGIQUE croissant (l'API les renvoie deja en -created_at, le reverse remet le plus ancien en premier)
- [x] CARTE 1 — ligne de mouvement: icone ArrowUpCircle text-green-600 si movement_type==='in', ArrowDownCircle text-red-600 si 'out'; titre = m.reason (truncate, font-medium); sous-titre xs muted = formatDateTime(m.created_at) + ' · ' + m.created_by_name (le ' · nom' n'apparait que si created_by_name existe); a droite montant '+money' vert ou '-money' rouge en font-semibold
- [x] CARTE 2 (Resume de la caisse) — titre 'Resume de la caisse' + description 'Tous les mouvements et les ventes de la periode, quelle que soit la session.'
- [x] CARTE 2 — 6 tuiles KPI (grid 2/3/6): 'Entrees' +money(summary.total_entrees) vert; 'Sorties' -money(summary.total_sorties) rouge; 'Solde' money(summary.solde); 'CA produits vendus' money(summary.ca_produits_vendus); 'Cout des produits vendus' money(summary.cout_produits_vendus) en text-orange-600; 'Benefice produits vendus' money(summary.benefice_produits_vendus) en text-green-700 avec petite icone PiggyBank h-3.5 dans le label
- [x] CARTE 2 — bloc 'Sorties par categorie' affiche UNIQUEMENT si summary.sorties_par_categorie.length > 0: une Badge variant outline par ligne, texte '{row.categorie} : {money(row.total)}' (le backend remplace une categorie nulle par 'Sans categorie', tri par total decroissant)
- [x] CARTE 2 — liste 'Mouvements de la periode (N)' avec N = periodMovements.length; conteneur border rounded-lg divide-y max-h-72 overflow-y-auto; ordre = ordre API = -created_at (plus recent en premier), PAS de reverse ici (contrairement a la carte 1)
- [x] CARTE 2 — ligne de mouvement de periode: identique a la carte 1 mais le titre est '{m.reason} · {m.category_name}' quand category_name existe
- [x] CARTE 3 (Historique des sessions) — titre 'Historique des sessions', description '{history.length} session(s) fermee(s)'. history = resultat de listSessions filtre cote client sur status === 'closed'
- [x] CARTE 3 — tableau dans un conteneur overflow-x-auto, 6 colonnes (voir filters/uxDetails pour le detail des cellules)
- [x] Pas de recherche, pas de tri cliquable, pas de pagination, pas d'export, pas de raccourci clavier, aucune action ligne (pas d'edition ni de suppression de mouvement dans cette page, bien que djangoClient.caisse.deleteMovement existe et ne soit pas utilise ici)
- [x] Rafraichissement temps reel via useRealtimeRefresh(['caisse_session','caisse_movement'], () => { fetchCaisse(); fetchSummary(); }) — WebSocket /ws/data/, debounce 400 ms
- [x] Chargement initial: 3 useEffect declenches quand !userLoading -> fetchStores() (admin seulement), fetchCaisse(), fetchSummary(); + 1 useEffect au montage qui charge les categories de depense (erreur silencieusement ignoree via .catch(() => {}))
- [x] FORMULAIRE 'Ouvrir la caisse' (dans le Dialog d'ouverture). Champs: (1) 'Montant d'ouverture (Ar) *' — Input type=number, min=0, step=0.01, required (validation HTML native), etat openingBalance, pre-rempli automatiquement avec total_stock_value du magasin (helper: 'Pre-rempli avec la valeur de stock actuelle du magasin — modifiable.'), le pre-remplissage arrive APRES l'ouverture du dialog (await asynchrone); (2) 'Heure d'ouverture' — composant DateTimeInput (deux inputs natifs separes: type=date + type=time w-32), initialise a maintenant (heure de l'APPAREIL via toDatetimeLocalValue), max = maintenant (seule la partie DATE de min/max est appliquee par le composant), helper 'Modifiable si la caisse a ete ouverte plus tot dans la journee.'; (3) 'Note (optionnel)' — Textarea, placeholder 'Ex: Fond de caisse du matin'. Validation JS: if (!magasinId) toast.error('Selectionnez un magasin') et abandon. Soumission: POST open avec opening_balance = openingBalance || 0, opening_note = openingNote || undefined, opened_at = ISO (new Date(value).toISOString()) ou undefined si vide. Succes: toast.success('Caisse ouverte'), fermeture du dialog, fetchCaisse(). Echec: toast.error(err.message || 'Erreur lors de l’ouverture'), dialog reste ouvert, champs conserves. Boutons: 'Annuler' (outline, disabled si submitting, ferme sans reset) et 'Ouvrir' (submit, disabled si submitting, icone Loader2 animate-spin pendant l'envoi sinon LockOpen).
- [x] FORMULAIRE 'Fermer la caisse' (Dialog de fermeture). Description du dialog: 'Solde attendu : {money(expectedBalance)} — comptez la caisse et indiquez le montant reel.' Champs: (1) 'Montant compte (Ar) *' — Input type=number min=0 step=0.01 required, etat closingBalance, pre-rempli avec total_stock_value (meme helper que l'ouverture), et sous le champ un indicateur d'ecart en direct affiche des que closingBalance !== '': 'Ecart : {signe}{money(Number(closingBalance) - expectedBalance)}' en text-green-600 si l'ecart vaut exactement 0, sinon text-orange-600, avec un '+' explicite si l'ecart est positif; (2) 'Heure de fermeture' — DateTimeInput, initialise a maintenant, min = session.opened_at (converti en datetime-local, partie date seulement), max = maintenant, helper 'Modifiable si la caisse a ete fermee plus tot.'; (3) 'Note (optionnel)' — Textarea placeholder 'Ex: Compte OK'. Validation JS: if (!session || closingBalance === '') toast.error('Montant compte requis') et abandon. Soumission: POST close(session.id, {closing_balance, closing_note || undefined, closed_at ISO || undefined}). Succes: toast.success('Caisse fermee'), fermeture du dialog, fetchCaisse() SEUL (le resume n'est pas rafraichi). Echec: toast.error(err.message || 'Erreur lors de la fermeture'). Boutons: 'Annuler' outline + 'Fermer la caisse' variant destructive (Loader2 pendant l'envoi sinon Lock).
- [x] FORMULAIRE 'Ajouter un mouvement' (Dialog mouvement). Description: 'Apport ou retrait d'especes dans la caisse.' Champs: (1) 'Type *' — RadioGroup horizontal (flex gap-4) a 2 options: 'Entree' (value 'in', icone ArrowUpCircle verte) et 'Sortie' (value 'out', icone ArrowDownCircle rouge); valeur par defaut 'in'; (2) 'Montant (Ar) *' — Input type=number min=0 step=0.01 required; (3) 'Motif *' — Input texte required, placeholder 'Ex: Achat fournitures'; (4) 'Categorie (optionnel)' — Select AFFICHE UNIQUEMENT si movementType === 'out', options = expenseCategories (value = String(c.id), label = c.nom), placeholder 'Aucune categorie', helper 'Gerez les categories dans Parametres > Depenses.'. Validation JS: if (!movementAmount || !movementReason) toast.error('Montant et motif requis') et abandon (donc un montant '0' est refuse car chaine falsy... '0' est truthy en JS, seule la chaine vide bloque). Soumission: POST movements avec session = session?.id, movement_type, amount, reason, et category = Number(movementCategory) UNIQUEMENT si movementType==='out' ET movementCategory non vide (sinon undefined). Succes: toast.success('Mouvement ajoute'), fermeture du dialog, fetchCaisse() ET fetchSummary(). Echec: toast.error(err.message || 'Erreur lors de l’ajout du mouvement'). Boutons: 'Annuler' outline + 'Ajouter' (Loader2 pendant l'envoi sinon Plus). Reset a l'ouverture du dialog: type='in', montant '', motif '', categorie ''.
- [x] FILTRE DE PERIODE du resume (pas un form, deux Input type=date dans le header de la CARTE 2): 'du' summaryFrom (defaut = premier jour du mois courant, calcule par todayStr.slice(0,8) + '01' a partir de new Date().toISOString() donc en UTC), separateur texte '→', 'au' summaryTo (defaut = aujourd'hui, date UTC ISO). Chaque changement relance fetchSummary() (summary + listMovements) via la dependance du useCallback. Aucun bouton 'Appliquer', aucune validation from <= to.
- [x] Dialog 'Ouvrir la caisse' (shadcn Dialog, etat openDialogOpen) — titre 'Ouvrir la caisse', description 'Renseignez le fond de caisse de depart.', contient le formulaire d'ouverture, ferme via la croix/overlay (onOpenChange) ou le bouton Annuler
- [x] Dialog 'Fermer la caisse' (closeDialogOpen) — titre 'Fermer la caisse', description rappelant le solde attendu en gras, contient le formulaire de fermeture avec l'indicateur d'ecart temps reel
- [x] Dialog 'Ajouter un mouvement' (movementDialogOpen) — titre 'Ajouter un mouvement', description 'Apport ou retrait d'especes dans la caisse.', contient le RadioGroup type / montant / motif / select categorie conditionnel
- [x] Select (popover shadcn) 'Categorie' a l'interieur du dialog mouvement — liste des CaisseCategory (defaut serveur: Salaire, Pub, Commande stock, Autre), placeholder 'Aucune categorie'
- [x] Aucun dialog de confirmation destructive (la fermeture de caisse se fait sans confirmation supplementaire, le formulaire fait office de confirmation)
- [x] Aucun drawer, aucun menu contextuel, aucun popover hors le Select
- [x] Selecteur de magasin (admin uniquement) — boutons-onglets, pilote TOUTES les requetes de la page (caisse courante, sessions, resume, mouvements de periode, valeur de stock)
- [x] Plage de dates du resume: date_from / date_to envoyees a /users/caisse/summary/ et /users/caisse/movements/. Cote backend le filtre porte sur created_at__date__gte / __lte (comparaison sur la DATE, timezone serveur Indian/Antananarivo)
- [x] Filtre client sur l'historique: sessions.filter(s => s.status === 'closed')
- [x] Tri: aucun tri utilisateur. Ordre impose par le backend — sessions: ordering ['-opened_at']; mouvements: ordering ['-created_at']. La liste des mouvements de SESSION est inversee cote client (.reverse()) donc chronologique croissante, celle de la PERIODE reste anti-chronologique
- [x] Pagination: aucune (listes completes, defilement interne max-h-64 / max-h-72 et tableau en overflow-x-auto)
- [x] Aucune barre de recherche
- [x] userLoading: retour anticipe -> page entiere remplacee par 3 Skeleton h-16 w-full dans un conteneur p-6 space-y-4
- [x] loading (fetch caisse): 3 Skeleton h-16 w-full a la place des 3 cartes
- [x] summaryLoading: Skeleton h-40 w-full a la place du contenu de la carte Resume
- [x] Empty 'aucun magasin resolu' (!magasinId): Card avec texte muted centre py-12 — 'Selectionnez un magasin pour gerer sa caisse.' si isAdmin, sinon 'Aucun magasin associe a votre compte.'
- [x] Empty liste magasins (admin): texte 'Aucun magasin'
- [x] Empty mouvements de session: 'Aucun mouvement pour l'instant' (p-4, centre, muted)
- [x] Empty mouvements de periode: 'Aucun mouvement pour cette periode'
- [x] Empty historique: ligne de tableau unique colSpan=6, 'Aucune session fermee', centree py-8 muted
- [x] Etat 'caisse fermee' vs 'caisse ouverte': change le titre, l'icone, la description et le jeu de boutons de la carte 1; le bloc KPI + mouvements n'existe que si session
- [x] Erreurs: uniquement des toasts sonner (chargement magasins, chargement caisse, chargement resume, echec des 3 soumissions). Aucun ecran d'erreur, aucun retry, les donnees precedentes restent affichees
- [x] Unauthorized: AUCUN etat gere dans la page — un preparateur/livreur qui force /caisse verra la coquille de page + des toasts d'erreur 403 (a implementer proprement en Flutter)
- [x] Disabled: bouton Actualiser disabled pendant loading; les 6 boutons des dialogs disabled pendant submitting; le champ Select categorie n'est pas disabled mais purement conditionnel
- [x] Succes: toasts 'Caisse ouverte' / 'Caisse fermee' / 'Mouvement ajoute' + fermeture du dialog + refetch
- [x] Formatage monetaire money(v): Number(v ?? 0).toLocaleString('fr-FR', {minimumFractionDigits: 0, maximumFractionDigits: 2}) + ' Ar' — separateur d'espace insecable francais, jusqu'a 2 decimales (different du format du bilan qui arrondit)
- [x] Formatage date/heure formatDateTime: date-fns format(new Date(v), 'dd MMM yyyy HH:mm', {locale: fr}) -> ex '10 sept. 2026 14:30'; '-' si null. ATTENTION: utilise le fuseau de l'APPAREIL, pas APP_TIME_ZONE (Indian/Antananarivo) contrairement a la page bilan — incoherence a trancher au portage Flutter
- [x] Code couleur systematique: entrees/positif = green-600 (ArrowUpCircle, prefixe '+'), sorties/negatif = red-600 (ArrowDownCircle, prefixe '-'), cout = orange-600, benefice = green-700, ecart nul = vert, ecart non nul = orange
- [x] Colonne 'Ecart' de l'historique: Badge variant outline dont les classes changent — 'text-green-700 border-green-200' si Number(s.difference) === 0, sinon 'text-orange-700 border-orange-200'; le contenu prefixe '+' si difference > 0 (jamais de '-' explicite, il vient du money())
- [x] Colonnes du tableau Historique: 'Ouverte le' = formatDateTime(opened_at); 'Fermee le' = formatDateTime(closed_at); 'Fond' = money(opening_balance); 'Compte' = money(closing_balance); 'Ecart' = badge decrit ci-dessus; 'Ouvert / Ferme par' = '{opened_by_name || '-'} / {closed_by_name || '-'}' en text-xs muted
- [x] Icone d'etat de caisse: LockOpen vert = ouverte, Lock gris = fermee; le bouton de fermeture est rouge (destructive) pour marquer l'irreversibilite
- [x] Rafraichissement temps reel silencieux (WebSocket) sur les modeles 'caisse_session' et 'caisse_movement', debounce 400 ms — la caisse se met a jour toute seule quand un autre poste enregistre un mouvement
- [x] Le bouton 'Actualiser' ne recharge PAS le resume de periode (asymetrie a reproduire ou corriger)
- [x] Toasts sonner globaux (Toaster monte dans app/layout.tsx); les messages d'erreur backend arrivent sous la forme 'error: <message>' car le backend renvoie {'error': ...} alors que le client cherche d'abord 'detail' puis serialise les paires cle: valeur
- [x] Le pre-remplissage des montants (ouverture ET fermeture) est recalcule a chaque ouverture de dialog a partir de la valeur de stock courante — le stock bougeant avec les ventes, la valeur proposee change pendant la session
- [x] Le DateTimeInput separe volontairement date et heure (Firefox ne propose pas de picker d'heure sur datetime-local); seule la partie date des bornes min/max est appliquee cote client, le serveur reste l'autorite
- [x] Responsive: grilles 2/4 et 2/3/6 colonnes, header du resume qui passe en colonne sur mobile, tableau en overflow-x-auto

### `/dashboard`  —  VERIFIED

Écran Flutter : `features/dashboard/dashboard_screen.dart` (+ `features/dashboard/widgets/*`, `features/dashboard/sections/*`, `models/reports.dart`, `models/campaign.dart`, `state/reports_provider.dart`, `state/campaigns_provider.dart`, `data/repositories/reports_repository.dart`, `data/repositories/campaigns_repository.dart`)  
Référence web : `app/(app)/dashboard/page.tsx` (ReportsCenter), `lib/reports.ts`, `components/reports/*` — la page Rapports a été supprimée côté web, le tableau de bord EST le centre de rapports à 8 sections.  
Fonctionnalités à garantir : 63

- [x] Titre `Tableau de bord` + sous-titre `{section.label} — {section.description}` de la section active
- [x] Squelettes pendant le chargement de l'utilisateur ; carte `Accès refusé — le tableau de bord est réservé au gérant.` si !isGerant (le serveur répond 403 de toute façon : `IsGerant` sur chaque vue d'orders/reporting.py)
- [x] Bouton `Imprimer / PDF` (window.print côté web → PDF de la section affichée via les paquets pdf/printing : en-tête, `Période du … au … (comparée à … → …)`, KPI et tableaux)
- [x] 8 sections, UNE SEULE montée à la fois : Vue générale, Ventes, Financier, Dépenses, Stock, Commandes, Livraisons, Marketing (libellés et descriptions de `SECTIONS`)
- [x] Onglets sur écran large ; sur mobile bouton pleine largeur `Liste des rapports · {section}` ouvrant la liste (libellé + description + coche) ; onglet mémorisé (équivalent du `?tab=` de l'URL)
- [x] Filtres communs : 8 préréglages `Aujourd'hui`, `7 derniers jours`, `Cette semaine`, `Ce mois`, `Mois précédent`, `Cette année`, `Année précédente`, `Personnalisée` (défaut : Ce mois)
- [x] Champs `Du` / `Au` : toute saisie bascule en Personnalisée en conservant l'autre borne ; bornes inversées remises dans l'ordre
- [x] `periodeDepuisPreset` : jour métier d'Antananarivo (appToday), semaine qui commence le lundi, période de comparaison = mois/année/semaine calendaires précédents pour les préréglages, fenêtre de même longueur juste avant pour 7 jours / personnalisée, personnalisée vide = 30 derniers jours
- [x] Sélecteur `Granularité` : `Automatique` (≤ 31 j jour, ≤ 120 j semaine, ≤ 800 j mois, sinon année), `Jour`, `Semaine`, `Mois`, `Année`
- [x] Ligne `{from} → {to} · comparé à {prevFrom} → {prevTo}` (dates JJ/MM/AAAA)
- [x] Bouton Actualiser : vide le cache et recharge la section affichée (icône qui tourne pendant le chargement)
- [x] Appels `GET /api/orders/reports/{section}/?date_from&date_to&prev_from&prev_to&granularity` (+ `dormant_days` pour Stock, `platform` pour Marketing) ; paramètres vides non envoyés
- [x] Cache mémoire par (section, paramètres) : revenir sur un onglet déjà consulté est instantané ; un changement de filtre ne recharge que la section affichée
- [x] Temps réel : sur un événement order / order_status_history / stock_movement / caisse_movement, cache vidé et rechargement SILENCIEUX de la section affichée (débounce 400 ms)
- [x] Formats : `fmtAr` (`1 234 Ar`, arrondi entier), `fmtNb`, `fmtPct` (1 décimale, `—` si null, `+` si signé), `fmtArCourt` (`1.2 M`, `12 k`), `fmtDate`, `fmtDateHeure` (heure d'Antananarivo), `fmtDuree` (`1 h 05` / `12 min`)
- [x] KpiCard : titre + icône, valeur (`—` si absente), `VariationBadge` (flèche ↗/↘/–, vert/rouge, `inverse` pour dépenses/annulations/retours, `n/a (période préc. = 0)` si null), `préc. {valeur}`, détail, mini-courbe de tendance, squelette en chargement
- [x] Grille de KPI responsive : 1 colonne sur mobile, 2 sur tablette, 4 ou 5 sur grand écran
- [x] ChartCard : titre, description, états chargement / erreur / `Aucune donnée sur la période.`
- [x] SerieChart : barres + courbes sur le même axe temporel, axe Ar (fmtArCourt) et axe `nb` à droite, légende, info-bulle (fmtAr / fmtNb), barres empilées (stackId), points si ≤ 31 périodes
- [x] BarresChart (classement horizontal, top 10) et CamembertChart (anneau, valeurs > 0 seulement, PALETTE ou couleurs de statut)
- [x] ReportTable : états chargement / erreur / vide, défilement horizontal, pagination client (`a–b sur n`, `p/pages`, précédent/suivant, uniquement si > 1 page), bouton export Excel (désactivé si vide, colonne `export` ou valeur brute, fichier `{exportNom}_{AAAA-MM-JJ}.xlsx` remis à la feuille de partage), emplacement `actions`, mode compact
- [x] VUE GÉNÉRALE — KPI `Chiffre d'affaires` (+ tendance `ventes`), `Bénéfice net` (vert/rouge, détail `CA − coût d'achat − dépenses (hors achats de stock)`, tendance `benefices`), `Commandes` (détail `{n} livrées`), `Panier moyen` (détail `CA / commandes livrées`) — chacun avec variation et `préc.`
- [x] VUE GÉNÉRALE — graphique `Ventes, dépenses et bénéfices` (description `Par {jour|semaine|mois|année} — {from} → {to}`, barres Ventes (CA) #2563eb et Dépenses #ef4444, courbe Bénéfices #16a34a, hauteur 320) + anneau `Commandes par statut` (STATUT_COULEURS)
- [x] VUE GÉNÉRALE — cartes `Total des bénéfices obtenus` (marge brute des articles livrés sur la période, variation) et `Total du bénéfice estimé` (stock actuel : valeur de vente − valeur d'achat, détail articles / vente / achat) — `benefices` de GET /api/orders/reports/overview/ (ajouté le 12/09/2026, web + Flutter)
- [x] VUE GÉNÉRALE — carte `Comparaison avec la période précédente` : Indicateur / Période actuelle / Période précédente / Écart / Évolution pour Chiffre d'affaires, Marge brute (produits), Dépenses (inverse), Bénéfice net, Commandes, Commandes livrées, Panier moyen
- [x] VENTES — KPI `Chiffre d'affaires` (détail `dont produits …`), `Ventes (commandes livrées)`, `Quantité vendue` (`articles livrés, hors retours`), `Panier moyen`
- [x] VENTES — graphique `Évolution des ventes` (barres `CA produits`, courbe `Commandes livrées` en nb)
- [x] VENTES — tableau `Ventes par {dimension}` avec sélecteur de dimension (data.dimensions, défaut produit), description `Commandes livrées de la période, articles rapportés exclus. Marge = CA − coût d'achat actuel du catalogue.`, colonnes Libellé / Qté vendue / Commandes / CA / Marge / Marge %, export `ventes_par_{dimension}`
- [x] VENTES — `Top 10 par {dimension} (CA)` (barres horizontales, hauteur 360)
- [x] VENTES — `Produits les plus vendus` et `Produits les moins vendus` (`Parmi les produits vendus au moins une fois sur la période.`, 10 par page, exports top_produits / produits_moins_vendus)
- [x] VENTES — `Ventes par livreur` (`CA = total encaissé des commandes livrées (articles + frais).`, Livreur / Commandes / Livrées / Retours / En cours / CA / Taux réussite, vide `Aucune commande assignée à un livreur sur la période.`) + `CA par livreur` (barres #16a34a)
- [x] FINANCIER — 5 KPI `CA brut` (détail produits + livraison), `Coût d'achat des ventes` (inverse, `prix d'achat actuel × quantités`), `Marge brute` (`{taux} du CA produits`), `Dépenses (charges)` (inverse, `caisse … · tournées …` + `· achats de stock exclus : …`), `Bénéfice net` (vert/rouge, `{taux} du CA`)
- [x] FINANCIER — graphique `Rentabilité dans le temps` (CA, Coût d'achat #f59e0b, Dépenses, courbe Bénéfice net, hauteur 320) + carte `Période actuelle vs précédente` (CA brut, Coût d'achat, Marge brute, Dépenses, Bénéfice net avec `préc.`, écart signé et badge)
- [x] FINANCIER — paragraphe explicatif intégral (`Bénéfice net = CA (produits + frais de livraison encaissés) − coût d'achat des articles vendus − sorties de caisse − frais de tournée des livreurs acceptés. …`)
- [x] FINANCIER — tableaux `Rentabilité par produit` (Libellé / Qté / CA / Coût d'achat / Marge (rouge si < 0) / Marge %), `Rentabilité par catégorie`, `Rentabilité par sous-type` (10 par page, exports rentabilite_*)
- [x] DÉPENSES — 4 KPI `Total des sorties` (inverse, `{n} opérations · charges …`), `Sorties de caisse` (inverse, `dont achats de stock … (hors bénéfice)` ou `salaires, pub, autres`), `Frais de tournée (livreurs)` (inverse, `dépenses acceptées par le gérant`), `Marge sur livraison` (vert/rouge, `facturé … − coût réel …`)
- [x] DÉPENSES — graphique `Évolution des dépenses` (barres empilées Caisse #ef4444 / Tournées livreurs #f59e0b) + anneau `Dépenses par catégorie` (Ar)
- [x] DÉPENSES — tableau `Dépenses par catégorie` (description intégrale, Catégorie + badge `Achat de stock · hors bénéfice` si hors_resultat, Source badge Caisse/Livreur, Opérations, Total, Part %) — export depenses_par_categorie
- [x] DÉPENSES — carte `Livraison : facturé au client vs coût réel` (description intégrale, 6 lignes dont `Marge livraison` en gras vert/rouge)
- [x] DÉPENSES — tableau `Détail des dépenses` (`Les 300 opérations les plus récentes de la période.`, Date (date-heure caisse / date livreur), Source, Catégorie, Libellé, Par, Montant, 20 par page, compact, export detail_depenses)
- [x] STOCK — texte `L'état du stock est celui d'aujourd'hui ; l'historique des mouvements suit la période sélectionnée.`
- [x] STOCK — 5 KPI `Quantité en stock` (`{n} variantes · {n} références`), `Valeur du stock (achat)` (`valeur de vente …`), `Produits en rupture` (rouge si > 0, `stock à 0`), `À réapprovisionner` (ambre si > 0, `stock ≤ seuil (dont {n} en stock bas)`), `Stock dormant ({jours} j)` (`… immobilisés`)
- [x] STOCK — graphique `Entrées et sorties de stock` (`Quantités par période`, barres Entrées #16a34a / Sorties #ef4444 en nb) + `Valeur du stock par catégorie` (barres, 10 premières)
- [x] STOCK — tableaux `Ruptures de stock` (`Variantes à 0.`, vide `Aucune rupture.`) et `À réapprovisionner` (`Stock ≤ seuil d'alerte (ruptures comprises).`, vide `Rien à réapprovisionner.`) : Produit / Variante (`—`) / Stock (rouge si ≤ 0) / Seuil d'alerte / Prix d'achat, 10 par page, exports ruptures / reapprovisionnement
- [x] STOCK — `Stock dormant — sans vente depuis {jours} jours` : sélecteur 30 / 60 / 90 jours + `Personnalisé` (nombre ≥ 1) envoyé en `dormant_days`, description intégrale, colonnes Produit / Variante / Stock restant / Dernière vente (date ou badge `Jamais`) / Jours sans vente / Valeur immobilisée, 15 par page, export stock_dormant, vide `Aucun produit dormant sur cette durée.`
- [x] STOCK — `Mouvements par origine` (Origine / Nb / Entrées / Sorties) et `Historique des mouvements` (`{n} mouvements sur la période (300 plus récents affichés).`, Date / Produit (variante) / Type badge Entrée-Sortie / Qté / Origine / Réf. (référence ou note) / Par, 15 par page, compact, export mouvements_stock, vide `Aucun mouvement sur la période.`)
- [x] STOCK — lien `Voir tous les mouvements →` vers /movements
- [x] COMMANDES — 5 KPI `Commandes` (`{n} nouvelles · {n} en préparation/prêtes`), `En livraison`, `Livrées` (`taux de livraison …`), `Annulées` (inverse, rouge si > 0, `taux d'annulation … · {montant_annule}`), `Retournées` (inverse, `taux de retour … · {montant_retourne}`)
- [x] COMMANDES — graphique `Commandes dans le temps` (barres Toutes #94a3b8, courbes Livrées / Annulées / Retours en nb) + anneau `Répartition par statut` (STATUT_COULEURS)
- [x] COMMANDES — tableaux `Détail par statut` (pastille de couleur, Nb, Part %), `Par zone de livraison` (badge `Récupération` pour RECUPERATION, Commandes, Livrées, CA livré), `Par mode de paiement` (Mode, Commandes, CA livré) — exports commandes_par_*
- [x] LIVRAISONS — paragraphe intégral (`La livraison est assurée par les livreurs de l'équipe (pas d'agence externe) … Délai = passage « En livraison » → « Livré ».`)
- [x] LIVRAISONS — 5 KPI `Livraisons terminées` (`{n} en cours`), `Taux de réussite` (vert, `{n} réussies`), `Taux d'échec` (rouge si échecs, `{n} retours`), `Coût moyen / livraison` (`total … · marge …`), `Délai moyen` (fmtDuree, `sur {n} livraisons mesurées`)
- [x] LIVRAISONS — `Comparatif des livreurs` : Livreur / Livraisons / Réussies (vert) / Échouées (rouge) / En cours / Coût total payé / Coût moyen / Frais facturés / Marge livraison (rouge si < 0) / Taux réussite / Taux échec / Délai moyen — export livraisons_par_livreur, vide `Aucune livraison assignée sur la période.`
- [x] LIVRAISONS — graphique `Livraisons réussies et échouées` (barres empilées) + `Taux de réussite par livreur` (barres #16a34a) + tableau `Par zone de livraison` (Zone, Livraisons, Réussies, Échouées, Frais encaissés, Taux réussite)
- [x] MARKETING — paragraphe ROI intégral + `{n} commandes de la période ne sont rattachées à aucune campagne.` si > 0
- [x] MARKETING — 4 KPI `Dépenses de campagnes` (`{n} campagnes · Pub en caisse : …`), `Commandes générées` (`{n} livrées`), `CA généré` (`marge produits …`), `ROI global` (`n/a` si null, signé, vert/rouge, `aucune dépense de campagne`)
- [x] MARKETING — filtre plateforme `Toutes plateformes` / Facebook / Instagram / TikTok / Google / Autre (paramètre `platform`) et bouton `Campagne` (nouvelle campagne)
- [x] MARKETING — tableau `Campagnes` (description `Campagnes actives sur la période. Créez-les ici, puis rattachez les commandes concernées.`, Campagne + badge `Inactive`, Plateforme, Période (`→ en cours`), Dépenses, Commandes (`n (n livrées)`), CA généré, Marge produits, Bénéfice attribué (rouge si < 0), ROI (`n/a (coût 0)`, signé, vert/rouge), actions Modifier / Supprimer ; vide `Aucune campagne sur la période. Cliquez sur « Campagne » pour en enregistrer une.` ; export campagnes_marketing)
- [x] MARKETING — anneau `Dépenses par plateforme`, barres `CA généré par plateforme`, tableau `Par plateforme` (Plateforme / Camp. / Dépenses / Cmd / CA / ROI)
- [x] MARKETING — `Campagnes les plus rentables` / `Campagnes les moins rentables` (5 lignes, vide `Il faut au moins deux campagnes avec un coût pour comparer.`) affichés seulement si l'une des deux listes n'est pas vide
- [x] MARKETING — dialog `Nouvelle campagne` / `Modifier la campagne` : Nom (placeholder `Ex: Boost coques iPhone – septembre`), Plateforme, Dépense (Ar), Début (défaut aujourd'hui), Fin (facultatif, ≥ début), Note ; validation `Nom et date de début sont requis` ; POST/PATCH `/api/orders/campaigns/` ; `Enregistrement…` ; toasts `Campagne créée` / `Campagne modifiée` ; cache vidé et section rechargée
- [x] MARKETING — dialog `Supprimer la campagne « {nom} » ?` (`Les commandes rattachées ne seront pas supprimées, elles perdront seulement leur campagne.`) → DELETE, toast `Campagne supprimée`
- [x] Erreurs de section affichées dans les cartes (message `messageFromError`), jamais de données simulées
- [x] Toutes les clés JSON lues correspondent à orders/reporting.py (kpis.*.actuel/precedent/variation/variation_pct, periode.granularity, series[].label, totaux, livraison, dormant.lignes, par_livreur[].delai_moyen_minutes nullable, roi_pct nullable…)

### `/reports`  —  SUPPRIMÉE CÔTÉ WEB

La page Rapports n'existe plus dans le frontend Next.js : `app/(app)/reports/page.tsx` a été supprimée et
l'entrée « Rapports » retirée du menu ; son contenu (centre de rapports à 8 sections) est devenu le
tableau de bord (`/dashboard`, voir ci-dessus). Côté Flutter, `features/reports/` a été supprimé et la
route `/reports` redirige vers `/dashboard` (anciens liens). Aucune fonctionnalité à porter ici.

## COMPOSANTS PARTAGÉS & SOCLE

### `(global) TopBar — cloche de notifications (dropdown)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 39

- [x] Declencheur : Button variant='ghost' size='icon' className='relative' contenant l'icone Bell h-5 w-5
- [x] Badge compteur : span absolute -top-0.5 -right-0.5, h-4 min-w-4, rounded-full, bg-destructive, text-[10px] font-bold text-destructive-foreground. Affiche unreadCount, ou '9+' si unreadCount > 9. Masque totalement si unreadCount === 0
- [x] Contenu du dropdown : DropdownMenuContent align='end' className='w-96 p-0'
- [x] DropdownMenuLabel : titre 'Notifications' (font-semibold) + Badge variant='secondary' text-[10px] '{n} non lue' / '{n} non lues' (pluriel si >1), affiche uniquement si unreadCount > 0
- [x] Barre d'actions (visible uniquement si notifications.length > 0, border-b) : 2 boutons ghost sm h-7 flex-1 text-xs
- [x] Bouton 'Tout marquer lu' (icone Check h-3.5 w-3.5) -> markAllAsRead(). disabled si unreadCount === 0 || actionLoading. Garde supplementaire en debut de fonction : `if (unreadCount === 0 || actionLoading) return;`
- [x] Bouton 'Tout effacer' (icone Trash2 h-3.5 w-3.5, hover:text-destructive) -> clearAll(). ATTENTION : ne supprime RIEN en base ; masque seulement localement (voir notes). Garde : `if (notifications.length === 0) return;`. Jamais disabled visuellement
- [x] Liste : ScrollArea max-h-96 contenant AU MAXIMUM les 8 premieres notifications (`notifications.slice(0, 8)`)
- [x] Item : DropdownMenuItem avec onSelect={(e)=>e.preventDefault()} -> cliquer sur un item NE FERME PAS le menu et ne navigue nulle part (cursor-default). rounded-none border-b px-4 py-3, last:border-b-0
- [x] Item : pastille ronde 8x8 avec typeIcon(notif_type) ; fond conditionnel : lue = 'bg-muted text-muted-foreground', non lue = 'bg-primary/10 text-primary'
- [x] Item : message text-sm leading-snug line-clamp-2 (tronque a 2 lignes) ; style conditionnel : lue = 'text-muted-foreground', non lue = 'font-medium'
- [x] Item : point bleu de non-lu (span mt-1 h-2 w-2 rounded-full bg-primary) affiche uniquement si !is_read
- [x] Item : Badge variant='outline' text-[10px] + getTypeBadgeClass(notif_type) avec typeLabel(notif_type)
- [x] Item : date formatee (text-[10px] text-muted-foreground) affichee uniquement si created_at present
- [x] Item : bouton texte 'Marquer lu' (ml-auto text-[10px] font-medium text-primary hover:underline) affiche uniquement si !is_read -> markAsRead(id)
- [x] Pied : DropdownMenuSeparator puis DropdownMenuItem asChild justify-center text-sm font-medium contenant un Link Next vers /notifications, libelle 'Voir toutes les notifications'. Toujours affiche, meme quand la liste est vide
- [x] Temps reel : useNotificationsWebSocket({onNotification: handleNewNotification, showToast: true}) -> c'est CE composant qui emet le toast.info global de toute l'application pour chaque notification poussee
- [x] Aucun formulaire, aucun champ de saisie.
- [x] DropdownMenu (Radix, composants ui/dropdown-menu) — le seul overlay : declencheur cloche, contenu w-96 aligne a droite, DropdownMenuLabel d'en-tete, DropdownMenuItem par notification (selection neutralisee), DropdownMenuSeparator, DropdownMenuItem final 'Voir toutes les notifications'.
- [x] ScrollArea Radix (max-h-96) imbriquee dans le dropdown pour le defilement de la liste.
- [x] Aucune confirmation pour 'Tout effacer' (mais l'action n'est que locale, donc non destructive cote donnees).
- [x] Aucun filtre, aucune recherche, aucun tri configurable.
- [x] Troncature fixe a 8 elements affiches (slice(0,8)) — pas de pagination ni de 'voir plus', le lien vers /notifications joue ce role.
- [x] Filtre implicite : toutes les notifications dont l'id est dans localStorage 'stockv2_dismissed_notification_ids' sont retirees, aussi bien au fetch qu'a l'arrivee WebSocket.
- [x] loading : spinner Loader2 h-5 w-5 animate-spin centre, py-8, text-muted-foreground. Note : loading n'est jamais remis a true apres le 1er chargement (pas de bouton actualiser ici)
- [x] empty : bloc centre avec icone Bell h-8 w-8 opacity-30 + texte 'Aucune notification' (px-4 py-10 text-sm text-muted-foreground)
- [x] error de chargement : uniquement console.error('Notifications error:', error), AUCUN toast, AUCUN affichage d'erreur — l'utilisateur voit simplement l'etat vide
- [x] error markAsRead : console.error('Mark read error:', error), silencieux pour l'utilisateur
- [x] error markAllAsRead : console.error('Mark all read error:', error), silencieux
- [x] actionLoading : desactive le bouton 'Tout marquer lu' pendant l'appel
- [x] Aucun etat unauthorized gere ; le hook WS ne se connecte simplement pas si djangoClient.isAuthenticated() est faux
- [x] Persistance locale : cle localStorage 'stockv2_dismissed_notification_ids', valeur = tableau JSON d'ids. Ecriture bornee aux 200 derniers (`ids.slice(-200)`), donc au-dela de 200 ids masques les plus anciens ressortent de l'oubli et reapparaissent dans la cloche
- [x] Lecture defensive : loadDismissed() renvoie [] si window indefini ou si le JSON est invalide (try/catch)
- [x] Compteur unreadCount = notifications.filter(n=>!n.is_read).length calcule sur la liste DEJA filtree des dismissed -> une notification non lue masquee localement ne compte plus dans le badge, alors qu'elle reste non lue en base et comptera sur la page /notifications
- [x] Toast temps reel emis ici pour toute l'app : toast.info(message, {description:`Type : ${typeLabel(notif_type)}`, duration:5000})
- [x] DOUBLON DE TOAST sur /notifications : la cloche (showToast:true) et la page (toast dans son propre handleNewNotification) sont montees simultanement -> 2 toasts identiques pour la meme notification poussee
- [x] Mises a jour optimistes : markAsRead et markAllAsRead modifient l'etat local sans refetch, donc la cloche et la page peuvent diverger jusqu'au prochain rechargement
- [x] Aucun rechargement periodique / polling : la fraicheur depend uniquement du WebSocket et du montage du composant
- [x] La cloche est rendue a gauche du bouton de theme et du menu utilisateur dans la TopBar (flex items-center gap-3), barre sticky top-0 z-10 h-16 px-6 avec border-b

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- État « Connexion... » approximé (aucune valeur reçue et socket non connecté).

### `/auth/pending-approval`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 14

- [x] metadata : title "En attente d'approbation", description "Votre compte est en attente d'approbation par un administrateur"
- [x] Conteneur `min-h-screen flex items-center justify-center bg-gradient-to-b from-background to-muted/20 p-4` (degrade vertical, different des autres pages auth)
- [x] Carte `w-full max-w-md shadow-xl`, header `text-center pb-6`
- [x] Pastille `bg-amber-100 dark:bg-amber-950 p-3 rounded-full` avec icone Clock `h-8 w-8 text-amber-600 dark:text-amber-400` (variantes dark gerees, contrairement a /pending-approval)
- [x] Titre 'En attente d'approbation' (text-2xl) ; description 'Votre compte doit etre approuve par un administrateur'
- [x] ENCADRE INFO ambre : `bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-800 rounded-lg p-4` — sous-titre en gras avec icone Mail : "Qu'est-ce qui se passe maintenant?"
- [x] LISTE NUMEROTEE (numeros en gras, texte amber-800/amber-200) : 1. 'Un administrateur examinera votre demande d'inscription' ; 2. 'Vous recevrez une notification par email une fois approuve' ; 3. 'Vous pourrez vous connecter avec vos identifiants'
- [x] Paragraphe muted : "Le processus d'approbation peut prendre quelques minutes a quelques heures selon la disponibilite de l'administrateur."
- [x] UN SEUL bouton : `variant='outline'` pleine largeur 'Retour a la connexion' dans un `<Link href='/login' className='block'>` (le Link enveloppe le Button, pattern different du `asChild` utilise ailleurs)
- [x] PAS de bouton de deconnexion ici (contrairement a /pending-approval)
- [x] Aucun etat : page statique, pas de polling
- [x] Palette ambre complete avec variantes dark (amber-50/100/200/800/950, texte amber-600/800/900/100/200/400)
- [x] Le point 2 promet une notification par email alors qu'AUCUN backend d'email n'est configure — promesse non tenue par le systeme (regle metier a verifier avant portage)
- [x] Deux pages 'pending approval' coexistent avec des contenus differents : a unifier en une seule route Flutter

### `/* (RootLayout — enveloppe TOUTES les pages, y compris /login, /register, /forgo`  —  IMPLEMENTED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 19

- [ ] metadata.title = 'StockManager' (titre d'onglet global, jamais surcharge par les layouts enfants du perimetre)
- [ ] metadata.description = 'Gestion de stock intelligente'
- [ ] metadata.generator = 'v0.app'
- [ ] Favicons : /icon-light-32x32.png avec media '(prefers-color-scheme: light)', /icon-dark-32x32.png avec media '(prefers-color-scheme: dark)', /icon.svg type image/svg+xml, apple = /apple-icon.png (fichiers presents dans /public)
- [ ] Polices Google chargees : Geist({subsets:['latin']}) et Geist_Mono({subsets:['latin']}) — assignees a des variables _geist / _geistMono JAMAIS utilisees dans le JSX ; la police est en realite appliquee par le token CSS --font-sans: 'Geist','Geist Fallback' de globals.css (et --font-mono: 'Geist Mono')
- [ ] ThemeProvider avec attribute="class" (ajoute la classe .dark sur <html>), defaultTheme="system", enableSystem, disableTransitionOnChange (pas d'animation lors du changement de theme)
- [ ] Toaster sonner global rendu a l'interieur du ThemeProvider, apres {children} — commentaire code : 'Toast global — visible sur toutes les pages'
- [ ] Toaster: position="top-right", richColors (couleurs semantiques success/error/info/warning), closeButton (croix de fermeture sur chaque toast), expand (toasts empiles deplies), toastOptions.duration = 5000 ms
- [ ] Le Toaster (components/ui/sonner.tsx) recupere le theme via useTheme() (defaut 'system') et injecte les variables CSS --normal-bg: var(--popover), --normal-text: var(--popover-foreground), --normal-border: var(--border) + className 'toaster group'
- [ ] <Analytics/> de @vercel/analytics/next rendu UNIQUEMENT si process.env.NODE_ENV === 'production'
- [ ] import { GlobalErrorBoundary } present ligne 6 mais le composant N'EST JAMAIS RENDU dans le JSX — code mort, l'error boundary n'est actif nulle part dans l'app (verifie par grep sur tout le repo)
- [ ] Aucun etat React (composant serveur pur, pas de loading/empty/error)
- [ ] Etat d'erreur global THEORIQUE via GlobalErrorBoundary — non branche (voir features)
- [ ] Langue du document : fr
- [ ] suppressHydrationWarning sur <html> pour eviter le warning d'hydratation du au theme injecte par next-themes
- [ ] body: font-sans antialiased
- [ ] Palette de tokens definie dans app/globals.css : :root (clair) --background oklch(1 0 0), --foreground oklch(0.145 0 0), --primary oklch(0.205 0 0), --destructive oklch(0.577 0.245 27.325), --radius 0.625rem ; .dark (sombre) --background oklch(0.145 0 0), --foreground oklch(0.985 0 0), --primary oklch(0.985 0 0), --destructive oklch(0.396 0.141 25.723)
- [ ] Tokens sidebar dedies : --sidebar / --sidebar-foreground / --sidebar-primary / --sidebar-accent / --sidebar-border / --sidebar-ring (clair et sombre) — utilises seulement par components/ui/sidebar.tsx (non utilise)
- [ ] Rayons derives : --radius-sm = radius-4px, --radius-md = radius-2px, --radius-lg = radius, --radius-xl = radius+4px

### `/(app)/* — shell applicatif protege (couvre /dashboard, /orders, /pickup, /bilan`  —  IMPLEMENTED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 13

- [ ] 'use client' — layout client
- [ ] Redirection /login via router.replace (remplace l'entree d'historique, pas de retour arriere possible)
- [ ] DataSyncProvider englobe tout le shell : ouvre un WebSocket /ws/data/?token=<access> et expose { socketStatus, subscribe(listener) } a toutes les pages enfants
- [ ] Structure : <div class="flex h-screen bg-background"> [Sidebar] <div class="flex-1 flex flex-col overflow-hidden"> [TopBar] <main class="flex-1 overflow-auto">{children}</main> </div> </div>
- [ ] Hauteur fixee a h-screen : seule la zone <main> defile, la TopBar (sticky) et la Sidebar (h-screen) restent fixes
- [ ] Aucun ecran de chargement / splash pendant la verification d'auth : les children sont montes immediatement, donc flash possible de contenu protege avant la redirection
- [ ] unauthorized : redirection client vers /login (aucun ecran intermediaire, aucun toast)
- [ ] Aucun loading/skeleton/empty/error gere a ce niveau
- [ ] socketStatus du DataSyncProvider : 'connecting' | 'connected' | 'disconnected' — expose mais NON affiche dans ce layout (aucun indicateur visuel de connexion dans la coque)
- [ ] bg-background sur le conteneur racine (suit le theme clair/sombre)
- [ ] overflow-hidden sur la colonne droite + overflow-auto sur <main> : le scroll est interne, la page ne scrolle jamais globalement
- [ ] Reconnexion WebSocket automatique du DataSync apres 3000 ms si le code de fermeture != 1000 ; fermeture propre (code 1000) au demontage
- [ ] Modeles pousses par /ws/data/ : product_variant, stock_movement, order, order_status_history, supplier_order, caisse_session, caisse_movement ; actions : created | updated | deleted ; payload { model, action, id, magasin_id }

### `/(app)/* — Sidebar de navigation (rendue sur toutes les routes du groupe (app))`  —  IMPLEMENTED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 49

- [ ] Bouton bascule mobile : Button variant=ghost size=icon, positionne fixed left-4 top-4 z-40, classe lg:hidden ; icone X (h-5 w-5) si ouvert, sinon Menu (h-5 w-5) ; onClick => setOpen(!open)
- [ ] Etat local `open` (useState(false)) : uniquement pour le tiroir mobile, non persiste (pas de cookie/localStorage)
- [ ] Overlay mobile : div fixed inset-0 bg-black/50 z-20 lg:hidden backdrop-blur-sm, rendu seulement si open ; clic => setOpen(false)
- [ ] Bloc logo (p-6, border-b) : carre 40x40 rounded-lg, degrade from-blue-500 to-cyan-600 (dark: from-blue-400 to-cyan-500), shadow-lg, overflow-hidden, contenant une <img> object-cover alt='Logo'
- [ ] Source du logo : user?.store_logo || URL Cloudinary codee en dur 'https://res.cloudinary.com/dxj0d1v3g/image/upload/v1697040915/valheri-wear/logo_2x_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1_1.png' (fallback marque Valheri Wear)
- [ ] Titre h1 : user?.store_name || (isAdmin ? 'Societe' : 'Valheri Wear') — text-lg font-bold tracking-wide, truncate, max-w-[140px]
- [ ] Sous-titre fixe : 'Smart kajy' (text-xs, slate-500 / dark slate-400)
- [ ] Item de menu 1 : 'Tableau de bord' -> /dashboard, icone BarChart3, flag adminOnly
- [ ] Item 2 : 'Commandes' -> /orders, icone ShoppingCart, AUCUN flag (visible par tous les roles)
- [ ] Item 3 : 'Recuperation' -> /pickup, icone PackageCheck, flag adminOnly
- [ ] Item 4 : 'Bilan du jour' -> /bilan, icone Receipt, flag livreurOnly (invisible meme pour l'admin)
- [ ] Item 5 : 'Produits' -> /products, icone Shirt, flag hideLivreur
- [ ] Item 6 : 'Caisse' -> /caisse, icone Wallet, flags hidePreparateur + hideLivreur
- [ ] Item 7 : 'Chats' -> /chats, icone MessageCircle, AUCUN flag (tous les roles)
- [ ] Item 8 : 'Mouvements' -> /movements, icone TrendingUp, flag adminOnly
- [ ] Item 9 : 'Alertes' -> /alerts, icone AlertCircle, flag adminOnly
- [ ] Item 10 : 'Fournisseurs' -> /suppliers, icone Truck, flag adminOnly
- [ ] Item 11 : 'Transferts' -> /transfers, icone ArrowLeftRight, flag superAdminOnly
- [ ] Item 12 : 'Notifications' -> /notifications, icone Bell, flag adminOnly
- [ ] Item 13 : 'Rapports' -> /reports, icone FileBarChart, flag adminOnly
- [ ] Item 14 : 'Magasins' -> /stores, icone Store, flag superAdminOnly
- [ ] Item 15 : 'Super Admin' -> /users, icone Shield, flag superAdminOnly (libelle 'Super Admin' mais URL /users)
- [ ] Item 16 : 'Parametres' -> /settings, icone Settings, flag superAdminOnly
- [ ] Chaque lien : <Link href> avec onClick={() => setOpen(false)} — ferme automatiquement le tiroir mobile a la navigation
- [ ] Etat actif calcule par egalite STRICTE : pathname === item.href (une sous-route comme /orders/42 ne surligne PAS 'Commandes')
- [ ] Indicateur d'actif supplementaire : pastille ronde h-2 w-2 bg-white rounded-full shadow-lg, positionnee ml-auto a droite du libelle
- [ ] Bouton 'Deconnexion' en pied de sidebar : Button variant=ghost, w-full justify-start, icone LogOut h-4 w-4 mr-2, texte slate-500 -> hover slate-900 (dark slate-400 -> white)
- [ ] handleLogout : await djangoClient.auth.logout() puis router.push('/login') puis router.refresh()
- [ ] Aucun sous-menu, aucun groupe/section, aucun accordeon, aucun badge de compteur, aucune recherche dans la sidebar
- [ ] La sidebar n'utilise PAS le kit components/ui/sidebar.tsx (implementation totalement independante)
- [ ] Tiroir mobile (drawer) maison : <aside> translate-x-0 / -translate-x-full + overlay bg-black/50 backdrop-blur-sm — pas de composant Sheet/Dialog radix
- [ ] Aucune confirmation avant deconnexion (action immediate)
- [ ] Filtrage du menu par role (voir roles) — il n'y a aucune recherche, aucun tri, aucune pagination dans la sidebar
- [ ] loading (useCurrentUser.loading = true) : AFFICHE TOUS les items sauf ceux marques superAdminOnly, pour eviter le flash de menu — commentaire code : 'Pendant le chargement on affiche tout pour eviter le flash'. Consequence : un preparateur/livreur voit brievement Tableau de bord, Recuperation, Produits, Caisse, Mouvements, Alertes, Fournisseurs, Notifications, Rapports avant filtrage
- [ ] Pas de skeleton, pas d'etat vide, pas d'etat d'erreur : si GET /users/me/ echoue, useCurrentUser met user=null et loading=false => seuls les items sans flag restent (Commandes, Chats) car isSuperAdmin/isAdminOrSuperAdmin/isLivreur sont tous false ; Produits et Caisse restent aussi visibles (leurs flags sont hideXxx, faux quand user est null)
- [ ] Etat actif / inactif des liens (voir uxDetails)
- [ ] Aucun etat disabled
- [ ] <aside> : fixed left-0 top-0 z-30 h-screen w-64 (256 px), shadow-xl, border-r
- [ ] Fond clair : degrade lineaire from-white via-slate-50 to-slate-100, texte slate-900, bordure slate-200
- [ ] Fond sombre : degrade from-stone-950 via-stone-900 to-stone-950, texte blanc, bordure stone-800
- [ ] Transition : transition-transform duration-300 ; open => translate-x-0, ferme => -translate-x-full ; a partir de lg : lg:relative lg:translate-x-0 (toujours visible, occupe le flux)
- [ ] Bandeau logo et pied de page : degrade horizontal from-slate-50/50 to-transparent (dark from-slate-900/50), separes par border-b / border-t
- [ ] Nav : flex-1 p-4 space-y-1 overflow-y-auto (scroll interne si trop d'items)
- [ ] Lien : flex items-center gap-3 px-4 py-3 rounded-lg transition-all duration-200 group
- [ ] Lien ACTIF : degrade horizontal from-blue-600 to-blue-500, texte blanc, shadow-lg shadow-blue-500/20
- [ ] Lien INACTIF : texte slate-600, hover bg-slate-100 + texte slate-900 (dark : slate-300, hover bg-slate-800/60 + texte blanc)
- [ ] Icone : h-5 w-5, transition-transform 200 ms ; group-hover:scale-110 seulement si NON actif
- [ ] Libelle : text-sm font-medium
- [ ] Aucun tooltip, aucun mode 'icone seule' / collapse desktop : la sidebar desktop est toujours deployee a 256 px

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Dépôt et Tournée (écrans dédiés mobiles) précèdent les entrées web pour le préparateur et le livreur ; /superadmin et /scanner (pages sans lien dans le menu web) sont exposées avec le gating de leur page.

### `/(app)/* — TopBar (barre superieure, rendue sur toutes les routes du groupe (app`  —  IMPLEMENTED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 40

- [ ] Conteneur : border-b, bg-background, sticky top-0 z-10 ; ligne interne flex items-center justify-between h-16 px-6
- [ ] Zone gauche : <div class="flex-1" /> vide — AUCUN titre de page, AUCUN fil d'Ariane, AUCUNE recherche globale
- [ ] Zone droite : flex items-center gap-3 contenant [Notifications] [bascule theme] [menu utilisateur]
- [ ] Composant <Notifications /> (voir sharedComponents et details ci-dessous)
- [ ] Bascule de theme : Button variant=ghost size=icon ; onClick => setTheme(theme === 'dark' ? 'light' : 'dark')
- [ ] Icone de bascule : Sun (h-4 w-4) si mounted && theme === 'dark', sinon Moon (h-4 w-4)
- [ ] Garde d'hydratation : useState(mounted=false) + useEffect(() => setMounted(true), []) ; avant montage l'icone est toujours Moon
- [ ] Declencheur du menu utilisateur : Button variant=ghost, relative h-8 w-8 rounded-full, contenant un Avatar h-8 w-8 avec AvatarFallback (pas d'AvatarImage : la photo de l'utilisateur n'est jamais affichee)
- [ ] Initiales : user.full_name.split(' ').filter(Boolean).map(n => n[0]).join('').toUpperCase().slice(0,2), repli 'U' si pas de full_name
- [ ] Style des initiales : bg-blue-600, texte blanc, text-xs font-semibold, cercle 32x32
- [ ] Deconnexion : djangoClient.auth.logout() appele SANS await (fire-and-forget) puis router.push('/login') immediat — pas de router.refresh() ici, contrairement a la Sidebar
- [ ] DropdownMenu utilisateur (radix) : DropdownMenuContent align="end" w-56 ; contenu = DropdownMenuLabel (identite) / Separator / item 'Mon profil' / Separator / item 'Deconnexion'
- [ ] DropdownMenu Notifications (radix) : DropdownMenuContent align="end" w-96 p-0, liste scrollable (voir details Notifications)
- [ ] Aucune modale de confirmation (ni pour la deconnexion, ni pour 'Tout effacer' les notifications)
- [ ] mounted / non monte : evite le mismatch d'hydratation de l'icone de theme
- [ ] user absent : affiche 'Utilisateur', email vide, aucune ligne de role, initiales 'U'
- [ ] Notifications : loading (spinner Loader2 animate-spin, py-8, texte muted), empty ('Aucune notification' + icone Bell h-8 w-8 opacity-30, px-4 py-10, centre), liste (max 8 items)
- [ ] Bouton 'Tout marquer lu' : disabled si unreadCount === 0 || actionLoading
- [ ] Aucun etat d'erreur visuel pour les notifications : les echecs sont seulement console.error ('Notifications error:', 'Mark read error:', 'Mark all read error:')
- [ ] Ligne d'identite du menu : nom complet (text-sm font-medium truncate) puis email (text-xs text-muted-foreground truncate) puis role en text-xs text-blue-600 font-medium mt-0.5
- [ ] Table de libelles de role : admin -> 'Administrateur', magasin -> 'Gerant de magasin', employer -> 'Commercial' ; si le role n'est pas dans la table, la valeur brute est affichee ; la ligne n'apparait que si user?.role est defini
- [ ] Le sous-role commande_role (PREPARATEUR / LIVREUR) N'EST PAS affiche dans la TopBar : un livreur est etiquete 'Commercial'
- [ ] 'Mon profil' : icone User mr-2 h-4 w-4, Link vers /settings, className cursor-pointer
- [ ] 'Deconnexion' : icone LogOut mr-2 h-4 w-4, classes text-red-600 focus:text-red-600
- [ ] Badge de notifications non lues : span absolu -top-0.5 -right-0.5, h-4 min-w-4, rounded-full, bg-destructive / text-destructive-foreground, text-[10px] font-bold ; affiche le nombre, ou '9+' si > 9 ; masque si 0
- [ ] En-tete du menu notifications : 'Notifications' en font-semibold + Badge variant=secondary text-[10px] '<n> non lue' / 'non lues' (accord au pluriel si > 1)
- [ ] Barre d'actions notifications (visible seulement si la liste n'est pas vide) : 2 boutons ghost size=sm h-7 flex-1 text-xs — 'Tout marquer lu' (icone Check h-3.5 w-3.5) et 'Tout effacer' (icone Trash2, hover:text-destructive) ; separes par border-b
- [ ] 'Tout effacer' est PUREMENT LOCAL : il ajoute les ids dans localStorage['stockv2_dismissed_notification_ids'] (conserve les 200 derniers) et vide la liste affichee — rien n'est supprime en base (commentaire code explicite)
- [ ] Element de notification : DropdownMenuItem avec onSelect preventDefault (le menu ne se ferme pas au clic), border-b, px-4 py-3, cursor-default
- [ ] Pastille d'icone 8x8 rounded-full : bg-muted/text-muted-foreground si lue, bg-primary/10 + text-primary si non lue
- [ ] Icones par type (typeIcon) : sale->Package, user->User, product->Mail, chat->MessageSquare, transfer->ArrowLeftRight, movement->ArrowUpDown, defaut->Bell (h-4 w-4)
- [ ] Libelles de type (typeLabel) : sale->'Vente', product->'Produit', user->'Utilisateur', chat->'Chat', transfer->'Transfert', movement->'Mouvement', defaut->'Autre'
- [ ] Couleurs de badge par type (getTypeBadgeClass) : sale=vert (bg-green-500/10 text-green-700 dark:text-green-400 border-green-500/20), product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange, defaut=muted
- [ ] Message : text-sm leading-snug line-clamp-2 ; muted si lue, font-medium si non lue ; point bleu 2x2 bg-primary a droite si non lue
- [ ] Date : new Date(created_at).toLocaleString('fr-FR', {day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) en text-[10px] muted
- [ ] Lien texte 'Marquer lu' (text-[10px] font-medium text-primary hover:underline, ml-auto) affiche uniquement sur les notifications non lues
- [ ] Liste limitee a notifications.slice(0, 8) dans une ScrollArea max-h-96
- [ ] Pied du menu : DropdownMenuSeparator + item centre 'Voir toutes les notifications' -> Link /notifications
- [ ] Temps reel : chaque message WebSocket declenche toast.info(message, { description: 'Type : <libelle>', duration: 5000 }) et insere la notification en tete de liste (dedoublonnage par id, ignore les ids 'dismissed')
- [ ] Reconnexion WebSocket notifications automatique apres 3000 ms si code de fermeture != 1000 ; connexion seulement si djangoClient.isAuthenticated()

### `* — GlobalErrorBoundary (composant transverse, actuellement NON monte)`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 16

- [ ] Props : { children, fallback? } — fallback = UI de repli personnalisee (defaut : ecran de repli interne)
- [ ] State : { hasError: boolean, error: Error | null }, initialise a { false, null }
- [ ] static getDerivedStateFromError(error) => { hasError: true, error }
- [ ] componentDidCatch(error, info) : construit message = error?.message ?? 'Erreur inattendue' et detail = premiere ligne de info.componentStack.trim().split('\n')[0]
- [ ] toast.error(message, { description: detail || undefined, duration: 8000 })
- [ ] console.error('[GlobalErrorBoundary]', error, info) dans tous les environnements (commentaire : remplacer par Sentry/Datadog en production)
- [ ] handleRetry = () => this.setState({ hasError: false, error: null }) — remonte l'arbre enfant sans recharger la page
- [ ] Si props.fallback est fourni, il est rendu tel quel et le repli interne est ignore
- [ ] Normal : rend simplement this.props.children
- [ ] Erreur : rend le fallback fourni, sinon l'ecran de repli interne
- [ ] Apres 'Reessayer' : retour a l'etat normal (re-render des children)
- [ ] Ecran de repli en styles INLINE (pas de Tailwind) : role='alert', display flex, flexDirection column, alignItems center, justifyContent center, minHeight '100dvh', gap '1rem', fontFamily 'system-ui, sans-serif', color '#ef4444'
- [ ] Icone : emoji ⚠️ en fontSize '2rem'
- [ ] Message : <p> margin 0, fontWeight 600, texte = this.state.error?.message ?? 'Une erreur est survenue'
- [ ] Bouton 'Reessayer' : padding '0.5rem 1.25rem', border '1px solid #ef4444', borderRadius '0.5rem', background transparent, color '#ef4444', cursor pointer, fontSize '0.875rem'
- [ ] Le toast d'erreur dure 8000 ms (contre 5000 ms pour les toasts standards du Toaster global)

**Pourquoi sans objet :**
- Composant non monté côté web (aucune page ne l'utilise) : rien à porter.

### `* — ThemeProvider (wrapper de theme, monte dans app/layout.tsx)`  —  IMPLEMENTED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 6

- [ ] export function ThemeProvider({ children, ...props }: ThemeProviderProps) => <NextThemesProvider {...props}>{children}</NextThemesProvider>
- [ ] Aucune logique propre : ni valeur par defaut interne, ni persistance custom — tout vient des props passees dans app/layout.tsx (attribute='class', defaultTheme='system', enableSystem, disableTransitionOnChange)
- [ ] Persistance geree par next-themes : cle localStorage 'theme' par defaut ; valeurs possibles 'light' | 'dark' | 'system'
- [ ] theme = 'system' | 'light' | 'dark' ; resolvedTheme calcule par next-themes ; risque de mismatch d'hydratation gere par suppressHydrationWarning + le flag `mounted` dans la TopBar
- [ ] attribute='class' => la classe .dark est posee sur <html>, ce qui active le bloc .dark de globals.css
- [ ] disableTransitionOnChange => aucune animation de couleur lors du basculement (evite le flash de transition)

### `(aucune route) — components/ui/sidebar.tsx : kit de primitives shadcn/ui NON UTI`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 48

- [ ] Constantes : SIDEBAR_COOKIE_NAME='sidebar_state', SIDEBAR_COOKIE_MAX_AGE=604800 s (7 jours), SIDEBAR_WIDTH='16rem', SIDEBAR_WIDTH_MOBILE='18rem', SIDEBAR_WIDTH_ICON='3rem', SIDEBAR_KEYBOARD_SHORTCUT='b'
- [ ] SidebarProvider : props defaultOpen=true, open (controle), onOpenChange, className, style ; etats internes _open et openMobile ; setOpen ecrit le cookie `sidebar_state=<bool>; path=/; max-age=604800`
- [ ] toggleSidebar() : bascule openMobile si isMobile, sinon open
- [ ] Raccourci clavier GLOBAL : Ctrl+B ou Cmd+B (event.key === 'b' && (metaKey || ctrlKey)) => preventDefault + toggleSidebar ; listener ajoute/retire sur window
- [ ] state derive : 'expanded' si open, sinon 'collapsed' (expose en data-state)
- [ ] Le provider enveloppe TooltipProvider delayDuration={0} et pose les variables CSS --sidebar-width et --sidebar-width-icon sur un wrapper flex min-h-svh w-full
- [ ] useSidebar() : leve l'erreur 'useSidebar must be used within a SidebarProvider.' hors contexte ; expose { state, open, setOpen, openMobile, setOpenMobile, isMobile, toggleSidebar }
- [ ] Sidebar : props side='left'|'right' (defaut left), variant='sidebar'|'floating'|'inset' (defaut sidebar), collapsible='offcanvas'|'icon'|'none' (defaut offcanvas)
- [ ] collapsible='none' : simple div bg-sidebar text-sidebar-foreground h-full w-(--sidebar-width) flex-col, non repliable
- [ ] Mode mobile (isMobile via useIsMobile, breakpoint 768 px) : rendu dans un <Sheet open={openMobile} onOpenChange={setOpenMobile}> ; SheetContent w-(--sidebar-width) avec --sidebar-width=18rem, p-0, bouton de fermeture natif masque ([&>button]:hidden), side = side
- [ ] SheetHeader en sr-only : SheetTitle 'Sidebar', SheetDescription 'Displays the mobile sidebar.' (accessibilite)
- [ ] Mode desktop : hidden md:block ; div 'sidebar-gap' qui reserve la largeur (w-0 en offcanvas replie, w-(--sidebar-width-icon) en icon) + div 'sidebar-container' fixed inset-y-0 z-10 h-svh, transition sur [left,right,width] 200 ms ease-linear
- [ ] Attributs de donnees exposes pour le style : data-state, data-collapsible, data-variant, data-side, data-slot, data-sidebar
- [ ] SidebarTrigger : Button ghost size=icon size-7 avec PanelLeftIcon + <span class='sr-only'>Toggle Sidebar</span> ; appelle onClick puis toggleSidebar
- [ ] SidebarRail : <button> invisible de 16 px sur le bord, aria-label='Toggle Sidebar', title='Toggle Sidebar', tabIndex={-1}, curseurs w-resize/e-resize selon cote et etat, onClick toggleSidebar
- [ ] SidebarInset : <main> bg-background flex-1 ; en variant=inset ajoute marge, rounded-xl et shadow-sm sur desktop
- [ ] SidebarInput : Input bg-background h-8 w-full shadow-none (champ de recherche de sidebar)
- [ ] SidebarHeader / SidebarFooter : flex flex-col gap-2 p-2
- [ ] SidebarSeparator : Separator bg-sidebar-border mx-2 w-auto
- [ ] SidebarContent : flex min-h-0 flex-1 flex-col gap-2 overflow-auto ; overflow-hidden quand collapsible=icon
- [ ] SidebarGroup : conteneur relative flex w-full min-w-0 flex-col p-2
- [ ] SidebarGroupLabel : titre de section h-8 text-xs font-medium, opacity-0 et -mt-8 quand la sidebar est repliee en mode icone ; supporte asChild
- [ ] SidebarGroupAction : bouton d'action carre 20x20 en haut a droite du groupe (top-3.5 right-3), zone de clic elargie sur mobile (after:-inset-2), masque en mode icone
- [ ] SidebarGroupContent : div w-full text-sm
- [ ] SidebarMenu : <ul> flex flex-col gap-1 ; SidebarMenuItem : <li> group/menu-item relative
- [ ] SidebarMenuButton (cva) : variantes variant='default'|'outline', size='default' (h-8 text-sm) | 'sm' (h-7 text-xs) | 'lg' (h-12 text-sm) ; props asChild, isActive (=> data-active=true : bg-sidebar-accent, font-medium, text-sidebar-accent-foreground), tooltip
- [ ] Tooltip du MenuButton : accepte une string ou les props de TooltipContent ; TooltipContent side='right' align='center', hidden si state !== 'collapsed' || isMobile (le tooltip n'apparait donc QUE en mode icone sur desktop)
- [ ] Etats disabled/aria-disabled du MenuButton : pointer-events-none + opacity-50
- [ ] SidebarMenuAction : bouton carre 20x20 a droite de l'item (top ajuste selon la taille du bouton parent : sm->top-1, default->top-1.5, lg->top-2.5) ; prop showOnHover => opacity-0 sur md, visible au hover/focus/ouvert ; masque en mode icone
- [ ] SidebarMenuBadge : pastille absolue a droite, h-5 min-w-5, text-xs font-medium tabular-nums, pointer-events-none, select-none ; masquee en mode icone
- [ ] SidebarMenuSkeleton : ligne squelette h-8 avec largeur ALEATOIRE entre 50% et 90% (Math.floor(Math.random()*40)+50, memoisee) ; prop showIcon => ajoute un Skeleton size-4 rounded-md
- [ ] SidebarMenuSub : <ul> de sous-menu avec bordure gauche (border-l, mx-3.5, px-2.5, py-0.5), masque en mode icone
- [ ] SidebarMenuSubItem : <li> group/menu-sub-item relative
- [ ] SidebarMenuSubButton : <a> h-7, tailles 'sm' (text-xs) / 'md' (text-sm, defaut), data-active pour l'etat actif, masque en mode icone
- [ ] Exports : Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupAction, SidebarGroupContent, SidebarGroupLabel, SidebarHeader, SidebarInput, SidebarInset, SidebarMenu, SidebarMenuAction, SidebarMenuBadge, SidebarMenuButton, SidebarMenuItem, SidebarMenuSkeleton, SidebarMenuSub, SidebarMenuSubButton, SidebarMenuSubItem, SidebarProvider, SidebarRail, SidebarSeparator, SidebarTrigger, useSidebar
- [ ] SidebarInput : champ de saisie generique (pas de validation, pas de soumission) prevu pour une recherche dans la sidebar
- [ ] Sheet (radix Dialog) utilise comme tiroir mobile de la sidebar, largeur 18rem, bouton de fermeture natif masque, titre/description en sr-only
- [ ] expanded / collapsed (data-state), persiste dans le cookie sidebar_state pendant 7 jours
- [ ] openMobile true/false (Sheet)
- [ ] isActive sur MenuButton et MenuSubButton (data-active=true)
- [ ] disabled / aria-disabled : pointer-events-none + opacity-50
- [ ] loading : SidebarMenuSkeleton (squelette de ligne de menu, largeur aleatoire)
- [ ] Largeurs : 16rem deployee, 3rem en mode icone, 18rem en tiroir mobile ; en variant floating/inset le mode icone vaut calc(var(--sidebar-width-icon) + spacing(4))
- [ ] Transitions : 200 ms ease-linear sur width et left/right
- [ ] variant='floating' : coins arrondis rounded-lg + border + shadow-sm autour du contenu interne
- [ ] group-data-[side=right]:rotate-180 sur le div de gap (miroir pour la sidebar droite)
- [ ] Raccourci clavier Ctrl/Cmd+B documente uniquement par le code (aucune aide visible a l'ecran)
- [ ] Tooltips actifs uniquement en mode icone sur desktop

**Pourquoi sans objet :**
- Kit de primitives shadcn/ui non utilisé par le web : rien à porter.

### `(composant partagé) <ImageUpload /> — zone de dépôt + prévisualisation d'image`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 48

- [ ] Props: onImageSelect: (file: File) => void — OBLIGATOIRE, appelée avec le File validé  — _sans objet côté Flutter : composant web orphelin (jamais importé par une page) ; Flutter : image_picker (reference_dialogs.dart:108, settings_screen.dart:166, stores_screen.dart:752)_
- [ ] Props: maxSize?: number (en MB) — défaut 5  — _sans objet côté Flutter : composant orphelin ; aucun plafond de taille côté Flutter (image_picker recompresse imageQuality 85 / maxWidth 1600)_
- [ ] Props: acceptedFormats?: string[] — défaut ['image/jpeg','image/png','image/webp']  — _sans objet côté Flutter : composant orphelin ; pas de filtre MIME côté Flutter (image_picker ne renvoie que des images)_
- [ ] Props: onUploadStart?: () => void — DÉCLARÉE MAIS JAMAIS APPELÉE dans le corps du composant (prop morte)  — _sans objet côté Flutter : prop morte d'un composant orphelin_
- [ ] Props: onUploadEnd?: () => void — DÉCLARÉE MAIS JAMAIS APPELÉE (prop morte)  — _sans objet côté Flutter : prop morte d'un composant orphelin_
- [ ] 4 états locaux: dragActive (bool), preview (string|null = data URL base64), selectedFile (File|null), error (string|null)  — _sans objet côté Flutter : état React d'un composant orphelin (drag & drop navigateur)_
- [ ] Rendu à deux branches mutuellement exclusives: si `preview` non nul -> vue prévisualisation ; sinon -> vue dropzone  — _sans objet côté Flutter : composant orphelin ; prévisualisation Flutter propre à chaque écran hôte (Image.file)_
- [ ] VUE DROPZONE — conteneur border-2 border-dashed rounded-lg p-8 text-center transition-all  — _sans objet côté Flutter : Tailwind / dropzone navigateur_
- [ ] VUE DROPZONE — icône Upload (lucide) 12x12 text-slate-400 centrée, mb-3  — _sans objet côté Flutter : Tailwind / dropzone navigateur_
- [ ] VUE DROPZONE — titre h3 'Déposer l’image ici' (font-semibold text-slate-900 mb-1)  — _sans objet côté Flutter : glisser-déposer navigateur, sans objet mobile_
- [ ] VUE DROPZONE — sous-titre 'ou cliquez pour parcourir' (text-sm text-slate-600 mb-4)  — _sans objet côté Flutter : glisser-déposer navigateur, sans objet mobile_
- [ ] VUE DROPZONE — bandeau d'erreur conditionnel (affiché seulement si error !== null)  — _sans objet côté Flutter : composant orphelin (aucune validation locale d'image côté Flutter)_
- [ ] VUE DROPZONE — <input type=file> caché (className='hidden', id='image-input'), attribut accept = acceptedFormats.join(',')  — _sans objet côté Flutter : DOM navigateur_
- [ ] VUE DROPZONE — <label htmlFor='image-input'> enveloppant un Button variant='outline' asChild avec <span> contenant icône Upload 4x4 + texte 'Sélectionner une image'  — _sans objet côté Flutter : DOM navigateur_
- [ ] VUE DROPZONE — bloc d'aide bas de zone, text-xs text-slate-500 : ligne 1 'Format supporté: JPEG, PNG, WebP' (texte EN DUR, ne suit pas la prop acceptedFormats), ligne 2 'Taille maximum: {maxSize}MB' (dynamique)  — _sans objet côté Flutter : composant orphelin_
- [ ] GLISSER-DÉPOSER — onDragEnter/onDragOver -> setDragActive(true) ; onDragLeave -> setDragActive(false) ; onDrop -> setDragActive(false) puis handleFile(e.dataTransfer.files[0])  — _sans objet côté Flutter : drag & drop navigateur_
- [ ] GLISSER-DÉPOSER — preventDefault + stopPropagation systématiques sur tous les événements drag/drop  — _sans objet côté Flutter : drag & drop navigateur_
- [ ] GLISSER-DÉPOSER — SEUL LE PREMIER FICHIER est pris (files[0]), un multi-drop est silencieusement tronqué  — _sans objet côté Flutter : drag & drop navigateur_
- [ ] SÉLECTION FICHIER — handleChange sur l'input : prend e.target.files[0] uniquement (l'input n'a pas l'attribut multiple)  — _sans objet côté Flutter : DOM ; image_picker.pickImage renvoie un seul fichier_
- [ ] VUE PRÉVISUALISATION — conteneur relative w-full aspect-square bg-slate-100 rounded-lg overflow-hidden border-2 border-blue-200  — _sans objet côté Flutter : Tailwind / next/image_
- [ ] VUE PRÉVISUALISATION — next/image `fill` className='object-cover', src = data URL base64, alt='Preview'  — _sans objet côté Flutter : next/image / data URL_
- [ ] VUE PRÉVISUALISATION — encart infos fichier bg-slate-50 p-3 rounded border border-slate-200 : icône Check verte 4x4 + libellé 'Image sélectionnée' (text-sm font-medium text-slate-700)  — _sans objet côté Flutter : composant orphelin_
- [ ] VUE PRÉVISUALISATION — nom du fichier selectedFile?.name (text-xs text-slate-600 break-all)  — _sans objet côté Flutter : composant orphelin_
- [ ] VUE PRÉVISUALISATION — taille affichée en MB : (size / 1024 / 1024).toFixed(2) suivi de ' MB' (text-xs text-slate-500)  — _sans objet côté Flutter : composant orphelin_
- [ ] VUE PRÉVISUALISATION — Button variant='outline' pleine largeur (w-full gap-2) avec icône X 4x4 + libellé 'Changer l’image' -> clearSelection()  — _sans objet côté Flutter : composant orphelin_
- [ ] clearSelection() remet selectedFile=null, preview=null, error=null — mais NE PRÉVIENT PAS le parent (aucun onImageSelect(null) / onClear) : le parent garde l'ancien File en mémoire  — _sans objet côté Flutter : bug d'un composant orphelin, à ne pas reproduire_
- [ ] Import de Badge (@/components/ui/badge) présent mais JAMAIS utilisé dans le JSX (import mort)  — _sans objet côté Flutter : import mort JS_
- [ ] useCallback sur handleFile avec deps [onImageSelect, maxSize, acceptedFormats] — acceptedFormats étant un tableau littéral par défaut, la callback est recréée à chaque rendu si le parent ne mémoïse pas  — _sans objet côté Flutter : détail React_
- [ ] Formulaire implicite « sélection d'image » — 1 seul champ : input type=file, id='image-input', accept={acceptedFormats.join(',')}, caché visuellement, piloté par un <label> et par le drop.  — _sans objet côté Flutter : DOM navigateur ; Flutter : bottom sheet caméra/galerie (settings_screen.dart:166)_
- [ ] VALIDATION 1 (taille) — condition file.size > maxSize * 1024 * 1024. Message inline (state error) : `Fichier trop volumineux (max {maxSize}MB)`. Toast : toast.error(`Fichier trop volumineux (max {maxSize}MB)`). Retourne false, le fichier est rejeté (ni selectedFile ni preview ni onImageSelect).  — _sans objet côté Flutter : composant orphelin ; NOTE : aucun contrôle de taille côté Flutter (recompression image_picker uniquement)_
- [ ] VALIDATION 2 (format MIME) — condition !acceptedFormats.includes(file.type). Message inline (state error) : `Format d'image non supporté (JPEG, PNG, WebP)`. Toast : toast.error('Format d'image non supporté') — ATTENTION : le message du toast est PLUS COURT que le message inline (les deux textes diffèrent volontairement/par oubli).  — _sans objet côté Flutter : composant orphelin ; NOTE : aucun contrôle MIME côté Flutter (chat_repository.dart:85-104 déduit seulement le type de l'extension)_
- [ ] validateFile() commence toujours par setError(null) — l'erreur précédente est effacée à chaque nouvelle tentative.  — _sans objet côté Flutter : composant orphelin_
- [ ] COMPORTEMENT APRÈS SUCCÈS — dans l'ordre : setSelectedFile(file) ; onImageSelect(file) appelée IMMÉDIATEMENT (avant que la preview base64 soit prête) ; puis FileReader.readAsDataURL -> onloadend -> setPreview(dataURL) ; puis toast.success(`Image "{file.name}" sélectionnée`).  — _sans objet côté Flutter : FileReader / data URL navigateur_
- [ ] Aucun onerror n'est branché sur le FileReader ici : si la lecture échoue, la preview ne s'affiche jamais et aucune erreur n'est signalée (le parent a pourtant déjà reçu le File).  — _sans objet côté Flutter : FileReader navigateur_
- [ ] Aucun modal/dialog/drawer/popover. Le seul overlay est le sélecteur de fichiers natif du navigateur, ouvert via le <label htmlFor='image-input'>.  — _sans objet côté Flutter : sélecteur natif navigateur ; Flutter ouvre un bottom sheet caméra/galerie_
- [ ] DROPZONE INACTIVE (état par défaut/vide) : border-slate-300 bg-slate-50, hover:border-slate-400  — _sans objet côté Flutter : Tailwind_
- [ ] DROPZONE ACTIVE (survol pendant un drag) : border-blue-500 bg-blue-50  — _sans objet côté Flutter : Tailwind / drag_
- [ ] ERREUR : bandeau bg-red-50 text-red-700 px-3 py-2 rounded text-sm mb-4 avec icône AlertCircle 4x4 — visible UNIQUEMENT dans la branche dropzone ; si une preview est affichée, aucune erreur ne peut apparaître  — _sans objet côté Flutter : Tailwind / composant orphelin_
- [ ] SUCCÈS / IMAGE SÉLECTIONNÉE : bascule complète vers la vue prévisualisation  — _sans objet côté Flutter : composant orphelin_
- [ ] AUCUN état loading/spinner (la lecture base64 est considérée instantanée), AUCUN état disabled, AUCUN état unauthorized  — _sans objet côté Flutter : composant orphelin_
- [ ] Toasts via `sonner` : 1 succès (sélection) + 2 erreurs possibles (taille, format)  — _sans objet côté Flutter : composant orphelin (sonner)_
- [ ] Double signalement d'erreur : bandeau inline persistant + toast éphémère  — _sans objet côté Flutter : composant orphelin_
- [ ] Ratio d'affichage forcé carré (aspect-square) avec object-cover : les images non carrées sont rognées, pas déformées  — _sans objet côté Flutter : CSS_
- [ ] Taille affichée avec 2 décimales fixes (ex. « 1.37 MB »)  — _sans objet côté Flutter : composant orphelin_
- [ ] Nom de fichier en break-all pour ne jamais déborder  — _sans objet côté Flutter : CSS_
- [ ] Transition CSS sur la bordure du dropzone (transition-all)  — _sans objet côté Flutter : CSS_
- [ ] Textes de l'UI en français, formats listés en dur (JPEG, PNG, WebP)  — _sans objet côté Flutter : composant orphelin_
- [ ] next.config.mjs a images.unoptimized = true : les <Image> next se comportent comme de simples <img>  — _sans objet côté Flutter : configuration Next.js_

**Pourquoi sans objet :**
- Composant web orphelin (jamais importé par une page) : glisser-déposer navigateur sans équivalent ; les écrans Flutter choisissent leurs images via image_picker (caméra / galerie).

### `(composant partagé) <ProductImageGallery /> — galerie photos produit + QR codes`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 41

- [ ] Props: images: ProductImage[] (id, image_url, qr_code_image?, size?, color_variant?, is_primary)
- [ ] Props: productName: string — affiché dans la description et dans les alt/QR data
- [ ] Props: productSku: string — affiché dans l'encart détails et encodé dans les données QR copiées
- [ ] Props: onDelete?: (imageId: string) => void — optionnelle, conditionne le bouton supprimer
- [ ] Props: onSetPrimary?: (imageId: string) => void — optionnelle, conditionne le bouton 'Principal'
- [ ] État local selectedImage initialisé à images.find(is_primary) || images[0] || null — CALCULÉ UNIQUEMENT AU MONTAGE (initialiseur de useState) : si la prop `images` change ensuite, la sélection n'est pas resynchronisée
- [ ] État local copiedId (string|null) pour l'animation « copié »
- [ ] EN-TÊTE (liste non vide) — CardTitle 'Galerie d’images et QR Codes', CardDescription `{images.length} image(s) - {productName}`
- [ ] BLOC PRINCIPAL — grille responsive grid-cols-1 md:grid-cols-2 gap-6, rendue seulement si selectedImage non nul
- [ ] COLONNE GAUCHE — image produit : relative w-full aspect-square bg-slate-100 rounded-lg overflow-hidden border border-slate-200, next/image fill object-cover, alt = `{productName} - {color_variant || 'Variante'}`
- [ ] COLONNE GAUCHE — Badge 'Principal' bg-blue-500 en absolute top-2 left-2, affiché uniquement si selectedImage.is_primary
- [ ] COLONNE GAUCHE — métadonnées conditionnelles text-sm text-slate-600 : ligne 'Taille: <b>{size}</b>' si size présent, ligne 'Couleur: <b>{color_variant}</b>' si color_variant présent
- [ ] COLONNE DROITE — titre h4 'Code QR d’identification' (font-semibold text-sm)
- [ ] COLONNE DROITE — QR code affiché seulement si selectedImage.qr_code_image existe : encadré bg-white p-4 border border-slate-200 rounded-lg inline-block, next/image width=200 height=200 rendu en w-48 h-48. AUCUN fallback/placeholder si le QR est absent (bloc simplement vide)
- [ ] ACTION — Button outline size='sm' 'Télécharger' avec icône Download 4x4
- [ ] ACTION — Button outline size='sm' 'Copier données' avec icône Copy 4x4 qui devient Check 4x4 pendant 2 secondes après le clic
- [ ] ENCART DÉTAILS — bg-slate-50 p-3 rounded border border-slate-200 text-xs : '<b>SKU:</b> {productSku}', '<b>ID Image:</b> {id.slice(0,8)}...' (8 premiers caractères + points de suspension), '<b>Créée:</b> {new Date().toLocaleDateString()}'
- [ ] VIGNETTES — section affichée UNIQUEMENT si images.length > 1 : séparateur border-t pt-4 + h4 'Toutes les images'
- [ ] VIGNETTES — grille grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3
- [ ] VIGNETTES — chaque vignette est un <button> carré (aspect-square, rounded-lg, overflow-hidden, border-2, transition-all) : sélectionnée -> 'border-blue-500 ring-2 ring-blue-200', non sélectionnée -> 'border-slate-200 hover:border-slate-300'. Clic -> setSelectedImage(image)
- [ ] VIGNETTES — légende text-xs text-center sous chaque image : ligne size si présent, ligne color_variant (text-slate-500) si présent
- [ ] VIGNETTES — bouton 'Principal' (variant outline, size sm, flex-1 text-xs) rendu SEULEMENT si onSetPrimary fournie ET !image.is_primary -> onSetPrimary(image.id)
- [ ] VIGNETTES — bouton suppression (variant ghost, size sm, icône X 3x3, text-red-500 hover:text-red-700) rendu SEULEMENT si onDelete fournie -> onDelete(image.id) SANS AUCUNE CONFIRMATION
- [ ] handleCopyQRData(imageId) : retrouve l'image dans le tableau, écrit dans le presse-papiers le JSON {sku: productSku, productName, imageId, timestamp: new Date().toISOString()} — NOTE: le payload copié NE contient PAS size ni color_variant, contrairement au QR généré par lib/qrcode-generator.ts
- [ ] handleDownloadQRCode(imageId) : si qr_code_image existe, crée dynamiquement un <a href={qr_code_image} download=`qrcode-{productSku}-{imageId}.png`>, l'ajoute au body, click(), le retire. Si qr_code_image absent : ne fait RIEN et n'affiche AUCUN message
- [ ] Aucun modal/dialog/popover/confirmation. La suppression d'une image est IMMÉDIATE au clic (pas de ConfirmDeleteDialog branché ici).
- [ ] Aucune recherche, aucun filtre, aucun tri, aucune pagination. Les images sont affichées dans l'ordre exact du tableau reçu.
- [ ] ÉTAT VIDE — si !images || images.length === 0 : Card avec CardTitle 'Galerie d’images', CardDescription 'Aucune image ajoutée pour ce produit' et CardContent centré (text-center py-8 text-slate-500) 'Ajoutez des images pour visualiser les photos du produit et leurs codes QR'. Retour anticipé, rien d'autre n'est rendu.
- [ ] ÉTAT 1 SEULE IMAGE — le bloc principal s'affiche mais la section vignettes est masquée (condition images.length > 1)
- [ ] ÉTAT SÉLECTION — vignette active mise en évidence par bordure bleue + ring
- [ ] ÉTAT COPIÉ — icône Copy remplacée par Check pendant exactement 2000 ms (setTimeout non nettoyé au démontage)
- [ ] AUCUN état loading/skeleton, AUCUN état error, AUCUN état disabled, AUCUN état unauthorized
- [ ] Toast succès copie : 'QR code data copied to clipboard' — EN ANGLAIS alors que toute l'UI est en français
- [ ] Toast succès téléchargement : 'QR code downloaded' — EN ANGLAIS également
- [ ] Feedback visuel du copier : bascule d'icône Copy -> Check pendant 2 s (le libellé du bouton reste 'Copier données')
- [ ] Badge 'Principal' bleu (bg-blue-500) posé en overlay sur l'image principale
- [ ] Couleur destructive du bouton supprimer : text-red-500, hover text-red-700
- [ ] Nom de fichier de téléchargement normalisé : `qrcode-{SKU}-{imageId}.png`
- [ ] BUG/PIÈGE UX : le champ 'Créée:' affiche `new Date().toLocaleDateString()` — c'est la DATE DU JOUR, recalculée à chaque rendu, pas la vraie date de création de l'image (la donnée n'existe pas dans l'interface ProductImage)
- [ ] Format de date : toLocaleDateString() sans locale explicite -> dépend de la locale du navigateur/appareil
- [ ] ID d'image tronqué à 8 caractères pour l'affichage

**Pourquoi sans objet :**
- Non monté dans /products côté web et sans modèle backend (une seule photo par référence) : non portable en l'état.

### `(composant partagé) <ConfirmDeleteDialog /> — modal de suppression avec ré-authe`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 38

- [ ] Props: open: boolean — contrôlé par le parent (typiquement `open={!!deleteTarget}`)  — _sans objet côté Flutter : contrôle React ; Flutter : showDialog à la demande (superadmin_screen.dart:556-563, users_screen.dart:1698-1700)_
- [ ] Props: onOpenChange: (open: boolean) => void  — _sans objet côté Flutter : contrôle React ; Navigator.pop(true/false)_
- [x] Props: title?: string — défaut 'Confirmer la suppression' ; les deux appelants passent 'Supprimer cet utilisateur'
- [x] Props: description?: React.ReactNode — nœud React libre (les appelants y injectent le nom en gras) ; rendu seulement si fourni
- [x] Props: onConfirm: (password: string) => Promise<void> — DOIT throw/reject avec une Error dont le `message` sera affiché tel quel à l'utilisateur en cas d'échec
- [x] 3 états locaux : password (string), loading (bool), error (string|null)
- [ ] DialogContent className='sm:max-w-md'  — _sans objet côté Flutter : Tailwind ; SizedBox(width: 420) superadmin_screen.dart:616-617_
- [x] DialogTitle en flex items-center gap-2 text-red-600 avec icône ShieldAlert h-5 w-5 + le titre
- [ ] Formulaire <form onSubmit={handleSubmit} className='space-y-4'>  — _sans objet côté Flutter : DOM ; onSubmitted du TextField (superadmin_screen.dart:645-647, users_screen.dart:1787-1789)_
- [x] Bouton 'Annuler' : type='button', variant='outline', disabled={loading}, onClick -> handleOpenChange(false)
- [x] Bouton 'Supprimer définitivement' : type='submit', variant='destructive', disabled={loading || !password}
- [x] Pendant la soumission le bouton affiche <Loader2 className='h-4 w-4 mr-2 animate-spin' /> + le texte 'Suppression...'
- [x] handleOpenChange(next) : si loading === true la fonction RETOURNE IMMÉDIATEMENT — impossible de fermer le modal (croix, Échap, clic overlay, bouton Annuler) tant que la requête est en cours
- [x] À la fermeture (next === false) : reset password='' et error=null
- [x] Après un succès : setPassword('') puis onOpenChange(false) — le modal se referme tout seul
- [x] Formulaire « confirmation par mot de passe » — 1 SEUL CHAMP.
- [x] CHAMP: Label 'Votre mot de passe' (htmlFor='confirm-delete-password') + Input id='confirm-delete-password', type='password', autoComplete='current-password', placeholder='••••••••', autoFocus, required, disabled={loading}, value={password}.
- [x] onChange du champ : setPassword(valeur) ET setError(null) — l'erreur affichée disparaît dès la première frappe.
- [x] VALIDATION CLIENT : si !password au submit -> setError('Mot de passe requis.') et sortie anticipée (aucun appel réseau). Le bouton submit est de toute façon disabled tant que password est vide, donc ce garde-fou ne se déclenche que si le formulaire est soumis par la touche Entrée dans un cas limite.
- [x] SOUMISSION : e.preventDefault() -> setLoading(true) -> setError(null) -> await onConfirm(password).
- [x] SUCCÈS : setPassword('') puis onOpenChange(false) — le modal se ferme ; le message de succès (toast) est émis par la page appelante, pas par le composant.
- [x] ÉCHEC : catch(err) -> setError(err?.message || 'Erreur lors de la suppression.') ; le modal RESTE OUVERT, le mot de passe saisi est CONSERVÉ dans le champ, l'utilisateur peut corriger et resoumettre.
- [x] finally : setLoading(false) dans tous les cas.
- [x] Affichage de l'erreur : <p className='text-sm text-red-600'>{error}</p> juste sous l'input.
- [ ] EST lui-même le dialog (Dialog + DialogContent + DialogHeader + DialogTitle + DialogDescription + DialogFooter de @/components/ui/dialog, basé sur Radix).  — _sans objet côté Flutter : Radix ; AlertDialog Material (superadmin_screen.dart:608)_
- [x] Usage /superadmin : description = 'Vous êtes sur le point de supprimer définitivement <b>{deleteTarget.name}</b>. Cette action est irréversible. Entrez votre mot de passe pour confirmer.'
- [x] Usage /users : description IDENTIQUE (même texte, même mise en forme du nom en font-medium text-foreground).
- [x] IDLE : bouton submit disabled tant que le champ mot de passe est vide
- [x] LOADING : input disabled, bouton Annuler disabled, bouton submit disabled + spinner Loader2 + libellé 'Suppression...', fermeture du modal verrouillée
- [x] ERROR : message rouge sous le champ, modal maintenu ouvert, saisie conservée
- [x] SUCCESS : fermeture automatique + reset du champ (feedback textuel délégué au parent)
- [x] Pas d'état empty/unauthorized (le composant n'est monté que quand la cible existe)
- [x] Code couleur destructif : titre text-red-600 + icône bouclier d'alerte ShieldAlert, bouton principal variant='destructive'
- [x] autoFocus sur le champ mot de passe à l'ouverture -> clavier ouvert immédiatement
- [x] Libellé volontairement explicite 'Supprimer définitivement' (et non 'OK'/'Confirmer')
- [x] Le message d'erreur serveur est affiché BRUT (err.message) — c'est le backend Django qui rédige le texte vu par l'utilisateur (ex. mot de passe incorrect)
- [x] Aucun toast émis par le composant : succès et erreurs réseau sont respectivement toastés/affichés par la page appelante ou inline
- [x] Verrouillage anti-double-soumission complet pendant loading

### `(composant partagé) <AIAnalysis /> — carte « Analyse IA Stratégique ». Monté en `  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 41

- [ ] Props: data: AIAnalysisData (un seul objet, tous les champs optionnels)
- [ ] AIAnalysisData.periode?: string
- [ ] AIAnalysisData.ca?: number
- [ ] AIAnalysisData.beneficeNet?: number
- [ ] AIAnalysisData.valeurStock?: number
- [ ] AIAnalysisData.beneficeEstimeStock?: number
- [ ] AIAnalysisData.ventesImpayeesCount?: number
- [ ] AIAnalysisData.topProduits?: { name, qty, revenue?, profit? }[]
- [ ] AIAnalysisData.produitsSansMouvement?: { name }[]
- [ ] AIAnalysisData.rupturesStock?: { name, stock? }[]
- [ ] AIAnalysisData.stockBas?: { name, stock?, seuil? }[]
- [ ] AIAnalysisData.repartitionMouvements?: Record<string, number>
- [ ] AIAnalysisData.topVendeurs?: { name, revenue }[]
- [ ] AIAnalysisData.topMagasins?: { name, revenue }[]
- [ ] 3 états locaux : analysis (string, '' au départ), loading (bool), error (bool)
- [ ] Carte à dégradé : bg-gradient-to-br from-indigo-50 to-purple-50, dark:from-indigo-950/20 dark:to-purple-950/20, border-indigo-100 dark:border-indigo-900/50
- [ ] CardTitle text-lg flex items-center gap-2, couleur text-indigo-700 dark:text-indigo-400, icône Sparkles h-5 w-5, libellé 'Analyse IA Stratégique'
- [ ] CardDescription : 'Générez une analyse basée sur le CA, le bénéfice, le stock et les produits les plus vendus.'
- [ ] BOUTON PRIMAIRE 'Générer l'analyse' — rendu uniquement si (!analysis && !loading) ; classes bg-indigo-600 hover:bg-indigo-700 text-white ; icône Sparkles h-4 w-4 mr-2
- [ ] BOUTON SECONDAIRE 'Régénérer' — rendu dans l'état résultat ; size='sm', variant='outline', disabled={loading}, icône Sparkles h-3.5 w-3.5 mr-2 ; relance exactement le même appel
- [ ] Affichage du résultat : <div className='text-sm whitespace-pre-wrap leading-relaxed'> — les retours à la ligne du modèle sont préservés, aucun rendu markdown
- [ ] Couleur du résultat conditionnelle : error ? 'text-red-600 dark:text-red-400' : 'text-gray-800 dark:text-gray-200'
- [ ] Aucun bouton copier/exporter/partager le texte généré
- [ ] Aucune annulation possible pendant la génération (pas d'AbortController côté client)
- [ ] Aucune persistance : l'analyse est perdue au démontage/refresh, et n'est jamais renvoyée au backend
- [ ] Aucun formulaire, aucun champ saisissable : l'unique interaction est le déclenchement du bouton.
- [ ] Aucun modal/dialog/popover : tout est rendu inline dans la Card.
- [ ] IDLE (aucune analyse, pas de chargement) : uniquement le bouton 'Générer l'analyse'
- [ ] LOADING (skeleton) : phrase d'attente text-xs text-muted-foreground mb-1 'Génération en cours (modèle IA local — cela peut prendre plusieurs minutes)...' + 4 <Skeleton> h-4 de largeurs w-full, w-[90%], w-[80%], w-[85%]
- [ ] SUCCESS : texte de l'analyse en gris foncé + bouton 'Régénérer'
- [ ] ERROR HTTP (res.ok === false) : même mise en page que success mais texte en rouge (le contenu affiché est le message d'erreur renvoyé par la route)
- [ ] ERROR RÉSEAU (throw du fetch) : console.error + analysis = 'Erreur réseau lors de l'appel à l'analyse IA.' + error = true (affiché en rouge)
- [ ] Un nouveau clic sur 'Régénérer' remet error à false et loading à true avant de relancer
- [ ] Pas d'état empty distinct (l'état idle joue ce rôle), pas d'état unauthorized
- [ ] Identité visuelle IA : dégradé indigo->violet + icône Sparkles répétée (titre, bouton générer, bouton régénérer)
- [ ] Support du thème sombre explicite sur la carte, le titre et le texte de résultat
- [ ] Avertissement d'attente longue affiché AVANT les skeletons (le modèle tourne en CPU sur le VPS, plusieurs minutes possibles)
- [ ] Le texte du modèle est demandé en français, texte brut sans markdown (contrainte imposée dans le prompt serveur) et rendu en whitespace-pre-wrap
- [ ] La carte est le DERNIER élément de la page /reports (après les KPI, graphiques et tableaux)
- [ ] La page /reports se rafraîchit en temps réel via useRealtimeRefresh(['product_variant','order','stock_movement']) mais l'analyse IA déjà générée N'EST PAS régénérée automatiquement : elle devient silencieusement obsolète
- [ ] Formatage des montants côté /reports : Intl.NumberFormat('fr-MG') + suffixe ' Ar' (les nombres envoyés à l'IA sont en revanche bruts)

**Pourquoi sans objet :**
- N'est plus monté nulle part (la page Rapports qui le portait a été supprimée) : rien à porter.

### `POST /api/ai/analyze — route API Next.js (Route Handler)`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 23

- [ ] Export unique : `export async function POST(req: Request)` — aucune autre méthode HTTP n'est exposée (GET/PUT/DELETE -> 405 par défaut Next.js)
- [ ] Configuration par variables d'environnement : OLLAMA_BASE_URL (défaut 'http://localhost:11434') et OLLAMA_MODEL (défaut 'qwen3:4b')
- [ ] buildPrompt(data) : fonction pure, seul endroit à éditer pour changer le ton/contenu/longueur (documenté dans l'en-tête du fichier)
- [ ] Le prompt insère la période entre parenthèses seulement si data.periode est fourni
- [ ] Chiffres clés injectés avec fallback textuel 'non disponible' pour ca, beneficeNet, valeurStock, beneficeEstimeStock ; ventesImpayeesCount tombe à 0 (`?? 0`)
- [ ] Toutes les listes sont injectées en JSON.stringify avec fallback [] ou {} : topProduits, produitsSansMouvement, rupturesStock, stockBas, repartitionMouvements, topVendeurs, topMagasins
- [ ] Le prompt demande explicitement 4 sections : 1) résumé de la santé financière (CA, bénéfice, marge) 2) observation sur les produits qui se vendent le mieux et ceux qui ne bougent pas 3) alerte ruptures + stocks bas avec priorité de réapprovisionnement 4) conseils actionnables concrets ventes et cash-flow
- [ ] Consigne de format imposée au modèle : français, texte brut avec sauts de ligne, SANS markdown (pas de gras, pas d'astérisques, pas de titres #), paragraphes courts, concis et professionnel
- [ ] Toutes les valeurs monétaires sont libellées en Ar (Ariary malgache) dans le prompt
- [ ] Flag `think: false` envoyé à Ollama : qwen3 est un modèle « hybrid reasoning » qui sinon passe l'essentiel du temps à raisonner en interne ; Ollama ignore silencieusement le flag si le modèle ne le supporte pas
- [ ] `stream: false` : réponse en un bloc, pas de streaming vers le client
- [ ] Timeout requête : AbortSignal.timeout(600_000) = 10 MINUTES (volontairement large, CPU sur VPS)
- [ ] Post-traitement : suppression des blocs de raisonnement via text.replace(/<think>[\s\S]*?<\/think>/gi, '') puis .trim()
- [ ] Le corps de requête est parsé sans aucune validation de schéma (pas de zod) : tous les champs sont optionnels et non vérifiés
- [ ] Redémarrage du conteneur frontend nécessaire pour prendre en compte un changement de prompt (documenté : docker compose -f docker-compose.prod.yml up -d --build frontend)
- [ ] SUCCÈS : statut 200 avec le texte nettoyé
- [ ] ERREUR TIMEOUT (error.name === 'TimeoutError') : hint = 'Le modèle a mis trop de temps à répondre (délai dépassé).'
- [ ] ERREUR AUTRE (Ollama injoignable, 4xx/5xx, JSON invalide...) : hint = `Impossible de contacter Ollama sur {OLLAMA_BASE_URL}. Vérifiez qu'Ollama tourne sur le VPS et que OLLAMA_BASE_URL est bien configuré (voir roadmap.md).` — l'URL interne du VPS FUIT donc dans la réponse envoyée au navigateur
- [ ] Toute erreur est aussi console.error("Erreur lors de l'analyse IA (Ollama) :", error) côté serveur
- [ ] Le client (<AIAnalysis/>) affiche indistinctement le champ `analysis` dans les deux cas, en rouge quand le statut n'est pas ok
- [ ] Le contrat d'API est volontairement « toujours du texte » : jamais de champ `error` séparé, ce qui permet au composant d'afficher l'erreur au même endroit que l'analyse
- [ ] Le délai de 10 minutes doit être répliqué côté client Flutter (timeout Dio/http par défaut bien plus court, sinon l'appel échouera avant Ollama)
- [ ] Aucun cache : chaque clic sur Générer/Régénérer relance une inférence complète

**Pourquoi sans objet :**
- Route Next.js utilisée uniquement par <AIAnalysis />, lui-même démonté : rien à porter. L'assistant (bulle) utilise POST /api/ai/assistant, porté.

### `POST /api/ai/check-duplicates — route API Next.js (Route Handler)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 26

- [ ] Export unique : `export async function POST(req: Request)`  — _sans objet côté Flutter : route Next.js ; Flutter remplace l'inférence par une analyse locale findNearDuplicates (features/catalog/import_export.dart:167-215)_
- [ ] Même configuration Ollama que /api/ai/analyze : OLLAMA_BASE_URL (défaut http://localhost:11434), OLLAMA_MODEL (défaut qwen3:4b), stream:false, think:false, AbortSignal.timeout(600_000) = 10 minutes  — _sans objet côté Flutter : aucune inférence Ollama côté Flutter (analyse locale)_
- [x] COURT-CIRCUIT : si !data.newNames?.length -> renvoie immédiatement { warnings: [] } SANS appeler Ollama (économise une inférence de plusieurs minutes)
- [ ] Le prompt injecte les deux listes en JSON.stringify : d'abord les références existantes du catalogue, puis les nouvelles créées par l'import  — _sans objet côté Flutter : pas de prompt LLM (analyse locale)_
- [x] Consigne au modèle : ne signaler QUE les références suspectes (ne pas inclure celles clairement légitimes), ignorer les différences de casse (déjà gérées ailleurs), détecter faute de frappe / variante d'écriture / espace ou tiret en trop / modèle très proche type « A05 » vs « A05S » pouvant être une erreur de saisie
- [x] Format de sortie imposé : tableau JSON STRICT d'objets {"nouvelle", "ressemble_a", "raison"}, ou exactement `[]` si rien de suspect, sans texte avant/après ni balises markdown
- [ ] NETTOYAGE 1 : suppression des blocs <think>...</think> (regex /gi) puis trim  — _sans objet côté Flutter : pas de sortie LLM à nettoyer_
- [ ] NETTOYAGE 2 : suppression d'un éventuel fence markdown malgré la consigne — replace(/^```(?:json)?\s*/i, '') puis replace(/```\s*$/i, '') puis trim  — _sans objet côté Flutter : pas de sortie LLM à nettoyer_
- [ ] PARSING TOLÉRANT : JSON.parse dans un try/catch ; le résultat n'est retenu que si Array.isArray(parsed) ; toute réponse non-JSON -> warnings = [] (on ne casse jamais l'UI d'un import par ailleurs réussi)  — _sans objet côté Flutter : pas de JSON à parser ; l'échec de l'analyse ne casse pas la revue (catchError → done, import_export.dart:251-254)_
- [ ] Aucune validation de la forme des objets retournés par le modèle (nouvelle/ressemble_a/raison sont supposés présents et affichés tels quels côté /products)  — _sans objet côté Flutter : objets typés Dart, pas de sortie LLM_
- [x] Dialog de revue d'import (dans /products, app/(app)/products/page.tsx) piloté par `open={!!importReview}` — c'est là que le résultat de cette route est affiché.
- [x] Contenu du dialog : 2 cartes côte à côte (grid-cols-2) — « Ajouté » (vert) avec created_references référence(s) + created_variants couleur(s), « Mis à jour » (bleu) avec updated_references + updated_variants.
- [x] Puis : liste 'Nouvelles références :' (line-clamp-3, noms joints par ', '), liste 'Références mises à jour :' (line-clamp-3), ligne '{skipped_count} ligne(s) déjà traitée(s) ignorée(s).' si > 0, ligne rouge '{errors_count} ligne(s) en erreur — voir le fichier téléchargé.' si > 0.
- [x] Encadré 'Analyse IA (quasi-doublons)' (rounded-md border p-3) affichant les 4 états ci-dessus.
- [x] Footer du dialog — 3 boutons : « Annuler l'import » (variant destructive, libellé 'Annulation...' pendant cancellingImport) = SEUL bouton qui déclenche un appel réseau ; « Modifier » (variant outline) = ferme la revue et pré-remplit la recherche du tableau sur la 1re référence touchée + toast.info ; « Enregistrer » (primaire) = ne fait qu'un toast.success('Import conservé.') et referme (l'import est DÉJÀ en base).
- [x] ENTRÉE VIDE : réponse instantanée { warnings: [] } (côté /products cela correspond à aiStatus='skipped' -> texte 'Aucune nouvelle référence à vérifier.')
- [x] EN COURS côté client : aiStatus='loading' -> 'Analyse en cours…' (text-muted-foreground) dans le dialog de revue
- [x] TERMINÉ SANS ALERTE : aiStatus='done' + aiWarnings vide -> 'Aucun doublon suspect détecté.'
- [x] TERMINÉ AVEC ALERTES : liste <ul> d'items « "{nouvelle}" ressemble à "{ressemble_a}" — {raison} » (les noms en font-medium, la raison en suffixe seulement si non vide)
- [x] OLLAMA INDISPONIBLE / .catch() côté client : aiStatus passe quand même à 'done' (avec aiWarnings inchangé/vide) — la vérification est simplement marquée non concluante, l'import reste valide
- [ ] Log serveur en cas d'échec : console.error('Erreur lors de la revue IA des doublons (Ollama) :', error)  — _sans objet côté Flutter : log serveur Next.js_
- [ ] Contrat « best-effort » assumé : statut 200 même en erreur, warnings vide plutôt qu'une exception  — _sans objet côté Flutter : pas de route HTTP ; même esprit (l'import reste valide)_
- [x] Résultat affiché DANS le dialog de revue plutôt qu'en toast séparé, pour que l'utilisateur voie tout au même endroit avant de décider Enregistrer/Modifier/Annuler
- [x] Toast d'erreur d'import (côté /products) : `{errors_count} ligne(s) en erreur — voir la colonne "Statut" du fichier téléchargé.` avec duration: 10000 ms
- [x] Le champ `existingNames` est construit en concaténant marque + nom de référence : `${brand_name} ${reference_name}`
- [x] Les guillemets typographiques autour des noms dans la liste d'alertes sont des guillemets droits ("...")

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Route Next.js injoignable depuis l'app (qui ne parle qu'à Django) : remplacée par l'analyse locale de import_export.dart (voir /products).

### `(module partagé) lib/image-service.ts — service de gestion des images`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 18

- [ ] Interface ImageUploadResult { url: string; filename: string; size: number }
- [ ] uploadImage(file: File): Promise<ImageUploadResult> — lit le fichier via FileReader.readAsDataURL, renvoie url = data URL base64 complète, filename = `${Date.now()}-${file.name}` (préfixe timestamp anti-collision), size = file.size
- [ ] uploadImage — reader.onload dans un try/catch qui reject(new Error('Failed to process image')) ; reader.onerror -> reject(new Error('Failed to read image file'))
- [ ] uploadImageToBackend(file: File, productId: string): Promise<ImageUploadResult> — construit un FormData avec les champs 'image' (le File) et 'product_id' (l'id), POST /api/upload, renvoie { url: data.url, filename: data.filename, size: file.size }
- [ ] uploadImageToBackend — si !response.ok : throw new Error('Failed to upload image') ; le catch global log '[v0] Error uploading image to backend:' puis throw new Error('Failed to upload image to backend storage') (le message d'origine est PERDU)
- [ ] getOptimizedImageUrl(url, width?, height?, quality?): string — si url.startsWith('data:') retourne l'URL telle quelle ; sinon construit des query params width/height/quality (seulement ceux fournis) et les concatène avec '&' si l'URL contient déjà '?', sinon '?' ; si aucun paramètre, retourne l'URL inchangée
- [ ] validateImageFile(file, maxSizeMB = 5, acceptedFormats = ['image/jpeg','image/png','image/webp']): { valid: boolean; error?: string } — même logique que ImageUpload mais messages EN ANGLAIS
- [ ] getImageDimensions(imageUrl: string): Promise<{width, height}> — instancie un `new Image()` du DOM avec crossOrigin = 'anonymous', résout sur onload avec img.width/img.height, reject(new Error('Failed to load image')) sur onerror
- [ ] deleteImage(imagePath: string): Promise<void> — DELETE /api/upload?path={imagePath} (le chemin est interpolé BRUT dans l'URL, sans encodeURIComponent) ; throw 'Failed to delete image' si !ok, log '[v0] Error deleting image:'
- [ ] batchUploadImages(files: File[], productId: string, onProgress?: (current, total) => void): Promise<ImageUploadResult[]> — boucle SÉQUENTIELLE (for + await, pas de Promise.all), appelle uploadImage(files[i]) (donc la version BASE64, jamais uploadImageToBackend) ; le paramètre productId est reçu mais JAMAIS UTILISÉ
- [ ] batchUploadImages — en cas d'erreur sur un fichier : console.error(`[v0] Error uploading file ${i+1}:`) et CONTINUE avec le suivant ; le tableau retourné peut donc être plus court que `files` et le rapprochement index<->fichier est perdu
- [ ] batchUploadImages — onProgress?.(i + 1, files.length) appelé UNIQUEMENT après un succès (un échec ne fait pas avancer la barre de progression)
- [ ] Aucun état UI (module non-React) : uniquement des promesses résolues/rejetées et des booléens de validation.
- [ ] Messages d'erreur (tous en anglais) : 'Failed to process image', 'Failed to read image file', 'Failed to upload image', 'Failed to upload image to backend storage', 'Failed to load image', 'Failed to delete image', `File size exceeds ${maxSizeMB}MB limit`, 'File format not supported. Use JPEG, PNG, or WebP'.
- [ ] Tous les logs sont préfixés '[v0]' (héritage du générateur v0.dev) — utile pour repérer le code non retravaillé
- [ ] Limite par défaut cohérente avec <ImageUpload/> : 5 MB, JPEG/PNG/WebP
- [ ] Stratégie actuelle = data URL base64 : très lourd si stocké en base ou transmis (≈ +33 % par rapport au binaire), à remplacer par un vrai upload multipart en Flutter
- [ ] Le nommage `${Date.now()}-${file.name}` conserve le nom d'origine (donc les accents/espaces) — à normaliser côté mobile

**Pourquoi sans objet :**
- Service d'images navigateur (canvas, localStorage) sans usage côté API Django : sans équivalent mobile nécessaire (les photos passent par image_picker + multipart).

### `(module partagé) lib/qrcode-generator.ts — génération et lecture de QR codes`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 15

- [ ] Dépendance npm : `qrcode` ^1.5.4 (import QRCode from 'qrcode'). Le projet embarque aussi `qrcode.react` ^4.2.0 (non utilisé ici).
- [ ] Interface QRCodeOptions { sku: string; productName: string; imageId: string; size?: string; colorVariant?: string }
- [ ] generateQRCode(options): Promise<string> — valeurs par défaut size = 'S' et colorVariant = 'Default'
- [ ] generateQRCode — la charge utile encodée est JSON.stringify({ sku, productName, imageId, size, colorVariant, timestamp: new Date().toISOString() })
- [ ] generateQRCode — options de rendu : errorCorrectionLevel 'H' (le plus robuste, ~30 % de correction — adapté à une étiquette collée/abîmée), type 'image/png', quality 0.95, margin 1, width 300
- [ ] generateQRCode — en cas d'échec : console.error('[v0] Error generating QR code:', error) puis throw new Error('Failed to generate QR code')
- [ ] generateSimpleQRCode(text: string): Promise<string> — errorCorrectionLevel 'M' (moyen), type 'image/png', quality 0.95, margin 1, width 200 ; erreur -> log '[v0] Error generating simple QR code:' + throw 'Failed to generate QR code'
- [ ] parseQRCodeData(qrData: string) — JSON.parse dans un try ; en cas d'échec renvoie { raw: qrData } (jamais d'exception) : un QR non-JSON scanné reste exploitable via le champ `raw`
- [ ] Aucune fonction de scan/décodage caméra ici : le commentaire précise que le décodage réel serait fait par un scanner QR externe
- [ ] Promesses résolues (data URL) ou rejetées avec le message 'Failed to generate QR code'.
- [ ] parseQRCodeData ne rejette jamais : fallback { raw }.
- [ ] INCOHÉRENCE À CONNAÎTRE : le QR généré ici contient 6 champs (sku, productName, imageId, size, colorVariant, timestamp) alors que le bouton « Copier données » de <ProductImageGallery/> copie un JSON à 4 champs seulement (sku, productName, imageId, timestamp). Les deux payloads ne sont donc pas identiques.
- [ ] Le timestamp est régénéré à chaque appel : deux QR successifs pour la même image produisent des images DIFFÉRENTES (non idempotent, non comparable octet à octet).
- [ ] Deux niveaux de correction d'erreur volontairement distincts : 'H'/300px pour l'étiquette produit, 'M'/200px pour un QR générique.
- [ ] Marge de 1 module (quiet zone minimale) : à surveiller sur certains scanners exigeants.

**Pourquoi sans objet :**
- Utilisé seulement par <ProductImageGallery /> non monté : rien à porter (le scanner de recherche produit est porté).

### `(hook partagé) lib/hooks/useDeliveryZones.ts — zones de livraison configurables`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 20

- [x] Interface exportée DeliveryZoneOption { id: number; code: string; nom: string; prix: number; actif: boolean }
- [x] Retour du hook : { zones: DeliveryZoneOption[], loading: boolean, refetch: () => Promise<void> }
- [x] État initial : zones = [] et loading = TRUE (le hook démarre toujours en chargement)
- [ ] refetch est un useCallback(deps: []) — référence stable, donc le useEffect([refetch]) ne déclenche QU'UN SEUL fetch au montage  — _sans objet côté Flutter : mémoïsation React ; provider partagé = un seul fetch (orders_provider.dart:31)_
- [x] refetch() : setLoading(true) -> djangoClient.zones.list() -> .then(setZones) -> .catch(() => setZones([])) -> .finally(() => setLoading(false))
- [x] GESTION D'ERREUR SILENCIEUSE : en cas d'échec réseau, les zones sont vidées, AUCUN état d'erreur n'est exposé, AUCUN toast n'est émis. Le consommateur ne peut PAS distinguer « pas de zones configurées » de « le serveur est tombé »
- [x] Le hook NE FILTRE PAS sur le champ `actif` : il renvoie tel quel ce que l'API retourne
- [ ] 3 points d'appel indépendants dans app/(app)/orders/page.tsx (OrdersPage l.248, dialog d'édition l.1993, dialog de création l.2645) — soit potentiellement 3 requêtes GET simultanées pour la même donnée  — _sans objet côté Flutter : détail React ; un seul provider partagé_
- [ ] La page /settings n'utilise PAS le hook : elle appelle directement djangoClient.zones.list().then(setDeliveryZones).catch(() => {}) et fait le CRUD  — _sans objet côté Flutter : Flutter : même provider partout (settings_screen.dart:976)_
- [x] Le hook n'a pas de formulaire, mais il alimente ceux de /orders : le champ « zone » des dialogs de création et d'édition de commande, dont la valeur détermine les frais de livraison.
- [x] Aucun filtre/tri/pagination : la liste est renvoyée brute et complète.
- [x] LOADING : true au montage et à chaque refetch (aucun consommateur de /orders n'exploite ce flag — ils ne déstructurent que `{ zones }`)
- [x] SUCCÈS : tableau de zones
- [x] ERREUR : tableau vide, indistinguable de l'état vide
- [x] Aucun état unauthorized géré (un 401/403 tombe dans le même catch silencieux)
- [x] buildZoneOptions() dans app/(app)/orders/page.tsx transforme la liste en options { value: code, label: `${nom} (${fmt(prix)})`, frais: Number(prix) } et AJOUTE TOUJOURS une option littérale supplémentaire { value: 'RECUPERATION', label: 'Récupération (0 Ar)', frais: 0 } — le retrait sur place est structurellement à part (pas de livreur, pas de frais) et n'est jamais stocké en base comme une zone
- [x] RÈGLE MÉTIER /orders : un PREPARATEUR ne crée QUE des retraits sur place — la zone est forcée à 'RECUPERATION' à l'ouverture du dialog et il ne voit aucune donnée financière (showPrices = !isPreparateur)
- [x] RÈGLE MÉTIER /orders : pour les autres rôles, un useEffect sélectionne automatiquement la PREMIÈRE zone payante (première option dont value !== 'RECUPERATION') dès que les zones arrivent, à condition que le champ zone soit encore vide — nécessaire car le fetch est asynchrone
- [x] Le libellé de zone affiché à l'utilisateur inclut le prix formaté entre parenthèses
- [x] Écran /settings : liste 'Toutes les zones ({zones.length})', message vide 'Aucune zone.' (text-sm text-muted-foreground text-center py-4), édition inline (nom + prix, trim sur le nom, Number(prix) || 0 en repli)

### `(hook partagé) lib/hooks/useDebouncedValue.ts — valeur temporisée pour les reche`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 14

- [ ] Signature générique : useDebouncedValue<T>(value: T, delayMs = 250): T  — _sans objet côté Flutter : hook React ; Flutter : Timer par écran (movements_screen.dart:80, catalog_screen.dart:122, users_screen.dart:191, chat_list_screen.dart:183)_
- [x] État interne initialisé AVEC la valeur courante : la toute première valeur est renvoyée IMMÉDIATEMENT, sans délai (pas de undefined/flash au montage)
- [x] useEffect([value, delayMs]) : setTimeout(() => setDebounced(value), delayMs) avec cleanup clearTimeout — chaque frappe annule le timer précédent (debounce trailing classique)
- [x] Délai par défaut 250 ms ; TOUS les consommateurs actuels utilisent ce défaut (aucun n'passe de delayMs explicite)
- [x] Pas de flush immédiat, pas d'annulation manuelle, pas de version leading-edge
- [x] CONSOMMATEUR — app/(app)/movements/page.tsx l.146 : debouncedSearchTerm = useDebouncedValue(searchTerm)
- [ ] CONSOMMATEUR — app/(app)/chats/page.tsx l.402 : debouncedProductSearch = useDebouncedValue(productSearch)  — _sans objet côté Flutter : recherche produit absente de la page chats web actuelle (seul searchQuery l.500 subsiste)_
- [x] CONSOMMATEUR — app/(app)/chats/page.tsx l.482 : debouncedSearchQuery = useDebouncedValue(searchQuery)
- [x] CONSOMMATEUR — app/(app)/products/page.tsx l.164 : debouncedSearch = useDebouncedValue(search)
- [x] CONSOMMATEUR — app/(app)/users/page.tsx l.276 : debouncedSearchTerm = useDebouncedValue(searchTerm)
- [x] C'est l'infrastructure de TOUTES les barres de recherche de l'app : produits, mouvements de stock, utilisateurs, et les deux recherches de la page chats (recherche de produit et recherche de conversation).
- [x] Aucun état UI exposé : le hook ne renvoie qu'une valeur. Il n'existe donc AUCUN indicateur visuel « recherche en attente » pendant les 250 ms de latence.
- [x] Le champ de saisie reste toujours contrôlé par l'état non temporisé (frappe fluide) — c'est la LISTE qui accuse 250 ms de retard
- [x] À porter en Flutter avec un Timer + cancel dans dispose(), ou un debounce sur le TextEditingController ; attention à annuler le timer au démontage pour ne pas setState sur un widget détruit

### `(couche transport) DjangoAPIClient — coeur HTTP/JWT`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 36

- [x] const API_BASE_URL = process.env.NEXT_PUBLIC_DJANGO_API_URL ?? 'http://127.0.0.1:8010/api' (fallback en dur 127.0.0.1:8010)
- [x] Etat interne: `tokens: {access, refresh} | null`, `isRefreshing: boolean`, `refreshQueue: Array<(token)=>void>`
- [x] constructor() appelle loadTokensFromStorage() : lit localStorage['django_tokens'], JSON.parse dans try/catch, log '[v0] Failed to parse stored tokens' si echec (pas de crash)
- [x] saveTokensToStorage(tokens) : ecrit localStorage['django_tokens'] = JSON.stringify(tokens) et met a jour le champ memoire
- [x] clearTokensFromStorage() : tokens=null + localStorage.removeItem('django_tokens')
- [x] Toutes les fonctions storage sortent immediatement si typeof window === 'undefined' (SSR-safe) — en Flutter remplacer par SharedPreferences / secure storage
- [x] refreshAccessToken() : si pas de refresh token -> null. Si un refresh est deja en cours (isRefreshing) -> retourne une Promise mise en file dans refreshQueue (aucun double refresh concurrent, tous les appels 401 simultanes attendent le meme resultat)
- [x] refreshAccessToken() succes : conserve le refresh existant, remplace seulement `access`, sauvegarde, puis appelle chaque callback de refreshQueue avec le nouveau token et vide la file
- [x] refreshAccessToken() echec HTTP (response non ok) : clearTokensFromStorage() PUIS redirection dure `window.location.href = '/login'` et retourne null
- [x] refreshAccessToken() exception reseau : console.error('[v0] Token refresh failed:', error) + clearTokens + null (pas de redirection dans ce cas)
- [ ] finally: isRefreshing = false dans tous les cas  — _sans objet côté Flutter : pas de drapeau isRefreshing côté Flutter_
- [x] getAuthHeaders() : {'Content-Type':'application/json'} + Authorization: `Bearer <access>` seulement si un access existe
- [x] request<T>(endpoint, options) : normalise l'endpoint — si il commence par 'http' il est utilise tel quel, sinon `${API_BASE_URL sans slash final}/${endpoint sans slash initial}`
- [x] request() fusionne les headers : headers d'auth d'abord, puis options.headers qui ECRASENT (extraHeaders.forEach -> requestHeaders.set)
- [x] request() sur status 401 : tente refreshAccessToken(); si null -> lit le JSON d'erreur (catch -> {}) et throw Error(error.detail || 'Authentication failed'); sinon rejoue la requete UNE seule fois avec les nouveaux headers
- [x] request() erreur non-ok : si content-type contient application/json -> message = error.detail || error.non_field_errors[0] (si tableau) || toutes les entrees `${cle}: ${valeur ou valeur[0]}` jointes par ' | ' || `API Error: ${status}`. Sinon -> response.text() tronque a 200 caracteres
- [x] request() succes 204 ou 205 -> retourne undefined (typé T) ; corps vide ('' ) -> undefined ; parse JSON uniquement si content-type contient application/json, sinon undefined
- [x] Verbes exposes : get<T>(endpoint), post<T>(endpoint, data?), put<T>, patch<T>, delete<T>(endpoint, data?) — NOTE: delete accepte un BODY JSON (utilise par users.delete qui envoie {password})
- [ ] post/put/patch n'envoient un body que si `data` est truthy (undefined sinon)  — _sans objet côté Flutter : détail fetch JS ; Dio n'envoie pas de corps quand data est null (ex. users_repository.dart:170-175)_
- [x] requestFormData<T>(endpoint, method, FormData) : URL = `${API_BASE_URL}${endpoint}` (concatenation brute, pas de normalisation), header Authorization seul (PAS de Content-Type — laisse le navigateur poser le boundary), 401 -> refresh + rejeu, erreur -> toutes les entrees `${cle}: ${valeurs jointes par ', '}` jointes par ' | ', sinon `API Error: ${status}`; retourne response.json()
- [x] postFormData<T>(endpoint, FormData) et patchFormData<T>(endpoint, FormData) publics
- [x] requestBlob(endpoint, method='GET') : Authorization seul, 401 -> refresh + rejeu, erreur -> error.detail sinon `API Error: ${status}`; extrait le nom de fichier depuis Content-Disposition via /filename="?([^"]+)"?/ avec fallback 'backup.zip'; retourne {blob, filename}
- [x] requestFormDataForBlob(endpoint, FormData) : POST multipart dont la reponse est un FICHIER (pas du JSON) accompagne d'un resume porte par des en-tetes personnalisees (CORS_EXPOSE_HEADERS cote Django) ; erreur -> error.error || error.detail ; filename fallback 'export.xlsx' ; retourne {blob, filename, headers}
- [x] isAuthenticated(): boolean -> !!tokens?.access (verifie la simple PRESENCE du token, jamais son expiration)
- [x] getAccessToken(): string | null -> utilise pour construire les URL WebSocket (?token=...)
- [x] export const djangoClient = new DjangoAPIClient() — singleton instancie a l'import (le chargement des tokens se fait donc au premier import cote client)
- [ ] export type { AuthResponse, AuthTokens }  — _sans objet côté Flutter : types TS ; équivalent LoginResult (auth_repository.dart:12-18)_
- [x] Interface AuthResponse (interne) : {access, refresh, user:{id, email, username, full_name, role:'admin'|'magasin'|'employer', is_confirmed, store_id?, magasin_id?, shop_name?, company_name?, position?}}
- [ ] Interface ApiErrorResponse : {detail?: string, [key:string]: any}  — _sans objet côté Flutter : type TS ; messageFromError lit la Map dynamiquement (api_client.dart:148-165)_
- [ ] Loading : aucun (la classe est bas niveau, l'etat de chargement est gere par les hooks/pages appelants)  — _sans objet côté Flutter : idem : chargement géré par les providers/écrans_
- [x] Erreur : toujours une Error JS avec un message deja lisible en francais quand le backend le fournit (error.detail) — a mapper sur une exception Dart typee
- [x] Unauthorized : 401 -> refresh transparent ; echec du refresh -> purge des tokens + redirection dure vers /login (en Flutter : navigation vers l'ecran de connexion + purge du storage)
- [x] Succes vide : 204/205 et corps vide normalises en `undefined` (important pour DELETE et pour caisse.current)
- [x] La redirection /login se fait par window.location.href (rechargement complet de l'app) — en Flutter, prevoir un equivalent global (redirection Navigator + reset des providers)
- [ ] Tous les logs de debug sont prefixes '[v0]'  — _sans objet côté Flutter : convention de logs web_
- [x] Le refresh ne renouvelle QUE l'access token ; le refresh token reste celui de la connexion initiale (donc a duree de vie limitee cote Django : prevoir la deconnexion quand il expire)

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- `references.update` utilise PATCH (partiel) au lieu de PUT : même endpoint, la fiche envoie tous les champs.
- Un échec réseau du renouvellement de jeton déclenche aussi la déconnexion (sessionExpired), là où le web ne fait que purger les jetons.

### `djangoClient.auth — authentification, inscription, mot de passe oublie`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 25

- [x] register(email, username, password, role, extraData?) : traduit role 'store_manager' -> 'magasin' et 'employee' -> 'employer' avant envoi ; full_name par defaut = username si non fourni ; extraData est etale dans le body
- [x] extraData de register : full_name?, company_name?, shop_name?, admin_email?, position?
- [x] login(email, password) : POST puis saveTokensToStorage({access, refresh}) IMMEDIATEMENT, puis un second appel getCurrentUser() pour recuperer le profil ; retourne {access, refresh, user}
- [x] login envoie le champ `email` (pas `username`)
- [x] logout() : 1) POST /users/logout-event/ dans un try/catch (echec ignore, console.warn '[v0] Logout event recording failed:') 2) recupere le refresh token en memoire ou, a defaut, relit localStorage['django_tokens'] 3) POST /users/refresh/ avec ce refresh (fire-and-forget, warn '[v0] Logout refresh request failed:') 4) localStorage.clear() — EFFACE TOUT le localStorage, pas seulement les tokens 5) this.tokens = null
- [x] getCurrentUser() : GET /users/me/ puis mapping role backend->front : 'admin'->'admin', 'magasin'->'store_manager', 'employer'->'employee' (defaut 'employee')
- [ ] getCurrentUser() derive first_name = full_name.split(' ')[0] et last_name = le reste joint par des espaces ; full_name '' si absent  — _sans objet côté Flutter : first_name/last_name ne sont consommés par aucune page web ; AppUser.fullName ('' si absent, models/user.dart:89)_
- [x] getCurrentUser() expose is_approved ET is_confirmed, tous deux alimentes par response.is_confirmed ; conserve raw_role (valeur backend brute) ; remonte company_name, shop_name, magasin_id, position, phone
- [x] approveUser(userId) : PUT sans body
- [x] rejectUser(userId) : POST sans body
- [x] getPendingUsers() : liste des comptes en attente de validation
- [x] forgotPasswordRequest(email) -> {message}
- [x] forgotPasswordStatus(email) -> {status: 'none' | 'pending' | 'approved' | 'rejected'} — email encode via encodeURIComponent (polling cote UI)
- [x] forgotPasswordConfirm(email, newPassword) -> {message} ; le champ envoye s'appelle `new_password`
- [x] Inscription : email, username, password, role (store_manager|employee|admin), full_name (optionnel -> username), company_name (optionnel), shop_name (optionnel), admin_email (optionnel — rattachement a l'admin), position (optionnel). Aucune validation client dans ce fichier : toutes les erreurs viennent du backend et arrivent sous forme 'champ: message | champ2: message'.
- [x] Connexion : email + password. Erreur backend renvoyee telle quelle (ex. identifiants invalides, compte non confirme).
- [x] Mot de passe oublie etape 1 : email seul.
- [x] Mot de passe oublie etape 3 : email + new_password (aucune regle de longueur cote client dans ce fichier).
- [x] Non authentifie : isAuthenticated() false -> les hooks n'appellent meme pas /users/me/
- [x] Compte non confirme : is_confirmed/is_approved false -> useAuth expose isPendingApproval = !!user && !user.is_approved (ecran 'en attente d'approbation')
- [x] Erreur de connexion : useAuth stocke error = message de l'exception, et remet user a null
- [x] Chargement : useAuth gere isLoading (true au montage, true pendant login/register, false en finally)
- [ ] Le logout vide TOUT le localStorage : en Flutter, purger aussi les preferences applicatives (theme, filtres memorises, brouillons) pour reproduire le comportement  — _écart (le web ne le fait pas non plus) : logout ne purge que les jetons (auth_repository.dart:153) : theme_mode (theme_provider.dart:12-36) et stockv2_dismissed_notification_ids (notifications_repository.dart:144-175) restent en SharedPreferences_
- [x] Le parcours mot de passe oublie est asynchrone et humain : l'utilisateur demande, un admin approuve, puis l'utilisateur revient confirmer — l'UI doit poller forgotPasswordStatus
- [x] Apres login, deux requetes reseau s'enchainent (login puis /users/me/) : prevoir un seul spinner couvrant les deux

### `djangoClient.passwordResetRequests — moderation des demandes de reinitialisation`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 5

- [x] list(statusFilter?) : ajoute ?status=<valeur> uniquement si un filtre est fourni
- [x] resolve(requestId, action) : action strictement typee 'approve' | 'reject', envoyee en PATCH dans {action}
- [ ] A prevoir cote UI : confirmation avant approbation/rejet (non implementee dans ce fichier)  — _écart (le web ne le fait pas non plus) : aucune confirmation avant resolve (users_screen.dart:1073-1085) — le web n'en a pas non plus_
- [x] Filtre par statut de la demande via le parametre `status` (chaine libre cote client, generalement pending/approved/rejected)
- [x] Aucun etat gere ici : liste brute, la page appelante gere loading/empty/erreur

### `djangoClient.catalog.categories — Categories du catalogue (§8)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 6

- [x] list(magasinId?) : ?magasin_id=<id> seulement si fourni
- [x] create({nom, ordre?, magasin_id?, avec_couleurs?}) — `ordre` pilote le tri d'affichage, `avec_couleurs` indique si les references de cette categorie se declinent en couleurs
- [x] update(id, {nom?, ordre?, avec_couleurs?}) en PATCH (partiel)
- [x] delete(id) — DELETE, reponse 204 normalisee en undefined
- [x] Formulaire Categorie : nom (obligatoire cote backend), ordre (entier, optionnel), avec_couleurs (booleen / switch, optionnel), magasin_id (a la creation seulement, optionnel)
- [x] `avec_couleurs` est le switch cle : il conditionne l'affichage du choix de couleur dans les formulaires de reference/variante en aval

### `djangoClient.catalog.types — Sous-types rattaches a une categorie`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 7

- [x] list(categoryId?) : ?category=<id> pour filtrer par categorie parente
- [x] create({category, nom}) — la categorie parente est obligatoire
- [x] update(id, {nom?, category?}) — permet de deplacer un type vers une autre categorie
- [x] delete(id)
- [x] Formulaire Type : category (selecteur de categorie, obligatoire a la creation), nom (obligatoire)
- [x] Filtre `category` pour n'afficher que les types d'une categorie
- [x] Le type est l'unite de regroupement utilisee par references.bulkUpdatePrice (mise a jour de prix par type)

### `djangoClient.catalog.brands — Marques`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 5

- [x] list(magasinId?) : ?magasin_id=
- [x] create({nom, magasin_id?})
- [x] update(id, {nom}) — seul le nom est modifiable
- [x] delete(id)
- [x] Formulaire Marque : nom (obligatoire), magasin_id (optionnel a la creation)

### `djangoClient.catalog.colors — Couleurs (referentiel des variantes)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 6

- [x] list(magasinId?) : ?magasin_id=
- [x] create({nom, magasin_id?})
- [x] update(id, {nom})
- [x] delete(id)
- [x] Formulaire Couleur : nom (obligatoire), magasin_id (optionnel a la creation)
- [x] La couleur 'Standard' est traitee comme une absence de couleur ailleurs dans le client (movements et sales n'ajoutent pas le suffixe ' (Standard)' au nom du produit)

### `djangoClient.catalog.references — References produit (fiche article) + import/ex`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 21

- [x] list({type?, brand?, category?}) : construit une querystring via URLSearchParams, n'ajoute que les filtres truthy (attention : un id 0 serait ignore)
- [x] autocomplete(query, {type?, brand?, category?}) : GET /catalog/references/autocomplete/?q=<query>&... — brique de la recherche produit dans les formulaires de commande
- [x] getById(id)
- [x] create({type, brand, reference_name, prix_achat?, prix_vente, actif?}) — prix_vente OBLIGATOIRE, prix_achat optionnel ; les prix acceptent number ou string
- [x] update(id, data) en PUT (remplacement COMPLET, pas un PATCH : il faut renvoyer tous les champs)
- [x] delete(id)
- [x] bulkUpdatePrice({type_id, prix_achat?, prix_vente?}) -> {updated: number} — applique un prix a toutes les references d'un type, retourne le nombre de lignes modifiees (a afficher dans un toast)
- [x] exportExcel() -> {blob, filename} via requestBlob (filename lu dans Content-Disposition, fallback 'export.xlsx' pour l'import / 'backup.zip' pour requestBlob generique)
- [x] importExcel(file) : POST multipart champ `file`, la reponse est un FICHIER (rapport Excel) + un resume dans les en-tetes
- [x] importExcel retourne : {blob, filename, batch_id, created_references, updated_references, created_variants, updated_variants, errors_count, skipped_count, new_reference_names[], updated_reference_names[]}
- [x] Les compteurs sont lus avec Number(header || 0) ; les listes de noms sont des tableaux JSON parses dans un try/catch qui retombe sur [] en cas de JSON invalide
- [x] batch_id peut etre null — c'est la cle qui permet l'annulation post-import
- [x] Formulaire Reference : type (selecteur, obligatoire), brand (selecteur, obligatoire), reference_name (texte, obligatoire), prix_achat (nombre, optionnel), prix_vente (nombre, obligatoire), actif (booleen/switch, optionnel)
- [x] Formulaire Mise a jour de prix en masse : type_id (obligatoire), prix_achat et/ou prix_vente (au moins un attendu) — retour {updated} a afficher
- [x] Formulaire Import Excel : un unique champ fichier (`file`), soumis en multipart
- [x] Dialogue de revue post-import (mentionne explicitement dans le commentaire, implemente dans products/page.tsx) : affiche les compteurs crees/mis a jour/erreurs/ignores, la liste des nouvelles references et des references mises a jour, avec un bouton d'annulation branche sur catalog.importBatches.cancel(batch_id)
- [x] Telechargement du rapport d'import (blob) et de l'export Excel
- [x] references.list : filtres type / brand / category
- [x] references.autocomplete : recherche texte `q` combinable avec les memes filtres type/brand/category
- [ ] En-tetes personnalisees a exposer cote serveur (CORS_EXPOSE_HEADERS) : X-Import-Batch-Id, X-Import-Created-References, X-Import-Updated-References, X-Import-Created-Variants, X-Import-Updated-Variants, X-Import-Errors-Count, X-Import-Skipped-Count, X-Import-New-Reference-Names, X-Import-Updated-Reference-Names  — _sans objet côté Flutter : CORS = navigateur ; Dio lit directement les X-Import-* (catalog_repository.dart:480-492)_
- [x] En Flutter, le telechargement de blob doit etre remplace par une ecriture fichier + ouverture (share/open_file) — il n'y a pas d'equivalent direct a l'ancre de telechargement du navigateur

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- `update` en PATCH partiel plutôt que PUT (même endpoint).

### `djangoClient.catalog.importBatches — Annulation d'un import Excel`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 4

- [x] cancel(batchId: string | number) -> {status: string} — POST avec un body vide {}
- [x] Le batchId provient de l'en-tete X-Import-Batch-Id de la reponse d'import
- [ ] Confirmation d'annulation attendue cote UI (action destructive : elle supprime des references creees)  — _écart (le web ne le fait pas non plus) : aucune boîte de confirmation avant cancelImportBatch (import_export.dart:258-275) — le web n'en a pas non plus_
- [x] Retour {status} a afficher en toast de succes ; l'erreur remonte en Error avec le message backend

### `djangoClient.catalog.variants — Variantes (couleur) et ajustement de stock`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 9

- [x] list(referenceId?) : ?reference=<id>
- [x] create({product_reference, couleur, stock_actuel?, seuil_alerte?})
- [x] delete(id)
- [x] adjust(id, {type: 'ENTREE' | 'SORTIE', quantite: number, note?: string}) — POST /catalog/variants/{id}/adjust/
- [x] Il n'existe PAS de variants.update : pour corriger un stock il faut passer par adjust (tracabilite imposee)
- [x] Formulaire Variante : product_reference (id de la reference parente, obligatoire), couleur (texte/selecteur issu de catalog.colors, obligatoire), stock_actuel (entier, optionnel — stock initial), seuil_alerte (entier, optionnel — declenche l'alerte de rupture)
- [x] Formulaire Ajustement de stock : type (radio/segment ENTREE|SORTIE, obligatoire), quantite (entier > 0), note (texte libre, optionnelle — reprise dans l'historique des mouvements)
- [x] seuil_alerte par defaut cote mapping = 1 (voir mapReferenceToProduct : min des seuils, retombe a 1 si aucun)
- [x] Un ajustement cree une ligne dans l'historique des mouvements avec movement_type 'Ajustement manuel'

### `djangoClient.orders — Module Commandes (coeur metier, §5-§7)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 41

- [x] list(filters?) : statut, date_debut, date_fin, magasin_id, livraison_zone, historique (envoye comme '1'), date_from, date_to, preparateur_id — tous optionnels, ajoutes seulement si truthy
- [x] getById(id) : detail complet d'une commande
- [x] create(data) : client_nom, telephone, livraison_zone, items[{product_variant, quantite}], note_preparateur?, note_livreur?, adresse_livraison?, mode_paiement ('AVANT' | 'LIVRAISON'), date_commande?, magasin_id?
- [x] livraison_zone attend le `code` d'une zone creee dans Parametres, OU la valeur speciale 'RECUPERATION' (retrait sur place — remplace l'ancien module Vente/Ticket)
- [x] changeStatus(id, statut, note?, assignee?, photo?) : DEUX modes — si `photo` est fourni, envoi multipart (champs statut, note, preparateur_id, livreur_id, assigned_at, photo) ; sinon POST JSON {statut, note, ...assignee}
- [x] assignee = {preparateur_id?, livreur_id?, assigned_at?} — assigned_at permet de dater l'assignation (creneau)
- [x] Les ids d'assignee ne sont ajoutes au FormData que s'ils sont != null (0 reste donc valide, contrairement aux filtres)
- [x] cancel(id, note?) : POST /orders/{id}/cancel/ — annulation distincte d'un changement de statut (restitue le stock cote backend)
- [x] assignLivreur(id, livreurId) : PRE-assignation d'un livreur AVANT que la commande soit Prete, SANS changer le statut ; reutilisee automatiquement au passage 'En livraison' (orders/services.py::assign_livreur_early/_resolve_assignee)
- [x] assignPreparateur(id, preparateurId) : PRE-assignation d'un preparateur SANS faire progresser le statut — la commande reste 'Nouvelle' (en attente) jusqu'a ce que le preparateur clique lui-meme 'Commencer la preparation'
- [x] availableStaff(role, magasinId?, dateCommande?) -> [{id, full_name, magasin_id, available}] — role strictement 'PREPARATEUR' | 'LIVREUR'
- [x] availableStaff avec date_commande (pour LIVREUR) : SIGNALE sans BLOQUER un conflit d'horaire avec une autre commande deja (pre-)assignee a ce livreur le meme jour/heure — le champ `available` sert a afficher un avertissement, pas a desactiver le choix
- [x] update(id, data) : PATCH partiel, uniquement pour une commande encore 'Nouvelle' (verifie cote backend, orders/views.py) — champs client_nom, telephone, livraison_zone, adresse_livraison, mode_paiement, date_commande, note_preparateur, note_livreur, items[]
- [x] delete(id) : DELETE /orders/{id}/ -> void
- [ ] dashboard({date_from?, date_to?, magasin_id?}) : indicateurs du module commandes  — _sans objet côté Flutter : orders.dashboard n'est appelé par aucune page web ; le tableau de bord Flutter utilise orders/reports/{section} (reports_repository.dart:17-28)_
- [x] Formulaire Creation de commande — champs : client_nom (obligatoire), telephone (obligatoire), livraison_zone (obligatoire, selecteur alimente par zones.list() + option 'RECUPERATION'), adresse_livraison (optionnel, pertinent seulement hors RECUPERATION), mode_paiement ('AVANT' = paye d'avance | 'LIVRAISON' = paye a la livraison), date_commande (date/heure planifiee — a composer avec appDatetimeLocalToIso pour rester en heure d'Antananarivo), note_preparateur (texte libre destine au preparateur), note_livreur (texte libre destine au livreur), magasin_id (pour un admin multi-magasins), items[] : liste de lignes {product_variant (id de variante choisi via catalog.references.autocomplete), quantite}
- [x] Formulaire Modification de commande : memes champs, tous optionnels (PATCH), MAIS uniquement tant que le statut est NOUVELLE — sinon le backend refuse
- [x] Formulaire Changement de statut : statut (obligatoire), note (optionnelle), preparateur_id / livreur_id / assigned_at (selon la transition), photo (fichier — preuve de livraison)
- [x] Formulaire Annulation : note (motif, optionnel)
- [x] Formulaire Assignation preparateur : preparateur_id choisi dans availableStaff('PREPARATEUR', magasinId)
- [x] Formulaire Assignation livreur : livreur_id choisi dans availableStaff('LIVREUR', magasinId, dateCommande) avec badge de disponibilite
- [x] Dialogue de changement de statut avec note et, pour la livraison, capture/selection de photo
- [x] Dialogue d'annulation avec motif
- [x] Dialogue/selecteur d'assignation preparateur
- [x] Dialogue/selecteur d'assignation livreur avec indicateur de conflit d'horaire
- [x] Confirmation de suppression de commande
- [x] Par statut (statut)
- [x] Par plage de dates : deux couples coexistent — date_debut/date_fin ET date_from/date_to (le second est utilise avec appDayBounds pour des bornes ISO absolues)
- [x] Par magasin (magasin_id)
- [x] Par zone de livraison (livraison_zone)
- [x] Mode historique (historique=1) — bascule entre commandes actives et archivees
- [x] Par preparateur (preparateur_id)
- [ ] Dashboard filtrable par date_from/date_to/magasin_id  — _sans objet côté Flutter : cf. orders.dashboard (aucune page web) ; rapports Flutter filtrés date_from/date_to reports_repository.dart:17-28_
- [x] Le champ de statut courant s'appelle `statut_courant` cote objet commande (voir le service sales qui filtre sur statut_courant === 'LIVRE')
- [x] Les 6+2 statuts utilises dans l'app : NOUVELLE, EN_PREPARATION, PRETE, EN_LIVRAISON, LIVRE, RETOUR, ANNULEE
- [x] Une commande a un historique de statuts (modele WebSocket 'order_status_history')
- [x] Un refus de transition arrive en erreur backend avec message lisible (ex. jour J non atteint)
- [x] La photo de livraison est la seule donnee binaire du module : elle bascule l'appel en multipart (en Flutter : MultipartFile depuis la camera/galerie)
- [x] Le conflit d'horaire livreur est un AVERTISSEMENT visuel (badge/couleur), jamais un blocage
- [x] La zone 'RECUPERATION' est la vente sur place : masquer l'adresse de livraison et le prix de zone
- [x] Les evenements WebSocket 'order' et 'order_status_history' declenchent un rafraichissement automatique de la liste (useRealtimeRefresh, debounce 400 ms)

### `djangoClient.zones — Zones de livraison configurables (Parametres)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 12

- [x] list() -> [{id, code, nom, prix, actif}] — le `code` est la valeur envoyee dans une commande, pas l'id
- [x] create({nom, prix})
- [x] update(id, {nom?, prix?, actif?}) — `actif` permet de desactiver/reactiver une zone
- [x] delete(id) -> void — SUPPRESSION DOUCE : une zone deja utilisee par des commandes n'est pas reellement supprimee cote serveur, elle est desactivee (DeliveryZoneOptionViewSet.destroy)
- [x] Hook useDeliveryZones() : {zones, loading, refetch} — fetch au montage, catch -> liste vide (jamais d'erreur affichee), un fetch par composant monte (liste courte, changeant rarement)
- [x] Formulaire Zone : nom (texte, obligatoire), prix (nombre, obligatoire) ; en edition s'ajoute actif (switch)
- [x] Dialogue de creation/edition de zone dans Parametres
- [ ] Confirmation de suppression (avec l'avertissement qu'une zone utilisee sera seulement desactivee)  — _écart (le web ne le fait pas non plus) : suppression immédiate sans confirmation, toast après coup (settings_screen.dart:933-943) — le web n'en a pas non plus_
- [x] loading : true pendant le fetch du hook
- [x] erreur : silencieuse — la liste retombe a [] (pas de toast). A reproduire ou ameliorer en Flutter
- [x] Ne jamais utiliser l'`id` comme valeur de formulaire de commande : c'est le `code` qui est attendu par orders.create/update
- [x] Les zones inactives doivent etre masquees du selecteur de commande mais rester affichees (grisees) dans Parametres

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Paramètres › Zones affiche l'erreur de chargement avec « Réessayer » (le web retombe silencieusement sur une liste vide).

### `djangoClient.movements — Historique des mouvements de stock (§7.4/§10)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 16

- [x] list({variant_id?}) : ?variant=<id> pour l'historique d'une variante precise, sinon tout l'historique
- [x] MAPPING complet applique a chaque ligne (a reproduire tel quel en Dart) :
- [x] - id <- m.id
- [x] - product <- m.product_variant
- [x] - product_name <- m.reference_name + ' (couleur)' UNIQUEMENT si m.couleur existe ET n'est pas 'Standard'
- [x] - product_reference <- m.reference_name
- [x] - variant_label <- m.couleur
- [x] - changed_by_name <- m.user_name
- [x] - change <- SIGNE : -quantite si m.type === 'SORTIE', +quantite sinon
- [x] - movement_type <- libelle francais de m.origine (voir table ci-dessous), avec repli sur la valeur brute si origine inconnue
- [x] - note <- m.note ; created_at <- m.timestamp
- [x] Table des origines : PREPARATION -> 'Preparation de commande', RETOUR -> 'Retour de commande', ANNULATION -> 'Annulation de commande', LIVRE -> 'Commande livree', FOURNISSEUR -> 'Reception fournisseur', AJUSTEMENT -> 'Ajustement manuel'
- [x] Filtre par variante (variant_id)
- [x] `change` est deja signe : afficher en vert quand > 0 et en rouge quand < 0, avec un prefixe +/-
- [x] Les 6 origines correspondent aux automatismes metier : une commande genere des mouvements a la preparation, au retour, a l'annulation et a la livraison — plus les receptions fournisseur et les ajustements manuels
- [x] Le suffixe couleur est omis pour 'Standard' : meme regle que dans le service sales

### `djangoClient.products — Service de compatibilite (lecture seule)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 11

- [x] list({store_id?, magasin_id?, category?}) : magasinId = magasin_id ?? store_id ; recupere TOUTES les references puis filtre EN MEMOIRE par Number(r.magasin) === Number(magasinId) puis par r.category_name === filters.category
- [x] getById(id) : catalog.references.getById puis mapReferenceToProduct
- [x] delete(id) : delegue a catalog.references.delete
- [x] search(query) : recupere TOUTES les references puis filtre en memoire sur reference_name.toLowerCase().includes(q) OU brand_name.toLowerCase().includes(q) — recherche client, non paginee
- [x] mapReferenceToProduct : id, name = reference_name, reference = reference_name, brand = brand_name, category = category_name, description = [type_name, brand_name] filtres et joints par ' — ', unit_price = null, purchase_price = null, shell_price = prix_vente, initial_quantity = SOMME des variants.stock_actuel (0 si absent), alert_threshold = MIN des variants.seuil_alerte (defaut 1 par variante, et 1 si aucune variante), expiry_date/image1/image2/image3/qr_code = null, magasin, variants = [{id, size: '' (toujours vide), color: couleur, quantity: stock_actuel}]
- [x] Filtre magasin (magasin_id ou store_id, en memoire)
- [ ] Filtre categorie par NOM (category_name, en memoire)  — _sans objet côté Flutter : aucune page web ne passe `category` ; Flutter filtre par id serveur (catalog_repository.dart:276-283) ou localement (catalog_screen.dart:300)_
- [x] Recherche texte en memoire sur nom de reference et marque
- [ ] Aucune image ni QR n'est disponible dans ce mapping (tous a null) : les ecrans qui les affichaient sont vides par construction  — _sans objet côté Flutter : constat sur le mapping web ; Flutter expose la photo de référence (catalog_repository.dart:338-344)_
- [x] unit_price et purchase_price sont TOUJOURS null : seul shell_price (= prix_vente) porte un prix — piege classique lors du portage
- [x] Le filtrage/recherche etant client, prevoir un cout memoire proportionnel a la taille du catalogue (charger une fois puis filtrer localement en Dart)

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Service de compatibilité web (lecture seule) : pas de service dédié côté Flutter, les mêmes données passent par CatalogRepository / StoresRepository (filtre magasin côté serveur).

### `djangoClient.sales — Ventes derivees des commandes livrees (compatibilite)`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 5

- [ ] list({store_id?}) : appelle orders.list({magasin_id: store_id}) si store_id fourni, sinon orders.list() sans filtre  — _sans objet côté Flutter : service orphelin côté web (aucune page n'appelle djangoClient.sales) — non porté_
- [ ] Ne garde QUE les commandes dont order.statut_courant === 'LIVRE' (les autres sont ignorees par `continue`)  — _sans objet côté Flutter : service orphelin ; les ventes viennent des rapports serveur (reports_repository.dart:35)_
- [ ] Explose chaque commande en une ligne par item : id = `${order.id}-${item.id}`, product = item.product_variant, variant = item.product_variant, product_name = item.reference_name + ' (couleur)' si couleur && couleur !== 'Standard', quantity = item.quantite, sale_price = item.prix_unitaire, total_price = prix_unitaire != null ? Number(prix_unitaire) * quantite : null, customer_name = order.client_nom, is_paid = TOUJOURS true, total_profit = TOUJOURS 0, sold_at = order.updated_at || order.created_at  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] is_paid code en dur a true et total_profit code en dur a 0 : tout ecran qui affiche une marge a partir de ce service affichera 0 — a NE PAS reimplementer tel quel en Flutter sans le signaler  — _sans objet côté Flutter : non réimplémenté (conforme à la recommandation) ; marges calculées côté serveur (orders/reports)_
- [ ] La date de vente utilise updated_at en priorite : c'est la date de derniere transition (donc approximativement la date de livraison)  — _sans objet côté Flutter : service orphelin — non porté_

**Pourquoi sans objet :**
- Service de compatibilité (ventes dérivées) non utilisé par les pages : rien à porter.

### `djangoClient.notifications — Notifications in-app`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 18

- [x] list() : GET /users/notifications/
- [x] markRead(id, isRead) : PATCH {is_read} — le booleen permet aussi de REMETTRE en non-lu
- [x] markAllRead() : POST mark-all-read/
- [x] delete(id) : DELETE -> void
- [x] deleteAll() : POST delete-all/ -> void
- [x] bulkRead(ids: number[]) : POST bulk-read/ {ids} — selection multiple
- [x] bulkDelete(ids: number[]) : POST bulk-delete/ {ids} — selection multiple
- [x] WebSocket : ws(s)://<host de NEXT_PUBLIC_DJANGO_API_URL>/ws/notifications/?token=<access>
- [x] Reconnexion automatique toutes les 3000 ms si la fermeture n'est pas volontaire (code !== 1000)
- [x] Statut de socket expose : 'connecting' | 'connected' | 'disconnected'
- [x] Option showToast : affiche toast.info(message) avec description `Type : <libelle>` et duration 5000 ms
- [x] Confirmation attendue pour 'tout supprimer' (action destructive)
- [x] Badge de statut socket : connecte (emeraude), connexion en cours (ambre), deconnecte (rose) — classes dans notifications-utils.tsx::getSocketStatusBadgeClass
- [x] Carte de notification : non lue = fond primary/5, bordure primary/30, ombre ; lue = fond muted/40, bordure neutre (getNotificationCardClass)
- [x] Types de notification et libelles (typeLabel) : sale->'Vente', product->'Produit', user->'Utilisateur', chat->'Chat', transfer->'Transfert', movement->'Mouvement', defaut->'Autre'
- [x] Icones par type (typeIcon, lucide) : sale->Package, user->User, product->Mail, chat->MessageSquare, transfer->ArrowLeftRight, movement->ArrowUpDown, defaut->Bell
- [x] Couleurs de badge par type (getTypeBadgeClass) : sale=vert, product=bleu, user=violet, chat=ambre, transfer=cyan, movement=orange, defaut=muted
- [x] Format de date des notifications : fr-FR JJ/MM/AAAA HH:mm — ATTENTION, formatNotificationDate n'applique PAS le fuseau Indian/Antananarivo (incoherence avec timezone.ts)

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Dates affichées en heure d'Antananarivo (le web formate en heure du navigateur).

### `djangoClient.users — Utilisateurs, employes, profil`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 12

- [x] list(role?) : le parametre `role` est ACCEPTE MAIS IGNORE — l'appel est toujours GET /users/magasins/users/ sans querystring (piege a signaler)
- [ ] getById(id) : appelle en realite GET /users/me/ — l'id est IGNORE (retourne toujours l'utilisateur connecte ; bug de compatibilite a ne pas reproduire)  — _sans objet côté Flutter : bug de compatibilité à ne pas reproduire ; AuthRepository.me() existe (auth_repository.dart:178-190)_
- [x] update(id, data) : PUT /users/role/{id}/ — endpoint de changement de role
- [x] delete(id, password) : DELETE /users/delete/{id}/ avec un BODY {password} — le mot de passe de l'operateur est exige pour confirmer
- [x] updateProfile(data) : PATCH /users/me/
- [x] getEmployeesByStore(storeId) : GET /users/magasins/users/ puis, en memoire, find(m => m.magasin_id === storeId) et retourne found.employers (tableau vide si magasin introuvable)
- [x] La structure retournee par /users/magasins/users/ est donc une liste de magasins, chacun portant un tableau `employers`
- [x] Formulaire Suppression d'utilisateur : password (obligatoire — mot de passe de l'operateur, envoye dans le corps du DELETE)
- [x] Formulaire Role : data libre envoyee en PUT sur /users/role/{id}/ (role, et selon le backend commande_role PREPARATEUR/LIVREUR)
- [x] Formulaire Profil (PATCH /users/me/) : champs correspondant a CurrentUser — full_name, phone, adresse, photo, company_name, logo, shop_name, shop_logo, position
- [x] Dialogue de suppression avec saisie du mot de passe (double confirmation implicite)
- [x] commande_role ('PREPARATEUR' | 'LIVREUR' | null) est le sous-role qui n'existe que pour role='employer' : c'est lui qui pilote tout le gating du module Commandes

### `djangoClient.dashboard — Indicateurs generaux`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 8

- [ ] getStats(storeId?) : GET /users/dashboard/ -> retourne res.kpis (le parametre storeId est IGNORE)  — _sans objet côté Flutter : service orphelin côté web (aucune page n'appelle djangoClient.dashboard) ; tableau de bord Flutter = orders/reports/{section} (reports_repository.dart)_
- [ ] getTopProducts(storeId?, limit=5) : meme appel -> res.lists?.top_products || [] (storeId ET limit IGNORES — la troncature doit se faire cote client)  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] getRevenueChart(storeId?, period='monthly') : meme appel -> res.lists?.recent_sales || [] (storeId et period IGNORES — malgre son nom, retourne les ventes recentes)  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] getSalesAnalytics(storeId?) : meme appel -> payload complet  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] Structure attendue : {kpis: {...}, lists: {top_products: [...], recent_sales: [...]}}  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] Listes absentes normalisees en [] (|| []) — l'etat vide est donc naturel  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] kpis peut etre undefined si la reponse ne le contient pas (aucune protection)  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] Optimisation evidente pour le portage : un seul GET /users/dashboard/ puis distribution locale des trois sous-parties  — _sans objet côté Flutter : sans objet : endpoint non consommé (rapports par section, cache reportsProvider)_

**Pourquoi sans objet :**
- L'endpoint /orders/dashboard/ n'est plus utilisé par le web (tableau de bord = centre de rapports) : rien à porter.

### `djangoClient.transfers — Transfert de stock entre magasins + vue benefice`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 7

- [x] transfer(sourceId, destinationId, items) : POST {source_magasin_id, destination_magasin_id, items:[{variant_id, quantity}]}
- [x] items est une liste : un transfert peut porter sur plusieurs variantes en une operation
- [x] getProfitByMagasins() : GET /users/magasins/overview/ puis REEMBALLE la reponse : {profit_by_magasins: res.magasins}
- [x] Formulaire Transfert : magasin source (selecteur, obligatoire), magasin destination (selecteur, obligatoire, doit differer de la source), lignes items[] : variante (variant_id) + quantite (quantity, entier > 0). Les erreurs de stock insuffisant remontent du backend.
- [ ] Confirmation de transfert attendue cote UI (operation qui deplace du stock reel)  — _écart (le web ne le fait pas non plus) : _submit envoie directement sans boîte de confirmation (transfers_screen.dart:545-575) — le web n'en a pas non plus_
- [x] Un transfert genere des mouvements de stock et une notification de type 'transfer' (badge cyan)
- [x] Le WebSocket 'product_variant' / 'stock_movement' rafraichit les ecrans concernes

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- `getProfitByMagasins` : le bénéfice par magasin est fusionné dans le modèle Magasin (pas de clé profit_by_magasins).

### `djangoClient.caisse — Sessions de caisse, mouvements, categories, synthese`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 28

- [x] listSessions({magasinId?, status?}) : status strictement 'open' | 'closed' ; querystring magasin_id / status
- [x] current(magasinId?) : GET /users/caisse/sessions/current/ ; un 204 (aucune session ouverte) est normalise en NULL grace au `data ?? null` combine au traitement des corps vides dans request()
- [x] open({magasin_id?, opening_balance, opening_note?, opened_at?}) : opening_balance accepte number ou string
- [x] close(sessionId, {closing_balance, closing_note?, closed_at?}) : POST /users/caisse/sessions/{id}/close/
- [x] listMovements({sessionId?, magasinId?, dateFrom?, dateTo?}) : querystring session_id / magasin_id / date_from / date_to
- [x] addMovement({session?, movement_type, amount, reason, category?}) : movement_type strictement 'in' | 'out' ; `session` optionnel (la session courante est deduite cote serveur si absent) ; `category` = id d'une categorie de depense
- [x] deleteMovement(id) -> void
- [x] summary({dateFrom?, dateTo?, magasinId?}) -> {date_from, date_to, total_entrees, total_sorties, solde, sorties_par_categorie: [{categorie, total}], ca_produits_vendus, cout_produits_vendus, benefice_produits_vendus}
- [x] categories.list() -> [{id, nom, created_at}]
- [x] categories.create(nom) / categories.update(id, nom) / categories.delete(id)
- [x] Formulaire Ouverture de caisse : opening_balance (montant du fond de caisse, obligatoire, number|string), opening_note (texte, optionnel), opened_at (date/heure, optionnel — a composer avec appDatetimeLocalToIso), magasin_id (optionnel)
- [x] Formulaire Fermeture de caisse : closing_balance (montant compte en caisse, obligatoire), closing_note (texte, optionnel — justification d'ecart), closed_at (date/heure, optionnel)
- [x] Formulaire Mouvement de caisse : movement_type (segment Entree/Sortie, obligatoire), amount (montant, obligatoire), reason (motif, OBLIGATOIRE — chaine requise par la signature), category (selecteur de categorie de depense, optionnel), session (id, optionnel)
- [x] Formulaire Categorie de caisse : nom (obligatoire)
- [x] Dialogue Ouvrir la caisse
- [x] Dialogue Fermer la caisse (avec ecart eventuel entre solde theorique et closing_balance)
- [x] Dialogue Ajouter un mouvement (entree/sortie)
- [ ] Confirmation de suppression d'un mouvement  — _écart (le web ne le fait pas non plus) : aucune action de suppression de mouvement dans l'UI (deleteMovement existe dans le repo mais n'est pas branché) — idem web_
- [x] Dialogue CRUD des categories de depense
- [x] Sessions : par magasin et par statut open/closed
- [x] Mouvements : par session, par magasin, par plage de dates (date_from/date_to)
- [x] Synthese : par plage de dates et par magasin
- [x] Aucune session ouverte : current() retourne null -> ecran 'caisse fermee' avec bouton Ouvrir
- [x] Session ouverte : afficher solde courant, mouvements du jour et bouton Fermer
- [x] Les evenements WebSocket 'caisse_session' et 'caisse_movement' declenchent un rafraichissement automatique
- [x] sorties_par_categorie alimente naturellement un graphique en secteurs / barres
- [x] benefice_produits_vendus = ca_produits_vendus - cout_produits_vendus (a verifier cote backend, mais les trois champs sont fournis)
- [x] Les montants acceptent des chaines a l'envoi (number | string) : formatter/parser proprement en Dart (num vs String)

### `djangoClient.suppliers — Commandes fournisseur (§7.6)`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 8

- [x] list(magasinId?) : GET /suppliers/orders/?magasin_id=
- [x] getById(id) : detail
- [x] create({description?, prix_fournisseur, fret_import, douane, lines:[{product_variant, quantite}], magasin_id?}) — les trois montants sont OBLIGATOIRES (number | string)
- [x] receive(id) : POST /suppliers/orders/{id}/receive/ — declenche la reception, generant des mouvements de stock d'origine FOURNISSEUR ('Reception fournisseur')
- [x] Formulaire Commande fournisseur : description (texte, optionnel), prix_fournisseur (montant, obligatoire), fret_import (montant, obligatoire), douane (montant, obligatoire), magasin_id (optionnel), lines[] : product_variant (variante, obligatoire) + quantite (entier, obligatoire)
- [x] Confirmation de reception (action irreversible qui incremente le stock)
- [x] Le cout de revient d'une variante decoule de prix_fournisseur + fret_import + douane repartis sur les lignes : c'est ce qui alimente cout_produits_vendus dans la synthese de caisse
- [x] L'evenement WebSocket 'supplier_order' rafraichit la liste

### `djangoClient.backup — Sauvegarde / restauration (admin uniquement)`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 5

- [ ] export() : requestBlob('/users/backup/export/') -> {blob, filename} ; filename lu dans Content-Disposition, fallback 'backup.zip'  — _sans objet côté Flutter : service orphelin côté web (aucune page Sauvegarde) — non porté (aucun appel users/backup/ dans smartcross)_
- [ ] import(file) : POST multipart champ `file` -> {detail: string} (message a afficher en toast)  — _sans objet côté Flutter : service orphelin — non porté_
- [ ] Formulaire Restauration : un unique champ fichier (archive), soumis en multipart  — _sans objet côté Flutter : aucun formulaire côté web non plus — non porté_
- [ ] Confirmation forte avant l'import (ecrasement potentiel de toutes les donnees)  — _sans objet côté Flutter : aucune UI côté web non plus — non porté_
- [ ] En Flutter : ecrire le blob dans un fichier local puis proposer un partage/enregistrement ; pour l'import, utiliser un file picker  — _sans objet côté Flutter : sans objet tant que la fonctionnalité n'existe pas dans l'UI ; le mécanisme existe déjà pour l'Excel (import_export.dart:22-26)_

**Pourquoi sans objet :**
- Utilisé par aucune page du frontend : rien à porter.

### `djangoClient.chat — Messagerie interne`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 6

- [x] users() : GET /users/chat/users/
- [x] history({recipient_id?, room_name?}) : querystring construite via URLSearchParams, parametres ajoutes seulement si truthy
- [ ] Le temps reel du chat n'est PAS dans ce fichier (WebSocket dedie ailleurs) ; seuls les notifications (/ws/notifications/) et la synchro donnees (/ws/data/) sont definis dans lib/  — _sans objet côté Flutter : constat ; Flutter : core/chat_socket_service.dart (ws/chat/) + notifications_socket_service.dart_
- [x] Conversation privee : recipient_id
- [x] Salon : room_name
- [x] Une notification de type 'chat' (badge ambre, icone MessageSquare) est emise a la reception d'un message

### `lib/types.ts — Modeles TypeScript partages`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 14

- [x] UserRole : 'admin' | 'store_manager' | 'employee'
- [x] User : id, email, username, first_name, last_name, role: UserRole, is_approved, store_id?, created_at
- [x] AuthState : user | null, isAuthenticated, isLoading, error | null
- [ ] Product (HERITE, ne correspond PAS a mapReferenceToProduct) : id, name, description, sku, category, quantity, unit_price, unit_cost, store_id, supplier_id?, created_at, updated_at  — _sans objet côté Flutter : type hérité non branché ; modèle réel ProductReference models/catalog.dart:104-165_
- [ ] Sale (HERITE) : id, product_id, quantity, unit_price, total_price, employee_id, store_id, created_at, notes?  — _sans objet côté Flutter : type hérité non branché_
- [ ] Store : id, name, address, city, country, phone, email, manager_id, created_at  — _sans objet côté Flutter : type hérité (address/city/country absents de l'API) ; modèle réel Magasin models/magasin.dart_
- [ ] Supplier : id, name, contact_person, email, phone, address, city, country, created_at  — _sans objet côté Flutter : type hérité ; l'API n'a que des commandes fournisseur (models/supplier.dart)_
- [ ] DashboardStats : total_revenue, total_sales, total_products, total_stores, pending_approvals, monthly_growth  — _sans objet côté Flutter : type orphelin (aucun endpoint)_
- [ ] RevenueSummary : today, this_week, this_month, all_time  — _sans objet côté Flutter : type orphelin_
- [ ] TopProduct : id, name, quantity_sold, revenue  — _sans objet côté Flutter : type orphelin_
- [ ] RevenueData : date, revenue  — _sans objet côté Flutter : type orphelin_
- [ ] SalesAnalytics : total_sales, average_sale_value, top_products: TopProduct[], sales_by_employee: Record<string, number>  — _sans objet côté Flutter : type orphelin_
- [x] Piege de portage : le type `Product` de ce fichier n'a rien a voir avec l'objet reellement produit par mapReferenceToProduct (qui expose reference/brand/shell_price/initial_quantity/alert_threshold/variants). Ne pas s'appuyer sur types.ts pour modeliser le catalogue en Dart — s'appuyer sur mapReferenceToProduct et sur les payloads catalog.*
- [ ] DashboardStats/RevenueSummary/SalesAnalytics ne sont branches sur aucun endpoint reel du client (le dashboard renvoie {kpis, lists}) : ce sont des types orphelins  — _sans objet côté Flutter : types orphelins ; rapports Flutter typés sur orders/reporting (models/reports.dart)_

### `lib/validation.ts — Schemas Zod (heritage, non branches sur l'API actuelle)`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 11

- [ ] productSchema : sku (string, min 2 'SKU minimum 2 caracteres', max 50 'SKU maximum 50 caracteres', regex /^[A-Z0-9\-_]+$/ 'SKU doit contenir seulement des majuscules, chiffres, tirets et underscores'), name (min 3 'Nom minimum 3 caracteres', max 200 'Nom maximum 200 caracteres'), description (max 500 'Description maximum 500 caracteres', optionnel), category_id (uuid 'Categorie invalide', optionnel), supplier_id (uuid 'Fournisseur invalide', optionnel), location (max 100 'Localisation maximum 100 caracteres', optionnel), unit_price (number min 0 'Prix doit etre positif', max 99999 'Prix trop eleve'), color (max 50 'Couleur maximum 50 caracteres', optionnel), material (max 100 'Matiere maximum 100 caracteres', optionnel), status (enum in_stock|low|out_of_stock, optionnel)
- [ ] productSizeSchema : size (enum S|M|XL|XXL, message 'Taille invalide'), quantity (min 0 'Quantite doit etre positive', int 'Quantite doit etre un entier'), reorder_level (min 0 'Limite doit etre positive', int 'Limite doit etre un entier')
- [ ] stockMovementSchema : product_id (uuid 'Produit invalide'), product_size_id (uuid 'Taille invalide', optionnel), size (enum S|M|XL|XXL, optionnel), type (enum entry|exit, message 'Type de mouvement invalide'), quantity (min 1 'Quantite minimum 1', max 10000 'Quantite maximum 10000', int 'Quantite doit etre un entier'), notes (max 500 'Notes maximum 500 caracteres', optionnel)
- [ ] productImageSchema : image_url (url 'URL image invalide'), size (enum S|M|XL|XXL, optionnel), color_variant (max 50 'Variante couleur maximum 50 caracteres', optionnel), is_primary (boolean, optionnel)
- [ ] supplierSchema : name (min 2 'Nom minimum 2 caracteres', max 200 'Nom maximum 200 caracteres'), email (email 'Email invalide', optionnel), phone (max 20 'Telephone maximum 20 caracteres', optionnel), address (max 500 'Adresse maximum 500 caracteres', optionnel), city (max 100 'Ville maximum 100 caracteres', optionnel), country (max 100 'Pays maximum 100 caracteres', optionnel), payment_terms (max 200 'Conditions maximum 200 caracteres', optionnel)
- [ ] excelImportRowSchema (colonnes en francais, cles exactes) : 'SKU' (min 2 'SKU requis'), 'Nom du produit' (min 3 'Nom requis'), 'Categorie' (optionnel), 'Couleur' (optionnel), 'Matiere' (optionnel), 'Prix unitaire' (number positive 'Prix doit etre positif'), 'Taille S'/'Taille M'/'Taille XL'/'Taille XXL' (number nonnegative 'Quantite non negative', optionnels)
- [ ] Helpers safeParse : validateProduct, validateProductSize, validateStockMovement, validateProductImage, validateSupplier, validateExcelImportRow
- [ ] formatValidationErrors(errors) : aplatit recursivement l'arbre d'erreurs en tableau de chaines `chemin.pointe: message` (prefixe cumule a chaque niveau)
- [ ] Aucun formulaire actif du module Commandes/Catalogue n'est valide par ces schemas : les validations en vigueur sont celles du backend (messages renvoyes et concatenes par request())
- [ ] Pour le portage Flutter : reutiliser les LIBELLES d'erreur francais (coherence de ton) mais reconstruire les regles a partir des vrais champs (reference_name, prix_vente, quantite, client_nom, telephone, etc.)
- [ ] Les tailles S/M/XL/XXL n'existent plus dans le modele actuel (remplacees par la couleur de variante) — ne pas les porter

**Pourquoi sans objet :**
- Schémas Zod hérités, non branchés sur l'API actuelle : rien à porter.

### `lib/timezone.ts — Fuseau metier Indian/Antananarivo (regle du 'jour J')`  —  VERIFIED

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 13

- [x] APP_TIME_ZONE = 'Indian/Antananarivo'
- [x] APP_UTC_OFFSET = '+03:00' (decalage fixe toute l'annee)
- [x] appDayKey(date = new Date()) -> 'YYYY-MM-DD' a Antananarivo, via Intl.DateTimeFormat('en-CA') ; retourne '' si la date est invalide (NaN)
- [x] Les cles de jour sont comparables directement avec < et <= (ordre lexicographique = ordre chronologique)
- [x] appToday() -> appDayKey(new Date())
- [x] appDayBounds(dayKey = appToday()) -> {start, end} en ISO absolu : `${dayKey}T00:00:00.000+03:00` et `${dayKey}T23:59:59.999+03:00` convertis en toISOString() — a envoyer tels quels en date_from/date_to
- [x] fmtAppDate(value) -> toLocaleDateString('fr-FR', {timeZone: APP_TIME_ZONE}) ; retourne le tiret cadratin '—' si value est absente ou invalide
- [x] fmtAppDateTime(value) -> toLocaleString('fr-FR', {timeZone, day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit'}) — ex. '10/09/2026 09:30' ; '—' si absent/invalide
- [x] appDatetimeLocalValue(date = new Date()) -> 'YYYY-MM-DDTHH:mm' a l'heure d'Antananarivo, pour pre-remplir un champ date/heure ; corrige le cas ou le moteur renvoie '24' pour minuit en le remplacant par '00'
- [x] appDatetimeLocalToIso(value) : lit une saisie 'YYYY-MM-DDTHH:mm' COMME une heure d'Antananarivo (ajoute ':00' si longueur 16, puis suffixe +03:00) et retourne l'instant ISO absolu
- [x] Toutes les dates affichees dans l'app doivent passer par fmtAppDate / fmtAppDateTime : format francais JJ/MM/AAAA et JJ/MM/AAAA HH:mm
- [x] La valeur vide affichee est '—' (tiret cadratin), pas une chaine vide
- [x] Incoherence a corriger au portage : formatNotificationDate (notifications-utils.tsx) n'applique pas le fuseau applicatif

### `lib/utils.ts — Helper de classes CSS`  —  SANS OBJET

Écran Flutter : `a rattacher a l ecran hote`  
Fonctionnalités à garantir : 2

- [ ] cn(...inputs: ClassValue[]) = twMerge(clsx(inputs)) — combine clsx (classes conditionnelles) et tailwind-merge (derniere classe gagnante en cas de conflit Tailwind)
- [ ] Sans equivalent en Flutter : ce helper disparait au portage, remplace par des ThemeData / styles conditionnels Dart

**Pourquoi sans objet :**
- Helper de classes CSS (Tailwind) : sans objet en Flutter.

## AUTHENTIFICATION

### `/`  —  VERIFIED

Écran Flutter : `features/auth/splash_screen.dart`  
Fonctionnalités à garantir : 5

- [x] `redirect('/login')` execute cote serveur — reponse HTTP 307, jamais de flash de contenu
- [x] metadata.title = 'E-kajy Entana'
- [x] Aucun bouton, aucun etat, aucun contenu rendu (la fonction ne retourne rien apres redirect)
- [x] Aucun etat UI — redirection instantanee
- [x] Equivalent Flutter : route initiale '/' qui fait un `Navigator.pushReplacementNamed('/login')` ou un redirect GoRouter sans splash

### `/login`  —  VERIFIED

Écran Flutter : `features/auth/login_screen.dart`  
Fonctionnalités à garantir : 26

- [x] Page serveur : conteneur plein ecran `min-h-screen flex items-center justify-center bg-gradient-to-br from-background to-muted p-4`
- [x] `<Suspense fallback={null}>` autour de LoginForm (necessaire car LoginForm utilise useSearchParams) — donc AUCUN skeleton pendant l'hydratation
- [x] metadata.title = 'Connexion - E-kajy Entana'
- [x] Carte centree `max-w-md shadow-xl` : titre 'Connexion' (text-2xl font-bold), description 'Accedez a votre espace E-kajy Entana'
- [x] Champ Email avec icone Mail (lucide) positionnee en absolute a gauche (pl-10), pointer-events-none
- [x] Champ Mot de passe avec icone Lock a gauche (pl-10) et bouton oeil a droite (pr-10)
- [x] Bouton toggle visibilite du mot de passe : icone Eye / EyeOff, `type=button`, `tabIndex={-1}`, aria-label dynamique 'Masquer le mot de passe' / 'Afficher le mot de passe' — bascule input type password <-> text
- [x] Lien 'Mot de passe oublie ?' (text-xs, primary, hover:underline) place a droite du label Mot de passe, sur la meme ligne -> /forgot-password
- [x] Bouton submit pleine largeur 'Se connecter' ; en cours de chargement affiche `<Loader2 animate-spin>` + texte 'Connexion…' et devient disabled
- [x] Lien bas de carte : 'Pas encore de compte? Creer un compte' -> /register
- [x] Pre-remplissage automatique de l'email depuis le query param `?email=` (useEffect sur searchParams -> setEmail)
- [x] `noValidate` sur le <form> : la validation HTML native est desactivee, donc les attributs `required` ne bloquent PAS la soumission — on peut soumettre vide et l'erreur vient du backend
- [x] Navigation apres succes via `router.push(destination)` (helper `goTo`)
- [x] Formulaire 'Connexion' (handleLogin). CHAMPS : (1) email — id `login-email`, type=email, autoComplete=email, placeholder 'vous@example.com', required (inoperant car noValidate), disabled pendant loading, pre-rempli par ?email= ; (2) password — id `login-password`, type password|text selon showPw, autoComplete=current-password, placeholder '••••••••', required (inoperant), disabled pendant loading. AUCUNE validation cote client (pas de longueur min, pas de regex email) : tout est delegue au backend. SOUMISSION : e.preventDefault() -> setLoading(true) -> djangoClient.auth.login(email, password). SUCCES : si `!response.user.is_confirmed` -> toast.error('Compte en attente d\'approbation. Contactez votre manager.') + setLoading(false) + return (PAS de redirection, mais les tokens restent en localStorage) ; sinon toast.success('Connexion reussie !') puis push vers /dashboard (admin|magasin) ou /orders (autres). ERREUR : toast.error(friendlyError(message)). `finally` remet toujours loading a false.
- [x] Aucun modal / dialog / drawer / popover sur cette page. Les seuls retours utilisateur sont des toasts Sonner (Toaster global monte dans app/layout.tsx)
- [x] loading : etat booleen unique — desactive les deux inputs ET le bouton submit, remplace le libelle du bouton par spinner + 'Connexion…'
- [x] error : PAS d'affichage inline — uniquement via toast.error (rouge, richColors)
- [x] success : toast.success('Connexion reussie !') puis navigation
- [x] unauthorized / compte non approuve : toast.error, on reste sur la page
- [x] empty : non applicable
- [x] Aucun skeleton (Suspense fallback = null)
- [x] TABLE DE TRADUCTION DES ERREURS (`ERRORS`, matching par `msg.includes(key)`, premiere cle qui matche gagne, sinon le message brut backend est affiche tel quel) : 'Invalid login credentials' -> 'Email ou mot de passe incorrect.' ; 'No active account found' -> 'Email ou mot de passe incorrect.' ; 'Email not confirmed' -> 'Compte non confirme. Contactez l\'administrateur.' ; 'Compte non approuve' -> 'Compte en attente d\'approbation. Contactez votre administrateur.' ; 'User not found' -> 'Aucun compte avec cet email.' ; 'Too many requests' -> 'Trop de tentatives. Attendez quelques minutes.' ; 'Account pending approval' -> 'Compte en attente d\'approbation. Contactez votre manager.' ; 'Account rejected' -> 'Compte rejete. Contactez votre manager.' ; 'Authentication failed' -> 'Email ou mot de passe incorrect.'
- [x] Toasts : position top-right, richColors, closeButton, expand, duration 5000ms (config globale du <Toaster> dans app/layout.tsx)
- [x] Fond degrade `bg-gradient-to-br from-background to-muted`, carte `shadow-xl`
- [x] Theme clair/sombre gere par next-themes (attribute='class', defaultTheme='system', enableSystem, disableTransitionOnChange)
- [x] Le libelle de la marque affiche est 'E-kajy Entana' (titre metadata) alors que le titre global du layout est 'StockManager' — incoherence de branding presente dans le code

### `/register`  —  VERIFIED

Écran Flutter : `features/auth/register_screen.dart`  
Fonctionnalités à garantir : 34

- [x] Page serveur, pas de Suspense (le formulaire n'utilise pas useSearchParams) ; conteneur `min-h-screen flex items-center min-w-fit justify-center bg-linear-to-br from-background to-muted p-4`
- [x] metadata.title = 'Inscription - E-kajy Entana'
- [x] Carte `max-w-md shadow-xl border-t-4 border-t-primary` (liseret colore en haut, distinctif vs login)
- [x] Titre 'Creer un compte', description 'Rejoignez E-kajy Entana'
- [x] RadioGroup 'Type de compte' en grille 3 colonnes (`grid grid-cols-3 gap-2`), chaque option est une carte bordee cliquable p-2 avec RadioGroupItem + Label
- [x] Couleur de selection par role : admin -> `border-blue-500 bg-blue-50 dark:bg-blue-950/30` ; store_manager -> `border-cyan-500 bg-cyan-50 dark:bg-cyan-950/30` ; employee -> `border-green-500 bg-green-50 dark:bg-green-950/30` ; non selectionne -> `hover:bg-muted/50`
- [x] Champs dynamiques apparaissant avec animation `animate-in fade-in duration-200` selon le role choisi
- [x] role=admin : ajoute UN champ 'Nom de l'entreprise' (icone Building2)
- [x] role=store_manager : ajoute DEUX champs — 'Nom du magasin' (Building2) et 'Email de l'administrateur' (Mail)
- [x] role=employee : ajoute DEUX champs — 'Email du responsable (Admin ou Gerant)' (Mail) et 'Poste / Fonction' (User)
- [x] Champ 'Nom d'utilisateur' explicitement marque (Optionnel) en text-muted-foreground text-xs
- [x] Toggle visibilite mot de passe (Eye/EyeOff), meme mecanique que le login (type=button, tabIndex=-1, aria-label dynamique)
- [x] Texte d'aide sous le mot de passe : 'Minimum 6 caracteres' (text-xs muted)
- [x] Asterisque rouge `<span className='text-destructive'>*</span>` sur tous les champs obligatoires
- [x] Bouton submit pleine largeur : "S'inscrire" ; pendant loading -> Loader2 spinner + 'Creation du compte…' et disabled
- [x] Lien bas de carte : 'Deja un compte? Se connecter' -> /login
- [x] `noValidate` sur le form : les `required` / `minLength={6}` HTML ne bloquent pas — toute la validation est faite en JS avant l'appel API
- [x] Tous les inputs sont `disabled={loading}`
- [x] Formulaire 'Creer un compte' (handleRegister). CHAMPS COMMUNS : (1) role — RadioGroup, defaut 'employee' ; (2) fullName — id `reg-fullname`, type text, placeholder 'Jean Dupont', OBLIGATOIRE ; (3) username — id `reg-username`, type text, autoComplete=username, placeholder 'jean_dupont', OPTIONNEL (fallback = partie locale de l'email) ; (4) email — id `reg-email`, type email, autoComplete=email, placeholder 'vous@example.com', OBLIGATOIRE (mais pas de validation JS explicite !) ; (5) password — id `reg-password`, type password|text, autoComplete=new-password, placeholder '••••••••', minLength=6, OBLIGATOIRE.
- [x] CHAMPS CONDITIONNELS role=admin : companyName — id `reg-companyname`, type text, placeholder 'Ma Super Entreprise', OBLIGATOIRE.
- [x] CHAMPS CONDITIONNELS role=store_manager : shopName — id `reg-shopname`, type text, placeholder 'Boutique Centre-Ville', OBLIGATOIRE ; adminEmail — id `reg-adminemail`, type email, placeholder 'admin@boutique.com', OBLIGATOIRE.
- [x] CHAMPS CONDITIONNELS role=employee : adminEmail — id `reg-manageremail`, type email, placeholder 'gerant@boutique.com', OBLIGATOIRE (meme state React `adminEmail` que le manager, donc la valeur est conservee si on change de role) ; position — id `reg-position`, type text, placeholder 'Caissier, Vendeur...', OBLIGATOIRE.
- [x] VALIDATIONS CLIENT dans l'ordre exact, chacune fait toast.error + return (arret immediat, un seul message a la fois) : (a) !fullName.trim() -> 'Le nom complet est requis.' ; (b) password.length < 6 -> 'Le mot de passe doit contenir au moins 6 caracteres.' ; (c) role==='admin' && !companyName.trim() -> "Le nom de l'entreprise est requis." ; (d) role==='store_manager' && !shopName.trim() -> 'Le nom du magasin est requis.' ; (e) role==='store_manager' && !adminEmail.trim() -> "L'email de l'administrateur est requis." ; (f) role==='employee' && !adminEmail.trim() -> "L'email du responsable est requis." ; (g) role==='employee' && !position.trim() -> 'Le poste / fonction est requis.' — ATTENTION : l'EMAIL du compte lui-meme n'est JAMAIS valide cote client (ni presence ni format).
- [x] APRES SOUMISSION REUSSIE : toast.success avec un message dependant du role — admin : "Compte cree ! En attente d'approbation." ; store_manager et employee : "Compte cree ! En attente d'approbation par un administrateur." — puis `router.push('/auth/pending-approval')`. Le formulaire n'est PAS reinitialise, aucune connexion automatique, aucun token n'est stocke.
- [x] ERREUR : toast.error(friendlyError(message)) et on reste sur le formulaire (les valeurs saisies sont conservees).
- [x] Aucun modal/dialog. Feedback exclusivement par toasts Sonner.
- [x] loading : tous les inputs + le bouton disabled, bouton = spinner + 'Creation du compte…'
- [x] error : toast rouge uniquement (aucun message d'erreur inline sous les champs, aucun etat 'champ invalide' visuel)
- [x] success : toast vert + navigation vers /auth/pending-approval
- [x] Aucun etat empty / skeleton / unauthorized
- [x] TABLE DE TRADUCTION DES ERREURS (matching par includes) : 'User already registered' -> 'Un compte existe deja avec cet email.' ; 'Password should be at least' -> 'Le mot de passe doit contenir au moins 6 caracteres.' ; 'Unable to validate email' -> 'Adresse email invalide.' ; 'Too many requests' -> 'Trop de tentatives. Attendez quelques minutes.' — sinon message backend brut (souvent du type 'admin_email: Administrateur introuvable avec cet email.' ou 'email: user with this email already exists.')
- [x] Les erreurs backend metier les plus frequentes a prevoir : 'admin_email: Administrateur introuvable avec cet email.' (role magasin, email admin inconnu) ; 'admin_email: Responsable (administrateur ou gerant) introuvable avec cet email.' (role employer)
- [x] Icones lucide utilisees : Loader2, Mail, Lock, User, Eye, EyeOff, Building2
- [x] Le sous-role Commande (PREPARATEUR / LIVREUR) N'EST PAS choisissable a l'inscription : le serializer accepte `commande_role` mais le formulaire ne l'envoie jamais — il est attribue plus tard par le gerant (endpoint /users/employers/<id>/commande-role/)

**Écarts documentés (adaptations mobiles assumées ou limites du backend) :**
- Un administrateur auto-inscrit est confirmé immédiatement (users/serializers.py) : message « Compte créé ! Vous pouvez vous connecter. » et retour à /login, là où le web affiche « en attente d'approbation » pour tous.

### `/forgot-password`  —  VERIFIED

Écran Flutter : `features/auth/forgot_password_screen.dart`  
Fonctionnalités à garantir : 27

- [x] Page serveur avec `<Suspense fallback={null}>` ; conteneur `min-h-screen ... bg-gradient-to-br from-background to-muted p-4`
- [x] metadata.title = 'Mot de passe oublie - E-kajy Entana'
- [x] Carte `max-w-md shadow-xl` ; titre avec icone KeyRound + 'Mot de passe oublie'
- [x] MACHINE A ETATS a 2 ecrans dans la meme carte : state `step` = 'request' | 'check' (defaut 'request')
- [x] Description de la carte dynamique : step='request' -> 'Entrez votre email : votre demande sera transmise pour validation.' ; step='check' -> 'Verifiez si votre demande a ete validee.'
- [x] ETAPE 'request' : champ Email + bouton 'Envoyer la demande' + lien texte 'Demande deja envoyee ? Verifier le statut' (bouton type=button qui bascule step vers 'check' SANS appel API)
- [x] ETAPE 'check' : champ Email + bouton outline 'Verifier le statut' ; puis bandeau de statut ; puis (si approuve) sous-formulaire de nouveau mot de passe ; puis lien 'Faire une nouvelle demande' (fleche ArrowLeft) qui remet step='request' ET status=null
- [x] BANDEAU DE STATUT (affiche seulement si status non nul ET different de 'none') — 3 variantes : approved -> icone CheckCircle2, `border-green-200 bg-green-50 text-green-700 dark:bg-green-950/20 dark:text-green-400`, texte 'Demande validee : vous pouvez definir votre nouveau mot de passe.' ; pending -> icone Clock, `border-orange-200 bg-orange-50 text-orange-700 dark:bg-orange-950/20 dark:text-orange-400`, texte 'En attente de validation par votre administrateur.' ; rejected -> icone XCircle, `border-red-200 bg-red-50 text-red-700 dark:bg-red-950/20 dark:text-red-400`, texte 'Votre demande a ete rejetee. Contactez votre administrateur.'
- [x] SOUS-FORMULAIRE 'nouveau mot de passe' visible UNIQUEMENT si status === 'approved', separe par `border-t pt-4`
- [x] Lien permanent en bas de carte : 'Retour a la connexion' -> /login
- [x] Les 3 formulaires utilisent la validation HTML native (PAS de noValidate ici) : `required` et `minLength=6` bloquent donc reellement la soumission
- [x] Tous les inputs et boutons sont `disabled={loading}` ; les boutons affichent un Loader2 spinner a gauche du libelle pendant loading (libelle inchange)
- [x] FORMULAIRE 1 'Demande' (handleRequest, step='request'). CHAMP : email — id `fp-email`, type=email, placeholder 'vous@example.com', required, disabled pendant loading. Aucune validation JS. SOUMISSION : POST forgotPasswordRequest -> setStatus('pending') + setStep('check') + toast.success(res.message) (message renvoye par le BACKEND, pas en dur). ERREUR : toast.error(err.message || "Erreur lors de l'envoi de la demande"). NOTE : en cas de succes le statut est force a 'pending' localement sans relire le serveur.
- [x] FORMULAIRE 2 'Verification du statut' (handleCheckStatus, step='check'). CHAMP : email — id `fp-check-email`, type=email, placeholder 'vous@example.com', required, disabled pendant loading (meme state React `email`, donc pre-rempli si on vient de l'etape 1). SOUMISSION : GET forgotPasswordStatus -> setStatus(res.status) ; si res.status === 'none' -> toast.error('Aucune demande trouvee pour cet email.') et le bandeau reste masque. ERREUR : toast.error(err.message || 'Erreur lors de la verification'). Bouton `variant='outline'`.
- [x] FORMULAIRE 3 'Definir le mot de passe' (handleSetPassword, visible si status==='approved'). CHAMPS : newPassword — id `fp-new`, type=password, minLength=6, required, disabled pendant loading, PAS de toggle de visibilite ; confirm — id `fp-confirm`, type=password, required, disabled pendant loading, PAS de minLength. VALIDATION JS : `newPassword !== confirm` -> toast.error('Les mots de passe ne correspondent pas') + return. SOUMISSION : POST forgotPasswordConfirm(email, newPassword) -> toast.success('Mot de passe defini avec succes. Vous pouvez vous connecter.') + router.push('/login'). ERREUR : toast.error(err.message || 'Erreur lors de la definition du mot de passe'). Bouton 'Definir le mot de passe'.
- [x] Aucun modal. Le changement d'etape se fait in-place dans la meme carte (pas de drawer ni de stepper visuel).
- [x] loading (partage par les 3 formulaires) : inputs + boutons disabled, Loader2 spinner dans le bouton
- [x] status = null : aucun bandeau (etat initial de l'ecran 'check')
- [x] status = 'none' : bandeau MASQUE volontairement + toast d'erreur
- [x] status = 'pending' / 'approved' / 'rejected' : bandeau colore correspondant
- [x] success final : toast + redirection /login
- [x] error : toasts uniquement, aucun message inline
- [x] Pas d'email envoye du tout — c'est un flux d'approbation manuelle par l'admin, l'utilisateur doit revenir verifier lui-meme (a expliquer clairement dans l'UI Flutter)
- [x] Le message de succes de l'etape 1 vient du serveur (`res.message`), pas d'une constante — a ne pas coder en dur
- [x] Le bouton 'Verifier le statut' de l'ecran 'request' est un simple lien texte stylise (primary, font-medium, hover:underline), pas un Button
- [x] 'Faire une nouvelle demande' remet a zero step + status mais CONSERVE l'email saisi
- [x] Toute erreur backend est affichee brute si `err.message` existe (djangoClient aplati les erreurs DRF en 'cle: valeur | cle2: valeur2'). Le champ backend d'erreur est `error` (et non `detail`) pour ces 3 endpoints : djangoClient produira donc des chaines du type 'error: Une demande est deja en attente.'

### `/reset-password`  —  VERIFIED

Écran Flutter : `features/auth/reset_password_screen.dart`  
Fonctionnalités à garantir : 20

- [x] Page serveur avec `<Suspense>` dont le fallback est un vrai composant `ResetPasswordFallback` : carte `w-full max-w-md p-8 text-center bg-card rounded-lg shadow-xl border` + `<Loader2 className='mx-auto h-8 w-8 animate-spin text-primary mb-4'>` + texte 'Chargement...' (seul ecran de chargement de type skeleton de tout le perimetre auth)
- [x] metadata.title = 'Reinitialiser le mot de passe - E-kajy Entana'
- [x] Conteneur `min-h-screen flex items-center justify-center bg-linear-to-br from-background to-muted p-4`
- [x] Carte `w-full max-w-md` (PAS de shadow-xl, contrairement aux autres cartes auth)
- [x] Titre avec icone Lock : 'Changer le mot de passe' ; description : 'Entrez votre mot de passe actuel et votre nouveau mot de passe'
- [x] 3 champs empiles + bouton pleine largeur
- [x] AUCUN toggle de visibilite des mots de passe (les 3 champs restent type=password)
- [x] Le formulaire n'a PAS `noValidate` : la validation HTML native s'applique (required sur les 3, minLength=6 sur le nouveau)
- [x] Les inputs ne sont PAS disabled pendant le chargement (seul le bouton l'est) — l'utilisateur peut modifier les champs pendant l'appel
- [x] Aucun lien de retour vers /login ni ailleurs sur cette page
- [x] Formulaire 'Changer le mot de passe' (handleSubmit). CHAMPS : (1) oldPassword — id `old`, label 'Mot de passe actuel', type=password, required ; (2) newPassword — id `new`, label 'Nouveau mot de passe', type=password, minLength=6, required ; (3) confirm — id `confirm`, label 'Confirmer', type=password, required, PAS de minLength. VALIDATION JS : `newPassword !== confirm` -> toast.error('Les mots de passe ne correspondent pas') + return (le controle de longueur min est laisse au navigateur/backend). SOUMISSION : setLoading(true) -> POST -> toast.success('Mot de passe change avec succes') -> router.push('/login') (l'utilisateur est renvoye a l'ecran de connexion MAIS ses tokens ne sont PAS effaces : il reste techniquement authentifie en localStorage). ERREUR : toast.error(err.message || 'Erreur lors du changement'), on reste sur la page, champs conserves.
- [x] Aucun modal ni confirmation.
- [x] Suspense fallback : carte 'Chargement...' avec spinner Loader2 (seul vrai etat loading de page du perimetre)
- [x] loading (submit) : le bouton passe de 'Changer le mot de passe' a 'Changement...' et devient disabled ; PAS de spinner icone ici (texte seul)
- [x] error : toast rouge
- [x] success : toast vert + redirection /login
- [x] unauthorized : non gere cote UI — se traduit par une erreur toast avec le message backend, ou par une redirection dure vers /login declenchee par l'intercepteur 401 du client
- [x] Nom de route trompeur : /reset-password = changement de mot de passe authentifie ; le vrai 'mot de passe oublie' est /forgot-password
- [x] Route morte : elle n'est referencee par aucun Link/router.push du frontend (a confirmer avec le produit avant de la porter en Flutter)
- [x] Message d'erreur du backend porte par la cle `error` pour le 403 (aplati par djangoClient en 'error: Seul le gerant...') et par `detail` pour les 400 (affiche tel quel)

### `/verify-email`  —  VERIFIED

Écran Flutter : `features/auth/verify_email_screen.dart`  
Fonctionnalités à garantir : 11

- [x] Conteneur `min-h-screen flex items-center justify-center bg-muted/30 p-4` (fond uni muted/30, pas de degrade)
- [x] Carte `w-full max-w-md shadow-xl text-center`
- [x] Pastille ronde centree `mx-auto bg-primary/10 w-16 h-16 rounded-full` contenant l'icone Mail `h-8 w-8 text-primary`
- [x] Titre 'Verifiez votre email' (text-2xl font-bold)
- [x] Description : 'Un lien de confirmation vous a ete envoye.'
- [x] Paragraphe explicatif (text-sm muted) : 'Veuillez cliquer sur le lien dans l'email pour activer votre compte. Si vous ne le voyez pas, verifiez vos courriers indesirables.'
- [x] UN SEUL bouton : `variant='outline'`, pleine largeur, `asChild` autour d'un Link -> /login, contenu : icone ArrowLeft (mr-2 h-4 w-4) + 'Retour a la connexion'
- [x] Pas de metadata exportee (herite du title global 'StockManager')
- [x] Aucun etat : page purement statique
- [x] Aucun bouton 'Renvoyer l'email' n'existe
- [x] A NE PROBABLEMENT PAS PORTER en Flutter tel quel : le produit ne verifie pas les emails, il utilise l'approbation manuelle par l'admin

### `/pending-approval`  —  VERIFIED

Écran Flutter : `features/auth/pending_approval_screen.dart`  
Fonctionnalités à garantir : 13

- [x] Conteneur `min-h-screen flex items-center justify-center bg-muted/30 p-4`
- [x] Carte `w-full max-w-md shadow-xl text-center`
- [x] Pastille ronde `mx-auto bg-amber-100 w-16 h-16 rounded-full` avec icone Clock `h-8 w-8 text-amber-600` (couleur ambre = attente ; note : pas de variante dark ici)
- [x] Titre 'Compte en attente' (text-2xl font-bold)
- [x] Description : 'Votre acces doit etre approuve par un administrateur.'
- [x] Paragraphe : 'Merci de votre patience. Un administrateur examine actuellement votre demande. Vous recevrez un acces complet des que votre compte sera approuve.'
- [x] BOUTON 1 (primaire, pleine largeur) libelle 'Actualiser la page' — mais c'est en realite un `<Link href='/login'>` : il NE rafraichit PAS le statut, il renvoie vers la connexion (libelle trompeur, a corriger/adapter en Flutter)
- [x] BOUTON 2 `variant='ghost'` pleine largeur `text-muted-foreground` : icone LogOut + 'Se deconnecter' -> Link vers /logout
- [x] Les deux boutons sont empiles dans un `flex flex-col gap-2`
- [x] Pas de metadata exportee
- [x] Aucun etat : page statique, aucun polling du statut d'approbation
- [x] Code couleur attente : amber-100 / amber-600
- [x] Aucune verification periodique du statut (pas de polling, pas de websocket) — l'utilisateur doit re-tenter une connexion manuellement

### `/logout`  —  VERIFIED

Écran Flutter : `widgets/topbar.dart`  
Fonctionnalités à garantir : 9

- [x] useEffect au montage (dependance [router]) : appelle `djangoClient.auth.logout()` PUIS `router.push('/login')` PUIS `router.refresh()`
- [x] BUG A CONNAITRE : `djangoClient.auth.logout()` est async mais n'est PAS await — la navigation demarre avant la fin de la purge (le `localStorage.clear()` peut s'executer apres la redirection)
- [x] Rendu : `<div className='flex items-center justify-center min-h-screen'><p className='text-muted-foreground'>Deconnexion...</p></div>` — un simple texte, sans spinner
- [x] Pas de metadata, pas de bouton, pas d'interaction
- [x] Aucune confirmation de deconnexion (ni sur cette route, ni depuis la sidebar/topbar)
- [x] Un unique ecran transitoire avec le texte 'Deconnexion...'
- [x] EFFET DE BORD MAJEUR : `localStorage.clear()` — vide TOUT le localStorage du domaine, pas seulement la cle 'django_tokens' (toute preference/cache stocke par d'autres ecrans est detruit). Puis `this.tokens = null` en memoire
- [x] Il n'y a AUCUNE invalidation serveur du JWT (commentaire explicite du backend) : un token deja emis reste valide jusqu'a expiration
- [x] Le meme `djangoClient.auth.logout()` est aussi declenche par le bouton Deconnexion de la Sidebar (avec await + router.push('/login') + router.refresh()) et de la TopBar (sans await, + router.push('/login'))

## AJOUTÉ AU NEXT.JS DEPUIS L'AUDIT

Fonctionnalités ajoutées au frontend après l'audit automatisé — elles n'y figurent pas et sont
listées ici avec leur état Flutter constaté.

### COMMANDES — /orders — détail de commande

- [x] Boutons de statut en bas de la fiche, sous l'historique détaillé ; « Modifier » seul en en-tête  `VERIFIED`
- [x] La fiche reste ouverte jusqu'au statut terminal : après chaque transition elle se recharge et propose l'étape suivante  `VERIFIED`
- [x] Confirmation intégrée (note + photo) sans fermer la fiche  `VERIFIED`
- [x] Photo de préparation : boutons « Prendre une photo » / « Choisir un fichier » + « Retirer »  `VERIFIED`
- [x] Assigner un préparateur / un livreur SANS faire avancer le statut  `VERIFIED`
- [x] Boutons d'assignation proposés seulement tant que le poste est vacant ; livreur assignable dès que le préparateur l'est  `VERIFIED`
- [x] Corriger l'état d'une commande close (Livré <-> Retour), gérant, avec remise en stock  `VERIFIED`
- [x] Mot à retaper avant Retour (RETOUR) et Annuler (ANNULER)  `VERIFIED`
- [x] Livraison partielle : oui/non pour 1 article, cases à cocher au-delà ; décoché = rapporté en stock et retiré du total ; rien = Retour  `VERIFIED`
- [x] Second numéro de téléphone (création, modification, détail, colonne livreur cliquable)  `VERIFIED`
- [x] Modifier reste disponible jusqu'à la livraison : zone, adresse, paiement, note livreur (frais et total recalculés)  `VERIFIED`
- [x] Partager la commande (résumé + photo) au livreur assigné dans la messagerie  `VERIFIED`
- [x] Ligne « Livraison prévue le / Livrée le » et métadonnées d'article étiquetées (Type, Sous-type, Marque, Quantité)  `VERIFIED`

### COMMANDES — /orders — listes par rôle

- [x] Tri : la plus récemment créée en haut, pour les 3 rôles  `VERIFIED`
- [x] Livreur : tournée filtrée sur la fenêtre d'affichage (jour J, et 5 h avant) ; bouton masqué avant minuit  `VERIFIED`
- [x] Livreur : commandes Nouvelle assignées visibles dans son planning  `VERIFIED`
- [x] Livreur : filtre statut réduit à « À récupérer » / « Livrées »  `VERIFIED`
- [x] Préparateur : fenêtre aujourd'hui + demain à partir de 19h00  `VERIFIED`
- [x] Filtres de date par défaut au jour J (Antananarivo) et « Réinitialiser » qui y ramène  `VERIFIED`

### COMMANDES — /bilan

- [x] Gérant : liste des livreurs avec totaux du jour (livraisons, retours, produits, frais, encaissé), ligne Total, clic = détail  `VERIFIED`
- [x] Gérant : sélecteur de jour  `VERIFIED`
- [x] Commande payée d'avance = 0 Ar encaissé, ligne « Dont payé d'avance »  `VERIFIED`
- [x] Dépenses du livreur : déclaration (type ou libre, montant, quantité, motif), liste avec statut, retrait tant qu'en attente  `VERIFIED`
- [x] Gérant : accepter / rejeter chaque dépense ; colonne « Dépenses » et « n à valider » dans la vue d'ensemble  `VERIFIED`
- [x] Ticket : « DÉPENSES VALIDÉES » et « NET À REMETTRE »  `VERIFIED`

### PILOTAGE — /dashboard (ex-/reports : le centre de rapports remplace le tableau de bord)

- [ ] Centre de rapports à 8 sections (Vue générale, Ventes, Financier, Dépenses, Stock, Commandes, Livraisons, Marketing) sur GET /api/orders/reports/{section}/  `__DASH__`
- [ ] Filtres communs : 8 préréglages, bornes libres, granularité automatique / jour / semaine / mois / année, comparaison avec la période précédente  `__DASH__`
- [ ] Cache par (section, paramètres), rechargement silencieux temps réel, bouton Actualiser  `__DASH__`
- [ ] Tableaux paginés avec export Excel, graphiques (séries, classements, anneaux), KPI avec variation  `__DASH__`
- [ ] Marketing : campagnes (créer / modifier / supprimer), ROI, filtre plateforme  `__DASH__`
- [ ] « Imprimer / PDF » de la section affichée  `__DASH__`
- [x] Page Rapports supprimée et entrée de menu retirée ; /reports redirige vers /dashboard  `IMPLEMENTED`
- [x] Vente à crédit supprimée  `IMPLEMENTED`

### COMMANDES — /orders — création

- [ ] Sélecteur « Campagne marketing (facultatif) » (campagnes actives, non-préparateur), envoyé en `campagne`  `__CAMP__`

### CATALOGUE & STOCK — /products

- [ ] Notes « produits à commander » : bouton « Nouvelle note », carte avec tableau, dialog de création (nom, catégorie, sous-type, marque, couleurs), suppression — GET/POST/DELETE /api/catalog/notes/  `__NOTES__`

### COMMUNICATION — /chats

- [x] Envoi d'image (fichier ou appareil photo) via POST /users/chat/upload/, affichage dans la bulle  `VERIFIED`
- [x] Salon Général retiré : conversations directes uniquement  `VERIFIED`
- [x] Badge de non-lus par contact  `VERIFIED`
- [x] Liste triée : non-lus d'abord, puis conversation la plus récente  `VERIFIED`
- [x] En-tête de page retiré ; liste des contacts défilante  `VERIFIED`

### COMMUNICATION — Navigation

- [x] Badge de messages non lus sur l'entrée « Chats » du menu (GET /users/chat/unread-count/, toutes les 30 s et à chaque page)  `VERIFIED`

### ADMINISTRATION — /settings

- [x] Carte « Dépenses des livreurs » : CRUD des types (nom, montant, à l'unité, actif, modifier, supprimer)  `VERIFIED`

### COMPOSANTS PARTAGÉS & SOCLE — Assistant

- [x] Bulle flottante en bas à droite : questions sur le guide de l'app (POST /api/ai/assistant, mode guide)  `IMPLEMENTED`
- [x] Gérant : « Générer le rapport du mois » (mode rapport)  `IMPLEMENTED`

### COMPOSANTS PARTAGÉS & SOCLE — Socle

- [x] Modèle de rôles admin / magasin / employer + drapeaux (core/permissions.dart)  `VERIFIED`
- [x] Menu identique au sidebar web + gardes de route  `VERIFIED`
- [x] Fuseau Indian/Antananarivo pour toutes les dates et le jour J  `VERIFIED`
- [x] Dialogues défilants (max-h 90dvh)  `IMPLEMENTED`

### COMMUNICATION — Notifications système (spécifique mobile, au-delà du web)

- [x] Notification dans la barre du téléphone (son, vibration) pour chaque événement temps réel reçu quand l'app n'est pas au premier plan : messages privés (« {expéditeur} : {texte} », « 📷 Photo »), commandes, dépenses, caisse…  `IMPLEMENTED`
- [x] Appui : ouvre la messagerie, la fiche de la commande citée (numéro CMD-… résolu) ou la page Notifications — y compris au lancement de l'app par la notification  `IMPLEMENTED`
- [x] Permission demandée après connexion (Android 13+, iOS) ; canaux Android « Messages » et « Notifications »  `IMPLEMENTED`
- [x] Au premier plan : toast in-app de la TopBar (comme le web), « Voir » ouvre la messagerie pour un message privé  `IMPLEMENTED`
- [ ] Réception app fermée / processus tué (push serveur via Firebase Cloud Messaging) — nécessite un projet Firebase et un envoi côté backend  `MISSING`

## SYNTHÈSE

| | Routes |
| --- | --- |
| MISSING | 0 |
| PARTIAL | 0 |
| IMPLEMENTED | 5 |
| VERIFIED | 54 |
| Supprimées côté web (rien à porter) | 1 |
| Sans objet côté Flutter (non utilisé par le web ou sans équivalent mobile) | 13 |
| Retirées de l'app à la demande (/superadmin, /scanner) | 2 |

Fonctionnalités ajoutées depuis l'audit : 53 (MISSING 1 · PARTIAL 0 · IMPLEMENTED 9 · VERIFIED 35)

**Total de cases à cocher : 2171 — cochées : 1623.**
