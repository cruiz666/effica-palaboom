# Diseño: App de aprendizaje de idiomas

**Fecha:** 2026-09-07
**Estado:** Aprobado para pasar a plan de implementación

## 1. Visión y alcance del MVP

**Producto:** app móvil (iOS/Android) para aprender idiomas, con lecciones cortas, gamificadas y pensadas para "enganchar" sin ser infantiles. El objetivo de largo plazo es soportar múltiples idiomas; el objetivo inicial es validar rápido si la mecánica de aprendizaje y retención funciona.

**MVP:** un solo curso — **inglés** — con unas semanas de contenido (no un catálogo completo). El MVP debe validar dos cosas:
1. Que la mecánica de aprendizaje (estructura + repetición espaciada + gamificación) realmente engancha y la gente vuelve.
2. Que el pipeline de "agregar/editar contenido sin publicar una nueva versión de la app" funciona en la práctica.

**Incluido en el MVP:**
- Curso de inglés con unidades y lecciones organizadas por nivel (CEFR simplificado).
- Motor de ejercicios con múltiples tipos: opción múltiple, completar espacio, ordenar palabras, escuchar, y habla en **versión ligera** (grabar + comparar con audio nativo + verificación básica de que se dijo la frase correcta, vía speech-to-text nativo del sistema operativo — sin scoring fino de pronunciación).
- Repetición espaciada (SRS) por concepto aprendido, no por ejercicio.
- Gamificación: rachas (streaks), XP, límite de errores por sesión — tono adulto, no infantil.
- Cuenta de usuario y progreso sincronizado.
- Contenido editable remotamente (Supabase) sin republicar la app.
- Modelo freemium con suscripción (ver sección 4), con paywall inicial generoso.

**Fast-follow inmediato tras el MVP (v1.1):**
- Bot conversacional con IA para práctica de conversación.

**Explícitamente fuera de alcance por ahora:**
- Múltiples idiomas simultáneos (la arquitectura lo soporta, pero solo se construye contenido de inglés).
- Panel de administración visual (CMS) — el contenido se edita directo en Supabase; se construye un panel más amigable cuando se sumen colaboradores no técnicos.
- Scoring de pronunciación fino (tipo Azure Pronunciation Assessment).
- Funciones sociales (leaderboards, amigos, competencia).

## 2. Metodología pedagógica

Se combinan tres enfoques probados, cada uno resolviendo un problema distinto:

- **Estructura por niveles tipo CEFR (A1→C2, simplificado):** cada curso se organiza en unidades temáticas dentro de niveles. Resuelve la sensación de progreso y estructura claros.
- **Repetición espaciada (SRS) para retención:** cada palabra o estructura gramatical aprendida (`LearningItem`) reaparece en intervalos crecientes calculados según qué tan bien se recordó la última vez (algoritmo tipo SM-2). Resuelve que el aprendizaje se quede en memoria a largo plazo.
- **Gamificación con tono adulto:** rachas diarias, XP por lección, límite de errores por sesión, metas semanales — sin mascotas ni tono infantil, más cercano a una app de fitness/hábitos. Resuelve la retención de uso diario.

## 3. Modelo de datos / estructura de contenido

**Jerarquía de contenido** (vive en Supabase, editable sin republicar la app):

```
Course (ej. "Inglés para hispanohablantes")
 └─ Unit (agrupa por nivel CEFR, ej. "A1 - Presentaciones")
     └─ Lesson (ej. "Saludos básicos")
         └─ Exercise (tipo: opción múltiple, completar, ordenar palabras, escuchar, hablar)
```

- Cada `Exercise` tiene un campo `type` + contenido flexible (JSON) según el tipo, para poder agregar variantes de ejercicio sin cambiar el esquema de base de datos.
- Cada `Course` y `Unit` tiene estado `draft`/`published`; la app solo sincroniza contenido publicado.
- **`LearningItem`:** unidad atómica de conocimiento (ej. la palabra "breakfast" o una regla gramatical). Los ejercicios practican uno o varios `LearningItem`. El estado de repetición espaciada se calcula por usuario + `LearningItem`, no por ejercicio — así el sistema sabe qué tan bien se domina cada concepto independientemente de qué ejercicio se use para practicarlo.

**Progreso del usuario** (separado del contenido):
- Estado SRS por usuario + `LearningItem` (facilidad, próxima fecha de repaso, historial).
- Progreso por lección/unidad completada.
- Racha, XP, nivel.
- Enrollments (curso al que está inscrito).
- Entitlements (a qué tiene acceso pago — ver sección 4).

**Sincronización y offline:** la app sincroniza contenido publicado nuevo/modificado (por `updated_at`) al abrir, y lo cachea localmente (SQLite) para que las lecciones ya descargadas funcionen sin conexión. El progreso/SRS se sincroniza a Supabase cuando hay conexión; el dispositivo es la fuente de verdad mientras está offline, y el progreso es mayormente aditivo, por lo que no hace falta resolución de conflictos compleja.

## 4. Monetización

**Modelo elegido: Freemium + suscripción.**

- Contenido base gratis con límite (ej. cantidad de lecciones por día); suscripción mensual/anual desbloquea sin límites.
- La suscripción es también el lugar natural para, a futuro, incluir el bot de IA conversacional como beneficio premium, sin necesitar un segundo sistema de cobro — importante porque el bot tiene costo recurrente por uso.
- Escala mejor que un cobro único por curso cuando se agreguen más idiomas (una suscripción cubre todo, no hay que re-comprar por idioma).
- **Para el MVP específicamente:** el límite gratuito debe ser generoso (incluso todo el curso piloto gratis), porque el objetivo en esta etapa es validar retención y enganche, no maximizar ingreso. La tabla de `entitlements` se construye desde ahora para no rediseñar nada, pero el paywall real se activa/ajusta después vía configuración, una vez que haya datos de retención.
- **Infraestructura de pago:** RevenueCat sobre App Store/Google Play — maneja recibos y renovaciones, y expone el estado de suscripción para poblar `entitlements`.

## 5. Arquitectura técnica

- **App:** Flutter — un solo código para iOS/Android. Se eligió sobre React Native porque Flutter dibuja sus propios widgets en vez de usar los nativos de cada plataforma, dando consistencia visual exacta entre iOS/Android (requisito explícito del proyecto).
- **Backend:** Supabase (Postgres + Auth + Storage). Se eligió sobre Firebase porque el contenido (curso → unidad → lección → ejercicio) es naturalmente relacional, y porque Supabase tiene precio plano y predecible frente al cobro por lectura de Firestore — relevante para un proyecto mantenido por una sola persona. Es además open-source, por lo que self-hostear en el futuro (ej. EC2) es una migración de infraestructura, no una reescritura de la app, si algún día el volumen justifica el ahorro frente al costo de tiempo de operación.
- **Pagos:** RevenueCat (ver sección 4).
- **Separación motor/contenido:** el código de la app (tipos de ejercicio, algoritmo SRS, gamificación) es agnóstico al idioma; el contenido vive en Supabase. Agregar un idioma nuevo es, en su mayoría, trabajo de contenido, no de reconstrucción de la app — salvo que un idioma requiera un tipo de ejercicio nuevo (ej. declinaciones en alemán).
- **Voz (versión ligera del MVP):** grabación local + speech-to-text nativo del sistema operativo (Speech framework de iOS / SpeechRecognizer de Android), sin depender de un servicio de pago externo todavía.
- **Autoría de contenido:** por ahora se edita directo en Supabase (Table Editor); cuando se sumen colaboradores no técnicos, se construye un panel de administración encima del mismo esquema, sin migrar datos.

## 6. Casos límite y manejo de errores

- **Progreso offline:** el dispositivo es la fuente de verdad mientras no hay conexión; al reconectar, se sincroniza a Supabase de forma aditiva.
- **Repasos SRS acumulados** tras días sin abrir la app: se limita cuántos ítems vencidos se muestran por sesión, liberándolos gradualmente en vez de abrumar al usuario.
- **Suscripción vence estando offline:** se respeta el último estado de entitlement conocido durante un período de gracia corto, para no cortar una lección a mitad de camino.
- **Reconocimiento de voz falla** (sin permiso de micrófono, ambiente ruidoso, no reconoce): el ejercicio nunca bloquea el avance; se ofrece una opción manual de "marcar como dicho".
- **Contenido se actualiza en medio de una lección activa:** la sesión en curso usa la versión con la que arrancó; el cambio se aplica en la próxima sesión.
- **Racha y zonas horarias:** el "día" para efectos de racha se calcula en la zona horaria del dispositivo, no en UTC del servidor.

## 7. Validación del MVP

**Métricas de éxito, definidas antes del lanzamino:**
- Retención Día 1 / Día 7 (señal principal de que la mecánica engancha).
- % de usuarios que termina el curso piloto (calibración de dificultad/contenido).
- Racha promedio (proxy de qué tan "adictivo" resulta en la práctica).
- Interacción con la pantalla de paywall, aunque el acceso sea gratuito al inicio (señal temprana de intención de pago).

Se instrumenta con una tabla simple de eventos en Supabase o el free tier de una herramienta tipo PostHog — no se justifica infraestructura de analítica más pesada a este tamaño.

**Testing técnico:** la lógica del motor puro (cálculo de SRS, scoring de ejercicios, lógica de entitlements) se cubre con tests automatizados por ser lógica de negocio aislable. La UI se valida con QA manual en ambas plataformas antes de cada release, sin automatización de UI pesada a este tamaño de proyecto.

## 8. Dirección visual

El diseño de UI/UX detallado (pantallas, flujos de navegación) se define pantalla por pantalla durante la implementación, no como una etapa separada previa. Lo único fijado de antemano es la dirección de tema: **Midnight Teal** (paleta oscura con teal como color dominante/de acento). Cualquier decisión visual durante el desarrollo debe partir de esta base para mantener consistencia entre iOS/Android.
