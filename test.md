# API Endpoints - JSON Documentation

## Base URL
```
http://localhost:8000/api/users/
```

---

## 1. Authentication

### 1.1 POST `/api/users/login/`
**Description:** Authentifie un utilisateur et retourne les tokens JWT (access & refresh)

**Request:**
```json
{
  "username": "user@example.com",
  "password": "password123"
}
```

**Response (200 OK):**
```json
{
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response (401 Unauthorized):**
```json
{
  "detail": "Invalid credentials"
}
```

---

### 1.2 POST `/api/users/refresh/`
**Description:** Rafraîchit le token d'accès JWT expiré

**Request:**
```json
{
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response (200 OK):**
```json
{
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

---

## 2. User Management

### 2.1 POST `/api/users/register/`
**Description:** Inscrit un nouvel utilisateur

#### 2.1.1 Register as Admin
**Request:**
```json
{
  "full_name": "John Admin",
  "email": "admin@example.com",
  "password": "password123",
  "phone": "+1234567890",
  "role": "admin",
  "company_name": "My Company"
}
```

**Response (200 OK):**
```json
{
  "message": "Inscription réussie"
}
```

#### 2.1.2 Register as Magasin (Store Manager)
**Request:**
```json
{
  "full_name": "Store Manager",
  "email": "magasin@example.com",
  "password": "password123",
  "phone": "+1234567890",
  "role": "magasin",
  "shop_name": "My Shop",
  "admin_email": "admin@example.com"
}
```

**Response (200 OK):**
```json
{
  "message": "Inscription réussie"
}
```

#### 2.1.3 Register as Employer (Employee/Seller)
**Request:**
```json
{
  "full_name": "John Seller",
  "email": "seller@example.com",
  "password": "password123",
  "phone": "+1234567890",
  "role": "employer",
  "position": "Sales Representative",
  "admin_email": "admin@example.com"
}
```

**Response (200 OK):**
```json
{
  "message": "Inscription réussie"
}
```

**Response (400 Bad Request):**
```json
{
  "email": ["Ce champ doit être unique."],
  "role": ["Rôle invalide"]
}
```

---

### 2.2 GET `/api/users/me/`
**Description:** Retourne le profil complet de l'utilisateur connecté

**Auth:** Required (Bearer Token)

**Response (200 OK):**
```json
{
  "id": 1,
  "username": "user@example.com",
  "email": "user@example.com",
  "role": "admin",
  "is_confirmed": true
}
```

---

### 2.3 PUT `/api/users/approve/<user_id>/`
**Description:** Approuve et active un compte utilisateur en attente

**Auth:** Required - Admin or Magasin role

**URL Parameter:** `user_id` (integer) - ID de l'utilisateur à approuver

**Response (200 OK):**
```json
{
  "message": "Utilisateur approuvé"
}
```

**Response (403 Forbidden):**
```json
{
  "error": "Permission refusée"
}
```

**Response (404 Not Found):**
```json
{
  "error": "Utilisateur introuvable"
}
```

---

### 2.4 PUT `/api/users/role/<user_id>/`
**Description:** Modifie le rôle d'un utilisateur (Admin only)

**Auth:** Required - Admin role

**URL Parameter:** `user_id` (integer) - ID de l'utilisateur

**Request:**
```json
{
  "role": "magasin"
}
```

**Allowed roles:** `admin`, `magasin`, `employer`

**Response (200 OK):**
```json
{
  "message": "Rôle modifié de employer à magasin",
  "user_id": 2,
  "email": "user@example.com",
  "new_role": "magasin"
}
```

**Response (400 Bad Request):**
```json
{
  "error": "Rôle invalide. Les rôles valides sont: admin, magasin, employer"
}
```

**Response (404 Not Found):**
```json
{
  "error": "Utilisateur introuvable"
}
```

---

## 3. Products Management

### 3.1 GET `/api/users/products/`
**Description:** Liste les produits (prix d'achat masqué pour magasin/employé)

**Auth:** Required

**Query Parameters (Filtering):**
- `magasin` - Filter by magasin ID (only for Magasin role)
- `category` - Filter by category
- `brand` - Filter by brand

**Response (200 OK) - Admin view:**
```json
[
  {
    "id": 1,
    "name": "Product Name",
    "reference": "REF-001",
    "brand": "Brand Name",
    "category": "Electronics",
    "description": "Product description",
    "unit_price": 50.00,
    "shell_price": 75.00,
    "initial_quantity": 100,
    "alert_threshold": 10,
    "expiry_date": "2027-12-31",
    "created_at": "2026-05-20T10:30:00Z",
    "updated_at": "2026-05-20T10:30:00Z",
    "magasin": 1
  }
]
```

**Response (200 OK) - Magasin/Employer view (unit_price hidden):**
```json
[
  {
    "id": 1,
    "name": "Product Name",
    "reference": "REF-001",
    "brand": "Brand Name",
    "category": "Electronics",
    "description": "Product description",
    "shell_price": 75.00,
    "initial_quantity": 100,
    "alert_threshold": 10,
    "expiry_date": "2027-12-31",
    "created_at": "2026-05-20T10:30:00Z",
    "updated_at": "2026-05-20T10:30:00Z",
    "magasin": 1
  }
]
```

---

### 3.2 POST `/api/users/products/`
**Description:** Crée un nouveau produit

**Auth:** Required - Admin or Magasin role

**Request (Admin):**
```json
{
  "name": "New Product",
  "reference": "REF-002",
  "brand": "Brand Name",
  "category": "Electronics",
  "description": "Product description",
  "unit_price": 50.00,
  "shell_price": 75.00,
  "initial_quantity": 100,
  "alert_threshold": 10,
  "expiry_date": "2027-12-31",
  "magasin": 1
}
```

**Request (Magasin):**
```json
{
  "name": "New Product",
  "reference": "REF-003",
  "brand": "Brand Name",
  "category": "Electronics",
  "description": "Product description",
  "unit_price": 50.00,
  "shell_price": 75.00,
  "initial_quantity": 100,
  "alert_threshold": 10,
  "expiry_date": "2027-12-31"
}
```

**Response (201 Created):**
```json
{
  "id": 2,
  "name": "New Product",
  "reference": "REF-002",
  "brand": "Brand Name",
  "category": "Electronics",
  "description": "Product description",
  "unit_price": 50.00,
  "shell_price": 75.00,
  "initial_quantity": 100,
  "alert_threshold": 10,
  "expiry_date": "2027-12-31",
  "created_at": "2026-05-20T10:30:00Z",
  "updated_at": "2026-05-20T10:30:00Z",
  "magasin": 1
}
```

**Response (400 Bad Request):**
```json
{
  "reference": ["Le produit avec cette référence existe déjà"],
  "initial_quantity": ["Ce champ est obligatoire"]
}
```

---

### 3.3 GET `/api/users/products/<id>/`
**Description:** Récupère les détails d'un produit spécifique

**Auth:** Required

**URL Parameter:** `id` (integer) - Product ID

**Response (200 OK):**
```json
{
  "id": 1,
  "name": "Product Name",
  "reference": "REF-001",
  "brand": "Brand Name",
  "category": "Electronics",
  "description": "Product description",
  "unit_price": 50.00,
  "shell_price": 75.00,
  "initial_quantity": 100,
  "alert_threshold": 10,
  "expiry_date": "2027-12-31",
  "created_at": "2026-05-20T10:30:00Z",
  "updated_at": "2026-05-20T10:30:00Z",
  "magasin": 1
}
```

**Response (404 Not Found):**
```json
{
  "detail": "Not found."
}
```

---

### 3.4 PUT/PATCH `/api/users/products/<id>/`
**Description:** Modifie un produit (Admin only)

**Auth:** Required - Admin role

**URL Parameter:** `id` (integer) - Product ID

**Request (PUT - Replace all fields):**
```json
{
  "name": "Updated Product",
  "reference": "REF-001",
  "brand": "Updated Brand",
  "category": "Electronics",
  "description": "Updated description",
  "unit_price": 60.00,
  "shell_price": 90.00,
  "initial_quantity": 150,
  "alert_threshold": 15,
  "expiry_date": "2028-12-31",
  "magasin": 1
}
```

**Request (PATCH - Partial update):**
```json
{
  "unit_price": 60.00,
  "shell_price": 90.00,
  "initial_quantity": 150
}
```

**Response (200 OK):**
```json
{
  "id": 1,
  "name": "Updated Product",
  "reference": "REF-001",
  "brand": "Updated Brand",
  "category": "Electronics",
  "description": "Updated description",
  "unit_price": 60.00,
  "shell_price": 90.00,
  "initial_quantity": 150,
  "alert_threshold": 15,
  "expiry_date": "2028-12-31",
  "created_at": "2026-05-20T10:30:00Z",
  "updated_at": "2026-05-20T11:00:00Z",
  "magasin": 1
}
```

**Response (403 Forbidden):**
```json
{
  "error": "Seul admin peut modifier"
}
```

---

### 3.5 DELETE `/api/users/products/<id>/`
**Description:** Supprime un produit (Admin only)

**Auth:** Required - Admin role

**URL Parameter:** `id` (integer) - Product ID

**Response (204 No Content):**
```
(Empty body)
```

**Response (403 Forbidden):**
```json
{
  "error": "Seul admin peut supprimer"
}
```

**Response (404 Not Found):**
```json
{
  "detail": "Not found."
}
```

---

## 4. Sales Management

### 4.1 GET `/api/users/sales/`
**Description:** Liste l'historique des ventes (filtré par rôle)

**Auth:** Required

**Query Parameters:**
- `product` - Filter by product ID
- `magasin` - Filter by magasin ID
- `seller` - Filter by seller ID
- `ordering` - Sort by field (e.g., `-sold_at` for latest first)

**Response (200 OK):**
```json
[
  {
    "id": 1,
    "product": 1,
    "magasin": 1,
    "shop_name": "My Shop",
    "seller": 3,
    "seller_name": "John Seller",
    "quantity": 5,
    "sale_price": 100.00,
    "total_price": 500.00,
    "sold_at": "2026-05-20T14:30:00Z"
  },
  {
    "id": 2,
    "product": 2,
    "magasin": 1,
    "shop_name": "My Shop",
    "seller": 3,
    "seller_name": "John Seller",
    "quantity": 3,
    "sale_price": 75.00,
    "total_price": 225.00,
    "sold_at": "2026-05-20T15:00:00Z"
  }
]
```

---

### 4.2 POST `/api/users/sales/`
**Description:** Enregistre une nouvelle vente

**Auth:** Required

**Request:**
```json
{
  "product": 1,
  "quantity": 5,
  "sale_price": 100.00
}
```

**Response (201 Created):**
```json
{
  "id": 3,
  "product": 1,
  "magasin": 1,
  "shop_name": "My Shop",
  "seller": 3,
  "seller_name": "John Seller",
  "quantity": 5,
  "sale_price": 100.00,
  "total_price": 500.00,
  "sold_at": "2026-05-20T15:30:00Z"
}
```

**Response (400 Bad Request) - Insufficient stock:**
```json
{
  "quantity": "Quantité en stock insuffisante. Stock disponible : 10."
}
```

**Response (400 Bad Request) - Missing fields:**
```json
{
  "product": ["Ce champ est obligatoire"],
  "quantity": ["Ce champ est obligatoire"],
  "sale_price": ["Ce champ est obligatoire"]
}
```

---

### 4.3 GET `/api/users/sales/<id>/`
**Description:** Récupère les détails d'une vente spécifique

**Auth:** Required

**URL Parameter:** `id` (integer) - Sale ID

**Response (200 OK):**
```json
{
  "id": 1,
  "product": 1,
  "magasin": 1,
  "shop_name": "My Shop",
  "seller": 3,
  "seller_name": "John Seller",
  "quantity": 5,
  "sale_price": 100.00,
  "total_price": 500.00,
  "sold_at": "2026-05-20T14:30:00Z"
}
```

---

### 4.4 PUT/PATCH `/api/users/sales/<id>/`
**Description:** Modifie une vente existante

**Auth:** Required

**Request:**
```json
{
  "quantity": 10,
  "sale_price": 95.00
}
```

**Response (200 OK):**
```json
{
  "id": 1,
  "product": 1,
  "magasin": 1,
  "shop_name": "My Shop",
  "seller": 3,
  "seller_name": "John Seller",
  "quantity": 10,
  "sale_price": 95.00,
  "total_price": 950.00,
  "sold_at": "2026-05-20T14:30:00Z"
}
```

---

### 4.5 DELETE `/api/users/sales/<id>/`
**Description:** Supprime une vente

**Auth:** Required

**URL Parameter:** `id` (integer) - Sale ID

**Response (204 No Content):**
```
(Empty body)
```

---

## 5. Analytics & Reporting

### 5.1 GET `/api/users/sales/totals/`
**Description:** Calcule la somme globale des unit_price et shell_price de tous les produits

**Auth:** Required

**Response (200 OK):**
```json
{
  "total_unit_price": 5000.00,
  "total_shell_price": 7500.00
}
```

---

### 5.2 GET `/api/users/sales/profit/`
**Description:** Calcule le bénéfice réel total

**Auth:** Required

**Response (200 OK):**
```json
{
  "profit": 1250.50
}
```

---

### 5.3 GET `/api/users/magasins/users/`
**Description:** Liste tous les utilisateurs (managers et employés) regroupés par magasin

**Auth:** Required

**Response (200 OK):**
```json
[
  {
    "magasin_id": 1,
    "shop_name": "My Shop",
    "manager": {
      "id": 2,
      "full_name": "Store Manager",
      "email": "magasin@example.com",
      "is_confirmed": true,
      "role": "magasin"
    },
    "employers": [
      {
        "id": 3,
        "full_name": "John Seller",
        "email": "seller@example.com",
        "is_confirmed": true,
        "position": "Sales Representative",
        "role": "employer"
      },
      {
        "id": 4,
        "full_name": "Jane Seller",
        "email": "jane@example.com",
        "is_confirmed": true,
        "position": "Sales Representative",
        "role": "employer"
      }
    ]
  },
  {
    "magasin_id": 2,
    "shop_name": "Shop Two",
    "manager": {
      "id": 5,
      "full_name": "Another Manager",
      "email": "manager2@example.com",
      "is_confirmed": true,
      "role": "magasin"
    },
    "employers": []
  }
]
```

---

### 5.4 GET `/api/users/dashboard/`
**Description:** Tableau de bord analytique dynamique adapté au rôle de l'utilisateur

**Auth:** Required

#### 5.4.1 Dashboard Response - Admin
**Response (200 OK):**
```json
{
  "role": "admin",
  "kpis": {
    "total_revenue": 50000.00,
    "total_profit": 12500.00,
    "total_stock_value": 125000.00,
    "total_magasins": 5,
    "total_employers": 20,
    "total_products": 150,
    "total_sales": 350,
    "sales_today": 25,
    "profit_today": 625.00,
    "low_stock_count": 8,
    "expired_count": 2,
    "expiring_soon_count": 12
  },
  "lists": {
    "top_products": [
      {
        "product__name": "Popular Product",
        "product__magasin__shop_name": "My Shop",
        "qty_sold": 150,
        "profit": 5000.00
      }
    ],
    "bottom_products": [
      {
        "name": "Slow Product",
        "initial_quantity": 100,
        "qty_sold": 5
      }
    ],
    "low_stock_products": [
      {
        "name": "Low Stock Item",
        "initial_quantity": 3,
        "alert_threshold": 10,
        "magasin__shop_name": "My Shop"
      }
    ],
    "expired_products": [
      {
        "name": "Expired Item",
        "expiry_date": "2026-05-10",
        "magasin__shop_name": "My Shop"
      }
    ],
    "expiring_soon_products": [
      {
        "name": "Expiring Soon",
        "expiry_date": "2026-06-15",
        "magasin__shop_name": "My Shop"
      }
    ],
    "recent_sales": [
      {
        "product_name": "Product A",
        "quantity": 5,
        "sale_price": 100.00,
        "total_price": 500.00,
        "seller_name": "John Seller",
        "shop_name": "My Shop",
        "sold_at": "2026-05-20T15:30:00Z"
      }
    ],
    "best_employees": [
      {
        "seller__full_name": "Top Seller",
        "sales_count": 85,
        "total_amount": 8500.00,
        "profit": 2125.00
      }
    ],
    "best_shops": [
      {
        "magasin__shop_name": "Best Shop",
        "total_amount": 25000.00,
        "profit": 6250.00,
        "sales_count": 175,
        "total_stock": 2000
      }
    ]
  }
}
```

#### 5.4.2 Dashboard Response - Magasin
**Response (200 OK):**
```json
{
  "role": "magasin",
  "kpis": {
    "sales_today": 10,
    "profit_today": 250.00,
    "stock_value": 25000.00,
    "total_products": 50,
    "total_sales": 120,
    "low_stock_count": 3,
    "expired_count": 1
  },
  "lists": {
    "top_products": [
      {
        "product__name": "Best Seller",
        "qty_sold": 45
      }
    ],
    "bottom_products": [
      {
        "name": "Slow Item",
        "initial_quantity": 50,
        "qty_sold": 2
      }
    ],
    "low_stock_products": [
      {
        "name": "Low Stock",
        "initial_quantity": 2
      }
    ],
    "recent_sales": [
      {
        "product_name": "Product A",
        "quantity": 5,
        "total_price": 500.00,
        "seller_name": "John Seller",
        "sold_at": "2026-05-20T15:30:00Z"
      }
    ],
    "best_sellers": [
      {
        "seller__full_name": "Top Seller",
        "sales_count": 35,
        "total_amount": 3500.00
      }
    ]
  }
}
```

#### 5.4.3 Dashboard Response - Employer
**Response (200 OK):**
```json
{
  "role": "employer",
  "kpis": {
    "my_sales_today": 5,
    "total_amount_sold": 2500.00,
    "products_sold_count": 50,
    "clients_count": 45
  },
  "lists": {
    "recent_sales": [
      {
        "product_name": "Product A",
        "quantity": 5,
        "total_price": 500.00,
        "sold_at": "2026-05-20T15:30:00Z"
      }
    ]
  }
}
```

---

## 6. System Information

### 6.1 GET `/api/users/endpoints/`
**Description:** Liste l'ensemble des endpoints disponibles avec descriptions

**Auth:** Not required (Public endpoint)

**Response (200 OK):**
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
    "path": "/api/users/register/",
    "method": "POST",
    "auth_required": false,
    "roles_allowed": ["Any"],
    "description": "Inscrit un nouvel utilisateur (admin créé automatiquement, magasin/employé en attente)."
  },
  {
    "path": "/api/users/me/",
    "method": "GET",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Retourne le profil complet et les informations de l'utilisateur connecté."
  },
  {
    "path": "/api/users/approve/<user_id>/",
    "method": "PUT",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin"],
    "description": "Approuve et active un compte utilisateur en attente de validation."
  },
  {
    "path": "/api/users/role/<user_id>/",
    "method": "PUT",
    "auth_required": true,
    "roles_allowed": ["admin"],
    "description": "Modifie le rôle d'un utilisateur existant."
  },
  {
    "path": "/api/users/products/",
    "method": "GET, POST",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "GET: Liste les produits. POST: Crée un nouveau produit."
  },
  {
    "path": "/api/users/products/<id>/",
    "method": "GET, PUT, PATCH, DELETE",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Consulte, modifie ou supprime un produit spécifique."
  },
  {
    "path": "/api/users/sales/",
    "method": "GET, POST",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "GET: Historique des ventes. POST: Enregistre une nouvelle vente."
  },
  {
    "path": "/api/users/sales/<id>/",
    "method": "GET, PUT, PATCH, DELETE",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Consulte ou modifie une vente spécifique."
  },
  {
    "path": "/api/users/sales/totals/",
    "method": "GET",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Calcule la somme globale des unit_price et shell_price."
  },
  {
    "path": "/api/users/sales/profit/",
    "method": "GET",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Calcule le bénéfice réel total."
  },
  {
    "path": "/api/users/magasins/users/",
    "method": "GET",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Retourne la liste des utilisateurs regroupés par magasin."
  },
  {
    "path": "/api/users/dashboard/",
    "method": "GET",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Tableau de bord analytique dynamique adapté au profil utilisateur."
  },
  {
    "path": "/api/users/endpoints/",
    "method": "GET",
    "auth_required": false,
    "roles_allowed": ["Any"],
    "description": "Liste l'ensemble des endpoints disponibles."
  }
]
```

---

## HTTP Status Codes Reference

| Code | Meaning |
|------|---------|
| 200 | OK - Requête réussie |
| 201 | Created - Ressource créée |
| 204 | No Content - Suppression réussie |
| 400 | Bad Request - Erreur de validation |
| 401 | Unauthorized - Authentification requise |
| 403 | Forbidden - Permission refusée |
| 404 | Not Found - Ressource non trouvée |
| 500 | Internal Server Error - Erreur serveur |

---

## Authentication Header Example

Pour tous les endpoints protégés, inclure l'en-tête:
```
Authorization: Bearer <access_token>
```

Exemple complet:
```
GET /api/users/me/
Host: localhost:8000
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```
