import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Phone control: gives a signed 12-hour pass to a signed-in, approved person who has the "phone" box ticked (admin always).
// The pass only works for ONE phone address. Secret: app_secrets.phone_secret.
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
const HOST = "phone.unrealagency.ai";
const b64u = (b: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const tok = (req.headers.get("authorization") || "").replace(/^Bearer /i, "");
  const { data: u } = await admin.auth.getUser(tok);
  if (!u?.user) return json({ error: "Please sign in again" }, 401);
  const { data: me } = await admin.from("profiles").select("role,approved,perms").eq("id", u.user.id).maybeSingle();
  const ok = !!me && me.approved !== false && (me.role === "admin" || (me.perms || []).includes("phone"));
  if (!ok) return json({ error: "no access" }, 403);
  const { data: s } = await admin.from("app_secrets").select("value").eq("key", "phone_secret").maybeSingle();
  if (!s?.value) return json({ error: "not_set_up" }, 500);
  const end = Date.now() + 12 * 3600 * 1000;
  const body = `${u.user.id}~${end}~${HOST}`;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(s.value), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = b64u(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  return json({ url: `https://${HOST}/?vbpass=${body}~${sig}`, host: HOST });
});
