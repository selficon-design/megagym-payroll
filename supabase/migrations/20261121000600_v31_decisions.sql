-- Έκδοση 3.1 · Αποφάσεις 21/11/2026
--  • Προθεσμίες βελτίωσης 15/7/7: ημερολογιακές ημέρες (ενεργοποιείται η αυτόματη πρόταση).
--  • «Παλιά μέλη — Άμεσο»: ξεχωριστό μέγεθος, ΔΕΝ περιέχεται στο DR → προστίθεται στις ανανεώσεις και στο γενικό σύνολο.
--  • «Παλιά μέλη» σε κάθε είδος στατιστικών (Ρεσεψιόν, Επίβλεψη, Exclusive), με τα ίδια πεδία με τα «Νέα μέλη».
--  • Managers / assistant managers: εμφανίζονται στο πρόγραμμα και στις άδειες της Ρεσεψιόν, αλλά ΔΕΝ μετρούν στην κάλυψη της.
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: νέες στήλες (κενές για τις παλιές εγγραφές), καμία αναταξινόμηση ή επινόηση μηδενικών.

update public.improvement_settings set day_mode = 'calendar', updated_by = 'απόφαση 21/11/2026', updated_at = now() where id = 1 and day_mode is null;

alter table public.daily_stats
  add column if not exists old_trials_attended int, add column if not exists old_trials_enrolled int,
  add column if not exists old_trials_done int, add column if not exists old_enr_pilates int;

-- Πεδία «Παλιών μελών» ανά είδος: old_<πεδίο> για κάθε πεδίο του είδους + «Παλιά μέλη — Άμεσο»
create or replace function public.stats_old_fields(p_kind text) returns text[] language sql immutable as $$
  select array(select 'old_' || f from unnest(public.stats_fields(p_kind)) f) || array['old_direct']
$$;
create or replace function public.stats_old_fields() returns text[] language sql immutable as $$ select public.stats_old_fields('reception') $$;

-- Έλεγχος γραμμής: τα πεδία παλιών μελών του είδους είναι όλα συμπληρωμένα ή όλα κενά (παλιά εγγραφή)· όσα δεν ανήκουν στο είδος κενά
alter table public.daily_stats drop constraint if exists stats_old_members;
create or replace function public.stats_old_check() returns trigger language plpgsql as $$
declare j jsonb := to_jsonb(new); f text; v_set int := 0; v_tot int := 0;
        v_all text[] := array['old_dr','old_lost','old_cb','old_trials_sent','old_trials_attended','old_trials_enrolled','old_trials_done',
                              'old_enr_fitness','old_enr_body','old_enr_muscle','old_enr_pilates','old_enr_from_trials','old_direct'];
begin
  foreach f in array v_all loop
    if f = any(public.stats_old_fields(new.kind)) then
      v_tot := v_tot + 1;
      if j->>f is not null then v_set := v_set + 1; if (j->>f)::int < 0 then raise exception 'Μόνο μη αρνητικοί αριθμοί.'; end if; end if;
    elsif j->>f is not null then raise exception 'Το πεδίο % δεν ανήκει στα στατιστικά αυτού του είδους.', f;
    end if;
  end loop;
  if v_set not in (0, v_tot) then raise exception 'Συμπληρώστε όλα τα πεδία «Παλιά μέλη» (0 όπου δεν υπάρχουν).'; end if;
  return new;
end $$;
drop trigger if exists daily_stats_old_check on public.daily_stats;
create trigger daily_stats_old_check before insert or update on public.daily_stats for each row execute function public.stats_old_check();

create or replace function public.stats_save(p_date date, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.require_perm('stats.entry');
  r jsonb; e public.employees; v_kind text; v_out jsonb := '[]'::jsonb; s public.daily_stats;
  v_old jsonb; f text; v_vals jsonb; v_oldv jsonb; v_has_old boolean;
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
        if not public.can_see_store(s.store) then raise exception 'Η καταχώριση ανήκει σε άλλο κατάστημα.'; end if;
        if s.version <> coalesce((r->>'version')::int, -1) then raise exception 'Η καταχώριση άλλαξε από άλλον χρήστη. Ανανεώστε.'; end if;
        v_vals := '{}'::jsonb;
        foreach f in array public.stats_fields(s.kind) loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop;
        -- πεδία παλιών μελών: αν στάλθηκαν, όλα υποχρεωτικά· αν όχι, κρατούνται όπως είναι (κενά στις παλιές εγγραφές)
        v_has_old := exists (select 1 from unnest(public.stats_old_fields(s.kind)) k where r ? k and jsonb_typeof(r->k) <> 'null');
        if v_has_old then foreach f in array public.stats_old_fields(s.kind) loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop;
        elsif s.old_direct is not null then
          v_has_old := true;
          foreach f in array public.stats_old_fields(s.kind) loop v_vals := v_vals || jsonb_build_object(f, to_jsonb(s) -> f); end loop;
        end if;
        v_old := (select jsonb_object_agg(k, to_jsonb(s) -> k) from unnest(public.stats_fields(s.kind) || case when v_has_old then public.stats_old_fields(s.kind) else '{}'::text[] end) k);
        if v_old = v_vals then v_out := v_out || jsonb_build_object('employee_code', e.code, 'ok', true, 'id', s.id, 'unchanged', true); continue; end if;
        update public.daily_stats set
          dr = (v_vals->>'dr')::int, lost = (v_vals->>'lost')::int, cb = (v_vals->>'cb')::int,
          trials_sent = (v_vals->>'trials_sent')::int, trials_attended = (v_vals->>'trials_attended')::int,
          trials_enrolled = (v_vals->>'trials_enrolled')::int, trials_done = (v_vals->>'trials_done')::int,
          enr_fitness = (v_vals->>'enr_fitness')::int, enr_body = (v_vals->>'enr_body')::int, enr_muscle = (v_vals->>'enr_muscle')::int,
          enr_pilates = (v_vals->>'enr_pilates')::int, enr_from_trials = (v_vals->>'enr_from_trials')::int,
          old_dr = (v_vals->>'old_dr')::int, old_lost = (v_vals->>'old_lost')::int, old_cb = (v_vals->>'old_cb')::int,
          old_trials_sent = (v_vals->>'old_trials_sent')::int, old_enr_fitness = (v_vals->>'old_enr_fitness')::int,
          old_enr_body = (v_vals->>'old_enr_body')::int, old_enr_muscle = (v_vals->>'old_enr_muscle')::int,
          old_enr_from_trials = (v_vals->>'old_enr_from_trials')::int, old_direct = (v_vals->>'old_direct')::int,
          old_trials_attended = (v_vals->>'old_trials_attended')::int, old_trials_enrolled = (v_vals->>'old_trials_enrolled')::int,
          old_trials_done = (v_vals->>'old_trials_done')::int, old_enr_pilates = (v_vals->>'old_enr_pilates')::int,
          updated_by = public.current_email(), updated_at = now(), version = version + 1
        where id = s.id;
        insert into public.daily_stats_history(stats_id, changed_by, old_values, new_values) values (s.id, public.current_email(), v_old, v_vals);
        v_out := v_out || jsonb_build_object('employee_code', e.code, 'ok', true, 'id', s.id, 'updated', true);
      else
        if not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν ανήκει στο κατάστημά σας.'; end if;
        perform public.stats_insert(e, p_date, r, public.current_email());
        select * into s from public.daily_stats where employee_code = e.code and stat_date = p_date and store = e.store and specialty = e.specialty;
        v_out := v_out || jsonb_build_object('employee_code', e.code, 'ok', true, 'id', s.id, 'created', true);
      end if;
    exception when others then
      v_out := v_out || jsonb_build_object('employee_code', r->>'employee_code', 'ok', false, 'error',
        case when sqlerrm like '%unique%' or sqlerrm like '%duplicate%' then 'Υπάρχει ήδη καταχώριση για αυτή την ημέρα.' else sqlerrm end);
    end;
  end loop;
  return jsonb_build_object('rows', v_out);
end $$;

create or replace function public.stats_insert(e public.employees, p_date date, r jsonb, p_by text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_kind text; v_vals jsonb := '{}'::jsonb; f text; v_id bigint;
begin
  if e.status <> 'Ενεργός' then raise exception 'Ανενεργός εργαζόμενος.'; end if;
  select stat_kind into v_kind from public.specialties where name = e.specialty;
  if v_kind is null then raise exception 'Η ειδικότητα του εργαζομένου δεν έχει στατιστικά.'; end if;
  foreach f in array public.stats_fields(v_kind) loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop;
  foreach f in array public.stats_old_fields(v_kind) loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop;
  perform pg_advisory_xact_lock(hashtext('stats:' || e.code || ':' || p_date || ':' || v_kind));
  if exists (select 1 from public.daily_stats where employee_code = e.code and stat_date = p_date and kind = v_kind) then
    raise exception 'Υπάρχει ήδη καταχώριση για αυτή την ημέρα. Ανοίξτε την για διόρθωση.';
  end if;
  insert into public.daily_stats(employee_code, stat_date, store, specialty, kind,
    dr, lost, cb, trials_sent, trials_attended, trials_enrolled, trials_done, enr_fitness, enr_body, enr_muscle, enr_pilates, enr_from_trials,
    old_dr, old_lost, old_cb, old_trials_sent, old_enr_fitness, old_enr_body, old_enr_muscle, old_enr_from_trials, old_direct,
    old_trials_attended, old_trials_enrolled, old_trials_done, old_enr_pilates, created_by)
  values (e.code, p_date, e.store, e.specialty, v_kind,
    (v_vals->>'dr')::int, (v_vals->>'lost')::int, (v_vals->>'cb')::int, (v_vals->>'trials_sent')::int,
    (v_vals->>'trials_attended')::int, (v_vals->>'trials_enrolled')::int, (v_vals->>'trials_done')::int,
    (v_vals->>'enr_fitness')::int, (v_vals->>'enr_body')::int, (v_vals->>'enr_muscle')::int,
    (v_vals->>'enr_pilates')::int, (v_vals->>'enr_from_trials')::int,
    (v_vals->>'old_dr')::int, (v_vals->>'old_lost')::int, (v_vals->>'old_cb')::int, (v_vals->>'old_trials_sent')::int,
    (v_vals->>'old_enr_fitness')::int, (v_vals->>'old_enr_body')::int, (v_vals->>'old_enr_muscle')::int,
    (v_vals->>'old_enr_from_trials')::int, (v_vals->>'old_direct')::int,
    (v_vals->>'old_trials_attended')::int, (v_vals->>'old_trials_enrolled')::int, (v_vals->>'old_trials_done')::int, (v_vals->>'old_enr_pilates')::int, p_by)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.statlink_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.stats_links := public.statlink_lookup(p_token);
begin
  return jsonb_build_object('store', l.store, 'today', public.athens_today(),
    'employees', (select coalesce(jsonb_agg(jsonb_build_object('code', e.code, 'name', e.last || ' ' || e.first) order by e.last, e.first), '[]')
                    from public.employees e join public.specialties sp on sp.name = e.specialty
                   where e.store = l.store and e.status = 'Ενεργός' and sp.stat_kind = 'reception'
                     and (e.leave_date is null or e.leave_date >= public.athens_today() - 31)),
    'fields', to_jsonb(public.stats_fields('reception') || public.stats_old_fields('reception')));
end $$;

-- Report νέων εγγραφών / ανανεώσεων ανά είδος (Ρεσεψιόν, Επίβλεψη: DR + CB · Exclusive: εγγραφές από δοκιμαστικά).
-- Ανανεώσεις = DR + CB παλιών μελών + «Άμεσο» (ξεχωριστό μέγεθος, όχι μέρος του DR). Γενικό σύνολο = νέες + ανανεώσεις.
drop function if exists public.stats_members_report(date, date, text);
create function public.stats_members_report(p_from date, p_to date, p_store text default null, p_kind text default 'reception')
returns table (store text, rows_split int, rows_unsplit int, new_informed int, new_enrolled int, old_informed int, old_enrolled int,
               old_direct int, renewals int, grand_total int, unsplit_enrolled int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_perm('stats.reports') then raise exception 'Δεν έχετε δικαίωμα για αναφορές στατιστικών.'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'Μη έγκυρο διάστημα.'; end if;
  if p_kind not in ('reception','supervision','exclusive') then raise exception 'Μη έγκυρο είδος.'; end if;
  return query
  with x as (
    select s.store, s.old_direct is not null as split,
           case when p_kind = 'exclusive' then 0 else s.dr + s.lost end as n_inf,
           case when p_kind = 'exclusive' then s.enr_from_trials else s.dr + s.cb end as n_enr,
           case when p_kind = 'exclusive' then 0 else coalesce(s.old_dr + s.old_lost, 0) end as o_inf,
           case when p_kind = 'exclusive' then coalesce(s.old_enr_from_trials, 0) else coalesce(s.old_dr + s.old_cb, 0) end as o_enr,
           coalesce(s.old_direct, 0) as o_dir
      from public.daily_stats s
     where s.kind = p_kind and s.stat_date between p_from and p_to and public.can_see_store(s.store) and (p_store is null or s.store = p_store))
  select x.store, count(*) filter (where split)::int, count(*) filter (where not split)::int,
         coalesce(sum(n_inf) filter (where split), 0)::int, coalesce(sum(n_enr) filter (where split), 0)::int,
         coalesce(sum(o_inf), 0)::int, coalesce(sum(o_enr), 0)::int, coalesce(sum(o_dir), 0)::int,
         coalesce(sum(o_enr + o_dir), 0)::int,
         (coalesce(sum(n_enr) filter (where split), 0) + coalesce(sum(o_enr + o_dir), 0))::int,
         coalesce(sum(n_enr) filter (where not split), 0)::int
    from x group by x.store order by x.store;
end $$;

-- ═══════ Πρόγραμμα: managers στη Ρεσεψιόν μόνο για εμφάνιση ═══════
create or replace function public.sched_week(p_store text, p_week_start date, p_specialty text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_days date[]; d date; e record; v_emps jsonb := '[]'::jsonb; v_cov jsonb := '{}'::jsonb; s jsonb; v_seg jsonb; v_min int;
        v_planned int; v_leave_min int; v_has_leave boolean; v_leave jsonb; v_pending jsonb; v_departed boolean; v_daymap jsonb; v_terms record;
        v_hours jsonb := '{}'::jsonb; v_open time; v_close time; v_lo int; v_hi int; v_slot int; v_cnt int; v_req int; v_slots jsonb; v_present jsonb;
        v_needs jsonb := '[]'::jsonb; v_wd int; v_inopen boolean; v_kind text; v_carry jsonb; v_prev jsonb; v_counts boolean; v_rec boolean := public.is_reception(p_specialty); v_shown boolean;
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
    -- Manager / assistant manager άλλου τμήματος στη Ρεσεψιόν: μόνο εμφάνιση (πρόγραμμα, άδειες), ΟΧΙ κάλυψη
    v_shown := v_rec and e.store_role is not null and e.specialty is distinct from p_specialty;
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
      v_counts := v_leave is null and not v_departed and v_min > 0 and not v_shown;
      if v_leave is not null then v_has_leave := true; v_leave_min := v_leave_min + v_min;
      elsif not v_departed then v_planned := v_planned + v_min; end if;
      if v_min > 0 and (v_leave is not null or v_departed) and not v_shown then
        v_needs := v_needs || jsonb_build_object('employee_code', e.code, 'employee_name', e.first || ' ' || e.last, 'day', d, 'segments', v_seg,
                                                 'why', case when v_departed then 'αποχώρηση' else coalesce(v_leave->>'label', 'άδεια') end);
      end if;
      -- ουρά προηγούμενης ημέρας (00:00 → λήξη), μόνο αν εκείνη η ημέρα μετρά
      v_carry := '[]'::jsonb;
      if v_prev is not null then
        select coalesce(jsonb_agg(jsonb_build_array('00:00', x->>1)), '[]') into v_carry from jsonb_array_elements(v_prev->'segments') x
         where public.sched_end(x->>0, x->>1) > 1440 and x->>1 <> '00:00';
        if exists (select 1 from public.leave_days ld where ld.employee_code = e.code and ld.day = d - 1 and ld.status = 'active')
           or (e.leave_date is not null and d - 1 > e.leave_date) or (e.hire_date is not null and d - 1 < e.hire_date) or v_shown then v_carry := '[]'::jsonb; end if;
      end if;
      v_daymap := v_daymap || jsonb_build_object(d::text, jsonb_build_object('segments', v_seg, 'source', s->>'source', 'minutes', v_min,
        'kind', v_kind, 'off', v_kind = 'off' and v_leave is null and not v_departed, 'deleted', v_kind = 'deleted',
        'overlap', public.sched_overlaps(v_seg), 'leave', v_leave, 'pending', v_pending, 'departed', v_departed,
        'reason', s->>'reason', 'counts', v_counts, 'carry', v_carry,
        'night_minutes', case when v_counts then public.sched_night_minutes(v_seg) else 0 end));
      v_prev := s;
    end loop;
    v_emps := v_emps || jsonb_build_object('code', e.code, 'name', e.first || ' ' || e.last, 'specialty', e.specialty, 'leave_date', e.leave_date,
      'store_role', e.store_role, 'store_role_label', public.store_role_label(e.store_role), 'shown_only', v_shown,
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
       and (p_specialty is null or x.specialty = p_specialty)   -- managers: στο δικό τους τμήμα (στη Ρεσεψιόν μόνο εμφάνιση)
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

revoke execute on all functions in schema public from public, anon;
grant execute on function public.stats_save(date, jsonb), public.stats_members_report(date, date, text, text), public.stats_old_fields(), public.stats_old_fields(text),
  public.sched_week(text, date, text), public.sched_night(text, date, date, text) to authenticated;
revoke execute on function public.stats_insert(public.employees, date, jsonb, text), public.stats_old_check() from authenticated;
grant execute on function public.statlink_info(text), public.statlink_submit(text, jsonb) to anon;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
