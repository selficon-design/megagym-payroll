// Κοινή κατάσταση εφαρμογής
import { currentMonth } from "./util.js";

export const S = {
  api: null,
  me: null,            // { email, name, role, store }
  lists: { stores: [], companies: [], specialties: [] },
  month: (() => { try { return localStorage.getItem("mg-month") || currentMonth(); } catch { return currentMonth(); } })(),
  cache: {},
  filters: {},
  chat: [],
};

export const role = () => S.me?.role;
export const can = {
  payroll: () => ["owner", "hr", "manager"].includes(role()),
  editEmployees: () => ["owner", "hr"].includes(role()),
  prepare: () => ["owner", "hr", "manager"].includes(role()),
  sign: () => ["owner", "manager"].includes(role()),
  void: () => role() === "owner",
  audit: () => ["owner", "hr"].includes(role()),
  users: () => role() === "owner",
  settings: () => role() === "owner",
  backup: () => role() === "owner",
  allStores: () => ["owner", "hr"].includes(role()),
  // Επέκταση: τα δικαιώματα ελέγχονται στον server· εδώ μόνο τι εμφανίζεται
  requests: () => ["owner", "hr", "manager"].includes(role()),
  createRequests: () => ["owner", "hr", "manager"].includes(role()),
  decide: () => ["owner", "hr"].includes(role()),
  gm: () => role() === "owner",
  templates: () => role() === "owner",
  statsEntry: () => ["owner", "manager"].includes(role()),
  statsReports: () => ["owner", "hr"].includes(role()),
  assessAdmin: () => role() === "owner",
  assessResults: () => ["owner", "hr"].includes(role()),
  assessOpen: () => ["owner", "hr", "manager", "trainer"].includes(role()),
};

export const activeStores = () => S.lists.stores.filter((s) => s.active).map((s) => s.name);
export const activeSpecialties = () => (S.lists.specialties || []).filter((s) => s.active).map((s) => s.name);
export const specialtyKind = (name) => (S.lists.specialties || []).find((s) => s.name === name)?.stat_kind || null;
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
