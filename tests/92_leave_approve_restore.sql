\set ON_ERROR_STOP 1
-- Απόφαση 21/11/2026: η έγκριση ημερών άδειας λειτουργεί όπως στην 3.0 (χρέωση από το σύστημα εργασίας, χωρίς
-- υποχρεωτική αιτιολογία ή διόρθωση των ημερών του manager). Μόνη προσθήκη: έγκριση όλων ή μόνο συγκεκριμένων ημερομηνιών.
-- Έλεγχος ότι δεν γίνεται διπλή αφαίρεση υπολοίπου. ΟΛΑ ΤΑ ΣΤΟΙΧΕΙΑ ΕΙΝΑΙ ΕΙΚΟΝΙΚΑ.
insert into app_users(email,name,role,store) values
 ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('glyfada@x.gr','Manager Γλυφάδας','manager','Γλυφάδα');
insert into employees(code,first,last,store,company,specialty,work_week,hire_date) values
 ('A1','Νίκος','Αλεξίου','Γλυφάδα','BEST GREEK GYMS IKE','Ρεσεψιόν',5,'2024-03-16');

create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.ver(p uuid) returns int language sql as $$ select version from hr_requests where id = p $$;
create or replace function pg_temp.leave(s date, e date, n text) returns uuid language plpgsql as $$
declare v uuid;
begin
  v := (req_create(jsonb_build_object('category','leave','employee_code','A1','entry_mode','manager_record','leave_type','annual',
        'start_date',s,'end_date',e,'days_requested',n,'body','Παρακαλώ να εγκρίνετε την άδεια του εργαζομένου.'))->>'id')::uuid;
  perform req_submit(v, 1);
  return v;
end $$;
create or replace function pg_temp.active(p uuid) returns text language sql as $$
  select coalesce(string_agg(to_char(day, 'DD/MM'), ',' order by day), '') from leave_days where request_id = p and status = 'active' $$;
create or replace function pg_temp.charged(p uuid) returns numeric language sql as $$
  select coalesce(sum(c.amount), 0) from leave_charges c join leave_days d on d.id = c.leave_day_id where d.request_id = p and d.status = 'active' $$;

select pg_temp.as_user('hr@x.gr');
select leave_apply_bases('A1');
select (leave_balance_calc('A1', '2026-12-31')->>'taken')::numeric as taken0 \gset

-- ═══ 1. Παρασκευή–Σάββατο σε πενθήμερο: εγκρίνεται κανονικά, 2 ημερομηνίες, χρέωση 1 ημέρα ═══
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.leave('2026-12-04', '2026-12-05', '2') as fs \gset
select pg_temp.as_user('hr@x.gr');
select req_decide(:'fs', 'approve', '{"message":"Το αίτημά σας για κανονική άδεια εγκρίθηκε."}', pg_temp.ver(:'fs'));
select pg_temp.eq((select status from hr_requests where id = :'fs'), 'approved', 'εγκρίθηκε χωρίς αιτιολογία και χωρίς διόρθωση των 2 ημερών του manager');
select pg_temp.eq(pg_temp.active(:'fs'), '04/12,05/12', 'καταγράφονται και οι δύο ημερομηνίες');
select pg_temp.eq(pg_temp.charged(:'fs'), 1.00, 'χρεώνεται 1 ημέρα (το Σάββατο δεν είναι εργάσιμη σε πενθήμερο)');
select pg_temp.eq((select approved_days || '|' || jsonb_array_length(approved_dates) || '|' || (diff_reason is null) from hr_decisions where request_id = :'fs' and superseded_at is null),
  '1.0|2|true', 'απόφαση: 1 ημέρα χρέωσης, 2 εγκεκριμένες ημερομηνίες, καμία «διαφοροποίηση»');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from notifications where request_id = :'fs' and title like '%μόνο ορισμένες%'), 0::bigint, 'ο manager δεν βλέπει ένδειξη τμηματικής έγκρισης');

-- ═══ 2. Τμηματική έγκριση εκκρεμούς αιτήματος (χωρίς προηγούμενη πλήρη έγκριση, χωρίς αιτιολογία) ═══
select pg_temp.leave('2026-12-07', '2026-12-10', '4') as pt \gset
select pg_temp.as_user('hr@x.gr');
select req_decide(:'pt', 'approve', '{"message":"Εγκρίνεται η άδεια για τις 7 και 9 Δεκεμβρίου.","include":["2026-12-07","2026-12-09"]}', pg_temp.ver(:'pt'));
select pg_temp.eq(pg_temp.active(:'pt'), '07/12,09/12', 'μόνο οι επιλεγμένες ημερομηνίες καταγράφονται ως ληφθείσες');
select pg_temp.eq(pg_temp.charged(:'pt'), 2.00, 'αφαιρούνται 2 ημέρες, μία φορά');
select pg_temp.eq((select approved_days || '|' || jsonb_array_length(approved_dates) from hr_decisions where request_id = :'pt' and superseded_at is null), '2.0|2', 'απόφαση με 2 ημέρες');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select count(*) from notifications where request_id = :'pt' and title like '%εγκρίθηκαν μόνο ορισμένες από τις αιτούμενες ημερομηνίες%'), 1::bigint, 'ο manager ενημερώνεται ότι εγκρίθηκαν μόνο ορισμένες');
select pg_temp.as_user('hr@x.gr');
select pg_temp.eq((leave_balance_calc('A1', '2026-12-31')->>'taken')::numeric - :taken0, 3.00, 'υπόλοιπο: ληφθείσες 1 + 2 = 3');

-- ═══ 3. Αναθεώρηση από ΓΔ: πλήρης → τμηματική → πλήρης, χωρίς διπλή αφαίρεση ═══
select pg_temp.as_user('owner@x.gr');
select req_decide(:'pt', 'approve', '{"message":"Εγκρίνεται τελικά όλο το διάστημα."}', pg_temp.ver(:'pt'));
select pg_temp.eq(pg_temp.active(:'pt') || ' / ' || pg_temp.charged(:'pt'), '07/12,08/12,09/12,10/12 / 4.00', 'αναθεώρηση σε πλήρη: 4 ημέρες (όχι 2 + 4)');
select req_decide(:'pt', 'approve', '{"message":"Εγκρίνεται μόνο η 8η Δεκεμβρίου.","include":["2026-12-08"]}', pg_temp.ver(:'pt'));
select pg_temp.eq(pg_temp.active(:'pt') || ' / ' || pg_temp.charged(:'pt'), '08/12 / 1.00', 'αναθεώρηση σε τμηματική: 1 ημέρα');
select pg_temp.eq((select count(*) from leave_days where request_id = :'pt' and status = 'active'), 1::bigint, 'καμία διπλή ενεργή ημέρα');
select pg_temp.eq(leave_charged('A1', 2026), 2.00, 'σύνολο χρεώσεων 2026: 1 (Παρ–Σαβ) + 1 = 2');
select pg_temp.eq((leave_balance_calc('A1', '2026-12-31')->>'taken')::numeric - :taken0, 2.00, 'το υπόλοιπο μειώθηκε συνολικά κατά 2 ημέρες');
select pg_temp.eq((select count(*) from hr_decisions where request_id = :'pt'), 3::bigint, 'κρατιέται όλο το ιστορικό αποφάσεων');

-- ═══ 4. Ξανά η ίδια πλήρης έγκριση δεν αφαιρεί ξανά ═══
select req_decide(:'fs', 'approve', '{"message":"Επιβεβαίωση έγκρισης Παρασκευής–Σαββάτου."}', pg_temp.ver(:'fs'));
select pg_temp.eq(pg_temp.charged(:'fs') || '|' || leave_charged('A1', 2026), '1.00|2.00', 'επανάληψη έγκρισης: καμία επιπλέον αφαίρεση');

reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
