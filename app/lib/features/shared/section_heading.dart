import 'package:flutter/material.dart';

/// Rótulo de sección en versalita discreta. Nació privado en el detalle de
/// solicitud del proveedor (T4, 2026-08-01) y sube aquí al aparecer el segundo
/// consumidor: el detalle del lado del cliente. Mismo criterio que se siguió
/// con `CollapsingPhotoPanel`.
Widget sectionHeading(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 2),
      child: Text(t.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
    );
