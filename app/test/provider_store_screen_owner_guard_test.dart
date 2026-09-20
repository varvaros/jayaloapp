import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:jayalo_app/features/client/provider_store_screen.dart';

/// Blinda el CABLEADO de I-5, no solo la decisión pura `esDuenoDe`
/// (`store_ownership_test.dart`): monta la pantalla REAL
/// (`ProviderStoreScreen`, no `ProviderStoreView`) con `loadBusinesses`
/// inyectado (mismo patrón que `AssistantMonthlyCard._cargar()`,
/// `features/provider/assistant_monthly_card.dart:70`:
/// `await (widget.loadBusinesses ?? myBusinessesForAssistant)()`) y afirma lo
/// que el USUARIO ve. Si alguien revierte `provider_store_screen.dart` a
/// `myBusinessId() == widget.businessId` (o a comparar solo con el primer
/// negocio de la lista), este archivo se pone ROJO aunque
/// `store_ownership_test.dart` siga en verde — confirmado a mano antes de
/// escribir esto: parcheando `_load()` para usar solo `negocios.first.id`,
/// el caso (a) de abajo falla.
///
/// Este repo NO mockea Supabase en general (`admin_recruit_repos_test.dart`:
/// "un singleton que exige `Supabase.initialize()` real"). Aquí se hace una
/// EXCEPCIÓN deliberada y acotada, porque `ProviderStoreScreen.build()` lee
/// `supa.auth.currentUser` directo (para esconder el botón sin sesión) y sin
/// eso el widget no monta en absoluto. `Supabase.initialize` con un proyecto
/// FALSO no toca la red real (`TestWidgetsFlutterBinding` intercepta
/// `HttpClient` y devuelve 400 sin salir de la máquina — confirmado con un
/// sondeo antes de escribir esto), y `auth.recoverSession` con un JWT
/// fabricado a mano NO llama a la red (gotrue solo reintenta por red si el
/// token está VENCIDO — `gotrue_client.dart:1159`); las demás llamadas de
/// `_load()` (stats/identidad/paquetes/ubicación/catálogo) sí intentan de
/// verdad, fallan con ese 400 y degradan a sus valores por defecto — todas
/// YA tenían ese trato "best-effort" salvo el catálogo propio
/// (`myStoreProducts`/`myPortfolioItems`), al que esta misma revisión le
/// sumó un `.catchError` para que un fallo ahí no le impida a `_esDueno`
/// llegar a aplicarse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.invalid.test',
      publishableKey: 'test-publishable-key',
    );
    // Sesión LOCAL (sin red): sin ella `currentUser` es null y el botón se
    // esconde SIEMPRE por "sin sesión" (`provider_store_screen.dart:187`),
    // sin importar el resultado de `loadBusinesses` — el caso (b) de abajo
    // no probaría nada.
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': _fakeJwt('cliente-de-prueba'),
        'token_type': 'bearer',
        'refresh_token': 'refresh-fake',
        'expires_in': 3600,
        'user': {'id': 'cliente-de-prueba'},
      }),
    );
  });

  Future<void> montarTienda(
    WidgetTester tester, {
    required String businessId,
    required List<({String id, String name})> misNegocios,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderStoreScreen(
          businessId: businessId,
          loadBusinesses: () async => misNegocios,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }

  testWidgets(
    '(a) proveedor con DOS negocios NO ve «Pedir cotización» en su SEGUNDA '
    'tienda (bug I-5: myBusinessId() sin ORDER BY podía devolver la otra)',
    (tester) async {
      await montarTienda(
        tester,
        businessId: 'b2',
        misNegocios: const [(id: 'b1', name: 'Uno'), (id: 'b2', name: 'Dos')],
      );
      expect(find.text('Pedir cotización'), findsNothing);
    },
  );

  testWidgets(
    '(b) SÍ ve «Pedir cotización» en la tienda de un negocio que NO es suyo',
    (tester) async {
      await montarTienda(
        tester,
        businessId: 'b2',
        misNegocios: const [(id: 'b1', name: 'Uno')],
      );
      expect(find.text('Pedir cotización'), findsOneWidget);
    },
  );
}

String _fakeJwt(String sub) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
      1000;
  final header = b64({'alg': 'none', 'typ': 'JWT'});
  final payload = b64({'sub': sub, 'exp': exp});
  return '$header.$payload.sig';
}
