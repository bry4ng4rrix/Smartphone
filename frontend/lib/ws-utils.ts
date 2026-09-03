export function buildWebSocketUrl(path: string, token: string): string {
  const wsProto = typeof window !== 'undefined' && window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const apiURL = process.env.NEXT_PUBLIC_DJANGO_API_URL || 'http://localhost:8000/api';
  const host = apiURL.replace(/^https?:\/\//, '').split('/')[0];
  return `${wsProto}//${host}${path}?token=${token}`;
}
