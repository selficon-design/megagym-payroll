-- Έκδοση 3.1 · Στατιστικά
-- 16. Απομονωμένος σύνδεσμος στατιστικών Ρεσεψιόν ανά κατάστημα (μόνο υποβολή· ανάκληση/αντικατάσταση· έλεγχοι στον server).
-- 17. Ομάδα «Παλιά μέλη» (ίδια πεδία με τα «Νέα μέλη») και «Παλιά μέλη — Άμεσο»· μηνιαίο report νέων εγγραφών/ανανεώσεων.
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: οι παλιές εγγραφές μένουν χωρίς διάκριση (κενά πεδία, ΟΧΙ μηδενικά) και δεν αναταξινομούνται.

-- ═══════════════ 17. Παλιά μέλη (Ρεσεψιόν) ═══════════════
alter table public.daily_stats
  add column if not exists old_dr int, add column if not exists old_lost int, add column if not exists old_cb int,
  add column if not exists old_trials_sent int, add column if not exists old_enr_fitness int, add column if not exists old_enr_body int,
  add column if not exists old_enr_muscle int, add column if not exists old_enr_from_trials int, add column if not exists old_direct int;
alter table public.daily_stats drop constraint if exists stats_old_members;
alter table public.daily_stats add constraint stats_old_members check (
  -- όλα ή κανένα (παλιές εγγραφές χωρίς διάκριση νέων/παλιών)· μόνο στη Ρεσεψιόν· μη αρνητικά
  num_nonnulls(old_dr, old_lost, old_cb, old_trials_sent, old_enr_fitness, old_enr_body, old_enr_muscle, old_enr_from_trials, old_direct) in (0, 9)
  and (kind = 'reception' or num_nonnulls(old_dr, old_lost, old_cb, old_trials_sent, old_enr_fitness, old_enr_body, old_enr_muscle, old_enr_from_trials, old_direct) = 0)
  and coalesce(least(old_dr, old_lost, old_cb, old_trials_sent, old_enr_fitness, old_enr_body, old_enr_muscle, old_enr_from_trials, old_direct), 0) >= 0);

create or replace function public.stats_old_fields() returns text[] language sql immutable as $$
  select array['old_dr','old_lost','old_cb','old_trials_sent','old_enr_fitness','old_enr_body','old_enr_muscle','old_enr_from_trials','old_direct']
$$;

-- Καταχώριση / διόρθωση: στη Ρεσεψιόν οι νέες εγγραφές συμπληρώνουν και τα «Παλιά μέλη». Στη διόρθωση παλιάς εγγραφής
-- χωρίς διάκριση, τα πεδία παλιών μελών μένουν κενά αν δεν δοθούν (δεν επινοούνται μηδενικά).
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
        v_has_old := s.kind = 'reception' and (s.old_dr is not null or exists (select 1 from unnest(public.stats_old_fields()) k where r ? k and jsonb_typeof(r->k) <> 'null'));
        if v_has_old then foreach f in array public.stats_old_fields() loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop; end if;
        v_old := (select jsonb_object_agg(k, to_jsonb(s) -> k) from unnest(public.stats_fields(s.kind) || case when v_has_old then public.stats_old_fields() else '{}'::text[] end) k);
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

-- Κοινή εισαγωγή νέας ημερήσιας εγγραφής (εφαρμογή και σύνδεσμος). Μία εγγραφή ανά εργαζόμενο, ημέρα και είδος στατιστικών.
create or replace function public.stats_insert(e public.employees, p_date date, r jsonb, p_by text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_kind text; v_vals jsonb := '{}'::jsonb; f text; v_id bigint;
begin
  if e.status <> 'Ενεργός' then raise exception 'Ανενεργός εργαζόμενος.'; end if;
  select stat_kind into v_kind from public.specialties where name = e.specialty;
  if v_kind is null then raise exception 'Η ειδικότητα του εργαζομένου δεν έχει στατιστικά.'; end if;
  foreach f in array public.stats_fields(v_kind) loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop;
  if v_kind = 'reception' then foreach f in array public.stats_old_fields() loop v_vals := v_vals || jsonb_build_object(f, public.stats_int(r, f)); end loop; end if;
  perform pg_advisory_xact_lock(hashtext('stats:' || e.code || ':' || p_date || ':' || v_kind));
  if exists (select 1 from public.daily_stats where employee_code = e.code and stat_date = p_date and kind = v_kind) then
    raise exception 'Υπάρχει ήδη καταχώριση για αυτή την ημέρα. Ανοίξτε την για διόρθωση.';
  end if;
  insert into public.daily_stats(employee_code, stat_date, store, specialty, kind,
    dr, lost, cb, trials_sent, trials_attended, trials_enrolled, trials_done, enr_fitness, enr_body, enr_muscle, enr_pilates, enr_from_trials,
    old_dr, old_lost, old_cb, old_trials_sent, old_enr_fitness, old_enr_body, old_enr_muscle, old_enr_from_trials, old_direct, created_by)
  values (e.code, p_date, e.store, e.specialty, v_kind,
    (v_vals->>'dr')::int, (v_vals->>'lost')::int, (v_vals->>'cb')::int, (v_vals->>'trials_sent')::int,
    (v_vals->>'trials_attended')::int, (v_vals->>'trials_enrolled')::int, (v_vals->>'trials_done')::int,
    (v_vals->>'enr_fitness')::int, (v_vals->>'enr_body')::int, (v_vals->>'enr_muscle')::int,
    (v_vals->>'enr_pilates')::int, (v_vals->>'enr_from_trials')::int,
    (v_vals->>'old_dr')::int, (v_vals->>'old_lost')::int, (v_vals->>'old_cb')::int, (v_vals->>'old_trials_sent')::int,
    (v_vals->>'old_enr_fitness')::int, (v_vals->>'old_enr_body')::int, (v_vals->>'old_enr_muscle')::int,
    (v_vals->>'old_enr_from_trials')::int, (v_vals->>'old_direct')::int, p_by)
  returning id into v_id;
  return v_id;
end $$;

-- Μηνιαίο / οποιουδήποτε διαστήματος report νέων εγγραφών και ανανεώσεων (Ρεσεψιόν), ανά κατάστημα και συνολικά.
-- Νέες εγγραφές = DR + CB (νέα μέλη) · Ανανεώσεις = DR + CB (παλιά μέλη) · Γενικό σύνολο = άθροισμα των δύο.
-- Οι ενημερώσεις (DR + LOST) δεν είναι εγγραφές. Το «Παλιά μέλη — Άμεσο» εμφανίζεται χωριστά και ΔΕΝ προστίθεται
-- στα σύνολα μέχρι να οριστεί αν είναι ήδη μέρος του DR παλιών μελών. Παλιές εγγραφές χωρίς διάκριση μετρώνται χωριστά.
create or replace function public.stats_members_report(p_from date, p_to date, p_store text default null)
returns table (store text, rows_split int, rows_unsplit int, new_informed int, new_enrolled int, old_informed int, renewals int,
               grand_total int, old_direct int, unsplit_enrolled int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_perm('stats.reports') then raise exception 'Δεν έχετε δικαίωμα για αναφορές στατιστικών.'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'Μη έγκυρο διάστημα.'; end if;
  return query
  select s.store,
         count(*) filter (where s.old_dr is not null)::int, count(*) filter (where s.old_dr is null)::int,
         coalesce(sum(s.dr + s.lost) filter (where s.old_dr is not null), 0)::int,
         coalesce(sum(s.dr + s.cb) filter (where s.old_dr is not null), 0)::int,
         coalesce(sum(s.old_dr + s.old_lost), 0)::int,
         coalesce(sum(s.old_dr + s.old_cb), 0)::int,
         (coalesce(sum(s.dr + s.cb) filter (where s.old_dr is not null), 0) + coalesce(sum(s.old_dr + s.old_cb), 0))::int,
         coalesce(sum(s.old_direct), 0)::int,
         coalesce(sum(s.dr + s.cb) filter (where s.old_dr is null), 0)::int
    from public.daily_stats s
   where s.kind = 'reception' and s.stat_date between p_from and p_to and public.can_see_store(s.store) and (p_store is null or s.store = p_store)
   group by s.store order by s.store;
end $$;

-- ═══════════════ 16. Σύνδεσμος στατιστικών Ρεσεψιόν ανά κατάστημα ═══════════════
create table if not exists public.stats_links (
  id          bigserial primary key,
  store       text not null references public.stores(name) on update cascade,
  token_hash  text unique,                -- sha256 του κλειδιού· null μετά την ανάκληση
  status      text not null default 'active' check (status in ('active','revoked')),
  created_by  text not null,
  created_at  timestamptz not null default now(),
  revoked_by  text, revoked_at timestamptz, revoke_reason text,
  submissions int not null default 0,
  last_used_at timestamptz
);
create unique index if not exists one_active_stats_link on public.stats_links(store) where status = 'active';
alter table public.stats_links enable row level security;
revoke all on public.stats_links from anon, authenticated;

-- Δημιουργία ή αντικατάσταση (το προηγούμενο κλειδί ανακαλείται). Το κλειδί επιστρέφεται ΜΟΝΟ τώρα· αποθηκεύεται hash.
create or replace function public.statlink_create(p_store text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_token text := public.fill_new_token(); v_id bigint;
begin
  perform public.require_perm('stats.links');
  if not exists (select 1 from public.stores where name = p_store) or not public.can_see_store(p_store) then raise exception 'Το κατάστημα δεν βρέθηκε στο πεδίο σας.'; end if;
  update public.stats_links set status = 'revoked', token_hash = null, revoked_by = public.current_email(), revoked_at = now(), revoke_reason = 'Αντικατάσταση'
   where store = p_store and status = 'active';
  insert into public.stats_links(store, token_hash, created_by) values (p_store, public.fill_hash(v_token), public.current_email()) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'token', v_token);
end $$;
create or replace function public.statlink_revoke(p_store text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_perm('stats.links');
  if not public.can_see_store(p_store) then raise exception 'Το κατάστημα δεν βρέθηκε στο πεδίο σας.'; end if;
  update public.stats_links set status = 'revoked', token_hash = null, revoked_by = public.current_email(), revoked_at = now(), revoke_reason = nullif(trim(coalesce(p_reason, '')), '')
   where store = p_store and status = 'active';
  if not found then raise exception 'Δεν υπάρχει ενεργός σύνδεσμος.'; end if;
  return jsonb_build_object('ok', true);
end $$;
create or replace function public.statlink_list() returns table (store text, status text, created_by text, created_at timestamptz, revoked_by text, revoked_at timestamptz, submissions int, last_used_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_perm('stats.links');
  return query select l.store, l.status, l.created_by, l.created_at, l.revoked_by, l.revoked_at, l.submissions, l.last_used_at
                 from public.stats_links l where public.can_see_store(l.store) order by l.store, l.created_at desc;
end $$;

-- ── Ανώνυμες κλήσεις του συνδέσμου (ρόλος anon): μόνο το κλειδί· τίποτα από προηγούμενες εγγραφές ──
create or replace function public.statlink_lookup(p_token text) returns public.stats_links
language plpgsql security definer set search_path = public as $$
declare l public.stats_links;
begin
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{32,200}$' then raise exception 'Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί.'; end if;
  select * into l from public.stats_links where token_hash = public.fill_hash(p_token) and status = 'active';
  if not found then raise exception 'Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί.'; end if;
  return l;
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
    'fields', to_jsonb(public.stats_fields('reception') || public.stats_old_fields()));
end $$;

create or replace function public.statlink_submit(p_token text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.stats_links := public.statlink_lookup(p_token); e public.employees; v_date date;
begin
  begin v_date := (p->>'date')::date; exception when others then raise exception 'Μη έγκυρη ημερομηνία.'; end;
  if v_date is null or v_date > public.athens_today() then raise exception 'Η ημερομηνία δεν μπορεί να είναι μελλοντική.'; end if;
  if v_date < public.athens_today() - 31 then raise exception 'Για ημερομηνίες παλαιότερες του μήνα απευθυνθείτε στον manager του καταστήματος.'; end if;
  select x.* into e from public.employees x join public.specialties sp on sp.name = x.specialty
   where x.code = p->>'employee_code' and x.store = l.store and sp.stat_kind = 'reception';
  if not found then raise exception 'Επιλέξτε εργαζόμενο Ρεσεψιόν του καταστήματος.'; end if;
  if e.leave_date is not null and v_date > e.leave_date then raise exception 'Επιλέξτε εργαζόμενο Ρεσεψιόν του καταστήματος.'; end if;
  if exists (select 1 from public.daily_stats where employee_code = e.code and stat_date = v_date and kind = 'reception') then
    -- καμία αποκάλυψη δεδομένων: μόνο οδηγία για διόρθωση από εξουσιοδοτημένο χρήστη
    raise exception 'Υπάρχει ήδη καταχώριση για αυτόν τον εργαζόμενο και αυτή την ημέρα. Για διόρθωση επικοινωνήστε με τον manager του καταστήματος.';
  end if;
  perform public.stats_insert(e, v_date, coalesce(p->'values', '{}'::jsonb), 'σύνδεσμος:' || l.store);
  update public.stats_links set submissions = submissions + 1, last_used_at = now() where id = l.id;
  return jsonb_build_object('ok', true);
exception when unique_violation then
  raise exception 'Υπάρχει ήδη καταχώριση για αυτόν τον εργαζόμενο και αυτή την ημέρα. Για διόρθωση επικοινωνήστε με τον manager του καταστήματος.';
end $$;

insert into public.permissions(code, module, label, description, fixed_roles, sort) values
 ('stats.links', 'Στατιστικά', 'Σύνδεσμοι στατιστικών Ρεσεψιόν', 'Δημιουργία, αντικατάσταση και ανάκληση του απομονωμένου συνδέσμου υποβολής ανά κατάστημα', null, 75)
on conflict (code) do nothing;
insert into public.role_permissions(role, perm, allowed) values ('owner','stats.links',true) on conflict (role, perm) do nothing;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.stats_save(date, jsonb), public.stats_members_report(date, date, text), public.stats_old_fields(),
  public.statlink_create(text), public.statlink_revoke(text, text), public.statlink_list() to authenticated;
revoke execute on function public.stats_insert(public.employees, date, jsonb, text), public.statlink_lookup(text) from authenticated;
grant execute on function public.statlink_info(text), public.statlink_submit(text, jsonb) to anon;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
