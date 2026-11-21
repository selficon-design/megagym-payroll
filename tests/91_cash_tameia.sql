\set ON_ERROR_STOP 1
-- Ταμεία · Κλείσιμο ταμείου: σύνδεσμος ρεσεψιόν, υπολογισμοί, ροή manager → λογιστήριο, επιστροφές, διορθώσεις, δικαιώματα.
-- ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ Δοκιμή','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστής Δοκιμή','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('R1','Άννα','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2025-01-01'),
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

create or replace function pg_temp.ver(p bigint) returns int language sql security definer as $$ select version from public.cash_days where id = p $$;

-- ═══════ Δικαιώματα: αρχικές ρυθμίσεις ═══════
select pg_temp.eq((select string_agg(role, ',' order by role) from role_permissions where perm = 'cash.refund_approve' and allowed), 'owner', 'έγκριση επιστροφών αρχικά μόνο η ΓΔ');
select pg_temp.eq((select string_agg(role, ',' order by role) from role_permissions where perm = 'cash.view' and allowed), 'accounting,manager,owner', 'προβολή: ΓΔ, λογιστήριο, manager');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*)::int from jsonb_array_elements(permissions_matrix()->'permissions') p where p->>'module' = 'Ταμεία'), 8, 'τα δικαιώματα Ταμείων εμφανίζονται στον ίδιο πίνακα ρόλων');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select cash_overview(current_date - 5, current_date)$$, 'HR χωρίς πρόσβαση στα ταμεία');

-- ═══════ Σύνδεσμος ρεσεψιόν ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select cashlink_create('Γλυφάδα')$$, 'ο manager δεν δημιουργεί σύνδεσμο');
select pg_temp.as_user('owner@x.gr');
select cashlink_create('Γλυφάδα')->>'token' as tok \gset
select cashlink_create('Κηφισιά')->>'token' as tokk \gset
reset role;
select pg_temp.eq((select count(*) from cash_links where token_hash = :'tok'), 0::bigint, 'αποθηκεύεται μόνο το hash');
select athens_today()::text as today \gset
select count(*) filter (where role = 'owner')::int as n_owner, count(*) filter (where role in ('owner','manager'))::int as n_om from app_users where active \gset
select (athens_today() - 1)::text as yday \gset

select pg_temp.as_anon();
select cashlink_info(:'tok') as info \gset
select pg_temp.eq((:'info'::jsonb->>'store') || '|' || (select string_agg(x->>'code', ',') from jsonb_array_elements(:'info'::jsonb->'employees') x), 'Γλυφάδα|R1', 'μόνο ρεσεψιόν του καταστήματος');
select pg_temp.eq(jsonb_array_length(:'info'::jsonb->'approvers'), :n_owner, 'εγκρίνοντες: μόνο όσοι έχουν το δικαίωμα (ΓΔ)');
select pg_temp.eq(:'info'::text like '%@%', false, 'ο σύνδεσμος δεν αποκαλύπτει email');
select (select x->>'id' from jsonb_array_elements(:'info'::jsonb->'approvers') x where x->>'name' = 'ΓΔ Δοκιμή') as appr \gset
select pg_temp.expect_fail($$select * from cash_days$$, 'ο σύνδεσμος δεν διαβάζει πίνακες');
select pg_temp.expect_fail($$select cash_overview(current_date, current_date)$$, 'ούτε τις λειτουργίες της εφαρμογής');
select pg_temp.expect_fail(format($$select cashlink_submit(%L, '{"date":"%s","shift":"supplement","employee_code":"R1","counted_cash":"10"}')$$, :'tok', :'today'), 'συμπληρωματικό πριν από το βραδινό');
select pg_temp.expect_fail(format($$select cashlink_submit(%L, '{"date":"%s","shift":"morning","employee_code":"S1","counted_cash":"10"}')$$, :'tok', :'today'), 'όχι εργαζόμενος άλλης ειδικότητας');
select pg_temp.expect_fail(format($$select cashlink_submit(%L, '{"date":"%s","shift":"morning","employee_code":"R1","counted_cash":"10"}')$$, :'tok', (current_date - 5)::text), 'μόνο σήμερα ή χθες');
-- Πρωινό: 100 έναρξη + 520 εισπράξεις, ένα Live Pay, ένα έξοδο με φωτογραφία
select cashlink_submit(:'tok', format('{"date":"%s","shift":"morning","employee_code":"R1","counted_cash":"620,00",
  "livepay":[{"customer":"Πελάτης Α","amount":"45"}],
  "expenses":[{"amount":"12,50","category":"Αναλώσιμα","description":"Χαρτί εκτυπωτή","file":{"name":"a.jpg","mime":"image/jpeg","data":"/9j/4AAQSkZJRg=="}}]}', :'today')::jsonb);
select pg_temp.expect_fail(format($$select cashlink_submit(%L, '{"date":"%s","shift":"morning","employee_code":"R1","counted_cash":"1"}')$$, :'tok', :'today'), 'δεύτερο πρωινό την ίδια ημέρα');
select pg_temp.expect_fail(format($$select cashlink_submit(%L, '{"date":"%s","shift":"evening","employee_code":"R1","counted_cash":"400","iris_total":"30","expenses":[{"amount":"5","category":"Διάφορα","description":"χωρίς"}]}')$$, :'tok', :'today'), 'βραδινό χωρίς πακέτο POS');
-- Βραδινό: 100 έναρξη + 380 εισπράξεις, POS, IRIS, επιστροφή μετρητών 20 €
select cashlink_submit(:'tok', format('{"date":"%s","shift":"evening","employee_code":"R1","counted_cash":"480","pos_cards":"1.250,40","iris_total":"60",
  "refunds":[{"amount":"20","method":"cash","customer":"Πελάτης Β","reason":"Διπλή χρέωση","approver":"%s"}]}', :'today', :'appr')::jsonb);
-- Συμπληρωματικό: 15 € μετρητά μετά το κλείσιμο
select cashlink_submit(:'tok', format('{"date":"%s","shift":"supplement","employee_code":"R1","counted_cash":"15"}', :'today')::jsonb);
select pg_temp.expect_fail(format($$select cashlink_submit(%L, '{"date":"%s","shift":"morning","employee_code":"R1","counted_cash":"1"}')$$, :'tokk', :'today'), 'ο σύνδεσμος Κηφισιάς δεν βλέπει εργαζόμενο Γλυφάδας');
reset role;
select id as did from cash_days where store = 'Γλυφάδα' and day = :'today'::date \gset

-- ═══════ Υπολογισμοί ═══════
select pg_temp.as_user('glyfada@x.gr');
select cash_day_get(:did) as d \gset
select pg_temp.eq((:'d'::jsonb->'sum'->>'cash_to_deposit')::numeric, 915.00, 'προς κατάθεση = (620−100)+(480−100)+15 = 915 (το ταμείο έναρξης μένει)');
select pg_temp.eq((:'d'::jsonb->'sum'->>'expected_cash'), null, 'χωρίς SoftOne δεν υπάρχει αναμενόμενο');
select cash_day_save(:did, (:'d'::jsonb->>'version')::int, '{"softone_cash":"930","softone_cards":"1250.40","softone_iris":"55"}');
select cash_day_get(:did) as d \gset
select pg_temp.eq((:'d'::jsonb->'sum'->>'expected_cash')::numeric, 897.50, 'αναμενόμενα = 930 − 12,50 έξοδα − 20 επιστροφή');
select pg_temp.eq((:'d'::jsonb->'sum'->>'diff_cash')::numeric, 17.50, 'διαφορά μετρητών +17,50');
select pg_temp.eq((:'d'::jsonb->'sum'->>'diff_cards')::numeric, 0.00, 'κάρτες: POS = SoftOne');
select pg_temp.eq((:'d'::jsonb->'sum'->>'diff_iris')::numeric, 5.00, 'IRIS +5 χωριστά');
select cash_item_add(:did, 'adjustment', '{"kind":"cash","amount":"15","reason":"Συμπληρωματικό που δεν πέρασε στο SoftOne"}');
select cash_item_add(:did, 'adjustment', '{"kind":"iris","amount":"5","reason":"IRIS καταχωρίστηκε την επόμενη"}');
select cash_day_get(:did) as d \gset
select pg_temp.eq((:'d'::jsonb->'sum'->>'unexplained_cash')::numeric, 2.50, 'ανεξήγητη διαφορά μετά τις προσαρμογές');
select pg_temp.expect_fail(format($$select cash_day_save(%s, 1, '{"softone_cash":"1"}')$$, :did), 'παλιά έκδοση: ταυτόχρονη αλλαγή');

-- ═══════ Πεδίο καταστημάτων ═══════
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select cash_day_get(%s)$$, :did), 'manager άλλου καταστήματος δεν βλέπει την ημέρα');
select pg_temp.eq(jsonb_array_length(cash_overview(current_date - 3, current_date)), 0, 'η επισκόπηση δείχνει μόνο το δικό του κατάστημα');

-- ═══════ Επιστροφές: έγκριση μόνο με το δικαίωμα ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select cash_confirm(%s, %s)$$, :did, :'d'::jsonb->>'version'), 'επιβεβαίωση με επιστροφή σε αναμονή');
reset role;
select (select id from cash_refunds limit 1) as rid, (select id from cash_livepay limit 1) as lpid \gset
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select cash_refund_decide(%s, true)$$, :rid), 'ο manager δεν εγκρίνει επιστροφές');
select pg_temp.expect_fail(format($$select cash_item_add(%s, 'refund', '{"amount":"5","method":"cash","customer":"Γ","reason":"Λάθος","approver":"glyfada@x.gr"}')$$, :did), 'εγκρίνων χωρίς δικαίωμα');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq(jsonb_array_length(cash_refunds_pending()), 1, 'η ΓΔ βλέπει τις επιστροφές σε αναμονή');
select cash_refund_decide(:rid, true, null);
reset role;
select pg_temp.eq((select status || '|' || decided_name from cash_refunds where id = :rid), 'approved|ΓΔ Δοκιμή', 'καταγράφεται ποιος ενέκρινε');
-- Η ΓΔ δίνει την έγκριση και στους managers από τον πίνακα ρόλων
select pg_temp.as_user('owner@x.gr');
select permissions_save('[{"role":"manager","perm":"cash.refund_approve","allowed":true}]', null, 'Οι managers εγκρίνουν επιστροφές');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq(jsonb_array_length(cash_lists()->'approvers'), :n_om, 'μετά την εκχώρηση οι managers εμφανίζονται ως εγκρίνοντες');
select pg_temp.eq((whoami()->'perms') ? 'cash.refund_approve', true, 'whoami: ο manager έχει πλέον το δικαίωμα');
select pg_temp.as_user('owner@x.gr');
select permissions_save('[{"role":"manager","perm":"cash.refund_approve","allowed":false}]', null, 'Επαναφορά');
select pg_temp.expect_fail($$select permissions_save('[{"role":"accounting","perm":"cash.correct_approve","allowed":true}]', null, 'δοκιμή')$$, 'η έγκριση διορθώσεων μένει μόνο στη ΓΔ');

-- ═══════ Ροή: manager → λογιστήριο → κλείδωμα ═══════
select pg_temp.as_user('acc@x.gr');
select pg_temp.expect_fail(format($$select cash_lock(%s, 1)$$, :did), 'κλείδωμα πριν από την επιβεβαίωση manager');
select pg_temp.as_user('glyfada@x.gr');
select cash_day_get(:did) as d \gset
select cash_confirm(:did, (:'d'::jsonb->>'version')::int);
select pg_temp.expect_fail(format($$select cash_item_add(%s, 'livepay', '{"customer":"Χ","amount":"1"}')$$, :did), 'μετά την επιβεβαίωση δεν αλλάζει');
select pg_temp.as_user('acc@x.gr');
select pg_temp.expect_fail(format($$select cash_unconfirm(%s, '')$$, :did), 'επιστροφή στον manager χωρίς σημείωση');
select cash_unconfirm(:did, 'Ελέγξτε το IRIS');
select pg_temp.as_user('glyfada@x.gr');
select cash_day_get(:did) as d \gset
select cash_confirm(:did, (:'d'::jsonb->>'version')::int);
select pg_temp.as_user('acc@x.gr');
select cash_day_get(:did) as d \gset
select pg_temp.eq((:'d'::jsonb->'can'->>'audit')::boolean, true, 'το λογιστήριο μπορεί να ελέγξει');
select cash_lock(:did, (:'d'::jsonb->>'version')::int);
reset role;
select pg_temp.eq((select status || '|' || audited_name || '|' || (audited_at is not null)::text from cash_days where id = :did), 'locked|Λογιστής Δοκιμή|true', 'κλείδωμα με όνομα, ημερομηνία και ώρα ελεγκτή');
select pg_temp.as_anon();
select pg_temp.expect_fail(format($$select cashlink_submit(%L, '{"date":"%s","shift":"supplement","employee_code":"R1","counted_cash":"1"}')$$, :'tok', :'today'), 'ο σύνδεσμος δεν προσθέτει σε ελεγμένη ημέρα');
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail(format($$select cash_day_save(%1$s, pg_temp.ver(%1$s), '{"softone_cash":"1"}')$$, :did), 'ούτε η ΓΔ αλλάζει κλειδωμένη ημέρα απευθείας');

-- Live Pay ↔ τράπεζα και κατάθεση μετά το κλείδωμα
select pg_temp.as_user('acc@x.gr');
select cash_livepay_match(:lpid, true, 'ΤΡ-001');
select pg_temp.as_user('glyfada@x.gr');
select cash_deposit_add(:did, format('{"date":"%s","amount":"915","file":{"name":"d.jpg","mime":"image/jpeg","data":"/9j/4AAQ"}}', :'today')::jsonb);
select cash_day_get(:did) as d \gset
select pg_temp.eq((:'d'::jsonb->'sum'->>'deposit_left')::numeric || '|' || (:'d'::jsonb->'sum'->>'livepay_matched'), '0.00|1', 'κατάθεση και αντιστοίχιση Live Pay');

-- ═══════ Διόρθωση κλειδωμένης ημέρας ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select cash_correction_request(%s, 'Λάθος ποσό SoftOne')$$, :did), 'ο manager δεν ζητά διόρθωση κλειδωμένης');
select pg_temp.as_user('acc@x.gr');
select cash_correction_request(:did, 'Λάθος ποσό SoftOne μετρητών');
reset role;
select id as cid from cash_corrections limit 1 \gset
select pg_temp.as_user('acc@x.gr');
select pg_temp.expect_fail(format($$select cash_day_save(%1$s, pg_temp.ver(%1$s), '{"softone_cash":"932.50"}')$$, :did), 'χωρίς έγκριση ΓΔ δεν διορθώνεται');
select pg_temp.expect_fail(format($$select cash_correction_decide(%s, true)$$, :cid), 'το λογιστήριο δεν εγκρίνει μόνο του');
select pg_temp.as_user('owner@x.gr');
select cash_correction_decide(:cid, true, null);
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select cash_day_save(%1$s, pg_temp.ver(%1$s), '{"softone_cash":"1"}')$$, :did), 'σε διόρθωση: μόνο το λογιστήριο');
select pg_temp.as_user('acc@x.gr');
select cash_day_get(:did) as d \gset
select cash_day_save(:did, (:'d'::jsonb->>'version')::int, '{"softone_cash":"932.50"}');
select cash_day_get(:did) as d \gset
select pg_temp.eq((:'d'::jsonb->'sum'->>'unexplained_cash')::numeric, 0.00, 'μετά τη διόρθωση: καμία ανεξήγητη διαφορά');
select cash_lock(:did, (:'d'::jsonb->>'version')::int);
reset role;
select pg_temp.eq((select status from cash_corrections), 'applied', 'η διόρθωση καταγράφεται ως εφαρμοσμένη');
select pg_temp.eq((select count(*) > 0 from audit_log where entity = 'cash_days' and details->'changes' ? 'softone_cash'), true, 'ιστορικό αλλαγών πεδίων στο audit_log');
select pg_temp.eq((select string_agg(action, ',' order by id) from cash_events where day_id = :did) like 'submit_morning,submit_evening,submit_supplement,refund_approved,confirm,returned,confirm,lock,%correction_requested,correction_approved,correction_applied', true, 'πλήρες χρονολόγιο ημέρας');

-- ═══════ Αρχεία: μόνο για όσους βλέπουν την ημέρα ═══════
reset role;
select file_id as fid from cash_expenses limit 1 \gset
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select cash_file_get(%L)$$, :'fid'), 'παραστατικό άλλου καταστήματος');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select * from cash_files$$, 'ο χρήστης δεν διαβάζει πίνακες άμεσα');
select pg_temp.eq(cash_file_get(:'fid')->>'mime', 'image/jpeg', 'ο manager του καταστήματος ανοίγει το παραστατικό');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.expect_fail(format($$select cash_file_get(%L)$$, :'fid'), 'εκπαιδευτής χωρίς πρόσβαση');
-- Έξοδο χωρίς παραστατικό: δεν καταχωρίζεται (νέα ανοιχτή ημέρα, χθες)
select pg_temp.as_user('glyfada@x.gr');
select (cash_day_open('Γλυφάδα', current_date - 1)->>'id')::bigint as d2 \gset
select pg_temp.expect_fail(format($$select cash_item_add(%s, 'expense', '{"amount":"5","category":"Διάφορα","description":"Χωρίς απόδειξη"}')$$, :d2), 'έξοδο χωρίς φωτογραφία παραστατικού');
select pg_temp.expect_fail(format($$select cash_item_add(%s, 'expense', '{"amount":"5","category":"Άγνωστη","description":"Κάτι","file":{"name":"a.jpg","mime":"image/jpeg","data":"/9j/"}}')$$, :d2), 'έξοδο με άγνωστη κατηγορία');
select pg_temp.expect_fail(format($$select cash_item_add(%s, 'expense', '{"amount":"5","category":"Διάφορα","description":"Κάτι","file":{"name":"a.exe","mime":"application/x-msdownload","data":"TVqQ"}}')$$, :d2), 'μόνο εικόνες ή PDF');
select pg_temp.as_user('owner@x.gr');
select cash_category_save(null, 'Γραφική ύλη', true, null);
select pg_temp.eq((cash_lists()->'categories') @> '[{"name":"Γραφική ύλη"}]', true, 'η ΓΔ προσθέτει κατηγορία εξόδων');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select cash_category_save(null, 'Άλλη', true, null)$$, 'ο manager δεν αλλάζει κατηγορίες');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
