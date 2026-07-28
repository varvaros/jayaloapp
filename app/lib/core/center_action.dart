import 'package:flutter/widgets.dart';

/// Acción que se APROPIA del botón central de la barra flotante mientras la
/// pantalla al frente la tenga registrada (pedido PO 2026-07-28).
///
/// El centro de la barra es "＋ / Crear solicitud", pero DENTRO de
/// `/client/create` no hacía nada: `home_shell` tiene una guarda
/// (`if (loc != d.route)`) para no apilar dos copias de la ventana, así que
/// tocarlo ahí era un no-op. En vez de dejarlo muerto, la pantalla de crear
/// solicitud registra aquí su selector de foto y el botón pasa a ser una
/// CÁMARA mientras esa pantalla vive.
///
/// Vive en `core/` y no en `data/repos.dart` (donde están los badges) porque es
/// estado de la CÁSCARA, no un dato del backend: meterlo ahí obligaría a
/// importar `widgets.dart` en la capa de datos solo para poder nombrar un
/// [IconData].
///
/// Contrato para quien lo tome:
/// - registrar en `initState` (o cuando la pantalla pasa al frente) y
///   **limpiar siempre en `dispose`** con [releaseCenterAction];
/// - solo lo toma la pantalla que está al frente. Si dos lo tomaran, gana la
///   última — por eso [releaseCenterAction] comprueba identidad antes de
///   limpiar, para que el `dispose` de una pantalla que ya perdió el botón no
///   le borre la acción a la que lo tiene ahora.
///
/// `null` = el centro se comporta como siempre (navegar).
final ValueNotifier<VoidCallback?> centerAction = ValueNotifier(null);

/// Ícono a pintar mientras [centerAction] esté tomado. `null` = el del destino.
final ValueNotifier<IconData?> centerActionIcon = ValueNotifier(null);

/// Toma el botón central. Idempotente: volver a llamarlo con lo mismo no
/// notifica a nadie (los `ValueNotifier` ya comparan por igualdad).
void takeCenterAction(VoidCallback action, IconData icon) {
  centerAction.value = action;
  centerActionIcon.value = icon;
}

/// Suelta el botón central, pero SOLO si [action] sigue siendo la registrada.
///
/// La comprobación de identidad importa por el orden de ciclo de vida de
/// Flutter: al reemplazar una pantalla, el `initState` de la nueva corre ANTES
/// del `dispose` de la vieja. Un `releaseCenterAction()` incondicional en ese
/// `dispose` borraría la acción que la pantalla nueva acaba de registrar y
/// dejaría el botón muerto otra vez.
void releaseCenterAction(VoidCallback action) {
  if (!identical(centerAction.value, action)) return;
  centerAction.value = null;
  centerActionIcon.value = null;
}
