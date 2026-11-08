-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEGA GYM · Φωνή ElevenLabs για τον Βοηθό AI (έκδοση 2.5)
-- Το κλειδί API το επικολλά η Γενική Διευθύντρια μέσα στην εφαρμογή. Φυλάσσεται σε πίνακα χωρίς ΚΑΜΙΑ πρόσβαση
-- από την εφαρμογή· το διαβάζει μόνο η λειτουργία του server «tts» (service role). Ποτέ δεν επιστρέφεται.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

create table public.app_secrets (
  name       text primary key check (name in ('elevenlabs_api_key')),
  value      text not null,
  updated_by text not null,
  updated_at timestamptz not null default now()
);
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;

-- Ρυθμίσεις φωνής (όχι μυστικές): ποια φωνή/μοντέλο χρησιμοποιεί ο Βοηθός για όλους
create table public.voice_settings (
  id         int primary key default 1 check (id = 1),
  provider   text not null default 'browser' check (provider in ('browser','elevenlabs')),
  voice_id   text,
  voice_name text,
  model      text not null default 'eleven_multilingual_v2',
  updated_by text,
  updated_at timestamptz not null default now()
);
insert into public.voice_settings(id) values (1);
alter table public.voice_settings enable row level security;
create policy vs_read on public.voice_settings for select to authenticated using (public.my_role() is not null);
revoke all on public.voice_settings from anon, authenticated;
grant select on public.voice_settings to authenticated;

-- Αποθήκευση / διαγραφή κλειδιού (μόνο ΓΔ). Επιστρέφει μόνο ότι ορίστηκε.
create or replace function public.voice_set_key(p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_key text := nullif(trim(coalesce(p_key, '')), '');
begin
  perform public.require_role(array['owner']);
  if v_key is null then
    delete from public.app_secrets where name = 'elevenlabs_api_key';
    update public.voice_settings set provider = 'browser', updated_by = public.current_email(), updated_at = now() where id = 1;
    return jsonb_build_object('ok', true, 'configured', false);
  end if;
  if length(v_key) < 20 or length(v_key) > 200 or v_key ~ '\s' then raise exception 'Το κλειδί δεν μοιάζει με κλειδί ElevenLabs.'; end if;
  insert into public.app_secrets(name, value, updated_by) values ('elevenlabs_api_key', v_key, public.current_email())
  on conflict (name) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('ok', true, 'configured', true);
end $$;

create or replace function public.voice_key_status()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('configured', exists (select 1 from public.app_secrets where name = 'elevenlabs_api_key'),
    'updated_at', (select updated_at from public.app_secrets where name = 'elevenlabs_api_key'),
    'updated_by', (select updated_by from public.app_secrets where name = 'elevenlabs_api_key'))
  where public.my_role() = 'owner'
$$;

-- Επιλογή φωνής για όλους τους χρήστες του Βοηθού (μόνο ΓΔ)
create or replace function public.voice_set(p_provider text, p_voice_id text, p_voice_name text, p_model text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(array['owner']);
  if p_provider not in ('browser','elevenlabs') then raise exception 'Μη έγκυρη επιλογή.'; end if;
  if p_provider = 'elevenlabs' and not exists (select 1 from public.app_secrets where name = 'elevenlabs_api_key') then
    raise exception 'Πρώτα αποθηκεύστε το κλειδί ElevenLabs.';
  end if;
  if p_provider = 'elevenlabs' and nullif(trim(coalesce(p_voice_id, '')), '') is null then raise exception 'Διαλέξτε φωνή.'; end if;
  if coalesce(p_model, 'eleven_multilingual_v2') !~ '^[a-z0-9_]{3,60}$' then raise exception 'Μη έγκυρο μοντέλο.'; end if;
  update public.voice_settings set provider = p_provider, voice_id = nullif(trim(coalesce(p_voice_id, '')), ''),
         voice_name = left(nullif(trim(coalesce(p_voice_name, '')), ''), 120), model = coalesce(p_model, 'eleven_multilingual_v2'),
         updated_by = public.current_email(), updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.voice_set_key(text), public.voice_key_status(), public.voice_set(text, text, text, text) to authenticated;
grant execute on function public.link_get(text), public.link_save(text, jsonb), public.link_submit(text, jsonb) to anon;
grant execute on function public.fill_get(text), public.fill_save_request(text, jsonb), public.fill_attach(text, text, text, text),
  public.fill_finish_request(text), public.fill_save_answers(text, jsonb), public.fill_submit_assessment(text, jsonb) to anon;
