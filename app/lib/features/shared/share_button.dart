import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/share_links.dart';

/// El botón de compartir de la app (pedido PO 2026-08-30).
///
/// 🔴 **UNA sola forma y UN solo sitio, en todas las pantallas** (PO
/// 2026-08-30): un botón redondo arriba, sobre la foto, al otro extremo del
/// atrás. Antes cada pantalla lo ponía donde le cuadraba —al lado de la acción
/// en unas, en la barra de la foto en otras— y no había forma de aprender dónde
/// buscarlo. Si mañana hace falta otra variante, se añade AQUÍ y se razona;
/// pintarla suelta en una pantalla es cómo se llegó al desorden anterior.
///
/// Aquí NO hay respaldo al portapapeles: la hoja nativa de Android/iOS existe
/// siempre. Y no se avisa de nada al volver — cerrar la hoja sin elegir destino
/// es una decisión del usuario, no un fallo (misma regla que en la web).
Future<void> compartir(String texto, String url) async {
  try {
    await SharePlus.instance.share(
      ShareParams(text: ShareLinks.mensaje(texto, url), subject: texto),
    );
  } catch (_) {
    // Sin hoja de compartir (ROM rara, o el usuario la cerró de golpe) el
    // remedio es volver a tocar. Reventar la pantalla por un botón secundario
    // sería mucho peor.
  }
}

/// El botón redondo de la barra de la foto. Copia EXACTA del atrás
/// (`productBackButton`) en color, forma, tamaño y elevación: las dos esquinas
/// tienen que leerse como la misma familia.
///
/// Va en el `actions` de [CollapsingPhotoPanel], así que sigue tocable con el
/// panel plegado — igual que el atrás, y por el mismo motivo.
class SharePhotoAction extends StatelessWidget {
  const SharePhotoAction({
    super.key,
    required this.texto,
    required this.url,
  });

  final String texto;
  final String url;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          // Aire contra el borde derecho, el mismo que el atrás tiene contra el
          // izquierdo por el padding del `leading` de la barra.
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            elevation: 1,
            child: Tooltip(
              message: 'Compartir',
              child: InkWell(
                onTap: () => compartir(texto, url),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Semantics(
                    button: true,
                    label: 'Compartir',
                    child: Icon(
                      Icons.share_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
