\set ON_ERROR_STOP 1
-- Έκδοση 3.1 · Παρακολούθηση βελτίωσης & συνεργασίας, πρότυπο/εκτύπωση εντύπου σταδίου 2. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('B1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-01-01'),
 ('B2','Μαρία','Βλάχου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-01-01');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.cv(p bigint) returns int language sql security definer as $$ select version from improvement_cases where id = p $$;

-- ═══════ Υποθέσεις ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select imp_create('{"employee_code":"B2","severity":"minor","incident_type":"Καθυστέρηση","description":"Καθυστερήσεις προσέλευσης","incident_date":"2026-11-10"}')$$, 'manager: όχι εργαζόμενος άλλου καταστήματος');
select pg_temp.expect_fail($$select imp_create('{"employee_code":"B1","severity":"x","incident_type":"Καθυστέρηση","description":"Καθυστερήσεις","incident_date":"2026-11-10"}')$$, 'βαρύτητα από τις τρεις επιλογές');
select (imp_create('{"employee_code":"B1","severity":"significant","incident_type":"Καθυστέρηση προσέλευσης","description":"Τρεις καθυστερήσεις άνω των 15 λεπτών τον Νοέμβριο.","incident_date":"2026-11-10","documentation":"Βιβλίο παρουσιών","actions":"Συζήτηση και σχέδιο δράσης"}'))->>'id' as c1 \gset
select pg_temp.eq((select stage || '|' || status || '|' || coalesce(next_review_due::text, 'χωρίς') from imp_list() where id = :c1), '1|open|χωρίς',
  'στάδιο 1· χωρίς αυτόματη προθεσμία μέχρι να οριστούν ημερολογιακές/εργάσιμες ημέρες');
select (imp_create('{"employee_code":"B1","severity":"minor","incident_type":"Στολή","description":"Χωρίς στολή εργασίας στη βάρδια.","incident_date":"2026-11-12","next_review_due":"2026-12-01"}'))->>'id' as c2 \gset
select pg_temp.eq((select count(*) from imp_list('B1')), 2::bigint, 'περισσότερες από μία ξεχωριστές υποθέσεις ανά εργαζόμενο');
select pg_temp.eq((select ref from imp_list() where id = :c1) like 'ΒΣ-2026-%', true, 'μοναδικός αριθμός υπόθεσης');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from imp_list()), 0::bigint, 'manager άλλου καταστήματος δεν βλέπει');
select pg_temp.expect_fail(format($$select imp_get(%s)$$, :c1), 'ούτε με απευθείας κλήση');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq((select count(*) from imp_list()), 0::bigint, 'ο εκπαιδευτής δεν βλέπει υποθέσεις');
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select count(*) from imp_list()), 0::bigint, 'ούτε το λογιστήριο');

-- ═══════ Ρύθμιση ημερών (ΓΔ) → προτεινόμενη προθεσμία ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select imp_set_day_mode('calendar')$$, 'μόνο η ΓΔ ορίζει τον τύπο ημερών');
select pg_temp.eq(imp_suggest_due(1, '2026-11-02'), null::date, 'χωρίς απόφαση: κανένας αυτόματος υπολογισμός');
select pg_temp.as_user('owner@x.gr');
select imp_set_day_mode('working');
select pg_temp.eq(imp_suggest_due(1, '2026-11-02') || '|' || imp_suggest_due(2, '2026-11-02'), '2026-11-23|2026-11-11', 'εργάσιμες: 15 και 7 εργάσιμες ημέρες');
select imp_set_day_mode('calendar');
select pg_temp.eq(imp_suggest_due(1, '2026-11-02') || '|' || imp_suggest_due(3, '2026-11-02'), '2026-11-17|2026-11-09', 'ημερολογιακές: 15 / 7');
select imp_set_day_mode(null);

-- ═══════ Επανεξέταση: εκβάσεις, αιτιολογία, ιστορικό, καμία αυτόματη ενέργεια ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select imp_review(%s, 'partial', 'λίγο', '2026-11-20', '2026-12-05', %s)$$, :c1, pg_temp.cv(:c1)), 'χωρίς αιτιολογία');
select pg_temp.expect_fail(format($$select imp_review(%s, 'partial', 'Μερική βελτίωση στην προσέλευση', '2026-11-20', null, %s)$$, :c1, pg_temp.cv(:c1)), 'μερική βελτίωση χωρίς νέα προθεσμία');
select imp_review(:c1, 'partial', 'Μερική βελτίωση στην προσέλευση', '2026-11-20', '2026-12-05', pg_temp.cv(:c1));
select pg_temp.eq((select stage || '|' || last_outcome || '|' || next_review_due from imp_list() where id = :c1), '1|partial|2026-12-05', 'συνέχιση παρακολούθησης με νέα προθεσμία');
select imp_review(:c1, 'noncompliant', 'Νέες καθυστερήσεις μετά τη συζήτηση', '2026-11-21', null, pg_temp.cv(:c1));
select pg_temp.eq((select stage || '|' || proposed_stage from imp_list() where id = :c1), '1|2', 'μη συμμόρφωση: εισήγηση επόμενου σταδίου (όχι αυτόματη μετάβαση)');
select pg_temp.expect_fail(format($$select imp_set_stage(%s, 3, 'Κατευθείαν έγγραφη', null, %s)$$, :c1, pg_temp.cv(:c1)), 'ένα στάδιο κάθε φορά');
select imp_set_stage(:c1, 2, 'Επίσημη προφορική επισήμανση μετά τη μη συμμόρφωση', '2026-12-01', pg_temp.cv(:c1));
select pg_temp.expect_fail(format($$select imp_set_stage(%s, 3, 'Έγγραφη προειδοποίηση', null, %s)$$, :c1, pg_temp.cv(:c1)), 'στάδιο 3 μόνο με αίτημα έγγραφης προειδοποίησης');
select imp_review(:c1, 'back', 'Βελτίωση — επιστροφή σε προφορική παρακολούθηση', '2026-11-21', '2026-12-10', pg_temp.cv(:c1));
select pg_temp.eq((select stage from imp_list() where id = :c1), 1::smallint, 'επιστροφή σε προηγούμενο στάδιο');
select imp_review(:c2, 'complied', 'Φοράει κανονικά τη στολή εργασίας', '2026-11-21', null, pg_temp.cv(:c2));
select pg_temp.eq((select status || '|' || last_outcome from imp_list() where id = :c2), 'closed|complied', 'συμμορφώθηκε: κλείσιμο, διατήρηση συνεργασίας');
select pg_temp.expect_fail(format($$select imp_review(%s, 'partial', 'Ξανά επανεξέταση', '2026-11-21', '2026-12-30', %s)$$, :c2, pg_temp.cv(:c2)), 'κλειστή υπόθεση');
reset role;
update improvement_cases set next_review_due = '2026-11-01' where id = :c1;
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select overdue || '|' || stage || '|' || status from imp_list() where id = :c1), 'true|1|open', 'παρέλευση προθεσμίας: μόνο επισήμανση καθυστέρησης, καμία αυτόματη ενέργεια');
select pg_temp.eq((select string_agg(action || coalesce(':' || outcome, ''), ',' order by at) from jsonb_to_recordset(imp_get(:c1)->'events') as x(action text, outcome text, at timestamptz)),
  'created,review:partial,review:noncompliant,stage_change,review:back', 'πλήρες ιστορικό με εκβάσεις');
select pg_temp.eq((select count(*) from jsonb_to_recordset(imp_get(:c1)->'events') as x(action_date date, due_date date) where action_date is not null and due_date is not null), 2::bigint,
  'πραγματικές ημερομηνίες χωριστά από προθεσμίες');

-- Έγγραφη προειδοποίηση: ροή Manager → HR → ΓΔ → HR· στάδιο 4 χωρίς αλλαγή κατάστασης εργαζομένου
select imp_set_stage(:c1, 2, 'Επίσημη προφορική επισήμανση', '2026-12-01', pg_temp.cv(:c1));
select (req_create('{"category":"warning_request","employee_code":"B1","incident_date":"2026-11-20","details":{"description":"Επανειλημμένες καθυστερήσεις","examples":"10/11, 14/11, 18/11","prior_discussion":"Ναι, 12/11","proposed_action":"Έγγραφη προειδοποίηση"}}'))->>'id' as wr \gset
select imp_link_warning(:c1, :'wr', pg_temp.cv(:c1));
select imp_set_stage(:c1, 3, 'Αίτημα έγγραφης προειδοποίησης προς HR', null, pg_temp.cv(:c1));
select pg_temp.eq((select category || '|' || status from hr_requests where id = :'wr'), 'warning_request|draft', 'η προειδοποίηση ακολουθεί την υπάρχουσα ροή αιτημάτων (όχι αυτόματη έκδοση)');
select pg_temp.expect_fail(format($$select imp_set_stage(%s, 4, 'Εξέταση λύσης', null, %s)$$, :c1, pg_temp.cv(:c1)), 'ο manager δεν ξεκινά εξέταση λύσης συνεργασίας');
select pg_temp.as_user('hr@x.gr');
select imp_set_stage(:c1, 4, 'Μη συμμόρφωση μετά την έγγραφη προειδοποίηση', null, pg_temp.cv(:c1));
select pg_temp.eq((select status || '|' || coalesce(leave_date::text, '-') from employees where code = 'B1'), 'Ενεργός|-', 'η εξέταση λύσης δεν κάνει τον εργαζόμενο αποχωρήσαντα');

-- ═══════ Συγκεντρωτικός πίνακας ΓΔ ═══════
select pg_temp.expect_fail($$select imp_summary()$$, 'το HR δεν έχει τον συγκεντρωτικό πίνακα ΓΔ');
select pg_temp.as_user('owner@x.gr');
select imp_summary() as s \gset
select pg_temp.eq((:'s'::jsonb->>'open') || '|' || (:'s'::jsonb->>'closed') || '|' || (:'s'::jsonb->'by_stage'->>'4') || '|' || (:'s'::jsonb->'by_outcome'->>'complied'), '1|1|1|1',
  'σύνολα ανά στάδιο και έκβαση');
select pg_temp.eq((select count(*) from jsonb_array_elements(:'s'::jsonb->'rows') x where x ? 'next_review_due' and x ? 'owner' and x ? 'last_action'), 2::bigint,
  'ανά εργαζόμενο: στάδιο, υπεύθυνος, τελευταία ενέργεια, επόμενη επανεξέταση');

-- ═══════ 19. Έντυπο σταδίου 2 ═══════
select (imp_create('{"employee_code":"B1","severity":"critical","incident_type":"Συμπεριφορά","description":"Ακατάλληλη συμπεριφορά προς μέλος.","incident_date":"2026-11-15"}'))->>'id' as c3 \gset
select imp_set_stage(:c3, 2, 'Επίσημη προφορική επισήμανση', '2026-12-01', pg_temp.cv(:c3));
select pg_temp.expect_fail(format($$select imp_issue_form(%s)$$, :c3), 'χωρίς πρότυπο: «Δεν έχει προστεθεί πρότυπο», η έκδοση μένει ανενεργή');
select pg_temp.eq(jsonb_array_length(form_template_info('improvement_stage2')->'versions'), 0, 'καμία έκδοση προτύπου ακόμη');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select form_template_upload('improvement_stage2', '{"name":"stage2.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}', 'κείμενο', '[]')$$, 'μόνο η ΓΔ ανεβάζει πρότυπο');
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail($$select form_template_upload('improvement_stage2', '{"name":"x.png","mime":"image/png","data":"iVBORw0KGgo="}', null, '[]')$$, 'το πρότυπο είναι PDF');
select form_template_upload('improvement_stage2', '{"name":"stage2_v1.pdf","mime":"application/pdf","data":"JVBERi0xLjQKJXYx"}', 'Συνοδευτικό κείμενο v1', '["ονοματεπώνυμο","κατάστημα"]');
select pg_temp.as_user('glyfada@x.gr');
select (imp_issue_form(:c3))->>'form_id' as f1 \gset
select pg_temp.as_user('owner@x.gr');
select form_template_upload('improvement_stage2', null, 'Συνοδευτικό κείμενο v2', '["ονοματεπώνυμο"]');
select pg_temp.eq(jsonb_array_length(form_template_info('improvement_stage2')->'versions'), 2, 'εκδόσεις προτύπου');
select pg_temp.as_user('glyfada@x.gr');
select imp_form_print(:f1) as p \gset
select pg_temp.eq((:'p'::jsonb->>'body') || '|' || (:'p'::jsonb->>'data') || '|' || (:'p'::jsonb->'values'->>'κατάστημα'), 'Συνοδευτικό κείμενο v1|JVBERi0xLjQKJXYx|Γλυφάδα',
  'αντίγραφο του εκδοθέντος εντύπου: η αλλαγή προτύπου δεν το αλλοιώνει');
select pg_temp.eq((select count(*) from jsonb_to_recordset(imp_get(:c3)->'events') as x(action text) where action in ('form_issued','form_printed')), 2::bigint, 'καταγράφονται έκδοση και εκτύπωση');
select pg_temp.eq((select (x->>'signed')::boolean from jsonb_array_elements(imp_get(:c3)->'forms') x), false, 'η εκτύπωση δεν θεωρείται παράδοση ή υπογραφή');
select imp_note(:c3, 'Υπογεγραμμένο έντυπο', '{"name":"υπογραφή.jpg","mime":"image/jpeg","data":"/9j/4AAQ"}', 'signed_uploaded', :f1);
select pg_temp.eq((select (x->>'signed')::boolean from jsonb_array_elements(imp_get(:c3)->'forms') x), true, 'επισύναψη υπογεγραμμένου εντύπου (σάρωση/φωτογραφία)');
-- το ειδικό δικαίωμα εκτύπωσης δεν δίνει άλλη πρόσβαση σε PDF
select pg_temp.eq(has_perm('improvement.stage_two_print') and not has_perm('payroll.pdf') and not has_perm('payroll.bulk') and not has_perm('payroll.backup'), true,
  'ο manager εκτυπώνει έντυπο σταδίου 2 χωρίς δικαιώματα PDF μισθοδοσίας / μαζικής λήψης / backup');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select imp_form_print(%s)$$, :f1), 'manager άλλου καταστήματος δεν εκτυπώνει');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
