import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/chat/conversations_screen.dart';
import 'package:jayalo_app/features/notifications/notification_bell.dart';
import 'package:jayalo_app/features/shared/profile_avatar_button.dart';

/// I1 (revisión final de rama): Mensajes es el puesto 3 en ambas barras
/// (spec navbar-iteración 2) pero era la ÚNICA pestaña raíz que se había
/// quedado sin campana ni avatar. Antes era cosmético; esta iteración sacó
/// Ajustes (ambos roles) y Estadísticas (proveedor) de la barra flotante,
/// dejando el avatar del AppBar como ÚNICA puerta a esas pantallas — un
/// usuario parado en Mensajes no tenía ninguna vía a Ajustes sin cambiar de
/// pestaña primero (la invariante que declara el docstring de
/// `profile_avatar_button.dart`).
///
/// H2 (revisión final de rama, iteración 2 de la barra): la versión anterior
/// de este test SOLO leía `const ConversationsScreen().actions` y comparaba
/// el valor por defecto, SIN montar el widget — si alguien conservara el
/// campo pero dejara de pasarlo al `AppBar` de verdad, el test seguía verde
/// y el hallazgo I1 volvía sin avisar. Se corrige con DOS pruebas
/// complementarias: (1) el valor por defecto sigue siendo el esperado
/// (barato, sin montar nada) y (2) esas acciones — inyectadas — SÍ aparecen
/// dentro del `AppBar` real al montar la pantalla, que es lo único que de
/// verdad descarta la regresión I1.
///
/// (2) inyecta marcadores en vez de usar el default: `NotificationBell` crea
/// el singleton `notifCountStore` en su `initState`, que toca
/// `Supabase.instance` SIN atrapar el error (a diferencia de `_load()` de
/// esta pantalla o de `ProfileStore.refresh()`, que sí son "best-effort") —
/// revienta si Supabase no está inicializado, que es el caso en los tests de
/// widgets de este proyecto. `actions` es inyectable precisamente para poder
/// probar el contrato del `AppBar` sin necesitar esos dos widgets reales
/// (mismo patrón que `CatalogView`/`ProviderInboxView`).
void main() {
  test('por defecto expone NotificationBell y ProfileAvatarButton, como '
      'las demás 7 pestañas raíz', () {
    const screen = ConversationsScreen();
    expect(screen.actions.whereType<NotificationBell>().length, 1,
        reason: 'sin la campana, Mensajes queda sin vía a Notificaciones');
    expect(screen.actions.whereType<ProfileAvatarButton>().length, 1,
        reason: 'sin el avatar, Mensajes queda sin vía a Ajustes/Estadísticas');
  });

  testWidgets(
      'las acciones SÍ llegan al AppBar real al montar la pantalla (I1: si '
      'alguien deja de pasarlas al AppBar, este test debe fallar)',
      (tester) async {
    const marcador1 = ValueKey('accion-1');
    const marcador2 = ValueKey('accion-2');
    await tester.pumpWidget(const MaterialApp(
      home: ConversationsScreen(
        actions: [SizedBox(key: marcador1), SizedBox(key: marcador2)],
      ),
    ));
    // No `pumpAndSettle()`: el `_load()` de la pantalla es best-effort (sin
    // Supabase en los tests de widgets, cae a `_error = true`), pero eso no
    // impide que el primer frame ya tenga el `AppBar` armado.
    await tester.pump();

    final appBar = find.byType(AppBar);
    expect(appBar, findsOneWidget);
    expect(find.descendant(of: appBar, matching: find.byKey(marcador1)),
        findsOneWidget,
        reason: 'la primera acción inyectada no llegó al AppBar real');
    expect(find.descendant(of: appBar, matching: find.byKey(marcador2)),
        findsOneWidget,
        reason: 'la segunda acción inyectada no llegó al AppBar real');
  });
}
