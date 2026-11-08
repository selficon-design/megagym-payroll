-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Έκδοση 3.0 · Μέρος 3: Πρόγραμμα προσωπικού
--   Σταθερό εβδομαδιαίο πρόγραμμα με ημερομηνία ισχύος · προσωρινές αλλαγές ανά ημερομηνία (αυτόματη
--   επιστροφή) · μόνιμες αλλαγές με νέα ημερομηνία ισχύος · έτοιμα ωράρια · σπαστά ωράρια · ωράρια
--   λειτουργίας · κάλυψη ανά μισάωρο · οριστικοποίηση εβδομάδας και πλήρες ιστορικό με αιτιολογία.
--   + Μόνιμη μεταφορά καταστήματος με ημερομηνία ισχύος.
--   + Δομή (μόνο δεδομένα) για μελλοντικό προτεινόμενο πρόγραμμα. ΚΑΜΙΑ αυτόματη δημιουργία προγράμματος.
-- Ώρες: διαστήματα ["ΩΩ:ΛΛ","ΩΩ:ΛΛ"] την ίδια ημέρα. Σπαστό = περισσότερα διαστήματα· μετράει μόνο ο χρόνος των διαστημάτων.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ─────────────── Έτοιμα ωράρια & ωράρια λειτουργίας ───────────────
create table public.shift_templates (
  id         bigserial primary key,
  label      text not null check (length(trim(label)) between 1 and 60),
  segments   jsonb not null,
  store      text references public.stores(name) on update cascade,   -- κενό = όλα τα καταστήματα
  active     boolean not null default true,
  sort       int not null default 0,
  created_by text not null default 'system',
  created_at timestamptz not null default now()
);
insert into public.shift_templates(label, segments, sort) values
  ('06:30–12:30', '[["06:30","12:30"]]', 1), ('08:00–16:00', '[["08:00","16:00"]]', 2),
  ('13:00–15:00', '[["13:00","15:00"]]', 3), ('08:00–12:00 & 17:00–21:00', '[["08:00","12:00"],["17:00","21:00"]]', 4);

-- Ωράριο λειτουργίας καταστήματος/τμήματος ανά ημέρα εβδομάδας (1 = Δευτέρα … 7 = Κυριακή), με ημερομηνία ισχύος
create table public.store_hours (
  id         bigserial primary key,
  store      text not null references public.stores(name) on update cascade,
  specialty  text references public.specialties(name) on update cascade,   -- κενό = όλο το κατάστημα
  weekday    smallint not null check (weekday between 1 and 7),
  opens      time not null,
  closes     time not null,
  valid_from date not null default date '2000-01-01',
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  check (closes > opens),
  unique nulls not distinct (store, specialty, weekday, valid_from)
);

-- ─────────────── Πρόγραμμα ───────────────
-- Σταθερό εβδομαδιαίο πρόγραμμα: days = { "1": [["08:00","16:00"]], …, "7": [] }
create table public.schedule_patterns (
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade,
  store         text not null,
  valid_from    date not null,
  valid_to      date,
  days          jsonb not null,
  status        text not null default 'active' check (status in ('active','superseded')),
  reason        text,
  created_by    text not null,
  created_at    timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from)
);
create unique index one_active_pattern_start on public.schedule_patterns(employee_code, valid_from) where status = 'active';
create index schedule_patterns_store_idx on public.schedule_patterns(store, valid_from);

-- Προσωρινή αλλαγή για συγκεκριμένη ημερομηνία ([] = εκτός προγράμματος την ημέρα αυτή)
create table public.schedule_overrides (
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade,
  store         text not null,
  day           date not null,
  segments      jsonb not null,
  status        text not null default 'active' check (status in ('active','replaced','cleared')),
  reason        text,
  created_by    text not null,
  created_at    timestamptz not null default now(),
  ended_by      text,
  ended_at      timestamptz
);
create unique index one_active_override on public.schedule_overrides(employee_code, day) where status = 'active';
create index schedule_overrides_store_idx on public.schedule_overrides(store, day);

create table public.schedule_finalizations (
  store        text not null,
  week_start   date not null check (extract(isodow from week_start) = 1),
  finalized_by text not null,
  finalized_at timestamptz not null default now(),
  primary key (store, week_start)
);

-- Ιστορικό προγράμματος (δεν αλλάζει ποτέ)
create table public.schedule_changes (
  id             bigserial primary key,
  at             timestamptz not null default now(),
  actor          text not null,
  store          text not null,
  employee_code  text,
  change_type    text not null check (change_type in ('permanent','temporary','temporary_cleared','finalize','transfer')),
  affected_from  date,
  affected_to    date,
  effective_date date,
  prev_value     jsonb,
  new_value      jsonb,
  reason         text,
  after_finalize boolean not null default false
);
create index schedule_changes_store_idx on public.schedule_changes(store, at desc);

-- ─────────────── Δομή για μελλοντικό προτεινόμενο πρόγραμμα (μόνο δεδομένα) ───────────────
create table public.positions (
  code      text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  label     text not null,
  specialty text references public.specialties(name) on update cascade,
  active    boolean not null default true
);
create table public.employee_positions (           -- καταλληλότητα για θέση
  employee_code text not null references public.employees(code) on update cascade on delete cascade,
  position      text not null references public.positions(code) on update cascade,
  valid_from    date not null,
  valid_to      date,
  primary key (employee_code, position, valid_from)
);
create table public.employee_availability (        -- διαθεσιμότητα / περιορισμοί / προτιμήσεις
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade on delete cascade,
  weekday       smallint check (weekday between 1 and 7),
  time_from     time,
  time_to       time,
  kind          text not null check (kind in ('unavailable','available','preferred','avoid')),
  is_mandatory  boolean not null,                   -- υποχρεωτικός κανόνας ή προτίμηση
  valid_from    date not null,
  valid_to      date,
  note          text
);
create table public.schedule_rules (                -- κανόνες ανά κατάστημα / τμήμα / θέση / εργαζόμενο / ημέρα / διάστημα
  id            bigserial primary key,
  store         text references public.stores(name) on update cascade,
  specialty     text references public.specialties(name) on update cascade,
  position      text references public.positions(code) on update cascade,
  employee_code text references public.employees(code) on update cascade,
  weekday       smallint check (weekday between 1 and 7),
  time_from     time,
  time_to       time,
  rule_type     text not null,                      -- π.χ. min_rest_hours, max_daily_hours, fixed_shift, max_days_week
  is_mandatory  boolean not null,
  value         jsonb not null default '{}'::jsonb,
  valid_from    date not null,
  valid_to      date,
  active        boolean not null default true,
  note          text,
  created_by    text not null default 'system',
  created_at    timestamptz not null default now()
);
create table public.staffing_requirements (         -- απαιτούμενες θέσεις ανά μισάωρο
  id         bigserial primary key,
  store      text not null references public.stores(name) on update cascade,
  specialty  text references public.specialties(name) on update cascade,
  position   text references public.positions(code) on update cascade,
  weekday    smallint not null check (weekday between 1 and 7),
  slot_start time not null check (extract(minute from slot_start) in (0, 30)),
  required   int not null check (required >= 0),
  valid_from date not null,
  valid_to   date
);

-- ─────────────── Βοηθητικές ───────────────
-- Έλεγχος/κανονικοποίηση διαστημάτων: [["08:00","12:00"],["17:00","21:00"]] (έως 4, ίδια ημέρα, έναρξη < λήξη)
create or replace function public.sched_segments(p jsonb) returns jsonb
language plpgsql immutable as $$
declare s jsonb; v_out jsonb := '[]'::jsonb; a text; b text;
begin
  if p is null or jsonb_typeof(p) = 'null' then return '[]'::jsonb; end if;
  if jsonb_typeof(p) <> 'array' then raise exception 'Μη έγκυρο ωράριο.'; end if;
  if jsonb_array_length(p) > 4 then raise exception 'Έως 4 διαστήματα την ημέρα.'; end if;
  for s in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(s) <> 'array' or jsonb_array_length(s) <> 2 then raise exception 'Κάθε διάστημα έχει ώρα έναρξης και λήξης.'; end if;
    a := s->>0; b := s->>1;
    if a !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or b !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$|^24:00$' then
      raise exception 'Μη έγκυρη ώρα «%–%» (μορφή ΩΩ:ΛΛ).', a, b;
    end if;
    if b <= a then raise exception 'Η λήξη (%) πρέπει να είναι μετά την έναρξη (%) την ίδια ημέρα.', b, a; end if;
    v_out := v_out || jsonb_build_array(jsonb_build_array(a, b));
  end loop;
  return (select coalesce(jsonb_agg(x order by x->>0, x->>1), '[]'::jsonb) from jsonb_array_elements(v_out) x);
end $$;

create or replace function public.sched_min(p text) returns int language sql immutable as $$
  select split_part(p, ':', 1)::int * 60 + split_part(p, ':', 2)::int
$$;

-- Λεπτά εργασίας (ένωση διαστημάτων: επικάλυψη δεν μετράει δύο φορές· το κενό ενός σπαστού δεν μετράει)
create or replace function public.sched_minutes(p jsonb) returns int
language plpgsql immutable as $$
declare s jsonb; v_total int := 0; v_end int := -1; a int; b int;
begin
  for s in select x from jsonb_array_elements(coalesce(p, '[]'::jsonb)) x order by public.sched_min(x->>0) loop
    a := public.sched_min(s->>0); b := public.sched_min(s->>1);
    if a >= v_end then v_total := v_total + (b - a); v_end := b;
    elsif b > v_end then v_total := v_total + (b - v_end); v_end := b; end if;
  end loop;
  return v_total;
end $$;

create or replace function public.sched_overlaps(p jsonb) returns boolean
language sql immutable as $$
  select exists (select 1 from jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality x(a, i)
                   join jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality y(b, j) on j > i
                  where public.sched_min(x.a->>0) < public.sched_min(y.b->>1) and public.sched_min(y.b->>0) < public.sched_min(x.a->>1))
$$;

create or replace function public.sched_days(p jsonb) returns jsonb
language plpgsql immutable as $$
declare v_out jsonb := '{}'::jsonb; d int;
begin
  if jsonb_typeof(p) <> 'object' then raise exception 'Μη έγκυρο εβδομαδιαίο πρόγραμμα.'; end if;
  if exists (select 1 from jsonb_object_keys(p) k where k !~ '^[1-7]$') then raise exception 'Ημέρες εβδομάδας 1 (Δευτέρα) έως 7 (Κυριακή).'; end if;
  for d in 1..7 loop v_out := v_out || jsonb_build_object(d::text, public.sched_segments(p->d::text)); end loop;
  return v_out;
end $$;

-- Πρόγραμμα εργαζομένου μια ημέρα: προσωρινή αλλαγή > σταθερό πρόγραμμα > τίποτα
create or replace function public.sched_day(p_code text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.schedule_overrides; p public.schedule_patterns;
begin
  select * into o from public.schedule_overrides where employee_code = p_code and day = p_day and status = 'active';
  if found then return jsonb_build_object('segments', o.segments, 'source', 'temporary', 'store', o.store, 'override_id', o.id, 'reason', o.reason); end if;
  select * into p from public.schedule_patterns where employee_code = p_code and status = 'active' and valid_from <= p_day
     and (valid_to is null or p_day <= valid_to) order by valid_from desc limit 1;
  if found then return jsonb_build_object('segments', coalesce(p.days->(extract(isodow from p_day)::int)::text, '[]'::jsonb), 'source', 'pattern', 'store', p.store, 'pattern_id', p.id); end if;
  return null;
end $$;

create or replace function public.sched_week_of(p_day date) returns date language sql immutable as $$
  select p_day - (extract(isodow from p_day)::int - 1)
$$;

-- Υπάρχει οριστικοποιημένη εβδομάδα του καταστήματος που επηρεάζεται από ημερομηνίες [από, έως];
create or replace function public.sched_touches_final(p_store text, p_from date, p_to date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.schedule_finalizations f where f.store = p_store
                   and f.week_start <= coalesce(p_to, date '9999-12-31') and f.week_start + 6 >= p_from)
$$;

create or replace function public.sched_check_emp(p_code text) returns public.employees
language plpgsql stable security definer set search_path = public as $$
declare e public.employees;
begin
  perform public.require_perm('schedule.manage');
  select * into e from public.employees where code = p_code;
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  return e;
end $$;

-- ─────────────── Μόνιμη αλλαγή / νέο σταθερό πρόγραμμα από ημερομηνία ───────────────
create or replace function public.sched_set_pattern(p_code text, p_valid_from date, p_days jsonb, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_days jsonb := public.sched_days(p_days); prev public.schedule_patterns; nxt public.schedule_patterns;
        v_final boolean; v_id bigint; v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  e := public.sched_check_emp(p_code);
  if p_valid_from is null then raise exception 'Συμπληρώστε ημερομηνία ισχύος.'; end if;
  if e.leave_date is not null and p_valid_from > e.leave_date then raise exception 'Ο εργαζόμενος αποχωρεί στις %.', to_char(e.leave_date, 'DD/MM/YYYY'); end if;
  select * into prev from public.schedule_patterns where employee_code = p_code and status = 'active' and valid_from <= p_valid_from
     and (valid_to is null or p_valid_from <= valid_to) order by valid_from desc limit 1 for update;
  select * into nxt from public.schedule_patterns where employee_code = p_code and status = 'active' and valid_from > p_valid_from order by valid_from limit 1;
  v_final := public.sched_touches_final(e.store, p_valid_from, case when nxt.id is not null then nxt.valid_from - 1 end);
  if v_final and coalesce(length(v_reason), 0) < 3 then raise exception 'Το πρόγραμμα έχει οριστικοποιηθεί. Η αιτιολογία της αλλαγής είναι υποχρεωτική.'; end if;
  if prev.id is not null and prev.valid_from = p_valid_from then
    update public.schedule_patterns set status = 'superseded' where id = prev.id;
  elsif prev.id is not null then
    update public.schedule_patterns set valid_to = p_valid_from - 1 where id = prev.id;
  end if;
  insert into public.schedule_patterns(employee_code, store, valid_from, valid_to, days, reason, created_by)
  values (p_code, e.store, p_valid_from, case when nxt.id is not null then nxt.valid_from - 1 end, v_days, v_reason, public.current_email())
  returning id into v_id;
  insert into public.schedule_changes(actor, store, employee_code, change_type, affected_from, affected_to, effective_date, prev_value, new_value, reason, after_finalize)
  values (public.current_email(), e.store, p_code, 'permanent', p_valid_from, case when nxt.id is not null then nxt.valid_from - 1 end, p_valid_from,
          case when prev.id is not null then prev.days end, v_days, v_reason, v_final);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ─────────────── Προσωρινή αλλαγή για συγκεκριμένες ημερομηνίες (επιστροφή αυτόματα στο σταθερό) ───────────────
create or replace function public.sched_set_temp(p_code text, p_days date[], p_segments jsonb, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_seg jsonb := public.sched_segments(p_segments); d date; v_prev jsonb; v_final boolean; v_reason text := nullif(trim(coalesce(p_reason, '')), '');
        v_prevs jsonb := '{}'::jsonb;
begin
  e := public.sched_check_emp(p_code);
  if coalesce(cardinality(p_days), 0) = 0 then raise exception 'Επιλέξτε ημερομηνίες.'; end if;
  if cardinality(p_days) > 62 then raise exception 'Έως 62 ημέρες σε μία προσωρινή αλλαγή· για μεγαλύτερη περίοδο χρησιμοποιήστε μόνιμη αλλαγή.'; end if;
  if e.leave_date is not null and exists (select 1 from unnest(p_days) x where x > e.leave_date) then
    raise exception 'Ο εργαζόμενος αποχωρεί στις %.', to_char(e.leave_date, 'DD/MM/YYYY');
  end if;
  v_final := exists (select 1 from unnest(p_days) x where public.sched_touches_final(e.store, x, x));
  if v_final and coalesce(length(v_reason), 0) < 3 then raise exception 'Το πρόγραμμα έχει οριστικοποιηθεί. Η αιτιολογία της αλλαγής είναι υποχρεωτική.'; end if;
  foreach d in array (select array_agg(distinct x order by x) from unnest(p_days) x) loop
    v_prev := public.sched_day(p_code, d);
    v_prevs := v_prevs || jsonb_build_object(d::text, v_prev->'segments');
    update public.schedule_overrides set status = 'replaced', ended_by = public.current_email(), ended_at = now()
     where employee_code = p_code and day = d and status = 'active';
    insert into public.schedule_overrides(employee_code, store, day, segments, reason, created_by)
    values (p_code, e.store, d, v_seg, v_reason, public.current_email());
  end loop;
  insert into public.schedule_changes(actor, store, employee_code, change_type, affected_from, affected_to, prev_value, new_value, reason, after_finalize)
  values (public.current_email(), e.store, p_code, 'temporary', (select min(x) from unnest(p_days) x), (select max(x) from unnest(p_days) x),
          v_prevs, jsonb_build_object('segments', v_seg, 'days', to_jsonb(p_days)), v_reason, v_final);
  return jsonb_build_object('ok', true, 'days', cardinality(p_days));
end $$;

-- Κατάργηση προσωρινής αλλαγής (επιστροφή στο σταθερό πρόγραμμα)
create or replace function public.sched_clear_temp(p_code text, p_days date[], p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_final boolean; v_reason text := nullif(trim(coalesce(p_reason, '')), ''); v_n int;
begin
  e := public.sched_check_emp(p_code);
  v_final := exists (select 1 from unnest(p_days) x where public.sched_touches_final(e.store, x, x));
  if v_final and coalesce(length(v_reason), 0) < 3 then raise exception 'Το πρόγραμμα έχει οριστικοποιηθεί. Η αιτιολογία της αλλαγής είναι υποχρεωτική.'; end if;
  with x as (update public.schedule_overrides set status = 'cleared', ended_by = public.current_email(), ended_at = now()
              where employee_code = p_code and day = any(p_days) and status = 'active' returning day, segments)
  select count(*) into v_n from x;
  if v_n = 0 then raise exception 'Δεν υπάρχει προσωρινή αλλαγή στις ημερομηνίες αυτές.'; end if;
  insert into public.schedule_changes(actor, store, employee_code, change_type, affected_from, affected_to, new_value, reason, after_finalize)
  values (public.current_email(), e.store, p_code, 'temporary_cleared', (select min(x) from unnest(p_days) x), (select max(x) from unnest(p_days) x),
          jsonb_build_object('days', to_jsonb(p_days)), v_reason, v_final);
  return jsonb_build_object('ok', true, 'cleared', v_n);
end $$;

-- Οριστικοποίηση εβδομάδας από τον manager (χωρίς έγκριση HR/ΓΔ). Μετά, κάθε αλλαγή θέλει αιτιολογία.
create or replace function public.sched_finalize(p_store text, p_week_start date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('schedule.manage');
  if not public.can_see_store(p_store) then raise exception 'Το κατάστημα δεν ανήκει στο πεδίο σας.'; end if;
  if extract(isodow from p_week_start) <> 1 then raise exception 'Η εβδομάδα ξεκινά Δευτέρα.'; end if;
  if exists (select 1 from public.schedule_finalizations where store = p_store and week_start = p_week_start) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  insert into public.schedule_finalizations(store, week_start, finalized_by) values (p_store, p_week_start, public.current_email());
  insert into public.schedule_changes(actor, store, change_type, affected_from, affected_to, reason)
  values (public.current_email(), p_store, 'finalize', p_week_start, p_week_start + 6, null);
  return jsonb_build_object('ok', true);
end $$;

-- ─────────────── Μόνιμη μεταφορά καταστήματος (ίδιος κωδικός, πλήρες ιστορικό) ───────────────
-- Οι παλιές εγγραφές (δηλώσεις, αιτήματα, στατιστικά) κρατούν το κατάστημα στο οποίο αφορούσαν.
create or replace function public.emp_transfer(p_code text, p_store text, p_effective date, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_ts timestamptz; v_n int;
begin
  perform public.require_perm('employees.edit');
  select * into e from public.employees where code = p_code for update;
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if not exists (select 1 from public.stores where name = p_store and active) then raise exception 'Άγνωστο κατάστημα.'; end if;
  if p_store = e.store then raise exception 'Ο εργαζόμενος ανήκει ήδη στο κατάστημα %.', p_store; end if;
  if p_effective is null then raise exception 'Συμπληρώστε ημερομηνία ισχύος.'; end if;
  if p_effective > public.athens_today() then raise exception 'Η μεταφορά καταχωρίζεται από την ημέρα ισχύος της (όχι μελλοντικά).'; end if;
  if e.hire_date is not null and p_effective < e.hire_date then raise exception 'Η μεταφορά δεν μπορεί να είναι πριν από την πρόσληψη.'; end if;
  if exists (select 1 from public.employee_assignments where employee_code = p_code and valid_to is null and (valid_from at time zone 'Europe/Athens')::date > p_effective) then
    raise exception 'Υπάρχει νεότερη αλλαγή θέσης· η μεταφορά δεν μπορεί να έχει προγενέστερη ισχύ.';
  end if;
  v_ts := p_effective::timestamp at time zone 'Europe/Athens';
  update public.employees set store = p_store where code = p_code;      -- ο υπάρχων μηχανισμός γράφει το ιστορικό θέσης
  update public.employee_assignments set valid_to = v_ts
   where employee_code = p_code and valid_to is not null and valid_to = (select max(valid_to) from public.employee_assignments where employee_code = p_code);
  update public.employee_assignments set valid_from = v_ts where employee_code = p_code and valid_to is null;
  -- Πρόγραμμα: το σταθερό πρόγραμμα του παλιού καταστήματος λήγει την προηγούμενη ημέρα· οι προσωρινές αλλαγές μετά την ισχύ παύουν
  update public.schedule_patterns set valid_to = p_effective - 1
   where employee_code = p_code and status = 'active' and store = e.store and valid_from < p_effective and (valid_to is null or valid_to >= p_effective);
  update public.schedule_patterns set status = 'superseded'
   where employee_code = p_code and status = 'active' and store = e.store and valid_from >= p_effective;
  update public.schedule_overrides set status = 'cleared', ended_by = public.current_email(), ended_at = now()
   where employee_code = p_code and status = 'active' and store = e.store and day >= p_effective;
  get diagnostics v_n = row_count;
  insert into public.schedule_changes(actor, store, employee_code, change_type, affected_from, effective_date, prev_value, new_value, reason)
  values (public.current_email(), e.store, p_code, 'transfer', p_effective, p_effective, jsonb_build_object('store', e.store), jsonb_build_object('store', p_store), nullif(trim(p_note), ''));
  insert into public.employee_lifecycle(employee_code, kind, effective_date, old_value, new_value, note, actor)
  values (p_code, 'transfer', p_effective, jsonb_build_object('store', e.store), jsonb_build_object('store', p_store), nullif(trim(p_note), ''), public.current_email());
  return jsonb_build_object('ok', true);
end $$;

alter table public.shift_templates        enable row level security;
alter table public.store_hours            enable row level security;
alter table public.schedule_patterns      enable row level security;
alter table public.schedule_overrides     enable row level security;
alter table public.schedule_finalizations enable row level security;
alter table public.schedule_changes       enable row level security;
alter table public.positions              enable row level security;
alter table public.employee_positions     enable row level security;
alter table public.employee_availability  enable row level security;
alter table public.schedule_rules         enable row level security;
alter table public.staffing_requirements  enable row level security;

create policy sht_read  on public.shift_templates for select to authenticated using (public.has_perm('schedule.view') or public.has_perm('schedule.settings'));
create policy sht_write on public.shift_templates for all to authenticated using (public.has_perm('schedule.settings')) with check (public.has_perm('schedule.settings'));
create policy sth_read  on public.store_hours for select to authenticated using ((public.has_perm('schedule.view') or public.has_perm('schedule.settings')) and public.can_see_store(store));
create policy sth_write on public.store_hours for all to authenticated using (public.has_perm('schedule.settings')) with check (public.has_perm('schedule.settings'));
create policy shp_read  on public.schedule_patterns for select to authenticated using (public.has_perm('schedule.view') and public.can_see_store(store));
create policy sho_read  on public.schedule_overrides for select to authenticated using (public.has_perm('schedule.view') and public.can_see_store(store));
create policy shf_read  on public.schedule_finalizations for select to authenticated using (public.has_perm('schedule.view') and public.can_see_store(store));
create policy shc_read  on public.schedule_changes for select to authenticated using (public.has_perm('schedule.view') and public.can_see_store(store));
create policy pos_read  on public.positions for select to authenticated using (public.has_perm('schedule.view') or public.has_perm('schedule.settings'));
create policy pos_write on public.positions for all to authenticated using (public.has_perm('schedule.settings')) with check (public.has_perm('schedule.settings'));
create policy epos_read on public.employee_positions for select to authenticated using (public.has_perm('schedule.view') and exists (select 1 from public.employees e where e.code = employee_code));
create policy eav_read  on public.employee_availability for select to authenticated using (public.has_perm('schedule.view') and exists (select 1 from public.employees e where e.code = employee_code));
create policy sru_read  on public.schedule_rules for select to authenticated using (public.has_perm('schedule.view') or public.has_perm('schedule.settings'));
create policy sreq_read on public.staffing_requirements for select to authenticated using ((public.has_perm('schedule.view') or public.has_perm('schedule.settings')) and public.can_see_store(store));
create policy sreq_write on public.staffing_requirements for all to authenticated using (public.has_perm('schedule.settings')) with check (public.has_perm('schedule.settings'));

revoke all on public.schedule_patterns, public.schedule_overrides, public.schedule_finalizations, public.schedule_changes,
  public.employee_positions, public.employee_availability, public.schedule_rules from anon, authenticated;
grant select on public.schedule_patterns, public.schedule_overrides, public.schedule_finalizations, public.schedule_changes,
  public.employee_positions, public.employee_availability, public.schedule_rules to authenticated;
revoke all on public.shift_templates, public.store_hours, public.positions, public.staffing_requirements from anon;
create trigger schedule_changes_append_only before update or delete on public.schedule_changes for each row execute function public.append_only();
create trigger audit_store_hours after insert or update or delete on public.store_hours for each row execute function public.audit_trigger();
create trigger audit_shift_templates after insert or update or delete on public.shift_templates for each row execute function public.audit_trigger();
