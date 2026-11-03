// ΜΟΝΟ ΓΙΑ ΤΟΠΙΚΟ ΕΛΕΓΧΟ των λειτουργιών server (Deno): ίδιες κλήσεις supabase-js, πάνω στο supabase-shim.js
globalThis.window ??= globalThis;
const mem = {}; globalThis.localStorage ??= { getItem: (k) => mem[k] ?? null, setItem: (k, v) => (mem[k] = v), removeItem: (k) => delete mem[k] };
await import("./supabase-shim.js");
export function createClient(url, key, opts = {}) {
  const c = window.supabase.createClient(url, key, opts);
  const H = { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" };
  const call = async (method, path, body) => {
    const r = await fetch(url + path, { method, headers: H, body: body ? JSON.stringify(body) : undefined });
    const j = await r.json().catch(() => ({}));
    return r.ok ? { data: j, error: null } : { data: null, error: { message: j.message || r.statusText, status: r.status } };
  };
  c.auth.getUser = async (token) => { const r = await fetch(url + "/auth/v1/user", { headers: { apikey: key, Authorization: "Bearer " + token } }); const j = await r.json(); return r.ok ? { data: { user: j }, error: null } : { data: { user: null }, error: { message: j.message } }; };
  c.auth.admin = {
    listUsers: async ({ page = 1, perPage = 50 } = {}) => { const r = await call("GET", `/auth/v1/admin/users?page=${page}&per_page=${perPage}`); return r.error ? r : { data: { users: r.data.users }, error: null }; },
    createUser: (b) => call("POST", "/auth/v1/admin/users", b),
    updateUserById: (id, b) => call("PUT", `/auth/v1/admin/users/${id}`, b),
    deleteUser: (id) => call("DELETE", `/auth/v1/admin/users/${id}`),
  };
  return c;
}
