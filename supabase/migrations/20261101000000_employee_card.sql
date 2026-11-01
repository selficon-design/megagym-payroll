-- MEGA GYM · Επέκταση: Ενιαία καρτέλα εργαζομένου
--   Αιτήματα & Αναφορές Προσωπικού · Πρότυπα κειμένων · Ημερήσια στατιστικά · Αξιολογήσεις · Ρόλος εκπαιδευτή
--
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο νέοι πίνακες/συναρτήσεις, νέες προαιρετικές στήλες στους εργαζομένους
-- και διεύρυνση του ελέγχου ρόλων ώστε να δέχεται και τον «εκπαιδευτή».
-- Δεν διαγράφεται ούτε αλλάζει καμία υπάρχουσα εγγραφή (δηλώσεις, υπογραφές, χρήστες, εργαζόμενοι).
-- Όλοι οι έλεγχοι δικαιωμάτων γίνονται στη βάση (RLS + συναρτήσεις).

-- ═══════════════════════════ 1. Ρόλοι & ειδικότητες ═══════════════════════════
alter table public.app_users drop constraint if exists app_users_role_check;
alter table public.app_users add constraint app_users_role_check check (role in ('owner','hr','manager','trainer'));

create table public.specialties (
  name      text primary key check (length(trim(name)) between 2 and 80),
  stat_kind text check (stat_kind in ('reception','supervision','exclusive')),
  sort      int not null default 0,
  active    boolean not null default true
);
insert into public.specialties(name, stat_kind, sort) values
  ('Ρεσεψιόν','reception',1), ('Επίβλεψη','supervision',2), ('Exclusive','exclusive',3);

-- Πεδίο ευθύνης εκπαιδευτή: κενό κατάστημα = όλα, κενή ειδικότητα = όλες
create table public.trainer_scopes (
  id        bigserial primary key,
  email     text not null references public.app_users(email) on update cascade on delete cascade,
  store     text references public.stores(name) on update cascade,
  specialty text references public.specialties(name) on update cascade,
  unique nulls not distinct (email, store, specialty)
);

-- Νέα προαιρετικά στοιχεία εργαζομένου (οι υπάρχουσες εγγραφές μένουν ως έχουν)
alter table public.employees add column if not exists specialty text references public.specialties(name) on update cascade;
alter table public.employees add column if not exists hire_date date;

-- Ιστορικό καταστήματος / εταιρείας / ειδικότητας: ο κωδικός μένει ίδιος, το ιστορικό διατηρείται
create table public.employee_assignments (
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade on delete cascade,
  store         text not null,
  company       text not null,
  specialty     text,
  valid_from    timestamptz not null default now(),
  valid_to      timestamptz,
  changed_by    text
);
create unique index one_open_assignment on public.employee_assignments(employee_code) where valid_to is null;
insert into public.employee_assignments(employee_code, store, company, specialty, valid_from, changed_by)
  select code, store, company, specialty, created_at, 'system' from public.employees;

create or replace function public.track_assignment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.store is not distinct from old.store and new.company is not distinct from old.company
     and new.specialty is not distinct from old.specialty then
    return new;
  end if;
  update public.employee_assignments set valid_to = now() where employee_code = new.code and valid_to is null;
  insert into public.employee_assignments(employee_code, store, company, specialty, changed_by)
  values (new.code, new.store, new.company, new.specialty, coalesce(public.current_email(), 'system'));
  return new;
end $$;
create trigger employees_track_assignment after insert or update on public.employees
  for each row execute function public.track_assignment();

-- Ο νέος ρόλος «εκπαιδευτής» ΔΕΝ έχει πρόσβαση στη μισθοδοσία. Η υπάρχουσα συνάρτηση έλεγχε μόνο
-- «χωρίς ρόλο»· εδώ ορίζεται ρητά ποιοι ρόλοι προετοιμάζουν δηλώσεις (η λογική κατά τα άλλα μένει ίδια).
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
  if v_role is null or v_role not in ('owner','hr','manager') then raise exception 'Δεν επιτρέπεται η πρόσβαση.'; end if;
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

-- ═══════════════════════════ 2. Βοηθητικές συναρτήσεις ═══════════════════════════
create or replace function public.athens_today() returns date
language sql stable as $$ select (now() at time zone 'Europe/Athens')::date $$;

-- 'YYYY-MM-DD HH:MM' ώρας Ελλάδας → timestamptz (σωστά με θερινή/χειμερινή ώρα)
create or replace function public.athens_ts(p text) returns timestamptz
language plpgsql stable as $$
declare v_local timestamp; v_ts timestamptz;
begin
  if p is null or trim(p) = '' then return null; end if;
  v_local := replace(trim(p), 'T', ' ')::timestamp;
  v_ts := v_local at time zone 'Europe/Athens';
  if (v_ts at time zone 'Europe/Athens') <> v_local then
    raise exception 'Η ώρα % δεν υπάρχει στην Ελλάδα λόγω αλλαγής ώρας. Επιλέξτε άλλη ώρα.', to_char(v_local, 'DD/MM/YYYY HH24:MI');
  end if;
  return v_ts;
end $$;

create or replace function public.in_trainer_scope(p_store text, p_specialty text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() = 'trainer' and exists (
    select 1 from public.trainer_scopes t
     where t.email = public.current_email()
       and (t.store is null or t.store = p_store)
       and (t.specialty is null or t.specialty = p_specialty))
$$;

-- Εργαζόμενος στο πεδίο του χρήστη (με βάση το τρέχον κατάστημα/ειδικότητα)
create or replace function public.employee_in_scope(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case public.my_role()
      when 'owner' then true
      when 'hr' then true
      when 'manager' then e.store = public.my_store()
      when 'trainer' then public.in_trainer_scope(e.store, e.specialty)
      else false end
    from public.employees e where e.code = p_code), false)
$$;

create or replace function public.require_role(p_roles text[]) returns text
language plpgsql stable security definer set search_path = public as $$
declare v text := public.my_role();
begin
  if v is null or not (v = any(p_roles)) then raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.'; end if;
  return v;
end $$;

-- Εκπαιδευτής: βλέπει μόνο τα βασικά στοιχεία των εργαζομένων του πεδίου του (όχι μισθοδοσία κ.λπ.)
create or replace function public.trainer_employees()
returns table (code text, first text, last text, store text, company text, specialty text, status text)
language sql stable security definer set search_path = public as $$
  select e.code, e.first, e.last, e.store, e.company, e.specialty, e.status
    from public.employees e
   where public.in_trainer_scope(e.store, e.specialty)
   order by e.last, e.first
$$;

-- ═══════════════════════════ 3. Πρότυπα κειμένων (με εκδόσεις) ═══════════════════════════
create table public.text_templates (
  key         text primary key,
  label       text not null,
  description text,
  variables   text[] not null default '{}',
  sort        int not null default 0
);
create table public.text_template_versions (
  id         bigserial primary key,
  key        text not null references public.text_templates(key),
  version    int not null,
  body       text not null check (length(trim(body)) between 3 and 8000),
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  unique (key, version)
);

insert into public.text_templates(key, label, description, variables, sort) values
 ('leave_request_body','Αίτηση άδειας — κείμενο','Αρχικό κείμενο της αίτησης άδειας', '{ονοματεπώνυμο,είδος_άδειας,έναρξη,λήξη,ημέρες}', 1),
 ('leave_request_help','Αίτηση άδειας — βοηθητικό κείμενο','Εμφανίζεται στη φόρμα της αίτησης', '{}', 2),
 ('leave_approve','Άδεια — έγκριση','Κείμενο έγκρισης άδειας', '{ονοματεπώνυμο,είδος_άδειας,έναρξη,λήξη,ημέρες}', 3),
 ('leave_reject','Άδεια — απόρριψη','Κείμενο απόρριψης άδειας', '{ονοματεπώνυμο,είδος_άδειας,έναρξη,λήξη,αιτιολογία,εναλλακτικό_διάστημα}', 4),
 ('leave_reason_ops','Άδεια — αιτιολογία επιχειρησιακών αναγκών','Πρότυπο αιτιολογίας για κανονική άδεια', '{περίοδος}', 5),
 ('leave_needs_info','Άδεια — διευκρινίσεις','Κείμενο αιτήματος διευκρινίσεων / δικαιολογητικών', '{ονοματεπώνυμο,στοιχεία}', 6),
 ('generic_approve','Λοιπά αιτήματα — έγκριση','Κείμενο έγκρισης για αιτήματα εκτός αδειών', '{ονοματεπώνυμο,κατηγορία}', 7),
 ('generic_reject','Λοιπά αιτήματα — απόρριψη','Κείμενο απόρριψης για αιτήματα εκτός αδειών', '{ονοματεπώνυμο,κατηγορία,αιτιολογία}', 8),
 ('generic_needs_info','Λοιπά αιτήματα — διευκρινίσεις','Κείμενο διευκρινίσεων για αιτήματα εκτός αδειών', '{ονοματεπώνυμο,κατηγορία,στοιχεία}', 9),
 ('warning_draft','Έγγραφη προειδοποίηση — αρχικό προσχέδιο HR','Σκελετός· το κείμενο το συντάσσει το HR', '{ονοματεπώνυμο,κωδικός,κατάστημα,ημερομηνία_περιστατικού}', 10);

insert into public.text_template_versions(key, version, body) values
 ('leave_request_body', 1, 'Παρακαλώ να εγκρίνετε τη χορήγηση {είδος_άδειας} για το χρονικό διάστημα από {έναρξη} έως και {λήξη}, συνολικής διάρκειας {ημέρες} ημερών άδειας.'),
 ('leave_request_help', 1, 'Συμπληρώστε τις ημέρες άδειας που αιτείστε για το παραπάνω διάστημα, σύμφωνα με το πρόγραμμα εργασίας σας.

Η υποβολή της αίτησης δεν αποτελεί έγκριση. Η τελική απόφαση θα σας γνωστοποιηθεί μέσω του manager του καταστήματός σας.'),
 ('leave_approve', 1, 'Το αίτημά σας για {είδος_άδειας} εγκρίθηκε για το χρονικό διάστημα από {έναρξη} έως και {λήξη}, συνολικά {ημέρες} ημέρες άδειας. Παρακαλούμε να συνεννοηθείτε με τον manager του καταστήματός σας για την ενημέρωση του προγράμματος εργασίας.'),
 ('leave_reject', 1, 'Το αίτημά σας για {είδος_άδειας}, από {έναρξη} έως και {λήξη}, δεν εγκρίθηκε για το συγκεκριμένο διάστημα.
Αιτιολογία: {αιτιολογία}.
Προτεινόμενο εναλλακτικό διάστημα: {εναλλακτικό_διάστημα}.
Για διευκρινίσεις ή υποβολή νέου αιτήματος, παρακαλούμε να επικοινωνήσετε με τον manager του καταστήματός σας.'),
 ('leave_reason_ops', 1, 'Κατά την περίοδο {περίοδος}, απαιτείται η πλήρης στελέχωση του καταστήματος για την εξυπηρέτηση των μελών και την κάλυψη του προγράμματος λειτουργίας.'),
 ('leave_needs_info', 1, 'Για να ολοκληρωθεί η εξέταση του αιτήματός σας, απαιτούνται τα παρακάτω στοιχεία: {στοιχεία}. Το αίτημά σας παραμένει σε εκκρεμότητα μέχρι να συμπληρωθούν τα απαραίτητα στοιχεία.'),
 ('generic_approve', 1, 'Το αίτημά σας ({κατηγορία}) εγκρίθηκε. Για τα επόμενα βήματα παρακαλούμε να συνεννοηθείτε με τον manager του καταστήματός σας.'),
 ('generic_reject', 1, 'Το αίτημά σας ({κατηγορία}) δεν εγκρίθηκε.
Αιτιολογία: {αιτιολογία}.
Για διευκρινίσεις, παρακαλούμε να επικοινωνήσετε με τον manager του καταστήματός σας.'),
 ('generic_needs_info', 1, 'Για να ολοκληρωθεί η εξέταση του αιτήματός σας ({κατηγορία}), απαιτούνται τα παρακάτω στοιχεία: {στοιχεία}. Το αίτημά σας παραμένει σε εκκρεμότητα μέχρι να συμπληρωθούν τα απαραίτητα στοιχεία.'),
 ('warning_draft', 1, 'Προς: {ονοματεπώνυμο} (κωδ. {κωδικός}), κατάστημα {κατάστημα}
Θέμα: Έγγραφη προειδοποίηση

[Το κείμενο συντάσσεται από το HR με βάση την αναφορά της {ημερομηνία_περιστατικού}.]');

-- Αποθήκευση νέας έκδοσης (μόνο Γενική Διευθύντρια). Οι παλιές εκδόσεις μένουν.
create or replace function public.template_save(p_key text, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_next int; v_id bigint;
begin
  perform public.require_role(array['owner']);
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

-- ═══════════════════════════ 4. Είδη άδειας & λόγοι απόρριψης ═══════════════════════════
create table public.leave_types (
  code   text primary key check (code ~ '^[a-z_]{2,30}$'),
  label  text not null check (length(trim(label)) between 2 and 80),
  sort   int not null default 0,
  active boolean not null default true
);
insert into public.leave_types(code, label, sort) values
 ('annual','κανονική (ετήσια) άδεια',1), ('sick','άδεια ασθενείας',2), ('unpaid','άδεια άνευ αποδοχών',3),
 ('maternity','άδεια μητρότητας',4), ('paternity','άδεια πατρότητας / γέννησης τέκνου',5), ('marriage','άδεια γάμου',6),
 ('bereavement','άδεια πένθους',7), ('study','εκπαιδευτική / εξεταστική άδεια',8), ('blood','άδεια αιμοδοσίας',9),
 ('other','άλλη άδεια',10);

-- leave_types: σε ποια είδη άδειας επιτρέπεται ο λόγος (κενό = σε όλα)
create table public.reject_reasons (
  code            text primary key check (code ~ '^[a-z_]{2,30}$'),
  label           text not null check (length(trim(label)) between 3 and 200),
  leave_types     text[],
  for_other       boolean not null default false,
  template_key    text references public.text_templates(key),
  sort            int not null default 0,
  active          boolean not null default true
);
insert into public.reject_reasons(code, label, leave_types, for_other, template_key, sort) values
 ('ops_needs','Αυξημένες επιχειρησιακές ανάγκες της περιόδου','{annual,unpaid}', true, 'leave_reason_ops', 1),
 ('coverage','Αδυναμία κάλυψης προγράμματος','{annual,unpaid}', true, null, 2),
 ('overlap','Σύμπτωση με ήδη εγκεκριμένες άδειες','{annual,unpaid}', false, null, 3),
 ('balance','Ανεπαρκές υπόλοιπο άδειας','{annual}', false, null, 4),
 ('conditions','Μη πλήρωση προϋποθέσεων, μετά από έλεγχο HR', null, true, null, 5),
 ('other','Άλλος λόγος (με υποχρεωτική εξήγηση)', null, true, null, 6);

-- ═══════════════════════════ 5. Αιτήματα & Αναφορές ═══════════════════════════
create sequence public.hr_request_no;

create table public.hr_requests (
  id             uuid primary key default gen_random_uuid(),
  ref            text not null unique,
  process        text not null check (process in ('employee','manager')),
  category       text not null check (category in (
                   'leave','shift_change','raise','contract_change','advance','documents','transfer','other_hr',
                   'negative_review','incident','warning_request')),
  employee_code  text not null references public.employees(code) on update cascade,
  employee_name  text not null,
  store          text not null,
  company        text not null,
  specialty      text,
  status         text not null default 'draft' check (status in
                   ('draft','submitted','under_review','needs_info','awaiting_gm','approved','rejected','completed')),
  entry_mode     text check (entry_mode in ('manager_record','employee_fill')),
  stated_by      text not null,      -- ποιος διατύπωσε το αίτημα  ('employee:<κωδικός>' ή email manager)
  written_by     text,               -- ποιος συμπλήρωσε το κείμενο ('employee:<κωδικός>' ή email)
  written_at     timestamptz,
  submitted_by   text,               -- ποιος το υπέβαλε
  submitted_at   timestamptz,
  created_by     text not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  assignee       text,               -- υπεύθυνος χειρισμού
  body           text,               -- τελικό κείμενο αιτήματος (αποθηκεύεται όπως υποβλήθηκε)
  template_version_id bigint references public.text_template_versions(id),
  leave_type     text references public.leave_types(code),
  leave_type_label text,
  start_date     date,
  end_date       date,
  days_requested numeric(5,1) check (days_requested is null or (days_requested > 0 and days_requested < 400)),
  incident_date  date,
  details        jsonb not null default '{}'::jsonb,
  manager_note   text,               -- χωριστή εισήγηση manager (π.χ. κάλυψη προγράμματος)
  notified_at    timestamptz,        -- πότε ο manager ενημέρωσε τον εργαζόμενο
  notified_by    text,
  notify_note    text,
  completed_at   timestamptz,
  completed_by   text,
  completion_note text,
  version        int not null default 1,
  constraint process_category check (
    (process = 'manager' and category in ('negative_review','incident','warning_request') and entry_mode is null) or
    (process = 'employee' and category not in ('negative_review','incident','warning_request') and entry_mode is not null)),
  constraint leave_dates check (end_date is null or start_date is null or end_date >= start_date)
);
create index hr_requests_store_idx on public.hr_requests(store, status);
create index hr_requests_emp_idx on public.hr_requests(employee_code);

-- Εσωτερικά στοιχεία HR (εισήγηση HR, προσχέδιο προειδοποίησης): μόνο ΓΔ και HR
create table public.hr_request_internal (
  request_id        uuid primary key references public.hr_requests(id) on delete cascade,
  hr_note           text,
  hr_note_by        text,
  hr_note_at        timestamptz,
  warning_draft     text,
  warning_draft_by  text,
  warning_draft_at  timestamptz
);

create table public.hr_decisions (
  id             bigserial primary key,
  request_id     uuid not null references public.hr_requests(id) on delete cascade,
  outcome        text not null check (outcome in ('approve','reject','needs_info')),
  decided_by     text not null,
  decided_role   text not null,
  decided_at     timestamptz not null default now(),
  reason_code    text,
  reason_label   text,
  reason_text    text,
  message        text not null,     -- τελικό κείμενο προς τον εργαζόμενο (όπως αποθηκεύτηκε)
  template_version_id bigint references public.text_template_versions(id),
  approved_start date,
  approved_end   date,
  approved_days  numeric(5,1),
  alternative    text,
  info_requested text,
  supersedes     bigint references public.hr_decisions(id),
  superseded_at  timestamptz,
  is_revision    boolean not null default false
);
-- Μία μόνο ισχύουσα απόφαση ανά αίτημα: αποκλείει ταυτόχρονες αντικρουόμενες αποφάσεις
create unique index one_current_decision on public.hr_decisions(request_id) where superseded_at is null;

create table public.hr_request_events (
  id          bigserial primary key,
  request_id  uuid not null references public.hr_requests(id) on delete cascade,
  at          timestamptz not null default now(),
  actor       text not null,
  actor_role  text,
  action      text not null,
  from_status text,
  to_status   text,
  note        text,
  internal    boolean not null default false,
  data        jsonb
);
create index hr_request_events_req_idx on public.hr_request_events(request_id, at);

create table public.hr_attachments (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.hr_requests(id) on delete cascade,
  filename    text not null check (length(filename) between 1 and 200),
  mime        text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','image/heic')),
  size        int not null check (size > 0 and size <= 4194304),
  data        text not null,       -- base64
  uploaded_by text not null,
  uploaded_at timestamptz not null default now()
);
create index hr_attachments_req_idx on public.hr_attachments(request_id);

create or replace function public.req_flow(p_category text) returns text
language sql immutable as $$
  select case
    when p_category = 'leave' then 'leave'
    when p_category in ('raise','contract_change') then 'gm'
    when p_category = 'warning_request' then 'warning'
    when p_category in ('negative_review','incident') then 'report'
    else 'generic' end
$$;

create or replace function public.req_category_label(p_category text) returns text
language sql immutable as $$
  select case p_category
    when 'leave' then 'Άδεια / απουσία' when 'shift_change' then 'Αλλαγή βάρδιας, ρεπό ή προγράμματος'
    when 'raise' then 'Αύξηση αποδοχών' when 'contract_change' then 'Αλλαγή ωρών ή σύμβασης'
    when 'advance' then 'Προκαταβολή' when 'documents' then 'Βεβαιώσεις και έγγραφα'
    when 'transfer' then 'Μετακίνηση καταστήματος ή αλλαγή θέσης' when 'other_hr' then 'Λοιπό αίτημα προς HR'
    when 'negative_review' then 'Αρνητική αξιολόγηση' when 'incident' then 'Περιστατικό'
    when 'warning_request' then 'Αίτημα έγγραφης προειδοποίησης' else p_category end
$$;

create or replace function public.req_event(p_id uuid, p_action text, p_from text, p_to text, p_note text,
                                            p_data jsonb default null, p_internal boolean default false, p_actor text default null)
returns void language sql security definer set search_path = public as $$
  insert into public.hr_request_events(request_id, actor, actor_role, action, from_status, to_status, note, data, internal)
  values (p_id, coalesce(p_actor, public.current_email(), 'system'), public.my_role(), p_action, p_from, p_to, nullif(trim(p_note), ''), p_data, p_internal)
$$;

-- Κλείδωμα αιτήματος με έλεγχο ορατότητας και έκδοσης (αποτρέπει ταυτόχρονες αλλαγές)
create or replace function public.req_lock(p_id uuid, p_version int) returns public.hr_requests
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  select * into r from public.hr_requests where id = p_id for update;
  if not found or not public.can_see_store(r.store) then raise exception 'Το αίτημα δεν βρέθηκε.'; end if;
  if p_version is not null and r.version <> p_version then
    raise exception 'Το αίτημα άλλαξε στο μεταξύ από άλλον χρήστη. Ανανεώστε τη σελίδα και δοκιμάστε ξανά.';
  end if;
  return r;
end $$;

-- Εφαρμογή πεδίων σε πρόχειρο. p_employee = true όταν γράφει ο ίδιος ο εργαζόμενος (απομονωμένη φόρμα).
create or replace function public.req_apply_fields(p_id uuid, p jsonb, p_employee boolean)
returns void language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_details jsonb; v_lt public.leave_types;
begin
  select * into r from public.hr_requests where id = p_id;
  if p ? 'leave_type' and nullif(p->>'leave_type','') is not null then
    select * into v_lt from public.leave_types where code = p->>'leave_type' and active;
    if not found then raise exception 'Άγνωστο είδος άδειας.'; end if;
  end if;
  v_details := r.details;
  if p ? 'details' and jsonb_typeof(p->'details') = 'object' then
    select v_details || coalesce(jsonb_object_agg(key, to_jsonb(left(value #>> '{}', 4000))), '{}'::jsonb) into v_details
      from jsonb_each(p->'details')
     where key in ('subject','description','examples','prior_discussion','proposed_action','notes','requested_change','period','amount_text');
  end if;
  begin
    update public.hr_requests set
      body           = case when p ? 'body' then left(nullif(trim(p->>'body'),''), 8000) else body end,
      template_version_id = case when p ? 'template_version_id' then nullif(p->>'template_version_id','')::bigint else template_version_id end,
      leave_type     = case when p ? 'leave_type' then nullif(p->>'leave_type','') else leave_type end,
      leave_type_label = case when p ? 'leave_type' then v_lt.label else leave_type_label end,
      start_date     = case when p ? 'start_date' then nullif(p->>'start_date','')::date else start_date end,
      end_date       = case when p ? 'end_date' then nullif(p->>'end_date','')::date else end_date end,
      days_requested = case when p ? 'days_requested' then nullif(replace(p->>'days_requested', ',', '.'),'')::numeric else days_requested end,
      incident_date  = case when p ? 'incident_date' then nullif(p->>'incident_date','')::date else incident_date end,
      details        = v_details,
      manager_note   = case when not p_employee and p ? 'manager_note' then left(nullif(trim(p->>'manager_note'),''), 4000) else manager_note end,
      updated_at     = now(),
      version        = version + 1
    where id = p_id;
  exception
    when invalid_datetime_format or datetime_field_overflow then raise exception 'Μη έγκυρη ημερομηνία.';
    when invalid_text_representation then raise exception 'Μη έγκυρος αριθμός ημερών.';
    when check_violation then raise exception 'Ελέγξτε τις ημερομηνίες και τον αριθμό ημερών (η λήξη δεν μπορεί να είναι πριν από την έναρξη).';
  end;
end $$;

-- Δημιουργία προχείρου
create or replace function public.req_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_role(array['owner','hr','manager']);
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
  perform public.require_role(array['owner','hr','manager']);
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
  perform public.require_role(array['owner','hr','manager']);
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

create or replace function public.req_delete_draft(p_id uuid, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_role(array['owner','hr','manager']);
  r := public.req_lock(p_id, p_version);
  if r.status <> 'draft' then raise exception 'Μόνο πρόχειρα διαγράφονται. Τα υποβληθέντα αιτήματα μένουν στο ιστορικό.'; end if;
  if public.my_role() = 'manager' and r.created_by <> public.current_email() then raise exception 'Διαγράφει μόνο όποιος δημιούργησε το πρόχειρο.'; end if;
  insert into public.audit_log(actor, action, entity, entity_id, details)
  values (public.current_email(), 'delete', 'hr_requests', r.ref, jsonb_build_object('label', r.employee_name, 'category', r.category, 'store', r.store));
  delete from public.fill_sessions where request_id = p_id;
  delete from public.hr_requests where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Ανάληψη / ανάθεση χειρισμού (HR, ΓΔ)
create or replace function public.req_assign(p_id uuid, p_email text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_to text := lower(trim(coalesce(p_email, public.current_email())));
begin
  perform public.require_role(array['owner','hr']);
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

-- Εισήγηση HR και προώθηση στη ΓΔ (αυξήσεις / αλλαγές σύμβασης)
create or replace function public.req_forward_gm(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_role(array['owner','hr']);
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

-- Προσχέδιο προειδοποίησης από HR (p_send = προώθηση στη ΓΔ για απόφαση)
create or replace function public.req_warning_draft(p_id uuid, p_text text, p_send boolean, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_to text;
begin
  perform public.require_role(array['owner','hr']);
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

-- Απόφαση / αναθεώρηση απόφασης
create or replace function public.req_decide(p_id uuid, p_outcome text, p jsonb, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_role(array['owner','hr']);
  r public.hr_requests; v_flow text; v_rev boolean; v_reason public.reject_reasons;
  v_prev bigint; v_new bigint; v_to text; v_msg text := trim(coalesce(p->>'message',''));
  v_start date; v_end date; v_days numeric; v_draft text;
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

  if p_outcome = 'approve' and r.category = 'leave' then
    begin
      v_start := coalesce(nullif(p->>'approved_start','')::date, r.start_date);
      v_end := coalesce(nullif(p->>'approved_end','')::date, r.end_date);
      v_days := coalesce(nullif(replace(p->>'approved_days', ',', '.'),'')::numeric, r.days_requested);
    exception when others then raise exception 'Μη έγκυρες εγκεκριμένες ημερομηνίες ή ημέρες.'; end;
    if v_end < v_start then raise exception 'Η λήξη δεν μπορεί να είναι πριν από την έναρξη.'; end if;
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
         template_version_id, approved_start, approved_end, approved_days, alternative, info_requested, supersedes, is_revision)
  values (p_id, p_outcome, public.current_email(), v_role,
          case when p_outcome = 'reject' then v_reason.code end, case when p_outcome = 'reject' then v_reason.label end,
          case when p_outcome = 'reject' then trim(p->>'reason_text') end, v_msg,
          nullif(p->>'template_version_id','')::bigint, v_start, v_end, v_days,
          case when p_outcome = 'reject' then coalesce(nullif(trim(p->>'alternative'),''), 'Προς συνεννόηση') end,
          case when p_outcome = 'needs_info' then trim(p->>'info') end, v_prev, v_rev)
  returning id into v_new;
  v_to := case p_outcome when 'approve' then 'approved' when 'reject' then 'rejected' else 'needs_info' end;
  update public.hr_requests set status = v_to, assignee = coalesce(assignee, public.current_email()),
         notified_at = case when v_rev then null else notified_at end,
         notified_by = case when v_rev then null else notified_by end,
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, case when v_rev then 'revise' else 'decide' end, r.status, v_to, p->>'reason_text',
    jsonb_build_object('decision_id', v_new, 'outcome', p_outcome, 'supersedes', v_prev));
  return jsonb_build_object('ok', true, 'status', v_to, 'decision_id', v_new, 'version', r.version + 1);
end $$;

-- Συμπλήρωση διευκρινίσεων (manager του καταστήματος, HR, ΓΔ)
create or replace function public.req_provide_info(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_to text;
begin
  perform public.require_role(array['owner','hr','manager']);
  r := public.req_lock(p_id, p_version);
  if r.status <> 'needs_info' then raise exception 'Το αίτημα δεν περιμένει διευκρινίσεις.'; end if;
  if length(trim(coalesce(p_note,''))) < 3 then raise exception 'Γράψτε τις διευκρινίσεις.'; end if;
  v_to := case when r.assignee is null then 'submitted' else 'under_review' end;
  update public.hr_requests set status = v_to, updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'info_provided', 'needs_info', v_to, p_note);
  return jsonb_build_object('ok', true, 'status', v_to, 'version', r.version + 1);
end $$;

-- Πότε ο manager ενημέρωσε τον εργαζόμενο για την απόφαση
create or replace function public.req_mark_notified(p_id uuid, p_at timestamptz, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_at timestamptz := coalesce(p_at, now()); v_dec timestamptz;
begin
  perform public.require_role(array['owner','hr','manager']);
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

-- Ολοκλήρωση: υλοποίηση εγκεκριμένου, αρχειοθέτηση αναφοράς, κοινοποίηση προειδοποίησης
create or replace function public.req_complete(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_flow text;
begin
  perform public.require_role(array['owner','hr']);
  r := public.req_lock(p_id, p_version);
  v_flow := public.req_flow(r.category);
  if length(trim(coalesce(p_note,''))) < 3 then raise exception 'Γράψτε σύντομη σημείωση ολοκλήρωσης.'; end if;
  if v_flow = 'report' then
    if r.status not in ('submitted','under_review') then raise exception 'Η αναφορά δεν είναι σε εξέταση.'; end if;
  elsif r.status <> 'approved' then
    raise exception 'Ολοκληρώνονται μόνο εγκεκριμένα αιτήματα (η έγκριση διαφέρει από την υλοποίηση).';
  end if;
  update public.hr_requests set status = 'completed', completed_at = now(), completed_by = public.current_email(),
         completion_note = trim(p_note),
         notified_at = case when v_flow = 'warning' then now() else notified_at end,
         notified_by = case when v_flow = 'warning' then public.current_email() else notified_by end,
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, case v_flow when 'warning' then 'warning_communicated' when 'report' then 'report_closed' else 'implemented' end,
    r.status, 'completed', p_note);
  return jsonb_build_object('ok', true, 'version', r.version + 1);
end $$;

create or replace function public.req_attach(p_id uuid, p_filename text, p_mime text, p_data text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_id uuid; v_size int;
begin
  perform public.require_role(array['owner','hr','manager']);
  r := public.req_lock(p_id, null);
  if r.status = 'completed' then raise exception 'Το αίτημα έχει ολοκληρωθεί.'; end if;
  if public.my_role() = 'manager' and r.status not in ('draft','needs_info') then
    raise exception 'Συνημμένα από manager προστίθενται στο πρόχειρο ή όταν ζητούνται διευκρινίσεις.';
  end if;
  return public.attach_file(p_id, p_filename, p_mime, p_data, public.current_email());
end $$;

create or replace function public.attach_file(p_id uuid, p_filename text, p_mime text, p_data text, p_by text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_size int;
begin
  if p_data !~ '^[A-Za-z0-9+/=]+$' then raise exception 'Μη έγκυρο αρχείο.'; end if;
  v_size := (length(p_data) * 3) / 4 - (length(p_data) - length(rtrim(p_data, '=')));
  if v_size > 4194304 then raise exception 'Το αρχείο ξεπερνά τα 4 MB.'; end if;
  if (select count(*) from public.hr_attachments where request_id = p_id) >= 10 then raise exception 'Έως 10 συνημμένα ανά αίτημα.'; end if;
  insert into public.hr_attachments(request_id, filename, mime, size, data, uploaded_by)
  values (p_id, left(trim(p_filename), 200), p_mime, v_size, p_data, p_by) returning id into v_id;
  perform public.req_event(p_id, 'attachment', null, null, left(trim(p_filename), 200), null, false, p_by);
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation then raise exception 'Επιτρέπονται PDF ή εικόνες (JPG, PNG, WEBP, HEIC) έως 4 MB.';
end $$;


-- Υπεύθυνοι χειρισμού (για ανάθεση αιτημάτων)
create or replace function public.hr_handlers()
returns table (email text, name text, role text)
language sql stable security definer set search_path = public as $$
  select email, name, role from public.app_users
   where active and role in ('owner','hr') and public.my_role() in ('owner','hr')
   order by role desc, name
$$;

-- ═══════════════════════════ 6. Ημερήσια στατιστικά ═══════════════════════════
create table public.daily_stats (
  id               bigserial primary key,
  employee_code    text not null references public.employees(code) on update cascade,
  stat_date        date not null,
  store            text not null,
  specialty        text not null,
  kind             text not null check (kind in ('reception','supervision','exclusive')),
  dr int, lost int, cb int,
  trials_sent int, trials_attended int, trials_enrolled int, trials_done int,
  enr_fitness int, enr_body int, enr_muscle int, enr_pilates int, enr_from_trials int,
  -- Ενημερώσεις = DR + LOST (υπολογίζεται, δεν πληκτρολογείται)
  informed int generated always as (case when kind in ('reception','supervision') then dr + lost end) stored,
  created_by text not null, created_at timestamptz not null default now(),
  updated_by text, updated_at timestamptz,
  version int not null default 1,
  unique (employee_code, stat_date, store, specialty),
  constraint stats_non_negative check (
    coalesce(dr,0) >= 0 and coalesce(lost,0) >= 0 and coalesce(cb,0) >= 0 and coalesce(trials_sent,0) >= 0 and
    coalesce(trials_attended,0) >= 0 and coalesce(trials_enrolled,0) >= 0 and coalesce(trials_done,0) >= 0 and
    coalesce(enr_fitness,0) >= 0 and coalesce(enr_body,0) >= 0 and coalesce(enr_muscle,0) >= 0 and
    coalesce(enr_pilates,0) >= 0 and coalesce(enr_from_trials,0) >= 0),
  constraint stats_fields_by_kind check (case kind
    when 'reception' then num_nulls(dr,lost,cb,trials_sent,enr_fitness,enr_body,enr_muscle,enr_from_trials) = 0
                      and num_nonnulls(trials_attended,trials_enrolled,trials_done,enr_pilates) = 0
    when 'supervision' then num_nulls(dr,lost,cb,trials_sent,trials_attended,trials_enrolled,enr_body,enr_muscle,enr_pilates) = 0
                      and num_nonnulls(trials_done,enr_fitness,enr_from_trials) = 0
    when 'exclusive' then num_nulls(trials_done,enr_from_trials) = 0
                      and num_nonnulls(dr,lost,cb,trials_sent,trials_attended,trials_enrolled,enr_fitness,enr_body,enr_muscle,enr_pilates) = 0
    end)
);
create index daily_stats_date_idx on public.daily_stats(stat_date, store);

create table public.daily_stats_history (
  id         bigserial primary key,
  stats_id   bigint not null references public.daily_stats(id) on delete cascade,
  changed_at timestamptz not null default now(),
  changed_by text not null,
  old_values jsonb not null,
  new_values jsonb not null
);

create or replace function public.stats_fields(p_kind text) returns text[]
language sql immutable as $$
  select case p_kind
    when 'reception' then array['dr','lost','cb','trials_sent','enr_fitness','enr_body','enr_muscle','enr_from_trials']
    when 'supervision' then array['dr','lost','cb','trials_sent','trials_attended','trials_enrolled','enr_body','enr_muscle','enr_pilates']
    when 'exclusive' then array['trials_done','enr_from_trials'] end
$$;

create or replace function public.stats_int(p jsonb, k text) returns int
language plpgsql immutable as $$
declare v jsonb := p->k; n numeric;
begin
  if v is null or jsonb_typeof(v) = 'null' then raise exception 'Λείπει το πεδίο %.', k; end if;
  begin n := (v #>> '{}')::numeric; exception when others then raise exception 'Το πεδίο % δεν είναι αριθμός.', k; end;
  if n < 0 or n <> trunc(n) or n > 100000 then raise exception 'Το πεδίο % δέχεται μόνο μη αρνητικούς ακέραιους.', k; end if;
  return n::int;
end $$;

-- p_rows: [{ "id": (για διόρθωση), "version": n, "employee_code": "...", "dr": 3, ... }]
-- Επιστρέφει αποτέλεσμα ανά γραμμή· μια λάθος γραμμή δεν χαλάει τις υπόλοιπες.
create or replace function public.stats_save(p_date date, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_role(array['owner','manager']);
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
        if v_role = 'manager' and s.store <> public.my_store() then raise exception 'Η καταχώριση ανήκει σε άλλο κατάστημα.'; end if;
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
        if v_role = 'manager' and e.store <> public.my_store() then raise exception 'Ο εργαζόμενος δεν ανήκει στο κατάστημά σας.'; end if;
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

-- ═══════════════════════════ 7. Αξιολογήσεις ═══════════════════════════
create table public.questionnaires (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(trim(title)) between 3 and 200),
  description text,
  specialties text[] not null default '{}',
  participants text[],                     -- κενό = όλοι οι ενεργοί των ειδικοτήτων
  starts_at   timestamptz,
  ends_at     timestamptz,
  status      text not null default 'draft' check (status in ('draft','active','closed')),
  current_version_id uuid,
  created_by  text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint window_order check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table public.questionnaire_versions (
  id               uuid primary key default gen_random_uuid(),
  questionnaire_id uuid not null references public.questionnaires(id) on delete cascade,
  version          int not null,
  status           text not null default 'draft' check (status in ('draft','published','retired')),
  multi_rule       text check (multi_rule in ('all_or_nothing','partial')),
  source_filename  text,
  created_by       text not null,
  created_at       timestamptz not null default now(),
  published_at     timestamptz,
  published_by     text,
  unique (questionnaire_id, version)
);
alter table public.questionnaires add constraint questionnaires_current_version_fk
  foreign key (current_version_id) references public.questionnaire_versions(id);

create table public.assessment_questions (
  id          uuid primary key default gen_random_uuid(),
  version_id  uuid not null references public.questionnaire_versions(id) on delete cascade,
  row_no      int not null,
  specialty   text,
  section     text not null default 'Γενικά',
  text        text not null,
  qtype       text not null check (qtype in ('single','multi','scale','text')),
  options     jsonb not null default '[]'::jsonb,   -- [{ "key": "Α", "label": "..." }]
  correct     jsonb,                                 -- ["Α","Γ"]
  points      numeric(6,2) check (points is null or points > 0),
  required    boolean not null default true,
  sort        int not null default 0,
  scale_min   int, scale_max int, scale_min_label text, scale_max_label text,
  scale_rule  text check (scale_rule in ('linear'))
);
create index assessment_questions_ver_idx on public.assessment_questions(version_id, sort, row_no);

create table public.questionnaire_window_log (
  id               bigserial primary key,
  questionnaire_id uuid not null references public.questionnaires(id) on delete cascade,
  at               timestamptz not null default now(),
  actor            text not null,
  old_starts       timestamptz, old_ends timestamptz,
  new_starts       timestamptz, new_ends timestamptz,
  note             text
);

create table public.assessment_attempts (
  id               uuid primary key default gen_random_uuid(),
  questionnaire_id uuid not null references public.questionnaires(id),
  version_id       uuid not null references public.questionnaire_versions(id),
  employee_code    text not null references public.employees(code) on update cascade,
  employee_name    text not null,
  store            text not null,
  specialty        text,
  company          text,
  opened_by        text not null,     -- εξουσιοδοτημένος χρήστης που άνοιξε τη διαδικασία
  opened_role      text not null,
  started_at       timestamptz not null default now(),
  last_saved_at    timestamptz,
  submitted_at     timestamptz,
  status           text not null default 'in_progress' check (status in ('in_progress','submitted','pending_manual')),
  answers          jsonb not null default '{}'::jsonb,   -- προσωρινές απαντήσεις
  score            numeric(8,2),
  max_score        numeric(8,2),
  unique (questionnaire_id, employee_code)
);

create table public.assessment_answers (
  id           bigserial primary key,
  attempt_id   uuid not null references public.assessment_attempts(id) on delete cascade,
  question_id  uuid not null references public.assessment_questions(id),
  answer       jsonb,
  is_correct   boolean,
  points       numeric(6,2),
  max_points   numeric(6,2),
  needs_manual boolean not null default false,
  graded_by    text,
  graded_at    timestamptz,
  unique (attempt_id, question_id)
);

-- Κεφαλαία χωρίς τόνους, ανεξάρτητα από τη ρύθμιση γλώσσας του server (και λατινικά A/B/E → ελληνικά)
create or replace function public.gr_up(p text) returns text
language sql immutable as $$
  select translate(trim(coalesce(p,'')),
    'αβγδεζηθικλμνξοπρσςτυφχψωάέήίόύώϊϋΐΰΆΈΉΊΌΎΏΪΫabcdefghijklmnopqrstuvwxyzABE',
    'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΣΤΥΦΧΨΩΑΕΗΙΟΥΩΙΥΙΥΑΕΗΙΟΥΩΙΥΑΒCDΕFGHIJKLMNOPQRSTUVWXYZΑΒΕ')
$$;

create or replace function public.q_type_code(p text) returns text
language sql immutable as $$
  select case regexp_replace(public.gr_up(p), '\s+', ' ', 'g')
    when 'ΜΙΑ ΕΠΙΛΟΓΗ' then 'single' when 'ΠΟΛΛΕΣ ΕΠΙΛΟΓΕΣ' then 'multi'
    when 'ΚΛΙΜΑΚΑ' then 'scale' when 'ΕΛΕΥΘΕΡΟ ΚΕΙΜΕΝΟ' then 'text' end
$$;

create or replace function public.q_letters() returns text[] language sql immutable as $$ select array['Α','Β','Γ','Δ','Ε','ΣΤ'] $$;

-- Έλεγχος και μετατροπή γραμμών Excel. Επιστρέφει { errors: [...], questions: [...] }
create or replace function public.q_parse_rows(p_rows jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r jsonb; v_row int; v_errs jsonb := '[]'::jsonb; v_qs jsonb := '[]'::jsonb; v_type text; v_opts jsonb; v_letters text[] := public.q_letters();
  i int; v_val text; v_gap boolean; v_correct text[]; v_c text; v_points numeric; v_req text; v_sort int; v_spec text;
  v_smin int; v_smax int; v_rule text; v_err text; v_n int := 0;
begin
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Μη έγκυρα δεδομένα.'; end if;
  if jsonb_array_length(p_rows) = 0 then return jsonb_build_object('errors', jsonb_build_array(jsonb_build_object('row', null, 'msg', 'Το αρχείο δεν έχει ερωτήσεις.')), 'questions', '[]'::jsonb); end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'Έως 500 ερωτήσεις ανά ερωτηματολόγιο.'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_n := v_n + 1;
    v_row := coalesce((r->>'row')::int, v_n + 1);
    v_err := null;
    v_type := public.q_type_code(r->>'type');
    v_spec := nullif(trim(coalesce(r->>'specialty','')), '');
    if v_spec is not null and not exists (select 1 from public.specialties where name = v_spec) then
      v_err := format('Άγνωστη ειδικότητα «%s».', v_spec);
    elsif length(trim(coalesce(r->>'text',''))) < 3 then v_err := 'Λείπει η ερώτηση.';
    elsif v_type is null then v_err := format('Μη έγκυρος τύπος απάντησης «%s». Επιτρέπονται: Μία επιλογή, Πολλές επιλογές, Κλίμακα, Ελεύθερο κείμενο.', coalesce(r->>'type',''));
    end if;
    -- Επιλογές Α..ΣΤ
    v_opts := '[]'::jsonb; v_gap := false;
    if v_err is null then
      for i in 1..6 loop
        v_val := nullif(trim(coalesce(r->'options'->>(i-1), '')), '');
        if v_val is null then v_gap := true;
        elsif v_gap and v_type in ('single','multi') then v_err := format('Η επιλογή %s υπάρχει ενώ λείπει προηγούμενη επιλογή.', v_letters[i]); exit;
        else v_opts := v_opts || jsonb_build_object('key', v_letters[i], 'label', left(v_val, 500)); end if;
      end loop;
    end if;
    -- Βαθμοί
    v_points := null;
    if v_err is null and nullif(trim(coalesce(r->>'points','')), '') is not null then
      begin v_points := replace(trim(r->>'points'), ',', '.')::numeric; exception when others then v_err := 'Οι βαθμοί πρέπει να είναι αριθμός.'; end;
      if v_err is null and (v_points <= 0 or v_points > 1000) then v_err := 'Οι βαθμοί πρέπει να είναι θετικός αριθμός.'; end if;
    end if;
    -- Υποχρεωτική
    v_req := public.gr_up(r->>'required');
    if v_err is null and v_req not in ('ΝΑΙ','ΟΧΙ') then v_err := 'Η στήλη «Υποχρεωτική» δέχεται Ναι ή Όχι.'; end if;
    -- Σειρά
    v_sort := null;
    if v_err is null and nullif(trim(coalesce(r->>'order','')), '') is not null then
      begin v_sort := trim(r->>'order')::int; exception when others then v_err := 'Η σειρά εμφάνισης πρέπει να είναι ακέραιος.'; end;
    end if;
    -- Σωστή απάντηση
    v_correct := null; v_rule := null; v_smin := null; v_smax := null;
    if v_err is null then
      v_c := public.gr_up(r->>'correct');
      if v_type in ('single','multi') then
        if jsonb_array_length(v_opts) < 2 then v_err := 'Χρειάζονται τουλάχιστον δύο επιλογές (Α, Β).';
        elsif v_c <> '' then
          select array_agg(distinct trim(x)) into v_correct from regexp_split_to_table(replace(v_c, ' ', ''), '[,;/]') x where trim(x) <> '';
          if exists (select 1 from unnest(v_correct) x where not (x = any(v_letters[1:jsonb_array_length(v_opts)]))) then
            v_err := format('Η σωστή απάντηση «%s» δεν αντιστοιχεί σε συμπληρωμένη επιλογή.', v_c);
          elsif v_type = 'single' and array_length(v_correct, 1) > 1 then v_err := 'Ερώτηση μίας επιλογής με περισσότερες από μία σωστές απαντήσεις.';
          end if;
        end if;
        if v_err is null and v_points is not null and v_correct is null then v_err := 'Ορίστηκαν βαθμοί χωρίς σωστή απάντηση.'; end if;
      elsif v_type = 'scale' then
        begin
          v_smin := nullif(trim(coalesce(r->'options'->>0,'')),'')::int; v_smax := nullif(trim(coalesce(r->'options'->>1,'')),'')::int;
        exception when others then v_err := 'Κλίμακα: Επιλογή Α = ελάχιστη και Επιλογή Β = μέγιστη τιμή (ακέραιοι).'; end;
        if v_err is null and (v_smin is null or v_smax is null) then v_err := 'Κλίμακα: Επιλογή Α = ελάχιστη και Επιλογή Β = μέγιστη τιμή (ακέραιοι).';
        elsif v_err is null and (v_smax <= v_smin or v_smax - v_smin > 10) then v_err := 'Κλίμακα: η μέγιστη τιμή πρέπει να είναι μεγαλύτερη από την ελάχιστη (έως 10 βήματα).';
        elsif v_err is null and v_c not in ('', 'ΑΝΑΛΟΓΙΚΑ') then v_err := 'Κλίμακα: η «Σωστή απάντηση» μένει κενή ή γράφει ΑΝΑΛΟΓΙΚΑ (κανόνας βαθμολόγησης).';
        elsif v_err is null and v_points is not null and v_c = '' then v_err := 'Κλίμακα με βαθμούς χωρίς κανόνα: γράψτε ΑΝΑΛΟΓΙΚΑ στη «Σωστή απάντηση» ή αφήστε κενούς τους βαθμούς.';
        elsif v_err is null and v_points is null and v_c <> '' then v_err := 'Κλίμακα με κανόνα ΑΝΑΛΟΓΙΚΑ χωρίς βαθμούς.';
        end if;
        if v_c = 'ΑΝΑΛΟΓΙΚΑ' then v_rule := 'linear'; end if;
        v_opts := '[]'::jsonb;
      elsif v_type = 'text' then
        if v_c <> '' then v_err := 'Οι ερωτήσεις ελεύθερου κειμένου δεν έχουν σωστή απάντηση (βαθμολογούνται χειροκίνητα).';
        elsif jsonb_array_length(v_opts) > 0 then v_err := 'Οι ερωτήσεις ελεύθερου κειμένου δεν έχουν επιλογές.'; end if;
      end if;
    end if;
    if v_err is not null then
      v_errs := v_errs || jsonb_build_object('row', v_row, 'msg', v_err);
    else
      v_qs := v_qs || jsonb_build_object('row_no', v_row, 'specialty', v_spec,
        'section', coalesce(nullif(trim(r->>'section'),''), 'Γενικά'), 'text', left(trim(r->>'text'), 2000), 'qtype', v_type,
        'options', v_opts, 'correct', to_jsonb(v_correct), 'points', v_points, 'required', v_req = 'ΝΑΙ',
        'sort', coalesce(v_sort, v_n), 'scale_min', v_smin, 'scale_max', v_smax,
        'scale_min_label', case when v_type = 'scale' then nullif(trim(coalesce(r->'options'->>2,'')),'') end,
        'scale_max_label', case when v_type = 'scale' then nullif(trim(coalesce(r->'options'->>3,'')),'') end,
        'scale_rule', v_rule);
    end if;
  end loop;
  return jsonb_build_object('errors', v_errs, 'questions', v_qs);
end $$;

create or replace function public.q_create(p_title text, p_description text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.require_role(array['owner']);
  insert into public.questionnaires(title, description, created_by) values (trim(p_title), nullif(trim(p_description),''), public.current_email()) returning id into v_id;
  insert into public.questionnaire_versions(questionnaire_id, version, created_by) values (v_id, 1, public.current_email());
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.q_update_meta(p_id uuid, p_title text, p_description text, p_specialties text[], p_participants text[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(array['owner']);
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

-- Πρόχειρη έκδοση: αν η τελευταία έκδοση έχει δημοσιευτεί, δημιουργείται νέα
create or replace function public.q_draft_version(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v public.questionnaire_versions; v_new uuid;
begin
  select * into v from public.questionnaire_versions where questionnaire_id = p_id order by version desc limit 1;
  if found and v.status = 'draft' then return v.id; end if;
  insert into public.questionnaire_versions(questionnaire_id, version, multi_rule, created_by)
  values (p_id, coalesce(v.version, 0) + 1, v.multi_rule, public.current_email()) returning id into v_new;
  insert into public.assessment_questions(version_id, row_no, specialty, section, text, qtype, options, correct, points, required, sort,
         scale_min, scale_max, scale_min_label, scale_max_label, scale_rule)
  select v_new, row_no, specialty, section, text, qtype, options, correct, points, required, sort,
         scale_min, scale_max, scale_min_label, scale_max_label, scale_rule
    from public.assessment_questions where version_id = v.id;
  return v_new;
end $$;

-- Αποθήκευση ερωτήσεων (από Excel ή διορθώσεις) σε πρόχειρη έκδοση. Ποτέ αυτόματη ενεργοποίηση.
create or replace function public.q_save_questions(p_id uuid, p_rows jsonb, p_filename text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_parsed jsonb; v_ver uuid; q jsonb;
begin
  perform public.require_role(array['owner']);
  if not exists (select 1 from public.questionnaires where id = p_id) then raise exception 'Το ερωτηματολόγιο δεν βρέθηκε.'; end if;
  v_parsed := public.q_parse_rows(p_rows);
  if jsonb_array_length(v_parsed->'errors') > 0 then
    return jsonb_build_object('ok', false, 'errors', v_parsed->'errors');
  end if;
  v_ver := public.q_draft_version(p_id);
  delete from public.assessment_questions where version_id = v_ver;
  for q in select * from jsonb_array_elements(v_parsed->'questions') loop
    insert into public.assessment_questions(version_id, row_no, specialty, section, text, qtype, options, correct, points, required, sort,
           scale_min, scale_max, scale_min_label, scale_max_label, scale_rule)
    values (v_ver, (q->>'row_no')::int, q->>'specialty', q->>'section', q->>'text', q->>'qtype', q->'options',
           case when jsonb_typeof(q->'correct') = 'array' then q->'correct' end, (q->>'points')::numeric, (q->>'required')::boolean,
           (q->>'sort')::int, (q->>'scale_min')::int, (q->>'scale_max')::int, q->>'scale_min_label', q->>'scale_max_label', q->>'scale_rule');
  end loop;
  update public.questionnaire_versions set source_filename = left(p_filename, 200) where id = v_ver;
  update public.questionnaires set updated_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'version_id', v_ver, 'count', jsonb_array_length(v_parsed->'questions'));
end $$;

create or replace function public.q_set_multi_rule(p_id uuid, p_rule text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ver uuid;
begin
  perform public.require_role(array['owner']);
  if p_rule is not null and p_rule not in ('all_or_nothing','partial') then raise exception 'Μη έγκυρος κανόνας.'; end if;
  v_ver := public.q_draft_version(p_id);
  update public.questionnaire_versions set multi_rule = p_rule where id = v_ver;
  return jsonb_build_object('ok', true, 'version_id', v_ver);
end $$;

-- Διάστημα διαθεσιμότητας σε ώρα Ελλάδας, με πλήρη καταγραφή αλλαγών / παρατάσεων
create or replace function public.q_set_window(p_id uuid, p_starts text, p_ends text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare q public.questionnaires; v_s timestamptz := public.athens_ts(p_starts); v_e timestamptz := public.athens_ts(p_ends);
begin
  perform public.require_role(array['owner']);
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

-- Έλεγχοι πριν από ενεργοποίηση. Επιστρέφει λίστα προβλημάτων.
create or replace function public.q_check(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q public.questionnaires; v public.questionnaire_versions; v_errs jsonb := '[]'::jsonb; s text;
begin
  select * into q from public.questionnaires where id = p_id;
  select * into v from public.questionnaire_versions where questionnaire_id = p_id order by version desc limit 1;
  if not exists (select 1 from public.assessment_questions where version_id = v.id) then v_errs := v_errs || to_jsonb('Δεν υπάρχουν ερωτήσεις.'::text); end if;
  if cardinality(q.specialties) = 0 then v_errs := v_errs || to_jsonb('Ορίστε σε ποιες ειδικότητες απευθύνεται.'::text); end if;
  if q.starts_at is null or q.ends_at is null then v_errs := v_errs || to_jsonb('Ορίστε διάστημα διαθεσιμότητας.'::text); end if;
  foreach s in array q.specialties loop
    if not exists (select 1 from public.assessment_questions where version_id = v.id and (specialty is null or specialty = s)) then
      v_errs := v_errs || to_jsonb(format('Δεν υπάρχουν ερωτήσεις για την ειδικότητα «%s».', s));
    end if;
  end loop;
  if exists (select 1 from public.assessment_questions where version_id = v.id and specialty is not null and not (specialty = any(q.specialties))) then
    v_errs := v_errs || to_jsonb('Υπάρχουν ερωτήσεις για ειδικότητα που δεν συμμετέχει στο ερωτηματολόγιο.'::text);
  end if;
  if v.multi_rule is null and exists (select 1 from public.assessment_questions where version_id = v.id and qtype = 'multi' and points is not null) then
    v_errs := v_errs || to_jsonb('Ορίστε κανόνα βαθμολόγησης για τις ερωτήσεις πολλών σωστών επιλογών.'::text);
  end if;
  return v_errs;
end $$;

create or replace function public.q_publish(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_errs jsonb; v public.questionnaire_versions;
begin
  perform public.require_role(array['owner']);
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
  perform public.require_role(array['owner']);
  update public.questionnaires set status = 'closed', updated_at = now() where id = p_id and status = 'active';
  if not found then raise exception 'Το ερωτηματολόγιο δεν είναι ενεργό.'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Κατάσταση αξιολόγησης για έναν εργαζόμενο
create or replace function public.attempt_state(a public.assessment_attempts, q public.questionnaires) returns text
language sql stable as $$
  select case
    when a.id is null then 'not_started'
    when a.status in ('submitted','pending_manual') then a.status
    when q.ends_at is not null and now() > q.ends_at then 'expired'
    else 'in_progress' end
$$;

-- Εργαζόμενοι που αφορά ένα ενεργό ερωτηματολόγιο, στο πεδίο του χρήστη (χωρίς βαθμολογίες)
create or replace function public.assessment_targets(p_qid uuid)
returns table (employee_code text, employee_name text, store text, specialty text, state text, started_at timestamptz, submitted_at timestamptz)
language sql stable security definer set search_path = public as $$
  select e.code, e.first || ' ' || e.last, e.store, e.specialty, public.attempt_state(a, q), a.started_at, a.submitted_at
    from public.questionnaires q
    join public.employees e on e.status = 'Ενεργός' and e.specialty = any(q.specialties)
         and (q.participants is null or e.code = any(q.participants))
    left join public.assessment_attempts a on a.questionnaire_id = q.id and a.employee_code = e.code
   where q.id = p_qid and q.status in ('active','closed')
     and public.my_role() in ('owner','hr','manager','trainer')
     and public.employee_in_scope(e.code)
   order by e.store, e.last, e.first
$$;

-- Ενεργά ερωτηματολόγια ορατά στον χρήστη (για επιλογή), χωρίς ερωτήσεις
create or replace function public.assessments_open()
returns table (id uuid, title text, description text, specialties text[], starts_at timestamptz, ends_at timestamptz, status text, version int)
language sql stable security definer set search_path = public as $$
  select q.id, q.title, q.description, q.specialties, q.starts_at, q.ends_at, q.status, v.version
    from public.questionnaires q join public.questionnaire_versions v on v.id = q.current_version_id
   where q.status = 'active' and public.my_role() in ('owner','hr','manager','trainer')
   order by q.ends_at
$$;

-- Κατάσταση αξιολογήσεων ενός εργαζομένου (για manager/εκπαιδευτή: χωρίς απαντήσεις ή βαθμούς)
create or replace function public.employee_assessments(p_code text)
returns table (questionnaire_id uuid, title text, version int, state text, store text, specialty text,
               opened_by text, started_at timestamptz, submitted_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select q.id, q.title, v.version, public.attempt_state(a, q), a.store, a.specialty, a.opened_by, a.started_at, a.submitted_at, q.ends_at
    from public.assessment_attempts a
    join public.questionnaires q on q.id = a.questionnaire_id
    join public.questionnaire_versions v on v.id = a.version_id
   where a.employee_code = p_code and public.employee_in_scope(p_code)
     and (public.my_role() in ('owner','hr') or public.can_see_store(a.store) or public.in_trainer_scope(a.store, a.specialty))
   order by a.started_at desc
$$;

create or replace function public.grade_attempt(p_attempt uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  a public.assessment_attempts; qv public.questionnaire_versions; q public.assessment_questions;
  v_ans jsonb; v_sel text[]; v_cor text[]; v_pts numeric; v_ok boolean; v_manual boolean; v_hit int; v_wrong int; v_num numeric;
begin
  select * into a from public.assessment_attempts where id = p_attempt;
  select * into qv from public.questionnaire_versions where id = a.version_id;
  delete from public.assessment_answers where attempt_id = p_attempt;
  for q in select * from public.assessment_questions where version_id = a.version_id and (specialty is null or specialty = a.specialty) loop
    v_ans := a.answers -> q.id::text;
    v_pts := null; v_ok := null; v_manual := false;
    if q.qtype in ('single','multi') then
      select coalesce(array_agg(x order by x), '{}') into v_sel from jsonb_array_elements_text(case when jsonb_typeof(v_ans) = 'array' then v_ans when jsonb_typeof(v_ans) = 'string' then jsonb_build_array(v_ans) else '[]'::jsonb end) x;
      if q.correct is not null then
        select array_agg(x order by x) into v_cor from jsonb_array_elements_text(q.correct) x;
        v_ok := v_sel = v_cor;
        if q.points is not null then
          if q.qtype = 'single' or qv.multi_rule = 'all_or_nothing' then
            v_pts := case when v_ok then q.points else 0 end;
          else
            select count(*) filter (where x = any(v_cor)), count(*) filter (where not (x = any(v_cor))) into v_hit, v_wrong from unnest(v_sel) x;
            v_pts := round(q.points * greatest(0, v_hit - v_wrong)::numeric / cardinality(v_cor), 2);
          end if;
        end if;
      end if;
    elsif q.qtype = 'scale' then
      if q.points is not null and q.scale_rule = 'linear' then
        v_num := case when jsonb_typeof(v_ans) = 'number' then (v_ans #>> '{}')::numeric end;
        v_pts := case when v_num is null then 0 else round(q.points * (v_num - q.scale_min) / (q.scale_max - q.scale_min), 2) end;
      end if;
    elsif q.qtype = 'text' then
      v_manual := q.points is not null and coalesce(trim(v_ans #>> '{}'), '') <> '';
      if q.points is not null and not v_manual then v_pts := 0; end if;
    end if;
    insert into public.assessment_answers(attempt_id, question_id, answer, is_correct, points, max_points, needs_manual)
    values (p_attempt, q.id, v_ans, v_ok, v_pts, q.points, v_manual);
  end loop;
  update public.assessment_attempts set
    status = case when exists (select 1 from public.assessment_answers where attempt_id = p_attempt and needs_manual and graded_at is null) then 'pending_manual' else 'submitted' end,
    max_score = (select sum(max_points) from public.assessment_answers where attempt_id = p_attempt),
    score = case when exists (select 1 from public.assessment_answers where attempt_id = p_attempt and needs_manual and graded_at is null) then null
                 else (select sum(points) from public.assessment_answers where attempt_id = p_attempt and max_points is not null) end
  where id = p_attempt;
end $$;

-- Χειροκίνητη βαθμολόγηση ερώτησης ελεύθερου κειμένου (ΓΔ, HR)
create or replace function public.assessment_grade(p_attempt uuid, p_question uuid, p_points numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.assessment_answers;
begin
  perform public.require_role(array['owner','hr']);
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

-- ═══════════════════════════ 8. Απομονωμένη συμπλήρωση από εργαζόμενο ═══════════════════════════
-- Ο εξουσιοδοτημένος χρήστης ανοίγει τη διαδικασία και παίρνει ένα κλειδί μίας χρήσης.
-- Η εφαρμογή ΑΠΟΣΥΝΔΕΕΙ τον χρήστη από τη συσκευή· η οθόνη του εργαζομένου έχει ΜΟΝΟ αυτό το κλειδί,
-- που δίνει πρόσβαση σε μία φόρμα ενός εργαζομένου. Η επιστροφή απαιτεί νέα είσοδο με κωδικό.
create table public.fill_sessions (
  id            uuid primary key default gen_random_uuid(),
  token_hash    text not null unique,
  kind          text not null check (kind in ('request','assessment')),
  request_id    uuid references public.hr_requests(id) on delete cascade,
  attempt_id    uuid references public.assessment_attempts(id) on delete cascade,
  employee_code text not null,
  opened_by     text not null,
  opened_role   text not null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz,
  completed_at  timestamptz,
  cancelled_at  timestamptz,
  cancelled_by  text,
  constraint one_target check ((kind = 'request' and request_id is not null and attempt_id is null) or (kind = 'assessment' and attempt_id is not null and request_id is null))
);

create or replace function public.fill_hash(p_token text) returns text
language sql immutable as $$ select encode(sha256(convert_to(coalesce(p_token,''), 'UTF8')), 'hex') $$;

create or replace function public.fill_new_token() returns text
language sql volatile as $$ select replace(gen_random_uuid()::text || gen_random_uuid()::text || gen_random_uuid()::text, '-', '') $$;

create or replace function public.fill_start_request(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_token text := public.fill_new_token(); v_id uuid;
begin
  perform public.require_role(array['owner','hr','manager']);
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
  v_role text := public.require_role(array['owner','hr','manager','trainer']);
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
  select * into a from public.assessment_attempts where questionnaire_id = p_qid and employee_code = e.code for update;
  if found and a.status <> 'in_progress' then raise exception 'Ο εργαζόμενος έχει ήδη υποβάλει αυτή την αξιολόγηση.'; end if;
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

-- Ακύρωση ανοιχτής συμπλήρωσης (από όποιον την άνοιξε ή ΓΔ/HR)
create or replace function public.fill_cancel(p_session uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions;
begin
  perform public.require_role(array['owner','hr','manager','trainer']);
  select * into s from public.fill_sessions where id = p_session for update;
  if not found then raise exception 'Δεν βρέθηκε.'; end if;
  if s.opened_by <> public.current_email() and public.my_role() not in ('owner','hr') then raise exception 'Δεν επιτρέπεται.'; end if;
  if s.completed_at is null and s.cancelled_at is null then
    update public.fill_sessions set cancelled_at = now(), cancelled_by = public.current_email() where id = p_session;
  end if;
  return jsonb_build_object('ok', true, 'completed', s.completed_at is not null);
end $$;

-- Κατάσταση συμπλήρωσης (για τον χρήστη που επιστρέφει)
create or replace function public.fill_status(p_session uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('kind', kind, 'request_id', request_id, 'attempt_id', attempt_id,
         'completed', completed_at is not null, 'cancelled', cancelled_at is not null)
    from public.fill_sessions
   where id = p_session and (opened_by = public.current_email() or public.my_role() in ('owner','hr'))
$$;

-- Εσωτερικό: έγκυρο κλειδί → συνεδρία
create or replace function public.fill_session(p_token text) returns public.fill_sessions
language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions;
begin
  select * into s from public.fill_sessions where token_hash = public.fill_hash(p_token) for update;
  if not found or s.cancelled_at is not null then raise exception 'Η φόρμα δεν είναι διαθέσιμη. Ζητήστε από τον υπεύθυνο να την ανοίξει ξανά.'; end if;
  if s.expires_at is not null and now() > s.expires_at then raise exception 'Η φόρμα έληξε. Ζητήστε από τον υπεύθυνο να την ανοίξει ξανά.'; end if;
  return s;
end $$;

-- Ό,τι χρειάζεται η οθόνη του εργαζομένου — και ΤΙΠΟΤΑ ΑΛΛΟ (ούτε σωστές απαντήσεις ούτε βαθμοί)
create or replace function public.fill_get(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions; r public.hr_requests; a public.assessment_attempts; q public.questionnaires;
begin
  s := public.fill_session(p_token);
  if s.completed_at is not null then return jsonb_build_object('completed', true, 'kind', s.kind); end if;
  if s.kind = 'request' then
    select * into r from public.hr_requests where id = s.request_id;
    return jsonb_build_object('kind', 'request', 'completed', false,
      'employee', jsonb_build_object('code', r.employee_code, 'name', r.employee_name, 'store', r.store, 'company', r.company),
      'ref', r.ref, 'category', r.category, 'category_label', public.req_category_label(r.category),
      'fields', jsonb_build_object('body', r.body, 'leave_type', r.leave_type, 'start_date', r.start_date, 'end_date', r.end_date,
                'days_requested', r.days_requested, 'details', r.details, 'template_version_id', r.template_version_id),
      'leave_types', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) order by sort), '[]') from public.leave_types where active),
      'templates', (select jsonb_object_agg(t.key, jsonb_build_object('id', v.id, 'body', v.body))
                      from public.text_templates t
                      join lateral (select id, body from public.text_template_versions where key = t.key order by version desc limit 1) v on true
                     where t.key in ('leave_request_body','leave_request_help')),
      'attachments', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'filename', filename)), '[]') from public.hr_attachments where request_id = r.id));
  end if;
  select * into a from public.assessment_attempts where id = s.attempt_id;
  select * into q from public.questionnaires where id = a.questionnaire_id;
  if a.status <> 'in_progress' then return jsonb_build_object('completed', true, 'kind', 'assessment'); end if;
  return jsonb_build_object('kind', 'assessment', 'completed', false,
    'employee', jsonb_build_object('code', a.employee_code, 'name', a.employee_name, 'store', a.store),
    'title', q.title, 'description', q.description, 'starts_at', q.starts_at, 'ends_at', q.ends_at, 'now', now(),
    'open', q.status = 'active' and now() between q.starts_at and q.ends_at,
    'answers', a.answers,
    'questions', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', x.id, 'section', x.section, 'text', x.text, 'qtype', x.qtype, 'options', x.options, 'required', x.required,
        'scale_min', x.scale_min, 'scale_max', x.scale_max, 'scale_min_label', x.scale_min_label, 'scale_max_label', x.scale_max_label)
        order by x.sort, x.row_no), '[]')
      from public.assessment_questions x where x.version_id = a.version_id and (x.specialty is null or x.specialty = a.specialty)));
end $$;

create or replace function public.fill_save_request(p_token text, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions; r public.hr_requests;
begin
  s := public.fill_session(p_token);
  if s.kind <> 'request' or s.completed_at is not null then raise exception 'Η φόρμα έχει ολοκληρωθεί.'; end if;
  select * into r from public.hr_requests where id = s.request_id for update;
  if r.status <> 'draft' then raise exception 'Το αίτημα έχει ήδη υποβληθεί.'; end if;
  perform public.req_apply_fields(r.id, p - 'manager_note', true);
  update public.hr_requests set written_by = 'employee:' || r.employee_code, written_at = now() where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.fill_attach(p_token text, p_filename text, p_mime text, p_data text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions;
begin
  s := public.fill_session(p_token);
  if s.kind <> 'request' or s.completed_at is not null then raise exception 'Η φόρμα έχει ολοκληρωθεί.'; end if;
  return public.attach_file(s.request_id, p_filename, p_mime, p_data, 'employee:' || s.employee_code);
end $$;

-- Ο εργαζόμενος ολοκληρώνει το κείμενό του· το αίτημα περιμένει έλεγχο και υποβολή από τον manager
create or replace function public.fill_finish_request(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions; r public.hr_requests;
begin
  s := public.fill_session(p_token);
  if s.kind <> 'request' then raise exception 'Μη έγκυρη φόρμα.'; end if;
  if s.completed_at is not null then return jsonb_build_object('ok', true, 'already', true); end if;
  select * into r from public.hr_requests where id = s.request_id for update;
  if coalesce(r.written_by,'') not like 'employee:%' then raise exception 'Συμπληρώστε πρώτα το αίτημα.'; end if;
  perform public.req_validate(r);
  update public.fill_sessions set completed_at = now() where id = s.id;
  insert into public.hr_request_events(request_id, actor, actor_role, action, from_status, to_status)
  values (r.id, 'employee:' || r.employee_code, 'employee', 'employee_completed', 'draft', 'draft');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.fill_check_window(a public.assessment_attempts) returns void
language plpgsql stable security definer set search_path = public as $$
declare q public.questionnaires;
begin
  select * into q from public.questionnaires where id = a.questionnaire_id;
  if q.status <> 'active' then raise exception 'Η αξιολόγηση δεν είναι πλέον ενεργή.'; end if;
  if now() < q.starts_at then raise exception 'Η αξιολόγηση δεν έχει ξεκινήσει ακόμη.'; end if;
  if now() > q.ends_at then raise exception 'Η προθεσμία έληξε στις %. Οι απαντήσεις δεν υποβλήθηκαν.', to_char(q.ends_at at time zone 'Europe/Athens', 'DD/MM/YYYY HH24:MI'); end if;
end $$;

-- Κρατά μόνο έγκυρες απαντήσεις σε ερωτήσεις αυτής της έκδοσης/ειδικότητας
create or replace function public.fill_clean_answers(a public.assessment_attempts, p_answers jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare x public.assessment_questions; v jsonb; v_keys text[]; v_out jsonb := '{}'::jsonb; n numeric;
begin
  if jsonb_typeof(p_answers) <> 'object' then return v_out; end if;
  for x in select * from public.assessment_questions where version_id = a.version_id and (specialty is null or specialty = a.specialty) loop
    v := p_answers -> x.id::text;
    continue when v is null or jsonb_typeof(v) = 'null';
    select coalesce(array_agg(o->>'key'), '{}') into v_keys from jsonb_array_elements(x.options) o;
    if x.qtype = 'single' then
      if jsonb_typeof(v) = 'string' and (v #>> '{}') = any(v_keys) then v_out := v_out || jsonb_build_object(x.id::text, v); end if;
    elsif x.qtype = 'multi' then
      if jsonb_typeof(v) = 'array' and jsonb_array_length(v) <= 6
         and not exists (select 1 from jsonb_array_elements(v) e where jsonb_typeof(e) <> 'string' or not ((e #>> '{}') = any(v_keys))) then
        v_out := v_out || jsonb_build_object(x.id::text, (select coalesce(jsonb_agg(distinct e), '[]') from jsonb_array_elements(v) e));
      end if;
    elsif x.qtype = 'scale' then
      if jsonb_typeof(v) = 'number' then
        n := (v #>> '{}')::numeric;
        if n = trunc(n) and n between x.scale_min and x.scale_max then v_out := v_out || jsonb_build_object(x.id::text, v); end if;
      end if;
    elsif x.qtype = 'text' then
      if jsonb_typeof(v) = 'string' and length(v #>> '{}') <= 4000 then v_out := v_out || jsonb_build_object(x.id::text, v); end if;
    end if;
  end loop;
  return v_out;
end $$;

create or replace function public.fill_save_answers(p_token text, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions; a public.assessment_attempts;
begin
  s := public.fill_session(p_token);
  if s.kind <> 'assessment' or s.completed_at is not null then raise exception 'Η αξιολόγηση έχει ήδη υποβληθεί.'; end if;
  select * into a from public.assessment_attempts where id = s.attempt_id for update;
  if a.status <> 'in_progress' then raise exception 'Η αξιολόγηση έχει ήδη υποβληθεί.'; end if;
  perform public.fill_check_window(a);
  update public.assessment_attempts set answers = public.fill_clean_answers(a, coalesce(p_answers, '{}')), last_saved_at = now() where id = a.id;
  return jsonb_build_object('ok', true, 'saved_at', now());
end $$;

-- Οριστική υποβολή από τον εργαζόμενο. Προστασία από διπλό πάτημα: δεύτερη κλήση δεν δημιουργεί νέο αποτέλεσμα.
create or replace function public.fill_submit_assessment(p_token text, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.fill_sessions; a public.assessment_attempts; v_missing int; v_clean jsonb;
begin
  s := public.fill_session(p_token);
  if s.kind <> 'assessment' then raise exception 'Μη έγκυρη φόρμα.'; end if;
  select * into a from public.assessment_attempts where id = s.attempt_id for update;
  if a.status <> 'in_progress' or s.completed_at is not null then return jsonb_build_object('ok', true, 'already', true); end if;
  perform public.fill_check_window(a);
  v_clean := public.fill_clean_answers(a, coalesce(p_answers, a.answers));
  select count(*) into v_missing from public.assessment_questions x
   where x.version_id = a.version_id and (x.specialty is null or x.specialty = a.specialty) and x.required
     and (not v_clean ? x.id::text or v_clean -> x.id::text in ('null'::jsonb, '""'::jsonb, '[]'::jsonb));
  if v_missing > 0 then raise exception 'Υπάρχουν % υποχρεωτικές ερωτήσεις χωρίς απάντηση.', v_missing; end if;
  update public.assessment_attempts set answers = v_clean, submitted_at = now(), last_saved_at = now(), status = 'submitted' where id = a.id;
  perform public.grade_attempt(a.id);
  update public.fill_sessions set completed_at = now() where id = s.id;
  return jsonb_build_object('ok', true);
end $$;

-- ═══════════════════════════ 9. Row Level Security ═══════════════════════════
alter table public.specialties             enable row level security;
alter table public.trainer_scopes          enable row level security;
alter table public.employee_assignments    enable row level security;
alter table public.text_templates          enable row level security;
alter table public.text_template_versions  enable row level security;
alter table public.leave_types             enable row level security;
alter table public.reject_reasons          enable row level security;
alter table public.hr_requests             enable row level security;
alter table public.hr_request_internal     enable row level security;
alter table public.hr_decisions            enable row level security;
alter table public.hr_request_events       enable row level security;
alter table public.hr_attachments          enable row level security;
alter table public.daily_stats             enable row level security;
alter table public.daily_stats_history     enable row level security;
alter table public.questionnaires          enable row level security;
alter table public.questionnaire_versions  enable row level security;
alter table public.assessment_questions    enable row level security;
alter table public.questionnaire_window_log enable row level security;
alter table public.assessment_attempts     enable row level security;
alter table public.assessment_answers      enable row level security;
alter table public.fill_sessions           enable row level security;

create policy spec_read  on public.specialties for select to authenticated using (public.my_role() is not null);
create policy spec_write on public.specialties for all to authenticated using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

create policy ts_read  on public.trainer_scopes for select to authenticated using (public.my_role() = 'owner' or email = public.current_email());
create policy ts_write on public.trainer_scopes for all to authenticated using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

-- Ιστορικό θέσεων: όσοι βλέπουν τον εργαζόμενο
create policy asg_read on public.employee_assignments for select to authenticated
  using (exists (select 1 from public.employees e where e.code = employee_code));

create policy tpl_read  on public.text_templates for select to authenticated using (public.my_role() in ('owner','hr','manager'));
create policy tplv_read on public.text_template_versions for select to authenticated using (public.my_role() in ('owner','hr','manager'));
create policy lt_read   on public.leave_types for select to authenticated using (public.my_role() in ('owner','hr','manager'));
create policy lt_write  on public.leave_types for all to authenticated using (public.my_role() = 'owner') with check (public.my_role() = 'owner');
create policy rr_read   on public.reject_reasons for select to authenticated using (public.my_role() in ('owner','hr','manager'));
create policy rr_write  on public.reject_reasons for all to authenticated using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

-- Αιτήματα: ΓΔ/HR όλα τα καταστήματα, manager μόνο το δικό του (με βάση το κατάστημα της εγγραφής), εκπαιδευτής τίποτα
create policy req_read  on public.hr_requests for select to authenticated using (public.can_see_store(store));
create policy reqi_read on public.hr_request_internal for select to authenticated using (public.my_role() in ('owner','hr'));
create policy dec_read  on public.hr_decisions for select to authenticated
  using (exists (select 1 from public.hr_requests r where r.id = request_id));
create policy ev_read   on public.hr_request_events for select to authenticated
  using ((not internal or public.my_role() in ('owner','hr')) and exists (select 1 from public.hr_requests r where r.id = request_id));
create policy att_read  on public.hr_attachments for select to authenticated
  using (exists (select 1 from public.hr_requests r where r.id = request_id));

create policy st_read  on public.daily_stats for select to authenticated using (public.can_see_store(store));
create policy sth_read on public.daily_stats_history for select to authenticated
  using (exists (select 1 from public.daily_stats s where s.id = stats_id));

-- Αξιολογήσεις: πλήρη στοιχεία (ερωτήσεις, σωστές απαντήσεις, βαθμοί) μόνο ΓΔ και HR
create policy q_read   on public.questionnaires for select to authenticated using (public.my_role() in ('owner','hr'));
create policy qv_read  on public.questionnaire_versions for select to authenticated using (public.my_role() in ('owner','hr'));
create policy qq_read  on public.assessment_questions for select to authenticated using (public.my_role() in ('owner','hr'));
create policy qw_read  on public.questionnaire_window_log for select to authenticated using (public.my_role() in ('owner','hr'));
create policy qa_read  on public.assessment_attempts for select to authenticated using (public.my_role() in ('owner','hr'));
create policy qan_read on public.assessment_answers for select to authenticated using (public.my_role() in ('owner','hr'));
-- fill_sessions: καμία απευθείας πρόσβαση (μόνο μέσω συναρτήσεων)

-- Εγγραφές μόνο μέσω των συναρτήσεων
revoke all on all tables in schema public from anon;
revoke insert, update, delete on public.employee_assignments, public.text_template_versions, public.text_templates,
  public.hr_requests, public.hr_request_internal, public.hr_decisions, public.hr_request_events, public.hr_attachments,
  public.daily_stats, public.daily_stats_history, public.questionnaires, public.questionnaire_versions,
  public.assessment_questions, public.questionnaire_window_log, public.assessment_attempts, public.assessment_answers,
  public.fill_sessions from authenticated;
revoke all on public.fill_sessions from authenticated;

-- Τα αρχεία καταγραφής δεν αλλάζουν ποτέ
create or replace function public.append_only() returns trigger language plpgsql as $$
begin raise exception 'Το ιστορικό δεν τροποποιείται.'; end $$;
create trigger hr_events_append_only before update or delete on public.hr_request_events
  for each row when (pg_trigger_depth() = 0) execute function public.append_only();
create trigger stats_history_append_only before update or delete on public.daily_stats_history
  for each row when (pg_trigger_depth() = 0) execute function public.append_only();
create trigger window_log_append_only before update or delete on public.questionnaire_window_log
  for each row when (pg_trigger_depth() = 0) execute function public.append_only();
create trigger tplv_append_only before update or delete on public.text_template_versions
  for each row execute function public.append_only();

-- Καταγραφή αλλαγών ρυθμίσεων στο υπάρχον Ιστορικό ενεργειών
create trigger audit_specialties    after insert or update or delete on public.specialties    for each row execute function public.audit_trigger();
create trigger audit_trainer_scopes after insert or update or delete on public.trainer_scopes for each row execute function public.audit_trigger();
create trigger audit_leave_types    after insert or update or delete on public.leave_types    for each row execute function public.audit_trigger();
create trigger audit_reject_reasons after insert or update or delete on public.reject_reasons for each row execute function public.audit_trigger();
create trigger audit_tpl_versions   after insert on public.text_template_versions for each row execute function public.audit_trigger();
create trigger audit_questionnaires after insert or update on public.questionnaires for each row execute function public.audit_trigger();

-- ═══════════════════════════ 10. Δικαιώματα εκτέλεσης ═══════════════════════════
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
-- Εσωτερικές συναρτήσεις: όχι απευθείας κλήση
revoke execute on function public.req_apply_fields(uuid, jsonb, boolean), public.req_event(uuid, text, text, text, text, jsonb, boolean, text),
  public.attach_file(uuid, text, text, text, text), public.grade_attempt(uuid), public.fill_session(text),
  public.q_draft_version(uuid), public.track_assignment(), public.append_only(), public.fill_check_window(public.assessment_attempts),
  public.fill_clean_answers(public.assessment_attempts, jsonb)
  from authenticated;
-- Η οθόνη του εργαζομένου (χωρίς λογαριασμό) καλεί ΜΟΝΟ αυτές, με το κλειδί μίας χρήσης
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb)
  to anon;
