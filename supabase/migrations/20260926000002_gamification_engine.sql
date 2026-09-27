create table user_gamification_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  xp_total int not null default 0,
  current_streak int not null default 0,
  longest_streak int not null default 0,
  last_activity_date date
);

alter table user_gamification_state enable row level security;

create policy "Users can view their own gamification state"
  on user_gamification_state for select using (auth.uid() = user_id);

create policy "Users can insert their own gamification state"
  on user_gamification_state for insert with check (auth.uid() = user_id);

create policy "Users can update their own gamification state"
  on user_gamification_state for update using (auth.uid() = user_id);

create or replace function add_xp(p_amount int)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  insert into public.user_gamification_state (user_id, xp_total)
  values (v_user_id, p_amount)
  on conflict (user_id) do update set
    xp_total = public.user_gamification_state.xp_total + p_amount;
end;
$$;

grant execute on function add_xp(int) to authenticated;

create or replace function record_activity()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_current_streak int;
  v_longest_streak int;
  v_last_activity_date date;
  v_new_streak int;
begin
  select current_streak, longest_streak, last_activity_date
    into v_current_streak, v_longest_streak, v_last_activity_date
    from public.user_gamification_state
    where user_id = v_user_id;

  if not found then
    v_current_streak := 0;
    v_longest_streak := 0;
    v_last_activity_date := null;
  end if;

  if v_last_activity_date is null or v_last_activity_date < current_date - 1 then
    v_new_streak := 1;
  elsif v_last_activity_date = current_date - 1 then
    v_new_streak := v_current_streak + 1;
  else
    -- v_last_activity_date = current_date: ya se registró actividad hoy.
    v_new_streak := v_current_streak;
  end if;

  insert into public.user_gamification_state
    (user_id, xp_total, current_streak, longest_streak, last_activity_date)
  values
    (v_user_id, 0, v_new_streak, greatest(v_longest_streak, v_new_streak), current_date)
  on conflict (user_id) do update set
    current_streak = v_new_streak,
    longest_streak = greatest(public.user_gamification_state.longest_streak, v_new_streak),
    last_activity_date = current_date;
end;
$$;

grant execute on function record_activity() to authenticated;

create or replace function get_gamification_state()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'xpTotal', coalesce(s.xp_total, 0),
    'currentStreak', coalesce(s.current_streak, 0),
    'longestStreak', coalesce(s.longest_streak, 0),
    'level', coalesce(s.xp_total, 0) / 100 + 1
  )
  from (values (1)) as one_row(x)
  left join public.user_gamification_state s on s.user_id = auth.uid();
$$;

grant execute on function get_gamification_state() to authenticated;
