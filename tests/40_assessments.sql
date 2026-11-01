\set ON_ERROR_STOP 1
-- Αξιολογήσεις: εισαγωγή Excel με έλεγχο ανά γραμμή, πρόχειρο/ενεργοποίηση, εκδόσεις, χρονικό διάστημα στον server,
-- απομόνωση εργαζομένου, καμία διαρροή σωστών απαντήσεων, βαθμολόγηση στον server, διπλό πάτημα. Εικονικά στοιχεία.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),
 ('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into trainer_scopes(email, store, specialty) values ('trainer@x.gr', null, 'Ρεσεψιόν');
insert into employees(code,first,last,store,company,specialty) values
 ('R1','Ελένη','Πέτρου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('R2','Κατερίνα','Σταύρου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('S1','Σάκης','Ιωάννου','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη');

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

-- Ώρα Ελλάδας με θερινή/χειμερινή ώρα
select pg_temp.eq(athens_ts('2026-07-01 10:00'), '2026-07-01 07:00:00+00'::timestamptz, 'θερινή ώρα: 10:00 Ελλάδας = 07:00 UTC');
select pg_temp.eq(athens_ts('2026-12-01 10:00'), '2026-12-01 08:00:00+00'::timestamptz, 'χειμερινή ώρα: 10:00 Ελλάδας = 08:00 UTC');
select pg_temp.expect_fail($$select athens_ts('2027-03-28 03:30')$$, 'ώρα που δεν υπάρχει (αλλαγή ώρας)');

select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select q_create('Τεστ HR', null)$$, 'HR δεν δημιουργεί ερωτηματολόγια');

select pg_temp.as_user('owner@x.gr');
select (q_create('Γνώσεις ρεσεψιόν — Νοέμβριος', 'Ερωτήσεις γνώσεων και αυτοαξιολόγησης'))->>'id' as q \gset
-- Λάθη εισαγωγής με αριθμό γραμμής, ΧΩΡΙΣ αποθήκευση
select q_save_questions(:'q', '[
  {"row":2,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Τι σημαίνει DR;","type":"Μία επιλογή","options":["Άμεση εγγραφή","Δοκιμαστικό"],"correct":"Α","points":"1","required":"Ναι","order":"1"},
  {"row":3,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Ερώτηση με λάθος τύπο","type":"Πολλαπλή","options":["α","β"],"correct":"Α","points":"1","required":"Ναι"},
  {"row":4,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Σωστή που δεν υπάρχει","type":"Μία επιλογή","options":["α","β"],"correct":"Δ","points":"1","required":"Ναι"},
  {"row":5,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Μία επιλογή, δύο σωστές","type":"Μία επιλογή","options":["α","β"],"correct":"Α,Β","points":"1","required":"Ναι"},
  {"row":6,"specialty":"Ρεσεψιόν","section":"Αυτοαξιολόγηση","text":"Κλίμακα με βαθμούς χωρίς κανόνα","type":"Κλίμακα","options":["1","5"],"correct":"","points":"2","required":"Ναι"},
  {"row":7,"specialty":"Ταμίας","section":"Χ","text":"Άγνωστη ειδικότητα","type":"Ελεύθερο κείμενο","options":[],"required":"Ναι"},
  {"row":8,"specialty":"","section":"Χ","text":"","type":"Ελεύθερο κείμενο","options":[],"required":"Ναι"},
  {"row":9,"specialty":"","section":"Χ","text":"Χωρίς Ναι/Όχι","type":"Ελεύθερο κείμενο","options":[],"required":"ίσως"}
]', 'λάθη.xlsx') as bad \gset
select pg_temp.eq((select jsonb_agg((e->>'row')::int order by (e->>'row')::int) from jsonb_array_elements((:'bad'::jsonb)->'errors') e)::text, '[3, 4, 5, 6, 7, 8, 9]', 'Excel: λάθη εντοπίζονται με αριθμό γραμμής');
select pg_temp.eq((select count(*) from assessment_questions), 0::bigint, 'Excel με λάθη: τίποτα δεν αποθηκεύεται');
-- Έγκυρο αρχείο (λατινικό A και πεζά «ναι» γίνονται δεκτά)
select q_save_questions(:'q', '[
  {"row":2,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Τι σημαίνει DR;","type":"Μία επιλογή","options":["Άμεση εγγραφή","Δοκιμαστικό","Χαμένη ενημέρωση"],"correct":"A","points":"2","required":"ναι","order":"1"},
  {"row":3,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Ποια είναι προγράμματα Exclusive;","type":"Πολλές επιλογές","options":["BODY","MUSCLE","Fitness","Pilates"],"correct":"Α, Β","points":"4","required":"Ναι","order":"2"},
  {"row":4,"specialty":"Ρεσεψιόν","section":"Αυτοαξιολόγηση","text":"Πόσο άνετα χειρίζεστε τις τηλεφωνικές ενημερώσεις;","type":"Κλίμακα","options":["1","5","Καθόλου","Πολύ"],"correct":"","points":"","required":"Ναι","order":"3"},
  {"row":5,"specialty":"Ρεσεψιόν","section":"Αυτοαξιολόγηση","text":"Συνολική αυτοεκτίμηση ετοιμότητας","type":"Κλίμακα","options":["1","5"],"correct":"αναλογικά","points":"4","required":"Ναι","order":"4"},
  {"row":6,"specialty":"","section":"Γενικά","text":"Περιγράψτε μια δύσκολη συνομιλία με μέλος.","type":"Ελεύθερο κείμενο","options":[],"correct":"","points":"5","required":"Όχι","order":"5"},
  {"row":7,"specialty":"Επίβλεψη","section":"Γενικά","text":"Ερώτηση μόνο για επίβλεψη","type":"Μία επιλογή","options":["Ναι","Όχι"],"correct":"Α","points":"1","required":"Ναι","order":"6"}
]', 'ερωτήσεις.xlsx') as good \gset
select pg_temp.eq((:'good'::jsonb)->>'count', '6', 'Excel: έγκυρο αρχείο αποθηκεύτηκε ως πρόχειρο');
select pg_temp.eq((select status from questionnaires where id = :'q'), 'draft', 'το ανέβασμα Excel δεν ενεργοποιεί το ερωτηματολόγιο');
select pg_temp.eq((select scale_rule from assessment_questions where row_no = 5), 'linear', 'κλίμακα με ρητό κανόνα ΑΝΑΛΟΓΙΚΑ');

-- Έλεγχοι πριν από ενεργοποίηση
select pg_temp.eq(jsonb_array_length((q_publish(:'q'))->'errors') >= 3, true, 'ενεργοποίηση μπλοκάρεται: χωρίς ειδικότητες, διάστημα, κανόνα πολλαπλών');
select q_update_meta(:'q', 'Γνώσεις ρεσεψιόν — Νοέμβριος', 'Ερωτήσεις γνώσεων και αυτοαξιολόγησης', '{Ρεσεψιόν,Επίβλεψη}', null);
select q_set_window(:'q', pg_temp.ath('1 day'), pg_temp.ath('2 days'), 'αρχικό διάστημα');
select pg_temp.eq(((q_publish(:'q'))->'errors')::text like '%πολλών σωστών%', true, 'απαιτείται κανόνας για πολλές σωστές επιλογές');
select q_set_multi_rule(:'q', 'partial');
select pg_temp.eq((q_publish(:'q'))->>'ok', 'true', 'ενεργοποίηση μετά από όλους τους ελέγχους');

-- Ορατότητα: σωστές απαντήσεις και βαθμοί μόνο ΓΔ/HR
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from assessment_questions), 0::bigint, 'manager δεν βλέπει ερωτήσεις/σωστές απαντήσεις');
select pg_temp.eq((select count(*) from questionnaires), 0::bigint, 'manager δεν διαβάζει απευθείας ερωτηματολόγια');
select pg_temp.eq((select count(*) from assessments_open()), 1::bigint, 'manager βλέπει τα ενεργά ερωτηματολόγια για επιλογή');
select pg_temp.eq((select count(*) from assessment_targets(:'q')), 2::bigint, 'manager: εργαζόμενοι του καταστήματός του (R1, S1)');
select pg_temp.expect_fail(format($$select fill_start_assessment(%L, 'R1')$$, :'q'), 'έναρξη πριν από το διάστημα (έλεγχος server)');

select pg_temp.as_user('owner@x.gr');
select q_set_window(:'q', pg_temp.ath('-1 hour'), pg_temp.ath('1 hour'), 'έναρξη τώρα');
select pg_temp.eq((select count(*) from questionnaire_window_log where questionnaire_id = :'q'), 2::bigint, 'κάθε αλλαγή διαστήματος καταγράφεται');

select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select fill_start_assessment(%L, 'R1')$$, :'q'), 'manager άλλου καταστήματος');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.expect_fail(format($$select fill_start_assessment(%L, 'S1')$$, :'q'), 'εκπαιδευτής εκτός πεδίου (Επίβλεψη)');
select pg_temp.eq((select count(*) from assessment_targets(:'q')), 2::bigint, 'εκπαιδευτής: Ρεσεψιόν όλων των καταστημάτων');
select fill_start_assessment(:'q', 'R2') as t2 \gset
select pg_temp.as_user('glyfada@x.gr');
select fill_start_assessment(:'q', 'R1') as t1 \gset
select (:'t1'::jsonb)->>'token' as tok, (:'t1'::jsonb)->>'attempt_id' as att \gset

-- Η οθόνη του εργαζομένου: μόνο το κλειδί, καμία διαρροή
select pg_temp.as_anon();
select fill_get(:'tok') as form \gset
select pg_temp.eq((:'form'::jsonb)->'employee'->>'code', 'R1', 'φόρμα: μόνο ο συγκεκριμένος εργαζόμενος');
select pg_temp.eq(jsonb_array_length((:'form'::jsonb)->'questions'), 5, 'φόρμα: μόνο ερωτήσεις της ειδικότητάς του');
select pg_temp.eq((select count(*) from jsonb_array_elements((:'form'::jsonb)->'questions') x where x ? 'correct' or x ? 'points'), 0::bigint, 'φόρμα: ΚΑΜΙΑ σωστή απάντηση ή βαθμός στο πρόγραμμα περιήγησης');
select pg_temp.eq(:'form' like '%"correct"%' or :'form' like '%"points"%' or :'form' like '%Σταύρου%', false, 'φόρμα: ούτε σωστές απαντήσεις ούτε στοιχεία άλλων εργαζομένων');
select pg_temp.eq((:'form'::jsonb) ? 'ends_at', true, 'φόρμα: εμφανίζεται η ακριβής προθεσμία');
select pg_temp.expect_fail($$select count(*) from assessment_attempts$$, 'φόρμα: καμία πρόσβαση σε προηγούμενες αξιολογήσεις');
select pg_temp.expect_fail($$select count(*) from assessment_questions$$, 'φόρμα: καμία πρόσβαση σε πίνακα ερωτήσεων');
select pg_temp.expect_fail(format($$select assessment_targets(%L)$$, :'q'), 'φόρμα: καμία πρόσβαση σε λίστες εργαζομένων');

-- Ερωτήσεις κατά σειρά: q1 single(2β), q2 multi(4β), q3 κλίμακα χωρίς βαθμό, q4 κλίμακα αναλογική(4β), q5 κείμενο(5β, χειροκίνητα)
create temp table qs as select row_number() over (order by x->>'id') n, x->>'id' id, x->>'qtype' t, x->>'text' tx from jsonb_array_elements((:'form'::jsonb)->'questions') x;
select (select id from qs where tx like 'Τι σημαίνει%') q1, (select id from qs where tx like 'Ποια είναι%') q2,
       (select id from qs where tx like 'Πόσο άνετα%') q3, (select id from qs where tx like 'Συνολική%') q4, (select id from qs where tx like 'Περιγράψτε%') q5 \gset
-- Προσωρινή αποθήκευση
select fill_save_answers(:'tok', jsonb_build_object(:'q1', 'Α', :'q3', 4));
select pg_temp.expect_fail(format($$select fill_submit_assessment(%L, null)$$, :'tok'), 'υποχρεωτικές χωρίς απάντηση');
-- Μη έγκυρες απαντήσεις αγνοούνται (επιλογή που δεν υπάρχει, τιμή εκτός κλίμακας)
select fill_save_answers(:'tok', jsonb_build_object(:'q1', 'Ω', :'q2', jsonb_build_array('Α','Γ'), :'q3', 9, :'q4', 4, :'q5', 'Μίλησα ήρεμα και βρήκαμε λύση.'));
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select (answers ? :'q1')::text || (answers ? :'q3')::text from assessment_attempts where id = :'att'), 'falsefalse', 'μη έγκυρες απαντήσεις δεν αποθηκεύονται');
select pg_temp.eq((select status from assessment_attempts where id = :'att'), 'in_progress', 'προσωρινές απαντήσεις ≠ υποβολή');
select pg_temp.eq((select count(*) from assessment_answers), 0::bigint, 'προσωρινές απαντήσεις δεν βαθμολογούνται');
select pg_temp.eq((select opened_by from assessment_attempts where id = :'att'), 'glyfada@x.gr', 'καταγράφεται ποιος άνοιξε τη διαδικασία');

-- Η ΓΔ αλλάζει ερωτήσεις ενώ τρέχει: νέα έκδοση, η τρέχουσα προσπάθεια μένει στην αρχική
select q_save_questions(:'q', '[
  {"row":2,"specialty":"Ρεσεψιόν","section":"Πωλήσεις","text":"Τι σημαίνει DR; (v2)","type":"Μία επιλογή","options":["Δοκιμαστικό","Άμεση εγγραφή"],"correct":"Β","points":"2","required":"Ναι","order":"1"},
  {"row":3,"specialty":"Επίβλεψη","section":"Γενικά","text":"Ερώτηση μόνο για επίβλεψη","type":"Μία επιλογή","options":["Ναι","Όχι"],"correct":"Α","points":"1","required":"Ναι","order":"2"}
]', 'v2.xlsx');
select pg_temp.eq((select count(*) from questionnaire_versions where questionnaire_id = :'q'), 2::bigint, 'αλλαγή ερωτήσεων ενεργού → νέα πρόχειρη έκδοση');
select pg_temp.eq((select v.version from questionnaires q join questionnaire_versions v on v.id = q.current_version_id where q.id = :'q'), 1, 'η ενεργή έκδοση μένει η 1 μέχρι νέα ενεργοποίηση');
select q_publish(:'q');

-- Οριστική υποβολή από τον εργαζόμενο + διπλό πάτημα
select pg_temp.as_anon();
select fill_submit_assessment(:'tok', jsonb_build_object(:'q1', 'Α', :'q2', jsonb_build_array('Α','Γ'), :'q3', 4, :'q4', 4, :'q5', 'Μίλησα ήρεμα και βρήκαμε λύση.'));
select pg_temp.eq((fill_submit_assessment(:'tok', jsonb_build_object(:'q1', 'Β')))->>'already', 'true', 'διπλό πάτημα υποβολής: δεν δημιουργείται δεύτερο αποτέλεσμα');
select pg_temp.eq((fill_get(:'tok'))->>'completed', 'true', 'μετά την υποβολή η φόρμα δεν ξανανοίγει (ούτε δείχνει βαθμούς)');
select pg_temp.expect_fail(format($$select fill_save_answers(%L, '{}')$$, :'tok'), 'αλλαγή μετά την υποβολή');

select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from assessment_answers where attempt_id = :'att'), 5::bigint, 'μία σειρά απαντήσεων (καμία διπλή)');
select pg_temp.eq((select v.version from assessment_attempts a join questionnaire_versions v on v.id = a.version_id where a.id = :'att'), 1, 'η υποβολή κρατά την έκδοση με την οποία ξεκίνησε');
-- Βαθμολόγηση στον server: q1 σωστό 2/2 · q2 μερική: (1 σωστή − 1 λάθος)/2 → 0/4 · q3 χωρίς βαθμό · q4 (4−1)/(5−1)×4 = 3/4 · q5 χειροκίνητα
select pg_temp.eq((select points from assessment_answers where attempt_id = :'att' and question_id = :'q1'::uuid), 2.00, 'βαθμός μίας επιλογής');
select pg_temp.eq((select points from assessment_answers where attempt_id = :'att' and question_id = :'q2'::uuid), 0.00, 'βαθμός πολλών επιλογών με κανόνα «μερική»');
select pg_temp.eq((select coalesce(points::text,'—')||'|'||coalesce(is_correct::text,'—') from assessment_answers where attempt_id = :'att' and question_id = :'q3'::uuid), '—|—', 'αυτοαξιολόγηση: ούτε σωστό/λάθος ούτε βαθμός');
select pg_temp.eq((select points from assessment_answers where attempt_id = :'att' and question_id = :'q4'::uuid), 3.00, 'κλίμακα με ρητό αναλογικό κανόνα');
select pg_temp.eq((select status||'|'||coalesce(score::text,'—') from assessment_attempts where id = :'att'), 'pending_manual|—', 'ελεύθερο κείμενο: αναμένει χειροκίνητη βαθμολόγηση, χωρίς συνολικό');
select pg_temp.expect_fail(format($$select assessment_grade(%L, %L, 9)$$, :'att', :'q5'), 'χειροκίνητος βαθμός πάνω από το μέγιστο');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select assessment_grade(%L, %L, 4)$$, :'att', :'q5'), 'manager δεν βαθμολογεί');
select pg_temp.eq((select state from employee_assessments('R1')), 'pending_manual', 'manager βλέπει μόνο κατάσταση (χωρίς βαθμούς)');
select pg_temp.as_user('hr@x.gr');
select assessment_grade(:'att', :'q5', 4);
select pg_temp.eq((select status||'|'||score||'/'||max_score from assessment_attempts where id = :'att'), 'submitted|9.00/15.00', 'συνολικό μετά τη χειροκίνητη βαθμολόγηση: 9/15');

-- Λήξη: η προσωρινή αποθήκευση δεν γίνεται υποβολή, ο server αρνείται μετά τη λήξη
select pg_temp.as_user('owner@x.gr');
select q_set_window(:'q', pg_temp.ath('-2 hours'), pg_temp.ath('-1 minute'), 'λήξη');
select pg_temp.as_anon();
select pg_temp.expect_fail(format($$select fill_save_answers(%L, '{}')$$, (:'t2'::jsonb)->>'token'), 'αποθήκευση μετά τη λήξη (έλεγχος server)');
select pg_temp.expect_fail(format($$select fill_submit_assessment(%L, '{}')$$, (:'t2'::jsonb)->>'token'), 'υποβολή μετά τη λήξη (έλεγχος server)');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select state from assessment_targets(:'q') where employee_code = 'R2'), 'expired', 'έληξε χωρίς υποβολή');
select pg_temp.eq((select state from assessment_targets(:'q') where employee_code = 'S1'), 'not_started', 'δεν ξεκίνησε');
select pg_temp.expect_fail(format($$select fill_start_assessment(%L, 'S1')$$, :'q'), 'νέα έναρξη μετά τη λήξη');
-- Παράταση από ΓΔ: καταγράφεται και η αξιολόγηση ξαναγίνεται διαθέσιμη
select q_set_window(:'q', pg_temp.ath('-2 hours'), pg_temp.ath('3 hours'), 'παράταση 3 ωρών');
select pg_temp.eq((select note from questionnaire_window_log where questionnaire_id = :'q' order by id desc limit 1), 'παράταση 3 ωρών', 'η παράταση καταγράφεται στο ιστορικό');
select pg_temp.eq((select state from assessment_targets(:'q') where employee_code = 'R2'), 'in_progress', 'μετά την παράταση: σε εξέλιξη');
select pg_temp.expect_fail(format($$select fill_start_assessment(%L, 'R1')$$, :'q'), 'δεύτερη αξιολόγηση μετά την υποβολή (δεν έχουν συμφωνηθεί επαναλήψεις)');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
