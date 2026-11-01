\set ON_ERROR_STOP 1
-- Ημερήσια στατιστικά: δικαιώματα, ακέραιοι ≥ 0, διπλές καταχωρίσεις, ιστορικό διορθώσεων, υπολογισμοί. Εικονικά στοιχεία.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),
 ('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty) values
 ('R1','Ελένη','Ρεσεψιόν','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('S1','Σάκης','Επίβλεψη','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη'),
 ('X1','Ξένια','Exclusive','Γλυφάδα','BEST GREEK GYMS IKE','Exclusive'),
 ('K1','Κώστας','Κηφισιά','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν'),
 ('N1','Νίκη','ΧωρίςΕιδικότητα','Γλυφάδα','BEST GREEK GYMS IKE',null);

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.row_err(res jsonb) returns text language sql as $$ select res->'rows'->0->>'error' $$;
create or replace function pg_temp.expect_row_err(res jsonb, label text) returns void language plpgsql as $$
begin if (res->'rows'->0->>'ok')::boolean then raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να απορριφθεί: %', label; end if;
raise notice 'OK απορρίφθηκε (%): %', label, res->'rows'->0->>'error'; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;

select pg_temp.as_user('glyfada@x.gr');
-- Ρεσεψιόν: 10 ενημερώσεις = DR 4 + LOST 6, CB 2 → μετατροπή (4+2)/10 = 60%
select stats_save('2026-10-20', '[
  {"employee_code":"R1","dr":4,"lost":6,"cb":2,"trials_sent":3,"enr_fitness":3,"enr_body":2,"enr_muscle":1,"enr_from_trials":1},
  {"employee_code":"S1","dr":2,"lost":3,"cb":1,"trials_sent":4,"trials_attended":2,"trials_enrolled":1,"enr_body":1,"enr_muscle":1,"enr_pilates":1},
  {"employee_code":"X1","trials_done":5,"enr_from_trials":2}]') as res \gset
select pg_temp.eq((select count(*) from jsonb_array_elements((:'res'::jsonb)->'rows') r where (r->>'ok')::boolean), 3::bigint, 'καταχώριση ημέρας για 3 εργαζόμενους/ειδικότητες');
select pg_temp.eq((select informed from daily_stats where employee_code = 'R1'), 10, 'Ενημερώσεις = DR + LOST (υπολογίζονται)');
select pg_temp.eq((select store||'|'||specialty||'|'||kind||'|'||created_by from daily_stats where employee_code = 'R1'), 'Γλυφάδα|Ρεσεψιόν|reception|glyfada@x.gr', 'καταχώριση συνδέεται με κατάστημα, ειδικότητα και χρήστη');
select pg_temp.expect_fail($$update daily_stats set informed = 99$$, 'οι ενημερώσεις δεν πληκτρολογούνται');
select pg_temp.expect_fail($$insert into daily_stats(employee_code,stat_date,store,specialty,kind,trials_done,enr_from_trials,created_by) values ('X1','2026-10-21','Γλυφάδα','Exclusive','exclusive',1,1,'x')$$, 'απευθείας εγγραφή στον πίνακα');

-- Ακέραιοι ≥ 0, πλήρη πεδία
select pg_temp.expect_row_err(stats_save('2026-10-21', '[{"employee_code":"X1","trials_done":-1,"enr_from_trials":0}]'), 'αρνητικός αριθμός');
select pg_temp.expect_row_err(stats_save('2026-10-21', '[{"employee_code":"X1","trials_done":1.5,"enr_from_trials":0}]'), 'δεκαδικός αριθμός');
select pg_temp.expect_row_err(stats_save('2026-10-21', '[{"employee_code":"X1","trials_done":"abc","enr_from_trials":0}]'), 'μη αριθμός');
select pg_temp.expect_row_err(stats_save('2026-10-21', '[{"employee_code":"X1","trials_done":2}]'), 'ελλιπή πεδία');
select pg_temp.expect_row_err(stats_save('2026-10-21', '[{"employee_code":"N1","trials_done":2,"enr_from_trials":0}]'), 'ειδικότητα χωρίς στατιστικά');
select pg_temp.expect_fail($$select stats_save(athens_today() + 1, '[]')$$, 'μελλοντική ημερομηνία');
-- Αποτροπή διπλής καταχώρισης
select pg_temp.expect_row_err(stats_save('2026-10-20', '[{"employee_code":"X1","trials_done":9,"enr_from_trials":9}]'), 'διπλή καταχώριση ίδιας ημέρας');
select pg_temp.eq((select trials_done from daily_stats where employee_code = 'X1'), 5, 'η διπλή καταχώριση δεν άλλαξε τα στοιχεία');
-- Μηδενικά ≠ χωρίς καταχώριση
select stats_save('2026-10-21', '[{"employee_code":"X1","trials_done":0,"enr_from_trials":0}]');
select pg_temp.eq((select count(*) from daily_stats where employee_code = 'X1'), 2::bigint, 'ημέρα με μηδενικά αποθηκεύεται ως καταχώριση');
select pg_temp.eq((select count(*) from daily_stats where employee_code = 'R1' and stat_date = '2026-10-21'), 0::bigint, 'ημέρα χωρίς καταχώριση: καμία εγγραφή (όχι μηδέν)');

-- Διόρθωση με ιστορικό
select id as x1, version as v from daily_stats where employee_code = 'X1' and stat_date = '2026-10-20' \gset
select stats_save('2026-10-20', format('[{"id":%s,"version":%s,"employee_code":"X1","trials_done":6,"enr_from_trials":2}]', :x1, :v)::jsonb);
select pg_temp.eq((select trials_done||'|'||updated_by||'|'||version from daily_stats where id = :x1), '6|glyfada@x.gr|2', 'διόρθωση με χρήστη τροποποίησης');
select pg_temp.eq((select (old_values->>'trials_done')||'→'||(new_values->>'trials_done') from daily_stats_history where stats_id = :x1), '5→6', 'ιστορικό προηγούμενων τιμών');
select pg_temp.expect_row_err(stats_save('2026-10-20', format('[{"id":%s,"version":1,"employee_code":"X1","trials_done":7,"enr_from_trials":2}]', :x1)::jsonb), 'διόρθωση με παλιά έκδοση');
select pg_temp.expect_fail($$update daily_stats_history set changed_by = 'x'$$, 'ιστορικό διορθώσεων δεν αλλάζει');

-- Δικαιώματα
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from daily_stats), 0::bigint, 'manager Κηφισιάς δεν βλέπει στοιχεία Γλυφάδας');
select pg_temp.expect_row_err(stats_save('2026-10-20', '[{"employee_code":"R1","dr":1,"lost":1,"cb":0,"trials_sent":0,"enr_fitness":0,"enr_body":0,"enr_muscle":0,"enr_from_trials":0}]'), 'manager: εργαζόμενος άλλου καταστήματος');
select pg_temp.expect_row_err(stats_save('2026-10-20', format('[{"id":%s,"version":2,"employee_code":"X1","trials_done":1,"enr_from_trials":0}]', :x1)::jsonb), 'manager: διόρθωση άλλου καταστήματος');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select count(*) from daily_stats), 4::bigint, 'HR βλέπει όλα τα καταστήματα');
select pg_temp.expect_fail($$select stats_save('2026-10-20', '[]')$$, 'HR μόνο ανάγνωση στατιστικών');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq((select count(*) from daily_stats), 0::bigint, 'εκπαιδευτής δεν βλέπει στατιστικά');

-- Τύποι διαστήματος από ΑΘΡΟΙΣΜΑΤΑ (όχι μέσος όρος ποσοστών)
select pg_temp.as_user('owner@x.gr');
select stats_save('2026-10-21', '[{"employee_code":"R1","dr":1,"lost":89,"cb":0,"trials_sent":0,"enr_fitness":1,"enr_body":0,"enr_muscle":0,"enr_from_trials":0}]');
-- Ημέρα 1: 6/10 = 60%, ημέρα 2: 1/90 ≈ 1,1% → μέσος όρος 30,6% (ΛΑΘΟΣ) · από αθροίσματα 7/100 = 7% (ΣΩΣΤΟ)
select pg_temp.eq((select round(100.0 * (sum(dr) + sum(cb)) / nullif(sum(informed), 0), 1) from daily_stats where employee_code = 'R1'), 7.0, 'μετατροπή διαστήματος = (ΣDR + ΣCB) / ΣΕνημερώσεις');
select pg_temp.eq((select round(100.0 * (sum(enr_body) + sum(enr_muscle)) / nullif(sum(informed), 0), 1) from daily_stats where employee_code = 'R1'), 3.0, 'ποσοστό Exclusive = (BODY + MUSCLE) / Ενημερώσεις');
select pg_temp.eq((select (sum(dr) + sum(cb))::int from daily_stats where employee_code = 'R1'), 7, 'συνολικές εγγραφές = DR + CB (χωρίς να προστίθενται ξανά τα προγράμματα)');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
