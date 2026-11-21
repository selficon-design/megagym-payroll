-- Έκδοση 3.1 · Εργασίες, αναφορές προς κατάστημα, αυτόματος κωδικός εργαζομένου, βάσεις άδειας στην επέτειο
-- 11. Αλλαγή βάσης άδειας στην επέτειο πρόσληψης (όχι 1/1): εφαρμογή προτεινόμενων βάσεων και ανάλυση υποπεριόδων.
-- 13. Αυτόματος, μοναδικός κωδικός εργαζομένου από τον server (ενιαία αρίθμηση, χωρίς επανάχρηση, ασφαλής σε ταυτόχρονη χρήση).
-- 14. «Οι εργασίες μου» (πραγματικές εργασίες με σωστό πεδίο) και «Όλες οι ανατεθειμένες εργασίες» για τη ΓΔ.
-- 15. Αναφορές ΓΔ/εκπαιδευτών προς κατάστημα και manager, με απαντήσεις, ανάληψη, ολοκλήρωση και πλήρες ιστορικό.
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο νέες στήλες/πίνακες/συναρτήσεις· οι υπάρχουσες εργασίες και κωδικοί μένουν ως έχουν.

-- ═══════════════ Κοινό: έλεγχος συνημμένου (base64, ίδιοι κανόνες με τα αιτήματα) ═══════════════
create or replace function public.file_check(p jsonb) returns jsonb
language plpgsql immutable as $$
declare v_size int;
begin
  if p is null or jsonb_typeof(p) <> 'object' or coalesce(p->>'data', '') = '' then return null; end if;
  if coalesce(p->>'mime', '') not in ('application/pdf','image/jpeg','image/png','image/webp','image/heic') then
    raise exception 'Επιτρέπονται μόνο PDF ή εικόνες (JPG, PNG, WEBP, HEIC).';
  end if;
  begin v_size := length(decode(p->>'data', 'base64')); exception when others then raise exception 'Μη έγκυρο αρχείο.'; end;
  if v_size <= 0 or v_size > 4194304 then raise exception 'Το αρχείο πρέπει να είναι έως 4 MB.'; end if;
  return jsonb_build_object('name', left(coalesce(nullif(trim(p->>'name'), ''), 'αρχείο'), 200), 'mime', p->>'mime', 'size', v_size, 'data', p->>'data');
end $$;

-- ═══════════════ 15. Πίνακες αναφορών προς κατάστημα (χρειάζονται και στις εργασίες) ═══════════════
create table if not exists public.store_reports (
  id               bigserial primary key,
  ref              text not null unique,
  store            text not null references public.stores(name) on update cascade,
  manager_email    text,
  subject          text not null check (length(trim(subject)) between 3 and 200),
  description      text not null check (length(trim(description)) between 5 and 8000),
  observations     text,
  required_actions text,
  action_required  boolean not null default false,
  due_date         date,
  status           text not null default 'open' check (status in ('open','in_progress','done')),
  created_by       text not null,
  created_role     text not null,
  created_at       timestamptz not null default now(),
  claimed_by       text, claimed_at timestamptz,
  completed_by     text, completed_at timestamptz, completion_note text,
  updated_at       timestamptz not null default now()
);
create index if not exists store_reports_store_idx on public.store_reports(store, created_at desc);
create table if not exists public.store_report_events (
  id         bigserial primary key,
  report_id  bigint not null references public.store_reports(id),
  action     text not null check (action in ('submitted','read','reply','claimed','completed','attachment')),
  note       text,
  file_name  text, file_mime text, file_size int, file_data text,
  actor      text not null,
  actor_role text,
  at         timestamptz not null default now()
);
create index if not exists store_report_events_idx on public.store_report_events(report_id, at);
create table if not exists public.user_notices (
  id         bigserial primary key,
  user_email text not null,
  kind       text not null,
  title      text not null,
  link       text,
  report_id  bigint references public.store_reports(id),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists user_notices_unread_idx on public.user_notices(user_email) where read_at is null;
alter table public.store_reports enable row level security;
alter table public.store_report_events enable row level security;
alter table public.user_notices enable row level security;
revoke all on public.store_reports, public.store_report_events, public.user_notices from anon, authenticated;

-- Ορατότητα: ΓΔ όλες · εκπαιδευτής τις δικές του · manager του καταστήματός του
create or replace function public.store_report_visible(s public.store_reports) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_perm('store_reports.view_all')
      or (public.has_perm('store_reports.create') and s.created_by = public.current_email())
      or (public.has_perm('store_reports.respond') and public.my_role() = 'manager' and public.can_see_store(s.store))
$$;

-- ═══════════════ 11. Βάσεις άδειας στην επέτειο πρόσληψης ═══════════════
-- Εφαρμόζει τις προτεινόμενες βάσεις (πρόσληψη, 1η και 2η επέτειος, αλλαγές πενθήμερου/εξαήμερου) που δεν υπάρχουν ακόμη.
-- Καμία αναδρομική αλλαγή: όσες βάσεις υπάρχουν μένουν ως έχουν· οι νέες ισχύουν από την ημερομηνία τους.
create or replace function public.leave_apply_bases(p_code text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; v_n int := 0; v_rows jsonb := '[]'::jsonb;
begin
  perform public.require_perm('leave.adjust');
  for x in select * from jsonb_array_elements(public.leave_suggest_bases(p_code)->'rows') loop
    if (x->>'exists')::boolean then continue; end if;
    perform public.leave_set_base(p_code, (x->>'annual_days')::numeric, (x->>'valid_from')::date,
      coalesce(nullif(trim(p_note), ''), 'Βάση από ' || case when (x->>'service_years')::int = 0 then 'την πρόσληψη' else 'την ' || (x->>'service_years') || 'η επέτειο πρόσληψης' end));
    v_n := v_n + 1; v_rows := v_rows || x;
  end loop;
  return jsonb_build_object('ok', true, 'added', v_n, 'rows', v_rows);
end $$;

-- Ανάλυση ημερολογιακού έτους σε υποπεριόδους βάσης (π.χ. 01/01–14/11 με 20 ημέρες, 15/11–31/12 με 21): το άθροισμα
-- ισούται με τη συνολική αναλογία του έτους. Ο υπολογισμός είναι ο υπάρχων ημερήσιος (βάση ÷ 12 ÷ ημέρες του μήνα).
create or replace function public.leave_breakdown(p_code text, p_year int, p_upto date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; v_a date; v_b date; r record; v_out jsonb := '[]'::jsonb; v_sum numeric := 0; v_part numeric;
begin
  if not public.has_perm('leave.view') or not public.employee_in_scope(p_code) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  select * into e from public.employees where code = p_code;
  v_a := greatest(make_date(p_year, 1, 1), coalesce(e.hire_date, make_date(p_year, 1, 1)));
  v_b := least(coalesce(p_upto, make_date(p_year, 12, 31)), make_date(p_year, 12, 31), coalesce(e.leave_date, make_date(p_year, 12, 31)));
  for r in
    select x.annual_days, greatest(x.valid_from, v_a) f, least(x.nxt - 1, v_b) t, x.valid_from
      from (select annual_days, valid_from, coalesce(lead(valid_from) over (order by valid_from), date '9999-12-31') nxt
              from public.leave_entitlements where employee_code = p_code and superseded_at is null) x
     where x.valid_from <= v_b and x.nxt > v_a order by x.valid_from
  loop
    select coalesce(sum(r.annual_days / 12.0 / extract(day from (date_trunc('month', d) + interval '1 month - 1 day'))::numeric), 0) into v_part
      from generate_series(r.f, r.t, interval '1 day') d;
    v_out := v_out || jsonb_build_object('from', r.f, 'to', r.t, 'annual_days', r.annual_days, 'valid_from', r.valid_from,
                                         'work_week', (select work_week from public.work_terms_on(p_code, r.f)), 'accrued', round(v_part, 4));
    v_sum := v_sum + v_part;
  end loop;
  return jsonb_build_object('year', p_year, 'from', v_a, 'to', v_b, 'periods', v_out, 'accrued', round(v_sum, 4),
    'rule', 'Ημερήσια αναλογία: ετήσια βάση ÷ 12 ÷ ημέρες του μήνα, για κάθε ημέρα της υποπεριόδου (ίδιος κανόνας με τον μήνα πρόσληψης).');
end $$;

-- ═══════════════ 13. Αυτόματος κωδικός εργαζομένου ═══════════════
create table if not exists public.employee_code_counter (
  prefix text primary key,
  width  int not null default 0,
  last   bigint not null default 0
);
alter table public.employee_code_counter enable row level security;
revoke all on public.employee_code_counter from anon, authenticated;

-- Επόμενος κωδικός: ίδια μορφή με τους υπάρχοντες (πιο συχνό πρόθεμα και πλήθος ψηφίων), αριθμός μεγαλύτερος από τον
-- μεγαλύτερο υπάρχοντα. Ο μετρητής μόνο αυξάνει (καμία επανάχρηση, ακόμη κι αν σβηστεί γραμμή) και κλειδώνεται ανά πρόθεμα.
create or replace function public.employee_next_code() returns text
language plpgsql security definer set search_path = public as $$
declare v_prefix text; v_width int; v_max bigint; v_next bigint; v_code text;
begin
  select coalesce(m[1], ''), length(m[2]) into v_prefix, v_width
    from (select regexp_match(code, '^([^0-9]*)([0-9]+)$') m from public.employees) z
   where m is not null group by 1, 2 order by count(*) desc, 1 limit 1;
  v_prefix := coalesce(v_prefix, ''); v_width := coalesce(v_width, 0);
  insert into public.employee_code_counter(prefix, width, last) values (v_prefix, v_width, 0) on conflict (prefix) do nothing;
  perform 1 from public.employee_code_counter where prefix = v_prefix for update;
  select max((regexp_match(code, '^' || regexp_replace(v_prefix, '([.^$*+?()[\]{}|\\])', '\\\1', 'g') || '([0-9]+)$'))[1]::bigint) into v_max
    from public.employees;
  select greatest(last, coalesce(v_max, 0)) + 1 into v_next from public.employee_code_counter where prefix = v_prefix;
  loop
    v_code := v_prefix || lpad(v_next::text, greatest(v_width, length(v_next::text)), '0');
    exit when not exists (select 1 from public.employees where code = v_code);
    v_next := v_next + 1;
  end loop;
  update public.employee_code_counter set last = v_next, width = v_width where prefix = v_prefix;
  return v_code;
end $$;

create or replace function public.employee_auto_code() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.code is null or trim(new.code) = '' or upper(trim(new.code)) = 'AUTO' then
    new.code := public.employee_next_code();
  end if;
  return new;
end $$;
drop trigger if exists employees_auto_code on public.employees;
create trigger employees_auto_code before insert on public.employees for each row execute function public.employee_auto_code();

-- ═══════════════ 14. Εργασίες ═══════════════
-- Οι εργασίες HR/λογιστηρίου (request_tasks) κρατούν τις καταστάσεις τους (Ανοιχτή → Ολοκληρώθηκε) και προστίθενται
-- προαιρετικά: προθεσμία, ανάληψη, τελευταία ενημέρωση. Σχόλια/συνημμένα/ιστορικό στον πίνακα task_notes.
alter table public.request_tasks add column if not exists due_date date,
  add column if not exists claimed_by text, add column if not exists claimed_at timestamptz,
  add column if not exists updated_at timestamptz;
update public.request_tasks set updated_at = coalesce(done_at, created_at) where updated_at is null;

create table if not exists public.task_notes (
  id         bigserial primary key,
  task_kind  text not null check (task_kind in ('request_task','implementation','store_report')),
  task_ref   text not null,
  action     text not null check (action in ('created','comment','claimed','done','attachment','due_changed','read','reply')),
  note       text,
  file_name  text, file_mime text, file_size int, file_data text,
  actor      text not null,
  actor_role text,
  at         timestamptz not null default now()
);
create index if not exists task_notes_ref_idx on public.task_notes(task_kind, task_ref, at);
alter table public.task_notes enable row level security;
revoke all on public.task_notes from anon, authenticated;

drop function if exists public.req_task_add(uuid, text, text);
create function public.req_task_add(p_id uuid, p_role text, p_text text, p_due date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_id bigint;
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, null);
  if p_role not in ('hr','accounting') then raise exception 'Επιλέξτε HR ή λογιστήριο.'; end if;
  if p_due is not null and p_due < (now() at time zone 'Europe/Athens')::date then raise exception 'Η προθεσμία δεν μπορεί να είναι στο παρελθόν.'; end if;
  insert into public.request_tasks(request_id, owner_role, description, created_by, due_date, updated_at)
  values (p_id, p_role, trim(p_text), public.current_email(), p_due, now()) returning id into v_id;
  perform public.req_event(p_id, 'task_added', null, null, trim(p_text), jsonb_build_object('task', v_id, 'owner_role', p_role, 'due', p_due), true);
  insert into public.task_notes(task_kind, task_ref, action, note, actor, actor_role) values ('request_task', v_id::text, 'created', trim(p_text), public.current_email(), public.my_role());
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.req_task_done(p_task bigint, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t public.request_tasks; r public.hr_requests;
begin
  select * into t from public.request_tasks where id = p_task for update;
  if not found then raise exception 'Η ενέργεια δεν βρέθηκε.'; end if;
  select * into r from public.hr_requests where id = t.request_id;
  if not (public.my_role() = t.owner_role or public.my_role() = 'owner') or not public.can_see_store(r.store) then raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.'; end if;
  if t.status = 'done' then return jsonb_build_object('ok', true, 'already', true); end if;
  update public.request_tasks set status = 'done', done_by = public.current_email(), done_at = now(), done_note = nullif(trim(p_note), ''), updated_at = now() where id = p_task;
  insert into public.hr_request_events(request_id, actor, actor_role, action, note, internal, data)
  values (t.request_id, public.current_email(), public.my_role(), 'task_done', nullif(trim(p_note), ''), true, jsonb_build_object('task', t.id));
  insert into public.task_notes(task_kind, task_ref, action, note, actor, actor_role) values ('request_task', t.id::text, 'done', nullif(trim(p_note), ''), public.current_email(), public.my_role());
  return jsonb_build_object('ok', true);
end $$;

-- Ενιαία λίστα εργασιών (πηγή αλήθειας: οι πίνακες των αιτημάτων/αναφορών). p_mine = μόνο όσες είναι ευθύνη του χρήστη.
-- Η ΓΔ βλέπει όλες χωρίς να χρειάζεται να τις αναλάβει.
create or replace function public.tasks_all(p_mine boolean default true)
returns table (kind text, ref text, title text, related_ref text, related_id text, store text, employee_name text,
               assigned_by text, assigned_at timestamptz, responsible text, claimed_by text, due_date date, status text, status_label text,
               updated_at timestamptz, notes int, files int, overdue boolean, can_act boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_role text := public.my_role(); v_me text := public.current_email(); v_today date := (now() at time zone 'Europe/Athens')::date;
        v_all boolean := public.has_perm('tasks.view_all');
begin
  if v_role is null then raise exception 'Δεν έχετε πρόσβαση.'; end if;
  if not p_mine and not v_all then raise exception 'Η συνολική προβολή εργασιών είναι διαθέσιμη μόνο στη Γενική Διεύθυνση.'; end if;
  return query
  -- 1. Εργασίες HR / λογιστηρίου σε αιτήματα
  select 'request_task'::text, t.id::text, t.description, r.ref, r.id::text, r.store, r.employee_name,
         t.created_by, t.created_at, case t.owner_role when 'hr' then 'HR' else 'Λογιστήριο' end, t.claimed_by, t.due_date,
         case when t.status = 'done' then 'done' when t.claimed_by is not null then 'in_progress' else 'open' end,
         case when t.status = 'done' then 'Ολοκληρώθηκε' when t.claimed_by is not null then 'Σε εξέλιξη' else 'Ανοιχτή' end,
         coalesce(t.updated_at, t.created_at),
         (select count(*)::int from public.task_notes n where n.task_kind = 'request_task' and n.task_ref = t.id::text and n.action = 'comment'),
         (select count(*)::int from public.task_notes n where n.task_kind = 'request_task' and n.task_ref = t.id::text and n.file_data is not null),
         t.status <> 'done' and t.due_date is not null and t.due_date < v_today,
         t.status <> 'done' and (t.owner_role = v_role or v_role = 'owner')
    from public.request_tasks t join public.hr_requests r on r.id = t.request_id
   where public.can_see_store(r.store) and ((not p_mine) or t.owner_role = v_role)
  union all
  -- 2. Υλοποίηση εγκεκριμένων αιτημάτων από τον manager (πρώτα ενημέρωση εργαζομένου, μετά ανάληψη)
  select 'implementation', r.id::text, 'Υλοποίηση: ' || public.req_category_label(r.category), r.ref, r.id::text, r.store, r.employee_name,
         coalesce((select d.decided_by from public.hr_decisions d where d.request_id = r.id and d.superseded_at is null), r.assignee),
         coalesce((select d.decided_at from public.hr_decisions d where d.request_id = r.id and d.superseded_at is null), r.updated_at),
         coalesce(r.impl_claimed_by, 'Manager ' || r.store), r.impl_claimed_by, null::date,
         case when r.status = 'completed' then 'done' when r.impl_claimed_by is not null then 'in_progress' when r.notified_at is null then 'waiting' else 'open' end,
         case when r.status = 'completed' then 'Ολοκληρώθηκε' when r.impl_claimed_by is not null then 'Σε εξέλιξη (ανάληψη)'
              when r.notified_at is null then 'Αναμονή ενημέρωσης εργαζομένου' else 'Ανοιχτή' end,
         r.updated_at,
         (select count(*)::int from public.task_notes n where n.task_kind = 'implementation' and n.task_ref = r.id::text and n.action = 'comment'),
         (select count(*)::int from public.hr_attachments a where a.request_id = r.id),
         false,
         r.status = 'approved' and public.has_perm('requests.implement') and public.can_see_store(r.store)
    from public.hr_requests r
   where public.req_flow(r.category) in ('leave','generic','gm') and (r.status = 'approved' or (r.status = 'completed' and r.impl_claimed_by is not null))
     and public.can_see_store(r.store)
     and ((not p_mine) or (public.has_perm('requests.implement') and v_role = 'manager'))
  union all
  -- 3. Αναφορές προς κατάστημα που απαιτούν ενέργεια
  select 'store_report', s.id::text, s.subject, s.ref, s.id::text, s.store, null::text,
         s.created_by, s.created_at, coalesce(s.manager_email, 'Manager ' || s.store), s.claimed_by, s.due_date,
         case when s.status = 'done' then 'done' when s.claimed_by is not null then 'in_progress' else 'open' end,
         case when s.status = 'done' then 'Ολοκληρώθηκε' when s.claimed_by is not null then 'Σε εξέλιξη' else 'Ανοιχτή' end,
         s.updated_at,
         (select count(*)::int from public.store_report_events x where x.report_id = s.id and x.action = 'reply'),
         (select count(*)::int from public.store_report_events x where x.report_id = s.id and x.file_data is not null),
         s.status <> 'done' and s.due_date is not null and s.due_date < v_today,
         s.status <> 'done' and public.has_perm('store_reports.respond') and public.can_see_store(s.store)
    from public.store_reports s
   where s.action_required and public.store_report_visible(s)
     and ((not p_mine) or (public.has_perm('store_reports.respond') and v_role = 'manager' and public.can_see_store(s.store)));
end $$;

-- Ανάληψη / σχόλιο / συνημμένο σε εργασία HR-λογιστηρίου
create or replace function public.task_claim(p_task bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.request_tasks; r public.hr_requests;
begin
  select * into t from public.request_tasks where id = p_task for update;
  if not found then raise exception 'Η εργασία δεν βρέθηκε.'; end if;
  select * into r from public.hr_requests where id = t.request_id;
  if public.my_role() <> t.owner_role or not public.can_see_store(r.store) then raise exception 'Η εργασία δεν είναι στην ευθύνη σας.'; end if;
  if t.status = 'done' then raise exception 'Η εργασία έχει ολοκληρωθεί.'; end if;
  if t.claimed_by is not null then raise exception 'Η εργασία έχει ήδη αναληφθεί από %.', t.claimed_by; end if;
  update public.request_tasks set claimed_by = public.current_email(), claimed_at = now(), updated_at = now() where id = p_task;
  insert into public.task_notes(task_kind, task_ref, action, actor, actor_role) values ('request_task', p_task::text, 'claimed', public.current_email(), public.my_role());
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.task_note(p_kind text, p_ref text, p_note text, p_file jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f jsonb := public.file_check(p_file); v_store text; v_ok boolean := false; t public.request_tasks;
begin
  if length(trim(coalesce(p_note, ''))) < 2 and f is null then raise exception 'Γράψτε σχόλιο ή επισυνάψτε αρχείο.'; end if;
  if p_kind = 'request_task' then
    select * into t from public.request_tasks where id = p_ref::bigint;
    select store into v_store from public.hr_requests where id = t.request_id;
    v_ok := found and public.can_see_store(v_store) and (public.my_role() in (t.owner_role, 'owner') or public.has_perm('requests.decide'));
    if v_ok then update public.request_tasks set updated_at = now() where id = t.id; end if;
  elsif p_kind = 'implementation' then
    select store into v_store from public.hr_requests where id = p_ref::uuid;
    v_ok := found and public.can_see_store(v_store) and (public.has_perm('requests.implement') or public.has_perm('requests.decide'));
  else raise exception 'Μη έγκυρο είδος εργασίας.'; end if;
  if not v_ok then raise exception 'Η εργασία δεν βρέθηκε στο πεδίο σας.'; end if;
  insert into public.task_notes(task_kind, task_ref, action, note, file_name, file_mime, file_size, file_data, actor, actor_role)
  values (p_kind, p_ref, case when f is not null and length(trim(coalesce(p_note, ''))) < 2 then 'attachment' else 'comment' end, nullif(trim(p_note), ''),
          f->>'name', f->>'mime', (f->>'size')::int, f->>'data', public.current_email(), public.my_role());
  return jsonb_build_object('ok', true);
end $$;

-- Πλήρες ιστορικό εργασίας (σχόλια, συνημμένα, ενέργειες)· τα δεδομένα αρχείων δίνονται χωριστά (task_file)
create or replace function public.task_history(p_kind text, p_ref text)
returns table (id text, action text, note text, file_name text, actor text, at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_store text;
begin
  if p_kind = 'request_task' then select r.store into v_store from public.request_tasks t join public.hr_requests r on r.id = t.request_id where t.id = p_ref::bigint;
  elsif p_kind = 'implementation' then select r.store into v_store from public.hr_requests r where r.id = p_ref::uuid;
  elsif p_kind = 'store_report' then
    if not exists (select 1 from public.store_reports s where s.id = p_ref::bigint and public.store_report_visible(s)) then raise exception 'Δεν βρέθηκε.'; end if;
    return query select 's' || x.id, x.action, x.note, x.file_name, x.actor, x.at from public.store_report_events x where x.report_id = p_ref::bigint order by x.at;
    return;
  end if;
  if v_store is null or not public.can_see_store(v_store) or not (public.has_perm('requests.view') or public.my_role() in ('hr','accounting','owner')) then raise exception 'Δεν βρέθηκε.'; end if;
  return query
    select 'n' || n.id, n.action, n.note, n.file_name, n.actor, n.at from public.task_notes n where n.task_kind = p_kind and n.task_ref = p_ref
    union all
    select 'e' || e.id, e.action, e.note, null, e.actor, e.at from public.hr_request_events e
     where p_kind = 'implementation' and e.request_id = p_ref::uuid and e.action in ('decide','revise','notified','impl_claimed','implemented')
    order by 6;
end $$;

create or replace function public.task_file(p_id text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare n public.task_notes; x public.store_report_events;
begin
  if left(p_id, 1) = 'n' then
    select * into n from public.task_notes where id = substr(p_id, 2)::bigint and file_data is not null;
    if not found then raise exception 'Το αρχείο δεν βρέθηκε.'; end if;
    perform 1 from public.task_history(n.task_kind, n.task_ref) limit 1;   -- ίδιος έλεγχος πρόσβασης
    return jsonb_build_object('name', n.file_name, 'mime', n.file_mime, 'data', n.file_data);
  elsif left(p_id, 1) = 's' then
    select * into x from public.store_report_events where id = substr(p_id, 2)::bigint and file_data is not null;
    if not found or not exists (select 1 from public.store_reports s where s.id = x.report_id and public.store_report_visible(s)) then raise exception 'Το αρχείο δεν βρέθηκε.'; end if;
    return jsonb_build_object('name', x.file_name, 'mime', x.file_mime, 'data', x.file_data);
  end if;
  raise exception 'Το αρχείο δεν βρέθηκε.';
end $$;

-- ═══════════════ 15. Αναφορές προς κατάστημα ═══════════════
create or replace function public.srep_notify(p_report bigint, p_to text[], p_kind text, p_title text) returns void
language sql security definer set search_path = public as $$
  insert into public.user_notices(user_email, kind, title, link, report_id)
  select distinct x, p_kind, left(p_title, 300), '#/store-reports?id=' || p_report, p_report from unnest(p_to) x
   where x is not null and x is distinct from public.current_email()
$$;

create or replace function public.srep_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_ref text; v_store text := trim(coalesce(p->>'store', '')); v_mgr text := nullif(trim(coalesce(p->>'manager_email', '')), '');
        v_due date; f jsonb; v_to text[]; v_act boolean := coalesce((p->>'action_required')::boolean, false);
begin
  perform public.require_perm('store_reports.create');
  if not exists (select 1 from public.stores where name = v_store) then raise exception 'Επιλέξτε κατάστημα.'; end if;
  if v_mgr is not null and not exists (select 1 from public.app_users where email = v_mgr and role = 'manager' and store = v_store and active) then
    raise exception 'Ο manager δεν ανήκει στο κατάστημα.';
  end if;
  begin v_due := nullif(p->>'due_date', '')::date; exception when others then raise exception 'Μη έγκυρη προθεσμία.'; end;
  if v_act and length(trim(coalesce(p->>'required_actions', ''))) < 3 then raise exception 'Περιγράψτε τις απαιτούμενες ενέργειες.'; end if;
  v_ref := 'ΑΚ-' || to_char(now() at time zone 'Europe/Athens', 'YYYY') || '-' || lpad((coalesce((select count(*) from public.store_reports), 0) + 1)::text, 5, '0');
  while exists (select 1 from public.store_reports where ref = v_ref) loop v_ref := v_ref || 'α'; end loop;
  insert into public.store_reports(ref, store, manager_email, subject, description, observations, required_actions, action_required, due_date, created_by, created_role)
  values (v_ref, v_store, v_mgr, trim(p->>'subject'), trim(p->>'description'), nullif(trim(coalesce(p->>'observations', '')), ''),
          nullif(trim(coalesce(p->>'required_actions', '')), ''), v_act, v_due, public.current_email(), public.my_role())
  returning id into v_id;
  insert into public.store_report_events(report_id, action, actor, actor_role) values (v_id, 'submitted', public.current_email(), public.my_role());
  for f in select public.file_check(x) from jsonb_array_elements(coalesce(p->'files', '[]'::jsonb)) x loop
    if f is null then continue; end if;
    insert into public.store_report_events(report_id, action, file_name, file_mime, file_size, file_data, actor, actor_role)
    values (v_id, 'attachment', f->>'name', f->>'mime', (f->>'size')::int, f->>'data', public.current_email(), public.my_role());
  end loop;
  -- ειδοποίηση: ο επιλεγμένος manager ή όλοι οι managers του καταστήματος
  select array_agg(email) into v_to from public.app_users where active and role = 'manager' and store = v_store and (v_mgr is null or email = v_mgr);
  perform public.srep_notify(v_id, v_to, 'store_report', 'Νέα αναφορά ' || v_ref || ': ' || trim(p->>'subject') || case when v_act then ' (απαιτείται ενέργεια)' else '' end);
  return jsonb_build_object('ok', true, 'id', v_id, 'ref', v_ref);
end $$;

create or replace function public.srep_list(p_store text default null, p_status text default null)
returns table (id bigint, ref text, store text, manager_email text, subject text, action_required boolean, due_date date, status text,
               created_by text, created_role text, created_at timestamptz, updated_at timestamptz, replies int, unread boolean, overdue boolean)
language sql stable security definer set search_path = public as $$
  select s.id, s.ref, s.store, s.manager_email, s.subject, s.action_required, s.due_date, s.status, s.created_by, s.created_role, s.created_at, s.updated_at,
         (select count(*)::int from public.store_report_events x where x.report_id = s.id and x.action = 'reply'),
         exists (select 1 from public.user_notices n where n.report_id = s.id and n.user_email = public.current_email() and n.read_at is null),
         s.status <> 'done' and s.due_date is not null and s.due_date < (now() at time zone 'Europe/Athens')::date
    from public.store_reports s
   where public.store_report_visible(s) and (p_store is null or s.store = p_store) and (p_status is null or s.status = p_status)
   order by s.created_at desc limit 500
$$;

-- Άνοιγμα αναφοράς: καταγράφεται η (πρώτη) ανάγνωση ανά χρήστη και σημειώνονται ως διαβασμένες οι ειδοποιήσεις της
create or replace function public.srep_get(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.store_reports;
begin
  select * into s from public.store_reports where id = p_id;
  if not found or not public.store_report_visible(s) then raise exception 'Η αναφορά δεν βρέθηκε.'; end if;
  if s.created_by <> public.current_email() and not exists (select 1 from public.store_report_events where report_id = p_id and action = 'read' and actor = public.current_email()) then
    insert into public.store_report_events(report_id, action, actor, actor_role) values (p_id, 'read', public.current_email(), public.my_role());
  end if;
  update public.user_notices set read_at = now() where report_id = p_id and user_email = public.current_email() and read_at is null;
  return to_jsonb(s) || jsonb_build_object(
    'events', (select coalesce(jsonb_agg(jsonb_build_object('id', 's' || x.id, 'action', x.action, 'note', x.note, 'file_name', x.file_name, 'actor', x.actor,
                 'actor_role', x.actor_role, 'at', x.at) order by x.at), '[]') from public.store_report_events x where x.report_id = p_id),
    'can_respond', public.has_perm('store_reports.respond') and public.my_role() = 'manager' and public.can_see_store(s.store) and s.status <> 'done',
    'can_reply', s.status <> 'done' and (s.created_by = public.current_email() or public.has_perm('store_reports.view_all')
                 or (public.has_perm('store_reports.respond') and public.can_see_store(s.store))));
end $$;

create or replace function public.srep_act(p_id bigint, p_action text, p_note text default null, p_file jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.store_reports; f jsonb := public.file_check(p_file); v_note text := nullif(trim(coalesce(p_note, '')), ''); v_to text[];
        v_mgr boolean;
begin
  select * into s from public.store_reports where id = p_id for update;
  if not found or not public.store_report_visible(s) then raise exception 'Η αναφορά δεν βρέθηκε.'; end if;
  v_mgr := public.has_perm('store_reports.respond') and public.my_role() = 'manager' and public.can_see_store(s.store);
  if s.status = 'done' then raise exception 'Η αναφορά έχει ολοκληρωθεί.'; end if;
  if p_action = 'reply' then
    if v_note is null and f is null then raise exception 'Γράψτε απάντηση.'; end if;
  elsif p_action = 'claimed' then
    if not v_mgr then raise exception 'Την ανάληψη κάνει ο manager του καταστήματος.'; end if;
    if not s.action_required then raise exception 'Η αναφορά δεν απαιτεί ενέργεια.'; end if;
    if s.claimed_by is not null then raise exception 'Έχει ήδη αναληφθεί από %.', s.claimed_by; end if;
    update public.store_reports set claimed_by = public.current_email(), claimed_at = now(), status = 'in_progress' where id = p_id;
  elsif p_action = 'completed' then
    if not v_mgr then raise exception 'Την ολοκλήρωση κάνει ο manager του καταστήματος.'; end if;
    if v_note is null or length(v_note) < 3 then raise exception 'Γράψτε σχόλιο ολοκλήρωσης.'; end if;
    update public.store_reports set status = 'done', completed_by = public.current_email(), completed_at = now(), completion_note = v_note,
           claimed_by = coalesce(claimed_by, public.current_email()), claimed_at = coalesce(claimed_at, now()) where id = p_id;
  else raise exception 'Μη έγκυρη ενέργεια.'; end if;
  update public.store_reports set updated_at = now() where id = p_id;
  insert into public.store_report_events(report_id, action, note, file_name, file_mime, file_size, file_data, actor, actor_role)
  values (p_id, p_action, v_note, f->>'name', f->>'mime', (f->>'size')::int, f->>'data', public.current_email(), public.my_role());
  -- ενημέρωση της άλλης πλευράς: συντάκτης ↔ manager(s)
  if v_mgr then v_to := array[s.created_by];
  else select array_agg(email) into v_to from public.app_users where active and role = 'manager' and store = s.store and (s.manager_email is null or email = s.manager_email);
  end if;
  perform public.srep_notify(p_id, v_to, 'store_report_' || p_action,
    case p_action when 'reply' then 'Απάντηση' when 'claimed' then 'Ανάληψη' else 'Ολοκλήρωση' end || ' στην αναφορά ' || s.ref || ': ' || s.subject);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.notice_count() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.user_notices n join public.store_reports s on s.id = n.report_id
   where n.user_email = public.current_email() and n.read_at is null and public.store_report_visible(s)
$$;

-- ═══════════════ Δικαιώματα ═══════════════
insert into public.permissions(code, module, label, description, fixed_roles, sort) values
 ('tasks.view_all', 'Αιτήματα', 'Όλες οι ανατεθειμένες εργασίες (εποπτεία)', 'Προβολή όλων των εργασιών όλων των χρηστών και καταστημάτων, χωρίς ανάληψη', null, 38),
 ('store_reports.create', 'Αναφορές καταστημάτων', 'Υποβολή αναφοράς προς κατάστημα', 'Βλέπει τις δικές του αναφορές και τις απαντήσεις τους', null, 60),
 ('store_reports.respond', 'Αναφορές καταστημάτων', 'Απάντηση / ανάληψη / ολοκλήρωση αναφορών καταστήματος', 'Μόνο για αναφορές του δικού του καταστήματος', null, 61),
 ('store_reports.view_all', 'Αναφορές καταστημάτων', 'Προβολή όλων των αναφορών καταστημάτων', null, null, 62)
on conflict (code) do nothing;
insert into public.role_permissions(role, perm, allowed) values
 ('owner','tasks.view_all',true), ('owner','store_reports.create',true), ('owner','store_reports.view_all',true),
 ('trainer','store_reports.create',true), ('manager','store_reports.respond',true)
on conflict (role, perm) do nothing;

-- ═══════════════ Δικαιώματα εκτέλεσης ═══════════════
revoke execute on all functions in schema public from public, anon;
grant execute on function public.leave_apply_bases(text, text), public.leave_breakdown(text, int, date),
  public.req_task_add(uuid, text, text, date), public.req_task_done(bigint, text), public.tasks_all(boolean), public.task_claim(bigint),
  public.task_note(text, text, text, jsonb), public.task_history(text, text), public.task_file(text),
  public.srep_create(jsonb), public.srep_list(text, text), public.srep_get(bigint), public.srep_act(bigint, text, text, jsonb), public.notice_count() to authenticated;
revoke execute on function public.employee_next_code(), public.employee_auto_code(), public.srep_notify(bigint, text[], text, text),
  public.store_report_visible(public.store_reports), public.file_check(jsonb) from authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;

-- Managers καταστήματος για την επιλογή «αρμόδιος manager» στη νέα αναφορά (μόνο όνομα και email)
create or replace function public.srep_managers(p_store text) returns table (email text, name text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('store_reports.create');
  return query select u.email, u.name from public.app_users u where u.active and u.role = 'manager' and u.store = p_store order by u.name;
end $$;
revoke execute on function public.srep_managers(text) from public, anon;
grant execute on function public.srep_managers(text) to authenticated;
