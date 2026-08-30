import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/share_links.dart';

/// El botón de compartir de la app (pedido PO 2026-08-30). Espeja el de la web
/// (`src/components/ui/ShareButton.tsx`) hasta en dónde se coloca: AL LADO de
/// la acción principal de cada pantalla, no debajo.
///
/// Dos formas, la misma de la web:
///  · [ShareButton] con texto, para cuando va solo.
///  · [ShareIconButton] cuadrado, para cuando comparte fila con un botón
///    grande — así el principal conserva su texto entero y sigue mandando.
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
    // seria mucho peor.
  }
}

class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.texto,
    required this.url,
    this.label = 'Compartir',
  });

  final String texto;
  final String url;
  final String label;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () => compartir(texto, url),
        icon: const Icon(Icons.share_outlined, size: 18),
        label: Text(label),
      );
}

/// Cuadrado, solo el ícono, con el nombre para el lector de pantalla. [alto]
/// se pasa igual al del botón que tiene al lado para que la fila quede pareja.
class ShareIconButton extends StatelessWidget {
  const ShareIconButton({
    super.key,
    required this.texto,
    required this.url,
    this.alto = 48,
  });

  final String texto;
  final String url;
  final double alto;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: alto,
        height: alto,
        child: OutlinedButton(
          onPressed: () => compartir(texto, url),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Tooltip(
            message: 'Compartir',
            child: Semantics(
              button: true,
              label: 'Compartir',
              child: const Icon(Icons.share_outlined, size: 20),
            ),
          ),
        ),
      );
}
