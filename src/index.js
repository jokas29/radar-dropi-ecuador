const AUTH_URL = 'https://kzwzputkwcpojevffjrm.supabase.co/functions/v1/radar-dropi-ec-7f3c?action=proxyauth';
const DROP_BASE = 'https://api.dropi.ec';

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store'
    }
  });
}

function allowed(path, method) {
  if (method === 'POST' && path === '/api/login') return true;
  if (method === 'GET' && /^\/api\/products\/productlist\/v1\/show\/\?id=\d+$/.test(path)) return true;
  return false;
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/') {
      return json({ ok: true, service: 'Radar Dropi proxy', mode: 'ticket-auth' });
    }

    if (request.method !== 'POST' || url.pathname !== '/proxy') {
      return json({ error: 'Not found' }, 404);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'Invalid JSON' }, 400);
    }

    const ticket = String(body?.ticket || '');
    const path = String(body?.path || '');
    const method = String(body?.method || '').toUpperCase();
    const bearer = String(body?.bearer || '');

    if (!ticket || !allowed(path, method)) {
      return json({ error: 'Denied' }, 403);
    }

    const auth = await fetch(AUTH_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ticket, path, method })
    });

    if (!auth.ok) {
      return json({ error: 'Ticket rejected' }, 401);
    }

    const headers = new Headers({
      accept: 'application/json',
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140 Safari/537.36'
    });

    if (method === 'POST') {
      headers.set('content-type', 'application/json');
      headers.set('origin', 'https://app.dropi.ec');
      headers.set('referer', 'https://app.dropi.ec/login');
    }

    if (bearer) {
      headers.set('authorization', `Bearer ${bearer}`);
      headers.set('origin', 'https://app.dropi.ec');
      headers.set('referer', 'https://app.dropi.ec/');
    }

    const upstream = await fetch(`${DROP_BASE}${path}`, {
      method,
      headers,
      body: method === 'POST' ? JSON.stringify(body?.payload || {}) : undefined,
      redirect: 'follow'
    });

    const text = await upstream.text();

    return new Response(text, {
      status: upstream.status,
      headers: {
        'content-type': upstream.headers.get('content-type') || 'application/json; charset=utf-8',
        'cache-control': 'no-store'
      }
    });
  }
};
