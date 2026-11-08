-- v3 · Μεταφορά αδειών που εγκρίθηκαν πριν από την 3.0 στις ημέρες άδειας (ημερολόγιο, κάλυψη, υπόλοιπο).
-- ΜΗ ΚΑΤΑΣΤΡΟΦΙΚΗ: μόνο προσθήκες. Δεν αλλάζει αιτήματα ούτε αποφάσεις. Μπορεί να ξανατρέξει: παραλείπει όσα έχουν ήδη ημέρες.
-- Οι ημέρες χρεώνονται με τους ίδιους κανόνες (αργία → πρόγραμμα → πενθήμερο/εξαήμερο). Όπου λείπει το σύστημα εργασίας,
-- η ημέρα καταχωρίζεται χωρίς χρέωση και σημειώνεται στο ιστορικό του αιτήματος για έλεγχο (διόρθωση υπολοίπου από την καρτέλα).
-- Δεν μπλοκάρεται τίποτα: ημέρες που συμπίπτουν με άλλη εγκεκριμένη άδεια παραλείπονται και σημειώνονται.
do $$
declare r record; v_plan jsonb; x jsonb; v_id bigint; v_skipped int; v_n int; v_type text;
begin
  for r in
    select q.id, q.employee_code, q.store, q.leave_type,
           coalesce(d.approved_start, q.start_date) as s, coalesce(d.approved_end, q.end_date) as e
      from public.hr_requests q
      join lateral (select * from public.hr_decisions x where x.request_id = q.id and x.superseded_at is null order by x.decided_at desc limit 1) d on true
     where q.category = 'leave' and q.status in ('approved', 'completed') and d.outcome = 'approve'
       and coalesce(d.approved_start, q.start_date) is not null and coalesce(d.approved_end, q.end_date) is not null
       and not exists (select 1 from public.leave_days ld where ld.request_id = q.id)
       and exists (select 1 from public.employees e where e.code = q.employee_code)
     order by coalesce(d.approved_start, q.start_date)
  loop
    v_type := coalesce(r.leave_type, 'other');
    v_plan := public.leave_plan(r.employee_code, r.s, r.e, v_type, null, array[r.id]);
    v_skipped := 0; v_n := 0;
    for x in select * from jsonb_array_elements(v_plan->'days') loop
      if exists (select 1 from public.leave_days where employee_code = r.employee_code and day = (x->>'day')::date and status = 'active') then
        v_skipped := v_skipped + 1; continue;
      end if;
      insert into public.leave_days(request_id, employee_code, store, leave_type, day, chargeable, charge, created_by)
      values (r.id, r.employee_code, r.store, v_type, (x->>'day')::date, coalesce((x->>'workday')::boolean, false), coalesce((x->>'charge')::numeric, 0), 'system')
      returning id into v_id;
      insert into public.leave_charges(leave_day_id, leave_year, amount)
      select v_id, (b->>'year')::int, (b->>'amount')::numeric from jsonb_array_elements(coalesce(x->'buckets', '[]'::jsonb)) b;
      v_n := v_n + 1;
    end loop;
    perform public.req_event(r.id, 'leave_backfill', null, null,
      'Μεταφορά στις ημέρες άδειας της έκδοσης 3.0: ' || v_n || ' ημέρες'
        || case when coalesce((v_plan->>'unknown_days')::int, 0) > 0 and v_type = 'annual'
                then ' · ' || (v_plan->>'unknown_days') || ' χωρίς χρέωση επειδή λείπει πενθήμερο/εξαήμερο — ελέγξτε το υπόλοιπο' else '' end
        || case when v_skipped > 0 then ' · ' || v_skipped || ' παραλείφθηκαν (υπάρχει ήδη άλλη άδεια την ίδια ημέρα)' else '' end,
      jsonb_build_object('days', v_n, 'unknown', coalesce((v_plan->>'unknown_days')::int, 0), 'skipped', v_skipped), true, 'system');
  end loop;
end $$;
