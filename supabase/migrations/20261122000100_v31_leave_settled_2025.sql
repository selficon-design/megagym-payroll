-- Έκδοση 3.1 · Αρχική ρύθμιση βάσεων άδειας: οι κανονικές άδειες του 2025 και όλων των προηγούμενων ετών θεωρούνται
-- τακτοποιημένες εκτός εφαρμογής (απόφαση Γενικής Διεύθυνσης, 21/11/2026).
--  • Κανένα διαθέσιμο υπόλοιπο, μεταφορά (έως 31/03) ή εκκρεμότητα εκκαθάρισης από έτη ≤ 2025.
--  • Η καταχώριση ημερομηνίας πρόσληψης ή ετήσιας βάσης ΔΕΝ ξαναδημιουργεί αυτά τα υπόλοιπα (ο κανόνας είναι στον υπολογισμό).
--  • Το 2026 δεν μηδενίζεται· η προϋπηρεσία (ημερομηνία πρόσληψης) για τη βάση άδειας μένει ως έχει.
--  • ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: καμία διαγραφή αδειών, εγκρίσεων, υπογραφών, εκκαθαρίσεων ή ιστορικού· καμία εικονική πληρωμή/αίτηση.
--    Όσες ημέρες άδειας του 2026 είχαν χρεωθεί στο υπόλοιπο 2025 (Ιαν.–Μάρ.) λογίζονται πλέον στο 2026 (οι γραμμές μένουν ως έχουν).

create table if not exists public.leave_settings (
  id                    int primary key default 1 check (id = 1),
  settled_through_year  int check (settled_through_year between 2000 and 2100),
  decided_by            text,
  decided_at            timestamptz,
  note                  text
);
insert into public.leave_settings(id, settled_through_year, decided_by, decided_at, note)
values (1, 2025, 'Γενική Διεύθυνση', now(), 'Κανονικές άδειες 2025 και προηγούμενων ετών: ληφθείσες ή τακτοποιημένες εκτός εφαρμογής')
on conflict (id) do nothing;
alter table public.leave_settings enable row level security;
revoke all on public.leave_settings from anon, authenticated;

create or replace function public.leave_settled_through() returns int language sql stable security definer set search_path = public as $$
  select settled_through_year from public.leave_settings where id = 1
$$;
create or replace function public.leave_year_settled(p_year int) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(p_year <= (select settled_through_year from public.leave_settings where id = 1), false)
$$;

create or replace function public.leave_year_balance(p_code text, p_year int, p_as_of date, p_exclude uuid[] default '{}') returns numeric
language sql stable security definer set search_path = public as $$
  -- Έτη έως και το «τακτοποιημένο έτος» (απόφαση ΓΔ): κανένα υπόλοιπο, μεταφορά ή εκκαθάριση
  select case when public.leave_year_settled(p_year) then 0::numeric else
         case when p_year >= extract(year from p_as_of)::int
              then public.leave_accrued(p_code, p_year, p_as_of)
              else public.leave_accrued(p_code, p_year, make_date(p_year, 12, 31)) - public.leave_settled(p_code, p_year) end
         + public.leave_adjusted(p_code, p_year) - public.leave_charged(p_code, p_year, null, p_exclude) end
$$;

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
    'settled_through', public.leave_settled_through(),
    'prev_settled_outside', public.leave_year_settled(y - 1),
    'prev_state', case when public.leave_year_settled(y - 1) then 'settled_outside' when v_prev <= 0 then 'none' when p_as_of <= v_deadline then 'usable' else 'to_settle' end);
end $$;

create or replace function public.leave_settle(p_code text, p_year int, p_days numeric, p_amount numeric, p_paid_on date, p_doc jsonb, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_out numeric; v_id bigint;
begin
  perform public.require_perm('leave.settle');
  select * into e from public.employees where code = p_code for update;   -- σειριοποίηση: αποτρέπει διπλή πληρωμή από ταυτόχρονα πατήματα
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if public.leave_year_settled(p_year) then
    raise exception 'Οι άδειες του % έχουν τακτοποιηθεί εκτός εφαρμογής (απόφαση Γενικής Διεύθυνσης)· δεν καταχωρίζεται εκκαθάριση.', p_year;
  end if;
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

create or replace function public.leave_adjust(p_code text, p_year int, p_new_value numeric, p_as_of date, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_prev numeric; v_id bigint; v_as_of date := coalesce(p_as_of, public.athens_today());
begin
  perform public.require_perm('leave.adjust');
  select * into e from public.employees where code = p_code for update;
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'Γράψτε αιτιολογία διόρθωσης (τουλάχιστον 5 χαρακτήρες).'; end if;
  if p_new_value is null or abs(p_new_value) > 400 then raise exception 'Μη έγκυρη νέα τιμή.'; end if;
  if public.leave_year_settled(p_year) then
    raise exception 'Οι άδειες του % έχουν τακτοποιηθεί εκτός εφαρμογής (απόφαση Γενικής Διεύθυνσης)· το υπόλοιπο δεν διορθώνεται.', p_year;
  end if;
  if p_year > extract(year from v_as_of)::int then raise exception 'Το έτος δεν μπορεί να είναι μετά την ημερομηνία αναφοράς.'; end if;
  v_prev := round(public.leave_year_balance(p_code, p_year, v_as_of), 2);
  if v_prev = round(p_new_value, 2) then raise exception 'Η νέα τιμή είναι ίδια με την τρέχουσα (%).', v_prev; end if;
  insert into public.leave_adjustments(employee_code, leave_year, as_of, prev_value, new_value, delta, reason, created_by, created_role)
  values (p_code, p_year, v_as_of, v_prev, round(p_new_value, 2), round(p_new_value, 2) - v_prev, trim(p_reason), public.current_email(), public.my_role())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'prev', v_prev, 'new', round(p_new_value, 2));
end $$;

-- Ημέρες άδειας από 1/1/2026 που είχαν χρεωθεί στο υπόλοιπο τακτοποιημένου έτους (π.χ. 2025, Ιαν.–Μάρ.): οι γραμμές
-- χρέωσης ΔΕΝ αλλάζουν (το ιστορικό είναι αμετάβλητο)· στον υπολογισμό λογίζονται στο έτος της ημέρας.
create or replace function public.leave_charge_year(p_charge_year int, p_day date) returns int
language sql stable security definer set search_path = public as $$
  select case when public.leave_year_settled(p_charge_year) and not public.leave_year_settled(extract(year from p_day)::int)
              then extract(year from p_day)::int else p_charge_year end
$$;

create or replace function public.leave_charged(p_code text, p_year int, p_upto date default null, p_exclude uuid[] default '{}') returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(c.amount), 0) from public.leave_charges c join public.leave_days d on d.id = c.leave_day_id
   where d.employee_code = p_code and d.status = 'active' and public.leave_charge_year(c.leave_year, d.day) = p_year
     and (p_upto is null or d.day <= p_upto) and not (d.request_id = any(coalesce(p_exclude, '{}')))
$$;

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
                     'years', (select jsonb_agg(jsonb_build_object('year', public.leave_charge_year(c.leave_year, d.day), 'amount', c.amount)) from public.leave_charges c where c.leave_day_id = d.id))
                     order by d.day desc), '[]')
               from public.leave_days d join public.hr_requests r on r.id = d.request_id left join public.leave_types lt on lt.code = d.leave_type
              where d.employee_code = p_code and d.day >= make_date(extract(year from v_as_of)::int - 1, 1, 1)));
end $$;

-- Καμία εκκρεμότητα εκκαθάρισης για τακτοποιημένα έτη (ο υπολογισμός δίνει 0· ρητός έλεγχος για σαφήνεια)
create or replace function public.leave_to_settle(p_year int default null)
returns table (employee_code text, employee_name text, store text, leave_year int, outstanding numeric, settled numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_today date := public.athens_today(); v_y int;
begin
  if not (public.has_perm('leave.settle') or public.has_perm('leave.view')) then raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.'; end if;
  v_y := coalesce(p_year, case when v_today > make_date(extract(year from v_today)::int, 3, 31) then extract(year from v_today)::int - 1 else extract(year from v_today)::int - 2 end);
  if v_today <= make_date(v_y + 1, 3, 31) or public.leave_year_settled(v_y) then return; end if;
  return query
    select e.code, e.first || ' ' || e.last, e.store, v_y, round(public.leave_year_balance(e.code, v_y, v_today), 2), public.leave_settled(e.code, v_y)
      from public.employees e
     where public.can_see_store(e.store)
       and (exists (select 1 from public.leave_entitlements x where x.employee_code = e.code and x.superseded_at is null)
            or exists (select 1 from public.leave_adjustments x where x.employee_code = e.code and x.leave_year = v_y))
       and round(public.leave_year_balance(e.code, v_y, v_today), 2) > 0
     order by e.store, e.last, e.first;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.leave_settled_through(), public.leave_year_settled(int), public.leave_charge_year(int, date) to authenticated;
grant execute on function public.statlink_info(text), public.statlink_submit(text, jsonb) to anon;
grant execute on function public.cashlink_info(text), public.cashlink_submit(text, jsonb) to anon;   -- εφαρμογή «Ταμεία»
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
