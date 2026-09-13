import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/core/error_reporter.dart';
import 'package:jayalo_app/features/provider/unlock_flow.dart';
import 'package:jayalo_app/features/shared/celebration.dart';

/// «¡Iniciar conversación!» tiene que ABRIR el chat.
///
/// El botón cierra la celebración y navega, y ese orden es el contrato que se
/// ancla aquí: el cierre del overlay viaja por el Navigator IMPERATIVO
/// (`showGeneralDialog` → `maybePop`) y el chat por la pila DECLARATIVA de
/// GoRouter. Son dos caminos distintos y no se deduce leyendo cuál gana.
///
/// El arnés reproduce el cableado REAL de `unlock_flow.dart` y de
/// `product_interest_detail_screen.dart` (misma celebración, mismo footer,
/// mismo `context.push('/messages/<id>')` con el context de la PANTALLA) y,
/// con [conShell], la FORMA real del router: la pantalla de la que sales vive
/// DENTRO del `ShellRoute` y el chat es una ruta TOP-LEVEL hermana del shell
/// (así está declarado a propósito en `core/router.dart`, para que el chat
/// cubra la barra inferior). Ir de una a otra reescribe la pila de GoRouter
/// por debajo del overlay.
/// Pantalla de origen cuyo CONTEXTO puede morir mientras la celebración está
/// abierta — exactamente lo que pasa en «Mis ofertas»: el `context` que se le
/// pasa al flujo es el de la TARJETA de la oferta, y entre el desbloqueo y el
/// toque en «¡Iniciar conversación!» pasan segundos en los que la lista se
/// refresca y esa tarjeta se reemplaza.
class _Origen extends StatefulWidget {
  const _Origen({required this.onAbrir});
  final void Function(BuildContext) onAbrir;
  @override
  State<_Origen> createState() => _OrigenState();
}

class _OrigenState extends State<_Origen> {
  int _gen = 0;
  void refrescar() => setState(() => _gen++);
  @override
  Widget build(BuildContext context) => Center(
        child: Builder(
          key: ValueKey(_gen),
          builder: (c) => ElevatedButton(
            onPressed: () => widget.onAbrir(c),
            child: const Text('desbloquear'),
          ),
        ),
      );
}

void main() {
  const convId = 'd7a8a31a-8389-4a5a-ab9e-4d21a7c9b650';

  GoRoute rutaHome({Future<String?> Function()? crear}) => GoRoute(
        path: '/',
        builder: (_, _) => _Origen(
          onAbrir: (c) => showUnlockCelebration(
            c,
            footer: (dismiss) => StartChatButton(
              conversationKind: 'offer',
              sourceId: 'offer-1',
              dismiss: dismiss,
              createConversation: (_, _) async =>
                  crear != null ? await crear() : convId,
              onOpen: (router, id) => router.push('/messages/$id'),
            ),
          ),
        ),
      );

  GoRoute rutaChat() => GoRoute(
        path: '/messages/:id',
        builder: (_, s) => Scaffold(
          body: Center(child: Text('CHAT ${s.pathParameters['id']}')),
        ),
      );

  Widget host({required bool conShell, Future<String?> Function()? crear}) =>
      MaterialApp.router(
        theme: jayaloTheme(Brightness.light),
        routerConfig: GoRouter(
          navigatorKey: GlobalKey<NavigatorState>(),
          initialLocation: '/',
          routes: [
            if (conShell)
              ShellRoute(
                builder: (_, _, child) => Scaffold(
                  body: child,
                  bottomNavigationBar: const SizedBox(height: 56),
                ),
                routes: [rutaHome(crear: crear)],
              )
            else
              rutaHome(crear: crear),
            rutaChat(),
          ],
        ),
      );

  /// [asentar] solo cuando se espera que la celebración se CIERRE. Si se
  /// queda abierta, su animación no para nunca y `pumpAndSettle` expira.
  Future<void> desbloquearYPulsar(WidgetTester tester,
      {bool asentar = true}) async {
    await tester.tap(find.text('desbloquear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // El footer solo se revela cuando la celebración termina de entrar.
    await tester.pump(const Duration(seconds: 4));
    final boton = find.text('¡Iniciar conversación!');
    expect(boton, findsOneWidget, reason: 'el footer tiene que estar visible');
    await tester.tap(boton);
    if (asentar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('con la forma REAL del router (shell → ruta top-level) acaba en el chat',
      (tester) async {
    await tester.pumpWidget(host(conShell: true));
    await desbloquearYPulsar(tester);

    expect(find.text('CHAT $convId'), findsOneWidget,
        reason: 'el botón promete llevar al chat; tiene que llevar');
    expect(find.byKey(const ValueKey('celebration-unlock')), findsNothing,
        reason: 'la celebración no puede quedarse encima del chat');
  });

  // El fallo tiene que verse DONDE mira el usuario. Iba por
  // `ScaffoldMessenger` y era invisible por construcción: la celebración es un
  // overlay violeta a pantalla completa y el snack se dibuja en el Scaffold de
  // debajo — un desbloqueo ya cobrado fallaba sin decir nada.
  testWidgets('si no hay conversación, el aviso se ve DENTRO de la celebración',
      (tester) async {
    await tester.pumpWidget(host(conShell: true, crear: () async => null));
    await desbloquearYPulsar(tester, asentar: false);

    expect(find.text('No se pudo abrir el chat. Intenta de nuevo.'),
        findsOneWidget,
        reason: 'el aviso tiene que estar sobre el violeta, no detrás');
    expect(find.byKey(const ValueKey('celebration-unlock')), findsOneWidget,
        reason: 'la celebración no se cierra: deja reintentar');
    expect(find.text('CHAT $convId'), findsNothing);
  });

  testWidgets('si el RPC lanza, se reporta y no queda mudo', (tester) async {
    Object? reportado;
    debugOnReport = (e) => reportado = e;
    addTearDown(() => debugOnReport = null);

    await tester.pumpWidget(
        host(conShell: true, crear: () async => throw StateError('boom')));
    await desbloquearYPulsar(tester, asentar: false);

    expect(reportado, isA<StateError>(),
        reason: 'un `catch (_) {}` dejaba este camino sin rastro en error_events');
    expect(find.text('No se pudo abrir el chat. Intenta de nuevo.'),
        findsOneWidget);
  });

  // 🔴 EL FALLO QUE REPORTÓ EL PO (2026-09-12): «la ventana solo salió y se
  // quedó en el mismo lugar, no abrió el chat». Medido en el teléfono con el
  // 1.0.4+125: la celebración SÍ se cerró (o sea, la conversación se creó bien)
  // y `error_events` no registró nada — la navegación se descartó en silencio
  // porque el `context` de la tarjeta de origen ya estaba muerto.
  testWidgets('si la pantalla de origen se refresca, IGUAL acaba en el chat',
      (tester) async {
    await tester.pumpWidget(host(conShell: true));
    await tester.tap(find.text('desbloquear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 4));

    // La lista de ofertas se refresca mientras el violeta está encima: la
    // tarjeta que abrió el flujo se reemplaza y su elemento queda difunto.
    tester.state<_OrigenState>(find.byType(_Origen)).refrescar();
    await tester.pump();

    await tester.tap(find.text('¡Iniciar conversación!'));
    await tester.pumpAndSettle();

    expect(find.text('CHAT $convId'), findsOneWidget,
        reason: 'navegar no puede depender de que siga viva la tarjeta que '
            'abrió el flujo');
  });

  testWidgets('sin shell (rutas planas) también acaba en el chat',
      (tester) async {
    await tester.pumpWidget(host(conShell: false));
    await desbloquearYPulsar(tester);

    expect(find.text('CHAT $convId'), findsOneWidget);
  });
}
