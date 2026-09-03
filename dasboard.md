# DONNEES A AFFICHER SUR LES DASHBOARDS

# DASHBOARD ADMIN

## Cartes Statistiques Principales

- Chiffre d’affaires total
- Bénéfices totaux
- Valeur totale du stock
- Nombre total de magasins
- Nombre total d’employés
- Nombre total de produits
- Nombre total de ventes
- Ventes du jour
- Bénéfices du jour
- Produits en stock faible
- Produits expirés
- Produits bientôt expirés

---

# Données Produits

## Produits plus vendus

Afficher :

- nom produit
- quantité vendue
- bénéfice généré
- magasin concerné

## Produits moins vendus

Afficher :

- nom produit
- quantité vendue
- stock restant

## Produits en stock faible

Condition :

- stock_quantity <= alert_threshold

Afficher :

- nom produit
- stock restant
- seuil alerte
- magasin

## Produits expirés

Afficher :

- nom produit
- date expiration
- magasin

## Produits bientôt expirés

Afficher :

- expire dans moins de 7 jours
- expire dans moins de 30 jours

---

# Données Ventes

## Dernières ventes

Afficher :

- produit
- quantité
- prix vente
- total
- vendeur
- magasin
- date

## Historique ventes

Filtres :

- aujourd’hui
- semaine
- mois
- année
- magasin
- employé

---

# Données Employés

## Meilleurs employés

Afficher :

- nom
- nombre ventes
- montant total ventes
- bénéfices générés

## Employés actifs

Afficher :

- nom
- magasin
- rôle
- statut

---

# Données Magasins

## Meilleurs magasins

Afficher :

- chiffre d’affaires
- bénéfices
- nombre ventes
- stock total

## Magasins actifs

Afficher :

- nom magasin
- nombre employés
- nombre produits
- statut

---

# Graphiques ADMIN

## Graphique ventes

Types :

- journalier
- hebdomadaire
- mensuel
- annuel

## Graphique bénéfices

Afficher :

- évolution bénéfices

## Répartition ventes par magasin

Afficher :

- pourcentage ventes par magasin

## Répartition catégories produits

Afficher :

- catégorie
- quantité
- pourcentage

---

# DASHBOARD MAGASIN

## Cartes Principales

- ventes du jour
- bénéfices du jour
- valeur stock
- nombre produits
- nombre ventes
- stock faible
- produits expirés

---

# Données Produits

## Produits plus vendus

Afficher :

- nom produit
- quantité vendue

## Produits moins vendus

Afficher :

- nom produit
- stock restant

## Produits stock faible

Afficher :

- nom produit
- quantité restante

---

# Données Ventes

## Dernières ventes

Afficher :

- produit
- quantité
- vendeur
- total
- date

## Historique ventes

Filtres :

- jour
- semaine
- mois

---

# Données Employés

## Meilleurs vendeurs

Afficher :

- nom employé
- nombre ventes
- montant total

---

# Graphiques MAGASIN

## Ventes semaine

## Bénéfices semaine

## Produits populaires

## Répartition catégories

---

# DASHBOARD EMPLOYÉ

## Cartes Principales

- mes ventes aujourd’hui
- montant total vendu
- nombre produits vendus
- nombre clients

---

# Données Ventes

## Mes dernières ventes

Afficher :

- produit
- quantité
- total
- date

## Historique personnel

Filtres :

- aujourd’hui
- semaine
- mois

---

# ALERTES IMPORTANTES

## Stock faible

## Produits expirés

## Produits bientôt expirés

## Vente importante

## Activité suspecte

---

# FILTRES GLOBAUX

- aujourd’hui
- 7 jours
- 30 jours
- année
- magasin
- employé
- catégorie
- produit

---

# DONNEES IMPORTANTES A CALCULER

## Chiffre d’affaires

total ventes

## Bénéfices

(selling_price - purchase_price) \* quantité

## Valeur stock

purchase_price \* stock_quantity

## Valeur vente stock

selling_price \* stock_quantity

## Produits plus vendus

SUM(quantity)

## Produits moins vendus

ORDER BY ventes ASC

---

# DONNEES A NE PAS AFFICHER

## Pour magasin et employé

Ne jamais afficher :

- purchase_price
- bénéfices globaux société
- données autres magasins
- employés autres magasins

---

# KPI PRINCIPAUX

- chiffre affaires
- bénéfices
- valeur stock
- top ventes
- stock faible
- croissance ventes
- rentabilité produits
- magasin performant
- employé performant
