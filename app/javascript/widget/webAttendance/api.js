const API_PATH = '/web-attendance/api';

export class AttendanceError extends Error {
  constructor(status) {
    super(`Attendance request failed (${status})`);
    this.status = status;
  }
}

export function takeInvitation(
  location = window.location,
  history = window.history
) {
  const token = new URLSearchParams(location.hash.slice(1)).get('token');
  if (location.hash)
    history.replaceState(
      history.state,
      '',
      `${location.pathname}${location.search}`
    );
  return token;
}

export function mergeMessages(current, incoming) {
  const messages = new Map(current.map(message => [message.id, message]));
  incoming.forEach(message => messages.set(message.id, message));
  return [...messages.values()].sort((left, right) => left.id - right.id);
}

// Only cookie-authorized media from this attendance API can be rendered.
export function attachmentUrl(value, origin = window.location.origin) {
  if (!value) return '';
  try {
    const url = new URL(value, origin);
    return url.origin === origin &&
      /^\/web-attendance\/api\/attachments\/\d+$/.test(url.pathname)
      ? `${url.pathname}${url.search}`
      : '';
  } catch {
    return '';
  }
}

export async function request(
  path,
  { method = 'GET', body, signal, keepalive = false } = {}
) {
  const controller = keepalive ? null : new AbortController();
  const abort = () => controller?.abort();
  signal?.addEventListener('abort', abort, { once: true });
  if (signal?.aborted) abort();
  const timeout = keepalive
    ? null
    : setTimeout(abort, method === 'POST' ? 120000 : 15000);
  try {
    const headers = { Accept: 'application/json' };
    if (method === 'POST') headers['X-Web-Attendance'] = '1';
    if (body && !(body instanceof FormData))
      headers['Content-Type'] = 'application/json';
    const response = await fetch(`${API_PATH}${path}`, {
      method,
      credentials: 'same-origin',
      cache: 'no-store',
      headers,
      body: body instanceof FormData ? body : body && JSON.stringify(body),
      ...(keepalive ? { keepalive: true } : { signal: controller.signal }),
    });
    if (!response.ok) throw new AttendanceError(response.status);
    const content = await response.text();
    return content ? JSON.parse(content) : null;
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener('abort', abort);
  }
}
