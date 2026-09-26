create table user_learning_item_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  learning_item_id uuid not null references learning_items(id) on delete cascade,
  ease_factor numeric not null default 2.5,
  repetitions int not null default 0,
  interval_days int not null default 0,
  next_review_date date not null default current_date,
  last_reviewed_at timestamptz,
  primary key (user_id, learning_item_id)
);

alter table user_learning_item_progress enable row level security;

create policy "Users can view their own learning item progress"
  on user_learning_item_progress for select using (auth.uid() = user_id);

create policy "Users can insert their own learning item progress"
  on user_learning_item_progress for insert with check (auth.uid() = user_id);

create policy "Users can update their own learning item progress"
  on user_learning_item_progress for update using (auth.uid() = user_id);

create or replace function update_learning_item_progress(p_learning_item_id uuid, p_correct boolean)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_ease_factor numeric;
  v_repetitions int;
  v_interval_days int;
begin
  select ease_factor, repetitions, interval_days
    into v_ease_factor, v_repetitions, v_interval_days
    from public.user_learning_item_progress
    where user_id = v_user_id and learning_item_id = p_learning_item_id;

  if not found then
    v_ease_factor := 2.5;
    v_repetitions := 0;
    v_interval_days := 0;
  end if;

  if p_correct then
    v_repetitions := v_repetitions + 1;
    v_interval_days := case
      when v_repetitions = 1 then 1
      when v_repetitions = 2 then 6
      else round(v_interval_days * v_ease_factor)::int
    end;
    v_ease_factor := least(v_ease_factor + 0.05, 2.8);
  else
    v_repetitions := 0;
    v_interval_days := 1;
    v_ease_factor := greatest(v_ease_factor - 0.2, 1.3);
  end if;

  insert into public.user_learning_item_progress
    (user_id, learning_item_id, ease_factor, repetitions, interval_days, next_review_date, last_reviewed_at)
  values
    (v_user_id, p_learning_item_id, v_ease_factor, v_repetitions, v_interval_days,
     current_date + v_interval_days, now())
  on conflict (user_id, learning_item_id) do update set
    ease_factor = excluded.ease_factor,
    repetitions = excluded.repetitions,
    interval_days = excluded.interval_days,
    next_review_date = excluded.next_review_date,
    last_reviewed_at = excluded.last_reviewed_at;
end;
$$;

grant execute on function update_learning_item_progress(uuid, boolean) to authenticated;

create or replace function get_due_learning_items()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with due as (
    select distinct on (uilp.learning_item_id)
      uilp.learning_item_id,
      uilp.next_review_date,
      e.id as exercise_id,
      e.type,
      e.content,
      e.correct_answer,
      e.sort_order
    from public.user_learning_item_progress uilp
    join public.exercise_learning_items eli on eli.learning_item_id = uilp.learning_item_id
    join public.exercises e on e.id = eli.exercise_id
    where uilp.user_id = auth.uid()
      and uilp.next_review_date <= current_date
    order by uilp.learning_item_id, e.sort_order
  ),
  ranked as (
    select
      exercise_id,
      type,
      content,
      correct_answer,
      learning_item_id,
      next_review_date,
      row_number() over (order by next_review_date) as sort_order
    from due
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', exercise_id,
    'sortOrder', sort_order,
    'type', type,
    'content', content,
    'correctAnswer', correct_answer,
    'learningItemIds', jsonb_build_array(learning_item_id)
  )), '[]'::jsonb)
  from ranked;
$$;

grant execute on function get_due_learning_items() to authenticated;

create or replace function get_unit_progress_summary()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'unitId', u.id,
    'unitTitle', u.title,
    'totalLessons', lesson_counts.total_lessons,
    'completedLessons', coalesce(progress_counts.completed_lessons, 0),
    'totalLearningItems', item_counts.total_items,
    'learnedItems', coalesce(item_progress.learned_items, 0),
    'dueTodayItems', coalesce(item_progress.due_today_items, 0)
  ) order by u.sort_order), '[]'::jsonb)
  from public.units u
  join public.courses c on c.id = u.course_id
  left join lateral (
    select count(*) as total_lessons from public.lessons l where l.unit_id = u.id
  ) lesson_counts on true
  left join lateral (
    select count(distinct ulp.lesson_id) as completed_lessons
    from public.user_lesson_progress ulp
    join public.lessons l on l.id = ulp.lesson_id
    where l.unit_id = u.id and ulp.user_id = auth.uid()
  ) progress_counts on true
  left join lateral (
    select count(distinct eli.learning_item_id) as total_items
    from public.exercise_learning_items eli
    join public.exercises e on e.id = eli.exercise_id
    join public.lessons l on l.id = e.lesson_id
    where l.unit_id = u.id
  ) item_counts on true
  left join lateral (
    select
      count(distinct uilp.learning_item_id) filter (where uilp.repetitions >= 2) as learned_items,
      count(distinct uilp.learning_item_id) filter (where uilp.next_review_date <= current_date) as due_today_items
    from public.user_learning_item_progress uilp
    join public.exercise_learning_items eli on eli.learning_item_id = uilp.learning_item_id
    join public.exercises e on e.id = eli.exercise_id
    join public.lessons l on l.id = e.lesson_id
    where l.unit_id = u.id and uilp.user_id = auth.uid()
  ) item_progress on true
  where u.status = 'published' and c.status = 'published';
$$;

grant execute on function get_unit_progress_summary() to authenticated;

create or replace function get_active_course()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id,
    'title', c.title,
    'units', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id,
        'title', u.title,
        'cefrLevel', u.cefr_level,
        'sortOrder', u.sort_order,
        'lessons', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', l.id,
            'title', l.title,
            'sortOrder', l.sort_order,
            'exercises', coalesce((
              select jsonb_agg(jsonb_build_object(
                'id', e.id,
                'sortOrder', e.sort_order,
                'type', e.type,
                'content', e.content,
                'correctAnswer', e.correct_answer,
                'learningItemIds', coalesce((
                  select jsonb_agg(eli.learning_item_id)
                  from public.exercise_learning_items eli
                  where eli.exercise_id = e.id
                ), '[]'::jsonb)
              ) order by e.sort_order)
              from public.exercises e where e.lesson_id = l.id
            ), '[]'::jsonb)
          ) order by l.sort_order)
          from public.lessons l where l.unit_id = u.id
        ), '[]'::jsonb)
      ) order by u.sort_order)
      from public.units u where u.course_id = c.id and u.status = 'published'
    ), '[]'::jsonb)
  )
  from public.courses c
  where c.status = 'published'
  order by c.created_at
  limit 1;
$$;
