let csrf;
export class ApiError extends Error { constructor(message, status) { super(message); this.status = status } }
export async function api(path, method = 'GET', body, retry = true) {
  if (method !== 'GET' && !csrf) csrf = (await api('/auth/csrf')).token;
  const response = await fetch(`/api${path}`, { method, credentials: 'include', headers: { 'Content-Type': 'application/json', ...(method !== 'GET' ? { 'X-XSRF-TOKEN': csrf } : {}) }, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
  const data = await response.json().catch(() => ({ message: 'The server returned an unexpected response.' }));
  if (!response.ok) {
    if (response.status === 403 && data.message?.includes('CSRF') && retry) { csrf = null; return api(path, method, body, false) }
    throw new ApiError(data.message || 'The request could not be completed.', response.status);
  }
  return data;
}
export const label = value => String(value ?? '').replaceAll('_', ' ').replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
export const dateTime = value => value ? new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—';
export function download(data, name) { const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })); const a = document.createElement('a'); a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000) }
export const has = (user, book, target) => user?.role === 'ADMIN' || user?.scopes?.some(s => s.active && s.book === book && (!target || s.targetId === target));
