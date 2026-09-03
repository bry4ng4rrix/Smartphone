// TypeScript Types for Django Backend Integration

export type UserRole = 'admin' | 'store_manager' | 'employee'

export interface User {
  id: number
  email: string
  username: string
  first_name: string
  last_name: string
  role: UserRole
  is_approved: boolean
  store_id?: number
  created_at: string
}

export interface AuthState {
  user: User | null
  isAuthenticated: boolean
  isLoading: boolean
  error: string | null
}

export interface Product {
  id: number
  name: string
  description: string
  sku: string
  category: string
  quantity: number
  unit_price: number
  unit_cost: number
  store_id: number
  supplier_id?: number
  created_at: string
  updated_at: string
}

export interface Sale {
  id: number
  product_id: number
  quantity: number
  unit_price: number
  total_price: number
  employee_id: number
  store_id: number
  created_at: string
  notes?: string
}

export interface Store {
  id: number
  name: string
  address: string
  city: string
  country: string
  phone: string
  email: string
  manager_id: number
  created_at: string
}

export interface Supplier {
  id: number
  name: string
  contact_person: string
  email: string
  phone: string
  address: string
  city: string
  country: string
  created_at: string
}

export interface DashboardStats {
  total_revenue: number
  total_sales: number
  total_products: number
  total_stores: number
  pending_approvals: number
  monthly_growth: number
}

export interface RevenueSummary {
  today: number
  this_week: number
  this_month: number
  all_time: number
}

export interface TopProduct {
  id: number
  name: string
  quantity_sold: number
  revenue: number
}

export interface RevenueData {
  date: string
  revenue: number
}

export interface SalesAnalytics {
  total_sales: number
  average_sale_value: number
  top_products: TopProduct[]
  sales_by_employee: Record<string, number>
}
