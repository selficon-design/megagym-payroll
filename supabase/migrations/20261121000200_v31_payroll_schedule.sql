-- Έκδοση 3.1 · Μισθοδοσία & πρόγραμμα
--  3. Καμία υποχρέωση μισθοδοσίας πριν από την πρόσληψη ή μετά την αποχώρηση (μετρούν οι μήνες με απασχόληση).
--  4. Αποχωρήσαντες: εκτός μελλοντικού προγράμματος· οι βάρδιές τους μετά την αποχώρηση → «χρειάζονται κάλυψη».
--  5. «Ρεπό» ως ρητή ένδειξη (χωρίς ώρες, χωρίς κάλυψη).
--  6. «Διαγραφή ωραρίου» (ανάθεσης) διακριτή από την «Απόκρυψη» έτοιμου ωραρίου· διαγραφή έτοιμου ωραρίου χωρίς επίπτωση στις αναθέσεις.
--  7. Managers / assistant managers στη Ρεσεψιόν του καταστήματός τους (πρόγραμμα & ημερολόγιο αδειών).
--  8. Ειδοποίηση λογιστηρίου για κάθε αλλαγή οριστικοποιημένου προγράμματος (όχι στη ΓΔ), με ανάγνωση ανά χρήστη.
-- 12. Βάρδιες μετά τα μεσάνυχτα και «Προγραμματισμένες ώρες μετά τις 22:00» (χωριστά από παρουσίες/αποδοχές).
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο νέες στήλες/πίνακες/συναρτήσεις· καμία διαγραφή δεδομένων.

-- ═══════════════ 3. Μισθοδοσία μόνο για μήνες με απασχόληση ═══════════════
create or replace function public.emp_employed_in_month(p_hire date, p_leave date, p_month text) returns boolean
language sql immutable as $$
  select (p_hire is null or p_hire <= (to_date(p_month || '-01', 'YYYY-MM-DD') + interval '1 month' - interval '1 day')::date)
     and (p_leave is null or p_leave >= to_date(p_month || '-01', 'YYYY-MM-DD'))
$$;

drop function if exists public.month_status(text);
create function public.month_status(p_month text)
returns table (
  code text, first text, last text, store text, company text, emp_status text,
  declaration_id uuid, status text, amount numeric, period text, end_date date,
  signed_at timestamptz, signer text, prepared_at timestamptz,
  hire_date date, leave_date date, employment text
) language sql stable security invoker set search_path = public as $$
  -- «missing» (εκκρεμότητα) μόνο για όσους απασχολήθηκαν μέσα στον μήνα· οι δηλώσεις που υπάρχουν (υπογεγραμμένες ή προς
  -- υπογραφή) εμφανίζονται ΠΑΝΤΑ — αν είναι εκτός περιόδου απασχόλησης επισημαίνονται («outside»), δεν κρύβονται.
  select e.code, e.first, e.last, e.store, e.company, e.status,
         d.id, coalesce(d.status, 'missing'), d.amount, d.period, d.end_date, d.signed_at, d.signer, d.prepared_at,
         e.hire_date, e.leave_date,
         case when not public.emp_employed_in_month(e.hire_date, e.leave_date, p_month) then 'outside'
              when e.hire_date is not null and to_char(e.hire_date, 'YYYY-MM') = p_month then 'hire'
              when e.leave_date is not null and to_char(e.leave_date, 'YYYY-MM') = p_month then 'leave' end
    from public.employees e
    left join public.declarations d on d.employee_code = e.code and d.month = p_month and d.status <> 'voided'
   where d.id is not null
      or (public.emp_employed_in_month(e.hire_date, e.leave_date, p_month) and (e.status = 'Ενεργός' or e.leave_date is not null))
   order by e.store, e.last, e.first
$$;

-- Προετοιμασία: δεκτοί όσοι απασχολήθηκαν στον μήνα (και όσοι αποχώρησαν μέσα στον μήνα)
create or replace function public.prepare_declarations(p_month text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
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
    if not public.emp_employed_in_month(e.hire_date, e.leave_date, p_month) then
      v_skipped := v_skipped || jsonb_build_object('code', e.code, 'reason',
        case when e.hire_date is not null and e.hire_date > v_last then 'Εκτός περιόδου απασχόλησης (πρόσληψη ' || to_char(e.hire_date, 'DD/MM/YYYY') || ')'
             else 'Εκτός περιόδου απασχόλησης (αποχώρηση ' || to_char(e.leave_date, 'DD/MM/YYYY') || ')' end); continue;
    end if;
    if e.status <> 'Ενεργός' and e.leave_date is null then
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
      v_end := coalesce(nullif(trim(r ->> 'end_date'), '')::date, least(v_last, coalesce(e.leave_date, v_last)));
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

-- ═══════════════ 7. Ρόλος καταστήματος (manager / assistant manager) ═══════════════
alter table public.employees add column if not exists store_role text check (store_role in ('manager','assistant_manager'));
comment on column public.employees.store_role is 'Manager / assistant manager του καταστήματος: εμφανίζεται και στη Ρεσεψιόν (πρόγραμμα, ημερολόγιο αδειών)';
create or replace function public.store_role_label(p text) returns text language sql immutable as $$
  select case p when 'manager' then 'Manager' when 'assistant_manager' then 'Assistant manager' end
$$;
create or replace function public.is_reception(p_specialty text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.specialties where name = p_specialty and stat_kind = 'reception')
$$;

-- ═══════════════ 5/6/12. Ωράρια: ρεπό, διαγραφή, βάρδιες μετά τα μεσάνυχτα ═══════════════
alter table public.schedule_overrides add column if not exists kind text not null default 'shift' check (kind in ('shift','off','deleted'));
alter table public.schedule_changes drop constraint if exists schedule_changes_change_type_check;
alter table public.schedule_changes add constraint schedule_changes_change_type_check
  check (change_type in ('permanent','temporary','temporary_cleared','finalize','transfer','deleted','off'));
alter table public.shift_templates add column if not exists deleted_at timestamptz, add column if not exists deleted_by text;

-- Λήξη διαστήματος σε λεπτά από τα μεσάνυχτα της ημέρας έναρξης: «17:00–01:30» λήγει στο 1530 (επόμενη ημέρα).
create or replace function public.sched_end(p_start text, p_end text) returns int language sql immutable as $$
  select case when public.sched_min(p_end) <= public.sched_min(p_start) then public.sched_min(p_end) + 1440 else public.sched_min(p_end) end
$$;

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
    if b = a then raise exception 'Η λήξη (%) δεν μπορεί να είναι ίδια με την έναρξη.', b; end if;
    if b = '24:00' then b := '00:00'; end if;            -- 24:00 ≡ μεσάνυχτα (λήξη)
    if public.sched_end(a, b) - public.sched_min(a) > 960 then
      raise exception 'Το διάστημα «%–%» ξεπερνά τις 16 ώρες. Για βάρδια μετά τα μεσάνυχτα γράψτε π.χ. 17:00–01:30.', a, s->>1;
    end if;
    -- λήξη πριν από την έναρξη = βάρδια που τελειώνει μετά τα μεσάνυχτα (την επόμενη ημέρα)
    v_out := v_out || jsonb_build_array(jsonb_build_array(a, b));
  end loop;
  return (select coalesce(jsonb_agg(x order by x->>0, x->>1), '[]'::jsonb) from jsonb_array_elements(v_out) x);
end $$;

-- Διάρκεια χωρίς διπλομέτρηση επικαλύψεων (και μετά τα μεσάνυχτα)
create or replace function public.sched_minutes(p jsonb) returns int
language plpgsql immutable as $$
declare s jsonb; v_total int := 0; v_end int := -1; a int; b int;
begin
  for s in select x from jsonb_array_elements(coalesce(p, '[]'::jsonb)) x order by public.sched_min(x->>0) loop
    a := public.sched_min(s->>0); b := public.sched_end(s->>0, s->>1);
    if a >= v_end then v_total := v_total + (b - a); v_end := b;
    elsif b > v_end then v_total := v_total + (b - v_end); v_end := b; end if;
  end loop;
  return v_total;
end $$;

create or replace function public.sched_overlaps(p jsonb) returns boolean
language sql immutable as $$
  select exists (select 1 from jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality x(a, i)
                   join jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality y(b, j) on j > i
                  where public.sched_min(x.a->>0) < public.sched_end(y.b->>0, y.b->>1) and public.sched_min(y.b->>0) < public.sched_end(x.a->>0, x.a->>1))
$$;

-- Λεπτά μετά τις 22:00: από τις 22:00 έως τη λήξη της βάρδιας (και μετά τα μεσάνυχτα), χωρίς διπλομέτρηση.
-- 17:00–23:30 → 90 · 20:00–02:00 → 240 · σπαστό 18:00–21:00 & 21:30–23:00 → 60.
create or replace function public.sched_night_minutes(p jsonb) returns int
language plpgsql immutable as $$
declare s record; v_total int := 0; v_end int := -1;
begin
  for s in select greatest(public.sched_min(x->>0), 1320) a, public.sched_end(x->>0, x->>1) b from jsonb_array_elements(coalesce(p, '[]'::jsonb)) x
            where public.sched_end(x->>0, x->>1) > 1320 order by 1 loop
    if s.a >= v_end then v_total := v_total + (s.b - s.a); v_end := s.b;
    elsif s.b > v_end then v_total := v_total + (s.b - v_end); v_end := s.b; end if;
  end loop;
  return v_total;
end $$;

create or replace function public.sched_day(p_code text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.schedule_overrides; p public.schedule_patterns; v_seg jsonb;
begin
  select * into o from public.schedule_overrides where employee_code = p_code and day = p_day and status = 'active';
  if found then return jsonb_build_object('segments', o.segments, 'source', 'temporary', 'store', o.store, 'override_id', o.id, 'reason', o.reason,
                                          'kind', case when o.kind = 'shift' and jsonb_array_length(o.segments) = 0 then 'off' else o.kind end); end if;
  select * into p from public.schedule_patterns where employee_code = p_code and status = 'active' and valid_from <= p_day
     and (valid_to is null or p_day <= valid_to) order by valid_from desc limit 1;
  if found then
    v_seg := coalesce(p.days->(extract(isodow from p_day)::int)::text, '[]'::jsonb);
    return jsonb_build_object('segments', v_seg, 'source', 'pattern', 'store', p.store, 'pattern_id', p.id,
                              'kind', case when jsonb_array_length(v_seg) = 0 then 'off' else 'shift' end);
  end if;
  return null;
end $$;

-- Προσωρινή αλλαγή: ωράριο ή «Ρεπό» (p_kind = 'off')
drop function if exists public.sched_set_temp(text, date[], jsonb, text);
create function public.sched_set_temp(p_code text, p_days date[], p_segments jsonb, p_reason text, p_kind text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_kind text := coalesce(nullif(p_kind, ''), 'shift'); v_seg jsonb; d date; v_prev jsonb; v_final boolean;
        v_reason text := nullif(trim(coalesce(p_reason, '')), ''); v_prevs jsonb := '{}'::jsonb;
begin
  e := public.sched_check_emp(p_code);
  if v_kind not in ('shift','off') then raise exception 'Μη έγκυρο είδος.'; end if;
  v_seg := case when v_kind = 'off' then '[]'::jsonb else public.sched_segments(p_segments) end;
  if v_kind = 'shift' and jsonb_array_length(v_seg) = 0 then v_kind := 'off'; end if;
  if coalesce(cardinality(p_days), 0) = 0 then raise exception 'Επιλέξτε ημερομηνίες.'; end if;
  if cardinality(p_days) > 62 then raise exception 'Έως 62 ημέρες σε μία προσωρινή αλλαγή· για μεγαλύτερη περίοδο χρησιμοποιήστε μόνιμη αλλαγή.'; end if;
  if e.leave_date is not null and exists (select 1 from unnest(p_days) x where x > e.leave_date) then
    raise exception 'Ο εργαζόμενος αποχωρεί στις %.', to_char(e.leave_date, 'DD/MM/YYYY');
  end if;
  if e.hire_date is not null and exists (select 1 from unnest(p_days) x where x < e.hire_date) then
    raise exception 'Ο εργαζόμενος προσλαμβάνεται στις %.', to_char(e.hire_date, 'DD/MM/YYYY');
  end if;
  v_final := exists (select 1 from unnest(p_days) x where public.sched_touches_final(e.store, x, x));
  if v_final and coalesce(length(v_reason), 0) < 3 then raise exception 'Το πρόγραμμα έχει οριστικοποιηθεί. Η αιτιολογία της αλλαγής είναι υποχρεωτική.'; end if;
  foreach d in array (select array_agg(distinct x order by x) from unnest(p_days) x) loop
    v_prev := public.sched_day(p_code, d);
    v_prevs := v_prevs || jsonb_build_object(d::text, v_prev->'segments');
    update public.schedule_overrides set status = 'replaced', ended_by = public.current_email(), ended_at = now()
     where employee_code = p_code and day = d and status = 'active';
    insert into public.schedule_overrides(employee_code, store, day, segments, reason, created_by, kind)
    values (p_code, e.store, d, v_seg, v_reason, public.current_email(), v_kind);
  end loop;
  insert into public.schedule_changes(actor, store, employee_code, change_type, affected_from, affected_to, prev_value, new_value, reason, after_finalize)
  values (public.current_email(), e.store, p_code, case when v_kind = 'off' then 'off' else 'temporary' end,
          (select min(x) from unnest(p_days) x), (select max(x) from unnest(p_days) x),
          v_prevs, jsonb_build_object('segments', v_seg, 'days', to_jsonb(p_days), 'kind', v_kind), v_reason, v_final);
  return jsonb_build_object('ok', true, 'days', cardinality(p_days));
end $$;

-- «Διαγραφή ωραρίου»: αφαιρεί την ανάθεση των ημερών (ώρες και κάλυψη ενημερώνονται), με ιστορικό.
-- Δεν σβήνει γραμμές: καταγράφεται ως ενεργή εγγραφή «deleted» πάνω από το σταθερό πρόγραμμα· επαναφορά με «Επαναφορά στο σταθερό».
create or replace function public.sched_delete(p_code text, p_days date[], p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; d date; v_prev jsonb; v_final boolean; v_reason text := nullif(trim(coalesce(p_reason, '')), '');
        v_prevs jsonb := '{}'::jsonb; v_n int := 0;
begin
  e := public.sched_check_emp(p_code);
  if coalesce(cardinality(p_days), 0) = 0 then raise exception 'Επιλέξτε ημερομηνίες.'; end if;
  if cardinality(p_days) > 62 then raise exception 'Έως 62 ημέρες ανά διαγραφή.'; end if;
  v_final := exists (select 1 from unnest(p_days) x where public.sched_touches_final(e.store, x, x));
  if v_final and coalesce(length(v_reason), 0) < 3 then raise exception 'Το πρόγραμμα έχει οριστικοποιηθεί. Η αιτιολογία της διαγραφής είναι υποχρεωτική.'; end if;
  foreach d in array (select array_agg(distinct x order by x) from unnest(p_days) x) loop
    v_prev := public.sched_day(p_code, d);
    if v_prev is null or jsonb_array_length(coalesce(v_prev->'segments', '[]')) = 0 then continue; end if;
    v_prevs := v_prevs || jsonb_build_object(d::text, v_prev->'segments');
    update public.schedule_overrides set status = 'replaced', ended_by = public.current_email(), ended_at = now()
     where employee_code = p_code and day = d and status = 'active';
    insert into public.schedule_overrides(employee_code, store, day, segments, reason, created_by, kind)
    values (p_code, e.store, d, '[]'::jsonb, v_reason, public.current_email(), 'deleted');
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Δεν υπάρχει ωράριο για διαγραφή στις επιλεγμένες ημερομηνίες.'; end if;
  insert into public.schedule_changes(actor, store, employee_code, change_type, affected_from, affected_to, prev_value, new_value, reason, after_finalize)
  values (public.current_email(), e.store, p_code, 'deleted', (select min(x::date) from jsonb_object_keys(v_prevs) x), (select max(x::date) from jsonb_object_keys(v_prevs) x),
          v_prevs, jsonb_build_object('days', (select jsonb_agg(x order by x) from jsonb_object_keys(v_prevs) x), 'segments', '[]'::jsonb), v_reason, v_final);
  return jsonb_build_object('ok', true, 'deleted', v_n);
end $$;

-- Έτοιμα ωράρια: «Απόκρυψη» = μόνο από τη λίστα επιλογών· «Διαγραφή» = αφαίρεση από τη λίστα ρυθμίσεων (με ιστορικό).
-- Καμία από τις δύο δεν αγγίζει αναθέσεις: τα ωράρια αποθηκεύονται στο πρόγραμμα με τις ώρες τους.
create or replace function public.shift_template_delete(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('schedule.settings');
  update public.shift_templates set deleted_at = now(), deleted_by = public.current_email(), active = false where id = p_id and deleted_at is null;
  if not found then raise exception 'Το έτοιμο ωράριο δεν βρέθηκε.'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- ═══════════════ 4/5/7/12. Εβδομαδιαίο πρόγραμμα ═══════════════
create or replace function public.sched_week(p_store text, p_week_start date, p_specialty text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_days date[]; d date; e record; v_emps jsonb := '[]'::jsonb; v_cov jsonb := '{}'::jsonb; s jsonb; v_seg jsonb; v_min int;
        v_planned int; v_leave_min int; v_has_leave boolean; v_leave jsonb; v_pending jsonb; v_departed boolean; v_daymap jsonb; v_terms record;
        v_hours jsonb := '{}'::jsonb; v_open time; v_close time; v_lo int; v_hi int; v_slot int; v_cnt int; v_req int; v_slots jsonb; v_present jsonb;
        v_needs jsonb := '[]'::jsonb; v_wd int; v_inopen boolean; v_kind text; v_carry jsonb; v_prev jsonb; v_counts boolean; v_rec boolean := public.is_reception(p_specialty);
begin
  if not public.has_perm('schedule.view') or not public.can_see_store(p_store) then raise exception 'Δεν έχετε πρόσβαση στο πρόγραμμα του καταστήματος.'; end if;
  if extract(isodow from p_week_start) <> 1 then raise exception 'Η εβδομάδα ξεκινά Δευτέρα.'; end if;
  select array_agg((p_week_start + i)::date order by i) into v_days from generate_series(0, 6) i;
  -- Εργαζόμενοι με στήλη: του καταστήματος ή με πρόγραμμα του καταστήματος στην εβδομάδα, που ΔΕΝ έχουν αποχωρήσει πριν από
  -- την εβδομάδα (οι αποχωρήσαντες εμφανίζονται κανονικά στις παλιές εβδομάδες). Στη Ρεσεψιόν και οι managers / assistant
  -- managers του καταστήματος.
  for e in
    select x.code, x.first, x.last, x.specialty, x.hire_date, x.leave_date, x.store_role from public.employees x
     where (x.store = p_store or exists (select 1 from public.schedule_patterns p where p.employee_code = x.code and p.store = p_store and p.status = 'active'
                                           and p.valid_from <= p_week_start + 6 and (p.valid_to is null or p.valid_to >= p_week_start))
                              or exists (select 1 from public.schedule_overrides o where o.employee_code = x.code and o.store = p_store and o.status = 'active'
                                           and o.day between p_week_start and p_week_start + 6))
       and (p_specialty is null or x.specialty = p_specialty or (v_rec and x.store_role is not null and x.store = p_store))
       and (x.hire_date is null or x.hire_date <= p_week_start + 6)
       and (x.leave_date is null or x.leave_date >= p_week_start)
       and (x.status = 'Ενεργός' or x.leave_date is not null)
     order by (x.store_role is null), x.specialty nulls last, x.last, x.first
  loop
    v_daymap := '{}'::jsonb; v_planned := 0; v_leave_min := 0; v_has_leave := false;
    select * into v_terms from public.work_terms_on(e.code, p_week_start);
    -- ουρά βάρδιας της προηγούμενης ημέρας που περνά τα μεσάνυχτα
    v_prev := public.sched_day(e.code, p_week_start - 1);
    if v_prev is not null and v_prev->>'store' is distinct from p_store then v_prev := null; end if;
    foreach d in array v_days loop
      s := public.sched_day(e.code, d);
      if s is not null and s->>'store' is distinct from p_store then s := null; end if;
      v_seg := coalesce(s->'segments', '[]'::jsonb);
      v_kind := s->>'kind';
      v_min := public.sched_minutes(v_seg);
      select jsonb_build_object('type', ld.leave_type, 'label', lt.label, 'request_id', ld.request_id, 'charge', ld.charge) into v_leave
        from public.leave_days ld left join public.leave_types lt on lt.code = ld.leave_type where ld.employee_code = e.code and ld.day = d and ld.status = 'active';
      select jsonb_build_object('label', coalesce(r.leave_type_label, 'άδεια'), 'request_id', r.id, 'ref', r.ref) into v_pending
        from public.hr_requests r where r.employee_code = e.code and r.category in ('leave','sick_leave','leave_change')
         and r.status in ('submitted','under_review','needs_info','awaiting_gm') and d between r.start_date and r.end_date limit 1;
      v_departed := (e.leave_date is not null and d > e.leave_date) or (e.hire_date is not null and d < e.hire_date);
      v_counts := v_leave is null and not v_departed and v_min > 0;
      if v_leave is not null then v_has_leave := true; v_leave_min := v_leave_min + v_min;
      elsif not v_departed then v_planned := v_planned + v_min; end if;
      if v_min > 0 and (v_leave is not null or v_departed) then
        v_needs := v_needs || jsonb_build_object('employee_code', e.code, 'employee_name', e.first || ' ' || e.last, 'day', d, 'segments', v_seg,
                                                 'why', case when v_departed then 'αποχώρηση' else coalesce(v_leave->>'label', 'άδεια') end);
      end if;
      -- ουρά προηγούμενης ημέρας (00:00 → λήξη), μόνο αν εκείνη η ημέρα μετρά
      v_carry := '[]'::jsonb;
      if v_prev is not null then
        select coalesce(jsonb_agg(jsonb_build_array('00:00', x->>1)), '[]') into v_carry from jsonb_array_elements(v_prev->'segments') x
         where public.sched_end(x->>0, x->>1) > 1440 and x->>1 <> '00:00';
        if exists (select 1 from public.leave_days ld where ld.employee_code = e.code and ld.day = d - 1 and ld.status = 'active')
           or (e.leave_date is not null and d - 1 > e.leave_date) or (e.hire_date is not null and d - 1 < e.hire_date) then v_carry := '[]'::jsonb; end if;
      end if;
      v_daymap := v_daymap || jsonb_build_object(d::text, jsonb_build_object('segments', v_seg, 'source', s->>'source', 'minutes', v_min,
        'kind', v_kind, 'off', v_kind = 'off' and v_leave is null and not v_departed, 'deleted', v_kind = 'deleted',
        'overlap', public.sched_overlaps(v_seg), 'leave', v_leave, 'pending', v_pending, 'departed', v_departed,
        'reason', s->>'reason', 'counts', v_counts, 'carry', v_carry,
        'night_minutes', case when v_counts then public.sched_night_minutes(v_seg) else 0 end));
      v_prev := s;
    end loop;
    v_emps := v_emps || jsonb_build_object('code', e.code, 'name', e.first || ' ' || e.last, 'specialty', e.specialty, 'leave_date', e.leave_date,
      'store_role', e.store_role, 'store_role_label', public.store_role_label(e.store_role),
      'work_week', v_terms.work_week, 'contract_hours', v_terms.weekly_hours, 'planned_hours', round(v_planned / 60.0, 2),
      'leave_hours', round(v_leave_min / 60.0, 2), 'has_leave', v_has_leave,
      'deviation', case when v_terms.weekly_hours is not null then round(v_planned / 60.0 - v_terms.weekly_hours, 2) end, 'days', v_daymap);
  end loop;

  -- Αποχωρήσαντες πριν από την εβδομάδα: χωρίς στήλη και χωρίς κάλυψη· όσες βάρδιες είχαν προγραμματιστεί → «χρειάζονται κάλυψη»
  for e in
    select x.code, x.first, x.last, x.leave_date from public.employees x
     where x.leave_date is not null and x.leave_date < p_week_start and (p_specialty is null or x.specialty = p_specialty)
       and (exists (select 1 from public.schedule_patterns p where p.employee_code = x.code and p.store = p_store and p.status = 'active'
                      and p.valid_from <= p_week_start + 6 and (p.valid_to is null or p.valid_to >= p_week_start))
            or exists (select 1 from public.schedule_overrides o where o.employee_code = x.code and o.store = p_store and o.status = 'active'
                      and o.day between p_week_start and p_week_start + 6))
  loop
    foreach d in array v_days loop
      s := public.sched_day(e.code, d);
      if s is null or s->>'store' is distinct from p_store or jsonb_array_length(coalesce(s->'segments', '[]')) = 0 then continue; end if;
      v_needs := v_needs || jsonb_build_object('employee_code', e.code, 'employee_name', e.first || ' ' || e.last, 'day', d, 'segments', s->'segments',
                                               'why', 'αποχώρηση ' || to_char(e.leave_date, 'DD/MM/YYYY'));
    end loop;
  end loop;

  -- κάλυψη ανά μισάωρο (με τις ουρές βαρδιών μετά τα μεσάνυχτα· καμία διπλομέτρηση ατόμου)
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
      select min(h.opens), max(h.closes) into v_open, v_close from public.store_hours h
       where h.store = p_store and h.weekday = v_wd
         and h.valid_from = (select max(h2.valid_from) from public.store_hours h2 where h2.store = h.store and h2.weekday = h.weekday
                               and h2.specialty is not distinct from h.specialty and h2.valid_from <= d);
    end if;
    v_hours := v_hours || jsonb_build_object(d::text, case when v_open is not null then jsonb_build_object('opens', to_char(v_open, 'HH24:MI'), 'closes', to_char(v_close, 'HH24:MI')) end);
    select min(lo), max(hi) into v_lo, v_hi from (
      select public.sched_min(x->>0) lo, least(public.sched_end(x->>0, x->>1), 1440) hi
        from jsonb_array_elements(v_emps) emp, jsonb_array_elements(emp->'days'->d::text->'segments') x
      union all
      select 0, public.sched_min(x->>1) from jsonb_array_elements(v_emps) emp, jsonb_array_elements(emp->'days'->d::text->'carry') x) z;
    if v_open is not null then
      v_lo := least(coalesce(v_lo, 1440), extract(hour from v_open)::int * 60 + extract(minute from v_open)::int);
      v_hi := greatest(coalesce(v_hi, 0), extract(hour from v_close)::int * 60 + extract(minute from v_close)::int);
    end if;
    v_slots := '[]'::jsonb;
    if v_lo is not null and v_hi is not null and v_hi > v_lo then
      v_slot := (v_lo / 30) * 30;
      while v_slot < v_hi loop
        select count(*), coalesce(jsonb_agg(emp->>'code'), '[]') into v_cnt, v_present from jsonb_array_elements(v_emps) emp
         where ((emp->'days'->d::text->>'counts')::boolean
                and exists (select 1 from jsonb_array_elements(emp->'days'->d::text->'segments') x
                             where public.sched_min(x->>0) <= v_slot and v_slot < public.sched_end(x->>0, x->>1)))
            or (emp->'days'->d::text->'leave' = 'null'::jsonb or emp->'days'->d::text->'leave' is null)
               and not (emp->'days'->d::text->>'departed')::boolean
               and exists (select 1 from jsonb_array_elements(emp->'days'->d::text->'carry') x where v_slot < public.sched_min(x->>1));
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
    'can_manage', public.has_perm('schedule.manage') and public.can_see_store(p_store),
    'can_night', public.has_perm('schedule.night_hours'));
end $$;

-- ═══════════════ 12. Προγραμματισμένες ώρες μετά τις 22:00 (προβολή λογιστηρίου) ═══════════════
-- Μόνο από το πρόγραμμα (όχι παρουσίες, όχι αποδοχές, κανένας υπολογισμός προσαύξησης). Εξαιρούνται ρεπό, άδειες/απουσίες,
-- ημέρες πριν από την πρόσληψη ή μετά την αποχώρηση. Η βάρδια λογίζεται στην ημέρα έναρξής της.
create or replace function public.sched_night(p_store text, p_from date, p_to date, p_specialty text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e record; d date; s jsonb; v_m int; v_days jsonb; v_tot int; v_rows jsonb := '[]'::jsonb; v_by_day jsonb := '{}'::jsonb; v_all int := 0;
        v_rec boolean := public.is_reception(p_specialty);
begin
  if not public.has_perm('schedule.night_hours') or not public.can_see_store(p_store) then raise exception 'Δεν έχετε πρόσβαση στις ώρες μετά τις 22:00 του καταστήματος.'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then raise exception 'Επιλέξτε διάστημα έως 63 ημερών.'; end if;
  for e in
    select x.code, x.first, x.last, x.specialty, x.hire_date, x.leave_date from public.employees x
     where (x.store = p_store or exists (select 1 from public.schedule_patterns p where p.employee_code = x.code and p.store = p_store and p.status = 'active'
                                           and p.valid_from <= p_to and (p.valid_to is null or p.valid_to >= p_from))
                              or exists (select 1 from public.schedule_overrides o where o.employee_code = x.code and o.store = p_store and o.status = 'active'
                                           and o.day between p_from and p_to))
       and (p_specialty is null or x.specialty = p_specialty or (v_rec and x.store_role is not null and x.store = p_store))
       and (x.hire_date is null or x.hire_date <= p_to) and (x.leave_date is null or x.leave_date >= p_from)
     order by x.last, x.first
  loop
    v_days := '{}'::jsonb; v_tot := 0;
    for d in select g::date from generate_series(p_from, p_to, interval '1 day') g loop
      if (e.hire_date is not null and d < e.hire_date) or (e.leave_date is not null and d > e.leave_date) then continue; end if;
      if exists (select 1 from public.leave_days ld where ld.employee_code = e.code and ld.day = d and ld.status = 'active') then continue; end if;
      s := public.sched_day(e.code, d);
      if s is null or s->>'store' is distinct from p_store or s->>'kind' <> 'shift' then continue; end if;
      v_m := public.sched_night_minutes(s->'segments');
      if v_m > 0 then
        v_days := v_days || jsonb_build_object(d::text, v_m); v_tot := v_tot + v_m;
        v_by_day := jsonb_set(v_by_day, array[d::text], to_jsonb(coalesce((v_by_day->>d::text)::int, 0) + v_m));
      end if;
    end loop;
    if v_tot > 0 then
      v_rows := v_rows || jsonb_build_object('code', e.code, 'name', e.first || ' ' || e.last, 'specialty', e.specialty, 'days', v_days, 'total_minutes', v_tot);
      v_all := v_all + v_tot;
    end if;
  end loop;
  return jsonb_build_object('store', p_store, 'from', p_from, 'to', p_to, 'employees', v_rows, 'by_day', v_by_day, 'total_minutes', v_all);
end $$;

-- ═══════════════ 8. Ειδοποιήσεις λογιστηρίου για αλλαγές οριστικοποιημένου προγράμματος ═══════════════
create table if not exists public.schedule_alerts (
  id         bigserial primary key,
  change_id  bigint not null references public.schedule_changes(id),
  user_email text not null,
  created_at timestamptz not null default now(),
  read_at    timestamptz,
  unique (change_id, user_email)
);
create index if not exists schedule_alerts_unread_idx on public.schedule_alerts(user_email) where read_at is null;
alter table public.schedule_alerts enable row level security;
revoke all on public.schedule_alerts from anon, authenticated;

create or replace function public.sched_alert_on_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not new.after_finalize or new.change_type = 'finalize' then return new; end if;
  -- αρμόδιοι χρήστες λογιστηρίου (δικαίωμα «schedule.alerts») μέσα στο πεδίο τους· ποτέ η ΓΔ
  insert into public.schedule_alerts(change_id, user_email)
  select new.id, u.email from public.app_users u join public.role_scopes s on s.role = u.role
   where u.active and u.role <> 'owner' and public.role_has_perm(u.role, 'schedule.alerts')
     and (s.scope = 'all' or (s.scope = 'own_store' and u.store = new.store))
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists schedule_changes_alert on public.schedule_changes;
create trigger schedule_changes_alert after insert on public.schedule_changes for each row execute function public.sched_alert_on_change();

create or replace function public.sched_alerts(p_all boolean default false)
returns table (id bigint, change_id bigint, store text, employee_code text, employee_name text, change_type text, affected_from date, affected_to date,
               prev_value jsonb, new_value jsonb, reason text, actor text, at timestamptz, created_at timestamptz, read_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, c.id, c.store, c.employee_code, coalesce(e.first || ' ' || e.last, c.employee_code), c.change_type, c.affected_from, c.affected_to,
         c.prev_value, c.new_value, c.reason, c.actor, c.at, a.created_at, a.read_at
    from public.schedule_alerts a join public.schedule_changes c on c.id = a.change_id
    left join public.employees e on e.code = c.employee_code
   where a.user_email = public.current_email() and public.has_perm('schedule.alerts') and public.can_see_store(c.store)
     and (p_all or a.read_at is null)
   order by a.created_at desc limit 300
$$;
create or replace function public.sched_alert_count() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.schedule_alerts a join public.schedule_changes c on c.id = a.change_id
   where a.user_email = public.current_email() and a.read_at is null and public.has_perm('schedule.alerts') and public.can_see_store(c.store)
$$;
create or replace function public.sched_alert_read(p_id bigint default null) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform public.require_perm('schedule.alerts');
  update public.schedule_alerts set read_at = now()
   where user_email = public.current_email() and read_at is null and (p_id is null or id = p_id);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- Νέα δικαιώματα (ειδικά, όχι γενική πρόσβαση στο πρόγραμμα)
insert into public.permissions(code, module, label, description, fixed_roles, sort) values
 ('schedule.night_hours', 'Πρόγραμμα', 'Ώρες μετά τις 22:00 (προβολή λογιστηρίου)', 'Προγραμματισμένες ώρες μετά τις 22:00 ανά εργαζόμενο/ημέρα· δεν δίνει πρόσβαση στο υπόλοιπο πρόγραμμα', null, 53),
 ('schedule.alerts', 'Πρόγραμμα', 'Ειδοποιήσεις αλλαγών οριστικοποιημένου προγράμματος', 'Ενημερωτικές ειδοποιήσεις μέσα στην εφαρμογή (η ΓΔ δεν λαμβάνει)', null, 54)
on conflict (code) do nothing;
insert into public.role_permissions(role, perm, allowed) values
 ('accounting','schedule.night_hours',true), ('owner','schedule.night_hours',true), ('accounting','schedule.alerts',true)
on conflict (role, perm) do nothing;

-- ═══════════════ 7. Ημερολόγιο αδειών: managers στη Ρεσεψιόν, Αναρρωτική Άδεια ═══════════════
drop function if exists public.leave_calendar(date, date, text, text, boolean);
create function public.leave_calendar(p_from date, p_to date, p_store text default null, p_specialty text default null, p_include_closed boolean default false)
returns table (employee_code text, employee_name text, store text, specialty text, day date, status text, leave_type text, label text, request_id uuid, ref text, store_role text)
language plpgsql stable security definer set search_path = public as $$
declare v_rec boolean := public.is_reception(p_specialty);
begin
  if not public.has_perm('leave.view') then raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'Μη έγκυρο διάστημα.'; end if;
  return query
  select x.c_code, x.c_name, x.c_store, x.c_spec, x.c_day, x.c_status, x.c_type, x.c_label, x.c_req, x.c_ref, x.c_role from (
    select d.employee_code as c_code, e.first || ' ' || e.last as c_name, d.store as c_store, e.specialty as c_spec, d.day as c_day,
           case d.status when 'active' then 'approved' else 'cancelled' end as c_status, d.leave_type as c_type, lt.label as c_label, d.request_id as c_req, r.ref as c_ref,
           e.store_role as c_role, e.store as c_home
      from public.leave_days d join public.employees e on e.code = d.employee_code join public.hr_requests r on r.id = d.request_id
      left join public.leave_types lt on lt.code = d.leave_type
     where d.day between p_from and p_to and (d.status = 'active' or (p_include_closed and d.status = 'cancelled'))
    union all
    select r.employee_code, r.employee_name, r.store, e.specialty, g::date,
           case when r.status = 'rejected' then 'rejected' else 'pending' end,
           coalesce(r.leave_type, o.leave_type), coalesce(r.leave_type_label, o.leave_type_label), r.id, r.ref, e.store_role, e.store
      from public.hr_requests r join public.employees e on e.code = r.employee_code
      left join public.hr_requests o on o.id = r.original_request_id
      cross join lateral generate_series(greatest(r.start_date, p_from), least(r.end_date, p_to), interval '1 day') g
     where r.category in ('leave','sick_leave','leave_change') and r.start_date <= p_to and r.end_date >= p_from
       and (r.status in ('submitted','under_review','needs_info','awaiting_gm') or (p_include_closed and r.status = 'rejected'))
  ) x
  where public.can_see_store(x.c_store) and (p_store is null or x.c_store = p_store)
    and (p_specialty is null or x.c_spec = p_specialty or (v_rec and x.c_role is not null and x.c_store = x.c_home))
  order by x.c_day, x.c_name;
end $$;

-- ═══════════════ Δικαιώματα εκτέλεσης ═══════════════
revoke execute on all functions in schema public from public, anon;
grant execute on function public.month_status(text), public.prepare_declarations(text, jsonb),
  public.sched_set_temp(text, date[], jsonb, text, text), public.sched_delete(text, date[], text), public.shift_template_delete(bigint),
  public.sched_week(text, date, text), public.sched_night(text, date, date, text),
  public.sched_alerts(boolean), public.sched_alert_count(), public.sched_alert_read(bigint),
  public.leave_calendar(date, date, text, text, boolean), public.store_role_label(text), public.is_reception(text),
  public.emp_employed_in_month(date, date, text), public.sched_end(text, text), public.sched_night_minutes(jsonb) to authenticated;
revoke execute on function public.sched_alert_on_change() from authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
