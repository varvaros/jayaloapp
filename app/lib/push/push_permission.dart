import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/session_state.dart';

/// ¿Toca ya pedir el permiso de notificaciones de Android 13+?
///
/// Solo con un rol RESUELTO, o sea cuando el usuario ya está DENTRO de la app
/// (`/client` o `/provider`). Antes de eso el diálogo del sistema no tiene
/// nada que ofrecer —sin cuenta no hay chats ni ofertas que avisar— y sí tiene
/// mucho que romper:
///
/// - Tapaba los recuadros «Busco algo / Vendo algo» de la primera apertura, y
///   desde 2026-08-20 esa apertura es la ÚNICA en la vida del teléfono
///   ([IntroSeenStore]): perdérsela ya no se arregla volviendo a abrir la app.
/// - Con el gotcha de MIUI (los toques atraviesan los overlays), un toque en
///   «No permitir» podía además elegir lado por debajo sin que el usuario se
///   enterara.
///
/// Pedirlo al llegar a la app es también lo que recomienda Android: en
/// contexto, no a bocajarro en el arranque en frío.
///
/// Pura para poder fijarla en un test sin Firebase.
bool shouldAskPushPermission(RoleState role) =>
    role == RoleState.consumer || role == RoleState.provider;

/// Deja el permiso pedido en el PRIMER instante en que [role] devuelva un rol
/// resuelto, y ni uno más: [ask] corre como mucho una vez por proceso.
///
/// [source]/[role] y [ask] se inyectan para poder probar el cableado sin
/// Firebase ni `roleStore` global. Devuelve la función que desengancha.
VoidCallback wirePushPermissionPrompt({
  required Listenable source,
  required RoleState Function() role,
  required Future<void> Function() ask,
}) {
  var asked = false;
  var detached = false;
  late final VoidCallback onChange;

  void detach() {
    if (detached) return;
    detached = true;
    source.removeListener(onChange);
  }

  onChange = () {
    if (asked || !shouldAskPushPermission(role())) return;
    asked = true;
    // Desenganchar ANTES de pedir: `ask()` puede tardar lo que el usuario
    // tarde en decidir, y en ese rato el rol puede notificar otra vez.
    detach();
    unawaited(
      ask().catchError(
        (Object e) => debugPrint('requestPermission falló: $e'),
      ),
    );
  };

  source.addListener(onChange);
  // Arranque en caliente: el rol podría estar resuelto ya al cablear.
  onChange();
  return detach;
}
