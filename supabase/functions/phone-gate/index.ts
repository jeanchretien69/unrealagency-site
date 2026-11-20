import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Phone control gate: the phone reader asks "is this pass still good?" (pass sent in the x-pass header).
// 200 = yes. Anything else = no. Checks: signature, one phone only, not expired, and the person still has access today.
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const HOST = "phone.unrealagency.ai";
const H = { "Cache-Control": "no-store" };
const no = () => new Response("no", { status: 401, headers: H });
const b64u = (b: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const same = (a: string, b: string) => { if (a.length !== b.length) return false; let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i); return d === 0; };

Deno.serve(async (req: Request) => {
  const host = (new URL(req.url).searchParams.get("host") || "").toLowerCase();
  const pass = req.headers.get("x-pass") || "";
  const p = pass.split("~");
  if (p.length !== 4 || host !== HOST) return no();
  const [uid, end, phone, sig] = p;
  if (phone !== host || !(Number(end) > Date.now())) return no();
  const secret = Deno.env.get("PHONE_SECRET") || "";
  if (secret.length < 24) return no();
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const want = b64u(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${uid}~${end}~${phone}`)));
  if (!same(want, sig)) return no();
  // access can be taken away any time: check the person today
  const { data: me } = await admin.from("profiles").select("role,approved,perms").eq("id", uid).maybeSingle();
  if (!me || me.approved === false || !(me.role === "admin" || (me.perms || []).includes("phone"))) return no();
  return new Response("ok", { status: 200, headers: H });
});
