\set ON_ERROR_STOP 1
-- Αιτήματα & Αναφορές: ρόλοι, κατάστημα, ροές έγκρισης, αναθεώρηση, ταυτόχρονες αποφάσεις,
-- απομονωμένη φόρμα εργαζομένου, πρότυπα, μετακίνηση καταστήματος. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','Γενική Διευθύντρια','owner',null),('hr@x.gr','HR Χρήστης','hr',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),
 ('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into trainer_scopes(email, store, specialty) values ('trainer@x.gr','Γλυφάδα','Ρεσεψιόν');
insert into employees(code,first,last,store,company,specialty) values
 ('E1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('E2','Μαρία','Βλάχου','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη'),
 ('E3','Γιώργος','Γεωργίου','Κηφισιά','ARG BEST GREEK GYMS IKE','Exclusive');
insert into employees(code,first,last,store,company,status) values ('E4','Άννα','Δήμου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ανενεργός');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.as_anon() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', '{}', false); execute 'set role anon'; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.req(p_ref_like text) returns uuid language sql as $$ select id from hr_requests where employee_name like p_ref_like order by created_at desc limit 1 $$;
create or replace function pg_temp.ver(p uuid) returns int language sql as $$ select version from hr_requests where id = p $$;

-- ───────── Α. Άδεια, καταγραφή από manager ─────────
select pg_temp.as_user('glyfada@x.gr');
select req_create('{"category":"leave","employee_code":"E1","entry_mode":"manager_record","leave_type":"annual","start_date":"2026-12-01","end_date":"2026-12-05","days_requested":"7","body":"Παρακαλώ να εγκρίνετε τη χορήγηση κανονικής άδειας…","manager_note":"Καλύπτει η Μαρία"}') ->> 'id' as leave1 \gset
select pg_temp.expect_fail($$select req_create('{"category":"leave","employee_code":"E3","entry_mode":"manager_record"}')$$, 'manager: εργαζόμενος άλλου καταστήματος');
select pg_temp.expect_fail($$select req_create('{"category":"leave","employee_code":"E1"}')$$, 'χωρίς τρόπο καταχώρισης');
select pg_temp.expect_fail($$select req_create('{"category":"nonsense","employee_code":"E1","entry_mode":"manager_record"}')$$, 'άγνωστη κατηγορία');
select pg_temp.expect_fail($$insert into hr_requests(ref,process,category,employee_code,employee_name,store,company,entry_mode,stated_by,created_by) values('X','employee','leave','E1','x','Γλυφάδα','c','manager_record','x','x')$$, 'απευθείας εγγραφή στον πίνακα');
select pg_temp.expect_fail(format('select req_submit(%L, 1)', :'leave1'), 'ημέρες άδειας > ημερολογιακές');
select req_update_draft(:'leave1', '{"days_requested":"4"}', 1);
select pg_temp.expect_fail(format('select req_submit(%L, 1)', :'leave1'), 'παλιά έκδοση (ταυτόχρονη αλλαγή)');
select req_submit(:'leave1', pg_temp.ver(:'leave1'));
select pg_temp.eq((select status from hr_requests where id = :'leave1'), 'submitted', 'άδεια υποβλήθηκε');
select pg_temp.eq((select stated_by||'|'||written_by||'|'||submitted_by from hr_requests where id = :'leave1'), 'employee:E1|glyfada@x.gr|glyfada@x.gr', 'καταγράφονται χωριστά: διατύπωσε / συμπλήρωσε / υπέβαλε');
select pg_temp.eq((select ref like 'ΑΙ-2026-%' from hr_requests where id = :'leave1'), true, 'μοναδικός αριθμός αιτήματος');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Εγκρίθηκε κανονικά."}',%s)$$, :'leave1', 3), 'manager δεν αποφασίζει');

select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from hr_requests), 0::bigint, 'manager Κηφισιάς δεν βλέπει αιτήματα Γλυφάδας');
select pg_temp.expect_fail(format('select req_assign(%L, null, 3)', :'leave1'), 'manager Κηφισιάς δεν χειρίζεται');

select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq((select count(*) from hr_requests), 0::bigint, 'εκπαιδευτής δεν βλέπει αιτήματα');
select pg_temp.eq((select count(*) from employees), 0::bigint, 'εκπαιδευτής δεν βλέπει μητρώο εργαζομένων');
select pg_temp.eq((select count(*) from declarations), 0::bigint, 'εκπαιδευτής δεν βλέπει μισθοδοσία');
select pg_temp.eq((select count(*) from trainer_employees()), 1::bigint, 'εκπαιδευτής βλέπει μόνο το πεδίο του (Γλυφάδα·Ρεσεψιόν)');
select pg_temp.expect_fail($$select req_create('{"category":"leave","employee_code":"E1","entry_mode":"manager_record"}')$$, 'εκπαιδευτής δεν δημιουργεί αιτήματα');
select pg_temp.expect_fail($$select prepare_declarations('2026-10','[{"code":"E1","amount":"1"}]')$$, 'εκπαιδευτής δεν προετοιμάζει δηλώσεις');

-- HR: απόρριψη με λόγο που εφαρμόζεται + αιτιολογία
select pg_temp.as_user('hr@x.gr');
select req_assign(:'leave1', null, pg_temp.ver(:'leave1'));
select pg_temp.eq((select status||'|'||assignee from hr_requests where id = :'leave1'), 'under_review|hr@x.gr', 'HR ανέλαβε (σε εξέταση, υπεύθυνος χειρισμού)');
select pg_temp.expect_fail(format($$select req_decide(%L,'reject','{"message":"Δεν εγκρίθηκε το αίτημα.","reason_code":"ops_needs","reason_text":"λίγο"}',%s)$$, :'leave1', pg_temp.ver(:'leave1')), 'απόρριψη χωρίς συγκεκριμένη αιτιολογία');
select pg_temp.expect_fail(format($$select req_decide(%L,'reject','{"message":"Δεν εγκρίθηκε το αίτημα.","reason_text":"Πλήρης στελέχωση τον Δεκέμβριο"}',%s)$$, :'leave1', pg_temp.ver(:'leave1')), 'απόρριψη χωρίς λόγο');
select req_decide(:'leave1','reject','{"message":"Το αίτημά σας δεν εγκρίθηκε για το συγκεκριμένο διάστημα.","reason_code":"ops_needs","reason_text":"Πλήρης στελέχωση λόγω εορτών"}', pg_temp.ver(:'leave1'));
select pg_temp.eq((select alternative from hr_decisions where request_id = :'leave1'), 'Προς συνεννόηση', 'εναλλακτικό διάστημα: «Προς συνεννόηση» αν δεν δοθεί');
-- HR δεν αναθεωρεί
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Εγκρίθηκε μετά από επανεξέταση."}',%s)$$, :'leave1', pg_temp.ver(:'leave1')), 'HR δεν αναθεωρεί απόφαση');

-- Η ΓΔ αναθεωρεί: η προηγούμενη απόφαση μένει στο ιστορικό
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Εγκρίθηκε."}',%s)$$, :'leave1', pg_temp.ver(:'leave1') - 1), 'ταυτόχρονη αντικρουόμενη απόφαση (παλιά έκδοση)');
select req_decide(:'leave1','approve','{"message":"Το αίτημά σας για κανονική άδεια εγκρίθηκε από 01/12/2026 έως και 03/12/2026, συνολικά 3 ημέρες.","approved_start":"2026-12-01","approved_end":"2026-12-03","approved_days":"3"}', pg_temp.ver(:'leave1'));
select pg_temp.eq((select count(*) from hr_decisions where request_id = :'leave1'), 2::bigint, 'αναθεώρηση: και οι δύο αποφάσεις στο ιστορικό');
select pg_temp.eq((select outcome||'|'||is_revision||'|'||approved_days from hr_decisions where request_id = :'leave1' and superseded_at is null), 'approve|true|3.0', 'ισχύουσα απόφαση: έγκριση 3 ημερών (αναθεώρηση)');
select pg_temp.eq((select outcome from hr_decisions where request_id = :'leave1' and superseded_at is not null), 'reject', 'η απόρριψη διατηρείται ως προηγούμενη απόφαση');
select pg_temp.expect_fail(format($$insert into hr_decisions(request_id,outcome,decided_by,decided_role,message) values(%L,'approve','x','owner','xxxxxxxxxxxx')$$, :'leave1'), 'απευθείας εγγραφή απόφασης');

-- Ενημέρωση εργαζομένου από manager, υλοποίηση από HR
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from hr_decisions where request_id = :'leave1'), 2::bigint, 'manager βλέπει τις αποφάσεις του καταστήματός του');
select pg_temp.expect_fail(format($$select req_complete(%L,'έγινε',%s)$$, :'leave1', pg_temp.ver(:'leave1')), 'manager δεν ολοκληρώνει');
select req_mark_notified(:'leave1', null, 'Ενημερώθηκε προφορικά', pg_temp.ver(:'leave1'));
select pg_temp.eq((select notified_by from hr_requests where id = :'leave1'), 'glyfada@x.gr', 'καταγράφεται πότε/ποιος ενημέρωσε τον εργαζόμενο');
select pg_temp.as_user('hr@x.gr');
select req_complete(:'leave1', 'Ενημερώθηκε το πρόγραμμα', pg_temp.ver(:'leave1'));
select pg_temp.eq((select status from hr_requests where id = :'leave1'), 'completed', 'έγκριση ≠ υλοποίηση: ολοκληρώθηκε χωριστά');
select pg_temp.expect_fail(format($$select req_decide(%L,'reject','{"message":"xxxxxxxxxxxxxx","reason_code":"other","reason_text":"xxxxxxxxxxxxx"}',%s)$$, :'leave1', pg_temp.ver(:'leave1')), 'ολοκληρωμένο δεν ξαναποφασίζεται');

-- Λόγοι απόρριψης ανά είδος άδειας / διευκρινίσεις αντί για αυτόματη απόρριψη
select pg_temp.as_user('glyfada@x.gr');
select req_create('{"category":"leave","employee_code":"E2","entry_mode":"manager_record","leave_type":"sick","start_date":"2026-11-02","end_date":"2026-11-03","days_requested":"2","body":"Παρακαλώ να εγκρίνετε άδεια ασθενείας."}') ->> 'id' as sick \gset
select req_submit(:'sick', 1);
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail(format($$select req_decide(%L,'reject','{"message":"Δεν εγκρίθηκε το αίτημα.","reason_code":"ops_needs","reason_text":"Πολύ φόρτο εργασίας"}',%s)$$, :'sick', pg_temp.ver(:'sick')), 'άδεια ασθενείας: δεν απορρίπτεται για επιχειρησιακές ανάγκες');
select req_decide(:'sick','needs_info','{"message":"Απαιτούνται τα παρακάτω στοιχεία: βεβαίωση ιατρού.","info":"βεβαίωση ιατρού"}', pg_temp.ver(:'sick'));
select pg_temp.eq((select status from hr_requests where id = :'sick'), 'needs_info', 'έλλειψη δικαιολογητικών → εκκρεμότητα, όχι απόρριψη');
select pg_temp.as_user('glyfada@x.gr');
select req_attach(:'sick', 'βεβαίωση.pdf', 'application/pdf', encode('%PDF-1.4 test'::bytea, 'base64'));
select pg_temp.expect_fail(format($$select req_attach(%L, 'x.exe', 'application/x-msdownload', 'QUJD')$$, :'sick'), 'μη επιτρεπτός τύπος συνημμένου');
select req_provide_info(:'sick', 'Επισυνάφθηκε η βεβαίωση', pg_temp.ver(:'sick'));
select pg_temp.eq((select status from hr_requests where id = :'sick'), 'under_review', 'μετά τις διευκρινίσεις επιστρέφει σε εξέταση στον ίδιο υπεύθυνο');
-- Η ΓΔ αποφασίζει χωρίς να περιμένει το HR
select pg_temp.as_user('owner@x.gr');
select req_decide(:'sick','approve','{"message":"Το αίτημά σας για άδεια ασθενείας εγκρίθηκε."}', pg_temp.ver(:'sick'));
select pg_temp.eq((select status from hr_requests where id = :'sick'), 'approved', 'ΓΔ εγκρίνει άδεια απευθείας (χωρίς προηγούμενη ενέργεια HR)');

-- ───────── Αύξηση: τελική έγκριση μόνο από ΓΔ, καμία αυτόματη μεταβολή ─────────
select pg_temp.as_user('glyfada@x.gr');
select req_create('{"category":"raise","employee_code":"E2","entry_mode":"manager_record","body":"Ο εργαζόμενος ζητά αύξηση αποδοχών λόγω νέων καθηκόντων."}') ->> 'id' as raise \gset
select req_submit(:'raise', 1);
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Εγκρίθηκε η αύξηση."}',%s)$$, :'raise', pg_temp.ver(:'raise')), 'HR δεν εγκρίνει αύξηση');
select req_forward_gm(:'raise', 'Προτείνεται αύξηση από 1/1', pg_temp.ver(:'raise'));
select pg_temp.eq((select status from hr_requests where id = :'raise'), 'awaiting_gm', 'αύξηση: αναμονή έγκρισης ΓΔ');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from hr_request_internal), 0::bigint, 'manager δεν βλέπει την εσωτερική εισήγηση HR');
select pg_temp.eq((select count(*) from hr_request_events where request_id = :'raise' and internal), 0::bigint, 'manager δεν βλέπει εσωτερικά γεγονότα');
select pg_temp.as_user('owner@x.gr');
create temp table emp_before as select * from employees;
select req_decide(:'raise','approve','{"message":"Το αίτημά σας (Αύξηση αποδοχών) εγκρίθηκε."}', pg_temp.ver(:'raise'));
select pg_temp.eq((select count(*) from employees e join emp_before b using (code) where row(e.*)::text = row(b.*)::text), 4::bigint, 'έγκριση αύξησης δεν αλλάζει αυτόματα κανένα στοιχείο');
select pg_temp.eq((select count(*) from declarations), 0::bigint, 'έγκριση αύξησης δεν δημιουργεί οικονομική μεταβολή');

-- ───────── Β. Αίτημα έγγραφης προειδοποίησης: manager → HR προσχέδιο → ΓΔ → κοινοποίηση HR ─────────
select pg_temp.as_user('glyfada@x.gr');
select req_create('{"category":"warning_request","employee_code":"E2","incident_date":"2026-10-28","details":{"description":"Τρίτη καθυστέρηση προσέλευσης μέσα στον μήνα.","examples":"20/10, 24/10, 28/10","prior_discussion":"Ναι, 21/10","proposed_action":"Έγγραφη προειδοποίηση"}}') ->> 'id' as warn \gset
select pg_temp.eq((select process||'|'||stated_by from hr_requests where id = :'warn'), 'manager|glyfada@x.gr', 'αναφορά manager: καταγράφεται ως διαδικασία Β');
select req_submit(:'warn', 1);
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Προειδοποίηση εγκρίνεται τώρα."}',%s)$$, :'warn', pg_temp.ver(:'warn')), 'ΓΔ δεν εγκρίνει χωρίς προσχέδιο HR');
select pg_temp.as_user('hr@x.gr');
select req_warning_draft(:'warn', 'Προς: Μαρία Βλάχου — Έγγραφη προειδοποίηση για επαναλαμβανόμενες καθυστερήσεις.', true, pg_temp.ver(:'warn'));
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Εγκρίνεται η προειδοποίηση."}',%s)$$, :'warn', pg_temp.ver(:'warn')), 'HR δεν εκδίδει προειδοποίηση');
select pg_temp.expect_fail(format($$select req_complete(%L,'Παραδόθηκε',%s)$$, :'warn', pg_temp.ver(:'warn')), 'καμία κοινοποίηση πριν από έγκριση ΓΔ');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from hr_decisions where request_id = :'warn'), 0::bigint, 'η αναφορά του manager δεν είναι εγκεκριμένη προειδοποίηση');
select pg_temp.expect_fail(format($$select req_mark_notified(%L,null,'x',%s)$$, :'warn', pg_temp.ver(:'warn')), 'manager δεν κοινοποιεί προειδοποίηση');
select pg_temp.as_user('owner@x.gr');
select req_decide(:'warn','approve','{}', pg_temp.ver(:'warn'));
select pg_temp.eq((select message from hr_decisions where request_id = :'warn' and superseded_at is null), 'Προς: Μαρία Βλάχου — Έγγραφη προειδοποίηση για επαναλαμβανόμενες καθυστερήσεις.', 'τελικό κείμενο προειδοποίησης αποθηκεύεται');
select pg_temp.as_user('hr@x.gr');
select req_complete(:'warn', 'Παραδόθηκε ιδιοχείρως', pg_temp.ver(:'warn'));
select pg_temp.eq((select status||'|'||(notified_at is not null) from hr_requests where id = :'warn'), 'completed|true', 'κοινοποίηση από HR μετά την έγκριση ΓΔ');

-- Αρνητική αξιολόγηση ≠ προειδοποίηση: δεν εγκρίνεται, εξετάζεται
select pg_temp.as_user('glyfada@x.gr');
select req_create('{"category":"negative_review","employee_code":"E1","incident_date":"2026-10-30","details":{"description":"Χαμηλή εξυπηρέτηση πελατών στη ρεσεψιόν.","examples":"Παράπονα 2 μελών","prior_discussion":"Όχι","proposed_action":"Επανεκπαίδευση"}}') ->> 'id' as neg \gset
select req_create('{"category":"incident","employee_code":"E1","details":{"description":"Περιστατικό χωρίς παραδείγματα"}}') ->> 'id' as inc \gset
select pg_temp.expect_fail(format('select req_submit(%L, 1)', :'inc'), 'ελλιπής αναφορά (λείπουν ημερομηνία/παραδείγματα)');
select req_submit(:'neg', 1);
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Εγκρίνεται η αναφορά."}',%s)$$, :'neg', pg_temp.ver(:'neg')), 'αρνητική αξιολόγηση δεν «εγκρίνεται» ως προειδοποίηση');
select pg_temp.as_user('hr@x.gr');
select req_complete(:'neg', 'Προγραμματίστηκε επανεκπαίδευση', pg_temp.ver(:'neg'));
select pg_temp.eq((select category||'|'||status from hr_requests where id = :'neg'), 'negative_review|completed', 'αρνητική αξιολόγηση: χωριστή κατηγορία, ολοκληρώθηκε');

-- ───────── Α. Συμπλήρωση από εργαζόμενο (απομονωμένη φόρμα) ─────────
select pg_temp.as_user('glyfada@x.gr');
select req_create('{"category":"leave","employee_code":"E1","entry_mode":"employee_fill"}') ->> 'id' as fill \gset
select req_update_draft(:'fill', '{"body":"Ο manager γράφει αντί του εργαζομένου","manager_note":"Κάλυψη από Ε2"}', 1);
select pg_temp.eq((select coalesce(body,'-')||'|'||manager_note from hr_requests where id = :'fill'), '-|Κάλυψη από Ε2', 'ο manager δεν γράφει το κείμενο του εργαζομένου· μόνο τη δική του εισήγηση');
select pg_temp.expect_fail(format('select req_submit(%L, %s)', :'fill', pg_temp.ver(:'fill')), 'υποβολή πριν συμπληρώσει ο εργαζόμενος');
select fill_start_request(:'fill') as f \gset
select (:'f'::jsonb)->>'token' as tok \gset
select pg_temp.expect_fail(format('select req_submit(%L, %s)', :'fill', pg_temp.ver(:'fill')), 'υποβολή ενώ η φόρμα είναι ανοιχτή');
-- Η συσκευή έχει πλέον ΜΟΝΟ το κλειδί (ανώνυμη σύνδεση)
select pg_temp.as_anon();
select pg_temp.expect_fail($$select count(*) from hr_requests$$, 'φόρμα εργαζομένου: καμία πρόσβαση σε πίνακες αιτημάτων');
select pg_temp.expect_fail($$select count(*) from employees$$, 'φόρμα εργαζομένου: καμία πρόσβαση στο μητρώο');
select pg_temp.expect_fail($$select count(*) from declarations$$, 'φόρμα εργαζομένου: καμία πρόσβαση στη μισθοδοσία');
select pg_temp.expect_fail($$select whoami()$$, 'φόρμα εργαζομένου: καμία άλλη λειτουργία');
select pg_temp.expect_fail(format($$select req_submit(%L, 1)$$, :'fill'), 'φόρμα εργαζομένου: δεν υποβάλλει η ίδια');
select pg_temp.expect_fail($$select fill_get('λάθος-κλειδί')$$, 'λάθος κλειδί');
select pg_temp.eq((select (fill_get(:'tok'))->'employee'->>'code'), 'E1', 'φόρμα εργαζομένου: βλέπει μόνο τον εαυτό του');
select pg_temp.eq((select (fill_get(:'tok'))::text like '%Κάλυψη από%'), false, 'φόρμα εργαζομένου: δεν βλέπει την εισήγηση του manager');
select fill_save_request(:'tok', '{"leave_type":"annual","start_date":"2026-12-20","end_date":"2026-12-24","days_requested":"3","body":"Παρακαλώ να εγκρίνετε τη χορήγηση κανονικής άδειας από 20/12 έως 24/12.","manager_note":"παραβίαση"}');
select fill_finish_request(:'tok');
select pg_temp.eq((select (fill_finish_request(:'tok'))->>'already'), 'true', 'διπλό πάτημα «Ολοκλήρωση»: καμία διπλή καταχώριση');
select pg_temp.expect_fail(format($$select fill_save_request(%L, '{"body":"αλλαγή μετά την ολοκλήρωση"}')$$, :'tok'), 'μετά την ολοκλήρωση η φόρμα κλειδώνει');
-- Επιστροφή του manager (νέα είσοδος), έλεγχος και υποβολή
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select manager_note from hr_requests where id = :'fill'), 'Κάλυψη από Ε2', 'ο εργαζόμενος δεν αλλάζει την εισήγηση του manager');
select req_submit(:'fill', pg_temp.ver(:'fill'));
select pg_temp.eq((select stated_by||'|'||written_by||'|'||submitted_by from hr_requests where id = :'fill'), 'employee:E1|employee:E1|glyfada@x.gr', 'φόρμα εργαζομένου: διατύπωσε & συμπλήρωσε ο εργαζόμενος, υπέβαλε ο manager');
select pg_temp.eq((select count(*) from hr_request_events where request_id = :'fill' and action = 'employee_completed' and actor = 'employee:E1'), 1::bigint, 'ιστορικό: ολοκλήρωση από τον εργαζόμενο');

-- ───────── Πρότυπα κειμένων με εκδόσεις ─────────
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select template_save('leave_approve','Νέο κείμενο έγκρισης')$$, 'HR δεν αλλάζει πρότυπα');
select pg_temp.as_user('owner@x.gr');
select template_save('leave_approve', 'ΝΕΟ: Το αίτημά σας για {είδος_άδειας} εγκρίθηκε ({ημέρες} ημέρες).');
select pg_temp.eq((select count(*) from text_template_versions where key = 'leave_approve'), 2::bigint, 'πρότυπο: κρατιούνται και οι δύο εκδόσεις');
select pg_temp.eq((select message like 'Το αίτημά σας για κανονική%' from hr_decisions where request_id = :'leave1' and superseded_at is null), true, 'πρότυπο: παλιά απόφαση δεν αλλοιώνεται αναδρομικά');
select pg_temp.expect_fail($$update text_template_versions set body = 'αλλοίωση' where key = 'leave_approve'$$, 'εκδόσεις προτύπων δεν τροποποιούνται');
select pg_temp.expect_fail($$update hr_request_events set note = 'αλλοίωση'$$, 'ιστορικό αιτημάτων δεν τροποποιείται');
select pg_temp.expect_fail(format($$select req_delete_draft(%L, %s)$$, :'leave1', pg_temp.ver(:'leave1')), 'υποβληθέν αίτημα δεν διαγράφεται');
update reject_reasons set label = 'Αυξημένες επιχειρησιακές ανάγκες (νέα διατύπωση)' where code = 'ops_needs';
select pg_temp.eq((select reason_label from hr_decisions where request_id = :'leave1' and outcome = 'reject'), 'Αυξημένες επιχειρησιακές ανάγκες της περιόδου', 'αλλαγή λόγου απόρριψης δεν αλλάζει παλιές αποφάσεις');
select pg_temp.eq((select count(*) from audit_log where entity = 'reject_reasons'), 1::bigint, 'αλλαγή λόγου απόρριψης στο ιστορικό ενεργειών');

-- ───────── Μετακίνηση καταστήματος: ίδιος κωδικός, ιστορικό ανέπαφο ─────────
select pg_temp.as_user('hr@x.gr');
update employees set store = 'Κηφισιά', specialty = 'Επίβλεψη' where code = 'E1';
select pg_temp.eq((select count(*) from employee_assignments where employee_code = 'E1'), 2::bigint, 'μετακίνηση: ιστορικό θέσεων (2 περίοδοι)');
select pg_temp.eq((select count(*) from employees where code = 'E1'), 1::bigint, 'μετακίνηση: μία καρτέλα, ίδιος κωδικός');
select pg_temp.eq((select count(*) from hr_requests where employee_code = 'E1' and store = 'Γλυφάδα'), 4::bigint, 'μετακίνηση: παλιά αιτήματα κρατούν το κατάστημα της περιόδου');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from hr_requests where employee_code = 'E1'), 4::bigint, 'ο manager της Γλυφάδας βλέπει τα αιτήματα της περιόδου του');
select pg_temp.expect_fail($$select req_create('{"category":"other_hr","employee_code":"E1","entry_mode":"manager_record","body":"Νέο αίτημα μετά τη μετακίνηση"}')$$, 'πρώην manager δεν δημιουργεί νέα αιτήματα');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from hr_requests where employee_code = 'E1'), 0::bigint, 'ο νέος manager δεν βλέπει αιτήματα άλλου καταστήματος');
select (req_create('{"category":"documents","employee_code":"E1","entry_mode":"manager_record","body":"Βεβαίωση προϋπηρεσίας για τράπεζα."}') ->> 'ref') is not null as ok \gset
select pg_temp.eq(:'ok'::text, 't'::text, 'ο νέος manager δημιουργεί αίτημα για τον μετακινημένο εργαζόμενο');
select pg_temp.eq((select store||'|'||specialty from hr_requests where employee_code = 'E1' and category = 'documents'), 'Κηφισιά|Επίβλεψη', 'νέο αίτημα: κατάστημα & ειδικότητα της νέας περιόδου');

-- Πρόχειρο: διαγραφή μόνο από όποιον το δημιούργησε
select req_create('{"category":"advance","employee_code":"E3","entry_mode":"manager_record"}') ->> 'id' as adv \gset
select pg_temp.as_user('owner@x.gr');
select req_delete_draft(:'adv', 1);
select pg_temp.eq((select count(*) from hr_requests where id = :'adv'), 0::bigint, 'πρόχειρο διαγράφεται');
select pg_temp.eq((select count(*) from audit_log where entity = 'hr_requests' and action = 'delete'), 1::bigint, 'η διαγραφή προχείρου καταγράφεται');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
