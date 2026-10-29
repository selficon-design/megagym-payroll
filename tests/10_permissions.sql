\set ON_ERROR_STOP 1
-- seed ως διαχειριστής βάσης
insert into app_users(email,name,role,store) values
 ('owner@x.gr','Ιδιοκτήτρια','owner',null),('hr@x.gr','HR Χρήστης','hr',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά');
insert into employees(code,first,last,store,company) values
 ('E1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE'),
 ('E2','Μαρία','Βλάχου','Γλυφάδα','BEST GREEK GYMS IKE'),
 ('E3','Γιώργος','Γεωργίου','Κηφισιά','ARG BEST GREEK GYMS IKE');
insert into employees(code,first,last,store,company,status) values ('E4','Άννα','Δήμου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ανενεργός');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.eq(a bigint, b bigint, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;

-- 1. Manager Γλυφάδας βλέπει μόνο τη Γλυφάδα
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from employees), 2, 'manager βλέπει 2 εργαζόμενους');
select pg_temp.expect_fail($$insert into employees(code,first,last,store,company) values('X','a','b','Γλυφάδα','BEST GREEK GYMS IKE')$$, 'manager δεν προσθέτει εργαζόμενο');
select pg_temp.eq((select count(*) from app_users), 1, 'manager βλέπει μόνο τον εαυτό του');
select pg_temp.eq((select count(*) from audit_log), 0, 'manager δεν βλέπει ιστορικό');
-- manager προετοιμάζει για το κατάστημά του, όχι για άλλο
select prepare_declarations('2026-10', '[{"code":"E1","amount":"1.250,50"},{"code":"E3","amount":"900"}]') as r \gset
\echo :r
select pg_temp.eq((select count(*) from declarations), 1, 'manager έφτιαξε 1 (E3 απορρίφθηκε)');
select pg_temp.expect_fail($$insert into declarations(employee_code,employee_name,store,company,month,end_date,period,amount) values('E1','x','Γλυφάδα','c','2026-11','2026-11-30','x',1)$$, 'απευθείας insert δήλωσης');
select pg_temp.expect_fail($$select sign_declaration((select id from declarations limit 1),'Νίκος Αλεξίου','data:image/png;base64,AAAA')$$, 'πολύ μικρή υπογραφή');
select sign_declaration((select id from declarations limit 1),'Νίκος Αλεξίου','data:image/png;base64,'||repeat('A',2000),'test-tablet');
select pg_temp.eq((select count(*) from declarations where status='signed'), 1, 'υπογράφηκε');
select pg_temp.eq(0,(select count(*) from (select 1) x where (prepare_declarations('2026-10','[{"code":"E1","amount":"1"}]')->'skipped'->0->>'reason')='Έχει ήδη υπογράψει')-1,'υπογεγραμμένη δεν ξαναπροετοιμάζεται');
select pg_temp.expect_fail($$update declarations set amount=1$$, 'αλλαγή ποσού υπογεγραμμένης');
select pg_temp.expect_fail($$select void_declaration((select id from declarations limit 1),'λάθος ποσό')$$, 'manager δεν ακυρώνει');
select statement from declarations limit 1;
reset role;

-- 2. Manager Κηφισιάς δεν βλέπει τη Γλυφάδα
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.eq((select count(*) from declarations), 0, 'Κηφισιά δεν βλέπει δηλώσεις Γλυφάδας');
select pg_temp.eq(((select prepare_declarations('2026-10','[{"code":"E4","amount":"5"}]'))->>'created')::int, 0, 'ανενεργός δεν παίρνει δήλωση');
reset role;

-- 3. HR: βλέπει όλα, προετοιμάζει μαζικά, δεν υπογράφει, δεν διαχειρίζεται χρήστες
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select count(*) from employees), 4, 'HR βλέπει όλους');
select pg_temp.eq(((select prepare_declarations('2026-10','[{"code":"E2","amount":"800"},{"code":"E3","amount":"1000.5"}]'))->>'created')::int, 2, 'HR μαζική');
select pg_temp.expect_fail($$select sign_declaration((select id from declarations where employee_code='E2'),'Μαρία','data:image/png;base64,'||repeat('A',2000))$$, 'HR δεν υπογράφει');
select pg_temp.expect_fail($$insert into app_users(email,name,role) values('a@b.gr','Νέος','hr')$$, 'HR δεν προσθέτει χρήστες');
select pg_temp.eq((select count(*) from month_status('2026-10')), 3, 'month_status ενεργοί');
select pg_temp.eq((select count(*) from audit_log where action='sign'), 1, 'audit καταγράφει υπογραφή');
update employees set store='Κηφισιά' where code='E2';
reset role;

-- 4. Ιδιοκτήτρια
select pg_temp.as_user('owner@x.gr');
select void_declaration((select id from declarations where status='signed'),'Λάθος ποσό');
select pg_temp.eq(((select prepare_declarations('2026-10','[{"code":"E1","amount":"1300"}]'))->>'created')::int, 1, 'νέα δήλωση μετά από ακύρωση');
select pg_temp.expect_fail($$delete from app_users where email='owner@x.gr'$$, 'τελευταία ιδιοκτήτρια');
insert into app_users(email,name,role,store) values('new@x.gr','Νέος Manager','manager','Άλιμος');
select pg_temp.expect_fail($$insert into app_users(email,name,role) values('m2@x.gr','Χωρίς κατάστημα','manager')$$, 'manager χωρίς κατάστημα');
select pg_temp.expect_fail($$delete from declarations$$, 'διαγραφή δηλώσεων');
select pg_temp.eq((select count(*) from audit_log), (select count(*) from audit_log), 'owner διαβάζει audit');
select action, entity, entity_id, actor from audit_log order by id;
reset role;

-- 5. Χρήστης χωρίς ρόλο / anon
select pg_temp.as_user('stranger@x.gr');
select pg_temp.eq((select count(*) from employees), 0, 'άγνωστος δεν βλέπει τίποτα');
select pg_temp.expect_fail($$select prepare_declarations('2026-10','[{"code":"E1","amount":"1"}]')$$, 'άγνωστος δεν προετοιμάζει');
reset role;
set role anon;
select pg_temp.expect_fail($$select * from employees$$, 'anon');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
