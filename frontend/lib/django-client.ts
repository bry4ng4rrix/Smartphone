// Django Backend API Client with JWT Authentication
// Handles all API calls to Django backend with automatic token management

const API_BASE_URL = process.env.NEXT_PUBLIC_DJANGO_API_URL ?? 'http://127.0.0.1:8000/api'

interface AuthTokens {
  access: string
  refresh: string
}

interface AuthResponse {
  access: string
  refresh: string
  device_status?: 'new' | 'known' | null
  user: {
    id: number
    email: string
    username: string
    full_name: string
    role: 'admin' | 'magasin' | 'employer' | 'platform_admin'
    is_confirmed: boolean
    store_id?: number
    magasin_id?: number
    shop_name?: string
    company_name?: string
    position?: string
  }
}

interface ApiErrorResponse {
  detail?: string
  [key: string]: any
}

// Adapte une ProductReference (catalogue §8 Smartreadme.md) vers l'ancienne
// forme "Product" plate (name/brand/category/initial_quantity/variants...)
// attendue par les pages non prioritaires (alertes, rapports, dashboard,
// chat, scanner, transferts) — évite de les récrire une à une alors qu'elles
// n'ont besoin que d'une lecture simple, pas du détail Catégorie/Type.
function mapReferenceToProduct(ref: any) {
  const variants = Array.isArray(ref.variants) ? ref.variants : []
  const totalStock = variants.reduce((s: number, v: any) => s + (v.stock_actuel || 0), 0)
  const minAlert = variants.reduce((min: number, v: any) => Math.min(min, v.seuil_alerte ?? 1), Infinity)
  return {
    id: ref.id,
    name: ref.reference_name,
    reference: ref.reference_name,
    brand: ref.brand_name,
    category: ref.category_name,
    description: [ref.type_name, ref.brand_name].filter(Boolean).join(' — '),
    unit_price: null,
    purchase_price: null,
    shell_price: ref.prix_vente,
    initial_quantity: totalStock,
    alert_threshold: Number.isFinite(minAlert) ? minAlert : 1,
    expiry_date: null,
    image1: null,
    image2: null,
    image3: null,
    qr_code: null,
    magasin: ref.magasin,
    variants: variants.map((v: any) => ({ id: v.id, size: '', color: v.couleur, quantity: v.stock_actuel })),
  }
}

class DjangoAPIClient {
  private tokens: AuthTokens | null = null
  private isRefreshing = false
  private refreshQueue: Array<(token: string) => void> = []

  constructor() {
    this.loadTokensFromStorage()
  }

  // ==================== Token Management ====================
  private loadTokensFromStorage(): void {
    if (typeof window === 'undefined') return
    const stored = localStorage.getItem('django_tokens')
    if (stored) {
      try {
        this.tokens = JSON.parse(stored)
      } catch (e) {
        console.error('[v0] Failed to parse stored tokens')
      }
    }
  }

  private saveTokensToStorage(tokens: AuthTokens): void {
    if (typeof window === 'undefined') return
    this.tokens = tokens
    localStorage.setItem('django_tokens', JSON.stringify(tokens))
  }

  private clearTokensFromStorage(): void {
    if (typeof window === 'undefined') return
    this.tokens = null
    localStorage.removeItem('django_tokens')
  }

  private async refreshAccessToken(): Promise<string | null> {
    if (!this.tokens?.refresh) return null

    if (this.isRefreshing) {
      return new Promise((resolve) => {
        this.refreshQueue.push(resolve)
      })
    }

    this.isRefreshing = true

    try {
      const response = await fetch(`${API_BASE_URL}/users/refresh/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh: this.tokens.refresh }),
      })

      if (!response.ok) {
        let blocked = false
        try {
          const err = await response.json()
          if (err.code === 'subscription_inactive') blocked = true
        } catch {}
        this.clearTokensFromStorage()
        window.location.href = blocked ? '/abonnement-expire' : '/login'
        return null
      }

      const data = await response.json()
      this.tokens = { ...this.tokens!, access: data.access }
      this.saveTokensToStorage(this.tokens)

      this.refreshQueue.forEach((callback) => callback(data.access))
      this.refreshQueue = []

      return data.access
    } catch (error) {
      console.error('[v0] Token refresh failed:', error)
      this.clearTokensFromStorage()
      return null
    } finally {
      this.isRefreshing = false
    }
  }

  private getAuthHeaders(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      ...(this.tokens?.access && { Authorization: `Bearer ${this.tokens.access}` }),
    }
  }

  // ==================== Core HTTP Methods ====================
  private async request<T>(
    endpoint: string,
    options: RequestInit = {},
  ): Promise<T> {
    const normalizedEndpoint = endpoint.startsWith('http')
      ? endpoint
      : `${API_BASE_URL.replace(/\/$/, '')}/${endpoint.replace(/^\//, '')}`

    const headers = this.getAuthHeaders()
    const requestHeaders = new Headers(headers)
    const extraHeaders = new Headers(options.headers ?? {})
    extraHeaders.forEach((value, key) => requestHeaders.set(key, value))

    let response = await fetch(normalizedEndpoint, {
      ...options,
      headers: requestHeaders,
    })

    if (response.status === 401) {
      const newToken = await this.refreshAccessToken()
      if (!newToken) {
        const error = await response.json().catch(() => ({})) as ApiErrorResponse
        throw new Error(error.detail || 'Authentication failed')
      }

      const refreshedHeaders = new Headers(this.getAuthHeaders())
      const refreshedExtra = new Headers(options.headers ?? {})
      refreshedExtra.forEach((value, key) => refreshedHeaders.set(key, value))

      response = await fetch(normalizedEndpoint, {
        ...options,
        headers: refreshedHeaders,
      })
    }

    if (!response.ok) {
      const contentType = response.headers.get('content-type') || ''
      let errorMessage = `API Error: ${response.status}`
      if (contentType.includes('application/json')) {
        const error = (await response.json()) as ApiErrorResponse
        errorMessage = error.detail
          || (Array.isArray(error.non_field_errors) ? error.non_field_errors[0] : null)
          || Object.entries(error).map(([k, v]) => `${k}: ${Array.isArray(v) ? v[0] : v}`).join(' | ')
          || errorMessage
      } else {
        const text = await response.text()
        if (text) errorMessage = text.slice(0, 200)
      }
      throw new Error(errorMessage)
    }

    // 204/205 and empty bodies are valid success responses (e.g. DELETE)
    if (response.status === 204 || response.status === 205) {
      return undefined as T
    }

    const contentType = response.headers.get('content-type') || ''
    const text = await response.text()
    if (!text) {
      return undefined as T
    }

    if (contentType.includes('application/json')) {
      return JSON.parse(text) as T
    }

    return undefined as T
  }

  async get<T>(endpoint: string): Promise<T> {
    return this.request<T>(endpoint, { method: 'GET' })
  }

  async post<T>(endpoint: string, data?: any): Promise<T> {
    return this.request<T>(endpoint, {
      method: 'POST',
      body: data ? JSON.stringify(data) : undefined,
    })
  }

  async put<T>(endpoint: string, data?: any): Promise<T> {
    return this.request<T>(endpoint, {
      method: 'PUT',
      body: data ? JSON.stringify(data) : undefined,
    })
  }

  async patch<T>(endpoint: string, data?: any): Promise<T> {
    return this.request<T>(endpoint, {
      method: 'PATCH',
      body: data ? JSON.stringify(data) : undefined,
    })
  }

  async delete<T>(endpoint: string, data?: any): Promise<T> {
    return this.request<T>(endpoint, {
      method: 'DELETE',
      body: data ? JSON.stringify(data) : undefined,
    })
  }

  // ==================== FormData Methods (for file uploads) ====================
  private async requestFormData<T>(
    endpoint: string,
    method: string,
    data: FormData,
  ): Promise<T> {
    const url = `${API_BASE_URL}${endpoint}`
    const headers: Record<string, string> = {}
    if (this.tokens?.access) {
      headers['Authorization'] = `Bearer ${this.tokens.access}`
    }

    let response = await fetch(url, { method, headers, body: data })

    if (response.status === 401) {
      const newToken = await this.refreshAccessToken()
      if (!newToken) throw new Error('Authentication failed')
      headers['Authorization'] = `Bearer ${newToken}`
      response = await fetch(url, { method, headers, body: data })
    }

    if (!response.ok) {
      let errorMsg = `API Error: ${response.status}`
      try {
        const error = await response.json()
        const messages = Object.entries(error)
          .map(([k, v]) => `${k}: ${Array.isArray(v) ? v.join(', ') : v}`)
        errorMsg = messages.join(' | ') || errorMsg
      } catch {}
      throw new Error(errorMsg)
    }

    return response.json()
  }

  async postFormData<T>(endpoint: string, data: FormData): Promise<T> {
    return this.requestFormData<T>(endpoint, 'POST', data)
  }

  async patchFormData<T>(endpoint: string, data: FormData): Promise<T> {
    return this.requestFormData<T>(endpoint, 'PATCH', data)
  }

  // ==================== Blob Methods (for file downloads) ====================
  private async requestBlob(endpoint: string, method: string = 'GET'): Promise<{ blob: Blob; filename: string }> {
    const url = `${API_BASE_URL}${endpoint}`
    const headers: Record<string, string> = {}
    if (this.tokens?.access) {
      headers['Authorization'] = `Bearer ${this.tokens.access}`
    }

    let response = await fetch(url, { method, headers })

    if (response.status === 401) {
      const newToken = await this.refreshAccessToken()
      if (!newToken) throw new Error('Authentication failed')
      headers['Authorization'] = `Bearer ${newToken}`
      response = await fetch(url, { method, headers })
    }

    if (!response.ok) {
      let errorMsg = `API Error: ${response.status}`
      try {
        const error = await response.json()
        errorMsg = error.detail || errorMsg
      } catch {}
      throw new Error(errorMsg)
    }

    const disposition = response.headers.get('content-disposition') || ''
    const match = disposition.match(/filename="?([^"]+)"?/)
    const filename = match ? match[1] : 'backup.zip'
    const blob = await response.blob()
    return { blob, filename }
  }

  // ==================== Authentication Service ====================
  auth = {
    register: async (
      email: string,
      username: string,
      password: string,
      role: string,
      extraData?: {
        full_name?: string
        company_name?: string
        shop_name?: string
        admin_email?: string
        position?: string
      }
    ) => {
      let backendRole = role
      if (role === 'store_manager') backendRole = 'magasin'
      if (role === 'employee') backendRole = 'employer'

      return this.post<any>('/users/register/', {
        email,
        username,
        password,
        role: backendRole,
        full_name: extraData?.full_name || username,
        ...extraData,
      })
    },

    login: async (email: string, password: string) => {
      const { getOrCreateDeviceId, getBrowserLocation } = await import('./device')
      const location = await getBrowserLocation()
      const response = await this.post<{ access: string; refresh: string; device_status?: 'new' | 'known' | null }>('/users/login/', {
        email: email,
        password,
        device_id: getOrCreateDeviceId(),
        ...(location ? { latitude: location.latitude, longitude: location.longitude } : {}),
      })
      this.saveTokensToStorage({ access: response.access, refresh: response.refresh })
      const user = await this.auth.getCurrentUser()

      return {
        access: response.access,
        refresh: response.refresh,
        user,
        device_status: response.device_status,
      } as unknown as AuthResponse
    },

    logout: async () => {
      try {
        await this.post('/users/logout-event/')
      } catch (error) {
        console.warn('[v0] Logout event recording failed:', error)
      }

      const refreshToken = this.tokens?.refresh || (() => {
        if (typeof window === 'undefined') return null
        try {
          const stored = localStorage.getItem('django_tokens')
          return stored ? JSON.parse(stored).refresh : null
        } catch {
          return null
        }
      })()

      if (refreshToken) {
        try {
          await fetch(`${API_BASE_URL}/users/refresh/`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ refresh: refreshToken }),
          })
        } catch (error) {
          console.warn('[v0] Logout refresh request failed:', error)
        }
      }

      if (typeof window !== 'undefined') {
        // Preserve the device_id across logout: it must stay stable for this
        // browser so the next login is recognized as the same registered
        // device instead of being counted as a brand new one.
        const deviceId = localStorage.getItem('device_id')
        localStorage.clear()
        if (deviceId) localStorage.setItem('device_id', deviceId)
      }

      this.tokens = null
    },

    getCurrentUser: async () => {
      const response = await this.get<any>('/users/me/')
      let mappedRole: 'admin' | 'store_manager' | 'employee' | 'platform_admin' = 'employee'
      if (response.role === 'admin') mappedRole = 'admin'
      else if (response.role === 'magasin') mappedRole = 'store_manager'
      else if (response.role === 'employer') mappedRole = 'employee'
      else if (response.role === 'platform_admin') mappedRole = 'platform_admin'

      return {
        id: response.id,
        email: response.email,
        username: response.username,
        full_name: response.full_name || '',
        first_name: response.full_name?.split(' ')[0] || '',
        last_name: response.full_name?.split(' ').slice(1).join(' ') || '',
        phone: response.phone,
        role: mappedRole,
        raw_role: response.role,
        is_approved: response.is_confirmed,
        is_confirmed: response.is_confirmed,
        company_name: response.company_name,
        shop_name: response.shop_name,
        magasin_id: response.magasin_id,
        position: response.position,
      } as any
    },

    approveUser: async (userId: number) => {
      return this.put(`/users/approve/${userId}/`)
    },

    rejectUser: async (userId: number) => {
      return this.post(`/users/reject/${userId}/`)
    },

    getPendingUsers: async () => {
      return this.get<any[]>('/users/pending/')
    },

    // Forgot password (no auth): admin accounts are routed to Label
    // Technology for approval, magasin/employer accounts to their admin.
    forgotPasswordRequest: async (email: string) => {
      return this.post<{ queue: 'label' | 'admin'; message: string }>('/users/public/forgot-password/', { email })
    },

    forgotPasswordStatus: async (email: string) => {
      return this.get<{ status: 'none' | 'pending' | 'approved' | 'rejected' }>(
        `/users/public/forgot-password/status/?email=${encodeURIComponent(email)}`
      )
    },

    forgotPasswordConfirm: async (email: string, newPassword: string) => {
      return this.post<{ message: string }>('/users/public/forgot-password/confirm/', {
        email,
        new_password: newPassword,
      })
    },
  }

  // ==================== Employee Password Reset Requests (admin side) ====================
  passwordResetRequests = {
    list: async (statusFilter?: string) => {
      const query = statusFilter ? `?status=${statusFilter}` : ''
      return this.get<any[]>(`/users/password-reset-requests/${query}`)
    },
    resolve: async (requestId: number, action: 'approve' | 'reject') => {
      return this.patch<any>(`/users/password-reset-requests/${requestId}/`, { action })
    },
  }

  // ==================== Catalog Service (§8 Smartreadme.md) ====================
  // Catégorie → Sous-type → Marque → Référence → Variante (couleur).
  catalog = {
    categories: {
      list: async (magasinId?: number) => {
        const q = magasinId ? `?magasin_id=${magasinId}` : ''
        return this.get<any[]>(`/catalog/categories/${q}`)
      },
      create: async (data: { nom: string; ordre?: number; magasin_id?: number }) => {
        return this.post<any>('/catalog/categories/', data)
      },
      update: async (id: number, data: { nom?: string; ordre?: number }) => {
        return this.patch<any>(`/catalog/categories/${id}/`, data)
      },
      delete: async (id: number) => {
        return this.delete(`/catalog/categories/${id}/`)
      },
    },
    types: {
      list: async (categoryId?: number) => {
        const q = categoryId ? `?category=${categoryId}` : ''
        return this.get<any[]>(`/catalog/types/${q}`)
      },
      create: async (data: { category: number; nom: string }) => {
        return this.post<any>('/catalog/types/', data)
      },
      update: async (id: number, data: { nom?: string; category?: number }) => {
        return this.patch<any>(`/catalog/types/${id}/`, data)
      },
      delete: async (id: number) => {
        return this.delete(`/catalog/types/${id}/`)
      },
    },
    brands: {
      list: async (magasinId?: number) => {
        const q = magasinId ? `?magasin_id=${magasinId}` : ''
        return this.get<any[]>(`/catalog/brands/${q}`)
      },
      create: async (data: { nom: string; magasin_id?: number }) => {
        return this.post<any>('/catalog/brands/', data)
      },
      update: async (id: number, data: { nom: string }) => {
        return this.patch<any>(`/catalog/brands/${id}/`, data)
      },
      delete: async (id: number) => {
        return this.delete(`/catalog/brands/${id}/`)
      },
    },
    colors: {
      list: async (magasinId?: number) => {
        const q = magasinId ? `?magasin_id=${magasinId}` : ''
        return this.get<any[]>(`/catalog/colors/${q}`)
      },
      create: async (data: { nom: string; magasin_id?: number }) => {
        return this.post<any>('/catalog/colors/', data)
      },
      update: async (id: number, data: { nom: string }) => {
        return this.patch<any>(`/catalog/colors/${id}/`, data)
      },
      delete: async (id: number) => {
        return this.delete(`/catalog/colors/${id}/`)
      },
    },
    references: {
      list: async (filters?: { type?: number; brand?: number }) => {
        const params = new URLSearchParams()
        if (filters?.type) params.append('type', String(filters.type))
        if (filters?.brand) params.append('brand', String(filters.brand))
        const query = params.toString() ? `?${params.toString()}` : ''
        return this.get<any[]>(`/catalog/references/${query}`)
      },
      autocomplete: async (query: string, filters?: { type?: number; brand?: number; category?: number }) => {
        const params = new URLSearchParams({ q: query })
        if (filters?.type) params.append('type', String(filters.type))
        if (filters?.brand) params.append('brand', String(filters.brand))
        if (filters?.category) params.append('category', String(filters.category))
        return this.get<any[]>(`/catalog/references/autocomplete/?${params.toString()}`)
      },
      getById: async (id: number) => this.get<any>(`/catalog/references/${id}/`),
      create: async (data: { type: number; brand: number; reference_name: string; prix_achat?: number | string; prix_vente: number | string; actif?: boolean }) => {
        return this.post<any>('/catalog/references/', data)
      },
      update: async (id: number, data: any) => {
        return this.put<any>(`/catalog/references/${id}/`, data)
      },
      delete: async (id: number) => {
        return this.delete(`/catalog/references/${id}/`)
      },
    },
    variants: {
      list: async (referenceId?: number) => {
        const q = referenceId ? `?reference=${referenceId}` : ''
        return this.get<any[]>(`/catalog/variants/${q}`)
      },
      create: async (data: { product_reference: number; couleur: string; stock_actuel?: number; seuil_alerte?: number }) => {
        return this.post<any>('/catalog/variants/', data)
      },
      delete: async (id: number) => {
        return this.delete(`/catalog/variants/${id}/`)
      },
      adjust: async (id: number, data: { type: 'ENTREE' | 'SORTIE'; quantite: number; note?: string }) => {
        return this.post<any>(`/catalog/variants/${id}/adjust/`, data)
      },
    },
  }

  // ==================== Orders Service (module Commandes, §5-§7 Smartreadme.md) ====================
  orders = {
    list: async (filters?: { statut?: string; date_debut?: string; date_fin?: string; magasin_id?: number }) => {
      const params = new URLSearchParams()
      if (filters?.statut) params.append('statut', filters.statut)
      if (filters?.date_debut) params.append('date_debut', filters.date_debut)
      if (filters?.date_fin) params.append('date_fin', filters.date_fin)
      if (filters?.magasin_id) params.append('magasin_id', String(filters.magasin_id))
      const query = params.toString() ? `?${params.toString()}` : ''
      return this.get<any[]>(`/orders/${query}`)
    },
    getById: async (id: number) => {
      return this.get<any>(`/orders/${id}/`)
    },
    create: async (data: {
      client_nom: string
      telephone: string
      livraison_zone: 'ZONE1' | 'ZONE2' | 'ZONE3' | 'RECUPERATION'
      items: { product_variant: number; quantite: number }[]
      note?: string
      adresse_livraison?: string
      date_commande?: string
      magasin_id?: number
    }) => {
      return this.post<any>('/orders/', data)
    },
    changeStatus: async (id: number, statut: string, note?: string) => {
      return this.post<any>(`/orders/${id}/status/`, { statut, note })
    },
    dashboard: async (params?: { date_from?: string; date_to?: string; magasin_id?: number }) => {
      const q = new URLSearchParams()
      if (params?.date_from) q.append('date_from', params.date_from)
      if (params?.date_to) q.append('date_to', params.date_to)
      if (params?.magasin_id) q.append('magasin_id', String(params.magasin_id))
      const suffix = q.toString() ? `?${q.toString()}` : ''
      return this.get<any>(`/orders/dashboard/${suffix}`)
    },
  }

  // ==================== Movements Service (historique stock, §7.4/§10) ====================
  movements = {
    list: async (filters?: { variant_id?: number }) => {
      const query = filters?.variant_id ? `?variant=${filters.variant_id}` : ''
      const rows = await this.get<any[]>(`/catalog/movements/${query}`)
      const originLabel: Record<string, string> = {
        LIVRE: 'Commande livrée',
        FOURNISSEUR: 'Réception fournisseur',
        AJUSTEMENT: 'Ajustement manuel',
      }
      return rows.map((m) => ({
        id: m.id,
        product: m.product_variant,
        product_name: m.reference_name + (m.couleur && m.couleur !== 'Standard' ? ` (${m.couleur})` : ''),
        product_reference: m.reference_name,
        variant_label: m.couleur,
        changed_by_name: m.user_name,
        change: m.type === 'SORTIE' ? -m.quantite : m.quantite,
        movement_type: originLabel[m.origine] || m.origine,
        note: m.note,
        created_at: m.timestamp,
      }))
    },
  }

  // ==================== Products Service (compat — voir mapReferenceToProduct) ====================
  // Conservé pour les pages en lecture seule (alertes, rapports, dashboard,
  // chat, scanner, transferts) : le formulaire produit lui-même utilise
  // directement `catalog.*` (hiérarchie Catégorie→Type→Marque→Référence).
  products = {
    list: async (filters?: { store_id?: number; magasin_id?: number; category?: string }) => {
      const magasinId = filters?.magasin_id ?? filters?.store_id
      const refs = await this.catalog.references.list()
      return refs
        .filter((r: any) => !magasinId || Number(r.magasin) === Number(magasinId))
        .filter((r: any) => !filters?.category || r.category_name === filters.category)
        .map(mapReferenceToProduct)
    },

    getById: async (id: number) => {
      const ref = await this.catalog.references.getById(id)
      return mapReferenceToProduct(ref)
    },

    delete: async (id: number) => {
      return this.catalog.references.delete(id)
    },

    search: async (query: string) => {
      const refs = await this.catalog.references.list()
      const q = query.toLowerCase()
      return refs
        .filter((r: any) => r.reference_name.toLowerCase().includes(q) || (r.brand_name || '').toLowerCase().includes(q))
        .map(mapReferenceToProduct)
    },
  }

  // ==================== Sales Service (compat — dérivé des Commandes Livrées) ====================
  // Le module Ventes/Ticket (caisse rapide) est retiré : le seul flux de
  // vente est désormais la Commande à 6 statuts (§5 Smartreadme.md), qui
  // couvre aussi la vente sur place via la zone "Récupération". Conservé
  // pour les pages d'analytics en lecture seule (rapports, dashboard).
  sales = {
    list: async (filters?: { store_id?: number }) => {
      const orders = await this.orders.list(filters?.store_id ? { magasin_id: filters.store_id } : undefined)
      const rows: any[] = []
      for (const order of orders) {
        if (order.statut_courant !== 'LIVRE') continue
        for (const item of order.items || []) {
          rows.push({
            id: `${order.id}-${item.id}`,
            product: item.product_variant,
            variant: item.product_variant,
            product_name: item.reference_name + (item.couleur && item.couleur !== 'Standard' ? ` (${item.couleur})` : ''),
            quantity: item.quantite,
            sale_price: item.prix_unitaire,
            total_price: item.prix_unitaire != null ? Number(item.prix_unitaire) * item.quantite : null,
            customer_name: order.client_nom,
            is_paid: true,
            total_profit: 0,
            sold_at: order.updated_at || order.created_at,
          })
        }
      }
      return rows
    },
  }

  // ==================== Notifications Service ====================
  notifications = {
    list: async () => this.get<any[]>('/users/notifications/'),
    markRead: async (id: number, isRead: boolean) => this.patch<any>(`/users/notifications/${id}/`, { is_read: isRead }),
    markAllRead: async () => this.post<any>('/users/notifications/mark-all-read/'),
    delete: async (id: number) => this.delete<void>(`/users/notifications/${id}/`),
    deleteAll: async () => this.post<void>('/users/notifications/delete-all/'),
    bulkRead: async (ids: number[]) => this.post<any>('/users/notifications/bulk-read/', { ids }),
    bulkDelete: async (ids: number[]) => this.post<void>('/users/notifications/bulk-delete/', { ids }),
  }

  // ==================== Users Service ====================
  users = {
    list: async (role?: string) => {
      return this.get<any[]>('/users/magasins/users/')
    },

    getById: async (id: number) => {
      return this.get<any>(`/users/me/`)
    },

    update: async (id: number, data: any) => {
      return this.put<any>(`/users/role/${id}/`, data)
    },

    delete: async (id: number, password: string) => {
      return this.delete(`/users/delete/${id}/`, { password })
    },

    updateProfile: async (data: any) => {
      return this.patch<any>('/users/me/', data)
    },

    getEmployeesByStore: async (storeId: number) => {
      const list = await this.get<any[]>('/users/magasins/users/')
      const found = list.find((m: any) => m.magasin_id === storeId)
      return found ? found.employers : []
    },
  }

  // ==================== Dashboard Service ====================
  dashboard = {
    getStats: async (storeId?: number) => {
      const res = await this.get<any>('/users/dashboard/')
      return res.kpis
    },

    getTopProducts: async (storeId?: number, limit: number = 5) => {
      const res = await this.get<any>('/users/dashboard/')
      return res.lists?.top_products || []
    },

    getRevenueChart: async (storeId?: number, period: string = 'monthly') => {
      const res = await this.get<any>('/users/dashboard/')
      return res.lists?.recent_sales || []
    },

    getSalesAnalytics: async (storeId?: number) => {
      return this.get<any>('/users/dashboard/')
    },
  }

  // ==================== Transfers Service (transfert de stock entre magasins) ====================
  transfers = {
    transfer: async (
      sourceId: number,
      destinationId: number,
      items: { variant_id: number; quantity: number }[]
    ) => {
      return this.post<any>('/users/transfer/products/', {
        source_magasin_id: sourceId,
        destination_magasin_id: destinationId,
        items,
      })
    },

    // Résumé par magasin (stock, bénéfice estimé, ventes de la semaine) — admin uniquement.
    getProfitByMagasins: async () => {
      const res = await this.get<{ magasins: any[] }>('/users/magasins/overview/')
      return { profit_by_magasins: res.magasins }
    },
  }

  // ==================== Caisse Service ====================
  caisse = {
    listSessions: async (params?: { magasinId?: number; status?: 'open' | 'closed' }) => {
      const qs = new URLSearchParams()
      if (params?.magasinId) qs.set('magasin_id', String(params.magasinId))
      if (params?.status) qs.set('status', params.status)
      const suffix = qs.toString() ? `?${qs}` : ''
      return this.get<any[]>(`/users/caisse/sessions/${suffix}`)
    },

    // 204 (no open session) is normalized to null — see request()'s handling
    // of empty/204 bodies, which returns `undefined` here.
    current: async (magasinId?: number) => {
      const suffix = magasinId ? `?magasin_id=${magasinId}` : ''
      const data = await this.get<any>(`/users/caisse/sessions/current/${suffix}`)
      return data ?? null
    },

    open: async (data: {
      magasin_id?: number
      opening_balance: number | string
      opening_note?: string
      opened_at?: string
    }) => {
      return this.post<any>('/users/caisse/sessions/open/', data)
    },

    close: async (
      sessionId: number,
      data: { closing_balance: number | string; closing_note?: string; closed_at?: string },
    ) => {
      return this.post<any>(`/users/caisse/sessions/${sessionId}/close/`, data)
    },

    listMovements: async (params?: { sessionId?: number; magasinId?: number }) => {
      const qs = new URLSearchParams()
      if (params?.sessionId) qs.set('session_id', String(params.sessionId))
      if (params?.magasinId) qs.set('magasin_id', String(params.magasinId))
      const suffix = qs.toString() ? `?${qs}` : ''
      return this.get<any[]>(`/users/caisse/movements/${suffix}`)
    },

    addMovement: async (data: {
      session?: number
      movement_type: 'in' | 'out'
      amount: number | string
      reason: string
    }) => {
      return this.post<any>('/users/caisse/movements/', data)
    },
  }

  // ==================== Suppliers Service (module Commandes Fournisseur, §7.6) ====================
  suppliers = {
    list: async (magasinId?: number) => {
      const q = magasinId ? `?magasin_id=${magasinId}` : ''
      return this.get<any[]>(`/suppliers/orders/${q}`)
    },

    getById: async (id: number) => {
      return this.get<any>(`/suppliers/orders/${id}/`)
    },

    create: async (data: {
      description?: string
      prix_fournisseur: number | string
      fret_import: number | string
      douane: number | string
      meta_ads: number | string
      lines: { product_variant: number; quantite: number }[]
      magasin_id?: number
    }) => {
      return this.post<any>('/suppliers/orders/', data)
    },

    receive: async (id: number) => {
      return this.post<any>(`/suppliers/orders/${id}/receive/`)
    },
  }

  // ==================== Backup Service (admin only) ====================
  backup = {
    export: async () => {
      return this.requestBlob('/users/backup/export/')
    },

    import: async (file: File) => {
      const fd = new FormData()
      fd.append('file', file)
      return this.postFormData<{ detail: string }>('/users/backup/import/', fd)
    },
  }

  // ==================== Chat Service ====================
  chat = {
    users: async () => {
      return this.get<any[]>('/users/chat/users/')
    },
    history: async (params?: { recipient_id?: number; room_name?: string }) => {
      const urlParams = new URLSearchParams()
      if (params?.recipient_id) urlParams.append('recipient_id', params.recipient_id.toString())
      if (params?.room_name) urlParams.append('room_name', params.room_name)
      const query = urlParams.toString() ? `?${urlParams.toString()}` : ''
      return this.get<any[]>(`/users/chat/history/${query}`)
    }
  }

  // ==================== Platform Admin Service (Label Technology) ====================
  platformAdmin = {
    listCompanies: async () => {
      return this.get<any[]>('/users/platform-admin/companies/')
    },
    createCompany: async (data: {
      company_name: string
      full_name: string
      email: string
      password: string
      phone?: string
      status?: string
    }) => {
      return this.post<any>('/users/platform-admin/companies/', data)
    },
    updateCompany: async (adminProfileId: number, data: { company_name?: string; admin_full_name?: string; admin_phone?: string }) => {
      return this.patch<any>(`/users/platform-admin/companies/${adminProfileId}/`, data)
    },
    deleteCompany: async (adminProfileId: number) => {
      return this.requestBlob(`/users/platform-admin/companies/${adminProfileId}/`, 'DELETE')
    },
    updateStatus: async (adminProfileId: number, status: string) => {
      return this.patch<any>(`/users/platform-admin/companies/${adminProfileId}/status/`, { status })
    },
    activateAll: async () => {
      return this.post<{ activated: number }>('/users/platform-admin/companies/activate-all/')
    },
    backupCompany: async (adminProfileId: number) => {
      return this.requestBlob(`/users/platform-admin/companies/${adminProfileId}/backup/`)
    },
    getDevices: async (adminProfileId: number) => {
      return this.get<{ devices: any[]; count: number; limit: number }>(`/users/platform-admin/companies/${adminProfileId}/devices/`)
    },
    deleteDevice: async (adminProfileId: number, deviceId: number) => {
      return this.delete<void>(`/users/platform-admin/companies/${adminProfileId}/devices/?device_id=${deviceId}`)
    },
    assignOffer: async (adminProfileId: number, offerId: number | null) => {
      return this.patch<any>(`/users/platform-admin/companies/${adminProfileId}/offer/`, { offer_id: offerId })
    },
    getMonitoring: async () => {
      return this.get<any>('/users/platform-admin/monitoring/')
    },
    listRequests: async (statusFilter?: string) => {
      const query = statusFilter ? `?status=${statusFilter}` : ''
      return this.get<any[]>(`/users/platform-admin/requests/${query}`)
    },
    resolveRequest: async (requestId: number, action: 'approve' | 'reject') => {
      return this.patch<any>(`/users/platform-admin/requests/${requestId}/`, { action })
    },
    getExpiringSoon: async () => {
      return this.get<any[]>('/users/platform-admin/expiring-soon/')
    },
    // Subscription offers catalog
    listOffers: async () => {
      return this.get<any[]>('/users/platform-admin/offers/')
    },
    createOffer: async (data: { name: string; price: number; max_devices: number; duration_months: number; is_active?: boolean }) => {
      return this.post<any>('/users/platform-admin/offers/', data)
    },
    updateOffer: async (offerId: number, data: Partial<{ name: string; price: number; max_devices: number; duration_months: number; is_active: boolean }>) => {
      return this.patch<any>(`/users/platform-admin/offers/${offerId}/`, data)
    },
    deleteOffer: async (offerId: number) => {
      return this.delete<void>(`/users/platform-admin/offers/${offerId}/`)
    },
  }

  // ==================== My Company Service (tenant side) ====================
  myCompany = {
    getDevices: async () => {
      return this.get<{ devices: any[]; count: number; limit: number }>('/users/my-company/devices/')
    },
    getSubscription: async () => {
      return this.get<any>('/users/my-company/subscription/')
    },
    listRequests: async () => {
      return this.get<any[]>('/users/my-company/requests/')
    },
    createRequest: async (data: { request_type: 'device_deletion' | 'activation'; device_id?: number; login_event_id?: number; note?: string }) => {
      return this.post<any>('/users/my-company/requests/', data)
    },
  }

  // ==================== Public Service (no auth — subscription-expired page) ====================
  public = {
    listOffers: async () => {
      return this.get<any[]>('/users/public/offers/')
    },
    verifyAccount: async (data: { email: string; password: string }) => {
      return this.post<{
        email: string
        full_name: string
        role: string
        is_admin: boolean
        company_name: string
      }>('/users/public/verify-account/', data)
    },
    createPaymentRequest: async (data: {
      email: string
      password: string
      offer_id: number
      payment_method: 'mvola' | 'paypal' | 'visa' | 'mastercard'
      payment_reference: string
      note?: string
    }) => {
      return this.post<any>('/users/public/payment-request/', data)
    },
  }

  // ==================== Token Status ====================
  isAuthenticated(): boolean {
    return !!this.tokens?.access
  }

  getAccessToken(): string | null {
    return this.tokens?.access || null
  }
}

export const djangoClient = new DjangoAPIClient()
export type { AuthResponse, AuthTokens }

