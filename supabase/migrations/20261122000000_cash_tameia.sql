-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Ταμεία (χωριστή εφαρμογή web/tameia/, ΙΔΙΑ βάση) · Μέρος 1: Κλείσιμο ταμείου
--   • Ένα φυσικό ταμείο ανά κατάστημα· πρωινό κλείσιμο (16:00), βραδινό, συμπληρωματικά της βραδινής.
--   • Ταμείο έναρξης 100 € (ρέστα): εκτός εισπράξεων και εκτός ποσού προς κατάθεση.
--   • Μετρητά (καταμέτρηση), κάρτες (ημερήσιο πακέτο POS), IRIS (ημερήσιο σύνολο), Live Pay ανά πελάτη.
--   • Έξοδα με παραστατικό, επιστροφές με έγκριση (δικαίωμα cash.refund_approve, αρχικά μόνο ΓΔ).
--   • Σύγκριση με SoftOne (καταχωρίζει ο manager), προσαρμογές με αιτιολογία, καταθέσεις τράπεζας.
--   • Ροή: ρεσεψιόν (σύνδεσμος καταστήματος) → manager (επιβεβαίωση) → λογιστήριο (έλεγχος & κλείδωμα).
--     Διόρθωση κλειδωμένης ημέρας: αίτημα λογιστηρίου → έγκριση ΓΔ → διόρθωση λογιστηρίου → νέο κλείδωμα.
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο νέοι πίνακες/συναρτήσεις/δικαιώματα. Τίποτα δεν διαγράφεται· οι εγγραφές ακυρώνονται με αιτιολογία.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ─────────────── Δικαιώματα (ίδιος πίνακας με την εφαρμογή HR, ενότητα «Ταμεία») ───────────────
insert into public.permissions(code, module, label, description, fixed_roles, sort) values
 ('cash.view',           'Ταμεία', 'Προβολή κλεισιμάτων ταμείου', 'Στο πεδίο καταστημάτων του ρόλου', null, 200),
 ('cash.manage',         'Ταμεία', 'Έλεγχος & καταχώριση (manager)', 'Πακέτο POS, SoftOne, προσαρμογές, καταθέσεις, επιβεβαίωση ημέρας', null, 201),
 ('cash.audit',          'Ταμεία', 'Έλεγχος λογιστηρίου & κλείδωμα', 'Έλεγχος με όνομα/ώρα, επιστροφή στον manager, αντιστοίχιση Live Pay με την τράπεζα', null, 202),
 ('cash.refund_approve', 'Ταμεία', 'Έγκριση επιστροφών χρημάτων', 'Αρχικά μόνο η Γενική Διεύθυνση', null, 203),
 ('cash.correct_apply',  'Ταμεία', 'Διόρθωση κλειδωμένων στοιχείων', 'Αίτημα διόρθωσης και εφαρμογή μετά την έγκριση της ΓΔ', null, 204),
 ('cash.correct_approve','Ταμεία', 'Έγκριση διορθώσεων κλειδωμένων στοιχείων', 'Μόνο η Γενική Διεύθυνση (δεν αλλάζει)', '{owner}', 205),
 ('cash.links',          'Ταμεία', 'Σύνδεσμοι ταμείου ρεσεψιόν', 'Δημιουργία, αντικατάσταση και ανάκληση του συνδέσμου ανά κατάστημα', null, 206),
 ('cash.settings',       'Ταμεία', 'Ρυθμίσεις ταμείων', 'Κατηγορίες εξόδων', null, 207)
on conflict (code) do nothing;

insert into public.role_permissions(role, perm, allowed)
select r, p, false from unnest(array['owner','hr','accounting','manager','trainer']) r
 cross join unnest(array['cash.view','cash.manage','cash.audit','cash.refund_approve','cash.correct_apply','cash.correct_approve','cash.links','cash.settings']) p
on conflict (role, perm) do nothing;
update public.role_permissions x set allowed = true from (values
 ('owner','cash.view'),('owner','cash.manage'),('owner','cash.audit'),('owner','cash.refund_approve'),('owner','cash.correct_approve'),('owner','cash.links'),('owner','cash.settings'),
 ('accounting','cash.view'),('accounting','cash.audit'),('accounting','cash.correct_apply'),
 ('manager','cash.view'),('manager','cash.manage')
) v(r, p) where x.role = v.r and x.perm = v.p and x.updated_by = 'system';

-- ─────────────── Πίνακες ───────────────
create table if not exists public.cash_expense_categories (
  name   text primary key check (length(trim(name)) between 2 and 60),
  sort   int not null default 0,
  active boolean not null default true
);
insert into public.cash_expense_categories(name, sort) values
 ('Καθαριότητα', 1), ('Αναλώσιμα', 2), ('Συντήρηση / Επισκευές', 3), ('Ταχυδρομικά / Courier', 4), ('Διάφορα', 5)
on conflict (name) do nothing;

create table if not exists public.cash_files (
  id          uuid primary key default gen_random_uuid(),
  filename    text not null check (length(filename) between 1 and 200),
  mime        text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','image/heic')),
  size        int not null check (size > 0 and size <= 4194304),
  data        text not null,          -- base64
  uploaded_by text not null,
  uploaded_at timestamptz not null default now()
);

create table if not exists public.cash_days (
  id            bigserial primary key,
  store         text not null references public.stores(name) on update cascade,
  day           date not null,
  status        text not null default 'open' check (status in ('open','confirmed','locked','correction')),
  float_amount  numeric(10,2) not null default 100 check (float_amount >= 0),
  pos_cards     numeric(10,2) check (pos_cards >= 0),        -- ημερήσιο πακέτο POS
  iris_total    numeric(10,2) check (iris_total >= 0),       -- IRIS ημέρας
  softone_cash  numeric(10,2) check (softone_cash >= 0),
  softone_cards numeric(10,2) check (softone_cards >= 0),
  softone_iris  numeric(10,2) check (softone_iris >= 0),
  manager_note  text,
  confirmed_by  text, confirmed_at timestamptz,
  audited_by    text, audited_name text, audited_at timestamptz,
  version       int not null default 1,
  created_at    timestamptz not null default now(),
  unique (store, day)
);

create table if not exists public.cash_shifts (
  id            bigserial primary key,
  day_id        bigint not null references public.cash_days(id),
  shift         text not null check (shift in ('morning','evening','supplement')),
  counted_cash  numeric(10,2) not null check (counted_cash >= 0),  -- πρωινό/βραδινό: σύνολο συρταριού (με τα 100 €)· συμπληρωματικό: επιπλέον μετρητά
  employee_code text,
  employee_name text,
  note          text,
  source        text not null check (source in ('link','app')),
  created_by    text not null,
  created_at    timestamptz not null default now(),
  voided_by     text, voided_at timestamptz, void_reason text
);
create unique index if not exists cash_one_shift on public.cash_shifts(day_id, shift) where shift in ('morning','evening') and voided_at is null;

create table if not exists public.cash_livepay (
  id         bigserial primary key,
  day_id     bigint not null references public.cash_days(id),
  shift      text check (shift in ('morning','evening','supplement')),
  customer   text not null check (length(trim(customer)) between 2 and 120),
  amount     numeric(10,2) not null check (amount > 0),
  created_by text not null, created_at timestamptz not null default now(),
  matched_by text, matched_at timestamptz, bank_ref text,      -- αντιστοίχιση με την τράπεζα (λογιστήριο)
  voided_by  text, voided_at timestamptz, void_reason text
);

create table if not exists public.cash_expenses (
  id           bigserial primary key,
  day_id       bigint not null references public.cash_days(id),
  shift        text check (shift in ('morning','evening','supplement')),
  expense_date date not null,
  amount       numeric(10,2) not null check (amount > 0),
  category     text not null references public.cash_expense_categories(name) on update cascade,
  description  text not null check (length(trim(description)) between 2 and 300),
  file_id      uuid not null references public.cash_files(id),
  created_by   text not null, created_at timestamptz not null default now(),
  voided_by    text, voided_at timestamptz, void_reason text
);

create table if not exists public.cash_refunds (
  id             bigserial primary key,
  day_id         bigint not null references public.cash_days(id),
  shift          text check (shift in ('morning','evening','supplement')),
  amount         numeric(10,2) not null check (amount > 0),
  method         text not null check (method in ('cash','card')),
  customer       text not null check (length(trim(customer)) between 2 and 120),
  reason         text not null check (length(trim(reason)) between 2 and 300),
  approver_email text not null,                                  -- ποιος ορίστηκε να εγκρίνει
  approver_name  text not null,
  status         text not null default 'pending' check (status in ('pending','approved','rejected')),
  decided_by     text, decided_name text, decided_at timestamptz, decision_note text,
  created_by     text not null, created_at timestamptz not null default now(),
  voided_by      text, voided_at timestamptz, void_reason text
);

create table if not exists public.cash_adjustments (
  id         bigserial primary key,
  day_id     bigint not null references public.cash_days(id),
  kind       text not null check (kind in ('cash','cards','iris')),
  amount     numeric(10,2) not null check (amount <> 0),          -- με πρόσημο: εξηγεί μέρος της διαφοράς
  reason     text not null check (length(trim(reason)) between 3 and 300),
  created_by text not null, created_at timestamptz not null default now(),
  voided_by  text, voided_at timestamptz, void_reason text
);

create table if not exists public.cash_deposits (
  id           bigserial primary key,
  day_id       bigint not null references public.cash_days(id),
  deposit_date date not null,
  amount       numeric(10,2) not null check (amount > 0),
  file_id      uuid not null references public.cash_files(id),
  created_by   text not null, created_at timestamptz not null default now(),
  voided_by    text, voided_at timestamptz, void_reason text
);

create table if not exists public.cash_corrections (
  id            bigserial primary key,
  day_id        bigint not null references public.cash_days(id),
  reason        text not null check (length(trim(reason)) between 5 and 500),
  status        text not null default 'pending' check (status in ('pending','approved','rejected','applied')),
  requested_by  text not null, requested_at timestamptz not null default now(),
  decided_by    text, decided_at timestamptz, decision_note text,
  applied_by    text, applied_at timestamptz
);
create unique index if not exists cash_one_open_correction on public.cash_corrections(day_id) where status in ('pending','approved');

create table if not exists public.cash_events (
  id     bigserial primary key,
  day_id bigint not null references public.cash_days(id),
  at     timestamptz not null default now(),
  actor  text not null,
  action text not null,
  note   text
);
create index if not exists cash_events_day_idx on public.cash_events(day_id, at);

create table if not exists public.cash_links (
  id           bigserial primary key,
  store        text not null references public.stores(name) on update cascade,
  token_hash   text unique,
  status       text not null default 'active' check (status in ('active','revoked')),
  created_by   text not null, created_at timestamptz not null default now(),
  revoked_by   text, revoked_at timestamptz, revoke_reason text,
  submissions  int not null default 0,
  last_used_at timestamptz
);
create unique index if not exists one_active_cash_link on public.cash_links(store) where status = 'active';

do $$ declare t text; begin
  foreach t in array array['cash_expense_categories','cash_files','cash_days','cash_shifts','cash_livepay','cash_expenses','cash_refunds',
                           'cash_adjustments','cash_deposits','cash_corrections','cash_events','cash_links'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
  foreach t in array array['cash_days','cash_shifts','cash_livepay','cash_expenses','cash_refunds','cash_adjustments','cash_deposits','cash_corrections','cash_expense_categories'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$I', t);
    execute format('create trigger audit_%1$s after insert or update or delete on public.%1$I for each row execute function public.audit_trigger()', t);
  end loop;
end $$;

-- ─────────────── Βοηθητικές (εσωτερικές, χωρίς πρόσβαση από την οθόνη) ───────────────
create or replace function public.cash_amount(p jsonb, p_label text, p_required boolean default true, p_signed boolean default false)
returns numeric language plpgsql immutable as $$
declare s text; v numeric;
begin
  if p is null or p = 'null'::jsonb or (jsonb_typeof(p) = 'string' and trim(p #>> '{}') = '') then
    if p_required then raise exception 'Συμπληρώστε: %.', p_label; end if;
    return null;
  end if;
  s := replace(replace(trim(p #>> '{}'), '€', ''), ' ', '');
  if s ~ '^-?\d{1,3}(\.\d{3})+(,\d{1,2})?$' then s := replace(replace(s, '.', ''), ',', '.');
  elsif s ~ '^-?\d+,\d{1,2}$' then s := replace(s, ',', '.'); end if;
  if s !~ '^-?\d+(\.\d{1,2})?$' then raise exception 'Μη έγκυρο ποσό: %.', p_label; end if;
  v := s::numeric;
  if (v < 0 and not p_signed) or abs(v) >= 1000000 then raise exception 'Μη έγκυρο ποσό: %.', p_label; end if;
  return v;
end $$;

create or replace function public.cash_text(p text, p_label text, p_min int default 2, p_max int default 300) returns text
language plpgsql immutable as $$
declare v text := nullif(trim(coalesce(p, '')), '');
begin
  if v is null or length(v) < p_min then raise exception 'Συμπληρώστε: %.', p_label; end if;
  return left(v, p_max);
end $$;

create or replace function public.cash_file_add(p jsonb, p_by text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_size int; v_data text := p->>'data';
begin
  if p is null or v_data is null then raise exception 'Επισυνάψτε φωτογραφία του παραστατικού.'; end if;
  v_data := regexp_replace(v_data, '^data:[^,]*,', '');
  if v_data !~ '^[A-Za-z0-9+/=]+$' then raise exception 'Μη έγκυρο αρχείο.'; end if;
  v_size := (length(v_data) * 3) / 4 - (length(v_data) - length(rtrim(v_data, '=')));
  if v_size > 4194304 then raise exception 'Το αρχείο ξεπερνά τα 4 MB.'; end if;
  insert into public.cash_files(filename, mime, size, data, uploaded_by)
  values (left(coalesce(nullif(trim(p->>'name'), ''), 'parastatiko.jpg'), 200), coalesce(p->>'mime', 'image/jpeg'), v_size, v_data, p_by) returning id into v_id;
  return v_id;
exception when check_violation then raise exception 'Επιτρέπονται εικόνες (JPG, PNG, WEBP, HEIC) ή PDF έως 4 MB.';
end $$;

create or replace function public.cash_event(p_day bigint, p_action text, p_note text default null, p_actor text default null) returns void
language sql security definer set search_path = public as $$
  insert into public.cash_events(day_id, actor, action, note) values (p_day, coalesce(p_actor, public.current_email(), 'system'), p_action, p_note)
$$;

create or replace function public.cash_ensure_day(p_store text, p_day date) returns public.cash_days
language plpgsql security definer set search_path = public as $$
declare d public.cash_days;
begin
  if not exists (select 1 from public.stores where name = p_store) then raise exception 'Άγνωστο κατάστημα.'; end if;
  insert into public.cash_days(store, day) values (p_store, p_day) on conflict (store, day) do nothing;
  select * into d from public.cash_days where store = p_store and day = p_day for update;
  return d;
end $$;

-- Κλειδώνει τη γραμμή και ελέγχει πεδίο καταστημάτων + προβολή
create or replace function public.cash_day_row(p_day bigint) returns public.cash_days
language plpgsql security definer set search_path = public as $$
declare d public.cash_days;
begin
  perform public.require_perm('cash.view');
  select * into d from public.cash_days where id = p_day for update;
  if not found or not public.can_see_store(d.store) then raise exception 'Η ημέρα δεν βρέθηκε στο πεδίο σας.'; end if;
  return d;
end $$;

-- Ποιος επεξεργάζεται: ανοιχτή ημέρα → manager (cash.manage)· σε διόρθωση → λογιστήριο (cash.correct_apply)
create or replace function public.cash_require_edit(d public.cash_days) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if d.status = 'open' then perform public.require_perm('cash.manage');
  elsif d.status = 'correction' then perform public.require_perm('cash.correct_apply');
  elsif d.status = 'confirmed' then raise exception 'Η ημέρα έχει επιβεβαιωθεί από τον manager. Για αλλαγές πρώτα «Αναίρεση επιβεβαίωσης».';
  else raise exception 'Η ημέρα είναι κλειδωμένη. Οι διορθώσεις γίνονται από το λογιστήριο μετά από έγκριση της Γενικής Διευθύντριας.';
  end if;
end $$;

create or replace function public.cash_touch(p_day bigint) returns void
language sql security definer set search_path = public as $$
  update public.cash_days set version = version + 1 where id = p_day
$$;

-- Υπολογισμοί ημέρας
create or replace function public.cash_summary(p_day bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.cash_days; v_counted numeric; v_morning numeric; v_evening numeric; v_supp numeric; v_exp numeric; v_ref_cash numeric; v_ref_card numeric;
        v_ref_pending int; v_adj_cash numeric; v_adj_cards numeric; v_adj_iris numeric; v_lp numeric; v_lp_n int; v_lp_matched int; v_dep numeric;
        v_expected numeric; v_dcash numeric; v_dcards numeric; v_diris numeric;
begin
  select * into d from public.cash_days where id = p_day;
  select max(counted_cash) filter (where shift = 'morning'), max(counted_cash) filter (where shift = 'evening'), coalesce(sum(counted_cash) filter (where shift = 'supplement'), 0)
    into v_morning, v_evening, v_supp from public.cash_shifts where day_id = p_day and voided_at is null;
  -- Από κάθε καταμέτρηση πρωινής/βραδινής αφαιρείται το ταμείο έναρξης· το συμπληρωματικό είναι μόνο επιπλέον μετρητά
  v_counted := greatest(coalesce(v_morning, 0) - case when v_morning is null then 0 else d.float_amount end, 0)
             + greatest(coalesce(v_evening, 0) - case when v_evening is null then 0 else d.float_amount end, 0) + v_supp;
  select coalesce(sum(amount), 0) into v_exp from public.cash_expenses where day_id = p_day and voided_at is null;
  select coalesce(sum(amount) filter (where method = 'cash' and status <> 'rejected'), 0), coalesce(sum(amount) filter (where method = 'card' and status <> 'rejected'), 0),
         count(*) filter (where status = 'pending')
    into v_ref_cash, v_ref_card, v_ref_pending from public.cash_refunds where day_id = p_day and voided_at is null;
  select coalesce(sum(amount) filter (where kind = 'cash'), 0), coalesce(sum(amount) filter (where kind = 'cards'), 0), coalesce(sum(amount) filter (where kind = 'iris'), 0)
    into v_adj_cash, v_adj_cards, v_adj_iris from public.cash_adjustments where day_id = p_day and voided_at is null;
  select coalesce(sum(amount), 0), count(*), count(*) filter (where matched_at is not null) into v_lp, v_lp_n, v_lp_matched
    from public.cash_livepay where day_id = p_day and voided_at is null;
  select coalesce(sum(amount), 0) into v_dep from public.cash_deposits where day_id = p_day and voided_at is null;
  v_expected := case when d.softone_cash is null then null else d.softone_cash - v_exp - v_ref_cash end;
  v_dcash  := case when v_expected is null then null else v_counted - v_expected end;
  v_dcards := case when d.softone_cards is null or d.pos_cards is null then null else d.pos_cards - d.softone_cards end;
  v_diris  := case when d.softone_iris is null or d.iris_total is null then null else d.iris_total - d.softone_iris end;
  return jsonb_build_object(
    'float', d.float_amount, 'morning_count', v_morning, 'evening_count', v_evening, 'supplement_cash', v_supp,
    'cash_to_deposit', v_counted, 'expenses', v_exp, 'refunds_cash', v_ref_cash, 'refunds_card', v_ref_card, 'refunds_pending', v_ref_pending,
    'expected_cash', v_expected,
    'diff_cash', v_dcash, 'adj_cash', v_adj_cash, 'unexplained_cash', v_dcash - v_adj_cash,
    'diff_cards', v_dcards, 'adj_cards', v_adj_cards, 'unexplained_cards', v_dcards - v_adj_cards,
    'diff_iris', v_diris, 'adj_iris', v_adj_iris, 'unexplained_iris', v_diris - v_adj_iris,
    'livepay_total', v_lp, 'livepay_count', v_lp_n, 'livepay_matched', v_lp_matched,
    'deposited', v_dep, 'deposit_left', v_counted - v_dep);
end $$;

-- ═══════════════ Σύνδεσμος ταμείου ρεσεψιόν (όπως ο σύνδεσμος στατιστικών s.html) ═══════════════
create or replace function public.cashlink_create(p_store text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_token text := public.fill_new_token(); v_id bigint;
begin
  perform public.require_perm('cash.links');
  if not exists (select 1 from public.stores where name = p_store) or not public.can_see_store(p_store) then raise exception 'Το κατάστημα δεν βρέθηκε στο πεδίο σας.'; end if;
  update public.cash_links set status = 'revoked', token_hash = null, revoked_by = public.current_email(), revoked_at = now(), revoke_reason = 'Αντικατάσταση'
   where store = p_store and status = 'active';
  insert into public.cash_links(store, token_hash, created_by) values (p_store, public.fill_hash(v_token), public.current_email()) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'token', v_token);
end $$;

create or replace function public.cashlink_revoke(p_store text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('cash.links');
  if not public.can_see_store(p_store) then raise exception 'Το κατάστημα δεν βρέθηκε στο πεδίο σας.'; end if;
  update public.cash_links set status = 'revoked', token_hash = null, revoked_by = public.current_email(), revoked_at = now(), revoke_reason = nullif(trim(coalesce(p_reason, '')), '')
   where store = p_store and status = 'active';
  if not found then raise exception 'Δεν υπάρχει ενεργός σύνδεσμος.'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cashlink_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('cash.links');
  return coalesce((select jsonb_agg(jsonb_build_object('store', l.store, 'status', l.status, 'created_by', l.created_by, 'created_at', l.created_at,
            'revoked_by', l.revoked_by, 'revoked_at', l.revoked_at, 'submissions', l.submissions, 'last_used_at', l.last_used_at) order by l.store, l.created_at desc)
     from public.cash_links l where public.can_see_store(l.store)), '[]');
end $$;

create or replace function public.cashlink_lookup(p_token text) returns public.cash_links
language plpgsql security definer set search_path = public as $$
declare l public.cash_links;
begin
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{32,200}$' then raise exception 'Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί.'; end if;
  select * into l from public.cash_links where token_hash = public.fill_hash(p_token) and status = 'active';
  if not found then raise exception 'Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί.'; end if;
  return l;
end $$;

-- Εγκρίνοντες επιστροφών: ενεργοί χρήστες με το δικαίωμα (όνομα + αδιαφανής κωδικός, όχι email)
create or replace function public.cash_approvers() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', left(public.fill_hash(u.email), 16), 'name', u.name) order by u.name), '[]')
    from public.app_users u where u.active and public.role_has_perm(u.role, 'cash.refund_approve')
$$;

create or replace function public.cashlink_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.cash_links := public.cashlink_lookup(p_token); v_today date := public.athens_today();
begin
  -- Μόνο ό,τι χρειάζεται η φόρμα. Καμία ποσότητα ή προηγούμενη εγγραφή — μόνο ποια κλεισίματα έχουν ήδη υποβληθεί.
  return jsonb_build_object('store', l.store, 'today', v_today, 'yesterday', v_today - 1, 'float', 100,
    'employees', (select coalesce(jsonb_agg(jsonb_build_object('code', e.code, 'name', e.last || ' ' || e.first) order by e.last, e.first), '[]')
                    from public.employees e join public.specialties sp on sp.name = e.specialty
                   where e.store = l.store and e.status = 'Ενεργός' and sp.stat_kind = 'reception'),
    'categories', (select coalesce(jsonb_agg(name order by sort, name), '[]') from public.cash_expense_categories where active),
    'approvers', public.cash_approvers(),
    'done', (select coalesce(jsonb_object_agg(d.day::text, jsonb_build_object('status', d.status,
                'shifts', (select coalesce(jsonb_agg(distinct s.shift), '[]') from public.cash_shifts s where s.day_id = d.id and s.voided_at is null and s.shift <> 'supplement'))), '{}')
               from public.cash_days d where d.store = l.store and d.day between v_today - 1 and v_today));
end $$;

-- Εσωτερική: προσθήκη στοιχείων (Live Pay, έξοδα, επιστροφές) σε ημέρα
create or replace function public.cash_add_items(d public.cash_days, p_shift text, p jsonb, p_by text) returns int
language plpgsql security definer set search_path = public as $$
declare x jsonb; n int := 0; v_appr public.app_users; v_cat text;
begin
  for x in select * from jsonb_array_elements(coalesce(p->'livepay', '[]')) loop
    insert into public.cash_livepay(day_id, shift, customer, amount, created_by)
    values (d.id, p_shift, public.cash_text(x->>'customer', 'πελάτης Live Pay', 2, 120), public.cash_amount(x->'amount', 'ποσό Live Pay'), p_by);
    n := n + 1;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p->'expenses', '[]')) loop
    select name into v_cat from public.cash_expense_categories where name = x->>'category' and active;
    if v_cat is null then raise exception 'Επιλέξτε κατηγορία εξόδου.'; end if;
    insert into public.cash_expenses(day_id, shift, expense_date, amount, category, description, file_id, created_by)
    values (d.id, p_shift, coalesce(nullif(x->>'date', '')::date, d.day), public.cash_amount(x->'amount', 'ποσό εξόδου'), v_cat,
            public.cash_text(x->>'description', 'περιγραφή εξόδου'), public.cash_file_add(x->'file', p_by), p_by);
    n := n + 1;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p->'refunds', '[]')) loop
    select * into v_appr from public.app_users u
     where u.active and public.role_has_perm(u.role, 'cash.refund_approve') and (left(public.fill_hash(u.email), 16) = x->>'approver' or u.email = lower(x->>'approver'));
    if not found then raise exception 'Επιλέξτε ποιος ενέκρινε την επιστροφή (μόνο όσοι έχουν το δικαίωμα έγκρισης).'; end if;
    if coalesce(x->>'method', '') not in ('cash','card') then raise exception 'Επιλέξτε τρόπο επιστροφής (μετρητά ή κάρτα).'; end if;
    insert into public.cash_refunds(day_id, shift, amount, method, customer, reason, approver_email, approver_name, created_by)
    values (d.id, p_shift, public.cash_amount(x->'amount', 'ποσό επιστροφής'), x->>'method', public.cash_text(x->>'customer', 'πελάτης επιστροφής', 2, 120),
            public.cash_text(x->>'reason', 'αιτία επιστροφής'), v_appr.email, v_appr.name, p_by);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Υποβολή ενός κλεισίματος από τη ρεσεψιόν (ατομικά: όλα ή τίποτα)
-- p: { date, shift: morning|evening|supplement, employee_code, counted_cash, pos_cards?, iris_total?, note?, livepay[], expenses[], refunds[] }
create or replace function public.cashlink_submit(p_token text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.cash_links := public.cashlink_lookup(p_token); d public.cash_days; e public.employees; v_date date; v_shift text := p->>'shift';
        v_by text; v_pos numeric; v_iris numeric;
begin
  begin v_date := (p->>'date')::date; exception when others then raise exception 'Μη έγκυρη ημερομηνία.'; end;
  if v_date is null or v_date > public.athens_today() or v_date < public.athens_today() - 1 then
    raise exception 'Το κλείσιμο αφορά σήμερα ή χθες. Για άλλες ημέρες απευθυνθείτε στον manager του καταστήματος.';
  end if;
  if v_shift is null or v_shift not in ('morning','evening','supplement') then raise exception 'Επιλέξτε κλείσιμο (πρωινό, βραδινό ή συμπληρωματικό).'; end if;
  select x.* into e from public.employees x join public.specialties sp on sp.name = x.specialty
   where x.code = p->>'employee_code' and x.store = l.store and x.status = 'Ενεργός' and sp.stat_kind = 'reception';
  if not found then raise exception 'Επιλέξτε εργαζόμενο Ρεσεψιόν του καταστήματος.'; end if;
  d := public.cash_ensure_day(l.store, v_date);
  if d.status <> 'open' then raise exception 'Η ημέρα έχει ήδη ελεγχθεί. Για αλλαγές επικοινωνήστε με τον manager του καταστήματος.'; end if;
  if v_shift = 'supplement' and not exists (select 1 from public.cash_shifts where day_id = d.id and shift = 'evening' and voided_at is null) then
    raise exception 'Το συμπληρωματικό καταχωρίζεται μετά το βραδινό κλείσιμο της ίδιας ημέρας.';
  end if;
  v_by := 'σύνδεσμος:' || l.store || ' · ' || e.last || ' ' || e.first;
  insert into public.cash_shifts(day_id, shift, counted_cash, employee_code, employee_name, note, source, created_by)
  values (d.id, v_shift, public.cash_amount(p->'counted_cash', case when v_shift = 'supplement' then 'επιπλέον μετρητά' else 'καταμέτρηση μετρητών' end),
          e.code, e.last || ' ' || e.first, nullif(left(trim(coalesce(p->>'note', '')), 500), ''), 'link', v_by);
  if v_shift in ('evening','supplement') then
    v_pos := public.cash_amount(p->'pos_cards', 'πακέτο POS (κάρτες)', v_shift = 'evening');
    v_iris := public.cash_amount(p->'iris_total', 'IRIS ημέρας', v_shift = 'evening');
    update public.cash_days set pos_cards = coalesce(v_pos, pos_cards), iris_total = coalesce(v_iris, iris_total) where id = d.id;
  end if;
  perform public.cash_add_items(d, v_shift, p, v_by);
  perform public.cash_touch(d.id);
  perform public.cash_event(d.id, 'submit_' || v_shift, null, v_by);
  update public.cash_links set submissions = submissions + 1, last_used_at = now() where id = l.id;
  return jsonb_build_object('ok', true);
exception when unique_violation then
  raise exception 'Αυτό το κλείσιμο έχει ήδη υποβληθεί για την ημέρα. Για διόρθωση επικοινωνήστε με τον manager του καταστήματος.';
end $$;

-- ═══════════════ Εφαρμογή Ταμεία (συνδεδεμένοι χρήστες) ═══════════════
create or replace function public.cash_lists() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('cash.view');
  return jsonb_build_object(
    'stores', (select coalesce(jsonb_agg(name order by sort, name), '[]') from public.stores where active and public.can_see_store(name)),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'sort', sort, 'active', active) order by sort, name), '[]') from public.cash_expense_categories),
    'approvers', public.cash_approvers(),
    'today', public.athens_today());
end $$;

-- Επισκόπηση: ημέρες στο διάστημα, ανά κατάστημα του πεδίου
create or replace function public.cash_overview(p_from date, p_to date, p_store text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('cash.view');
  if p_to < p_from or p_to - p_from > 92 then raise exception 'Επιλέξτε διάστημα έως 3 μηνών.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'store', d.store, 'day', d.day, 'status', d.status, 'version', d.version,
            'confirmed_by', d.confirmed_by, 'audited_name', d.audited_name, 'audited_at', d.audited_at,
            'shifts', (select coalesce(jsonb_agg(s.shift order by s.created_at), '[]') from public.cash_shifts s where s.day_id = d.id and s.voided_at is null),
            'correction', (select c.status from public.cash_corrections c where c.day_id = d.id and c.status in ('pending','approved') limit 1),
            'sum', public.cash_summary(d.id)) order by d.day desc, d.store)
     from public.cash_days d
    where d.day between p_from and p_to and public.can_see_store(d.store) and (p_store is null or d.store = p_store)), '[]');
end $$;

create or replace function public.cash_day_get(p_day bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.cash_days;
begin
  perform public.require_perm('cash.view');
  select * into d from public.cash_days where id = p_day;
  if not found or not public.can_see_store(d.store) then raise exception 'Η ημέρα δεν βρέθηκε στο πεδίο σας.'; end if;
  return to_jsonb(d) || jsonb_build_object(
    'sum', public.cash_summary(d.id),
    'shifts',   (select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at), '[]') from public.cash_shifts s where s.day_id = d.id),
    'livepay',  (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]') from public.cash_livepay x where x.day_id = d.id),
    'expenses', (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('filename', f.filename) order by x.created_at), '[]')
                   from public.cash_expenses x join public.cash_files f on f.id = x.file_id where x.day_id = d.id),
    'refunds',  (select coalesce(jsonb_agg(to_jsonb(x) - 'approver_email' order by x.created_at), '[]') from public.cash_refunds x where x.day_id = d.id),
    'adjustments', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]') from public.cash_adjustments x where x.day_id = d.id),
    'deposits', (select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('filename', f.filename) order by x.created_at), '[]')
                   from public.cash_deposits x join public.cash_files f on f.id = x.file_id where x.day_id = d.id),
    'corrections', (select coalesce(jsonb_agg(to_jsonb(x) order by x.requested_at), '[]') from public.cash_corrections x where x.day_id = d.id),
    'events',   (select coalesce(jsonb_agg(to_jsonb(x) order by x.at), '[]') from public.cash_events x where x.day_id = d.id),
    'can', jsonb_build_object(
      'edit', (d.status = 'open' and public.has_perm('cash.manage')) or (d.status = 'correction' and public.has_perm('cash.correct_apply')),
      'confirm', d.status = 'open' and public.has_perm('cash.manage'),
      'unconfirm', d.status = 'confirmed' and (public.has_perm('cash.manage') or public.has_perm('cash.audit')),
      'audit', d.status in ('confirmed','correction') and public.has_perm('cash.audit') and (d.status = 'confirmed' or public.has_perm('cash.correct_apply')),
      'match', public.has_perm('cash.audit'),
      'request_correction', d.status = 'locked' and public.has_perm('cash.correct_apply'),
      'approve_correction', public.has_perm('cash.correct_approve'),
      'approve_refund', public.has_perm('cash.refund_approve')));
end $$;

-- Άνοιγμα ημέρας από τον manager (π.χ. καταχώριση από χαρτί)
create or replace function public.cash_day_open(p_store text, p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days;
begin
  perform public.require_perm('cash.manage');
  if not public.can_see_store(p_store) then raise exception 'Το κατάστημα δεν βρέθηκε στο πεδίο σας.'; end if;
  if p_day > public.athens_today() then raise exception 'Η ημερομηνία δεν μπορεί να είναι μελλοντική.'; end if;
  d := public.cash_ensure_day(p_store, p_day);
  return jsonb_build_object('id', d.id);
end $$;

-- Στοιχεία ημέρας από τον manager: πακέτο POS, IRIS, SoftOne, σημείωση (με έλεγχο ταυτόχρονης αλλαγής)
create or replace function public.cash_day_save(p_day bigint, p_version int, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day);
begin
  perform public.cash_require_edit(d);
  if d.version <> p_version then raise exception 'Τα στοιχεία άλλαξαν στο μεταξύ από άλλον χρήστη. Ανανεώστε τη σελίδα.'; end if;
  update public.cash_days set
    pos_cards     = case when p ? 'pos_cards'     then public.cash_amount(p->'pos_cards', 'πακέτο POS', false) else pos_cards end,
    iris_total    = case when p ? 'iris_total'    then public.cash_amount(p->'iris_total', 'IRIS ημέρας', false) else iris_total end,
    softone_cash  = case when p ? 'softone_cash'  then public.cash_amount(p->'softone_cash', 'SoftOne μετρητά', false) else softone_cash end,
    softone_cards = case when p ? 'softone_cards' then public.cash_amount(p->'softone_cards', 'SoftOne κάρτες', false) else softone_cards end,
    softone_iris  = case when p ? 'softone_iris'  then public.cash_amount(p->'softone_iris', 'SoftOne IRIS', false) else softone_iris end,
    manager_note  = case when p ? 'manager_note'  then nullif(left(trim(coalesce(p->>'manager_note', '')), 1000), '') else manager_note end,
    version = version + 1
  where id = d.id;
  return jsonb_build_object('ok', true);
end $$;

-- Κλείσιμο βάρδιας από την εφαρμογή (manager): νέο ή αντικατάσταση (το παλιό ακυρώνεται με αιτιολογία)
create or replace function public.cash_shift_save(p_day bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day); v_shift text := p->>'shift'; v_old bigint;
begin
  perform public.cash_require_edit(d);
  if v_shift is null or v_shift not in ('morning','evening','supplement') then raise exception 'Επιλέξτε κλείσιμο.'; end if;
  if p ? 'replace_id' then
    update public.cash_shifts set voided_by = public.current_email(), voided_at = now(), void_reason = public.cash_text(p->>'reason', 'αιτιολογία διόρθωσης', 3)
     where id = (p->>'replace_id')::bigint and day_id = d.id and voided_at is null returning id into v_old;
    if v_old is null then raise exception 'Η εγγραφή δεν βρέθηκε.'; end if;
  end if;
  insert into public.cash_shifts(day_id, shift, counted_cash, employee_code, employee_name, note, source, created_by)
  values (d.id, v_shift, public.cash_amount(p->'counted_cash', 'καταμέτρηση μετρητών'), null, nullif(left(trim(coalesce(p->>'employee_name', '')), 120), ''),
          nullif(left(trim(coalesce(p->>'note', '')), 500), ''), 'app', public.current_email());
  perform public.cash_touch(d.id);
  perform public.cash_event(d.id, case when v_old is null then 'shift_add' else 'shift_replace' end, v_shift);
  return jsonb_build_object('ok', true);
exception when unique_violation then raise exception 'Υπάρχει ήδη αυτό το κλείσιμο. Χρησιμοποιήστε «Διόρθωση».';
end $$;

-- Προσθήκη Live Pay / εξόδων / επιστροφών / προσαρμογών από την εφαρμογή
create or replace function public.cash_item_add(p_day bigint, p_kind text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day); v_kind text;
begin
  perform public.cash_require_edit(d);
  if p_kind = 'adjustment' then
    v_kind := p->>'kind';
    if v_kind is null or v_kind not in ('cash','cards','iris') then raise exception 'Επιλέξτε τι αφορά η προσαρμογή.'; end if;
    insert into public.cash_adjustments(day_id, kind, amount, reason, created_by)
    values (d.id, v_kind, public.cash_amount(p->'amount', 'ποσό προσαρμογής', true, true), public.cash_text(p->>'reason', 'αιτιολογία προσαρμογής', 3), public.current_email());
  elsif p_kind in ('livepay','expense','refund') then
    perform public.cash_add_items(d, nullif(p->>'shift', ''), jsonb_build_object(case p_kind when 'livepay' then 'livepay' when 'expense' then 'expenses' else 'refunds' end, jsonb_build_array(p)), public.current_email());
  else raise exception 'Άγνωστο είδος.';
  end if;
  perform public.cash_touch(d.id);
  return jsonb_build_object('ok', true);
end $$;

-- Ακύρωση εγγραφής με αιτιολογία (τίποτα δεν διαγράφεται)
create or replace function public.cash_item_void(p_kind text, p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_day bigint; d public.cash_days; v_reason text; v_tbl text;
begin
  v_tbl := case p_kind when 'shift' then 'cash_shifts' when 'livepay' then 'cash_livepay' when 'expense' then 'cash_expenses' when 'refund' then 'cash_refunds'
                       when 'adjustment' then 'cash_adjustments' when 'deposit' then 'cash_deposits' end;
  if v_tbl is null then raise exception 'Άγνωστο είδος.'; end if;
  v_reason := public.cash_text(p_reason, 'αιτιολογία ακύρωσης', 3);
  execute format('select day_id from public.%I where id = $1 and voided_at is null', v_tbl) into v_day using p_id;
  if v_day is null then raise exception 'Η εγγραφή δεν βρέθηκε ή έχει ήδη ακυρωθεί.'; end if;
  d := public.cash_day_row(v_day);
  -- Οι καταθέσεις γίνονται συνήθως μετά το κλείδωμα: τις διορθώνει ο manager ή το λογιστήριο σε κάθε κατάσταση
  if p_kind = 'deposit' then perform public.require_perm('cash.manage', 'cash.correct_apply');
  else perform public.cash_require_edit(d); end if;
  execute format('update public.%I set voided_by = $1, voided_at = now(), void_reason = $2 where id = $3', v_tbl) using public.current_email(), v_reason, p_id;
  perform public.cash_touch(d.id);
  perform public.cash_event(d.id, 'void_' || p_kind, v_reason);
  return jsonb_build_object('ok', true);
end $$;

-- Κατάθεση στην τράπεζα: ημερομηνία, ποσό, απόδειξη (και σε κλειδωμένη ημέρα: η κατάθεση γίνεται συνήθως αργότερα)
create or replace function public.cash_deposit_add(p_day bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day); v_date date;
begin
  perform public.require_perm('cash.manage', 'cash.correct_apply');
  begin v_date := (p->>'date')::date; exception when others then raise exception 'Μη έγκυρη ημερομηνία κατάθεσης.'; end;
  if v_date is null or v_date < d.day or v_date > public.athens_today() then raise exception 'Η ημερομηνία κατάθεσης είναι από την ημέρα του ταμείου έως σήμερα.'; end if;
  insert into public.cash_deposits(day_id, deposit_date, amount, file_id, created_by)
  values (d.id, v_date, public.cash_amount(p->'amount', 'ποσό κατάθεσης'), public.cash_file_add(p->'file', public.current_email()), public.current_email());
  perform public.cash_event(d.id, 'deposit', to_char(public.cash_amount(p->'amount', 'ποσό'), 'FM999990.00') || ' €');
  return jsonb_build_object('ok', true);
end $$;

-- Έγκριση / απόρριψη επιστροφής (δικαίωμα cash.refund_approve)
create or replace function public.cash_refund_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.cash_refunds; d public.cash_days; v_name text;
begin
  perform public.require_perm('cash.refund_approve');
  select * into r from public.cash_refunds where id = p_id and voided_at is null for update;
  if not found then raise exception 'Η επιστροφή δεν βρέθηκε.'; end if;
  select * into d from public.cash_days where id = r.day_id;
  if not public.can_see_store(d.store) then raise exception 'Η επιστροφή δεν βρέθηκε στο πεδίο σας.'; end if;
  if r.status <> 'pending' then raise exception 'Η επιστροφή έχει ήδη κριθεί.'; end if;
  if d.status = 'locked' then raise exception 'Η ημέρα είναι κλειδωμένη.'; end if;
  if not p_approve and length(trim(coalesce(p_note, ''))) < 3 then raise exception 'Γράψτε αιτιολογία απόρριψης.'; end if;
  select name into v_name from public.app_users where email = public.current_email();
  update public.cash_refunds set status = case when p_approve then 'approved' else 'rejected' end, decided_by = public.current_email(), decided_name = v_name,
         decided_at = now(), decision_note = nullif(trim(coalesce(p_note, '')), '') where id = r.id;
  perform public.cash_touch(d.id);
  perform public.cash_event(d.id, case when p_approve then 'refund_approved' else 'refund_rejected' end, r.customer || ' · ' || replace(to_char(r.amount, 'FM999990.00'), '.', ',') || ' €');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cash_refunds_pending() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('cash.refund_approve');
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'day_id', d.id, 'store', d.store, 'day', d.day, 'amount', r.amount, 'method', r.method,
            'customer', r.customer, 'reason', r.reason, 'approver_name', r.approver_name, 'mine', r.approver_email = public.current_email(),
            'created_by', r.created_by, 'created_at', r.created_at) order by r.created_at)
     from public.cash_refunds r join public.cash_days d on d.id = r.day_id
    where r.status = 'pending' and r.voided_at is null and public.can_see_store(d.store)), '[]');
end $$;

-- Ροή ημέρας
create or replace function public.cash_confirm(p_day bigint, p_version int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day); s jsonb;
begin
  perform public.require_perm('cash.manage');
  if d.status <> 'open' then raise exception 'Η ημέρα δεν είναι ανοιχτή.'; end if;
  if d.version <> p_version then raise exception 'Τα στοιχεία άλλαξαν στο μεταξύ. Ανανεώστε τη σελίδα και ελέγξτε ξανά.'; end if;
  if not exists (select 1 from public.cash_shifts where day_id = d.id and shift = 'evening' and voided_at is null) then raise exception 'Λείπει το βραδινό κλείσιμο.'; end if;
  if d.pos_cards is null or d.iris_total is null then raise exception 'Συμπληρώστε πακέτο POS και IRIS ημέρας.'; end if;
  if d.softone_cash is null or d.softone_cards is null or d.softone_iris is null then raise exception 'Καταχωρίστε τα ποσά του SoftOne (μετρητά, κάρτες, IRIS).'; end if;
  s := public.cash_summary(d.id);
  if (s->>'refunds_pending')::int > 0 then raise exception 'Υπάρχουν επιστροφές που περιμένουν έγκριση.'; end if;
  update public.cash_days set status = 'confirmed', confirmed_by = public.current_email(), confirmed_at = now(), version = version + 1 where id = d.id;
  perform public.cash_event(d.id, 'confirm',
    case when (s->>'unexplained_cash')::numeric <> 0 or (s->>'unexplained_cards')::numeric <> 0 or (s->>'unexplained_iris')::numeric <> 0
         then 'Με ανεξήγητη διαφορά' end);
  return jsonb_build_object('ok', true);
end $$;

-- Επιστροφή σε «ανοιχτή»: αναίρεση από τον manager ή επιστροφή από το λογιστήριο με σημείωση
create or replace function public.cash_unconfirm(p_day bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day); v_role_audit boolean := public.has_perm('cash.audit') and not public.has_perm('cash.manage');
begin
  perform public.require_perm('cash.manage', 'cash.audit');
  if d.status <> 'confirmed' then raise exception 'Η ημέρα δεν είναι σε κατάσταση «Επιβεβαιωμένη».'; end if;
  if v_role_audit and length(trim(coalesce(p_note, ''))) < 3 then raise exception 'Γράψτε τι πρέπει να διορθώσει ο manager.'; end if;
  update public.cash_days set status = 'open', confirmed_by = null, confirmed_at = null, version = version + 1 where id = d.id;
  perform public.cash_event(d.id, case when v_role_audit then 'returned' else 'unconfirm' end, nullif(trim(coalesce(p_note, '')), ''));
  return jsonb_build_object('ok', true);
end $$;

-- Έλεγχος λογιστηρίου & κλείδωμα (και μετά από διόρθωση)
create or replace function public.cash_lock(p_day bigint, p_version int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day); v_name text; c public.cash_corrections;
begin
  perform public.require_perm('cash.audit');
  if d.status not in ('confirmed','correction') then raise exception 'Το κλείδωμα γίνεται μετά την επιβεβαίωση του manager.'; end if;
  if d.status = 'correction' then perform public.require_perm('cash.correct_apply'); end if;
  if d.version <> p_version then raise exception 'Τα στοιχεία άλλαξαν στο μεταξύ. Ανανεώστε τη σελίδα και ελέγξτε ξανά.'; end if;
  if exists (select 1 from public.cash_refunds where day_id = d.id and status = 'pending' and voided_at is null) then raise exception 'Υπάρχουν επιστροφές που περιμένουν έγκριση.'; end if;
  select name into v_name from public.app_users where email = public.current_email();
  update public.cash_days set status = 'locked', audited_by = public.current_email(), audited_name = v_name, audited_at = now(), version = version + 1 where id = d.id;
  if d.status = 'correction' then
    update public.cash_corrections set status = 'applied', applied_by = public.current_email(), applied_at = now() where day_id = d.id and status = 'approved' returning * into c;
    perform public.cash_event(d.id, 'correction_applied', c.reason);
  else
    perform public.cash_event(d.id, 'lock', v_name);
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Αντιστοίχιση Live Pay με την τράπεζα (λογιστήριο· και σε κλειδωμένη ημέρα)
create or replace function public.cash_livepay_match(p_id bigint, p_matched boolean, p_bank_ref text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x public.cash_livepay; d public.cash_days;
begin
  perform public.require_perm('cash.audit');
  select * into x from public.cash_livepay where id = p_id and voided_at is null for update;
  if not found then raise exception 'Η εγγραφή δεν βρέθηκε.'; end if;
  select * into d from public.cash_days where id = x.day_id;
  if not public.can_see_store(d.store) then raise exception 'Η εγγραφή δεν βρέθηκε στο πεδίο σας.'; end if;
  update public.cash_livepay set matched_by = case when p_matched then public.current_email() end, matched_at = case when p_matched then now() end,
         bank_ref = case when p_matched then nullif(left(trim(coalesce(p_bank_ref, '')), 120), '') end where id = x.id;
  perform public.cash_event(d.id, case when p_matched then 'livepay_matched' else 'livepay_unmatched' end, x.customer || ' · ' || replace(to_char(x.amount, 'FM999990.00'), '.', ',') || ' €');
  return jsonb_build_object('ok', true);
end $$;

-- Διορθώσεις κλειδωμένης ημέρας: αίτημα (λογιστήριο) → έγκριση ΓΔ → ξεκλείδωμα για διόρθωση → νέο κλείδωμα
create or replace function public.cash_correction_request(p_day bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.cash_days := public.cash_day_row(p_day);
begin
  perform public.require_perm('cash.correct_apply');
  if d.status <> 'locked' then raise exception 'Αίτημα διόρθωσης γίνεται μόνο σε κλειδωμένη ημέρα.'; end if;
  insert into public.cash_corrections(day_id, reason, requested_by) values (d.id, public.cash_text(p_reason, 'αιτιολογία διόρθωσης', 5, 500), public.current_email());
  perform public.cash_event(d.id, 'correction_requested', trim(p_reason));
  return jsonb_build_object('ok', true);
exception when unique_violation then raise exception 'Υπάρχει ήδη ανοιχτό αίτημα διόρθωσης για αυτή την ημέρα.';
end $$;

create or replace function public.cash_correction_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.cash_corrections; d public.cash_days;
begin
  perform public.require_perm('cash.correct_approve');
  select * into c from public.cash_corrections where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'Το αίτημα δεν βρέθηκε ή έχει ήδη κριθεί.'; end if;
  d := public.cash_day_row(c.day_id);
  if not p_approve and length(trim(coalesce(p_note, ''))) < 3 then raise exception 'Γράψτε αιτιολογία απόρριψης.'; end if;
  update public.cash_corrections set status = case when p_approve then 'approved' else 'rejected' end, decided_by = public.current_email(), decided_at = now(),
         decision_note = nullif(trim(coalesce(p_note, '')), '') where id = c.id;
  if p_approve then update public.cash_days set status = 'correction', version = version + 1 where id = d.id; end if;
  perform public.cash_event(d.id, case when p_approve then 'correction_approved' else 'correction_rejected' end, nullif(trim(coalesce(p_note, '')), ''));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cash_corrections_pending() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('cash.correct_approve', 'cash.correct_apply');
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'day_id', d.id, 'store', d.store, 'day', d.day, 'reason', c.reason, 'status', c.status,
            'requested_by', c.requested_by, 'requested_at', c.requested_at) order by c.requested_at)
     from public.cash_corrections c join public.cash_days d on d.id = c.day_id
    where c.status in ('pending','approved') and public.can_see_store(d.store)), '[]');
end $$;

-- Παραστατικό / απόδειξη (μόνο για όσους βλέπουν την ημέρα)
create or replace function public.cash_file_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f public.cash_files; v_store text;
begin
  perform public.require_perm('cash.view');
  select * into f from public.cash_files where id = p_id;
  if not found then raise exception 'Το αρχείο δεν βρέθηκε.'; end if;
  select d.store into v_store from public.cash_days d
   where d.id = coalesce((select day_id from public.cash_expenses where file_id = p_id limit 1), (select day_id from public.cash_deposits where file_id = p_id limit 1));
  if v_store is null or not public.can_see_store(v_store) then raise exception 'Το αρχείο δεν βρέθηκε.'; end if;
  return jsonb_build_object('filename', f.filename, 'mime', f.mime, 'data', f.data);
end $$;

-- Κατηγορίες εξόδων
create or replace function public.cash_category_save(p_name text, p_new_name text default null, p_active boolean default true, p_sort int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_new text := public.cash_text(coalesce(p_new_name, p_name), 'όνομα κατηγορίας', 2, 60);
begin
  perform public.require_perm('cash.settings');
  if p_name is null or not exists (select 1 from public.cash_expense_categories where name = p_name) then
    insert into public.cash_expense_categories(name, sort, active) values (v_new, coalesce(p_sort, (select coalesce(max(sort), 0) + 1 from public.cash_expense_categories)), coalesce(p_active, true));
  else
    update public.cash_expense_categories set name = v_new, active = coalesce(p_active, active), sort = coalesce(p_sort, sort) where name = p_name;
  end if;
  return jsonb_build_object('ok', true);
exception when unique_violation then raise exception 'Υπάρχει ήδη κατηγορία με αυτό το όνομα.';
end $$;

-- ─────────────── Πρόσβαση: μόνο οι λειτουργίες της οθόνης· οι εσωτερικές κλειστές ───────────────
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'cash\_%' or p.proname like 'cashlink\_%') loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
grant execute on function
  public.cash_lists(), public.cash_overview(date, date, text), public.cash_day_get(bigint), public.cash_day_open(text, date),
  public.cash_day_save(bigint, int, jsonb), public.cash_shift_save(bigint, jsonb), public.cash_item_add(bigint, text, jsonb),
  public.cash_item_void(text, bigint, text), public.cash_deposit_add(bigint, jsonb), public.cash_refund_decide(bigint, boolean, text),
  public.cash_refunds_pending(), public.cash_confirm(bigint, int), public.cash_unconfirm(bigint, text), public.cash_lock(bigint, int),
  public.cash_livepay_match(bigint, boolean, text), public.cash_correction_request(bigint, text), public.cash_correction_decide(bigint, boolean, text),
  public.cash_corrections_pending(), public.cash_file_get(uuid), public.cash_category_save(text, text, boolean, int),
  public.cashlink_create(text), public.cashlink_revoke(text, text), public.cashlink_list()
  to authenticated;
grant execute on function public.cashlink_info(text), public.cashlink_submit(text, jsonb) to anon;
