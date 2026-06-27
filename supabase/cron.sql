-- ============================================================================
-- Schedule the emergency sender to run every minute.
-- Run AFTER you have deployed the `send-emergency` Edge Function.
-- Replace <PROJECT_REF> and <SERVICE_ROLE_KEY> with your values.
-- ============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'cortex-send-emergency',
  '* * * * *',                              -- every minute
  $$
  select net.http_post(
    url     := 'https://lrzvmzkrtwawpiqxrkik.functions.supabase.co/send-emergency',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      -- Paste your project's service_role key here (Supabase ▸ Settings ▸ API).
      -- NEVER commit the real key — this repo is public.
      'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- To remove later:  select cron.unschedule('cortex-send-emergency');
