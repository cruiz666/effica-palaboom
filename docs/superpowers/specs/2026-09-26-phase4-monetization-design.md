# Diseño: Fase 4 — Monetización (freemium + suscripción)

**Fecha:** 2026-09-26
**Estado:** Aprobado para pasar a plan de implementación

## 1. Visión y alcance de la Fase 4

Introduce el modelo freemium definido desde la Fase 1: contenido gratis con límite diario, y una suscripción mensual que lo elimina.

**Incluido en esta fase:**
- Límite de 3 lecciones fijas completadas por día (repasos/SRS quedan siempre ilimitados, sin cambios respecto a la Fase 3).
- Al intentar abrir una 4ta lección fija el mismo día, se muestra una pantalla de paywall en vez de la lección.
- Un solo producto de suscripción mensual que elimina el límite mientras esté activa.
- Arquitectura completa de "verdad en Supabase" (tabla de suscripciones + función SQL de estado), con un `PurchaseGateway` intercambiable: `MockPurchaseGateway` para desarrollo ahora, `RevenueCatPurchaseGateway` listo para cuando existan cuentas de Apple/Google.
- Edge Function de webhook de RevenueCat, escrita y probada con payloads simulados (sin cuenta real).

**Explícitamente fuera de esta fase:**
- Conexión real con App Store/Play Store (requiere cuentas de developer — pendiente, se activará en una fase futura sin cambios de arquitectura).
- Plan anual, períodos de prueba gratis, descuentos o cupones.
- El bot de IA conversacional mencionado en la Fase 1 como beneficio futuro de la suscripción — fuera de alcance, no se construye nada relacionado a él.
- Cambios al límite de errores por sesión o a las reglas de racha/XP de la Fase 3.

## 2. Reglas de negocio

**Contador diario de lecciones fijas:**
- Se cuentan las filas de `user_lesson_progress` con `completed_at::date = current_date` (zona horaria del servidor, mismo criterio que usa `record_activity()` en la Fase 3 con `current_date`).
- El límite es 3 por día para usuarios sin suscripción activa. Cada lección fija completada hoy cuenta, sin importar si esa lección ya se había completado antes ("lecciones nuevas" se refiere a lección fija vs. repaso, no a contenido nunca visto). Los repasos (SRS) no afectan ni son afectados por este contador.
- El contador se resetea solo por el cambio de fecha — no hay acumulación entre días ni columna de historial (a diferencia de la racha, aquí solo importa el día de hoy).

**Punto de bloqueo:**
- La verificación ocurre **antes** de entrar a la lección, no al enviarla — al tocar una lección fija en `CourseScreen`, se consulta el estado de entitlement; si no es premium y ya completó 3 hoy, se navega a `PaywallScreen` en lugar de `LessonScreen`.
- Si el usuario ya estaba dentro de una lección cuando cruzó la medianoche (caso extremo), esa lección en curso se puede terminar con normalidad — el límite solo aplica a la apertura de una lección nueva.

**Suscripción:**
- Un solo producto: mensual, activa/inactiva (sin períodos de gracia ni prueba gratis en esta fase).
- Mientras la suscripción esté activa (`status = 'active'` y `expires_at > now()`), el usuario nunca ve el paywall por límite diario, sin importar cuántas lecciones haya completado.
- Si la suscripción expira o se cancela, el usuario vuelve a estar sujeto al límite diario desde ese momento.

**Pantalla de Paywall:**
- Mensaje simple: cuántas lecciones gratis ya usó hoy, y un botón para suscribirse.
- Al tocar "Suscribirse", se invoca `PurchaseGateway.purchaseMonthly()`. Si tiene éxito, se muestra una confirmación y se puede volver a `CourseScreen` para intentar entrar a la lección de nuevo (ya sin bloqueo, porque el estado se vuelve a consultar en ese momento).

## 3. Modelo de datos

```sql
create table user_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'inactive' check (status in ('inactive', 'active', 'cancelled')),
  product_id text,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table user_subscriptions enable row level security;

-- Solo lectura para el propio usuario. Sin políticas de insert/update/delete
-- para 'authenticated' — todas las escrituras reales pasan por el rol de
-- servicio (la Edge Function del webhook), nunca por REST directo del cliente.
create policy "Users can view their own subscription state"
  on user_subscriptions for select using (auth.uid() = user_id);
```

Tres funciones/piezas:

- **`get_entitlement_state()`**: retorna `jsonb` con `{isPremium, freeLessonsUsedToday, freeLessonsLimit}`. `isPremium` = existe una fila con `status = 'active'` y `expires_at > now()`. `freeLessonsUsedToday` = `count(*)` de `user_lesson_progress` del usuario con `completed_at::date = current_date`. `freeLessonsLimit` = constante `3`.
- **`dev_mock_activate_subscription()`** *(temporal, solo desarrollo)*: `security definer`, hace upsert de `status = 'active'`, `product_id = 'dev_mock_monthly'`, `expires_at = now() + interval '30 days'` para el usuario autenticado. Otorgada a `authenticated` únicamente para poder probar el flujo de compra en la app antes de tener cuentas reales.
- La Edge Function del webhook (`supabase/functions/revenuecat-webhook/`) recibe eventos de RevenueCat, valida la firma/autorización del webhook, y hace upsert en `user_subscriptions` usando el rol de servicio.

**Nota de seguridad explícita:** `dev_mock_activate_subscription()` es una puerta de desarrollo — cualquier usuario autenticado podría llamarla para obtener premium gratis, ya que no valida ningún pago real. **Debe eliminarse o deshabilitarse antes de publicar la app en una tienda real.** El plan de implementación incluye esto como un ítem de seguimiento explícito para una fase futura (cuando existan cuentas reales de Apple/Google), no se resuelve dentro de esta fase.

## 4. Arquitectura técnica

Extiende el patrón de repositorios ya usado en las fases anteriores:

- **`EntitlementRepository`** (nuevo, mismo patrón que `GamificationRepository`): interfaz con `Future<EntitlementState> getState()`. `EntitlementState` es un modelo inmutable con `isPremium`, `freeLessonsUsedToday`, `freeLessonsLimit`. La implementación concreta (`SupabaseEntitlementRepository`) llama a `get_entitlement_state()` vía RPC.
- **`PurchaseGateway`** (nuevo): interfaz con `Future<bool> purchaseMonthly()` (retorna éxito/fracaso) y `Future<void> restorePurchases()` (para cuando el usuario reinstala la app — RevenueCat lo maneja nativamente). Dos implementaciones:
  - **`RevenueCatPurchaseGateway`**: envuelve el paquete `purchases_flutter`, llama a `Purchases.purchasePackage(...)`. Solo se instancia en plataformas nativas (iOS/Android) — en `main.dart`, se elige la implementación según `kIsWeb`.
  - **`MockPurchaseGateway`**: usado en web/Chrome y mientras no haya cuentas reales. `purchaseMonthly()` llama a `dev_mock_activate_subscription()` vía RPC y retorna éxito.
- **`CourseScreen`** (se modifica): antes de navegar a `LessonScreen` en el `onTap` de una lección fija, consulta `EntitlementRepository.getState()`. Si `isPremium == false` y `freeLessonsUsedToday >= freeLessonsLimit`, navega a `PaywallScreen` en su lugar. El repaso (Repaso card) no se toca — sigue sin restricción, como ya definió la Fase 3.
- **`PaywallScreen`** (nuevo widget): muestra "Ya usaste tus 3 lecciones gratis de hoy" + botón "Suscribirse" que llama a `PurchaseGateway.purchaseMonthly()`; si retorna éxito, muestra una confirmación y permite volver (`Navigator.pop`) — `CourseScreen` no necesita refrescar el entitlement inmediatamente porque el usuario vuelve a intentar abrir la lección, momento en el que se vuelve a consultar el estado.
- **Edge Function `revenuecat-webhook`**: recibe el POST de RevenueCat, valida el header de autorización (RevenueCat firma sus webhooks con un secret compartido), mapea el evento (`INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`) a un upsert en `user_subscriptions` usando el service role client. Se prueba con payloads simulados (curl/fetch con JSON de ejemplo tomado de la documentación de RevenueCat), no con eventos reales.

## 5. Validación de la Fase 4

- El contador diario refleja correctamente `user_lesson_progress` de hoy — verificable completando lecciones y consultando `get_entitlement_state()` directamente.
- Al llegar a 3 lecciones fijas completadas en el día, la 4ta abre `PaywallScreen` en vez de `LessonScreen`; los repasos siguen abriendo sin restricción.
- Tras "comprar" con `MockPurchaseGateway` (que activa `dev_mock_activate_subscription()`), el usuario deja de ver el paywall aunque haya superado el límite diario.
- La Edge Function del webhook procesa correctamente payloads simulados de `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION` y `EXPIRATION`, dejando `user_subscriptions` en el estado esperado en cada caso — verificable con `curl`/`fetch` contra la función local.
- Ningún usuario autenticado puede escribir en `user_subscriptions` vía REST directo (sin pasar por `dev_mock_activate_subscription()` o el webhook) — verificable intentando un `UPDATE`/`INSERT` directo vía el cliente autenticado y confirmando que RLS lo rechaza.
