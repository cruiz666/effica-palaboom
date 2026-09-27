# Fase 3 — Gamificación: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Racha diaria, XP por respuesta correcta, un nivel derivado del XP, y un límite de 3 errores por sesión que corta la lección/repaso de inmediato — con un encabezado siempre visible en la pantalla del curso mostrando los tres números.

**Architecture:** Se extiende el motor de las Fases 1-2 sin tocar decisiones de stack. La lógica de racha vive en SQL (`record_activity`), igual que el SM-2 de la Fase 2. XP y racha se otorgan en segundo plano (mismo patrón `unawaited` ya establecido para el SRS) desde `LessonScreen` y `ReviewSessionScreen`; el límite de errores es un contador en memoria por sesión, sin persistencia.

**Tech Stack:** Igual que Fases 1-2 — Flutter 3.24.5 (macOS 13 pinned), Supabase (Postgres + Auth), `supabase_flutter`.

**Spec:** `docs/superpowers/specs/2026-09-26-phase3-gamification-design.md`

## Global Constraints

- Todo lo de las Fases 1-2 sigue vigente: un solo código Flutter, backend único Supabase, tema Midnight Teal, tono adulto (nada de mecánicas tipo "vidas" que se regeneran con el tiempo), un solo curso activo.
- La lógica de racha (comparación de fechas, reinicio, récord histórico) vive en SQL (`record_activity`), no se reimplementa en Dart.
- La racha solo se actualiza al **completar** una lección o repaso completo — nunca por respuesta individual, y nunca si la sesión termina cortada por el límite de errores.
- El XP se otorga de inmediato por cada respuesta correcta y **no se revierte** aunque la sesión termine cortada después.
- El otorgamiento de XP y el registro de racha son mejoras de fondo: un fallo o demora ahí nunca debe bloquear ni mostrar error al usuario (mismo principio ya aplicado al SRS en `LessonScreen` en la Fase 2) — en **ambas** pantallas (`LessonScreen` y `ReviewSessionScreen`), a diferencia de la actualización de SRS, que en `ReviewSessionScreen` sí se surface como error (eso ya estaba así desde la Fase 2 y no cambia).
- El límite de errores (3) es un contador en memoria, no persistente, y se revisa antes de decidir si la sesión avanza o se completa.

---

## File Structure

**Backend (Supabase):**
- `supabase/migrations/20260926000002_gamification_engine.sql` — tabla `user_gamification_state` + RLS, funciones `add_xp(p_amount int)`, `record_activity()`, `get_gamification_state()`.

**App (Flutter, en `mobile/`):**
- `lib/features/gamification/gamification_state.dart` — modelo `GamificationState`.
- `lib/features/gamification/gamification_repository.dart` — interfaz + `SupabaseGamificationRepository`.
- `lib/features/gamification/gamification_header.dart` — widget presentacional (recibe el estado ya resuelto, no lo consulta él mismo).
- `lib/features/lesson/lesson_screen.dart` (modificado) — XP, límite de errores, registro de racha.
- `lib/features/srs/review_session_screen.dart` (modificado) — mismo tratamiento.
- `lib/features/course/course_screen.dart` (modificado) — agrega el encabezado de gamificación y pasa el repositorio a `LessonScreen`/`ReviewSessionScreen`.
- `lib/app.dart`, `lib/main.dart` (modificados) — wiring del repositorio nuevo.
- Archivos de test espejo bajo `test/...` para cada archivo nuevo o modificado.

---

### Task 1: Esquema de gamificación

**Files:**
- Create: `supabase/migrations/20260926000002_gamification_engine.sql`

**Interfaces:**
- Consumes: nada nuevo (usa `auth.users` ya existente).
- Produces: tabla `user_gamification_state`; funciones `add_xp(p_amount int)`, `record_activity()`, `get_gamification_state()` (retorna `jsonb`: `{xpTotal, currentStreak, longestStreak, level}`).

- [ ] **Step 1: Verificar estado inicial**

Run (desde la raíz del repo):
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\dt" | grep user_gamification_state
```
Expected: sin resultados (la tabla no existe todavía).

- [ ] **Step 2: Escribir la migración**

```sql
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
```

- [ ] **Step 3: Aplicar y verificar**

Run:
```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\dt" | grep user_gamification_state
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\df add_xp"
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\df record_activity"
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "\df get_gamification_state"
```
Expected: la tabla y las tres funciones existen.

Verifica también la lógica de racha manualmente (sustituye `<user-id>` por cualquier UUID válido, no necesita ser un usuario real para esta prueba con el rol `postgres`):
```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "
  insert into auth.users (id) values ('00000000-0000-0000-0000-000000000001') on conflict do nothing;
  set request.jwt.claims = '{\"sub\": \"00000000-0000-0000-0000-000000000001\"}';
  set role authenticated;
  select record_activity();
  select current_streak, last_activity_date from user_gamification_state;
"
```
Expected: `current_streak = 1`, `last_activity_date = current_date`. Ejecutar `record_activity()` una segunda vez en la misma sesión (mismo día) debe dejar `current_streak` sin cambios.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260926000002_gamification_engine.sql
git commit -m "feat: add gamification schema and streak/XP functions"
```

---

### Task 2: `GamificationState` y `GamificationRepository`

**Files:**
- Create: `mobile/lib/features/gamification/gamification_state.dart`
- Create: `mobile/lib/features/gamification/gamification_repository.dart`
- Test: `mobile/test/features/gamification/gamification_repository_test.dart`

**Interfaces:**
- Consumes: forma JSON de `get_gamification_state()` (Task 1).
- Produces: `GamificationState {xpTotal, currentStreak, longestStreak, level}` (todos `int`, con `fromJson`); `GamificationRepository` (interfaz: `Future<GamificationState> getState()`, `Future<void> awardXp(int amount)`, `Future<void> recordActivity()`), `SupabaseGamificationRepository`.

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/gamification/gamification_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

class FakeGamificationRepository implements GamificationRepository {
  FakeGamificationRepository({required this.state});
  GamificationState state;

  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async => state;

  @override
  Future<void> awardXp(int amount) async {
    xpAwards.add(amount);
  }

  @override
  Future<void> recordActivity() async {
    activityRecorded = true;
  }
}

void main() {
  test('GamificationState.fromJson parses all four fields', () {
    final state = GamificationState.fromJson({
      'xpTotal': 120,
      'currentStreak': 3,
      'longestStreak': 5,
      'level': 2,
    });

    expect(state.xpTotal, 120);
    expect(state.currentStreak, 3);
    expect(state.longestStreak, 5);
    expect(state.level, 2);
  });

  test('awardXp and recordActivity record their calls', () async {
    final repo = FakeGamificationRepository(
      state: const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1),
    );

    await repo.awardXp(10);
    await repo.recordActivity();

    expect(repo.xpAwards, [10]);
    expect(repo.activityRecorded, true);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/gamification/gamification_repository_test.dart` (dentro de `mobile/`)
Expected: FAIL — ninguno de los dos archivos de `lib/` existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/gamification/gamification_state.dart`:
```dart
class GamificationState {
  const GamificationState({
    required this.xpTotal,
    required this.currentStreak,
    required this.longestStreak,
    required this.level,
  });

  final int xpTotal;
  final int currentStreak;
  final int longestStreak;
  final int level;

  factory GamificationState.fromJson(Map<String, dynamic> json) {
    return GamificationState(
      xpTotal: json['xpTotal'] as int,
      currentStreak: json['currentStreak'] as int,
      longestStreak: json['longestStreak'] as int,
      level: json['level'] as int,
    );
  }
}
```

`mobile/lib/features/gamification/gamification_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gamification_state.dart';

abstract class GamificationRepository {
  Future<GamificationState> getState();
  Future<void> awardXp(int amount);
  Future<void> recordActivity();
}

class SupabaseGamificationRepository implements GamificationRepository {
  SupabaseGamificationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<GamificationState> getState() async {
    final result = await _client.rpc('get_gamification_state');
    return GamificationState.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> awardXp(int amount) async {
    await _client.rpc('add_xp', params: {'p_amount': amount});
  }

  @override
  Future<void> recordActivity() async {
    await _client.rpc('record_activity');
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan, incluyendo los 38 existentes de las Fases 1-2 y los 2 nuevos.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/gamification/gamification_state.dart mobile/lib/features/gamification/gamification_repository.dart mobile/test/features/gamification/gamification_repository_test.dart
git commit -m "feat: add GamificationState model and GamificationRepository"
```

---

### Task 3: Widget `GamificationHeader`

**Files:**
- Create: `mobile/lib/features/gamification/gamification_header.dart`
- Test: `mobile/test/features/gamification/gamification_header_test.dart`

**Interfaces:**
- Consumes: `GamificationState` (Task 2).
- Produces: `GamificationHeader({required GamificationState state})` — widget **presentacional**, no consulta el repositorio por su cuenta (el estado ya resuelto se lo pasa quien lo use — `CourseScreen` en la Tarea 6 — para poder refrescarlo desde afuera sin duplicar lógica de `Future` dentro del widget).

- [ ] **Step 1: Escribir el test (falla porque no existe)**

`mobile/test/features/gamification/gamification_header_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/gamification/gamification_header.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

void main() {
  testWidgets('shows streak, xp, and level', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GamificationHeader(
        state: GamificationState(xpTotal: 120, currentStreak: 3, longestStreak: 5, level: 2),
      ),
    ));

    expect(find.text('Racha: 3 días · 120 XP · Nivel 2'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/gamification/gamification_header_test.dart`
Expected: FAIL — el archivo no existe.

- [ ] **Step 3: Implementar**

`mobile/lib/features/gamification/gamification_header.dart`:
```dart
import 'package:flutter/material.dart';
import 'gamification_state.dart';

class GamificationHeader extends StatelessWidget {
  const GamificationHeader({super.key, required this.state});

  final GamificationState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Racha: ${state.currentStreak} días · ${state.xpTotal} XP · Nivel ${state.level}',
      ),
    );
  }
}
```

- [ ] **Step 4: Ejecutar y verificar que pasa**

Run: `flutter test test/features/gamification/gamification_header_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/gamification/gamification_header.dart mobile/test/features/gamification/gamification_header_test.dart
git commit -m "feat: add GamificationHeader widget"
```

---

### Task 4: `LessonScreen` — XP, límite de errores y racha

**Files:**
- Modify: `mobile/lib/features/lesson/lesson_screen.dart`
- Modify: `mobile/test/features/lesson/lesson_screen_test.dart`

**Interfaces:**
- Consumes: `GamificationRepository` (Task 2).
- Produces: `LessonScreen` ahora requiere también `required GamificationRepository gamificationRepository`.

- [ ] **Step 1: Actualizar el test**

El archivo `mobile/test/features/lesson/lesson_screen_test.dart` tiene CUATRO tests que construyen `LessonScreen` directamente: `'completing all exercises submits the score and shows completion'`, `'a throwing SRS repository never blocks or breaks lesson completion'`, `'opening a lesson with no exercises shows a friendly message instead of crashing'`, y `'a failed progress submission shows an error instead of a false completion'`. Agrega `gamificationRepository: FakeGamificationRepository()` (una instancia nueva por test) a las CUATRO construcciones.

Agrega el fake al inicio del archivo:
```dart
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

class FakeGamificationRepository implements GamificationRepository {
  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async =>
      const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1);

  @override
  Future<void> awardXp(int amount) async {
    xpAwards.add(amount);
  }

  @override
  Future<void> recordActivity() async {
    activityRecorded = true;
  }
}
```

En el test `'completing all exercises submits the score and shows completion'`, guarda la instancia del fake en una variable y agrega al final:
```dart
    expect(gamificationRepo.xpAwards, [10, 10]);
    expect(gamificationRepo.activityRecorded, true);
```

Agrega además una fixture nueva y un test nuevo para el límite de errores:
```dart
Lesson _lessonForErrorLimit() => const Lesson(
      id: 'lesson-limit',
      title: 'Práctica larga',
      sortOrder: 1,
      exercises: [
        Exercise(id: 'ex-1', sortOrder: 1, type: 'multiple_choice', content: {'prompt': 'p1', 'options': ['A', 'B']}, correctAnswer: 'A'),
        Exercise(id: 'ex-2', sortOrder: 2, type: 'multiple_choice', content: {'prompt': 'p2', 'options': ['A', 'B']}, correctAnswer: 'A'),
        Exercise(id: 'ex-3', sortOrder: 3, type: 'multiple_choice', content: {'prompt': 'p3', 'options': ['A', 'B']}, correctAnswer: 'A'),
        Exercise(id: 'ex-4', sortOrder: 4, type: 'multiple_choice', content: {'prompt': 'p4', 'options': ['A', 'B']}, correctAnswer: 'A'),
      ],
    );

// ...dentro de main():
  testWidgets('reaching the error limit ends the session before it completes', (tester) async {
    final progressRepo = FakeProgressRepository();
    final gamificationRepo = FakeGamificationRepository();
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(
        lesson: _lessonForErrorLimit(),
        progressRepository: progressRepo,
        srsRepository: FakeSrsRepository(),
        gamificationRepository: gamificationRepo,
      ),
    ));

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(find.text('Alcanzaste el límite de errores para esta sesión.'), findsOneWidget);
    expect(find.text('p4'), findsNothing);
    expect(progressRepo.lastLessonId, isNull);
    expect(gamificationRepo.activityRecorded, false);
  });
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/lesson/lesson_screen_test.dart`
Expected: FAIL — `LessonScreen` no tiene el parámetro `gamificationRepository` todavía.

- [ ] **Step 3: Implementar**

En `mobile/lib/features/lesson/lesson_screen.dart`:
- Agregar import: `import '../gamification/gamification_repository.dart';`
- Agregar al constructor: `required this.gamificationRepository,` y el campo `final GamificationRepository gamificationRepository;`.
- Agregar campos de estado: `int _incorrectCount = 0;`, `bool _limitReached = false;`, y la constante `static const _errorLimit = 3;`.
- Reemplazar `_onAnswered` completo por:
```dart
  Future<void> _onAnswered(bool correct) async {
    if (correct) {
      _correctCount++;
      unawaited(widget.gamificationRepository.awardXp(10).catchError((_) {}));
    } else {
      _incorrectCount++;
    }
    final exercise = widget.lesson.exercises[_currentIndex];
    for (final learningItemId in exercise.learningItemIds) {
      // SRS scheduling is a background enhancement; a failure or slow
      // response here must not block the user from finishing the lesson
      // (unlike submitLessonResult below, which is the completion signal).
      unawaited(
        widget.srsRepository
            .submitReviewResult(learningItemId: learningItemId, correct: correct)
            .catchError((_) {}),
      );
    }

    if (_incorrectCount >= _errorLimit) {
      if (!mounted) return;
      setState(() => _limitReached = true);
      return;
    }

    final isLast = _currentIndex == widget.lesson.exercises.length - 1;
    if (isLast) {
      final score = _correctCount / widget.lesson.exercises.length;
      try {
        await widget.progressRepository.submitLessonResult(
          lessonId: widget.lesson.id,
          score: score,
        );
        unawaited(widget.gamificationRepository.recordActivity().catchError((_) {}));
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
- Agregar, en `build()`, un nuevo branch para `_limitReached` — colócalo justo antes del branch de `_completed`:
```dart
    if (_limitReached) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lesson.title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Alcanzaste el límite de errores para esta sesión.'),
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
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/lesson/lesson_screen.dart mobile/test/features/lesson/lesson_screen_test.dart
git commit -m "feat: LessonScreen awards XP, records streak, and enforces error limit"
```

---

### Task 5: `ReviewSessionScreen` — XP, límite de errores y racha

**Files:**
- Modify: `mobile/lib/features/srs/review_session_screen.dart`
- Modify: `mobile/test/features/srs/review_session_screen_test.dart`

**Interfaces:**
- Consumes: `GamificationRepository` (Task 2).
- Produces: `ReviewSessionScreen` ahora requiere también `required GamificationRepository gamificationRepository`.

- [ ] **Step 1: Actualizar el test**

El archivo `mobile/test/features/srs/review_session_screen_test.dart` tiene TRES tests que construyen `ReviewSessionScreen` directamente: `'answering the only due exercise completes the session'`, `'shows an empty state when there is nothing due'`, y `'shows an error if the SRS update fails'`. Agrega `gamificationRepository: FakeGamificationRepository()` (una instancia nueva por test) a las TRES construcciones.

Agrega el fake (idéntico al de la Tarea 4, en este archivo de test):
```dart
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

class FakeGamificationRepository implements GamificationRepository {
  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async =>
      const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1);

  @override
  Future<void> awardXp(int amount) async {
    xpAwards.add(amount);
  }

  @override
  Future<void> recordActivity() async {
    activityRecorded = true;
  }
}
```

En el test `'answering the only due exercise completes the session'`, guarda la instancia del fake y agrega al final:
```dart
    expect(gamificationRepo.xpAwards, [10]);
    expect(gamificationRepo.activityRecorded, true);
```

Agrega una fixture y un test nuevo para el límite de errores:
```dart
List<Exercise> _exercisesForErrorLimit() => const [
      Exercise(id: 'ex-1', sortOrder: 1, type: 'multiple_choice', content: {'prompt': 'p1', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-1']),
      Exercise(id: 'ex-2', sortOrder: 2, type: 'multiple_choice', content: {'prompt': 'p2', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-2']),
      Exercise(id: 'ex-3', sortOrder: 3, type: 'multiple_choice', content: {'prompt': 'p3', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-3']),
      Exercise(id: 'ex-4', sortOrder: 4, type: 'multiple_choice', content: {'prompt': 'p4', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-4']),
    ];

// ...dentro de main():
  testWidgets('reaching the error limit ends the review session before it completes', (tester) async {
    final srsRepo = FakeSrsRepository();
    final gamificationRepo = FakeGamificationRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(
        exercises: _exercisesForErrorLimit(),
        srsRepository: srsRepo,
        gamificationRepository: gamificationRepo,
      ),
    ));

    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();

    expect(find.text('Alcanzaste el límite de errores para esta sesión.'), findsOneWidget);
    expect(find.text('p4'), findsNothing);
    expect(gamificationRepo.activityRecorded, false);
  });
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/srs/review_session_screen_test.dart`
Expected: FAIL — `ReviewSessionScreen` no tiene el parámetro `gamificationRepository` todavía.

- [ ] **Step 3: Implementar**

En `mobile/lib/features/srs/review_session_screen.dart`:
- Agregar `import 'dart:async';` y `import '../gamification/gamification_repository.dart';`.
- Agregar al constructor: `required this.gamificationRepository,` y el campo `final GamificationRepository gamificationRepository;`.
- Agregar campos: `int _incorrectCount = 0;`, `bool _limitReached = false;`, `static const _errorLimit = 3;`.
- Reemplazar `_onAnswered` completo por:
```dart
  Future<void> _onAnswered(bool correct) async {
    if (correct) {
      unawaited(widget.gamificationRepository.awardXp(10).catchError((_) {}));
    } else {
      _incorrectCount++;
    }
    final exercise = widget.exercises[_currentIndex];
    try {
      for (final learningItemId in exercise.learningItemIds) {
        await widget.srsRepository.submitReviewResult(
          learningItemId: learningItemId,
          correct: correct,
        );
      }
      if (!mounted) return;

      if (_incorrectCount >= _errorLimit) {
        setState(() {
          _errorMessage = null;
          _limitReached = true;
        });
        return;
      }

      final isLast = _currentIndex == widget.exercises.length - 1;
      if (isLast) {
        unawaited(widget.gamificationRepository.recordActivity().catchError((_) {}));
      }
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
```
- Agregar, en `build()`, un branch para `_limitReached`, antes del branch de `_completed`:
```dart
    if (_limitReached) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Alcanzaste el límite de errores para esta sesión.'),
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
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/srs/review_session_screen.dart mobile/test/features/srs/review_session_screen_test.dart
git commit -m "feat: ReviewSessionScreen awards XP, records streak, and enforces error limit"
```

---

### Task 6: `CourseScreen` — encabezado de gamificación y wiring

**Files:**
- Modify: `mobile/lib/features/course/course_screen.dart`
- Modify: `mobile/test/features/course/course_screen_test.dart`

**Interfaces:**
- Consumes: `GamificationRepository` (Task 2), `GamificationHeader` (Task 3).
- Produces: `CourseScreen` ahora requiere también `required GamificationRepository gamificationRepository`.

- [ ] **Step 1: Actualizar el test**

El archivo `mobile/test/features/course/course_screen_test.dart` tiene CINCO tests que construyen `CourseScreen` directamente. Agrega `gamificationRepository: FakeGamificationRepository()` a las CINCO construcciones.

Agrega el fake:
```dart
import 'package:effica_palaboom/features/gamification/gamification_header.dart';
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

class FakeGamificationRepository implements GamificationRepository {
  FakeGamificationRepository({this.state = const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1)});
  final GamificationState state;

  @override
  Future<GamificationState> getState() async => state;

  @override
  Future<void> awardXp(int amount) async {}

  @override
  Future<void> recordActivity() async {}
}
```

Agrega un test nuevo verificando que el encabezado aparece con los datos correctos:
```dart
  testWidgets('shows the gamification header with real state', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
        srsRepository: FakeSrsRepository(),
        progressSummaryRepository: FakeProgressSummaryRepository(),
        gamificationRepository: FakeGamificationRepository(
          state: const GamificationState(xpTotal: 50, currentStreak: 2, longestStreak: 4, level: 1),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(GamificationHeader), findsOneWidget);
    expect(find.text('Racha: 2 días · 50 XP · Nivel 1'), findsOneWidget);
  });
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test test/features/course/course_screen_test.dart`
Expected: FAIL — `CourseScreen` no acepta `gamificationRepository` todavía.

- [ ] **Step 3: Implementar**

En `mobile/lib/features/course/course_screen.dart`:
- Agregar imports: `import '../gamification/gamification_header.dart';` y `import '../gamification/gamification_repository.dart';` y `import '../gamification/gamification_state.dart';`.
- Agregar al constructor: `required this.gamificationRepository,` y el campo `final GamificationRepository gamificationRepository;`.
- Agregar en `_CourseScreenState`: `late Future<GamificationState> _gamificationStateFuture = widget.gamificationRepository.getState();`.
- En AMBOS lugares donde ya se refresca `_dueCountFuture` (después de volver de `LessonScreen` en el `onTap` de cada lección, y después de volver de `ReviewSessionScreen` en el `onTap` de la tarjeta de Repaso), agregar también el refresco de `_gamificationStateFuture` en el mismo `setState`:
```dart
                      setState(() {
                        _dueCountFuture = widget.srsRepository.getDueCount();
                        _gamificationStateFuture = widget.gamificationRepository.getState();
                      });
```
(hazlo en los dos lugares — el del `ListTile` de lección y el del `onTap` de la tarjeta de Repaso).
- Pasar `gamificationRepository: widget.gamificationRepository,` tanto al construir `LessonScreen` como al construir `ReviewSessionScreen`.
- Agregar, como primer elemento de `children` en el `ListView` (antes del `FutureBuilder<int>` de la tarjeta de Repaso):
```dart
              FutureBuilder<GamificationState>(
                future: _gamificationStateFuture,
                builder: (context, gamificationSnapshot) {
                  if (!gamificationSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  return GamificationHeader(state: gamificationSnapshot.data!);
                },
              ),
```

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/course/course_screen.dart mobile/test/features/course/course_screen_test.dart
git commit -m "feat: add GamificationHeader to CourseScreen"
```

---

### Task 7: Wiring final — `app.dart`, `main.dart`

**Files:**
- Modify: `mobile/lib/app.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/test/app_test.dart`

**Interfaces:**
- Consumes: `GamificationRepository`/`SupabaseGamificationRepository` (Task 2).
- Produces: `App` con acceso completo al repositorio de gamificación; `main.dart` lo instancia.

- [ ] **Step 1: Actualizar el test**

`mobile/test/app_test.dart` tiene una sola construcción de `App`. Agrega un fake `GamificationRepository` (mismo patrón que en la Tarea 6, con `getState()` devolviendo un `GamificationState` fijo) y pásalo como `gamificationRepository:` a esa construcción.

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `flutter test`
Expected: FAIL — `App` no acepta `gamificationRepository` todavía.

- [ ] **Step 3: Implementar**

En `mobile/lib/app.dart`:
- Agregar import: `import 'features/gamification/gamification_repository.dart';`.
- Agregar al constructor de `App`: `required this.gamificationRepository,` y el campo `final GamificationRepository gamificationRepository;`.
- Pasar `gamificationRepository: gamificationRepository,` a la construcción de `CourseScreen`.

En `mobile/lib/main.dart`:
- Agregar import: `import 'features/gamification/gamification_repository.dart';`.
- Al construir `App`, agregar `gamificationRepository: SupabaseGamificationRepository(client),`.

- [ ] **Step 4: Ejecutar y verificar que pasa, y correr toda la suite**

Run: `flutter test`
Expected: todos los tests pasan.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/app.dart mobile/lib/main.dart mobile/test/app_test.dart
git commit -m "feat: wire GamificationRepository through App/CourseScreen"
```

---

### Task 8: Verificación manual de punta a punta

**Files:** ninguno (verificación, no código nuevo).

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: confirmación de que la racha, el XP y el límite de errores funcionan contra Supabase local real.

- [ ] **Step 1: Levantar Supabase local con el contenido sembrado**

```bash
supabase db reset
```

- [ ] **Step 2: Correr la app y completar una lección respondiendo todo correcto**

```bash
cd mobile
flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon-key-de-supabase-status>
```
Loguéate con un usuario existente. Completa la lección "Saludar y despedirse" respondiendo todo correcto. Vuelve a la pantalla del curso y confirma que el encabezado ahora muestra "Racha: 1 días · 20 XP · Nivel 1" (2 ejercicios × 10 XP).

- [ ] **Step 3: Confirmar el estado en la base de datos**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select xp_total, current_streak, longest_streak, last_activity_date from user_gamification_state;"
```
Expected: `xp_total = 20`, `current_streak = 1`, `last_activity_date` = hoy.

- [ ] **Step 4: Provocar el límite de errores**

Entra a "Presentarse" y responde 3 veces incorrecto seguidas (elige la opción equivocada en `fill_blank`, y una palabra fuera de orden y confirma en `word_order` — si la lección tiene menos de 3 ejercicios, repite la lección las veces que hagan falta, o verifica directamente con el test automatizado del límite de errores de la Tarea 4/5 como evidencia adicional). Confirma que aparece "Alcanzaste el límite de errores para esta sesión." y que **no** cambió la racha en la base de datos tras ese intento.

- [ ] **Step 5: Verificar el reinicio de racha tras un salto de días**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "update user_gamification_state set last_activity_date = current_date - 3;"
```
Completa otra lección o repaso en la app. Confirma en la base de datos que `current_streak` volvió a `1` (no seguía sumando desde 1) y que `longest_streak` conservó el valor más alto ya alcanzado.

Con esto queda validada la Fase 3 de punta a punta.
