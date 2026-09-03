# Scénarios et Payloads de Test API (JSON)

Ce document rassemble tous les exemples de données (payloads JSON) pour tester l'intégralité des fonctionnalités de l'API avec des outils comme Postman, Insomnia ou cURL.

---

## 🔐 1. Authentification & Inscription

### 1.1 Inscription d'un Admin (Création directe & automatique)
* **Endpoint** : `POST /api/users/register/`
```json
{
  "full_name": "Admin Principal",
  "email": "admin@gmail.com",
  "password": "123456",
  "phone": "0340000000",
  "role": "admin",
  "company_name": "Smart Stock Company"
}
```

### 1.2 Inscription d'un Gérant de Magasin (En attente d'approbation)
* **Endpoint** : `POST /api/users/register/`
```json
{
  "full_name": "Gérant Analakely",
  "email": "magasin@gmail.com",
  "password": "123456",
  "phone": "0331111111",
  "role": "magasin",
  "shop_name": "Shop Center Analakely",
  "admin_email": "admin@gmail.com"
}
```

### 1.3 Inscription d'un Employé lié à un Magasin (En attente d'approbation)
* **Endpoint** : `POST /api/users/register/`
```json
{
  "full_name": "John Doe Vendeur",
  "email": "john@gmail.com",
  "password": "123456",
  "phone": "0322222222",
  "role": "employer",
  "position": "Caissier",
  "admin_email": "magasin@gmail.com"
}
```

### 1.4 Connexion (Génération des Tokens JWT)
* **Endpoint** : `POST /api/users/login/`
```json
{
  "email": "admin@gmail.com",
  "password": "123456"
}
```
* **Réponse de succès** :
```json
{
  "access": "eyJhbGciOi...",
  "refresh": "eyJhbGciOi..."
}
```

### 1.5 Approbation d'un utilisateur (Par l'Admin ou Magasin gérant)
* **Endpoint** : `PUT /api/users/approve/<user_id>/`
* **Headers** : `Authorization: Bearer <access_token>`
* **Réponse** :
```json
{
  "message": "Utilisateur approuvé avec succès",
  "user": "magasin@gmail.com",
  "is_confirmed": true
}
```

---

## 📦 2. Gestion des Produits

### 2.1 Création d'un Produit
* **Endpoint** : `POST /api/users/products/`
* **Headers** : `Authorization: Bearer <access_token>`
```json
{
  "name": "Smartphone Pro Max",
  "reference": "SP-PROMAX-001",
  "brand": "BrandX",
  "category": "Électronique",
  "description": "Dernier modèle de smartphone haute performance",
  "unit_price": "500.00",
  "shell_price": "750.00",
  "initial_quantity": 50,
  "alert_threshold": 5,
  "expiry_date": "2027-12-31"
}
```

### 2.2 Liste des Produits (Retour API pour un rôle non-admin)
* **Endpoint** : `GET /api/users/products/`
* **Réponse (unit_price masqué automatiquement)** :
```json
[
  {
    "id": 1,
    "name": "Smartphone Pro Max",
    "reference": "SP-PROMAX-001",
    "brand": "BrandX",
    "category": "Électronique",
    "description": "Dernier modèle de smartphone haute performance",
    "shell_price": "750.00",
    "initial_quantity": 50,
    "alert_threshold": 5,
    "expiry_date": "2027-12-31",
    "magasin": 1
  }
]
```

---

## 📈 3. Transactions de Vente

### 3.1 Enregistrement d'une Vente (Stock vérifié en temps réel)
* **Endpoint** : `POST /api/users/sales/`
* **Headers** : `Authorization: Bearer <access_token>`
```json
{
  "product": 1,
  "quantity": 2,
  "sale_price": "750.00"
}
```
* **Réponse** :
```json
{
  "id": 1,
  "product": 1,
  "magasin": 1,
  "shop_name": "Shop Center Analakely",
  "seller": 3,
  "seller_name": "John Doe Vendeur",
  "quantity": 2,
  "sale_price": "750.00",
  "total_price": "1500.00",
  "sold_at": "2026-05-19T12:00:00Z"
}
```

### 3.2 Tentative de Vente avec Stock Insuffisant (Bloqué par validation)
* **Endpoint** : `POST /api/users/sales/`
```json
{
  "product": 1,
  "quantity": 100,
  "sale_price": "750.00"
}
```
* **Réponse d'erreur (HTTP 400)** :
```json
{
  "quantity": [
    "Quantité en stock insuffisante. Stock disponible : 48."
  ]
}
```

---

## 📊 4. Analyses Financières & Tableau de Bord

### 4.1 Totaux de prix (Achat vs Vente)
* **Endpoint** : `GET /api/users/sales/totals/`
```json
{
  "total_unit_price": 500.00,
  "total_shell_price": 750.00
}
```

### 4.2 Bénéfices réels
* **Endpoint** : `GET /api/users/sales/profit/`
```json
{
  "profit": 500.00
}
```

### 4.3 Liste des Utilisateurs par Magasin
* **Endpoint** : `GET /api/users/magasins/users/`
```json
[
  {
    "magasin_id": 1,
    "shop_name": "Shop Center Analakely",
    "manager": {
      "id": 2,
      "full_name": "Gérant Analakely",
      "email": "magasin@gmail.com",
      "is_confirmed": true,
      "role": "magasin"
    },
    "employers": [
      {
        "id": 3,
        "full_name": "John Doe Vendeur",
        "email": "john@gmail.com",
        "is_confirmed": true,
        "position": "Caissier",
        "role": "employer"
      }
    ]
  }
]
```

### 4.4 Dashboard Unifié (Exemple de réponse pour rôle ADMIN)
* **Endpoint** : `GET /api/users/dashboard/`
```json
{
  "role": "admin",
  "kpis": {
    "total_revenue": 1500.00,
    "total_profit": 500.00,
    "total_stock_value": 24000.00,
    "total_magasins": 1,
    "total_employers": 1,
    "total_products": 1,
    "total_sales": 1,
    "sales_today": 1,
    "profit_today": 500.00,
    "low_stock_count": 0,
    "expired_count": 0,
    "expiring_soon_count": 0
  },
  "lists": {
    "top_products": [
      {
        "product__name": "Smartphone Pro Max",
        "product__magasin__shop_name": "Shop Center Analakely",
        "qty_sold": 2,
        "profit": 500.00
      }
    ],
    "bottom_products": [
      {
        "name": "Smartphone Pro Max",
        "initial_quantity": 48,
        "qty_sold": 2
      }
    ],
    "low_stock_products": [],
    "expired_products": [],
    "expiring_soon_products": [],
    "recent_sales": [
      {
        "product_name": "Smartphone Pro Max",
        "quantity": 2,
        "sale_price": "750.00",
        "total_price": "1500.00",
        "seller_name": "John Doe Vendeur",
        "shop_name": "Shop Center Analakely",
        "sold_at": "2026-05-19T12:00:00Z"
      }
    ],
    "best_employees": [
      {
        "seller__full_name": "John Doe Vendeur",
        "sales_count": 1,
        "total_amount": 1500.00,
        "profit": 500.00
      }
    ],
    "best_shops": [
      {
        "magasin__shop_name": "Shop Center Analakely",
        "total_amount": 1500.00,
        "profit": 500.00,
        "sales_count": 1,
        "total_stock": 48
      }
    ]
  }
}
```

### 4.5 Liste Globale des Endpoints (Découverte API)
* **Endpoint** : `GET /api/users/endpoints/`
* **Auth** : Non requis (Public)
* **Réponse** :
```json
[
  {
    "path": "/api/users/login/",
    "method": "POST",
    "auth_required": false,
    "roles_allowed": ["Any"],
    "description": "Authentifie un utilisateur et retourne les tokens JWT (access & refresh)."
  },
  {
    "path": "/api/users/refresh/",
    "method": "POST",
    "auth_required": false,
    "roles_allowed": ["Any"],
    "description": "Rafraîchit le token d'accès JWT expiré."
  },
  {
    "path": "/api/users/endpoints/",
    "method": "GET",
    "auth_required": false,
    "roles_allowed": ["Any"],
    "description": "Liste l'ensemble des endpoints disponibles avec leurs descriptions et permissions."
  }
]
```