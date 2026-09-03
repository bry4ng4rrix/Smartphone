# API Endpoints

Base URL: `/api/users/`

## Authentication

### POST `/api/users/login/`
- **Description**: Custom login with JWT token
- **Auth**: None required
- **Body**: 
  ```json
  {
    "username": "string",
    "password": "string"
  }
  ```
- **Response**: JWT access and refresh tokens

### POST `/api/users/refresh/`
- **Description**: Refresh JWT access token
- **Auth**: None required
- **Body**:
  ```json
  {
    "refresh": "string"
  }
  ```
- **Response**: New access token

## User Management

### POST `/api/users/register/`
- **Description**: Register a new user
- **Auth**: None required
- **Body**: Depends on RegisterSerializer fields
- **Response**: Success message

### GET `/api/users/me/`
- **Description**: Get current user profile
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Response**: User profile data

### PUT `/api/users/approve/<user_id>/`
- **Description**: Approve a user account
- **Auth**: Required (admin or magasin role only)
- **Permissions**: IsAuthenticated, role in ["admin", "magasin"]
- **Response**: Success message

### PUT `/api/users/role/<user_id>/`
- **Description**: Modify user role (admin only)
- **Auth**: Required (admin role only)
- **Permissions**: IsAuthenticated, IsAdmin
- **Body**:
  ```json
  {
    "role": "admin|magasin|employer"
  }
  ```
- **Response**: Success message with old and new role

### GET `/api/users/magasins/users/`
- **Description**: List all users (managers and employers) grouped by magasin.
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Response**:
  ```json
  [
    {
      "magasin_id": 1,
      "shop_name": "Shop Name",
      "manager": {
        "id": 2,
        "full_name": "Manager Full Name",
        "email": "manager@example.com",
        "is_confirmed": true,
        "role": "magasin"
      },
      "employers": [
        {
          "id": 3,
          "full_name": "Employee Full Name",
          "email": "employee@example.com",
          "is_confirmed": true,
          "position": "Seller Position",
          "role": "employer"
        }
      ]
    }
  ]
  ```

## Products

### GET `/api/users/products/`
- **Description**: List products
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Filtering**: 
  - Admin: All products
  - Magasin: Products from their magasin
  - Employer: Products from their magasin
- **Response**: List of products

### POST `/api/users/products/`
- **Description**: Create a new product
- **Auth**: Required
- **Permissions**: IsAuthenticated, role in ["admin", "magasin"]
- **Body**: Product data (magasin field optional for admin)
- **Response**: Created product

### GET `/api/users/products/<id>/`
- **Description**: Get product details
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Response**: Product details

### PUT `/api/users/products/<id>/`
- **Description**: Update a product (full update)
- **Auth**: Required
- **Permissions**: IsAuthenticated, admin only
- **Body**: Complete product data
- **Response**: Updated product

### PATCH `/api/users/products/<id>/`
- **Description**: Partially update a product
- **Auth**: Required
- **Permissions**: IsAuthenticated, admin only
- **Body**: Partial product data
- **Response**: Updated product

### DELETE `/api/users/products/<id>/`
- **Description**: Delete a product
- **Auth**: Required
- **Permissions**: IsAuthenticated, admin only
- **Response**: Success message

## Sales & Analytics

### GET `/api/users/sales/totals/`
- **Description**: Calculate and retrieve the total sum of `unit_price` and `shell_price` across all products
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Response**:
  ```json
  {
    "total_unit_price": "decimal",
    "total_shell_price": "decimal"
  }
  ```

### GET `/api/users/sales/profit/`
- **Description**: Calculate real-time profit using the formula: `total_revenue (sum of sale_price * quantity) - total_cost (sum of product unit_price * quantity)`
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Response**:
  ```json
  {
    "profit": "decimal"
  }
  ```

### GET `/api/users/sales/`
- **Description**: List sales transactions (includes magasin ID, shop name, seller user ID, and seller name)
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Filtering**:
  - Admin: All sales
  - Magasin: Sales related to their magasin's products
  - Employer: Sales related to their magasin's products
- **Response**: List of sales with structured store/employer data.

### POST `/api/users/sales/`
- **Description**: Record a new sale transaction (automatically decrements the corresponding product's stock, and automatically associates the seller's user profile and the product's magasin profile)
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Body**:
  ```json
  {
    "product": "int (ID)",
    "quantity": "int",
    "sale_price": "decimal"
  }
  ```
- **Response**:
  ```json
  {
    "id": 1,
    "product": 1,
    "magasin": 1,
    "shop_name": "My Shop",
    "seller": 2,
    "seller_name": "Employer Name",
    "quantity": 5,
    "sale_price": "10.00",
    "total_price": "50.00",
    "sold_at": "timestamp"
  }
  ```

### GET `/api/users/dashboard/`
- **Description**: Unified dashboard endpoint that automatically identifies the authenticated user's role and returns customized statistics, KPIs, and data lists according to security/confidentiality clearance levels.
- **Auth**: Required
- **Permissions**: IsAuthenticated
- **Response Schemas by Role**:
  - **Admin**: Returns overall sales, profit, full stock value, list of stores, list of employees, top-performing products/shops, soon-expiring list.
  - **Magasin**: Returns store-specific sales counts, total stock value, store profits, top sellers, and low stock warnings (sensitive company-wide variables are hidden).
  - **Employer**: Returns employee-specific daily count, total amount sold, quantity sold, and their recent sales list.

### GET `/api/users/endpoints/`
- **Description**: Publicly accessible API discovery endpoint that lists all available endpoints, their HTTP methods, whether they require authentication, their target role clearances, and human-friendly descriptions.
- **Auth**: None required
- **Response**: List of all API routes and their specifications.

## Admin

### GET `/admin/`
- **Description**: Django admin panel
- **Auth**: Admin user required
