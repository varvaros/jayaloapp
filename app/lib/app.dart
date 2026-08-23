import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
// `FrictionSimulation` (el fling exponencial) NO viene re-exportada por
// material.dart, a diferencia de `ClampingScrollSimulation`, que vive en
// widgets. Import explícito.
import 'package:flutter/physics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/brand.dart';
import 'core/play_billing_service.dart';
import 'core/motion.dart';
import 'features/shared/saldo_store.dart' show saldoStore;
import 'data/repos.dart';
import 'core/theme_store.dart';
import 'features/shared/onboarding_store.dart';

/// Traducciones de los widgets que trae Material de fábrica.
///
/// Hasta 2026-08-23 la app NO declaraba ninguna: toda la interfaz está escrita
/// en español a mano, pero lo que pinta Flutter por su cuenta salía en INGLÉS
/// («OK», «Cancel», «Select date», el menú de copiar/pegar…). Se notaba sobre
/// todo en el `showDatePicker` — queja vieja — y habría sido peor al estrenar
/// el `showTimePicker` de la fecha pautada.
///
/// Se declara UN solo idioma a propósito: con `supportedLocales` de un único
/// elemento, Flutter resuelve cualquier idioma del teléfono a `es`, así que un
/// usuario con el móvil en inglés también ve el calendario en español — que es
/// lo correcto en una app cuyo texto propio es todo español.
const List<LocalizationsDelegate<Object>> jayaloLocalizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Ver [jayaloLocalizationsDelegates]: uno solo, y a propósito.
const List<Locale> jayaloSupportedLocales = [Locale('es')];

/// SIN animación en los cambios de sección (PO 2026-07-19, 4ª pasada —
/// REVIERTE el deslizado de las directrices 07-18/07-19 anteriores):
/// "veo que WhatsApp, Spotify no tienen loader en cada sección, solo le das
/// clic y pasa… vamos a eliminar la animación de cambio de sección". El
/// deslizado horizontal con frenado de 2s quedó descartado — un solo builder
/// aquí cubre las ~15 rutas de `core/router.dart` sin tocarlas una por una.
///
/// Las 4 excepciones pedidas por el PO (Crear solicitud, Notificaciones, Ver
/// ofertas, menú de Avatar) NO pasan por este builder — cada una es un
/// `CustomTransitionPage`/`showModalBottomSheet`/`showGeneralDialog` con su
/// propia animación, independiente del `PageTransitionsTheme`. Ver
/// `core/router.dart` (`/client/create`, `/notifications`),
/// `client/request_status_screen.dart` (`_showOffers`) y
/// `shared/profile_avatar_button.dart` (`openProfileMenu`).
class _JayaloPageTransitionsBuilder extends PageTransitionsBuilder {
  const _JayaloPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// Física de scroll con frenado largo (PO 2026-07-19, 4ª pasada: "el scroll
/// de la pantalla ponle 2 segundos de frenado"; 5ª pasada: 4 s).
///
/// **Solo cambia la fase de FLING** — lo que pasa después de soltar el dedo. El
/// arrastre con el dedo, el rebote, el clamp de los bordes y el indicador de
/// overscroll siguen siendo exactamente los de Material/Android: esta clase no
/// redefine `applyPhysicsToUserOffset`, `applyBoundaryConditions`, `spring` ni
/// nada del gesto. Lo único que hace es sustituir la simulación balística.
///
/// Cuando la posición está FUERA de rango, `super` devuelve un
/// `ScrollSpringSimulation` (el muelle que devuelve el contenido al borde) —
/// ese caso se deja intacto: no es un fling, es una corrección de límite. Y
/// cuando `super` devuelve `null` (velocidad por debajo de la tolerancia, o ya
/// pegado al tope) tampoco se inventa nada.
///
/// Desde el 2026-08-03 el fling usa **decaimiento exponencial**
/// (`FrictionSimulation`, el modelo de iOS) en vez de la spline de Android
/// (`ClampingScrollSimulation`). El motivo, medido sobre 615 flings reales:
/// con la spline la duración iba como `v^0.736` y había 6.3× de diferencia
/// entre el swipe suave y el brusco, así que solo el brusco se sentía premium.
/// El exponencial baja ese reparto a 1.7×. La aritmética y el porqué están en
/// [dragForBrake]; la palanca sigue siendo [JayaloMotion.scrollBrake].
class JayaloScrollPhysics extends ClampingScrollPhysics {
  const JayaloScrollPhysics({super.parent});

  /// SONDA DE CALIBRACIÓN — TEMPORAL (2026-08-03).
  ///
  /// Registra la velocidad de cada fling REAL para saber dónde caen de verdad
  /// los swipes suave / moderado / fuerte en la mano del PO. De aquí salió el
  /// valor medido de [JayaloMotion.flingReference], que antes era una
  /// suposición (3000 px/s) que resultó estar en el p90-p95 del uso real.
  ///
  /// Apagada salvo que se compile con `--dart-define=SCROLL_PROBE=true`, así
  /// que no puede llegar a un release por descuido. Solo LEE: no cambia la
  /// simulación, ni el arrastre con el dedo, ni los bordes.
  ///
  /// Se conserva para poder recalibrar en otro device o con otra mano sin
  /// volver a escribirla.
  static const _probe = bool.fromEnvironment('SCROLL_PROBE');

  @override
  JayaloScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      JayaloScrollPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final sim = super.createBallisticSimulation(position, velocity);
    // Todo lo que NO sea un fling en rango se devuelve tal cual: el muelle del
    // borde y el `null` de "aquí no hay fling" son decisiones de `super`.
    if (sim is! ClampingScrollSimulation) return sim;
    if (_probe) {
      // Una línea por fling, greppable. `sim.velocity` y no el `velocity` del
      // argumento: es el que la simulación va a usar de verdad.
      debugPrint('SCROLLPROBE ${sim.velocity.abs().toStringAsFixed(1)}');
    }
    final tolerance = toleranceFor(position);
    return FrictionSimulation(
      JayaloMotion.scrollDragFor(tolerance.velocity),
      sim.position,
      sim.velocity,
      tolerance: tolerance,
    );
  }
}

/// Aplica [JayaloScrollPhysics] a TODA la app de una vez (listas, sheets,
/// scrollables anidados) sin tocar pantalla por pantalla. Un widget que pase
/// su propia `physics` explícita sigue mandando — p. ej. el
/// `NeverScrollableScrollPhysics` de `SkeletonList`.
class JayaloScrollBehavior extends MaterialScrollBehavior {
  const JayaloScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const JayaloScrollPhysics();
}

/// Los colores salen de `core/brand.dart` (tokens portados de la web) para que
/// app y jayalo.com se vean como la misma marca.
ThemeData jayaloTheme(Brightness b) {
  final cs = jayaloScheme(b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    visualDensity: VisualDensity.standard,
    // "F1 · Rellenos suaves" (elegida por el PO): la receta única de campo de
    // texto — fondo gris suave, radius 12, sin borde. Los TextField que no
    // pasan decoración explícita la heredan de aquí.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      // Solo Android: es la única plataforma que empaqueta la app (iOS
      // descartado, ver memoria del proyecto).
      TargetPlatform.android: _JayaloPageTransitionsBuilder(),
    }),
  );
}

class JayaloApp extends StatefulWidget {
  const JayaloApp({super.key, required this.router});
  final GoRouter router;
  @override
  State<JayaloApp> createState() => _JayaloAppState();
}

class _JayaloAppState extends State<JayaloApp> {
  // Para el snackbar global del retorno de PayPal (fuera de cualquier Scaffold).
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<CreditPurchaseEvent>? _billingSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    onboardingStore.ensureLoaded();
    // Un login nuevo (p. ej. cambio de usuario en el mismo dispositivo) debe
    // recargar el store desde el backend — ver `onboardingStore.reload()`.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) onboardingStore.reload();
    });
    _initPlayBilling();
  }

  /// Recuperacion de compras de Play, AL ARRANCAR y no al abrir la tienda.
  ///
  /// Una compra puede quedar cobrada y sin acreditar por muchas vias que el
  /// servidor marca como reintentables: Google caido, sesion vencida, un pago
  /// diferido que Google confirma horas despues. El reintento consiste en
  /// pedirle a Play las compras vivas (`restorePurchases`) y volver a
  /// verificarlas. Si eso solo ocurriera al abrir la tienda de creditos, el
  /// usuario que pago y no volvio a entrar ahi no cobraria nunca.
  ///
  /// El listener global existe porque para entonces la tienda no esta montada
  /// y nadie mas veria el resultado.
  Future<void> _initPlayBilling() async {
    _billingSub = playBilling.events.listen((e) {
      if (e.kind != CreditPurchaseKind.credited) return;
      // El saldo autoritativo lo acaba de devolver el servidor: sembrar el
      // cache evita que el navbar siga ensenando el saldo viejo hasta que
      // caduque el TTL, justo cuando el usuario acaba de pagar.
      if (e.balance != null) {
        AppCaches.wallet.set(e.balance!);
        // Y el contador de las cabeceras, que si no seguiría con el saldo de
        // antes de pagar hasta que la pantalla se volviera a montar.
        saldoStore.set(e.balance!);
      }
      // Con la tienda EN PANTALLA el aviso lo da ella, y en grande: el vuelo
      // de monedas al contador y, al terminar, la celebración de la recarga
      // (mockup B, PO 2026-08-23). Un snackbar además asomaría por debajo del
      // panel mientras baja y volvería a decir lo mismo al salir de él.
      //
      // Fuera de la tienda este listener sigue siendo el UNICO dueno del
      // aviso: cubre el pago diferido que Google confirma horas despues, con
      // la tienda ya desmontada y nadie mas mirando.
      final enLaTienda = widget.router.routerDelegate.currentConfiguration
          .matches
          .any((m) => m.matchedLocation == '/tienda-creditos');
      if (enLaTienda) return;
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text('Listo. Tienes ${e.balance ?? 0} créditos.'),
      ));
    });
    // Sin sesion no hay a quien acreditar. `watchAuth` rearranca cuando la
    // sesion APARECE: cubre el arranque en frio (`Supabase.initialize` no
    // espera a `recoverSession()`, asi que el guard de abajo puede saltar
    // aunque haya sesion guardada) y el login posterior a abrir la app. Sin
    // el, la recuperacion volvia a depender de abrir la tienda.
    playBilling.watchAuth(Supabase.instance.client.auth.onAuthStateChange);
    if (Supabase.instance.client.auth.currentSession == null) return;
    await playBilling.start();
  }

  /// Deep link de retorno de la recarga por PayPal (jayalo://wallet): trae la
  /// app al frente (lo hace el intent), va a "Mis ofertas" (que re-lee el
  /// saldo) y avisa. El pago sigue ocurriendo 100% en la web.
  Future<void> _initDeepLinks() async {
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink(); // arranque en frío
      if (initial != null) _handleLink(initial);
      _linkSub = links.uriLinkStream.listen(_handleLink, onError: (_) {});
    } catch (_) {
      // Sin deep links la app funciona igual (solo no auto-refresca al volver).
    }
  }

  /// El único deep link declarado en el manifest es `jayalo://wallet`.
  ///
  /// Antes esto solo miraba el `scheme`: CUALQUIER `jayalo://loquesea` navegaba
  /// a "Mis ofertas" y cantaba "¡Listo! Tus créditos ya están disponibles" sin
  /// mirar el host ni consultar el saldo. Tras CANCELAR en PayPal el usuario leía
  /// que tenía créditos que no tenía. No había riesgo de fraude (el saldo es
  /// server-side) pero sí de confianza y de tickets de soporte.
  ///
  /// Ahora: se exige el host, y el aviso se arma con el SALDO REAL releído del
  /// backend en vez de darlo por hecho.
  Future<void> _handleLink(Uri uri) async {
    if (uri.scheme != 'jayalo' || uri.host != 'wallet' || !mounted) return;
    widget.router.go('/provider/offers');

    // `?paid=1` lo pone el botón "Volver a la app" de la web, que aparece
    // vuelva o no de un pago exitoso: es una pista, no una prueba.
    if (uri.queryParameters['paid'] != '1') return;

    AppCaches.wallet.clear();
    int? balance;
    try {
      balance = await walletBalance();
    } catch (_) {
      balance = null;
    }
    if (!mounted) return;
    _messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(balance == null
              ? 'Volviste de la recarga. Revisa tu saldo en Billetera.'
              : 'Tu saldo es de $balance créditos.')));
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _authSub?.cancel();
    _billingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        // El toggle "Modo oscuro" de Ajustes escribe [themeStore]; el tema se
        // aplica a toda la app desde aquí (decisión PO 2026-07-23: el oscuro ya
        // se puede activar). El default del store es claro, así que sin tocar
        // el toggle la app se ve igual que antes. `themeMode` sigue siendo
        // binario claro/oscuro (no `system`) por pedido del PO.
        valueListenable: themeStore,
        builder: (context, mode, _) => MaterialApp.router(
          title: 'Jayalo',
          scaffoldMessengerKey: _messengerKey,
          theme: jayaloTheme(Brightness.light),
          darkTheme: jayaloTheme(Brightness.dark),
          themeMode: mode,
          localizationsDelegates: jayaloLocalizationsDelegates,
          supportedLocales: jayaloSupportedLocales,
          scrollBehavior: const JayaloScrollBehavior(),
          // Overlay de rendimiento, apagado salvo que se pida al compilar:
          //
          //   flutter build apk --profile --dart-define=PERF_OVERLAY=true
          //
          // Pinta las dos barras de Flutter (arriba el hilo de UI = construir
          // y hacer layout de widgets; abajo el de RASTER = pintar en la GPU).
          // Cada barra son 300 frames; la línea verde es el presupuesto de
          // 16ms. Las barras que la cruzan son los frames perdidos, y CUÁL de
          // las dos se pasa dice dónde está el problema: arriba es código
          // Dart, abajo son efectos de pintado (sombras, blur, clips).
          //
          // Va por `dart-define` y no por una constante a mano para que nadie
          // la deje encendida por olvido: en un build normal es `false`
          // constante y el árbol del overlay ni se compila.
          //
          // ⚠️ Medir SOLO en `--profile`. En debug los números mienten (el JIT
          // y los asserts pesan más que el código real) y en release no hay
          // instrumentación.
          showPerformanceOverlay:
              const bool.fromEnvironment('PERF_OVERLAY'),
          routerConfig: widget.router,
        ),
      );
}
