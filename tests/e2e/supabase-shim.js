// ΜΟΝΟ ΓΙΑ ΤΟΠΙΚΟ ΕΛΕΓΧΟ: υποκατάστατο του supabase-js v2 (ίδιο API που χρησιμοποιεί η εφαρμογή) πάνω σε PostgREST.
(function () {
  function createClient(url, key, opts = {}) {
    const a = opts.auth || {}; const SK = a.storageKey || "sb-auth"; const persist = a.persistSession !== false;
    let mem = null; const listeners = [];
    const load = () => { if (!persist) return mem; try { return JSON.parse(localStorage.getItem(SK) || "null"); } catch { return null; } };
    const store = (s) => { mem = s; if (persist) { if (s) localStorage.setItem(SK, JSON.stringify(s)); else localStorage.removeItem(SK); } };
    const headers = () => ({ apikey: key, Authorization: "Bearer " + ((opts.global?.headers?.Authorization || "").replace(/^Bearer /, "") || load()?.access_token || key) });
    async function req(method, path, { body, prefer, accept, range } = {}) {
      const h = { ...headers(), "Content-Type": "application/json" };
      if (prefer) h.Prefer = prefer; if (accept) h.Accept = accept;
      const r = await fetch(url + path, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) });
      const txt = await r.text(); let j = null; try { j = txt ? JSON.parse(txt) : null; } catch { j = txt; }
      if (!r.ok) return { data: null, error: { message: j?.message || txt || r.statusText, code: j?.code, details: j?.details, hint: j?.hint }, status: r.status };
      return { data: j, error: null, status: r.status };
    }
    class Q {
      constructor(path, method = "GET", body, prefer) { this.path = path; this.method = method; this.body = body; this.prefer = prefer; this.p = []; this.mode = null; }
      select(c = "*") { if (this.method === "GET") this.p.push("select=" + encodeURIComponent(c.replace(/\s/g, ""))); else this.prefer = (this.prefer ? this.prefer + "," : "") + "return=representation"; return this; }
      f(col, op, v) { this.p.push(encodeURIComponent(col) + "=" + op + "." + encodeURIComponent(v)); return this; }
      eq(c, v) { return this.f(c, "eq", v); } neq(c, v) { return this.f(c, "neq", v); } gte(c, v) { return this.f(c, "gte", v); } lte(c, v) { return this.f(c, "lte", v); } lt(c, v) { return this.f(c, "lt", v); } gt(c, v) { return this.f(c, "gt", v); }
      is(c, v) { this.p.push(encodeURIComponent(c) + "=is." + (v === null ? "null" : v)); return this; }
      in(c, arr) { this.p.push(encodeURIComponent(c) + "=in.(" + arr.map((x) => '"' + String(x).replace(/"/g, '\\"') + '"').map(encodeURIComponent).join(",") + ")"); return this; }
      order(c, o = {}) { this.p.push("order=" + encodeURIComponent(c) + "." + (o.ascending === false ? "desc" : "asc") + (o.nullsFirst === false ? ".nullslast" : o.nullsFirst ? ".nullsfirst" : "")); return this; }
      limit(n) { this.p.push("limit=" + n); return this; }
      range(a, b) { this.p.push("offset=" + a, "limit=" + (b - a + 1)); return this; }
      single() { this.mode = "single"; return this; } maybeSingle() { this.mode = "maybe"; return this; }
      async run() {
        const qs = this.p.length ? (this.path.includes("?") ? "&" : "?") + this.p.join("&") : "";
        const res = await req(this.method, this.path + qs, { body: this.body, prefer: this.prefer });
        if (res.error || !this.mode) return res;
        const rows = Array.isArray(res.data) ? res.data : res.data == null ? [] : [res.data];
        if (rows.length > 1) return { data: null, error: { message: "JSON object requested, multiple (or no) rows returned" } };
        if (this.mode === "single" && rows.length !== 1) return { data: null, error: { message: "JSON object requested, multiple (or no) rows returned" } };
        return { data: rows[0] ?? null, error: null };
      }
      then(ok, bad) { return this.run().then(ok, bad); }
    }
    const client = {
      from(t) {
        const P = "/rest/v1/" + encodeURIComponent(t);
        return {
          select: (c) => new Q(P).select(c),
          insert: (b) => new Q(P, "POST", b, "return=minimal"),
          update: (b) => new Q(P, "PATCH", b, "return=minimal"),
          delete: () => new Q(P, "DELETE", undefined, "return=minimal"),
          upsert: (b, o = {}) => new Q(P + (o.onConflict ? "?on_conflict=" + encodeURIComponent(o.onConflict) : ""), "POST", b, "return=minimal,resolution=" + (o.ignoreDuplicates ? "ignore" : "merge") + "-duplicates"),
        };
      },
      rpc(name, args) { return new Q("/rest/v1/rpc/" + name, "POST", args || {}); },
      functions: { async invoke() { return { data: null, error: { message: "Δεν υπάρχουν λειτουργίες server στον τοπικό έλεγχο.", context: { json: async () => ({}) } } }; } },
      auth: {
        async signInWithPassword({ email, password }) {
          const r = await req("POST", "/auth/v1/token?grant_type=password", { body: { email, password } });
          if (r.error) return { data: null, error: { message: "Invalid login credentials" } };
          store(r.data); listeners.forEach((f) => f("SIGNED_IN", r.data)); return { data: { session: r.data, user: r.data.user }, error: null };
        },
        async getSession() { return { data: { session: load() }, error: null }; },
        async getUser() { const s = load(); return { data: { user: s?.user || null }, error: null }; },
        async signOut() { store(null); listeners.forEach((f) => f("SIGNED_OUT", null)); return { error: null }; },
        async updateUser() { return { data: {}, error: null }; },
        onAuthStateChange(f) { listeners.push(f); return { data: { subscription: { unsubscribe() {} } } }; },
      },
    };
    return client;
  }
  window.supabase = { createClient };
})();
