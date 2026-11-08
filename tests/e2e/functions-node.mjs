// ΜΟΝΟ ΓΙΑ ΤΟΠΙΚΟ ΕΛΕΓΧΟ: τρέχει τις λειτουργίες server (Deno) σε Node 22+, στη θύρα 8788, όταν δεν υπάρχει deno.
//   SUPABASE_URL=http://localhost:8787 SERVICE_ROLE_KEY=<jwt service_role> ANON_KEY=<jwt anon> node --experimental-strip-types functions-node.mjs
//   και ο server.mjs με FUNCTIONS_URL=http://localhost:8788
import { register } from "node:module"; import http from "node:http";
const SHIM = new URL("./supabase-deno.mjs", import.meta.url).href;
register("data:text/javascript," + encodeURIComponent(`export async function resolve(s, c, n) { return s === "jsr:@supabase/supabase-js@2" ? n(${JSON.stringify(SHIM)}, c) : n(s, c); }`));
const handlers = {}; let current = null;
globalThis.Deno = { env: { get: (k) => process.env[k] }, serve: (h) => { handlers[current] = h; } };
for (const name of ["admin-users", "ask", "answer-key", "tts"]) {
  current = name;
  try { await import(new URL(`../../supabase/functions/${name}/index.ts`, import.meta.url).href); } catch (e) { console.error("load", name, e.message); }
}
http.createServer(async (req, res) => {
  const h = handlers[req.url.replace(/^\//, "").split("?")[0]]; if (!h) { res.writeHead(404); return res.end(); }
  const chunks = []; for await (const c of req) chunks.push(c);
  const r = await h(new Request("http://localhost" + req.url, { method: req.method, headers: req.headers, body: ["GET", "HEAD"].includes(req.method) ? undefined : Buffer.concat(chunks) }));
  res.writeHead(r.status, Object.fromEntries(r.headers)); res.end(Buffer.from(await r.arrayBuffer()));
}).listen(8788, () => console.log("functions on 8788", Object.keys(handlers)));
