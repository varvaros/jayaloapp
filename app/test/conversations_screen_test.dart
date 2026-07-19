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
/// No hace falta montar el widget para probar esto: `actions` es un campo
/// inyectable (mismo patrón que `CatalogView`/`ProviderInboxView`, ver
/// `catalog_screen_test.dart`) precisamente para no tener que instanciar
/// `NotificationBell`/`ProfileAvatarButton` de verdad en un test — ambos
/// tocan Supabase en su constructor/`initState` y esta app no inicializa
/// Supabase en los tests de widgets. Basta con leer el valor por defecto.
void main() {
  test(
      'Mensajes expone campana y avatar por defecto, como las demás 7 '
      'pestañas raíz', () {
    const screen = ConversationsScreen();
    expect(screen.actions.whereType<NotificationBell>().length, 1,
        reason: 'sin la campana, Mensajes queda sin vía a Notificaciones');
    expect(screen.actions.whereType<ProfileAvatarButton>().length, 1,
        reason: 'sin el avatar, Mensajes queda sin vía a Ajustes/Estadísticas');
  });
}
