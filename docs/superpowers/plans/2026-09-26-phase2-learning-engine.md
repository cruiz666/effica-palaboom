# Fase 2 — Motor de Aprendizaje: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dos ejercicios nuevos (completar espacio, ordenar palabras), repetición espaciada real (variante de SM-2) que se actualiza en cualquier ejercicio respondido — lección fija o repaso —, una sección "Repaso" en la pantalla del curso, y una pantalla de progreso de solo lectura por unidad.

**Architecture:** Se extiende el motor de la Fase 1 sin tocar decisiones de stack. El scheduling SM-2 vive en una función SQL (`update_learning_item_progress`), no duplicado en Dart. Los ejercicios nuevos comparten la interfaz `{exercise, onAnswered}` de `MultipleChoiceExercise`; un selector (`buildExerciseWidget`) elige el widget según `exercise.type`, reusado tanto por `LessonScreen` como por la nueva `ReviewSessionScreen`.

**Tech Stack:** Igual que Fase 1 — Flutter 3.24.5 (macOS 13 pinned), Supabase (Postgres + Auth), `supabase_flutter`, `shared_preferences`.

## Global Constraints

- Todo lo de la Fase 1 sigue vigente: un solo código Flutter, backend único Supabase, tema Midnight Teal, tono adulto, un solo curso activo, contenido editado directo en Supabase (sin CMS).
- El cálculo de repetición espaciada vive en SQL (`update_learning_item_progress`), no se reimplementa en Dart.
- El estado SRS de un `LearningItem` se actualiza al responder **cualquier** ejercicio que lo practique — en una lección fija o en una sesión de Repaso —, no solo en Repaso.
- Los ejercicios nuevos (`fill_blank`, `word_order`) se resuelven tocando opciones, nunca con entrada de texto libre.
- En `LessonScreen`, si falla la actualización de estado SRS de un ejercicio, no debe bloquear ni mostrar error al usuario — es una mejora de fondo, no la señal de finalización de la lección (esa sigue siendo `submitLessonResult`). En `ReviewSessionScreen`, en cambio, si falla sí se muestra un error — ahí actualizar el SRS **es** el propósito de la pantalla.

---

## File Structure

**Backend (Supabase):**
- `supabase/migrations/20260926000001_srs_engine.sql` — tabla `user_learning_item_progress` + RLS, funciones `update_learning_item_progress()`, `get_due_learning_items()`, `get_unit_progress_summary()`, y `create or replace` de `get_active_course()` agregando `learningItemIds` por ejercicio.
- `supabase/seed.sql` (modificado) — dos ejercicios nuevos (`fill_blank`, `word_order`) en la lección "Presentarse" (que en la Fase 1 quedó sin ejercicios a propósito), con sus `learning_items` y vínculos.

**App (Flutter, en `mobile/`):**
- `lib/features/content/models/exercise.dart` (modificado) — campo `learningItemIds`.
- `lib/features/lesson/widgets/fill_blank_exercise.dart` — nuevo widget.
- `lib/features/lesson/widgets/word_order_exercise.dart` — nuevo widget.
- `lib/features/lesson/exercise_widget_factory.dart` — selector de widget por `exercise.type`.
- `lib/features/lesson/lesson_screen.dart` (modificado) — usa el factory, emite `submitReviewResult` por ejercicio.
- `lib/features/srs/srs_repository.dart` — interfaz + `SupabaseSrsRepository`.
- `lib/features/srs/review_session_screen.dart` — sesión de repaso dinámica.
- `lib/features/course/course_screen.dart` (modificado) — tarjeta de Repaso, AppBar con acceso a progreso.
- `lib/features/progress/unit_progress_summary.dart` — modelo.
- `lib/features/progress/progress_summary_repository.dart` — interfaz + `SupabaseProgressSummaryRepository`.
- `lib/features/progress/progress_screen.dart` — pantalla de progreso.
- `lib/app.dart`, `lib/main.dart` (modificados) — wiring de los repositorios nuevos.
- Archivos de test espejo bajo `test/...` para cada archivo de lógica/widget nuevo o modificado.

---

### Task 1: Esquema SRS y actualización de `get_active_course()`

**Files:**
- Create: `supabase/migrations/20260926000001_srs_engine.sql`

**Interfaces:**
- Consumes: esquema de la Fase 1 (`learning_items`, `exercises`, `exercise_learning_items`, `lessons`, `units`, `courses`, `user_lesson_progress`).
- Produces: tabla `user_learning_item_progress`; funciones `update_learning_item_progress(p_learning_item_id uuid, p_correct boolean)`, `get_due_learning_items()` (retorna `jsonb`, mismo shape de ejercicio que `get_active_course()` más `learningItemIds`), `get_unit_progress_summary()` (retorna `jsonb`: `[{unitId, unitTitle, totalLessons, completedLessons, totalLearningItems, learnedItems, dueTodayItems}]`); `get_active_course()` actualizada con `learningItemIds` (array de uuids) por ejercicio.

- [ ] **Step 1: Verificar estado inicial**

Run:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\dt" | grep user_learning_item_progress
```
Expected: sin resultados (la tabla no existe todavía).

- [ ] **Step 2: Escribir la migración**

```sql
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
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', exercise_id,
    'sortOrder', row_number() over (order by next_review_date),
    'type', type,
    'content', content,
    'correctAnswer', correct_answer,
    'learningItemIds', jsonb_build_array(learning_item_id)
  )), '[]'::jsonb)
  from due;
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
    select count(*) as total_items from public.learning_items li where li.course_id = c.id
  ) item_counts on true
  left join lateral (
    select
      count(*) filter (where uilp.repetitions >= 2) as learned_items,
      count(*) filter (where uilp.next_review_date <= current_date) as due_today_items
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
```

- [ ] **Step 3: Aplicar y verificar**

Run:
```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\dt" | grep user_learning_item_progress
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\df get_due_learning_items"
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\df get_unit_progress_summary"
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select get_active_course();"
```
Expected: la tabla y ambas funciones existen; `get_active_course()` sigue retornando el curso sembrado, y cada ejercicio ahora incluye `"learningItemIds"` (será `[]` hasta la Tarea 2, ya que el seed actual de la Fase 1 no linkea `exercise_learning_items` para esos dos ejercicios existentes — verifica que al menos la clave esté presente y sea un array).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260926000001_srs_engine.sql
git commit -m "feat: add SRS schema, scheduling functions, and learningItemIds to get_active_course()"
```

---

### Task 2: Contenido semilla — ejercicios `fill_blank` y `word_order`

**Files:**
- Modify: `supabase/seed.sql`

**Interfaces:**
- Consumes: esquema de Task 1.
- Produces: dos `learning_items` nuevos, dos `exercises` (uno `fill_blank`, uno `word_order`) en la lección `44444444-4444-4444-4444-444444444444` ("Presentarse"), y sus filas en `exercise_learning_items`.

- [ ] **Step 1: Verificar que "Presentarse" sigue sin ejercicios**

Run:
```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select count(*) from exercises where lesson_id = '44444444-4444-4444-4444-444444444444';"
```
Expected: `0`.

- [ ] **Step 2: Agregar el contenido al final de `supabase/seed.sql`**

```sql
insert into learning_items (id, course_id, item_type, value, translation) values
  ('99999999-9999-9999-9999-999999999999', '11111111-1111-1111-1111-111111111111', 'vocab', 'name', 'nombre'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'grammar', 'My name is', 'Me llamo');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 1, 'fill_blank',
   '{"prompt": "What is your ___?", "options": ["name", "goodbye", "please"]}'::jsonb,
   '"name"'::jsonb),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '44444444-4444-4444-4444-444444444444', 2, 'word_order',
   '{"words": ["is", "My", "Ana", "name"]}'::jsonb,
   '"My name is Ana"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '99999999-9999-9999-9999-999999999999'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
```

- [ ] **Step 3: Verificar**

Run:
```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select get_active_course();"
```
Expected: la lección "Presentarse" ahora trae 2 ejercicios (`fill_blank` con `correctAnswer: "name"`, `word_order` con `correctAnswer: "My name is Ana"`), cada uno con `learningItemIds` conteniendo un uuid (no vacío).

- [ ] **Step 4: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat: seed fill_blank and word_order exercises in Presentarse lesson"
```

---

### Task 3: Modelo `Exercise` — soporte para `learningItemIds`

**Files:**
- Modify: `mobile/lib/features/content/models/exercise.dart`
- Test: `mobile/test/features/content/models/exercise_test.dart`

**Interfaces:**
- Consumes: forma JSON producida por `get_active_course()`/`get_due_learning_items()` (Task 1).
- Produces: `Exercise` con campo nuevo `List<String> learningItemIds` (default `[]` si la clave JSON no está presente — mantiene compatibilidad con fixtures existentes de la Fase 1 que no la incluyen).

- [ ] **Step 1: Escribir el test (falla porque el campo no existe)**

`mobile/test/features/content/models/exercise_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';

void main() {
  test('Exercise.fromJson parses learningItemIds when present', () {
    final exercise = Exercise.fromJson({
      'id': 'ex-1',
      'sortOrder': 1,
      'type': 'fill_blank',
      'content': {'prompt': 'x', 'options': <String>[]},
      'correctAnswer': 'x',
      'learningItemIds': ['li-1', 'li-2'],
    });

    expect(exercise.learningItemIds, ['li-1', 'li-2']);
  });

  test('Exercise.fromJson defaults learningItemIds to empty when absent', () {
    final exercise = Exercise.fromJson({
      'id': 'ex-1',
      'sortOrder': 1,
      'type': 'multiple_choice',
      'content': {'prompt': 'x', 'options': <String>[]},
      'correctAnswer': 'x',
    });

    expect(exercise.learningItemIds, isEmpty);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/content/models/exercise_test.dart` (dentro de `mobile/`)
Expected: FAIL — `The named parameter 'learningItemIds' isn't defined` o similar, ya que el test usa `exercise.learningItemIds` que no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/content/models/exercise.dart` (reemplaza el archivo completo):
```dart
class Exercise {
  const Exercise({
    required this.id,
    required this.sortOrder,
    required this.type,
    required this.content,
    required this.correctAnswer,
    this.learningItemIds = const [],
  });

  final String id;
  final int sortOrder;
  final String type;
  final Map<String, dynamic> content;
  final dynamic correctAnswer;
  final List<String> learningItemIds;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      sortOrder: json['sortOrder'] as int,
      type: json['type'] as String,
      content: Map<String, dynamic>.from(json['content'] as Map),
      correctAnswer: json['correctAnswer'],
      learningItemIds: json['learningItemIds'] == null
          ? const []
          : List<String>.from(json['learningItemIds'] as List),
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test` (dentro de `mobile/`)
Expected: todos los tests pasan, incluyendo los 18 existentes de la Fase 1 (el default `const []` no rompe ninguna fixture previa) y los 2 nuevos.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/content/models/exercise.dart mobile/test/features/content/models/exercise_test.dart
git commit -m "feat: add learningItemIds to Exercise model"
```

---

### Task 4: Widget `FillBlankExercise`

**Files:**
- Create: `mobile/lib/features/lesson/widgets/fill_blank_exercise.dart`
- Test: `mobile/test/features/lesson/widgets/fill_blank_exercise_test.dart`

**Interfaces:**
- Consumes: `Exercise` (Task 3), con `content = {"prompt": string, "options": [string]}` y `correctAnswer: string`.
- Produces: `FillBlankExercise({required Exercise exercise, required void Function(bool correct) onAnswered})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/lesson/widgets/fill_blank_exercise_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/fill_blank_exercise.dart';

Exercise _exercise() => const Exercise(
      id: 'ex-1',
      sortOrder: 1,
      type: 'fill_blank',
      content: {
        'prompt': 'What is your ___?',
        'options': ['name', 'goodbye'],
      },
      correctAnswer: 'name',
    );

void main() {
  testWidgets('selecting the correct option reports true and shows feedback', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: FillBlankExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('name'));
    await tester.pump();

    expect(result, true);
    expect(find.text('¡Correcto!'), findsOneWidget);
  });

  testWidgets('selecting the wrong option reports false and shows feedback', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: FillBlankExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('goodbye'));
    await tester.pump();

    expect(result, false);
    expect(find.text('Incorrecto'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/lesson/widgets/fill_blank_exercise_test.dart`
Expected: FAIL — el archivo no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/lesson/widgets/fill_blank_exercise.dart`:
```dart
import 'package:flutter/material.dart';
import '../../content/models/exercise.dart';

class FillBlankExercise extends StatefulWidget {
  const FillBlankExercise({
    super.key,
    required this.exercise,
    required this.onAnswered,
  });

  final Exercise exercise;
  final void Function(bool correct) onAnswered;

  @override
  State<FillBlankExercise> createState() => _FillBlankExerciseState();
}

class _FillBlankExerciseState extends State<FillBlankExercise> {
  String? _selected;

  void _select(String option) {
    if (_selected != null) return;
    final correct = option == widget.exercise.correctAnswer;
    setState(() => _selected = option);
    widget.onAnswered(correct);
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.exercise.content['prompt'] as String;
    final options = List<String>.from(widget.exercise.content['options'] as List);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prompt),
        for (final option in options)
          ElevatedButton(
            onPressed: () => _select(option),
            child: Text(option),
          ),
        if (_selected != null)
          Text(_selected == widget.exercise.correctAnswer ? '¡Correcto!' : 'Incorrecto'),
      ],
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/lesson/widgets/fill_blank_exercise_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/lesson/widgets/fill_blank_exercise.dart mobile/test/features/lesson/widgets/fill_blank_exercise_test.dart
git commit -m "feat: add FillBlankExercise widget"
```

---

### Task 5: Widget `WordOrderExercise`

**Files:**
- Create: `mobile/lib/features/lesson/widgets/word_order_exercise.dart`
- Test: `mobile/test/features/lesson/widgets/word_order_exercise_test.dart`

**Interfaces:**
- Consumes: `Exercise` (Task 3), con `content = {"words": [string]}` y `correctAnswer: string` (la oración completa, palabras separadas por un espacio).
- Produces: `WordOrderExercise({required Exercise exercise, required void Function(bool correct) onAnswered})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/lesson/widgets/word_order_exercise_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/word_order_exercise.dart';

Exercise _exercise() => const Exercise(
      id: 'ex-1',
      sortOrder: 1,
      type: 'word_order',
      content: {
        'words': ['is', 'My', 'Ana', 'name'],
      },
      correctAnswer: 'My name is Ana',
    );

void main() {
  testWidgets('tapping words in the correct order reports true', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: WordOrderExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('My'));
    await tester.pump();
    await tester.tap(find.text('name'));
    await tester.pump();
    await tester.tap(find.text('is'));
    await tester.pump();
    await tester.tap(find.text('Ana'));
    await tester.pump();

    expect(result, true);
    expect(find.text('¡Correcto!'), findsOneWidget);
  });

  testWidgets('tapping words in the wrong order reports false', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: WordOrderExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('is'));
    await tester.pump();
    await tester.tap(find.text('My'));
    await tester.pump();
    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('name'));
    await tester.pump();

    expect(result, false);
    expect(find.text('Incorrecto'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/lesson/widgets/word_order_exercise_test.dart`
Expected: FAIL — el archivo no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/lesson/widgets/word_order_exercise.dart`:
```dart
import 'package:flutter/material.dart';
import '../../content/models/exercise.dart';

class WordOrderExercise extends StatefulWidget {
  const WordOrderExercise({
    super.key,
    required this.exercise,
    required this.onAnswered,
  });

  final Exercise exercise;
  final void Function(bool correct) onAnswered;

  @override
  State<WordOrderExercise> createState() => _WordOrderExerciseState();
}

class _WordOrderExerciseState extends State<WordOrderExercise> {
  late List<String> _available = List<String>.from(widget.exercise.content['words'] as List);
  final List<String> _selected = [];
  bool _answered = false;

  void _select(int index) {
    if (_answered) return;
    setState(() {
      _selected.add(_available.removeAt(index));
    });
    if (_selected.length == (widget.exercise.content['words'] as List).length) {
      final correct = _selected.join(' ') == widget.exercise.correctAnswer;
      setState(() => _answered = true);
      widget.onAnswered(correct);
    }
  }

  void _unselect(int index) {
    if (_answered) return;
    setState(() {
      _available.add(_selected.removeAt(index));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _selected.length; i++)
              ElevatedButton(
                onPressed: () => _unselect(i),
                child: Text(_selected[i]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _available.length; i++)
              OutlinedButton(
                onPressed: () => _select(i),
                child: Text(_available[i]),
              ),
          ],
        ),
        if (_answered)
          Text(_selected.join(' ') == widget.exercise.correctAnswer ? '¡Correcto!' : 'Incorrecto'),
      ],
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/lesson/widgets/word_order_exercise_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/lesson/widgets/word_order_exercise.dart mobile/test/features/lesson/widgets/word_order_exercise_test.dart
git commit -m "feat: add WordOrderExercise widget"
```

---

### Task 6: `exercise_widget_factory` — selector de widget por tipo

**Files:**
- Create: `mobile/lib/features/lesson/exercise_widget_factory.dart`
- Test: `mobile/test/features/lesson/exercise_widget_factory_test.dart`
- Modify: `mobile/lib/features/lesson/lesson_screen.dart:1-3,93-103`

**Interfaces:**
- Consumes: `Exercise` (Task 3), `MultipleChoiceExercise` (Fase 1), `FillBlankExercise` (Task 4), `WordOrderExercise` (Task 5).
- Produces: `Widget buildExerciseWidget({required Exercise exercise, required void Function(bool correct) onAnswered})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/lesson/exercise_widget_factory_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/lesson/exercise_widget_factory.dart';
import 'package:effica_palaboom/features/lesson/widgets/fill_blank_exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/multiple_choice_exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/word_order_exercise.dart';

Exercise _exercise(String type) => Exercise(
      id: 'ex-1',
      sortOrder: 1,
      type: type,
      content: type == 'word_order' ? {'words': <String>[]} : {'prompt': 'x', 'options': <String>[]},
      correctAnswer: 'x',
    );

void main() {
  testWidgets('multiple_choice builds MultipleChoiceExercise', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildExerciseWidget(exercise: _exercise('multiple_choice'), onAnswered: (_) {}),
    ));
    expect(find.byType(MultipleChoiceExercise), findsOneWidget);
  });

  testWidgets('fill_blank builds FillBlankExercise', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildExerciseWidget(exercise: _exercise('fill_blank'), onAnswered: (_) {}),
    ));
    expect(find.byType(FillBlankExercise), findsOneWidget);
  });

  testWidgets('word_order builds WordOrderExercise', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildExerciseWidget(exercise: _exercise('word_order'), onAnswered: (_) {}),
    ));
    expect(find.byType(WordOrderExercise), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/lesson/exercise_widget_factory_test.dart`
Expected: FAIL — el archivo no existe.

- [ ] **Step 3: Implementar el factory**

`mobile/lib/features/lesson/exercise_widget_factory.dart`:
```dart
import 'package:flutter/widgets.dart';
import '../content/models/exercise.dart';
import 'widgets/fill_blank_exercise.dart';
import 'widgets/multiple_choice_exercise.dart';
import 'widgets/word_order_exercise.dart';

Widget buildExerciseWidget({
  required Exercise exercise,
  required void Function(bool correct) onAnswered,
}) {
  switch (exercise.type) {
    case 'fill_blank':
      return FillBlankExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: onAnswered,
      );
    case 'word_order':
      return WordOrderExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: onAnswered,
      );
    default:
      return MultipleChoiceExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: onAnswered,
      );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que el factory pasa**

Run: `flutter test test/features/lesson/exercise_widget_factory_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Usar el factory en `LessonScreen`**

En `mobile/lib/features/lesson/lesson_screen.dart`, reemplaza el import de `widgets/multiple_choice_exercise.dart` por `exercise_widget_factory.dart`, y reemplaza el bloque final del `build()`:

```dart
    final exercise = widget.lesson.exercises[_currentIndex];
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: MultipleChoiceExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: (correct) {
          _onAnswered(correct);
        },
      ),
    );
```
por:
```dart
    final exercise = widget.lesson.exercises[_currentIndex];
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: buildExerciseWidget(
        exercise: exercise,
        onAnswered: (correct) {
          _onAnswered(correct);
        },
      ),
    );
```

- [ ] **Step 6: Correr toda la suite**

Run: `flutter test` (dentro de `mobile/`)
Expected: todos los tests pasan (la lección seguía usando `MultipleChoiceExercise` para sus ejercicios existentes, el factory produce el mismo widget para `multiple_choice`, ningún test existente debería romperse).

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/features/lesson/exercise_widget_factory.dart mobile/test/features/lesson/exercise_widget_factory_test.dart mobile/lib/features/lesson/lesson_screen.dart
git commit -m "feat: add exercise widget factory and use it in LessonScreen"
```

---

### Task 7: `SrsRepository` — interfaz e implementación Supabase

**Files:**
- Create: `mobile/lib/features/srs/srs_repository.dart`
- Test: `mobile/test/features/srs/srs_repository_test.dart`

**Interfaces:**
- Consumes: `Exercise` (Task 3).
- Produces: `SrsRepository` (interfaz: `Future<int> getDueCount()`, `Future<List<Exercise>> getDueExercises()`, `Future<void> submitReviewResult({required String learningItemId, required bool correct})`), `SupabaseSrsRepository`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/srs/srs_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';

class FakeSrsRepository implements SrsRepository {
  final List<Exercise> due;
  FakeSrsRepository(this.due);

  String? lastLearningItemId;
  bool? lastCorrect;

  @override
  Future<int> getDueCount() async => due.length;

  @override
  Future<List<Exercise>> getDueExercises() async => due;

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    lastLearningItemId = learningItemId;
    lastCorrect = correct;
  }
}

void main() {
  test('getDueCount matches the number of due exercises', () async {
    final repo = FakeSrsRepository([
      const Exercise(id: 'e1', sortOrder: 1, type: 'multiple_choice', content: {}, correctAnswer: 'x'),
      const Exercise(id: 'e2', sortOrder: 2, type: 'multiple_choice', content: {}, correctAnswer: 'x'),
    ]);

    expect(await repo.getDueCount(), 2);
  });

  test('submitReviewResult records the learning item and result', () async {
    final repo = FakeSrsRepository(const []);

    await repo.submitReviewResult(learningItemId: 'li-1', correct: true);

    expect(repo.lastLearningItemId, 'li-1');
    expect(repo.lastCorrect, true);
  });
}
```

Nota: este test valida el contrato de la interfaz a través de un fake, igual que los repositorios de la Fase 1 — la implementación concreta contra Supabase se verifica manualmente en la Tarea 13 (verificación end-to-end), no con mocks del `SupabaseClient`.

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/srs/srs_repository_test.dart`
Expected: FAIL — el archivo no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/srs/srs_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../content/models/exercise.dart';

abstract class SrsRepository {
  Future<int> getDueCount();
  Future<List<Exercise>> getDueExercises();
  Future<void> submitReviewResult({required String learningItemId, required bool correct});
}

class SupabaseSrsRepository implements SrsRepository {
  SupabaseSrsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<int> getDueCount() async => (await getDueExercises()).length;

  @override
  Future<List<Exercise>> getDueExercises() async {
    final result = await _client.rpc('get_due_learning_items');
    final list = List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return list.map(Exercise.fromJson).toList();
  }

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    await _client.rpc('update_learning_item_progress', params: {
      'p_learning_item_id': learningItemId,
      'p_correct': correct,
    });
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/srs/srs_repository.dart mobile/test/features/srs/srs_repository_test.dart
git commit -m "feat: add SrsRepository"
```

---

### Task 8: `LessonScreen` emite `submitReviewResult` por ejercicio

**Files:**
- Modify: `mobile/lib/features/lesson/lesson_screen.dart`
- Modify: `mobile/test/features/lesson/lesson_screen_test.dart`

**Interfaces:**
- Consumes: `SrsRepository` (Task 7).
- Produces: `LessonScreen` ahora requiere `required SrsRepository srsRepository` además de lo ya existente.

- [ ] **Step 1: Modificar el test para inyectar un `FakeSrsRepository` y verificar la llamada**

En `mobile/test/features/lesson/lesson_screen_test.dart`, agrega el fake y actualiza la fixture de `_lesson()` para que sus ejercicios tengan `learningItemIds`, y pasa `srsRepository` al construir `LessonScreen`:

```dart
import 'package:effica_palaboom/features/srs/srs_repository.dart';

class FakeSrsRepository implements SrsRepository {
  final calls = <MapEntry<String, bool>>[];

  @override
  Future<int> getDueCount() async => 0;

  @override
  Future<List<Exercise>> getDueExercises() async => const [];

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    calls.add(MapEntry(learningItemId, correct));
  }
}
```

Actualiza `_lesson()` para que los dos ejercicios existentes incluyan `learningItemIds: ['li-1']` y `learningItemIds: ['li-2']` respectivamente.

El archivo tiene TRES tests que construyen `LessonScreen` directamente: `'completing all exercises submits the score and shows completion'`, `'opening a lesson with no exercises shows a friendly message instead of crashing'`, y `'a failed progress submission shows an error instead of a false completion'`. Agrega `srsRepository: FakeSrsRepository()` a las TRES construcciones para que las tres compilen (una instancia nueva por test, como ya se hace con `FakeProgressRepository`).

En el primer test (`completing all exercises...`), guarda la instancia del fake en una variable para poder inspeccionarla después de interactuar, y agrega al final:
```dart
    expect(srsRepo.calls, [
      const MapEntry('li-1', true),
      const MapEntry('li-2', true),
    ]);
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/lesson/lesson_screen_test.dart`
Expected: FAIL — `LessonScreen` no tiene el parámetro `srsRepository` todavía.

- [ ] **Step 3: Implementar**

En `mobile/lib/features/lesson/lesson_screen.dart`:
- Agregar import: `import '../srs/srs_repository.dart';`
- Agregar al constructor: `required this.srsRepository,` y el campo `final SrsRepository srsRepository;`.
- Reemplazar `_onAnswered` completo por:
```dart
  Future<void> _onAnswered(bool correct) async {
    if (correct) _correctCount++;
    final exercise = widget.lesson.exercises[_currentIndex];
    for (final learningItemId in exercise.learningItemIds) {
      try {
        await widget.srsRepository.submitReviewResult(
          learningItemId: learningItemId,
          correct: correct,
        );
      } catch (_) {
        // El scheduling SRS es una mejora de fondo; si falla, no debe
        // bloquear que el usuario termine la lección (a diferencia de
        // submitLessonResult más abajo, que sí es la señal de finalización).
      }
    }
    final isLast = _currentIndex == widget.lesson.exercises.length - 1;
    if (isLast) {
      final score = _correctCount / widget.lesson.exercises.length;
      try {
        await widget.progressRepository.submitLessonResult(
          lessonId: widget.lesson.id,
          score: score,
        );
        if (!mounted) return;
        setState(() {
          _errorMessage = null;
          _completed = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'No se pudo guardar tu progreso. Intenta de nuevo.';
        });
      }
    } else {
      setState(() => _currentIndex++);
    }
  }
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/lesson/lesson_screen.dart mobile/test/features/lesson/lesson_screen_test.dart
git commit -m "feat: LessonScreen updates SRS state for every answered exercise"
```

---

### Task 9: `ReviewSessionScreen` — sesión de repaso dinámica

**Files:**
- Create: `mobile/lib/features/srs/review_session_screen.dart`
- Test: `mobile/test/features/srs/review_session_screen_test.dart`

**Interfaces:**
- Consumes: `Exercise` (Task 3), `buildExerciseWidget` (Task 6), `SrsRepository` (Task 7).
- Produces: `ReviewSessionScreen({required List<Exercise> exercises, required SrsRepository srsRepository})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/srs/review_session_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/srs/review_session_screen.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';

class FakeSrsRepository implements SrsRepository {
  bool shouldFail = false;
  final calls = <String>[];

  @override
  Future<int> getDueCount() async => 0;

  @override
  Future<List<Exercise>> getDueExercises() async => const [];

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    if (shouldFail) throw Exception('network error');
    calls.add(learningItemId);
  }
}

List<Exercise> _exercises() => const [
      Exercise(
        id: 'ex-1',
        sortOrder: 1,
        type: 'multiple_choice',
        content: {'prompt': 'Hola?', 'options': ['Hello', 'Goodbye']},
        correctAnswer: 'Hello',
        learningItemIds: ['li-1'],
      ),
    ];

void main() {
  testWidgets('answering the only due exercise completes the session', (tester) async {
    final repo = FakeSrsRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(exercises: _exercises(), srsRepository: repo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['li-1']);
    expect(find.text('¡Repaso completado!'), findsOneWidget);
  });

  testWidgets('shows an empty state when there is nothing due', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(exercises: const [], srsRepository: FakeSrsRepository()),
    ));

    expect(find.text('No hay nada para repasar ahora mismo.'), findsOneWidget);
  });

  testWidgets('shows an error if the SRS update fails', (tester) async {
    final repo = FakeSrsRepository()..shouldFail = true;
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(exercises: _exercises(), srsRepository: repo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(find.text('¡Repaso completado!'), findsNothing);
    expect(find.textContaining('No se pudo'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/srs/review_session_screen_test.dart`
Expected: FAIL — el archivo no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/srs/review_session_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../content/models/exercise.dart';
import '../lesson/exercise_widget_factory.dart';
import 'srs_repository.dart';

class ReviewSessionScreen extends StatefulWidget {
  const ReviewSessionScreen({
    super.key,
    required this.exercises,
    required this.srsRepository,
  });

  final List<Exercise> exercises;
  final SrsRepository srsRepository;

  @override
  State<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  int _currentIndex = 0;
  bool _completed = false;
  String? _errorMessage;

  Future<void> _onAnswered(bool correct) async {
    final exercise = widget.exercises[_currentIndex];
    try {
      for (final learningItemId in exercise.learningItemIds) {
        await widget.srsRepository.submitReviewResult(
          learningItemId: learningItemId,
          correct: correct,
        );
      }
      if (!mounted) return;
      final isLast = _currentIndex == widget.exercises.length - 1;
      setState(() {
        _errorMessage = null;
        if (isLast) {
          _completed = true;
        } else {
          _currentIndex++;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo guardar tu repaso. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.exercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: const Center(child: Text('No hay nada para repasar ahora mismo.')),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    if (_completed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('¡Repaso completado!'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver al curso'),
              ),
            ],
          ),
        ),
      );
    }

    final exercise = widget.exercises[_currentIndex];
    return Scaffold(
      appBar: AppBar(title: const Text('Repaso')),
      body: buildExerciseWidget(exercise: exercise, onAnswered: _onAnswered),
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan (3 nuevos).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/srs/review_session_screen.dart mobile/test/features/srs/review_session_screen_test.dart
git commit -m "feat: add ReviewSessionScreen"
```

---

### Task 10: `CourseScreen` — tarjeta de Repaso

**Files:**
- Modify: `mobile/lib/features/course/course_screen.dart`
- Modify: `mobile/test/features/course/course_screen_test.dart`

**Interfaces:**
- Consumes: `SrsRepository` (Task 7), `ReviewSessionScreen` (Task 9).
- Produces: `CourseScreen` ahora requiere también `required SrsRepository srsRepository`.

- [ ] **Step 1: Actualizar el test existente y agregar el caso de la tarjeta de Repaso**

En `mobile/test/features/course/course_screen_test.dart`, agrega:
```dart
import 'package:effica_palaboom/features/srs/review_session_screen.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';

class FakeSrsRepository implements SrsRepository {
  FakeSrsRepository({this.due = const []});
  final List<Exercise> due;

  @override
  Future<int> getDueCount() async => due.length;

  @override
  Future<List<Exercise>> getDueExercises() async => due;

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {}
}
```
El archivo tiene DOS tests existentes que construyen `CourseScreen` directamente: `'shows lessons and navigates to LessonScreen on tap'` y `'a fetch failure shows an error message with a retry affordance instead of spinning forever'`. Agrega `srsRepository: FakeSrsRepository()` (sin nada pendiente) a las DOS construcciones de `CourseScreen` en esos dos tests, para que ambos sigan compilando. Luego agrega un test nuevo:
```dart
  testWidgets('shows the due count and navigates to ReviewSessionScreen on tap', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );
    final dueExercise = const Exercise(
      id: 'ex-due',
      sortOrder: 1,
      type: 'multiple_choice',
      content: {'prompt': 'x', 'options': ['a']},
      correctAnswer: 'a',
      learningItemIds: ['li-1'],
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
        srsRepository: FakeSrsRepository(due: [dueExercise]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 para repasar'), findsOneWidget);

    await tester.tap(find.text('Repaso'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewSessionScreen), findsOneWidget);
  });
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/course/course_screen_test.dart`
Expected: FAIL — `CourseScreen` no acepta `srsRepository` todavía.

- [ ] **Step 3: Implementar**

En `mobile/lib/features/course/course_screen.dart`:
- Agregar imports: `import '../srs/review_session_screen.dart';` y `import '../srs/srs_repository.dart';`.
- Agregar al constructor: `required this.srsRepository,` y el campo `final SrsRepository srsRepository;`.
- Agregar en `_CourseScreenState`: `late final Future<int> _dueCountFuture = widget.srsRepository.getDueCount();`.
- Modificar `LessonScreen` en el `onTap` de cada lección para pasar también `srsRepository: widget.srsRepository`.
- Agregar, como primer elemento de `children` en el `ListView` (antes del `for (final unit in units)`):
```dart
              FutureBuilder<int>(
                future: _dueCountFuture,
                builder: (context, dueSnapshot) {
                  final dueCount = dueSnapshot.data ?? 0;
                  return Card(
                    child: ListTile(
                      title: const Text('Repaso'),
                      subtitle: Text(
                        dueCount > 0 ? '$dueCount para repasar' : 'Sin repasos pendientes hoy',
                      ),
                      onTap: dueCount == 0
                          ? null
                          : () async {
                              final exercises = await widget.srsRepository.getDueExercises();
                              if (!context.mounted) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReviewSessionScreen(
                                    exercises: exercises,
                                    srsRepository: widget.srsRepository,
                                  ),
                                ),
                              );
                            },
                    ),
                  );
                },
              ),
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/course/course_screen.dart mobile/test/features/course/course_screen_test.dart
git commit -m "feat: add Repaso card to CourseScreen"
```

---

### Task 11: Pantalla de progreso por unidad

**Files:**
- Create: `mobile/lib/features/progress/unit_progress_summary.dart`
- Create: `mobile/lib/features/progress/progress_summary_repository.dart`
- Create: `mobile/lib/features/progress/progress_screen.dart`
- Test: `mobile/test/features/progress/progress_screen_test.dart`

**Interfaces:**
- Consumes: forma JSON de `get_unit_progress_summary()` (Task 1).
- Produces: `UnitProgressSummary`, `ProgressSummaryRepository` (interfaz: `Future<List<UnitProgressSummary>> getUnitProgressSummaries()`), `SupabaseProgressSummaryRepository`, `ProgressScreen({required ProgressSummaryRepository progressSummaryRepository})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/progress/progress_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/progress/progress_screen.dart';
import 'package:effica_palaboom/features/progress/progress_summary_repository.dart';
import 'package:effica_palaboom/features/progress/unit_progress_summary.dart';

class FakeProgressSummaryRepository implements ProgressSummaryRepository {
  FakeProgressSummaryRepository(this.summaries);
  final List<UnitProgressSummary> summaries;

  @override
  Future<List<UnitProgressSummary>> getUnitProgressSummaries() async => summaries;
}

void main() {
  testWidgets('shows a summary row per unit', (tester) async {
    final repo = FakeProgressSummaryRepository([
      const UnitProgressSummary(
        unitId: 'u1',
        unitTitle: 'Saludos básicos',
        totalLessons: 2,
        completedLessons: 1,
        totalLearningItems: 4,
        learnedItems: 2,
        dueTodayItems: 1,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ProgressScreen(progressSummaryRepository: repo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saludos básicos'), findsOneWidget);
    expect(find.textContaining('1/2 lecciones'), findsOneWidget);
    expect(find.textContaining('2/4 aprendidas'), findsOneWidget);
    expect(find.textContaining('1 para repasar hoy'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/progress/progress_screen_test.dart`
Expected: FAIL — ninguno de los tres archivos existe.

- [ ] **Step 3: Implementar el modelo**

`mobile/lib/features/progress/unit_progress_summary.dart`:
```dart
class UnitProgressSummary {
  const UnitProgressSummary({
    required this.unitId,
    required this.unitTitle,
    required this.totalLessons,
    required this.completedLessons,
    required this.totalLearningItems,
    required this.learnedItems,
    required this.dueTodayItems,
  });

  final String unitId;
  final String unitTitle;
  final int totalLessons;
  final int completedLessons;
  final int totalLearningItems;
  final int learnedItems;
  final int dueTodayItems;

  factory UnitProgressSummary.fromJson(Map<String, dynamic> json) {
    return UnitProgressSummary(
      unitId: json['unitId'] as String,
      unitTitle: json['unitTitle'] as String,
      totalLessons: json['totalLessons'] as int,
      completedLessons: json['completedLessons'] as int,
      totalLearningItems: json['totalLearningItems'] as int,
      learnedItems: json['learnedItems'] as int,
      dueTodayItems: json['dueTodayItems'] as int,
    );
  }
}
```

- [ ] **Step 4: Implementar el repositorio**

`mobile/lib/features/progress/progress_summary_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'unit_progress_summary.dart';

abstract class ProgressSummaryRepository {
  Future<List<UnitProgressSummary>> getUnitProgressSummaries();
}

class SupabaseProgressSummaryRepository implements ProgressSummaryRepository {
  SupabaseProgressSummaryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<UnitProgressSummary>> getUnitProgressSummaries() async {
    final result = await _client.rpc('get_unit_progress_summary');
    final list = List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return list.map(UnitProgressSummary.fromJson).toList();
  }
}
```

- [ ] **Step 5: Implementar la pantalla**

`mobile/lib/features/progress/progress_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'progress_summary_repository.dart';
import 'unit_progress_summary.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.progressSummaryRepository});

  final ProgressSummaryRepository progressSummaryRepository;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final Future<List<UnitProgressSummary>> _summariesFuture =
      widget.progressSummaryRepository.getUnitProgressSummaries();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tu progreso')),
      body: FutureBuilder<List<UnitProgressSummary>>(
        future: _summariesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('No se pudo cargar tu progreso.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summaries = snapshot.data!;
          return ListView(
            children: [
              for (final s in summaries)
                ListTile(
                  title: Text(s.unitTitle),
                  subtitle: Text(
                    '${s.completedLessons}/${s.totalLessons} lecciones · '
                    '${s.learnedItems}/${s.totalLearningItems} aprendidas · '
                    '${s.dueTodayItems} para repasar hoy',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/features/progress mobile/test/features/progress
git commit -m "feat: add ProgressScreen with per-unit summary"
```

---

### Task 12: Wiring final — `app.dart`, `main.dart`, acceso desde `CourseScreen`

**Files:**
- Modify: `mobile/lib/app.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/features/course/course_screen.dart`
- Modify: `mobile/test/app_test.dart`
- Modify: `mobile/test/features/course/course_screen_test.dart`

**Interfaces:**
- Consumes: `SrsRepository`/`SupabaseSrsRepository` (Task 7), `ProgressSummaryRepository`/`SupabaseProgressSummaryRepository` (Task 11).
- Produces: `App` y `CourseScreen` con acceso completo a los repositorios de la Fase 2; `main.dart` los instancia.

- [ ] **Step 1: Actualizar los tests que construyen `App`/`CourseScreen` directamente**

En `mobile/test/app_test.dart`, agrega fakes mínimos de `SrsRepository` y `ProgressSummaryRepository` (igual patrón que los demás) y pásalos al construir `App`.

En `mobile/test/features/course/course_screen_test.dart`, agrega un fake mínimo de `ProgressSummaryRepository` y pásalo a `CourseScreen` en todos los tests existentes de ese archivo. Agrega un test nuevo:
```dart
  testWidgets('AppBar has a button that opens ProgressScreen', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
        srsRepository: FakeSrsRepository(),
        progressSummaryRepository: FakeProgressSummaryRepository([]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    expect(find.byType(ProgressScreen), findsOneWidget);
  });
```
(agrega el import de `ProgressScreen`, `ProgressSummaryRepository` y un `FakeProgressSummaryRepository` local igual al de la Tarea 11).

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test`
Expected: FAIL — `CourseScreen`/`App` no aceptan los parámetros nuevos todavía.

- [ ] **Step 3: Implementar**

En `mobile/lib/features/course/course_screen.dart`:
- Agregar import: `import '../progress/progress_screen.dart';` y `import '../progress/progress_summary_repository.dart';`.
- Agregar al constructor: `required this.progressSummaryRepository,` y el campo `final ProgressSummaryRepository progressSummaryRepository;`.
- Cambiar el `Scaffold` del `build()` para que tenga `appBar`:
```dart
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu curso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProgressScreen(
                  progressSummaryRepository: widget.progressSummaryRepository,
                ),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Course>(
```
(el resto del `build()` — todo lo que sigue dentro de `FutureBuilder<Course>(...)` — no cambia; solo se le agregó `appBar:` al `Scaffold` antes de `body:`).

En `mobile/lib/app.dart`:
- Agregar imports de `SrsRepository` y `ProgressSummaryRepository`.
- Agregar al constructor de `App`: `required this.srsRepository, required this.progressSummaryRepository,` y sus campos.
- Pasar ambos a la construcción de `CourseScreen` dentro del `StreamBuilder`.

En `mobile/lib/main.dart`:
- Agregar imports de `features/srs/srs_repository.dart` y `features/progress/progress_summary_repository.dart`.
- Al construir `App`, agregar `srsRepository: SupabaseSrsRepository(client), progressSummaryRepository: SupabaseProgressSummaryRepository(client),`.

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/app.dart mobile/lib/main.dart mobile/lib/features/course/course_screen.dart mobile/test/app_test.dart mobile/test/features/course/course_screen_test.dart
git commit -m "feat: wire SrsRepository and ProgressSummaryRepository through App/CourseScreen"
```

---

### Task 13: Verificación manual de punta a punta

**Files:** ninguno (verificación, no código nuevo).

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: confirmación de que el motor SRS y los ejercicios nuevos funcionan contra Supabase local real.

- [ ] **Step 1: Levantar Supabase local con el contenido sembrado**

```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select get_active_course();"
```
Confirma que la lección "Presentarse" trae los dos ejercicios nuevos con `learningItemIds` no vacíos.

- [ ] **Step 2: Correr la app y responder los ejercicios nuevos**

```bash
cd mobile
flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon-key-de-supabase-status>
```
Loguéate con un usuario existente (o crea uno nuevo), entra a "Presentarse", responde el ejercicio de completar espacio y el de ordenar palabras. Confirma que ambos dan retroalimentación correcta/incorrecta según lo que elijas.

- [ ] **Step 3: Confirmar que el estado SRS se creó**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select learning_item_id, ease_factor, repetitions, interval_days, next_review_date from user_learning_item_progress;"
```
Expected: una fila por cada `learning_item` practicado, con `next_review_date` en el futuro si acertaste, o mañana si fallaste.

- [ ] **Step 4: Forzar un ítem "vencido" y verificar la sección de Repaso**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "update user_learning_item_progress set next_review_date = current_date;"
```
Vuelve a la pantalla del curso (o recárgala). La tarjeta "Repaso" debe mostrar la cantidad correcta de ítems pendientes. Tócala, responde los ejercicios de repaso, y confirma "¡Repaso completado!".

- [ ] **Step 5: Verificar que el repaso actualizó el intervalo**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select learning_item_id, repetitions, interval_days, next_review_date from user_learning_item_progress;"
```
Expected: `next_review_date` avanzó más allá de hoy para los ítems que acertaste en el repaso.

- [ ] **Step 6: Verificar la pantalla de progreso**

Desde el ícono en el AppBar de la pantalla del curso, abre "Tu progreso" y confirma que los números (lecciones completadas, ítems aprendidos, pendientes de repaso) coinciden con lo esperado dado lo que ya respondiste.

Con esto queda validada la Fase 2 de punta a punta.
