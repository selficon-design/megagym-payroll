\set ON_ERROR_STOP 1
-- Έκδοση 3.1 · Σύνδεσμος στατιστικών Ρεσεψιόν ανά κατάστημα, «Παλιά μέλη», report νέων εγγραφών/ανανεώσεων.
-- ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('R1','Άννα','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2025-01-01'),
 ('R2','Βασίλης','Βλάχος','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2025-01-01'),
 ('S1','Γωγώ','Γεωργίου','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη',5,'2025-01-01'),
 ('K1','Δημήτρης','Δήμου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2025-01-01');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.as_anon() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', '{}', false); execute 'set role anon'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;

-- ═══════ 17. Παλιά μέλη: πεδία, κανόνες, παλιές εγγραφές χωρίς διάκριση ═══════
-- παλιά εγγραφή (πριν από την 3.1) χωρίς διάκριση νέων/παλιών
reset role;
insert into daily_stats(employee_code, stat_date, store, specialty, kind, dr, lost, cb, trials_sent, enr_fitness, enr_body, enr_muscle, enr_from_trials, created_by)
values ('R1', '2026-10-01', 'Γλυφάδα', 'Ρεσεψιόν', 'reception', 5, 5, 1, 0, 2, 1, 0, 0, 'legacy@x.gr');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((stats_save('2026-11-02', '[{"employee_code":"R2","dr":3,"lost":5,"cb":1,"trials_sent":2,"enr_fitness":2,"enr_body":1,"enr_muscle":1,"enr_from_trials":0}]')->'rows'->0->>'error'),
  'Λείπει το πεδίο old_dr.', 'νέα καταχώριση Ρεσεψιόν: συμπληρώνονται και τα «Παλιά μέλη»');
select stats_save('2026-11-02', '[{"employee_code":"R2","dr":3,"lost":5,"cb":1,"trials_sent":2,"enr_fitness":2,"enr_body":1,"enr_muscle":1,"enr_from_trials":0,
  "old_dr":2,"old_lost":2,"old_cb":2,"old_trials_sent":0,"old_enr_fitness":3,"old_enr_body":1,"old_enr_muscle":0,"old_enr_from_trials":0,"old_direct":1}]');
select stats_save('2026-11-03', '[{"employee_code":"R1","dr":1,"lost":1,"cb":0,"trials_sent":0,"enr_fitness":1,"enr_body":0,"enr_muscle":0,"enr_from_trials":0,
  "old_dr":4,"old_lost":0,"old_cb":1,"old_trials_sent":0,"old_enr_fitness":4,"old_enr_body":1,"old_enr_muscle":0,"old_enr_from_trials":0,"old_direct":3}]');
select pg_temp.eq((select old_dr || '|' || old_direct from daily_stats where employee_code = 'R2'), '2|1', 'αποθήκευση πεδίων παλιών μελών');
select pg_temp.eq((select count(*) from daily_stats where old_dr is null), 1::bigint, 'η παλιά εγγραφή μένει χωρίς διάκριση (όχι μηδενικά)');
-- διόρθωση παλιάς εγγραφής χωρίς πεδία παλιών μελών: μένουν κενά
select id as l1, version as lv from daily_stats where employee_code = 'R1' and stat_date = '2026-10-01' \gset
select stats_save('2026-10-01', format('[{"id":%s,"version":%s,"employee_code":"R1","dr":6,"lost":5,"cb":1,"trials_sent":0,"enr_fitness":2,"enr_body":1,"enr_muscle":0,"enr_from_trials":0}]', :l1, :lv)::jsonb);
select pg_temp.eq((select dr || '|' || coalesce(old_dr::text, 'κενό') from daily_stats where id = :l1), '6|κενό', 'διόρθωση παλιάς εγγραφής χωρίς επινοημένα μηδενικά');
reset role;
select pg_temp.expect_fail($$insert into daily_stats(employee_code, stat_date, store, specialty, kind, trials_done, enr_from_trials, old_dr, created_by) values ('S1','2026-11-01','Γλυφάδα','Επίβλεψη','exclusive',1,1,1,'x')$$,
  'πεδία παλιών μελών μόνο στη Ρεσεψιόν');

select pg_temp.as_user('owner@x.gr');
select * from stats_members_report('2026-10-01', '2026-11-30', 'Γλυφάδα') \gset m_
select pg_temp.eq(:m_new_enrolled || '|' || :m_renewals || '|' || :m_grand_total, '5|9|14', 'νέες εγγραφές (DR+CB) 4+1 · ανανεώσεις (DR+CB παλιών) 4+5 · σύνολο 14');
select pg_temp.eq(:m_new_informed || '|' || :m_old_informed, '10|8', 'ενημερώσεις (DR+LOST) χωριστά — δεν είναι εγγραφές');
select pg_temp.eq(:m_old_direct, 4, '«Παλιά μέλη — Άμεσο» χωριστά, ΔΕΝ προστίθεται στο σύνολο');
select pg_temp.eq(:m_rows_unsplit || '|' || :m_unsplit_enrolled, '1|7', 'παλιές εγγραφές χωρίς διάκριση: μετρώνται χωριστά, όχι ως νέα ή παλιά');

-- ═══════ 16. Σύνδεσμος στατιστικών Ρεσεψιόν ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select statlink_create('Γλυφάδα')$$, 'ο manager δεν δημιουργεί σύνδεσμο (ειδικό δικαίωμα)');
select pg_temp.as_user('owner@x.gr');
select statlink_create('Γλυφάδα')->>'token' as tok \gset
select pg_temp.eq(length(:'tok') >= 64, true, 'μη προβλέψιμο κλειδί');
reset role;
select pg_temp.eq((select count(*) from stats_links where token_hash = :'tok'), 0::bigint, 'αποθηκεύεται μόνο το hash του κλειδιού');
select pg_temp.as_anon();
select statlink_info(:'tok') as info \gset
select pg_temp.eq((:'info'::jsonb->>'store') || '|' || (select string_agg(x->>'code', ',') from jsonb_array_elements(:'info'::jsonb->'employees') x), 'Γλυφάδα|R1,R2',
  'μόνο εργαζόμενοι Ρεσεψιόν του καταστήματος του συνδέσμου');
select pg_temp.eq(:'info'::jsonb ? 'rows' or :'info'::jsonb ? 'stats', false, 'καμία προηγούμενη εγγραφή ή αποτέλεσμα');
select pg_temp.eq((statlink_submit(:'tok', '{"employee_code":"R1","date":"2026-11-10","values":{"dr":2,"lost":3,"cb":1,"trials_sent":1,"enr_fitness":1,"enr_body":1,"enr_muscle":0,"enr_from_trials":0,"old_dr":1,"old_lost":1,"old_cb":0,"old_trials_sent":0,"old_enr_fitness":1,"old_enr_body":0,"old_enr_muscle":0,"old_enr_from_trials":0,"old_direct":0}}')->>'ok')::boolean,
  true, 'υποβολή από τον σύνδεσμο');
select pg_temp.expect_fail(format($$select statlink_submit(%L, '{"employee_code":"R1","date":"2026-11-10","values":{"dr":9,"lost":9,"cb":9,"trials_sent":9,"enr_fitness":9,"enr_body":9,"enr_muscle":9,"enr_from_trials":9,"old_dr":9,"old_lost":9,"old_cb":9,"old_trials_sent":9,"old_enr_fitness":9,"old_enr_body":9,"old_enr_muscle":9,"old_enr_from_trials":9,"old_direct":9}}')$$, :'tok'),
  'διπλή ημερήσια εγγραφή: μήνυμα επικοινωνίας με manager, χωρίς δεδομένα');
select pg_temp.expect_fail(format($$select statlink_submit(%L, '{"employee_code":"K1","date":"2026-11-10","values":{}}')$$, :'tok'), 'εργαζόμενος άλλου καταστήματος');
select pg_temp.expect_fail(format($$select statlink_submit(%L, '{"employee_code":"S1","date":"2026-11-10","values":{}}')$$, :'tok'), 'εργαζόμενος άλλης ειδικότητας');
select pg_temp.expect_fail(format($$select statlink_submit(%L, '{"employee_code":"R2","date":"2099-01-01","values":{}}')$$, :'tok'), 'μελλοντική ημερομηνία');
select pg_temp.expect_fail($$select * from daily_stats$$, 'ο σύνδεσμος δεν διαβάζει στατιστικά (μόνο υποβολή)');
select pg_temp.expect_fail($$select stats_save('2026-11-10', '[]')$$, 'ούτε καλεί τις λειτουργίες της εφαρμογής');
select pg_temp.expect_fail($$select statlink_info('abcdefabcdefabcdefabcdefabcdefabcdef')$$, 'λάθος κλειδί');
reset role;
select pg_temp.eq((select created_by || '|' || store || '|' || kind from daily_stats where employee_code = 'R1' and stat_date = '2026-11-10'), 'σύνδεσμος:Γλυφάδα|Γλυφάδα|reception', 'αποθηκεύεται στην ίδια ενότητα στατιστικών');
-- αντικατάσταση: το παλιό κλειδί παύει να λειτουργεί
select pg_temp.as_user('owner@x.gr');
select statlink_create('Γλυφάδα')->>'token' as tok2 \gset
select pg_temp.as_anon();
select pg_temp.expect_fail(format($$select statlink_info(%L)$$, :'tok'), 'το αντικατεστημένο κλειδί δεν λειτουργεί');
select pg_temp.eq(statlink_info(:'tok2')->>'store', 'Γλυφάδα', 'το νέο κλειδί λειτουργεί');
select pg_temp.as_user('owner@x.gr');
select statlink_revoke('Γλυφάδα', 'Τέλος δοκιμής');
select pg_temp.as_anon();
select pg_temp.expect_fail(format($$select statlink_info(%L)$$, :'tok2'), 'ανάκληση');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from statlink_list() where status = 'revoked'), 2::bigint, 'ιστορικό συνδέσμων');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
