-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Έκδοση 3.0 · Μέρος 4: Άδειες
--   Κανονική άδεια ανά ημερολογιακό έτος με μηνιαία αναλογία (εσωτερικός δείκτης) · υπόλοιπο προηγούμενου
--   έτους έως 31/03 · ημέρες χρέωσης από το πρόγραμμα/σύστημα εργασίας · υπέρβαση με ειδική έγκριση ΓΔ ·
--   διορθώσεις · ολική/μερική ακύρωση · αλλαγή ημερομηνιών με νέα έγκριση · εκκαθάριση μετά τις 31/03 ·
--   αναρρωτικές με χωριστό έλεγχο κάλυψης αποδοχών · ημερολόγιο αδειών · ειδοποιήσεις manager.
--
-- ΑΡΧΗ ΒΙΒΛΙΟΥ ΚΙΝΗΣΕΩΝ (καμία διπλή αφαίρεση «από κατασκευής»):
--   • Η έγκριση δημιουργεί ΜΙΑ εγγραφή ανά ημέρα άδειας (leave_days, μοναδική ανά εργαζόμενο & ημέρα)
--     και τη χρέωσή της ανά έτος (leave_charges). Αυτό είναι η «δέσμευση».
--   • «Ληφθείσες» = ενεργές χρεώσεις με ημερομηνία ≤ ημερομηνία αναφοράς· «εγκεκριμένες μελλοντικές» = > ημερομηνία.
--     Η μεταφορά από τη μία κατηγορία στην άλλη γίνεται μόνο από την ημερομηνία — δεν γράφεται νέα κίνηση.
--   • Ακύρωση/αλλαγή: οι ημέρες αλλάζουν κατάσταση (cancelled/replaced)· τίποτα δεν διαγράφεται.
--   • Υπόλοιπο = αναλογία + διορθώσεις − χρεώσεις (− εκκαθαρίσεις για το προηγούμενο έτος).
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ─────────────── Αργίες (δεν χρεώνονται ως ημέρες άδειας) ───────────────
create table public.public_holidays (
  day        date primary key,
  label      text not null,
  created_by text not null default 'system'
);
insert into public.public_holidays(day, label) values
 ('2025-01-01','Πρωτοχρονιά'),('2025-01-06','Θεοφάνεια'),('2025-03-03','Καθαρά Δευτέρα'),('2025-03-25','25η Μαρτίου'),
 ('2025-04-21','Δευτέρα του Πάσχα'),('2025-05-01','Πρωτομαγιά'),('2025-06-09','Αγίου Πνεύματος'),('2025-08-15','Δεκαπενταύγουστος'),
 ('2025-10-28','28η Οκτωβρίου'),('2025-12-25','Χριστούγεννα'),('2025-12-26','Σύναξη Θεοτόκου'),
 ('2026-01-01','Πρωτοχρονιά'),('2026-01-06','Θεοφάνεια'),('2026-02-23','Καθαρά Δευτέρα'),('2026-03-25','25η Μαρτίου'),
 ('2026-04-13','Δευτέρα του Πάσχα'),('2026-05-01','Πρωτομαγιά'),('2026-06-01','Αγίου Πνεύματος'),('2026-08-15','Δεκαπενταύγουστος'),
 ('2026-10-28','28η Οκτωβρίου'),('2026-12-25','Χριστούγεννα'),('2026-12-26','Σύναξη Θεοτόκου'),
 ('2027-01-01','Πρωτοχρονιά'),('2027-01-06','Θεοφάνεια'),('2027-03-15','Καθαρά Δευτέρα'),('2027-03-25','25η Μαρτίου'),
 ('2027-05-01','Πρωτομαγιά'),('2027-05-03','Δευτέρα του Πάσχα'),('2027-06-21','Αγίου Πνεύματος'),('2027-08-15','Δεκαπενταύγουστος'),
 ('2027-10-28','28η Οκτωβρίου'),('2027-12-25','Χριστούγεννα'),('2027-12-26','Σύναξη Θεοτόκου');

-- ─────────────── Ετήσια βάση κανονικής άδειας (ανά εργαζόμενο, με ημερομηνία ισχύος) ───────────────
-- Οι τιμές 20/21/22 (πενθήμερο) και 24/25/26 (εξαήμερο) είναι οι συνήθεις — όχι οι μόνες δυνατές.
create table public.leave_entitlements (
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade,
  annual_days   numeric(5,2) not null check (annual_days >= 0 and annual_days <= 60),
  valid_from    date not null,
  note          text,
  set_by        text not null,
  set_at        timestamptz not null default now(),
  superseded_at timestamptz,
  superseded_by text
);
create unique index one_entitlement_per_date on public.leave_entitlements(employee_code, valid_from) where superseded_at is null;

-- ─────────────── Αιτήματα: αλλαγή ημερομηνιών εγκεκριμένης άδειας ───────────────
alter table public.hr_requests drop constraint if exists hr_requests_category_check;
alter table public.hr_requests add constraint hr_requests_category_check check (category in (
  'leave','leave_change','shift_change','raise','contract_change','advance','documents','transfer','other_hr',
  'negative_review','incident','warning_request'));
alter table public.hr_requests
  add column if not exists original_request_id uuid references public.hr_requests(id),
  add column if not exists leave_requested numeric(6,2),
  add column if not exists leave_available numeric(7,2),
  add column if not exists leave_excess    numeric(6,2);
alter table public.hr_decisions
  add column if not exists leave_days_json   jsonb,
  add column if not exists overdraw_days     numeric(6,2),
  add column if not exists overdraw_available numeric(7,2);

create or replace function public.req_flow(p_category text) returns text
language sql immutable as $$
  select case
    when p_category in ('leave','leave_change') then 'leave'
    when p_category in ('raise','contract_change') then 'gm'
    when p_category = 'warning_request' then 'warning'
    when p_category in ('negative_review','incident') then 'report'
    else 'generic' end
$$;

create or replace function public.req_category_label(p_category text) returns text
language sql immutable as $$
  select case p_category
    when 'leave' then 'Άδεια / απουσία' when 'leave_change' then 'Αλλαγή ημερομηνιών εγκεκριμένης άδειας'
    when 'shift_change' then 'Αλλαγή βάρδιας, ρεπό ή προγράμματος'
    when 'raise' then 'Αύξηση αποδοχών' when 'contract_change' then 'Αλλαγή ωρών ή σύμβασης'
    when 'advance' then 'Προκαταβολή' when 'documents' then 'Βεβαιώσεις και έγγραφα'
    when 'transfer' then 'Μετακίνηση καταστήματος ή αλλαγή θέσης' when 'other_hr' then 'Λοιπό αίτημα προς HR'
    when 'negative_review' then 'Αρνητική αξιολόγηση' when 'incident' then 'Περιστατικό'
    when 'warning_request' then 'Αίτημα έγγραφης προειδοποίησης' else p_category end
$$;

-- ─────────────── Ημέρες άδειας & χρεώσεις ───────────────
create table public.leave_days (
  id            bigserial primary key,
  request_id    uuid not null references public.hr_requests(id),
  employee_code text not null references public.employees(code) on update cascade,
  store         text not null,
  leave_type    text not null,
  day           date not null,
  chargeable    boolean not null,                 -- εργάσιμη για τον εργαζόμενο (μόνο τότε μπορεί να χρεωθεί)
  charge        numeric(4,2) not null default 0 check (charge >= 0 and charge <= 1),
  status        text not null default 'active' check (status in ('active','cancelled','replaced')),
  created_by    text not null,
  created_at    timestamptz not null default now(),
  ended_by      text,
  ended_at      timestamptz,
  end_reason    text,
  end_ref       bigint,                           -- ακύρωση ή αίτημα αλλαγής που την αντικατέστησε
  replaced_by_request uuid references public.hr_requests(id)
);
-- Μία ενεργή άδεια ανά εργαζόμενο και ημέρα: αποτρέπει διπλές εγγραφές και διπλή χρέωση
create unique index one_active_leave_day on public.leave_days(employee_code, day) where status = 'active';
create index leave_days_req_idx on public.leave_days(request_id);
create index leave_days_day_idx on public.leave_days(day, store);

create table public.leave_charges (
  id           bigserial primary key,
  leave_day_id bigint not null references public.leave_days(id),
  leave_year   int not null check (leave_year between 2000 and 2100),
  amount       numeric(4,2) not null check (amount > 0 and amount <= 1)
);
create index leave_charges_day_idx on public.leave_charges(leave_day_id);

-- Χειροκίνητες διορθώσεις (με αιτιολογία, προηγούμενη/νέα τιμή, χρήστη, χρόνο)· δεν αλλάζουν ποτέ
create table public.leave_adjustments (
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade,
  leave_year    int not null,
  as_of         date not null,
  prev_value    numeric(8,2) not null,
  new_value     numeric(8,2) not null,
  delta         numeric(8,2) not null,
  reason        text not null check (length(trim(reason)) >= 5),
  created_by    text not null,
  created_role  text not null,
  created_at    timestamptz not null default now()
);

create table public.leave_cancellations (
  id           bigserial primary key,
  request_id   uuid not null references public.hr_requests(id),
  kind         text not null check (kind in ('total','partial')),
  days         date[] not null,
  charge_back  jsonb not null,                    -- ημέρες που επιστράφηκαν ανά έτος
  reason       text not null,
  approved_by  text not null,
  approved_role text not null,
  at           timestamptz not null default now()
);

-- Εκκαθάριση υπολοίπου προηγούμενου έτους από το λογιστήριο (μετά τις 31/03)
create table public.leave_settlements (
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade,
  leave_year    int not null,
  days          numeric(6,2) not null check (days > 0),
  amount        numeric(10,2) not null check (amount >= 0),
  paid_on       date not null,
  doc_name      text,
  doc_mime      text check (doc_mime is null or doc_mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  doc_data      text,
  note          text,
  created_by    text not null,
  created_at    timestamptz not null default now(),
  voided_at     timestamptz,
  voided_by     text,
  void_reason   text
);

-- ─────────────── Ειδοποιήσεις (ανά χρήστη) ───────────────
create table public.notifications (
  id         bigserial primary key,
  user_email text not null,
  request_id uuid references public.hr_requests(id) on delete cascade,
  kind       text not null,
  title      text not null,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index notifications_unread_idx on public.notifications(user_email) where read_at is null;

-- Ο αρμόδιος manager = ενεργός χρήστης του καταστήματος του αιτήματος με ρόλο που βλέπει αιτήματα και υλοποιεί
create or replace function public.notify_request(p_request uuid, p_kind text, p_title text) returns int
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_n int;
begin
  select * into r from public.hr_requests where id = p_request;
  if not found then return 0; end if;
  insert into public.notifications(user_email, request_id, kind, title)
  select u.email, r.id, p_kind, left(p_title, 300)
    from public.app_users u
    join public.role_scopes s on s.role = u.role and s.scope = 'own_store'
   where u.active and u.store = r.store and public.role_has_perm(u.role, 'requests.view')
     and u.email is distinct from public.current_email();
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ═══════════════ Υπολογισμοί ═══════════════
-- Εργάσιμη ημέρα για τον εργαζόμενο: 1) αργία → όχι 2) πρόγραμμα της ημέρας (σταθερό/προσωρινό) αν υπάρχει
-- 3) αλλιώς το σύστημα εργασίας του (πενθήμερο: Δευ–Παρ, εξαήμερο: Δευ–Σάβ). null = άγνωστο (λείπει σύστημα εργασίας).
create or replace function public.leave_workday(p_code text, p_day date) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare s jsonb; ww smallint;
begin
  if exists (select 1 from public.public_holidays where day = p_day) then return false; end if;
  s := public.sched_day(p_code, p_day);
  if s is not null then return jsonb_array_length(coalesce(s->'segments', '[]'::jsonb)) > 0; end if;
  select work_week into ww from public.work_terms_on(p_code, p_day);
  if ww is null then return null; end if;
  return extract(isodow from p_day) <= ww;
end $$;

-- Ετήσια βάση σε μια ημερομηνία
create or replace function public.leave_base_on(p_code text, p_day date) returns numeric
language sql stable security definer set search_path = public as $$
  select annual_days from public.leave_entitlements
   where employee_code = p_code and superseded_at is null and valid_from <= p_day order by valid_from desc limit 1
$$;

-- Αναλογία (εσωτερικός δείκτης) για το έτος έως και την ημερομηνία.
-- ΜΕΘΟΔΟΣ ΠΡΟΣ ΕΠΙΒΕΒΑΙΩΣΗ: κάθε ημέρα απασχόλησης δίνει (ετήσια βάση ÷ 12 ÷ ημέρες του μήνα).
--   ⇒ πλήρης μήνας = βάση/12 · μέρος μήνα (π.χ. από την πρόσληψη) = αναλογία ημερολογιακών ημερών του μήνα ·
--     αλλαγή βάσης μέσα στο έτος εφαρμόζεται από την ημερομηνία ισχύος της. Χωρίς στρογγυλοποίηση.
create or replace function public.leave_accrued(p_code text, p_year int, p_upto date) returns numeric
language sql stable security definer set search_path = public as $$
  with e as (select hire_date, leave_date from public.employees where code = p_code),
  rng as (select greatest(make_date(p_year, 1, 1), coalesce(e.hire_date, make_date(p_year, 1, 1))) a,
                 least(p_upto, make_date(p_year, 12, 31), coalesce(e.leave_date, make_date(p_year, 12, 31))) b from e),
  ent as (select annual_days, valid_from, coalesce(lead(valid_from) over (order by valid_from), date '9999-12-31') nxt
            from public.leave_entitlements where employee_code = p_code and superseded_at is null)
  select coalesce(sum(ent.annual_days / 12.0 / extract(day from (date_trunc('month', d) + interval '1 month - 1 day'))::numeric), 0)
    from rng, generate_series(rng.a, rng.b, interval '1 day') d
    join ent on d::date >= ent.valid_from and d::date < ent.nxt
   where rng.b >= rng.a
$$;

create or replace function public.leave_charged(p_code text, p_year int, p_upto date default null, p_exclude uuid[] default '{}') returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(c.amount), 0) from public.leave_charges c join public.leave_days d on d.id = c.leave_day_id
   where d.employee_code = p_code and d.status = 'active' and c.leave_year = p_year
     and (p_upto is null or d.day <= p_upto) and not (d.request_id = any(coalesce(p_exclude, '{}')))
$$;

create or replace function public.leave_adjusted(p_code text, p_year int) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(delta), 0) from public.leave_adjustments where employee_code = p_code and leave_year = p_year
$$;

create or replace function public.leave_settled(p_code text, p_year int) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(days), 0) from public.leave_settlements where employee_code = p_code and leave_year = p_year and voided_at is null
$$;

-- Υπόλοιπο ενός έτους (τρέχον: βάσει αναλογίας έως την ημερομηνία· προηγούμενα: ολόκληρη η αναλογία του έτους)
create or replace function public.leave_year_balance(p_code text, p_year int, p_as_of date, p_exclude uuid[] default '{}') returns numeric
language sql stable security definer set search_path = public as $$
  select case when p_year >= extract(year from p_as_of)::int
              then public.leave_accrued(p_code, p_year, p_as_of)
              else public.leave_accrued(p_code, p_year, make_date(p_year, 12, 31)) - public.leave_settled(p_code, p_year) end
         + public.leave_adjusted(p_code, p_year) - public.leave_charged(p_code, p_year, null, p_exclude)
$$;

-- Πλήρης εικόνα κανονικής άδειας σε μια ημερομηνία (2 δεκαδικά στην εμφάνιση· οι υπολογισμοί χωρίς στρογγυλοποίηση)
create or replace function public.leave_balance_calc(p_code text, p_as_of date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare y int := extract(year from p_as_of)::int; v_acc numeric; v_taken numeric; v_future numeric; v_adj numeric;
        v_prev numeric; v_prev_settled numeric; v_prev_taken numeric; v_base numeric; v_deadline date := make_date(y, 3, 31);
begin
  v_base := public.leave_base_on(p_code, p_as_of);
  v_acc := public.leave_accrued(p_code, y, p_as_of);
  v_taken := public.leave_charged(p_code, y, p_as_of);
  v_future := public.leave_charged(p_code, y) - v_taken;
  v_adj := public.leave_adjusted(p_code, y);
  v_prev := public.leave_year_balance(p_code, y - 1, p_as_of);
  v_prev_settled := public.leave_settled(p_code, y - 1);
  v_prev_taken := public.leave_charged(p_code, y - 1, null) - public.leave_charged(p_code, y - 1, make_date(y - 1, 12, 31));
  return jsonb_build_object(
    'as_of', p_as_of, 'year', y,
    'annual_days', round(v_base, 2),
    'base_missing', v_base is null,
    'accrued', round(v_acc, 2),
    'annual_full_year', round(public.leave_accrued(p_code, y, make_date(y, 12, 31)), 2),
    'taken', round(v_taken, 2),
    'future_approved', round(v_future, 2),
    'adjustments', round(v_adj, 2),
    'balance', round(v_acc + v_adj - v_taken - v_future, 2),
    'prev_year', y - 1,
    'prev_balance', round(v_prev, 2),
    'prev_used_this_year', round(v_prev_taken, 2),
    'prev_settled', round(v_prev_settled, 2),
    'prev_deadline', v_deadline,
    'prev_state', case when v_prev <= 0 then 'none' when p_as_of <= v_deadline then 'usable' else 'to_settle' end);
end $$;

-- Σχέδιο χρέωσης ενός διαστήματος: ανά ημέρα εργάσιμη/χρέωση και κατανομή ανά έτος.
-- Στο 1ο τρίμηνο χρεώνονται ΠΡΩΤΑ οι διαθέσιμες ημέρες του προηγούμενου έτους.
-- p_days (προαιρετικό): [{ "day": "2026-07-01", "charge": 1 }] από τον εγκρίνοντα· αλλιώς υπολογίζεται.
create or replace function public.leave_plan(p_code text, p_start date, p_end date, p_leave_type text, p_days jsonb default null, p_exclude uuid[] default '{}')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d date; v_work boolean; v_charge numeric; v_out jsonb := '[]'::jsonb; v_given jsonb; v_prev_avail jsonb := '{}'::jsonb; v_cur_used jsonb := '{}'::jsonb;
        y int; v_take_prev numeric; v_rest numeric; v_total numeric := 0; v_unknown int := 0; v_annual boolean := p_leave_type = 'annual';
        v_buckets jsonb; v_avail numeric := 0; v_cur numeric; v_years int[] := '{}'; e public.employees; v_last date;
begin
  if p_start is null or p_end is null or p_end < p_start then raise exception 'Μη έγκυρο διάστημα.'; end if;
  if p_end - p_start > 400 then raise exception 'Πολύ μεγάλο διάστημα.'; end if;
  select * into e from public.employees where code = p_code;
  if p_days is not null and jsonb_typeof(p_days) = 'array' then
    if exists (select 1 from jsonb_array_elements(p_days) x where (x->>'day')::date < p_start or (x->>'day')::date > p_end) then
      raise exception 'Οι ημέρες πρέπει να είναι μέσα στο εγκεκριμένο διάστημα.';
    end if;
    select jsonb_object_agg(x->>'day', coalesce((x->>'charge')::numeric, 1)) into v_given from jsonb_array_elements(p_days) x;
  end if;
  d := p_start;
  while d <= p_end loop
    v_work := public.leave_workday(p_code, d);
    if v_work is null then v_unknown := v_unknown + 1; end if;
    if e.leave_date is not null and d > e.leave_date then v_work := false; end if;
    if not v_annual then v_charge := 0;
    elsif v_given is not null then v_charge := coalesce((v_given->>d::text)::numeric, 0);
    else v_charge := case when coalesce(v_work, false) then 1 else 0 end; end if;
    if v_charge not in (0, 0.5, 1) then raise exception 'Η χρέωση ημέρας είναι 0, 0,5 ή 1.'; end if;
    if v_charge > 0 and not coalesce(v_work, false) and v_given is not null then
      raise exception 'Η % δεν είναι εργάσιμη για τον εργαζόμενο (πρόγραμμα/αργία) και δεν χρεώνεται.', to_char(d, 'DD/MM/YYYY');
    end if;
    v_buckets := '[]'::jsonb;
    if v_charge > 0 then
      y := extract(year from d)::int;
      v_rest := v_charge;
      if d <= make_date(y, 3, 31) then
        if not v_prev_avail ? (y - 1)::text then
          v_prev_avail := v_prev_avail || jsonb_build_object((y - 1)::text, greatest(public.leave_year_balance(p_code, y - 1, d, p_exclude), 0));
        end if;
        v_take_prev := least(v_rest, (v_prev_avail->>(y - 1)::text)::numeric);
        if v_take_prev > 0 then
          v_buckets := v_buckets || jsonb_build_object('year', y - 1, 'amount', v_take_prev);
          v_prev_avail := v_prev_avail || jsonb_build_object((y - 1)::text, (v_prev_avail->>(y - 1)::text)::numeric - v_take_prev);
          v_rest := v_rest - v_take_prev;
        end if;
      end if;
      if v_rest > 0 then
        v_buckets := v_buckets || jsonb_build_object('year', y, 'amount', v_rest);
        v_cur_used := v_cur_used || jsonb_build_object(y::text, coalesce((v_cur_used->>y::text)::numeric, 0) + v_rest);
        if not (y = any(v_years)) then v_years := v_years || y; end if;
      end if;
      v_total := v_total + v_charge;
    end if;
    v_out := v_out || jsonb_build_object('day', d, 'workday', v_work, 'charge', v_charge, 'buckets', v_buckets,
                                         'holiday', (select label from public.public_holidays where day = d));
    d := d + 1;
  end loop;
  -- Διαθέσιμο = ό,τι καλύφθηκε από το προηγούμενο έτος + υπόλοιπο βάσει αναλογίας του τρέχοντος έως την τελευταία ημέρα της άδειας
  v_avail := v_total - coalesce((select sum((v_cur_used->>k)::numeric) from jsonb_object_keys(v_cur_used) k), 0);
  foreach y in array v_years loop
    v_last := least(p_end, make_date(y, 12, 31));
    v_cur := public.leave_accrued(p_code, y, v_last) + public.leave_adjusted(p_code, y) - public.leave_charged(p_code, y, null, p_exclude);
    v_avail := v_avail + greatest(least(v_cur, (v_cur_used->>y::text)::numeric), 0);
  end loop;
  -- Χωρίς ετήσια βάση δεν υπάρχει αναλογία: η υπέρβαση είναι «άγνωστη» (δεν μπλοκάρει, εμφανίζεται προειδοποίηση)
  if v_annual and not exists (select 1 from public.leave_entitlements x where x.employee_code = p_code and x.superseded_at is null) then
    return jsonb_build_object('days', v_out, 'requested', v_total, 'available', null, 'excess', null, 'base_missing', true,
                              'unknown_days', v_unknown, 'annual', v_annual);
  end if;
  return jsonb_build_object('days', v_out, 'requested', v_total, 'available', round(v_avail, 2),
                            'excess', round(greatest(v_total - v_avail, 0), 2), 'base_missing', false, 'unknown_days', v_unknown, 'annual', v_annual);
end $$;

-- Επικαλύψεις με άλλες ενεργές άδειες ή εκκρεμή αιτήματα του ίδιου εργαζομένου
create or replace function public.leave_conflicts(p_code text, p_start date, p_end date, p_exclude uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(distinct jsonb_build_object('ref', r.ref, 'id', r.id, 'status', r.status)), '[]'::jsonb)
    from public.hr_requests r
   where r.employee_code = p_code and r.category in ('leave','leave_change') and not (r.id = any(coalesce(p_exclude, '{}')))
     and (
       (r.status in ('submitted','under_review','needs_info','awaiting_gm') and r.start_date <= p_end and r.end_date >= p_start)
       or exists (select 1 from public.leave_days d where d.request_id = r.id and d.status = 'active' and d.day between p_start and p_end))
$$;

-- ═══════════════ Αναρρωτικές: απουσία και έλεγχος κάλυψης αποδοχών (χωριστά) ═══════════════
-- Εργασιακό έτος: από την πρόσληψη έως την αντίστοιχη επέτειο (όχι ημερολογιακό).
-- Κάλυψη από την εταιρεία: προϋπόθεση 10 ημερών παροχής εργασίας· έως 15 ημέρες στο 1ο εργασιακό έτος·
-- έως 1 μήνα στα επόμενα. «1 μήνας» = ημερολογιακός μήνας από την πρώτη καλυπτόμενη ημέρα του εργασιακού έτους
-- (28–31 ημέρες ανάλογα με τον μήνα, όχι σταθερά 30) — ΜΕΘΟΔΟΣ ΠΡΟΣ ΕΠΙΒΕΒΑΙΩΣΗ.
-- Η κάλυψη ΔΕΝ είναι όριο απουσίας: η καταχώριση δεν μπλοκάρεται ποτέ. Δεν αφαιρείται από την κανονική άδεια.
create or replace function public.sick_status(p_code text, p_as_of date, p_extra date[] default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; v_ys date; v_ye date; v_first_year boolean; v_limit int; v_days date[]; d date; v_work int; v_eligible int := 0;
        v_first_cov date; v_total int; v_cond boolean := true;
begin
  select * into e from public.employees where code = p_code;
  if e.hire_date is null then
    return jsonb_build_object('known', false, 'note', 'Λείπει η ημερομηνία πρόσληψης· δεν υπολογίζεται εργασιακό έτος.');
  end if;
  v_ys := e.hire_date + (date_part('year', age(greatest(p_as_of, e.hire_date), e.hire_date))::int * interval '1 year');
  v_ye := (v_ys + interval '1 year')::date - 1;
  v_first_year := v_ys = e.hire_date;
  select array_agg(x order by x) into v_days from (
    select day x from public.leave_days where employee_code = p_code and leave_type = 'sick' and status = 'active' and day between v_ys and v_ye
    union select unnest(p_extra) where true) z where x between v_ys and v_ye;
  v_total := coalesce(cardinality(v_days), 0);
  if v_total > 0 then
    foreach d in array v_days loop
      -- προϋπόθεση 10 ημερών παροχής εργασίας πριν από την ημέρα ασθένειας (εργάσιμες από την πρόσληψη)
      select count(*) filter (where coalesce(public.leave_workday(p_code, g::date), extract(isodow from g) <= 5)) into v_work
        from generate_series(e.hire_date, least(d - 1, e.hire_date + 60), interval '1 day') g;
      if v_work >= 10 then
        v_eligible := v_eligible + 1;
        if v_first_cov is null then v_first_cov := d; end if;
      else v_cond := false; end if;
    end loop;
  end if;
  v_limit := case when v_first_year then 15 when v_first_cov is not null then ((v_first_cov + interval '1 month')::date - v_first_cov) else null end;
  return jsonb_build_object('known', true, 'work_year_start', v_ys, 'work_year_end', v_ye, 'first_work_year', v_first_year,
    'sick_days', v_total, 'eligible_days', v_eligible, 'ten_day_condition_unmet_days', v_total - v_eligible,
    'cover_limit', v_limit, 'cover_limit_rule', case when v_first_year then '15 ημέρες (1ο εργασιακό έτος)' else '1 ημερολογιακός μήνας από την πρώτη καλυπτόμενη ημέρα' end,
    'covered', least(v_eligible, coalesce(v_limit, v_eligible)),
    'exhausted', v_limit is not null and v_eligible >= v_limit,
    'message', case when v_limit is not null and v_eligible >= v_limit
      then 'Έχει εξαντληθεί το όριο ημερών αναρρωτικής με κάλυψη αποδοχών από την εταιρεία για το τρέχον εργασιακό έτος.' end);
end $$;

-- ═══════════════ Εφαρμογή απόφασης στις ημέρες άδειας ═══════════════
create or replace function public.leave_release(p_request uuid, p_reason text, p_ref bigint, p_replaced_by uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  update public.leave_days set status = case when p_replaced_by is not null then 'replaced' else 'cancelled' end,
         ended_by = coalesce(public.current_email(), 'system'), ended_at = now(), end_reason = p_reason, end_ref = p_ref, replaced_by_request = p_replaced_by
   where request_id = p_request and status = 'active';
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.leave_book(p_request uuid, p_plan jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; x jsonb; b jsonb; v_id bigint; v_n int := 0; v_type text;
begin
  select * into r from public.hr_requests where id = p_request;
  v_type := coalesce(r.leave_type, (select leave_type from public.hr_requests where id = r.original_request_id));
  for x in select * from jsonb_array_elements(p_plan->'days') loop
    begin
      insert into public.leave_days(request_id, employee_code, store, leave_type, day, chargeable, charge, created_by)
      values (r.id, r.employee_code, r.store, v_type, (x->>'day')::date, coalesce((x->>'workday')::boolean, false), (x->>'charge')::numeric,
              coalesce(public.current_email(), 'system'))
      returning id into v_id;
    exception when unique_violation then
      raise exception 'Ο εργαζόμενος έχει ήδη εγκεκριμένη άδεια/απουσία στις %. Δεν επιτρέπεται διπλή εγγραφή.', to_char((x->>'day')::date, 'DD/MM/YYYY');
    end;
    for b in select * from jsonb_array_elements(x->'buckets') loop
      insert into public.leave_charges(leave_day_id, leave_year, amount) values (v_id, (b->>'year')::int, (b->>'amount')::numeric);
    end loop;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Ελέγχει/εφαρμόζει μια απόφαση για άδεια. Καλείται από τη req_decide.
-- Επιστρέφει το σχέδιο (για αποθήκευση στην απόφαση).
create or replace function public.leave_on_decision(p_request uuid, p_outcome text, p jsonb, p_role text, p_start date, p_end date, p_was_approved boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_plan jsonb; v_excl uuid[]; v_type text; v_orig uuid;
begin
  select * into r from public.hr_requests where id = p_request;
  v_orig := r.original_request_id;
  v_type := coalesce(r.leave_type, (select leave_type from public.hr_requests where id = v_orig));
  if p_outcome <> 'approve' then
    if p_was_approved and p_outcome = 'reject' then
      -- Αναθεώρηση έγκρισης σε απόρριψη: οι ημέρες αποδεσμεύονται· για αλλαγή ημερομηνιών επανέρχεται η αρχική άδεια
      perform public.leave_release(p_request, 'Αναθεώρηση απόφασης σε απόρριψη', null);
      if v_orig is not null then
        update public.leave_days set status = 'active', ended_by = null, ended_at = null, end_reason = null, replaced_by_request = null
         where request_id = v_orig and status = 'replaced' and replaced_by_request = p_request;
      end if;
    end if;
    return null;
  end if;
  -- έγκριση: οι παλιές ημέρες αυτού του αιτήματος (αναθεώρηση) και της αρχικής άδειας (αλλαγή) δεν μετρούν στον υπολογισμό
  v_excl := array_remove(array[p_request, v_orig], null);
  v_plan := public.leave_plan(r.employee_code, p_start, p_end, v_type, p->'days', v_excl);
  if (v_plan->>'unknown_days')::int > 0 and v_type = 'annual' and p->'days' is null then
    raise exception 'Δεν έχει οριστεί πενθήμερο/εξαήμερο ή πρόγραμμα για τον εργαζόμενο· δεν μπορούν να υπολογιστούν οι ημέρες χρέωσης.';
  end if;
  if coalesce((v_plan->>'excess')::numeric, 0) > 0 then
    if p_role <> 'owner' or not public.has_perm('leave.overdraw') then
      raise exception 'Το αίτημα υπερβαίνει το αναλογικό υπόλοιπο κατά % ημέρες (διαθέσιμες %). Απαιτείται ειδική έγκριση της Γενικής Διευθύντριας.',
        replace((v_plan->>'excess'), '.', ','), replace((v_plan->>'available'), '.', ',');
    end if;
    if coalesce((p->>'overdraw_ok')::boolean, false) is not true then
      raise exception 'Επιβεβαιώστε την ειδική έγκριση υπέρβασης κατά % ημέρες.', replace((v_plan->>'excess'), '.', ',');
    end if;
  end if;
  perform public.leave_release(p_request, 'Αναθεώρηση απόφασης', null);
  if v_orig is not null then
    perform public.leave_release(v_orig, 'Αλλαγή ημερομηνιών με το αίτημα ' || r.ref, null, p_request);
  end if;
  perform public.leave_book(p_request, v_plan);
  if v_orig is not null then
    perform public.req_event(v_orig, 'leave_changed', null, null, 'Νέες ημερομηνίες με το αίτημα ' || r.ref,
      jsonb_build_object('change_request', p_request, 'start', p_start, 'end', p_end));
  end if;
  return v_plan;
end $$;

-- ═══════════════ Αιτήματα: υποβολή, απόφαση (επεκτάσεις των υπαρχουσών) ═══════════════
-- Έλεγχος πριν από υποβολή: διπλές εγγραφές, αλλαγή ημερομηνιών, στιγμιότυπο υπέρβασης (δεν μπλοκάρει την υποβολή)
create or replace function public.leave_on_submit(p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; o public.hr_requests; v_conf jsonb; v_plan jsonb; v_type text;
begin
  select * into r from public.hr_requests where id = p_request;
  if r.category not in ('leave','leave_change') then return; end if;
  if r.category = 'leave_change' then
    select * into o from public.hr_requests where id = r.original_request_id;
    if not found or o.category <> 'leave' or o.employee_code <> r.employee_code then raise exception 'Επιλέξτε την εγκεκριμένη άδεια που αλλάζει.'; end if;
    if not exists (select 1 from public.leave_days where request_id = o.id and status = 'active') then
      raise exception 'Η αρχική άδεια δεν έχει ενεργές ημέρες (ακυρώθηκε ή άλλαξε ήδη).';
    end if;
    if exists (select 1 from public.hr_requests x where x.original_request_id = o.id and x.id <> r.id and x.status in ('submitted','under_review','needs_info','awaiting_gm')) then
      raise exception 'Υπάρχει ήδη εκκρεμές αίτημα αλλαγής για αυτή την άδεια.';
    end if;
  end if;
  v_conf := public.leave_conflicts(r.employee_code, r.start_date, r.end_date, array_remove(array[r.id, r.original_request_id], null));
  if jsonb_array_length(v_conf) > 0 then
    raise exception 'Υπάρχει ήδη άδεια ή εκκρεμές αίτημα άδειας για τις ίδιες ημερομηνίες (%). Δεν επιτρέπονται διπλές εγγραφές.',
      (select string_agg(x->>'ref', ', ') from jsonb_array_elements(v_conf) x);
  end if;
  v_type := coalesce(r.leave_type, o.leave_type);
  if v_type = 'annual' then
    v_plan := public.leave_plan(r.employee_code, r.start_date, r.end_date, 'annual', null, array_remove(array[r.id, r.original_request_id], null));
    update public.hr_requests set leave_requested = (v_plan->>'requested')::numeric, leave_available = (v_plan->>'available')::numeric,
           leave_excess = (v_plan->>'excess')::numeric where id = r.id;
  end if;
end $$;

-- Προεπισκόπηση για φόρμες (νέο αίτημα, απόφαση): ημέρες, υπόλοιπο, υπέρβαση, αναρρωτική
create or replace function public.leave_preview(p_code text, p_start date, p_end date, p_leave_type text, p_request uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_plan jsonb; v_excl uuid[]; v_sick jsonb; r public.hr_requests; v_days date[];
begin
  if not (public.has_perm('leave.view') or public.has_perm('requests.view')) or not public.employee_in_scope(p_code) then
    raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.';
  end if;
  if p_request is not null then select * into r from public.hr_requests where id = p_request; end if;
  v_excl := array_remove(array[p_request, r.original_request_id], null);
  v_plan := public.leave_plan(p_code, p_start, p_end, coalesce(p_leave_type, 'annual'), null, v_excl);
  if p_leave_type = 'sick' then
    select array_agg(g::date) into v_days from generate_series(p_start, p_end, interval '1 day') g;
    v_sick := public.sick_status(p_code, p_end, v_days);
  end if;
  return v_plan || jsonb_build_object('conflicts', public.leave_conflicts(p_code, p_start, p_end, v_excl),
                                      'balance', public.leave_balance_calc(p_code, p_start), 'sick', v_sick);
end $$;

-- ═══════════════ Ακύρωση (ολική/μερική) — ΓΔ, HR, λογιστήριο ═══════════════
create or replace function public.leave_cancel(p_request uuid, p_days date[], p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_days date[]; v_kind text; v_id bigint; v_back jsonb; v_active int;
begin
  perform public.require_perm('leave.cancel');
  select * into r from public.hr_requests where id = p_request for update;
  if not found or not public.can_see_store(r.store) then raise exception 'Το αίτημα δεν βρέθηκε.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Γράψτε αιτιολογία ακύρωσης.'; end if;
  select count(*) into v_active from public.leave_days where request_id = p_request and status = 'active';
  if v_active = 0 then raise exception 'Η άδεια δεν έχει ενεργές ημέρες για ακύρωση.'; end if;
  if p_days is null or cardinality(p_days) = 0 then
    select array_agg(day order by day) into v_days from public.leave_days where request_id = p_request and status = 'active';
  else
    v_days := (select array_agg(distinct x order by x) from unnest(p_days) x);
    if exists (select 1 from unnest(v_days) x where not exists (select 1 from public.leave_days d where d.request_id = p_request and d.status = 'active' and d.day = x)) then
      raise exception 'Κάποια από τις ημερομηνίες δεν είναι ενεργή ημέρα αυτής της άδειας.';
    end if;
  end if;
  v_kind := case when cardinality(v_days) = v_active then 'total' else 'partial' end;
  select coalesce(jsonb_object_agg(leave_year, amt), '{}'::jsonb) into v_back from (
    select c.leave_year, sum(c.amount) amt from public.leave_charges c join public.leave_days d on d.id = c.leave_day_id
     where d.request_id = p_request and d.status = 'active' and d.day = any(v_days) group by c.leave_year) x;
  insert into public.leave_cancellations(request_id, kind, days, charge_back, reason, approved_by, approved_role)
  values (p_request, v_kind, v_days, v_back, trim(p_reason), public.current_email(), public.my_role()) returning id into v_id;
  update public.leave_days set status = 'cancelled', ended_by = public.current_email(), ended_at = now(), end_reason = trim(p_reason), end_ref = v_id
   where request_id = p_request and status = 'active' and day = any(v_days);
  perform public.req_event(p_request, case v_kind when 'total' then 'leave_cancelled' else 'leave_partially_cancelled' end, r.status, r.status, trim(p_reason),
    jsonb_build_object('days', to_jsonb(v_days), 'charge_back', v_back));
  perform public.notify_request(p_request, 'leave_cancelled',
    case v_kind when 'total' then 'Ακύρωση άδειας ' else 'Μερική ακύρωση άδειας ' end || r.employee_name || ' (' || r.ref || ')');
  return jsonb_build_object('ok', true, 'kind', v_kind, 'days', cardinality(v_days), 'charge_back', v_back);
end $$;

-- ═══════════════ Διορθώσεις υπολοίπων & ετήσιες βάσεις — ΓΔ, HR, λογιστήριο ═══════════════
create or replace function public.leave_adjust(p_code text, p_year int, p_new_value numeric, p_as_of date, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_prev numeric; v_id bigint; v_as_of date := coalesce(p_as_of, public.athens_today());
begin
  perform public.require_perm('leave.adjust');
  select * into e from public.employees where code = p_code for update;
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Γράψτε αιτιολογία διόρθωσης (τουλάχιστον 5 χαρακτήρες).'; end if;
  if p_new_value is null or abs(p_new_value) > 400 then raise exception 'Μη έγκυρη νέα τιμή.'; end if;
  if p_year > extract(year from v_as_of)::int then raise exception 'Το έτος δεν μπορεί να είναι μετά την ημερομηνία αναφοράς.'; end if;
  v_prev := round(public.leave_year_balance(p_code, p_year, v_as_of), 2);
  if v_prev = round(p_new_value, 2) then raise exception 'Η νέα τιμή είναι ίδια με την τρέχουσα (%).', v_prev; end if;
  insert into public.leave_adjustments(employee_code, leave_year, as_of, prev_value, new_value, delta, reason, created_by, created_role)
  values (p_code, p_year, v_as_of, v_prev, round(p_new_value, 2), round(p_new_value, 2) - v_prev, trim(p_reason), public.current_email(), public.my_role())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'prev', v_prev, 'new', round(p_new_value, 2));
end $$;

create or replace function public.leave_set_base(p_code text, p_annual numeric, p_valid_from date, p_note text, p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_old public.leave_entitlements;
begin
  perform public.require_perm('leave.adjust');
  select * into e from public.employees where code = p_code for update;
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if p_annual is null or p_annual < 0 or p_annual > 60 then raise exception 'Μη έγκυρες ετήσιες ημέρες.'; end if;
  if p_valid_from is null then raise exception 'Συμπληρώστε ημερομηνία ισχύος.'; end if;
  select * into v_old from public.leave_entitlements where employee_code = p_code and valid_from = p_valid_from and superseded_at is null for update;
  if found then
    if not coalesce(p_replace, false) then
      raise exception 'Υπάρχει ήδη ετήσια βάση με ισχύ % (% ημέρες). Επιλέξτε «Διόρθωση» για αντικατάσταση με καταγραφή.', to_char(p_valid_from, 'DD/MM/YYYY'), v_old.annual_days;
    end if;
    if length(trim(coalesce(p_note, ''))) < 5 then raise exception 'Γράψτε αιτιολογία διόρθωσης.'; end if;
    update public.leave_entitlements set superseded_at = now(), superseded_by = public.current_email() where id = v_old.id;
  end if;
  insert into public.leave_entitlements(employee_code, annual_days, valid_from, note, set_by)
  values (p_code, p_annual, p_valid_from, nullif(trim(p_note), ''), public.current_email());
  return jsonb_build_object('ok', true);
end $$;

-- Πρόταση ετήσιων βάσεων από πρόσληψη + σύστημα εργασίας (ΔΕΝ αποθηκεύεται· η αποθήκευση γίνεται ρητά).
-- ΚΑΝΟΝΑΣ ΠΡΟΣ ΕΠΙΒΕΒΑΙΩΣΗ: 20/24 από την πρόσληψη, 21/25 από την 1η επέτειο, 22/26 από τη 2η επέτειο.
create or replace function public.leave_suggest_bases(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; v_dates date[]; d date; ww smallint; yrs int; v_base numeric; v_prev numeric; v_out jsonb := '[]'::jsonb;
begin
  if not public.has_perm('leave.view') or not public.employee_in_scope(p_code) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  select * into e from public.employees where code = p_code;
  if e.hire_date is null then return jsonb_build_object('rows', '[]'::jsonb, 'note', 'Λείπει η ημερομηνία πρόσληψης.'); end if;
  select array_agg(distinct x order by x) into v_dates from (
    select e.hire_date x union select (e.hire_date + interval '1 year')::date union select (e.hire_date + interval '2 years')::date
    union select valid_from from public.employee_work_terms where employee_code = p_code and valid_from > e.hire_date) z;
  foreach d in array v_dates loop
    select work_week into ww from public.work_terms_on(p_code, d);
    continue when ww is null;
    yrs := date_part('year', age(d, e.hire_date))::int;
    v_base := case ww when 5 then 20 + least(yrs, 2) else 24 + least(yrs, 2) end;
    if v_base is distinct from v_prev then
      v_out := v_out || jsonb_build_object('valid_from', d, 'annual_days', v_base, 'work_week', ww, 'service_years', yrs,
                 'exists', exists (select 1 from public.leave_entitlements x where x.employee_code = p_code and x.valid_from = d and x.superseded_at is null));
      v_prev := v_base;
    end if;
  end loop;
  return jsonb_build_object('rows', v_out, 'rule', '20/24 από την πρόσληψη · 21/25 από την 1η επέτειο · 22/26 από τη 2η επέτειο (προς επιβεβαίωση)');
end $$;

-- ═══════════════ Εκκαθάριση μετά τις 31/03 — ΓΔ, λογιστήριο ═══════════════
create or replace function public.leave_settle(p_code text, p_year int, p_days numeric, p_amount numeric, p_paid_on date, p_doc jsonb, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_out numeric; v_id bigint;
begin
  perform public.require_perm('leave.settle');
  select * into e from public.employees where code = p_code for update;   -- σειριοποίηση: αποτρέπει διπλή πληρωμή από ταυτόχρονα πατήματα
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if public.athens_today() <= make_date(p_year + 1, 3, 31) then
    raise exception 'Οι ημέρες του % μπορούν να ληφθούν έως 31/03/%. Η εκκαθάριση καταχωρίζεται μετά.', p_year, p_year + 1;
  end if;
  if p_days is null or p_days <= 0 then raise exception 'Συμπληρώστε τις ημέρες που εκκαθαρίζονται.'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'Συμπληρώστε το ποσό.'; end if;
  if p_paid_on is null then raise exception 'Συμπληρώστε την ημερομηνία πληρωμής.'; end if;
  v_out := round(public.leave_year_balance(p_code, p_year, public.athens_today()), 2);
  if v_out <= 0 then raise exception 'Δεν υπάρχει υπόλοιπο προς εκκαθάριση για το % (ήδη εκκαθαρίστηκε ή δεν υπάρχει).', p_year; end if;
  if round(p_days, 2) > v_out then raise exception 'Οι ημέρες (%) υπερβαίνουν το υπόλοιπο προς εκκαθάριση (%). Αποτρέπεται διπλή πληρωμή.', p_days, v_out; end if;
  if p_doc is not null and nullif(p_doc->>'data', '') is not null then
    if (p_doc->>'data') !~ '^[A-Za-z0-9+/=]+$' or length(p_doc->>'data') > 5600000 then raise exception 'Μη έγκυρο παραστατικό (έως 4 MB).'; end if;
  end if;
  insert into public.leave_settlements(employee_code, leave_year, days, amount, paid_on, doc_name, doc_mime, doc_data, note, created_by)
  values (p_code, p_year, round(p_days, 2), round(p_amount, 2), p_paid_on, left(p_doc->>'name', 200), nullif(p_doc->>'mime', ''), nullif(p_doc->>'data', ''),
          nullif(trim(p_note), ''), public.current_email())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'remaining', v_out - round(p_days, 2));
end $$;

create or replace function public.leave_settle_void(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.leave_settlements;
begin
  perform public.require_perm('leave.settle');
  select * into s from public.leave_settlements where id = p_id for update;
  if not found or not public.employee_in_scope(s.employee_code) then raise exception 'Η εγγραφή δεν βρέθηκε.'; end if;
  if s.voided_at is not null then raise exception 'Έχει ήδη ακυρωθεί.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Γράψτε αιτιολογία ακύρωσης.'; end if;
  update public.leave_settlements set voided_at = now(), voided_by = public.current_email(), void_reason = trim(p_reason) where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Λίστα «Προς εκκαθάριση από το λογιστήριο»: υπόλοιπα προηγούμενων ετών μετά την προθεσμία της 31/03
create or replace function public.leave_to_settle(p_year int default null)
returns table (employee_code text, employee_name text, store text, leave_year int, outstanding numeric, settled numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_today date := public.athens_today(); v_y int;
begin
  if not (public.has_perm('leave.settle') or public.has_perm('leave.view')) then raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.'; end if;
  v_y := coalesce(p_year, case when v_today > make_date(extract(year from v_today)::int, 3, 31) then extract(year from v_today)::int - 1 else extract(year from v_today)::int - 2 end);
  if v_today <= make_date(v_y + 1, 3, 31) then return; end if;
  return query
    select e.code, e.first || ' ' || e.last, e.store, v_y, round(public.leave_year_balance(e.code, v_y, v_today), 2), public.leave_settled(e.code, v_y)
      from public.employees e
     where public.can_see_store(e.store)
       and (exists (select 1 from public.leave_entitlements x where x.employee_code = e.code and x.superseded_at is null)
            or exists (select 1 from public.leave_adjustments x where x.employee_code = e.code and x.leave_year = v_y))
       and round(public.leave_year_balance(e.code, v_y, v_today), 2) > 0
     order by e.store, e.last, e.first;
end $$;

-- ═══════════════ Καρτέλα εργαζομένου: άδειες ═══════════════
create or replace function public.leave_card(p_code text, p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_as_of date := coalesce(p_as_of, public.athens_today());
begin
  if not public.has_perm('leave.view') or not public.employee_in_scope(p_code) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  return jsonb_build_object(
    'balance', public.leave_balance_calc(p_code, v_as_of),
    'sick', public.sick_status(p_code, v_as_of),
    'entitlements', (select coalesce(jsonb_agg(to_jsonb(x) order by x.valid_from desc, x.set_at desc), '[]') from public.leave_entitlements x where x.employee_code = p_code),
    'adjustments', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]') from public.leave_adjustments x where x.employee_code = p_code),
    'settlements', (select coalesce(jsonb_agg(to_jsonb(x) - 'doc_data' || jsonb_build_object('has_doc', x.doc_data is not null) order by x.created_at desc), '[]')
                      from public.leave_settlements x where x.employee_code = p_code),
    'cancellations', (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('ref', r.ref) order by c.at desc), '[]')
                        from public.leave_cancellations c join public.hr_requests r on r.id = c.request_id where r.employee_code = p_code),
    'days', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'request_id', d.request_id, 'ref', r.ref, 'day', d.day, 'leave_type', d.leave_type,
                     'label', lt.label, 'chargeable', d.chargeable, 'charge', d.charge, 'status', d.status, 'end_reason', d.end_reason,
                     'years', (select jsonb_agg(jsonb_build_object('year', c.leave_year, 'amount', c.amount)) from public.leave_charges c where c.leave_day_id = d.id))
                     order by d.day desc), '[]')
               from public.leave_days d join public.hr_requests r on r.id = d.request_id left join public.leave_types lt on lt.code = d.leave_type
              where d.employee_code = p_code and d.day >= make_date(extract(year from v_as_of)::int - 1, 1, 1)));
end $$;

create or replace function public.leave_settlement_doc(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.leave_settlements;
begin
  perform public.require_perm('leave.settle', 'leave.adjust');
  select * into s from public.leave_settlements where id = p_id;
  if not found or not public.employee_in_scope(s.employee_code) or s.doc_data is null then raise exception 'Το παραστατικό δεν βρέθηκε.'; end if;
  return jsonb_build_object('name', s.doc_name, 'mime', s.doc_mime, 'data', s.doc_data);
end $$;

-- Έλεγχος αιτήματος (για την οθόνη αιτήματος / απόφασης)
create or replace function public.leave_check(p_request uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.hr_requests; v_type text;
begin
  select * into r from public.hr_requests where id = p_request;
  if not found or not public.can_see_store(r.store) or not (public.has_perm('requests.view') or public.has_perm('leave.view')) then
    raise exception 'Το αίτημα δεν βρέθηκε.';
  end if;
  if r.category not in ('leave','leave_change') or r.start_date is null then return null; end if;
  v_type := coalesce(r.leave_type, (select leave_type from public.hr_requests where id = r.original_request_id));
  return public.leave_preview(r.employee_code, r.start_date, r.end_date, v_type, r.id)
    || jsonb_build_object('active_days', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'charge', d.charge, 'chargeable', d.chargeable) order by d.day), '[]')
                                            from public.leave_days d where d.request_id = r.id and d.status = 'active'),
                          'original', case when r.original_request_id is not null then (select jsonb_build_object('id', o.id, 'ref', o.ref, 'start', o.start_date, 'end', o.end_date)
                                                                                         from public.hr_requests o where o.id = r.original_request_id) end);
end $$;

-- ═══════════════ Ημερολόγιο αδειών (από τα ίδια δεδομένα αιτημάτων — καμία δεύτερη καταχώριση) ═══════════════
-- status: approved (εγκεκριμένη ημέρα) · pending (εκκρεμές αίτημα: για προγραμματισμό, ΔΕΝ αφαιρεί από την κάλυψη)
--         cancelled / rejected (μόνο αν ζητηθούν)
create or replace function public.leave_calendar(p_from date, p_to date, p_store text default null, p_specialty text default null, p_include_closed boolean default false)
returns table (employee_code text, employee_name text, store text, specialty text, day date, status text, leave_type text, label text, request_id uuid, ref text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_perm('leave.view') then raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'Μη έγκυρο διάστημα.'; end if;
  return query
  select * from (
    select d.employee_code as c_code, e.first || ' ' || e.last as c_name, d.store as c_store, e.specialty as c_spec, d.day as c_day,
           case d.status when 'active' then 'approved' else 'cancelled' end as c_status, d.leave_type as c_type, lt.label as c_label, d.request_id as c_req, r.ref as c_ref
      from public.leave_days d join public.employees e on e.code = d.employee_code join public.hr_requests r on r.id = d.request_id
      left join public.leave_types lt on lt.code = d.leave_type
     where d.day between p_from and p_to and (d.status = 'active' or (p_include_closed and d.status = 'cancelled'))
    union all
    select r.employee_code, r.employee_name, r.store, e.specialty, g::date,
           case when r.status = 'rejected' then 'rejected' else 'pending' end,
           coalesce(r.leave_type, o.leave_type), coalesce(r.leave_type_label, o.leave_type_label), r.id, r.ref
      from public.hr_requests r join public.employees e on e.code = r.employee_code
      left join public.hr_requests o on o.id = r.original_request_id
      cross join lateral generate_series(greatest(r.start_date, p_from), least(r.end_date, p_to), interval '1 day') g
     where r.category in ('leave','leave_change') and r.start_date <= p_to and r.end_date >= p_from
       and (r.status in ('submitted','under_review','needs_info','awaiting_gm') or (p_include_closed and r.status = 'rejected'))
  ) x
  where public.can_see_store(x.c_store) and (p_store is null or x.c_store = p_store) and (p_specialty is null or x.c_spec = p_specialty)
  order by x.c_day, x.c_name;
end $$;

-- ═══════════════ Πρόγραμμα εβδομάδας με κάλυψη ανά μισάωρο ═══════════════
-- Μετράει όσους είναι προγραμματισμένοι στην αρχή κάθε μισάωρου, ΧΩΡΙΣ όσους έχουν εγκεκριμένη άδεια/απουσία
-- ή έχουν αποχωρήσει. Εκκρεμή αιτήματα εμφανίζονται αλλά δεν αφαιρούν από την κάλυψη.
-- Υπο/υπερστελέχωση εμφανίζεται ΜΟΝΟ όπου έχουν οριστεί απαιτήσεις κάλυψης.
create or replace function public.sched_week(p_store text, p_week_start date, p_specialty text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_days date[]; d date; e record; v_emps jsonb := '[]'::jsonb; v_day jsonb; v_cov jsonb := '{}'::jsonb; s jsonb; v_seg jsonb; v_min int;
        v_planned int; v_leave_min int; v_has_leave boolean; v_leave jsonb; v_pending jsonb; v_departed boolean; v_daymap jsonb; v_terms record;
        v_hours jsonb := '{}'::jsonb; v_open time; v_close time; v_lo int; v_hi int; v_slot int; v_cnt int; v_req int; v_slots jsonb; v_present jsonb;
        v_needs jsonb := '[]'::jsonb; v_wd int; v_inopen boolean;
begin
  if not public.has_perm('schedule.view') or not public.can_see_store(p_store) then raise exception 'Δεν έχετε πρόσβαση στο πρόγραμμα του καταστήματος.'; end if;
  if extract(isodow from p_week_start) <> 1 then raise exception 'Η εβδομάδα ξεκινά Δευτέρα.'; end if;
  select array_agg((p_week_start + i)::date order by i) into v_days from generate_series(0, 6) i;
  -- εργαζόμενοι: όσοι ανήκουν στο κατάστημα ή έχουν πρόγραμμα του καταστήματος μέσα στην εβδομάδα
  for e in
    select x.code, x.first, x.last, x.specialty, x.hire_date, x.leave_date from public.employees x
     where (x.store = p_store or exists (select 1 from public.schedule_patterns p where p.employee_code = x.code and p.store = p_store and p.status = 'active'
                                           and p.valid_from <= p_week_start + 6 and (p.valid_to is null or p.valid_to >= p_week_start))
                              or exists (select 1 from public.schedule_overrides o where o.employee_code = x.code and o.store = p_store and o.status = 'active'
                                           and o.day between p_week_start and p_week_start + 6))
       and (p_specialty is null or x.specialty = p_specialty)
       and (x.hire_date is null or x.hire_date <= p_week_start + 6)
       and (x.leave_date is null or x.leave_date >= p_week_start - 28 or exists (select 1 from public.schedule_patterns p where p.employee_code = x.code and p.status = 'active' and (p.valid_to is null or p.valid_to >= p_week_start)))
       and (x.status = 'Ενεργός' or x.leave_date is not null)
     order by x.specialty nulls last, x.last, x.first
  loop
    v_daymap := '{}'::jsonb; v_planned := 0; v_leave_min := 0; v_has_leave := false;
    select * into v_terms from public.work_terms_on(e.code, p_week_start);
    foreach d in array v_days loop
      s := public.sched_day(e.code, d);
      if s is not null and s->>'store' is distinct from p_store then s := null; end if;
      v_seg := coalesce(s->'segments', '[]'::jsonb);
      v_min := public.sched_minutes(v_seg);
      select jsonb_build_object('type', ld.leave_type, 'label', lt.label, 'request_id', ld.request_id, 'charge', ld.charge) into v_leave
        from public.leave_days ld left join public.leave_types lt on lt.code = ld.leave_type where ld.employee_code = e.code and ld.day = d and ld.status = 'active';
      select jsonb_build_object('label', coalesce(r.leave_type_label, 'άδεια'), 'request_id', r.id, 'ref', r.ref) into v_pending
        from public.hr_requests r where r.employee_code = e.code and r.category in ('leave','leave_change')
         and r.status in ('submitted','under_review','needs_info','awaiting_gm') and d between r.start_date and r.end_date limit 1;
      v_departed := (e.leave_date is not null and d > e.leave_date) or (e.hire_date is not null and d < e.hire_date);
      if v_leave is not null then v_has_leave := true; v_leave_min := v_leave_min + v_min;
      elsif not v_departed then v_planned := v_planned + v_min; end if;
      if v_min > 0 and (v_leave is not null or v_departed) then
        v_needs := v_needs || jsonb_build_object('employee_code', e.code, 'employee_name', e.first || ' ' || e.last, 'day', d, 'segments', v_seg,
                                                 'why', case when v_departed then 'αποχώρηση' else coalesce(v_leave->>'label', 'άδεια') end);
      end if;
      v_daymap := v_daymap || jsonb_build_object(d::text, jsonb_build_object('segments', v_seg, 'source', s->>'source', 'minutes', v_min,
        'overlap', public.sched_overlaps(v_seg), 'leave', v_leave, 'pending', v_pending, 'departed', v_departed,
        'reason', s->>'reason', 'counts', v_leave is null and not v_departed and v_min > 0));
    end loop;
    v_emps := v_emps || jsonb_build_object('code', e.code, 'name', e.first || ' ' || e.last, 'specialty', e.specialty, 'leave_date', e.leave_date,
      'work_week', v_terms.work_week, 'contract_hours', v_terms.weekly_hours, 'planned_hours', round(v_planned / 60.0, 2),
      'leave_hours', round(v_leave_min / 60.0, 2), 'has_leave', v_has_leave,
      'deviation', case when v_terms.weekly_hours is not null then round(v_planned / 60.0 - v_terms.weekly_hours, 2) end, 'days', v_daymap);
  end loop;

  -- κάλυψη ανά μισάωρο
  foreach d in array v_days loop
    v_wd := extract(isodow from d)::int;
    select h.opens, h.closes into v_open, v_close from public.store_hours h
     where h.store = p_store and h.weekday = v_wd and h.valid_from <= d and (h.specialty is not distinct from p_specialty)
     order by h.valid_from desc limit 1;
    if v_open is null and p_specialty is not null then
      select h.opens, h.closes into v_open, v_close from public.store_hours h
       where h.store = p_store and h.weekday = v_wd and h.valid_from <= d and h.specialty is null order by h.valid_from desc limit 1;
    end if;
    if v_open is null and p_specialty is null then
      -- όλα τα τμήματα: από το νωρίτερο άνοιγμα έως το αργότερο κλείσιμο των τμημάτων
      select min(h.opens), max(h.closes) into v_open, v_close from public.store_hours h
       where h.store = p_store and h.weekday = v_wd
         and h.valid_from = (select max(h2.valid_from) from public.store_hours h2 where h2.store = h.store and h2.weekday = h.weekday
                               and h2.specialty is not distinct from h.specialty and h2.valid_from <= d);
    end if;
    v_hours := v_hours || jsonb_build_object(d::text, case when v_open is not null then jsonb_build_object('opens', to_char(v_open, 'HH24:MI'), 'closes', to_char(v_close, 'HH24:MI')) end);
    -- εύρος: ωράριο λειτουργίας ∪ προγραμματισμένα διαστήματα
    select min(public.sched_min(x->>0)), max(public.sched_min(x->>1)) into v_lo, v_hi
      from jsonb_array_elements(v_emps) emp, jsonb_array_elements(emp->'days'->d::text->'segments') x;
    if v_open is not null then
      v_lo := least(coalesce(v_lo, 1440), extract(hour from v_open)::int * 60 + extract(minute from v_open)::int);
      v_hi := greatest(coalesce(v_hi, 0), extract(hour from v_close)::int * 60 + extract(minute from v_close)::int);
    end if;
    v_slots := '[]'::jsonb;
    if v_lo is not null and v_hi is not null and v_hi > v_lo then
      v_slot := (v_lo / 30) * 30;
      while v_slot < v_hi loop
        select count(*), coalesce(jsonb_agg(emp->>'code'), '[]') into v_cnt, v_present from jsonb_array_elements(v_emps) emp
         where (emp->'days'->d::text->>'counts')::boolean
           and exists (select 1 from jsonb_array_elements(emp->'days'->d::text->'segments') x
                        where public.sched_min(x->>0) <= v_slot and v_slot < public.sched_min(x->>1));
        select sum(r.required) into v_req from public.staffing_requirements r
         where r.store = p_store and r.weekday = v_wd and (r.specialty is not distinct from p_specialty or (p_specialty is null and r.specialty is null))
           and (extract(hour from r.slot_start)::int * 60 + extract(minute from r.slot_start)::int) = v_slot
           and r.valid_from <= d and (r.valid_to is null or r.valid_to >= d);
        v_inopen := v_open is not null and v_slot >= extract(hour from v_open)::int * 60 + extract(minute from v_open)::int
                    and v_slot < extract(hour from v_close)::int * 60 + extract(minute from v_close)::int;
        v_slots := v_slots || jsonb_build_object('slot', lpad((v_slot / 60)::text, 2, '0') || ':' || lpad((v_slot % 60)::text, 2, '0'),
          'count', v_cnt, 'present', v_present, 'open', v_inopen, 'uncovered', v_inopen and v_cnt = 0,
          'required', v_req, 'staffing', case when v_req is null then null when v_cnt < v_req then 'under' when v_cnt > v_req then 'over' else 'ok' end);
        v_slot := v_slot + 30;
      end loop;
    end if;
    v_cov := v_cov || jsonb_build_object(d::text, v_slots);
    v_open := null; v_close := null;
  end loop;

  return jsonb_build_object('store', p_store, 'week_start', p_week_start, 'days', to_jsonb(v_days), 'specialty', p_specialty,
    'hours', v_hours, 'employees', v_emps, 'coverage', v_cov, 'needs_cover', v_needs,
    'finalized', (select jsonb_build_object('by', finalized_by, 'at', finalized_at) from public.schedule_finalizations where store = p_store and week_start = p_week_start),
    'holidays', (select coalesce(jsonb_object_agg(day, label), '{}') from public.public_holidays where day between p_week_start and p_week_start + 6),
    'can_manage', public.has_perm('schedule.manage') and public.can_see_store(p_store));
end $$;

create or replace function public.sched_history(p_store text, p_from date default null, p_to date default null, p_employee text default null)
returns setof public.schedule_changes language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_perm('schedule.view') or not public.can_see_store(p_store) then raise exception 'Δεν έχετε πρόσβαση.'; end if;
  return query select * from public.schedule_changes c where c.store = p_store
    and (p_employee is null or c.employee_code = p_employee)
    and (p_from is null or coalesce(c.affected_to, c.affected_from, c.at::date) >= p_from)
    and (p_to is null or coalesce(c.affected_from, c.at::date) <= p_to)
    order by c.at desc limit 1000;
end $$;

-- ═══════════════ Επεκτάσεις υπαρχουσών συναρτήσεων αιτημάτων ═══════════════

-- Αλλαγή ημερομηνιών: το νέο αίτημα δένεται με την εγκεκριμένη άδεια· μέχρι την έγκρισή του ισχύει η αρχική
create or replace function public.leave_change_init(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; o public.hr_requests;
begin
  select * into r from public.hr_requests where id = p_id;
  begin select * into o from public.hr_requests where id = nullif(p->>'original_request_id', '')::uuid;
  exception when others then raise exception 'Επιλέξτε την εγκεκριμένη άδεια που αλλάζει.'; end;
  if o.id is null or o.category <> 'leave' or o.employee_code <> r.employee_code then raise exception 'Επιλέξτε την εγκεκριμένη άδεια που αλλάζει.'; end if;
  if o.status not in ('approved','completed') or not exists (select 1 from public.leave_days where request_id = o.id and status = 'active') then
    raise exception 'Αλλάζουν ημερομηνίες μόνο σε εγκεκριμένη άδεια με ενεργές ημέρες.';
  end if;
  update public.hr_requests set original_request_id = o.id, leave_type = o.leave_type, leave_type_label = o.leave_type_label,
         entry_mode = 'manager_record' where id = p_id;
end $$;

create or replace function public.req_validate_leave_change(r public.hr_requests) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if r.category <> 'leave_change' then return; end if;
  if r.original_request_id is null then raise exception 'Επιλέξτε την εγκεκριμένη άδεια που αλλάζει.'; end if;
  if r.start_date is null or r.end_date is null then raise exception 'Συμπληρώστε τις νέες ημερομηνίες έναρξης και λήξης.'; end if;
  if r.end_date < r.start_date then raise exception 'Η λήξη δεν μπορεί να είναι πριν από την έναρξη.'; end if;
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
  if v_cat = 'leave_change' then perform public.leave_change_init(v_id, p); end if;
  update public.hr_requests set version = 1 where id = v_id;
  perform public.req_event(v_id, 'create', null, 'draft', null,
    jsonb_build_object('category', v_cat, 'entry_mode', v_mode));
  return jsonb_build_object('id', v_id, 'ref', v_ref, 'version', 1);
end $$;

create or replace function public.req_validate(r public.hr_requests) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if r.process = 'employee' then
    if r.entry_mode = 'employee_fill' and coalesce(r.written_by, '') not like 'employee:%' then
      raise exception 'Ο εργαζόμενος δεν έχει ολοκληρώσει ακόμη τη συμπλήρωση.';
    end if;
    if length(trim(coalesce(r.body, ''))) < 10 then raise exception 'Συμπληρώστε το κείμενο του αιτήματος.'; end if;
  end if;
  if r.category = 'leave' then
    if r.leave_type is null then raise exception 'Επιλέξτε είδος άδειας.'; end if;
    if r.start_date is null or r.end_date is null then raise exception 'Συμπληρώστε ημερομηνία έναρξης και λήξης.'; end if;
    if r.end_date < r.start_date then raise exception 'Η λήξη δεν μπορεί να είναι πριν από την έναρξη.'; end if;
    if r.days_requested is null then raise exception 'Συμπληρώστε τον αριθμό ημερών άδειας.'; end if;
    if r.days_requested > (r.end_date - r.start_date + 1) then
      raise exception 'Οι ημέρες άδειας (%) δεν μπορούν να υπερβαίνουν τις ημερολογιακές ημέρες του διαστήματος (%).', r.days_requested, (r.end_date - r.start_date + 1);
    end if;
  end if;
  perform public.req_validate_leave_change(r);
  if r.process = 'manager' then
    if length(trim(coalesce(r.details->>'description',''))) < 10 then raise exception 'Συμπληρώστε περιγραφή (τουλάχιστον 10 χαρακτήρες).'; end if;
    if r.incident_date is null then raise exception 'Συμπληρώστε ημερομηνία περιστατικού.'; end if;
    if r.incident_date > public.athens_today() then raise exception 'Η ημερομηνία περιστατικού δεν μπορεί να είναι μελλοντική.'; end if;
    if length(trim(coalesce(r.details->>'examples',''))) < 3 then raise exception 'Συμπληρώστε συγκεκριμένα παραδείγματα.'; end if;
    if length(trim(coalesce(r.details->>'prior_discussion',''))) < 2 then raise exception 'Συμπληρώστε αν προηγήθηκε συζήτηση με τον εργαζόμενο.'; end if;
    if length(trim(coalesce(r.details->>'proposed_action',''))) < 2 then raise exception 'Συμπληρώστε την προτεινόμενη ενέργεια.'; end if;
  end if;
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
  perform public.leave_on_submit(p_id);
  update public.hr_requests set status = 'submitted', submitted_by = public.current_email(), submitted_at = now(),
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'submit', 'draft', 'submitted', null);
  return jsonb_build_object('ok', true, 'status', 'submitted', 'version', r.version + 1);
end $$;

create or replace function public.req_forward_gm(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, p_version);
  if public.req_flow(r.category) <> 'gm' and not (r.category in ('leave','leave_change') and coalesce(r.leave_excess, 0) > 0) then
    raise exception 'Η προώθηση αφορά αυξήσεις, αλλαγές σύμβασης και άδειες με υπέρβαση υπολοίπου.';
  end if;
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

create or replace function public.req_decide(p_id uuid, p_outcome text, p jsonb, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_role(array['owner','hr']);
  r public.hr_requests; v_flow text; v_rev boolean; v_reason public.reject_reasons;
  v_prev bigint; v_new bigint; v_to text; v_msg text := trim(coalesce(p->>'message',''));
  v_start date; v_end date; v_days numeric; v_draft text; v_plan jsonb;
begin
  r := public.req_lock(p_id, p_version);
  v_flow := public.req_flow(r.category);
  if p_outcome not in ('approve','reject','needs_info') then raise exception 'Μη έγκυρη απόφαση.'; end if;
  if r.status in ('draft','completed') then raise exception 'Δεν υπάρχει εκκρεμότητα για απόφαση.'; end if;
  v_rev := r.status in ('approved','rejected');
  if v_rev and v_role <> 'owner' then raise exception 'Η αναθεώρηση απόφασης γίνεται μόνο από τη Γενική Διευθύντρια.'; end if;
  if v_rev and p_outcome = 'needs_info' then raise exception 'Η αναθεώρηση είναι έγκριση ή απόρριψη.'; end if;
  if v_flow = 'report' and p_outcome <> 'needs_info' then
    raise exception 'Οι αναφορές δεν εγκρίνονται ούτε απορρίπτονται· ολοκληρώνεται η εξέτασή τους.';
  end if;
  if p_outcome in ('approve','reject') and v_flow in ('gm','warning') and v_role <> 'owner' then
    raise exception 'Απαιτείται τελική απόφαση της Γενικής Διευθύντριας.';
  end if;
  if v_flow = 'warning' and p_outcome = 'approve' then
    select warning_draft into v_draft from public.hr_request_internal where request_id = p_id;
    if coalesce(v_draft,'') = '' then raise exception 'Δεν υπάρχει προσχέδιο του HR για την προειδοποίηση.'; end if;
    if not v_rev and r.status <> 'awaiting_gm' then raise exception 'Το HR πρέπει πρώτα να στείλει το προσχέδιο για απόφαση.'; end if;
    if v_msg = '' then v_msg := v_draft; end if;
  end if;
  if length(v_msg) < 10 then raise exception 'Συμπληρώστε το κείμενο της απόφασης.'; end if;

  if p_outcome = 'approve' and r.category in ('leave','leave_change') then
    begin
      v_start := coalesce(nullif(p->>'approved_start','')::date, r.start_date);
      v_end := coalesce(nullif(p->>'approved_end','')::date, r.end_date);
      v_days := coalesce(nullif(replace(p->>'approved_days', ',', '.'),'')::numeric, r.days_requested);
    exception when others then raise exception 'Μη έγκυρες εγκεκριμένες ημερομηνίες ή ημέρες.'; end;
    if v_end < v_start then raise exception 'Η λήξη δεν μπορεί να είναι πριν από την έναρξη.'; end if;
    v_plan := public.leave_on_decision(p_id, 'approve', p, v_role, v_start, v_end, r.status in ('approved','completed'));
    if (v_plan->>'annual')::boolean then
      v_days := (v_plan->>'requested')::numeric;
      if v_days <= 0 then raise exception 'Δεν υπάρχουν εργάσιμες ημέρες χρέωσης στο διάστημα (πρόγραμμα, αργίες ή σύστημα εργασίας).'; end if;
    end if;
    if v_days is null or v_days <= 0 or v_days > (v_end - v_start + 1) then raise exception 'Μη έγκυρος αριθμός εγκεκριμένων ημερών.'; end if;
  end if;

  if p_outcome = 'reject' then
    select * into v_reason from public.reject_reasons where code = p->>'reason_code' and active;
    if not found then raise exception 'Επιλέξτε λόγο απόρριψης.'; end if;
    if r.category = 'leave' and v_reason.leave_types is not null and not (r.leave_type = any(v_reason.leave_types)) then
      raise exception 'Ο λόγος «%» δεν εφαρμόζεται σε %.', v_reason.label, r.leave_type_label;
    end if;
    if r.category <> 'leave' and not v_reason.for_other then raise exception 'Ο λόγος «%» αφορά μόνο άδειες.', v_reason.label; end if;
    if length(trim(coalesce(p->>'reason_text',''))) < 10 then raise exception 'Γράψτε συγκεκριμένη αιτιολογία (τουλάχιστον 10 χαρακτήρες).'; end if;
  end if;
  if p_outcome = 'needs_info' and length(trim(coalesce(p->>'info',''))) < 3 then raise exception 'Γράψτε ποια στοιχεία απαιτούνται.'; end if;

  update public.hr_decisions set superseded_at = now() where request_id = p_id and superseded_at is null returning id into v_prev;
  insert into public.hr_decisions(request_id, outcome, decided_by, decided_role, reason_code, reason_label, reason_text, message,
         template_version_id, approved_start, approved_end, approved_days, alternative, info_requested, supersedes, is_revision, leave_days_json, overdraw_days, overdraw_available)
  values (p_id, p_outcome, public.current_email(), v_role,
          case when p_outcome = 'reject' then v_reason.code end, case when p_outcome = 'reject' then v_reason.label end,
          case when p_outcome = 'reject' then trim(p->>'reason_text') end, v_msg,
          nullif(p->>'template_version_id','')::bigint, v_start, v_end, v_days,
          case when p_outcome = 'reject' then coalesce(nullif(trim(p->>'alternative'),''), 'Προς συνεννόηση') end,
          case when p_outcome = 'needs_info' then trim(p->>'info') end, v_prev, v_rev, v_plan->'days', nullif((v_plan->>'excess')::numeric, 0),
          case when (v_plan->>'excess')::numeric > 0 then (v_plan->>'available')::numeric end)
  returning id into v_new;
  if r.category in ('leave','leave_change') and p_outcome <> 'approve' then
    perform public.leave_on_decision(p_id, p_outcome, p, v_role, null, null, r.status = 'approved');
  end if;
  if coalesce((v_plan->>'excess')::numeric, 0) > 0 then
    perform public.req_event(p_id, 'overdraw_approved', r.status, 'approved', null,
      jsonb_build_object('requested', v_plan->'requested', 'available', v_plan->'available', 'excess', v_plan->'excess'));
  end if;
  v_to := case p_outcome when 'approve' then 'approved' when 'reject' then 'rejected' else 'needs_info' end;
  update public.hr_requests set status = v_to, assignee = coalesce(assignee, public.current_email()),
         notified_at = case when v_rev then null else notified_at end,
         notified_by = case when v_rev then null else notified_by end,
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, case when v_rev then 'revise' else 'decide' end, r.status, v_to, p->>'reason_text',
    jsonb_build_object('decision_id', v_new, 'outcome', p_outcome, 'supersedes', v_prev));
  return jsonb_build_object('ok', true, 'status', v_to, 'decision_id', v_new, 'version', r.version + 1);
end $$;

alter table public.public_holidays     enable row level security;
alter table public.leave_entitlements  enable row level security;
alter table public.leave_days          enable row level security;
alter table public.leave_charges       enable row level security;
alter table public.leave_adjustments   enable row level security;
alter table public.leave_cancellations enable row level security;
alter table public.leave_settlements   enable row level security;
alter table public.notifications       enable row level security;
create policy hol_read  on public.public_holidays for select to authenticated using (public.my_role() is not null);
create policy hol_write on public.public_holidays for all to authenticated using (public.has_perm('settings.manage')) with check (public.has_perm('settings.manage'));
create policy lent_read on public.leave_entitlements for select to authenticated using (public.has_perm('leave.view') and public.employee_in_scope(employee_code));
create policy ld_read   on public.leave_days for select to authenticated using ((public.has_perm('leave.view') or public.has_perm('schedule.view')) and public.can_see_store(store));
create policy lc_read   on public.leave_charges for select to authenticated using (exists (select 1 from public.leave_days d where d.id = leave_day_id));
create policy ladj_read on public.leave_adjustments for select to authenticated using (public.has_perm('leave.view') and public.employee_in_scope(employee_code));
create policy lcan_read on public.leave_cancellations for select to authenticated using (exists (select 1 from public.hr_requests r where r.id = request_id) or public.has_perm('leave.cancel'));
create policy lset_read on public.leave_settlements for select to authenticated using ((public.has_perm('leave.settle') or public.has_perm('leave.adjust')) and public.employee_in_scope(employee_code));
create policy ntf_read  on public.notifications for select to authenticated using (user_email = public.current_email());
revoke all on public.leave_entitlements, public.leave_days, public.leave_charges, public.leave_adjustments, public.leave_cancellations,
  public.leave_settlements, public.notifications from anon, authenticated;
grant select on public.leave_entitlements, public.leave_days, public.leave_charges, public.leave_adjustments, public.leave_cancellations, public.notifications to authenticated;
grant select (id, employee_code, leave_year, days, amount, paid_on, doc_name, doc_mime, note, created_by, created_at, voided_at, voided_by, void_reason)
  on public.leave_settlements to authenticated;
revoke all on public.public_holidays from anon;
create trigger leave_adjustments_append_only before update or delete on public.leave_adjustments for each row execute function public.append_only();
create trigger leave_cancellations_append_only before update or delete on public.leave_cancellations for each row execute function public.append_only();
create trigger leave_charges_append_only before update or delete on public.leave_charges for each row execute function public.append_only();
create or replace function public.leave_days_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Οι ημέρες άδειας δεν διαγράφονται· ακυρώνονται.'; end if;
  if new.day is distinct from old.day or new.employee_code is distinct from old.employee_code or new.charge is distinct from old.charge
     or new.request_id is distinct from old.request_id then raise exception 'Οι ημέρες άδειας δεν τροποποιούνται· ακυρώνονται ή αντικαθίστανται.'; end if;
  return new;
end $$;
create trigger leave_days_guard before update or delete on public.leave_days for each row execute function public.leave_days_guard();
create trigger audit_leave_entitlements after insert or update on public.leave_entitlements for each row execute function public.audit_trigger();
create trigger audit_leave_settlements after insert or update on public.leave_settlements for each row execute function public.audit_trigger();
create trigger audit_holidays after insert or update or delete on public.public_holidays for each row execute function public.audit_trigger();

revoke execute on all functions in schema public from public, anon;
revoke execute on function public.leave_release(uuid, text, bigint, uuid), public.leave_book(uuid, jsonb),
  public.leave_on_decision(uuid, text, jsonb, text, date, date, boolean), public.leave_on_submit(uuid), public.notify_request(uuid, text, text),
  public.leave_change_init(uuid, jsonb), public.leave_days_guard(), public.sched_check_emp(text) from authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
