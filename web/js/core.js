// Κοινή κατάσταση εφαρμογής
import { currentMonth } from "./util.js";

export const S = {
  api: null,
  me: null,            // { email, name, role, store }
  lists: { stores: [], companies: [] },
  month: (() => { try { return localStorage.getItem("mg-month") || currentMonth(); } catch { return currentMonth(); } })(),
  cache: {},
  filters: {},
  chat: [],
};

export const role = () => S.me?.role;
export const can = {
  editEmployees: () => ["owner", "hr"].includes(role()),
  prepare: () => ["owner", "hr", "manager"].includes(role()),
  sign: () => ["owner", "manager"].includes(role()),
  void: () => role() === "owner",
  audit: () => ["owner", "hr"].includes(role()),
  users: () => role() === "owner",
  settings: () => role() === "owner",
  backup: () => role() === "owner",
  allStores: () => ["owner", "hr"].includes(role()),
};

export const activeStores = () => S.lists.stores.filter((s) => s.active).map((s) => s.name);
export const activeCompanies = () => S.lists.companies.filter((c) => c.active).map((c) => c.name);
export const visibleStores = () => (role() === "manager" ? [S.me.store] : activeStores());

export function invalidate() { S.cache = {}; }

export async function getStatus(month = S.month) {
  return (S.cache["st:" + month] ??= S.api.monthStatus(month).catch((e) => { delete S.cache["st:" + month]; throw e; }));
}
export async function getEmployees() {
  return (S.cache.emps ??= S.api.employees().catch((e) => { delete S.cache.emps; throw e; }));
}

export function setMonth(m) {
  S.month = m;
  try { localStorage.setItem("mg-month", m); } catch {}
}
