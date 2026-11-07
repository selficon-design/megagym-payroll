\set ON_ERROR_STOP 1
-- Προσωπικοί σύνδεσμοι αξιολόγησης: αντιστοίχιση εργαζομένου/ερωτηματολογίου, πρόσβαση χωρίς λογαριασμό,
-- χρονικά όρια (ώρα server), προσωρινή αποθήκευση, μία υποβολή, ακύρωση/επανέκδοση, απομόνωση, καρτέλα εργαζομένου.
-- Μόνο εικονικά στοιχεία.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά');
insert into employees(code,first,last,store,company,specialty) values
 ('R1','Ελένη','Πέτρου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('R2','Κατερίνα','Σταύρου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('R3','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('S1','Σάκης','Ιωάννου','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη'),
 ('X1','Άννα','Μάρκου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν');
update employees set status = 'Ανενεργός' where code = 'X1';
insert into declarations(employee_code, employee_name, store, company, month, end_date, period, amount, status, prepared_by)
values ('R1','Ελένη Πέτρου','Γλυφάδα','BEST GREEK GYMS IKE','2026-10','2026-10-31','Οκτώβριος 2026', 900, 'pending', 'owner@x.gr');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.as_anon() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', '{}', false); execute 'set role anon'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.ath(i interval) returns text language sql as $$ select to_char((now() + i) at time zone 'Europe/Athens', 'YYYY-MM-DD HH24:MI') $$;
create or replace function pg_temp.tok(r jsonb, code text) returns text language sql as $$
  select x->>'token' from jsonb_array_elements(r->'rows') x where x->>'employee_code' = code $$;

-- ── Ερωτηματολόγιο από Excel (υπάρχουσα ροή, αμετάβλητη) ──
select pg_temp.as_user('owner@x.gr');
select (q_create('Γνώσεις ρεσεψιόν', 'Σύντομο τεστ'))->>'id' as q \gset
select q_save_questions(:'q', '[
  {"row":2,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Τι σημαίνει DR;","type":"Μία επιλογή","options":["Άμεση εγγραφή","Δοκιμαστικό"],"correct":"Α","points":"2","required":"Ναι","order":"1"},
  {"row":3,"specialty":"Ρεσεψιόν","section":"Αυτοαξιολόγηση","text":"Πόσο άνετα χειρίζεστε τα τηλέφωνα;","type":"Κλίμακα","options":["1","5"],"correct":"","points":"","required":"Ναι","order":"2"},
  {"row":4,"specialty":"","section":"Γενικά","text":"Σχόλια","type":"Ελεύθερο κείμενο","options":[],"correct":"","points":"","required":"Όχι","order":"3"},
  {"row":5,"specialty":"Επίβλεψη","section":"Γενικά","text":"Ερώτηση επίβλεψης","type":"Μία επιλογή","options":["Ναι","Όχι"],"correct":"Α","points":"1","required":"Ναι","order":"4"}
]', 'τεστ.xlsx');
select q_update_meta(:'q', 'Γνώσεις ρεσεψιόν', 'Σύντομο τεστ', '{Ρεσεψιόν,Επίβλεψη}', null);
select q_set_window(:'q', pg_temp.ath('-1 day'), pg_temp.ath('10 days'), 'διάστημα ερωτηματολογίου');
select pg_temp.eq((q_publish(:'q'))->>'ok', 'true', 'ερωτηματολόγιο ενεργό');

-- ══ 1. Δικαιώματα δημιουργίας: μόνο ΓΔ ══
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail(format($$select link_create(%L, '{R1}', %L, %L)$$, :'q', pg_temp.ath('-1 hour'), pg_temp.ath('2 hours')), 'HR δεν δημιουργεί συνδέσμους');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select link_create(%L, '{R1}', %L, %L)$$, :'q', pg_temp.ath('-1 hour'), pg_temp.ath('2 hours')), 'manager δεν δημιουργεί συνδέσμους');
select pg_temp.expect_fail(format($$select * from assessment_links(%L)$$, :'q'), 'manager δεν βλέπει τους συνδέσμους');

-- ══ 2. Δημιουργία: ένας διαφορετικός σύνδεσμος ανά εργαζόμενο ══
select pg_temp.as_user('owner@x.gr');
select link_create(:'q', '{R1,R2,S1,X1,ZZZ}', pg_temp.ath('-1 hour'), pg_temp.ath('2 hours')) as c \gset
select pg_temp.eq(((:'c')::jsonb->>'created')::int, 3, 'δημιουργήθηκαν 3 σύνδεσμοι (R1, R2, S1)');
select pg_temp.eq((select x->>'error' from jsonb_array_elements((:'c')::jsonb->'rows') x where x->>'employee_code' = 'X1'), 'Ο εργαζόμενος είναι ανενεργός.', 'ανενεργός εργαζόμενος απορρίπτεται με αιτιολογία');
select pg_temp.eq((select x->>'error' from jsonb_array_elements((:'c')::jsonb->'rows') x where x->>'employee_code' = 'ZZZ'), 'Ο κωδικός δεν βρέθηκε.', 'άγνωστος κωδικός απορρίπτεται');
select pg_temp.tok(:'c', 'R1') as t1, pg_temp.tok(:'c', 'R2') as t2, pg_temp.tok(:'c', 'S1') as ts \gset
select pg_temp.eq(:'t1' <> :'t2' and :'t1' <> :'ts', true, 'διαφορετικό κλειδί για κάθε εργαζόμενο');
select pg_temp.eq(length(:'t1') >= 64 and :'t1' ~ '^[0-9a-f]+$', true, 'κλειδί: μακρύ τυχαίο (≥256 bit), χωρίς προβλέψιμα στοιχεία');
select pg_temp.eq(position('R1' in upper(:'t1')) = 0 and position('ΠΕΤΡΟΥ' in upper(:'t1')) = 0, true, 'το κλειδί δεν περιέχει κωδικό ή όνομα εργαζομένου');
reset role;
select pg_temp.eq((select count(*) from assessment_assignments where token_hash = :'t1'), 0::bigint, 'στη βάση φυλάσσεται hash, όχι το κλειδί ως αναγνωριστικό');
select pg_temp.eq((select count(*) from assessment_assignments where token_hash = fill_hash(:'t1')), 1::bigint, 'το κλειδί επαληθεύεται στον server μέσω του hash');
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail($$select token_hash from assessment_assignments$$, 'ούτε η ΓΔ διαβάζει το hash απευθείας');
select pg_temp.eq((select v.version from assessment_assignments g join questionnaire_versions v on v.id = g.version_id where g.employee_code = 'R1'), 1, 'ο σύνδεσμος δένεται με την ενεργή έκδοση (1)');
select pg_temp.eq((select count(*) from assessment_links(:'q') where token is not null), 3::bigint, 'η ΓΔ μπορεί να ξανα-αντιγράψει τους ενεργούς συνδέσμους');
select pg_temp.eq(((link_create(:'q', '{R1}', pg_temp.ath('-1 hour'), pg_temp.ath('2 hours')))->'rows'->0->>'error') like 'Υπάρχει ήδη ενεργός σύνδεσμος%', true, 'όχι δεύτερος ενεργός σύνδεσμος για την ίδια αξιολόγηση');
select pg_temp.expect_fail(format($$select link_create(%L, '{R3}', %L, %L)$$, :'q', pg_temp.ath('-3 hours'), pg_temp.ath('-1 hour')), 'λήξη στο παρελθόν');
select pg_temp.expect_fail(format($$select link_create(%L, '{R3}', %L, %L)$$, :'q', pg_temp.ath('3 hours'), pg_temp.ath('1 hour')), 'λήξη πριν από την έναρξη');

-- ══ 3. Πρόσβαση χωρίς λογαριασμό, σωστή αντιστοίχιση ══
select pg_temp.as_anon();
select link_get(:'t1') as g1 \gset
select pg_temp.eq((:'g1')::jsonb->>'state', 'open', 'ανώνυμος επισκέπτης (χωρίς λογαριασμό/email) ανοίγει τον σύνδεσμο');
select pg_temp.eq((:'g1')::jsonb->'employee'->>'name', 'Ελένη Πέτρου', 'ο σύνδεσμος ανοίγει την αξιολόγηση του σωστού εργαζομένου');
select pg_temp.eq((:'g1')::jsonb->>'title', 'Γνώσεις ρεσεψιόν', 'ο σύνδεσμος ανοίγει το σωστό ερωτηματολόγιο');
select pg_temp.eq(jsonb_array_length((:'g1')::jsonb->'questions'), 3, 'μόνο οι ερωτήσεις της ειδικότητάς του (3 ρεσεψιόν + κοινές)');
select pg_temp.eq(jsonb_array_length((link_get(:'ts'))->'questions'), 2, 'ο επόπτης βλέπει τις δικές του ερωτήσεις (επίβλεψη + κοινές)');
select pg_temp.eq((link_get(:'t2'))->'employee'->>'name', 'Κατερίνα Σταύρου', 'δεύτερος σύνδεσμος → δεύτερη εργαζόμενη');
select pg_temp.eq(:'g1' ~ '"(correct|points|score|max_score|is_correct|scale_rule|multi_rule)"', false, 'ΚΑΜΙΑ σωστή απάντηση, βαθμός ή κανόνας βαθμολόγησης στο πρόγραμμα περιήγησης');
select pg_temp.eq(:'g1' like '%R1%' or :'g1' like '%Σταύρου%' or :'g1' like '%owner@x.gr%', false, 'χωρίς κωδικό εργαζομένου, στοιχεία άλλων ή email διαχειριστών');
select pg_temp.expect_fail($$select link_get('00000000000000000000000000000000000000000000000000000000000000000000')$$, 'άγνωστο κλειδί');
select pg_temp.expect_fail($$select link_get('R1')$$, 'κλειδί = κωδικός εργαζομένου δεν ανοίγει τίποτα');
select pg_temp.expect_fail(format($$select link_get(%L)$$, upper(:'t1')), 'τροποποιημένο κλειδί');

-- ══ 4. Απομόνωση: τίποτα άλλο από τον σύνδεσμο ══
select pg_temp.expect_fail($$select count(*) from assessment_attempts$$, 'σύνδεσμος: καμία πρόσβαση σε αποτελέσματα/προηγούμενες αξιολογήσεις');
select pg_temp.expect_fail($$select count(*) from assessment_questions$$, 'σύνδεσμος: καμία πρόσβαση σε ερωτήσεις/σωστές απαντήσεις');
select pg_temp.expect_fail($$select count(*) from assessment_assignments$$, 'σύνδεσμος: καμία πρόσβαση σε άλλες αναθέσεις');
select pg_temp.expect_fail($$select count(*) from assessment_link_secrets$$, 'σύνδεσμος: καμία πρόσβαση σε κλειδιά');
select pg_temp.expect_fail($$select count(*) from employees$$, 'σύνδεσμος: καμία πρόσβαση σε καρτέλες εργαζομένων');
select pg_temp.expect_fail($$select count(*) from declarations$$, 'σύνδεσμος: καμία πρόσβαση σε μισθοδοσία/υπογραφές');
select pg_temp.expect_fail($$select count(*) from hr_requests$$, 'σύνδεσμος: καμία πρόσβαση σε αιτήματα/άδειες/αναφορές');
select pg_temp.expect_fail($$select count(*) from app_users$$, 'σύνδεσμος: καμία πρόσβαση σε χρήστες');
select pg_temp.expect_fail(format($$select * from assessment_links(%L)$$, :'q'), 'σύνδεσμος: καμία πρόσβαση στη λίστα συνδέσμων');
select pg_temp.expect_fail(format($$select * from assessment_targets(%L)$$, :'q'), 'σύνδεσμος: καμία πρόσβαση σε λίστες εργαζομένων');
select pg_temp.expect_fail($$select * from employee_assessments('R1')$$, 'σύνδεσμος: καμία πρόσβαση στην καρτέλα αξιολογήσεων');
select pg_temp.expect_fail(format($$select link_lookup(%L)$$, :'t1'), 'σύνδεσμος: εσωτερικές συναρτήσεις κλειστές');
select pg_temp.expect_fail(format($$select link_create(%L, '{R3}', %L, %L)$$, :'q', pg_temp.ath('-1 hour'), pg_temp.ath('1 hour')), 'σύνδεσμος: καμία διαχειριστική ενέργεια');
select pg_temp.expect_fail($$select whoami()$$, 'σύνδεσμος: καμία συνεδρία διαχείρισης');

-- ══ 5. Προσωρινή αποθήκευση (ανανέωση σελίδας / διακοπή σύνδεσης) ══
create temp table qs as select x->>'id' id, x->>'text' tx from jsonb_array_elements((:'g1')::jsonb->'questions') x;
grant select on qs to anon, authenticated;
select (select id from qs where tx like 'Τι σημαίνει%') q1, (select id from qs where tx like 'Πόσο άνετα%') q2, (select id from qs where tx = 'Σχόλια') q3 \gset
select pg_temp.eq((link_save(:'t1', jsonb_build_object(:'q1', 'Β')))->>'ok', 'true', 'προσωρινή αποθήκευση');
select pg_temp.eq((link_get(:'t1'))->'answers'->>:'q1', 'Β', 'μετά από ανανέωση η σελίδα ξαναφέρνει τις απαντήσεις');
select pg_temp.expect_fail(format($$select link_submit(%L, null)$$, :'t1'), 'υποβολή με υποχρεωτικές χωρίς απάντηση');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select status from assessment_attempts where employee_code = 'R1'), 'in_progress', 'η προσωρινή αποθήκευση ΔΕΝ είναι υποβολή');
select pg_temp.eq((select count(*) from assessment_answers a join assessment_attempts t on t.id = a.attempt_id where t.employee_code = 'R1'), 0::bigint, 'προσωρινές απαντήσεις δεν βαθμολογούνται');
select pg_temp.eq((select opened_role from assessment_attempts where employee_code = 'R1'), 'link', 'καταγράφεται ότι η συμπλήρωση έγινε από σύνδεσμο');
select pg_temp.eq((select count(*) from assessment_attempts where employee_code = 'R2'), 1::bigint, 'το άνοιγμα της R2 δημιούργησε μόνο τη δική της προσπάθεια');
select pg_temp.eq((select answers from assessment_attempts where employee_code = 'R2'), '{}'::jsonb, 'η αποθήκευση της R1 δεν άγγιξε την R2');

-- ══ 6. Υποβολή: μία φορά, χωρίς εμφάνιση βαθμών ══
select pg_temp.as_anon();
select pg_temp.eq((link_submit(:'t1', jsonb_build_object(:'q1', 'Α', :'q2', 4, :'q3', 'Όλα καλά')))->>'ok', 'true', 'οριστική υποβολή');
select pg_temp.eq((link_submit(:'t1', jsonb_build_object(:'q1', 'Β', :'q2', 1)))->>'already', 'true', 'διπλό πάτημα / δεύτερη καρτέλα: καμία δεύτερη υποβολή');
select link_get(:'t1') as after \gset
select pg_temp.eq((:'after')::jsonb->>'state', 'submitted', 'ο σύνδεσμος δείχνει μόνο «υποβλήθηκε»');
select pg_temp.eq((:'after')::jsonb ? 'questions' or (:'after')::jsonb ? 'answers' or :'after' ~ '"(score|points|correct)"', false, 'μετά την υποβολή: ούτε βαθμολογία ούτε σωστές ούτε υποβληθείσες απαντήσεις');
select pg_temp.expect_fail(format($$select link_save(%L, '{}')$$, :'t1'), 'αλλαγή απαντήσεων μετά την υποβολή');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select status || '|' || score || '/' || max_score from assessment_attempts where employee_code = 'R1'), 'submitted|2.00/2.00', 'βαθμολόγηση στον server: 2/2 (με τις απαντήσεις της πρώτης υποβολής)');
select pg_temp.eq((select count(*) from assessment_attempts where employee_code = 'R1' and status <> 'in_progress'), 1::bigint, 'μία μόνο υποβολή για την ανάθεση');
select pg_temp.eq((select count(*) from assessment_assignment_events e join assessment_assignments g on g.id = e.assignment_id where g.employee_code = 'R1' and e.action = 'submitted'), 1::bigint, 'μία εγγραφή υποβολής στο ιστορικό');

-- ══ 7. Χρονικά όρια με ώρα server ══
select link_create(:'q', '{R3}', pg_temp.ath('2 hours'), pg_temp.ath('5 hours')) as c3 \gset
select pg_temp.tok(:'c3', 'R3') as t3 \gset
select id as a3 from assessment_assignments where employee_code = 'R3' \gset
select pg_temp.as_anon();
select pg_temp.eq((link_get(:'t3'))->>'state', 'scheduled', 'πριν από την έναρξη: «δεν είναι ακόμη διαθέσιμη»');
select pg_temp.eq((link_get(:'t3')) ? 'questions', false, 'πριν από την έναρξη: δεν στέλνονται ερωτήσεις');
select pg_temp.expect_fail(format($$select link_save(%L, '{}')$$, :'t3'), 'αποθήκευση πριν από την έναρξη');
select pg_temp.expect_fail(format($$select link_submit(%L, '{}')$$, :'t3'), 'υποβολή πριν από την έναρξη');
select pg_temp.as_user('owner@x.gr');
select link_set_window(array[:'a3']::uuid[], pg_temp.ath('-1 hour'), pg_temp.ath('1 hour'), 'έναρξη τώρα');
select pg_temp.as_anon();
select pg_temp.eq((link_get(:'t3'))->>'state', 'open', 'μέσα στο διάστημα: ανοιχτή');
select link_save(:'t3', jsonb_build_object(:'q1', 'Α'));
-- Η σελίδα ανοίχτηκε· στο μεταξύ η προθεσμία λήγει
select pg_temp.as_user('owner@x.gr');
select link_set_window(array[:'a3']::uuid[], pg_temp.ath('-2 hours'), pg_temp.ath('-1 minute'), 'λήξη');
select pg_temp.as_anon();
select pg_temp.expect_fail(format($$select link_submit(%L, %L)$$, :'t3', jsonb_build_object(:'q1', 'Α', :'q2', 3)), 'υποβολή μετά τη λήξη, παρότι η σελίδα είχε ανοιχτεί νωρίτερα');
select pg_temp.expect_fail(format($$select link_save(%L, '{}')$$, :'t3'), 'αποθήκευση μετά τη λήξη');
select pg_temp.eq((link_get(:'t3'))->>'state', 'expired', 'μετά τη λήξη: «η προθεσμία έληξε»');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select state from assessment_links(:'q') where employee_code = 'R3'), 'expired', 'η ΓΔ βλέπει «έληξε χωρίς υποβολή»');
-- Παράταση με καταγραφή
select link_set_window(array[:'a3']::uuid[], pg_temp.ath('-2 hours'), pg_temp.ath('3 hours'), 'παράταση 3 ωρών');
select pg_temp.eq((select count(*) from assessment_assignment_events where assignment_id = :'a3' and action = 'window_changed'), 3::bigint, 'κάθε αλλαγή διαθεσιμότητας καταγράφεται');
select pg_temp.eq((select detail->>'note' from assessment_assignment_events where assignment_id = :'a3' and action = 'window_changed' order by id desc limit 1), 'παράταση 3 ωρών', 'η σημείωση παράτασης καταγράφεται');
select pg_temp.eq((select (detail ? 'old_ends') and (detail ? 'new_ends') from assessment_assignment_events where assignment_id = :'a3' and action = 'window_changed' order by id desc limit 1), true, 'καταγράφονται παλιό και νέο διάστημα');
select pg_temp.eq((select due_at = g.ends_at from assessment_attempts a join assessment_assignments g on g.id = a.assignment_id where g.id = :'a3'), true, 'η προθεσμία της προσπάθειας ακολουθεί την παράταση');
select pg_temp.as_anon();
select pg_temp.eq((link_get(:'t3'))->'answers'->>:'q1', 'Α', 'μετά την παράταση: οι προσωρινές απαντήσεις είναι εκεί');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select link_set_window(array[%L]::uuid[], %L, %L, null)$$, :'a3', pg_temp.ath('-1 hour'), pg_temp.ath('9 hours')), 'manager δεν αλλάζει διαθεσιμότητα');

-- ══ 8. Ακύρωση και επανέκδοση ══
select pg_temp.as_anon();
select link_save(:'t2', jsonb_build_object(:'q1', 'Β', :'q2', 2));
select pg_temp.as_user('owner@x.gr');
select id as a2 from assessment_assignments where employee_code = 'R2' \gset
select link_cancel(:'a2', 'λάθος κατάστημα');
select pg_temp.as_anon();
select pg_temp.expect_fail(format($$select link_get(%L)$$, :'t2'), 'ακυρωμένος σύνδεσμος δεν ανοίγει');
select pg_temp.expect_fail(format($$select link_submit(%L, '{}')$$, :'t2'), 'ακυρωμένος σύνδεσμος δεν υποβάλλει');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select token from assessment_links(:'q') where employee_code = 'R2'), null::text, 'ακυρωμένος: δεν υπάρχει σύνδεσμος για αντιγραφή');
select (link_reissue(:'a2'))->>'token' as t2b \gset
select (link_reissue(:'a2'))->>'token' as t2c \gset
select pg_temp.as_anon();
select pg_temp.expect_fail(format($$select link_get(%L)$$, :'t2b'), 'επανέκδοση: ο προηγούμενος σύνδεσμος ακυρώνεται ΑΜΕΣΑ');
select pg_temp.expect_fail(format($$select link_get(%L)$$, :'t2'), 'επανέκδοση: ο αρχικός σύνδεσμος παραμένει άκυρος');
select pg_temp.eq((link_get(:'t2c'))->'answers'->>:'q1', 'Β', 'επανέκδοση: οι προσωρινές απαντήσεις δεν διαγράφονται');
select pg_temp.eq((link_get(:'t2c'))->'employee'->>'name', 'Κατερίνα Σταύρου', 'επανέκδοση: ίδια ανάθεση/εργαζόμενη');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select link_no from assessment_links(:'q') where employee_code = 'R2'), 3, 'αρίθμηση εκδόσεων συνδέσμου (3η)');
select pg_temp.eq((select string_agg(action, ',' order by id) from assessment_assignment_events where assignment_id = :'a2'), 'created,opened,cancelled,reissued,reissued', 'πλήρες ιστορικό ανάθεσης');
select id as a1 from assessment_assignments where employee_code = 'R1' \gset
select pg_temp.expect_fail(format($$select link_reissue(%L)$$, :'a1'), 'επανέκδοση ολοκληρωμένης αξιολόγησης');
select pg_temp.expect_fail(format($$select link_cancel(%L, null)$$, :'a1'), 'ακύρωση ολοκληρωμένης αξιολόγησης');
select pg_temp.expect_fail(format($$select link_set_window(array[%L]::uuid[], %L, %L, null)$$, :'a1', pg_temp.ath('-1 hour'), pg_temp.ath('9 hours')), 'παράταση ολοκληρωμένης αξιολόγησης');
select pg_temp.as_anon();
select pg_temp.eq((link_submit(:'t1', jsonb_build_object(:'q1', 'Β', :'q2', 1)))->>'already', 'true', 'ο παλιός σύνδεσμος της R1 δεν δίνει δεύτερη υποβολή');

-- ══ 9. Επαναξιολόγηση = νέα, διακριτή ανάθεση ══
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq(((link_create(:'q', '{R1}', pg_temp.ath('-1 hour'), pg_temp.ath('2 hours')))->'rows'->0->>'error') like 'Έχει ήδη υποβάλει%', true, 'χωρίς «Επαναξιολόγηση» δεν δημιουργείται νέος σύνδεσμος για όποιον υπέβαλε');
select link_create(:'q', '{R1}', pg_temp.ath('-1 hour'), pg_temp.ath('2 hours'), true) as re \gset
select pg_temp.eq(((:'re')::jsonb->'rows'->0->>'round')::int, 2, 'επαναξιολόγηση: νέα ανάθεση, 2ος γύρος');
select pg_temp.as_anon();
select pg_temp.eq((link_get(pg_temp.tok(:'re', 'R1')))->>'state', 'open', 'ο νέος σύνδεσμος ανοίγει νέα, κενή αξιολόγηση');
select pg_temp.eq((link_get(pg_temp.tok(:'re', 'R1')))->'answers', '{}'::jsonb, 'η νέα αξιολόγηση δεν φέρνει τις προηγούμενες απαντήσεις');
select link_submit(pg_temp.tok(:'re', 'R1'), jsonb_build_object(:'q1', 'Β', :'q2', 2));
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select string_agg(score::text, ',' order by submitted_at) from assessment_attempts where employee_code = 'R1'), '2.00,0.00', 'δύο διακριτά αποτελέσματα· το πρώτο δεν άλλαξε');

-- ══ 10. Συνύπαρξη με την υπάρχουσα «Έναρξη συμπλήρωσης» ══
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select fill_start_assessment(%L, 'R3')$$, :'q'), 'η παλιά ροή δεν ανοίγει δεύτερη συμπλήρωση όταν υπάρχει σύνδεσμος');
select pg_temp.expect_fail(format($$select fill_start_assessment(%L, 'R1')$$, :'q'), 'η παλιά ροή δεν επιτρέπει δεύτερη υποβολή');
-- Μισή συμπλήρωση από την παλιά ροή → συνεχίζει από σύνδεσμο με τις απαντήσεις της
reset role;
insert into employees(code,first,last,store,company,specialty) values ('R4','Μαρία','Ζαχαρίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν');
select pg_temp.as_user('glyfada@x.gr');
select (fill_start_assessment(:'q', 'R4'))->>'token' as lt \gset
select pg_temp.as_anon();
select fill_save_answers(:'lt', jsonb_build_object(:'q1', 'Α'));
select pg_temp.as_user('owner@x.gr');
select link_create(:'q', '{R4}', pg_temp.ath('-1 hour'), pg_temp.ath('2 hours')) as c4 \gset
select pg_temp.as_anon();
select pg_temp.eq((link_get(pg_temp.tok(:'c4', 'R4')))->'answers'->>:'q1', 'Α', 'μισή συμπλήρωση της παλιάς ροής συνεχίζει από τον σύνδεσμο');
select pg_temp.expect_fail(format($$select fill_save_answers(%L, '{}')$$, :'lt'), 'το παλιό κλειδί της φόρμας ακυρώθηκε');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from assessment_attempts where employee_code = 'R4'), 1::bigint, 'καμία διπλή προσπάθεια (συνέχεια, όχι νέα)');

-- ══ 11. Ορατότητα συνδέσμων και κλειδιών ══
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select count(*) from assessment_assignments) > 0, true, 'HR βλέπει την κατάσταση των αναθέσεων');
select pg_temp.expect_fail($$select token_hash from assessment_assignments$$, 'HR δεν βλέπει το hash του κλειδιού');
select pg_temp.expect_fail($$select * from assessment_link_secrets$$, 'HR δεν βλέπει κλειδιά');
select pg_temp.expect_fail(format($$select * from assessment_links(%L)$$, :'q'), 'HR δεν αντιγράφει συνδέσμους');
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail($$select * from assessment_link_secrets$$, 'ούτε η ΓΔ διαβάζει απευθείας τον πίνακα κλειδιών (μόνο μέσω της λίστας)');
select pg_temp.expect_fail($$update assessment_assignments set ends_at = now() + interval '9 days'$$, 'καμία απευθείας αλλαγή αναθέσεων (μόνο μέσω συναρτήσεων με καταγραφή)');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from assessment_assignments), 0::bigint, 'manager δεν διαβάζει απευθείας αναθέσεις');
reset role;
select pg_temp.expect_fail($$update assessment_assignment_events set actor = 'x'$$, 'το ιστορικό αναθέσεων δεν τροποποιείται');

-- ══ 12. Αποτελέσματα στην ενιαία καρτέλα εργαζομένου ══
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from assessment_attempts where employee_code = 'R1' and assignment_id is not null and score is not null), 2::bigint, 'ΓΔ/HR: τα αποτελέσματα (με βαθμούς) είναι στην καρτέλα του σωστού εργαζομένου');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select string_agg(state, ',' order by submitted_at) from employee_assessments('R1')), 'submitted,submitted', 'manager: βλέπει τις δύο υποβολές της R1 (χωρίς βαθμούς)');
select pg_temp.eq((select state from employee_assessments('R3')), 'in_progress', 'manager: σε εξέλιξη για R3');
select pg_temp.eq((select count(*) from employee_assessments('R2')), 0::bigint, 'manager Γλυφάδας δεν βλέπει εργαζόμενη Κηφισιάς');
select pg_temp.as_user('owner@x.gr');
select link_create(:'q', '{R1}', pg_temp.ath('1 hour'), pg_temp.ath('2 hours'), true);
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from employee_assessments('R1') where state = 'not_started'), 1::bigint, 'manager: ανάθεση που δεν ανοίχτηκε ακόμη φαίνεται ως «δεν ξεκίνησε»');
select pg_temp.eq((select count(*) from assessment_targets(:'q') where employee_code = 'R1'), 1::bigint, 'λίστα εργαζομένων: μία γραμμή ανά εργαζόμενο (η πιο πρόσφατη)');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
