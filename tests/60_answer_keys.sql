\set ON_ERROR_STOP 1
-- Σωστές απαντήσεις (κατ' εκτίμηση → επιβεβαίωση → νέα έκδοση), παραδείγματα βαθμολόγησης, αξιολογήσεις AI. Εικονικά στοιχεία.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα');
insert into employees(code,first,last,store,company,specialty) values
 ('G1','Νίκος','Γυμναστής','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη'),
 ('G2','Μαρία','Προπονήτρια','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη'),
 ('G3','Τάκης','Δοκιμαστικός','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη');

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

-- Ερωτηματολόγιο γυμναστών ΧΩΡΙΣ σωστές απαντήσεις (όπως ανέβηκε από Excel), ενεργό, με υποβολές
select pg_temp.as_user('owner@x.gr');
select (q_create('Γνώσεις γυμναστών', null))->>'id' as q \gset
select q_save_questions(:'q', '[
  {"row":2,"specialty":"Επίβλεψη","section":"Ασφάλεια","text":"Τι κάνετε αν ένας πελάτης ζαλιστεί στο διάδρομο;","type":"Μία επιλογή","options":["Τον αφήνω να συνεχίσει","Σταματώ το μηχάνημα και τον βάζω να καθίσει","Του δίνω ενεργειακό ποτό"],"correct":"","points":"","required":"Ναι","order":"1"},
  {"row":3,"specialty":"Επίβλεψη","section":"Ασφάλεια","text":"Ποια σημεία ελέγχετε στα μηχανήματα κάθε πρωί;","type":"Πολλές επιλογές","options":["Καλώδια","Συρματόσχοινα","Χρώμα"],"correct":"","points":"","required":"Ναι","order":"2"},
  {"row":4,"specialty":"Επίβλεψη","section":"Εξυπηρέτηση","text":"Πώς προτείνετε προσωπική προπόνηση σε νέο μέλος;","type":"Ελεύθερο κείμενο","options":[],"correct":"","points":"","required":"Ναι","order":"3"},
  {"row":5,"specialty":"Επίβλεψη","section":"Αυτοαξιολόγηση","text":"Πόσο άνετα νιώθετε με νέα μέλη;","type":"Κλίμακα","options":["1","5"],"correct":"","points":"","required":"Ναι","order":"4"}
]', 'γυμναστές.xlsx');
select q_update_meta(:'q', 'Γνώσεις γυμναστών', null, '{Επίβλεψη}', null);
select q_set_window(:'q', pg_temp.ath('-1 day'), pg_temp.ath('10 days'), null);
select q_publish(:'q');
select current_version_id as v1 from questionnaires where id = :'q' \gset
select (select id from assessment_questions where version_id = :'v1' and row_no = 2) as v1q1, (select id from assessment_questions where version_id = :'v1' and row_no = 4) as v1q3 \gset
-- Δύο γυμναστές υποβάλλουν (με την έκδοση 1)
select link_create(:'q', '{G1,G2,G3}', pg_temp.ath('-1 hour'), pg_temp.ath('5 hours')) as c \gset
create temp table toks as select x->>'employee_code' code, x->>'token' t from jsonb_array_elements((:'c')::jsonb->'rows') x;
grant select on toks to anon, authenticated;
select (select id from assessment_questions where version_id = :'v1' and row_no = 3) as v1q2, (select id from assessment_questions where version_id = :'v1' and row_no = 5) as v1q4 \gset
select pg_temp.as_anon();
select link_get((select t from toks where code = 'G1'));
select link_submit((select t from toks where code = 'G1'), jsonb_build_object(:'v1q1', 'Β', :'v1q2', '["Α","Β"]'::jsonb, :'v1q3', 'Του λέω τα οφέλη και του κλείνω δωρεάν δοκιμαστική προπόνηση.', :'v1q4', 4));
select link_get((select t from toks where code = 'G2'));
select link_submit((select t from toks where code = 'G2'), jsonb_build_object(:'v1q1', 'Α', :'v1q2', '["Γ"]'::jsonb, :'v1q3', 'Του λέω ότι είναι ακριβή αλλά αξίζει.', :'v1q4', 2));
select link_get((select t from toks where code = 'G3'));
select link_submit((select t from toks where code = 'G3'), jsonb_build_object(:'v1q1', 'Β', :'v1q2', '["Α"]'::jsonb, :'v1q3', 'Τον ρωτάω για τους στόχους του και του προτείνω πρόγραμμα.', :'v1q4', 5));

-- ══ 1. Σωστές απαντήσεις σε πρόχειρη έκδοση ══
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail(format($$select q_key_save(%L, '["Β"]', null, null, 'estimate')$$, :'v1q1'), 'καμία αλλαγή στην ενεργή έκδοση');
select q_key_begin(:'q') as b \gset
select ((:'b')::jsonb->>'version_id') as v2 \gset
select pg_temp.eq(((:'b')::jsonb->>'version')::int, 2, 'η «Έναρξη» δημιουργεί πρόχειρη έκδοση 2');
select pg_temp.eq((select current_version_id from questionnaires where id = :'q'), (:'v1')::uuid, 'οι εργαζόμενοι συνεχίζουν με την ενεργή έκδοση 1');
select pg_temp.eq((q_key_begin(:'q'))->>'version_id', :'v2', 'δεύτερη «Έναρξη»: ίδια πρόχειρη (όχι νέα)');
select (select id from assessment_questions where version_id = :'v2' and row_no = 2) as q1, (select id from assessment_questions where version_id = :'v2' and row_no = 3) as q2,
       (select id from assessment_questions where version_id = :'v2' and row_no = 4) as q3, (select id from assessment_questions where version_id = :'v2' and row_no = 5) as q4 \gset
select q_key_save(:'q1', '["Β"]', 'Ασφάλεια πρώτα: σταματάμε και καθίζουμε.', null, 'estimate', 'το δεύτερο, σταματάω το μηχάνημα', null);
select q_key_save(:'q2', '["Α","Β"]', null, null, 'estimate', 'α και β', 'Χαμηλή βεβαιότητα του AI — ελέγξτε.');
select q_key_save(:'q3', null, 'Ρωτάω στόχους, προτείνω δωρεάν δοκιμαστική, κλείνω ραντεβού. Ποτέ πίεση ή σχόλια για το σώμα.', null, 'estimate', 'πρώτα ρωτάς στόχους…', null);
select pg_temp.eq((select key_status || '|' || correct::text || '|' || key_spoken from assessment_questions where id = :'q1'), 'estimate|["Β"]|το δεύτερο, σταματάω το μηχάνημα', 'εκτίμηση: επιλογή, κατάσταση και τι ειπώθηκε');
select pg_temp.eq((select correct from assessment_questions where id = :'v1q1'), null::jsonb, 'η ενεργή έκδοση δεν άλλαξε');
select pg_temp.expect_fail(format($$select q_key_save(%L, '["Α","Β"]', null, null, 'estimate')$$, :'q1'), 'μία επιλογή: όχι δύο σωστές');
select pg_temp.expect_fail(format($$select q_key_save(%L, '["Ζ"]', null, null, 'estimate')$$, :'q1'), 'σωστή που δεν υπάρχει στις επιλογές');
select pg_temp.expect_fail(format($$select q_key_save(%L, '["Α"]', 'x', null, 'estimate')$$, :'q3'), 'ελεύθερο κείμενο: χωρίς σωστή επιλογή');
select pg_temp.expect_fail(format($$select q_key_save(%L, null, null, 2, 'confirmed')$$, :'q1'), 'βαθμοί χωρίς σωστή απάντηση');
select pg_temp.expect_fail(format($$select q_key_save(%L, null, 'x', 3, 'confirmed')$$, :'q4'), 'κλίμακα: βαθμοί μόνο από Excel');
-- Ενεργοποίηση μπλοκάρεται όσο υπάρχουν εκτιμήσεις
select pg_temp.eq((select count(*) from jsonb_array_elements_text(q_check(:'q')) e where e like '%κατ'' εκτίμηση%'), 1::bigint, 'έλεγχος ενεργοποίησης: «3 κατ'' εκτίμηση δεν επιβεβαιώθηκαν»');
select pg_temp.eq((q_publish(:'q'))->>'ok', 'false', 'δεν ενεργοποιείται έκδοση με ανεπιβεβαίωτες εκτιμήσεις του AI');
-- Διόρθωση + επιβεβαίωση
select q_key_save(:'q2', '["Α","Β"]', null, null, 'confirmed');
select pg_temp.eq((select key_status || '|' || coalesce(key_note, '-') from assessment_questions where id = :'q2'), 'confirmed|-', 'διόρθωση = επιβεβαίωση, φεύγει η σημείωση');
select pg_temp.eq(((q_key_confirm(:'v2', null))->>'confirmed')::int, 2, 'επιβεβαίωση όλων των υπολοίπων εκτιμήσεων');
select pg_temp.eq(((q_key_points(:'v2', 2))->>'updated')::int, 2, 'βαθμοί (2) σε όσες επιλογές έχουν σωστή απάντηση');
select q_key_save(:'q3', null, (select model_answer from assessment_questions where id = :'q3'), 10, 'confirmed');
select q_set_multi_rule(:'q', 'partial');
select pg_temp.eq((q_publish(:'q'))->>'version', '2', 'ενεργοποίηση έκδοσης 2 μετά την επιβεβαίωση');
select pg_temp.eq((select score::text from assessment_attempts where employee_code = 'G1'), null, 'οι υποβολές της έκδοσης 1 μένουν όπως ήταν (χωρίς αναδρομική βαθμολόγηση)');

-- ══ 2. Η πρότυπη απάντηση δεν φτάνει ποτέ στον εργαζόμενο ══
select link_create(:'q', '{G1}', pg_temp.ath('-1 hour'), pg_temp.ath('5 hours'), true) as c2 \gset
select pg_temp.as_anon();
select link_get((select x->>'token' from jsonb_array_elements((:'c2')::jsonb->'rows') x)) as g \gset
select pg_temp.eq(:'g' like '%δοκιμαστική, κλείνω%' or :'g' ~ '"(correct|model_answer|key_spoken|points)"', false, 'σελίδα εργαζομένου: ούτε σωστή/πρότυπη απάντηση ούτε βαθμοί');
select pg_temp.eq(jsonb_array_length((:'g')::jsonb->'questions'), 4, 'ο νέος σύνδεσμος παίρνει την έκδοση 2');
select pg_temp.expect_fail($$select q_key_begin('00000000-0000-0000-0000-000000000000')$$, 'σύνδεσμος: καμία πρόσβαση στις σωστές απαντήσεις');
select pg_temp.expect_fail($$select count(*) from answer_examples$$, 'σύνδεσμος: καμία πρόσβαση στα παραδείγματα');
select pg_temp.expect_fail($$select count(*) from ai_evaluations$$, 'σύνδεσμος: καμία πρόσβαση στις αξιολογήσεις AI');

-- ══ 3. Παραδείγματα βαθμολόγησης ══
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from ex_answers(:'q')), 3::bigint, 'λίστα απαντήσεων ελεύθερου κειμένου (3 υποβολές)');
select pg_temp.eq((select count(*) from ex_answers(:'q') where model_answer like 'Ρωτάω στόχους%'), 3::bigint, 'απαντήσεις της έκδοσης 1 αξιολογούνται με τη σωστή απάντηση που ορίστηκε στην έκδοση 2');
select pg_temp.eq((select answer_text from ex_answers(:'q') where employee_code = 'G2'), 'Του λέω ότι είναι ακριβή αλλά αξίζει.', 'η απάντηση εμφανίζεται ως κείμενο');
select id as a1 from assessment_attempts where employee_code = 'G1' and version_id = :'v1' \gset
select attempt_id as a2 from ex_answers(:'q') where employee_code = 'G2' \gset
select attempt_id as a3 from ex_answers(:'q') where employee_code = 'G3' \gset
select ex_save(:'a1', :'v1q3', 8, 'Καλά: δοκιμαστική. Έλειπε: δεν ρώτησε στόχους.', 'οκτώ, γιατί…', 'voice');
select ex_save(:'a2', :'v1q3', 3, 'Δεν λέμε ποτέ «ακριβή»· καμία πρόταση δοκιμαστικής.', null, 'typed');
select pg_temp.eq((select count(*) from answer_examples where questionnaire_id = :'q'), 2::bigint, 'δύο παραδείγματα με βαθμό και λόγο');
select ex_save(:'a1', :'v1q3', 7.5, 'Αναθεώρηση.', null, 'typed');
select pg_temp.eq((select score::text from answer_examples where attempt_id = :'a1'), '7.5', 'ξαναβαθμολόγηση: ενημέρωση, όχι διπλό');
select pg_temp.eq((select count(*) from ex_for_question(:'q3')), 2::bigint, 'τα παραδείγματα ισχύουν και για τη νέα έκδοση της ίδιας ερώτησης');
select pg_temp.expect_fail(format($$select ex_save(%L, %L, 11, null)$$, :'a1', :'v1q3'), 'βαθμός εκτός 0–10');
select pg_temp.expect_fail(format($$select ex_save(%L, %L, 5, null)$$, :'a1', :'q3'), 'λάθος ερώτηση για την απάντηση (άλλη έκδοση)');

-- ══ 4. Αξιολογήσεις AI: προτάσεις → αποδοχή / διόρθωση / απόρριψη ══
select ev_save(:'v1q3', jsonb_build_array(jsonb_build_object('attempt_id', :'a3', 'score', 9.2, 'reason', 'Ρώτησε στόχους και πρότεινε πρόγραμμα· δεν ανέφερε δοκιμαστική.'),
                                          jsonb_build_object('attempt_id', :'a2', 'score', 3, 'reason', 'Είπε «ακριβή».')), 2, 'claude-haiku-5-5');
select pg_temp.eq((select score::text || '|' || status from ai_evaluations where attempt_id = :'a3'), '9.2|suggested', 'πρόταση AI αποθηκεύεται (δεν αλλάζει βαθμολογία)');
select pg_temp.eq((select graded_at from assessment_answers where attempt_id = :'a3' and question_id = :'v1q3'), null::timestamptz, 'η πρόταση δεν βαθμολογεί από μόνη της');
select id as e3 from ai_evaluations where attempt_id = :'a3' \gset
select id as e2 from ai_evaluations where attempt_id = :'a2' \gset
select pg_temp.eq((ev_review(:'e3', 'correct', 6, 'Έλειπε η δοκιμαστική.'))->>'ok', 'true', 'διόρθωση από τη ΓΔ');
select pg_temp.eq((select score::text || '|' || source from answer_examples where attempt_id = :'a3'), '6.0|correction', 'η διόρθωση έγινε νέο παράδειγμα για το AI');
select pg_temp.eq((select status || '|' || final_score from ai_evaluations where id = :'e3'), 'corrected|6.0', 'κρατιέται πρόταση AI και τελικός βαθμός');
select ev_save(:'v1q3', jsonb_build_array(jsonb_build_object('attempt_id', :'a3', 'score', 1, 'reason', 'x')), 0, 'm');
select pg_temp.eq((select final_score::text from ai_evaluations where id = :'e3'), '6.0', 'νέα εκτέλεση AI δεν αλλάζει όσες έλεγξε η ΓΔ');
select ev_review(:'e2', 'reject', null, null);
select pg_temp.eq((select status from ai_evaluations where id = :'e2'), 'rejected', 'απόρριψη πρότασης');
-- Ερώτηση με βαθμούς (έκδοση 2): ο βαθμός περνά αναλογικά
select pg_temp.as_anon();
select link_submit((select x->>'token' from jsonb_array_elements((:'c2')::jsonb->'rows') x), jsonb_build_object(:'q1', 'Β', :'q2', '["Α","Β"]'::jsonb, :'q3', 'Ρωτάω στόχους και προτείνω δοκιμαστική.', :'q4', 3));
select pg_temp.as_user('owner@x.gr');
select id as a4 from assessment_attempts where employee_code = 'G1' and version_id = :'v2' \gset
select pg_temp.eq((select status from assessment_attempts where id = :'a4'), 'pending_manual', 'νέα έκδοση: η ερώτηση κειμένου (10 βαθμοί) αναμένει βαθμολόγηση');
select ev_save(:'q3', jsonb_build_array(jsonb_build_object('attempt_id', :'a4', 'score', 8.5, 'reason', 'Πλήρης.')), 3, 'm');
select pg_temp.eq((ev_review((select id from ai_evaluations where attempt_id = :'a4'), 'accept'))->>'points', '8.50', 'αποδοχή: 8,5/10 → 8,5 από 10 βαθμούς');
select pg_temp.eq((select status || '|' || score from assessment_attempts where id = :'a4'), 'submitted|12.50', 'η βαθμολογία ολοκληρώθηκε (2 + 2 + 8,5)');

-- ══ 5. Δικαιώματα ══
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select count(*) from ex_answers(:'q')) > 0, true, 'HR βλέπει απαντήσεις/παραδείγματα/αξιολογήσεις');
select pg_temp.expect_fail(format($$select ex_save(%L, %L, 5, null)$$, :'a1', :'v1q3'), 'HR δεν προσθέτει παραδείγματα');
select pg_temp.expect_fail(format($$select ev_review(%L, 'accept')$$, :'e2'), 'HR δεν αποδέχεται προτάσεις AI');
select pg_temp.expect_fail(format($$select q_key_begin(%L)$$, :'q'), 'HR δεν αλλάζει σωστές απαντήσεις');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select * from ex_answers(%L)$$, :'q'), 'manager: καμία πρόσβαση');
select pg_temp.eq((select count(*) from answer_examples), 0::bigint, 'manager δεν διαβάζει παραδείγματα');
select pg_temp.expect_fail($$insert into ai_evaluations(attempt_id, question_id, score, reason, created_by) values (gen_random_uuid(), gen_random_uuid(), 1, 'x', 'x')$$, 'καμία απευθείας εγγραφή');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
