\set ON_ERROR_STOP 1
-- Έκδοση 3.1 · Βάσεις άδειας στην επέτειο, αυτόματος κωδικός εργαζομένου, «Οι εργασίες μου» / όλες οι εργασίες (ΓΔ),
-- αναφορές ΓΔ/εκπαιδευτών προς κατάστημα. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),
 ('trainer@x.gr','Εκπαιδευτής','trainer',null),('trainer2@x.gr','Εκπαιδευτής 2','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('0098','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2026-11-15'),
 ('0120','Μαρία','Βλάχου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-03-16'),
 ('0007','Γιώργος','Γεωργίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',6,'2025-06-10');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.ver(p uuid) returns int language sql as $$ select version from hr_requests where id = p $$;

-- ═══════ 11. Αλλαγή βάσης άδειας στην επέτειο πρόσληψης ═══════
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((leave_apply_bases('0098')->>'added')::int, 3, 'εφαρμογή προτεινόμενων βάσεων: πρόσληψη, 1η και 2η επέτειος');
select pg_temp.eq((select string_agg(valid_from || ':' || annual_days, ' ' order by valid_from) from leave_entitlements where employee_code = '0098'),
  '2026-11-15:20.00 2027-11-15:21.00 2028-11-15:22.00', 'πρόσληψη 15/11/2026 → βάση 2ου έτους από 15/11/2027 (όχι από 1/1)');
select pg_temp.eq((leave_apply_bases('0098')->>'added')::int, 0, 'δεύτερη εκτέλεση: τίποτα διπλό');
select leave_breakdown('0098', 2027) as b \gset
select pg_temp.eq((select string_agg((x->>'from') || '–' || (x->>'to') || ':' || (x->>'annual_days'), ' ') from jsonb_array_elements(:'b'::jsonb->'periods') x),
  '2027-01-01–2027-11-14:20.00 2027-11-15–2027-12-31:21.00', '2027: δύο υποπερίοδοι με αλλαγή στην επέτειο');
select pg_temp.eq(round((:'b'::jsonb->>'accrued')::numeric, 2), round(leave_accrued('0098', 2027, '2027-12-31'), 2), 'άθροισμα υποπεριόδων = αναλογία έτους');
select pg_temp.eq(round((:'b'::jsonb->>'accrued')::numeric, 2), 20.13, 'με δεκαδικά: 20×(10+14/30)/12 + 21×(16/30+1)/12');
select pg_temp.eq(round((leave_breakdown('0098', 2026)->>'accrued')::numeric, 2), 2.56, '2026: από την πρόσληψη (16/30 του Νοεμβρίου + Δεκέμβριος)');
select pg_temp.eq(round((leave_breakdown('0098', 2027, '2027-06-30')->>'accrued')::numeric, 2), 10.00, 'πριν από την επέτειο ισχύει η παλιά βάση (καμία αναδρομική εφαρμογή)');
-- σύστημα εργασίας με την ίδια λογική (αλλαγή με ημερομηνία ισχύος → νέα βάση από εκείνη την ημέρα)
select pg_temp.as_user('acc@x.gr');
select emp_set_work_terms('0007', 5, null, '2027-03-01', 'Μετάβαση σε πενθήμερο');
select pg_temp.as_user('hr@x.gr');
select leave_apply_bases('0007');
select pg_temp.eq((select string_agg(valid_from || ':' || annual_days, ' ' order by valid_from) from leave_entitlements where employee_code = '0007'),
  '2025-06-10:24.00 2026-06-10:25.00 2027-03-01:21.00 2027-06-10:22.00', 'αλλαγή εξαήμερου → πενθήμερου: νέα βάση από την ημερομηνία ισχύος');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select leave_apply_bases('0098')$$, 'manager δεν αλλάζει βάσεις');

-- ═══════ 13. Αυτόματος κωδικός εργαζομένου ═══════
select pg_temp.as_user('hr@x.gr');
insert into employees(code,first,last,store,company,specialty,work_week) values ('AUTO','Άλκης','Βασιλείου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5);
select pg_temp.eq((select code from employees where last = 'Βασιλείου'), '0121', 'επόμενος αριθμός μετά τον μεγαλύτερο, ίδια μορφή (4 ψηφία)');
insert into employees(code,first,last,store,company,specialty,work_week) values ('','Βίκυ','Γαλάνη','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5);
select pg_temp.eq((select code from employees where last = 'Γαλάνη'), '0122', 'ενιαία αρίθμηση για όλα τα καταστήματα');
select pg_temp.eq((select count(*) from employees where code in ('0098','0120','0007')), 3::bigint, 'οι υπάρχοντες κωδικοί δεν αλλάζουν');
reset role;
delete from employees where code = '0122';
select pg_temp.as_user('hr@x.gr');
insert into employees(code,first,last,store,company,specialty,work_week) values ('AUTO','Γιάννα','Δούκα','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5);
select pg_temp.eq((select code from employees where last = 'Δούκα'), '0123', 'κανένας κωδικός δεν ξαναχρησιμοποιείται (ούτε μετά από διαγραφή)');
insert into employees(code,first,last,store,company,specialty,work_week) values ('X-500','Δέσποινα','Ευαγγέλου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5);
select pg_temp.eq((select count(*) from employees where code = 'X-500'), 1::bigint, 'χειροκίνητος κωδικός γίνεται δεκτός όπως πριν');
select emp_transfer('0123', 'Κηφισιά', (now() at time zone 'Europe/Athens')::date, 'Μεταφορά');
select pg_temp.eq((select count(*) from employees where code = '0123'), 1::bigint, 'ίδιος κωδικός μετά τη μεταφορά');
select pg_temp.expect_fail($$insert into employees(code,first,last,store,company,work_week) values ('0121','Α','Β','Γλυφάδα','BEST GREEK GYMS IKE',5)$$, 'διπλός κωδικός απορρίπτεται');

-- ═══════ 14. Εργασίες ═══════
select pg_temp.as_user('glyfada@x.gr');
select (req_create('{"category":"documents","employee_code":"0098","entry_mode":"manager_record","body":"Ο εργαζόμενος ζητά βεβαίωση εργασίας."}'))->>'id' as rq \gset
select req_submit(:'rq', 1);
select pg_temp.as_user('hr@x.gr');
select req_decide(:'rq', 'approve', '{"message":"Το αίτημα εγκρίθηκε· η βεβαίωση θα εκδοθεί."}', pg_temp.ver(:'rq'));
select req_task_add(:'rq', 'accounting', 'Έκδοση βεβαίωσης αποδοχών', ((now() at time zone 'Europe/Athens')::date + 3));
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select count(*) from tasks_all(true)), 1::bigint, '«Οι εργασίες μου»: η εργασία του λογιστηρίου φορτώνει');
select pg_temp.eq((select status || '|' || responsible || '|' || store || '|' || related_ref from tasks_all(true)), 'open|Λογιστήριο|Γλυφάδα|ΑΙ-2026-00001', 'στοιχεία εργασίας');
select pg_temp.expect_fail($$select * from tasks_all(false)$$, 'όχι συνολική προβολή εκτός ΓΔ');
select task_claim((select ref::bigint from tasks_all(true)));
select pg_temp.eq((select status || '|' || claimed_by from tasks_all(true)), 'in_progress|acc@x.gr', 'ανάληψη ενημερώνει λίστα/κατάσταση');
select task_note('request_task', (select ref from tasks_all(true)), 'Ζητήθηκαν στοιχεία από τη μισθοδοσία', null);
select task_note('request_task', (select ref from tasks_all(true)), '', '{"name":"σχέδιο.pdf","mime":"application/pdf","data":"JVBERi0xLjQ="}');
select pg_temp.eq((select notes || '|' || files from tasks_all(true)), '1|1', 'σχόλια και συνημμένα');
select pg_temp.expect_fail(format($$select task_note('request_task', %L, '', '{"name":"x.exe","mime":"application/x-msdownload","data":"QUJD"}')$$, (select ref from tasks_all(true))), 'μη επιτρεπτό αρχείο');
select req_task_done((select ref::bigint from tasks_all(true)), 'Εκδόθηκε');
select pg_temp.eq((select status from tasks_all(true)), 'done', 'ολοκλήρωση');
select pg_temp.eq((select string_agg(action, ',' order by at) from task_history('request_task', (select ref from tasks_all(true)))), 'created,claimed,comment,attachment,done', 'πλήρες ιστορικό');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select count(*) from tasks_all(true)), 0::bigint, 'HR: άδεια λίστα (όχι σφάλμα) όταν δεν υπάρχουν εργασίες του');
-- υλοποίηση από manager: η ενημέρωση του εργαζομένου προηγείται της ανάληψης
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select status_label from tasks_all(true) where kind = 'implementation'), 'Αναμονή ενημέρωσης εργαζομένου', 'manager: υλοποίηση σε αναμονή ενημέρωσης');
select pg_temp.expect_fail(format($$select req_impl_claim(%L, %s)$$, :'rq', pg_temp.ver(:'rq')), 'ανάληψη πριν την ενημέρωση εργαζομένου');
select req_mark_notified(:'rq', null, 'Ενημερώθηκε στο κατάστημα', pg_temp.ver(:'rq'));
select req_impl_claim(:'rq', pg_temp.ver(:'rq'));
select pg_temp.eq((select status from tasks_all(true) where kind = 'implementation'), 'in_progress', 'ανάληψη υλοποίησης');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from tasks_all(true)), 0::bigint, 'manager άλλου καταστήματος δεν βλέπει τις εργασίες');
-- ΓΔ: όλες οι εργασίες, χωρίς ανάληψη, με επισήμανση καθυστέρησης
select pg_temp.as_user('hr@x.gr');
select req_task_add(:'rq', 'hr', 'Αρχειοθέτηση αντιγράφου');
reset role;
update request_tasks set due_date = (now() at time zone 'Europe/Athens')::date - 2 where description = 'Αρχειοθέτηση αντιγράφου';
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from tasks_all(false)), 3::bigint, 'ΓΔ: όλες οι ανατεθειμένες εργασίες (όλοι οι χρήστες/καταστήματα)');
select pg_temp.eq((select overdue from tasks_all(false) where title = 'Αρχειοθέτηση αντιγράφου'), true, 'επισήμανση καθυστέρησης');
select pg_temp.eq((select claimed_by from tasks_all(false) where title = 'Αρχειοθέτηση αντιγράφου'), null, 'η ΓΔ παρακολουθεί χωρίς ανάληψη');

-- ═══════ 15. Αναφορές προς κατάστημα ═══════
select pg_temp.as_user('trainer@x.gr');
select (srep_create('{"store":"Γλυφάδα","subject":"Καθαριότητα αποδυτηρίων","description":"Στον έλεγχο της Τρίτης τα αποδυτήρια δεν ήταν καθαρά.","observations":"Επαναλαμβανόμενο","required_actions":"Πρόγραμμα καθαριότητας ανά δίωρο","action_required":true,"due_date":"2026-12-15","files":[{"name":"φωτο.jpg","mime":"image/jpeg","data":"/9j/4AAQ"}]}'))->>'id' as sr \gset
select pg_temp.expect_fail($$select srep_create('{"store":"Γλυφάδα","subject":"Θέμα","description":"Περιγραφή αναφοράς","action_required":true}')$$, 'ενέργεια χωρίς περιγραφή ενεργειών');
select pg_temp.expect_fail($$select srep_create('{"store":"Γλυφάδα","manager_email":"kifisia@x.gr","subject":"Θέμα","description":"Περιγραφή αναφοράς"}')$$, 'manager άλλου καταστήματος');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select srep_create('{"store":"Γλυφάδα","subject":"Θέμα","description":"Περιγραφή αναφοράς"}')$$, 'ο manager δεν υποβάλλει αναφορά προς κατάστημα');
select pg_temp.eq(notice_count(), 1, 'ο manager λαμβάνει ειδοποίηση');
select pg_temp.eq((select count(*) from tasks_all(true) where kind = 'store_report'), 1::bigint, 'και εργασία όταν απαιτείται ενέργεια');
select pg_temp.eq((srep_get(:'sr')->>'can_respond')::boolean, true, 'ανοίγει την αναφορά');
select pg_temp.eq(notice_count(), 0, 'η ανάγνωση καθαρίζει την ειδοποίηση');
select srep_act(:'sr', 'reply', 'Ξεκινάμε σήμερα το νέο πρόγραμμα.');
select srep_act(:'sr', 'claimed');
select pg_temp.expect_fail(format($$select srep_act(%s, 'completed', '')$$, :'sr'), 'ολοκλήρωση χωρίς σχόλιο');
select srep_act(:'sr', 'completed', 'Τοποθετήθηκε πρόγραμμα καθαριότητας', '{"name":"πρόγραμμα.pdf","mime":"application/pdf","data":"JVBERi0xLjQ="}');
select pg_temp.eq((select status from tasks_all(true) where kind = 'store_report'), 'done', 'η εργασία ολοκληρώθηκε');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from srep_list()), 0::bigint, 'manager άλλου καταστήματος δεν βλέπει την αναφορά');
select pg_temp.expect_fail(format($$select srep_get(%s)$$, :'sr'), 'ούτε με απευθείας κλήση');
select pg_temp.as_user('trainer2@x.gr');
select pg_temp.eq((select count(*) from srep_list()), 0::bigint, 'άλλος εκπαιδευτής δεν βλέπει τις αναφορές του πρώτου');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq(notice_count(), 3, 'ο εκπαιδευτής ενημερώνεται για απάντηση, ανάληψη, ολοκλήρωση');
select pg_temp.eq((select string_agg(action, ',' order by at) from jsonb_to_recordset(srep_get(:'sr')->'events') as x(action text, at timestamptz)),
  'submitted,attachment,read,reply,claimed,completed', 'καταγράφονται υποβολή, ανάγνωση, απαντήσεις, ενέργειες');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from srep_list()), 1::bigint, 'η ΓΔ βλέπει όλες τις αναφορές');
select (srep_create('{"store":"Κηφισιά","subject":"Ενημέρωση για νέο πρόγραμμα","description":"Από 1/12 αλλάζει το ωράριο ομαδικών."}'))->>'id' as sr2 \gset
select pg_temp.eq((select count(*) from tasks_all(false) where kind = 'store_report'), 1::bigint, 'χωρίς απαιτούμενη ενέργεια: μόνο ειδοποίηση, όχι εργασία');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
