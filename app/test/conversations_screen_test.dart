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
}
