\set ON_ERROR_STOP 1
create or replace function pg_temp.eq(a bigint, b bigint, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
-- Η δήλωση, το κείμενο και η υπογραφή είναι byte-προς-byte ίδια μετά τη migration
select pg_temp.eq((select count(*) from declarations d join zz_snapshot s on s.id = d.id and s.h = md5(d::text)), 1, 'αναβάθμιση: υπογεγραμμένη δήλωση αμετάβλητη');
select pg_temp.eq((select count(*) from employees e join zz_snapshot_emp s on s.code = e.code
   and s.h = md5(row(e.code,e.first,e.last,e.store,e.company,e.status,e.created_at)::text)), 2, 'αναβάθμιση: εργαζόμενοι αμετάβλητοι');
select pg_temp.eq((select count(*) from audit_log), (select n from zz_snapshot_audit), 'αναβάθμιση: ιστορικό ενεργειών αμετάβλητο');
select pg_temp.eq((select count(*) from employee_assignments where valid_to is null), 2, 'αναβάθμιση: αρχικό ιστορικό θέσης για κάθε εργαζόμενο');
select pg_temp.eq((select count(*) from employees where specialty is null and hire_date is null), 2, 'αναβάθμιση: νέα πεδία κενά (προς συμπλήρωση)');
-- Η μισθοδοσία συνεχίζει κανονικά μετά την αναβάθμιση
select set_config('request.jwt.claims', '{"email":"owner@x.gr"}', false);
set role authenticated;
select pg_temp.eq(((select prepare_declarations('2026-11','[{"code":"E1","amount":"900"},{"code":"E2","amount":"800"}]'))->>'created')::int, 2, 'αναβάθμιση: προετοιμασία δηλώσεων λειτουργεί');
select sign_declaration((select id from declarations where month='2026-11' and employee_code='E2'),'Μαρία Βλάχου','data:image/png;base64,'||repeat('B',3000),'t');
select pg_temp.eq((select count(*) from declarations where status='signed'), 2, 'αναβάθμιση: υπογραφή λειτουργεί');
select pg_temp.eq((select count(*) from month_status('2026-10')), 2, 'αναβάθμιση: κατάσταση μήνα λειτουργεί');
reset role;
drop table zz_snapshot, zz_snapshot_emp, zz_snapshot_audit;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
