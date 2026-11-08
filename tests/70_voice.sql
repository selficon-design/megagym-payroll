\set ON_ERROR_STOP 1
-- Φωνή ElevenLabs: το κλειδί δεν διαβάζεται ποτέ από την εφαρμογή· μόνο η ΓΔ το ορίζει / επιλέγει φωνή.
insert into app_users(email,name,role,store) values ('owner@x.gr','ΓΔ','owner',null),('hr@x.gr','HR','hr',null),('glyfada@x.gr','Manager','manager','Γλυφάδα');
create or replace function pg_temp.as_user(e text) returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', json_build_object('email',e)::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.as_anon() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claims', '{}', false); execute 'set role anon'; end $$;
create or replace function pg_temp.eq(a anyelement, b anyelement, label text) returns void language plpgsql as $$
begin if a is distinct from b then raise exception 'ΑΠΟΤΥΧΙΑ % : % != %', label, a, b; end if; raise notice 'OK %', label; end $$;
create or replace function pg_temp.expect_fail(q text, label text) returns void language plpgsql as $$
begin execute q; raise exception 'ΑΠΟΤΥΧΙΑ: έπρεπε να μπλοκαριστεί: %', label;
exception when others then if sqlerrm like 'ΑΠΟΤΥΧΙΑ%' then raise; end if; raise notice 'OK μπλοκαρίστηκε (%): %', label, sqlerrm; end $$;

select pg_temp.as_user('owner@x.gr');
select pg_temp.eq((voice_key_status())->>'configured', 'false', 'αρχικά χωρίς κλειδί');
select pg_temp.expect_fail($$select voice_set('elevenlabs', 'abc123def456', 'Μαρία', null)$$, 'ElevenLabs χωρίς κλειδί');
select pg_temp.expect_fail($$select voice_set_key('short')$$, 'μη έγκυρο κλειδί');
select voice_set_key('sk_test_0123456789abcdef0123456789abcdef');
select pg_temp.eq((voice_key_status())->>'configured', 'true', 'το κλειδί αποθηκεύτηκε');
select pg_temp.eq(voice_key_status()::text like '%0123456789abcdef%', false, 'η κατάσταση δεν επιστρέφει ποτέ το κλειδί');
select pg_temp.expect_fail($$select * from app_secrets$$, 'ούτε η ΓΔ διαβάζει το κλειδί από την εφαρμογή');
select pg_temp.expect_fail($$select voice_set('elevenlabs', null, null, null)$$, 'ElevenLabs χωρίς φωνή');
select voice_set('elevenlabs', 'abc123def456', 'Μαρία', 'eleven_flash_v2_5');
select pg_temp.expect_fail($$update voice_settings set provider = 'browser'$$, 'καμία απευθείας αλλαγή ρυθμίσεων');
select pg_temp.as_user('glyfada@x.gr');
select pg_temp.eq((select provider || '|' || voice_name from voice_settings), 'elevenlabs|Μαρία', 'κάθε χρήστης βλέπει ποια φωνή χρησιμοποιεί ο Βοηθός');
select pg_temp.expect_fail($$select * from app_secrets$$, 'manager: καμία πρόσβαση στο κλειδί');
select pg_temp.expect_fail($$select voice_set_key('sk_test_99999999999999999999999999')$$, 'manager δεν αλλάζει το κλειδί');
select pg_temp.expect_fail($$select voice_set('browser', null, null, null)$$, 'manager δεν αλλάζει φωνή');
select pg_temp.eq(voice_key_status(), null::jsonb, 'manager δεν βλέπει κατάσταση κλειδιού');
select pg_temp.as_user('hr@x.gr');
select pg_temp.expect_fail($$select voice_set_key('sk_test_99999999999999999999999999')$$, 'HR δεν αλλάζει το κλειδί');
select pg_temp.as_anon();
select pg_temp.expect_fail($$select * from voice_settings$$, 'χωρίς σύνδεση: καμία πρόσβαση');
select pg_temp.expect_fail($$select voice_key_status()$$, 'χωρίς σύνδεση: καμία κλήση');
select pg_temp.as_user('owner@x.gr');
select voice_set_key('');
select pg_temp.eq((select provider from voice_settings), 'browser', 'διαγραφή κλειδιού → επιστροφή στη φωνή της συσκευής');
reset role;
\echo ΟΛΑ ΤΑ TESTS ΠΕΡΑΣΑΝ
