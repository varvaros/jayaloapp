import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// «Null check operator used on a null value», 5 veces en producción.
///
/// `State.context` es `_element!`: si la pantalla ya murió, el `!` revienta.
/// `_useLocation` del alta de cliente avisa DESPUÉS de esperas largas — el
/// permiso del sistema y, sobre todo, los 15 s de `timeLimit` del GPS. Quien
/// toca «Usar mi ubicación» bajo techo y se va de la pantalla se lleva el
/// crash: el `catch` dispara el aviso contra un `State` desmontado.
///
/// La pantalla NO se puede montar en un widget test (su `initState` lee
/// `supa.auth.currentUser`, y `Supabase.instance` exige `Supabase.initialize`
/// — el mismo motivo documentado en `offer_prefill_from_store_test.dart`), así
/// que la guarda se vigila sobre el fuente, como en `no_link_out_test.dart`.
///
/// El barrido cubre los DIEZ helpers `_snack` del repo, no solo el que se
/// llevó el crash: el patrón se copia de pantalla en pantalla, y de los diez
/// solo `chat_screen.dart` traía la guarda. Un fichero nuevo con `_snack` no
/// entra solo en esta lista — añadirlo aquí es parte de escribirlo.
void main() {
  const vigilados = <String>[
    'lib/features/chat/chat_screen.dart',
    'lib/features/client/offer_actions.dart',
    'lib/features/onboarding/consumer_onboarding_screen.dart',
    'lib/features/onboarding/provider_onboarding_screen.dart',
    'lib/features/provider/credit_shop_screen.dart',
    'lib/features/provider/product_interest_detail_screen.dart',
    // Función suelta, no método de un State: comprueba `context.mounted`.
    'lib/features/provider/unlock_flow.dart',
    'lib/features/settings/address_screen.dart',
    'lib/features/settings/settings_screen.dart',
    'lib/features/verification/id_doc_sheet.dart',
  ];

  for (final ruta in vigilados) {
    test('$ruta: _snack no toca context sin comprobar mounted', () {
      final src = File(ruta).readAsStringSync();
      final i = src.indexOf('void _snack(');
      expect(i, greaterThan(-1), reason: 'se movió o se renombró _snack en $ruta');

      // Cuerpo del helper: de la firma a la primera línea en blanco (el
      // siguiente miembro). Una ventana de N caracteres se metería dentro de
      // `build` y daría verde con un `mounted` que no es el de aquí.
      final resto = src.substring(i).replaceAll('\r\n', '\n');
      final fin = resto.indexOf('\n\n');
      final cuerpo = fin == -1 ? resto : resto.substring(0, fin);

      expect(cuerpo.contains('ScaffoldMessenger.of(context)'), isTrue,
          reason: '_snack ya no usa context — revisar este test');
      expect(cuerpo.contains('mounted'), isTrue,
          reason: '_snack volvió a tocar context sin guarda de mounted en $ruta');
    });
  }
}
