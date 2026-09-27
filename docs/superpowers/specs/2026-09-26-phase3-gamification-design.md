# Diseño: Fase 3 — Gamificación (rachas, XP, límite de errores)

**Fecha:** 2026-09-26
**Estado:** Aprobado para pasar a plan de implementación

## 1. Visión y alcance de la Fase 3

Continúa sobre la Fase 2 (Motor de aprendizaje), ya mergeada a `master`. El objetivo de esta fase es la retención de uso diario: una racha, XP acumulado, un nivel simple derivado del XP, y un límite de errores por sesión que mete algo de tensión sin caer en una mecánica de "vidas" que se regeneran con el tiempo (más propia de apps infantiles).

**Incluido en esta fase:**
- Racha diaria: cualquier lección o repaso **completado** cuenta (no exige contenido nuevo específicamente).
- XP: +10 por cada respuesta correcta, en lección fija o en repaso.
- Nivel: derivado del XP total (`nivel = xp_total / 100 + 1`), no se guarda por separado.
- Límite de errores por sesión: al tercer error, la sesión (lección o repaso) termina de inmediato.
- Encabezado siempre visible en `CourseScreen` con racha, XP y nivel.

**Explícitamente fuera de esta fase:**
- Monetización (Fase 4) y contenido real más allá del piloto (Fase 5).
- Cualquier mecánica de "vidas"/corazones que se regeneren con el tiempo real.
- Funciones sociales (comparar racha/XP con otros usuarios, leaderboards).

## 2. Reglas del juego

**Racha:** se actualiza solo al **completar** una lección o repaso (no por respuesta individual, y no si la sesión termina cortada por el límite de errores).
- Si la última actividad registrada fue ayer → racha actual +1.
- Si ya hubo actividad hoy → sin cambio (ya contaba).
- Si hay un salto de uno o más días sin actividad → racha vuelve a 1.
- Primera actividad registrada → racha = 1.
- Se mantiene además `longest_streak` (récord histórico, nunca disminuye).

**XP:** +10 por cada respuesta correcta, otorgado en el momento en que se responde. No se revierte si la sesión termina cortada después por el límite de errores — la respuesta correcta ya ocurrió.

**Nivel:** puramente derivado del XP total en el momento de consultarlo, sin columna propia.

**Límite de errores:** un contador de errores por sesión (lección o repaso), que vive solo en memoria del cliente mientras dura esa sesión — no persiste entre sesiones. Al llegar a 3 errores:
- La sesión corta ahí mismo, sin procesar los ejercicios restantes.
- No se llama a la función de completar lección/repaso existente (Fases 1-2), por lo tanto tampoco se registra actividad de racha para esa sesión.
- Se muestra un mensaje ("Alcanzaste el límite de errores para esta sesión.") con una acción para volver al curso.

## 3. Modelo de datos

Tabla nueva, con el mismo patrón de RLS ya usado en las fases anteriores (`auth.uid() = user_id` para select/insert/update):

```sql
create table user_gamification_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  xp_total int not null default 0,
  current_streak int not null default 0,
  longest_streak int not null default 0,
  last_activity_date date
);
```

Tres funciones SQL (la lógica de racha/XP vive en SQL, no se duplica en Dart — mismo principio ya aplicado al algoritmo SRS de la Fase 2):

- **`add_xp(p_amount int)`**: suma `p_amount` al `xp_total` del usuario autenticado (crea la fila con ese valor si no existe todavía).
- **`record_activity()`**: implementa la lógica de racha descrita en la sección 2 (ayer→+1, hoy→sin cambio, salto→reinicia a 1, primera vez→1), actualiza `longest_streak` si el nuevo valor de `current_streak` lo supera, y actualiza `last_activity_date` a la fecha actual.
- **`get_gamification_state()`**: retorna `jsonb` con `{xpTotal, currentStreak, longestStreak, level}` para el usuario autenticado (fila inexistente → todos los valores en cero/nivel 1).

## 4. Arquitectura técnica

Extiende lo construido en las fases anteriores, mismo patrón de repositorios:

- **`GamificationRepository`** (nuevo, mismo patrón que `SrsRepository`): interfaz con `Future<GamificationState> getState()`, `Future<void> awardXp(int amount)`, `Future<void> recordActivity()`. La implementación concreta llama a las tres funciones SQL vía RPC.
- **`LessonScreen` y `ReviewSessionScreen`** (ya existentes, se modifican): al responder correctamente un ejercicio, llaman a `awardXp(10)` en segundo plano — mismo patrón `unawaited` ya usado para las actualizaciones SRS, de forma que un fallo al otorgar XP nunca bloquea ni interrumpe la sesión. Ambas pantallas suman además un contador local de errores (en memoria, reiniciado en cada sesión nueva); al llegar a 3, se muestra el estado de "límite de errores alcanzado" en vez de continuar, y no se llama a `recordActivity()`. Si la sesión termina normalmente (todos los ejercicios respondidos sin llegar al límite), sí se llama a `recordActivity()`, además de lo que cada pantalla ya hacía (`submitLessonResult` en `LessonScreen`; nada adicional en `ReviewSessionScreen`, que solo actualiza SRS).
- **`GamificationHeader`** (nuevo widget): se agrega a `CourseScreen`, sobre la tarjeta de Repaso, mostrando racha/XP/nivel en una línea (ej. "Racha: 3 días · 120 XP · Nivel 2"). Solo lectura, sin acciones.

## 5. Validación de la Fase 3

- La racha se comporta correctamente ante los tres casos de fecha (ayer, hoy, salto de días) — verificable manipulando `last_activity_date` directo en la base y llamando a `record_activity()`.
- El XP se acumula por cada respuesta correcta, tanto en lección fija como en repaso, sin bloquear la sesión si la llamada de red falla.
- El límite de errores corta la sesión exactamente al tercer error, sin registrar racha para esa sesión, y el XP ya ganado antes del corte se mantiene intacto.
- El encabezado en `CourseScreen` refleja los números reales tras completar actividad, verificable con datos de prueba.
