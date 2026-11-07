-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Σωστές απαντήσεις, παραδείγματα βαθμολόγησης και αξιολογήσεις AI (έκδοση 2.4)
--
-- Η Γενική Διευθύντρια λέει προφορικά τη σωστή απάντηση κάθε ερώτησης· το AI την περνά «κατ' εκτίμηση».
-- Όλα γράφονται ΜΟΝΟ σε πρόχειρη έκδοση του ερωτηματολογίου. Η ενεργή έκδοση και οι υποβολές δεν αλλάζουν.
-- Η νέα έκδοση ενεργοποιείται μόνο όταν επιβεβαιωθούν όλες οι εκτιμήσεις (έλεγχος στην «Ενεργοποίηση»).
-- ═══════════════════════════════════════════════════════════════════════════════════════════

alter table public.assessment_questions
  add column model_answer text,               -- πρότυπη απάντηση / αιτιολόγηση (βοηθά τη χειροκίνητη βαθμολόγηση)
  add column key_status   text check (key_status in ('estimate','confirmed')),   -- null = από Excel ή χωρίς απάντηση
  add column key_spoken   text,               -- τι ειπώθηκε (για έλεγχο της εκτίμησης)
  add column key_note     text,               -- σημείωση του AI όταν δεν είναι σίγουρο
  add column key_by       text,
  add column key_at       timestamptz;

-- Η πρόχειρη έκδοση αντιγράφει και τα νέα πεδία
create or replace function public.q_draft_version(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v public.questionnaire_versions; v_new uuid;
begin
  select * into v from public.questionnaire_versions where questionnaire_id = p_id order by version desc limit 1;
  if found and v.status = 'draft' then return v.id; end if;
  insert into public.questionnaire_versions(questionnaire_id, version, multi_rule, created_by)
  values (p_id, coalesce(v.version, 0) + 1, v.multi_rule, public.current_email()) returning id into v_new;
  insert into public.assessment_questions(version_id, row_no, specialty, section, text, qtype, options, correct, points, required, sort,
         scale_min, scale_max, scale_min_label, scale_max_label, scale_rule, model_answer, key_status, key_spoken, key_note, key_by, key_at)
  select v_new, row_no, specialty, section, text, qtype, options, correct, points, required, sort,
         scale_min, scale_max, scale_min_label, scale_max_label, scale_rule, model_answer, key_status, key_spoken, key_note, key_by, key_at
    from public.assessment_questions where version_id = v.id;
  return v_new;
end $$;

-- Έναρξη: εξασφαλίζει πρόχειρη έκδοση (αντίγραφο της ενεργής) για να γραφτούν οι απαντήσεις
create or replace function public.q_key_begin(p_qid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ver uuid;
begin
  perform public.require_role(array['owner']);
  perform 1 from public.questionnaires where id = p_qid for update;
  if not found then raise exception 'Το ερωτηματολόγιο δεν βρέθηκε.'; end if;
  if not exists (select 1 from public.questionnaire_versions v join public.assessment_questions x on x.version_id = v.id where v.questionnaire_id = p_qid) then
    raise exception 'Το ερωτηματολόγιο δεν έχει ερωτήσεις.';
  end if;
  v_ver := public.q_draft_version(p_qid);
  update public.questionnaires set updated_at = now() where id = p_qid;
  return jsonb_build_object('version_id', v_ver, 'version', (select version from public.questionnaire_versions where id = v_ver));
end $$;

-- Αποθήκευση σωστής απάντησης / πρότυπης απάντησης / βαθμών μίας ερώτησης (μόνο σε πρόχειρη έκδοση)
create or replace function public.q_key_save(p_question_id uuid, p_correct jsonb, p_model text, p_points numeric,
                                             p_status text, p_spoken text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare x public.assessment_questions; v_status text; v_keys text[]; v_opts text[]; v_model text := nullif(trim(coalesce(p_model, '')), '');
begin
  perform public.require_role(array['owner']);
  select * into x from public.assessment_questions where id = p_question_id for update;
  if not found then raise exception 'Η ερώτηση δεν βρέθηκε.'; end if;
  if (select status from public.questionnaire_versions where id = x.version_id) <> 'draft' then
    raise exception 'Αλλαγές γίνονται μόνο σε πρόχειρη έκδοση. Ανοίξτε ξανά τις «Σωστές απαντήσεις».';
  end if;
  if p_status is not null and p_status not in ('estimate','confirmed') then raise exception 'Μη έγκυρη κατάσταση.'; end if;
  if p_points is not null and (p_points <= 0 or p_points > 1000) then raise exception 'Οι βαθμοί πρέπει να είναι θετικός αριθμός.'; end if;
  if length(coalesce(v_model, '')) > 4000 then raise exception 'Η πρότυπη απάντηση είναι πολύ μεγάλη (έως 4.000 χαρακτήρες).'; end if;
  v_opts := array(select o->>'key' from jsonb_array_elements(x.options) o);
  if p_correct is not null and jsonb_typeof(p_correct) = 'array' and jsonb_array_length(p_correct) > 0 then
    v_keys := array(select distinct k from jsonb_array_elements_text(p_correct) k order by 1);
  end if;
  if x.qtype in ('single','multi') then
    if exists (select 1 from unnest(coalesce(v_keys, '{}')) k where not (k = any(v_opts))) then raise exception 'Η σωστή απάντηση δεν αντιστοιχεί σε επιλογή της ερώτησης.'; end if;
    if x.qtype = 'single' and cardinality(v_keys) > 1 then raise exception 'Ερώτηση μίας επιλογής: μόνο μία σωστή απάντηση.'; end if;
    if p_points is not null and v_keys is null then raise exception 'Ορίστηκαν βαθμοί χωρίς σωστή απάντηση.'; end if;
  elsif v_keys is not null then
    raise exception 'Αυτός ο τύπος ερώτησης δεν έχει σωστή επιλογή· γράψτε πρότυπη απάντηση.';
  end if;
  if x.qtype = 'scale' and p_points is distinct from x.points then raise exception 'Οι βαθμοί της κλίμακας αλλάζουν μόνο από το Excel.'; end if;
  v_status := case when v_keys is null and v_model is null then null else coalesce(p_status, 'confirmed') end;
  update public.assessment_questions set
    correct = case when v_keys is null then null else to_jsonb(v_keys) end,
    model_answer = v_model, points = p_points, key_status = v_status,
    key_spoken = case when p_spoken is not null then left(p_spoken, 2000) else key_spoken end,
    key_note = case when p_status = 'estimate' then nullif(left(trim(coalesce(p_note, '')), 500), '') when p_status = 'confirmed' then null else key_note end,
    key_by = public.current_email(), key_at = now()
   where id = x.id;
  return jsonb_build_object('ok', true, 'key_status', v_status);
end $$;

-- Επιβεβαίωση εκτιμήσεων (όλων ή επιλεγμένων)
create or replace function public.q_key_confirm(p_version_id uuid, p_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform public.require_role(array['owner']);
  if (select status from public.questionnaire_versions where id = p_version_id) is distinct from 'draft' then raise exception 'Μόνο σε πρόχειρη έκδοση.'; end if;
  update public.assessment_questions set key_status = 'confirmed', key_note = null, key_by = public.current_email(), key_at = now()
   where version_id = p_version_id and key_status = 'estimate' and (p_ids is null or id = any(p_ids));
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'confirmed', v_n);
end $$;

-- Βαθμοί σε όσες ερωτήσεις επιλογής έχουν σωστή απάντηση αλλά όχι βαθμούς
create or replace function public.q_key_points(p_version_id uuid, p_points numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform public.require_role(array['owner']);
  if (select status from public.questionnaire_versions where id = p_version_id) is distinct from 'draft' then raise exception 'Μόνο σε πρόχειρη έκδοση.'; end if;
  if p_points is null or p_points <= 0 or p_points > 1000 then raise exception 'Οι βαθμοί πρέπει να είναι θετικός αριθμός.'; end if;
  update public.assessment_questions set points = p_points
   where version_id = p_version_id and qtype in ('single','multi') and correct is not null and points is null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'updated', v_n);
end $$;

-- Ενεργοποίηση: δεν περνούν εκτιμήσεις του AI που δεν έχουν επιβεβαιωθεί
create or replace function public.q_check(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q public.questionnaires; v public.questionnaire_versions; v_errs jsonb := '[]'::jsonb; s text; v_est int;
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
  select count(*) into v_est from public.assessment_questions where version_id = v.id and key_status = 'estimate';
  if v.status = 'draft' and v_est > 0 then
    v_errs := v_errs || to_jsonb(format('Υπάρχουν %s σωστές απαντήσεις «κατ'' εκτίμηση» που δεν έχετε επιβεβαιώσει (καρτέλα «Σωστές απαντήσεις»).', v_est));
  end if;
  return v_errs;
end $$;

-- ═══════════════════════════ Παραδείγματα βαθμολόγησης ═══════════════════════════
-- Πραγματικές απαντήσεις εργαζομένων που βαθμολόγησε η ΓΔ (0–10) με αιτιολογία. Διδάσκουν στο AI
-- τι αξίζει κάθε απάντηση και τι δεν πρέπει να λέγεται. Η ερώτηση αναγνωρίζεται με ερωτηματολόγιο + γραμμή,
-- ώστε τα παραδείγματα να ισχύουν και στις επόμενες εκδόσεις.
create table public.answer_examples (
  id               uuid primary key default gen_random_uuid(),
  questionnaire_id uuid not null references public.questionnaires(id) on delete cascade,
  row_no           int not null,
  question_id      uuid references public.assessment_questions(id) on delete set null,
  question_text    text not null,
  attempt_id       uuid references public.assessment_attempts(id) on delete set null,
  employee_code    text,
  answer_text      text not null,
  score            numeric(4,1) not null check (score between 0 and 10),
  reason           text,
  spoken           text,
  source           text not null default 'voice' check (source in ('voice','typed','correction')),
  created_by       text not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index answer_examples_one_per_answer on public.answer_examples(attempt_id, question_id) where attempt_id is not null;
create index answer_examples_q_idx on public.answer_examples(questionnaire_id, row_no);

-- Αξιολογήσεις AI: προτεινόμενος βαθμός 0–10 και αιτιολογία ανά απάντηση. Δεν αλλάζουν βαθμολογία μόνες τους.
create table public.ai_evaluations (
  id            uuid primary key default gen_random_uuid(),
  attempt_id    uuid not null references public.assessment_attempts(id) on delete cascade,
  question_id   uuid not null references public.assessment_questions(id) on delete cascade,
  score         numeric(4,1) not null check (score between 0 and 10),
  reason        text not null,
  examples_used int not null default 0,
  model         text,
  created_by    text not null,
  created_at    timestamptz not null default now(),
  status        text not null default 'suggested' check (status in ('suggested','accepted','corrected','rejected')),
  final_score   numeric(4,1) check (final_score between 0 and 10),
  final_reason  text,
  reviewed_by   text,
  reviewed_at   timestamptz,
  unique (attempt_id, question_id)
);

-- Η πιο πρόσφατη πρότυπη απάντηση για την ίδια ερώτηση (ίδιο ερωτηματολόγιο + γραμμή), σε όποια έκδοση κι αν ορίστηκε.
-- Έτσι απαντήσεις που υποβλήθηκαν σε παλιότερη έκδοση αξιολογούνται με τη σωστή απάντηση που ορίστηκε μετά.
create or replace function public.q_latest_model(p_question uuid) returns text
language sql stable security definer set search_path = public as $$
  select y.model_answer
    from public.assessment_questions x
    join public.questionnaire_versions vx on vx.id = x.version_id
    join public.questionnaire_versions vy on vy.questionnaire_id = vx.questionnaire_id
    join public.assessment_questions y on y.version_id = vy.id and y.row_no = x.row_no and y.model_answer is not null
   where x.id = p_question and public.my_role() in ('owner','hr')
   order by vy.version desc limit 1
$$;

-- Απαντήσεις ελεύθερου κειμένου ενός ερωτηματολογίου (υποβληθείσες), με παράδειγμα/αξιολόγηση αν υπάρχουν
create or replace function public.ex_answers(p_qid uuid)
returns table (attempt_id uuid, question_id uuid, row_no int, version int, section text, question_text text, model_answer text, points numeric,
               employee_code text, employee_name text, store text, answer_text text, submitted_at timestamptz,
               grade_points numeric, max_points numeric, graded_at timestamptz,
               example_id uuid, example_score numeric, example_reason text,
               eval_id uuid, eval_score numeric, eval_reason text, eval_status text, eval_final numeric, eval_examples int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(array['owner','hr']);
  return query
  select a.id, x.id, x.row_no, v.version, x.section, x.text, public.q_latest_model(x.id), x.points,
         a.employee_code, a.employee_name, a.store, an.answer #>> '{}', a.submitted_at,
         an.points, an.max_points, an.graded_at,
         e.id, e.score, e.reason, ev.id, ev.score, ev.reason, ev.status, ev.final_score, ev.examples_used
    from public.assessment_attempts a
    join public.questionnaire_versions v on v.id = a.version_id
    join public.assessment_questions x on x.version_id = a.version_id and x.qtype = 'text'
    join public.assessment_answers an on an.attempt_id = a.id and an.question_id = x.id
    left join public.answer_examples e on e.attempt_id = a.id and e.question_id = x.id
    left join public.ai_evaluations ev on ev.attempt_id = a.id and ev.question_id = x.id
   where a.questionnaire_id = p_qid and a.status in ('submitted','pending_manual')
     and nullif(trim(an.answer #>> '{}'), '') is not null
   order by x.sort, x.row_no, a.submitted_at;
end $$;

-- Παράδειγμα από απάντηση εργαζομένου (ή διόρθωση αξιολόγησης AI)
create or replace function public.ex_save(p_attempt uuid, p_question uuid, p_score numeric, p_reason text, p_spoken text default null, p_source text default 'voice')
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assessment_attempts; x public.assessment_questions; v_ans text; v_id uuid;
begin
  perform public.require_role(array['owner']);
  if p_score is null or p_score < 0 or p_score > 10 then raise exception 'Ο βαθμός πρέπει να είναι από 0 έως 10.'; end if;
  if p_source not in ('voice','typed','correction') then raise exception 'Μη έγκυρη πηγή.'; end if;
  select * into a from public.assessment_attempts where id = p_attempt;
  select * into x from public.assessment_questions where id = p_question;
  if a.id is null or x.id is null or x.version_id <> a.version_id then raise exception 'Η απάντηση δεν βρέθηκε.'; end if;
  select answer #>> '{}' into v_ans from public.assessment_answers where attempt_id = p_attempt and question_id = p_question;
  if nullif(trim(coalesce(v_ans, '')), '') is null then raise exception 'Δεν υπάρχει απάντηση σε αυτή την ερώτηση.'; end if;
  insert into public.answer_examples(questionnaire_id, row_no, question_id, question_text, attempt_id, employee_code, answer_text, score, reason, spoken, source, created_by)
  values (a.questionnaire_id, x.row_no, x.id, x.text, a.id, a.employee_code, left(v_ans, 4000), round(p_score, 1), nullif(left(trim(coalesce(p_reason, '')), 2000), ''),
          left(p_spoken, 2000), p_source, public.current_email())
  on conflict (attempt_id, question_id) where attempt_id is not null do update
    set score = excluded.score, reason = excluded.reason, spoken = coalesce(excluded.spoken, answer_examples.spoken), source = excluded.source, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.ex_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(array['owner']);
  delete from public.answer_examples where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Παραδείγματα για μία ερώτηση (ίδιο ερωτηματολόγιο + γραμμή, σε όποια έκδοση)
create or replace function public.ex_for_question(p_question uuid)
returns table (id uuid, answer_text text, score numeric, reason text, source text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(array['owner','hr']);
  return query select e.id, e.answer_text, e.score, e.reason, e.source, e.created_at
    from public.answer_examples e
    join public.assessment_questions x on x.id = p_question
    join public.questionnaire_versions v on v.id = x.version_id
   where e.questionnaire_id = v.questionnaire_id and e.row_no = x.row_no
   order by e.score desc, e.created_at;
end $$;

-- Αποθήκευση προτάσεων του AI (δεν αλλάζει όσες έχει ήδη ελέγξει η ΓΔ)
create or replace function public.ev_save(p_question uuid, p_rows jsonb, p_examples int, p_model text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; v_n int := 0;
begin
  perform public.require_role(array['owner']);
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if not exists (select 1 from public.assessment_answers where attempt_id = (r->>'attempt_id')::uuid and question_id = p_question) then continue; end if;
    insert into public.ai_evaluations(attempt_id, question_id, score, reason, examples_used, model, created_by)
    values ((r->>'attempt_id')::uuid, p_question, least(10, greatest(0, round((r->>'score')::numeric, 1))), left(coalesce(r->>'reason', ''), 2000), coalesce(p_examples, 0), left(p_model, 80), public.current_email())
    on conflict (attempt_id, question_id) do update
      set score = excluded.score, reason = excluded.reason, examples_used = excluded.examples_used, model = excluded.model,
          created_by = excluded.created_by, created_at = now()
      where ai_evaluations.status = 'suggested';
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'saved', v_n);
end $$;

-- Έλεγχος πρότασης AI: αποδοχή, διόρθωση (γίνεται και νέο παράδειγμα) ή απόρριψη.
-- Με αποδοχή/διόρθωση, αν η ερώτηση έχει βαθμούς, περνά ο βαθμός στη βαθμολογία (αναλογικά: βαθμός/10 × μέγιστο).
create or replace function public.ev_review(p_id uuid, p_action text, p_score numeric default null, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ev public.ai_evaluations; an public.assessment_answers; v_final numeric; v_pts numeric; v_applied boolean := false;
begin
  perform public.require_role(array['owner']);
  select * into ev from public.ai_evaluations where id = p_id for update;
  if not found then raise exception 'Η αξιολόγηση δεν βρέθηκε.'; end if;
  if p_action not in ('accept','correct','reject') then raise exception 'Μη έγκυρη ενέργεια.'; end if;
  if p_action = 'reject' then
    update public.ai_evaluations set status = 'rejected', reviewed_by = public.current_email(), reviewed_at = now() where id = ev.id;
    return jsonb_build_object('ok', true, 'applied', false);
  end if;
  v_final := case when p_action = 'correct' then p_score else ev.score end;
  if v_final is null or v_final < 0 or v_final > 10 then raise exception 'Ο βαθμός πρέπει να είναι από 0 έως 10.'; end if;
  update public.ai_evaluations set status = case when p_action = 'correct' then 'corrected' else 'accepted' end,
         final_score = v_final, final_reason = case when p_action = 'correct' then nullif(trim(coalesce(p_reason, '')), '') end,
         reviewed_by = public.current_email(), reviewed_at = now()
   where id = ev.id;
  if p_action = 'correct' then
    perform public.ex_save(ev.attempt_id, ev.question_id, v_final, coalesce(nullif(trim(coalesce(p_reason, '')), ''), 'Διόρθωση πρότασης AI (πρόταση: ' || ev.score || ')'), null, 'correction');
  end if;
  select * into an from public.assessment_answers where attempt_id = ev.attempt_id and question_id = ev.question_id;
  if an.max_points is not null then
    v_pts := round(v_final / 10 * an.max_points, 2);
    perform public.assessment_grade(ev.attempt_id, ev.question_id, v_pts);
    v_applied := true;
  end if;
  return jsonb_build_object('ok', true, 'applied', v_applied, 'points', v_pts, 'max_points', an.max_points);
end $$;

alter table public.answer_examples enable row level security;
alter table public.ai_evaluations  enable row level security;
create policy aex_read on public.answer_examples for select to authenticated using (public.my_role() in ('owner','hr'));
create policy aev_read on public.ai_evaluations  for select to authenticated using (public.my_role() in ('owner','hr'));
revoke all on public.answer_examples, public.ai_evaluations from anon, authenticated;
grant select on public.answer_examples, public.ai_evaluations to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.q_key_begin(uuid), public.q_key_save(uuid, jsonb, text, numeric, text, text, text),
  public.q_key_confirm(uuid, uuid[]), public.q_key_points(uuid, numeric),
  public.q_latest_model(uuid), public.ex_answers(uuid), public.ex_save(uuid, uuid, numeric, text, text, text), public.ex_delete(uuid), public.ex_for_question(uuid),
  public.ev_save(uuid, jsonb, int, text), public.ev_review(uuid, text, numeric, text) to authenticated;
-- (η σελίδα του προσωπικού συνδέσμου και η απομονωμένη φόρμα κρατούν τα δικαιώματά τους)
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
