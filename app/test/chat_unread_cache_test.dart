import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

/// Bug del PO (2026-08-25): "entré a un chat y no se quita el número".
///
/// Al abrir un chat SÍ se marcan leídas sus notificaciones y el badge se
/// recuenta contra el servidor — eso funcionaba. Lo que lo deshacía era la
/// vuelta atrás: la lista de chats vive en un `TtlCache` de 20 s y `readFresh`
/// sirve el valor vigente SIN ir a la red, así que `conversations_screen`
/// volvía a sumar el `unread_count` de ANTES de leer y pisaba el badge con el
/// número viejo (`messagesBadge.set`, línea 171). La bolita de la propia fila
/// (línea 478) sale de ese mismo dato, así que se quedaba puesta igual.
///
/// Se corrige a mano sobre la lista cacheada en vez de vaciarla: vaciar
/// obligaría a un round-trip al volver y devolvería el loader que ese caché
/// existe para quitar.
void main() {
  List<Map<String, dynamic>> filas() => [
        {'id': 'a', 'unread_count': 3},
        {'id': 'b', 'unread_count': 2},
        {'id': 'c', 'unread_count': 0},
      ];

  test('pone a cero el no-leído del chat abierto', () {
    final rows = filas();
    expect(clearUnreadCountFor(rows, 'a'), isTrue);
    expect(rows.firstWhere((r) => r['id'] == 'a')['unread_count'], 0);
  });

  test('no toca las demás conversaciones', () {
    final rows = filas();
    clearUnreadCountFor(rows, 'a');
    expect(rows.firstWhere((r) => r['id'] == 'b')['unread_count'], 2);
    expect(rows.firstWhere((r) => r['id'] == 'c')['unread_count'], 0);
  });

  test('la suma del badge baja exactamente lo leído', () {
    final rows = filas();
    int suma() =>
        rows.fold<int>(0, (s, c) => s + ((c['unread_count'] as int?) ?? 0));
    expect(suma(), 5);
    clearUnreadCountFor(rows, 'a');
    expect(suma(), 2);
  });

  test('avisa que no cambió nada si ya estaba en cero', () {
    // Sin esto no se distingue "lo bajé" de "no había nada", y quien llame no
    // sabe si vale la pena repintar.
    expect(clearUnreadCountFor(filas(), 'c'), isFalse);
  });

  test('un id que no está en la lista no rompe ni cambia nada', () {
    // Pasa de verdad: al chat se puede llegar por push sin haber abierto nunca
    // la lista, así que el caché puede no tener esa fila.
    final rows = filas();
    expect(clearUnreadCountFor(rows, 'zzz'), isFalse);
    expect(rows.fold<int>(0, (s, c) => s + (c['unread_count'] as int)), 5);
  });

  test('una fila sin unread_count no revienta', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'a'},
    ];
    expect(clearUnreadCountFor(rows, 'a'), isFalse);
  });
}
