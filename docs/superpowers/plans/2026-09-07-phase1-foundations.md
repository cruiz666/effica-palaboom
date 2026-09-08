# Fase 1 — Cimientos: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar un "esqueleto caminante": un usuario se loguea, ve el curso de inglés (traído desde Supabase), completa una lección con ejercicios de opción múltiple, y su progreso queda guardado — funcionando de punta a punta, online y con cache offline del contenido.

**Architecture:** Separación motor/contenido desde el día uno. El contenido (curso → unidad → lección → ejercicio → learning item) vive en Postgres (Supabase) y se expone como un único árbol JSON vía la función `get_active_course()`. La app Flutter usa repositorios con interfaces (`ContentRepository`, `AuthRepository`, `ProgressRepository`) que envuelven Supabase, de forma que la lógica de UI se puede testear con implementaciones falsas sin tocar la red.

**Tech Stack:** Flutter (Dart), Supabase (Postgres + Auth), paquetes `supabase_flutter`, `shared_preferences`. Testing con `flutter_test` (incluido en el SDK de Flutter) usando dobles de prueba escritos a mano (sin librería de mocking).

## Global Constraints

- Flutter, un solo código para iOS/Android — sin ramas de código específicas por plataforma salvo que sea estrictamente necesario.
- Backend único: Supabase (Postgres + Auth + Storage). No se introduce otro backend.
- Tema visual: **Midnight Teal** (paleta oscura, color semilla `#0F3D3E`) en toda la UI.
- Tono de producto: adulto, no infantil — aplica a todo el copy visible.
- Alcance de contenido en este ciclo: un solo curso (inglés). El esquema no debe bloquear multi-idioma a futuro, pero no se construye soporte activo para múltiples cursos todavía.
- El contenido se edita directo en Supabase (Table Editor / SQL). No hay panel de administración (CMS) en este ciclo.

---

## File Structure

**Backend (Supabase):**
- `supabase/migrations/20260907000001_content_and_progress_schema.sql` — tablas de contenido y progreso, RLS, función `get_active_course()`.
- `supabase/seed.sql` — curso de inglés de ejemplo con una unidad, dos lecciones y ejercicios de opción múltiple.

**App (Flutter, proyecto en `mobile/`):**
- `mobile/lib/theme/app_theme.dart` — tema Midnight Teal.
- `mobile/lib/features/content/models/{exercise,lesson,unit,course}.dart` — modelos de contenido con `fromJson`.
- `mobile/lib/features/content/content_remote_data_source.dart` — interfaz + implementación Supabase para traer el curso activo.
- `mobile/lib/features/content/content_cache.dart` — interfaz + implementación con `shared_preferences` para cachear el curso.
- `mobile/lib/features/content/content_repository.dart` — combina fuente remota + cache con fallback offline.
- `mobile/lib/features/auth/auth_repository.dart` — interfaz + implementación Supabase de autenticación.
- `mobile/lib/features/auth/login_screen.dart` — pantalla de login.
- `mobile/lib/features/lesson/progress_repository.dart` — interfaz + implementación Supabase para guardar progreso.
- `mobile/lib/features/lesson/widgets/multiple_choice_exercise.dart` — widget de ejercicio de opción múltiple.
- `mobile/lib/features/lesson/lesson_screen.dart` — recorre los ejercicios de una lección y reporta el resultado.
- `mobile/lib/features/course/course_screen.dart` — lista unidades/lecciones del curso activo.
- `mobile/lib/app.dart` — widget raíz, enruta entre login y curso según sesión.
- `mobile/lib/main.dart` — entrypoint, inicializa Supabase y arma las dependencias.
- Archivos de test espejo bajo `mobile/test/...` para cada archivo de lógica/widget listado arriba.

---

### Task 1: Esquema de contenido y progreso en Supabase

**Files:**
- Create: `supabase/migrations/20260907000001_content_and_progress_schema.sql`

**Interfaces:**
- Consumes: nada (primera tarea).
- Produces: tablas `languages, courses, units, lessons, exercises, learning_items, exercise_learning_items, user_lesson_progress`; función `get_active_course()` que retorna un `jsonb` con forma:
  ```json
  {
    "id": "uuid", "title": "string",
    "units": [{
      "id": "uuid", "title": "string", "cefrLevel": "string", "sortOrder": 1,
      "lessons": [{
        "id": "uuid", "title": "string", "sortOrder": 1,
        "exercises": [{
          "id": "uuid", "sortOrder": 1, "type": "multiple_choice",
          "content": {"prompt": "string", "options": ["string"]},
          "correctAnswer": "string"
        }]
      }]
    }]
  }
  ```

- [ ] **Step 1: Verificar el estado inicial (sin tablas)**

Run: `supabase start` (si no está corriendo) y luego:
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\dt"
```
Expected: no aparecen las tablas `courses`, `units`, `lessons`, `exercises`, `learning_items`, `exercise_learning_items`, `user_lesson_progress` (o el comando falla porque no existen).

- [ ] **Step 2: Escribir la migración**

```sql
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
```

- [ ] **Step 3: Verificar que las tablas y la función existen**

Run:
```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\dt"
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\df get_active_course"
```
Expected: las 7 tablas aparecen en `\dt`, y `get_active_course` aparece en `\df`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260907000001_content_and_progress_schema.sql
git commit -m "feat: add content and progress schema with get_active_course()"
```

---

### Task 2: Contenido semilla del curso piloto de inglés

**Files:**
- Create: `supabase/seed.sql`

**Interfaces:**
- Consumes: esquema de Task 1.
- Produces: un curso publicado con id `11111111-1111-1111-1111-111111111111`, una unidad, dos lecciones (`33333333-...` con 2 ejercicios, `44444444-...` sin ejercicios), dos learning items, dos ejercicios de tipo `multiple_choice`. Estos IDs se usan como referencia en la verificación manual de la Tarea 11.

- [ ] **Step 1: Verificar que el curso activo está vacío**

Run:
```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select get_active_course();"
```
Expected: `get_active_course()` retorna `null` (no hay cursos publicados todavía).

- [ ] **Step 2: Escribir el seed**

```sql
insert into languages (code, name) values
  ('en', 'English'),
  ('es', 'Español')
on conflict (code) do nothing;

insert into courses (id, source_language, target_language, title, status)
values ('11111111-1111-1111-1111-111111111111', 'es', 'en', 'Inglés para hispanohablantes', 'published');

insert into units (id, course_id, cefr_level, title, sort_order, status)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'A1', 'Saludos básicos', 1, 'published');

insert into lessons (id, unit_id, title, sort_order) values
  ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'Saludar y despedirse', 1),
  ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'Presentarse', 2);

insert into learning_items (id, course_id, item_type, value, translation) values
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'vocab', 'Hello', 'Hola'),
  ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', 'vocab', 'Goodbye', 'Adiós');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('77777777-7777-7777-7777-777777777777', '33333333-3333-3333-3333-333333333333', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Hola\" en inglés?", "options": ["Hello", "Goodbye", "Please"]}'::jsonb,
   '"Hello"'::jsonb),
  ('88888888-8888-8888-8888-888888888888', '33333333-3333-3333-3333-333333333333', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Adiós\" en inglés?", "options": ["Hello", "Goodbye", "Thanks"]}'::jsonb,
   '"Goodbye"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('77777777-7777-7777-7777-777777777777', '55555555-5555-5555-5555-555555555555'),
  ('88888888-8888-8888-8888-888888888888', '66666666-6666-6666-6666-666666666666');
```

- [ ] **Step 3: Verificar que el curso activo trae el contenido sembrado**

Run:
```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select get_active_course();"
```
Expected: el JSON retornado contiene `"title": "Inglés para hispanohablantes"`, una unidad `"Saludos básicos"` con dos lecciones, y la primera lección con dos ejercicios cuyo `"correctAnswer"` es `"Hello"` y `"Goodbye"` respectivamente.

- [ ] **Step 4: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat: seed pilot English course content"
```

---

### Task 3: Proyecto Flutter y tema Midnight Teal

**Files:**
- Create: proyecto Flutter en `mobile/` (via `flutter create`)
- Create: `mobile/lib/theme/app_theme.dart`
- Test: `mobile/test/theme/app_theme_test.dart`
- Modify: `mobile/lib/main.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `appTheme` (`ThemeData`) importable desde `package:effica_palaboom/theme/app_theme.dart`.

- [ ] **Step 1: Crear el proyecto y agregar dependencias**

Run (desde la raíz del repo):
```bash
flutter create mobile --org com.efficapalaboom --project-name effica_palaboom
cd mobile
flutter pub add supabase_flutter provider shared_preferences
```

- [ ] **Step 2: Escribir el test del tema (falla porque `app_theme.dart` no existe)**

`mobile/test/theme/app_theme_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/theme/app_theme.dart';

void main() {
  test('appTheme uses a dark Midnight Teal color scheme', () {
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.scaffoldBackgroundColor, const Color(0xFF0A1F22));
    expect(appTheme.colorScheme.brightness, Brightness.dark);
  });
}
```

- [ ] **Step 3: Ejecutar y verificar que falla**

Run: `flutter test test/theme/app_theme_test.dart` (dentro de `mobile/`)
Expected: FAIL — `Target of URI doesn't exist: 'package:effica_palaboom/theme/app_theme.dart'`.

- [ ] **Step 4: Implementar el tema**

`mobile/lib/theme/app_theme.dart`:
```dart
import 'package:flutter/material.dart';

const _midnightTealSeed = Color(0xFF0F3D3E);

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _midnightTealSeed,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: const Color(0xFF0A1F22),
);
```

Modifica `mobile/lib/main.dart` para usarlo como placeholder mientras se completan las siguientes tareas:
```dart
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PlaceholderApp());
}

class PlaceholderApp extends StatelessWidget {
  const PlaceholderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      home: const Scaffold(body: Center(child: Text('effica-palaboom'))),
    );
  }
}
```

- [ ] **Step 5: Ejecutar y verificar que pasa**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile
git commit -m "feat: scaffold Flutter app with Midnight Teal theme"
```

---

### Task 4: Modelos de contenido (Course/Unit/Lesson/Exercise)

**Files:**
- Create: `mobile/lib/features/content/models/exercise.dart`
- Create: `mobile/lib/features/content/models/lesson.dart`
- Create: `mobile/lib/features/content/models/unit.dart`
- Create: `mobile/lib/features/content/models/course.dart`
- Test: `mobile/test/features/content/models/course_test.dart`

**Interfaces:**
- Consumes: forma del JSON producida por `get_active_course()` (Task 1).
- Produces: `Course.fromJson`, `Unit.fromJson`, `Lesson.fromJson`, `Exercise.fromJson`; `Course` tiene `List<Unit> units`, `Unit` tiene `List<Lesson> lessons` (+ `cefrLevel`, `sortOrder`), `Lesson` tiene `List<Exercise> exercises` (+ `sortOrder`), `Exercise` tiene `id, sortOrder, type, content (Map<String,dynamic>), correctAnswer (dynamic)`.

- [ ] **Step 1: Escribir el test de parseo (falla porque las clases no existen)**

`mobile/test/features/content/models/course_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/course.dart';

void main() {
  test('Course.fromJson parses the nested content tree', () {
    final json = {
      'id': 'course-1',
      'title': 'Inglés para hispanohablantes',
      'units': [
        {
          'id': 'unit-1',
          'title': 'Saludos básicos',
          'cefrLevel': 'A1',
          'sortOrder': 1,
          'lessons': [
            {
              'id': 'lesson-1',
              'title': 'Saludar y despedirse',
              'sortOrder': 1,
              'exercises': [
                {
                  'id': 'ex-1',
                  'sortOrder': 1,
                  'type': 'multiple_choice',
                  'content': {
                    'prompt': '¿Cómo se dice "Hola" en inglés?',
                    'options': ['Hello', 'Goodbye', 'Please'],
                  },
                  'correctAnswer': 'Hello',
                },
              ],
            },
          ],
        },
      ],
    };

    final course = Course.fromJson(json);

    expect(course.title, 'Inglés para hispanohablantes');
    expect(course.units, hasLength(1));
    expect(course.units.first.cefrLevel, 'A1');
    expect(course.units.first.lessons, hasLength(1));
    expect(course.units.first.lessons.first.exercises, hasLength(1));
    final exercise = course.units.first.lessons.first.exercises.first;
    expect(exercise.type, 'multiple_choice');
    expect(exercise.content['prompt'], '¿Cómo se dice "Hola" en inglés?');
    expect(exercise.correctAnswer, 'Hello');
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/content/models/course_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:effica_palaboom/features/content/models/course.dart'`.

- [ ] **Step 3: Implementar los modelos**

`mobile/lib/features/content/models/exercise.dart`:
```dart
class Exercise {
  const Exercise({
    required this.id,
    required this.sortOrder,
    required this.type,
    required this.content,
    required this.correctAnswer,
  });

  final String id;
  final int sortOrder;
  final String type;
  final Map<String, dynamic> content;
  final dynamic correctAnswer;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      sortOrder: json['sortOrder'] as int,
      type: json['type'] as String,
      content: Map<String, dynamic>.from(json['content'] as Map),
      correctAnswer: json['correctAnswer'],
    );
  }
}
```

`mobile/lib/features/content/models/lesson.dart`:
```dart
import 'exercise.dart';

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.sortOrder,
    required this.exercises,
  });

  final String id;
  final String title;
  final int sortOrder;
  final List<Exercise> exercises;

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as String,
      title: json['title'] as String,
      sortOrder: json['sortOrder'] as int,
      exercises: (json['exercises'] as List)
          .map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
```

`mobile/lib/features/content/models/unit.dart`:
```dart
import 'lesson.dart';

class Unit {
  const Unit({
    required this.id,
    required this.title,
    required this.cefrLevel,
    required this.sortOrder,
    required this.lessons,
  });

  final String id;
  final String title;
  final String cefrLevel;
  final int sortOrder;
  final List<Lesson> lessons;

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'] as String,
      title: json['title'] as String,
      cefrLevel: json['cefrLevel'] as String,
      sortOrder: json['sortOrder'] as int,
      lessons: (json['lessons'] as List)
          .map((l) => Lesson.fromJson(Map<String, dynamic>.from(l as Map)))
          .toList(),
    );
  }
}
```

`mobile/lib/features/content/models/course.dart`:
```dart
import 'unit.dart';

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.units,
  });

  final String id;
  final String title;
  final List<Unit> units;

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      title: json['title'] as String,
      units: (json['units'] as List)
          .map((u) => Unit.fromJson(Map<String, dynamic>.from(u as Map)))
          .toList(),
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/content/models/course_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/content/models mobile/test/features/content/models
git commit -m "feat: add content models with JSON parsing"
```

---

### Task 5: Repositorio de contenido con cache offline

**Files:**
- Create: `mobile/lib/features/content/content_remote_data_source.dart`
- Create: `mobile/lib/features/content/content_cache.dart`
- Create: `mobile/lib/features/content/content_repository.dart`
- Test: `mobile/test/features/content/content_repository_test.dart`

**Interfaces:**
- Consumes: `Course.fromJson` (Task 4).
- Produces: `ContentRemoteDataSource` (interfaz, `Future<Map<String,dynamic>> fetchActiveCourse()`), `SupabaseContentRemoteDataSource`, `ContentCache` (interfaz, `saveActiveCourse`/`loadActiveCourse`), `SharedPreferencesContentCache`, `ContentRepository` con `Future<Course> getActiveCourse()`.

- [ ] **Step 1: Escribir el test del repositorio (falla porque no existe)**

`mobile/test/features/content/content_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';

class FakeRemoteDataSource implements ContentRemoteDataSource {
  FakeRemoteDataSource({this.shouldThrow = false, required this.json});
  final bool shouldThrow;
  final Map<String, dynamic> json;

  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async {
    if (shouldThrow) throw Exception('network error');
    return json;
  }
}

class FakeContentCache implements ContentCache {
  Map<String, dynamic>? stored;

  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async => stored;

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {
    stored = courseJson;
  }
}

Map<String, dynamic> _fixture(String title) => {
      'id': 'course-1',
      'title': title,
      'units': <dynamic>[],
    };

void main() {
  test('getActiveCourse fetches remotely and caches the result', () async {
    final cache = FakeContentCache();
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(json: _fixture('Curso remoto')),
      cache: cache,
    );

    final course = await repository.getActiveCourse();

    expect(course.title, 'Curso remoto');
    expect(cache.stored?['title'], 'Curso remoto');
  });

  test('getActiveCourse falls back to cache when the fetch fails', () async {
    final cache = FakeContentCache()..stored = _fixture('Curso cacheado');
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(shouldThrow: true, json: _fixture('no usado')),
      cache: cache,
    );

    final course = await repository.getActiveCourse();

    expect(course.title, 'Curso cacheado');
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/content/content_repository_test.dart`
Expected: FAIL — los archivos `content_cache.dart`, `content_remote_data_source.dart` y `content_repository.dart` no existen.

- [ ] **Step 3: Implementar**

`mobile/lib/features/content/content_remote_data_source.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ContentRemoteDataSource {
  Future<Map<String, dynamic>> fetchActiveCourse();
}

class SupabaseContentRemoteDataSource implements ContentRemoteDataSource {
  SupabaseContentRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async {
    final result = await _client.rpc('get_active_course');
    return Map<String, dynamic>.from(result as Map);
  }
}
```

`mobile/lib/features/content/content_cache.dart`:
```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ContentCache {
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson);
  Future<Map<String, dynamic>?> loadActiveCourse();
}

class SharedPreferencesContentCache implements ContentCache {
  static const _key = 'cached_active_course';

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(courseJson));
  }

  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
}
```

`mobile/lib/features/content/content_repository.dart`:
```dart
import 'content_cache.dart';
import 'content_remote_data_source.dart';
import 'models/course.dart';

class ContentRepository {
  ContentRepository({required this.remoteDataSource, required this.cache});

  final ContentRemoteDataSource remoteDataSource;
  final ContentCache cache;

  Future<Course> getActiveCourse() async {
    try {
      final json = await remoteDataSource.fetchActiveCourse();
      await cache.saveActiveCourse(json);
      return Course.fromJson(json);
    } catch (_) {
      final cached = await cache.loadActiveCourse();
      if (cached == null) rethrow;
      return Course.fromJson(cached);
    }
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/content/content_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/content mobile/test/features/content/content_repository_test.dart
git commit -m "feat: add content repository with offline cache fallback"
```

---

### Task 6: Autenticación y pantalla de login

**Files:**
- Create: `mobile/lib/features/auth/auth_repository.dart`
- Create: `mobile/lib/features/auth/login_screen.dart`
- Test: `mobile/test/features/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: nada nuevo.
- Produces: `AuthRepository` (interfaz: `Stream<bool> get authStateChanges`, `Future<void> signIn({required String email, required String password})`), `SupabaseAuthRepository`, `LoginScreen({required AuthRepository authRepository})`.

- [ ] **Step 1: Escribir el test de la pantalla de login (falla porque no existe)**

`mobile/test/features/auth/login_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/auth/auth_repository.dart';
import 'package:effica_palaboom/features/auth/login_screen.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.shouldFail = false});
  final bool shouldFail;
  String? lastEmail;
  String? lastPassword;

  @override
  Stream<bool> get authStateChanges => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
    if (shouldFail) throw Exception('invalid credentials');
  }
}

void main() {
  testWidgets('successful login calls signIn with entered credentials', (tester) async {
    final repo = FakeAuthRepository();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(authRepository: repo)));

    await tester.enterText(find.byKey(const Key('emailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(repo.lastEmail, 'user@example.com');
    expect(repo.lastPassword, 'secret123');
    expect(find.text('Correo o contraseña incorrectos'), findsNothing);
  });

  testWidgets('failed login shows an error message', (tester) async {
    final repo = FakeAuthRepository(shouldFail: true);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(authRepository: repo)));

    await tester.enterText(find.byKey(const Key('emailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'wrong');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: FAIL — `auth_repository.dart` y `login_screen.dart` no existen.

- [ ] **Step 3: Implementar**

`mobile/lib/features/auth/auth_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthRepository {
  Stream<bool> get authStateChanges;
  Future<void> signIn({required String email, required String password});
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<bool> get authStateChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session != null);

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }
}
```

`mobile/lib/features/auth/login_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    try {
      await widget.authRepository.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } catch (_) {
      setState(() => _errorMessage = 'Correo o contraseña incorrectos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('emailField'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Correo'),
            ),
            TextField(
              key: const Key('passwordField'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('loginButton'),
              onPressed: _submit,
              child: const Text('Ingresar'),
            ),
            if (_errorMessage != null) Text(_errorMessage!),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/auth mobile/test/features/auth
git commit -m "feat: add auth repository and login screen"
```

---

### Task 7: Widget de ejercicio de opción múltiple

**Files:**
- Create: `mobile/lib/features/lesson/widgets/multiple_choice_exercise.dart`
- Test: `mobile/test/features/lesson/widgets/multiple_choice_exercise_test.dart`

**Interfaces:**
- Consumes: `Exercise` (Task 4).
- Produces: `MultipleChoiceExercise({required Exercise exercise, required void Function(bool correct) onAnswered})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/lesson/widgets/multiple_choice_exercise_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/multiple_choice_exercise.dart';

Exercise _exercise() => const Exercise(
      id: 'ex-1',
      sortOrder: 1,
      type: 'multiple_choice',
      content: {
        'prompt': '¿Cómo se dice "Hola" en inglés?',
        'options': ['Hello', 'Goodbye'],
      },
      correctAnswer: 'Hello',
    );

void main() {
  testWidgets('selecting the correct option reports true and shows feedback', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: MultipleChoiceExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pump();

    expect(result, true);
    expect(find.text('¡Correcto!'), findsOneWidget);
  });

  testWidgets('selecting the wrong option reports false and shows feedback', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: MultipleChoiceExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('Goodbye'));
    await tester.pump();

    expect(result, false);
    expect(find.text('Incorrecto'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/lesson/widgets/multiple_choice_exercise_test.dart`
Expected: FAIL — el archivo no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/lesson/widgets/multiple_choice_exercise.dart`:
```dart
import 'package:flutter/material.dart';
import '../../content/models/exercise.dart';

class MultipleChoiceExercise extends StatefulWidget {
  const MultipleChoiceExercise({
    super.key,
    required this.exercise,
    required this.onAnswered,
  });

  final Exercise exercise;
  final void Function(bool correct) onAnswered;

  @override
  State<MultipleChoiceExercise> createState() => _MultipleChoiceExerciseState();
}

class _MultipleChoiceExerciseState extends State<MultipleChoiceExercise> {
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

Run: `flutter test test/features/lesson/widgets/multiple_choice_exercise_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/lesson/widgets mobile/test/features/lesson/widgets
git commit -m "feat: add multiple choice exercise widget"
```

---

### Task 8: Progreso de lección y pantalla de lección

**Files:**
- Create: `mobile/lib/features/lesson/progress_repository.dart`
- Create: `mobile/lib/features/lesson/lesson_screen.dart`
- Test: `mobile/test/features/lesson/lesson_screen_test.dart`

**Interfaces:**
- Consumes: `Lesson`/`Exercise` (Task 4), `MultipleChoiceExercise` (Task 7).
- Produces: `ProgressRepository` (interfaz: `Future<void> submitLessonResult({required String lessonId, required double score})`), `SupabaseProgressRepository`, `LessonScreen({required Lesson lesson, required ProgressRepository progressRepository})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/lesson/lesson_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/content/models/lesson.dart';
import 'package:effica_palaboom/features/lesson/lesson_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';

class FakeProgressRepository implements ProgressRepository {
  String? lastLessonId;
  double? lastScore;

  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {
    lastLessonId = lessonId;
    lastScore = score;
  }
}

Lesson _lesson() => const Lesson(
      id: 'lesson-1',
      title: 'Saludar y despedirse',
      sortOrder: 1,
      exercises: [
        Exercise(
          id: 'ex-1',
          sortOrder: 1,
          type: 'multiple_choice',
          content: {'prompt': 'Hola?', 'options': ['Hello', 'Goodbye']},
          correctAnswer: 'Hello',
        ),
        Exercise(
          id: 'ex-2',
          sortOrder: 2,
          type: 'multiple_choice',
          content: {'prompt': 'Adiós?', 'options': ['Hello', 'Goodbye']},
          correctAnswer: 'Goodbye',
        ),
      ],
    );

void main() {
  testWidgets('completing all exercises submits the score and shows completion', (tester) async {
    final progressRepo = FakeProgressRepository();
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(lesson: _lesson(), progressRepository: progressRepo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();

    expect(progressRepo.lastLessonId, 'lesson-1');
    expect(progressRepo.lastScore, 1.0);
    expect(find.text('¡Lección completada!'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/lesson/lesson_screen_test.dart`
Expected: FAIL — `progress_repository.dart` y `lesson_screen.dart` no existen.

- [ ] **Step 3: Implementar**

`mobile/lib/features/lesson/progress_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ProgressRepository {
  Future<void> submitLessonResult({required String lessonId, required double score});
}

class SupabaseProgressRepository implements ProgressRepository {
  SupabaseProgressRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('user_lesson_progress').insert({
      'user_id': userId,
      'lesson_id': lessonId,
      'score': score,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }
}
```

`mobile/lib/features/lesson/lesson_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../content/models/lesson.dart';
import 'widgets/multiple_choice_exercise.dart';
import 'progress_repository.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.lesson,
    required this.progressRepository,
  });

  final Lesson lesson;
  final ProgressRepository progressRepository;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  int _currentIndex = 0;
  int _correctCount = 0;
  bool _completed = false;

  void _onAnswered(bool correct) {
    if (correct) _correctCount++;
    final isLast = _currentIndex == widget.lesson.exercises.length - 1;
    if (isLast) {
      final score = _correctCount / widget.lesson.exercises.length;
      widget.progressRepository.submitLessonResult(
        lessonId: widget.lesson.id,
        score: score,
      );
      setState(() => _completed = true);
    } else {
      setState(() => _currentIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return const Scaffold(
        body: Center(child: Text('¡Lección completada!')),
      );
    }
    final exercise = widget.lesson.exercises[_currentIndex];
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: MultipleChoiceExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: _onAnswered,
      ),
    );
  }
}
```

Nota: el `key: ValueKey(exercise.id)` es necesario — sin él, Flutter reutiliza el `State` del widget anterior al pasar al siguiente ejercicio, y `_selected` seguiría marcado como respondido, bloqueando la interacción.

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/lesson/lesson_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/lesson/progress_repository.dart mobile/lib/features/lesson/lesson_screen.dart mobile/test/features/lesson/lesson_screen_test.dart
git commit -m "feat: add progress repository and lesson screen flow"
```

---

### Task 9: Pantalla del curso (unidades y lecciones)

**Files:**
- Create: `mobile/lib/features/course/course_screen.dart`
- Test: `mobile/test/features/course/course_screen_test.dart`

**Interfaces:**
- Consumes: `ContentRepository` (Task 5), `Course` (Task 4), `LessonScreen`/`ProgressRepository` (Task 8).
- Produces: `CourseScreen({required ContentRepository contentRepository, required ProgressRepository progressRepository})`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/course/course_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';
import 'package:effica_palaboom/features/course/course_screen.dart';
import 'package:effica_palaboom/features/lesson/lesson_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';

class FakeRemoteDataSource implements ContentRemoteDataSource {
  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async => {
        'id': 'course-1',
        'title': 'Inglés para hispanohablantes',
        'units': [
          {
            'id': 'unit-1',
            'title': 'Saludos básicos',
            'cefrLevel': 'A1',
            'sortOrder': 1,
            'lessons': [
              {
                'id': 'lesson-1',
                'title': 'Saludar y despedirse',
                'sortOrder': 1,
                'exercises': [
                  {
                    'id': 'ex-1',
                    'sortOrder': 1,
                    'type': 'multiple_choice',
                    'content': {'prompt': 'Hola?', 'options': ['Hello', 'Goodbye']},
                    'correctAnswer': 'Hello',
                  },
                ],
              },
            ],
          },
        ],
      };
}

class FakeContentCache implements ContentCache {
  Map<String, dynamic>? stored;

  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async => stored;

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {
    stored = courseJson;
  }
}

class FakeProgressRepository implements ProgressRepository {
  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {}
}

void main() {
  testWidgets('shows lessons and navigates to LessonScreen on tap', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saludos básicos'), findsOneWidget);
    expect(find.text('Saludar y despedirse'), findsOneWidget);

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/course/course_screen_test.dart`
Expected: FAIL — `course_screen.dart` no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/course/course_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../content/content_repository.dart';
import '../content/models/course.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/progress_repository.dart';

class CourseScreen extends StatefulWidget {
  const CourseScreen({
    super.key,
    required this.contentRepository,
    required this.progressRepository,
  });

  final ContentRepository contentRepository;
  final ProgressRepository progressRepository;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  late final Future<Course> _courseFuture = widget.contentRepository.getActiveCourse();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Course>(
        future: _courseFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final course = snapshot.data!;
          return ListView(
            children: [
              for (final unit in course.units) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(unit.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                for (final lesson in unit.lessons)
                  ListTile(
                    title: Text(lesson.title),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonScreen(
                          lesson: lesson,
                          progressRepository: widget.progressRepository,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/course/course_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/course mobile/test/features/course
git commit -m "feat: add course screen listing units and lessons"
```

---

### Task 10: Enrutamiento raíz según sesión (App + main.dart)

**Files:**
- Create: `mobile/lib/app.dart`
- Modify: `mobile/lib/main.dart`
- Test: `mobile/test/app_test.dart`

**Interfaces:**
- Consumes: `AuthRepository`/`LoginScreen` (Task 6), `ContentRepository` (Task 5), `CourseScreen` (Task 9), `ProgressRepository` (Task 8), `appTheme` (Task 3).
- Produces: `App({required AuthRepository authRepository, required ContentRepository contentRepository, required ProgressRepository progressRepository})`; `main.dart` como entrypoint final de la Fase 1.

- [ ] **Step 1: Escribir el test (falla porque `app.dart` no existe)**

`mobile/test/app_test.dart`:
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/app.dart';
import 'package:effica_palaboom/features/auth/auth_repository.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';
import 'package:effica_palaboom/features/course/course_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get authStateChanges => _controller.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {}

  void emit(bool signedIn) => _controller.add(signedIn);
}

class FakeRemoteDataSource implements ContentRemoteDataSource {
  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async =>
      {'id': 'c1', 'title': 'Curso', 'units': <dynamic>[]};
}

class FakeContentCache implements ContentCache {
  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async => null;

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {}
}

class FakeProgressRepository implements ProgressRepository {
  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {}
}

void main() {
  testWidgets('shows LoginScreen when signed out and CourseScreen when signed in', (tester) async {
    final authRepository = FakeAuthRepository();

    await tester.pumpWidget(App(
      authRepository: authRepository,
      contentRepository: ContentRepository(
        remoteDataSource: FakeRemoteDataSource(),
        cache: FakeContentCache(),
      ),
      progressRepository: FakeProgressRepository(),
    ));

    authRepository.emit(false);
    await tester.pump();
    expect(find.byKey(const Key('emailField')), findsOneWidget);

    authRepository.emit(true);
    await tester.pump();
    expect(find.byType(CourseScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/app_test.dart`
Expected: FAIL — `app.dart` no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/content/content_repository.dart';
import 'features/course/course_screen.dart';
import 'features/lesson/progress_repository.dart';
import 'theme/app_theme.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.authRepository,
    required this.contentRepository,
    required this.progressRepository,
  });

  final AuthRepository authRepository;
  final ContentRepository contentRepository;
  final ProgressRepository progressRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      home: StreamBuilder<bool>(
        stream: authRepository.authStateChanges,
        builder: (context, snapshot) {
          final signedIn = snapshot.data ?? false;
          if (!signedIn) {
            return LoginScreen(authRepository: authRepository);
          }
          return CourseScreen(
            contentRepository: contentRepository,
            progressRepository: progressRepository,
          );
        },
      ),
    );
  }
}
```

`mobile/lib/main.dart` (versión final):
```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'features/auth/auth_repository.dart';
import 'features/content/content_cache.dart';
import 'features/content/content_remote_data_source.dart';
import 'features/content/content_repository.dart';
import 'features/lesson/progress_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  final client = Supabase.instance.client;
  runApp(App(
    authRepository: SupabaseAuthRepository(client),
    contentRepository: ContentRepository(
      remoteDataSource: SupabaseContentRemoteDataSource(client),
      cache: SharedPreferencesContentCache(),
    ),
    progressRepository: SupabaseProgressRepository(client),
  ));
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/app_test.dart`
Expected: PASS.

- [ ] **Step 5: Correr toda la suite de tests de la Fase 1**

Run: `flutter test` (dentro de `mobile/`)
Expected: todos los tests de las Tareas 3 a 10 pasan.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/app.dart mobile/lib/main.dart mobile/test/app_test.dart
git commit -m "feat: wire auth-gated routing between login and course screens"
```

---

### Task 11: Verificación manual de punta a punta

**Files:** ninguno (verificación, no código nuevo).

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: confirmación de que el esqueleto caminante funciona contra Supabase local real.

- [ ] **Step 1: Levantar Supabase local con el contenido sembrado**

```bash
supabase start
supabase db reset
supabase status
```
Anota el `API URL` (normalmente `http://127.0.0.1:54321`) y el `anon key` que imprime `supabase status`.

- [ ] **Step 2: Crear un usuario de prueba**

Abre Supabase Studio local (normalmente `http://127.0.0.1:54323`) → Authentication → Add user → crea un usuario con email y contraseña (confirmado, sin verificación de correo en local).

- [ ] **Step 3: Correr la app apuntando a Supabase local**

```bash
cd mobile
flutter run --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon-key-de-supabase-status>
```

- [ ] **Step 4: Verificar el flujo completo**

1. En la pantalla de login, ingresa el email/contraseña del usuario creado en el Paso 2 y presiona "Ingresar".
2. Verifica que aparece la unidad "Saludos básicos" con las lecciones "Saludar y despedirse" y "Presentarse".
3. Entra a "Saludar y despedirse" y responde correctamente ambos ejercicios ("Hello" y "Goodbye").
4. Verifica que aparece el texto "¡Lección completada!".

- [ ] **Step 5: Confirmar que el progreso quedó guardado**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select lesson_id, score from user_lesson_progress;"
```
Expected: una fila con `lesson_id = '33333333-3333-3333-3333-333333333333'` y `score = 1`.

Con esto queda validado el esqueleto de punta a punta de la Fase 1.
