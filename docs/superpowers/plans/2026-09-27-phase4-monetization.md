# Fase 4: Monetización (freemium + suscripción) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a freemium model — 3 free lessons/day, a paywall past that limit, and a monthly subscription that removes it — with the subscription's source of truth in Supabase and a swappable purchase provider (mock now, RevenueCat later).

**Architecture:** Extends the existing repository pattern (`EntitlementRepository`, mirroring `GamificationRepository`) plus a new `PurchaseGateway` abstraction with two implementations (`MockPurchaseGateway` for local/web dev, `RevenueCatPurchaseGateway` for native builds once store accounts exist). All entitlement truth lives in Supabase (`user_subscriptions` table + `get_entitlement_state()` SQL function); a Supabase Edge Function receives RevenueCat webhook events and is the only real writer of that table.

**Tech Stack:** Flutter 3.24.5, Supabase (Postgres + Auth + Edge Functions/Deno), `purchases_flutter` package (RevenueCat SDK, added but not connectable until store accounts exist).

**Spec:** docs/superpowers/specs/2026-09-26-phase4-monetization-design.md

## Global Constraints

- Free tier limit: 3 lecciones fijas completadas por día (constante, tanto en SQL como en el modelo Dart). Los repasos (SRS) nunca cuentan ni son afectados.
- El bloqueo ocurre **antes** de navegar a `LessonScreen` (al hacer `onTap`), nunca al enviar el resultado.
- `user_subscriptions` no tiene políticas RLS de insert/update/delete para `authenticated` — todas las escrituras reales pasan por el rol de servicio (la Edge Function del webhook).
- `dev_mock_activate_subscription()` es una función temporal, solo para desarrollo — cualquier usuario autenticado podría llamarla para obtener premium gratis. Debe eliminarse o deshabilitarse antes de publicar la app en una tienda real (ítem de seguimiento explícito para una fase futura, no se resuelve en este plan).
- `PurchaseGateway` se selecciona según `kIsWeb`: `MockPurchaseGateway` en web, `RevenueCatPurchaseGateway` en nativo. La implementación de RevenueCat no puede probarse de punta a punta en esta fase (no hay cuentas de Apple/Google) — se implementa completa y correcta contra la API documentada del SDK, pero queda sin verificar hasta que existan esas cuentas, igual que la conexión real de compras quedó fuera de alcance en el spec.
- Todas las funciones SQL nuevas usan `set search_path = ''` y tablas calificadas con `public.`. `get_entitlement_state()` es `security invoker` (mismo patrón que el resto del proyecto); `dev_mock_activate_subscription()` es la única excepción — `security definer`, deliberadamente, porque su propósito es escribir una fila que el usuario normalmente no podría escribir.
- No se toca ninguna regla de racha/XP/límite de errores de la Fase 3.

---

### Task 1: Esquema SQL — suscripciones y estado de entitlement

**Files:**
- Create: `supabase/migrations/20260927000001_monetization_engine.sql`

**Interfaces:**
- Consumes: `user_lesson_progress` (Fase 1, columnas `user_id`, `completed_at`).
- Produces: tabla `user_subscriptions`; funciones SQL `get_entitlement_state()` → `jsonb {isPremium: bool, freeLessonsUsedToday: int, freeLessonsLimit: int}`, y `dev_mock_activate_subscription()` → `void`.

- [ ] **Step 1: Escribir la migración**

Crear `supabase/migrations/20260927000001_monetization_engine.sql`:

```sql
create table user_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'inactive' check (status in ('inactive', 'active', 'cancelled')),
  product_id text,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table user_subscriptions enable row level security;

-- Solo lectura para el propio usuario. Deliberadamente sin políticas de
-- insert/update/delete para 'authenticated' — todas las escrituras reales
-- pasan por el rol de servicio (la Edge Function del webhook de RevenueCat),
-- nunca por REST directo del cliente. Esto es lo que evita que un usuario se
-- autootorgue "premium" con una llamada directa a la tabla.
create policy "Users can view their own subscription state"
  on user_subscriptions for select using (auth.uid() = user_id);

create or replace function get_entitlement_state()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'isPremium', exists (
      select 1 from public.user_subscriptions
      where user_id = auth.uid()
        and status = 'active'
        and expires_at > now()
    ),
    'freeLessonsUsedToday', (
      select count(*)::int from public.user_lesson_progress
      where user_id = auth.uid()
        and completed_at::date = current_date
    ),
    'freeLessonsLimit', 3
  );
$$;

grant execute on function get_entitlement_state() to authenticated;

-- TEMPORAL, SOLO DESARROLLO. Otorga premium sin ninguna verificación de pago
-- real — necesario porque no existen cuentas de Apple/Google Developer
-- todavía, así que no hay forma de que un webhook real de RevenueCat
-- dispare esta escritura. security definer (a diferencia del resto de las
-- funciones del proyecto, que son security invoker) porque su propósito
-- explícito es escribir una fila que la política RLS de arriba no permite
-- escribir directamente al usuario autenticado.
--
-- DEBE eliminarse o deshabilitarse antes de publicar la app en una tienda
-- real — cualquier usuario autenticado puede llamarla para obtener premium
-- gratis, sin pagar nada.
create or replace function dev_mock_activate_subscription()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  insert into public.user_subscriptions (user_id, status, product_id, expires_at, updated_at)
  values (v_user_id, 'active', 'dev_mock_monthly', now() + interval '30 days', now())
  on conflict (user_id) do update set
    status = 'active',
    product_id = 'dev_mock_monthly',
    expires_at = now() + interval '30 days',
    updated_at = now();
end;
$$;

grant execute on function dev_mock_activate_subscription() to authenticated;
```

- [ ] **Step 2: Aplicar la migración y verificar que compila**

Run: `supabase db reset`
Expected: la migración se aplica sin errores (aparece en la lista de "Applying migration...").

- [ ] **Step 3: Verificación manual básica con psql**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values ('22222222-2222-2222-2222-222222222221', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'phase4-test@example.com', crypt('password123', gen_salt('bf')), now(), now(), now(), '{\"provider\":\"email\",\"providers\":[\"email\"]}', '{}');
"

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres <<'SQL'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222221","role":"authenticated"}';
select get_entitlement_state() as before_purchase;
select dev_mock_activate_subscription();
select get_entitlement_state() as after_purchase;
commit;
SQL
```

Expected: `before_purchase` = `{"isPremium": false, "freeLessonsUsedToday": 0, "freeLessonsLimit": 3}`. `after_purchase` = `{"isPremium": true, "freeLessonsUsedToday": 0, "freeLessonsLimit": 3}`.

- [ ] **Step 4: Verificar que RLS bloquea la escritura directa**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres <<'SQL'
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222221","role":"authenticated"}';
update user_subscriptions set status = 'active' where user_id = '22222222-2222-2222-2222-222222222221';
rollback;
SQL
```

Expected: `UPDATE 0` (la fila existe por el paso anterior, pero no hay política de update para `authenticated`, así que la sentencia no falla con error pero tampoco actualiza ninguna fila — RLS filtra la fila objetivo silenciosamente, que es el comportamiento correcto de Postgres para updates sin política de UPDATE que otorgue acceso).

- [ ] **Step 5: Dejar la base limpia y commitear**

```bash
supabase db reset
git add supabase/migrations/20260927000001_monetization_engine.sql
git commit -m "feat: add subscription schema and entitlement functions"
```

---

### Task 2: `EntitlementState` y `EntitlementRepository`

**Files:**
- Create: `mobile/lib/features/entitlement/entitlement_state.dart`
- Create: `mobile/lib/features/entitlement/entitlement_repository.dart`
- Test: `mobile/test/features/entitlement/entitlement_repository_test.dart`

**Interfaces:**
- Consumes: función SQL `get_entitlement_state()` (Task 1) vía RPC, que retorna `{isPremium, freeLessonsUsedToday, freeLessonsLimit}`.
- Produces: `EntitlementState { bool isPremium; int freeLessonsUsedToday; int freeLessonsLimit; bool get limitReached; EntitlementState.fromJson(Map<String, dynamic>) }`; `abstract class EntitlementRepository { Future<EntitlementState> getState(); }`; `SupabaseEntitlementRepository(SupabaseClient)`.

- [ ] **Step 1: Escribir el modelo**

Crear `mobile/lib/features/entitlement/entitlement_state.dart`:

```dart
class EntitlementState {
  const EntitlementState({
    required this.isPremium,
    required this.freeLessonsUsedToday,
    required this.freeLessonsLimit,
  });

  final bool isPremium;
  final int freeLessonsUsedToday;
  final int freeLessonsLimit;

  bool get limitReached => !isPremium && freeLessonsUsedToday >= freeLessonsLimit;

  factory EntitlementState.fromJson(Map<String, dynamic> json) {
    return EntitlementState(
      isPremium: json['isPremium'] as bool,
      freeLessonsUsedToday: json['freeLessonsUsedToday'] as int,
      freeLessonsLimit: json['freeLessonsLimit'] as int,
    );
  }
}
```

- [ ] **Step 2: Escribir el repositorio**

Crear `mobile/lib/features/entitlement/entitlement_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'entitlement_state.dart';

abstract class EntitlementRepository {
  Future<EntitlementState> getState();
}

class SupabaseEntitlementRepository implements EntitlementRepository {
  SupabaseEntitlementRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EntitlementState> getState() async {
    final result = await _client.rpc('get_entitlement_state');
    return EntitlementState.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
```

- [ ] **Step 3: Escribir los tests**

Crear `mobile/test/features/entitlement/entitlement_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_repository.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_state.dart';

class FakeEntitlementRepository implements EntitlementRepository {
  FakeEntitlementRepository({required this.state});
  EntitlementState state;

  @override
  Future<EntitlementState> getState() async => state;
}

void main() {
  test('EntitlementState.fromJson parses all three fields', () {
    final state = EntitlementState.fromJson({
      'isPremium': false,
      'freeLessonsUsedToday': 2,
      'freeLessonsLimit': 3,
    });

    expect(state.isPremium, false);
    expect(state.freeLessonsUsedToday, 2);
    expect(state.freeLessonsLimit, 3);
  });

  test('limitReached is true only when not premium and usage has reached the limit', () {
    const underLimit = EntitlementState(isPremium: false, freeLessonsUsedToday: 2, freeLessonsLimit: 3);
    const atLimit = EntitlementState(isPremium: false, freeLessonsUsedToday: 3, freeLessonsLimit: 3);
    const pastLimitButPremium = EntitlementState(isPremium: true, freeLessonsUsedToday: 5, freeLessonsLimit: 3);

    expect(underLimit.limitReached, false);
    expect(atLimit.limitReached, true);
    expect(pastLimitButPremium.limitReached, false);
  });

  test('getState returns the fake repository state', () async {
    final repo = FakeEntitlementRepository(
      state: const EntitlementState(isPremium: true, freeLessonsUsedToday: 0, freeLessonsLimit: 3),
    );

    final state = await repo.getState();

    expect(state.isPremium, true);
  });
}
```

- [ ] **Step 4: Ejecutar los tests**

Run: `cd mobile && flutter test test/features/entitlement/entitlement_repository_test.dart`
Expected: 3 tests pasan.

Nota (misma dinámica ya aceptada para `SupabaseGamificationRepository` en la Fase 3): ningún test ejercita el RPC real de `SupabaseEntitlementRepository` — solo el parseo del modelo y un fake. El wiring real contra Supabase se verifica en la Tarea 7 (manual E2E).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/entitlement/entitlement_state.dart mobile/lib/features/entitlement/entitlement_repository.dart mobile/test/features/entitlement/entitlement_repository_test.dart
git commit -m "feat: add EntitlementState and EntitlementRepository"
```

---

### Task 3: `PurchaseGateway` (Mock + RevenueCat)

**Files:**
- Create: `mobile/lib/features/entitlement/purchase_gateway.dart`
- Modify: `mobile/pubspec.yaml`

**Interfaces:**
- Consumes: función SQL `dev_mock_activate_subscription()` (Task 1) vía RPC; paquete `purchases_flutter` (RevenueCat SDK).
- Produces: `abstract class PurchaseGateway { Future<bool> purchaseMonthly(); }`; `MockPurchaseGateway(SupabaseClient)`; `RevenueCatPurchaseGateway({required String apiKey})`.

- [ ] **Step 1: Agregar la dependencia**

En `mobile/pubspec.yaml`, dentro de `dependencies:`, agregar (junto a `supabase_flutter` y `shared_preferences`):

```yaml
  purchases_flutter: ^10.13.2
```

Run: `cd mobile && flutter pub get`
Expected: resuelve sin errores.

- [ ] **Step 2: Escribir el gateway**

Crear `mobile/lib/features/entitlement/purchase_gateway.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class PurchaseGateway {
  Future<bool> purchaseMonthly();
}

class MockPurchaseGateway implements PurchaseGateway {
  MockPurchaseGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> purchaseMonthly() async {
    await _client.rpc('dev_mock_activate_subscription');
    return true;
  }
}

class RevenueCatPurchaseGateway implements PurchaseGateway {
  RevenueCatPurchaseGateway({required this.apiKey});

  final String apiKey;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _configured = true;
  }

  @override
  Future<bool> purchaseMonthly() async {
    await _ensureConfigured();
    try {
      final offerings = await Purchases.getOfferings();
      final package = offerings.current?.monthly;
      if (package == null) return false;
      await Purchases.purchase(PurchaseParams.package(package));
      return true;
    } on PlatformException {
      return false;
    }
  }
}
```

- [ ] **Step 3: Verificar que el proyecto compila y la suite existente sigue verde**

Run: `cd mobile && flutter test`
Expected: todos los tests existentes siguen pasando (este archivo no tiene tests propios — ver la nota abajo).

Nota: no hay un archivo de test dedicado para `purchase_gateway.dart` en esta tarea. `MockPurchaseGateway` envuelve un `SupabaseClient` real (mismo problema que `SupabaseEntitlementRepository`/`SupabaseGamificationRepository`: no hay forma de fakear el cliente de Supabase de forma barata), y `RevenueCatPurchaseGateway` envuelve un plugin nativo que no puede ejecutarse en el entorno de test. Ambos se ejercitan indirectamente: `RevenueCatPurchaseGateway` mediante `PaywallScreen`/`CourseScreen`'s tests (Tareas 4-5), que usan un `FakePurchaseGateway` que implementa la misma interfaz — y de punta a punta contra el RPC real en la Tarea 7 (manual E2E) para `MockPurchaseGateway`. La implementación de RevenueCat en sí queda sin verificar hasta que existan cuentas reales, como ya establece el spec.

- [ ] **Step 4: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/features/entitlement/purchase_gateway.dart
git commit -m "feat: add PurchaseGateway with Mock and RevenueCat implementations"
```

---

### Task 4: `PaywallScreen`

**Files:**
- Create: `mobile/lib/features/entitlement/paywall_screen.dart`
- Test: `mobile/test/features/entitlement/paywall_screen_test.dart`

**Interfaces:**
- Consumes: `PurchaseGateway` (Task 3).
- Produces: `PaywallScreen({required int freeLessonsUsedToday, required int freeLessonsLimit, required PurchaseGateway purchaseGateway})`.

- [ ] **Step 1: Escribir el widget**

Crear `mobile/lib/features/entitlement/paywall_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'purchase_gateway.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.freeLessonsUsedToday,
    required this.freeLessonsLimit,
    required this.purchaseGateway,
  });

  final int freeLessonsUsedToday;
  final int freeLessonsLimit;
  final PurchaseGateway purchaseGateway;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isPurchasing = false;
  bool _purchased = false;
  bool _purchaseFailed = false;

  Future<void> _purchase() async {
    setState(() {
      _isPurchasing = true;
      _purchaseFailed = false;
    });
    final success = await widget.purchaseGateway.purchaseMonthly();
    if (!mounted) return;
    setState(() {
      _isPurchasing = false;
      _purchased = success;
      _purchaseFailed = !success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suscripción')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_purchased) ...[
                const Text('¡Listo! Ya eres usuario premium.'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver al curso'),
                ),
              ] else ...[
                Text(
                  'Ya usaste tus ${widget.freeLessonsUsedToday} lecciones gratis de hoy '
                  '(límite: ${widget.freeLessonsLimit}).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_purchaseFailed) ...[
                  const Text('No se pudo completar la suscripción. Intenta de nuevo.'),
                  const SizedBox(height: 16),
                ],
                ElevatedButton(
                  onPressed: _isPurchasing ? null : _purchase,
                  child: _isPurchasing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Suscribirse'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Escribir los tests**

Crear `mobile/test/features/entitlement/paywall_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/entitlement/paywall_screen.dart';
import 'package:effica_palaboom/features/entitlement/purchase_gateway.dart';

class FakePurchaseGateway implements PurchaseGateway {
  FakePurchaseGateway({this.shouldSucceed = true});
  final bool shouldSucceed;
  int purchaseCalls = 0;

  @override
  Future<bool> purchaseMonthly() async {
    purchaseCalls++;
    return shouldSucceed;
  }
}

void main() {
  testWidgets('shows how many free lessons were used today', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        freeLessonsUsedToday: 3,
        freeLessonsLimit: 3,
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));

    expect(find.textContaining('Ya usaste tus 3 lecciones gratis de hoy'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Suscribirse'), findsOneWidget);
  });

  testWidgets('tapping Suscribirse calls purchaseMonthly and shows success', (tester) async {
    final gateway = FakePurchaseGateway();
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        freeLessonsUsedToday: 3,
        freeLessonsLimit: 3,
        purchaseGateway: gateway,
      ),
    ));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, 1);
    expect(find.text('¡Listo! Ya eres usuario premium.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Volver al curso'), findsOneWidget);
  });

  testWidgets('a failed purchase shows an error message and allows retry', (tester) async {
    final gateway = FakePurchaseGateway(shouldSucceed: false);
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        freeLessonsUsedToday: 3,
        freeLessonsLimit: 3,
        purchaseGateway: gateway,
      ),
    ));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo completar la suscripción. Intenta de nuevo.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Suscribirse'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, 2);
  });
}
```

- [ ] **Step 3: Ejecutar los tests**

Run: `cd mobile && flutter test test/features/entitlement/paywall_screen_test.dart`
Expected: 3 tests pasan.

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/features/entitlement/paywall_screen.dart mobile/test/features/entitlement/paywall_screen_test.dart
git commit -m "feat: add PaywallScreen"
```

---

### Task 5: Wiring completo — `CourseScreen`, `App`, `main.dart`

**Files:**
- Modify: `mobile/lib/features/course/course_screen.dart`
- Modify: `mobile/lib/app.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/test/features/course/course_screen_test.dart`
- Modify: `mobile/test/app_test.dart`

**Interfaces:**
- Consumes: `EntitlementRepository`/`EntitlementState` (Task 2), `PurchaseGateway`/`MockPurchaseGateway`/`RevenueCatPurchaseGateway` (Task 3), `PaywallScreen` (Task 4).
- Produces: `CourseScreen`/`App` ahora requieren también `required EntitlementRepository entitlementRepository` y `required PurchaseGateway purchaseGateway`.

Esta tarea toca los tres archivos (`CourseScreen`, `App`, `main.dart`) juntos, en un solo commit, precisamente para que el proyecto compile en todo momento — si solo se agregaran los parámetros nuevos a `CourseScreen` sin actualizar `App`/`main.dart` en el mismo paso, la construcción de `CourseScreen(...)` dentro de `App` dejaría de compilar.

- [ ] **Step 1: Actualizar el test de `CourseScreen`**

En `mobile/test/features/course/course_screen_test.dart`, agregar estos imports (junto a los existentes):

```dart
import 'package:effica_palaboom/features/entitlement/entitlement_repository.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_state.dart';
import 'package:effica_palaboom/features/entitlement/paywall_screen.dart';
import 'package:effica_palaboom/features/entitlement/purchase_gateway.dart';
```

Agregar estos dos fakes (junto a los fakes existentes como `FakeGamificationRepository`):

```dart
class FakeEntitlementRepository implements EntitlementRepository {
  FakeEntitlementRepository({
    this.state = const EntitlementState(isPremium: false, freeLessonsUsedToday: 0, freeLessonsLimit: 3),
  });
  final EntitlementState state;

  @override
  Future<EntitlementState> getState() async => state;
}

class FakePurchaseGateway implements PurchaseGateway {
  @override
  Future<bool> purchaseMonthly() async => true;
}
```

El archivo tiene SEIS construcciones de `CourseScreen(...)` (una por cada `testWidgets`). Agregar a las SEIS:

```dart
        entitlementRepository: FakeEntitlementRepository(),
        purchaseGateway: FakePurchaseGateway(),
```

(El `FakeEntitlementRepository()` por defecto está bajo el límite — 0 de 3 — así que las seis pruebas existentes siguen abriendo `LessonScreen` normalmente sin cambios de comportamiento.)

Agregar estos dos tests nuevos al final de `main()`, antes del cierre:

```dart
  testWidgets('opens PaywallScreen instead of LessonScreen when the daily limit is reached',
      (tester) async {
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(
          state: const EntitlementState(isPremium: false, freeLessonsUsedToday: 3, freeLessonsLimit: 3),
        ),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.byType(LessonScreen), findsNothing);
  });

  testWidgets('opens LessonScreen even past the daily limit when the user is premium',
      (tester) async {
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(
          state: const EntitlementState(isPremium: true, freeLessonsUsedToday: 5, freeLessonsLimit: 3),
        ),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonScreen), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);
  });
```

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `cd mobile && flutter test test/features/course/course_screen_test.dart`
Expected: FAIL — `CourseScreen` no acepta `entitlementRepository`/`purchaseGateway` todavía.

- [ ] **Step 3: Implementar — `course_screen.dart`**

Reemplazar el contenido completo de `mobile/lib/features/course/course_screen.dart` por:

```dart
import 'package:flutter/material.dart';
import '../content/content_repository.dart';
import '../content/models/course.dart';
import '../entitlement/entitlement_repository.dart';
import '../entitlement/paywall_screen.dart';
import '../entitlement/purchase_gateway.dart';
import '../gamification/gamification_header.dart';
import '../gamification/gamification_repository.dart';
import '../gamification/gamification_state.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/progress_repository.dart';
import '../progress/progress_screen.dart';
import '../progress/progress_summary_repository.dart';
import '../srs/review_session_screen.dart';
import '../srs/srs_repository.dart';

class CourseScreen extends StatefulWidget {
  const CourseScreen({
    super.key,
    required this.contentRepository,
    required this.progressRepository,
    required this.srsRepository,
    required this.progressSummaryRepository,
    required this.gamificationRepository,
    required this.entitlementRepository,
    required this.purchaseGateway,
  });

  final ContentRepository contentRepository;
  final ProgressRepository progressRepository;
  final SrsRepository srsRepository;
  final ProgressSummaryRepository progressSummaryRepository;
  final GamificationRepository gamificationRepository;
  final EntitlementRepository entitlementRepository;
  final PurchaseGateway purchaseGateway;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  late Future<Course> _courseFuture = widget.contentRepository.getActiveCourse();
  late Future<int> _dueCountFuture = widget.srsRepository.getDueCount();
  late Future<GamificationState> _gamificationStateFuture = widget.gamificationRepository.getState();
  bool _isOpeningReview = false;
  bool _isOpeningLesson = false;

  void _retry() {
    final future = widget.contentRepository.getActiveCourse();
    // Mark this future's error (if any) as handled synchronously, before the
    // setState below yields control back to the event loop. Without this, if
    // the future rejects in a microtask that runs before FutureBuilder
    // resubscribes on the next build, it surfaces as an unhandled async
    // error instead of being routed through snapshot.hasError. FutureBuilder
    // still gets its own independent listener on the same future once it
    // rebuilds, so the error still reaches the UI.
    future.ignore();
    setState(() {
      _courseFuture = future;
    });
  }

  @override
  Widget build(BuildContext context) {
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
        future: _courseFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No se pudo cargar el curso.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final course = snapshot.data!;
          final units = [...course.units]
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          return ListView(
            children: [
              FutureBuilder<GamificationState>(
                future: _gamificationStateFuture,
                builder: (context, gamificationSnapshot) {
                  if (!gamificationSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  return GamificationHeader(state: gamificationSnapshot.data!);
                },
              ),
              FutureBuilder<int>(
                future: _dueCountFuture,
                builder: (context, dueSnapshot) {
                  if (dueSnapshot.hasError) {
                    return const Card(
                      child: ListTile(
                        title: Text('Repaso'),
                        subtitle: Text('No se pudo cargar el repaso.'),
                      ),
                    );
                  }
                  final dueCount = dueSnapshot.data ?? 0;
                  return Card(
                    child: ListTile(
                      title: const Text('Repaso'),
                      subtitle: Text(
                        dueCount > 0 ? '$dueCount para repasar' : 'Sin repasos pendientes hoy',
                      ),
                      onTap: dueCount == 0 || _isOpeningReview || _isOpeningLesson
                          ? null
                          : () async {
                              setState(() => _isOpeningReview = true);
                              try {
                                final exercises = await widget.srsRepository.getDueExercises();
                                if (!context.mounted) return;
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ReviewSessionScreen(
                                      exercises: exercises,
                                      srsRepository: widget.srsRepository,
                                      gamificationRepository: widget.gamificationRepository,
                                    ),
                                  ),
                                );
                                if (!context.mounted) return;
                                final dueCountFuture = widget.srsRepository.getDueCount();
                                final gamificationStateFuture =
                                    widget.gamificationRepository.getState();
                                // See _retry() above for why these futures are marked
                                // as handled before setState: otherwise a rejection
                                // that happens before the next FutureBuilder rebuild
                                // subscribes would surface as an unhandled async error.
                                dueCountFuture.ignore();
                                gamificationStateFuture.ignore();
                                setState(() {
                                  _dueCountFuture = dueCountFuture;
                                  _gamificationStateFuture = gamificationStateFuture;
                                });
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No se pudo abrir el repaso. Intenta de nuevo.'),
                                  ),
                                );
                              } finally {
                                if (context.mounted) setState(() => _isOpeningReview = false);
                              }
                            },
                    ),
                  );
                },
              ),
              for (final unit in units) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(unit.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                for (final lesson in [...unit.lessons]
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
                  ListTile(
                    title: Text(lesson.title),
                    onTap: _isOpeningReview || _isOpeningLesson
                        ? null
                        : () async {
                            setState(() => _isOpeningLesson = true);
                            try {
                              final entitlement = await widget.entitlementRepository.getState();
                              if (!context.mounted) return;
                              if (entitlement.limitReached) {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PaywallScreen(
                                      freeLessonsUsedToday: entitlement.freeLessonsUsedToday,
                                      freeLessonsLimit: entitlement.freeLessonsLimit,
                                      purchaseGateway: widget.purchaseGateway,
                                    ),
                                  ),
                                );
                              } else {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => LessonScreen(
                                      lesson: lesson,
                                      progressRepository: widget.progressRepository,
                                      srsRepository: widget.srsRepository,
                                      gamificationRepository: widget.gamificationRepository,
                                    ),
                                  ),
                                );
                              }
                              if (!context.mounted) return;
                              final dueCountFuture = widget.srsRepository.getDueCount();
                              final gamificationStateFuture =
                                  widget.gamificationRepository.getState();
                              // See _retry() above for why these futures are marked as
                              // handled before setState: otherwise a rejection that happens
                              // before the next FutureBuilder rebuild subscribes would
                              // surface as an unhandled async error.
                              dueCountFuture.ignore();
                              gamificationStateFuture.ignore();
                              setState(() {
                                _dueCountFuture = dueCountFuture;
                                _gamificationStateFuture = gamificationStateFuture;
                              });
                            } finally {
                              if (context.mounted) setState(() => _isOpeningLesson = false);
                            }
                          },
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

- [ ] **Step 4: Implementar — `app.dart`**

Reemplazar el contenido completo de `mobile/lib/app.dart` por:

```dart
import 'package:flutter/material.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/content/content_repository.dart';
import 'features/course/course_screen.dart';
import 'features/entitlement/entitlement_repository.dart';
import 'features/entitlement/purchase_gateway.dart';
import 'features/gamification/gamification_repository.dart';
import 'features/lesson/progress_repository.dart';
import 'features/progress/progress_summary_repository.dart';
import 'features/srs/srs_repository.dart';
import 'theme/app_theme.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.authRepository,
    required this.contentRepository,
    required this.progressRepository,
    required this.srsRepository,
    required this.progressSummaryRepository,
    required this.gamificationRepository,
    required this.entitlementRepository,
    required this.purchaseGateway,
  });

  final AuthRepository authRepository;
  final ContentRepository contentRepository;
  final ProgressRepository progressRepository;
  final SrsRepository srsRepository;
  final ProgressSummaryRepository progressSummaryRepository;
  final GamificationRepository gamificationRepository;
  final EntitlementRepository entitlementRepository;
  final PurchaseGateway purchaseGateway;

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
            srsRepository: srsRepository,
            progressSummaryRepository: progressSummaryRepository,
            gamificationRepository: gamificationRepository,
            entitlementRepository: entitlementRepository,
            purchaseGateway: purchaseGateway,
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Implementar — `main.dart`**

Reemplazar el contenido completo de `mobile/lib/main.dart` por:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'features/auth/auth_repository.dart';
import 'features/content/content_cache.dart';
import 'features/content/content_remote_data_source.dart';
import 'features/content/content_repository.dart';
import 'features/entitlement/entitlement_repository.dart';
import 'features/entitlement/purchase_gateway.dart';
import 'features/gamification/gamification_repository.dart';
import 'features/lesson/progress_repository.dart';
import 'features/progress/progress_summary_repository.dart';
import 'features/srs/srs_repository.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _revenueCatApiKey = String.fromEnvironment('REVENUECAT_API_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL / SUPABASE_ANON_KEY. Run with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
  }
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );
  final client = Supabase.instance.client;
  final purchaseGateway = kIsWeb
      ? MockPurchaseGateway(client)
      : RevenueCatPurchaseGateway(apiKey: _revenueCatApiKey);
  runApp(App(
    authRepository: SupabaseAuthRepository(client),
    contentRepository: ContentRepository(
      remoteDataSource: SupabaseContentRemoteDataSource(client),
      cache: SharedPreferencesContentCache(),
    ),
    progressRepository: SupabaseProgressRepository(client),
    srsRepository: SupabaseSrsRepository(client),
    progressSummaryRepository: SupabaseProgressSummaryRepository(client),
    gamificationRepository: SupabaseGamificationRepository(client),
    entitlementRepository: SupabaseEntitlementRepository(client),
    purchaseGateway: purchaseGateway,
  ));
}
```

- [ ] **Step 6: Actualizar `app_test.dart`**

En `mobile/test/app_test.dart`, agregar estos imports:

```dart
import 'package:effica_palaboom/features/entitlement/entitlement_repository.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_state.dart';
import 'package:effica_palaboom/features/entitlement/purchase_gateway.dart';
```

Agregar estos dos fakes (junto a `FakeGamificationRepository`):

```dart
class FakeEntitlementRepository implements EntitlementRepository {
  @override
  Future<EntitlementState> getState() async =>
      const EntitlementState(isPremium: false, freeLessonsUsedToday: 0, freeLessonsLimit: 3);
}

class FakePurchaseGateway implements PurchaseGateway {
  @override
  Future<bool> purchaseMonthly() async => true;
}
```

En la única construcción de `App(...)`, agregar:

```dart
      entitlementRepository: FakeEntitlementRepository(),
      purchaseGateway: FakePurchaseGateway(),
```

- [ ] **Step 7: Ejecutar toda la suite**

Run: `cd mobile && flutter test`
Expected: todos los tests pasan (los 46 existentes + los 8 nuevos de esta tarea y las anteriores: 3 de `entitlement_repository_test.dart`, 3 de `paywall_screen_test.dart`, 2 nuevos en `course_screen_test.dart` = 54 en total).

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/features/course/course_screen.dart mobile/lib/app.dart mobile/lib/main.dart mobile/test/features/course/course_screen_test.dart mobile/test/app_test.dart
git commit -m "feat: gate lesson access behind daily free limit and paywall"
```

---

### Task 6: Edge Function del webhook de RevenueCat

**Files:**
- Create: `supabase/functions/revenuecat-webhook/index.ts`
- Modify: `supabase/config.toml`
- Create: `supabase/functions/.env.local` (no se commitea — ver Step 3)

**Interfaces:**
- Consumes: `user_subscriptions` (Task 1), payloads de webhook de RevenueCat (`{event: {type, app_user_id, product_id, expiration_at_ms}}`).
- Produces: endpoint HTTP `POST /functions/v1/revenuecat-webhook` que hace upsert en `user_subscriptions` usando el rol de servicio.

- [ ] **Step 1: Escribir la función**

Crear `supabase/functions/revenuecat-webhook/index.ts`:

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const WEBHOOK_AUTHORIZATION = Deno.env.get("REVENUECAT_WEBHOOK_AUTHORIZATION") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Eventos de RevenueCat que cambian el estado de la suscripción. Cualquier
// otro tipo de evento (ej. BILLING_ISSUE, PRODUCT_CHANGE) se acepta con 200
// pero se ignora — no hay nada que este esquema simple necesite reflejar
// para esos casos.
function statusForEventType(eventType: string): "active" | "cancelled" | "inactive" | null {
  switch (eventType) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
      return "active";
    case "CANCELLATION":
      return "cancelled";
    case "EXPIRATION":
      return "inactive";
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (WEBHOOK_AUTHORIZATION === "" || req.headers.get("Authorization") !== WEBHOOK_AUTHORIZATION) {
    return new Response("Unauthorized", { status: 401 });
  }

  let body: { event?: { type?: string; app_user_id?: string; product_id?: string; expiration_at_ms?: number } };
  try {
    body = await req.json();
  } catch {
    return new Response("Malformed JSON", { status: 400 });
  }

  const event = body.event;
  if (!event || !event.app_user_id || !event.type) {
    return new Response("Malformed payload", { status: 400 });
  }

  const status = statusForEventType(event.type);
  if (status === null) {
    return new Response(JSON.stringify({ ok: true, ignored: true }), { status: 200 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { error } = await supabase.from("user_subscriptions").upsert({
    user_id: event.app_user_id,
    status,
    product_id: event.product_id ?? null,
    expires_at: event.expiration_at_ms ? new Date(event.expiration_at_ms).toISOString() : null,
    updated_at: new Date().toISOString(),
  });

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true }), { status: 200 });
});
```

- [ ] **Step 2: Configurar la función para saltar la verificación de JWT de Supabase**

Esta función la invoca RevenueCat, no un usuario con sesión de Supabase — su propio header `Authorization` es el secreto compartido del webhook, no un JWT de Supabase. Agregar al final de `supabase/config.toml`:

```toml
[functions.revenuecat-webhook]
verify_jwt = false
```

- [ ] **Step 3: Crear el archivo de variables de entorno local (no se commitea)**

Crear `supabase/functions/.env.local` con:

```
REVENUECAT_WEBHOOK_AUTHORIZATION=test-secret-for-local-dev
```

Confirmar que git lo ignora (ya está cubierto por el patrón `.env.local` en `supabase/.gitignore`):

```bash
git check-ignore supabase/functions/.env.local
```

Expected: imprime la ruta (confirma que está ignorado). Si no imprime nada, DETENERSE y agregar `supabase/functions/.env.local` a `supabase/.gitignore` antes de continuar — nunca commitear este archivo.

- [ ] **Step 4: Levantar la función localmente y probarla con payloads simulados**

```bash
cd /Users/carlosruiz/Workspace/effica-palaboom
supabase functions serve revenuecat-webhook --no-verify-jwt --env-file supabase/functions/.env.local &
sleep 3

# Necesitamos un usuario real para que el upsert no falle por la FK a auth.users.
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values ('33333333-3333-3333-3333-333333333331', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'webhook-test@example.com', crypt('password123', gen_salt('bf')), now(), now(), now(), '{\"provider\":\"email\",\"providers\":[\"email\"]}', '{}')
on conflict (id) do nothing;
"

# INITIAL_PURCHASE -> active
curl -s -i -X POST http://127.0.0.1:54321/functions/v1/revenuecat-webhook \
  -H "Authorization: test-secret-for-local-dev" \
  -H "Content-Type: application/json" \
  -d '{"event": {"type": "INITIAL_PURCHASE", "app_user_id": "33333333-3333-3333-3333-333333333331", "product_id": "monthly", "expiration_at_ms": 4102444800000}}'

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select status, product_id from user_subscriptions where user_id = '33333333-3333-3333-3333-333333333331';"

# CANCELLATION -> cancelled
curl -s -i -X POST http://127.0.0.1:54321/functions/v1/revenuecat-webhook \
  -H "Authorization: test-secret-for-local-dev" \
  -H "Content-Type: application/json" \
  -d '{"event": {"type": "CANCELLATION", "app_user_id": "33333333-3333-3333-3333-333333333331", "product_id": "monthly"}}'

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select status, product_id from user_subscriptions where user_id = '33333333-3333-3333-3333-333333333331';"

# RENEWAL -> active again (e.g. after a CANCELLATION was reversed, or a normal renewal)
curl -s -i -X POST http://127.0.0.1:54321/functions/v1/revenuecat-webhook \
  -H "Authorization: test-secret-for-local-dev" \
  -H "Content-Type: application/json" \
  -d '{"event": {"type": "RENEWAL", "app_user_id": "33333333-3333-3333-3333-333333333331", "product_id": "monthly", "expiration_at_ms": 4102444800000}}'

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select status, product_id from user_subscriptions where user_id = '33333333-3333-3333-3333-333333333331';"

# EXPIRATION -> inactive
curl -s -i -X POST http://127.0.0.1:54321/functions/v1/revenuecat-webhook \
  -H "Authorization: test-secret-for-local-dev" \
  -H "Content-Type: application/json" \
  -d '{"event": {"type": "EXPIRATION", "app_user_id": "33333333-3333-3333-3333-333333333331", "product_id": "monthly"}}'

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select status, product_id from user_subscriptions where user_id = '33333333-3333-3333-3333-333333333331';"

# Authorization incorrecto -> 401
curl -s -i -X POST http://127.0.0.1:54321/functions/v1/revenuecat-webhook \
  -H "Authorization: wrong-secret" \
  -H "Content-Type: application/json" \
  -d '{"event": {"type": "INITIAL_PURCHASE", "app_user_id": "33333333-3333-3333-3333-333333333331"}}'

kill %1
```

Expected: la primera `curl` (INITIAL_PURCHASE) retorna `{"ok":true}` (HTTP 200) y la consulta subsiguiente muestra `status = active, product_id = monthly`. La segunda (CANCELLATION) retorna `{"ok":true}` y la consulta muestra `status = cancelled`. La tercera (RENEWAL) retorna `{"ok":true}` y la consulta muestra `status = active` de nuevo. La cuarta (EXPIRATION) muestra `status = inactive`. La quinta `curl` (`Authorization` incorrecto) retorna `401 Unauthorized`.

- [ ] **Step 5: Dejar la base limpia**

```bash
supabase db reset
```

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/revenuecat-webhook/index.ts supabase/config.toml
git commit -m "feat: add RevenueCat webhook Edge Function"
```

(No se commitea `supabase/functions/.env.local` — queda ignorado por git, es solo para pruebas locales.)

---

### Task 7: Verificación manual de punta a punta

**Files:** ninguno (verificación, no código nuevo).

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: confirmación de que el límite diario, el paywall, la compra simulada y la protección RLS funcionan contra Supabase local real.

- [ ] **Step 1: Levantar Supabase local limpio**

```bash
supabase db reset
```

- [ ] **Step 2: Correr la app y agotar el límite diario**

```bash
cd mobile
flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<anon-key-de-supabase-status>
```

Regístrate o inicia sesión con un usuario. Completa 3 lecciones fijas distintas (o la misma lección 3 veces, si el curso sembrado no tiene 3 lecciones — el contador cuenta cualquier envío, no lecciones distintas). Confirma que después de la 3ra, al tocar cualquier lección fija, se abre la pantalla de "Suscripción" (`PaywallScreen`) mostrando "Ya usaste tus 3 lecciones gratis de hoy (límite: 3)." en vez de la lección. Confirma que el Repaso sigue abriéndose sin restricción durante todo este proceso.

- [ ] **Step 3: Confirmar el estado en la base de datos antes de comprar**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select count(*) from user_subscriptions;"
```

Expected: `0` filas — todavía no existe ninguna suscripción para ningún usuario.

- [ ] **Step 4: "Comprar" desde el paywall**

En la app, con el paywall abierto, toca "Suscribirse". Como corres en Chrome, esto usa `MockPurchaseGateway`. Confirma que aparece "¡Listo! Ya eres usuario premium." Toca "Volver al curso" y confirma que ahora SÍ se puede abrir cualquier lección fija sin ver el paywall, sin importar cuántas ya se completaron hoy.

- [ ] **Step 5: Confirmar el estado en la base de datos después de comprar**

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -c "select status, product_id, expires_at > now() as still_valid from user_subscriptions;"
```

Expected: una fila con `status = active`, `product_id = dev_mock_monthly`, `still_valid = t`.

- [ ] **Step 6: Confirmar que RLS sigue bloqueando la escritura directa**

Con la app todavía abierta y con sesión iniciada, intenta forzar una escritura directa a la tabla de suscripciones vía el cliente autenticado (simulando lo que un atacante intentaría hacer sin pasar por `dev_mock_activate_subscription()` ni por el webhook):

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres <<'SQL'
begin;
set local role authenticated;
set local request.jwt.claims = (select json_build_object('sub', user_id, 'role', 'authenticated')::text from user_subscriptions limit 1);
insert into user_subscriptions (user_id, status) values (gen_random_uuid(), 'active');
rollback;
SQL
```

Expected: `INSERT 0 0` o un error de política — en cualquier caso, ninguna fila nueva queda escrita (confirmar con `select count(*) from user_subscriptions;` antes y después, deben coincidir).

Con esto queda validada la Fase 4 de punta a punta.
