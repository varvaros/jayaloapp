import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/conversations_screen.dart';
import 'package:jayalo_app/features/shared/swipe_to_actions.dart';
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

  Map<String, dynamic> conv(String id,
          {String status = 'abierto', bool archived = false}) =>
      {
        'id': id,
        'status': status,
        'archived': archived,
        'customer_id': 'me',
        'provider_user_id': 'peer',
        'peer_name': 'Peer $id',
        'product_name': 'Asunto $id',
        'unread_count': 0,
        'last_kind': 'text',
        'last_body': 'hola',
        'last_created_at': '2026-07-31T10:00:00Z',
        'updated_at': '2026-07-31T10:00:00Z',
      };

  Future<void> mount(
          WidgetTester tester, List<Map<String, dynamic>> rows) async {
    await tester.pumpWidget(MaterialApp(
      home: ConversationsScreen(
        leading: const SizedBox(),
        actions: const [SizedBox()],
        loadConversations: () async => rows,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('la píldora Archivados NO aparece sin conversaciones archivadas',
      (tester) async {
    await mount(tester, [conv('a')]);
    expect(find.textContaining('Archivados'), findsNothing);
  });

  // El vacío de Mensajes trae al Jayi con su celular (mockup aprobado PO
  // 08-10, burbujas verdes), no la mascota genérica de EmptyState. El gate
  // de FLUTTER_TEST deja el painter en frame fijo — sin él, el bucle
  // infinito colgaría cualquier pumpAndSettle de esta pantalla.
  testWidgets('el vacío pinta al Jayi con celular, no la mascota genérica',
      (tester) async {
    await mount(tester, []);
    expect(find.textContaining('Sin conversaciones abiertas'), findsOneWidget);
    expect(find.byKey(const ValueKey('jayi_celular')), findsOneWidget);
  });

  testWidgets('la píldora Archivados aparece con al menos una', (tester) async {
    await mount(tester, [conv('a'), conv('b', archived: true)]);
    expect(find.textContaining('Archivados'), findsOneWidget);
  });

  testWidgets('las archivadas NO salen en la pestaña Abierto', (tester) async {
    await mount(tester, [conv('a'), conv('b', archived: true)]);
    expect(find.text('Peer a'), findsOneWidget);
    expect(find.text('Peer b'), findsNothing,
        reason: 'archivar oculta de la bandeja');
  });

  testWidgets('las archivadas no cuentan en la píldora de su estado',
      (tester) async {
    await mount(tester, [conv('a'), conv('b', archived: true)]);
    expect(find.text('Abierto 1'), findsOneWidget,
        reason: 'el conteo debe excluir las archivadas');
  });

  /// Se conserva el finder acotado aunque los literales ya no colisionen: la
  /// píldora del filtro vive SIEMPRE en pantalla y acotar al `SwipeToActions`
  /// deja el test inmune a que alguien vuelva a acercar los dos textos.
  Finder swipeText(String label) => find.descendant(
      of: find.byType(SwipeToActions), matching: find.text(label));

  /// La píldora del filtro dice "No concretado" (nombre del ESTADO) y la franja
  /// del swipe decía el mismo literal exacto (nombre de la ACCIÓN). La
  /// ambigüedad era tal que este fichero tuvo que introducir `swipeText` para
  /// poder distinguirlos; si el test necesita desambiguar, el usuario también.
  /// La franja pasó a "Marcar no concretado" (revisión final, 2026-08-01).
  testWidgets('la franja del swipe NO usa el mismo literal que la píldora del '
      'filtro', (tester) async {
    await mount(tester, [conv('a')]);
    await tester.drag(find.text('Peer a'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(swipeText('No concretado'), findsNothing,
        reason: 'la franja debe nombrar la ACCIÓN, no el estado');
    expect(swipeText('Marcar no concretado'), findsOneWidget);
    // Y sin acotar, cada literal apunta a un solo sitio: la ambigüedad se fue.
    expect(find.text('Marcar no concretado'), findsOneWidget);
  });

  testWidgets('deslizar una conversación abierta revela Marcar no concretado y '
      'Archivar', (tester) async {
    await mount(tester, [conv('a')]);
    await tester.drag(find.text('Peer a'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(swipeText('Marcar no concretado'), findsOneWidget);
    expect(swipeText('Archivar'), findsOneWidget);
  });

  testWidgets('en la pestaña Archivados la acción es Desarchivar',
      (tester) async {
    await mount(tester, [conv('b', archived: true)]);
    await tester.tap(find.textContaining('Archivados'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Peer b'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(swipeText('Desarchivar'), findsOneWidget);
    expect(swipeText('Marcar no concretado'), findsNothing);
  });

  testWidgets('Marcar no concretado pide confirmación y cancelar no hace nada',
      (tester) async {
    await mount(tester, [conv('a')]);
    await tester.drag(find.text('Peer a'), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.tap(swipeText('Marcar no concretado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no se puede reabrir'), findsOneWidget,
        reason: 'marcar perdido es irreversible: hay que decirlo');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Peer a'), findsOneWidget);
  });

  /// Punto 6 del brief: el fallo lógico en el cálculo original de `_body` —
  /// corregía el ÍNDICE de la píldora (`safeIndex`) para que no se saliera de
  /// rango cuando la pestaña Archivados desaparece, pero dejaba el ESTADO
  /// `_tab` clavado en 'archivados'. Resultado: la píldora se pintaría como
  /// "Abierto" mientras el contenido seguía filtrando por archivados — lista
  /// vacía con una píldora que miente.
  ///
  /// Se reproduce sin depender de Supabase (los widget-tests no lo
  /// inicializan): se está viendo la pestaña Archivados cuando, por una
  /// recarga (`loadConversations` inyectable + pull-to-refresh real vía
  /// `JayaloRefresh`/`RefreshIndicator`), el servidor deja de reportar
  /// conversaciones archivadas. `_tab` queda en 'archivados' (nadie tocó la
  /// píldora), así que esto ejercita exactamente la rama que `effectiveTab`
  /// tiene que resolver sin un `setState` en `build`.
  testWidgets(
      'si la recarga deja sin archivadas estando en esa pestaña, cae a '
      'Abierto de verdad (contenido y píldora), no una Archivados vacía',
      (tester) async {
    var archivedGone = false;
    await tester.pumpWidget(MaterialApp(
      home: ConversationsScreen(
        leading: const SizedBox(),
        actions: const [SizedBox()],
        loadConversations: () async =>
            archivedGone ? [conv('a')] : [conv('a'), conv('b', archived: true)],
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.textContaining('Archivados'));
    await tester.pumpAndSettle();
    expect(find.text('Peer b'), findsOneWidget);

    // La próxima recarga (pull-to-refresh real) ya no trae archivadas.
    archivedGone = true;
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // La píldora Archivados desapareció (ya no hay nada que mostrar en ella)
    // y el contenido visible es el de Abierto, no una lista vacía.
    expect(find.textContaining('Archivados'), findsNothing);
    expect(find.text('Peer a'), findsOneWidget);
    expect(find.text('Abierto 1'), findsOneWidget);
  });
}
