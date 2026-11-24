// SCL375 · φωτογραφία στο «Στήθηκε». Δεν δέχεται τίποτα χωρίς έγκυρο σύνδεσμο φαρμακείου: ο έλεγχος γίνεται στη βάση (scl375_photo_*).
// v2: γράφει και το μέγεθος· τα Κεντρικά ανοίγουν φωτογραφία με το κλειδί τους (hq_get).
// Ο χώρος αρχείων «scl375-setup» είναι κλειστός· μόνο αυτό το πρόγραμμα γράφει, σβήνει και δίνει προσωρινό σύνδεσμο προβολής (2 λεπτά).
const URL_ = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "scl375-setup";
const MAX = 614400;
const ORIGINS = ["https://vprodro-spec.github.io"];
const sh = { apikey: KEY, Authorization: `Bearer ${KEY}` };

function cors(req: Request) {
  const o = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const out = (req: Request, status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });

class Fail extends Error {
  constructor(public status: number, message: string, public code?: string) { super(message); }
}
async function rpc(fn: string, args: Record<string, unknown>) {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, { method: "POST", headers: { ...sh, "Content-Type": "application/json" }, body: JSON.stringify(args) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Fail(j?.code === "P0002" ? 404 : j?.code === "42501" ? 403 : 400, j?.message ?? "Σφάλμα", j?.code);
  return j;
}
const obj = (path: string) => `${URL_}/storage/v1/object/${BUCKET}/${path.split("/").map(encodeURIComponent).join("/")}`;
async function remove(path?: string | null) {
  if (path) await fetch(obj(path), { method: "DELETE", headers: sh }).catch(() => null);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return out(req, 405, { message: "Μόνο POST" });
  try {
    const b = await req.json().catch(() => null);
    const link = typeof b?.link === "string" ? b.link : "";
    const pos = typeof b?.position_id === "string" ? b.position_id : "";
    const hq = b?.action === "hq_get" && typeof b?.key === "string" && b.key;
    if ((!link && !hq) || !pos) throw new Fail(400, "Λείπουν στοιχεία.");

    if (b.action === "put") {
      if (typeof b.image !== "string" || b.image.length > MAX * 1.4) throw new Fail(413, "Η φωτογραφία είναι πολύ μεγάλη.");
      let bytes: Uint8Array;
      try { bytes = Uint8Array.from(atob(b.image), (c) => c.charCodeAt(0)); } catch { throw new Fail(400, "Μη έγκυρη φωτογραφία."); }
      if (bytes.length > MAX) throw new Fail(413, "Η φωτογραφία είναι πολύ μεγάλη.");
      if (bytes.length < 1000 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) throw new Fail(400, "Μη έγκυρη φωτογραφία.");
      const { path } = await rpc("scl375_photo_begin", { p_link: link, p_position_id: pos });
      const up = await fetch(obj(path), { method: "POST", headers: { ...sh, "Content-Type": "image/jpeg", "x-upsert": "false" }, body: bytes });
      if (!up.ok) throw new Fail(502, "Δεν αποθηκεύτηκε η φωτογραφία. Δοκίμασε ξανά.");
      let res;
      try { res = await rpc("scl375_photo_commit", { p_link: link, p_position_id: pos, p_path: path, p_bytes: bytes.length }); }
      catch (e) { await remove(path); throw e; }
      if (res?.old && res.old !== path) await remove(res.old);
      return out(req, 200, { photo: true, bytes: bytes.length });
    }
    if (b.action === "del") {
      const res = await rpc("scl375_photo_commit", { p_link: link, p_position_id: pos, p_path: null });
      await remove(res?.old);
      return out(req, 200, { photo: false });
    }
    if (b.action === "get" || hq) {
      const { path } = hq
        ? await rpc("scl375_photo_path_hq", { p_key: b.key, p_pharmacy_id: b.pharmacy_id, p_year: b.year, p_month: b.month, p_position_id: pos })
        : await rpc("scl375_photo_path", { p_link: link, p_year: b.year, p_month: b.month, p_position_id: pos });
      if (!path) throw new Fail(404, "Δεν υπάρχει φωτογραφία.");
      const s = await fetch(`${URL_}/storage/v1/object/sign/${BUCKET}/${path.split("/").map(encodeURIComponent).join("/")}`, { method: "POST", headers: { ...sh, "Content-Type": "application/json" }, body: JSON.stringify({ expiresIn: 120 }) });
      const j = await s.json().catch(() => null);
      const signed = j?.signedURL ?? j?.signedUrl;
      if (!s.ok || !signed) throw new Fail(502, "Δεν άνοιξε η φωτογραφία.");
      return out(req, 200, { url: `${URL_}/storage/v1${signed}` });
    }
    throw new Fail(400, "Άγνωστη ενέργεια.");
  } catch (e) {
    if (e instanceof Fail) return out(req, e.status, { message: e.message, code: e.code });
    return out(req, 500, { message: "Κάτι πήγε στραβά. Δοκίμασε ξανά." });
  }
});
