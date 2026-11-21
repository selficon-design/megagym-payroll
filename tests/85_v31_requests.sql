\set ON_ERROR_STOP 1
-- Έκδοση 3.1 · Exit Interview/ερωτηματολόγια έως 12 επιλογές (Α..ΙΒ), «Αναρρωτική Άδεια» ως κύρια κατηγορία
-- με ασφαλή μεταφορά των παλιών, αλλαγή ημερομηνιών εκκρεμούς άδειας από manager (αναθεωρήσεις), τμηματική
-- έγκριση από HR/ΓΔ (μόνο συγκεκριμένες ημέρες ή άλλες ημερομηνίες)· η αιτιολογία είναι προαιρετική (απόφαση 21/11).
-- ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά');
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('R1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-03-16'),
 ('R2','Μαρία','Βλάχου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-03-16');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.ver(p uuid) returns int language sql as $$ select version from hr_requests where id = p $$;
create or replace function pg_temp.leave(c text, cat text, t text, s date, e date, n text) returns uuid language plpgsql as $$
declare v uuid;
begin
  v := (req_create(jsonb_build_object('category',cat,'employee_code',c,'entry_mode','manager_record','leave_type',t,
        'start_date',s,'end_date',e,'days_requested',n,'body','Παρακαλώ να εγκρίνετε την άδεια του εργαζομένου.'))->>'id')::uuid;
  perform req_submit(v, 1);
  return v;
end $$;

-- ═══════ 1. Έως 12 επιλογές (Α..ΙΒ) ═══════
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq(array_length(q_letters(), 1) || '|' || (q_letters())[6] || '|' || (q_letters())[12], '12|ΣΤ|ΙΒ', 'γράμματα Α,Β,Γ,Δ,Ε,ΣΤ,Ζ,Η,Θ,Ι,ΙΑ,ΙΒ');
select q_parse_rows('[{"row":2,"text":"Ποιος ήταν ο κύριος λόγος αποχώρησης;","type":"Μία επιλογή","required":"Ναι","correct":"ΙΒ","points":"1",
  "options":["Αποδοχές","Ωράριο","Απόσταση","Σχέσεις","Εξέλιξη","Σπουδές","Υγεία","Οικογένεια","Νέα θέση","Μετακόμιση","Συνθήκες","Άλλο"]}]'::jsonb) as p12 \gset
select pg_temp.eq(jsonb_array_length(:'p12'::jsonb->'errors'), 0, '12 επιλογές χωρίς σφάλμα');
select pg_temp.eq(jsonb_array_length(:'p12'::jsonb->'questions'->0->'options'), 12, 'αποθηκεύονται και οι 12 επιλογές');
select pg_temp.eq(:'p12'::jsonb->'questions'->0->'options'->11->>'key' || '|' || (:'p12'::jsonb->'questions'->0->'options'->11->>'label'), 'ΙΒ|Άλλο', 'η 12η επιλογή έχει γράμμα ΙΒ');
select pg_temp.eq(:'p12'::jsonb->'questions'->0->'correct'->>0, 'ΙΒ', 'σωστή απάντηση ΙΒ');
select pg_temp.eq(q_parse_rows('[{"row":2,"text":"Ερώτηση με κενό","type":"Μία επιλογή","required":"Ναι","options":["Α1","Β1","","","","","","","","","Λ","Μ"]}]'::jsonb)->'errors'->0->>'msg',
  'Η επιλογή ΙΑ υπάρχει ενώ λείπει προηγούμενη επιλογή.', 'κενό πριν από την ΙΑ: σαφές μήνυμα');
select pg_temp.eq(q_parse_rows('[{"row":2,"text":"Ερώτηση με 6 επιλογές","type":"Πολλές επιλογές","required":"Όχι","correct":"Α,ΣΤ","options":["1","2","3","4","5","6"]}]'::jsonb)->'questions'->0->'correct',
  '["Α","ΣΤ"]'::jsonb, 'παλιά πρότυπα 6 επιλογών λειτουργούν όπως πριν');

-- ═══════ 2. Αναρρωτική Άδεια ως κύρια κατηγορία ═══════
select pg_temp.as_user('hr@x.gr');
select leave_set_base('R1', 22, '2024-03-16', 'Βάση πενθημέρου');
select leave_set_base('R2', 22, '2024-03-16', 'Βάση πενθημέρου');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select req_create('{"category":"leave","employee_code":"R1","entry_mode":"manager_record","leave_type":"sick","start_date":"2026-11-02","end_date":"2026-11-03","days_requested":"2","body":"Παρακαλώ να εγκρίνετε την άδεια."}')$$,
  'η αναρρωτική δεν καταχωρίζεται πια ως υποκατηγορία της «Άδεια / απουσία»');
select leave_balance_calc('R1', '2026-12-31')->>'balance' as bal0 \gset
select pg_temp.leave('R1','sick_leave',null,'2026-11-02','2026-11-03','2') as sk \gset
select pg_temp.eq((select category||'|'||leave_type||'|'||req_category_label(category) from hr_requests where id = :'sk'), 'sick_leave|sick|Αναρρωτική Άδεια', 'νέα κατηγορία: είδος «sick» ορίζεται αυτόματα');
select pg_temp.as_user('hr@x.gr');
select req_decide(:'sk','approve','{"message":"Η αναρρωτική άδεια καταχωρίστηκε."}', pg_temp.ver(:'sk'));
select pg_temp.eq((select count(*) from leave_days where request_id = :'sk' and leave_type = 'sick' and status = 'active'), 2::bigint, 'ημέρες αναρρωτικής στο ημερολόγιο');
select pg_temp.eq(leave_balance_calc('R1', '2026-12-31')->>'balance', :'bal0', 'η αναρρωτική δεν αφαιρείται από την κανονική άδεια');
select pg_temp.eq((sick_status('R1','2026-11-30')->>'sick_days')::int = 2, true, 'μετρά στην κάλυψη αποδοχών αναρρωτικής');
-- Παλιό αίτημα «Άδεια / απουσία → Αναρρωτική» (όπως ήταν πριν από την 3.1): ίδιο id, κατάσταση, ημέρες, ιστορικό
reset role;
alter table hr_requests disable trigger hr_requests_sick_category;
update hr_requests set category = 'leave' where id = :'sk';
alter table hr_requests enable trigger hr_requests_sick_category;
select count(*) as ev0 from hr_request_events where request_id = :'sk' \gset
select pg_temp.eq(req_migrate_sick(), 1, 'μεταφορά παλιού αιτήματος αναρρωτικής');
select pg_temp.eq((select category||'|'||status||'|'||ref from hr_requests where id = :'sk'), 'sick_leave|approved|' || (select ref from hr_requests where id = :'sk'), 'ίδιο αίτημα, ίδια κατάσταση και αριθμός');
select pg_temp.eq((select count(*) from leave_days where request_id = :'sk' and status = 'active'), 2::bigint, 'οι ημέρες άδειας δεν διπλασιάστηκαν ούτε χάθηκαν');
select pg_temp.eq((select count(*) from hr_request_events where request_id = :'sk'), (:ev0 + 1)::bigint, 'το ιστορικό κρατιέται και προστίθεται «μεταφορά»');
select pg_temp.eq(req_migrate_sick(), 0, 'η μεταφορά δεν ξανατρέχει σε ήδη μεταφερμένα (χωρίς διπλά)');
select pg_temp.eq((select count(*) from hr_decisions where request_id = :'sk'), 1::bigint, 'η απόφαση μένει ως είχε');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from hr_requests where category = 'sick_leave')::int || '|' || (select count(*) from hr_requests where category = 'leave')::int, '1|0', 'ξεχωριστό φίλτρο κατηγορίας στο ιστορικό');

-- ═══════ 9. Αλλαγή ημερομηνιών εκκρεμούς αιτήματος από manager ═══════
select pg_temp.leave('R1','leave','annual','2026-12-07','2026-12-11','5') as lv \gset
select pg_temp.eq((select leave_requested from hr_requests where id = :'lv'), 5.00, 'αρχικό αίτημα 5 ημερών');
select pg_temp.expect_fail(format($$select req_change_dates(%L,'2026-12-14','2026-12-18',5,'x',%s)$$, :'lv', pg_temp.ver(:'lv')), 'χωρίς λόγο αλλαγής');
select pg_temp.ver(:'lv') as v1 \gset
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select req_change_dates(%L,'2026-12-14','2026-12-18',5,'Αλλαγή προγράμματος',%s)$$, :'lv', :v1), 'manager άλλου καταστήματος');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.ver(:'lv') as v_old \gset
select req_change_dates(:'lv', '2026-12-14', '2026-12-17', 4, 'Ο εργαζόμενος ζήτησε να μετακινηθεί μία εβδομάδα', :v_old);
select pg_temp.eq((select start_date||'|'||end_date||'|'||days_requested||'|'||leave_requested||'|'||date_revision from hr_requests where id = :'lv'),
  '2026-12-14|2026-12-17|4.0|4.00|2', 'νέες ημερομηνίες και επανυπολογισμός ημερών');
select pg_temp.eq((select string_agg(rev_no||':'||start_date||'-'||end_date||':'||days_requested, ' ' order by rev_no) from hr_request_revisions where request_id = :'lv'),
  '1:2026-12-07-2026-12-11:5.0 2:2026-12-14-2026-12-17:4.0', 'κρατιούνται οι αρχικές ημερομηνίες και κάθε αναθεώρηση');
select pg_temp.expect_fail(format($$select req_change_dates(%L,'2026-12-21','2026-12-22',2,'Δεύτερη αλλαγή',%s)$$, :'lv', :v_old), 'αλλαγή πάνω σε παλιά έκδοση');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select count(*) from notifications where user_email = 'hr@x.gr' and request_id = :'lv' and kind = 'dates_revised'), 1::bigint, 'ειδοποίηση του αρμόδιου εγκρίνοντα');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Το αίτημα εγκρίθηκε."}',%s)$$, :'lv', :v_old), 'έγκριση παλιάς έκδοσης μπλοκάρεται');

-- ═══════ 10. Μερική έγκριση: μόνο συγκεκριμένες ημέρες ═══════
select pg_temp.eq((leave_preview('R1','2026-12-14','2026-12-17','annual',:'lv','{2026-12-14,2026-12-15}'::date[])->>'requested')::numeric, 2::numeric, 'προεπισκόπηση: χρέωση μόνο των επιλεγμένων ημερών');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Το αίτημα εγκρίθηκε.","include":[],"diff_reason":"Κάλυψη προγράμματος"}',%s)$$, :'lv', pg_temp.ver(:'lv')),
  'έγκριση χωρίς καμία ημέρα');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Το αίτημα εγκρίθηκε.","include":["2026-12-21"],"diff_reason":"Κάλυψη προγράμματος"}',%s)$$, :'lv', pg_temp.ver(:'lv')),
  'ημέρα εκτός διαστήματος');
select req_decide(:'lv', 'approve', '{"message":"Το αίτημα εγκρίθηκε για τις 14 και 15 Δεκεμβρίου.","include":["2026-12-14","2026-12-15"],"diff_reason":"Δεν καλύπτεται το πρόγραμμα 16-17/12"}', pg_temp.ver(:'lv'));
select pg_temp.eq((select string_agg(day::text, ',' order by day) from leave_days where request_id = :'lv' and status = 'active'), '2026-12-14,2026-12-15', 'μόνο οι εγκεκριμένες ημέρες στο ημερολόγιο');
select pg_temp.eq((select sum(c.amount) from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = :'lv' and d.status = 'active'), 2.00, 'χρέωση υπολοίπου μόνο 2 ημέρες, μία φορά');
select pg_temp.eq((select requested_start||'|'||requested_end||'|'||requested_days||'|'||approved_days||'|'||jsonb_array_length(approved_dates)||'|'||date_revision||'|'||(diff_reason is not null)
   from hr_decisions where request_id = :'lv' and superseded_at is null), '2026-12-14|2026-12-17|4.0|2.0|2|2|true', 'αποθηκεύονται αιτούμενες vs εγκεκριμένες ημέρες και η αιτιολογία');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from notifications where user_email = 'glyfada@x.gr' and request_id = :'lv' and title like '%τελικές ημερομηνίες 14/12, 15/12/2026 (2 ημέρες)%εγκρίθηκαν μόνο ορισμένες από τις αιτούμενες ημερομηνίες%'), 1::bigint,
  'ο manager ενημερώνεται για τις τελικές ημερομηνίες');
select pg_temp.expect_fail(format($$select req_change_dates(%L,'2026-12-21','2026-12-22',2,'Αλλαγή μετά την έγκριση',%s)$$, :'lv', pg_temp.ver(:'lv')), 'εγκεκριμένη άδεια: μόνο με τη ροή νέας έγκρισης');

-- ═══════ 10β. Έγκριση με άλλες ημερομηνίες (λιγότερες ημέρες) — η αιτιολογία είναι προαιρετική ═══════
select pg_temp.leave('R2','leave','annual','2026-12-07','2026-12-11','5') as lv2 \gset
select pg_temp.as_user('owner@x.gr');
select req_decide(:'lv2', 'approve', '{"message":"Εγκρίνεται με άλλες ημερομηνίες.","approved_start":"2026-12-09","approved_end":"2026-12-10"}', pg_temp.ver(:'lv2'));
select pg_temp.eq((select count(*) from leave_days where request_id = :'lv2' and status = 'active'), 2::bigint, 'κρατήθηκαν μόνο οι 2 εγκεκριμένες ημέρες');
select pg_temp.eq((select requested_start||'|'||approved_start||'|'||approved_end from hr_decisions where request_id = :'lv2' and superseded_at is null), '2026-12-07|2026-12-09|2026-12-10', 'αρχικές και τελικές ημερομηνίες χωριστά');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
