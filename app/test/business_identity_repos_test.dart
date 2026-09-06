import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

void main() {
  test('businessImagePath espeja la ruta de la web y arranca con el uid', () {
    final p = businessImagePath(
        uid: 'u1', businessId: 'b1', kind: 'covers', ext: 'png', ts: 123);
    expect(p, 'u1/covers/b1-123.png'); // RLS: primera carpeta = auth.uid()
  });
  test('businessImagePath para logo no repite el patrón viejo', () {
    final p = businessImagePath(
        uid: 'u1', businessId: 'b1', kind: 'logos', ext: 'jpg', ts: 9);
    expect(p, 'u1/logos/b1-9.jpg');
  });


  // --- Regresión: el 42501 que dejó Ajustes sin filas de verificación ---
  // La migración 20260710011825 (`close_rnc_address_grant`) le revocó a
  // `authenticated` el SELECT sobre `rnc`/`address` y dejó la RPC
  // `get_my_business_private` como única puerta del dueño. Pedir `rnc` en el
  // select NO devuelve null: PostgREST corta con
  // `42501 permission denied for table provider_businesses` y tumba la
  // consulta ENTERA, así que `_biz` se quedaba en null y desaparecían tanto
  // "Validar RNC" como "Validar negocio (cédula)".
  test('el select de verificación no pide columnas sin grant de SELECT', () {
    final cols = kBusinessVerificationColumns.split(',');
    // Candado contra la lista COMPLETA, no solo contra `rnc`: la misma mina
    // pisó `whatsapp` en `_verifyBusiness` y nadie se enteró en mes y medio.
    for (final prohibida in kProviderBusinessesSinSelect) {
      expect(cols, isNot(contains(prohibida)),
          reason: '`$prohibida` no tiene SELECT para authenticated: pedirla '
              'tumba la consulta ENTERA con 42501, no la devuelve nula.');
    }
    // Y sigue trayendo lo que Ajustes necesita para decidir qué filas pinta.
    expect(cols, containsAll(<String>['id', 'business_type']));
    expect(cols, containsAll(<String>['identity_verified_at', 'business_verified_at']));
  });

  test('mergeBusinessRnc pega el rnc de la RPC sobre la fila base', () {
    final m = mergeBusinessRnc(
      {'id': 'b1', 'business_type': 'formal', 'business_verified_at': null},
      [
        {'rnc': '132753313', 'address': 'Calle X'}
      ],
    );
    expect(m['rnc'], '132753313');
    expect(m['id'], 'b1');
    expect(m['business_type'], 'formal');
  });

  test('mergeBusinessRnc sin fila privada deja el rnc nulo y no revienta', () {
    expect(mergeBusinessRnc({'id': 'b1'}, <dynamic>[])['rnc'], isNull);
    expect(mergeBusinessRnc({'id': 'b1'}, null)['rnc'], isNull);
    // El Map suelto NO es un contrato de PostgREST (rpc() es POST y siempre
    // devuelve lista): se tolera por barato, no porque ocurra.
    expect(mergeBusinessRnc({'id': 'b1'}, {'rnc': '131005969'})['rnc'],
        '131005969');
  });
}
