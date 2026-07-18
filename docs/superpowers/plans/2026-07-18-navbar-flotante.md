# Barra flotante con botón central por rol — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sustituir el `NavigationBar` de Material por una píldora flotante con botón circular central contextual por rol, y añadir los dos destinos de métricas que ese botón deja hueco (Reputación / Estadísticas) más el toggle "Para ti · Todas" en el inbox del proveedor.

**Architecture:** La barra se parte en dos piezas: `nav_destinations.dart` (lógica pura: rol → destinos, ruta → índice activo, sin un solo widget) y `floating_nav_bar.dart` (puro dibujo: no sabe de rutas ni de roles, recibe destinos e índice). `home_shell.dart` se queda solo con lo que le toca — resolver el índice y navegar. Las dos pantallas nuevas son de solo lectura sobre RPCs que ya existen en producción.

**Tech Stack:** Flutter 3.44.6 (`C:\dev\flutter`), go_router, supabase_flutter, flutter_animate. Paquete: `jayalo_app`. Todos los comandos se corren desde `C:\Users\ac\Downloads\jayalo-app\app`.

**Spec:** `docs/superpowers/specs/2026-07-18-navbar-flotante-design.md`

---

## Global Constraints

- **Cero backend nuevo.** Ninguna migración, ninguna Edge Function. Si una tarea parece necesitar SQL, es que algo se entendió mal — parar y preguntar.
- **Movimiento:** toda duración y curva sale de `JayaloMotion` (`lib/core/motion.dart`). Prohibido escribir `Duration(milliseconds: …)` o `Curves.…` sueltos en una pantalla. Toda animación se apaga con `JayaloMotion.reduced(context)`.
- **Color:** todo sale del `ColorScheme` del tema o de `JayaloColors`/`JayaloStatus` (`lib/core/brand.dart`). Prohibido `Colors.green`, `Colors.grey` y demás literales.
- **Widgets compartidos:** usar los de `features/shared/brand_kit.dart` (`JayaloCard`, `SectionHeader`, `EmptyState`, `ErrorRetry`, `cascadeIn`) y `JayaloLoaderBlock` de `jayalo_loader.dart` para cargas. No re-derivar radios ni paddings.
- **Copy en español dominicano, claro y sin jerga.** Público analógico: nada de "métricas", "KPI", "dashboard".
- **El catálogo de productos NO se construye aquí** (decisión PO). Solo aparece como cifra en una tarjeta apagada.
- **Cada tarea termina con `flutter analyze` en 0 y `flutter test` en verde**, y con su propio commit. Los commits son revertibles uno a uno (doctrina PO: cada rediseño en su commit aislado).

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `lib/domain/money.dart` | Formato RD$ (extraído de una pantalla) | 1 |
| `lib/data/repos.dart` | +4 funciones de datos | 2 |
| `lib/features/client/reputation_screen.dart` | Pantalla de reputación del cliente | 3 |
| `lib/features/provider/stats_screen.dart` | Pantalla de estadísticas del proveedor | 4 |
| `lib/features/shell/nav_destinations.dart` | Lógica pura de destinos e índice activo | 5 |
| `lib/features/shell/floating_nav_bar.dart` | La barra: píldora, botón central, estados | 6 |
| `lib/features/shell/home_shell.dart` | Monta la barra, `extendBody`, índice | 7 |
| `lib/features/provider/inbox_screen.dart` | Toggle "Para ti · Todas" | 8 |
| `lib/core/router.dart` | +2 rutas | 3, 4 |

---

## Task 1: Extraer el formateo de RD$ a `domain/money.dart`

`fmtRD` vive hoy dentro de `features/client/request_status_screen.dart:11`, una pantalla. Las Estadísticas del proveedor lo necesitan para los ingresos, y una pantalla de proveedor no debe importar una pantalla de cliente. Se extrae primero para que las tareas 3 y 4 lo consuman limpio.

**Files:**
- Create: `lib/domain/money.dart`
- Create: `test/money_test.dart`
- Modify: `lib/features/client/request_status_screen.dart:11-13` (borrar la función, importar la nueva)

**Interfaces:**
- Produces: `String fmtRD(num? v)` en `package:jayalo_app/domain/money.dart` — devuelve `''` si `v` es nulo, si no `RD$` + entero con separador de miles.

- [ ] **Step 1: Escribir el test que falla**

Crear `test/money_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/money.dart';

/// El formato de dinero es el mismo de la web: RD$ + entero con coma de
/// miles, sin decimales (los precios en RD$ no se muestran con centavos).
void main() {
  test('nulo devuelve cadena vacía, no "RD\$0"', () {
    expect(fmtRD(null), '');
  });

  test('cero se muestra explícito', () {
    expect(fmtRD(0), 'RD\$0');
  });

  test('por debajo de mil no lleva coma', () {
    expect(fmtRD(999), 'RD\$999');
  });

  test('el salto de los miles pone una coma', () {
    expect(fmtRD(1000), 'RD\$1,000');
  });

  test('los millones llevan dos comas', () {
    expect(fmtRD(1234567), 'RD\$1,234,567');
  });

  test('los decimales se redondean, no se truncan a la baja', () {
    expect(fmtRD(1999.6), 'RD\$2,000');
  });
}
```

- [ ] **Step 2: Correr el test para verificar que falla**

```
flutter test test/money_test.dart
```

Esperado: FAIL — `Error: Couldn't resolve the package 'jayalo_app/domain/money.dart'`.

- [ ] **Step 3: Crear `lib/domain/money.dart`**

```dart
/// Formato de dinero de la app: RD$ + entero con separador de miles.
///
/// Salió de `features/client/request_status_screen.dart`, donde vivía dentro
/// de una pantalla; lo necesitan también las estadísticas del proveedor y una
/// pantalla de proveedor no debe importar una de cliente.
library;

String fmtRD(num? v) => v == null
    ? ''
    : 'RD\$${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';
```

- [ ] **Step 4: Correr el test para verificar que pasa**

```
flutter test test/money_test.dart
```

Esperado: PASS, 6 tests.

- [ ] **Step 5: Quitar la función vieja de la pantalla**

En `lib/features/client/request_status_screen.dart`, borrar las líneas 11-13 (la declaración de `fmtRD`) y añadir el import junto a los demás:

```dart
import '../../domain/money.dart';
```

- [ ] **Step 6: Verificar que nada quedó colgando**

```
flutter analyze
flutter test
```

Esperado: `No issues found!` y toda la suite en verde. Si `analyze` se queja de que `fmtRD` no está definida en otro archivo, ese archivo lo importaba desde `request_status_screen.dart` con un `show` — añadirle también `import '../../domain/money.dart';`.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/money.dart test/money_test.dart lib/features/client/request_status_screen.dart
git commit -m "refactor: fmtRD sale de la pantalla a domain/money.dart"
```

---

## Task 2: Funciones de datos en `repos.dart`

Las cuatro consultas que alimentan las pantallas nuevas y el toggle. Las tres RPCs ya están en producción con `GRANT EXECUTE ... TO authenticated` (migraciones `20260709200910` y `20260629140000` de jayalo-main); `get_provider_stats` y `get_provider_reviews_summary` son `SECURITY INVOKER`, así que la RLS aplica y el proveedor solo ve lo suyo.

No llevan test unitario: son envoltorios de una línea sobre la red, sin lógica que probar. Se verifican de verdad en el device (Task 9).

**Files:**
- Modify: `lib/data/repos.dart` (añadir al final)

**Interfaces:**
- Consumes: `supa` (ya existe en `repos.dart:7`)
- Produces:
  - `Future<Map<String, dynamic>?> customerReputation()`
  - `Future<Map<String, dynamic>> providerStats()`
  - `Future<({int productos, int servicios})> providerCatalogCounts()`
  - `Future<List<Map<String, dynamic>>> allOpenRequests({String? kind})`

- [ ] **Step 1: Añadir las cuatro funciones al final de `lib/data/repos.dart`**

```dart
// ── Métricas: reputación del cliente y estadísticas del proveedor ───────────

/// Reputación del usuario actual como CLIENTE. `null` si la RPC no devuelve
/// fila (usuario recién creado sin actividad).
///
/// Campos: avg_rating, reviews_count, completed_purchases, requests_count,
/// median_response_minutes, response_samples.
Future<Map<String, dynamic>?> customerReputation() async {
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(
      await supa.rpc('get_customer_reputation', params: {'_customer_id': uid}));
  return rows.isEmpty ? null : rows.first;
}

/// Estadísticas del usuario actual como PROVEEDOR: fusiona las dos RPCs en un
/// solo mapa porque la pantalla las muestra juntas y ninguna tiene sentido
/// sola. Las claves ausentes quedan en 0 (proveedor sin actividad todavía).
///
/// Campos: clients_count, completed_count, points_invested, revenue_total,
/// avg_rating, reviews_count.
Future<Map<String, dynamic>> providerStats() async {
  final uid = supa.auth.currentUser!.id;
  final results = await Future.wait([
    supa.rpc('get_provider_stats', params: {'_user_id': uid}),
    supa.rpc('get_provider_reviews_summary', params: {'_user_id': uid}),
  ]);
  final stats = List<Map<String, dynamic>>.from(results[0] as List);
  final reviews = List<Map<String, dynamic>>.from(results[1] as List);
  return {
    ...(stats.isEmpty ? const <String, dynamic>{} : stats.first),
    ...(reviews.isEmpty ? const <String, dynamic>{} : reviews.first),
  };
}

/// Cuántos productos y cuántos servicios tiene publicados el proveedor.
/// Solo la CIFRA — el catálogo navegable es un spec aparte.
Future<({int productos, int servicios})> providerCatalogCounts() async {
  final uid = supa.auth.currentUser!.id;
  final rows = List<Map<String, dynamic>>.from(await supa
      .from('provider_products')
      .select('kind')
      .eq('user_id', uid));
  return (
    productos: rows.where((r) => r['kind'] == 'producto').length,
    servicios: rows.where((r) => r['kind'] == 'servicio').length,
  );
}

/// TODAS las solicitudes abiertas, de cualquier rubro, excluyendo las propias.
///
/// Decisión PO 2026-07-17: esta vista existe para que el marketplace no se vea
/// vacío, así que NUNCA filtra por rubro ni categoría del proveedor. Antes la
/// web aplicaba las preferencias por defecto y dejaba la pestaña en "0
/// resultados" aunque hubiera solicitudes abiertas de otros rubros.
Future<List<Map<String, dynamic>>> allOpenRequests({String? kind}) async {
  final uid = supa.auth.currentUser!.id;
  var q = supa
      .from('customer_requests')
      .select('id,title,description,kind,urgency,zone,created_at')
      .eq('status', 'open')
      .neq('user_id', uid);
  if (kind != null) q = q.eq('kind', kind);
  return List<Map<String, dynamic>>.from(
      await q.order('created_at', ascending: false).limit(100));
}
```

- [ ] **Step 2: Verificar que compila**

```
flutter analyze
```

Esperado: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/data/repos.dart
git commit -m "feat(data): reputacion, estadisticas, conteo de catalogo y solicitudes abiertas"
```

---

## Task 3: Pantalla Reputación del cliente

**Files:**
- Create: `lib/features/client/reputation_screen.dart`
- Create: `test/reputation_screen_test.dart`
- Modify: `lib/core/router.dart` (import + ruta dentro del `ShellRoute`)

**Interfaces:**
- Consumes: `customerReputation()` (Task 2)
- Produces: `class ReputationScreen extends StatefulWidget` con constructor `const ReputationScreen({super.key})`; `class MetricTile extends StatelessWidget` con `const MetricTile({super.key, required this.icon, required this.value, required this.label})` — la reusa Task 4.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/reputation_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/client/reputation_screen.dart';

/// El contrato de la pantalla de reputación. El umbral de 5 muestras para el
/// tiempo de respuesta es la regla de la web (`src/lib/responseTime.ts`): con
/// menos, la mediana miente y NO se muestra nada — ni la cifra ni un "sin
/// datos", que solo genera preguntas.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  testWidgets('con 4 muestras NO muestra el tiempo de respuesta',
      (tester) async {
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 4.5,
      'reviews_count': 3,
      'completed_purchases': 3,
      'requests_count': 7,
      'median_response_minutes': 12,
      'response_samples': 4,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Regularmente respondes'), findsNothing);
  });

  testWidgets('con 5 muestras SÍ muestra el tiempo de respuesta',
      (tester) async {
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 4.5,
      'reviews_count': 3,
      'completed_purchases': 3,
      'requests_count': 7,
      'median_response_minutes': 12,
      'response_samples': 5,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Regularmente respondes'), findsOneWidget);
  });

  testWidgets('sin reseñas muestra el estado vacío, no una rejilla de ceros',
      (tester) async {
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 0,
      'reviews_count': 0,
      'completed_purchases': 0,
      'requests_count': 0,
      'median_response_minutes': null,
      'response_samples': 0,
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no tienes'), findsOneWidget);
    expect(find.byType(MetricTile), findsNothing);
  });

  testWidgets('con actividad muestra las cifras', (tester) async {
    await tester.pumpWidget(host(const ReputationView(data: {
      'avg_rating': 4.5,
      'reviews_count': 3,
      'completed_purchases': 3,
      'requests_count': 7,
      'median_response_minutes': 12,
      'response_samples': 5,
    })));
    await tester.pumpAndSettle();
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('7'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```
flutter test test/reputation_screen_test.dart
```

Esperado: FAIL — `Couldn't resolve the package 'jayalo_app/features/client/reputation_screen.dart'`.

- [ ] **Step 3: Crear `lib/features/client/reputation_screen.dart`**

Fíjate en la separación: `ReputationScreen` carga datos, `ReputationView` solo pinta. Por eso los tests pueden pasar datos a mano sin tocar la red.

```dart
import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../data/repos.dart';
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shell/home_scroll.dart';

/// Umbral de la web (`src/lib/responseTime.ts`): con menos de 5 respuestas
/// medidas la mediana no representa nada y se omite por completo.
const kMinResponseSamples = 5;

class ReputationScreen extends StatefulWidget {
  const ReputationScreen({super.key});
  @override
  State<ReputationScreen> createState() => _ReputationScreenState();
}

class _ReputationScreenState extends State<ReputationScreen> {
  late Future<Map<String, dynamic>?> _load = customerReputation();

  void _refetch() => setState(() => _load = customerReputation());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Mi reputación'),
            actions: const [NotificationBell()]),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _load,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorRetry(onRetry: () async => _refetch());
            }
            if (!snap.hasData && snap.connectionState != ConnectionState.done) {
              return const JayaloLoaderBlock();
            }
            return ReputationView(data: snap.data ?? const {});
          },
        ),
      );
}

/// Solo dibuja. Recibe el mapa crudo de `get_customer_reputation`.
class ReputationView extends StatelessWidget {
  const ReputationView({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final reviews = (data['reviews_count'] as num?)?.toInt() ?? 0;
    final purchases = (data['completed_purchases'] as num?)?.toInt() ?? 0;
    final requests = (data['requests_count'] as num?)?.toInt() ?? 0;
    final samples = (data['response_samples'] as num?)?.toInt() ?? 0;
    final minutes = (data['median_response_minutes'] as num?)?.toInt();
    final rating = (data['avg_rating'] as num?)?.toDouble() ?? 0;

    if (reviews == 0 && purchases == 0 && requests == 0) {
      return EmptyState(
        controller: homeScrollController,
        message: 'Todavía no tienes reputación.\n\n'
            'Se construye sola: pide lo que necesitas, completa tus compras '
            'y califica a quien te atendió. Los proveedores la verán y te '
            'responderán con más confianza.',
      );
    }

    return ListView(
      // Controlador PROPIO, no `homeScrollController`. Ese singleton lo lee
      // `BackGuard._handleBack` con `c.offset`, que lanza "Too many elements"
      // si hay más de una posición adjunta — y el AnimatedSwitcher del shell
      // mantiene dos pestañas montadas durante los 250 ms del cambio.
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionHeader(text: 'CÓMO TE VEN'),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.star_rounded,
                    value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                    label: reviews == 1 ? '1 reseña' : '$reviews reseñas')),
            Expanded(
                child: MetricTile(
                    icon: Icons.shopping_bag_outlined,
                    value: '$purchases',
                    label: 'compras completadas')),
          ]),
        ).cascadeIn(0),
        const SectionHeader(text: 'TU ACTIVIDAD'),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.receipt_long_outlined,
                    value: '$requests',
                    label: 'solicitudes hechas')),
          ]),
        ).cascadeIn(1),
        if (samples >= kMinResponseSamples && minutes != null)
          JayaloCard(
            child: Row(children: [
              Icon(Icons.schedule,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      'Regularmente respondes en ${_humanMinutes(minutes)}')),
            ]),
          ).cascadeIn(2),
      ],
    );
  }
}

/// "45 minutos" / "unas 2 horas" / "1 día" — nunca "min" ni "h" abreviados:
/// el público de la app lee palabras, no unidades.
String _humanMinutes(int m) {
  if (m < 60) return '$m minutos';
  final horas = (m / 60).round();
  if (horas < 24) return horas == 1 ? 'una hora' : 'unas $horas horas';
  final dias = (horas / 24).round();
  return dias == 1 ? 'un día' : '$dias días';
}

/// Cifra grande + etiqueta. La reusan Reputación y Estadísticas.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: cs.primary, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

```
flutter test test/reputation_screen_test.dart
```

Esperado: PASS, 4 tests. Si el tercero falla porque `JayaloMotion.reduced` es false y la cascada aún no terminó, el `pumpAndSettle` ya lo cubre — si aun así falla, revisar que el estado vacío no envuelva nada en `cascadeIn`.

- [ ] **Step 5: Registrar la ruta**

En `lib/core/router.dart`, añadir el import junto a los demás:

```dart
import '../features/client/reputation_screen.dart';
```

Y dentro de `ShellRoute`, justo después de la ruta `/client/create`:

```dart
            GoRoute(
                path: '/client/reputation',
                builder: (_, _) => const BackGuard(child: ReputationScreen())),
```

- [ ] **Step 6: Verificar**

```
flutter analyze
flutter test
```

Esperado: `No issues found!` y toda la suite en verde.

- [ ] **Step 7: Commit**

```bash
git add lib/features/client/reputation_screen.dart test/reputation_screen_test.dart lib/core/router.dart
git commit -m "feat(cliente): pantalla de reputacion"
```

---

## Task 4: Pantalla Estadísticas del proveedor

**Files:**
- Create: `lib/features/provider/stats_screen.dart`
- Create: `test/stats_screen_test.dart`
- Modify: `lib/core/router.dart` (import + ruta)

**Interfaces:**
- Consumes: `providerStats()`, `providerCatalogCounts()` (Task 2); `fmtRD` (Task 1); `MetricTile` de `features/client/reputation_screen.dart` (Task 3)
- Produces: `class StatsScreen extends StatefulWidget` con `const StatsScreen({super.key})`

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/stats_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/provider/stats_screen.dart';

/// El contrato de Estadísticas. La tarjeta de catálogo es deliberadamente
/// INERTE: el catálogo navegable es un spec aparte (decisión PO 2026-07-18) y
/// una tarjeta que parece tocable pero no hace nada es peor que una apagada.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: child,
      );

  const conActividad = {
    'clients_count': 8,
    'completed_count': 12,
    'points_invested': 45,
    'revenue_total': 128500,
    'avg_rating': 4.8,
    'reviews_count': 9,
  };

  testWidgets('muestra trabajos, clientes e ingresos formateados en RD\$',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(
        data: conActividad, productos: 12, servicios: 3)));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsWidgets);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('RD\$128,500'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
  });

  testWidgets('la tarjeta de catálogo muestra el conteo y NO es tocable',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(
        data: conActividad, productos: 12, servicios: 3)));
    await tester.pumpAndSettle();
    expect(find.textContaining('12 productos'), findsOneWidget);
    expect(find.textContaining('3 servicios'), findsOneWidget);

    final catalogo = tester.widget<CatalogCard>(find.byType(CatalogCard));
    expect(catalogo.onTap, isNull,
        reason: 'el catálogo navegable es un spec aparte; hasta entonces la '
            'tarjeta no debe responder al toque');
  });

  testWidgets('sin trabajos completados muestra el estado vacío',
      (tester) async {
    await tester.pumpWidget(host(const StatsView(data: {
      'clients_count': 0,
      'completed_count': 0,
      'points_invested': 0,
      'revenue_total': 0,
      'avg_rating': 0,
      'reviews_count': 0,
    }, productos: 0, servicios: 0)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no has completado'), findsOneWidget);
  });

  testWidgets('singular y plural del catálogo', (tester) async {
    await tester.pumpWidget(host(const StatsView(
        data: conActividad, productos: 1, servicios: 1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 producto ·'), findsOneWidget);
    expect(find.textContaining('1 servicio'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```
flutter test test/stats_screen_test.dart
```

Esperado: FAIL — paquete sin resolver.

- [ ] **Step 3: Crear `lib/features/provider/stats_screen.dart`**

```dart
import 'package:flutter/material.dart';

import '../../data/repos.dart';
import '../../domain/money.dart';
import '../client/reputation_screen.dart' show MetricTile;
import '../notifications/notification_bell.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<(Map<String, dynamic>, ({int productos, int servicios}))> _load =
      _fetch();

  Future<(Map<String, dynamic>, ({int productos, int servicios}))>
      _fetch() async {
    final r = await Future.wait([providerStats(), providerCatalogCounts()]);
    return (
      r[0] as Map<String, dynamic>,
      r[1] as ({int productos, int servicios}),
    );
  }

  void _refetch() => setState(() => _load = _fetch());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Mis estadísticas'),
            actions: const [NotificationBell()]),
        body: FutureBuilder<
            (Map<String, dynamic>, ({int productos, int servicios}))>(
          future: _load,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorRetry(onRetry: () async => _refetch());
            }
            if (!snap.hasData) return const JayaloLoaderBlock();
            final (data, catalogo) = snap.data!;
            return StatsView(
                data: data,
                productos: catalogo.productos,
                servicios: catalogo.servicios);
          },
        ),
      );
}

/// Solo dibuja.
///
/// Es Stateful solo para alojar su propio `ScrollController`: usar el
/// singleton `homeScrollController` aquí tumbaría la app (ver el comentario
/// del `ListView` de abajo). Misma solución que `ReputationView`.
class StatsView extends StatefulWidget {
  const StatsView({
    super.key,
    required this.data,
    required this.productos,
    required this.servicios,
  });

  final Map<String, dynamic> data;
  final int productos;
  final int servicios;

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final productos = widget.productos;
    final servicios = widget.servicios;
    final completed = (data['completed_count'] as num?)?.toInt() ?? 0;
    final clients = (data['clients_count'] as num?)?.toInt() ?? 0;
    final points = (data['points_invested'] as num?)?.toInt() ?? 0;
    final revenue = (data['revenue_total'] as num?) ?? 0;
    final rating = (data['avg_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (data['reviews_count'] as num?)?.toInt() ?? 0;

    if (completed == 0 && reviews == 0) {
      return EmptyState(
        controller: _scroll,
        message: 'Todavía no has completado ningún trabajo.\n\n'
            'Cuando cierres el primero verás aquí cuántos clientes has '
            'atendido, cuánto has facturado y cómo te califican.',
      );
    }

    return ListView(
      // Controlador PROPIO, no `homeScrollController`. Ese singleton lo lee
      // `BackGuard._handleBack` con `c.offset`, que lanza "Too many elements"
      // si hay más de una posición adjunta — y el AnimatedSwitcher del shell
      // mantiene dos pestañas montadas durante los 250 ms del cambio.
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionHeader(text: 'CÓMO TE CALIFICAN'),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.star_rounded,
                    value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                    label: reviews == 1 ? '1 reseña' : '$reviews reseñas')),
            Expanded(
                child: MetricTile(
                    icon: Icons.handshake_outlined,
                    value: '$completed',
                    label: 'trabajos realizados')),
          ]),
        ).cascadeIn(0),
        const SectionHeader(text: 'TU NEGOCIO'),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.people_alt_outlined,
                    value: '$clients',
                    label: 'clientes atendidos')),
            Expanded(
                child: MetricTile(
                    icon: Icons.payments_outlined,
                    value: fmtRD(revenue),
                    label: 'facturado')),
          ]),
        ).cascadeIn(1),
        JayaloCard(
          child: Row(children: [
            Expanded(
                child: MetricTile(
                    icon: Icons.toll_outlined,
                    value: '$points',
                    label: 'créditos invertidos')),
          ]),
        ).cascadeIn(2),
        const SectionHeader(text: 'LO QUE OFRECES'),
        CatalogCard(productos: productos, servicios: servicios).cascadeIn(3),
      ],
    );
  }
}

/// Conteo del catálogo. INERTE a propósito: `onTap` es nulo hasta que exista
/// el spec del catálogo navegable (decisión PO 2026-07-18). Cuando llegue, se
/// le pasa el `onTap` y nada más cambia.
class CatalogCard extends StatelessWidget {
  const CatalogCard({
    super.key,
    required this.productos,
    required this.servicios,
    this.onTap,
  });

  final int productos;
  final int servicios;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = productos == 1 ? '1 producto' : '$productos productos';
    final s = servicios == 1 ? '1 servicio' : '$servicios servicios';
    return JayaloCard(
      onTap: onTap,
      child: Row(children: [
        Icon(Icons.inventory_2_outlined, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$p · $s',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Se administran desde jayalo.com por ahora',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

```
flutter test test/stats_screen_test.dart
```

Esperado: PASS, 4 tests.

- [ ] **Step 5: Registrar la ruta**

En `lib/core/router.dart`, import:

```dart
import '../features/provider/stats_screen.dart';
```

Y dentro del `ShellRoute`, después de `/provider/offers`:

```dart
            GoRoute(
                path: '/provider/stats',
                builder: (_, _) => const BackGuard(child: StatsScreen())),
```

- [ ] **Step 6: Verificar**

```
flutter analyze
flutter test
```

Esperado: `No issues found!`, suite verde.

- [ ] **Step 7: Commit**

```bash
git add lib/features/provider/stats_screen.dart test/stats_screen_test.dart lib/core/router.dart
git commit -m "feat(proveedor): pantalla de estadisticas"
```

---

## Task 5: Lógica pura de destinos (`nav_destinations.dart`)

Se saca de `home_shell.dart` la tabla de pestañas y el cálculo del índice activo. Sin widgets: se puede probar el mapa de destinos de cada rol sin montar un `MaterialApp`.

**Files:**
- Create: `lib/features/shell/nav_destinations.dart`
- Create: `test/nav_destinations_test.dart`

**Interfaces:**
- Consumes: `RoleState` de `lib/core/session_state.dart`
- Produces:
  - `class NavDestination` con campos `route` (String), `icon` (IconData), `label` (String), `isCenter` (bool)
  - `List<NavDestination> destinationsFor(RoleState role)`
  - `int activeIndex(List<NavDestination> dests, String location)`
  - `const kCenterIndex = 2`

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/nav_destinations_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// La barra tiene 5 destinos: 2 · centro · 2. El del centro es la acción que
/// define al rol (crear si eres cliente, ver solicitudes si eres proveedor) y
/// es un destino más — puede estar activo como cualquier otro.
void main() {
  group('destinationsFor', () {
    test('cada rol tiene 5 destinos con el central en el medio', () {
      for (final rol in [RoleState.consumer, RoleState.provider]) {
        final d = destinationsFor(rol);
        expect(d.length, 5, reason: '$rol');
        expect(d[kCenterIndex].isCenter, isTrue, reason: '$rol');
        expect(d.where((x) => x.isCenter).length, 1, reason: '$rol');
      }
    });

    test('el centro del cliente es crear una solicitud', () {
      final d = destinationsFor(RoleState.consumer);
      expect(d[kCenterIndex].route, '/client/create');
    });

    test('el centro del proveedor es ver solicitudes', () {
      final d = destinationsFor(RoleState.provider);
      expect(d[kCenterIndex].route, '/provider');
    });

    test('el cliente llega a su reputación y el proveedor a sus estadísticas',
        () {
      expect(destinationsFor(RoleState.consumer).map((d) => d.route),
          contains('/client/reputation'));
      expect(destinationsFor(RoleState.provider).map((d) => d.route),
          contains('/provider/stats'));
    });

    test('ningún rol ve rutas del otro', () {
      expect(destinationsFor(RoleState.consumer).map((d) => d.route),
          isNot(contains('/provider')));
      expect(destinationsFor(RoleState.provider).map((d) => d.route),
          isNot(contains('/client')));
    });

    test('un rol sin resolver no revienta: cae al del cliente', () {
      expect(destinationsFor(RoleState.unknown).length, 5);
      expect(destinationsFor(RoleState.needsOnboarding).length, 5);
    });

    test('todas las etiquetas están en español y no vacías', () {
      for (final d in destinationsFor(RoleState.provider)) {
        expect(d.label.trim(), isNotEmpty);
      }
    });
  });

  group('activeIndex', () {
    final cliente = destinationsFor(RoleState.consumer);
    final proveedor = destinationsFor(RoleState.provider);

    test('la ruta exacta marca su destino', () {
      expect(activeIndex(cliente, '/messages'), 3);
      expect(activeIndex(cliente, '/client/create'), kCenterIndex);
    });

    test('gana el prefijo MÁS LARGO, no el primero que coincide', () {
      // '/provider/stats' empieza por '/provider' (el centro). Si ganara el
      // primero, estar en estadísticas encendería el botón central.
      expect(activeIndex(proveedor, '/provider/stats'), 1);
      expect(activeIndex(proveedor, '/provider/offers'), 0);
    });

    test('el detalle hereda la pestaña de su lista', () {
      expect(activeIndex(proveedor, '/provider/request/abc-123'), kCenterIndex);
      expect(activeIndex(cliente, '/client/request/abc-123'), 0);
      expect(activeIndex(cliente, '/messages/abc-123'), 3);
    });

    test('una ruta fuera de la barra no marca nada raro: cae en 0', () {
      expect(activeIndex(cliente, '/notifications'), 0);
    });
  });
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```
flutter test test/nav_destinations_test.dart
```

Esperado: FAIL — paquete sin resolver.

- [ ] **Step 3: Crear `lib/features/shell/nav_destinations.dart`**

```dart
/// Qué destinos ve cada rol en la barra, y cuál está activo según la ruta.
///
/// Lógica pura a propósito: nada de widgets aquí. La barra
/// (`floating_nav_bar.dart`) solo dibuja lo que este archivo decide, y así el
/// mapa de destinos de cada rol se prueba sin montar un MaterialApp.
library;

import 'package:flutter/material.dart';

import '../../core/session_state.dart';

/// Posición del botón central: 2 iconos, el centro, 2 iconos.
const kCenterIndex = 2;

class NavDestination {
  const NavDestination({
    required this.route,
    required this.icon,
    required this.label,
    this.isCenter = false,
  });

  final String route;
  final IconData icon;
  final String label;

  /// El círculo elevado del medio. Es un destino como los demás — puede estar
  /// activo y llevar su punto — solo que se dibuja distinto.
  final bool isCenter;
}

const _cliente = [
  NavDestination(
      route: '/client',
      icon: Icons.receipt_long_outlined,
      label: 'Mis solicitudes'),
  NavDestination(
      route: '/client/reputation',
      icon: Icons.workspace_premium_outlined,
      label: 'Reputación'),
  NavDestination(
      route: '/client/create',
      icon: Icons.add,
      label: 'Nueva solicitud',
      isCenter: true),
  NavDestination(
      route: '/messages', icon: Icons.chat_bubble_outline, label: 'Mensajes'),
  NavDestination(
      route: '/settings', icon: Icons.settings_outlined, label: 'Ajustes'),
];

const _proveedor = [
  NavDestination(
      route: '/provider/offers',
      icon: Icons.local_offer_outlined,
      label: 'Mis ofertas'),
  NavDestination(
      route: '/provider/stats',
      icon: Icons.insights_outlined,
      label: 'Estadísticas'),
  NavDestination(
      route: '/provider',
      icon: Icons.search,
      label: 'Ver solicitudes',
      isCenter: true),
  NavDestination(
      route: '/messages', icon: Icons.chat_bubble_outline, label: 'Mensajes'),
  NavDestination(
      route: '/settings', icon: Icons.settings_outlined, label: 'Ajustes'),
];

/// El gate garantiza que dentro del shell el rol ya está resuelto; el fallback
/// al cliente existe solo para que un estado transitorio no reviente la barra.
List<NavDestination> destinationsFor(RoleState role) =>
    role == RoleState.provider ? _proveedor : _cliente;

/// Índice del destino activo para una ubicación del router.
///
/// Gana el prefijo MÁS LARGO: '/provider/stats' empieza por '/provider' (el
/// botón central del proveedor), así que si ganara el primero que coincide,
/// estar en Estadísticas encendería el botón del medio.
int activeIndex(List<NavDestination> dests, String location) {
  var best = 0;
  var bestLen = -1;
  for (var i = 0; i < dests.length; i++) {
    final p = dests[i].route;
    if ((location == p || location.startsWith('$p/')) && p.length > bestLen) {
      bestLen = p.length;
      best = i;
    }
  }
  return best;
}
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

```
flutter test test/nav_destinations_test.dart
```

Esperado: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/shell/nav_destinations.dart test/nav_destinations_test.dart
git commit -m "feat(shell): destinos de navegacion por rol como logica pura"
```

---

## Task 6: La barra flotante (`floating_nav_bar.dart`)

Puro dibujo. No conoce rutas ni roles: recibe destinos, índice activo y un callback.

**Files:**
- Create: `lib/features/shell/floating_nav_bar.dart`
- Create: `test/floating_nav_bar_test.dart`

**Interfaces:**
- Consumes: `NavDestination`, `kCenterIndex` (Task 5); `JayaloMotion`
- Produces:
  - `class FloatingNavBar extends StatelessWidget` con `const FloatingNavBar({super.key, required this.destinations, required this.currentIndex, required this.onSelected})`
  - `const double kNavBarReservedSpace = 96` — alto que las pantallas deben reservar al final de sus listas

- [ ] **Step 1: Escribir los tests que fallan**

Crear `test/floating_nav_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/session_state.dart';
import 'package:jayalo_app/features/shell/floating_nav_bar.dart';
import 'package:jayalo_app/features/shell/nav_destinations.dart';

/// Contrato de la barra, no sus píxeles. Lo importante: que solo el activo
/// lleve texto (decisión PO — limpia como la referencia pero el usuario
/// siempre lee dónde está), que TODOS anuncien su nombre a un lector de
/// pantalla, y que el botón central pueda estar activo.
void main() {
  final dests = destinationsFor(RoleState.provider);

  Widget host(int index, {void Function(int)? onSelected, bool reduced = false}) =>
      MaterialApp(
        theme: jayaloTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            bottomNavigationBar: FloatingNavBar(
              destinations: dests,
              currentIndex: index,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      );

  testWidgets('solo el destino activo muestra su texto', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(find.text('Mis ofertas'), findsOneWidget);
    expect(find.text('Estadísticas'), findsNothing);
    expect(find.text('Mensajes'), findsNothing);
    expect(find.text('Ajustes'), findsNothing);
  });

  testWidgets('el texto se mueve al cambiar de destino', (tester) async {
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(3));
    await tester.pumpAndSettle();
    expect(find.text('Mis ofertas'), findsNothing);
    expect(find.text('Mensajes'), findsOneWidget);
  });

  testWidgets('el botón central también puede estar activo y llevar su texto',
      (tester) async {
    await tester.pumpWidget(host(kCenterIndex));
    await tester.pumpAndSettle();
    expect(find.text('Ver solicitudes'), findsOneWidget);
  });

  testWidgets('todos los destinos se anuncian a un lector de pantalla',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    for (final d in dests) {
      expect(find.bySemanticsLabel(d.label), findsOneWidget, reason: d.label);
    }
    handle.dispose();
  });

  testWidgets('tocar un destino avisa con su índice', (tester) async {
    final tocados = <int>[];
    await tester.pumpWidget(host(0, onSelected: tocados.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Ajustes'));
    await tester.pumpAndSettle();
    expect(tocados, [4]);
  });

  testWidgets('tocar el botón central avisa con el índice del centro',
      (tester) async {
    final tocados = <int>[];
    await tester.pumpWidget(host(0, onSelected: tocados.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Ver solicitudes'));
    await tester.pumpAndSettle();
    expect(tocados, [kCenterIndex]);
  });

  testWidgets('con reducir animaciones no queda nada animando',
      (tester) async {
    await tester.pumpWidget(host(0, reduced: true));
    await tester.pump();
    // Si algo siguiera animando, pumpAndSettle agotaría su presupuesto.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```
flutter test test/floating_nav_bar_test.dart
```

Esperado: FAIL — paquete sin resolver.

- [ ] **Step 3: Crear `lib/features/shell/floating_nav_bar.dart`**

```dart
/// La barra: píldora flotante con botón circular central elevado.
///
/// Solo dibuja. No sabe de rutas ni de roles — recibe los destinos que
/// `nav_destinations.dart` decidió y avisa por índice. Así se puede cambiar el
/// aspecto sin tocar la navegación.
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import 'nav_destinations.dart';

/// Alto que una barra FLOTANTE no reserva por sí sola. Toda lista del shell
/// debe añadir este padding al final o su último elemento queda debajo de la
/// barra, invisible. Ni `analyze` ni los tests lo detectan: solo se ve
/// recorriendo la lista hasta abajo en un teléfono.
const double kNavBarReservedSpace = 96;

const _pillHeight = 64.0;
const _centerSize = 56.0;

class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        // El botón central sobresale por arriba: el padding superior le deja
        // sitio para que no lo recorte el Scaffold.
        padding: const EdgeInsets.fromLTRB(16, _centerSize / 2, 16, 12),
        child: SizedBox(
          height: _pillHeight + _centerSize / 2,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Container(
                height: _pillHeight,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(_pillHeight / 2),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: .10),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: destinations[i].isCenter
                            // Hueco: el círculo se dibuja encima, en el Stack.
                            ? const SizedBox.shrink()
                            : _SideItem(
                                destination: destinations[i],
                                active: i == currentIndex,
                                onTap: () => onSelected(i),
                              ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: _pillHeight - _centerSize / 2 - 4,
                child: _CenterButton(
                  destination: destinations[kCenterIndex],
                  active: currentIndex == kCenterIndex,
                  onTap: () => onSelected(kCenterIndex),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icono lateral. El texto aparece SOLO cuando está activo (decisión PO): la
/// barra queda limpia pero el usuario siempre puede leer dónde está parado.
class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    final reduced = JayaloMotion.reduced(context);
    return Semantics(
      label: destination.label,
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(destination.icon, color: color, size: 24),
            AnimatedSize(
              duration: reduced ? Duration.zero : JayaloMotion.base,
              curve: JayaloMotion.enter,
              child: active
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    )
                  : const SizedBox(width: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// El círculo elevado. Lleva su texto debajo de la píldora cuando está activo,
/// para no meter texto dentro del círculo.
class _CenterButton extends StatelessWidget {
  const _CenterButton({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: destination.label,
      button: true,
      selected: active,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: cs.primary,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: cs.shadow.withValues(alpha: .35),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: _centerSize,
                height: _centerSize,
                child: Icon(destination.icon, color: cs.onPrimary, size: 28),
              ),
            ),
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                destination.label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

```
flutter test test/floating_nav_bar_test.dart
```

Esperado: PASS, 7 tests.

Si el test de semántica falla con `findsNothing` en el central, es porque el `Semantics` del botón envuelve un `Column` cuyo texto duplica la etiqueta: añadir `excludeSemantics: true` al `Semantics` del `_CenterButton`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/shell/floating_nav_bar.dart test/floating_nav_bar_test.dart
git commit -m "feat(shell): barra flotante con boton central"
```

---

## Task 7: Montar la barra y reservar espacio en las 11 pantallas

**El riesgo real de todo el plan está aquí.** Una barra flotante se superpone al contenido: hasta ahora `NavigationBar` era sólida y el cuerpo terminaba encima. Si una lista se queda sin el padding, su último elemento queda tapado y el usuario no entiende por qué. `flutter analyze` y los tests de widget no lo ven.

**Files:**
- Modify: `lib/features/shell/home_shell.dart` (reescritura de la mitad inferior)
- Modify: las 11 pantallas del shell (padding al final de cada scroll)

**Interfaces:**
- Consumes: `destinationsFor`, `activeIndex` (Task 5); `FloatingNavBar`, `kNavBarReservedSpace` (Task 6)

- [ ] **Step 1: Reescribir `home_shell.dart`**

Sustituir todo el contenido de `lib/features/shell/home_shell.dart` por:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion.dart';
import '../../core/session_state.dart';
import 'floating_nav_bar.dart';
import 'nav_destinations.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // El gate garantiza que aquí el rol ya está resuelto (spec §4).
    // El ATRÁS del sistema lo maneja BackGuard DENTRO de cada ruta del shell
    // (un PopScope aquí no funciona con predictive back; ver back_guard.dart).
    final dests = destinationsFor(roleStore.value);
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = activeIndex(dests, loc);

    // Cambiar de pestaña reemplaza la única página del Navigator anidado (no
    // la empuja encima), y Flutter no anima ese reemplazo por defecto —
    // `pageTransitionsTheme` (doctrina de movimiento, `app.dart`) solo cubre
    // pushes reales, como entrar al detalle de una solicitud, que sigue
    // dentro de la MISMA pestaña (`idx` no cambia, la key tampoco: no hay
    // doble transición). Aquí se anima el cambio de pestaña aparte, con
    // "fade through" (fundido + escala sutil) — el patrón de Material para
    // navegación entre pares, distinto al deslizado jerárquico de un push.
    return Scaffold(
      // La barra FLOTA: el cuerpo se extiende por debajo de ella. Cada
      // pantalla reserva `kNavBarReservedSpace` al final de su scroll.
      extendBody: true,
      body: AnimatedSwitcher(
        duration:
            JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base,
        switchInCurve: JayaloMotion.emphasized,
        switchOutCurve: JayaloMotion.emphasized,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero)
                    .animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(dests[idx].route), child: child),
      ),
      bottomNavigationBar: FloatingNavBar(
        destinations: dests,
        currentIndex: idx,
        onSelected: (i) => context.go(dests[i].route),
      ),
    );
  }
}
```

- [ ] **Step 2: Verificar que compila y la suite sigue verde**

```
flutter analyze
flutter test
```

Esperado: `No issues found!`, suite verde.

- [ ] **Step 3: Reservar espacio en cada pantalla del shell**

En **cada uno** de estos archivos, localizar el widget de scroll raíz (`ListView`, `ListView.builder`, `SingleChildScrollView` o `CustomScrollView`) y asegurarse de que su `padding` incluye abajo el espacio que reserva la barra. Añadir el import `import '../shell/floating_nav_bar.dart';` (ajustar la ruta relativa según la carpeta).

Usar la **función**, no la constante suelta: `navBarReservedSpace(context)` devuelve el alto de la barra más el inset de zona segura del dispositivo, que varía según el teléfono. La constante `kNavBarReservedSpace` (132) solo cubre la barra y existe para contextos sin `BuildContext`.

Si el scroll ya tiene padding, sumar el valor al `bottom` existente en vez de sustituirlo. Si no tiene padding, añadirlo:

```dart
padding: EdgeInsets.only(bottom: navBarReservedSpace(context)),
```

Ojo: al dejar de ser `const`, hay que quitar el `const` del `EdgeInsets` (y del widget entero si lo tenía).

Lista completa — marcar una por una:

- [ ] `lib/features/client/my_requests_screen.dart`
- [ ] `lib/features/client/create_request_screen.dart`
- [ ] `lib/features/client/request_status_screen.dart`
- [ ] `lib/features/client/reputation_screen.dart`
- [ ] `lib/features/provider/inbox_screen.dart`
- [ ] `lib/features/provider/my_offers_screen.dart`
- [ ] `lib/features/provider/request_detail_screen.dart`
- [ ] `lib/features/provider/stats_screen.dart`
- [ ] `lib/features/chat/conversations_screen.dart`
- [ ] `lib/features/settings/settings_screen.dart`
- [ ] `lib/features/notifications/notifications_screen.dart`

**Excepción: `lib/features/chat/chat_screen.dart` no lleva padding.** El chat tiene su propio composer anclado abajo y no es una ruta con barra visible; si se le añade, deja un hueco muerto sobre el campo de escribir.

**Caso especial `EmptyState`:** su `ListView` interno no acepta padding desde fuera. Añadir en `brand_kit.dart`, dentro del `ListView` de `EmptyState`, `padding: EdgeInsets.only(bottom: navBarReservedSpace(context))`. Con eso las 11 pantallas quedan cubiertas también en vacío.

**Comprobación de que no se quedó ninguna fuera**, antes de dar el paso por hecho:

```bash
grep -rL "navBarReservedSpace" \
  lib/features/client/my_requests_screen.dart \
  lib/features/client/create_request_screen.dart \
  lib/features/client/request_status_screen.dart \
  lib/features/client/reputation_screen.dart \
  lib/features/provider/inbox_screen.dart \
  lib/features/provider/my_offers_screen.dart \
  lib/features/provider/request_detail_screen.dart \
  lib/features/provider/stats_screen.dart \
  lib/features/chat/conversations_screen.dart \
  lib/features/settings/settings_screen.dart \
  lib/features/notifications/notifications_screen.dart
```

No debe listar ningún archivo. Si lista alguno, es una pantalla que se quedó sin reservar espacio.

- [ ] **Step 4: Verificar**

```
flutter analyze
flutter test
```

Esperado: `No issues found!`, suite verde.

- [ ] **Step 5: Confirmar con los ojos, no con el compilador**

```
flutter run -d <device>
```

Recorrer **cada una** de las 11 pantallas hasta el final del scroll y confirmar que el último elemento queda por encima de la barra, no debajo. Esta comprobación no es opcional: es el único momento en que este bug se ve.

- [ ] **Step 6: Commit**

```bash
git add lib/features/shell/home_shell.dart lib/features lib/features/shared/brand_kit.dart
git commit -m "feat(shell): monta la barra flotante y reserva espacio en las pantallas"
```

---

## Task 8: Toggle "Para ti · Todas" en el inbox del proveedor

**Files:**
- Modify: `lib/features/provider/inbox_screen.dart`

**Interfaces:**
- Consumes: `providerInbox()` (ya existe), `allOpenRequests()` (Task 2)

- [ ] **Step 1: Añadir el estado del toggle**

En `_ProviderInboxScreenState`, junto a `String? _kind;`:

```dart
  /// false = "Para ti" (su rubro), true = "Todas" (cualquier rubro).
  /// NO persiste entre sesiones: al entrar siempre arranca en "Para ti", que
  /// es la vista con solicitudes relevantes para ofertar.
  bool _todas = false;
```

Y cambiar `_refetch` para que elija la fuente:

```dart
  void _refetch() => setState(() =>
      _load = _todas ? allOpenRequests(kind: _kind) : providerInbox(kind: _kind));
```

- [ ] **Step 2: Añadir el selector encima del de tipo**

Dentro del `Column` del `body`, ANTES del `Padding` que contiene el `SegmentedButton` de Todo/Productos/Servicios:

```dart
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Para ti')),
              ButtonSegment(value: true, label: Text('Todas')),
            ],
            selected: {_todas},
            onSelectionChanged: (s) {
              _todas = s.first;
              _refetch();
            },
          ),
        ),
```

- [ ] **Step 3: Adaptar el título y el estado vacío**

El `AppBar` pasa a reflejar la vista:

```dart
      appBar: AppBar(
          title: Text(_todas ? 'Todas las solicitudes' : 'Solicitudes para ti'),
          actions: const [NotificationBell()]),
```

Y el `EmptyState` necesita un mensaje por vista — sustituir el `message:` actual por:

```dart
                    message: _todas
                        ? 'Ahora mismo no hay solicitudes abiertas.\n'
                            'Vuelve más tarde: entran nuevas todos los días.'
                        : 'Aquí verás las solicitudes que coinciden con tu negocio.\n'
                            'Te avisaremos cuando llegue una nueva.',
```

- [ ] **Step 4: Verificar**

```
flutter analyze
flutter test
```

Esperado: `No issues found!`, suite verde.

- [ ] **Step 5: Confirmar en el device que "Todas" trae datos**

```
flutter run -d <device>
```

Con sesión de proveedor, tocar "Todas". Debe listar solicitudes abiertas de rubros distintos al suyo y **ninguna propia**.

Si sale vacío teniendo la BD solicitudes abiertas, es la RLS de `customer_requests`: la app nunca había hecho esa consulta. Parar y reportarlo — es exactamente el riesgo anotado en el spec §8, y se arregla en jayalo-main, no aquí.

- [ ] **Step 6: Commit**

```bash
git add lib/features/provider/inbox_screen.dart
git commit -m "feat(proveedor): toggle Para ti / Todas en el inbox"
```

---

## Task 9: Verificación final y APK

**Files:** ninguno (salvo que aparezcan fallos)

- [ ] **Step 1: Suite completa y análisis**

```
flutter analyze
flutter test
```

Esperado: `No issues found!` y toda la suite verde (145 tests previos + los ~26 nuevos).

- [ ] **Step 2: Construir e instalar**

```
flutter build apk --debug
flutter install -d <device>
```

- [ ] **Step 3: Recorrido en el Redmi — lista de comprobación**

Con cuenta de **cliente**:

- [ ] La barra flota, con el botón ＋ violeta sobresaliendo en el centro
- [ ] Solo la pestaña activa muestra texto, y el texto se mueve al cambiar
- [ ] El ＋ abre Nueva solicitud y queda marcado como activo
- [ ] Reputación carga y muestra cifras reales (o su estado vacío)
- [ ] Ninguna de las 5 pantallas esconde su último elemento bajo la barra

Con cuenta de **proveedor**:

- [ ] El botón central 🔍 abre Solicitudes y queda activo
- [ ] Estar en Estadísticas NO enciende el botón central
- [ ] Estadísticas muestra ⭐, trabajos, clientes, facturado en RD$ y el conteo del catálogo
- [ ] La tarjeta de catálogo no responde al toque
- [ ] "Todas" lista solicitudes de otros rubros y ninguna propia
- [ ] Ninguna de las 6 pantallas esconde su último elemento bajo la barra

Transversal:

- [ ] Modo oscuro: la píldora se ve sobre el fondo y el círculo central es azul, no violeta
- [ ] El botón ATRÁS del sistema se comporta igual que antes (no minimiza dentro del shell)
- [ ] El círculo central no choca con la barra de gestos de MIUI
- [ ] Con "reducir animaciones" del sistema activo, nada parpadea ni salta

- [ ] **Step 4: Commit final**

```bash
git add -A
git commit -m "chore: verificacion en device de la barra flotante"
```

Si el recorrido no encontró nada que corregir, no hay nada que commitear — decirlo tal cual en vez de inventar un commit vacío.

---

## Notas para quien ejecute

**Lo que NO hay que hacer:**

- No construir el catálogo de productos navegable. La `CatalogCard` se queda inerte.
- No mover la campana de notificaciones a la barra. Se queda en el `AppBar`.
- No dividir "Mis solicitudes" del cliente en activas e historial. Sigue mostrando todo.
- No aplicar filtro de rubro en la vista "Todas". Solo excluye las propias.
- No tocar el `AnimatedSwitcher` de cambio de pestaña ni `pageTransitionsTheme`.

**Si algo del plan no cuadra con el código real** (una pantalla no tiene el scroll donde dice, una RPC devuelve otra forma): parar y reportarlo en vez de improvisar. El plan se escribió leyendo el código, pero el código manda.
