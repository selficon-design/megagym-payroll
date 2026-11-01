-- Εικονικά δεδομένα για τον έλεγχο (κανένα πραγματικό πρόσωπο)
do $$ begin if not exists (select 1 from pg_roles where rolname='authenticator') then create role authenticator login password 'auth' noinherit; end if; end $$;
grant anon, authenticated to authenticator;
insert into app_users(email,name,role,store) values
 ('owner@test.gr','Δοκιμαστική ΓΔ','owner',null),('hr@test.gr','Δοκιμαστικό HR','hr',null),
 ('glyfada@test.gr','Manager Γλυφάδας (test)','manager','Γλυφάδα'),('kifisia@test.gr','Manager Κηφισιάς (test)','manager','Κηφισιά'),
 ('trainer@test.gr','Εκπαιδευτής (test)','trainer',null);
insert into trainer_scopes(email, store, specialty) values ('trainer@test.gr', null, 'Ρεσεψιόν');
insert into employees(code,first,last,store,company,specialty,hire_date) values
 ('T100','Ελένη','Δοκιμή','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν','2024-03-01'),
 ('T101','Σάκης','Τεστάκης','Γλυφάδα','BEST GREEK GYMS IKE','Επίβλεψη','2023-09-15'),
 ('T102','Ξένια','Υπόδειγμα','Γλυφάδα','BEST GREEK GYMS IKE','Exclusive','2025-01-10'),
 ('T200','Κώστας','Παράδειγμα','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν','2022-05-20'),
 ('T201','Νίκη','Χωριςειδικότητα','Γλυφάδα','BEST GREEK GYMS IKE',null,null);
-- Μισθοδοσία πριν από τις δοκιμές (για να ελεγχθεί ότι δεν επηρεάζεται)
select set_config('request.jwt.claims','{"email":"glyfada@test.gr"}', false);
set role authenticated;
select prepare_declarations('2026-10','[{"code":"T100","amount":"1.100,00"},{"code":"T101","amount":"950"}]');
select sign_declaration((select id from declarations where employee_code='T100'),'Ελένη Δοκιμή','data:image/png;base64,'||repeat('A',3000),'e2e');
reset role;
-- Στατιστικά προηγούμενων ημερών (άμεση εισαγωγή ως διαχειριστής βάσης)
insert into daily_stats(employee_code,stat_date,store,specialty,kind,dr,lost,cb,trials_sent,enr_fitness,enr_body,enr_muscle,enr_from_trials,created_by)
select 'T100', d::date, 'Γλυφάδα','Ρεσεψιόν','reception', (i%4), 3+(i%5), (i%2), 1, (i%4)+(i%2)-((i%4)+(i%2))/2, ((i%4)+(i%2))/2, 0, 0, 'seed'
  from generate_series(current_date - 20, current_date - 2, interval '1 day') with ordinality g(d,i) where i % 7 <> 3;
insert into daily_stats(employee_code,stat_date,store,specialty,kind,dr,lost,cb,trials_sent,enr_fitness,enr_body,enr_muscle,enr_from_trials,created_by)
select 'T200', d::date, 'Κηφισιά','Ρεσεψιόν','reception', 2, 4, 1, 1, 2, 1, 0, 1, 'seed' from generate_series(current_date - 10, current_date - 2, interval '1 day') d;
insert into daily_stats(employee_code,stat_date,store,specialty,kind,dr,lost,cb,trials_sent,trials_attended,trials_enrolled,enr_body,enr_muscle,enr_pilates,created_by)
values ('T101', current_date - 3,'Γλυφάδα','Επίβλεψη','supervision',1,2,1,2,3,1,1,0,1,'seed');
