\set ON_ERROR_STOP 1
-- Έκδοση 3 · Πρόγραμμα προσωπικού: σταθερά, προσωρινά, μόνιμα και σπαστά ωράρια, κάλυψη ανά μισάωρο,
-- σωστή αντιμετώπιση αδειών/απουσιών/αποχωρήσεων, οριστικοποίηση με υποχρεωτική αιτιολογία και ιστορικό,
-- περιορισμός manager στο κατάστημά του, μόνιμη μεταφορά. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),
 ('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week,weekly_hours,hire_date) values
 ('S1','Άννα','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,40,'2025-01-01'),
 ('S2','Βασίλης','Βλάχος','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,40,'2025-01-01'),
 ('S3','Γωγώ','Γεωργίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',6,20,'2025-01-01'),
 ('K1','Δημήτρης','Δήμου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5,40,'2025-01-01');

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
create or replace function pg_temp.ver(p uuid) returns int language sql as $$ select version from hr_requests where id = p $$;

-- Ωράριο λειτουργίας τμήματος (ΓΔ: ρυθμίσεις προγράμματος)
select pg_temp.as_user('owner@x.gr');
insert into store_hours(store, specialty, weekday, opens, closes) select 'Γλυφάδα', 'Ρεσεψιόν', d, '06:30', '22:00' from generate_series(1, 7) d;
select pg_temp.eq((select count(*) from shift_templates where active), 4::bigint, 'έτοιμα ωράρια για γρήγορη επιλογή');
select pg_temp.expect_fail($$select sched_set_pattern('S1', '2026-11-02', '{"1":[["06:30","12:30"]]}', null)$$, 'η ΓΔ βλέπει, δεν διαχειρίζεται πρόγραμμα (αρχική ρύθμιση)');

-- ═══════ Σταθερό πρόγραμμα με ημερομηνία ισχύος (manager, χωρίς έγκριση) ═══════
select pg_temp.as_user('glyfada@x.gr');
select sched_set_pattern('S1', '2026-11-02', '{"1":[["06:30","12:30"]],"2":[["06:30","12:30"]],"3":[["06:30","12:30"]],"4":[["06:30","12:30"]],"5":[["06:30","12:30"]]}', null);
select sched_set_pattern('S2', '2026-11-02', '{"1":[["08:00","12:00"],["17:00","21:00"]],"2":[["08:00","12:00"],["17:00","21:00"]],"3":[["08:00","12:00"],["17:00","21:00"]],"4":[["08:00","12:00"],["17:00","21:00"]],"5":[["08:00","12:00"],["17:00","21:00"]]}', null);
select sched_set_pattern('S3', '2026-11-02', '{"6":[["13:00","15:00"]]}', null);
select pg_temp.expect_fail($$select sched_set_pattern('S1', '2026-11-02', '{"1":[["12:00","08:00"]]}', null)$$, 'λήξη πριν από την έναρξη');
select pg_temp.expect_fail($$select sched_set_pattern('K1', '2026-11-02', '{"1":[["08:00","16:00"]]}', null)$$, 'manager: όχι εργαζόμενος άλλου καταστήματος');
select pg_temp.eq(sched_minutes('[["08:00","12:00"],["17:00","21:00"]]'), 480, 'σπαστό 08:00–12:00 & 17:00–21:00 = 8 ώρες (χωρίς το ενδιάμεσο κενό)');

select sched_week('Γλυφάδα', '2026-11-16') as w \gset
select pg_temp.eq((pg_temp.emp(:'w','S2')->>'planned_hours')::numeric, 40.00, 'εβδομαδιαίες ώρες σπαστού ωραρίου');
select pg_temp.eq((pg_temp.emp(:'w','S1')->>'planned_hours')::numeric || '|' || (pg_temp.emp(:'w','S1')->>'deviation'), '30.00|-10.00', 'απόκλιση από τις συμβατικές ώρες');
select pg_temp.eq(jsonb_array_length(pg_temp.emp(:'w','S2')->'days'->'2026-11-16'->'segments'), 2, 'δύο μπάρες στο σπαστό ωράριο');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-16','06:30')->>'count')::int, 1, 'κάλυψη 06:30: 1 άτομο');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-16','08:00')->>'count')::int, 2, 'κάλυψη 08:00: 2 άτομα ταυτόχρονα');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-16','12:30')->>'uncovered')::boolean, true, 'κόκκινο: κανένας διαθέσιμος 12:30 μέσα στο ωράριο λειτουργίας');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-16','17:00')->>'count')::int, 1, 'κάλυψη 17:00: δεύτερο διάστημα του σπαστού');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-16','08:00')->>'staffing'), null, 'χωρίς απαιτήσεις κάλυψης: όχι χαρακτηρισμός υπο/υπερστελέχωσης');

-- ═══════ Προσωρινή αλλαγή & αυτόματη επιστροφή · μόνιμη αλλαγή με νέα ισχύ ═══════
select sched_set_temp('S1', array['2026-11-18']::date[], '[["14:00","20:00"]]', 'Κάλυψη απογευματινής');
select sched_week('Γλυφάδα', '2026-11-16') as w \gset
select pg_temp.eq(pg_temp.emp(:'w','S1')->'days'->'2026-11-18'->>'source', 'temporary', 'προσωρινή αλλαγή για συγκεκριμένη ημερομηνία');
select pg_temp.eq(pg_temp.emp(:'w','S1')->'days'->'2026-11-19'->>'source', 'pattern', 'αυτόματη επιστροφή στο σταθερό πρόγραμμα την επομένη');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-18','06:30')->>'uncovered')::boolean, true, 'η αλλαγή αφήνει ακάλυπτο το πρωί της Τετάρτης');
select sched_set_pattern('S1', '2026-11-23', '{"1":[["08:00","16:00"]],"2":[["08:00","16:00"]],"3":[["08:00","16:00"]],"4":[["08:00","16:00"]],"5":[["08:00","16:00"]]}', 'Νέο πρωινό ωράριο');
select pg_temp.eq(sched_day('S1', '2026-11-20')->'segments'->0->>0, '06:30', 'μόνιμη αλλαγή: πριν την ισχύ μένει το παλιό');
select pg_temp.eq(sched_day('S1', '2026-11-23')->'segments'->0->>0, '08:00', 'μόνιμη αλλαγή: από τη νέα ημερομηνία ισχύος');
select pg_temp.eq((select valid_to from schedule_patterns where employee_code = 'S1' and valid_from = '2026-11-02' and status = 'active'), '2026-11-22'::date, 'το προηγούμενο σταθερό πρόγραμμα κλείνει την προηγούμενη ημέρα');

-- ═══════ Επικαλυπτόμενες τοποθετήσεις ═══════
select sched_set_temp('S3', array['2026-11-22']::date[], '[["09:00","13:00"],["12:00","14:00"]]', 'Διπλή καταχώριση');
select sched_week('Γλυφάδα', '2026-11-16') as w \gset
select pg_temp.eq((pg_temp.emp(:'w','S3')->'days'->'2026-11-22'->>'overlap')::boolean, true, 'επισήμανση επικαλυπτόμενων τοποθετήσεων');
select pg_temp.eq((pg_temp.emp(:'w','S3')->'days'->'2026-11-22'->>'minutes')::int, 300, 'η επικάλυψη δεν μετριέται δύο φορές');

-- ═══════ Άδειες, εκκρεμή αιτήματα, αποχώρηση στην κάλυψη ═══════
select (req_create('{"category":"leave","employee_code":"S2","entry_mode":"manager_record","leave_type":"annual","start_date":"2026-11-19","end_date":"2026-11-19","days_requested":"1","body":"Παρακαλώ να εγκρίνετε μία ημέρα κανονικής άδειας."}'))->>'id' as lv \gset
select req_submit(:'lv', 1);
select (req_create('{"category":"leave","employee_code":"S1","entry_mode":"manager_record","leave_type":"annual","start_date":"2026-11-20","end_date":"2026-11-20","days_requested":"1","body":"Παρακαλώ να εγκρίνετε μία ημέρα κανονικής άδειας."}'))->>'id' as pend \gset
select req_submit(:'pend', 1);
select pg_temp.as_user('hr@x.gr');
select req_decide(:'lv', 'approve', '{"message":"Το αίτημα εγκρίθηκε όπως ζητήθηκε."}', pg_temp.ver(:'lv'));
select pg_temp.as_user('owner@x.gr');
select emp_set_dates('S3', '2025-01-01', '2026-11-20', 'Παραίτηση');
select pg_temp.as_user('glyfada@x.gr');
select sched_week('Γλυφάδα', '2026-11-16') as w \gset
select pg_temp.eq((pg_temp.slot(:'w','2026-11-19','08:00')->>'count')::int || '|' || (pg_temp.slot(:'w','2026-11-19','08:00')->'present' ? 'S2'), '1|false', 'σε άδεια δεν μετράει στην κάλυψη');
select pg_temp.eq((pg_temp.slot(:'w','2026-11-20','06:30')->>'count')::int, 1, 'εκκρεμές αίτημα: δεν αφαιρεί από την κάλυψη');
select pg_temp.eq(pg_temp.emp(:'w','S1')->'days'->'2026-11-20'->'pending'->>'ref' is not null, true, 'εκκρεμές αίτημα εμφανίζεται για προγραμματισμό');
select pg_temp.eq((pg_temp.emp(:'w','S2')->>'planned_hours')::numeric || '|' || (pg_temp.emp(:'w','S2')->>'leave_hours')::numeric || '|' || (pg_temp.emp(:'w','S2')->>'has_leave'),
  '32.00|8.00|true', 'ώρες εργασίας χωριστά από ώρες άδειας (η απόκλιση εβδομάδας άδειας δεν είναι υποχρέωση αναπλήρωσης)');
select pg_temp.eq((select count(*) from jsonb_array_elements(:'w'::jsonb->'needs_cover') x where x->>'employee_code' = 'S2' and x->>'day' = '2026-11-19'), 1::bigint, 'ανάγκη αντικατάστασης για βάρδια σε άδεια');
select pg_temp.eq((select x->>'why' from jsonb_array_elements(:'w'::jsonb->'needs_cover') x where x->>'employee_code' = 'S3' and x->>'day' = '2026-11-21'), 'αποχώρηση', 'βάρδια μετά την αποχώρηση: χρειάζεται κάλυψη (χωρίς διαγραφή ιστορικού)');
select pg_temp.eq((pg_temp.emp(:'w','S3')->'days'->'2026-11-21'->>'counts')::boolean, false, 'μετά την αποχώρηση δεν μετρά στη στελέχωση');
select pg_temp.eq((select count(*) from schedule_patterns where employee_code = 'S3'), 1::bigint, 'το πρόγραμμα του αποχωρήσαντος δεν διαγράφεται');

-- ═══════ Απαιτήσεις κάλυψης (μελλοντική δομή): μόνο τότε υπο/υπερστελέχωση ═══════
select pg_temp.as_user('owner@x.gr');
insert into staffing_requirements(store, specialty, weekday, slot_start, required, valid_from) values ('Γλυφάδα', 'Ρεσεψιόν', 1, '08:00', 3, '2026-01-01');
select pg_temp.as_user('glyfada@x.gr');
select sched_week('Γλυφάδα', '2026-11-16', 'Ρεσεψιόν') as w \gset
select pg_temp.eq(pg_temp.slot(:'w','2026-11-16','08:00')->>'staffing', 'under', 'με ορισμένη απαίτηση: υποστελέχωση');
select pg_temp.eq(pg_temp.slot(:'w','2026-11-16','09:00')->>'staffing', null, 'όπου δεν ορίζεται απαίτηση: κανένας χαρακτηρισμός');

-- ═══════ Οριστικοποίηση & υποχρεωτική αιτιολογία & ιστορικό ═══════
select sched_finalize('Γλυφάδα', '2026-11-16');
select pg_temp.expect_fail($$select sched_set_temp('S1', array['2026-11-17']::date[], '[["10:00","16:00"]]', null)$$, 'αλλαγή σε οριστικοποιημένο πρόγραμμα χωρίς αιτιολογία');
select pg_temp.expect_fail($$select sched_set_pattern('S2', '2026-11-18', '{"1":[["08:00","16:00"]]}', '')$$, 'μόνιμη αλλαγή που αγγίζει οριστικοποιημένη εβδομάδα χωρίς αιτιολογία');
select sched_set_temp('S1', array['2026-11-17']::date[], '[["10:00","16:00"]]', 'Ιατρικό ραντεβού το πρωί');
select pg_temp.eq((select after_finalize||'|'||change_type||'|'||reason||'|'||(prev_value->'2026-11-17'->0->>0)||'→'||(new_value->'segments'->0->>0) from schedule_changes where employee_code = 'S1' order by id desc limit 1),
  'true|temporary|Ιατρικό ραντεβού το πρωί|06:30→10:00', 'ιστορικό: χρήστης, χρόνος, προηγούμενη & νέα τιμή, είδος αλλαγής, αιτιολογία');
select pg_temp.eq((select actor from schedule_changes where employee_code = 'S1' order by id desc limit 1), 'glyfada@x.gr', 'καταγράφεται ο χρήστης');
select pg_temp.expect_fail($$update schedule_changes set reason = 'x'$$, 'το ιστορικό δεν αλλάζει');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) > 0 from sched_history('Γλυφάδα')), true, 'η ΓΔ βλέπει το πλήρες ιστορικό');
select pg_temp.eq((sched_week('Γλυφάδα', '2026-11-16')->'finalized'->>'by'), 'glyfada@x.gr', 'η ΓΔ βλέπει το τρέχον (οριστικοποιημένο) πρόγραμμα');
select pg_temp.eq((select count(*) from notifications), 0::bigint, 'καμία αυτόματη ειδοποίηση ΓΔ για αλλαγές προγράμματος');

-- ═══════ Πρόσβαση ═══════
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail($$select sched_week('Γλυφάδα', '2026-11-16')$$, 'manager άλλου καταστήματος δεν βλέπει το πρόγραμμα');
select pg_temp.expect_fail($$select sched_set_temp('S1', array['2026-11-24']::date[], '[]', 'x')$$, 'manager άλλου καταστήματος δεν αλλάζει το πρόγραμμα');
select pg_temp.eq((select count(*) from schedule_patterns), 0::bigint, 'manager άλλου καταστήματος: κανένα στοιχείο προγράμματος');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((sched_week('Γλυφάδα', '2026-11-16')->>'can_manage')::boolean, false, 'HR: προβολή χωρίς διαχείριση');
select pg_temp.expect_fail($$select sched_finalize('Γλυφάδα', '2026-11-23')$$, 'HR δεν οριστικοποιεί');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq(jsonb_array_length(sched_week('Γλυφάδα', '2026-11-16')->'employees') > 0, true, 'εκπαιδευτής: προβολή σε όλα τα καταστήματα');
select pg_temp.expect_fail($$select sched_set_temp('S1', array['2026-11-24']::date[], '[]', 'x')$$, 'εκπαιδευτής: η προβολή δεν δίνει επεξεργασία προγράμματος');
select pg_temp.as_user('acc@x.gr');
select pg_temp.expect_fail($$select sched_week('Γλυφάδα', '2026-11-16')$$, 'λογιστήριο: χωρίς πρόσβαση στο πρόγραμμα (αρχική ρύθμιση)');

-- ═══════ Μόνιμη μεταφορά καταστήματος (ίδιος κωδικός, πλήρες ιστορικό) ═══════
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail(format($$select emp_transfer('S1', 'Κηφισιά', %L, 'x')$$, athens_today() + 5), 'μεταφορά με μελλοντική ισχύ');
select emp_transfer('S1', 'Κηφισιά', athens_today(), 'Μόνιμη μετακίνηση');
reset role;
select pg_temp.eq((select store from employees where code = 'S1'), 'Κηφισιά', 'ίδιος κωδικός, νέο κατάστημα');
select pg_temp.eq((select store from hr_requests where id = :'pend'), 'Γλυφάδα', 'οι παλιές εγγραφές κρατούν το κατάστημα στο οποίο αφορούσαν');
select pg_temp.eq((select count(*) from schedule_patterns where employee_code = 'S1' and status = 'active' and store = 'Γλυφάδα' and (valid_to is null or valid_to >= athens_today())), 0::bigint,
  'το πρόγραμμα του παλιού καταστήματος λήγει από την ισχύ της μεταφοράς');
select pg_temp.eq((select count(*) from employee_assignments where employee_code = 'S1'), 2::bigint, 'ιστορικό θέσης');
select pg_temp.eq((select kind from employee_lifecycle where employee_code = 'S1' order by id desc limit 1), 'transfer', 'καταγραφή μεταφοράς');
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
