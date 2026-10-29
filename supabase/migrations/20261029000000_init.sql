-- MEGA GYM · Δηλώσεις μισθοδοσίας · αρχική δομή βάσης
-- Όλοι οι έλεγχοι δικαιωμάτων γίνονται εδώ (Row Level Security + συναρτήσεις),
-- ώστε να ισχύουν ακόμη κι αν κάποιος παρακάμψει την οθόνη της εφαρμογής.

-- ─────────────────────────── Πίνακες αναφοράς ───────────────────────────
create table public.stores (
  name   text primary key check (length(trim(name)) between 2 and 80),
  sort   int  not null default 0,
  active boolean not null default true
);

create table public.companies (
  name   text primary key check (length(trim(name)) between 2 and 120),
  sort   int  not null default 0,
  active boolean not null default true
);

insert into public.stores(name, sort) values
  ('Αγία Παρασκευή',1),('Βριλήσσια - Μελίσσια',2),('Γλυφάδα',3),('Κηφισιά',4),
  ('Μεταμόρφωση',5),('Άλιμος',6),('Γέρακας',7),('Νέα Ιωνία',8);

insert into public.companies(name, sort) values
  ('ΥΠΟΣΤΗΡΙΞΗ ΓΥΜΝΑΣΤΗΡΙΩΝ ΑΕ',1),('ARG BEST GREEK GYMS IKE',2),
  ('BEST GREEK GYMS IKE',3),('IONIA BEST GREEK GYMS IKE',4);

-- ─────────────────────────── Χρήστες εφαρμογής ───────────────────────────
create table public.app_users (
  email      text primary key check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  name       text not null check (length(trim(name)) between 2 and 150),
  role       text not null check (role in ('owner','hr','manager')),
  store      text references public.stores(name) on update cascade,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  constraint manager_needs_store check (role <> 'manager' or store is not null)
);

-- ─────────────────────────── Εργαζόμενοι ───────────────────────────
create table public.employees (
  code       text primary key check (length(trim(code)) between 1 and 80),
  first      text not null check (length(trim(first)) between 1 and 150),
  last       text not null check (length(trim(last)) between 1 and 150),
  store      text not null references public.stores(name) on update cascade,
  company    text not null references public.companies(name) on update cascade,
  status     text not null default 'Ενεργός' check (status in ('Ενεργός','Ανενεργός')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index employees_store_idx on public.employees(store);

-- ─────────────────────────── Δηλώσεις ───────────────────────────
-- pending = προετοιμασμένη, περιμένει υπογραφή · signed = υπογεγραμμένη · voided = ακυρωμένη
create table public.declarations (
  id            uuid primary key default gen_random_uuid(),
  employee_code text not null references public.employees(code) on update cascade,
  employee_name text not null,
  store         text not null,
  company       text not null,
  month         text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  end_date      date not null,
  period        text not null check (length(trim(period)) between 3 and 120),
  amount        numeric(12,2) not null check (amount >= 0 and amount < 1000000),
  status        text not null default 'pending' check (status in ('pending','signed','voided')),
  statement     text,
  signer        text,
  signature     text,
  signed_at     timestamptz,
  signed_by     text,
  device        text,
  prepared_by   text,
  prepared_at   timestamptz not null default now(),
  voided_by     text,
  voided_at     timestamptz,
  void_reason   text
);
-- Μία ενεργή δήλωση ανά εργαζόμενο και μήνα (οι ακυρωμένες δεν μετράνε)
create unique index one_declaration_per_employee_month
  on public.declarations(employee_code, month) where status <> 'voided';
create index declarations_month_idx on public.declarations(month, store);

-- ─────────────────────────── Ιστορικό ενεργειών ───────────────────────────
create table public.audit_log (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  actor     text not null default 'system',
  action    text not null,
  entity    text not null,
  entity_id text,
  details   jsonb
);
create index audit_log_at_idx on public.audit_log(at desc);

-- ─────────────────────────── Βοηθητικές συναρτήσεις ───────────────────────────
create or replace function public.current_email() returns text
language sql stable as $$
  select nullif(lower(coalesce(auth.jwt() ->> 'email', '')), '')
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.app_users where email = public.current_email() and active
$$;

create or replace function public.my_store() returns text
language sql stable security definer set search_path = public as $$
  select store from public.app_users where email = public.current_email() and active
$$;

-- Μπορεί ο τρέχων χρήστης να δει/χειριστεί αυτό το κατάστημα;
create or replace function public.can_see_store(p_store text) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.my_role()
    when 'owner' then true
    when 'hr' then true
    when 'manager' then p_store = public.my_store()
    else false end
$$;

-- ─────────────────────────── Row Level Security ───────────────────────────
alter table public.stores       enable row level security;
alter table public.companies    enable row level security;
alter table public.app_users    enable row level security;
alter table public.employees    enable row level security;
alter table public.declarations enable row level security;
alter table public.audit_log    enable row level security;

create policy stores_read  on public.stores    for select to authenticated using (public.my_role() is not null);
create policy stores_write on public.stores    for all    to authenticated using (public.my_role() = 'owner') with check (public.my_role() = 'owner');
create policy comp_read    on public.companies for select to authenticated using (public.my_role() is not null);
create policy comp_write   on public.companies for all    to authenticated using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

create policy users_read  on public.app_users for select to authenticated
  using (public.my_role() = 'owner' or email = public.current_email());
create policy users_write on public.app_users for all to authenticated
  using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

create policy emp_read   on public.employees for select to authenticated using (public.can_see_store(store));
create policy emp_insert on public.employees for insert to authenticated with check (public.my_role() in ('owner','hr'));
create policy emp_update on public.employees for update to authenticated
  using (public.my_role() in ('owner','hr')) with check (public.my_role() in ('owner','hr'));
create policy emp_delete on public.employees for delete to authenticated using (public.my_role() = 'owner');

-- Δηλώσεις: μόνο ανάγνωση απευθείας. Δημιουργία/υπογραφή/ακύρωση ΜΟΝΟ μέσω των συναρτήσεων πιο κάτω.
create policy decl_read on public.declarations for select to authenticated using (public.can_see_store(store));

create policy audit_read on public.audit_log for select to authenticated using (public.my_role() in ('owner','hr'));

revoke all on all tables in schema public from anon;
revoke insert, update, delete on public.declarations from authenticated;
revoke insert, update, delete on public.audit_log from authenticated;

-- ─────────────────────────── Προστασία ───────────────────────────
-- Υπογεγραμμένη δήλωση δεν αλλάζει ποτέ· επιτρέπεται μόνο ακύρωση (με αιτιολογία).
create or replace function public.protect_declarations() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Οι δηλώσεις δεν διαγράφονται· χρησιμοποιήστε ακύρωση.';
  end if;
  if old.status = 'voided' then
    raise exception 'Η δήλωση είναι ακυρωμένη και δεν αλλάζει.';
  end if;
  if old.status = 'signed' then
    if new.status <> 'voided'
       or new.amount is distinct from old.amount or new.statement is distinct from old.statement
       or new.signature is distinct from old.signature or new.signer is distinct from old.signer
       or new.month is distinct from old.month or new.employee_code is distinct from old.employee_code
       or new.signed_at is distinct from old.signed_at then
      raise exception 'Η υπογεγραμμένη δήλωση δεν μπορεί να τροποποιηθεί.';
    end if;
  end if;
  return new;
end $$;
create trigger declarations_protect before update or delete on public.declarations
  for each row execute function public.protect_declarations();

-- Να υπάρχει πάντα τουλάχιστον μία ενεργή ιδιοκτήτρια
create or replace function public.keep_one_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'DELETE' and old.role = 'owner')
     or (tg_op = 'UPDATE' and old.role = 'owner' and (new.role <> 'owner' or not new.active)) then
    if not exists (select 1 from public.app_users where role = 'owner' and active and email <> old.email) then
      raise exception 'Πρέπει να υπάρχει τουλάχιστον μία ενεργή ιδιοκτήτρια.';
    end if;
  end if;
  return coalesce(new, old);
end $$;
create trigger app_users_keep_owner before update or delete on public.app_users
  for each row execute function public.keep_one_owner();

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger employees_touch before update on public.employees
  for each row execute function public.touch_updated_at();

-- ─────────────────────────── Καταγραφή ενεργειών ───────────────────────────
create or replace function public.audit_trigger() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) - 'signature' - 'statement' end;
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) - 'signature' - 'statement' end;
  v_row jsonb := coalesce(v_new, v_old);
  v_action text := lower(tg_op);
  v_changes jsonb;
begin
  if tg_table_name = 'declarations' and tg_op = 'UPDATE' then
    v_action := case
      when new.status = 'signed' and old.status = 'pending' then 'sign'
      when new.status = 'voided' then 'void'
      else 'update' end;
  end if;
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(key, jsonb_build_object('from', v_old -> key, 'to', value))
      into v_changes
      from jsonb_each(v_new)
     where v_old -> key is distinct from value and key not in ('updated_at');
    if v_changes is null then return new; end if;
  end if;
  insert into public.audit_log(actor, action, entity, entity_id, details)
  values (
    coalesce(public.current_email(), 'system'),
    v_action,
    tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'code', v_row ->> 'email', v_row ->> 'name'),
    case when tg_op = 'UPDATE' then jsonb_build_object('changes', v_changes,
            'label', coalesce(v_row ->> 'employee_name', (v_row ->> 'first') || ' ' || (v_row ->> 'last'), v_row ->> 'name'),
            'month', v_row ->> 'month', 'store', v_row ->> 'store')
         else v_row end
  );
  return coalesce(new, old);
end $$;

create trigger audit_employees    after insert or update or delete on public.employees    for each row execute function public.audit_trigger();
create trigger audit_app_users    after insert or update or delete on public.app_users    for each row execute function public.audit_trigger();
create trigger audit_declarations after insert or update or delete on public.declarations for each row execute function public.audit_trigger();
create trigger audit_stores       after insert or update or delete on public.stores       for each row execute function public.audit_trigger();
create trigger audit_companies    after insert or update or delete on public.companies    for each row execute function public.audit_trigger();

-- ─────────────────────────── Λειτουργίες δηλώσεων ───────────────────────────
create or replace function public.fmt_amount(p numeric) returns text language sql immutable as $$
  select replace(replace(replace(to_char(p, 'FM999,999,990.00'), ',', '#'), '.', ','), '#', '.')
$$;

create or replace function public.statement_text(p_company text, p_end date, p_period text, p_amount numeric)
returns text language sql immutable as $$
  select format(
'Δηλώνω υπεύθυνα ότι από την ημερομηνία έναρξης της απασχόλησής μου στην εταιρεία %s και έως την %s, έχω λάβει όλες τις δεδουλευμένες αποδοχές μου, καθώς και οποιαδήποτε επιπρόσθετη οικονομική απαίτηση που ενδεχομένως υπήρχε (όπως αναρρωτική άδεια, υπερωριακή απασχόληση, νόμιμη άδεια κ.λπ.), πλήρως και χωρίς καμία εκκρεμότητα.

Πραγματοποιήθηκε ανάλυση των ποσών που αντιστοιχούν στο χρονικό διάστημα %s, ποσό: %s€, από το Τμήμα Ανθρώπινου Δυναμικού της επιχείρησης, έγινε αποδεκτή από εμένα, έχουν ήδη κατατεθεί στον τραπεζικό μου λογαριασμό και ουδεμία άλλη απαίτηση έχω.

Επιπλέον του μισθού μου, δηλώνω ότι έχω λάβει όλες τις πρόσθετες παροχές που δικαιούμαι σε μορφή διατακτικών, δωροκάρτας ή και των δύο.',
    p_company, to_char(p_end, 'DD/MM/YYYY'), p_period, public.fmt_amount(p_amount))
$$;

-- Προετοιμασία (μία ή πολλές) δηλώσεων για έναν μήνα.
-- p_rows: [{ "code": "...", "amount": "1000,50", "period": "...", "end_date": "YYYY-MM-DD" }]
-- owner/hr: όλα τα καταστήματα · manager: μόνο το δικό του.
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
  if v_role is null then raise exception 'Δεν επιτρέπεται η πρόσβαση.'; end if;
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
    if v_role = 'manager' and e.store <> v_store then
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

-- Υπογραφή από τον εργαζόμενο στη συσκευή του καταστήματος (owner ή manager του καταστήματος).
create or replace function public.sign_declaration(p_id uuid, p_signer text, p_signature text, p_device text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.my_role();
  d record;
begin
  if v_role not in ('owner','manager') then raise exception 'Δεν επιτρέπεται η υπογραφή από αυτόν τον λογαριασμό.'; end if;
  select * into d from public.declarations where id = p_id for update;
  if not found then raise exception 'Η δήλωση δεν βρέθηκε.'; end if;
  if v_role = 'manager' and d.store <> public.my_store() then raise exception 'Η δήλωση ανήκει σε άλλο κατάστημα.'; end if;
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

-- Ακύρωση (μόνο ιδιοκτήτρια, με αιτιολογία). Μετά μπορεί να γίνει νέα δήλωση για τον ίδιο μήνα.
create or replace function public.void_declaration(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() <> 'owner' then raise exception 'Μόνο η ιδιοκτήτρια μπορεί να ακυρώσει δήλωση.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Γράψτε αιτιολογία ακύρωσης.'; end if;
  update public.declarations set status = 'voided', voided_by = public.current_email(), voided_at = now(), void_reason = trim(p_reason)
   where id = p_id and status <> 'voided';
  if not found then raise exception 'Η δήλωση δεν βρέθηκε.'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Διαγραφή προετοιμασμένης (όχι υπογεγραμμένης) δήλωσης: owner/hr, ή manager για το κατάστημά του.
create or replace function public.discard_pending(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.declarations where id = p_id;
  if not found or d.status <> 'pending' then raise exception 'Μόνο δηλώσεις προς υπογραφή μπορούν να αφαιρεθούν.'; end if;
  if not (public.my_role() in ('owner','hr') or (public.my_role() = 'manager' and d.store = public.my_store())) then
    raise exception 'Δεν επιτρέπεται.';
  end if;
  update public.declarations set status = 'voided', voided_by = public.current_email(), voided_at = now(),
         void_reason = 'Αφαίρεση προετοιμασμένης δήλωσης' where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Κατάσταση μήνα: κάθε ενεργός εργαζόμενος που βλέπει ο χρήστης + η δήλωσή του (αν υπάρχει).
-- security invoker ⇒ ισχύουν τα δικαιώματα του χρήστη.
create or replace function public.month_status(p_month text)
returns table (
  code text, first text, last text, store text, company text, emp_status text,
  declaration_id uuid, status text, amount numeric, period text, end_date date,
  signed_at timestamptz, signer text, prepared_at timestamptz
) language sql stable security invoker set search_path = public as $$
  select e.code, e.first, e.last, e.store, e.company, e.status,
         d.id, coalesce(d.status, 'missing'), d.amount, d.period, d.end_date, d.signed_at, d.signer, d.prepared_at
    from public.employees e
    left join public.declarations d on d.employee_code = e.code and d.month = p_month and d.status <> 'voided'
   where e.status = 'Ενεργός' or d.id is not null
   order by e.store, e.last, e.first
$$;

-- Ποιος είμαι
create or replace function public.whoami()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object('email', email, 'name', name, 'role', role, 'store', store)
       from public.app_users where email = public.current_email() and active),
    jsonb_build_object('email', public.current_email(), 'role', null))
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.current_email(), public.my_role(), public.my_store(), public.can_see_store(text),
  public.prepare_declarations(text, jsonb), public.sign_declaration(uuid, text, text, text),
  public.void_declaration(uuid, text), public.discard_pending(uuid), public.month_status(text),
  public.whoami(), public.fmt_amount(numeric), public.statement_text(text, date, text, numeric)
  to authenticated;
