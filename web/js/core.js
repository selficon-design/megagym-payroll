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
// Δικαιώματα: έρχονται από τον server (whoami → perms, ίδιος πίνακας που ελέγχει κάθε ενέργεια).
// Στη λειτουργία επίδειξης (χωρίς server) χρησιμοποιούνται οι αρχικές ρυθμίσεις ανά ρόλο.
const DEMO_PERMS = {
  owner: ["payroll.view", "payroll.prepare", "payroll.sign", "payroll.void", "payroll.pdf", "payroll.bulk", "payroll.backup", "employees.view", "employees.edit", "audit.view", "users.manage", "settings.manage", "ai.assistant"],
  hr: ["payroll.view", "payroll.prepare", "employees.view", "employees.edit", "audit.view", "ai.assistant"],
  manager: ["payroll.view", "payroll.prepare", "payroll.sign", "employees.view", "ai.assistant"],
};
export const perms = () => S.me?.perms || DEMO_PERMS[role()] || [];
export const P = (p) => perms().includes(p);
export const can = {
  payroll: () => P("payroll.view"),
  employees: () => P("employees.view") || P("payroll.view"),
  editEmployees: () => P("employees.edit"),
  prepare: () => P("payroll.prepare"),
  sign: () => P("payroll.sign"),
  void: () => P("payroll.void"),
  pdf: () => P("payroll.pdf"),
  bulk: () => P("payroll.pdf") && P("payroll.bulk"),
  audit: () => P("audit.view"),
  users: () => P("users.manage"),
  settings: () => P("settings.manage"),
  backup: () => P("payroll.backup") && P("payroll.pdf"),
  allStores: () => (S.me?.scope ? S.me.scope !== "own_store" : ["owner", "hr"].includes(role())),
  // τα δικαιώματα ελέγχονται στον server· εδώ μόνο τι εμφανίζεται
  requests: () => P("requests.view"),
  createRequests: () => P("requests.create"),
  decide: () => P("requests.decide"),
  implement: () => P("requests.implement"),
  gm: () => role() === "owner",
  templates: () => P("templates.manage"),
  statsEntry: () => P("stats.entry"),
  statsReports: () => P("stats.reports"),
  statsExport: () => P("stats.export"),
  assessAdmin: () => P("assess.manage"),
  assessGrade: () => P("assess.grade"),
  assessResults: () => P("assess.results") || P("assess.manage") || P("assess.grade"),
  assessFull: () => P("assess.manage") || P("assess.grade"),
  assessOpen: () => P("assess.open"),
  exit: () => P("exit.view"),
  leave: () => P("leave.view"),
  leaveAdjust: () => P("leave.adjust"),
  leaveCancel: () => P("leave.cancel"),
  leaveSettle: () => P("leave.settle"),
  overdraw: () => P("leave.overdraw"),
  schedule: () => P("schedule.view"),
  scheduleManage: () => P("schedule.manage"),
  scheduleSettings: () => P("schedule.settings"),
  permissions: () => P("permissions.manage"),
  ai: () => P("ai.assistant"),
};

export const activeStores = () => S.lists.stores.filter((s) => s.active).map((s) => s.name);
export const activeSpecialties = () => (S.lists.specialties || []).filter((s) => s.active).map((s) => s.name);
export const specialtyKind = (name) => (S.lists.specialties || []).find((s) => s.name === name)?.stat_kind || null;
export const activeCompanies = () => S.lists.companies.filter((c) => c.active).map((c) => c.name);
export const visibleStores = () => (role() === "manager" || S.me?.scope === "own_store" ? [S.me.store].filter(Boolean) : activeStores());

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
