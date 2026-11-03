// Τοπικός «Supabase»: στατικά αρχεία + /rest/v1 → PostgREST + /auth/v1 (δοκιμαστικοί λογαριασμοί)
import http from "node:http"; import fs from "node:fs"; import path from "node:path"; import crypto from "node:crypto";
const WEB = process.argv[2], SECRET = process.env.JWT_SECRET, PG = "http://127.0.0.1:3000", PORT = 8787;
const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
export const jwt = (p) => { const h = b64({ alg: "HS256", typ: "JWT" }), b = b64(p); return `${h}.${b}.${crypto.createHmac("sha256", SECRET).update(`${h}.${b}`).digest("base64url")}`; };
// Δοκιμαστικοί λογαριασμοί σύνδεσης (μόνο τοπικά, στη μνήμη)
const AUTH = new Map(["owner@test.gr", "hr@test.gr", "glyfada@test.gr", "kifisia@test.gr", "trainer@test.gr", "mariamaneta@megagym.gr"]
  .map((e) => [e, { id: crypto.createHash("md5").update(e).digest("hex"), email: e, password: "test1234", banned_until: null, last_sign_in_at: null }]));
const claims = (req) => { try { return JSON.parse(Buffer.from((req.headers.authorization || "").split(" ")[1].split(".")[1], "base64url")); } catch { return {}; } };
const send = (res, code, obj) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); };
const pub = (u) => ({ id: u.id, email: u.email, banned_until: u.banned_until, last_sign_in_at: u.last_sign_in_at });
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json", ".ttf": "font/ttf" };
http.createServer(async (req, res) => {
  const u = new URL(req.url, "http://x");
  const body = await new Promise((r) => { let d = []; req.on("data", (c) => d.push(c)); req.on("end", () => r(Buffer.concat(d))); });
  if (u.pathname.startsWith("/auth/v1/")) {
    const j = body.length ? JSON.parse(body.toString()) : {};
    if (u.pathname === "/auth/v1/token") {
      const usr = AUTH.get(String(j.email || "").toLowerCase());
      if (!usr || usr.password !== j.password) return send(res, 400, { message: "Invalid login credentials" });
      if (usr.banned_until && new Date(usr.banned_until) > new Date()) return send(res, 400, { message: "User is banned" });
      usr.last_sign_in_at = new Date().toISOString();
      const exp = Math.floor(Date.now() / 1000) + 3600, user = { id: usr.id, email: usr.email };
      return send(res, 200, { access_token: jwt({ sub: user.id, email: usr.email, role: "authenticated", exp }), token_type: "bearer", expires_in: 3600, expires_at: exp, refresh_token: "r", user });
    }
    if (u.pathname === "/auth/v1/user") {
      const c = claims(req), usr = AUTH.get(c.email);
      if (!usr || c.role !== "authenticated") return send(res, 401, { message: "invalid JWT" });
      if (req.method === "PUT" && j.password) usr.password = j.password;
      return send(res, 200, pub(usr));
    }
    if (u.pathname.startsWith("/auth/v1/admin/users")) {
      if (claims(req).role !== "service_role") return send(res, 401, { message: "This endpoint requires a valid service_role key" });
      const id = u.pathname.split("/")[5];
      const usr = id ? [...AUTH.values()].find((x) => x.id === id) : null;
      if (req.method === "GET") { const page = Number(u.searchParams.get("page") || 1), per = Number(u.searchParams.get("per_page") || 50); return send(res, 200, { users: [...AUTH.values()].slice((page - 1) * per, page * per).map(pub) }); }
      if (req.method === "POST") {
        const e = String(j.email || "").toLowerCase(); if (AUTH.has(e)) return send(res, 422, { message: "User already registered" });
        const n = { id: crypto.randomUUID(), email: e, password: j.password, banned_until: null, last_sign_in_at: null }; AUTH.set(e, n); return send(res, 200, pub(n));
      }
      if (!usr) return send(res, 404, { message: "User not found" });
      if (req.method === "PUT") {
        if (j.password) usr.password = j.password;
        if (j.ban_duration) usr.banned_until = j.ban_duration === "none" ? null : new Date(Date.now() + 876000 * 3600e3).toISOString();
        return send(res, 200, pub(usr));
      }
      if (req.method === "DELETE") { AUTH.delete(usr.email); return send(res, 200, {}); }
    }
    res.writeHead(204); return res.end();
  }
  if (u.pathname.startsWith("/functions/v1/") && process.env.FUNCTIONS_URL) {
    const hdr = { ...req.headers }; delete hdr.host; delete hdr["content-length"];
    const r = await fetch(process.env.FUNCTIONS_URL + u.pathname.replace("/functions/v1", ""), { method: req.method, headers: hdr, body: ["GET", "HEAD"].includes(req.method) ? undefined : body });
    res.writeHead(r.status, { "Content-Type": r.headers.get("content-type") || "application/json" }); return res.end(Buffer.from(await r.arrayBuffer()));
  }
  if (u.pathname.startsWith("/rest/v1/")) {
    const target = PG + req.url.replace("/rest/v1", "");
    const hdr = { ...req.headers }; delete hdr.host; delete hdr["content-length"];
    const r = await fetch(target, { method: req.method, headers: hdr, body: ["GET", "HEAD"].includes(req.method) ? undefined : body });
    const out = Buffer.from(await r.arrayBuffer());
    res.writeHead(r.status, { "Content-Type": r.headers.get("content-type") || "application/json" }); return res.end(out);
  }
  let p = decodeURIComponent(u.pathname); if (p === "/") p = "/index.html";
  if (p === "/config.js") { res.writeHead(200, { "Content-Type": MIME[".js"] }); return res.end(`window.MEGA_CONFIG = { supabaseUrl: "http://localhost:${PORT}", supabaseAnonKey: "${jwt({ role: "anon", exp: 4102444800 })}" };`); }
  const f = p === "/vendor/supabase.js" ? path.join(path.dirname(new URL(import.meta.url).pathname), "supabase-shim.js") : path.join(WEB, p);
  if (!f.startsWith(WEB) && !f.endsWith("supabase-shim.js") || !fs.existsSync(f)) { res.writeHead(404); return res.end("not found"); }
  res.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" }); fs.createReadStream(f).pipe(res);
}).listen(PORT, () => console.log("ok on " + PORT));
