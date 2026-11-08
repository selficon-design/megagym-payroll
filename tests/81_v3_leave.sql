\set ON_ERROR_STOP 1
-- Έκδοση 3 · Άδειες: στοιχεία εργαζομένου, παρελθοντικές άδειες, αναλογία μέρους μήνα & δεκαδικά, παλαιό υπόλοιπο
-- και κατανομή ανά έτος, καμία διπλή αφαίρεση (έγκριση/λήψη/αλλαγή/ακύρωση), υπέρβαση μόνο με ΓΔ, ολική/μερική
-- ακύρωση, διορθώσεις, εκκαθάριση χωρίς διπλή πληρωμή, αναρρωτικές χωρίς μπλοκάρισμα, ημερολόγιο.
-- ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),
 ('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('L1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-03-16'),
 ('L2','Μαρία','Βλάχου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2026-03-16'),
 ('L3','Γιώργος','Γεωργίου','Κηφισιά','ARG BEST GREEK GYMS IKE','Exclusive',5,'2023-01-09'),
 ('L4','Ελένη','Δημητρίου','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη',5,'2026-01-01');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.ver(p uuid) returns int language sql as $$ select version from hr_requests where id = p $$;
create or replace function pg_temp.bal(c text, d date, k text) returns text language sql as $$ select leave_balance_calc(c, d)->>k $$;
-- Νέα άδεια: δημιουργία από manager + υποβολή. Επιστρέφει id.
create or replace function pg_temp.leave(c text, t text, s date, e date, n text default '1') returns uuid language plpgsql as $$
declare v uuid;
begin
  v := (req_create(jsonb_build_object('category','leave','employee_code',c,'entry_mode','manager_record','leave_type',t,
        'start_date',s,'end_date',e,'days_requested',n,'body','Παρακαλώ να εγκρίνετε την άδεια του εργαζομένου.'))->>'id')::uuid;
  perform req_submit(v, 1);
  return v;
end $$;
create or replace function pg_temp.approve(v uuid, extra jsonb default '{}') returns jsonb language sql as $$
  select req_decide(v, 'approve', jsonb_build_object('message','Το αίτημα εγκρίθηκε σύμφωνα με τα στοιχεία.') || extra, (select version from hr_requests where id = v))
$$;

-- ═══════ 1. Στοιχεία εργαζομένου: πενθήμερο/εξαήμερο με ημερομηνία ισχύος και ιστορικό ═══════
select pg_temp.as_user('acc@x.gr');
select emp_set_work_terms('L3', 6, 48, '2026-06-01', 'Μετάβαση σε εξαήμερο');
select pg_temp.eq((select work_week from work_terms_on('L3','2026-05-30')), 5::smallint, 'σύστημα εργασίας πριν την ισχύ: πενθήμερο');
select pg_temp.eq((select work_week from work_terms_on('L3','2026-06-06')), 6::smallint, 'μετά την ισχύ: εξαήμερο');
select pg_temp.eq(leave_workday('L3','2026-05-30'), false, 'Σάββατο πριν: όχι εργάσιμη (πενθήμερο)');
select pg_temp.eq(leave_workday('L3','2026-06-06'), true, 'Σάββατο μετά: εργάσιμη (εξαήμερο) — όχι ίδια αντιμετώπιση για όλους');
select pg_temp.eq(leave_workday('L1','2026-06-06'), false, 'Σάββατο για άλλον εργαζόμενο πενθημέρου: όχι εργάσιμη');
select pg_temp.expect_fail($$select emp_set_work_terms('L3', 5, null, '2026-06-01', 'x')$$, 'ίδια ημερομηνία ισχύος δεν αντικαθίσταται σιωπηρά');
select pg_temp.eq((select count(*) from employee_lifecycle where employee_code = 'L3' and kind = 'work_terms'), 1::bigint, 'ιστορικό αλλαγής συστήματος εργασίας');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select emp_set_work_terms('L1', 6, null, '2026-07-01', 'x')$$, 'manager δεν αλλάζει στοιχεία εργαζομένου');
select pg_temp.expect_fail($$insert into employees(code,first,last,store,company,work_week) values ('NEW','Α','Β','Γλυφάδα','BEST GREEK GYMS IKE',5)$$, 'manager δεν καταχωρίζει εργαζόμενους');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$insert into employees(code,first,last,store,company) values ('NEW','Α','Β','Γλυφάδα','BEST GREEK GYMS IKE')$$, 'νέος εργαζόμενος χωρίς πενθήμερο/εξαήμερο');
insert into employees(code,first,last,store,company,work_week,email,phone,hire_date) values ('NEW','Άλκης','Βασιλείου','Γλυφάδα','BEST GREEK GYMS IKE',6,'alkis@x.gr','210 1234567','2026-10-01');
select pg_temp.eq((select work_week||'|'||valid_from from employee_work_terms where employee_code = 'NEW'), '6|2026-10-01', 'νέος εργαζόμενος: σύστημα εργασίας από την πρόσληψη');
select emp_set_dates('NEW', '2026-10-01', '2026-12-31', 'Λήξη σύμβασης');
select pg_temp.eq((select kind||'|'||effective_date from employee_lifecycle where employee_code = 'NEW' order by id desc limit 1), 'leave|2026-12-31', 'αποχώρηση = τελευταία ημέρα απασχόλησης, με ιστορικό');
select pg_temp.eq(emp_active_on('NEW','2026-12-31') and not emp_active_on('NEW','2027-01-01'), true, 'μετά την αποχώρηση δεν μετρά');
select pg_temp.eq((select count(*) from employees where code = 'NEW'), 1::bigint, 'η καρτέλα διατηρείται');

-- ═══════ 2. Ετήσιες βάσεις: πρόταση 20/21/22 και καταχώριση ═══════
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select string_agg((x->>'valid_from')||':'||(x->>'annual_days'), ' ' order by x->>'valid_from') from jsonb_array_elements(leave_suggest_bases('L1')->'rows') x),
  '2024-03-16:20 2025-03-16:21 2026-03-16:22', 'πρόταση βάσεων πενθημέρου 20/21/22 με τις σωστές ημερομηνίες');
select pg_temp.eq((select string_agg(x->>'annual_days', ' ' order by x->>'valid_from') from jsonb_array_elements(leave_suggest_bases('NEW')->'rows') x),
  '24 25 26', 'πρόταση βάσεων εξαημέρου 24/25/26');
select leave_set_base('L1', 20, '2024-03-16', 'Βάση πενθημέρου');
select leave_set_base('L2', 20, '2026-03-16', 'Βάση πενθημέρου');
select leave_set_base('L4', 22, '2026-01-01', 'Βάση πενθημέρου');
select pg_temp.expect_fail($$select leave_set_base('L1', 25, '2024-03-16', 'x')$$, 'ίδια ημερομηνία βάσης δεν αντικαθίσταται σιωπηρά');
select leave_set_base('L1', 21, '2024-03-16', 'Διόρθωση λάθους καταχώρισης', true);
select pg_temp.eq((select count(*)||'|'||count(*) filter (where superseded_at is null) from leave_entitlements where employee_code = 'L1'), '2|1', 'διόρθωση βάσης: η παλιά μένει στο ιστορικό');
select leave_set_base('L1', 20, '2024-03-16', 'Επαναφορά στη σωστή βάση', true);
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select leave_set_base('L1', 30, '2026-01-01', 'x')$$, 'manager δεν ορίζει βάσεις');

-- ═══════ 3. Αναλογία: μέρος μήνα από την πρόσληψη, δύο δεκαδικά, χωρίς στρογγυλοποίηση ═══════
-- L2: πρόσληψη 16/03/2026, βάση 20 → Μάρτιος 20/12 × 16/31 = 0,86 · έως 30/06 = 0,86 + 3 × 1,6667 = 5,86
select pg_temp.eq(pg_temp.bal('L2','2026-03-31','accrued'), '0.86', 'αναλογία μέρους μήνα από την πρόσληψη (16/31 του μήνα)');
select pg_temp.eq(pg_temp.bal('L2','2026-06-30','accrued'), '5.86', 'αναλογία έως επιλεγμένη ημερομηνία, χωρίς μηνιαία στρογγυλοποίηση');
select pg_temp.eq(pg_temp.bal('L2','2026-03-10','accrued'), '0.00', 'πριν από την πρόσληψη: καμία αναλογία');
-- L4: βάση 22 από 01/01/2026 → 2 μήνες = 3,67· 3 ημέρες άδειας → 0,67 (το κλάσμα μένει)
select pg_temp.eq(pg_temp.bal('L4','2026-02-28','accrued'), '3.67', 'αναλογία 3,67 ημερών');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L4','annual','2026-04-06','2026-04-08','3') as l4a \gset
select pg_temp.as_user('hr@x.gr');
select pg_temp.approve(:'l4a');
select pg_temp.eq(pg_temp.bal('L4','2026-02-28','balance'), '0.67', 'υπόλοιπο 3,67 − 3 = 0,67 (το κλάσμα συνεχίζει να συσσωρεύεται)');
select pg_temp.eq(pg_temp.bal('L4','2026-04-07','taken')||'|'||pg_temp.bal('L4','2026-04-07','future_approved'), '2.00|1.00', 'λήψη: από εγκεκριμένες μελλοντικές σε ληφθείσες χωρίς νέα κίνηση');
select pg_temp.eq((select count(*) from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = :'l4a'), 3::bigint, 'έγκριση = μία δέσμευση ανά ημέρα (καμία διπλή αφαίρεση στη λήψη)');
select pg_temp.eq((select approved_days from hr_decisions where request_id = :'l4a' and superseded_at is null), 3.0, 'εγκεκριμένες ημέρες = ημέρες χρέωσης από το σύστημα εργασίας');

-- ═══════ 4. Παρελθοντική άδεια με την κανονική διαδικασία + παλαιό υπόλοιπο στο 1ο τρίμηνο ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L1','annual','2026-02-02','2026-02-04','3') as past \gset
select pg_temp.as_user('hr@x.gr');
select pg_temp.approve(:'past');
select pg_temp.eq((select string_agg(distinct c.leave_year::text, ',') from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = :'past'), '2025',
  'άδεια στο 1ο τρίμηνο: χρεώνεται πρώτα το υπόλοιπο του προηγούμενου έτους');
select pg_temp.eq(pg_temp.bal('L1','2026-11-01','taken'), '0.00', 'το τρέχον έτος δεν χρεώθηκε');
select pg_temp.eq(pg_temp.bal('L1','2026-03-15','prev_state'), 'usable', 'παλαιό υπόλοιπο διαθέσιμο έως 31/03');
-- διόρθωση παλαιού υπολοίπου 2025 σε 1,5 (λογιστήριο) και άδεια 30/03–01/04: 1 + 0,5 από 2025, 0,5 + 1 από 2026
select pg_temp.as_user('acc@x.gr');
select leave_adjust('L1', 2025, 1.5, '2026-03-01', 'Συμφωνία με τη μισθοδοσία 2025');
select pg_temp.eq((select prev_value||'→'||new_value from leave_adjustments where employee_code = 'L1' order by id desc limit 1), '17.00→1.50', 'διόρθωση: προηγούμενη και νέα τιμή, συμφωνία με το ιστορικό κινήσεων');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L1','annual','2026-03-30','2026-04-01','3') as split \gset
select pg_temp.as_user('hr@x.gr');
select pg_temp.approve(:'split');
select pg_temp.eq((select string_agg(c.leave_year||':'||c.amount, ' ' order by d.day, c.leave_year) from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = :'split'),
  '2025:1.00 2025:0.50 2026:0.50 2026:1.00', 'κατανομή ανά έτος: πρώτα οι διαθέσιμες ημέρες προηγούμενου έτους που μπορούν να χρησιμοποιηθούν');
select pg_temp.eq(pg_temp.bal('L1','2026-04-15','prev_balance'), '0.00', 'το παλαιό υπόλοιπο εξαντλήθηκε');

-- ═══════ 5. Ολική / μερική ακύρωση και αλλαγή ημερομηνιών — χωρίς διπλή χρέωση ═══════
select pg_temp.as_user('hr@x.gr');
select leave_cancel(:'split', array['2026-03-31']::date[], 'Επέστρεψε νωρίτερα στην εργασία');
select pg_temp.eq((select charge_back::text from leave_cancellations where request_id = :'split'), '{"2025": 0.50, "2026": 0.50}', 'μερική ακύρωση: επιστρέφονται μόνο οι χρεωμένες ημέρες, στο σωστό έτος');
select pg_temp.eq((select count(*) from leave_days where request_id = :'split' and status = 'active'), 2::bigint, 'οι υπόλοιπες ημέρες μένουν');
select pg_temp.eq((select count(*) from leave_days where request_id = :'split'), 3::bigint, 'η ακυρωμένη ημέρα μένει στο ιστορικό');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail(format($$select leave_cancel(%L, null, 'Ακύρωση από manager')$$, :'split'), 'manager δεν εγκρίνει ακύρωση');
select pg_temp.eq((select count(*) from notifications where user_email = 'glyfada@x.gr' and kind = 'leave_cancelled'), 1::bigint, 'ο manager ενημερώνεται για την ακύρωση');
-- καλοκαιρινή άδεια 06–10/07 → αλλαγή σε 13–15/07 με νέα έγκριση· μέχρι τότε ισχύει η αρχική
select pg_temp.leave('L1','annual','2026-07-06','2026-07-10','5') as summer \gset
select pg_temp.as_user('hr@x.gr');
select pg_temp.approve(:'summer');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select pg_temp.leave('L1','annual','2026-07-09','2026-07-14','2')$$, 'διπλή εγγραφή για τις ίδιες ημερομηνίες');
select (req_create(jsonb_build_object('category','leave_change','employee_code','L1','entry_mode','manager_record','original_request_id',:'summer',
        'start_date','2026-07-13','end_date','2026-07-15','body','Ο εργαζόμενος ζητά μετάθεση της άδειας μία εβδομάδα αργότερα.')))->>'id' as chg \gset
select req_submit(:'chg', 1);
select pg_temp.eq((select count(*) from leave_days where request_id = :'summer' and status = 'active'), 5::bigint, 'μέχρι την έγκριση της αλλαγής ισχύει η αρχική άδεια');
select pg_temp.expect_fail(format($$select req_decide(%L,'approve','{"message":"Εγκρίθηκε η αλλαγή ημερομηνιών."}',%s)$$, :'chg', pg_temp.ver(:'chg')), 'manager δεν εγκρίνει την αλλαγή');
select pg_temp.as_user('hr@x.gr');
select (leave_charged('L1', 2026)) as before_chg \gset
select pg_temp.approve(:'chg');
select pg_temp.eq((select count(*) from leave_days where request_id = :'summer' and status = 'replaced'), 5::bigint, 'αλλαγή: οι αρχικές ημέρες αντικαθίστανται (μένουν στο ιστορικό)');
select pg_temp.eq(leave_charged('L1', 2026), :'before_chg'::numeric - 5 + 3, 'αλλαγή: ενιαία ενημέρωση ημερών/υπολοίπου χωρίς διπλή δέσμευση');
select leave_cancel(:'chg', null, 'Ακυρώθηκε η άδεια με αίτημα του εργαζομένου');
select pg_temp.eq(leave_charged('L1', 2026), :'before_chg'::numeric - 5, 'ολική ακύρωση: επιστροφή όλων των ημερών');
select pg_temp.expect_fail(format($$select leave_cancel(%L, null, 'ξανά ακύρωση')$$, :'chg'), 'δεύτερη ακύρωση της ίδιας άδειας');
-- αναθεώρηση έγκρισης από ΓΔ σε απόρριψη: αποδέσμευση ημερών
select pg_temp.as_user('owner@x.gr');
select req_decide(:'l4a','reject','{"message":"Μετά από επανεξέταση το αίτημα δεν εγκρίνεται.","reason_code":"coverage","reason_text":"Δεν καλύπτεται το πρόγραμμα του Απριλίου"}', pg_temp.ver(:'l4a'));
select pg_temp.eq(pg_temp.bal('L4','2026-04-30','taken'), '0.00', 'αναθεώρηση σε απόρριψη: οι ημέρες αποδεσμεύονται');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from notifications where request_id = :'l4a'), 2::bigint, 'κάθε απόφαση (και αναθεώρηση) = νέα ενημέρωση για τον manager');

-- ═══════ 6. Υπέρβαση αναλογικού υπολοίπου: υποβολή επιτρέπεται, έγκριση ΜΟΝΟ από ΓΔ ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L4','annual','2026-05-04','2026-05-29','20') as over \gset
select pg_temp.eq((select leave_requested||'|'||(leave_excess > 0) from hr_requests where id = :'over'), '20.00|true', 'η υποβολή με υπέρβαση επιτρέπεται και καταγράφεται');
select pg_temp.eq((leave_check(:'over')->>'excess')::numeric > 0 and (leave_check(:'over')->>'available') is not null, true, 'εμφανίζονται αιτούμενες, διαθέσιμες και ημέρες υπέρβασης');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail(format($$select pg_temp.approve(%L)$$, :'over'), 'HR δεν εγκρίνει υπέρβαση');
select req_forward_gm(:'over', 'Προτείνεται έγκριση λόγω οικογενειακού γεγονότος.', pg_temp.ver(:'over'));
select pg_temp.eq((select status from hr_requests where id = :'over'), 'awaiting_gm', 'HR προωθεί στη ΓΔ για ειδική έγκριση');
select pg_temp.as_user('owner@x.gr');
select pg_temp.expect_fail(format($$select pg_temp.approve(%L)$$, :'over'), 'η ΓΔ επιβεβαιώνει ρητά την ειδική έγκριση');
select pg_temp.approve(:'over', '{"overdraw_ok":true}');
select pg_temp.eq((select (overdraw_days > 0)::text from hr_decisions where request_id = :'over' and superseded_at is null), 'true', 'η απόφαση υπέρβασης μένει στο ιστορικό');
select pg_temp.eq((select count(*) from hr_request_events where request_id = :'over' and action = 'overdraw_approved'), 1::bigint, 'καταγραφή ειδικής έγκρισης');
select pg_temp.eq((pg_temp.bal('L4','2026-05-31','balance'))::numeric < 0, true, 'το αρνητικό υπόλοιπο διατηρείται (δεν μηδενίζεται)');
reset role; update role_permissions set allowed = true where role = 'hr' and perm = 'leave.overdraw';
select pg_temp.eq(role_has_perm('hr','leave.overdraw'), false, 'η ειδική έγκριση υπέρβασης δεν δίνεται σε άλλον ρόλο ούτε από τον πίνακα');

-- ═══════ 7. Διορθώσεις: μόνο ΓΔ/HR/λογιστήριο, με αιτιολογία ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select leave_adjust('L1', 2026, 5, '2026-11-01', 'Διόρθωση από manager')$$, 'manager δεν διορθώνει υπόλοιπα');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select leave_adjust('L1', 2026, 5, '2026-11-01', 'x')$$, 'διόρθωση χωρίς αιτιολογία');
select leave_adjust('L2', 2026, 10, '2026-11-01', 'Μεταφορά ημερών από προηγούμενο εργοδότη');
select pg_temp.eq(round(leave_year_balance('L2', 2026, '2026-11-01'), 2), 10.00, 'μετά τη διόρθωση το υπόλοιπο ισούται με τη νέα τιμή');
select pg_temp.expect_fail($$update leave_adjustments set reason = 'αλλαγή'$$, 'οι διορθώσεις δεν αντικαθιστούν σιωπηρά παλιές εγγραφές');

-- ═══════ 8. Εκκαθάριση μετά τις 31/03 — αποτροπή διπλής πληρωμής ═══════
-- L1 2024: πρόσληψη 16/03/2024 → 0,86 + 9 × 1,6667 = 15,86 μη ληφθείσες ημέρες
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select outstanding from leave_to_settle(2024) where employee_code = 'L1'), 15.86, '«Προς εκκαθάριση από το λογιστήριο» μαζί με τα δεκαδικά');
select pg_temp.expect_fail($$select leave_settle('L1', 2026, 1, 50, '2026-11-01', null, null)$$, 'πριν από την 31/03 του επόμενου έτους δεν εκκαθαρίζεται');
select leave_settle('L1', 2024, 10, 500, '2025-04-30', '{"name":"εντολή.pdf","mime":"application/pdf","data":"JVBERi0xLjQ="}', 'Μισθοδοσία Απριλίου');
select pg_temp.expect_fail($$select leave_settle('L1', 2024, 6, 300, '2025-05-31', null, null)$$, 'πληρωμή πέρα από το υπόλοιπο (διπλή πληρωμή)');
select leave_settle('L1', 2024, 5.86, 293, '2025-05-31', null, 'Υπόλοιπο με δεκαδικά');
select pg_temp.expect_fail($$select leave_settle('L1', 2024, 1, 50, '2025-06-30', null, null)$$, 'δεύτερη πληρωμή ήδη εκκαθαρισμένου έτους');
select pg_temp.eq((select count(*) from leave_to_settle(2024) where employee_code = 'L1'), 0::bigint, 'μετά την πληρωμή δεν εμφανίζεται ως εκκρεμότητα');
select pg_temp.eq((select doc_name from leave_settlements where employee_code = 'L1' and doc_name is not null), 'εντολή.pdf', 'παραστατικό αποθηκεύτηκε με χρήστη/ημερομηνία');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select leave_settle('L1', 2025, 1, 50, '2026-05-01', null, null)$$, 'HR δεν καταχωρίζει πληρωμή εκκαθάρισης');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from leave_settlements where employee_code = 'L1'), 2::bigint, 'η ΓΔ βλέπει τις πληρωμές');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select doc_data from leave_settlements$$, 'κανείς δεν διαβάζει απευθείας το παραστατικό');

-- ═══════ 9. Αναρρωτικές: καταχώριση χωρίς μπλοκάρισμα, ακριβές μήνυμα, χωριστά από την κανονική ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L2','sick','2026-03-18','2026-03-19','2') as s1 \gset
select pg_temp.leave('L2','sick','2026-05-04','2026-05-20','17') as s2 \gset
select pg_temp.eq(leave_check(:'s2')->'sick'->>'message', 'Έχει εξαντληθεί το όριο ημερών αναρρωτικής με κάλυψη αποδοχών από την εταιρεία για το τρέχον εργασιακό έτος.', 'ακριβές μήνυμα εξάντλησης πριν την έγκριση');
select pg_temp.as_user('hr@x.gr');
select (leave_charged('L2', 2026)) as l2_before \gset
select pg_temp.approve(:'s1');
select pg_temp.approve(:'s2');
select pg_temp.eq((select count(*) from leave_days where employee_code = 'L2' and leave_type = 'sick' and status = 'active'), 19::bigint, 'η αναρρωτική καταχωρίστηκε (η κάλυψη δεν είναι όριο απουσίας)');
select pg_temp.eq(leave_charged('L2', 2026), :'l2_before'::numeric, 'δεν αφαιρέθηκε από την κανονική άδεια');
select pg_temp.eq((sick_status('L2','2026-06-01')->>'ten_day_condition_unmet_days')::int, 2, 'προϋπόθεση 10 ημερών παροχής εργασίας για την κάλυψη');
select pg_temp.eq((sick_status('L2','2026-06-01')->>'cover_limit')::int || '|' || (sick_status('L2','2026-06-01')->>'exhausted'), '15|true', '1ο εργασιακό έτος: έως 15 ημέρες κάλυψης');
select pg_temp.eq(sick_status('L2','2026-06-01')->>'work_year_start', '2026-03-16', 'εργασιακό έτος από την πρόσληψη (όχι ημερολογιακό)');
select pg_temp.eq((sick_status('L1','2026-06-01')->>'first_work_year'), 'false', 'επόμενα εργασιακά έτη: κάλυψη 1 μήνα');

-- ═══════ 10. Ημερολόγιο αδειών από τα ίδια δεδομένα ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L2','annual','2026-08-03','2026-08-04','2') as pend \gset
select pg_temp.eq((select count(*) from leave_calendar('2026-08-01','2026-08-31') where request_id = :'pend' and status = 'pending'), 2::bigint, 'εκκρεμές: εμφανίζεται «Σε αναμονή»');
select pg_temp.eq((select count(*) from leave_calendar('2026-03-01','2026-04-30') where request_id = :'split' and status = 'approved'), 2::bigint, 'εγκεκριμένες ημέρες ως «Εγκρίθηκε»');
select pg_temp.eq((select count(*) from leave_calendar('2026-03-01','2026-04-30') where request_id = :'split' and status = 'cancelled'), 0::bigint, 'ακυρωμένες κρυμμένες από την ενεργή προβολή');
select pg_temp.eq((select count(*) from leave_calendar('2026-03-01','2026-04-30', null, null, true) where request_id = :'split' and status = 'cancelled'), 1::bigint, '…αλλά διατηρούνται στο ιστορικό');
select pg_temp.eq((select count(*) from leave_calendar('2026-01-01','2026-12-31') where store <> 'Γλυφάδα'), 0::bigint, 'manager: ημερολόγιο μόνο του καταστήματός του');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail($$select leave_card('L1')$$, 'manager άλλου καταστήματος δεν βλέπει άδειες');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.expect_fail($$select leave_card('L1')$$, 'εκπαιδευτής δεν βλέπει υπόλοιπα αδειών');
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((leave_card('L1')->'balance'->>'year')::int > 2000, true, 'λογιστήριο βλέπει υπόλοιπα');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
