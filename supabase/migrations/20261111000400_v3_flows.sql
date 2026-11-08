-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Έκδοση 3.0 · Μέρος 5: Υλοποίηση από manager · Ειδοποιήσεις · Exit Interview · Αποτελέσματα
--   Εγκρίθηκε → Ενημερώθηκε ο εργαζόμενος → Ανάληψη υλοποίησης (manager) → Ολοκληρώθηκε.
--   Αδιάβαστες ενημερώσεις ανά χρήστη για τον αρμόδιο manager.
--   Exit Interview: ξεχωριστό είδος ερωτηματολογίου, χωρίς βαθμό· περιεχόμενο ΜΟΝΟ για ΓΔ/HR/εκπαιδευτή.
--   Προβολή απαντήσεων/βαθμολογίας κανονικών αξιολογήσεων για manager (κατάστημα) και εκπαιδευτή (όλα).
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ─────────────── Υλοποίηση εγκεκριμένων αιτημάτων ───────────────
alter table public.hr_requests
  add column if not exists impl_claimed_by text,
  add column if not exists impl_claimed_at timestamptz;

create or replace function public.req_impl_claim(p_id uuid, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.implement');
  r := public.req_lock(p_id, p_version);
  if public.req_flow(r.category) not in ('leave','generic','gm') then raise exception 'Η υλοποίηση από manager αφορά εγκεκριμένα αιτήματα εργαζομένων.'; end if;
  if r.status <> 'approved' then raise exception 'Αναλαμβάνεται μόνο εγκεκριμένο αίτημα που δεν έχει ολοκληρωθεί.'; end if;
  if r.notified_at is null then raise exception 'Καταγράψτε πρώτα την ενημέρωση του εργαζομένου («Ενημέρωσα τον εργαζόμενο»).'; end if;
  if r.impl_claimed_by is not null then raise exception 'Η υλοποίηση έχει ήδη αναληφθεί από %.', r.impl_claimed_by; end if;
  update public.hr_requests set impl_claimed_by = public.current_email(), impl_claimed_at = now(), updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'impl_claimed', r.status, r.status, null);
  return jsonb_build_object('ok', true, 'version', r.version + 1);
end $$;

-- Ολοκλήρωση υλοποίησης από τον manager, με σχόλιο και προαιρετικό δικαιολογητικό.
-- Δεν αλλάζει την απόφαση· δεν δίνει καμία άλλη αρμοδιότητα.
create or replace function public.req_impl_complete(p_id uuid, p_note text, p_file jsonb, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  perform public.require_perm('requests.implement');
  r := public.req_lock(p_id, p_version);
  if r.status <> 'approved' then raise exception 'Το αίτημα δεν είναι σε αναμονή υλοποίησης.'; end if;
  if r.impl_claimed_by is null then raise exception 'Πατήστε πρώτα «Αναλαμβάνω την υλοποίηση».'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'Γράψτε σύντομο σχόλιο υλοποίησης.'; end if;
  if p_file is not null and nullif(p_file->>'data', '') is not null then
    perform public.attach_file(p_id, p_file->>'name', p_file->>'mime', p_file->>'data', public.current_email());
  end if;
  update public.hr_requests set status = 'completed', completed_at = now(), completed_by = public.current_email(), completion_note = trim(p_note),
         updated_at = now(), version = version + 1 where id = p_id;
  perform public.req_event(p_id, 'implemented', 'approved', 'completed', p_note);
  return jsonb_build_object('ok', true, 'version', r.version + 1);
end $$;

-- Εξειδικευμένες ενέργειες HR/λογιστηρίου: παρακολουθούνται χωριστά από την υλοποίηση του manager
create table public.request_tasks (
  id          bigserial primary key,
  request_id  uuid not null references public.hr_requests(id) on delete cascade,
  owner_role  text not null check (owner_role in ('hr','accounting')),
  description text not null check (length(trim(description)) between 3 and 1000),
  status      text not null default 'open' check (status in ('open','done')),
  created_by  text not null,
  created_at  timestamptz not null default now(),
  done_by     text,
  done_at     timestamptz,
  done_note   text
);
create or replace function public.req_task_add(p_id uuid, p_role text, p_text text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_id bigint;
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, null);
  if p_role not in ('hr','accounting') then raise exception 'Επιλέξτε HR ή λογιστήριο.'; end if;
  insert into public.request_tasks(request_id, owner_role, description, created_by) values (p_id, p_role, trim(p_text), public.current_email()) returning id into v_id;
  perform public.req_event(p_id, 'task_added', null, null, trim(p_text), jsonb_build_object('task', v_id, 'owner_role', p_role), true);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
create or replace function public.req_task_done(p_task bigint, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t public.request_tasks; r public.hr_requests;
begin
  select * into t from public.request_tasks where id = p_task for update;
  if not found then raise exception 'Η ενέργεια δεν βρέθηκε.'; end if;
  select * into r from public.hr_requests where id = t.request_id;
  if not (public.my_role() = t.owner_role or public.my_role() = 'owner') or not public.can_see_store(r.store) then raise exception 'Δεν έχετε δικαίωμα για αυτή την ενέργεια.'; end if;
  if t.status = 'done' then return jsonb_build_object('ok', true, 'already', true); end if;
  update public.request_tasks set status = 'done', done_by = public.current_email(), done_at = now(), done_note = nullif(trim(p_note), '') where id = p_task;
  insert into public.hr_request_events(request_id, actor, actor_role, action, note, internal, data)
  values (t.request_id, public.current_email(), public.my_role(), 'task_done', nullif(trim(p_note), ''), true, jsonb_build_object('task', t.id));
  return jsonb_build_object('ok', true);
end $$;
create or replace function public.my_tasks()
returns table (id bigint, request_id uuid, ref text, employee_name text, store text, category text, description text, status text, created_at timestamptz, created_by text)
language sql stable security definer set search_path = public as $$
  select t.id, r.id, r.ref, r.employee_name, r.store, r.category, t.description, t.status, t.created_at, t.created_by
    from public.request_tasks t join public.hr_requests r on r.id = t.request_id
   where (t.owner_role = public.my_role() or public.my_role() = 'owner') and public.can_see_store(r.store)
   order by t.status, t.created_at desc
$$;

-- ─────────────── Ειδοποιήσεις απαντήσεων ───────────────
create or replace function public.notify_on_decision() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  select * into r from public.hr_requests where id = new.request_id;
  perform public.notify_request(new.request_id, 'decision_' || new.outcome,
    case new.outcome when 'approve' then 'Εγκρίθηκε' when 'reject' then 'Δεν εγκρίθηκε' else 'Ζητούνται διευκρινίσεις' end
    || case when new.is_revision then ' (αναθεώρηση)' else '' end || ': ' || public.req_category_label(r.category) || ' — ' || r.employee_name || ' (' || r.ref || ')');
  if new.is_revision then
    update public.hr_requests set impl_claimed_by = null, impl_claimed_at = null where id = new.request_id;
  end if;
  return new;
end $$;
create trigger hr_decisions_notify after insert on public.hr_decisions for each row execute function public.notify_on_decision();

create or replace function public.notify_on_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.hr_requests;
begin
  if new.action not in ('report_closed','warning_communicated') then return new; end if;
  select * into r from public.hr_requests where id = new.request_id;
  perform public.notify_request(new.request_id, new.action,
    case new.action when 'report_closed' then 'Ολοκληρώθηκε η εξέταση αναφοράς' else 'Κοινοποιήθηκε προειδοποίηση' end || ' — ' || r.employee_name || ' (' || r.ref || ')');
  return new;
end $$;
create trigger hr_events_notify after insert on public.hr_request_events for each row execute function public.notify_on_event();

create or replace function public.notif_list(p_all boolean default false)
returns table (id bigint, request_id uuid, ref text, store text, kind text, title text, created_at timestamptz, read_at timestamptz)
language sql stable security definer set search_path = public as $$
  select n.id, n.request_id, r.ref, r.store, n.kind, n.title, n.created_at, n.read_at
    from public.notifications n join public.hr_requests r on r.id = n.request_id
   where n.user_email = public.current_email() and public.can_see_store(r.store) and public.has_perm('requests.view')
     and (p_all or n.read_at is null)
   order by n.created_at desc limit 200
$$;
create or replace function public.notif_count() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.notifications n join public.hr_requests r on r.id = n.request_id
   where n.user_email = public.current_email() and n.read_at is null and public.can_see_store(r.store) and public.has_perm('requests.view')
$$;
-- Διαβάστηκε όταν ανοίγει το αίτημα (μόνο για τον τρέχοντα χρήστη)
create or replace function public.notif_read_request(p_request uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  update public.notifications set read_at = now() where user_email = public.current_email() and request_id = p_request and read_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ─────────────── Αποτελέσματα αξιολογήσεων στο πεδίο του χρήστη ───────────────
create or replace function public.assess_questionnaires()
returns table (id uuid, title text, kind text, status text, version int, specialties text[], starts_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select q.id, q.title, q.kind, q.status, v.version, q.specialties, q.starts_at, q.ends_at
    from public.questionnaires q left join public.questionnaire_versions v on v.id = q.current_version_id
   where q.status in ('active','closed') and (public.has_perm('assess.results') or public.has_perm('assess.manage'))
     and (q.kind <> 'exit_interview' or public.can_view_exit())
   order by q.created_at desc
$$;

create or replace function public.assess_results(p_qid uuid default null, p_code text default null)
returns table (attempt_id uuid, questionnaire_id uuid, title text, kind text, version int, employee_code text, employee_name text, store text,
               specialty text, state text, opened_role text, opened_by text, started_at timestamptz, submitted_at timestamptz, score numeric, max_score numeric)
language sql stable security definer set search_path = public as $$
  select a.id, q.id, q.title, q.kind, v.version, a.employee_code, a.employee_name, a.store, a.specialty, public.attempt_state(a, q),
         a.opened_role, a.opened_by, a.started_at, a.submitted_at,
         case when q.kind = 'assessment' then a.score end, case when q.kind = 'assessment' then a.max_score end
    from public.assessment_attempts a
    join public.questionnaires q on q.id = a.questionnaire_id
    join public.questionnaire_versions v on v.id = a.version_id
   where (p_qid is null or a.questionnaire_id = p_qid) and (p_code is null or a.employee_code = p_code)
     and (public.has_perm('assess.results') or public.has_perm('assess.manage') or public.has_perm('assess.grade'))
     and public.can_see_store(a.store)
     and (q.kind <> 'exit_interview' or public.can_view_exit())
   order by a.started_at desc
$$;

-- Πλήρης προβολή μιας αξιολόγησης. Σωστές επιλογές εμφανίζονται μόνο σε όσους διαχειρίζονται/βαθμολογούν.
create or replace function public.attempt_view(p_attempt uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.assessment_attempts; q public.questionnaires; v_keys boolean := public.has_perm('assess.manage') or public.has_perm('assess.grade');
begin
  select * into a from public.assessment_attempts where id = p_attempt;
  if not found then raise exception 'Η αξιολόγηση δεν βρέθηκε.'; end if;
  select * into q from public.questionnaires where id = a.questionnaire_id;
  if not (public.has_perm('assess.results') or v_keys) or not public.can_see_store(a.store) then raise exception 'Η αξιολόγηση δεν βρέθηκε στο πεδίο σας.'; end if;
  if q.kind = 'exit_interview' and not public.can_view_exit() then raise exception 'Το περιεχόμενο του Exit Interview είναι διαθέσιμο μόνο σε ΓΔ, HR και εκπαιδευτή.'; end if;
  return jsonb_build_object(
    'attempt', jsonb_build_object('id', a.id, 'employee_code', a.employee_code, 'employee_name', a.employee_name, 'store', a.store, 'specialty', a.specialty,
       'status', a.status, 'state', public.attempt_state(a, q), 'started_at', a.started_at, 'submitted_at', a.submitted_at,
       'score', case when q.kind = 'assessment' then a.score end, 'max_score', case when q.kind = 'assessment' then a.max_score end,
       'opened_by', a.opened_by, 'opened_role', a.opened_role,
       'version', (select version from public.questionnaire_versions where id = a.version_id)),
    'questionnaire', jsonb_build_object('id', q.id, 'title', q.title, 'kind', q.kind),
    'can_grade', public.has_perm('assess.grade') and q.kind = 'assessment',
    'questions', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'section', x.section, 'text', x.text, 'qtype', x.qtype, 'options', x.options,
        'scale_min', x.scale_min, 'scale_max', x.scale_max, 'correct', case when v_keys and q.kind = 'assessment' then x.correct end,
        'model_answer', case when v_keys and q.kind = 'assessment' then x.model_answer end,
        'answer', coalesce(an.answer, a.answers -> x.id::text), 'is_correct', case when q.kind = 'assessment' then an.is_correct end,
        'points', case when q.kind = 'assessment' then an.points end, 'max_points', case when q.kind = 'assessment' then an.max_points end,
        'needs_manual', coalesce(an.needs_manual, false) and q.kind = 'assessment', 'graded_at', an.graded_at)
        order by x.sort, x.row_no), '[]')
      from public.assessment_questions x
      left join public.assessment_answers an on an.attempt_id = a.id and an.question_id = x.id
     where x.version_id = a.version_id and (x.specialty is null or x.specialty = a.specialty)));
end $$;

-- ─────────────── Exit Interview: αναφορές λόγων αποχώρησης & ευρημάτων (ΜΟΝΟ ΓΔ/HR/εκπαιδευτής) ───────────────
create or replace function public.exit_report(p_qid uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_view_exit() then raise exception 'Οι αναφορές Exit Interview είναι διαθέσιμες μόνο σε ΓΔ, HR και εκπαιδευτή.'; end if;
  return jsonb_build_object(
    'submissions', (select coalesce(jsonb_agg(jsonb_build_object('attempt_id', a.id, 'questionnaire', q.title, 'employee_code', a.employee_code,
          'employee_name', a.employee_name, 'store', a.store, 'specialty', a.specialty, 'submitted_at', a.submitted_at,
          'leave_date', (select leave_date from public.employees where code = a.employee_code)) order by a.submitted_at desc), '[]')
        from public.assessment_attempts a join public.questionnaires q on q.id = a.questionnaire_id
       where q.kind = 'exit_interview' and a.status <> 'in_progress' and (p_qid is null or q.id = p_qid)
         and (p_from is null or a.submitted_at >= p_from) and (p_to is null or a.submitted_at < p_to + 1)),
    'questions', (select coalesce(jsonb_agg(qq order by qq->>'title', (qq->>'sort')::int), '[]') from (
        select jsonb_build_object('questionnaire_id', q.id, 'title', q.title, 'row_no', x.row_no, 'sort', x.sort, 'section', x.section, 'text', x.text,
          'qtype', x.qtype, 'options', x.options,
          'counts', (select coalesce(jsonb_object_agg(k, n), '{}') from (
               select o k, count(*) n from public.assessment_attempts a2
                 cross join lateral jsonb_array_elements_text(case jsonb_typeof(a2.answers -> x.id::text) when 'array' then a2.answers -> x.id::text
                                                                  when 'string' then jsonb_build_array(a2.answers -> x.id::text) else '[]'::jsonb end) o
                where a2.version_id = x.version_id and a2.status <> 'in_progress' and x.qtype in ('single','multi')
                  and (p_from is null or a2.submitted_at >= p_from) and (p_to is null or a2.submitted_at < p_to + 1)
                group by o) c),
          'scale_avg', (select round(avg((a2.answers ->> x.id::text)::numeric), 2) from public.assessment_attempts a2
                          where a2.version_id = x.version_id and a2.status <> 'in_progress' and x.qtype = 'scale' and jsonb_typeof(a2.answers -> x.id::text) = 'number'
                            and (p_from is null or a2.submitted_at >= p_from) and (p_to is null or a2.submitted_at < p_to + 1)),
          'texts', (select coalesce(jsonb_agg(jsonb_build_object('employee_name', a2.employee_name, 'store', a2.store, 'submitted_at', a2.submitted_at,
                       'text', a2.answers ->> x.id::text) order by a2.submitted_at desc), '[]') from public.assessment_attempts a2
                     where a2.version_id = x.version_id and a2.status <> 'in_progress' and x.qtype = 'text' and coalesce(trim(a2.answers ->> x.id::text), '') <> ''
                       and (p_from is null or a2.submitted_at >= p_from) and (p_to is null or a2.submitted_at < p_to + 1))) qq
          from public.assessment_questions x
          join public.questionnaire_versions v on v.id = x.version_id
          join public.questionnaires q on q.id = v.questionnaire_id
         where q.kind = 'exit_interview' and (p_qid is null or q.id = p_qid)
           and exists (select 1 from public.assessment_attempts a3 where a3.version_id = v.id and a3.status <> 'in_progress')) z));
end $$;

-- Exit Interview: q_create με είδος (η παλιά υπογραφή χωρίς είδος αντικαθίσταται)
drop function if exists public.q_create(text, text);
create or replace function public.q_create(p_title text, p_description text, p_kind text default 'assessment')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.require_perm('assess.manage');
  if coalesce(p_kind, 'assessment') not in ('assessment','exit_interview') then raise exception 'Άγνωστο είδος ερωτηματολογίου.'; end if;
  insert into public.questionnaires(title, description, created_by, kind) values (trim(p_title), nullif(trim(p_description),''), public.current_email(), coalesce(p_kind, 'assessment')) returning id into v_id;
  insert into public.questionnaire_versions(questionnaire_id, version, created_by) values (v_id, 1, public.current_email());
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.req_complete(p_id uuid, p_note text, p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.hr_requests; v_flow text;
begin
  perform public.require_perm('requests.decide');
  r := public.req_lock(p_id, p_version);
  v_flow := public.req_flow(r.category);
  if length(trim(coalesce(p_note,''))) < 3 then raise exception 'Γράψτε σύντομη σημείωση ολοκλήρωσης.'; end if;
  if v_flow = 'report' then
    if r.status not in ('submitted','under_review') then raise exception 'Η αναφορά δεν είναι σε εξέταση.'; end if;
  elsif v_flow <> 'warning' then
    raise exception 'Η υλοποίηση εγκεκριμένων αιτημάτων γίνεται από τον manager του καταστήματος («Αναλαμβάνω την υλοποίηση»).';
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

create or replace function public.q_save_questions(p_id uuid, p_rows jsonb, p_filename text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_parsed jsonb; v_ver uuid; q jsonb;
begin
  perform public.require_perm('assess.manage');
  if not exists (select 1 from public.questionnaires where id = p_id) then raise exception 'Το ερωτηματολόγιο δεν βρέθηκε.'; end if;
  v_parsed := public.q_parse_rows(p_rows);
  if public.q_kind(p_id) = 'exit_interview' then
    v_parsed := jsonb_set(v_parsed, '{errors}', (v_parsed->'errors') || coalesce((select jsonb_agg(jsonb_build_object('row', qq->'row_no',
      'msg', 'Το Exit Interview δεν έχει σωστές απαντήσεις ούτε βαθμούς (αφήστε κενές τις στήλες).')) from jsonb_array_elements(v_parsed->'questions') qq
      where qq->>'points' is not null or jsonb_typeof(qq->'correct') = 'array' or qq->>'scale_rule' is not null), '[]'::jsonb));
  end if;
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

create or replace function public.q_check(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q public.questionnaires; v public.questionnaire_versions; v_errs jsonb := '[]'::jsonb; s text; v_est int;
begin
  select * into q from public.questionnaires where id = p_id;
  select * into v from public.questionnaire_versions where questionnaire_id = p_id order by version desc limit 1;
  if not exists (select 1 from public.assessment_questions where version_id = v.id) then v_errs := v_errs || to_jsonb('Δεν υπάρχουν ερωτήσεις.'::text); end if;
  if cardinality(q.specialties) = 0 and q.kind <> 'exit_interview' then v_errs := v_errs || to_jsonb('Ορίστε σε ποιες ειδικότητες απευθύνεται.'::text); end if;
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
  select count(*) into v_est from public.assessment_questions where version_id = v.id and key_status = 'estimate';
  if v.status = 'draft' and v_est > 0 then
    v_errs := v_errs || to_jsonb(format('Υπάρχουν %s σωστές απαντήσεις «κατ'' εκτίμηση» που δεν έχετε επιβεβαιώσει (καρτέλα «Σωστές απαντήσεις»).', v_est));
  end if;
  return v_errs;
end $$;

create or replace function public.link_create(p_qid uuid, p_codes text[], p_starts text, p_ends text, p_reassess boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q public.questionnaires; e public.employees; prev public.assessment_attempts; g public.assessment_assignments;
  v_s timestamptz := public.athens_ts(p_starts); v_e timestamptz := public.athens_ts(p_ends);
  v_code text; v_token text; v_ver uuid; v_round int; v_out jsonb := '[]'::jsonb; v_n int := 0;
begin
  perform public.require_perm('assess.manage');
  select * into q from public.questionnaires where id = p_qid for update;
  if not found or q.status <> 'active' or q.current_version_id is null then raise exception 'Το ερωτηματολόγιο πρέπει να είναι ενεργό.'; end if;
  if v_s is null or v_e is null then raise exception 'Συμπληρώστε έναρξη και λήξη διαθεσιμότητας.'; end if;
  if v_e <= v_s then raise exception 'Η λήξη πρέπει να είναι μετά την έναρξη.'; end if;
  if v_e <= now() then raise exception 'Η λήξη έχει ήδη περάσει.'; end if;
  if coalesce(cardinality(p_codes), 0) = 0 then raise exception 'Επιλέξτε συμμετέχοντες.'; end if;
  if cardinality(p_codes) > 500 then raise exception 'Έως 500 εργαζόμενοι ανά δημιουργία.'; end if;
  foreach v_code in array (select array_agg(distinct c) from unnest(p_codes) c) loop
    begin
      select * into e from public.employees where code = v_code;
      if not found then raise exception 'Ο κωδικός δεν βρέθηκε.'; end if;
      if e.status <> 'Ενεργός' and q.kind <> 'exit_interview' then raise exception 'Ο εργαζόμενος είναι ανενεργός.'; end if;
      if q.kind <> 'exit_interview' and (e.specialty is null or not (e.specialty = any(q.specialties))) then raise exception 'Το ερωτηματολόγιο δεν αφορά την ειδικότητα του εργαζομένου.'; end if;
      if exists (select 1 from public.assessment_assignments where questionnaire_id = p_qid and employee_code = v_code and status = 'active' and completed_at is null) then
        raise exception 'Υπάρχει ήδη ενεργός σύνδεσμος. Χρησιμοποιήστε «Αντιγραφή» ή «Επανέκδοση».';
      end if;
      if exists (select 1 from public.assessment_attempts where questionnaire_id = p_qid and employee_code = v_code and status <> 'in_progress') and not coalesce(p_reassess, false) then
        raise exception 'Έχει ήδη υποβάλει αυτή την αξιολόγηση. Για νέα αξιολόγηση επιλέξτε «Επαναξιολόγηση».';
      end if;
      -- Μισή συμπλήρωση από την υπάρχουσα ροή: συνεχίζει μέσω του συνδέσμου, με τις απαντήσεις της
      select * into prev from public.assessment_attempts where questionnaire_id = p_qid and employee_code = v_code and assignment_id is null and status = 'in_progress' for update;
      v_ver := coalesce(prev.version_id, q.current_version_id);
      select count(*) + 1 into v_round from public.assessment_attempts where questionnaire_id = p_qid and employee_code = v_code and status <> 'in_progress';
      v_token := public.fill_new_token();
      insert into public.assessment_assignments(questionnaire_id, version_id, employee_code, employee_name, store, specialty, company,
             starts_at, ends_at, token_hash, round, created_by)
      values (p_qid, v_ver, e.code, e.first || ' ' || e.last, e.store, coalesce(prev.specialty, e.specialty), e.company,
             v_s, v_e, public.fill_hash(v_token), v_round, public.current_email())
      returning * into g;
      insert into public.assessment_link_secrets(assignment_id, token) values (g.id, v_token);
      if prev.id is not null then
        update public.assessment_attempts set assignment_id = g.id, due_at = g.ends_at where id = prev.id;
        update public.fill_sessions set cancelled_at = now(), cancelled_by = public.current_email()
         where attempt_id = prev.id and completed_at is null and cancelled_at is null;
      end if;
      perform public.link_event(g.id, public.current_email(), 'created', jsonb_build_object('starts_at', v_s, 'ends_at', v_e,
        'version', (select version from public.questionnaire_versions where id = v_ver), 'round', v_round, 'continued_attempt', prev.id is not null));
      v_n := v_n + 1;
      v_out := v_out || jsonb_build_object('employee_code', e.code, 'employee_name', g.employee_name, 'store', g.store, 'ok', true,
                                           'assignment_id', g.id, 'token', v_token, 'round', v_round);
    exception when others then
      v_out := v_out || jsonb_build_object('employee_code', v_code, 'employee_name', (select first || ' ' || last from public.employees where code = v_code),
        'ok', false, 'error', case when sqlerrm like '%one_open%' or sqlerrm like '%duplicate%' then 'Υπάρχει ήδη ενεργός σύνδεσμος.' else sqlerrm end);
    end;
  end loop;
  return jsonb_build_object('created', v_n, 'rows', v_out);
end $$;

alter table public.request_tasks enable row level security;
create policy rt_read on public.request_tasks for select to authenticated
  using ((owner_role = public.my_role() or public.has_perm('requests.decide')) and exists (select 1 from public.hr_requests r where r.id = request_id));
revoke all on public.request_tasks from anon, authenticated;
grant select on public.request_tasks to authenticated;

revoke execute on all functions in schema public from public, anon;
revoke execute on function public.notify_on_decision(), public.notify_on_event() from authenticated;
grant execute on function public.req_impl_claim(uuid, int), public.req_impl_complete(uuid, text, jsonb, int), public.req_task_add(uuid, text, text),
  public.req_task_done(bigint, text), public.my_tasks(), public.notif_list(boolean), public.notif_count(), public.notif_read_request(uuid),
  public.assess_questionnaires(), public.assess_results(uuid, text), public.attempt_view(uuid), public.exit_report(uuid, date, date),
  public.q_create(text, text, text) to authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
