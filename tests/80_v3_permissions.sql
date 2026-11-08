\set ON_ERROR_STOP 1
-- Έκδοση 3 · Ρόλοι & Δικαιώματα: πίνακας μόνο από ΓΔ με ιστορικό, προστασία από απώλεια πρόσβασης, ο server
-- ακολουθεί τον πίνακα, λογιστήριο, απαγόρευση υπογραφών (HR/εκπαιδευτής/λογιστήριο) και PDF (manager/HR/
-- εκπαιδευτής) — και από απευθείας ανάγνωση ή μαζικές λήψεις. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('acc@x.gr','Λογιστήριο','accounting',null),
 ('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα'),('kifisia@x.gr','Manager Κηφισιάς','manager','Κηφισιά'),
 ('trainer@x.gr','Εκπαιδευτής','trainer',null);
insert into employees(code,first,last,store,company,specialty,work_week) values
 ('P1','Ελένη','Πέτρου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5),
 ('P2','Κατερίνα','Σταύρου','Κηφισιά','ARG BEST GREEK GYMS IKE','Ρεσεψιόν',5);
insert into declarations(id, employee_code, employee_name, store, company, month, end_date, period, amount, status, prepared_by, signer, signature, signed_at, statement) values
 ('00000000-0000-0000-0000-000000000001','P1','Ελένη Πέτρου','Γλυφάδα','BEST GREEK GYMS IKE','2026-09','2026-09-30','Σεπτέμβριος 2026', 900, 'signed', 'owner@x.gr', 'Ελένη Πέτρου', 'data:image/png;base64,AAAA', now(), 'Δήλωση'),
 ('00000000-0000-0000-0000-000000000002','P2','Κατερίνα Σταύρου','Κηφισιά','ARG BEST GREEK GYMS IKE','2026-09','2026-09-30','Σεπτέμβριος 2026', 950, 'signed', 'owner@x.gr', 'Κατερίνα Σταύρου', 'data:image/png;base64,BBBB', now(), 'Δήλωση');
insert into declarations(id, employee_code, employee_name, store, company, month, end_date, period, amount, status, prepared_by) values
 ('00000000-0000-0000-0000-000000000003','P1','Ελένη Πέτρου','Γλυφάδα','BEST GREEK GYMS IKE','2026-10','2026-10-31','Οκτώβριος 2026', 900, 'pending', 'owner@x.gr');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;
select 'data:image/png;base64,' || repeat('A', 2000) as sig \gset

-- ═══════ Πίνακας δικαιωμάτων: μόνο η ΓΔ, με ιστορικό ═══════
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select permissions_matrix()$$, 'HR δεν βλέπει/αλλάζει τον πίνακα');
select pg_temp.expect_fail($$select permissions_save('[{"role":"hr","perm":"payroll.pdf","allowed":true}]', null, 'δοκιμή')$$, 'HR δεν αλλάζει δικαιώματα');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq(jsonb_array_length(permissions_matrix()->'permissions') >= 30, true, 'δικαιώματα ανά ενότητα και ενέργεια (όχι γενικό «πλήρης πρόσβαση»)');
select pg_temp.expect_fail($$select permissions_save('[{"role":"owner","perm":"users.manage","allowed":false}]', null, 'δοκιμή αφαίρεσης')$$, 'προστασία: η ΓΔ δεν χάνει τη διαχείριση χρηστών');
select pg_temp.expect_fail($$select permissions_save('[{"role":"owner","perm":"permissions.manage","allowed":false}]', null, 'δοκιμή αφαίρεσης')$$, 'προστασία: η ΓΔ δεν χάνει τον πίνακα δικαιωμάτων');
select pg_temp.expect_fail($$select permissions_save('[{"role":"hr","perm":"permissions.manage","allowed":true}]', null, 'δοκιμή')$$, 'ο πίνακας δικαιωμάτων δεν εκχωρείται σε άλλον ρόλο');
select pg_temp.expect_fail($$select permissions_save('[{"role":"manager","perm":"exit.view","allowed":true}]', null, 'δοκιμή')$$, 'Exit Interview δεν εκχωρείται σε manager');
select pg_temp.expect_fail($$select permissions_save('[{"role":"hr","perm":"payroll.pdf","allowed":true}]', null, '')$$, 'αλλαγή δικαιωμάτων χωρίς αιτιολογία');
select pg_temp.expect_fail($$select permissions_save(null, '{"owner":"own_store"}', 'δοκιμή')$$, 'η ΓΔ έχει πάντα όλα τα καταστήματα');
-- ο server ακολουθεί τον πίνακα (αλλαγή → ισχύει αμέσως)
select permissions_save('[{"role":"manager","perm":"stats.entry","allowed":false}]', null, 'Προσωρινά μόνο η ΓΔ καταχωρίζει στατιστικά');
select pg_temp.eq((select count(*) from permission_log where perm = 'stats.entry' and old_value = 'true' and new_value = 'false' and actor = 'owner@x.gr'), 1::bigint, 'ιστορικό αλλαγής δικαιώματος (ποιος, πότε, παλιά → νέα τιμή)');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.expect_fail($$select stats_save(current_date - 1, '[]')$$, 'ο server εφαρμόζει αμέσως την αφαίρεση δικαιώματος');
select pg_temp.eq((whoami()->'perms') ? 'stats.entry', false, 'η οθόνη παίρνει τα δικαιώματα από τον server');
select pg_temp.as_user('owner@x.gr');
select permissions_save('[{"role":"manager","perm":"stats.entry","allowed":true}]', null, 'Επαναφορά');
select pg_temp.expect_fail($$update role_permissions set allowed = true$$, 'καμία απευθείας αλλαγή του πίνακα');
select pg_temp.expect_fail($$delete from permission_log$$, 'το ιστορικό δεν διαγράφεται');
-- νέα ενότητα δεν δίνει αυτόματα δικαιώματα
reset role;
insert into permissions(code, module, label) values ('future.thing', 'Μελλοντική', 'Νέα ενότητα');
select pg_temp.eq(role_has_perm('hr', 'future.thing') or role_has_perm('manager', 'future.thing'), false, 'νέα ενότητα: κανένα δικαίωμα «από προεπιλογή»');
delete from permissions where code = 'future.thing';

-- ═══════ Λογιστήριο ═══════
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select count(*) from declarations), 3::bigint, 'λογιστήριο: προβολή δηλώσεων (πεδίο: όλα τα καταστήματα)');
select pg_temp.expect_fail($$select prepare_declarations('2026-11', '[{"code":"P1","amount":"1"}]')$$, 'λογιστήριο: όχι έναρξη διαδικασίας δηλώσεων');
select pg_temp.expect_fail(format($$select sign_declaration('00000000-0000-0000-0000-000000000003', 'Ελένη Πέτρου', %L)$$, :'sig'), 'λογιστήριο: όχι υπογραφή');
select pg_temp.eq((select count(*) from decl_pdf_data(array['00000000-0000-0000-0000-000000000001']::uuid[], 'single')), 1::bigint, 'λογιστήριο: λήψη PDF');
select pg_temp.expect_fail($$select * from decl_pdf_data(array['00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002']::uuid[], 'bulk')$$, 'λογιστήριο: όχι μαζική λήψη (αρχική ρύθμιση)');
select pg_temp.expect_fail($$select * from decl_pdf_data(array['00000000-0000-0000-0000-000000000001']::uuid[], 'backup')$$, 'λογιστήριο: το PDF δεν συνεπάγεται πλήρες backup');
select pg_temp.eq((select count(*) from hr_requests), 0::bigint, 'λογιστήριο: χωρίς γενική πρόσβαση σε εμπιστευτικές ενότητες (αιτήματα)');
select pg_temp.eq((select count(*) from audit_log), 0::bigint, 'λογιστήριο: χωρίς ιστορικό ενεργειών');
update employees set phone = '2101111111' where code = 'P2';
select pg_temp.eq((select phone from employees where code = 'P2'), '2101111111', 'λογιστήριο: καταχώριση στοιχείων εργαζομένων');

-- ═══════ PDF & υπογραφή: μόνο ΓΔ/λογιστήριο για PDF, μόνο ΓΔ/manager για υπογραφή ═══════
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from declarations), 2::bigint, 'manager: δηλώσεις μόνο του καταστήματός του');
select pg_temp.expect_fail($$select signature from declarations$$, 'manager: η εικόνα υπογραφής δεν διαβάζεται απευθείας (καμία δημιουργία PDF στον browser)');
select pg_temp.expect_fail($$select * from declarations$$, 'manager: ούτε με «select *» (απευθείας URL)');
select pg_temp.expect_fail($$select * from decl_pdf_data(array['00000000-0000-0000-0000-000000000001']::uuid[], 'single')$$, 'manager: όχι λήψη PDF');
select pg_temp.expect_fail($$select * from decl_pdf_data(array['00000000-0000-0000-0000-000000000001']::uuid[], 'bulk')$$, 'manager: όχι PDF μέσα σε ZIP');
select pg_temp.eq((select amount from declarations where id = '00000000-0000-0000-0000-000000000001'), 900.00, 'manager: βλέπει τα στοιχεία της δήλωσης');
select pg_temp.eq((sign_declaration('00000000-0000-0000-0000-000000000003', 'Ελένη Πέτρου', :'sig'))->>'ok', 'true', 'manager: διαδικασία υπογραφής με εργαζόμενο του καταστήματός του');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select * from decl_pdf_data(array['00000000-0000-0000-0000-000000000001']::uuid[], 'single')$$, 'HR: όχι λήψη PDF');
select pg_temp.expect_fail($$select signature from declarations$$, 'HR: η εικόνα υπογραφής δεν διαβάζεται');
reset role; insert into declarations(id, employee_code, employee_name, store, company, month, end_date, period, amount, status, prepared_by) values
 ('00000000-0000-0000-0000-000000000004','P2','Κατερίνα Σταύρου','Κηφισιά','ARG BEST GREEK GYMS IKE','2026-10','2026-10-31','Οκτώβριος 2026', 950, 'pending', 'owner@x.gr');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail(format($$select sign_declaration('00000000-0000-0000-0000-000000000004', 'Κατερίνα Σταύρου', %L)$$, :'sig'), 'HR: όχι διαδικασία υπογραφής');
select pg_temp.as_user('trainer@x.gr');
select pg_temp.expect_fail(format($$select sign_declaration('00000000-0000-0000-0000-000000000004', 'Κατερίνα Σταύρου', %L)$$, :'sig'), 'εκπαιδευτής: όχι διαδικασία υπογραφής');
select pg_temp.expect_fail($$select * from decl_pdf_data(array['00000000-0000-0000-0000-000000000002']::uuid[], 'single')$$, 'εκπαιδευτής: όχι λήψη PDF');
select pg_temp.eq((select count(*) from declarations), 0::bigint, 'εκπαιδευτής: χωρίς μισθοδοσία');
select pg_temp.as_user('kifisia@x.gr');
select pg_temp.expect_fail(format($$select sign_declaration('00000000-0000-0000-0000-000000000003', 'Ελένη Πέτρου', %L)$$, :'sig'), 'manager άλλου καταστήματος: όχι υπογραφή');
select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((select count(*) from decl_pdf_data(array['00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002']::uuid[], 'backup')), 2::bigint, 'ΓΔ: backup με PDF');
select pg_temp.eq((select count(*) from pdf_downloads), 2::bigint, 'κάθε λήψη PDF καταγράφεται (ποιος, πότε, ποιες δηλώσεις)');
-- αν η ΓΔ δώσει ρητά PDF στο HR από τον πίνακα, ο server το εφαρμόζει
select permissions_save('[{"role":"hr","perm":"payroll.pdf","allowed":true}]', null, 'Δοκιμή εκχώρησης');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((select count(*) from decl_pdf_data(array['00000000-0000-0000-0000-000000000001']::uuid[], 'single')), 1::bigint, 'ρητή εκχώρηση από τον πίνακα: ισχύει στον server');
select pg_temp.as_user('owner@x.gr');
select permissions_save('[{"role":"hr","perm":"payroll.pdf","allowed":false}]', null, 'Επαναφορά');

-- ═══════ Πεδίο καταστημάτων ═══════
select pg_temp.as_user('trainer@x.gr');
select pg_temp.eq((select count(*) from employees), 2::bigint, 'εκπαιδευτής: όλα τα καταστήματα (αρχική ρύθμιση)');
select pg_temp.as_user('owner@x.gr');
select permissions_save(null, '{"accounting":"own_store"}', 'Δοκιμή πεδίου');
select pg_temp.as_user('acc@x.gr');
select pg_temp.eq((select count(*) from declarations), 0::bigint, 'πεδίο «μόνο το κατάστημά του» για χρήστη χωρίς κατάστημα: τίποτα');
select pg_temp.as_user('owner@x.gr');
select permissions_save(null, '{"accounting":"all"}', 'Επαναφορά');
select pg_temp.eq((select count(*) from permission_log where perm is null), 2::bigint, 'ιστορικό αλλαγών πεδίου καταστημάτων');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
