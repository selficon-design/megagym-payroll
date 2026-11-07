-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Προσωπικοί σύνδεσμοι αξιολόγησης (έκδοση 2.2)
--
-- Η Γενική Διευθύντρια δημιουργεί για κάθε εργαζόμενο μια «ανάθεση» αξιολόγησης: συγκεκριμένο
-- ερωτηματολόγιο + έκδοση + εργαζόμενος (κωδικός) + δικό της διάστημα διαθεσιμότητας.
-- Κάθε ανάθεση έχει έναν ενεργό προσωπικό σύνδεσμο με τυχαίο κλειδί (χωρίς κωδικό ή στοιχεία εργαζομένου).
-- Το κλειδί αναζητείται στον server με το hash του· ο εργαζόμενος δεν χρειάζεται λογαριασμό ή email.
--
-- Προσθετική αλλαγή: δεν αλλάζει τα υπάρχοντα δεδομένα, τα ερωτηματολόγια από Excel, τα διαστήματα
-- διαθεσιμότητας ή την υπάρχουσα «Έναρξη συμπλήρωσης». Όλοι οι υπάρχοντες έλεγχοι πρόσβασης μένουν.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

create table public.assessment_assignments (
  id               uuid primary key default gen_random_uuid(),
  questionnaire_id uuid not null references public.questionnaires(id),
  version_id       uuid not null references public.questionnaire_versions(id),
  employee_code    text not null references public.employees(code) on update cascade,
  employee_name    text not null,
  store            text not null,
  specialty        text not null,
  company          text,
  starts_at        timestamptz not null,
  ends_at          timestamptz not null,
  status           text not null default 'active' check (status in ('active','cancelled')),
  token_hash       text unique,                 -- sha256 του ενεργού κλειδιού· null όταν ακυρωθεί
  link_no          int not null default 1,      -- πόσες φορές εκδόθηκε σύνδεσμος για την ανάθεση
  round            int not null default 1,      -- 1 = αρχική αξιολόγηση, 2+ = επαναξιολόγηση (νέα ανάθεση)
  created_by       text not null,
  created_at       timestamptz not null default now(),
  completed_at     timestamptz,                 -- οριστική υποβολή
  cancelled_at     timestamptz,
  cancelled_by     text,
  constraint asg_window check (ends_at > starts_at),
  constraint asg_token  check (status = 'cancelled' or completed_at is not null or token_hash is not null)
);
create index assessment_assignments_q_idx   on public.assessment_assignments(questionnaire_id);
create index assessment_assignments_emp_idx on public.assessment_assignments(employee_code);
-- Μία ανοιχτή (μη ολοκληρωμένη) ανάθεση ανά εργαζόμενο και ερωτηματολόγιο
create unique index assessment_assignments_one_open on public.assessment_assignments(questionnaire_id, employee_code)
  where status = 'active' and completed_at is null;

-- Το ίδιο το κλειδί, ώστε η ΓΔ να μπορεί να ξανα-αντιγράψει τον σύνδεσμο. ΚΑΜΙΑ απευθείας πρόσβαση:
-- διαβάζεται μόνο από τη συνάρτηση της ΓΔ (assessment_links).
create table public.assessment_link_secrets (
  assignment_id uuid primary key references public.assessment_assignments(id) on delete cascade,
  token         text not null
);

-- Ιστορικό ανάθεσης (δημιουργία, επανέκδοση, ακύρωση, αλλαγή διαθεσιμότητας, άνοιγμα, υποβολή). Δεν αλλάζει.
create table public.assessment_assignment_events (
  id            bigserial primary key,
  assignment_id uuid not null references public.assessment_assignments(id) on delete cascade,
  at            timestamptz not null default now(),
  actor         text not null,
  action        text not null check (action in ('created','reissued','cancelled','window_changed','opened','submitted')),
  detail        jsonb not null default '{}'::jsonb
);
create index assessment_assignment_events_idx on public.assessment_assignment_events(assignment_id, at);
create trigger assignment_events_append_only before update or delete on public.assessment_assignment_events
  for each row when (pg_trigger_depth() = 0) execute function public.append_only();

-- Οι προσπάθειες από σύνδεσμο ανήκουν σε μία ανάθεση. Η επαναξιολόγηση είναι νέα, διακριτή ανάθεση,
-- άρα το «μία προσπάθεια ανά εργαζόμενο και ερωτηματολόγιο» ισχύει πλέον μόνο για την υπάρχουσα ροή.
alter table public.assessment_attempts
  add column assignment_id uuid unique references public.assessment_assignments(id),
  add column due_at timestamptz;   -- προθεσμία της ανάθεσης (κενό = προθεσμία ερωτηματολογίου)
alter table public.assessment_attempts drop constraint assessment_attempts_questionnaire_id_employee_code_key;
create unique index assessment_attempts_one_legacy on public.assessment_attempts(questionnaire_id, employee_code)
  where assignment_id is null;

-- ═══════════════════════════ Βοηθητικές (εσωτερικές) ═══════════════════════════
create or replace function public.link_event(p_asg uuid, p_actor text, p_action text, p_detail jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.assessment_assignment_events(assignment_id, actor, action, detail) values (p_asg, p_actor, p_action, coalesce(p_detail, '{}'::jsonb))
$$;

-- Έγκυρο κλειδί → ανάθεση (κλειδωμένη για τη συναλλαγή). Ίδιο μήνυμα για άγνωστο και ακυρωμένο σύνδεσμο.
create or replace function public.link_lookup(p_token text) returns public.assessment_assignments
language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments;
begin
  if p_token is null or length(p_token) < 32 or length(p_token) > 200 then
    raise exception 'Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί. Απευθυνθείτε στον υπεύθυνο του καταστήματος.';
  end if;
  select * into g from public.assessment_assignments where token_hash = public.fill_hash(p_token) and status = 'active' for update;
  if not found then raise exception 'Ο σύνδεσμος δεν είναι έγκυρος ή έχει ακυρωθεί. Απευθυνθείτε στον υπεύθυνο του καταστήματος.'; end if;
  return g;
end $$;

-- Η προσπάθεια της ανάθεσης (δημιουργείται στο πρώτο άνοιγμα μέσα στο διάστημα)
create or replace function public.link_attempt(g public.assessment_assignments, p_create boolean) returns public.assessment_attempts
language plpgsql security definer set search_path = public as $$
declare a public.assessment_attempts;
begin
  select * into a from public.assessment_attempts where assignment_id = g.id for update;
  if found or not p_create then return a; end if;
  insert into public.assessment_attempts(questionnaire_id, version_id, employee_code, employee_name, store, specialty, company,
         opened_by, opened_role, assignment_id, due_at)
  values (g.questionnaire_id, g.version_id, g.employee_code, g.employee_name, g.store, g.specialty, g.company,
         g.created_by, 'link', g.id, g.ends_at)
  returning * into a;
  perform public.link_event(g.id, 'employee:' || g.employee_code, 'opened', jsonb_build_object('link_no', g.link_no));
  return a;
end $$;

-- Κατάσταση ανάθεσης με την ώρα του server
create or replace function public.link_state(g public.assessment_assignments, a public.assessment_attempts) returns text
language sql stable as $$
  select case
    when a.id is not null and a.status in ('submitted','pending_manual') then a.status
    when g.status = 'cancelled' then 'cancelled'
    when now() < g.starts_at then 'scheduled'
    when now() > g.ends_at then 'expired'
    when a.id is not null then 'in_progress'
    else 'ready' end
$$;

-- ═══════════════════════════ Σελίδα εργαζομένου (χωρίς λογαριασμό, μόνο με το κλειδί) ═══════════════════════════
-- Επιστρέφει ΜΟΝΟ ό,τι χρειάζεται η οθόνη: ποτέ σωστές απαντήσεις, βαθμούς, κανόνες, ούτε υποβληθείσες απαντήσεις.
create or replace function public.link_get(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments; q public.questionnaires; a public.assessment_attempts; v_base jsonb;
begin
  g := public.link_lookup(p_token);
  select * into q from public.questionnaires where id = g.questionnaire_id;
  a := public.link_attempt(g, false);
  v_base := jsonb_build_object('title', q.title, 'employee', jsonb_build_object('name', g.employee_name, 'store', g.store),
                               'starts_at', g.starts_at, 'ends_at', g.ends_at, 'now', now());
  if g.completed_at is not null or (a.id is not null and a.status <> 'in_progress') then
    return v_base || jsonb_build_object('state', 'submitted');
  end if;
  if q.status <> 'active' then return v_base || jsonb_build_object('state', 'closed'); end if;
  if now() < g.starts_at then return v_base || jsonb_build_object('state', 'scheduled'); end if;
  if now() > g.ends_at then return v_base || jsonb_build_object('state', 'expired'); end if;
  a := public.link_attempt(g, true);
  return v_base || jsonb_build_object('state', 'open', 'description', q.description,
    'answers', a.answers, 'saved_at', a.last_saved_at,
    'questions', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', x.id, 'section', x.section, 'text', x.text, 'qtype', x.qtype, 'options', x.options, 'required', x.required,
        'scale_min', x.scale_min, 'scale_max', x.scale_max, 'scale_min_label', x.scale_min_label, 'scale_max_label', x.scale_max_label)
        order by x.sort, x.row_no), '[]')
      from public.assessment_questions x where x.version_id = g.version_id and (x.specialty is null or x.specialty = g.specialty)));
end $$;

create or replace function public.link_check_open(g public.assessment_assignments) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if (select status from public.questionnaires where id = g.questionnaire_id) <> 'active' then raise exception 'Η αξιολόγηση δεν είναι πλέον διαθέσιμη.'; end if;
  if now() < g.starts_at then raise exception 'Η αξιολόγηση δεν είναι ακόμη διαθέσιμη (από %, ώρα Ελλάδας).', to_char(g.starts_at at time zone 'Europe/Athens', 'DD/MM/YYYY HH24:MI'); end if;
  if now() > g.ends_at then raise exception 'Η προθεσμία έληξε στις % (ώρα Ελλάδας). Οι απαντήσεις δεν υποβλήθηκαν.', to_char(g.ends_at at time zone 'Europe/Athens', 'DD/MM/YYYY HH24:MI'); end if;
end $$;

-- Προσωρινή αποθήκευση (δεν είναι υποβολή)
create or replace function public.link_save(p_token text, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments; a public.assessment_attempts;
begin
  g := public.link_lookup(p_token);
  a := public.link_attempt(g, false);
  if g.completed_at is not null or (a.id is not null and a.status <> 'in_progress') then raise exception 'Η αξιολόγηση έχει ήδη υποβληθεί.'; end if;
  perform public.link_check_open(g);
  a := public.link_attempt(g, true);
  update public.assessment_attempts set answers = public.fill_clean_answers(a, coalesce(p_answers, '{}')), last_saved_at = now() where id = a.id;
  return jsonb_build_object('ok', true, 'saved_at', now());
end $$;

-- Οριστική υποβολή. Η ανάθεση κλειδώνεται: διπλό πάτημα ή δεύτερη καρτέλα δεν δημιουργούν δεύτερη υποβολή.
create or replace function public.link_submit(p_token text, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments; a public.assessment_attempts; v_clean jsonb; v_missing int;
begin
  g := public.link_lookup(p_token);
  a := public.link_attempt(g, false);
  if g.completed_at is not null or (a.id is not null and a.status <> 'in_progress') then return jsonb_build_object('ok', true, 'already', true); end if;
  perform public.link_check_open(g);
  a := public.link_attempt(g, true);
  v_clean := public.fill_clean_answers(a, coalesce(p_answers, a.answers));
  select count(*) into v_missing from public.assessment_questions x
   where x.version_id = a.version_id and (x.specialty is null or x.specialty = a.specialty) and x.required
     and (not v_clean ? x.id::text or v_clean -> x.id::text in ('null'::jsonb, '""'::jsonb, '[]'::jsonb));
  if v_missing > 0 then raise exception 'Υπάρχουν % υποχρεωτικές ερωτήσεις χωρίς απάντηση.', v_missing; end if;
  update public.assessment_attempts set answers = v_clean, submitted_at = now(), last_saved_at = now(), status = 'submitted' where id = a.id;
  perform public.grade_attempt(a.id);
  update public.assessment_assignments set completed_at = now() where id = g.id;
  perform public.link_event(g.id, 'employee:' || g.employee_code, 'submitted', jsonb_build_object('link_no', g.link_no));
  return jsonb_build_object('ok', true);
end $$;

-- ═══════════════════════════ Διαχείριση (μόνο Γενική Διευθύντρια) ═══════════════════════════
-- Δημιουργία προσωπικών συνδέσμων για επιλεγμένους εργαζόμενους. Αποτέλεσμα ανά εργαζόμενο.
create or replace function public.link_create(p_qid uuid, p_codes text[], p_starts text, p_ends text, p_reassess boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q public.questionnaires; e public.employees; prev public.assessment_attempts; g public.assessment_assignments;
  v_s timestamptz := public.athens_ts(p_starts); v_e timestamptz := public.athens_ts(p_ends);
  v_code text; v_token text; v_ver uuid; v_round int; v_out jsonb := '[]'::jsonb; v_n int := 0;
begin
  perform public.require_role(array['owner']);
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
      if e.status <> 'Ενεργός' then raise exception 'Ο εργαζόμενος είναι ανενεργός.'; end if;
      if e.specialty is null or not (e.specialty = any(q.specialties)) then raise exception 'Το ερωτηματολόγιο δεν αφορά την ειδικότητα του εργαζομένου.'; end if;
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

-- Επανέκδοση: νέο κλειδί, ο προηγούμενος σύνδεσμος παύει ΑΜΕΣΑ. Οι προσωρινές απαντήσεις μένουν.
create or replace function public.link_reissue(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments; v_token text := public.fill_new_token();
begin
  perform public.require_role(array['owner']);
  select * into g from public.assessment_assignments where id = p_id for update;
  if not found then raise exception 'Η ανάθεση δεν βρέθηκε.'; end if;
  if g.completed_at is not null or exists (select 1 from public.assessment_attempts where assignment_id = g.id and status <> 'in_progress') then
    raise exception 'Η αξιολόγηση έχει ήδη υποβληθεί· ο σύνδεσμος δεν επανεκδίδεται. Για νέα αξιολόγηση δημιουργήστε νέα ανάθεση (Επαναξιολόγηση).';
  end if;
  if g.status = 'cancelled' and exists (select 1 from public.assessment_assignments where questionnaire_id = g.questionnaire_id and employee_code = g.employee_code
       and status = 'active' and completed_at is null and id <> g.id) then
    raise exception 'Υπάρχει ήδη άλλος ενεργός σύνδεσμος για τον εργαζόμενο σε αυτή την αξιολόγηση.';
  end if;
  update public.assessment_assignments set token_hash = public.fill_hash(v_token), link_no = link_no + 1, status = 'active', cancelled_at = null, cancelled_by = null
   where id = g.id;
  insert into public.assessment_link_secrets(assignment_id, token) values (g.id, v_token)
    on conflict (assignment_id) do update set token = excluded.token;
  perform public.link_event(g.id, public.current_email(), 'reissued', jsonb_build_object('link_no', g.link_no + 1, 'was_cancelled', g.status = 'cancelled'));
  return jsonb_build_object('ok', true, 'token', v_token, 'link_no', g.link_no + 1);
end $$;

-- Ακύρωση συνδέσμου (οι προσωρινές απαντήσεις μένουν· μπορεί να επανεκδοθεί)
create or replace function public.link_cancel(p_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments;
begin
  perform public.require_role(array['owner']);
  select * into g from public.assessment_assignments where id = p_id for update;
  if not found then raise exception 'Η ανάθεση δεν βρέθηκε.'; end if;
  if g.completed_at is not null then raise exception 'Η αξιολόγηση έχει ήδη υποβληθεί· δεν υπάρχει ενεργός σύνδεσμος για ακύρωση.'; end if;
  if g.status = 'cancelled' then return jsonb_build_object('ok', true, 'already', true); end if;
  update public.assessment_assignments set status = 'cancelled', token_hash = null, cancelled_at = now(), cancelled_by = public.current_email() where id = g.id;
  delete from public.assessment_link_secrets where assignment_id = g.id;
  perform public.link_event(g.id, public.current_email(), 'cancelled', jsonb_build_object('link_no', g.link_no, 'note', nullif(trim(p_note), '')));
  return jsonb_build_object('ok', true);
end $$;

-- Αλλαγή διαθεσιμότητας / παράταση για μία ή περισσότερες αναθέσεις, με καταγραφή
create or replace function public.link_set_window(p_ids uuid[], p_starts text, p_ends text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.assessment_assignments; v_s timestamptz := public.athens_ts(p_starts); v_e timestamptz := public.athens_ts(p_ends); v_n int := 0;
begin
  perform public.require_role(array['owner']);
  if v_s is null or v_e is null then raise exception 'Συμπληρώστε έναρξη και λήξη.'; end if;
  if v_e <= v_s then raise exception 'Η λήξη πρέπει να είναι μετά την έναρξη.'; end if;
  if coalesce(cardinality(p_ids), 0) = 0 then raise exception 'Επιλέξτε αναθέσεις.'; end if;
  if not exists (select 1 from public.assessment_assignments where id = any(p_ids)) then raise exception 'Η ανάθεση δεν βρέθηκε.'; end if;
  for g in select * from public.assessment_assignments where id = any(p_ids) order by id for update loop
    if g.completed_at is not null then raise exception 'Η αξιολόγηση του/της % έχει ήδη υποβληθεί· η διαθεσιμότητά της δεν αλλάζει.', g.employee_name; end if;
    continue when g.starts_at = v_s and g.ends_at = v_e;
    update public.assessment_assignments set starts_at = v_s, ends_at = v_e where id = g.id;
    update public.assessment_attempts set due_at = v_e where assignment_id = g.id;
    perform public.link_event(g.id, public.current_email(), 'window_changed', jsonb_build_object(
      'old_starts', g.starts_at, 'old_ends', g.ends_at, 'new_starts', v_s, 'new_ends', v_e, 'note', nullif(trim(p_note), '')));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'changed', v_n);
end $$;

-- Λίστα αναθέσεων ενός ερωτηματολογίου με τους συνδέσμους (μόνο ΓΔ)
create or replace function public.assessment_links(p_qid uuid)
returns table (id uuid, employee_code text, employee_name text, store text, specialty text, version int, round int, link_no int,
               starts_at timestamptz, ends_at timestamptz, state text, token text, created_by text, created_at timestamptz,
               opened_at timestamptz, last_saved_at timestamptz, submitted_at timestamptz, cancelled_at timestamptz, attempt_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(array['owner']);
  return query
  select g.id, g.employee_code, g.employee_name, g.store, g.specialty, v.version, g.round, g.link_no, g.starts_at, g.ends_at,
         public.link_state(g, a), case when g.status = 'active' and g.completed_at is null then s.token end,
         g.created_by, g.created_at, a.started_at, a.last_saved_at, a.submitted_at, g.cancelled_at, a.id
    from public.assessment_assignments g
    join public.questionnaire_versions v on v.id = g.version_id
    left join public.assessment_attempts a on a.assignment_id = g.id
    left join public.assessment_link_secrets s on s.assignment_id = g.id
   where g.questionnaire_id = p_qid
   order by g.store, g.employee_name, g.created_at;
end $$;

create or replace function public.link_history(p_id uuid)
returns table (at timestamptz, actor text, action text, detail jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(array['owner','hr']);
  return query select e.at, e.actor, e.action, e.detail from public.assessment_assignment_events e where e.assignment_id = p_id order by e.at, e.id;
end $$;

-- ═══════════════════════════ Προσαρμογή υπαρχουσών συναρτήσεων ═══════════════════════════
-- Προθεσμία: της ανάθεσης, αλλιώς του ερωτηματολογίου
create or replace function public.attempt_state(a public.assessment_attempts, q public.questionnaires) returns text
language sql stable as $$
  select case
    when a.id is null then 'not_started'
    when a.status in ('submitted','pending_manual') then a.status
    when coalesce(a.due_at, q.ends_at) is not null and now() > coalesce(a.due_at, q.ends_at) then 'expired'
    else 'in_progress' end
$$;

-- Πιο πρόσφατη προσπάθεια ανά εργαζόμενο (με επαναξιολογήσεις μπορεί να υπάρχουν περισσότερες)
create or replace function public.assessment_targets(p_qid uuid)
returns table (employee_code text, employee_name text, store text, specialty text, state text, started_at timestamptz, submitted_at timestamptz)
language sql stable security definer set search_path = public as $$
  select e.code, e.first || ' ' || e.last, e.store, e.specialty, public.attempt_state(a, q), a.started_at, a.submitted_at
    from public.questionnaires q
    join public.employees e on e.status = 'Ενεργός' and e.specialty = any(q.specialties)
         and (q.participants is null or e.code = any(q.participants))
    left join lateral (select x.* from public.assessment_attempts x where x.questionnaire_id = q.id and x.employee_code = e.code
                        order by x.started_at desc limit 1) a on true
   where q.id = p_qid and q.status in ('active','closed')
     and public.my_role() in ('owner','hr','manager','trainer')
     and public.employee_in_scope(e.code)
   order by e.store, e.last, e.first
$$;

-- Καρτέλα εργαζομένου (manager/εκπαιδευτής): και οι αναθέσεις που δεν έχουν ανοιχτεί ακόμη. Χωρίς απαντήσεις ή βαθμούς.
create or replace function public.employee_assessments(p_code text)
returns table (questionnaire_id uuid, title text, version int, state text, store text, specialty text,
               opened_by text, started_at timestamptz, submitted_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select * from (
    select q.id, q.title, v.version, public.attempt_state(a, q), a.store, a.specialty, a.opened_by, a.started_at, a.submitted_at, coalesce(a.due_at, q.ends_at)
      from public.assessment_attempts a
      join public.questionnaires q on q.id = a.questionnaire_id
      join public.questionnaire_versions v on v.id = a.version_id
     where a.employee_code = p_code and public.employee_in_scope(p_code)
       and (public.my_role() in ('owner','hr') or public.can_see_store(a.store) or public.in_trainer_scope(a.store, a.specialty))
    union all
    select q.id, q.title, v.version, case when now() > g.ends_at then 'expired' else 'not_started' end, g.store, g.specialty, g.created_by, null::timestamptz, null::timestamptz, g.ends_at
      from public.assessment_assignments g
      join public.questionnaires q on q.id = g.questionnaire_id
      join public.questionnaire_versions v on v.id = g.version_id
     where g.employee_code = p_code and g.status = 'active' and g.completed_at is null
       and not exists (select 1 from public.assessment_attempts a where a.assignment_id = g.id)
       and public.employee_in_scope(p_code)
       and (public.my_role() in ('owner','hr') or public.can_see_store(g.store) or public.in_trainer_scope(g.store, g.specialty))
  ) x order by x.started_at desc nulls first
$$;

-- Η υπάρχουσα «Έναρξη συμπλήρωσης» μένει ίδια, με δύο προσθήκες ασφαλείας:
--  • δεν ξεκινά αν υπάρχει ενεργός προσωπικός σύνδεσμος (για να μην υπάρξουν δύο παράλληλες συμπληρώσεις)
--  • δεν ξεκινά αν ο εργαζόμενος έχει ήδη υποβάλει (από οποιαδήποτε ροή)
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
  if exists (select 1 from public.assessment_assignments where questionnaire_id = p_qid and employee_code = e.code and status = 'active' and completed_at is null) then
    raise exception 'Για τον εργαζόμενο υπάρχει προσωπικός σύνδεσμος αξιολόγησης. Η συμπλήρωση γίνεται από τον σύνδεσμο.';
  end if;
  if exists (select 1 from public.assessment_attempts where questionnaire_id = p_qid and employee_code = e.code and status <> 'in_progress') then
    raise exception 'Ο εργαζόμενος έχει ήδη υποβάλει αυτή την αξιολόγηση.';
  end if;
  select * into a from public.assessment_attempts where questionnaire_id = p_qid and employee_code = e.code and assignment_id is null for update;
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

-- Η παλιά φόρμα: προσπάθεια που μεταφέρθηκε σε σύνδεσμο δεν συνεχίζεται από παλιό κλειδί
create or replace function public.fill_check_window(a public.assessment_attempts) returns void
language plpgsql stable security definer set search_path = public as $$
declare q public.questionnaires;
begin
  if a.assignment_id is not null then raise exception 'Η αξιολόγηση συμπληρώνεται πλέον από τον προσωπικό σύνδεσμο.'; end if;
  select * into q from public.questionnaires where id = a.questionnaire_id;
  if q.status <> 'active' then raise exception 'Η αξιολόγηση δεν είναι πλέον ενεργή.'; end if;
  if now() < q.starts_at then raise exception 'Η αξιολόγηση δεν έχει ξεκινήσει ακόμη.'; end if;
  if now() > q.ends_at then raise exception 'Η προθεσμία έληξε στις %. Οι απαντήσεις δεν υποβλήθηκαν.', to_char(q.ends_at at time zone 'Europe/Athens', 'DD/MM/YYYY HH24:MI'); end if;
end $$;

-- ═══════════════════════════ Ασφάλεια ═══════════════════════════
alter table public.assessment_assignments       enable row level security;
alter table public.assessment_link_secrets      enable row level security;
alter table public.assessment_assignment_events enable row level security;

-- Κατάσταση αναθέσεων: ΓΔ και HR (χωρίς το hash του κλειδιού). Κλειδιά: καμία απευθείας πρόσβαση.
create policy asg_read  on public.assessment_assignments for select to authenticated using (public.my_role() in ('owner','hr'));
create policy asge_read on public.assessment_assignment_events for select to authenticated using (public.my_role() in ('owner','hr'));
revoke all on public.assessment_assignments, public.assessment_link_secrets, public.assessment_assignment_events from anon, authenticated;
grant select (id, questionnaire_id, version_id, employee_code, employee_name, store, specialty, company, starts_at, ends_at, status,
              link_no, round, created_by, created_at, completed_at, cancelled_at, cancelled_by) on public.assessment_assignments to authenticated;
grant select on public.assessment_assignment_events to authenticated;
revoke all on sequence public.assessment_assignment_events_id_seq from anon, authenticated;

-- Δικαιώματα εκτέλεσης: καμία νέα συνάρτηση δεν είναι ανοιχτή «από προεπιλογή»
revoke execute on all functions in schema public from public, anon;
revoke execute on function public.link_event(uuid, text, text, jsonb), public.link_lookup(text),
  public.link_attempt(public.assessment_assignments, boolean), public.link_state(public.assessment_assignments, public.assessment_attempts),
  public.link_check_open(public.assessment_assignments)
  from authenticated;
grant execute on function public.link_create(uuid, text[], text, text, boolean), public.link_reissue(uuid), public.link_cancel(uuid, text),
  public.link_set_window(uuid[], text, text, text), public.assessment_links(uuid), public.link_history(uuid)
  to authenticated;
-- Η σελίδα του προσωπικού συνδέσμου (χωρίς λογαριασμό) καλεί ΜΟΝΟ αυτές, με το κλειδί
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon, authenticated;
-- Η υπάρχουσα απομονωμένη φόρμα εργαζομένου (αμετάβλητη)
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb)
  to anon;
