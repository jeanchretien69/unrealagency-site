// Private file storage for the members area (Cloudflare R2 bucket "unreal-files", binding FILES).
// GET  /api/files/<key>  -> admin only (Supabase session token in Authorization header)
// PUT  /api/files/<key>  -> admin, or the one-time import token (x-import-token)
const SB_URL = 'https://ljhpdqttcxwgufcejfor.supabase.co';
const SB_KEY = 'sb_publishable_Nu7S4SnvuTFRg1ODn4VVrA_hCH5X1wY';

async function rpc(name, body, token) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: SB_KEY, Authorization: `Bearer ${token || SB_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  });
  if (!r.ok) return false;
  return (await r.json()) === true;
}

async function isAdmin(request) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return false;
  return rpc('is_admin', {}, token);
}

function keyFrom(params) {
  const p = params.path;
  const key = Array.isArray(p) ? p.join('/') : (p || '');
  if (!key || key.includes('..') || key.length > 300) return null;
  return key;
}

export async function onRequestGet({ request, env, params }) {
  const key = keyFrom(params);
  if (!key) return new Response('bad key', { status: 400 });
  if (!(await isAdmin(request))) return new Response('forbidden', { status: 403 });
  const obj = await env.FILES.get(key);
  if (!obj) return new Response('not found', { status: 404 });
  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set('Cache-Control', 'private, max-age=3600');
  return new Response(obj.body, { headers });
}

export async function onRequestPut({ request, env, params }) {
  const key = keyFrom(params);
  if (!key) return new Response('bad key', { status: 400 });
  const tok = request.headers.get('x-import-token');
  const ok = tok ? await rpc('check_import_token', { tok }) : await isAdmin(request);
  if (!ok) return new Response('forbidden', { status: 403 });
  await env.FILES.put(key, request.body, {
    httpMetadata: { contentType: request.headers.get('Content-Type') || 'application/octet-stream' },
  });
  return new Response('ok');
}
