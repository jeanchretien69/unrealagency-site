// Panic button: GET/POST /api/panic?k=<panic token>
// Locks the members area, blocks all R2 files and signs every device out.
// Unlock only with the secret unlock code on unrealagency.ai/members.
const SB_URL = 'https://ljhpdqttcxwgufcejfor.supabase.co';
const SB_KEY = 'sb_publishable_Nu7S4SnvuTFRg1ODn4VVrA_hCH5X1wY';

async function run(request) {
  const url = new URL(request.url);
  let k = url.searchParams.get('k') || request.headers.get('x-panic-token') || '';
  if (!k && request.method === 'POST') { try { k = (await request.json()).k || ''; } catch (e) {} }
  const r = await fetch(`${SB_URL}/rest/v1/rpc/panic`, {
    method: 'POST',
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ tok: k }),
  });
  const res = r.ok ? await r.json() : 'error';
  const ok = res === 'locked';
  const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>${ok ? 'Locked' : 'Denied'}</title>
<body style="margin:0;height:100vh;display:grid;place-items:center;background:#120a0f;color:#fbeef4;font:600 22px -apple-system,system-ui,sans-serif;text-align:center">
<div>${ok ? '🔒<br>Everything is locked.<br><small style="font-weight:400;font-size:15px;opacity:.7">All devices signed out. Files blocked.</small>' : '⛔️ Denied'}</div></body>`;
  const wantsText = (request.headers.get('accept') || '').includes('text/plain') || url.searchParams.has('text');
  return new Response(wantsText ? (ok ? 'LOCKED' : 'DENIED') : html, {
    status: ok ? 200 : 403,
    headers: { 'Content-Type': wantsText ? 'text/plain' : 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}
export const onRequestGet = ({ request }) => run(request);
export const onRequestPost = ({ request }) => run(request);
