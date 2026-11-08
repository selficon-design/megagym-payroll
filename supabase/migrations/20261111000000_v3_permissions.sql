-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Έκδοση 3.0 · Μέρος 1: Ρόλοι & Δικαιώματα
--   Νέος ρόλος «Λογιστήριο» · επεξεργάσιμος πίνακας δικαιωμάτων ανά ενότητα/ενέργεια (μόνο η ΓΔ)
--   · πεδίο πρόσβασης σε καταστήματα ανά ρόλο · ιστορικό αλλαγών · προστασία από απώλεια πρόσβασης
--   · PDF/υπογραφές μόνο μέσω του server.
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: δεν διαγράφεται/αλλάζει καμία εγγραφή. Οι υπάρχουσες συναρτήσεις κρατούν
-- ακριβώς την ίδια λογική· αλλάζει μόνο ο έλεγχος («ρόλος» → «δικαίωμα του ρόλου»).
-- Οι αρχικές τιμές του πίνακα αναπαράγουν τα σημερινά δικαιώματα + τις αποφάσεις της ενότητας 17.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

alter table public.app_users drop constraint if exists app_users_role_check;
alter table public.app_users add constraint app_users_role_check check (role in ('owner','hr','accounting','manager','trainer'));

-- ─────────────── Κατάλογος δικαιωμάτων ───────────────
-- fixed_roles: δικαίωμα που ΔΕΝ αλλάζει από τον πίνακα (ισχύει μόνο για αυτούς τους ρόλους)
create table public.permissions (
  code        text primary key check (code ~ '^[a-z_]+\.[a-z_]+$'),
  module      text not null,
  label       text not null,
  description text,
  fixed_roles text[],
  sort        int not null default 0
);

insert into public.permissions(code, module, label, description, fixed_roles, sort) values
 ('payroll.view',      'Μισθοδοσία', 'Προβολή δηλώσεων', 'Επισκόπηση, εκκρεμότητες, αρχείο δηλώσεων (χωρίς εικόνα υπογραφής)', null, 10),
 ('payroll.prepare',   'Μισθοδοσία', 'Καταχώριση / προετοιμασία δηλώσεων', null, null, 11),
 ('payroll.sign',      'Μισθοδοσία', 'Διαδικασία υπογραφής μισθοδοσίας', 'Tablet καταστήματος και υπογραφή εργαζομένου', null, 12),
 ('payroll.void',      'Μισθοδοσία', 'Ακύρωση υπογεγραμμένης δήλωσης', null, null, 13),
 ('payroll.pdf',       'Μισθοδοσία', 'Λήψη PDF', 'Μόνο ο server δίνει την υπογραφή που χρειάζεται το PDF', null, 14),
 ('payroll.bulk',      'Μισθοδοσία', 'Μαζική λήψη αρχείων', 'ZIP πολλών δηλώσεων· απαιτεί και «Λήψη PDF»', null, 15),
 ('payroll.backup',    'Μισθοδοσία', 'Backup', 'Μηνιαίο πλήρες backup', null, 16),
 ('employees.view',    'Προσωπικό', 'Προβολή εργαζομένων / καρτέλας', null, null, 20),
 ('employees.edit',    'Προσωπικό', 'Καταχώριση & επεξεργασία στοιχείων εργαζομένων', 'Πρόσληψη, αποχώρηση, μόνιμη μεταφορά, πενθήμερο/εξαήμερο', null, 21),
 ('requests.view',     'Αιτήματα', 'Προβολή αιτημάτων', null, null, 30),
 ('requests.create',   'Αιτήματα', 'Καταχώριση αιτημάτων / αναφορών', null, null, 31),
 ('requests.decide',   'Αιτήματα', 'Έγκριση / απόρριψη', null, null, 32),
 ('requests.implement','Αιτήματα', 'Ανάληψη / ολοκλήρωση υλοποίησης', null, null, 33),
 ('leave.view',        'Άδειες', 'Προβολή υπολοίπων & ημερολογίου αδειών', null, null, 40),
 ('leave.adjust',      'Άδειες', 'Διόρθωση υπολοίπων & ετήσιων βάσεων', null, null, 41),
 ('leave.cancel',      'Άδειες', 'Έγκριση ολικής / μερικής ακύρωσης άδειας', null, null, 42),
 ('leave.settle',      'Άδειες', 'Καταχώριση πληρωμής εκκαθάρισης', null, null, 43),
 ('leave.overdraw',    'Άδειες', 'Ειδική έγκριση υπέρβασης αναλογικού υπολοίπου', 'Μόνο η Γενική Διεύθυνση (δεν αλλάζει)', '{owner}', 44),
 ('schedule.view',     'Πρόγραμμα', 'Προβολή προγράμματος', null, null, 50),
 ('schedule.manage',   'Πρόγραμμα', 'Διαχείριση & οριστικοποίηση προγράμματος', null, null, 51),
 ('schedule.settings', 'Πρόγραμμα', 'Ωράρια λειτουργίας & έτοιμα ωράρια', null, null, 52),
 ('stats.view',        'Στατιστικά', 'Προβολή στατιστικών', null, null, 60),
 ('stats.entry',       'Στατιστικά', 'Καταχώριση στατιστικών', null, null, 61),
 ('stats.reports',     'Στατιστικά', 'Reports', 'Προβολή μέσα στην εφαρμογή', null, 62),
 ('stats.export',      'Στατιστικά', 'Εξαγωγή reports (Excel)', null, null, 63),
 ('assess.manage',     'Αξιολογήσεις', 'Διαχείριση ερωτηματολογίων', 'Ερωτήσεις, σωστές απαντήσεις, σύνδεσμοι', null, 70),
 ('assess.open',       'Αξιολογήσεις', 'Άνοιγμα αξιολόγησης', null, null, 71),
 ('assess.results',    'Αξιολογήσεις', 'Προβολή απαντήσεων και βαθμολογίας', 'Κανονικές αξιολογήσεις, στο πεδίο του χρήστη', null, 72),
 ('assess.grade',      'Αξιολογήσεις', 'Βαθμολόγηση ελεύθερων απαντήσεων', null, null, 73),
 ('exit.view',         'Αξιολογήσεις', 'Περιεχόμενο & αναφορές Exit Interview', 'ΜΟΝΟ ΓΔ, HR, Εκπαιδευτής (δεν αλλάζει)', '{owner,hr,trainer}', 74),
 ('ai.assistant',      'Γενικά', 'Βοηθός AI', null, null, 80),
 ('audit.view',        'Διαχείριση', 'Ιστορικό ενεργειών', null, null, 90),
 ('users.manage',      'Διαχείριση', 'Διαχείριση χρηστών', null, null, 91),
 ('templates.manage',  'Διαχείριση', 'Πρότυπα κειμένων', null, null, 92),
 ('settings.manage',   'Διαχείριση', 'Ρυθμίσεις (καταστήματα, εταιρείες, ειδικότητες, είδη άδειας)', null, null, 93),
 ('permissions.manage','Διαχείριση', 'Αλλαγή δικαιωμάτων', 'Μόνο η Γενική Διεύθυνση (δεν αλλάζει)', '{owner}', 94);

create table public.role_permissions (
  role       text not null check (role in ('owner','hr','accounting','manager','trainer')),
  perm       text not null references public.permissions(code),
  allowed    boolean not null default false,
  updated_by text not null default 'system',
  updated_at timestamptz not null default now(),
  primary key (role, perm)
);

-- Αρχικές ρυθμίσεις: σημερινά δικαιώματα + ενότητα 17 (κάθε κελί υπάρχει ρητά· ό,τι δεν αναφέρεται = όχι)
insert into public.role_permissions(role, perm, allowed)
select r, p.code, false from unnest(array['owner','hr','accounting','manager','trainer']) r cross join public.permissions p;
update public.role_permissions x set allowed = true from (values
 ('owner','payroll.view'),('owner','payroll.prepare'),('owner','payroll.sign'),('owner','payroll.void'),('owner','payroll.pdf'),('owner','payroll.bulk'),('owner','payroll.backup'),
 ('owner','employees.view'),('owner','employees.edit'),('owner','requests.view'),('owner','requests.create'),('owner','requests.decide'),
 ('owner','leave.view'),('owner','leave.adjust'),('owner','leave.cancel'),('owner','leave.settle'),('owner','leave.overdraw'),
 ('owner','schedule.view'),('owner','schedule.settings'),('owner','stats.view'),('owner','stats.entry'),('owner','stats.reports'),('owner','stats.export'),
 ('owner','assess.manage'),('owner','assess.open'),('owner','assess.results'),('owner','assess.grade'),('owner','exit.view'),('owner','ai.assistant'),
 ('owner','audit.view'),('owner','users.manage'),('owner','templates.manage'),('owner','settings.manage'),('owner','permissions.manage'),
 ('hr','payroll.view'),('hr','payroll.prepare'),('hr','employees.view'),('hr','employees.edit'),('hr','requests.view'),('hr','requests.create'),('hr','requests.decide'),
 ('hr','leave.view'),('hr','leave.adjust'),('hr','leave.cancel'),('hr','schedule.view'),('hr','stats.view'),('hr','stats.reports'),('hr','stats.export'),
 ('hr','assess.open'),('hr','assess.results'),('hr','assess.grade'),('hr','exit.view'),('hr','ai.assistant'),('hr','audit.view'),
 ('accounting','payroll.view'),('accounting','payroll.pdf'),('accounting','employees.view'),('accounting','employees.edit'),
 ('accounting','leave.view'),('accounting','leave.adjust'),('accounting','leave.cancel'),('accounting','leave.settle'),
 ('manager','payroll.view'),('manager','payroll.prepare'),('manager','payroll.sign'),('manager','employees.view'),
 ('manager','requests.view'),('manager','requests.create'),('manager','requests.implement'),('manager','leave.view'),
 ('manager','schedule.view'),('manager','schedule.manage'),('manager','stats.view'),('manager','stats.entry'),('manager','stats.reports'),
 ('manager','assess.open'),('manager','assess.results'),('manager','ai.assistant'),
 ('trainer','employees.view'),('trainer','schedule.view'),('trainer','stats.view'),('trainer','stats.reports'),
 ('trainer','assess.open'),('trainer','assess.results'),('trainer','exit.view')
) v(r, p) where x.role = v.r and x.perm = v.p;
-- Τα «σταθερά» δικαιώματα ακολουθούν πάντα τον ορισμό τους
update public.role_permissions x set allowed = (x.role = any(p.fixed_roles)) from public.permissions p where p.code = x.perm and p.fixed_roles is not null;

-- Πεδίο πρόσβασης σε καταστήματα ανά ρόλο
--   all = όλα · own_store = μόνο το κατάστημα του χρήστη · assigned = όσα ορίζονται ανά χρήστη (πεδίο εκπαιδευτή)
create table public.role_scopes (
  role       text primary key check (role in ('owner','hr','accounting','manager','trainer')),
  scope      text not null check (scope in ('all','own_store','assigned')),
  updated_by text not null default 'system',
  updated_at timestamptz not null default now(),
  constraint owner_all check (role <> 'owner' or scope = 'all')
);
insert into public.role_scopes(role, scope) values ('owner','all'),('hr','all'),('accounting','all'),('manager','own_store'),('trainer','all');

-- Ιστορικό αλλαγών δικαιωμάτων (δεν αλλάζει ποτέ)
create table public.permission_log (
  id     bigserial primary key,
  at     timestamptz not null default now(),
  actor  text not null,
  role   text not null,
  perm   text,           -- null = αλλαγή πεδίου καταστημάτων
  old_value text,
  new_value text,
  note   text
);

-- ─────────────── Βοηθητικές συναρτήσεις ───────────────
create or replace function public.role_has_perm(p_role text, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when p.fixed_roles is not null then p_role = any(p.fixed_roles) else coalesce(rp.allowed, false) end
      from public.permissions p
      left join public.role_permissions rp on rp.role = p_role and rp.perm = p.code
     where p.code = p_perm), false)
$$;

create or replace function public.has_perm(p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.role_has_perm(public.my_role(), p_perm)
$$;

-- Τουλάχιστον ένα από τα δικαιώματα· επιστρέφει τον ρόλο
create or replace function public.require_perm(variadic p_perms text[]) returns text
language plpgsql stable security definer set search_path = public as $$
declare v text := public.my_role(); p text;
begin
  if v is not null then
    foreach p in array p_perms loop
      if public.role_has_perm(v, p) then return v; end if;
    end loop;
  end if;
  raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.';
end $$;

create or replace function public.my_scope() returns text
language sql stable security definer set search_path = public as $$
  select scope from public.role_scopes where role = public.my_role()
$$;

-- Πεδίο καταστημάτων του χρήστη (ανεξάρτητο από ενότητα· κάθε ενότητα ελέγχει ΚΑΙ το δικό της δικαίωμα)
create or replace function public.can_see_store(p_store text) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.my_scope()
    when 'all' then true
    when 'own_store' then p_store = public.my_store()
    when 'assigned' then exists (select 1 from public.trainer_scopes t where t.email = public.current_email() and (t.store is null or t.store = p_store))
    else false end
$$;

create or replace function public.employee_in_scope(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case public.my_scope()
      when 'all' then true
      when 'own_store' then e.store = public.my_store()
      when 'assigned' then exists (select 1 from public.trainer_scopes t where t.email = public.current_email()
                                     and (t.store is null or t.store = e.store) and (t.specialty is null or t.specialty = e.specialty))
      else false end
    from public.employees e where e.code = p_code), false)
$$;

-- Πεδίο εκπαιδευτή: πλέον ακολουθεί το πεδίο του ρόλου (προεπιλογή: όλα τα καταστήματα, ενότητα 17)
create or replace function public.in_trainer_scope(p_store text, p_specialty text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() = 'trainer' and case public.my_scope()
    when 'all' then true
    when 'assigned' then exists (select 1 from public.trainer_scopes t where t.email = public.current_email()
                                   and (t.store is null or t.store = p_store) and (t.specialty is null or t.specialty = p_specialty))
    else false end
$$;

-- Exit Interview: ΜΟΝΟ ΓΔ, HR, Εκπαιδευτής — ανεξάρτητα από τον πίνακα
create or replace function public.can_view_exit() returns boolean
language sql stable security definer set search_path = public as $$
  select public.role_has_perm(public.my_role(), 'exit.view')
$$;

-- Ποιος είμαι: ρόλος, κατάστημα, πεδίο και λίστα δικαιωμάτων (η οθόνη εμφανίζει μόνο ό,τι επιτρέπεται· ο server ελέγχει ξανά)
create or replace function public.whoami()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object('email', u.email, 'name', u.name, 'role', u.role, 'store', u.store, 'scope', public.my_scope(),
            'perms', (select coalesce(jsonb_agg(p.code order by p.sort), '[]') from public.permissions p where public.role_has_perm(u.role, p.code)))
       from public.app_users u where u.email = public.current_email() and u.active),
    jsonb_build_object('email', public.current_email(), 'role', null))
$$;

-- ─────────────── Διαχείριση πίνακα (μόνο ΓΔ) ───────────────
create or replace function public.permissions_matrix()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('permissions.manage');
  return jsonb_build_object(
    'permissions', (select jsonb_agg(jsonb_build_object('code', code, 'module', module, 'label', label, 'description', description, 'fixed_roles', fixed_roles) order by sort) from public.permissions),
    'grants', (select jsonb_object_agg(role, perms) from (select role, jsonb_object_agg(perm, public.role_has_perm(role, perm)) perms from public.role_permissions group by role) x),
    'scopes', (select jsonb_object_agg(role, scope) from public.role_scopes),
    'log', (select coalesce(jsonb_agg(to_jsonb(l) order by l.at desc), '[]') from (select * from public.permission_log order by at desc limit 300) l));
end $$;

-- p_changes: [{ "role": "hr", "perm": "payroll.pdf", "allowed": true }] · p_scopes: { "trainer": "all" }
create or replace function public.permissions_save(p_changes jsonb, p_scopes jsonb, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c jsonb; v_old boolean; v_new boolean; p public.permissions; v_n int := 0; k text; v_old_s text;
begin
  perform public.require_perm('permissions.manage');
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'Γράψτε σύντομη αιτιολογία για την αλλαγή δικαιωμάτων.'; end if;
  for c in select * from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) loop
    select * into p from public.permissions where code = c->>'perm';
    if not found then raise exception 'Άγνωστο δικαίωμα %.', c->>'perm'; end if;
    if (c->>'role') not in ('owner','hr','accounting','manager','trainer') then raise exception 'Άγνωστος ρόλος.'; end if;
    v_new := (c->>'allowed')::boolean;
    if p.fixed_roles is not null then
      if v_new is distinct from ((c->>'role') = any(p.fixed_roles)) then raise exception 'Το δικαίωμα «%» δεν αλλάζει από τον πίνακα.', p.label; end if;
      continue;
    end if;
    -- Προστασία: η ΓΔ δεν αφαιρεί από τον εαυτό της τη διαχείριση χρηστών
    if c->>'role' = 'owner' and p.code = 'users.manage' and not v_new then
      raise exception 'Η Γενική Διεύθυνση δεν μπορεί να χάσει τη διαχείριση χρηστών (προστασία από απώλεια πρόσβασης).';
    end if;
    select allowed into v_old from public.role_permissions where role = c->>'role' and perm = p.code for update;
    continue when v_old is not distinct from v_new;
    update public.role_permissions set allowed = v_new, updated_by = public.current_email(), updated_at = now() where role = c->>'role' and perm = p.code;
    insert into public.permission_log(actor, role, perm, old_value, new_value, note)
    values (public.current_email(), c->>'role', p.code, v_old::text, v_new::text, trim(p_note));
    v_n := v_n + 1;
  end loop;
  for k in select * from jsonb_object_keys(coalesce(p_scopes, '{}'::jsonb)) loop
    select scope into v_old_s from public.role_scopes where role = k for update;
    if not found then raise exception 'Άγνωστος ρόλος.'; end if;
    continue when v_old_s = p_scopes->>k;
    if k = 'owner' then raise exception 'Η Γενική Διεύθυνση έχει πάντα πρόσβαση σε όλα τα καταστήματα.'; end if;
    if (p_scopes->>k) not in ('all','own_store','assigned') then raise exception 'Μη έγκυρο πεδίο καταστημάτων.'; end if;
    update public.role_scopes set scope = p_scopes->>k, updated_by = public.current_email(), updated_at = now() where role = k;
    insert into public.permission_log(actor, role, perm, old_value, new_value, note) values (public.current_email(), k, null, v_old_s, p_scopes->>k, trim(p_note));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'changed', v_n);
end $$;

-- ─────────────── Χρήστες: ο ρόλος του λογιστηρίου ───────────────
-- Ο manager χρειάζεται κατάστημα (υπάρχων κανόνας). Το λογιστήριο/HR/εκπαιδευτής δεν δένονται σε κατάστημα.

-- ═══════════════ Υπάρχουσες συναρτήσεις: ίδια λογική, έλεγχος με τον πίνακα δικαιωμάτων ═══════════════
create or replace function public.prepare_declarations(p_month text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.my_role();
  v_store text := public.my_store();
  r jsonb; e record; d record;
  v_amount numeric; v_period text; v_end date;
  v_first date; v_last date;
  v_created int := 0; v_updated int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  perform public.require_perm('payroll.prepare');
  if p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Μη έγκυρος μήνας.'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 2000 then
    raise exception 'Δεν υπάρχουν γραμμές για καταχώριση.';
  end if;
  v_first := to_date(p_month || '-01', 'YYYY-MM-DD');
  v_last  := (v_first + interval '1 month' - interval '1 day')::date;

  for r in select * from jsonb_array_elements(p_rows) loop
    select * into e from public.employees where code = trim(r ->> 'code');
    if not found then
      v_skipped := v_skipped || jsonb_build_object('code', r ->> 'code', 'reason', 'Άγνωστος κωδικός'); continue;
    end if;
    if e.status <> 'Ενεργός' then
      v_skipped := v_skipped || jsonb_build_object('code', e.code, 'reason', 'Ανενεργός εργαζόμενος'); continue;
    end if;
    if not public.can_see_store(e.store) then
      v_skipped := v_skipped || jsonb_build_object('code', e.code, 'reason', 'Άλλο κατάστημα'); continue;
    end if;
    begin
      v_amount := replace(replace(trim(r ->> 'amount'), '.', ''), ',', '.')::numeric;
      if trim(r ->> 'amount') ~ '^\d+\.\d{1,2}$' then v_amount := trim(r ->> 'amount')::numeric; end if;
    exception when others then v_amount := null; end;
    if v_amount is null or v_amount < 0 or v_amount >= 1000000 then
      v_skipped := v_skipped || jsonb_build_object('code', e.code, 'reason', 'Μη έγκυρο ποσό'); continue;
    end if;
    v_period := coalesce(nullif(trim(r ->> 'period'), ''), to_char(v_first, 'DD/MM/YYYY') || ' – ' || to_char(v_last, 'DD/MM/YYYY'));
    begin
      v_end := coalesce(nullif(trim(r ->> 'end_date'), '')::date, v_last);
    exception when others then
      v_skipped := v_skipped || jsonb_build_object('code', e.code, 'reason', 'Μη έγκυρη ημερομηνία'); continue;
    end;

    select * into d from public.declarations where employee_code = e.code and month = p_month and status <> 'voided';
    if found then
      if d.status = 'signed' then
        v_skipped := v_skipped || jsonb_build_object('code', e.code, 'reason', 'Έχει ήδη υπογράψει'); continue;
      end if;
      update public.declarations
         set amount = v_amount, period = v_period, end_date = v_end,
             employee_name = e.first || ' ' || e.last, store = e.store, company = e.company,
             prepared_by = public.current_email(), prepared_at = now()
       where id = d.id;
      v_updated := v_updated + 1;
    else
      insert into public.declarations(employee_code, employee_name, store, company, month, end_date, period, amount, prepared_by)
      values (e.code, e.first || ' ' || e.last, e.store, e.company, p_month, v_end, v_period, v_amount, public.current_email());
      v_created := v_created + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end $$;

create or replace function public.sign_declaration(p_id uuid, p_signer text, p_signature text, p_device text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.my_role();
  d record;
begin
  if not public.has_perm('payroll.sign') then raise exception 'Δεν επιτρέπεται η υπογραφή από αυτόν τον λογαριασμό.'; end if;
  select * into d from public.declarations where id = p_id for update;
  if not found then raise exception 'Η δήλωση δεν βρέθηκε.'; end if;
  if not public.can_see_store(d.store) then raise exception 'Η δήλωση ανήκει σε άλλο κατάστημα.'; end if;
  if d.status <> 'pending' then raise exception 'Η δήλωση έχει ήδη υπογραφεί ή ακυρωθεί.'; end if;
  if not exists (select 1 from public.employees where code = d.employee_code and status = 'Ενεργός') then
    raise exception 'Ο εργαζόμενος δεν είναι ενεργός.';
  end if;
  if length(trim(coalesce(p_signer, ''))) < 3 or length(p_signer) > 150 then raise exception 'Συμπληρώστε ονοματεπώνυμο.'; end if;
  if p_signature !~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' or length(p_signature) > 600000 or length(p_signature) < 1500 then
    raise exception 'Η υπογραφή λείπει ή δεν είναι έγκυρη.';
  end if;
  update public.declarations set
    status = 'signed',
    statement = public.statement_text(d.company, d.end_date, d.period, d.amount),
    signer = trim(p_signer), signature = p_signature,
    signed_at = now(), signed_by = public.current_email(), device = left(p_device, 300)
  where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id);
end $$;

create or replace function public.void_declaration(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.has_perm('payroll.void') then raise exception 'Δεν έχετε δικαίωμα ακύρωσης δήλωσης.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Γράψτε αιτιολογία ακύρωσης.'; end if;
  update public.declarations set status = 'voided', voided_by = public.current_email(), voided_at = now(), void_reason = trim(p_reason)
   where id = p_id and status <> 'voided';
  if not found then raise exception 'Η δήλωση δεν βρέθηκε.'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.discard_pending(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.declarations where id = p_id;
  if not found or d.status <> 'pending' then raise exception 'Μόνο δηλώσεις προς υπογραφή μπορούν να αφαιρεθούν.'; end if;
  if not (public.has_perm('payroll.prepare') and public.can_see_store(d.store)) then
    raise exception 'Δεν επιτρέπεται.';
  end if;
  update public.declarations set status = 'voided', voided_by = public.current_email(), voided_at = now(),
         void_reason = 'Αφαίρεση προετοιμασμένης δήλωσης' where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.template_save(p_key text, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_next int; v_id bigint;
begin
  perform public.require_perm('templates.manage');
  if not exists (select 1 from public.text_templates where key = p_key) then raise exception 'Άγνωστο πρότυπο.'; end if;
  if length(trim(coalesce(p_body,''))) < 3 then raise exception 'Το κείμενο είναι κενό.'; end if;
  if trim(p_body) = (select body from public.text_template_versions where key = p_key order by version desc limit 1) then
    raise exception 'Δεν υπάρχει αλλαγή στο κείμενο.';
  end if;
  select coalesce(max(version), 0) + 1 into v_next from public.text_template_versions where key = p_key;
  insert into public.text_template_versions(key, version, body, created_by)
  values (p_key, v_next, trim(p_body), public.current_email()) returning id into v_id;
  return jsonb_build_object('id', v_id, 'version', v_next);
end $$;

create or replace function public.req_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_perm('requests.create');
  v_cat text := p->>'category'; v_mode text := p->>'entry_mode';
  e public.employees; v_id uuid; v_ref text; v_process text; v_written text;
begin
  if v_cat is null or public.req_category_label(v_cat) = v_cat then raise exception 'Άγνωστη κατηγορία.'; end if;
  select * into e from public.employees where code = trim(p->>'employee_code');
  if not found or not public.employee_in_scope(e.code) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if e.status <> 'Ενεργός' then raise exception 'Ο εργαζόμενος είναι ανενεργός.'; end if;
  v_process := case when v_cat in ('negative_review','incident','warning_request') then 'manager' else 'employee' end;
  if v_process = 'employee' and coalesce(v_mode,'') not in ('manager_record','employee_fill') then
    raise exception 'Επιλέξτε «Καταγραφή από manager» ή «Συμπλήρωση από εργαζόμενο».';
  end if;
  if v_process = 'manager' then v_mode := null; end if;
  v_written := case when v_mode = 'employee_fill' then null else public.current_email() end;
  v_ref := 'ΑΙ-' || to_char(public.athens_today(), 'YYYY') || '-' || lpad(nextval('public.hr_request_no')::text, 5, '0');
  insert into public.hr_requests(ref, process, category, employee_code, employee_name, store, company, specialty,
         entry_mode, stated_by, written_by, written_at, created_by)
  values (v_ref, v_process, v_cat, e.code, e.first || ' ' || e.last, e.store, e.company, e.specialty,
         v_mode, case when v_process = 'employee' then 'employee:' || e.code else public.current_email() end,
         v_written, case when v_written is not null then now() end, public.current_email())
  returning id into v_id;
  perform public.req_apply_fields(v_id, p, false);
  update public.hr_requests set version = 1 where id = v_id;
  perform public.req_event(v_id, 'create', null, 'draft', null,
    jsonb_build_object('category', v_cat, 'entry_mode', v_mode));
  return jsonb_build_object('id', v_id, 'ref', v_ref, 'version', 1);
end $$;

create or replace function public.req_update_draft(p_id uuid, p jsonb, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.create');
  r := public.req_lock(p_id, p_version);
  if r.status <> 'draft' then raise exception 'Μόνο πρόχειρα αιτήματα αλλάζουν.'; end if;
  if r.written_by like 'employee:%' or (r.entry_mode = 'employee_fill') then
    -- Το κείμενο του εργαζομένου δεν αλλάζει από τον manager· επιτρέπεται μόνο η χωριστή εισήγησή του
    p := jsonb_strip_nulls(jsonb_build_object('manager_note', p->'manager_note'));
  end if;
  perform public.req_apply_fields(p_id, p, false);
  if r.entry_mode = 'manager_record' or r.process = 'manager' then
    update public.hr_requests set written_by = public.current_email(), written_at = now() where id = p_id;
  end if;
  return jsonb_build_object('ok', true, 'version', r.version + 1);
end $$;

create or replace function public.req_submit(p_id uuid, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.create');
  r := public.req_lock(p_id, p_version);
  if r.status <> 'draft' then raise exception 'Το αίτημα έχει ήδη υποβληθεί.'; end if;
  if exists (select 1 from public.fill_sessions where request_id = p_id and completed_at is null and cancelled_at is null and expires_at > now()) then
    raise exception 'Η φόρμα του εργαζομένου είναι ακόμη ανοιχτή. Ολοκληρώστε ή ακυρώστε τη συμπλήρωση πρώτα.';
  end if;
  perform public.req_validate(r);
  update public.hr_requests set status = 'submitted', submitted_by = public.current_email(), submitted_at = now(),
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'submit', 'draft', 'submitted', null);
  return jsonb_build_object('ok', true, 'status', 'submitted', 'version', r.version + 1);
end $$;

create or replace function public.req_provide_info(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_to text;
begin
  perform public.require_perm('requests.create');
  r := public.req_lock(p_id, p_version);
  if r.status <> 'needs_info' then raise exception 'Το αίτημα δεν περιμένει διευκρινίσεις.'; end if;
  if length(trim(coalesce(p_note,''))) < 3 then raise exception 'Γράψτε τις διευκρινίσεις.'; end if;
  v_to := case when r.assignee is null then 'submitted' else 'under_review' end;
  update public.hr_requests set status = v_to, updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'info_provided', 'needs_info', v_to, p_note);
  return jsonb_build_object('ok', true, 'status', v_to, 'version', r.version + 1);
end $$;

create or replace function public.req_delete_draft(p_id uuid, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.create');
  r := public.req_lock(p_id, p_version);
  if r.status <> 'draft' then raise exception 'Μόνο πρόχειρα διαγράφονται. Τα υποβληθέντα αιτήματα μένουν στο ιστορικό.'; end if;
  if not public.has_perm('requests.decide') and r.created_by <> public.current_email() then raise exception 'Διαγράφει μόνο όποιος δημιούργησε το πρόχειρο.'; end if;
  insert into public.audit_log(actor, action, entity, entity_id, details)
  values (public.current_email(), 'delete', 'hr_requests', r.ref, jsonb_build_object('label', r.employee_name, 'category', r.category, 'store', r.store));
  delete from public.fill_sessions where request_id = p_id;
  delete from public.hr_requests where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.req_assign(p_id uuid, p_email text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_to text := lower(trim(coalesce(p_email, public.current_email())));
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, p_version);
  if r.status in ('draft','completed') then raise exception 'Δεν ανατίθεται σε αυτή την κατάσταση.'; end if;
  if not exists (select 1 from public.app_users where email = v_to and active and role in ('owner','hr')) then
    raise exception 'Ο υπεύθυνος πρέπει να είναι ενεργός χρήστης HR ή η ΓΔ.';
  end if;
  update public.hr_requests set assignee = v_to,
         status = case when status = 'submitted' then 'under_review' else status end,
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'assign', r.status, case when r.status = 'submitted' then 'under_review' else r.status end, null, jsonb_build_object('assignee', v_to));
  return jsonb_build_object('ok', true, 'version', r.version + 1);
end $$;

create or replace function public.req_forward_gm(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, p_version);
  if public.req_flow(r.category) <> 'gm' then raise exception 'Η προώθηση αφορά αυξήσεις και αλλαγές σύμβασης.'; end if;
  if r.status not in ('submitted','under_review') then raise exception 'Δεν προωθείται σε αυτή την κατάσταση.'; end if;
  if length(trim(coalesce(p_note,''))) < 5 then raise exception 'Γράψτε την εισήγηση του HR.'; end if;
  insert into public.hr_request_internal(request_id, hr_note, hr_note_by, hr_note_at)
  values (p_id, trim(p_note), public.current_email(), now())
  on conflict (request_id) do update set hr_note = excluded.hr_note, hr_note_by = excluded.hr_note_by, hr_note_at = excluded.hr_note_at;
  update public.hr_requests set status = 'awaiting_gm', assignee = coalesce(assignee, public.current_email()),
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'forward_gm', r.status, 'awaiting_gm', p_note, null, true);
  return jsonb_build_object('ok', true, 'version', r.version + 1);
end $$;

create or replace function public.req_warning_draft(p_id uuid, p_text text, p_send boolean, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_to text;
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, p_version);
  if r.category <> 'warning_request' then raise exception 'Αφορά μόνο αιτήματα έγγραφης προειδοποίησης.'; end if;
  if r.status not in ('submitted','under_review','awaiting_gm') then raise exception 'Το προσχέδιο δεν αλλάζει σε αυτή την κατάσταση.'; end if;
  if length(trim(coalesce(p_text,''))) < 20 then raise exception 'Το προσχέδιο είναι πολύ σύντομο.'; end if;
  insert into public.hr_request_internal(request_id, warning_draft, warning_draft_by, warning_draft_at)
  values (p_id, trim(p_text), public.current_email(), now())
  on conflict (request_id) do update set warning_draft = excluded.warning_draft, warning_draft_by = excluded.warning_draft_by, warning_draft_at = excluded.warning_draft_at;
  v_to := case when p_send then 'awaiting_gm' when r.status = 'submitted' then 'under_review' else r.status end;
  update public.hr_requests set status = v_to, assignee = coalesce(assignee, public.current_email()),
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, case when p_send then 'warning_draft_sent' else 'warning_draft_saved' end, r.status, v_to, null, null, true);
  return jsonb_build_object('ok', true, 'status', v_to, 'version', r.version + 1);
end $$;

create or replace function public.req_mark_notified(p_id uuid, p_at timestamptz, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_at timestamptz := coalesce(p_at, now()); v_dec timestamptz;
begin
  perform public.require_perm('requests.create', 'requests.decide', 'requests.implement');
  r := public.req_lock(p_id, p_version);
  if r.category = 'warning_request' then raise exception 'Η κοινοποίηση προειδοποίησης γίνεται από το HR.'; end if;
  if r.status not in ('approved','rejected','needs_info') then raise exception 'Δεν υπάρχει απόφαση για ενημέρωση.'; end if;
  select decided_at into v_dec from public.hr_decisions where request_id = p_id and superseded_at is null;
  if v_at < v_dec - interval '1 minute' or v_at > now() + interval '5 minutes' then
    raise exception 'Η ώρα ενημέρωσης πρέπει να είναι μετά την απόφαση και όχι στο μέλλον.';
  end if;
  update public.hr_requests set notified_at = v_at, notified_by = public.current_email(), notify_note = nullif(trim(p_note),''),
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'notified', r.status, r.status, p_note, jsonb_build_object('at', v_at));
  return jsonb_build_object('ok', true, 'version', r.version + 1);
end $$;

create or replace function public.req_attach(p_id uuid, p_filename text, p_mime text, p_data text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_id uuid; v_size int;
begin
  perform public.require_perm('requests.create', 'requests.decide', 'requests.implement');
  r := public.req_lock(p_id, null);
  if r.status = 'completed' then raise exception 'Το αίτημα έχει ολοκληρωθεί.'; end if;
  if not public.has_perm('requests.decide') and r.status not in ('draft','needs_info') then
    raise exception 'Συνημμένα από manager προστίθενται στο πρόχειρο ή όταν ζητούνται διευκρινίσεις.';
  end if;
  return public.attach_file(p_id, p_filename, p_mime, p_data, public.current_email());
end $$;

create or replace function public.hr_handlers()
returns table (email text, name text, role text)
language sql stable security definer set search_path = public as $$
  select email, name, role from public.app_users
   where active and public.role_has_perm(role, 'requests.decide') and public.has_perm('requests.decide')
   order by role desc, name
$$;

create or replace function public.stats_save(p_date date, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_perm('stats.entry');
  r jsonb; e public.employees; v_kind text; v_out jsonb := '[]'::jsonb; s public.daily_stats;
  v_new jsonb; v_old jsonb; f text; v_vals jsonb;
begin
  if p_date is null or p_date > public.athens_today() then raise exception 'Η ημερομηνία δεν μπορεί να είναι μελλοντική.'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'Μη έγκυρα δεδομένα.'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    begin
      select * into e from public.employees where code = r->>'employee_code';
      if not found then raise exception 'Άγνωστος κωδικός εργαζομένου.'; end if;
      if r ? 'id' and nullif(r->>'id','') is not null then
        select * into s from public.daily_stats where id = (r->>'id')::bigint for update;
        if not found then raise exception 'Η καταχώριση δεν βρέθηκε.'; end if;
        if not public.can_see_store(s.store) then raise exception 'Η καταχώριση ανήκει σε άλλο κατάστημα.'; end if;
        if s.version <> coalesce((r->>'version')::int, -1) then raise exception 'Η καταχώριση άλλαξε από άλλον χρήστη. Ανανεώστε.'; end if;
        v_vals := '{}'::jsonb;
        foreach f in array public.stats_fields(s.kind) loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop;
        v_old := (select jsonb_object_agg(k, to_jsonb(s) -> k) from unnest(public.stats_fields(s.kind)) k);
        if v_old = v_vals then v_out := v_out || jsonb_build_object('employee_code', e.code, 'ok', true, 'id', s.id, 'unchanged', true); continue; end if;
        update public.daily_stats set
          dr = (v_vals->>'dr')::int, lost = (v_vals->>'lost')::int, cb = (v_vals->>'cb')::int,
          trials_sent = (v_vals->>'trials_sent')::int, trials_attended = (v_vals->>'trials_attended')::int,
          trials_enrolled = (v_vals->>'trials_enrolled')::int, trials_done = (v_vals->>'trials_done')::int,
          enr_fitness = (v_vals->>'enr_fitness')::int, enr_body = (v_vals->>'enr_body')::int, enr_muscle = (v_vals->>'enr_muscle')::int,
          enr_pilates = (v_vals->>'enr_pilates')::int, enr_from_trials = (v_vals->>'enr_from_trials')::int,
          updated_by = public.current_email(), updated_at = now(), version = version + 1
        where id = s.id;
        insert into public.daily_stats_history(stats_id, changed_by, old_values, new_values) values (s.id, public.current_email(), v_old, v_vals);
        v_out := v_out || jsonb_build_object('employee_code', e.code, 'ok', true, 'id', s.id, 'updated', true);
      else
        if not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν ανήκει στο κατάστημά σας.'; end if;
        if e.status <> 'Ενεργός' then raise exception 'Ανενεργός εργαζόμενος.'; end if;
        select stat_kind into v_kind from public.specialties where name = e.specialty;
        if v_kind is null then raise exception 'Η ειδικότητα του εργαζομένου δεν έχει στατιστικά.'; end if;
        v_vals := '{}'::jsonb;
        foreach f in array public.stats_fields(v_kind) loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop;
        if exists (select 1 from public.daily_stats where employee_code = e.code and stat_date = p_date and store = e.store and specialty = e.specialty) then
          raise exception 'Υπάρχει ήδη καταχώριση για αυτή την ημέρα. Ανοίξτε την για διόρθωση.';
        end if;
        insert into public.daily_stats(employee_code, stat_date, store, specialty, kind,
          dr, lost, cb, trials_sent, trials_attended, trials_enrolled, trials_done, enr_fitness, enr_body, enr_muscle, enr_pilates, enr_from_trials, created_by)
        values (e.code, p_date, e.store, e.specialty, v_kind,
          (v_vals->>'dr')::int, (v_vals->>'lost')::int, (v_vals->>'cb')::int, (v_vals->>'trials_sent')::int,
          (v_vals->>'trials_attended')::int, (v_vals->>'trials_enrolled')::int, (v_vals->>'trials_done')::int,
          (v_vals->>'enr_fitness')::int, (v_vals->>'enr_body')::int, (v_vals->>'enr_muscle')::int,
          (v_vals->>'enr_pilates')::int, (v_vals->>'enr_from_trials')::int, public.current_email())
        returning * into s;
        v_out := v_out || jsonb_build_object('employee_code', e.code, 'ok', true, 'id', s.id, 'created', true);
      end if;
    exception when others then
      v_out := v_out || jsonb_build_object('employee_code', r->>'employee_code', 'ok', false, 'error',
        case when sqlerrm like '%unique%' or sqlerrm like '%duplicate%' then 'Υπάρχει ήδη καταχώριση για αυτή την ημέρα.' else sqlerrm end);
    end;
  end loop;
  return jsonb_build_object('rows', v_out);
end $$;

create or replace function public.q_update_meta(p_id uuid, p_title text, p_description text, p_specialties text[], p_participants text[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('assess.manage');
  if exists (select 1 from unnest(coalesce(p_specialties, '{}')) s where not exists (select 1 from public.specialties where name = s)) then
    raise exception 'Άγνωστη ειδικότητα.';
  end if;
  if exists (select 1 from unnest(coalesce(p_participants, '{}')) c where not exists (select 1 from public.employees where code = c)) then
    raise exception 'Άγνωστος κωδικός συμμετέχοντα.';
  end if;
  update public.questionnaires set title = trim(p_title), description = nullif(trim(p_description),''),
         specialties = coalesce(p_specialties, '{}'), participants = nullif(p_participants, '{}'), updated_at = now()
   where id = p_id;
  if not found then raise exception 'Το ερωτηματολόγιο δεν βρέθηκε.'; end if;
  if exists (select 1 from public.questionnaires q where q.id = p_id and q.status = 'active' and (
       cardinality(q.specialties) = 0 or exists (select 1 from unnest(q.specialties) s where not exists (
         select 1 from public.assessment_questions x where x.version_id = q.current_version_id and (x.specialty is null or x.specialty = s))))) then
    raise exception 'Το ενεργό ερωτηματολόγιο δεν έχει ερωτήσεις για κάποια από τις ειδικότητες που επιλέξατε.';
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.q_set_multi_rule(p_id uuid, p_rule text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ver uuid;
begin
  perform public.require_perm('assess.manage');
  if p_rule is not null and p_rule not in ('all_or_nothing','partial') then raise exception 'Μη έγκυρος κανόνας.'; end if;
  v_ver := public.q_draft_version(p_id);
  update public.questionnaire_versions set multi_rule = p_rule where id = v_ver;
  return jsonb_build_object('ok', true, 'version_id', v_ver);
end $$;

create or replace function public.q_set_window(p_id uuid, p_starts text, p_ends text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare q public.questionnaires; v_s timestamptz := public.athens_ts(p_starts); v_e timestamptz := public.athens_ts(p_ends);
begin
  perform public.require_perm('assess.manage');
  select * into q from public.questionnaires where id = p_id for update;
  if not found then raise exception 'Το ερωτηματολόγιο δεν βρέθηκε.'; end if;
  if v_s is null or v_e is null then raise exception 'Συμπληρώστε έναρξη και λήξη.'; end if;
  if v_e <= v_s then raise exception 'Η λήξη πρέπει να είναι μετά την έναρξη.'; end if;
  if q.starts_at is not distinct from v_s and q.ends_at is not distinct from v_e then return jsonb_build_object('ok', true, 'unchanged', true); end if;
  update public.questionnaires set starts_at = v_s, ends_at = v_e, updated_at = now() where id = p_id;
  insert into public.questionnaire_window_log(questionnaire_id, actor, old_starts, old_ends, new_starts, new_ends, note)
  values (p_id, public.current_email(), q.starts_at, q.ends_at, v_s, v_e, nullif(trim(p_note),''));
  return jsonb_build_object('ok', true, 'starts_at', v_s, 'ends_at', v_e);
end $$;

create or replace function public.q_publish(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_errs jsonb; v public.questionnaire_versions;
begin
  perform public.require_perm('assess.manage');
  perform 1 from public.questionnaires where id = p_id for update;
  if not found then raise exception 'Το ερωτηματολόγιο δεν βρέθηκε.'; end if;
  select * into v from public.questionnaire_versions where questionnaire_id = p_id order by version desc limit 1;
  v_errs := public.q_check(p_id);
  if jsonb_array_length(v_errs) > 0 then return jsonb_build_object('ok', false, 'errors', v_errs); end if;
  if v.status = 'draft' then
    update public.questionnaire_versions set status = 'retired' where questionnaire_id = p_id and status = 'published';
    update public.questionnaire_versions set status = 'published', published_at = now(), published_by = public.current_email() where id = v.id;
  end if;
  update public.questionnaires set status = 'active', current_version_id = v.id, updated_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'version', v.version);
end $$;

create or replace function public.q_close(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('assess.manage');
  update public.questionnaires set status = 'closed', updated_at = now() where id = p_id and status = 'active';
  if not found then raise exception 'Το ερωτηματολόγιο δεν είναι ενεργό.'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.link_create(p_qid uuid, p_codes text[], p_starts text, p_ends text, p_reassess boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q public.questionnaires; e public.employees; prev public.assessment_attempts; g public.assessment_assignments;
  v_s timestamptz := public.athens_ts(p_starts); v_e timestamptz := public.athens_ts(p_ends);
  v_code text; v_token text; v_ver uuid; v_round int; v_out jsonb := '[]'::jsonb; v_n int := 0;
begin
  perform public.require_perm('assess.manage');
  select * into q from public.questionnaires where id = p_qid for update;
  if not found or q.status <> 'active' or q.current_version_id is null then raise exception 'Το ερωτηματολόγιο πρέπει να είναι ενεργό.'; end if;
  if v_s is null or v_e is null then raise exception 'Συμπληρώστε έναρξη και λήξη διαθεσιμότητας.'; end if;
  if v_e <= v_s then raise exception 'Η λήξη πρέπει να είναι μετά την έναρξη.'; end if;
  if v_e <= now() then raise exception 'Η λήξη έχει ήδη περάσει.'; end if;
  if coalesce(cardinality(p_codes), 0) = 0 then raise exception 'Επιλέξτε συμμετέχοντες.'; end if;
  if cardinality(p_codes) > 500 then raise exception 'Έως 500 εργαζόμενοι ανά δημιουργία.'; end if;
  foreach v_code in array (select array_agg(distinct c) from unnest(p_codes) c) loop
    begin
      select * into e from public.employees where code = v_code;
      if not found then raise exception 'Ο κωδικός δεν βρέθηκε.'; end if;
      if e.status <> 'Ενεργός' then raise exception 'Ο εργαζόμενος είναι ανενεργός.'; end if;
      if e.specialty is null or not (e.specialty = any(q.specialties)) then raise exception 'Το ερωτηματολόγιο δεν αφορά την ειδικότητα του εργαζομένου.'; end if;
      if exists (select 1 from public.assessment_assignments where questionnaire_id = p_qid and employee_code = v_code and status = 'active' and completed_at is null) then
        raise exception 'Υπάρχει ήδη ενεργός σύνδεσμος. Χρησιμοποιήστε «Αντιγραφή» ή «Επανέκδοση».';
      end if;
      if exists (select 1 from public.assessment_attempts where questionnaire_id = p_qid and employee_code = v_code and status <> 'in_progress') and not coalesce(p_reassess, false) then
        raise exception 'Έχει ήδη υποβάλει αυτή την αξιολόγηση. Για νέα αξιολόγηση επιλέξτε «Επαναξιολόγηση».';
      end if;
      -- Μισή συμπλήρωση από την υπάρχουσα ροή: συνεχίζει μέσω του συνδέσμου, με τις απαντήσεις της
      select * into prev from public.assessment_attempts where questionnaire_id = p_qid and employee_code = v_code and assignment_id is null and status = 'in_progress' for update;
      v_ver := coalesce(prev.version_id, q.current_version_id);
      select count(*) + 1 into v_round from public.assessment_attempts where questionnaire_id = p_qid and employee_code = v_code and status <> 'in_progress';
      v_token := public.fill_new_token();
      insert into public.assessment_assignments(questionnaire_id, version_id, employee_code, employee_name, store, specialty, company,
             starts_at, ends_at, token_hash, round, created_by)
      values (p_qid, v_ver, e.code, e.first || ' ' || e.last, e.store, coalesce(prev.specialty, e.specialty), e.company,
             v_s, v_e, public.fill_hash(v_token), v_round, public.current_email())
      returning * into g;
      insert into public.assessment_link_secrets(assignment_id, token) values (g.id, v_token);
      if prev.id is not null then
        update public.assessment_attempts set assignment_id = g.id, due_at = g.ends_at where id = prev.id;
        update public.fill_sessions set cancelled_at = now(), cancelled_by = public.current_email()
         where attempt_id = prev.id and completed_at is null and cancelled_at is null;
      end if;
      perform public.link_event(g.id, public.current_email(), 'created', jsonb_build_object('starts_at', v_s, 'ends_at', v_e,
        'version', (select version from public.questionnaire_versions where id = v_ver), 'round', v_round, 'continued_attempt', prev.id is not null));
      v_n := v_n + 1;
      v_out := v_out || jsonb_build_object('employee_code', e.code, 'employee_name', g.employee_name, 'store', g.store, 'ok', true,
                                           'assignment_id', g.id, 'token', v_token, 'round', v_round);
    exception when others then
      v_out := v_out || jsonb_build_object('employee_code', v_code, 'employee_name', (select first || ' ' || last from public.employees where code = v_code),
        'ok', false, 'error', case when sqlerrm like '%one_open%' or sqlerrm like '%duplicate%' then 'Υπάρχει ήδη ενεργός σύνδεσμος.' else sqlerrm end);
    end;
  end loop;
  return jsonb_build_object('created', v_n, 'rows', v_out);
end $$;

create or replace function public.link_reissue(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments; v_token text := public.fill_new_token();
begin
  perform public.require_perm('assess.manage');
  select * into g from public.assessment_assignments where id = p_id for update;
  if not found then raise exception 'Η ανάθεση δεν βρέθηκε.'; end if;
  if g.completed_at is not null or exists (select 1 from public.assessment_attempts where assignment_id = g.id and status <> 'in_progress') then
    raise exception 'Η αξιολόγηση έχει ήδη υποβληθεί· ο σύνδεσμος δεν επανεκδίδεται. Για νέα αξιολόγηση δημιουργήστε νέα ανάθεση (Επαναξιολόγηση).';
  end if;
  if g.status = 'cancelled' and exists (select 1 from public.assessment_assignments where questionnaire_id = g.questionnaire_id and employee_code = g.employee_code
       and status = 'active' and completed_at is null and id <> g.id) then
    raise exception 'Υπάρχει ήδη άλλος ενεργός σύνδεσμος για τον εργαζόμενο σε αυτή την αξιολόγηση.';
  end if;
  update public.assessment_assignments set token_hash = public.fill_hash(v_token), link_no = link_no + 1, status = 'active', cancelled_at = null, cancelled_by = null
   where id = g.id;
  insert into public.assessment_link_secrets(assignment_id, token) values (g.id, v_token)
    on conflict (assignment_id) do update set token = excluded.token;
  perform public.link_event(g.id, public.current_email(), 'reissued', jsonb_build_object('link_no', g.link_no + 1, 'was_cancelled', g.status = 'cancelled'));
  return jsonb_build_object('ok', true, 'token', v_token, 'link_no', g.link_no + 1);
end $$;

create or replace function public.link_cancel(p_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments;
begin
  perform public.require_perm('assess.manage');
  select * into g from public.assessment_assignments where id = p_id for update;
  if not found then raise exception 'Η ανάθεση δεν βρέθηκε.'; end if;
  if g.completed_at is not null then raise exception 'Η αξιολόγηση έχει ήδη υποβληθεί· δεν υπάρχει ενεργός σύνδεσμος για ακύρωση.'; end if;
  if g.status = 'cancelled' then return jsonb_build_object('ok', true, 'already', true); end if;
  update public.assessment_assignments set status = 'cancelled', token_hash = null, cancelled_at = now(), cancelled_by = public.current_email() where id = g.id;
  delete from public.assessment_link_secrets where assignment_id = g.id;
  perform public.link_event(g.id, public.current_email(), 'cancelled', jsonb_build_object('link_no', g.link_no, 'note', nullif(trim(p_note), '')));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.link_set_window(p_ids uuid[], p_starts text, p_ends text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments; v_s timestamptz := public.athens_ts(p_starts); v_e timestamptz := public.athens_ts(p_ends); v_n int := 0;
begin
  perform public.require_perm('assess.manage');
  if v_s is null or v_e is null then raise exception 'Συμπληρώστε έναρξη και λήξη.'; end if;
  if v_e <= v_s then raise exception 'Η λήξη πρέπει να είναι μετά την έναρξη.'; end if;
  if coalesce(cardinality(p_ids), 0) = 0 then raise exception 'Επιλέξτε αναθέσεις.'; end if;
  if not exists (select 1 from public.assessment_assignments where id = any(p_ids)) then raise exception 'Η ανάθεση δεν βρέθηκε.'; end if;
  for g in select * from public.assessment_assignments where id = any(p_ids) order by id for update loop
    if g.completed_at is not null then raise exception 'Η αξιολόγηση του/της % έχει ήδη υποβληθεί· η διαθεσιμότητά της δεν αλλάζει.', g.employee_name; end if;
    continue when g.starts_at = v_s and g.ends_at = v_e;
    update public.assessment_assignments set starts_at = v_s, ends_at = v_e where id = g.id;
    update public.assessment_attempts set due_at = v_e where assignment_id = g.id;
    perform public.link_event(g.id, public.current_email(), 'window_changed', jsonb_build_object(
      'old_starts', g.starts_at, 'old_ends', g.ends_at, 'new_starts', v_s, 'new_ends', v_e, 'note', nullif(trim(p_note), '')));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'changed', v_n);
end $$;

create or replace function public.assessment_links(p_qid uuid)
returns table (id uuid, employee_code text, employee_name text, store text, specialty text, version int, round int, link_no int,
               starts_at timestamptz, ends_at timestamptz, state text, token text, created_by text, created_at timestamptz,
               opened_at timestamptz, last_saved_at timestamptz, submitted_at timestamptz, cancelled_at timestamptz, attempt_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('assess.manage');
  return query
  select g.id, g.employee_code, g.employee_name, g.store, g.specialty, v.version, g.round, g.link_no, g.starts_at, g.ends_at,
         public.link_state(g, a), case when g.status = 'active' and g.completed_at is null then s.token end,
         g.created_by, g.created_at, a.started_at, a.last_saved_at, a.submitted_at, g.cancelled_at, a.id
    from public.assessment_assignments g
    join public.questionnaire_versions v on v.id = g.version_id
    left join public.assessment_attempts a on a.assignment_id = g.id
    left join public.assessment_link_secrets s on s.assignment_id = g.id
   where g.questionnaire_id = p_qid
   order by g.store, g.employee_name, g.created_at;
end $$;

create or replace function public.q_key_begin(p_qid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ver uuid;
begin
  perform public.require_perm('assess.manage');
  perform 1 from public.questionnaires where id = p_qid for update;
  if not found then raise exception 'Το ερωτηματολόγιο δεν βρέθηκε.'; end if;
  if not exists (select 1 from public.questionnaire_versions v join public.assessment_questions x on x.version_id = v.id where v.questionnaire_id = p_qid) then
    raise exception 'Το ερωτηματολόγιο δεν έχει ερωτήσεις.';
  end if;
  v_ver := public.q_draft_version(p_qid);
  update public.questionnaires set updated_at = now() where id = p_qid;
  return jsonb_build_object('version_id', v_ver, 'version', (select version from public.questionnaire_versions where id = v_ver));
end $$;

create or replace function public.q_key_save(p_question_id uuid, p_correct jsonb, p_model text, p_points numeric,
                                             p_status text, p_spoken text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare x public.assessment_questions; v_status text; v_keys text[]; v_opts text[]; v_model text := nullif(trim(coalesce(p_model, '')), '');
begin
  perform public.require_perm('assess.manage');
  select * into x from public.assessment_questions where id = p_question_id for update;
  if not found then raise exception 'Η ερώτηση δεν βρέθηκε.'; end if;
  if (select status from public.questionnaire_versions where id = x.version_id) <> 'draft' then
    raise exception 'Αλλαγές γίνονται μόνο σε πρόχειρη έκδοση. Ανοίξτε ξανά τις «Σωστές απαντήσεις».';
  end if;
  if p_status is not null and p_status not in ('estimate','confirmed') then raise exception 'Μη έγκυρη κατάσταση.'; end if;
  if p_points is not null and (p_points <= 0 or p_points > 1000) then raise exception 'Οι βαθμοί πρέπει να είναι θετικός αριθμός.'; end if;
  if length(coalesce(v_model, '')) > 4000 then raise exception 'Η πρότυπη απάντηση είναι πολύ μεγάλη (έως 4.000 χαρακτήρες).'; end if;
  v_opts := array(select o->>'key' from jsonb_array_elements(x.options) o);
  if p_correct is not null and jsonb_typeof(p_correct) = 'array' and jsonb_array_length(p_correct) > 0 then
    v_keys := array(select distinct k from jsonb_array_elements_text(p_correct) k order by 1);
  end if;
  if x.qtype in ('single','multi') then
    if exists (select 1 from unnest(coalesce(v_keys, '{}')) k where not (k = any(v_opts))) then raise exception 'Η σωστή απάντηση δεν αντιστοιχεί σε επιλογή της ερώτησης.'; end if;
    if x.qtype = 'single' and cardinality(v_keys) > 1 then raise exception 'Ερώτηση μίας επιλογής: μόνο μία σωστή απάντηση.'; end if;
    if p_points is not null and v_keys is null then raise exception 'Ορίστηκαν βαθμοί χωρίς σωστή απάντηση.'; end if;
  elsif v_keys is not null then
    raise exception 'Αυτός ο τύπος ερώτησης δεν έχει σωστή επιλογή· γράψτε πρότυπη απάντηση.';
  end if;
  if x.qtype = 'scale' and p_points is distinct from x.points then raise exception 'Οι βαθμοί της κλίμακας αλλάζουν μόνο από το Excel.'; end if;
  v_status := case when v_keys is null and v_model is null then null else coalesce(p_status, 'confirmed') end;
  update public.assessment_questions set
    correct = case when v_keys is null then null else to_jsonb(v_keys) end,
    model_answer = v_model, points = p_points, key_status = v_status,
    key_spoken = case when p_spoken is not null then left(p_spoken, 2000) else key_spoken end,
    key_note = case when p_status = 'estimate' then nullif(left(trim(coalesce(p_note, '')), 500), '') when p_status = 'confirmed' then null else key_note end,
    key_by = public.current_email(), key_at = now()
   where id = x.id;
  return jsonb_build_object('ok', true, 'key_status', v_status);
end $$;

create or replace function public.q_key_confirm(p_version_id uuid, p_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform public.require_perm('assess.manage');
  if (select status from public.questionnaire_versions where id = p_version_id) is distinct from 'draft' then raise exception 'Μόνο σε πρόχειρη έκδοση.'; end if;
  update public.assessment_questions set key_status = 'confirmed', key_note = null, key_by = public.current_email(), key_at = now()
   where version_id = p_version_id and key_status = 'estimate' and (p_ids is null or id = any(p_ids));
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'confirmed', v_n);
end $$;

create or replace function public.q_key_points(p_version_id uuid, p_points numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform public.require_perm('assess.manage');
  if (select status from public.questionnaire_versions where id = p_version_id) is distinct from 'draft' then raise exception 'Μόνο σε πρόχειρη έκδοση.'; end if;
  if p_points is null or p_points <= 0 or p_points > 1000 then raise exception 'Οι βαθμοί πρέπει να είναι θετικός αριθμός.'; end if;
  update public.assessment_questions set points = p_points
   where version_id = p_version_id and qtype in ('single','multi') and correct is not null and points is null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'updated', v_n);
end $$;

create or replace function public.ex_save(p_attempt uuid, p_question uuid, p_score numeric, p_reason text, p_spoken text default null, p_source text default 'voice')
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assessment_attempts; x public.assessment_questions; v_ans text; v_id uuid;
begin
  perform public.require_perm('assess.manage');
  if p_score is null or p_score < 0 or p_score > 10 then raise exception 'Ο βαθμός πρέπει να είναι από 0 έως 10.'; end if;
  if p_source not in ('voice','typed','correction') then raise exception 'Μη έγκυρη πηγή.'; end if;
  select * into a from public.assessment_attempts where id = p_attempt;
  select * into x from public.assessment_questions where id = p_question;
  if a.id is null or x.id is null or x.version_id <> a.version_id then raise exception 'Η απάντηση δεν βρέθηκε.'; end if;
  select answer #>> '{}' into v_ans from public.assessment_answers where attempt_id = p_attempt and question_id = p_question;
  if nullif(trim(coalesce(v_ans, '')), '') is null then raise exception 'Δεν υπάρχει απάντηση σε αυτή την ερώτηση.'; end if;
  insert into public.answer_examples(questionnaire_id, row_no, question_id, question_text, attempt_id, employee_code, answer_text, score, reason, spoken, source, created_by)
  values (a.questionnaire_id, x.row_no, x.id, x.text, a.id, a.employee_code, left(v_ans, 4000), round(p_score, 1), nullif(left(trim(coalesce(p_reason, '')), 2000), ''),
          left(p_spoken, 2000), p_source, public.current_email())
  on conflict (attempt_id, question_id) where attempt_id is not null do update
    set score = excluded.score, reason = excluded.reason, spoken = coalesce(excluded.spoken, answer_examples.spoken), source = excluded.source, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.ex_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('assess.manage');
  delete from public.answer_examples where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ev_save(p_question uuid, p_rows jsonb, p_examples int, p_model text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; v_n int := 0;
begin
  perform public.require_perm('assess.manage');
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if not exists (select 1 from public.assessment_answers where attempt_id = (r->>'attempt_id')::uuid and question_id = p_question) then continue; end if;
    insert into public.ai_evaluations(attempt_id, question_id, score, reason, examples_used, model, created_by)
    values ((r->>'attempt_id')::uuid, p_question, least(10, greatest(0, round((r->>'score')::numeric, 1))), left(coalesce(r->>'reason', ''), 2000), coalesce(p_examples, 0), left(p_model, 80), public.current_email())
    on conflict (attempt_id, question_id) do update
      set score = excluded.score, reason = excluded.reason, examples_used = excluded.examples_used, model = excluded.model,
          created_by = excluded.created_by, created_at = now()
      where ai_evaluations.status = 'suggested';
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'saved', v_n);
end $$;

create or replace function public.ev_review(p_id uuid, p_action text, p_score numeric default null, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ev public.ai_evaluations; an public.assessment_answers; v_final numeric; v_pts numeric; v_applied boolean := false;
begin
  perform public.require_perm('assess.manage');
  select * into ev from public.ai_evaluations where id = p_id for update;
  if not found then raise exception 'Η αξιολόγηση δεν βρέθηκε.'; end if;
  if p_action not in ('accept','correct','reject') then raise exception 'Μη έγκυρη ενέργεια.'; end if;
  if p_action = 'reject' then
    update public.ai_evaluations set status = 'rejected', reviewed_by = public.current_email(), reviewed_at = now() where id = ev.id;
    return jsonb_build_object('ok', true, 'applied', false);
  end if;
  v_final := case when p_action = 'correct' then p_score else ev.score end;
  if v_final is null or v_final < 0 or v_final > 10 then raise exception 'Ο βαθμός πρέπει να είναι από 0 έως 10.'; end if;
  update public.ai_evaluations set status = case when p_action = 'correct' then 'corrected' else 'accepted' end,
         final_score = v_final, final_reason = case when p_action = 'correct' then nullif(trim(coalesce(p_reason, '')), '') end,
         reviewed_by = public.current_email(), reviewed_at = now()
   where id = ev.id;
  if p_action = 'correct' then
    perform public.ex_save(ev.attempt_id, ev.question_id, v_final, coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'Διόρθωση πρότασης AI (πρόταση: ' || ev.score || ')'), null, 'correction');
  end if;
  select * into an from public.assessment_answers where attempt_id = ev.attempt_id and question_id = ev.question_id;
  if an.max_points is not null then
    v_pts := round(v_final / 10 * an.max_points, 2);
    perform public.assessment_grade(ev.attempt_id, ev.question_id, v_pts);
    v_applied := true;
  end if;
  return jsonb_build_object('ok', true, 'applied', v_applied, 'points', v_pts, 'max_points', an.max_points);
end $$;

create or replace function public.link_history(p_id uuid)
returns table (at timestamptz, actor text, action text, detail jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('assess.manage', 'assess.grade');
  return query select e.at, e.actor, e.action, e.detail from public.assessment_assignment_events e where e.assignment_id = p_id order by e.at, e.id;
end $$;

create or replace function public.ex_answers(p_qid uuid)
returns table (attempt_id uuid, question_id uuid, row_no int, version int, section text, question_text text, model_answer text, points numeric,
               employee_code text, employee_name text, store text, answer_text text, submitted_at timestamptz,
               grade_points numeric, max_points numeric, graded_at timestamptz,
               example_id uuid, example_score numeric, example_reason text,
               eval_id uuid, eval_score numeric, eval_reason text, eval_status text, eval_final numeric, eval_examples int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('assess.manage', 'assess.grade');
  return query
  select a.id, x.id, x.row_no, v.version, x.section, x.text, public.q_latest_model(x.id), x.points,
         a.employee_code, a.employee_name, a.store, an.answer #>> '{}', a.submitted_at,
         an.points, an.max_points, an.graded_at,
         e.id, e.score, e.reason, ev.id, ev.score, ev.reason, ev.status, ev.final_score, ev.examples_used
    from public.assessment_attempts a
    join public.questionnaire_versions v on v.id = a.version_id
    join public.assessment_questions x on x.version_id = a.version_id and x.qtype = 'text'
    join public.assessment_answers an on an.attempt_id = a.id and an.question_id = x.id
    left join public.answer_examples e on e.attempt_id = a.id and e.question_id = x.id
    left join public.ai_evaluations ev on ev.attempt_id = a.id and ev.question_id = x.id
   where a.questionnaire_id = p_qid and a.status in ('submitted','pending_manual')
     and nullif(trim(an.answer #>> '{}'), '') is not null
   order by x.sort, x.row_no, a.submitted_at;
end $$;

create or replace function public.ex_for_question(p_question uuid)
returns table (id uuid, answer_text text, score numeric, reason text, source text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('assess.manage', 'assess.grade');
  return query select e.id, e.answer_text, e.score, e.reason, e.source, e.created_at
    from public.answer_examples e
    join public.assessment_questions x on x.id = p_question
    join public.questionnaire_versions v on v.id = x.version_id
   where e.questionnaire_id = v.questionnaire_id and e.row_no = x.row_no
   order by e.score desc, e.created_at;
end $$;

create or replace function public.q_latest_model(p_question uuid) returns text
language sql stable security definer set search_path = public as $$
  select y.model_answer
    from public.assessment_questions x
    join public.questionnaire_versions vx on vx.id = x.version_id
    join public.questionnaire_versions vy on vy.questionnaire_id = vx.questionnaire_id
    join public.assessment_questions y on y.version_id = vy.id and y.row_no = x.row_no and y.model_answer is not null
   where x.id = p_question and (public.has_perm('assess.manage') or public.has_perm('assess.grade'))
   order by vy.version desc limit 1
$$;

create or replace function public.assessment_grade(p_attempt uuid, p_question uuid, p_points numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.assessment_answers;
begin
  perform public.require_perm('assess.grade');
  select * into v from public.assessment_answers where attempt_id = p_attempt and question_id = p_question for update;
  if not found or v.max_points is null then raise exception 'Η ερώτηση δεν βαθμολογείται.'; end if;
  if p_points is null or p_points < 0 or p_points > v.max_points then raise exception 'Οι βαθμοί πρέπει να είναι από 0 έως %.', v.max_points; end if;
  update public.assessment_answers set points = p_points, graded_by = public.current_email(), graded_at = now() where id = v.id;
  update public.assessment_attempts a set
    status = case when exists (select 1 from public.assessment_answers where attempt_id = p_attempt and needs_manual and graded_at is null) then 'pending_manual' else 'submitted' end,
    score = case when exists (select 1 from public.assessment_answers where attempt_id = p_attempt and needs_manual and graded_at is null) then null
                 else (select sum(points) from public.assessment_answers where attempt_id = p_attempt and max_points is not null) end
  where id = p_attempt;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.assessment_targets(p_qid uuid)
returns table (employee_code text, employee_name text, store text, specialty text, state text, started_at timestamptz, submitted_at timestamptz)
language sql stable security definer set search_path = public as $$
  select e.code, e.first || ' ' || e.last, e.store, e.specialty, public.attempt_state(a, q), a.started_at, a.submitted_at
    from public.questionnaires q
    join public.employees e on e.status = 'Ενεργός' and e.specialty = any(q.specialties)
         and (q.participants is null or e.code = any(q.participants))
    left join lateral (select x.* from public.assessment_attempts x where x.questionnaire_id = q.id and x.employee_code = e.code
                        order by x.started_at desc limit 1) a on true
   where q.id = p_qid and q.status in ('active','closed')
     and (public.has_perm('assess.open') or public.has_perm('assess.results'))
     and public.employee_in_scope(e.code)
   order by e.store, e.last, e.first
$$;

create or replace function public.assessments_open()
returns table (id uuid, title text, description text, specialties text[], starts_at timestamptz, ends_at timestamptz, status text, version int)
language sql stable security definer set search_path = public as $$
  select q.id, q.title, q.description, q.specialties, q.starts_at, q.ends_at, q.status, v.version
    from public.questionnaires q join public.questionnaire_versions v on v.id = q.current_version_id
   where q.status = 'active' and (public.has_perm('assess.open') or public.has_perm('assess.results'))
   order by q.ends_at
$$;

create or replace function public.fill_start_request(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_token text := public.fill_new_token(); v_id uuid;
begin
  perform public.require_perm('requests.create');
  r := public.req_lock(p_request_id, null);
  if r.status <> 'draft' or r.entry_mode <> 'employee_fill' then raise exception 'Η φόρμα εργαζομένου ανοίγει μόνο για πρόχειρο «Συμπλήρωση από εργαζόμενο».'; end if;
  update public.fill_sessions set cancelled_at = now(), cancelled_by = public.current_email()
   where request_id = p_request_id and completed_at is null and cancelled_at is null;
  insert into public.fill_sessions(token_hash, kind, request_id, employee_code, opened_by, opened_role, expires_at)
  values (public.fill_hash(v_token), 'request', p_request_id, r.employee_code, public.current_email(), public.my_role(), now() + interval '12 hours')
  returning id into v_id;
  perform public.req_event(p_request_id, 'fill_opened', 'draft', 'draft', null, jsonb_build_object('session', v_id));
  return jsonb_build_object('token', v_token, 'session_id', v_id, 'opened_by', public.current_email());
end $$;

create or replace function public.fill_start_assessment(p_qid uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_perm('assess.open');
  q public.questionnaires; e public.employees; a public.assessment_attempts; v_token text := public.fill_new_token(); v_id uuid;
begin
  select * into q from public.questionnaires where id = p_qid;
  if not found or q.status <> 'active' then raise exception 'Το ερωτηματολόγιο δεν είναι ενεργό.'; end if;
  if now() < q.starts_at then raise exception 'Η αξιολόγηση δεν έχει ξεκινήσει ακόμη.'; end if;
  if now() > q.ends_at then raise exception 'Η προθεσμία της αξιολόγησης έχει λήξει.'; end if;
  select * into e from public.employees where code = p_code;
  if not found or not public.employee_in_scope(e.code) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if e.status <> 'Ενεργός' then raise exception 'Ο εργαζόμενος είναι ανενεργός.'; end if;
  if e.specialty is null or not (e.specialty = any(q.specialties)) then raise exception 'Το ερωτηματολόγιο δεν αφορά την ειδικότητα του εργαζομένου.'; end if;
  if q.participants is not null and not (e.code = any(q.participants)) then raise exception 'Ο εργαζόμενος δεν περιλαμβάνεται στους συμμετέχοντες.'; end if;
  if exists (select 1 from public.assessment_assignments where questionnaire_id = p_qid and employee_code = e.code and status = 'active' and completed_at is null) then
    raise exception 'Για τον εργαζόμενο υπάρχει προσωπικός σύνδεσμος αξιολόγησης. Η συμπλήρωση γίνεται από τον σύνδεσμο.';
  end if;
  if exists (select 1 from public.assessment_attempts where questionnaire_id = p_qid and employee_code = e.code and status <> 'in_progress') then
    raise exception 'Ο εργαζόμενος έχει ήδη υποβάλει αυτή την αξιολόγηση.';
  end if;
  select * into a from public.assessment_attempts where questionnaire_id = p_qid and employee_code = e.code and assignment_id is null for update;
  if not found then
    insert into public.assessment_attempts(questionnaire_id, version_id, employee_code, employee_name, store, specialty, company, opened_by, opened_role)
    values (p_qid, q.current_version_id, e.code, e.first || ' ' || e.last, e.store, e.specialty, e.company, public.current_email(), v_role)
    returning * into a;
  end if;
  update public.fill_sessions set cancelled_at = now(), cancelled_by = public.current_email()
   where attempt_id = a.id and completed_at is null and cancelled_at is null;
  insert into public.fill_sessions(token_hash, kind, attempt_id, employee_code, opened_by, opened_role)
  values (public.fill_hash(v_token), 'assessment', a.id, e.code, public.current_email(), v_role) returning id into v_id;
  return jsonb_build_object('token', v_token, 'session_id', v_id, 'attempt_id', a.id, 'opened_by', public.current_email());
end $$;

create or replace function public.fill_cancel(p_session uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions;
begin
  perform public.require_perm('assess.open', 'requests.create');
  select * into s from public.fill_sessions where id = p_session for update;
  if not found then raise exception 'Δεν βρέθηκε.'; end if;
  if s.opened_by <> public.current_email() and not (public.has_perm('assess.manage') or public.has_perm('requests.decide')) then raise exception 'Δεν επιτρέπεται.'; end if;
  if s.completed_at is null and s.cancelled_at is null then
    update public.fill_sessions set cancelled_at = now(), cancelled_by = public.current_email() where id = p_session;
  end if;
  return jsonb_build_object('ok', true, 'completed', s.completed_at is not null);
end $$;

create or replace function public.fill_status(p_session uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('kind', kind, 'request_id', request_id, 'attempt_id', attempt_id,
         'completed', completed_at is not null, 'cancelled', cancelled_at is not null)
    from public.fill_sessions
   where id = p_session and (opened_by = public.current_email() or (public.has_perm('assess.manage') or public.has_perm('requests.decide')))
$$;

create or replace function public.trainer_employees()
returns table (code text, first text, last text, store text, company text, specialty text, status text)
language sql stable security definer set search_path = public as $$
  select e.code, e.first, e.last, e.store, e.company, e.specialty, e.status
    from public.employees e
   where public.has_perm('employees.view') and public.employee_in_scope(e.code)
   order by e.last, e.first
$$;


-- Exit Interview: είδος ερωτηματολογίου (χρειάζεται εδώ για τους κανόνες πρόσβασης· η λειτουργία στο Μέρος 5)
alter table public.questionnaires add column if not exists kind text not null default 'assessment'
  check (kind in ('assessment','exit_interview'));

create or replace function public.q_kind(p_qid uuid) returns text
language sql stable security definer set search_path = public as $$ select kind from public.questionnaires where id = p_qid $$;

-- Κατάσταση αξιολογήσεων εργαζομένου (χωρίς απαντήσεις/βαθμούς). Exit Interview μόνο για ΓΔ/HR/εκπαιδευτή.
create or replace function public.employee_assessments(p_code text)
returns table (questionnaire_id uuid, title text, version int, state text, store text, specialty text,
               opened_by text, started_at timestamptz, submitted_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select * from (
    select q.id, q.title, v.version, public.attempt_state(a, q), a.store, a.specialty, a.opened_by, a.started_at, a.submitted_at, coalesce(a.due_at, q.ends_at)
      from public.assessment_attempts a
      join public.questionnaires q on q.id = a.questionnaire_id
      join public.questionnaire_versions v on v.id = a.version_id
     where a.employee_code = p_code and public.employee_in_scope(p_code)
       and (public.has_perm('assess.open') or public.has_perm('assess.results'))
       and (q.kind <> 'exit_interview' or public.can_view_exit())
    union all
    select q.id, q.title, v.version, case when now() > g.ends_at then 'expired' else 'not_started' end, g.store, g.specialty, g.created_by, null::timestamptz, null::timestamptz, g.ends_at
      from public.assessment_assignments g
      join public.questionnaires q on q.id = g.questionnaire_id
      join public.questionnaire_versions v on v.id = g.version_id
     where g.employee_code = p_code and g.status = 'active' and g.completed_at is null
       and not exists (select 1 from public.assessment_attempts a where a.assignment_id = g.id)
       and public.employee_in_scope(p_code)
       and (public.has_perm('assess.open') or public.has_perm('assess.results'))
       and (q.kind <> 'exit_interview' or public.can_view_exit())
  ) x order by x.started_at desc nulls first
$$;

-- ═══════════════ Κανόνες πρόσβασης (RLS): ενότητα + πεδίο καταστημάτων ═══════════════
drop policy if exists stores_write on public.stores;
create policy stores_write on public.stores for all to authenticated using (public.has_perm('settings.manage')) with check (public.has_perm('settings.manage'));
drop policy if exists comp_write on public.companies;
create policy comp_write on public.companies for all to authenticated using (public.has_perm('settings.manage')) with check (public.has_perm('settings.manage'));
drop policy if exists spec_write on public.specialties;
create policy spec_write on public.specialties for all to authenticated using (public.has_perm('settings.manage')) with check (public.has_perm('settings.manage'));
drop policy if exists lt_write on public.leave_types;
create policy lt_write on public.leave_types for all to authenticated using (public.has_perm('settings.manage')) with check (public.has_perm('settings.manage'));
drop policy if exists rr_write on public.reject_reasons;
create policy rr_write on public.reject_reasons for all to authenticated using (public.has_perm('settings.manage')) with check (public.has_perm('settings.manage'));
drop policy if exists ts_read on public.trainer_scopes;
create policy ts_read on public.trainer_scopes for select to authenticated using (public.has_perm('users.manage') or email = public.current_email());
drop policy if exists ts_write on public.trainer_scopes;
create policy ts_write on public.trainer_scopes for all to authenticated using (public.has_perm('users.manage')) with check (public.has_perm('users.manage'));

drop policy if exists users_read on public.app_users;
create policy users_read on public.app_users for select to authenticated using (public.has_perm('users.manage') or email = public.current_email());
drop policy if exists users_write on public.app_users;
create policy users_write on public.app_users for all to authenticated using (public.has_perm('users.manage')) with check (public.has_perm('users.manage'));

drop policy if exists emp_read on public.employees;
create policy emp_read on public.employees for select to authenticated
  using ((public.has_perm('employees.view') or public.has_perm('payroll.view')) and public.can_see_store(store));
drop policy if exists emp_insert on public.employees;
create policy emp_insert on public.employees for insert to authenticated with check (public.has_perm('employees.edit'));
drop policy if exists emp_update on public.employees;
create policy emp_update on public.employees for update to authenticated
  using (public.has_perm('employees.edit') and public.can_see_store(store)) with check (public.has_perm('employees.edit') and public.can_see_store(store));

drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select to authenticated using (public.has_perm('audit.view'));

drop policy if exists decl_read on public.declarations;
create policy decl_read on public.declarations for select to authenticated using (public.has_perm('payroll.view') and public.can_see_store(store));

drop policy if exists tpl_read on public.text_templates;
create policy tpl_read on public.text_templates for select to authenticated using (public.has_perm('requests.view') or public.has_perm('templates.manage'));
drop policy if exists tplv_read on public.text_template_versions;
create policy tplv_read on public.text_template_versions for select to authenticated using (public.has_perm('requests.view') or public.has_perm('templates.manage'));
drop policy if exists lt_read on public.leave_types;
create policy lt_read on public.leave_types for select to authenticated using (public.my_role() is not null);
drop policy if exists rr_read on public.reject_reasons;
create policy rr_read on public.reject_reasons for select to authenticated using (public.has_perm('requests.view') or public.has_perm('settings.manage'));

drop policy if exists req_read on public.hr_requests;
create policy req_read on public.hr_requests for select to authenticated using (public.has_perm('requests.view') and public.can_see_store(store));
drop policy if exists reqi_read on public.hr_request_internal;
create policy reqi_read on public.hr_request_internal for select to authenticated using (public.has_perm('requests.decide'));
drop policy if exists ev_read on public.hr_request_events;
create policy ev_read on public.hr_request_events for select to authenticated
  using ((not internal or public.has_perm('requests.decide')) and exists (select 1 from public.hr_requests r where r.id = request_id));

drop policy if exists st_read on public.daily_stats;
create policy st_read on public.daily_stats for select to authenticated
  using ((public.has_perm('stats.view') or public.has_perm('stats.reports') or public.has_perm('stats.entry')) and public.can_see_store(store));

-- Αξιολογήσεις: πλήρη στοιχεία μέσω πινάκων μόνο για διαχείριση/βαθμολόγηση· Exit Interview μόνο ΓΔ/HR/εκπαιδευτής
drop policy if exists q_read on public.questionnaires;
create policy q_read on public.questionnaires for select to authenticated
  using ((public.has_perm('assess.manage') or public.has_perm('assess.grade')) and (kind <> 'exit_interview' or public.can_view_exit()));
drop policy if exists qv_read on public.questionnaire_versions;
create policy qv_read on public.questionnaire_versions for select to authenticated
  using ((public.has_perm('assess.manage') or public.has_perm('assess.grade')) and (public.q_kind(questionnaire_id) <> 'exit_interview' or public.can_view_exit()));
drop policy if exists qq_read on public.assessment_questions;
create policy qq_read on public.assessment_questions for select to authenticated
  using ((public.has_perm('assess.manage') or public.has_perm('assess.grade'))
         and (public.can_view_exit() or (select q.kind from public.questionnaire_versions v join public.questionnaires q on q.id = v.questionnaire_id where v.id = version_id) <> 'exit_interview'));
drop policy if exists qw_read on public.questionnaire_window_log;
create policy qw_read on public.questionnaire_window_log for select to authenticated using (public.has_perm('assess.manage') or public.has_perm('assess.grade'));
drop policy if exists qa_read on public.assessment_attempts;
create policy qa_read on public.assessment_attempts for select to authenticated
  using ((public.has_perm('assess.manage') or public.has_perm('assess.grade')) and (public.q_kind(questionnaire_id) <> 'exit_interview' or public.can_view_exit()));
drop policy if exists qan_read on public.assessment_answers;
create policy qan_read on public.assessment_answers for select to authenticated
  using ((public.has_perm('assess.manage') or public.has_perm('assess.grade'))
         and (public.can_view_exit() or (select public.q_kind(a.questionnaire_id) from public.assessment_attempts a where a.id = attempt_id) <> 'exit_interview'));
drop policy if exists asg_read on public.assessment_assignments;
create policy asg_read on public.assessment_assignments for select to authenticated
  using ((public.has_perm('assess.manage') or public.has_perm('assess.grade')) and (public.q_kind(questionnaire_id) <> 'exit_interview' or public.can_view_exit()));
drop policy if exists asge_read on public.assessment_assignment_events;
create policy asge_read on public.assessment_assignment_events for select to authenticated using (public.has_perm('assess.manage') or public.has_perm('assess.grade'));
drop policy if exists aex_read on public.answer_examples;
create policy aex_read on public.answer_examples for select to authenticated using (public.has_perm('assess.manage') or public.has_perm('assess.grade'));
drop policy if exists aev_read on public.ai_evaluations;
create policy aev_read on public.ai_evaluations for select to authenticated using (public.has_perm('assess.manage') or public.has_perm('assess.grade'));

-- ═══════════════ PDF: η εικόνα υπογραφής ΜΟΝΟ μέσω του server ═══════════════
-- Χωρίς την υπογραφή δεν μπορεί να δημιουργηθεί το ίδιο PDF στον browser (ούτε από απευθείας URL).
revoke select on public.declarations from authenticated;
grant select (id, employee_code, employee_name, store, company, month, end_date, period, amount, status, statement, signer,
              signed_at, signed_by, device, prepared_by, prepared_at, voided_by, voided_at, void_reason) on public.declarations to authenticated;

create table public.pdf_downloads (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  actor   text not null,
  role    text not null,
  purpose text not null check (purpose in ('single','bulk','backup')),
  ids     uuid[] not null
);

-- p_purpose: single = ένα PDF · bulk = ZIP πολλών · backup = μηνιαίο backup
create or replace function public.decl_pdf_data(p_ids uuid[], p_purpose text default 'single')
returns setof jsonb language plpgsql security definer set search_path = public as $$
declare v_n int := coalesce(cardinality(p_ids), 0);
begin
  perform public.require_perm('payroll.pdf');
  if p_purpose not in ('single','bulk','backup') then raise exception 'Μη έγκυρη ενέργεια.'; end if;
  if v_n = 0 then return; end if;
  if v_n > 3000 then raise exception 'Πάρα πολλές δηλώσεις σε μία λήψη.'; end if;
  if p_purpose = 'single' and v_n > 1 then raise exception 'Για πολλές δηλώσεις χρησιμοποιήστε τη μαζική λήψη.'; end if;
  if p_purpose = 'bulk' and not public.has_perm('payroll.bulk') then raise exception 'Δεν έχετε δικαίωμα μαζικής λήψης αρχείων.'; end if;
  if p_purpose = 'backup' and not public.has_perm('payroll.backup') then raise exception 'Δεν έχετε δικαίωμα backup.'; end if;
  insert into public.pdf_downloads(actor, role, purpose, ids) values (public.current_email(), public.my_role(), p_purpose, p_ids);
  return query
    select to_jsonb(d) from public.declarations d
     where d.id = any(p_ids) and d.status = 'signed' and public.can_see_store(d.store);
end $$;

alter table public.permissions      enable row level security;
alter table public.role_permissions enable row level security;
alter table public.role_scopes      enable row level security;
alter table public.permission_log   enable row level security;
alter table public.pdf_downloads    enable row level security;
create policy perm_read on public.permissions for select to authenticated using (public.my_role() is not null);
create policy rp_read   on public.role_permissions for select to authenticated using (public.has_perm('permissions.manage') or role = public.my_role());
create policy rs_read   on public.role_scopes for select to authenticated using (public.my_role() is not null);
create policy pl_read   on public.permission_log for select to authenticated using (public.has_perm('permissions.manage'));
create policy pdl_read  on public.pdf_downloads for select to authenticated using (public.has_perm('audit.view'));
revoke all on public.permissions, public.role_permissions, public.role_scopes, public.permission_log, public.pdf_downloads from anon, authenticated;
grant select on public.permissions, public.role_permissions, public.role_scopes, public.permission_log, public.pdf_downloads to authenticated;
create trigger permission_log_append_only before update or delete on public.permission_log for each row execute function public.append_only();
create trigger pdf_downloads_append_only before update or delete on public.pdf_downloads for each row execute function public.append_only();

revoke execute on all functions in schema public from public, anon;
grant execute on function public.has_perm(text), public.require_perm(text[]), public.role_has_perm(text, text), public.my_scope(), public.can_view_exit(),
  public.whoami(), public.permissions_matrix(), public.permissions_save(jsonb, jsonb, text), public.decl_pdf_data(uuid[], text),
  public.employee_assessments(text), public.q_kind(uuid) to authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
