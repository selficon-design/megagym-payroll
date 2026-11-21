\set ON_ERROR_STOP 1
-- Έκδοση 3.1 · Μισθοδοσία μόνο για μήνες απασχόλησης, αποχωρήσαντες στο μελλοντικό πρόγραμμα, «Ρεπό», διαγραφή vs
-- απόκρυψη, managers στη Ρεσεψιόν, ειδοποιήσεις λογιστηρίου μετά την οριστικοποίηση, βάρδιες μετά τα μεσάνυχτα και
-- ώρες μετά τις 22:00. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),('acc2@x.gr','Λογιστήριο 2','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά');
insert into employees(code,first,last,store,company,specialty,work_week,weekly_hours,hire_date) values
 ('P1','Άννα','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,40,'2025-01-01'),
 ('P2','Βασίλης','Βλάχος','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,40,'2026-11-15'),
 ('P3','Γωγώ','Γεωργίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,40,'2025-01-01'),
 ('M1','Δέσποινα','Δήμου','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη',5,40,'2024-01-01'),
 ('K1','Ελένη','Ευαγγέλου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5,40,'2025-01-01');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.slot(w jsonb, d text, s text) returns jsonb language sql as $$
  select x from jsonb_array_elements(w->'coverage'->d) x where x->>'slot' = s $$;
create or replace function pg_temp.emp(w jsonb, c text) returns jsonb language sql as $$
  select x from jsonb_array_elements(w->'employees') x where x->>'code' = c $$;

-- ═══════ 3. Υποχρεώσεις μισθοδοσίας μόνο για μήνες με απασχόληση ═══════
select pg_temp.as_user('hr@x.gr');
select emp_set_dates('P3', '2025-01-01', '2026-11-10', 'Αποχώρηση');
select pg_temp.eq((select string_agg(code, ',' order by code) from month_status('2026-10') where status = 'missing'), 'K1,M1,P1,P3', 'Οκτώβριος: όχι εκκρεμότητα για τον P2 (πρόσληψη 15/11)');
select pg_temp.eq((select string_agg(code || ':' || coalesce(employment, '-'), ',' order by code) from month_status('2026-11') where status = 'missing'), 'K1:-,M1:-,P1:-,P2:hire,P3:leave',
  'Νοέμβριος: μετρά ο μήνας πρόσληψης και ο μήνας αποχώρησης');
select pg_temp.eq((select count(*) from month_status('2026-12') where code = 'P3'), 0::bigint, 'Δεκέμβριος: καμία υποχρέωση μετά την αποχώρηση');
select pg_temp.eq(prepare_declarations('2026-10', '[{"code":"P2","amount":"500"}]')->'skipped'->0->>'reason', 'Εκτός περιόδου απασχόλησης (πρόσληψη 15/11/2026)', 'προετοιμασία πριν την πρόσληψη απορρίπτεται');
select pg_temp.eq(prepare_declarations('2026-12', '[{"code":"P3","amount":"500"}]')->'skipped'->0->>'reason', 'Εκτός περιόδου απασχόλησης (αποχώρηση 10/11/2026)', 'προετοιμασία μετά την αποχώρηση απορρίπτεται');
select pg_temp.eq((prepare_declarations('2026-11', '[{"code":"P3","amount":"300"}]')->>'created')::int, 1, 'μήνας αποχώρησης: δεκτή δήλωση');
select pg_temp.eq((select end_date from declarations where employee_code = 'P3' and month = '2026-11'), '2026-11-10'::date, 'λήξη περιόδου = ημέρα αποχώρησης');
-- υπογεγραμμένη δήλωση εκτός (μεταγενέστερα διορθωμένης) περιόδου: δεν κρύβεται, επισημαίνεται
select prepare_declarations('2026-10', '[{"code":"P1","amount":"900"}]');
select pg_temp.as_user('glyfada@x.gr');
select sign_declaration((select id from declarations where employee_code = 'P1' and month = '2026-10'),'Άννα Αλεξίου','data:image/png;base64,'||repeat('A',2000),'test-tablet');
select pg_temp.as_user('hr@x.gr');
select emp_set_dates('P1', '2026-11-01', null, 'Διόρθωση ημερομηνίας πρόσληψης');
select pg_temp.eq((select status || '|' || employment from month_status('2026-10') where code = 'P1'), 'signed|outside', 'υπογεγραμμένη δήλωση μένει ορατή, με ένδειξη «εκτός περιόδου»');
select pg_temp.eq((select count(*) from declarations where status = 'signed'), 1::bigint, 'καμία υπογεγραμμένη δήλωση δεν αλλοιώθηκε');
select emp_set_dates('P1', '2025-01-01', null, 'Επαναφορά');

-- ═══════ 12. Βάρδιες μετά τα μεσάνυχτα & ώρες μετά τις 22:00 ═══════
select pg_temp.eq(sched_minutes('[["17:00","01:30"]]'), 510, 'βάρδια 17:00–01:30 = 8,5 ώρες');
select pg_temp.eq(sched_night_minutes('[["17:00","23:30"]]'), 90, '17:00–23:30 → 1ώ30λ μετά τις 22:00');
select pg_temp.eq(sched_night_minutes('[["20:00","02:00"]]'), 240, '20:00–02:00 → 4 ώρες (και μετά τα μεσάνυχτα)');
select pg_temp.eq(sched_night_minutes('[["18:00","21:00"],["21:30","23:00"]]'), 60, 'σπαστό: μόνο το τμήμα μετά τις 22:00');
select pg_temp.eq(sched_night_minutes('[["21:00","23:00"],["22:30","23:30"]]'), 90, 'επικαλυπτόμενα διαστήματα χωρίς διπλομέτρηση');
select pg_temp.eq(sched_night_minutes('[["08:00","16:00"]]'), 0, 'πρωινή βάρδια: 0');
select pg_temp.eq(sched_night_minutes('[["16:00","24:00"]]'), 120, '16:00–24:00 → 2 ώρες');
select pg_temp.expect_fail($$select sched_segments('[["12:00","08:00"]]')$$, 'διάστημα πάνω από 16 ώρες (πιθανό λάθος)');
select pg_temp.expect_fail($$select sched_segments('[["10:00","10:00"]]')$$, 'λήξη ίδια με έναρξη');

select pg_temp.as_user('owner@x.gr');
insert into store_hours(store, specialty, weekday, opens, closes) select 'Γλυφάδα', 'Ρεσεψιόν', d, '06:30', '23:00' from generate_series(1, 7) d;
select pg_temp.as_user('glyfada@x.gr');
select sched_set_pattern('P1', '2026-11-30', '{"1":[["17:00","01:30"]],"2":[["08:00","16:00"]],"3":[["08:00","16:00"]],"4":[["08:00","16:00"]],"5":[["17:00","23:30"]]}', null);
select sched_set_pattern('P2', '2026-11-30', '{"1":[["06:30","14:30"]],"2":[["14:30","22:30"]],"3":[["14:30","22:30"]],"4":[["14:30","22:30"]],"5":[["14:30","22:30"]]}', null);
select sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν') as w \gset
select pg_temp.eq((pg_temp.emp(:'w','P1')->>'planned_hours')::numeric, 39.00, 'εβδομαδιαίες ώρες με βάρδια μετά τα μεσάνυχτα');
select pg_temp.eq((pg_temp.slot(:'w','2026-12-01','00:30')->>'count')::int, 1, 'η ουρά της βάρδιας (00:00–01:30) μετρά στην κάλυψη της επόμενης ημέρας');
select pg_temp.eq((pg_temp.slot(:'w','2026-12-01','01:30')->>'count')::int, 0, 'κάλυψη μέχρι τη λήξη της βάρδιας (01:30)');
select pg_temp.eq((pg_temp.emp(:'w','P1')->'days'->'2026-11-30'->>'night_minutes')::int, 210, 'ώρες μετά τις 22:00 στην ημέρα έναρξης (22:00–01:30)');
select pg_temp.expect_fail($$select sched_night('Γλυφάδα', '2026-11-30', '2026-12-06', 'Ρεσεψιόν')$$, 'manager: όχι προβολή λογιστηρίου για ώρες μετά τις 22:00');
select pg_temp.as_user('acc@x.gr');
select pg_temp.expect_fail($$select sched_week('Γλυφάδα', '2026-11-30', null)$$, 'λογιστήριο: δεν παίρνει γενική πρόσβαση στο πρόγραμμα');
select sched_night('Γλυφάδα', '2026-11-30', '2026-12-06', 'Ρεσεψιόν') as n \gset
select pg_temp.eq((select (x->'days'->>'2026-11-30')::int || '|' || (x->'days'->>'2026-12-04')::int || '|' || (x->>'total_minutes')::int from jsonb_array_elements(:'n'::jsonb->'employees') x where x->>'code' = 'P1'),
  '210|90|300', 'ανά εργαζόμενο, ανά ημέρα και σύνολο διαστήματος');
select pg_temp.eq((select (x->>'total_minutes')::int from jsonb_array_elements(:'n'::jsonb->'employees') x where x->>'code' = 'P2'), 120, 'P2: 4 × 30λ (14:30–22:30)');
select pg_temp.eq((:'n'::jsonb->>'total_minutes')::int, 420, 'σύνολο καταστήματος');
select pg_temp.eq((:'n'::jsonb->'by_day'->>'2026-12-01')::int, 30, 'σύνολο ημέρας');

-- ═══════ 5. «Ρεπό» · 6. Διαγραφή ωραρίου vs απόκρυψη ═══════
select pg_temp.as_user('glyfada@x.gr');
select sched_set_temp('P2', array['2026-12-02']::date[], null, null, 'off');
select sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν') as w \gset
select pg_temp.eq(pg_temp.emp(:'w','P2')->'days'->'2026-12-02'->>'kind' || '|' || (pg_temp.emp(:'w','P2')->'days'->'2026-12-02'->>'off') || '|' || (pg_temp.emp(:'w','P2')->'days'->'2026-12-02'->>'minutes'),
  'off|true|0', 'ρητή ένδειξη «Ρεπό», χωρίς ώρες');
select pg_temp.eq((pg_temp.slot(:'w','2026-12-02','21:00')->>'count')::int, 0, 'το ρεπό δεν μετρά στην κάλυψη');
select pg_temp.eq(pg_temp.emp(:'w','P1')->'days'->'2026-12-05'->>'kind', 'off', 'ημέρα χωρίς ωράριο στο σταθερό = Ρεπό');
-- Απόκρυψη έτοιμου ωραρίου: δεν αγγίζει αναθέσεις
select pg_temp.as_user('owner@x.gr');
insert into shift_templates(label, segments) values ('14:30–22:30', '[["14:30","22:30"]]');
update shift_templates set active = false where label = '14:30–22:30';
select pg_temp.eq((select (pg_temp.emp(sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν'),'P2')->>'planned_hours')::numeric), 32.00, 'η απόκρυψη δεν αφαιρεί ώρες ή αναθέσεις');
select shift_template_delete((select id from shift_templates where label = '14:30–22:30'));
select pg_temp.eq((select deleted_by from shift_templates where label = '14:30–22:30'), 'owner@x.gr', 'διαγραφή έτοιμου ωραρίου με ιστορικό (η γραμμή δεν σβήνεται)');
select pg_temp.eq((select (pg_temp.emp(sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν'),'P2')->>'planned_hours')::numeric), 32.00, 'ούτε η διαγραφή έτοιμου ωραρίου αγγίζει αναθέσεις');
select pg_temp.as_user('glyfada@x.gr');
select sched_finalize('Γλυφάδα', '2026-11-30');
select pg_temp.expect_fail($$select sched_delete('P2', array['2026-12-03']::date[], null)$$, 'διαγραφή σε οριστικοποιημένο χωρίς αιτιολογία');
select sched_delete('P2', array['2026-12-03']::date[], 'Αλλαγή διαθεσιμότητας');
select sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν') as w \gset
select pg_temp.eq((pg_temp.emp(:'w','P2')->>'planned_hours')::numeric || '|' || (pg_temp.emp(:'w','P2')->'days'->'2026-12-03'->>'deleted'), '24.00|true', 'η διαγραφή ενημερώνει τις ώρες');
select pg_temp.eq((pg_temp.slot(:'w','2026-12-03','21:00')->>'count')::int, 0, 'και την κάλυψη');
select pg_temp.eq((select count(*) from schedule_changes where change_type = 'deleted' and employee_code = 'P2' and prev_value ? '2026-12-03'), 1::bigint, 'ιστορικό με το προηγούμενο ωράριο');
select pg_temp.expect_fail($$select sched_delete('P2', array['2026-12-03']::date[], 'ξανά')$$, 'δεν υπάρχει ωράριο για διαγραφή');

-- ═══════ 8. Ειδοποιήσεις λογιστηρίου μετά την οριστικοποίηση ═══════
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq(sched_alert_count(), 1, 'το λογιστήριο ειδοποιήθηκε για τη διαγραφή (όχι για την ίδια την οριστικοποίηση)');
select pg_temp.eq((select store || '|' || employee_code || '|' || change_type || '|' || affected_from || '|' || reason || '|' || actor || '|' || (prev_value->'2026-12-03'->0->>0)
   from sched_alerts()), 'Γλυφάδα|P2|deleted|2026-12-03|Αλλαγή διαθεσιμότητας|glyfada@x.gr|14:30', 'κατάστημα, εργαζόμενος, ημερομηνία, προηγούμενη τιμή, χρήστης, αιτιολογία');
select pg_temp.as_user('glyfada@x.gr');
select sched_set_temp('P1', array['2026-12-02']::date[], '[["09:00","17:00"]]', 'Κάλυψη Τετάρτης');
reset role;
select pg_temp.eq((select count(*) from schedule_alerts), 4::bigint, 'προσθήκη/μεταβολή επίσης ειδοποιεί (2 χρήστες λογιστηρίου × 2 αλλαγές)');
select pg_temp.eq((select count(*) from schedule_alerts a join app_users u on u.email = a.user_email where u.role in ('owner','hr','manager')), 0::bigint, 'η ΓΔ (και άλλοι ρόλοι) ΔΕΝ ειδοποιούνται');
select pg_temp.eq((select count(*) from schedule_finalizations where store = 'Γλυφάδα'), 1::bigint, 'ο manager αλλάζει χωρίς έγκριση λογιστηρίου');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select sched_alert_read(null)$$, 'ο manager δεν έχει ειδοποιήσεις λογιστηρίου');
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq(sched_alert_read((select id from sched_alerts() order by id limit 1)), 1, 'ανάγνωση μίας ειδοποίησης');
select pg_temp.eq(sched_alert_count(), 1, 'κατάσταση ανάγνωσης ανά χρήστη');
select pg_temp.as_user('acc2@x.gr');
select pg_temp.eq(sched_alert_count(), 2, 'ο άλλος χρήστης λογιστηρίου έχει ακόμη 2 αδιάβαστες');
select pg_temp.as_user('glyfada@x.gr');
select sched_set_temp('P1', array['2026-12-14']::date[], '[["09:00","17:00"]]', null);
reset role;
select pg_temp.eq((select count(*) from schedule_alerts), 4::bigint, 'αλλαγή σε μη οριστικοποιημένη εβδομάδα: καμία ειδοποίηση');

-- ═══════ 4. Αποχωρήσαντες στο μελλοντικό πρόγραμμα ═══════
select pg_temp.as_user('glyfada@x.gr');
select sched_set_pattern('P3', '2026-11-02', '{"1":[["06:30","14:30"]],"3":[["06:30","14:30"]]}', 'Σταθερό πρόγραμμα');
select sched_week('Γλυφάδα', '2026-11-09', 'Ρεσεψιόν') as w \gset
select pg_temp.eq(pg_temp.emp(:'w','P3') is not null, true, 'εβδομάδα αποχώρησης: εμφανίζεται κανονικά (παλιές ημέρες)');
select pg_temp.eq((pg_temp.emp(:'w','P3')->'days'->'2026-11-09'->>'counts')::boolean || '|' || (pg_temp.emp(:'w','P3')->'days'->'2026-11-11'->>'departed'), 'true|true', 'μετρά έως την αποχώρηση, όχι μετά');
select sched_week('Γλυφάδα', '2026-11-16', 'Ρεσεψιόν') as w \gset
select pg_temp.eq(pg_temp.emp(:'w','P3') is null, true, 'μελλοντική εβδομάδα: χωρίς δική του στήλη');
select pg_temp.eq((select count(*) from jsonb_array_elements(:'w'::jsonb->'needs_cover') x where x->>'employee_code' = 'P3' and x->>'why' like 'αποχώρηση%'), 2::bigint,
  'οι προγραμματισμένες βάρδιές του → «χρειάζονται κάλυψη» (χωρίς αυτόματη αντικατάσταση)');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-16','07:00')->>'count')::int, 0, 'δεν μετρά στην κάλυψη');
select pg_temp.expect_fail($$select sched_set_temp('P3', array['2026-11-20']::date[], '[["08:00","16:00"]]', null)$$, 'δεν προσφέρεται για νέες βάρδιες μετά την αποχώρηση');
select pg_temp.expect_fail($$select sched_set_pattern('P3', '2026-11-23', '{"1":[["08:00","16:00"]]}', null)$$, 'ούτε για σταθερό πρόγραμμα');

-- ═══════ 7. Managers / assistant managers στη Ρεσεψιόν ═══════
select pg_temp.as_user('hr@x.gr');
update employees set store_role = 'manager' where code = 'M1';
select pg_temp.as_user('glyfada@x.gr');
select sched_set_pattern('M1', '2026-11-30', '{"1":[["09:00","13:00"]],"2":[["09:00","17:00"]]}', 'Τοποθέτηση στη Ρεσεψιόν');
select sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν') as w \gset
select pg_temp.eq(pg_temp.emp(:'w','M1')->>'store_role_label', 'Manager', 'ο manager εμφανίζεται στη Ρεσεψιόν με ένδειξη ρόλου');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-30','10:00')->>'count')::int || '|' || (pg_temp.emp(:'w','M1')->>'shown_only'), '1|true', 'απόφαση 21/11: ο manager φαίνεται στη Ρεσεψιόν αλλά ΔΕΝ μετρά στην κάλυψη (μόνο P2)');
select pg_temp.eq((pg_temp.emp(:'w','M1')->'days'->'2026-11-30'->>'minutes')::int, 240, 'το ωράριό του εμφανίζεται κανονικά');
select pg_temp.eq((pg_temp.slot(sched_week('Γλυφάδα', '2026-11-30', 'Επίβλεψη'),'2026-11-30','10:00')->>'count')::int, 1, 'μετρά στην κάλυψη του δικού του τμήματος');
select pg_temp.eq((select count(*) from jsonb_array_elements(sched_week('Γλυφάδα', '2026-11-30', null)->'employees') x where x->>'code' = 'M1'), 1::bigint, 'χωρίς διπλή εμφάνιση στο «Όλα τα τμήματα»');
select pg_temp.eq(pg_temp.emp(sched_week('Γλυφάδα', '2026-11-30', 'Επίβλεψη'),'M1') is not null, true, 'εμφανίζεται και στο δικό του τμήμα');
select (req_create('{"category":"leave","employee_code":"M1","entry_mode":"manager_record","leave_type":"annual","start_date":"2026-11-30","end_date":"2026-11-30","days_requested":"1","body":"Παρακαλώ να εγκρίνετε την άδεια."}'))->>'id' as ml \gset
select req_submit(:'ml', 1);
select sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν') as w \gset
select pg_temp.eq((pg_temp.emp(:'w','M1')->'days'->'2026-11-30'->'pending'->>'ref') is not null and (pg_temp.slot(:'w','2026-11-30','10:00')->>'count')::int = 1, true,
  'εκκρεμές αίτημα manager: φαίνεται στη Ρεσεψιόν');
select pg_temp.as_user('hr@x.gr');
select leave_set_base('M1', 22, '2024-01-01', 'Βάση');
select req_decide(:'ml', 'approve', '{"message":"Η άδεια εγκρίθηκε."}', (select version from hr_requests where id = :'ml'));
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((pg_temp.emp(sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν'),'M1')->'days'->'2026-11-30'->'leave'->>'type') || '|' || (select count(*) from jsonb_array_elements(sched_week('Γλυφάδα', '2026-11-30', 'Ρεσεψιόν')->'needs_cover') x where x->>'employee_code' = 'M1'), 'annual|0',
  'εγκεκριμένη άδεια manager: φαίνεται στη Ρεσεψιόν, χωρίς «χρειάζεται κάλυψη» εκεί');
select pg_temp.eq((select string_agg(employee_code || ':' || status || ':' || coalesce(store_role, '-'), ',') from leave_calendar('2026-11-30', '2026-11-30', 'Γλυφάδα', 'Ρεσεψιόν')), 'M1:approved:manager',
  'ημερολόγιο αδειών Ρεσεψιόν: και οι managers του καταστήματος');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from leave_calendar('2026-11-30', '2026-11-30', null, 'Ρεσεψιόν')), 0::bigint, 'όχι σε άλλο κατάστημα');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
