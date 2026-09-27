create table user_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'inactive' check (status in ('inactive', 'active', 'cancelled')),
  product_id text,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table user_subscriptions enable row level security;

-- Solo lectura para el propio usuario. Deliberadamente sin políticas de
-- insert/update/delete para 'authenticated' — todas las escrituras reales
-- pasan por el rol de servicio (la Edge Function del webhook de RevenueCat),
-- nunca por REST directo del cliente. Esto es lo que evita que un usuario se
-- autootorgue "premium" con una llamada directa a la tabla.
create policy "Users can view their own subscription state"
  on user_subscriptions for select using (auth.uid() = user_id);

create or replace function get_entitlement_state()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'isPremium', exists (
      select 1 from public.user_subscriptions
      where user_id = auth.uid()
        and status = 'active'
        and expires_at > now()
    ),
    'freeLessonsUsedToday', (
      select count(*)::int from public.user_lesson_progress
      where user_id = auth.uid()
        and completed_at::date = current_date
    ),
    'freeLessonsLimit', 3
  );
$$;

grant execute on function get_entitlement_state() to authenticated;

-- TEMPORAL, SOLO DESARROLLO. Otorga premium sin ninguna verificación de pago
-- real — necesario porque no existen cuentas de Apple/Google Developer
-- todavía, así que no hay forma de que un webhook real de RevenueCat
-- dispare esta escritura. security definer (a diferencia del resto de las
-- funciones del proyecto, que son security invoker) porque su propósito
-- explícito es escribir una fila que la política RLS de arriba no permite
-- escribir directamente al usuario autenticado.
--
-- DEBE eliminarse o deshabilitarse antes de publicar la app en una tienda
-- real — cualquier usuario autenticado puede llamarla para obtener premium
-- gratis, sin pagar nada.
create or replace function dev_mock_activate_subscription()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  insert into public.user_subscriptions (user_id, status, product_id, expires_at, updated_at)
  values (v_user_id, 'active', 'dev_mock_monthly', now() + interval '30 days', now())
  on conflict (user_id) do update set
    status = 'active',
    product_id = 'dev_mock_monthly',
    expires_at = now() + interval '30 days',
    updated_at = now();
end;
$$;

grant execute on function dev_mock_activate_subscription() to authenticated;
