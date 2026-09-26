# Diseño: Fase 2 — Motor de aprendizaje (SRS + nuevos ejercicios)

**Fecha:** 2026-09-26
**Estado:** Aprobado para pasar a plan de implementación

## 1. Visión y alcance de la Fase 2

Continúa directamente sobre la Fase 1 (Cimientos), ya mergeada a `master`. El objetivo de esta fase es dos cosas: (a) ampliar el motor de ejercicios más allá de opción múltiple, y (b) introducir repetición espaciada (SRS) real, con una sección de repaso separada de las lecciones fijas y una pantalla de progreso de solo lectura.

**Incluido en esta fase:**
- Dos tipos de ejercicio nuevos: **completar espacio** (`fill_blank`) y **ordenar palabras** (`word_order`), ambos resueltos por selección de opciones (no texto libre).
- Algoritmo de repetición espaciada, variante simplificada de SM-2, por `LearningItem` y usuario.
- Sección "Repaso" en `CourseScreen`, separada de las unidades/lecciones fijas, que arma una sesión dinámica con los `LearningItem` vencidos.
- Pantalla de progreso de solo lectura: % de lecciones completadas y estado de aprendizaje de los `LearningItem`, por unidad.

**Explícitamente fuera de esta fase:**
- Ejercicios de escuchar y hablar (requieren audio/permisos de micrófono; se evalúan en una Fase 2b posterior).
- Rachas, XP, límite de errores por sesión y cualquier gamificación (Fase 3).
- Monetización (Fase 4) y contenido real más allá del piloto (Fase 5).

## 2. Tipos de ejercicio nuevos

Ambos se resuelven tocando opciones, igual que el ejercicio de opción múltiple ya existente de la Fase 1 — evita toda la complejidad de validar texto libre (mayúsculas, tildes, espacios) y reusa el mismo patrón de interacción.

**Completar espacio (`fill_blank`):** una frase con un hueco y una fila de palabras para elegir (una correcta, el resto distractores).
```json
{"type": "fill_blank", "content": {"prompt": "I ___ to school every day.", "options": ["go", "goes", "going"]}, "correctAnswer": "go"}
```

**Ordenar palabras (`word_order`):** las palabras de una oración desordenadas; el usuario las toca en el orden que cree correcto, armándolas en una fila superior, con opción de destocar antes de confirmar.
```json
{"type": "word_order", "content": {"words": ["is", "black", "The", "cat"]}, "correctAnswer": "The cat is black"}
```

Ambos comparten la misma interfaz de resultado que `MultipleChoiceExercise` (`onAnswered(bool correct)`), así que `LessonScreen` los intercala con un `switch` sobre `exercise.type` sin cambios grandes en su lógica de secuencia/score.

## 3. Algoritmo de repetición espaciada

Variante simplificada de SM-2 (el algoritmo detrás de Anki), adaptada a que nuestros ejercicios solo dan una señal binaria (correcto/incorrecto), en vez de la escala de calidad 0-5 del SM-2 clásico.

Por cada `LearningItem` y usuario se mantiene:
- **`ease_factor`** (arranca en 2.5): qué tan rápido crecen los intervalos.
- **`repetitions`**: repasos correctos consecutivos.
- **`interval_days`**: cada cuántos días toca repasar.
- **`next_review_date`**.

Al responder un ejercicio ligado a un `LearningItem`:
- **Acierto:** `repetitions += 1`. Intervalo: 1 día (primera vez) → 6 días (segunda) → `intervalo_anterior × ease_factor` de ahí en más. `ease_factor` sube +0.05 (tope 2.8).
- **Falla:** `repetitions = 0`, intervalo vuelve a 1 día, `ease_factor` baja -0.2 (piso 1.3).

Es la formulación estándar de SM-2 mapeando "correcto" a una calidad alta y "falla" a una baja, en vez de una heurística inventada — comportamiento predecible y ya validado en otras apps de flashcards.

## 4. Modelo de datos

Tabla nueva en Supabase, vinculada a `learning_items` (Fase 1) y a `auth.users`:

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
```

RLS: cada usuario solo lee/escribe sus propias filas (`auth.uid() = user_id`, mismo patrón que `user_lesson_progress` de la Fase 1).

Una función SQL `get_due_learning_items()` devuelve, para el usuario autenticado, los `LearningItem` con `next_review_date <= current_date`, junto con un ejercicio existente que los practique (vía `exercise_learning_items`, ya presente desde la Fase 1). El cálculo de SM-2 en sí vive en una función SQL (`update_learning_item_progress(...)`), no duplicado entre cliente y servidor.

## 5. Integración: sección de Repaso y pantalla de progreso

**Sección "Repaso":** en `CourseScreen`, sobre las unidades/lecciones fijas, una tarjeta muestra cuántos ítems tocan hoy (ej. "5 para repasar"). Si hay al menos uno, es tocable y abre una sesión tipo `LessonScreen`, pero armada dinámicamente a partir de `get_due_learning_items()` en vez de una lección fija — reutiliza el mismo motor de ejercicios y lógica de secuencia/score; al responder cada ejercicio, además actualiza el estado SRS del `LearningItem` vía `submitReviewResult`. Sin ítems vencidos, la tarjeta muestra "Sin repasos pendientes hoy" y no es tocable.

**Pantalla de progreso:** accesible desde `CourseScreen` (ícono en el AppBar), solo lectura. Por unidad: % de lecciones completadas (ya disponible vía `user_lesson_progress`) y cuántos `LearningItem` de esa unidad están "aprendidos" (`repetitions` ≥ umbral, ej. 2) vs. "pendientes de repaso hoy".

## 6. Arquitectura técnica

Extiende lo construido en la Fase 1, sin cambiar decisiones de stack:

- **Widgets de ejercicio:** `FillBlankExercise` y `WordOrderExercise`, misma interfaz `{exercise, onAnswered}` que `MultipleChoiceExercise`. `LessonScreen` y la nueva pantalla/sesión de repaso eligen el widget según `exercise.type` con un `switch`.
- **`SrsRepository`** (nuevo, mismo patrón que `ProgressRepository`): interfaz con `Future<int> getDueCount()`, `Future<List<Exercise>> getDueExercises()`, `Future<void> submitReviewResult({required String learningItemId, required bool correct})`. La implementación concreta habla con Supabase (RPC `get_due_learning_items()` + `update_learning_item_progress()`).
- **`ProgressScreen`** (nueva): usa `ContentRepository` (ya existe) más una consulta nueva de progreso agregado por unidad.

## 7. Validación de la Fase 2

- Los dos ejercicios nuevos se pueden responder correcta e incorrectamente dentro de una lección, con el mismo comportamiento de scoring ya validado en la Fase 1 (cubierto por tests, igual que `MultipleChoiceExercise`).
- El repaso cambia con el tiempo: un ítem fallado hoy debe reaparecer como "debido" mañana; uno acertado varias veces seguidas debe espaciarse — verificable manipulando `next_review_date` directo en la base y confirmando que `get_due_learning_items()` lo refleja.
- La pantalla de progreso refleja con precisión lecciones completadas y estado de repaso, verificable con datos sembrados de prueba.
