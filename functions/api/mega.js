// Mega: Gael's private file storage (R2 bucket "unreal-files", prefix mega/).
// GET  /api/mega            -> list files (admin, Bearer token)
// POST /api/mega {key}      -> 15-min download link (admin)
// GET  /api/mega?dl=<id>    -> stream the file for a valid link (Range ok; &inline for preview)
const SB_URL = 'https://ljhpdqttcxwgufcejfor.supabase.co';
const SB_KEY = 'sb_publishable_Nu7S4SnvuTFRg1ODn4VVrA_hCH5X1wY';
async function isAdmin(request) {
  const a = request.headers.get('Authorization') || '';
  const t = a.startsWith('Bearer ') ? a.slice(7) : '';
  if (!t) return false;
  const r = await fetch(`${SB_URL}/rest/v1/rpc/is_admin`, { method: 'POST', headers: { apikey: SB_KEY, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json' }, body: '{}' });
  return r.ok && (await r.json()) === true;
}
export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const dl = url.searchParams.get('dl');
  if (dl) {
    if (!/^[a-f0-9]{32}$/.test(dl)) return new Response('bad link', { status: 400 });
    const t = await env.FILES.get('tickets/' + dl);
    if (!t) return new Response('link expired', { status: 403 });
    const { key, exp } = await t.json();
    if (Date.now() > exp) return new Response('link expired', { status: 403 });
    const range = request.headers.get('Range');
    const m = range && /^bytes=(\d+)-(\d*)$/.exec(range);
    const opts = m ? { range: m[2] ? { offset: +m[1], length: +m[2] - +m[1] + 1 } : { offset: +m[1] } } : {};
    const obj = await env.FILES.get(key, opts);
    if (!obj) return new Response('not found', { status: 404 });
    const h = new Headers(); obj.writeHttpMetadata(h);
    const name = key.replace(/^mega\/\d+-/, '');
    h.set('Content-Disposition', `${url.searchParams.has('inline') ? 'inline' : 'attachment'}; filename*=UTF-8''${encodeURIComponent(name)}`);
    h.set('Accept-Ranges', 'bytes'); h.set('Cache-Control', 'private, no-store');
    if (m && obj.range) {
      const off = obj.range.offset || 0, len = obj.range.length ?? (obj.size - off);
      h.set('Content-Range', `bytes ${off}-${off + len - 1}/${obj.size}`); h.set('Content-Length', String(len));
      return new Response(obj.body, { status: 206, headers: h });
    }
    h.set('Content-Length', String(obj.size));
    return new Response(obj.body, { headers: h });
  }
  if (!(await isAdmin(request))) return new Response('forbidden', { status: 403 });
  const out = []; let cursor;
  do { const l = await env.FILES.list({ prefix: 'mega/', cursor, limit: 1000 }); for (const o of l.objects) out.push({ key: o.key, size: o.size, uploaded: o.uploaded }); cursor = l.truncated ? l.cursor : null; } while (cursor);
  out.sort((a, b) => new Date(b.uploaded) - new Date(a.uploaded));
  return Response.json(out);
}
export async function onRequestPost({ request, env }) {
  if (!(await isAdmin(request))) return new Response('forbidden', { status: 403 });
  const { key } = await request.json();
  if (!key || !key.startsWith('mega/') || key.includes('..')) return new Response('bad key', { status: 400 });
  const id = [...crypto.getRandomValues(new Uint8Array(16))].map(b => b.toString(16).padStart(2, '0')).join('');
  await env.FILES.put('tickets/' + id, JSON.stringify({ key, exp: Date.now() + 15 * 60 * 1000 }));
  return Response.json({ url: '/api/mega?dl=' + id });
}
