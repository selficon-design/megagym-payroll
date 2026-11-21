-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Έκδοση 3.1 · Μέρος 1: Ερωτηματολόγια, αιτήματα και άδειες
--   1. Έως 12 επιλογές ανά ερώτηση (Α … ΙΒ). Οι παλιές απαντήσεις μένουν δεμένες στην έκδοση ερωτήσεων τους.
--   2. «Αναρρωτική Άδεια» ως ανεξάρτητη κατηγορία (sick_leave)· τα παλιά αιτήματα αναρρωτικής μεταφέρονται
--      χωρίς αλλαγή ημερομηνιών, καταστάσεων, αποφάσεων, συνημμένων και ιστορικού (καταγράφεται γεγονός).
--   9. Αλλαγή ημερομηνιών ΕΚΚΡΕΜΟΥΣ αιτήματος άδειας από τον manager, με όλες τις αναθεωρήσεις.
--  10. Έγκριση άλλων ημερομηνιών ή μόνο συγκεκριμένων ημερών, με υποχρεωτική αιτιολογία διαφοροποίησης.
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: καμία διαγραφή δεδομένων.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ─────────────── 1. Έως 12 επιλογές ───────────────
create or replace function public.q_letters() returns text[] language sql immutable as $$
  select array['Α','Β','Γ','Δ','Ε','ΣΤ','Ζ','Η','Θ','Ι','ΙΑ','ΙΒ']
$$;

-- ─────────────── 2. Αναρρωτική Άδεια ως κατηγορία ───────────────
alter table public.hr_requests drop constraint if exists hr_requests_category_check;
alter table public.hr_requests add constraint hr_requests_category_check check (category in (
  'leave','sick_leave','leave_change','shift_change','raise','contract_change','advance','documents','transfer','other_hr',
  'negative_review','incident','warning_request'));

create or replace function public.is_leave_cat(p_category text) returns boolean language sql immutable as $$
  select p_category in ('leave','sick_leave')
$$;

create or replace function public.req_flow(p_category text) returns text
language sql immutable as $$
  select case
    when p_category in ('leave','sick_leave','leave_change') then 'leave'
    when p_category in ('raise','contract_change') then 'gm'
    when p_category = 'warning_request' then 'warning'
    when p_category in ('negative_review','incident') then 'report'
    else 'generic' end
$$;

create or replace function public.req_category_label(p_category text) returns text
language sql immutable as $$
  select case p_category
    when 'leave' then 'Άδεια / απουσία' when 'sick_leave' then 'Αναρρωτική Άδεια'
    when 'leave_change' then 'Αλλαγή ημερομηνιών εγκεκριμένης άδειας'
    when 'shift_change' then 'Αλλαγή βάρδιας, ρεπό ή προγράμματος'
    when 'raise' then 'Αύξηση αποδοχών' when 'contract_change' then 'Αλλαγή ωρών ή σύμβασης'
    when 'advance' then 'Προκαταβολή' when 'documents' then 'Βεβαιώσεις και έγγραφα'
    when 'transfer' then 'Μετακίνηση καταστήματος ή αλλαγή θέσης' when 'other_hr' then 'Λοιπό αίτημα προς HR'
    when 'negative_review' then 'Αρνητική αξιολόγηση' when 'incident' then 'Περιστατικό'
    when 'warning_request' then 'Αίτημα έγγραφης προειδοποίησης' else p_category end
$$;

-- Η αναρρωτική έχει μία διαδρομή καταχώρισης: η κατηγορία ορίζει το είδος άδειας «sick».
create or replace function public.req_sick_category() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.category = 'sick_leave' then
    new.leave_type := 'sick';
    new.leave_type_label := (select label from public.leave_types where code = 'sick');
  elsif new.category = 'leave' and new.leave_type = 'sick' and (tg_op = 'INSERT' or old.leave_type is distinct from 'sick') then
    raise exception 'Η αναρρωτική καταχωρίζεται στην κατηγορία «Αναρρωτική Άδεια».';
  end if;
  return new;
end $$;
drop trigger if exists hr_requests_sick_category on public.hr_requests;
create trigger hr_requests_sick_category before insert or update of category, leave_type on public.hr_requests
  for each row execute function public.req_sick_category();

-- Μεταφορά παλιών αιτημάτων αναρρωτικής: ίδιο αίτημα (ίδιο id, αριθμός, ημερομηνίες, κατάσταση, αποφάσεις,
-- συνημμένα, ημέρες άδειας)· αλλάζει μόνο η κατηγορία και καταγράφεται γεγονός στο ιστορικό. Επαναλήψιμη.
create or replace function public.req_migrate_sick() returns int
language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0;
begin
  for r in select id, status from public.hr_requests where category = 'leave' and leave_type = 'sick' loop
    update public.hr_requests set category = 'sick_leave' where id = r.id;
    perform public.req_event(r.id, 'category_migrated', r.status, r.status,
      'Μεταφορά στην κατηγορία «Αναρρωτική Άδεια» (έκδοση 3.1)', jsonb_build_object('from', 'leave', 'to', 'sick_leave'), true, 'system');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
select public.req_migrate_sick();

-- ─────────────── 9. Αναθεωρήσεις ημερομηνιών εκκρεμούς αιτήματος ───────────────
alter table public.hr_requests add column if not exists date_revision int not null default 1;
create table if not exists public.hr_request_revisions (
  id             bigserial primary key,
  request_id     uuid not null references public.hr_requests(id) on delete cascade,
  rev_no         int not null,
  start_date     date,
  end_date       date,
  days_requested numeric(5,1),
  leave_requested numeric(6,2),
  leave_excess   numeric(6,2),
  changed_by     text not null,
  changed_at     timestamptz not null default now(),
  reason         text,
  unique (request_id, rev_no)
);
alter table public.hr_request_revisions enable row level security;
create policy rev_read on public.hr_request_revisions for select to authenticated
  using (exists (select 1 from public.hr_requests r where r.id = request_id and public.can_see_store(r.store) and public.has_perm('requests.view')));


-- Ειδοποίηση των αρμόδιων για απόφαση (HR / ΓΔ μέσα στο πεδίο τους)
create or replace function public.notify_deciders(p_request uuid, p_kind text, p_title text) returns int
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_n int;
begin
  select * into r from public.hr_requests where id = p_request;
  if not found then return 0; end if;
  insert into public.notifications(user_email, request_id, kind, title)
  select u.email, r.id, p_kind, left(p_title, 300)
    from public.app_users u join public.role_scopes s on s.role = u.role
   where u.active and public.role_has_perm(u.role, 'requests.decide') and public.role_has_perm(u.role, 'requests.view')
     and (s.scope = 'all' or (s.scope = 'own_store' and u.store = r.store))
     and u.email is distinct from public.current_email();
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.req_change_dates(p_id uuid, p_start date, p_end date, p_days numeric, p_reason text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; n public.hr_requests; v_reason text := trim(coalesce(p_reason, ''));
begin
  perform public.require_perm('requests.create');
  r := public.req_lock(p_id, p_version);
  if not public.employee_in_scope(r.employee_code) then raise exception 'Το αίτημα δεν βρέθηκε στο πεδίο σας.'; end if;
  if not public.is_leave_cat(r.category) then raise exception 'Η αλλαγή ημερομηνιών αφορά αιτήματα άδειας.'; end if;
  if r.status not in ('submitted','under_review','needs_info','awaiting_gm') then
    raise exception 'Η αλλαγή πριν από την έγκριση αφορά εκκρεμή αιτήματα. Για εγκεκριμένη άδεια χρησιμοποιήστε «Αλλαγή ημερομηνιών» (νέα έγκριση).';
  end if;
  if length(v_reason) < 5 then raise exception 'Γράψτε τον λόγο της αλλαγής.'; end if;
  if p_start is null or p_end is null or p_end < p_start then raise exception 'Μη έγκυρο διάστημα.'; end if;
  if p_days is null or p_days <= 0 or p_days > (p_end - p_start + 1) then
    raise exception 'Οι ημέρες άδειας δεν μπορούν να υπερβαίνουν τις ημερολογιακές ημέρες του διαστήματος (%).', (p_end - p_start + 1);
  end if;
  if p_start = r.start_date and p_end = r.end_date and p_days = r.days_requested then raise exception 'Οι ημερομηνίες δεν άλλαξαν.'; end if;
  if not exists (select 1 from public.hr_request_revisions where request_id = r.id) then
    insert into public.hr_request_revisions(request_id, rev_no, start_date, end_date, days_requested, leave_requested, leave_excess, changed_by, changed_at, reason)
    values (r.id, 1, r.start_date, r.end_date, r.days_requested, r.leave_requested, r.leave_excess,
            coalesce(r.submitted_by, r.created_by), coalesce(r.submitted_at, r.created_at), 'Αρχική υποβολή');
  end if;
  update public.hr_requests set start_date = p_start, end_date = p_end, days_requested = p_days,
         date_revision = date_revision + 1, version = version + 1, updated_at = now()
   where id = r.id;
  perform public.leave_on_submit(r.id);   -- ξανά: έλεγχος διπλών και αναλογίας για τις νέες ημερομηνίες
  select * into n from public.hr_requests where id = r.id;
  insert into public.hr_request_revisions(request_id, rev_no, start_date, end_date, days_requested, leave_requested, leave_excess, changed_by, reason)
  values (n.id, n.date_revision, n.start_date, n.end_date, n.days_requested, n.leave_requested, n.leave_excess, public.current_email(), v_reason);
  perform public.req_event(r.id, 'dates_revised', r.status, r.status, v_reason,
    jsonb_build_object('revision', n.date_revision, 'from', jsonb_build_object('start', r.start_date, 'end', r.end_date, 'days', r.days_requested),
                       'to', jsonb_build_object('start', n.start_date, 'end', n.end_date, 'days', n.days_requested)));
  perform public.notify_deciders(r.id, 'dates_revised', 'Νέες ημερομηνίες (αναθεώρηση ' || n.date_revision || '): ' || r.employee_name
    || ' ' || to_char(n.start_date, 'DD/MM/YYYY') || '–' || to_char(n.end_date, 'DD/MM/YYYY') || ' (' || r.ref || ')');
  return jsonb_build_object('ok', true, 'version', n.version, 'revision', n.date_revision);
end $$;

-- ─────────────── 10. Απόφαση με άλλες ημερομηνίες / μόνο συγκεκριμένες ημέρες ───────────────
alter table public.hr_decisions
  add column if not exists requested_start date,
  add column if not exists requested_end   date,
  add column if not exists requested_days  numeric(5,1),
  add column if not exists date_revision   int,
  add column if not exists diff_reason     text,
  add column if not exists approved_dates  jsonb;

drop function if exists public.leave_plan(text, date, date, text, jsonb, uuid[]);
drop function if exists public.leave_preview(text, date, date, text, uuid);

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
    -- Επιλογές Α..ΙΒ (έως 12)
    v_opts := '[]'::jsonb; v_gap := false;
    if v_err is null then
      for i in 1..12 loop
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

create or replace function public.leave_plan(p_code text, p_start date, p_end date, p_leave_type text, p_days jsonb default null, p_exclude uuid[] default '{}', p_include date[] default null)
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
  if p_include is not null and exists (select 1 from unnest(p_include) x where x < p_start or x > p_end) then
    raise exception 'Οι εγκεκριμένες ημέρες πρέπει να είναι μέσα στο διάστημα.';
  end if;
  d := p_start;
  while d <= p_end loop
    if p_include is not null and not (d = any(p_include)) then d := d + 1; continue; end if;
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

create or replace function public.leave_preview(p_code text, p_start date, p_end date, p_leave_type text, p_request uuid default null, p_include date[] default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_plan jsonb; v_excl uuid[]; v_sick jsonb; r public.hr_requests; v_days date[];
begin
  if not (public.has_perm('leave.view') or public.has_perm('requests.view')) or not public.employee_in_scope(p_code) then
    raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.';
  end if;
  if p_request is not null then select * into r from public.hr_requests where id = p_request; end if;
  v_excl := array_remove(array[p_request, r.original_request_id], null);
  v_plan := public.leave_plan(p_code, p_start, p_end, coalesce(p_leave_type, 'annual'), null, v_excl, p_include);
  if p_leave_type = 'sick' then
    select array_agg(g::date) into v_days from generate_series(p_start, p_end, interval '1 day') g;
    v_sick := public.sick_status(p_code, p_end, v_days);
  end if;
  return v_plan || jsonb_build_object('conflicts', public.leave_conflicts(p_code, p_start, p_end, v_excl),
                                      'balance', public.leave_balance_calc(p_code, p_start), 'sick', v_sick);
end $$;

create or replace function public.leave_conflicts(p_code text, p_start date, p_end date, p_exclude uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(distinct jsonb_build_object('ref', r.ref, 'id', r.id, 'status', r.status)), '[]'::jsonb)
    from public.hr_requests r
   where r.employee_code = p_code and r.category in ('leave','sick_leave','leave_change') and not (r.id = any(coalesce(p_exclude, '{}')))
     and (
       (r.status in ('submitted','under_review','needs_info','awaiting_gm') and r.start_date <= p_end and r.end_date >= p_start)
       or exists (select 1 from public.leave_days d where d.request_id = r.id and d.status = 'active' and d.day between p_start and p_end))
$$;

create or replace function public.leave_check(p_request uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.hr_requests; v_type text;
begin
  select * into r from public.hr_requests where id = p_request;
  if not found or not public.can_see_store(r.store) or not (public.has_perm('requests.view') or public.has_perm('leave.view')) then
    raise exception 'Το αίτημα δεν βρέθηκε.';
  end if;
  if r.category not in ('leave','sick_leave','leave_change') or r.start_date is null then return null; end if;
  v_type := coalesce(r.leave_type, (select leave_type from public.hr_requests where id = r.original_request_id));
  return public.leave_preview(r.employee_code, r.start_date, r.end_date, v_type, r.id)
    || jsonb_build_object('active_days', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'charge', d.charge, 'chargeable', d.chargeable) order by d.day), '[]')
                                            from public.leave_days d where d.request_id = r.id and d.status = 'active'),
                          'original', case when r.original_request_id is not null then (select jsonb_build_object('id', o.id, 'ref', o.ref, 'start', o.start_date, 'end', o.end_date)
                                                                                         from public.hr_requests o where o.id = r.original_request_id) end);
end $$;

create or replace function public.leave_change_init(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; o public.hr_requests;
begin
  select * into r from public.hr_requests where id = p_id;
  begin select * into o from public.hr_requests where id = nullif(p->>'original_request_id', '')::uuid;
  exception when others then raise exception 'Επιλέξτε την εγκεκριμένη άδεια που αλλάζει.'; end;
  if o.id is null or not public.is_leave_cat(o.category) or o.employee_code <> r.employee_code then raise exception 'Επιλέξτε την εγκεκριμένη άδεια που αλλάζει.'; end if;
  if o.status not in ('approved','completed') or not exists (select 1 from public.leave_days where request_id = o.id and status = 'active') then
    raise exception 'Αλλάζουν ημερομηνίες μόνο σε εγκεκριμένη άδεια με ενεργές ημέρες.';
  end if;
  update public.hr_requests set original_request_id = o.id, leave_type = o.leave_type, leave_type_label = o.leave_type_label,
         entry_mode = 'manager_record' where id = p_id;
end $$;

create or replace function public.leave_on_submit(p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; o public.hr_requests; v_conf jsonb; v_plan jsonb; v_type text;
begin
  select * into r from public.hr_requests where id = p_request;
  if r.category not in ('leave','sick_leave','leave_change') then return; end if;
  if r.category = 'leave_change' then
    select * into o from public.hr_requests where id = r.original_request_id;
    if not found or not public.is_leave_cat(o.category) or o.employee_code <> r.employee_code then raise exception 'Επιλέξτε την εγκεκριμένη άδεια που αλλάζει.'; end if;
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

create or replace function public.req_validate(r public.hr_requests) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if r.process = 'employee' then
    if r.entry_mode = 'employee_fill' and coalesce(r.written_by, '') not like 'employee:%' then
      raise exception 'Ο εργαζόμενος δεν έχει ολοκληρώσει ακόμη τη συμπλήρωση.';
    end if;
    if length(trim(coalesce(r.body, ''))) < 10 then raise exception 'Συμπληρώστε το κείμενο του αιτήματος.'; end if;
  end if;
  if public.is_leave_cat(r.category) then
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

create or replace function public.req_forward_gm(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, p_version);
  if public.req_flow(r.category) <> 'gm' and not (r.category in ('leave','sick_leave','leave_change') and coalesce(r.leave_excess, 0) > 0) then
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
  v_plan := public.leave_plan(r.employee_code, p_start, p_end, v_type, p->'days', v_excl,
    case when jsonb_typeof(p->'include') = 'array' then coalesce((select array_agg(x::date) from jsonb_array_elements_text(p->'include') x), '{}'::date[]) end);
  if jsonb_array_length(v_plan->'days') = 0 then raise exception 'Επιλέξτε τουλάχιστον μία ημέρα για έγκριση.'; end if;
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

create or replace function public.req_decide(p_id uuid, p_outcome text, p jsonb, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_role(array['owner','hr']);
  r public.hr_requests; v_flow text; v_rev boolean; v_reason public.reject_reasons;
  v_prev bigint; v_new bigint; v_to text; v_msg text := trim(coalesce(p->>'message',''));
  v_start date; v_end date; v_days numeric; v_draft text; v_plan jsonb; v_diff boolean := false; v_dates jsonb;
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

  if p_outcome = 'approve' and r.category in ('leave','sick_leave','leave_change') then
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
    if not (v_plan->>'annual')::boolean and jsonb_typeof(p->'include') = 'array' then v_days := jsonb_array_length(v_plan->'days'); end if;
    if v_days is null or v_days <= 0 or v_days > (v_end - v_start + 1) then raise exception 'Μη έγκυρος αριθμός εγκεκριμένων ημερών.'; end if;
    select coalesce(jsonb_agg(x->'day' order by x->>'day'), '[]'::jsonb) into v_dates from jsonb_array_elements(v_plan->'days') x;
    -- Διαφοροποίηση από το αίτημα (άλλες ημερομηνίες, λιγότερες ημέρες): υποχρεωτική αιτιολογία
    v_diff := v_start is distinct from r.start_date or v_end is distinct from r.end_date or v_days is distinct from r.days_requested
              or jsonb_array_length(v_dates) < (v_end - v_start + 1);
    if r.category <> 'leave_change' and v_diff and length(trim(coalesce(p->>'diff_reason', ''))) < 5 then
      raise exception 'Οι εγκεκριμένες ημέρες διαφέρουν από τις αιτούμενες· γράψτε αιτιολογία διαφοροποίησης.';
    end if;
  end if;

  if p_outcome = 'reject' then
    select * into v_reason from public.reject_reasons where code = p->>'reason_code' and active;
    if not found then raise exception 'Επιλέξτε λόγο απόρριψης.'; end if;
    if public.is_leave_cat(r.category) and v_reason.leave_types is not null and not (r.leave_type = any(v_reason.leave_types)) then
      raise exception 'Ο λόγος «%» δεν εφαρμόζεται σε %.', v_reason.label, r.leave_type_label;
    end if;
    if not public.is_leave_cat(r.category) and not v_reason.for_other then raise exception 'Ο λόγος «%» αφορά μόνο άδειες.', v_reason.label; end if;
    if length(trim(coalesce(p->>'reason_text',''))) < 10 then raise exception 'Γράψτε συγκεκριμένη αιτιολογία (τουλάχιστον 10 χαρακτήρες).'; end if;
  end if;
  if p_outcome = 'needs_info' and length(trim(coalesce(p->>'info',''))) < 3 then raise exception 'Γράψτε ποια στοιχεία απαιτούνται.'; end if;

  update public.hr_decisions set superseded_at = now() where request_id = p_id and superseded_at is null returning id into v_prev;
  insert into public.hr_decisions(request_id, outcome, decided_by, decided_role, reason_code, reason_label, reason_text, message,
         template_version_id, approved_start, approved_end, approved_days, alternative, info_requested, supersedes, is_revision, leave_days_json, overdraw_days, overdraw_available,
         requested_start, requested_end, requested_days, date_revision, diff_reason, approved_dates)
  values (p_id, p_outcome, public.current_email(), v_role,
          case when p_outcome = 'reject' then v_reason.code end, case when p_outcome = 'reject' then v_reason.label end,
          case when p_outcome = 'reject' then trim(p->>'reason_text') end, v_msg,
          nullif(p->>'template_version_id','')::bigint, v_start, v_end, v_days,
          case when p_outcome = 'reject' then coalesce(nullif(trim(p->>'alternative'),''), 'Προς συνεννόηση') end,
          case when p_outcome = 'needs_info' then trim(p->>'info') end, v_prev, v_rev, v_plan->'days', nullif((v_plan->>'excess')::numeric, 0),
          case when (v_plan->>'excess')::numeric > 0 then (v_plan->>'available')::numeric end,
          r.start_date, r.end_date, r.days_requested, r.date_revision,
          case when v_diff then left(trim(p->>'diff_reason'), 2000) end, v_dates)
  returning id into v_new;
  if r.category in ('leave','sick_leave','leave_change') and p_outcome <> 'approve' then
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

create or replace function public.notify_on_decision() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  select * into r from public.hr_requests where id = new.request_id;
  perform public.notify_request(new.request_id, 'decision_' || new.outcome,
    case new.outcome when 'approve' then 'Εγκρίθηκε' when 'reject' then 'Δεν εγκρίθηκε' else 'Ζητούνται διευκρινίσεις' end
    || case when new.is_revision then ' (αναθεώρηση)' else '' end || ': ' || public.req_category_label(r.category) || ' — ' || r.employee_name || ' (' || r.ref || ')'
    || case when new.outcome = 'approve' and new.approved_start is not null and r.category in ('leave','sick_leave','leave_change') then
         ' · τελικές ημερομηνίες ' || case when jsonb_array_length(coalesce(new.approved_dates, '[]')) between 1 and 12
              and jsonb_array_length(new.approved_dates) < (new.approved_end - new.approved_start + 1)
           then (select string_agg(to_char(x::date, 'DD/MM'), ', ' order by x::date) from jsonb_array_elements_text(new.approved_dates) x) || '/' || to_char(new.approved_end, 'YYYY')
           else to_char(new.approved_start, 'DD/MM') || '–' || to_char(new.approved_end, 'DD/MM/YYYY') end
         || coalesce(' (' || jsonb_array_length(new.approved_dates) || ' ημέρες)', '')
         || case when new.diff_reason is not null then ' — διαφέρουν από τις αιτούμενες' else '' end else '' end);
  if new.is_revision then
    update public.hr_requests set impl_claimed_by = null, impl_claimed_at = null where id = new.request_id;
  end if;
  return new;
end $$;


revoke all on public.hr_request_revisions from anon, authenticated;
grant select on public.hr_request_revisions to authenticated;
revoke execute on all functions in schema public from public, anon;
grant execute on function public.req_change_dates(uuid, date, date, numeric, text, int),
  public.leave_preview(text, date, date, text, uuid, date[]) to authenticated;
revoke execute on function public.notify_deciders(uuid, text, text), public.req_sick_category(), public.req_migrate_sick(),
  public.leave_on_decision(uuid, text, jsonb, text, date, date, boolean), public.leave_on_submit(uuid), public.leave_change_init(uuid, jsonb) from authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
