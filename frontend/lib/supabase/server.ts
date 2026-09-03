// Django API client for server-side requests
// Replaces Supabase server client with Django backend integration

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000/api';

export async function createClient() {
  // Server-side client for Django API
  return {
    auth: {
      getUser: async () => {
        // Server-side auth check would need cookie handling
        return { data: { user: null } };
      },
    },
    from: (table: string) => ({
      select: () => ({
        data: [],
        error: null,
      }),
    }),
  };
}
