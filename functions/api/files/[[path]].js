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

async function canWrite(request) {
  const tok = request.headers.get('x-import-token');
  return tok ? rpc('check_import_token', { tok }) : isAdmin(request);
}

export async function onRequestGet({ request, env, params }) {
  const key = keyFrom(params);
  if (!key) return new Response('bad key', { status: 400 });
  if (!(await isAdmin(request))) return new Response('forbidden', { status: 403 });
  const range = request.headers.get('Range');
  let opts = {};
  const m = range && /^bytes=(\d+)-(\d*)$/.exec(range);
  if (m) {
    const offset = +m[1];
    opts.range = m[2] ? { offset, length: +m[2] - offset + 1 } : { offset };
  }
  const obj = await env.FILES.get(key, opts);
  if (!obj) return new Response('not found', { status: 404 });
  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set('Cache-Control', 'private, max-age=3600');
  headers.set('Accept-Ranges', 'bytes');
  if (m && obj.range) {
    const off = obj.range.offset || 0;
    const len = obj.range.length ?? (obj.size - off);
    headers.set('Content-Range', `bytes ${off}-${off + len - 1}/${obj.size}`);
    headers.set('Content-Length', String(len));
    return new Response(obj.body, { status: 206, headers });
  }
  headers.set('Content-Length', String(obj.size));
  return new Response(obj.body, { headers });
}

// HEAD: does the file exist? (import token or admin)
export async function onRequestHead({ request, env, params }) {
  const key = keyFrom(params);
  if (!key) return new Response(null, { status: 400 });
  if (!(await canWrite(request))) return new Response(null, { status: 403 });
  const obj = await env.FILES.head(key);
  if (!obj) return new Response(null, { status: 404 });
  return new Response(null, { headers: { 'Content-Length': String(obj.size) } });
}

export async function onRequestPut({ request, env, params }) {
  const key = keyFrom(params);
  if (!key) return new Response('bad key', { status: 400 });
  if (!(await canWrite(request))) return new Response('forbidden', { status: 403 });
  const url = new URL(request.url);
  const uploadId = url.searchParams.get('mpu');
  if (uploadId) {
    // multipart part upload (for files over 100 MB)
    const part = parseInt(url.searchParams.get('part') || '0', 10);
    if (!(part >= 1 && part <= 10000)) return new Response('bad part', { status: 400 });
    const up = env.FILES.resumeMultipartUpload(key, uploadId);
    const res = await up.uploadPart(part, request.body);
    return Response.json(res);
  }
  await env.FILES.put(key, request.body, {
    httpMetadata: { contentType: request.headers.get('Content-Type') || 'application/octet-stream' },
  });
  return new Response('ok');
}

// POST ?mpu=create  -> {uploadId}; POST ?mpu=<id>&complete (body: [{partNumber,etag}]) ; POST ?mpu=<id>&abort
export async function onRequestPost({ request, env, params }) {
  const key = keyFrom(params);
  if (!key) return new Response('bad key', { status: 400 });
  if (!(await canWrite(request))) return new Response('forbidden', { status: 403 });
  const url = new URL(request.url);
  const mpu = url.searchParams.get('mpu');
  if (mpu === 'create') {
    const up = await env.FILES.createMultipartUpload(key, {
      httpMetadata: { contentType: request.headers.get('Content-Type') || 'application/octet-stream' },
    });
    return Response.json({ uploadId: up.uploadId });
  }
  if (mpu && url.searchParams.has('complete')) {
    const up = env.FILES.resumeMultipartUpload(key, mpu);
    const parts = await request.json();
    const obj = await up.complete(parts);
    return Response.json({ ok: true, size: obj.size });
  }
  if (mpu && url.searchParams.has('abort')) {
    await env.FILES.resumeMultipartUpload(key, mpu).abort();
    return new Response('aborted');
  }
  return new Response('bad request', { status: 400 });
}

// DELETE /api/files/<key>  -> admin only
export async function onRequestDelete({ request, env, params }) {
  const key = keyFrom(params);
  if (!key) return new Response('bad key', { status: 400 });
  if (!(await isAdmin(request))) return new Response('forbidden', { status: 403 });
  await env.FILES.delete(key);
  return new Response('deleted');
}
