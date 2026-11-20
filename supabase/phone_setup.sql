-- Phone control setup (run once in Supabase). Only adds the secret the access pass is signed with.
insert into app_secrets(key, value)
values ('phone_secret', replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''))
on conflict (key) do nothing;
