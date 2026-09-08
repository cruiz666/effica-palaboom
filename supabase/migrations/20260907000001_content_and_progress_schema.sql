create extension if not exists pgcrypto;

create table languages (
  code text primary key,
  name text not null
);

create table courses (
  id uuid primary key default gen_random_uuid(),
  source_language text not null references languages(code),
  target_language text not null references languages(code),
  title text not null,
  status text not null default 'draft' check (status in ('draft', 'published')),
  created_at timestamptz not null default now()
);

create table units (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references courses(id) on delete cascade,
  cefr_level text not null,
  title text not null,
  sort_order int not null,
  status text not null default 'draft' check (status in ('draft', 'published'))
);

create table lessons (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id) on delete cascade,
  title text not null,
  sort_order int not null
);

create table learning_items (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references courses(id) on delete cascade,
  item_type text not null check (item_type in ('vocab', 'grammar')),
  value text not null,
  translation text not null
);

create table exercises (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references lessons(id) on delete cascade,
  sort_order int not null,
  type text not null,
  content jsonb not null,
  correct_answer jsonb not null
);

create table exercise_learning_items (
  exercise_id uuid not null references exercises(id) on delete cascade,
  learning_item_id uuid not null references learning_items(id) on delete cascade,
  primary key (exercise_id, learning_item_id)
);

create table user_lesson_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id uuid not null references lessons(id) on delete cascade,
  score numeric not null,
  completed_at timestamptz not null default now()
);

alter table courses enable row level security;
alter table units enable row level security;
alter table lessons enable row level security;
alter table exercises enable row level security;
alter table learning_items enable row level security;
alter table exercise_learning_items enable row level security;
alter table user_lesson_progress enable row level security;

create policy "Published courses are readable by anyone"
  on courses for select using (status = 'published');

create policy "Published units are readable by anyone"
  on units for select using (status = 'published');

create policy "Lessons are readable by anyone"
  on lessons for select using (true);

create policy "Exercises are readable by anyone"
  on exercises for select using (true);

create policy "Learning items are readable by anyone"
  on learning_items for select using (true);

create policy "Exercise learning item links are readable by anyone"
  on exercise_learning_items for select using (true);

create policy "Users can view their own progress"
  on user_lesson_progress for select using (auth.uid() = user_id);

create policy "Users can insert their own progress"
  on user_lesson_progress for insert with check (auth.uid() = user_id);

create or replace function get_active_course()
returns jsonb
language sql
stable
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
                'correctAnswer', e.correct_answer
              ) order by e.sort_order)
              from exercises e where e.lesson_id = l.id
            ), '[]'::jsonb)
          ) order by l.sort_order)
          from lessons l where l.unit_id = u.id
        ), '[]'::jsonb)
      ) order by u.sort_order)
      from units u where u.course_id = c.id and u.status = 'published'
    ), '[]'::jsonb)
  )
  from courses c
  where c.status = 'published'
  order by c.created_at
  limit 1;
$$;

grant execute on function get_active_course() to anon, authenticated;
