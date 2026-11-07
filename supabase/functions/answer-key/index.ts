// Σωστές απαντήσεις, παραδείγματα βαθμολόγησης και αξιολογήσεις AI (μόνο Γενική Διευθύντρια).
//  mode "key":      προφορική σωστή απάντηση → επιλογή(ές) / πρότυπη απάντηση (κατ' εκτίμηση)
//  mode "rate":     προφορική βαθμολογία μιας απάντησης εργαζομένου → βαθμός 0–10 + λόγος
//  mode "evaluate": απαντήσεις εργαζομένων → προτεινόμενος βαθμός 0–10 + αιτιολογία, με βάση τη σωστή απάντηση
//                   και τα παραδείγματα βαθμολόγησης της ΓΔ
// Δεν αποθηκεύει τίποτα· η εφαρμογή γράφει τα αποτελέσματα με τις συναρτήσεις της βάσης (έλεγχος ρόλου εκεί).
import { cors, identify, json, userClient } from "../_shared/common.ts";

const API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = Deno.env.get("AI_MODEL") || "claude-haiku-5-5";

const TOOL = {
  name: "set_answer",
  description: "Καταχώριση της σωστής απάντησης όπως την είπε η Γενική Διευθύντρια.",
  input_schema: {
    type: "object",
    properties: {
      correct: { type: "array", items: { type: "string" }, description: "Γράμματα των σωστών επιλογών (π.χ. [\"Β\"]). Κενό αν η ερώτηση δεν έχει επιλογές ή αν η απάντηση δεν αντιστοιχεί σε καμία επιλογή." },
      model_answer: { type: "string", description: "Για ελεύθερο κείμενο: η πρότυπη απάντηση, καθαρογραμμένη σε σύντομες φράσεις/σημεία, με τα λόγια της ΓΔ. Για ερωτήσεις επιλογής: μόνο αν έδωσε αιτιολόγηση/εξήγηση, αλλιώς κενό." },
      confidence: { type: "string", enum: ["high", "medium", "low"] },
      note: { type: "string", description: "Σύντομη σημείωση στα ελληνικά ΜΟΝΟ αν κάτι χρειάζεται έλεγχο (π.χ. «Η απάντηση δεν ταιριάζει με καμία επιλογή», «Είπατε δύο επιλογές σε ερώτηση μίας επιλογής»). Αλλιώς κενό." },
      spoken_summary: { type: "string", description: "Πολύ σύντομη επιβεβαίωση για να ακουστεί (π.χ. «Β, άμεση εγγραφή» ή «Κράτησα τρία σημεία»)." },
    },
    required: ["correct", "model_answer", "confidence", "note", "spoken_summary"],
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const who = await identify(req);
    if (!who.me) return json({ error: who.error }, who.status);
    if (who.me.role !== "owner") return json({ error: "Μόνο η Γενική Διευθύντρια ορίζει σωστές απαντήσεις." }, 403);
    if (!API_KEY) return json({ error: "Δεν έχει ρυθμιστεί το κλειδί του AI στον server." }, 500);

    const body = await req.json().catch(() => ({}));
    const mode = body.mode ?? "key";
    if (mode === "rate") return await rate(req, body);
    if (mode === "evaluate") return await evaluate(req, body);
    const spoken = String(body.spoken ?? "").trim().slice(0, 3000);
    if (!body.question_id || !spoken) return json({ error: "Λείπει η ερώτηση ή η απάντηση." }, 400);

    // Η ερώτηση διαβάζεται με τα δικαιώματα της χρήστριας (RLS)
    const { data: x, error } = await userClient(req).from("assessment_questions")
      .select("id,qtype,text,section,specialty,options,scale_min,scale_max").eq("id", body.question_id).maybeSingle();
    if (error || !x) return json({ error: "Η ερώτηση δεν βρέθηκε." }, 404);

    const TYPE: Record<string, string> = { single: "Μία σωστή επιλογή", multi: "Πολλές σωστές επιλογές (μία ή περισσότερες)", text: "Ελεύθερο κείμενο (χωρίς επιλογές)", scale: "Κλίμακα" };
    const opts = (x.options ?? []).map((o: any) => `${o.key}. ${o.label}`).join("\n");
    const system = `Βοηθάς τη Γενική Διευθύντρια της MEGA GYM να ορίσει τις σωστές απαντήσεις των ερωτηματολογίων αξιολόγησης προσωπικού.
Εκείνη λέει ΠΡΟΦΟΡΙΚΑ την απάντηση· το κείμενο προέρχεται από αναγνώριση ομιλίας και μπορεί να έχει λάθη ήχου.
Κατάλαβε τι εννοεί και αντιστοίχισέ το: «το δεύτερο», «β», «βήτα», «η άμεση εγγραφή» → Β κ.λπ. Στην πολλαπλή επιλογή μπορεί να πει πολλές («α και γ»).
Μην επινοείς απάντηση που δεν είπε. Αν δεν ταιριάζει με καμία επιλογή, άφησε κενό το correct, βάλε confidence low και εξήγησε στο note.
Για ελεύθερο κείμενο γράψε την πρότυπη απάντηση καθαρά, με τα λόγια της, χωρίς να προσθέτεις δικές σου γνώσεις.
Απάντησε ΜΟΝΟ καλώντας το εργαλείο set_answer.`;
    const user = `Ερώτηση (${TYPE[x.qtype] ?? x.qtype}${x.section ? ` · ενότητα ${x.section}` : ""}${x.specialty ? ` · ${x.specialty}` : ""}):
${x.text}
${opts ? `Επιλογές:\n${opts}` : ""}

Τι είπε η Γενική Διευθύντρια: «${spoken}»`;

    const a = await callTool(system, user, TOOL, 800);
    if (a instanceof Response) return a;

    // Καθαρισμός σύμφωνα με τον τύπο της ερώτησης (ο server της βάσης ελέγχει ξανά στην αποθήκευση)
    const keys = new Set((x.options ?? []).map((o: any) => o.key));
    let correct: string[] = x.qtype === "single" || x.qtype === "multi" ? [...new Set((a.correct ?? []).map((k: string) => String(k).trim().toUpperCase()).filter((k: string) => keys.has(k)))] as string[] : [];
    let note = String(a.note ?? "").trim();
    let confidence = ["high", "medium", "low"].includes(a.confidence) ? a.confidence : "medium";
    if (x.qtype === "single" && correct.length > 1) { note = note || "Ειπώθηκαν περισσότερες από μία επιλογές σε ερώτηση μίας επιλογής."; correct = []; confidence = "low"; }
    if ((x.qtype === "single" || x.qtype === "multi") && !correct.length && confidence !== "low") confidence = "low";
    return json({
      correct: correct.length ? correct.sort() : null,
      model_answer: String(a.model_answer ?? "").trim().slice(0, 4000) || null,
      confidence, note: note || null,
      spoken_summary: String(a.spoken_summary ?? "").trim().slice(0, 200),
    });
  } catch (e) {
    console.error(e);
    return json({ error: "Σφάλμα: " + ((e as Error).message ?? "") }, 500);
  }
});

// ─────────────── Κοινά ───────────────
async function callTool(system: string, user: string, tool: any, maxTokens: number): Promise<any> {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: maxTokens, system, tools: [tool], tool_choice: { type: "tool", name: tool.name }, messages: [{ role: "user", content: user }] }),
  });
  const out = await r.json();
  if (!r.ok) { console.error(out); return json({ error: "Το AI δεν απάντησε: " + (out?.error?.message ?? r.status) }, 502); }
  const call = (out.content ?? []).find((c: any) => c.type === "tool_use");
  if (!call) return json({ error: "Το AI δεν έδωσε απάντηση. Δοκιμάστε ξανά." }, 502);
  return call.input ?? {};
}
async function loadQuestion(req: Request, id: string) {
  const db = userClient(req);
  const { data } = await db.from("assessment_questions")
    .select("id,qtype,text,section,specialty,model_answer,options").eq("id", id).maybeSingle();
  if (!data) return null;
  // Πρότυπη απάντηση: η πιο πρόσφατη για την ίδια ερώτηση (π.χ. ορίστηκε σε νεότερη έκδοση)
  const { data: latest } = await db.rpc("q_latest_model", { p_question: id });
  return { ...data, model_answer: latest || data.model_answer };
}

// ─────────────── Προφορική βαθμολογία μιας απάντησης εργαζομένου ───────────────
const RATE_TOOL = {
  name: "set_rating",
  description: "Καταχώριση του βαθμού (0–10) και του λόγου που έδωσε η Γενική Διευθύντρια σε μια απάντηση εργαζομένου.",
  input_schema: {
    type: "object",
    properties: {
      score: { type: "number", description: "Βαθμός 0–10 όπως τον είπε (π.χ. «εφτάμισι» → 7.5). Αν δεν είπε αριθμό, null." },
      reason: { type: "string", description: "Ο λόγος/αιτιολογία με τα λόγια της, καθαρογραμμένος: τι ήταν καλό, τι έλειπε, τι ΔΕΝ πρέπει να λέγεται." },
      spoken_summary: { type: "string", description: "Πολύ σύντομη επιβεβαίωση για να ακουστεί (π.χ. «Επτά. Έλειπε η πρόταση για δοκιμαστικό.»)." },
    },
    required: ["score", "reason", "spoken_summary"],
  },
};
async function rate(req: Request, body: any) {
  const spoken = String(body.spoken ?? "").trim().slice(0, 3000);
  const answer = String(body.answer ?? "").trim().slice(0, 4000);
  if (!body.question_id || !spoken || !answer) return json({ error: "Λείπει η ερώτηση, η απάντηση ή η βαθμολογία." }, 400);
  const x = await loadQuestion(req, body.question_id);
  if (!x) return json({ error: "Η ερώτηση δεν βρέθηκε." }, 404);
  const system = `Η Γενική Διευθύντρια της MEGA GYM βαθμολογεί ΠΡΟΦΟΡΙΚΑ (0 έως 10) απαντήσεις γυμναστών/προσωπικού και εξηγεί τον λόγο.
Το κείμενο προέρχεται από αναγνώριση ομιλίας (μπορεί να έχει λάθη ήχου). Βγάλε τον αριθμό (λέξεις → αριθμός, «εφτάμισι» = 7.5, «άριστα» = 10 μόνο αν το εννοεί ρητά)
και καθαρόγραψε τον λόγο με τα λόγια της, χωρίς να προσθέτεις δικές σου κρίσεις. Απάντησε ΜΟΝΟ με το εργαλείο set_rating.`;
  const user = `Ερώτηση: ${x.text}
${x.model_answer ? `Σωστή/πρότυπη απάντηση: ${x.model_answer}\n` : ""}Απάντηση εργαζομένου: «${answer}»

Τι είπε η Γενική Διευθύντρια: «${spoken}»`;
  const a = await callTool(system, user, RATE_TOOL, 600);
  if (a instanceof Response) return a;
  const n = Number(a.score);
  const score = Number.isFinite(n) && n >= 0 && n <= 10 ? Math.round(n * 10) / 10 : null;
  return json({ score, reason: String(a.reason ?? "").trim().slice(0, 2000), spoken_summary: String(a.spoken_summary ?? "").trim().slice(0, 200) });
}

// ─────────────── Αξιολόγηση απαντήσεων από το AI ───────────────
const EVAL_TOOL = {
  name: "set_evaluations",
  description: "Προτεινόμενος βαθμός 0–10 και σύντομη αιτιολογία για κάθε απάντηση.",
  input_schema: {
    type: "object",
    properties: {
      items: { type: "array", items: { type: "object", properties: {
        n: { type: "integer", description: "Ο αριθμός της απάντησης όπως δόθηκε." },
        score: { type: "number", description: "0–10, με βήμα 0.5" },
        reason: { type: "string", description: "1–3 προτάσεις στα ελληνικά: τι κάλυψε, τι έλειψε, αν είπε κάτι που δεν πρέπει να λέγεται." },
      }, required: ["n", "score", "reason"] } },
    },
    required: ["items"],
  },
};
async function evaluate(req: Request, body: any) {
  const items = Array.isArray(body.items) ? body.items.slice(0, 25) : [];
  if (!body.question_id || !items.length) return json({ error: "Δεν υπάρχουν απαντήσεις για αξιολόγηση." }, 400);
  const x = await loadQuestion(req, body.question_id);
  if (!x) return json({ error: "Η ερώτηση δεν βρέθηκε." }, 404);
  const { data: ex } = await userClient(req).rpc("ex_for_question", { p_question: body.question_id });
  const examples = (ex ?? []).slice(0, 40);
  if (!x.model_answer && !examples.length) return json({ error: "Για να αξιολογήσει το AI χρειάζεται σωστή/πρότυπη απάντηση ή παραδείγματα βαθμολόγησης για αυτή την ερώτηση." }, 400);
  const system = `Αξιολογείς απαντήσεις προσωπικού της MEGA GYM (γυμναστές, ρεσεψιόν κ.λπ.) σε ερώτηση ελεύθερου κειμένου, με κλίμακα 0–10.
Βαθμολόγησε ΟΠΩΣ ΘΑ ΒΑΘΜΟΛΟΓΟΥΣΕ Η ΓΕΝΙΚΗ ΔΙΕΥΘΥΝΤΡΙΑ: η πρότυπη απάντηση δείχνει τι θεωρεί σωστό· τα παραδείγματά της δείχνουν πόσο αξίζει κάθε είδος απάντησης
και τι ΔΕΝ πρέπει να λέγεται. Ακολούθησε τα παραδείγματα πιο πιστά από τη δική σου γνώμη. Μην τιμωρείς ορθογραφία ή ύφος, εκτός αν το κάνουν τα παραδείγματα.
Αν μια απάντηση μοιάζει πολύ με παράδειγμα, δώσε κοντινό βαθμό. Η αιτιολογία να αναφέρει συγκεκριμένα τι κάλυψε και τι έλειψε. Απάντησε ΜΟΝΟ με το εργαλείο set_evaluations.`;
  const user = `Ερώτηση: ${x.text}
${x.model_answer ? `\nΣωστή / πρότυπη απάντηση (Γενική Διευθύντρια):\n${x.model_answer}\n` : ""}
${examples.length ? `Παραδείγματα βαθμολόγησης της Γενικής Διευθύντριας:\n${examples.map((e: any, i: number) => `${i + 1}) Απάντηση: «${String(e.answer_text).slice(0, 800)}» → βαθμός ${e.score}/10${e.reason ? ` · λόγος: ${String(e.reason).slice(0, 500)}` : ""}`).join("\n")}\n` : "(Δεν υπάρχουν ακόμη παραδείγματα βαθμολόγησης.)\n"}
Απαντήσεις προς αξιολόγηση:
${items.map((it: any, i: number) => `[${i + 1}] «${String(it.answer ?? "").slice(0, 1500)}»`).join("\n")}`;
  const a = await callTool(system, user, EVAL_TOOL, 300 + items.length * 160);
  if (a instanceof Response) return a;
  const out = (a.items ?? []).map((r: any) => {
    const it = items[Number(r.n) - 1]; const n = Number(r.score);
    return it && Number.isFinite(n) ? { attempt_id: it.attempt_id, score: Math.max(0, Math.min(10, Math.round(n * 2) / 2)), reason: String(r.reason ?? "").trim().slice(0, 2000) } : null;
  }).filter(Boolean);
  return json({ items: out, examples_used: examples.length, model: MODEL });
}
