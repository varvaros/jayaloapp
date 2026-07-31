import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Acción que se APROPIA del botón central de la barra flotante mientras la
/// pantalla al frente la tenga registrada (pedido PO 2026-07-28).
///
/// El centro de la barra es "＋ / Crear solicitud", pero DENTRO de
/// `/client/create` no hacía nada: `pushCreateRequestOnce`
/// (`core/create_request_nav.dart`) mira la pila VIVA del router para no apilar
/// dos copias de la ventana, así que tocarlo ahí era un no-op. En vez de
/// dejarlo muerto, la pantalla de crear solicitud registra aquí su selector de
/// foto y el botón pasa a ser una CÁMARA mientras esa pantalla vive.
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
void takeCenterAction(VoidCallback action, IconData icon) => _applySafely(() {
      // El ÍCONO primero y la acción al final: quien escucha reacciona a la
      // primera notificación que le llegue, y así cuando llega ya encuentra el
      // par completo en vez de un ícono todavía viejo.
      centerActionIcon.value = icon;
      centerAction.value = action;
    });

/// Aplica un cambio de estado del centro sin chocar con la fase de build.
///
/// ⚠️ POR QUÉ EXISTE ESTO (bug PO 2026-07-30, "el ＋ no se transforma en
/// cámara"): quien toma el botón lo hace desde su `initState`, es decir a
/// mitad de la fase de build del frame. Los notifiers de arriba los lee el
/// `ListenableBuilder` de la barra, que es un ANCESTRO del Navigator anidado
/// donde acaba de nacer esa pantalla — y Flutter prohíbe marcar sucio a un
/// ancestro que YA se construyó en este frame ("setState() or markNeedsBuild()
/// called during build"). El resultado no era un crash visible sino algo peor:
/// la notificación se DESCARTABA, la barra nunca se repintaba y el ícono
/// quedaba en null para siempre.
///
/// Aplazar al final del frame es responsabilidad del STORE y no de cada
/// pantalla: el contrato documentado arriba dice "registrar en `initState`",
/// así que hacer que eso sea seguro tiene que vivir de este lado. Si se dejara
/// en manos de quien lo usa, el próximo que tome el botón repetiría el bug.
///
/// [takeCenterAction] y [releaseCenterAction] pasan LAS DOS por acá para que
/// no se puedan cruzar: los post-frame callbacks corren en orden de encolado,
/// así que un `release` no puede adelantarse a un `take` que quedó pendiente.
/// Por eso, además, la comprobación de identidad del release se hace al
/// APLICAR y no al llamar.
void _applySafely(VoidCallback apply) {
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    binding.addPostFrameCallback((_) => apply());
    return;
  }
  apply();
}

/// Suelta el botón central, pero SOLO si [action] sigue siendo la registrada.
///
/// La comprobación de identidad importa por el orden de ciclo de vida de
/// Flutter: al reemplazar una pantalla, el `initState` de la nueva corre ANTES
/// del `dispose` de la vieja. Un `releaseCenterAction()` incondicional en ese
/// `dispose` borraría la acción que la pantalla nueva acaba de registrar y
/// dejaría el botón muerto otra vez.
void releaseCenterAction(VoidCallback action) => _applySafely(() {
      if (!identical(centerAction.value, action)) return;
      centerAction.value = null;
      centerActionIcon.value = null;
    });
