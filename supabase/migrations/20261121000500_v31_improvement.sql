-- Έκδοση 3.1 · 18. Παρακολούθηση βελτίωσης & συνεργασίας · 19. Πρότυπο και εκτύπωση εντύπου σταδίου 2
-- Το Excel «Ομαλή λύση Συνεργασίας_Προτότυπο.xlsx» ΔΕΝ παραλήφθηκε: υλοποιούνται τα πεδία/στάδια/εκβάσεις που περιγράφει η
-- προδιαγραφή. Ο αυτόματος υπολογισμός προθεσμιών (15/7/7) μένει ΑΝΕΝΕΡΓΟΣ μέχρι να οριστεί αν είναι ημερολογιακές ή
-- εργάσιμες ημέρες. Το PDF του σταδίου 2 δεν υπάρχει ακόμη: η έκδοση εντύπου μένει ανενεργή μέχρι να ανέβει πρότυπο.
-- Καμία αυτόματη προειδοποίηση ή λύση συνεργασίας· η υπόθεση δεν αλλάζει ποτέ την κατάσταση του εργαζομένου.
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο νέοι πίνακες, συναρτήσεις και δικαιώματα.

create table if not exists public.improvement_settings (
  id          int primary key default 1 check (id = 1),
  day_mode    text check (day_mode in ('calendar','working')),     -- null = δεν έχει αποφασιστεί → χωρίς αυτόματο υπολογισμό
  intervals   int[] not null default '{15,7,7}',
  updated_by  text, updated_at timestamptz
);
insert into public.improvement_settings(id) values (1) on conflict do nothing;

create table if not exists public.improvement_cases (
  id               bigserial primary key,
  ref              text not null unique,
  employee_code    text not null references public.employees(code) on update cascade,
  employee_name    text not null,
  store            text not null,
  specialty        text,
  severity         text not null check (severity in ('minor','significant','critical')),
  incident_type    text not null check (length(trim(incident_type)) between 2 and 200),
  description      text not null check (length(trim(description)) between 5 and 8000),
  incident_date    date not null,
  documentation    text,
  owner_email      text,
  actions          text,
  notes            text,
  stage            smallint not null default 1 check (stage between 1 and 4),
  status           text not null default 'open' check (status in ('open','closed')),
  last_outcome     text check (last_outcome in ('complied','partial','back','noncompliant')),
  proposed_stage   smallint,
  next_review_due  date,               -- προθεσμία επανεξέτασης (διακριτή από τις πραγματικές ημερομηνίες ενεργειών)
  warning_request_id uuid references public.hr_requests(id),
  last_action_at   timestamptz not null default now(),
  created_by       text not null,
  created_at       timestamptz not null default now(),
  closed_by        text, closed_at timestamptz,
  version          int not null default 1
);
create index if not exists improvement_cases_emp_idx on public.improvement_cases(employee_code);
create index if not exists improvement_cases_store_idx on public.improvement_cases(store, status);

create table if not exists public.improvement_events (
  id          bigserial primary key,
  case_id     bigint not null references public.improvement_cases(id),
  action      text not null check (action in ('created','updated','review','stage_change','note','attachment','due_set','closed',
                                              'warning_linked','form_issued','form_printed','signed_uploaded')),
  from_stage  smallint, to_stage smallint,
  outcome     text,
  reason      text,
  action_date date,                    -- πραγματική ημερομηνία της ενέργειας (π.χ. συνάντηση επανεξέτασης)
  due_date    date,                    -- προθεσμία που ορίστηκε
  form_id     bigint,
  file_name text, file_mime text, file_size int, file_data text,
  actor       text not null,
  actor_role  text,
  at          timestamptz not null default now()
);
create index if not exists improvement_events_idx on public.improvement_events(case_id, at);

-- 19. Πρότυπα εντύπων (PDF) με εκδόσεις · αντίγραφο κάθε εκδοθέντος εντύπου στην υπόθεση
create table if not exists public.form_templates (
  key   text primary key,
  label text not null,
  stage smallint
);
insert into public.form_templates(key, label, stage) values
 ('improvement_stage2', 'Στάδιο 2 — Επίσημη προφορική επισήμανση & πλάνο βελτίωσης', 2)
on conflict (key) do nothing;
create table if not exists public.form_template_versions (
  id         bigserial primary key,
  key        text not null references public.form_templates(key),
  version    int not null,
  pdf_name   text not null,
  pdf_data   text not null,            -- base64
  pdf_size   int not null,
  body       text,                     -- συνοδευτικό κείμενο
  fields     jsonb not null default '[]',  -- πεδία αυτόματης συμπλήρωσης (ορίζονται μετά την εξέταση του αρχείου)
  created_by text not null,
  created_at timestamptz not null default now(),
  unique (key, version)
);
create table if not exists public.improvement_forms (
  id                  bigserial primary key,
  case_id             bigint not null references public.improvement_cases(id),
  template_version_id bigint not null references public.form_template_versions(id),
  pdf_name            text not null,
  pdf_data            text not null,   -- αντίγραφο τη στιγμή της έκδοσης: αλλαγές προτύπου δεν το αλλοιώνουν
  body                text,
  values              jsonb not null default '{}',
  issued_by           text not null,
  issued_at           timestamptz not null default now(),
  print_count         int not null default 0
);
alter table public.improvement_settings enable row level security;
alter table public.improvement_cases enable row level security;
alter table public.improvement_events enable row level security;
alter table public.form_templates enable row level security;
alter table public.form_template_versions enable row level security;
alter table public.improvement_forms enable row level security;
revoke all on public.improvement_settings, public.improvement_cases, public.improvement_events, public.form_templates,
  public.form_template_versions, public.improvement_forms from anon, authenticated;

create or replace function public.imp_stage_label(p int) returns text language sql immutable as $$
  select case p when 1 then 'Προφορική επισήμανση & σχέδιο δράσης' when 2 then 'Επίσημη προφορική επισήμανση & πλάνο βελτίωσης'
                when 3 then 'Έγγραφη προειδοποίηση HR' when 4 then 'Εξέταση λύσης συνεργασίας' end
$$;

create or replace function public.imp_can_view(c public.improvement_cases) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_perm('improvement.view') and public.can_see_store(c.store)
$$;

create or replace function public.imp_lock(p_id bigint, p_version int) returns public.improvement_cases
language plpgsql security definer set search_path = public as $$
declare c public.improvement_cases;
begin
  select * into c from public.improvement_cases where id = p_id for update;
  if not found or not public.imp_can_view(c) then raise exception 'Η υπόθεση δεν βρέθηκε στο πεδίο σας.'; end if;
  if p_version is not null and c.version <> p_version then raise exception 'Η υπόθεση άλλαξε στο μεταξύ από άλλον χρήστη. Ανανεώστε τη σελίδα.'; end if;
  return c;
end $$;

create or replace function public.imp_event(p_case bigint, p_action text, p jsonb default '{}') returns void
language sql security definer set search_path = public as $$
  insert into public.improvement_events(case_id, action, from_stage, to_stage, outcome, reason, action_date, due_date, form_id, actor, actor_role)
  values (p_case, p_action, (p->>'from_stage')::smallint, (p->>'to_stage')::smallint, p->>'outcome', nullif(trim(coalesce(p->>'reason','')), ''),
          (p->>'action_date')::date, (p->>'due_date')::date, (p->>'form_id')::bigint, public.current_email(), public.my_role());
  update public.improvement_cases set last_action_at = now(), version = version + 1 where id = p_case;
$$;

-- Προτεινόμενη προθεσμία: ΜΟΝΟ αν η ΓΔ έχει ορίσει ημερολογιακές/εργάσιμες ημέρες· αλλιώς null (χειροκίνητη προθεσμία).
create or replace function public.imp_suggest_due(p_stage int, p_from date) returns date
language plpgsql stable security definer set search_path = public as $$
declare s public.improvement_settings; n int; d date := p_from;
begin
  select * into s from public.improvement_settings where id = 1;
  if s.day_mode is null or p_stage not between 1 and 3 then return null; end if;
  n := s.intervals[p_stage];
  if s.day_mode = 'calendar' then return p_from + n; end if;
  while n > 0 loop d := d + 1; if extract(isodow from d) < 6 and not exists (select 1 from public.public_holidays where day = d) then n := n - 1; end if; end loop;
  return d;
end $$;

create or replace function public.imp_settings() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('day_mode', day_mode, 'intervals', to_jsonb(intervals), 'updated_by', updated_by, 'updated_at', updated_at,
    'template', (select jsonb_build_object('version', v.version, 'pdf_name', v.pdf_name, 'body', v.body, 'fields', v.fields, 'created_by', v.created_by, 'created_at', v.created_at)
                   from public.form_template_versions v where v.key = 'improvement_stage2' order by v.version desc limit 1))
    from public.improvement_settings where id = 1 and public.has_perm('improvement.view')
$$;
create or replace function public.imp_set_day_mode(p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('improvement.settings');
  if p_mode is not null and p_mode not in ('calendar','working') then raise exception 'Επιλέξτε ημερολογιακές ή εργάσιμες ημέρες.'; end if;
  update public.improvement_settings set day_mode = p_mode, updated_by = public.current_email(), updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.imp_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_id bigint; v_ref text; v_date date; v_due date;
begin
  perform public.require_perm('improvement.manage');
  select * into e from public.employees where code = p->>'employee_code';
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if coalesce(p->>'severity', '') not in ('minor','significant','critical') then raise exception 'Επιλέξτε βαρύτητα.'; end if;
  begin v_date := (p->>'incident_date')::date; v_due := nullif(p->>'next_review_due', '')::date; exception when others then raise exception 'Μη έγκυρη ημερομηνία.'; end;
  if v_date is null or v_date > public.athens_today() then raise exception 'Η ημερομηνία περιστατικού δεν μπορεί να είναι μελλοντική.'; end if;
  v_due := coalesce(v_due, public.imp_suggest_due(1, public.athens_today()));
  v_ref := 'ΒΣ-' || to_char(now() at time zone 'Europe/Athens', 'YYYY') || '-' || lpad((select count(*) + 1 from public.improvement_cases)::text, 5, '0');
  while exists (select 1 from public.improvement_cases where ref = v_ref) loop v_ref := v_ref || 'α'; end loop;
  insert into public.improvement_cases(ref, employee_code, employee_name, store, specialty, severity, incident_type, description, incident_date,
         documentation, owner_email, actions, notes, next_review_due, created_by)
  values (v_ref, e.code, e.first || ' ' || e.last, e.store, e.specialty, p->>'severity', trim(p->>'incident_type'), trim(p->>'description'), v_date,
          nullif(trim(coalesce(p->>'documentation','')), ''), coalesce(nullif(trim(coalesce(p->>'owner_email','')), ''), public.current_email()),
          nullif(trim(coalesce(p->>'actions','')), ''), nullif(trim(coalesce(p->>'notes','')), ''), v_due, public.current_email())
  returning id into v_id;
  perform public.imp_event(v_id, 'created', jsonb_build_object('to_stage', 1, 'due_date', v_due, 'action_date', v_date));
  return jsonb_build_object('ok', true, 'id', v_id, 'ref', v_ref, 'next_review_due', v_due);
end $$;

create or replace function public.imp_update(p_id bigint, p jsonb, p_version int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.improvement_cases := public.imp_lock(p_id, p_version); v_due date;
begin
  perform public.require_perm('improvement.manage');
  if c.status = 'closed' then raise exception 'Η υπόθεση έχει κλείσει.'; end if;
  begin v_due := nullif(p->>'next_review_due', '')::date; exception when others then raise exception 'Μη έγκυρη προθεσμία.'; end;
  update public.improvement_cases set
    owner_email = coalesce(nullif(trim(coalesce(p->>'owner_email','')), ''), owner_email),
    actions = coalesce(p->>'actions', actions), notes = coalesce(p->>'notes', notes), documentation = coalesce(p->>'documentation', documentation),
    next_review_due = coalesce(v_due, next_review_due)
   where id = p_id;
  perform public.imp_event(p_id, case when v_due is not null and v_due is distinct from c.next_review_due then 'due_set' else 'updated' end,
    jsonb_build_object('due_date', v_due, 'reason', p->>'reason'));
  return jsonb_build_object('ok', true);
end $$;

-- Επανεξέταση: έκβαση + αιτιολογία (υποχρεωτικές)· ΚΑΜΙΑ αυτόματη μετάβαση σταδίου, προειδοποίηση ή λύση συνεργασίας.
create or replace function public.imp_review(p_id bigint, p_outcome text, p_reason text, p_action_date date, p_new_due date, p_version int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.improvement_cases := public.imp_lock(p_id, p_version); v_reason text := trim(coalesce(p_reason, ''));
begin
  perform public.require_perm('improvement.manage');
  if c.status = 'closed' then raise exception 'Η υπόθεση έχει κλείσει.'; end if;
  if p_outcome not in ('complied','partial','back','noncompliant') then raise exception 'Επιλέξτε έκβαση επανεξέτασης.'; end if;
  if length(v_reason) < 5 then raise exception 'Η αιτιολογία είναι υποχρεωτική.'; end if;
  if p_action_date is null or p_action_date > public.athens_today() then raise exception 'Συμπληρώστε την πραγματική ημερομηνία επανεξέτασης (όχι μελλοντική).'; end if;
  if p_outcome = 'partial' and p_new_due is null then raise exception 'Ορίστε νέα προθεσμία για τη συνέχιση της παρακολούθησης.'; end if;
  if p_outcome = 'back' and c.stage = 1 then raise exception 'Η υπόθεση είναι ήδη στο πρώτο στάδιο.'; end if;
  if p_new_due is not null and p_new_due <= p_action_date then raise exception 'Η νέα προθεσμία πρέπει να είναι μετά την επανεξέταση.'; end if;
  update public.improvement_cases set last_outcome = p_outcome,
    status = case when p_outcome = 'complied' then 'closed' else status end,
    closed_by = case when p_outcome = 'complied' then public.current_email() end, closed_at = case when p_outcome = 'complied' then now() end,
    stage = case when p_outcome = 'back' then stage - 1 else stage end,
    proposed_stage = case when p_outcome = 'noncompliant' and stage < 4 then stage + 1 else null end,
    next_review_due = case when p_outcome = 'complied' then null else coalesce(p_new_due, next_review_due) end
   where id = p_id;
  perform public.imp_event(p_id, 'review', jsonb_build_object('outcome', p_outcome, 'reason', v_reason, 'action_date', p_action_date, 'due_date', p_new_due,
    'from_stage', c.stage, 'to_stage', case when p_outcome = 'back' then c.stage - 1 else c.stage end));
  return jsonb_build_object('ok', true);
end $$;

-- Μετάβαση σταδίου (απόφαση χρήστη με αιτιολογία). Στάδιο 3 μόνο με συνδεδεμένο αίτημα έγγραφης προειδοποίησης
-- (Manager → HR προσχέδιο → ΓΔ → κοινοποίηση HR). Στάδιο 4 μόνο ΓΔ/HR — δεν αλλάζει τον εργαζόμενο σε αποχωρήσαντα.
create or replace function public.imp_set_stage(p_id bigint, p_stage int, p_reason text, p_new_due date, p_version int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.improvement_cases := public.imp_lock(p_id, p_version); v_due date;
begin
  perform public.require_perm('improvement.manage');
  if c.status = 'closed' then raise exception 'Η υπόθεση έχει κλείσει.'; end if;
  if p_stage not between 1 and 4 or p_stage = c.stage then raise exception 'Επιλέξτε άλλο στάδιο.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Η αιτιολογία είναι υποχρεωτική.'; end if;
  if p_stage > c.stage + 1 then raise exception 'Η μετάβαση γίνεται ένα στάδιο κάθε φορά.'; end if;
  if p_stage = 3 and c.warning_request_id is null then
    raise exception 'Για το στάδιο 3 συνδέστε πρώτα αίτημα έγγραφης προειδοποίησης (Manager → HR → ΓΔ → κοινοποίηση HR).';
  end if;
  if p_stage = 4 and public.my_role() not in ('owner','hr') then raise exception 'Την εξέταση λύσης συνεργασίας την ξεκινούν ΓΔ ή HR.'; end if;
  v_due := coalesce(p_new_due, case when p_stage < 4 then public.imp_suggest_due(p_stage, public.athens_today()) end);
  update public.improvement_cases set stage = p_stage, proposed_stage = null, next_review_due = v_due where id = p_id;
  perform public.imp_event(p_id, 'stage_change', jsonb_build_object('from_stage', c.stage, 'to_stage', p_stage, 'reason', p_reason, 'due_date', v_due));
  return jsonb_build_object('ok', true, 'next_review_due', v_due);
end $$;

create or replace function public.imp_link_warning(p_id bigint, p_request uuid, p_version int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.improvement_cases := public.imp_lock(p_id, p_version); r public.hr_requests;
begin
  perform public.require_perm('improvement.manage');
  select * into r from public.hr_requests where id = p_request;
  if not found or r.category <> 'warning_request' or r.employee_code <> c.employee_code then raise exception 'Επιλέξτε αίτημα έγγραφης προειδοποίησης του ίδιου εργαζομένου.'; end if;
  update public.improvement_cases set warning_request_id = p_request where id = p_id;
  perform public.imp_event(p_id, 'warning_linked', jsonb_build_object('reason', r.ref));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.imp_note(p_id bigint, p_note text, p_file jsonb, p_kind text default 'note', p_form bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.improvement_cases := public.imp_lock(p_id, null); f jsonb := public.file_check(p_file);
begin
  if not (public.has_perm('improvement.manage') or (p_kind = 'signed_uploaded' and public.has_perm('improvement.stage_two_print'))) then
    raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.';
  end if;
  if p_kind not in ('note','attachment','signed_uploaded') then raise exception 'Μη έγκυρη ενέργεια.'; end if;
  if p_kind = 'signed_uploaded' and (f is null or p_form is null or not exists (select 1 from public.improvement_forms where id = p_form and case_id = p_id)) then
    raise exception 'Επισυνάψτε τη σάρωση ή φωτογραφία του υπογεγραμμένου εντύπου.';
  end if;
  if f is null and length(trim(coalesce(p_note, ''))) < 2 then raise exception 'Γράψτε σημείωση ή επισυνάψτε αρχείο.'; end if;
  insert into public.improvement_events(case_id, action, reason, form_id, file_name, file_mime, file_size, file_data, actor, actor_role)
  values (p_id, case when p_kind = 'note' and f is not null then 'attachment' else p_kind end, nullif(trim(coalesce(p_note,'')), ''), p_form,
          f->>'name', f->>'mime', (f->>'size')::int, f->>'data', public.current_email(), public.my_role());
  update public.improvement_cases set last_action_at = now(), version = version + 1 where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.imp_list(p_employee text default null)
returns table (id bigint, ref text, employee_code text, employee_name text, store text, specialty text, severity text, incident_type text, incident_date date,
               stage smallint, stage_label text, status text, last_outcome text, proposed_stage smallint, owner_email text, next_review_due date,
               last_action_at timestamptz, overdue boolean, created_at timestamptz, version int)
language sql stable security definer set search_path = public as $$
  select c.id, c.ref, c.employee_code, c.employee_name, c.store, c.specialty, c.severity, c.incident_type, c.incident_date,
         c.stage, public.imp_stage_label(c.stage), c.status, c.last_outcome, c.proposed_stage, c.owner_email, c.next_review_due,
         c.last_action_at, c.status = 'open' and c.next_review_due is not null and c.next_review_due < public.athens_today(), c.created_at, c.version
    from public.improvement_cases c
   where public.imp_can_view(c) and (p_employee is null or c.employee_code = p_employee)
   order by c.status, c.next_review_due nulls last, c.created_at desc
$$;

create or replace function public.imp_get(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.improvement_cases;
begin
  select * into c from public.improvement_cases where id = p_id;
  if not found or not public.imp_can_view(c) then raise exception 'Η υπόθεση δεν βρέθηκε στο πεδίο σας.'; end if;
  return to_jsonb(c) || jsonb_build_object('stage_label', public.imp_stage_label(c.stage),
    'warning_ref', (select ref from public.hr_requests where id = c.warning_request_id),
    'warning_status', (select status from public.hr_requests where id = c.warning_request_id),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'action', x.action, 'from_stage', x.from_stage, 'to_stage', x.to_stage, 'outcome', x.outcome,
                 'reason', x.reason, 'action_date', x.action_date, 'due_date', x.due_date, 'form_id', x.form_id, 'file_name', x.file_name, 'actor', x.actor, 'at', x.at) order by x.at), '[]')
                 from public.improvement_events x where x.case_id = p_id),
    'forms', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'version', v.version, 'issued_by', f.issued_by, 'issued_at', f.issued_at, 'print_count', f.print_count,
                 'signed', exists (select 1 from public.improvement_events s where s.form_id = f.id and s.action = 'signed_uploaded')) order by f.issued_at), '[]')
                from public.improvement_forms f join public.form_template_versions v on v.id = f.template_version_id where f.case_id = p_id),
    'can_manage', public.has_perm('improvement.manage'),
    'can_print', public.has_perm('improvement.stage_two_print') or public.has_perm('improvement.manage'),
    'suggest_enabled', (select day_mode is not null from public.improvement_settings where id = 1));
end $$;

create or replace function public.imp_file(p_event bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare x public.improvement_events; c public.improvement_cases;
begin
  select * into x from public.improvement_events where id = p_event and file_data is not null;
  if not found then raise exception 'Το αρχείο δεν βρέθηκε.'; end if;
  select * into c from public.improvement_cases where id = x.case_id;
  if not public.imp_can_view(c) then raise exception 'Το αρχείο δεν βρέθηκε.'; end if;
  return jsonb_build_object('name', x.file_name, 'mime', x.file_mime, 'data', x.file_data);
end $$;

-- Συγκεντρωτικός πίνακας ΓΔ: ανά κατάστημα/εργαζόμενο + σύνολα ανά στάδιο και έκβαση
create or replace function public.imp_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('improvement.summary');
  return jsonb_build_object(
    'by_stage', (select coalesce(jsonb_object_agg(stage, n), '{}') from (select stage, count(*) n from public.improvement_cases where status = 'open' group by stage) z),
    'by_outcome', (select coalesce(jsonb_object_agg(coalesce(last_outcome, 'none'), n), '{}') from (select last_outcome, count(*) n from public.improvement_cases group by last_outcome) z),
    'open', (select count(*) from public.improvement_cases where status = 'open'),
    'closed', (select count(*) from public.improvement_cases where status = 'closed'),
    'overdue', (select count(*) from public.improvement_cases where status = 'open' and next_review_due < public.athens_today()),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ref', c.ref, 'store', c.store, 'employee_name', c.employee_name, 'employee_code', c.employee_code,
               'stage', c.stage, 'stage_label', public.imp_stage_label(c.stage), 'status', c.status, 'owner', c.owner_email, 'severity', c.severity,
               'last_action', (select x.action from public.improvement_events x where x.case_id = c.id order by x.at desc limit 1), 'last_action_at', c.last_action_at,
               'next_review_due', c.next_review_due, 'last_outcome', c.last_outcome, 'proposed_stage', c.proposed_stage,
               'overdue', c.status = 'open' and c.next_review_due < public.athens_today()) order by c.store, c.employee_name, c.created_at), '[]')
             from public.improvement_cases c));
end $$;

-- ═══════ 19. Πρότυπο σταδίου 2 ═══════
create or replace function public.form_template_upload(p_key text, p_file jsonb, p_body text, p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f jsonb := public.file_check(p_file); v_ver int;
begin
  perform public.require_perm('templates.manage');
  if not exists (select 1 from public.form_templates where key = p_key) then raise exception 'Άγνωστο πρότυπο.'; end if;
  if f is null then
    -- νέα έκδοση μόνο με αλλαγή κειμένου/πεδίων: κρατά το PDF της προηγούμενης έκδοσης
    select jsonb_build_object('name', pdf_name, 'mime', 'application/pdf', 'size', pdf_size, 'data', pdf_data) into f
      from public.form_template_versions where key = p_key order by version desc limit 1;
    if f is null then raise exception 'Ανεβάστε το PDF του εντύπου.'; end if;
  end if;
  if f->>'mime' <> 'application/pdf' then raise exception 'Το πρότυπο εντύπου πρέπει να είναι PDF.'; end if;
  if p_fields is not null and jsonb_typeof(p_fields) <> 'array' then raise exception 'Μη έγκυρα πεδία.'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from public.form_template_versions where key = p_key;
  insert into public.form_template_versions(key, version, pdf_name, pdf_data, pdf_size, body, fields, created_by)
  values (p_key, v_ver, f->>'name', f->>'data', (f->>'size')::int, nullif(trim(coalesce(p_body, '')), ''), coalesce(p_fields, '[]'), public.current_email());
  return jsonb_build_object('ok', true, 'version', v_ver);
end $$;

create or replace function public.form_template_info(p_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.has_perm('templates.manage') or public.has_perm('improvement.view')) then raise exception 'Δεν έχετε πρόσβαση.'; end if;
  return jsonb_build_object('key', p_key, 'label', (select label from public.form_templates where key = p_key),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('version', version, 'pdf_name', pdf_name, 'pdf_size', pdf_size, 'body', body, 'fields', fields,
                   'created_by', created_by, 'created_at', created_at) order by version desc), '[]') from public.form_template_versions where key = p_key));
end $$;

-- Έκδοση εντύπου σταδίου 2 για υπόθεση: αντίγραφο του τρέχοντος προτύπου + τιμές της υπόθεσης τη στιγμή της έκδοσης
create or replace function public.imp_issue_form(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.improvement_cases := public.imp_lock(p_id, null); v public.form_template_versions; v_form bigint;
begin
  perform public.require_perm('improvement.manage');
  if c.stage <> 2 then raise exception 'Το έντυπο αφορά υποθέσεις στο στάδιο 2.'; end if;
  select * into v from public.form_template_versions where key = 'improvement_stage2' order by version desc limit 1;
  if not found then raise exception 'Δεν έχει προστεθεί πρότυπο. Η έκδοση εντύπου ενεργοποιείται όταν η Γενική Διεύθυνση ανεβάσει το PDF.'; end if;
  insert into public.improvement_forms(case_id, template_version_id, pdf_name, pdf_data, body, values, issued_by)
  values (p_id, v.id, v.pdf_name, v.pdf_data, v.body,
          jsonb_build_object('ονοματεπώνυμο', c.employee_name, 'κωδικός', c.employee_code, 'κατάστημα', c.store, 'ειδικότητα', c.specialty,
                             'αριθμός_υπόθεσης', c.ref, 'είδος', c.incident_type, 'περιγραφή', c.description, 'ενέργειες', c.actions,
                             'προθεσμία', to_char(c.next_review_due, 'DD/MM/YYYY'), 'ημερομηνία', to_char(public.athens_today(), 'DD/MM/YYYY'), 'υπεύθυνος', c.owner_email),
          public.current_email())
  returning id into v_form;
  perform public.imp_event(p_id, 'form_issued', jsonb_build_object('form_id', v_form, 'reason', 'Έκδοση ' || v.version));
  return jsonb_build_object('ok', true, 'form_id', v_form);
end $$;

-- Εκτύπωση: μόνο το έντυπο σταδίου 2 μιας υπόθεσης στο πεδίο του χρήστη. Το δικαίωμα «improvement.stage_two_print» ΔΕΝ δίνει
-- πρόσβαση σε PDF μισθοδοσίας, άλλα PDF, μαζικές λήψεις ή backup. Η εκτύπωση καταγράφεται· δεν σημαίνει παράδοση ή υπογραφή.
create or replace function public.imp_form_print(p_form bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.improvement_forms; c public.improvement_cases;
begin
  if not (public.has_perm('improvement.stage_two_print') or public.has_perm('improvement.manage')) then raise exception 'Δεν έχετε δικαίωμα εκτύπωσης εντύπου σταδίου 2.'; end if;
  select * into f from public.improvement_forms where id = p_form;
  if not found then raise exception 'Το έντυπο δεν βρέθηκε.'; end if;
  select * into c from public.improvement_cases where id = f.case_id;
  if not public.can_see_store(c.store) or not public.has_perm('improvement.view') then raise exception 'Το έντυπο δεν βρέθηκε στο πεδίο σας.'; end if;
  update public.improvement_forms set print_count = print_count + 1 where id = p_form;
  perform public.imp_event(c.id, 'form_printed', jsonb_build_object('form_id', p_form));
  return jsonb_build_object('name', f.pdf_name, 'mime', 'application/pdf', 'data', f.pdf_data, 'body', f.body, 'values', f.values);
end $$;

-- Δικαιώματα
insert into public.permissions(code, module, label, description, fixed_roles, sort) values
 ('improvement.view', 'Βελτίωση & συνεργασία', 'Προβολή υποθέσεων βελτίωσης', 'Μέσα στο πεδίο καταστημάτων του ρόλου', null, 90),
 ('improvement.manage', 'Βελτίωση & συνεργασία', 'Καταχώριση / επανεξέταση / στάδια', null, null, 91),
 ('improvement.summary', 'Βελτίωση & συνεργασία', 'Συγκεντρωτικός πίνακας ΓΔ', null, null, 92),
 ('improvement.settings', 'Βελτίωση & συνεργασία', 'Ρυθμίσεις προθεσμιών (ημερολογιακές/εργάσιμες)', null, null, 93),
 ('improvement.stage_two_print', 'Βελτίωση & συνεργασία', 'Εκτύπωση εντύπου σταδίου 2 (μόνο δικό του κατάστημα)',
  'Ειδική εξαίρεση: ΔΕΝ δίνει πρόσβαση σε PDF μισθοδοσίας, άλλα PDF, μαζικές λήψεις ή backup', null, 94)
on conflict (code) do nothing;
insert into public.role_permissions(role, perm, allowed) values
 ('owner','improvement.view',true), ('owner','improvement.manage',true), ('owner','improvement.summary',true), ('owner','improvement.settings',true),
 ('hr','improvement.view',true), ('hr','improvement.manage',true),
 ('manager','improvement.view',true), ('manager','improvement.manage',true), ('manager','improvement.stage_two_print',true)
on conflict (role, perm) do nothing;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.imp_settings(), public.imp_set_day_mode(text), public.imp_create(jsonb), public.imp_update(bigint, jsonb, int),
  public.imp_review(bigint, text, text, date, date, int), public.imp_set_stage(bigint, int, text, date, int), public.imp_link_warning(bigint, uuid, int),
  public.imp_note(bigint, text, jsonb, text, bigint), public.imp_list(text), public.imp_get(bigint), public.imp_file(bigint), public.imp_summary(),
  public.form_template_upload(text, jsonb, text, jsonb), public.form_template_info(text), public.imp_issue_form(bigint), public.imp_form_print(bigint),
  public.imp_stage_label(int), public.imp_suggest_due(int, date) to authenticated;
revoke execute on function public.imp_can_view(public.improvement_cases), public.imp_lock(bigint, int), public.imp_event(bigint, text, jsonb) from authenticated;
grant execute on function public.statlink_info(text), public.statlink_submit(text, jsonb) to anon;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
