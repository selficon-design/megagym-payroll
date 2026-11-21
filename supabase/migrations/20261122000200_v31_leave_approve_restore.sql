-- Έκδοση 3.1 · Αποκατάσταση έγκρισης ημερών άδειας όπως στην 3.0 (απόφαση 21/11/2026)
-- • Η έγκριση ΔΕΝ ζητά αιτιολογία ούτε διόρθωση των ημερών που έγραψε ο manager. Οι ημέρες χρέωσης προκύπτουν όπως πριν
--   από το σύστημα εργασίας / πρόγραμμα (π.χ. Παρασκευή–Σάββατο σε πενθήμερο: 2 ημερομηνίες, χρέωση 1 ημέρα).
-- • Η μόνη προσθήκη: έγκριση όλων ή μόνο συγκεκριμένων από τις αιτούμενες ημερομηνίες ("include"), χωρίς προηγούμενη πλήρη
--   έγκριση. Η χρέωση, η αφαίρεση υπολοίπου και η καταγραφή ληφθεισών ημερών μένουν η λογική της 3.0 (leave_plan/leave_book),
--   με αποδέσμευση των προηγούμενων ημερών του αιτήματος πριν από νέα καταχώριση (καμία διπλή αφαίρεση).
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο αντικατάσταση συναρτήσεων.

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
    -- Τμηματική έγκριση = μόνο ορισμένες από τις αιτούμενες ημερομηνίες (ή άλλο διάστημα). Καταγράφεται για ενημέρωση·
    -- ΔΕΝ μπλοκάρει την έγκριση. Οι ημέρες χρέωσης (π.χ. Παρασκευή–Σάββατο σε πενθήμερο = 1) δεν θεωρούνται διαφοροποίηση.
    v_diff := v_start is distinct from r.start_date or v_end is distinct from r.end_date or jsonb_array_length(v_dates) < (v_end - v_start + 1);
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
          case when v_diff then nullif(left(trim(coalesce(p->>'diff_reason', '')), 2000), '') end, v_dates)
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
         || case when new.requested_start is not null and (new.approved_start is distinct from new.requested_start or new.approved_end is distinct from new.requested_end
              or jsonb_array_length(coalesce(new.approved_dates, '[]')) < (new.approved_end - new.approved_start + 1)) then ' — εγκρίθηκαν μόνο ορισμένες από τις αιτούμενες ημερομηνίες' else '' end else '' end);
  if new.is_revision then
    update public.hr_requests set impl_claimed_by = null, impl_claimed_at = null where id = new.request_id;
  end if;
  return new;
end $$;
