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
/// ⚠️ El MISMO patrón sin guarda sigue vivo en `provider_onboarding_screen.dart`
/// y `address_screen.dart` (reportado al PO, fuera del encargo de esta tanda).
/// El modelo bueno a copiar es el `_snack` de `chat_screen.dart`.
void main() {
  const vigilados = <String>[
    'lib/features/onboarding/consumer_onboarding_screen.dart',
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
