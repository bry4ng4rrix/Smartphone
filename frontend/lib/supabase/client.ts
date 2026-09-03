// Django API client for browser-side requests
// Replaces Supabase client with Django backend integration

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000/api';

export function createClient() {
  return {
    // Auth methods
    auth: {
      signInWithPassword: async ({ email, password }: { email: string; password: string }) => {
        const response = await fetch(`${API_BASE_URL}/users/login/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ username: email, password }),
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.detail || 'Login failed');
        return { data: { user: { email }, session: { access_token: data.access, refresh_token: data.refresh } } };
      },
      signUp: async ({ email, password, full_name, role }: any) => {
        const response = await fetch(`${API_BASE_URL}/users/register/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password, full_name, role }),
        });
        if (!response.ok) throw new Error('Registration failed');
        return { data: { user: { email } } };
      },
      signOut: async () => {
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        return { error: null };
      },
      getUser: async () => {
        const token = localStorage.getItem('access_token');
        if (!token) return { data: { user: null } };
        const response = await fetch(`${API_BASE_URL}/users/me/`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        const data = await response.json();
        return { data: { user: response.ok ? data : null } };
      },
    },
    // Generic API methods
    from: (table: string) => ({
      select: () => ({
        data: [],
        error: null,
      }),
    }),
  };
}
