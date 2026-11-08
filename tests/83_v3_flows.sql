\set ON_ERROR_STOP 1
-- Έκδοση 3 · Υλοποίηση από manager, αδιάβαστες ειδοποιήσεις ανά χρήστη, reports manager, Exit Interview με
-- περιορισμένη πρόσβαση, αποτελέσματα αξιολογήσεων για manager/εκπαιδευτή, διατήρηση προσωπικών συνδέσμων.
-- ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('glyfada2@x.gr','Β΄ Manager Γλυφάδας','manager','Γλυφάδα'),
 ('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('F1','Ελένη','Πέτρου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-01-01'),
 ('F2','Κατερίνα','Σταύρου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-01-01'),
 ('F3','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-01-01');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.as_anon() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', '{}', false); execute 'set role anon'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.ver(p uuid) returns int language sql as $$ select version from hr_requests where id = p $$;
create or replace function pg_temp.ath(i interval) returns text language sql as $$ select to_char((now() + i) at time zone 'Europe/Athens', 'YYYY-MM-DD HH24:MI') $$;
create or replace function pg_temp.tok(r jsonb, code text) returns text language sql as $$
  select x->>'token' from jsonb_array_elements(r->'rows') x where x->>'employee_code' = code $$;

-- ═══════ 1. Υλοποίηση: Εγκρίθηκε → Ενημερώθηκε → Ανάληψη (manager) → Ολοκληρώθηκε ═══════
select pg_temp.as_user('glyfada@x.gr');
select (req_create('{"category":"documents","employee_code":"F1","entry_mode":"manager_record","body":"Ο εργαζόμενος ζητά βεβαίωση προϋπηρεσίας για την τράπεζα."}'))->>'id' as rq \gset
select req_submit(:'rq', 1);
select pg_temp.as_user('hr@x.gr');
select req_decide(:'rq', 'approve', '{"message":"Το αίτημά σας εγκρίθηκε. Η βεβαίωση θα εκδοθεί."}', pg_temp.ver(:'rq'));
select req_task_add(:'rq', 'accounting', 'Έκδοση βεβαίωσης αποδοχών');
select pg_temp.expect_fail(format($$select req_impl_claim(%L, %s)$$, :'rq', pg_temp.ver(:'rq')), 'HR δεν αναλαμβάνει υλοποίηση αντί του manager');
select pg_temp.expect_fail(format($$select req_complete(%L, 'έγινε', %s)$$, :'rq', pg_temp.ver(:'rq')), 'HR δεν ολοκληρώνει υλοποίηση');
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail(format($$select req_impl_claim(%L, %s)$$, :'rq', pg_temp.ver(:'rq')), 'ΓΔ δεν αναλαμβάνει υλοποίηση αντί του manager');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select req_impl_claim(%L, null)$$, :'rq'), 'manager άλλου καταστήματος');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select req_impl_claim(%L, %s)$$, :'rq', pg_temp.ver(:'rq')), 'πρώτα καταγράφεται η ενημέρωση του εργαζομένου');
select req_mark_notified(:'rq', null, 'Ενημερώθηκε στο κατάστημα', pg_temp.ver(:'rq'));
select pg_temp.expect_fail(format($$select req_impl_complete(%L, 'Παραδόθηκε', null, %s)$$, :'rq', pg_temp.ver(:'rq')), 'ολοκλήρωση χωρίς ανάληψη');
select req_impl_claim(:'rq', pg_temp.ver(:'rq'));
select pg_temp.as_user('glyfada2@x.gr');
select pg_temp.expect_fail(format($$select req_impl_claim(%L, %s)$$, :'rq', pg_temp.ver(:'rq')), 'διπλή ανάληψη');
select pg_temp.as_user('glyfada@x.gr');
select req_impl_complete(:'rq', 'Παραδόθηκε η βεβαίωση στον εργαζόμενο', '{"name":"παραλαβή.pdf","mime":"application/pdf","data":"JVBERi0xLjQ="}', pg_temp.ver(:'rq'));
select pg_temp.eq((select status||'|'||completed_by||'|'||impl_claimed_by from hr_requests where id = :'rq'), 'completed|glyfada@x.gr|glyfada@x.gr', 'ο manager ανέλαβε και ολοκλήρωσε');
select pg_temp.eq((select string_agg(action, ',' order by id) from hr_request_events where request_id = :'rq' and action in ('decide','notified','impl_claimed','implemented')),
  'decide,notified,impl_claimed,implemented', 'σειρά: Εγκρίθηκε → Ενημερώθηκε → Ανάληψη → Ολοκληρώθηκε');
select pg_temp.eq((select count(*) from hr_attachments where request_id = :'rq'), 1::bigint, 'δικαιολογητικό υλοποίησης');
select pg_temp.eq((select outcome from hr_decisions where request_id = :'rq' and superseded_at is null), 'approve', 'η ανάληψη δεν αλλάζει την απόφαση');
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select count(*) from my_tasks() where status = 'open'), 1::bigint, 'εξειδικευμένη ενέργεια λογιστηρίου παρακολουθείται χωριστά');
select req_task_done((select id from my_tasks() limit 1), 'Εκδόθηκε');
select pg_temp.eq((select status from my_tasks() limit 1), 'done', 'ολοκλήρωση ενέργειας λογιστηρίου');

-- ═══════ 2. Αδιάβαστες ειδοποιήσεις απαντήσεων ανά χρήστη ═══════
select pg_temp.as_user('glyfada@x.gr');
select (req_create('{"category":"advance","employee_code":"F3","entry_mode":"manager_record","body":"Ο εργαζόμενος ζητά προκαταβολή 200 ευρώ."}'))->>'id' as adv \gset
select req_submit(:'adv', 1);
select notif_read_request(:'rq');
select pg_temp.as_user('glyfada2@x.gr');
select notif_read_request(:'rq');
select pg_temp.as_user('kifisia@x.gr');
select (req_create('{"category":"advance","employee_code":"F2","entry_mode":"manager_record","body":"Ο εργαζόμενος ζητά προκαταβολή 100 ευρώ."}'))->>'id' as advk \gset
select req_submit(:'advk', 1);
select pg_temp.as_user('hr@x.gr');
select req_decide(:'adv', 'needs_info', '{"message":"Απαιτούνται τα παρακάτω στοιχεία: ποσό και αιτιολογία.","info":"ποσό και αιτιολογία"}', pg_temp.ver(:'adv'));
select req_decide(:'advk', 'approve', '{"message":"Το αίτημα προκαταβολής εγκρίθηκε."}', pg_temp.ver(:'advk'));
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq(notif_count(), 1, '«Απαντήσεις 1» για τον αρμόδιο manager');
select pg_temp.eq((select count(*) from notif_list() where store <> 'Γλυφάδα'), 0::bigint, 'δεν εμφανίζονται ενημερώσεις άλλου καταστήματος');
select pg_temp.eq((select request_id::text from notif_list() limit 1), :'adv', 'η ενημέρωση οδηγεί στο αντίστοιχο αίτημα');
select (req_create('{"category":"other_hr","employee_code":"F1","entry_mode":"manager_record","body":"Ο εργαζόμενος ζητά συνάντηση με το HR."}'))->>'id' as oth \gset
select req_submit(:'oth', 1);
select pg_temp.eq((select count(*) from hr_requests where status in ('submitted','under_review','needs_info','approved'))::int || '|' || notif_count(), '2|1', 'ο αριθμός είναι χωριστός από τις συνολικές εκκρεμότητες');
select notif_read_request(:'adv');
select pg_temp.eq(notif_count(), 0, 'διαβάστηκε όταν άνοιξε το αίτημα');
select pg_temp.as_user('glyfada2@x.gr');
select pg_temp.eq(notif_count(), 1, 'η κατάσταση ανάγνωσης αποθηκεύεται ανά χρήστη');
select pg_temp.as_user('glyfada@x.gr');
select req_provide_info(:'adv', 'Ποσό 200€ για έξοδα ιατρού', pg_temp.ver(:'adv'));
select pg_temp.as_user('hr@x.gr');
select req_decide(:'adv', 'approve', '{"message":"Η προκαταβολή εγκρίθηκε όπως ζητήθηκε."}', pg_temp.ver(:'adv'));
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq(notif_count(), 1, 'νέα απάντηση στο ίδιο αίτημα = νέα αδιάβαστη ενημέρωση');
select pg_temp.expect_fail($$update notifications set read_at = now()$$, 'καμία απευθείας αλλαγή ειδοποιήσεων');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq(notif_count(), 1, 'manager Κηφισιάς: μόνο η δική του ενημέρωση');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq(notif_count(), 0, 'όποιος αποφασίζει δεν ειδοποιεί τον εαυτό του');

-- ═══════ 3. Reports στατιστικών manager: ελεύθερο διάστημα, μόνο το κατάστημά του, χωρίς λήψη ═══════
reset role;
insert into daily_stats(employee_code, stat_date, store, specialty, kind, dr, lost, cb, trials_sent, enr_fitness, enr_body, enr_muscle, enr_from_trials, created_by) values
 ('F1','2026-01-05','Γλυφάδα','Ρεσεψιόν','reception',2,1,0,1,1,0,0,0,'x'),('F2','2026-01-05','Κηφισιά','Ρεσεψιόν','reception',3,0,0,0,0,0,0,0,'x');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from daily_stats where stat_date between '2025-12-01' and '2026-02-01'), 1::bigint, 'manager: report οποιουδήποτε διαστήματος, μόνο του καταστήματός του');
select pg_temp.eq((whoami()->'perms') ? 'stats.reports' and not ((whoami()->'perms') ? 'stats.export') and not ((whoami()->'perms') ? 'payroll.pdf'), true, 'manager: προβολή reports χωρίς λήψη');

-- ═══════ 4. Κανονική αξιολόγηση: απαντήσεις & βαθμός για manager (κατάστημα) και εκπαιδευτή (όλα) ═══════
select pg_temp.as_user('owner@x.gr');
select (q_create('Γνώσεις ρεσεψιόν', 'Τεστ'))->>'id' as q \gset
select q_save_questions(:'q', '[{"row":2,"specialty":"","section":"Γενικά","text":"Τι σημαίνει DR;","type":"Μία επιλογή","options":["Άμεση εγγραφή","Δοκιμαστικό"],"correct":"Α","points":"2","required":"Ναι","order":"1"}]', 'τ.xlsx');
select q_update_meta(:'q', 'Γνώσεις ρεσεψιόν', 'Τεστ', '{Ρεσεψιόν}', null);
select q_set_window(:'q', pg_temp.ath('-1 day'), pg_temp.ath('10 days'), 'διάστημα');
select q_publish(:'q');
select link_create(:'q', '{F1,F2}', pg_temp.ath('-1 hour'), pg_temp.ath('5 hours')) as c \gset
select pg_temp.tok(:'c','F1') as t1, pg_temp.tok(:'c','F2') as t2 \gset
select (select id from assessment_questions where version_id = (select current_version_id from questionnaires where id = :'q')) as qid \gset
select pg_temp.as_anon();
select link_get(:'t1');
select link_submit(:'t1', jsonb_build_object(:'qid', 'Α'));
select link_get(:'t2');
select link_submit(:'t2', jsonb_build_object(:'qid', 'Β'));
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select string_agg(employee_code||':'||score, ',') from assess_results(:'q')), 'F1:2.00', 'manager: απαντήσεις & βαθμός κανονικών αξιολογήσεων, μόνο του καταστήματός του');
select (select attempt_id from assess_results(:'q')) as att1 \gset
select pg_temp.eq((attempt_view(:'att1')->'questions'->0->>'answer'), 'Α', 'manager: βλέπει την απάντηση');
select pg_temp.eq((attempt_view(:'att1')->'questions'->0->'correct'), 'null'::jsonb, 'manager: δεν λαμβάνει το κλειδί σωστών απαντήσεων');
select pg_temp.eq((select count(*) from assessment_questions), 0::bigint, 'manager: καμία απευθείας πρόσβαση σε ερωτήσεις/σωστές απαντήσεις');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select attempt_view(%L)$$, :'att1'), 'manager άλλου καταστήματος δεν βλέπει την αξιολόγηση');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq((select count(*) from assess_results(:'q')), 2::bigint, 'εκπαιδευτής: αποτελέσματα σε όλα τα καταστήματα');
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select count(*) from assess_results(:'q')), 0::bigint, 'λογιστήριο: χωρίς αποτελέσματα αξιολογήσεων');

-- ═══════ 5. Exit Interview ═══════
select pg_temp.as_user('owner@x.gr');
select (q_create('Exit Interview 2026', 'Συνέντευξη αποχώρησης', 'exit_interview'))->>'id' as ex \gset
select pg_temp.eq(((q_save_questions(:'ex', '[{"row":2,"specialty":"","section":"Λόγοι","text":"Κύριος λόγος αποχώρησης","type":"Μία επιλογή","options":["Αποδοχές","Ωράριο","Μετακόμιση"],"correct":"Α","points":"1","required":"Ναι","order":"1"}]', 'exit.xlsx'))->>'ok'), 'false',
  'Exit Interview: χωρίς βαθμό επιτυχίας/αποτυχίας (σωστή απάντηση/βαθμοί απορρίπτονται)');
select q_save_questions(:'ex', '[
  {"row":2,"specialty":"","section":"Λόγοι","text":"Κύριος λόγος αποχώρησης","type":"Μία επιλογή","options":["Αποδοχές","Ωράριο","Μετακόμιση"],"correct":"","points":"","required":"Ναι","order":"1"},
  {"row":3,"specialty":"","section":"Σχόλια","text":"Τι θα αλλάζατε;","type":"Ελεύθερο κείμενο","options":[],"correct":"","points":"","required":"Όχι","order":"2"}]', 'exit.xlsx');
select q_set_window(:'ex', pg_temp.ath('-1 day'), pg_temp.ath('30 days'), 'διάστημα');
select pg_temp.eq((q_publish(:'ex'))->>'ok', 'true', 'Exit Interview ενεργό (από Excel, για όλες τις ειδικότητες)');
reset role; update employees set status = 'Ανενεργός', leave_date = current_date - 1 where code = 'F3';
select pg_temp.as_user('owner@x.gr');
select link_create(:'ex', '{F3}', pg_temp.ath('-1 hour'), pg_temp.ath('48 hours')) as ce \gset
select pg_temp.tok(:'ce','F3') as te \gset
select pg_temp.eq(:'te' is not null, true, 'προσωπικός σύνδεσμος και για εργαζόμενο που αποχώρησε');
select (select id from assessment_questions where version_id = (select current_version_id from questionnaires where id = :'ex') and qtype = 'single') as exq1,
       (select id from assessment_questions where version_id = (select current_version_id from questionnaires where id = :'ex') and qtype = 'text') as exq2 \gset
select pg_temp.as_anon();
select pg_temp.eq(link_get(:'te')->>'state', 'open', 'η αποχώρηση δεν ακυρώνει την ενεργή ανάθεση μέσα στην προθεσμία');
select link_submit(:'te', jsonb_build_object(:'exq1', 'Β', :'exq2', 'Καλύτερο πρόγραμμα βαρδιών'));
select pg_temp.eq(link_get(:'te')->>'state', 'submitted', 'μετά την υποβολή ο σύνδεσμος δεν δείχνει τις απαντήσεις');
select pg_temp.eq(link_get(:'te')::text like '%βαρδιών%', false, 'το άνοιγμα του συνδέσμου δεν δίνει πρόσβαση στις απαντήσεις');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from assess_results() where kind = 'exit_interview'), 0::bigint, 'manager: όχι Exit Interview στα αποτελέσματα');
select pg_temp.eq((select count(*) from employee_assessments('F3')), 0::bigint, 'manager: ούτε στην καρτέλα εργαζομένου');
select pg_temp.expect_fail($$select exit_report()$$, 'manager: όχι αναφορές Exit Interview');
select pg_temp.expect_fail(format($$select attempt_view((select id from assessment_attempts where questionnaire_id = %L limit 1))$$, :'ex'), 'manager: όχι περιεχόμενο Exit Interview');
reset role; select id as exatt from assessment_attempts where questionnaire_id = :'ex' \gset
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select attempt_view(%L)$$, :'exatt'), 'manager: όχι περιεχόμενο Exit Interview ακόμη κι αν βλέπει την καρτέλα');
select pg_temp.as_user('acc@x.gr');
select pg_temp.expect_fail(format($$select attempt_view(%L)$$, :'exatt'), 'λογιστήριο: όχι περιεχόμενο Exit Interview');
select pg_temp.expect_fail($$select exit_report()$$, 'λογιστήριο: όχι αναφορές Exit Interview');
reset role; update role_permissions set allowed = true where role = 'manager' and perm in ('assess.grade','assess.manage');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from assessment_attempts where questionnaire_id = :'ex'), 0::bigint, 'ακόμη και με δικαιώματα διαχείρισης, ο manager δεν διαβάζει Exit Interview');
reset role; update role_permissions set allowed = false where role = 'manager' and perm in ('assess.grade','assess.manage');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq(jsonb_array_length(exit_report()->'submissions'), 1, 'HR: αναφορές Exit Interview');
select pg_temp.eq((attempt_view(:'exatt')->'attempt'->>'score'), null, 'Exit Interview: χωρίς βαθμό');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq((select (q->'counts'->>'Β')::int from jsonb_array_elements(exit_report()->'questions') q where q->>'qtype' = 'single'), 1, 'εκπαιδευτής: συγκεντρωτικοί λόγοι αποχώρησης');
select pg_temp.eq((select q->'texts'->0->>'text' from jsonb_array_elements(exit_report()->'questions') q where q->>'qtype' = 'text'), 'Καλύτερο πρόγραμμα βαρδιών', 'ευρήματα (ελεύθερο κείμενο)');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from assess_results(null, 'F3') where kind = 'exit_interview' and submitted_at is not null), 1::bigint, 'αποτέλεσμα & ημερομηνία υποβολής στην καρτέλα (και μετά την αποχώρηση)');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
