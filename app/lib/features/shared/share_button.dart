import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/brand.dart';
import '../../domain/share_links.dart';
import 'brand_kit.dart';

/// Abre la hoja de compartir del sistema con [content].
///
/// [origin] es el rectángulo del botón en coordenadas de pantalla: en iPad la
/// hoja es un popover y necesita saber de dónde sale. En Android no se usa,
/// pero se manda igual — cuesta cero y deja la puerta abierta a iOS.
///
/// Best-effort: si la hoja falla (no hay nada con qué compartir, el usuario
/// cancela con un error del sistema), se avisa con el toast de la app en vez
/// de reventar la pantalla.
Future<void> shareContent(BuildContext context, ShareContent content) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    await SharePlus.instance.share(
      ShareParams(text: content.text, sharePositionOrigin: origin),
    );
  } catch (_) {
    if (context.mounted) {
      showJayaloToast(context, 'No se pudo abrir el menú de compartir.');
    }
  }
}

/// Botón circular de compartir para las cabeceras de foto: mismo tamaño, color
/// y elevación que el botón de atrás que ya vive enfrente, para que la barra
/// quede simétrica.
///
/// Recibe un [ShareContent] ya construido y **se dibuja solo si no es null**:
/// las pantallas cuyo contenido no tiene página pública en jayalo.com (una
/// oferta, un interés de producto) simplemente no lo pasan, y no hay botón que
/// prometa un enlace que no existe.
class ShareFab extends StatelessWidget {
  const ShareFab({super.key, required this.content, this.tooltip = 'Compartir'});

  final ShareContent content;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          elevation: 1,
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              onTap: () => shareContent(context, content),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(Icons.ios_share,
                    size: 19, color: jayaloHead(context)),
              ),
            ),
          ),
        ),
      );
}

/// Compartir dentro de una `AppBar` normal (las pantallas que NO tienen
/// cabecera de foto): el icono pelado que espera `AppBar.actions`, no el
/// círculo elevado de [ShareFab], que ahí quedaría como un parche.
class ShareIconButton extends StatelessWidget {
  const ShareIconButton({super.key, required this.content});

  final ShareContent content;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Compartir',
        icon: const Icon(Icons.ios_share),
        onPressed: () => shareContent(context, content),
      );
}
