import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jayalo_app/app.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// `HeaderLeading`: el leading del header violeta que se auto-ajusta. Como
/// pestaña raíz (nada apilado que popear) muestra el avatar de perfil; abierto
/// apilado (p. ej. un proveedor entrando a "Mis solicitudes" desde el menú del
/// avatar) muestra una flecha de atrás en su lugar. Así las mismas pantallas
/// sirven de pestaña (avatar) y de sub-pantalla empujada (atrás visible).
void main() {
  GoRouter router() => GoRouter(
        initialLocation: '/root',
        routes: [
          GoRoute(
            path: '/root',
            builder: (_, _) => Scaffold(
              body: Column(children: [
                const VioletHeader(leading: HeaderLeading(), title: 'Raíz'),
                Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => context.push('/sub'),
                    child: const Text('ir'),
                  ),
                ),
              ]),
            ),
          ),
          GoRoute(
            path: '/sub',
            builder: (_, _) => const Scaffold(
              body: VioletHeader(leading: HeaderLeading(), title: 'Sub'),
            ),
          ),
        ],
      );

  Widget host() => MaterialApp.router(
        theme: jayaloTheme(Brightness.light),
        routerConfig: router(),
      );

  testWidgets('pestaña raíz (nada que popear): muestra el avatar, no atrás',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(HeaderAvatar), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('pantalla apilada (canPop): muestra atrás, no el avatar',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('ir'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byType(HeaderAvatar), findsNothing);
  });

  testWidgets('tocar atrás vuelve a la pantalla anterior', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('ir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Raíz'), findsOneWidget);
    expect(find.text('Sub'), findsNothing);
  });
}
