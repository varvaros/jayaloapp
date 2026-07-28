import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/conversations_screen.dart';
import 'package:jayalo_app/features/shared/violet_header.dart';

/// I1 (invariante de navegación, preservada tras el rediseño al header
/// violeta): Mensajes es la única pestaña raíz que se queda sin acceso propio
/// a Notificaciones y al menú de perfil (Ajustes/Estadísticas) si su header no
/// los trae. Antes eran `NotificationBell`/`ProfileAvatarButton` en el AppBar;
/// ahora son `HeaderBell` (acción) y `HeaderAvatar` (leading) del
/// `VioletHeader`. Dos pruebas complementarias: (1) los valores por defecto son
/// los esperados (barato, sin montar) y (2) el leading/acciones inyectados SÍ
/// llegan al `VioletHeader` real al montar la pantalla.
///
/// Se inyectan marcadores en vez de usar el default: `HeaderBell`/`HeaderAvatar`
/// tocan `Supabase.instance` en su `initState` (conteo/perfil) SIN atrapar el
/// error, y revienta si Supabase no está inicializado — el caso de los tests de
/// widgets de este proyecto. `leading`/`actions` son inyectables justo para
/// probar el contrato del header sin esos widgets reales (mismo patrón que
/// `CatalogView`/`ProviderInboxView`).
void main() {
  test('por defecto expone HeaderAvatar (leading) y HeaderBell (acción), como '
      'las demás pestañas raíz', () {
    const screen = ConversationsScreen();
    expect(screen.leading, isA<HeaderAvatar>(),
        reason: 'sin el avatar, Mensajes queda sin vía a Ajustes/Estadísticas');
    expect(screen.actions.whereType<HeaderBell>().length, 1,
        reason: 'sin la campana, Mensajes queda sin vía a Notificaciones');
  });

  testWidgets(
      'el leading y las acciones SÍ llegan al VioletHeader real al montar la '
      'pantalla (I1: si alguien deja de pasarlos, este test debe fallar)',
      (tester) async {
    const marcadorLeading = ValueKey('leading');
    const marcadorAccion = ValueKey('accion-1');
    await tester.pumpWidget(const MaterialApp(
      home: ConversationsScreen(
        leading: SizedBox(key: marcadorLeading),
        actions: [SizedBox(key: marcadorAccion)],
      ),
    ));
    // No `pumpAndSettle()`: el `_load()` de la pantalla es best-effort (sin
    // Supabase en los tests de widgets, cae a `_error = true`), pero eso no
    // impide que el primer frame ya tenga el header armado.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final header = find.byType(VioletHeader);
    expect(header, findsOneWidget);
    expect(find.descendant(of: header, matching: find.byKey(marcadorLeading)),
        findsOneWidget,
        reason: 'el leading inyectado no llegó al header real');
    expect(find.descendant(of: header, matching: find.byKey(marcadorAccion)),
        findsOneWidget,
        reason: 'la acción inyectada no llegó al header real');
  });

  /// Pedido PO 2026-07-28: "el chat solo tiene los nombres, debo entrar para
  /// saber qué se está negociando". El asunto (`product_name`, que en los chats
  /// de oferta ES el título de la solicitud) tiene que verse en su PROPIA línea.
  /// Antes iba concatenado al FINAL del último mensaje, donde el ellipsis se lo
  /// comía casi siempre — ese es el bug que este test fija.
  testWidgets('la fila muestra el asunto en su propia línea, no pegado al '
      'último mensaje', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ConversationsScreen(
        leading: const SizedBox(),
        actions: const [SizedBox()],
        loadConversations: () async => [
          {
            'id': 'c1',
            'status': 'abierto',
            'peer_name': 'Ana Pérez',
            'peer_avatar_url': null,
            'product_name': 'Nevera Mabe 11 pies',
            'agreed_price': 18500,
            'agreed_hourly_rate': null,
            'provider_user_id': 'otro-usuario',
            'last_kind': 'text',
            'last_body': 'Buenas, ¿sigue disponible?',
            'last_created_at': '2026-07-28T15:42:00Z',
            'unread_count': 0,
          },
        ],
      ),
    ));
    await tester.pump(); // resuelve el future de loadConversations
    await tester.pump(const Duration(milliseconds: 600)); // cascadeIn

    expect(find.text('Ana Pérez'), findsOneWidget);

    // El asunto se pinta (va en un Text.rich por el precio en violeta).
    expect(find.textContaining('Nevera Mabe 11 pies', findRichText: true),
        findsOneWidget,
        reason: 'el asunto de la conversación no aparece en la fila');

    // LA REGRESIÓN: el último mensaje va SOLO, sin el asunto ni el precio
    // encolados. Un `findsOneWidget` con el texto EXACTO falla si alguien
    // vuelve a concatenarlos.
    expect(find.text('Buenas, ¿sigue disponible?'), findsOneWidget,
        reason: 'el asunto volvió a concatenarse al último mensaje');
  });
}
