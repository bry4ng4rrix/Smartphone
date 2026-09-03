import { NextResponse, type NextRequest } from 'next/server';

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Public routes that don't need authentication
  const publicRoutes = ['/login', '/register', '/'];

  if (publicRoutes.includes(pathname)) {
    return NextResponse.next();
  }

  // Check for Django JWT token in localStorage (client-side will handle redirect)
  // Since we can't access localStorage in server-side, we allow all routes
  // and let client-side hooks handle authentication checks
  
  return NextResponse.next();
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.svg).*)',
  ],
};
