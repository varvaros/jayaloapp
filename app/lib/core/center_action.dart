import 'package:flutter/foundation.dart' show listEquals;
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
/// - una pantalla cuyo estado cambia **dentro de sí misma** sincroniza desde
///   `build` (ver la pantalla de la oferta del proveedor);
/// - solo lo toma la pantalla que está al frente. Si dos lo tomaran, gana la
///   última — por eso [releaseCenterAction] comprueba identidad antes de
///   limpiar, para que el `dispose` de una pantalla que ya perdió el botón no
///   le borre la acción a la que lo tiene ahora.

/// Un destino del menú que despliega el botón central.
///
/// Igualdad **por valor** a propósito: la pantalla que registra el menú lo
/// reconstruye en cada `build` (su `enabled` depende de si está ocupada y de
/// cuántas fotos lleva), y el formulario de la oferta se reconstruye con cada
/// tecla que se escribe en el campo de precio. Sin esta igualdad, cada
/// pulsación repintaría la barra flotante entera.
///
/// `onTap` se compara con `==` y no con `identical`: Dart garantiza que dos
/// tear-offs del mismo método sobre la misma instancia son iguales, pero NO que
/// sean el mismo objeto.
@immutable
class CenterMenuItem {
  const CenterMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.onDisabledTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// `false` = se pinta atenuado y su toque no dispara [onTap]. No se ESCONDE:
  /// un arco que pasa de cuatro satélites a uno se lee como un fallo.
  final bool enabled;

  /// Se dispara al tocar el ítem APAGADO — para avisar POR QUÉ, cuando hay
  /// algo que decir (p. ej. "ya tienes 5 fotos"). `null` = el toque queda
  /// inerte, que sigue siendo el default correcto cuando lo que apaga el
  /// ítem es una operación en curso (`busy`): ahí no hay nada que avisar,
  /// solo esperar.
  final VoidCallback? onDisabledTap;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CenterMenuItem &&
          other.icon == icon &&
          other.label == label &&
          other.onTap == onTap &&
          other.enabled == enabled &&
          other.onDisabledTap == onDisabledTap;

  @override
  int get hashCode =>
      Object.hash(icon, label, onTap, enabled, onDisabledTap);
}

/// `null` = el centro se comporta como siempre (navegar).
final ValueNotifier<VoidCallback?> centerAction = ValueNotifier(null);

/// Ícono a pintar mientras [centerAction] esté tomado. `null` = el del destino.
final ValueNotifier<IconData?> centerActionIcon = ValueNotifier(null);

/// Identidad de quien tomó el botón. Antes ese papel lo hacía el propio
/// `VoidCallback`; con un menú no hay UN callback que sirva de identidad, hay
/// cuatro. Registrar un no-op de mentira solo para tener token sería mentir
/// sobre para qué existe el campo.
final ValueNotifier<Object?> centerActionOwner = ValueNotifier(null);

/// Ruta que tomó el botón. **Sustituye a la constante cableada** que el shell
/// comparaba (`kCreateRequestRoute`), que impedía que ninguna otra pantalla
/// pudiera apropiarse del centro.
final ValueNotifier<String?> centerActionRoute = ValueNotifier(null);

/// Etiqueta bajo el círculo mientras está tomado. Antes vivía a fuego en
/// `home_shell.dart` ('Añadir foto').
final ValueNotifier<String?> centerActionLabel = ValueNotifier(null);

/// Destinos del menú. No-nulo = el centro DESPLIEGA en vez de actuar.
final ValueNotifier<List<CenterMenuItem>?> centerActionMenu = ValueNotifier(null);

/// `false` = el centro está TOMADO pero APAGADO: se pinta atenuado y su toque
/// no dispara nada. Es el mismo concepto de [CenterMenuItem.enabled], para el
/// botón de acción única.
///
/// Existe porque SOLTAR el botón no es lo mismo que apagarlo (bug PO
/// 2026-08-22): al soltarlo, el shell vuelve a pintar su destino por defecto
/// —«＋ Nueva solicitud», encendido— y ese toque, estando ya dentro de crear
/// solicitud, lo come el guard de `pushCreateRequestOnce` sin hacer nada. Un
/// botón encendido que se traga el toque en silencio es peor que uno apagado.
final ValueNotifier<bool> centerActionEnabled = ValueNotifier(true);

/// Toma el botón central.
///
/// Idempotente: volver a llamarlo con lo mismo no notifica a nadie. Los
/// `ValueNotifier` ya comparan por `==`, así que los escalares se guardan
/// solos; la LISTA necesita la comparación explícita porque `List` no tiene
/// igualdad por valor en Dart.
void takeCenterAction({
  required Object owner,
  required IconData icon,
  String? label,
  String? route,
  VoidCallback? action,
  List<CenterMenuItem>? menu,
  bool enabled = true,
}) {
  // `menu: []` (no-nulo pero VACÍO) es un estado ambiguo, no uno útil: la
  // barra lo trata exactamente como `menu: null` (`_CenterButton._toggle`
  // cae a `widget.onTap` con cualquiera de los dos), así que dejar pasar la
  // lista vacía aquí solo escondería, en quien llama, el mismo error de
  // "tomé el botón y no le di nada que hacer" que este assert ya vigila.
  //
  // El invariante que esto protege NO es «tomado ⇒ tiene qué hacer», sino
  // «se pinta ENCENDIDO ⇒ tiene qué hacer». `enabled: false` es esa misma
  // vaciedad, pero declarada y PINTADA: el usuario ve que está apagado, que es
  // justo lo contrario del accidente que el assert vigila.
  assert(!enabled || action != null || (menu != null && menu.isNotEmpty),
      'Un botón ENCENDIDO que no hace nada es justo el estado que esto viene a eliminar.');
  _applySafely(() {
    // Todo lo que el shell LEE se asigna antes que `centerAction`/
    // `centerActionMenu`, que son los que disparan el repintado: así cuando la
    // notificación llega, quien escucha encuentra el juego completo y no un
    // ícono todavía viejo.
    centerActionIcon.value = icon;
    centerActionLabel.value = label;
    centerActionRoute.value = route;
    centerActionOwner.value = owner;
    centerActionEnabled.value = enabled;
    if (!listEquals(centerActionMenu.value, menu)) centerActionMenu.value = menu;
    // Apagado ⇒ SIN acción, aunque quien llame haya pasado una: así el estado
    // «apagado pero con algo colgando» no existe aguas abajo y ningún camino
    // del shell puede dispararla por accidente.
    centerAction.value = enabled ? action : null;
  });
}

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

/// Suelta el botón central, pero SOLO si [owner] sigue siendo el dueño.
///
/// La comprobación de identidad importa por el orden de ciclo de vida de
/// Flutter: al reemplazar una pantalla, el `initState` de la nueva corre ANTES
/// del `dispose` de la vieja. Un release incondicional en ese `dispose`
/// borraría lo que la pantalla nueva acaba de registrar.
void releaseCenterAction(Object owner) => _applySafely(() {
      if (!identical(centerActionOwner.value, owner)) return;
      centerActionOwner.value = null;
      centerAction.value = null;
      centerActionIcon.value = null;
      centerActionLabel.value = null;
      centerActionRoute.value = null;
      centerActionMenu.value = null;
      // ⚠️ SIN ESTA LÍNEA, una pantalla que se va estando APAGADA deja el
      // botón central muerto en TODA la app: el shell solo mira
      // `centerActionEnabled` cuando alguien tiene el botón, pero el default
      // de la barra lo lee igual y nadie lo volvería a encender.
      centerActionEnabled.value = true;
    });
