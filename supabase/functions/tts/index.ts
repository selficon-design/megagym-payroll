// Φωνή ElevenLabs για τον Βοηθό AI.
//  action "speak":  κείμενο → ήχος mp3 (για κάθε χρήστη της εφαρμογής)
//  action "voices": οι φωνές του λογαριασμού ElevenLabs (μόνο Γενική Διευθύντρια, για επιλογή)
//  action "status": ποια φωνή είναι ενεργή
// Το κλειδί διαβάζεται ΜΟΝΟ εδώ (service role) από τον πίνακα app_secrets και δεν επιστρέφεται ποτέ.
import { adminClient, cors, identify, json } from "../_shared/common.ts";

const API = "https://api.elevenlabs.io/v1";

async function settings() {
  const db = adminClient();
  const [{ data: key }, { data: vs }] = await Promise.all([
    db.from("app_secrets").select("value").eq("name", "elevenlabs_api_key").maybeSingle(),
    db.from("voice_settings").select("provider,voice_id,voice_name,model,updated_by").eq("id", 1).maybeSingle(),
  ]);
  return { key: key?.value as string | undefined, vs: vs ?? { provider: "browser", voice_id: null, voice_name: null, model: "eleven_multilingual_v2", updated_by: null } as any };
}
// Αυτόματη ρύθμιση: αν το κλειδί μπήκε χειροκίνητα στη βάση και δεν έχει διαλέξει ποτέ κανείς φωνή,
// διαλέγουμε μόνοι μας (Μελίνα → ελληνική φωνή → δική σας φωνή → πρώτη διαθέσιμη) με το γρήγορο Flash v2.5.
// Δεν ξαναγίνεται αν η ΓΔ έχει ήδη επιλέξει ή απενεργοποιήσει φωνή (updated_by συμπληρωμένο).
async function autoSetup(key: string, vs: any) {
  if (vs.provider !== "browser" || vs.voice_id || vs.updated_by) return vs;
  const r = await fetch(`${API}/voices`, { headers: { "xi-api-key": key } });
  if (!r.ok) { console.error("auto-setup voices", r.status); return vs; }
  const list: any[] = (await r.json()).voices ?? [];
  const greek = (v: any) => /greek|ελλην|^el$/i.test([v.labels?.language, v.labels?.accent, v.verified_languages?.map((x: any) => x.language).join(" ")].filter(Boolean).join(" "));
  const pick = list.find((v) => /melina|μελίνα|μελινα/i.test(v.name ?? "")) ?? list.find(greek)
    ?? list.find((v) => v.category && v.category !== "premade") ?? list[0];
  if (!pick) return vs;
  const next = { provider: "elevenlabs", voice_id: pick.voice_id, voice_name: String(pick.name ?? "").slice(0, 120), model: "eleven_flash_v2_5", updated_by: "αυτόματη ρύθμιση" };
  const { data } = await adminClient().from("voice_settings").update({ ...next, updated_at: new Date().toISOString() })
    .eq("id", 1).is("updated_by", null).is("voice_id", null).select("provider,voice_id,voice_name,model,updated_by").maybeSingle();
  return data ?? vs;
}

const elError = (status: number, body: string) =>
  status === 401 ? "Το κλειδί ElevenLabs δεν είναι έγκυρο ή ακυρώθηκε."
  : status === 402 || /quota|credits|character_limit/i.test(body) ? "Εξαντλήθηκαν οι χαρακτήρες του λογαριασμού ElevenLabs για αυτόν τον μήνα."
  : status === 429 ? "Το ElevenLabs δέχεται πολλά αιτήματα αυτή τη στιγμή. Δοκιμάστε σε λίγο."
  : status === 404 ? "Η φωνή δεν βρέθηκε στον λογαριασμό ElevenLabs."
  : `Το ElevenLabs δεν απάντησε (${status}).`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const who = await identify(req);
    if (!who.me) return json({ error: who.error }, who.status);
    const body = await req.json().catch(() => ({}));
    const st = await settings();
    const key = st.key;
    const vs = key ? await autoSetup(key, st.vs) : st.vs;

    if (body.action === "status") return json({ provider: key ? vs.provider : "browser", voice_name: vs.voice_name, model: vs.model, configured: !!key });

    if (body.action === "voices") {
      if (who.me.role !== "owner") return json({ error: "Μόνο η Γενική Διευθύντρια επιλέγει φωνή." }, 403);
      if (!key) return json({ error: "Δεν έχει αποθηκευτεί κλειδί ElevenLabs." }, 400);
      const r = await fetch(`${API}/voices`, { headers: { "xi-api-key": key } });
      const t = await r.text();
      if (!r.ok) return json({ error: elError(r.status, t) }, 502);
      const voices = (JSON.parse(t).voices ?? []).map((v: any) => ({
        voice_id: v.voice_id, name: v.name, category: v.category ?? null,
        description: [v.labels?.gender, v.labels?.accent, v.labels?.age, v.labels?.description ?? v.labels?.descriptive].filter(Boolean).join(" · "),
      }));
      return json({ voices });
    }

    // speak
    const text = String(body.text ?? "").trim().slice(0, 2500);
    if (!text) return json({ error: "Δεν υπάρχει κείμενο." }, 400);
    if (!key) return json({ error: "Δεν έχει ρυθμιστεί φωνή ElevenLabs." }, 400);
    // Η ΓΔ μπορεί να δοκιμάσει άλλη φωνή πριν την επιλέξει
    const voice = who.me.role === "owner" && body.voice_id ? String(body.voice_id) : vs.voice_id;
    const model = who.me.role === "owner" && body.model ? String(body.model) : vs.model || "eleven_multilingual_v2";
    if (!voice) return json({ error: "Δεν έχει επιλεγεί φωνή ElevenLabs." }, 400);
    if (!/^[A-Za-z0-9]{8,40}$/.test(voice) || !/^[a-z0-9_]{3,60}$/.test(model)) return json({ error: "Μη έγκυρη φωνή ή μοντέλο." }, 400);
    const payload: Record<string, unknown> = { text, model_id: model };
    if (/v2_5|flash|turbo/.test(model)) payload.language_code = "el";
    const r = await fetch(`${API}/text-to-speech/${voice}?output_format=mp3_44100_64`, {
      method: "POST",
      headers: { "xi-api-key": key, "Content-Type": "application/json", Accept: "audio/mpeg" },
      body: JSON.stringify(payload),
    });
    if (!r.ok) { const t = await r.text(); console.error("elevenlabs", r.status, t.slice(0, 300)); return json({ error: elError(r.status, t) }, 502); }
    return new Response(r.body, { headers: { ...cors, "Content-Type": "application/octet-stream", "X-Audio-Type": "audio/mpeg", "Cache-Control": "no-store" } });
  } catch (e) {
    console.error(e);
    return json({ error: "Σφάλμα φωνής: " + ((e as Error).message ?? "") }, 500);
  }
});
