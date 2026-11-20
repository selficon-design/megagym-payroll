\set ON_ERROR_STOP 1
-- Δικαίωμα «Οδηγός χρήσης»: στον πίνακα δικαιωμάτων, αρχικά σε όλους, η ΓΔ το αφαιρεί ανά ρόλο και το whoami
-- (που ελέγχει η λειτουργία server «guide») ακολουθεί αμέσως. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager','manager','Γλυφάδα'),('trainer@x.gr','Εκπαιδευτής','trainer',null);
create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
create or replace function pg_temp.has_guide(e text) returns boolean language plpgsql as $$
declare r boolean; begin perform pg_temp.as_user(e); select (whoami()->'perms') ? 'guide.view' into r; reset role; return r; end $$;

select pg_temp.eq((select count(*)::int from role_permissions where perm = 'guide.view' and allowed), 5, 'αρχικά όλοι οι ρόλοι έχουν τον οδηγό (όπως ως τώρα)');
select pg_temp.eq(pg_temp.has_guide('trainer@x.gr') and pg_temp.has_guide('acc@x.gr') and pg_temp.has_guide('glyfada@x.gr'), true, 'whoami δίνει guide.view');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*)::int from jsonb_array_elements(permissions_matrix()->'permissions') p where p->>'code' = 'guide.view'), 1, 'ο οδηγός εμφανίζεται στον πίνακα δικαιωμάτων');
select pg_temp.expect_fail($$select permissions_save('[{"role":"trainer","perm":"guide.view","allowed":false}]', null, '')$$, 'αλλαγή χωρίς αιτιολογία');
select permissions_save('[{"role":"trainer","perm":"guide.view","allowed":false},{"role":"accounting","perm":"guide.view","allowed":false}]', null, 'Ο οδηγός μόνο σε ΓΔ, HR, managers');
reset role;
select pg_temp.eq(pg_temp.has_guide('trainer@x.gr') or pg_temp.has_guide('acc@x.gr'), false, 'μετά την αφαίρεση: εκπαιδευτής και λογιστήριο χωρίς οδηγό');
select pg_temp.eq(pg_temp.has_guide('glyfada@x.gr') and pg_temp.has_guide('hr@x.gr') and pg_temp.has_guide('owner@x.gr'), true, 'οι υπόλοιποι κρατούν τον οδηγό');
select pg_temp.eq((select count(*)::int from permission_log where perm = 'guide.view'), 2, 'ιστορικό αλλαγών για τον οδηγό');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select permissions_save('[{"role":"trainer","perm":"guide.view","allowed":true}]', null, 'παράκαμψη')$$, 'μόνο η ΓΔ δίνει πρόσβαση στον οδηγό');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
