# Quick Start - Snippets et Références Rapides

## 1. Configuration Minimale

### .env.local
```env
NEXT_PUBLIC_DJANGO_API_URL=http://localhost:8000/api/users
```

---

## 2. Appels API Courants

### Login
```typescript
const response = await fetch('http://localhost:8000/api/users/login/', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    username: 'user@example.com',
    password: 'password123'
  })
});

const { access, refresh } = await response.json();
localStorage.setItem('access_token', access);
localStorage.setItem('refresh_token', refresh);
```

### GET Protégé
```typescript
const token = localStorage.getItem('access_token');
const response = await fetch('http://localhost:8000/api/users/products/', {
  headers: {
    'Authorization': `Bearer ${token}`
  }
});

const products = await response.json();
```

### POST Vente
```typescript
const token = localStorage.getItem('access_token');
const response = await fetch('http://localhost:8000/api/users/sales/', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`
  },
  body: JSON.stringify({
    product: 1,
    quantity: 5,
    sale_price: 100.00
  })
});

const sale = await response.json();
```

### Dashboard
```typescript
const token = localStorage.getItem('access_token');
const response = await fetch('http://localhost:8000/api/users/dashboard/', {
  headers: {
    'Authorization': `Bearer ${token}`
  }
});

const dashboard = await response.json();
// dashboard.role = 'admin' | 'magasin' | 'employer'
// dashboard.kpis = { ... }
// dashboard.lists = { ... }
```

---

## 3. Logique d'Authentification Minimale

### Hook Simple
```typescript
'use client';

import { useEffect, useState } from 'react';

export function useAuth() {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem('access_token');
    if (!token) {
      setLoading(false);
      return;
    }

    fetch('http://localhost:8000/api/users/me/', {
      headers: { 'Authorization': `Bearer ${token}` }
    })
      .then(r => r.json())
      .then(data => {
        setUser(data);
        if (!data.is_confirmed) {
          window.location.href = '/pending-approval';
        }
      })
      .catch(() => setUser(null))
      .finally(() => setLoading(false));
  }, []);

  return { user, loading };
}
```

### Login Simple
```typescript
async function handleLogin(email: string, password: string) {
  const res = await fetch('http://localhost:8000/api/users/login/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: email, password })
  });

  if (!res.ok) {
    throw new Error('Login failed');
  }

  const { access, refresh } = await res.json();
  localStorage.setItem('access_token', access);
  localStorage.setItem('refresh_token', refresh);

  // Rediriger
  window.location.href = '/dashboard';
}
```

### Register Simple
```typescript
async function handleRegister(data: {
  full_name: string;
  email: string;
  password: string;
  role: 'admin' | 'magasin' | 'employer';
  company_name?: string;
}) {
  const res = await fetch('http://localhost:8000/api/users/register/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  });

  if (!res.ok) {
    throw new Error('Registration failed');
  }

  // Rediriger vers pending approval
  window.location.href = '/pending-approval';
}
```

---

## 4. Gestion des Permissions

### Vérifier le Rôle
```typescript
const { user } = useAuth();

if (!user) {
  return <div>Not authenticated</div>;
}

if (user.role === 'admin') {
  return <AdminDashboard />;
}

if (user.role === 'magasin') {
  return <MagasinDashboard />;
}

return <EmployerDashboard />;
```

### Vérifier l'Approbation
```typescript
const { user, loading } = useAuth();

if (loading) {
  return <div>Loading...</div>;
}

if (!user?.is_confirmed) {
  return (
    <div>
      Your account is pending approval. 
      Please contact your administrator.
    </div>
  );
}

return <YourComponent />;
```

### Guard Admin
```typescript
'use client';

import { useAuth } from '@/hooks/useAuth';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

export function AdminGuard({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && user?.role !== 'admin') {
      router.push('/dashboard');
    }
  }, [user, loading, router]);

  if (loading || user?.role !== 'admin') {
    return <div>Loading...</div>;
  }

  return <>{children}</>;
}
```

---

## 5. Affichage des Données

### Produits (Masquer unit_price pour non-admin)
```typescript
function ProductList() {
  const { user } = useAuth();
  const [products, setProducts] = useState([]);

  useEffect(() => {
    const token = localStorage.getItem('access_token');
    fetch('http://localhost:8000/api/users/products/', {
      headers: { 'Authorization': `Bearer ${token}` }
    })
      .then(r => r.json())
      .then(setProducts);
  }, []);

  return (
    <table>
      <thead>
        <tr>
          <th>Name</th>
          <th>Category</th>
          <th>Stock</th>
          {user?.role === 'admin' && <th>Unit Price</th>}
          <th>Sale Price</th>
        </tr>
      </thead>
      <tbody>
        {products.map(p => (
          <tr key={p.id}>
            <td>{p.name}</td>
            <td>{p.category}</td>
            <td>{p.initial_quantity}</td>
            {user?.role === 'admin' && <td>{p.unit_price}</td>}
            <td>{p.shell_price}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

### Dashboard
```typescript
function Dashboard() {
  const { user } = useAuth();
  const [dashboard, setDashboard] = useState(null);

  useEffect(() => {
    const token = localStorage.getItem('access_token');
    fetch('http://localhost:8000/api/users/dashboard/', {
      headers: { 'Authorization': `Bearer ${token}` }
    })
      .then(r => r.json())
      .then(setDashboard);
  }, []);

  if (!dashboard) return <div>Loading...</div>;

  if (dashboard.role === 'admin') {
    return (
      <div>
        <h1>Admin Dashboard</h1>
        <p>Total Revenue: ${dashboard.kpis.total_revenue}</p>
        <p>Total Profit: ${dashboard.kpis.total_profit}</p>
        <p>Stock Value: ${dashboard.kpis.total_stock_value}</p>
        {/* Afficher les listes */}
        <ul>
          {dashboard.lists.top_products.map(p => (
            <li key={p.product__name}>
              {p.product__name} - {p.qty_sold} sold
            </li>
          ))}
        </ul>
      </div>
    );
  }

  if (dashboard.role === 'magasin') {
    return (
      <div>
        <h1>Store Dashboard</h1>
        <p>Today's Sales: {dashboard.kpis.sales_today}</p>
        <p>Today's Profit: ${dashboard.kpis.profit_today}</p>
      </div>
    );
  }

  return (
    <div>
      <h1>My Sales</h1>
      <p>Today: {dashboard.kpis.my_sales_today}</p>
      <p>Total Sold: ${dashboard.kpis.total_amount_sold}</p>
    </div>
  );
}
```

---

## 6. Gérer les Tokens Expirés

### Renouvellement Automatique
```typescript
async function makeRequest(endpoint: string, options: any = {}) {
  let token = localStorage.getItem('access_token');

  let response = await fetch(
    `http://localhost:8000/api/users${endpoint}`,
    {
      ...options,
      headers: {
        ...options.headers,
        'Authorization': `Bearer ${token}`
      }
    }
  );

  // Si 401, essayer de renouveler
  if (response.status === 401) {
    const refresh = localStorage.getItem('refresh_token');
    if (!refresh) {
      window.location.href = '/login';
      return;
    }

    const refreshRes = await fetch('http://localhost:8000/api/users/refresh/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh })
    });

    if (!refreshRes.ok) {
      window.location.href = '/login';
      return;
    }

    const { access } = await refreshRes.json();
    localStorage.setItem('access_token', access);

    // Réessayer
    response = await fetch(
      `http://localhost:8000/api/users${endpoint}`,
      {
        ...options,
        headers: {
          ...options.headers,
          'Authorization': `Bearer ${access}`
        }
      }
    );
  }

  return response;
}

// Utilisation
const res = await makeRequest('/products/');
const products = await res.json();
```

---

## 7. Gestion des Erreurs Courantes

### 400 Bad Request
```typescript
if (response.status === 400) {
  const error = await response.json();
  console.log('Validation error:', error);
  // error.email, error.quantity, etc.
}
```

### 401 Unauthorized
```typescript
if (response.status === 401) {
  // Token expiré ou invalide
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
  window.location.href = '/login';
}
```

### 403 Forbidden
```typescript
if (response.status === 403) {
  // Pas de permission pour cette action
  alert('You do not have permission to perform this action');
}
```

### 404 Not Found
```typescript
if (response.status === 404) {
  // Ressource non trouvée
  alert('Resource not found');
}
```

---

## 8. Exemples de Mutations

### Créer un Produit
```typescript
async function createProduct(data: {
  name: string;
  reference: string;
  brand: string;
  category: string;
  description: string;
  unit_price: number;
  shell_price: number;
  initial_quantity: number;
  alert_threshold: number;
  expiry_date: string;
}) {
  const token = localStorage.getItem('access_token');
  const res = await fetch('http://localhost:8000/api/users/products/', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify(data)
  });

  if (!res.ok) {
    const error = await res.json();
    throw error;
  }

  return res.json();
}
```

### Enregistrer une Vente
```typescript
async function recordSale(data: {
  product: number;
  quantity: number;
  sale_price: number;
}) {
  const token = localStorage.getItem('access_token');
  const res = await fetch('http://localhost:8000/api/users/sales/', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify(data)
  });

  if (!res.ok) {
    const error = await res.json();
    if (error.quantity) {
      throw new Error(`Insufficient stock. Available: ${error.quantity}`);
    }
    throw error;
  }

  return res.json();
}
```

### Approuver un Utilisateur
```typescript
async function approveUser(userId: number) {
  const token = localStorage.getItem('access_token');
  const res = await fetch(
    `http://localhost:8000/api/users/approve/${userId}/`,
    {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      }
    }
  );

  if (!res.ok) {
    throw new Error('Failed to approve user');
  }

  return res.json();
}
```

---

## 9. Formulaires Réactuels

### Login Form
```typescript
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { toast } from 'sonner';

export function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);

    try {
      const res = await fetch('http://localhost:8000/api/users/login/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: email, password })
      });

      if (!res.ok) {
        toast.error('Invalid credentials');
        return;
      }

      const { access, refresh } = await res.json();
      localStorage.setItem('access_token', access);
      localStorage.setItem('refresh_token', refresh);

      toast.success('Login successful!');
      router.push('/dashboard');
    } catch (error) {
      toast.error('Login failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={onSubmit}>
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="Email"
        required
      />
      <input
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder="Password"
        required
      />
      <button disabled={loading}>
        {loading ? 'Logging in...' : 'Login'}
      </button>
    </form>
  );
}
```

### Register Form
```typescript
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { toast } from 'sonner';

export function RegisterForm() {
  const router = useRouter();
  const [role, setRole] = useState<'admin' | 'magasin' | 'employer'>('employer');
  const [data, setData] = useState({
    full_name: '',
    email: '',
    password: '',
    company_name: '',
    shop_name: '',
    position: '',
    admin_email: ''
  });
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);

    try {
      const res = await fetch('http://localhost:8000/api/users/register/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...data,
          role,
          ...(role === 'employer' && { admin_email: data.admin_email }),
          ...(role === 'magasin' && { admin_email: data.admin_email })
        })
      });

      if (!res.ok) {
        const error = await res.json();
        toast.error(error.detail || 'Registration failed');
        return;
      }

      toast.success('Registration successful! Awaiting approval...');
      router.push('/pending-approval');
    } catch (error) {
      toast.error('Registration failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={onSubmit}>
      <select value={role} onChange={(e) => setRole(e.target.value as any)}>
        <option value="admin">Admin</option>
        <option value="magasin">Store Manager</option>
        <option value="employer">Employee</option>
      </select>

      <input
        type="text"
        value={data.full_name}
        onChange={(e) => setData({ ...data, full_name: e.target.value })}
        placeholder="Full Name"
        required
      />

      <input
        type="email"
        value={data.email}
        onChange={(e) => setData({ ...data, email: e.target.value })}
        placeholder="Email"
        required
      />

      <input
        type="password"
        value={data.password}
        onChange={(e) => setData({ ...data, password: e.target.value })}
        placeholder="Password"
        required
      />

      {role === 'admin' && (
        <input
          type="text"
          value={data.company_name}
          onChange={(e) => setData({ ...data, company_name: e.target.value })}
          placeholder="Company Name"
        />
      )}

      {role === 'magasin' && (
        <>
          <input
            type="text"
            value={data.shop_name}
            onChange={(e) => setData({ ...data, shop_name: e.target.value })}
            placeholder="Shop Name"
          />
          <input
            type="email"
            value={data.admin_email}
            onChange={(e) => setData({ ...data, admin_email: e.target.value })}
            placeholder="Admin Email"
          />
        </>
      )}

      {role === 'employer' && (
        <>
          <input
            type="text"
            value={data.position}
            onChange={(e) => setData({ ...data, position: e.target.value })}
            placeholder="Position"
          />
          <input
            type="email"
            value={data.admin_email}
            onChange={(e) => setData({ ...data, admin_email: e.target.value })}
            placeholder="Admin Email"
          />
        </>
      )}

      <button disabled={loading}>
        {loading ? 'Registering...' : 'Register'}
      </button>
    </form>
  );
}
```

---

## 10. Pendant l'Approbation

### Page /pending-approval
```typescript
'use client';

import { useAuth } from '@/hooks/useAuth';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

export default function PendingApprovalPage() {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && user?.is_confirmed) {
      router.push('/dashboard');
    }
  }, [user, loading, router]);

  if (loading) {
    return <div>Loading...</div>;
  }

  if (!user) {
    return <div>Not authenticated</div>;
  }

  return (
    <div style={{ padding: '2rem', textAlign: 'center' }}>
      <h1>Account Pending Approval</h1>
      <p>Your account is awaiting approval from your administrator.</p>
      <p>Role: {user.role}</p>
      <p>Email: {user.email}</p>
      <p>Please check back later or contact your administrator.</p>
      <button onClick={() => window.location.href = '/logout'}>
        Logout
      </button>
    </div>
  );
}
```

---

## ⚡ Points-clés à Retenir

1. **Token dans chaque requête protégée**
   ```typescript
   headers: { 'Authorization': `Bearer ${token}` }
   ```

2. **Vérifier `is_confirmed` après login**
   ```typescript
   if (!user.is_confirmed) {
     redirect('/pending-approval');
   }
   ```

3. **Masquer `unit_price` pour non-admin**
   ```typescript
   {user.role === 'admin' && <td>{product.unit_price}</td>}
   ```

4. **Renouveler le token si expiré (401)**
   ```typescript
   if (response.status === 401) {
     // POST /refresh/ et réessayer
   }
   ```

5. **Gérer les erreurs de validation (400)**
   ```typescript
   if (response.status === 400) {
     const errors = await response.json();
     // error.quantity, error.email, etc.
   }
   ```

---

**Besoin d'aide?** Consultez:
- `ajouter.md` - Guide complet
- `django-backend-integration.md` - Documentation technique
- `IMPLEMENTATION_SUMMARY.md` - Vue d'ensemble

