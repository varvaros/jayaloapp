import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion.dart';
import '../../core/session_state.dart';
import 'floating_nav_bar.dart';
import 'nav_destinations.dart';

/// Desplazamiento vertical del `body` al entrar (spec de movimiento, punto 1
/// del cierre de rama): arranca `_bodyEnterSlide` px por debajo de su
/// posición final y sube mientras se desvanece — el mismo lenguaje visual
/// que ya usa la barra flotante al aparecer (`SizeTransition` + fundido más
/// abajo), solo que aquí es una traslación pequeña porque no hay ningún alto
/// de layout que reservar.
const _bodyEnterSlide = 16.0;

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // El gate garantiza que aquí el rol ya está resuelto (spec §4).
    // El ATRÁS del sistema lo maneja BackGuard DENTRO de cada ruta del shell
    // (un PopScope aquí no funciona con predictive back; ver back_guard.dart).
    final dests = destinationsFor(roleStore.value);
    // C2 (revisión final de rama, iteración 2): `GoRouterState.of(context)`
    // AQUÍ (dentro del builder del propio ShellRoute) expone el estado del
    // "top route" de la rama — `matchedLocation`/`topRoute` solo se mueven
    // cuando ese top route CAMBIA (`go` a otra ruta de nivel superior). Un
    // `push` (entrar al chat desde `conversations_screen.dart`, "Abrir chat"
    // de `inbox_screen.dart`, o abrir notificaciones) apila una página encima
    // SIN cambiar cuál es el top route, así que `matchedLocation` se quedaba
    // congelado en la pestaña de abajo — la barra flotante seguía viva
    // encima del chat tapando el campo de escribir, y `/provider/stats`/
    // `/notifications` heredaban la pestaña de abajo en vez de dar -1
    // (dejando `_excludedFromNav` como código muerto). `uri` sí seguía la
    // ubicación efectiva (incluye lo apilado por push) — se usa `.path`, NUNCA
    // `.toString()`: este proyecto tiene enlaces con query (`/messages?c=<id>`
    // desde las notificaciones de mensaje) y tanto `showsNavBar` como
    // `activeIndex` comparan por igualdad/prefijo — una query pegada rompería
    // ambas comparaciones en silencio.
    final loc = GoRouterState.of(context).uri.path;
    final idx = activeIndex(dests, loc);
    final showNavBar = showsNavBar(loc);

    return Scaffold(
      // La barra FLOTA: el cuerpo se extiende por debajo de ella. Cada
      // pantalla reserva `kNavBarReservedSpace` al final de su scroll. Dentro
      // de una conversación la barra se oculta (decisión PO: ahí no se
      // navega, se conversa) y `extendBody` deja de tener sentido — sin él el
      // cuerpo ocupa el alto normal y el campo de escribir del chat queda
      // donde debe, sin el hueco que dejaría el espacio reservado para una
      // barra que ya no está.
      extendBody: showNavBar,
      // NO envolver `child` en un `AnimatedSwitcher`/`KeyedSubtree` cuyo key
      // dependa de `idx`/`loc` (así estaba antes, para un "fade through" al
      // cambiar de pestaña; se retiró al escribir la cobertura de C2). `child`
      // es el Navigator anidado que arma el propio `ShellRoute`, con un
      // `GlobalKey` ESTABLE por diseño de go_router (necesario para conservar
      // su estado entre navegaciones dentro de la misma rama) — y
      // `AnimatedSwitcher` mantiene montadas simultáneamente la rama saliente
      // y la entrante mientras cruza-desvanece. Con un key que cambia en
      // cualquier transición de pestaña real (probado con un `go()` liso
      // entre dos pestañas normales, sin tocar `push` ni `-1`: `/provider` →
      // `/provider/offers`), las dos ramas embeben el MISMO `child` con el
      // MISMO `GlobalKey` a la vez → "Duplicate GlobalKey detected in widget
      // tree".
      //
      // Corrección (revisión final de rama, cierre): lo anterior NO era un
      // cuelgue real. Medido en vivo: es un `FlutterError` de BUILD atrapado
      // por el framework — se reporta una vez en el log y el frame se
      // recupera solo; la pantalla destino queda correcta al asentarse (sin
      // excepción a mitad de transición ni tras el settle, `ofertas=1`). El
      // daño real era doble: (a) un error de log en CADA cambio de pestaña,
      // puro ruido, y (b) que la rama saliente se destruía de golpe en vez de
      // cruzar-desvanecerse — el "fade through" nunca llegó a cruzar nada.
      // Quitarlo no regresionó nada que estuviera vivo. El "fade through"
      // auténtico (dos subárboles vivos a la vez, cruzando) exigiría que cada
      // pestaña tuviera su PROPIO Navigator (`StatefulShellRoute`) — decisión
      // de backlog del PO, no se hace aquí.
      //
      // Lo que SÍ repone el movimiento sin ese riesgo (doctrina PO: nada de
      // swaps instantáneos): fundido + deslizado SOLO DE ENTRADA, con UN
      // ÚNICO subárbol vivo a la vez. La key es `matchedLocation`, no
      // `loc`/`uri.path` de arriba — es justo la "ubicación pegajosa" que el
      // propio C2 documentó: se congela durante un `push` (entrar a un chat,
      // abrir Estadísticas o Notificaciones) y solo se mueve cuando cambia la
      // ruta de nivel superior. Por eso un `push` nunca dispara esta
      // animación (no compite con la transición propia del Navigator
      // empujando su página) y un cambio de pestaña real sí. Al cambiar la
      // key, Flutter desactiva el elemento viejo y arma uno nuevo en el mismo
      // paso síncrono — nunca coexisten dos, así que el `GlobalKey` estable de
      // `child` jamás se duplica (ver test "ningún `go()` entre pestañas
      // lanza excepción").
      body: TweenAnimationBuilder<double>(
        key: ValueKey(GoRouterState.of(context).matchedLocation),
        tween: Tween(begin: 0, end: 1),
        duration:
            JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base,
        curve: JayaloMotion.enter,
        builder: (context, t, bodyChild) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * _bodyEnterSlide),
            child: bodyChild,
          ),
        ),
        child: child,
      ),
      // M2 (revisión final de rama): antes era `showNavBar ? FloatingNavBar(
      // ...) : null` — un swap instantáneo, contra la doctrina de movimiento
      // (transiciones premium, deslizado + ease-out). `SizeTransition` (no
      // `AnimatedSlide`/`Offset`) porque esta barra es la que RESERVA su
      // propio espacio de layout: una traslación con `SlideTransition` solo
      // mueve el render, no el alto que el `Scaffold` reserva para ella —
      // el hueco muerto seguiría ahí hasta que el widget saliente se
      // desmontara de golpe al final (el mismo pop que se busca arreglar,
      // solo que retrasado). `SizeTransition` anima el alto reservado EN SÍ,
      // en sincronía con el desvanecido — así el chat recupera el espacio
      // del campo de escribir gradualmente, nunca de un salto ni con hueco
      // muerto. `axisAlignment: 1` la ancla abajo: crece hacia arriba desde
      // el borde inferior al aparecer, se hunde hacia ese mismo borde al
      // ocultarse — nunca cambia `kNavBarReservedSpace` ni el alto real
      // renderizado en reposo (`nav_bar_reserved_space_test.dart` sigue
      // midiendo el `FloatingNavBar` real, sin tocar).
      bottomNavigationBar: AnimatedSwitcher(
        duration:
            JayaloMotion.reduced(context) ? Duration.zero : JayaloMotion.base,
        switchInCurve: JayaloMotion.enter,
        switchOutCurve: JayaloMotion.exit,
        transitionBuilder: (child, animation) => SizeTransition(
          sizeFactor: animation,
          // Bottom-anchorada (el eje horizontal no importa: no se anima el
          // ancho, solo el alto). Reemplaza al `axisAlignment: 1` deprecado
          // — misma alineación efectiva (`AlignmentDirectional(-1.0, 1.0)`
          // con eje vertical), solo que expresado con la API nueva.
          alignment: Alignment.bottomCenter,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: showNavBar
            ? FloatingNavBar(
                key: const ValueKey('nav-bar-visible'),
                destinations: dests,
                currentIndex: idx,
                onSelected: (i) => context.go(dests[i].route),
              )
            : const SizedBox.shrink(key: ValueKey('nav-bar-hidden')),
      ),
    );
  }
}
