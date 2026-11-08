-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Έκδοση 3.0 · Μέρος 2: Στοιχεία και κύκλος ζωής εργαζομένου
--   Email, τηλέφωνο, πενθήμερο/εξαήμερο (ανά εργαζόμενο, με ημερομηνία ισχύος και ιστορικό),
--   εβδομαδιαίες συμβατικές ώρες, πρόσληψη, αποχώρηση (= τελευταία ημέρα απασχόλησης).
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: νέες προαιρετικές στήλες· οι υπάρχουσες εγγραφές μένουν ως έχουν.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

alter table public.employees
  add column if not exists email        text check (email is null or (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  add column if not exists phone        text check (phone is null or phone ~ '^[0-9+()\s.\-]{5,30}$'),
  add column if not exists work_week    smallint check (work_week in (5, 6)),
  add column if not exists weekly_hours numeric(5,2) check (weekly_hours is null or (weekly_hours > 0 and weekly_hours <= 60)),
  add column if not exists leave_date   date;
alter table public.employees drop constraint if exists employees_leave_after_hire;
alter table public.employees add constraint employees_leave_after_hire check (leave_date is null or hire_date is null or leave_date >= hire_date);

-- Σύστημα εργασίας ανά εργαζόμενο, με ημερομηνία ισχύος (το τρέχον αντιγράφεται και στον εργαζόμενο για τις λίστες)
create table public.employee_work_terms (
  id            bigserial primary key,
  employee_code text not null references public.employees(code) on update cascade on delete cascade,
  work_week     smallint not null check (work_week in (5, 6)),
  weekly_hours  numeric(5,2) check (weekly_hours is null or (weekly_hours > 0 and weekly_hours <= 60)),
  valid_from    date not null,
  note          text,
  set_by        text not null,
  set_at        timestamptz not null default now(),
  unique (employee_code, valid_from)
);

-- Πρόσληψη, αποχώρηση, μεταφορά, αλλαγή συστήματος εργασίας (δεν αλλάζει ποτέ)
create table public.employee_lifecycle (
  id             bigserial primary key,
  employee_code  text not null references public.employees(code) on update cascade,
  kind           text not null check (kind in ('hire','leave','leave_cancel','transfer','work_terms')),
  effective_date date,
  old_value      jsonb,
  new_value      jsonb,
  note           text,
  actor          text not null,
  at             timestamptz not null default now()
);
create index employee_lifecycle_emp_idx on public.employee_lifecycle(employee_code, at);

-- Σύστημα εργασίας σε μια ημερομηνία (πριν από την πρώτη καταχώριση: η τιμή της καρτέλας)
create or replace function public.work_terms_on(p_code text, p_day date)
returns table (work_week smallint, weekly_hours numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(t.work_week, e.work_week), coalesce(t.weekly_hours, e.weekly_hours)
    from public.employees e
    left join lateral (select x.work_week, x.weekly_hours from public.employee_work_terms x
                        where x.employee_code = e.code and x.valid_from <= p_day order by x.valid_from desc limit 1) t on true
   where e.code = p_code
$$;

-- Απασχολείται την ημέρα; (η αποχώρηση είναι η ΤΕΛΕΥΤΑΙΑ ημέρα απασχόλησης)
create or replace function public.emp_active_on(p_code text, p_day date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (e.hire_date is null or e.hire_date <= p_day) and (e.leave_date is null or p_day <= e.leave_date)
                     from public.employees e where e.code = p_code), false)
$$;

-- Αυτόματη καταγραφή: κάθε αλλαγή πρόσληψης / αποχώρησης / συστήματος εργασίας, από όποια οθόνη κι αν γίνει
create or replace function public.track_employee_lifecycle() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_actor text := coalesce(public.current_email(), 'system'); v_note text := nullif(current_setting('mg.note', true), '');
        v_from date := coalesce(nullif(current_setting('mg.valid_from', true), '')::date, public.athens_today());
begin
  if tg_op = 'INSERT' then
    if new.work_week is not null then
      insert into public.employee_work_terms(employee_code, work_week, weekly_hours, valid_from, note, set_by)
      values (new.code, new.work_week, new.weekly_hours, coalesce(new.hire_date, public.athens_today()), coalesce(v_note, 'Αρχική καταχώριση'), v_actor);
    end if;
    if new.hire_date is not null then
      insert into public.employee_lifecycle(employee_code, kind, effective_date, new_value, note, actor)
      values (new.code, 'hire', new.hire_date, jsonb_build_object('store', new.store, 'company', new.company), v_note, v_actor);
    end if;
    if new.leave_date is not null then
      insert into public.employee_lifecycle(employee_code, kind, effective_date, note, actor) values (new.code, 'leave', new.leave_date, v_note, v_actor);
    end if;
    return new;
  end if;
  if new.hire_date is distinct from old.hire_date then
    insert into public.employee_lifecycle(employee_code, kind, effective_date, old_value, new_value, note, actor)
    values (new.code, 'hire', new.hire_date, jsonb_build_object('hire_date', old.hire_date), jsonb_build_object('hire_date', new.hire_date), v_note, v_actor);
  end if;
  if new.leave_date is distinct from old.leave_date then
    insert into public.employee_lifecycle(employee_code, kind, effective_date, old_value, new_value, note, actor)
    values (new.code, case when new.leave_date is null then 'leave_cancel' else 'leave' end, coalesce(new.leave_date, old.leave_date),
            jsonb_build_object('leave_date', old.leave_date), jsonb_build_object('leave_date', new.leave_date), v_note, v_actor);
  end if;
  if (new.work_week is distinct from old.work_week or new.weekly_hours is distinct from old.weekly_hours)
     and coalesce(current_setting('mg.terms_rpc', true), '') <> '1' then
    if new.work_week is null then raise exception 'Το πενθήμερο/εξαήμερο δεν αφαιρείται· καταχωρίστε αλλαγή με ημερομηνία ισχύος.'; end if;
    -- αλλαγή από την καρτέλα χωρίς ημερομηνία ισχύος = από σήμερα
    if exists (select 1 from public.employee_work_terms where employee_code = new.code and valid_from = v_from) then
      raise exception 'Υπάρχει ήδη αλλαγή συστήματος εργασίας με ισχύ %. Καταχωρίστε την αλλαγή με άλλη ημερομηνία ισχύος.', to_char(v_from, 'DD/MM/YYYY');
    end if;
    insert into public.employee_work_terms(employee_code, work_week, weekly_hours, valid_from, note, set_by)
    values (new.code, new.work_week, new.weekly_hours, v_from, coalesce(v_note, 'Αλλαγή από την καρτέλα'), v_actor);
    insert into public.employee_lifecycle(employee_code, kind, effective_date, old_value, new_value, note, actor)
    values (new.code, 'work_terms', v_from, jsonb_build_object('work_week', old.work_week, 'weekly_hours', old.weekly_hours),
            jsonb_build_object('work_week', new.work_week, 'weekly_hours', new.weekly_hours), v_note, v_actor);
  end if;
  return new;
end $$;
create trigger employees_lifecycle after insert or update on public.employees
  for each row execute function public.track_employee_lifecycle();

-- Υποχρεωτική επιλογή πενθήμερου/εξαήμερου για κάθε νέο εργαζόμενο που καταχωρίζεται από την εφαρμογή
-- (οι υπάρχουσες εγγραφές δεν αλλάζουν· συμπληρώνονται από την καρτέλα)
create or replace function public.require_work_week() returns trigger language plpgsql as $$
begin
  if new.work_week is null and current_user in ('authenticated', 'anon') then
    raise exception 'Επιλέξτε πενθήμερο ή εξαήμερο για τον νέο εργαζόμενο (%).', new.code;
  end if;
  return new;
end $$;
create trigger employees_require_work_week before insert on public.employees
  for each row execute function public.require_work_week();

-- Αλλαγή πενθήμερου/εξαήμερου ή ωρών με ημερομηνία ισχύος (ΓΔ, HR, λογιστήριο)
create or replace function public.emp_set_work_terms(p_code text, p_work_week int, p_weekly_hours numeric, p_valid_from date, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; v_cur record;
begin
  perform public.require_perm('employees.edit');
  select * into e from public.employees where code = p_code for update;
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if p_work_week not in (5, 6) then raise exception 'Επιλέξτε πενθήμερο ή εξαήμερο.'; end if;
  if p_valid_from is null then raise exception 'Συμπληρώστε ημερομηνία ισχύος.'; end if;
  if p_weekly_hours is not null and (p_weekly_hours <= 0 or p_weekly_hours > 60) then raise exception 'Μη έγκυρες εβδομαδιαίες ώρες.'; end if;
  if exists (select 1 from public.employee_work_terms where employee_code = p_code and valid_from = p_valid_from) then
    raise exception 'Υπάρχει ήδη αλλαγή με ισχύ %. Δεν αντικαθίσταται σιωπηρά· επιλέξτε άλλη ημερομηνία.', to_char(p_valid_from, 'DD/MM/YYYY');
  end if;
  insert into public.employee_work_terms(employee_code, work_week, weekly_hours, valid_from, note, set_by)
  values (p_code, p_work_week, p_weekly_hours, p_valid_from, nullif(trim(p_note), ''), public.current_email());
  insert into public.employee_lifecycle(employee_code, kind, effective_date, old_value, new_value, note, actor)
  values (p_code, 'work_terms', p_valid_from, jsonb_build_object('work_week', e.work_week, 'weekly_hours', e.weekly_hours),
          jsonb_build_object('work_week', p_work_week, 'weekly_hours', p_weekly_hours), nullif(trim(p_note), ''), public.current_email());
  select * into v_cur from public.work_terms_on(p_code, public.athens_today());
  perform set_config('mg.terms_rpc', '1', true);
  update public.employees set work_week = v_cur.work_week, weekly_hours = v_cur.weekly_hours where code = p_code;
  perform set_config('mg.terms_rpc', '', true);
  return jsonb_build_object('ok', true);
end $$;

-- Πρόσληψη / αποχώρηση με σημείωση. Η αποχώρηση δεν διαγράφει τίποτα· ο εργαζόμενος απλώς δεν μετρά μετά από αυτήν.
create or replace function public.emp_set_dates(p_code text, p_hire date, p_leave date, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  perform public.require_perm('employees.edit');
  select * into e from public.employees where code = p_code for update;
  if not found or not public.can_see_store(e.store) then raise exception 'Ο εργαζόμενος δεν βρέθηκε στο πεδίο σας.'; end if;
  if p_leave is not null and p_hire is not null and p_leave < p_hire then raise exception 'Η αποχώρηση δεν μπορεί να είναι πριν από την πρόσληψη.'; end if;
  perform set_config('mg.note', coalesce(nullif(trim(p_note), ''), ''), true);
  update public.employees set hire_date = p_hire, leave_date = p_leave where code = p_code;
  perform set_config('mg.note', '', true);
  return jsonb_build_object('ok', true);
end $$;

alter table public.employee_work_terms enable row level security;
alter table public.employee_lifecycle  enable row level security;
create policy ewt_read on public.employee_work_terms for select to authenticated
  using (exists (select 1 from public.employees e where e.code = employee_code));
create policy elc_read on public.employee_lifecycle for select to authenticated
  using (exists (select 1 from public.employees e where e.code = employee_code));
revoke all on public.employee_work_terms, public.employee_lifecycle from anon, authenticated;
grant select on public.employee_work_terms, public.employee_lifecycle to authenticated;
create trigger employee_lifecycle_append_only before update or delete on public.employee_lifecycle
  for each row when (pg_trigger_depth() = 0) execute function public.append_only();
create trigger audit_work_terms after insert on public.employee_work_terms for each row execute function public.audit_trigger();

revoke execute on all functions in schema public from public, anon;
revoke execute on function public.track_employee_lifecycle(), public.require_work_week() from authenticated;
grant execute on function public.work_terms_on(text, date), public.emp_active_on(text, date),
  public.emp_set_work_terms(text, int, numeric, date, text), public.emp_set_dates(text, date, date, text) to authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
