\set ON_ERROR_STOP 1
-- Απόφαση ΓΔ (21/11/2026): οι κανονικές άδειες του 2025 και των προηγούμενων ετών θεωρούνται τακτοποιημένες εκτός
-- εφαρμογής. Κανένα υπόλοιπο, μεταφορά ή εκκαθάριση από ≤ 2025· το 2026 και η προϋπηρεσία μένουν ως έχουν.
-- ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα');
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('L1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2023-03-01'),
 ('L2','Μαρία','Βλάχου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-06-01');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.leave(c text, s date, e date, n text) returns uuid language plpgsql as $$
declare v uuid;
begin
  v := (req_create(jsonb_build_object('category','leave','employee_code',c,'entry_mode','manager_record','leave_type','annual',
        'start_date',s,'end_date',e,'days_requested',n,'body','Παρακαλώ να εγκρίνετε την άδεια του εργαζομένου.'))->>'id')::uuid;
  perform req_submit(v, 1);
  return v;
end $$;
create or replace function pg_temp.approve(v uuid) returns jsonb language sql as $$
  select req_decide(v, 'approve', '{"message":"Το αίτημα εγκρίθηκε σύμφωνα με τα στοιχεία."}', (select version from hr_requests where id = v)) $$;

select pg_temp.eq(leave_settled_through(), 2025, 'ρύθμιση: τακτοποιημένα έτη έως και το 2025');

-- ═══ Ετήσιες βάσεις από την πρόσληψη (προϋπηρεσία από 2023) ═══
select pg_temp.as_user('hr@x.gr');
select leave_apply_bases('L1');
select pg_temp.eq(leave_base_on('L1', '2026-06-01'), 22.00, 'η προϋπηρεσία (πρόσληψη 2023) δίνει βάση 22 ημερών το 2026 — δεν αλλάζει');
select pg_temp.eq(round(leave_accrued('L1', 2025, '2025-12-31'), 2) > 0, true, 'η αναλογία του 2025 υπολογίζεται (για ιστορικό), αλλά…');
select pg_temp.eq(leave_year_balance('L1', 2025, '2026-02-15'), 0::numeric, '…κανένα υπόλοιπο 2025');
select pg_temp.eq(leave_year_balance('L1', 2024, '2026-02-15'), 0::numeric, 'κανένα υπόλοιπο 2024');
select leave_balance_calc('L1', '2026-02-15') as b \gset
select pg_temp.eq((:'b'::jsonb->>'prev_balance')::numeric || '|' || (:'b'::jsonb->>'prev_state'), '0.00|settled_outside', 'κάρτα: καμία μεταφορά από το 2025 (τακτοποιημένο εκτός εφαρμογής)');
select pg_temp.eq((:'b'::jsonb->>'accrued')::numeric, round(22 / 12.0 + 22 / 12.0 * 15 / 28, 2), 'το 2026 ΔΕΝ μηδενίζεται: αναλογία Ιαν. + 15/28 Φεβρ.');
select pg_temp.eq((leave_balance_calc('L1', '2026-11-21')->>'annual_days')::numeric, 22.00, 'βάση 2026 με την προϋπηρεσία');

-- ═══ Καμία εκκρεμότητα εκκαθάρισης / διόρθωση για ≤ 2025 ═══
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select count(*) from leave_to_settle(2025)), 0::bigint, 'κανένας προς εκκαθάριση για το 2025');
select pg_temp.eq((select count(*) from leave_to_settle(2024)), 0::bigint, 'ούτε για το 2024');
select pg_temp.expect_fail($$select leave_settle('L1', 2025, 2, 100, '2026-11-20', null, 'Δοκιμή')$$, 'δεν καταχωρίζεται εκκαθάριση για το 2025 (καμία εικονική πληρωμή)');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select leave_adjust('L1', 2025, 5, '2026-02-15', 'Δοκιμαστική διόρθωση 2025')$$, 'δεν «ξαναδημιουργείται» υπόλοιπο 2025 με διόρθωση');

-- ═══ Αλλαγή πρόσληψης / νέα βάση δεν αναδημιουργεί παλιά υπόλοιπα ═══
select emp_set_dates('L2', '2020-01-15', null, 'Διόρθωση ημερομηνίας πρόσληψης');
select leave_apply_bases('L2');
select pg_temp.eq(leave_year_balance('L2', 2025, '2026-03-01') + leave_year_balance('L2', 2022, '2026-03-01'), 0::numeric, 'παλαιότερη πρόσληψη: κανένα υπόλοιπο ≤ 2025');
select leave_set_base('L2', 22, '2025-06-01', 'Βάση 2025');
select pg_temp.eq(leave_year_balance('L2', 2025, '2026-03-01'), 0::numeric, 'νέα ετήσια βάση για το 2025: πάλι κανένα υπόλοιπο');
select pg_temp.eq((leave_balance_calc('L2', '2026-11-21')->>'annual_days')::numeric, 22.00, 'η προϋπηρεσία από 2020 δίνει πλήρη βάση το 2026');

-- ═══ Άδεια Ιανουαρίου 2026: χρεώνεται στο 2026 (όχι σε υπόλοιπο 2025) ═══
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L1', '2026-01-12', '2026-01-13', '2') as l1 \gset
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail(format($$select pg_temp.approve(%L)$$, :'l1'), 'χωρίς μεταφορά από το 2025, η αναλογία Ιανουαρίου (0,77) δεν φτάνει: χρειάζεται έγκριση υπέρβασης ΓΔ');
select pg_temp.as_user('owner@x.gr');
select req_decide(:'l1', 'approve', '{"message":"Εγκρίνεται με υπέρβαση αναλογίας.","overdraw_ok":true}', (select version from hr_requests where id = :'l1'));
select pg_temp.eq((select string_agg(distinct c.leave_year::text, ',') from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = :'l1'), '2026', 'χρέωση στο 2026');

-- ═══ Παλιές χρεώσεις 2026 που είχαν πάει στο 2025: μεταφέρονται στο 2026 με καταγραφή, χωρίς διαγραφές ═══
reset role;
update leave_settings set settled_through_year = 2020;   -- κατάσταση πριν από την απόφαση
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('L1', '2026-02-02', '2026-02-03', '2') as l2 \gset
select pg_temp.as_user('hr@x.gr');
select pg_temp.approve(:'l2');
reset role;
select pg_temp.eq((select string_agg(distinct c.leave_year::text, ',') from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = :'l2'), '2025', 'πριν: η άδεια Φεβρουαρίου είχε χρεωθεί στο υπόλοιπο 2025');
select (select count(*) from leave_charges) as ch0 \gset
update leave_settings set settled_through_year = 2025;   -- απόφαση ΓΔ
select pg_temp.eq((select string_agg(distinct c.leave_year::text, ',') from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = :'l2'), '2025', 'οι γραμμές χρέωσης δεν αλλάζουν (αμετάβλητο ιστορικό)');
select pg_temp.eq((select count(*) from leave_charges), :ch0::bigint, 'καμία διαγραφή ή προσθήκη χρεώσεων');
select pg_temp.eq(leave_charged('L1', 2026), 4.00, 'στον υπολογισμό, η άδεια Φεβρουαρίου λογίζεται στο 2026');
select pg_temp.eq(leave_charged('L1', 2025), 0.00, 'και όχι στο τακτοποιημένο 2025');
select pg_temp.eq((select status from hr_requests where id = :'l2') || '|' || (select count(*) from hr_decisions where request_id = :'l2'), 'approved|1', 'η έγκριση και το ιστορικό μένουν');
select pg_temp.eq(round((leave_balance_calc('L1', '2026-11-21')->>'taken')::numeric, 2), 4.00, 'το 2026 μετρά σωστά τις 4 ημέρες που λήφθηκαν μέσα στο 2026');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
