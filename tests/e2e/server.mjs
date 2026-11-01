// Τοπικός «Supabase»: στατικά αρχεία + /rest/v1 → PostgREST + /auth/v1 (δοκιμαστικοί λογαριασμοί)
import http from "node:http"; import fs from "node:fs"; import path from "node:path"; import crypto from "node:crypto";
const WEB = process.argv[2], SECRET = process.env.JWT_SECRET, PG = "http://127.0.0.1:3000", PORT = 8787;
const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
export const jwt = (p) => { const h = b64({ alg: "HS256", typ: "JWT" }), b = b64(p); return `${h}.${b}.${crypto.createHmac("sha256", SECRET).update(`${h}.${b}`).digest("base64url")}`; };
const USERS = ["owner@test.gr", "hr@test.gr", "glyfada@test.gr", "kifisia@test.gr", "trainer@test.gr"];
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json", ".ttf": "font/ttf" };
http.createServer(async (req, res) => {
  const u = new URL(req.url, "http://x");
  const body = await new Promise((r) => { let d = []; req.on("data", (c) => d.push(c)); req.on("end", () => r(Buffer.concat(d))); });
  if (u.pathname.startsWith("/auth/v1/")) {
    if (u.pathname === "/auth/v1/token") {
      const { email, password } = JSON.parse(body.toString() || "{}");
      if (!USERS.includes(email) || password !== "test1234") { res.writeHead(400, { "Content-Type": "application/json" }); return res.end(JSON.stringify({ message: "Invalid login credentials" })); }
      const exp = Math.floor(Date.now() / 1000) + 3600, user = { id: crypto.createHash("md5").update(email).digest("hex"), email };
      res.writeHead(200, { "Content-Type": "application/json" });
      return res.end(JSON.stringify({ access_token: jwt({ sub: user.id, email, role: "authenticated", exp }), token_type: "bearer", expires_in: 3600, expires_at: exp, refresh_token: "r", user }));
    }
    res.writeHead(204); return res.end();
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
