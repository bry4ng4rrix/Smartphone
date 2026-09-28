# Volontairement vide.
#
# La boutique en ligne ne stocke aucune donnée qui lui soit propre : le
# catalogue vient de `catalog`, les commandes de `orders`. Le modèle `Client`
# (comptes acheteurs) a été retiré — le site ne demande plus ni inscription
# ni connexion, les coordonnées sont saisies à chaque commande et vivent sur
# la commande elle-même (`Order.client_nom`, `telephone`, `telephone_2`).
