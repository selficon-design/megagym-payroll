-- Πραγματικού τύπου δεδομένα μισθοδοσίας ΠΡΙΝ από την επέκταση (εικονικά στοιχεία)
insert into app_users(email,name,role,store) values ('owner@x.gr','ΓΔ','owner',null),('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα');
insert into employees(code,first,last,store,company) values
 ('E1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE'),('E2','Μαρία','Βλάχου','Κηφισιά','ARG BEST GREEK GYMS IKE');
select set_config('request.jwt.claims', '{"email":"glyfada@x.gr"}', false);
set role authenticated;
select prepare_declarations('2026-10','[{"code":"E1","amount":"1.250,50"}]');
select sign_declaration((select id from declarations limit 1),'Νίκος Αλεξίου','data:image/png;base64,'||repeat('A',3000),'tablet');
reset role;
create table public.zz_snapshot as
  select id, status, amount, statement, signature, signer, signed_at, md5(declarations::text) as h from declarations;
create table public.zz_snapshot_emp as select code, md5(row(code,first,last,store,company,status,created_at)::text) h from employees;
create table public.zz_snapshot_audit as select count(*) n from audit_log;
