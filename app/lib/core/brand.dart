/// Paleta de marca de Jayalo.
///
/// EL VIOLETA PRIMARIO (`#7147F2`) es la portada de la web — el relleno exacto
/// del isotipo `isojayalo.svg` — y no se toca: app y web comparten la acción.
///
/// El RESTO del tema CLARO ya NO es el gris frío de la web, sino la paleta
/// cálida "arena" que el PO aprobó para la app (doctrina de los mockups,
/// 2026-07-19: `docs/disenos/2026-07-19-mockups-app.html`, tokens `.warm`):
/// fondo arena, tintas en gris violáceo/violeta oscuro (CERO negro), acento
/// lila, sombra cálida. Es una divergencia deliberada de la web: la app tiene
/// su propia calidez; el violeta de acción es lo único que se mantiene idéntico
/// en las dos superficies.
///
/// OSCURO es VIOLETA (PO 2026-07-23: "debe ser violeta, no usamos azul") — se
/// reemplazó el oscuro "azul viejo" heredado de la web por una paleta violeta
/// (ver tokens `d*` abajo). El toggle de modo oscuro vive en Ajustes.
library;

import 'package:flutter/material.dart';

abstract final class JayaloColors {
  // ── Claro · paleta cálida "arena" (mockups aprobados, tokens `.warm`) ──────
  // Fondo: ARENA cálida (decisión PO 2026-08-10, «usa el mismo color de
  // background del mockup» — deshace el gris frío del 07-20 y vuelve al
  // mockup 07-19). El violeta de acción, las tarjetas blancas y las tintas
  // violáceas de texto no cambian.
  static const background = Color(0xFFF8F4EC); // --bg arena cálida
  static const foreground = Color(0xFF4A4458); // --fg gris violáceo (cuerpo)
  static const head = Color(0xFF3E3560); //       --head violeta oscuro (títulos)
  static const card = Color(0xFFFFFFFF); //       --card
  static const primary = Color(0xFF7147F2); //    --pri (acción, = isotipo)
  static const primaryFg = Color(0xFFFCFCFC);
  static const secondary = Color(0xFFE9ECF1); //  neutro frío (segmentos)
  static const muted = Color(0xFFE9ECF1);
  static const mutedFg = Color(0xFF847D8F); //    --mut
  // Navbar: la píldora es `primaryContainer` (= accent) y sus ítems
  // `onPrimaryContainer` (= accentFg). PO 2026-07-20: el lila se OSCURECIÓ un
  // punto (#F0EAFF → #E2D6FB) para que la barra flotante no se pierda contra el
  // fondo gris frío nuevo. El ícono lateral inactivo sigue cumpliendo WCAG 3:1
  // (el test de contraste en `floating_nav_bar_test.dart` recalcula el ratio
  // REAL desde estos tokens, no un valor fijo). El botón central (+) pasó a
  // `primary` (el violeta del header) — ver `floating_nav_bar.dart`.
  static const accent = Color(0xFFE2D6FB); //     lila de acento (navbar)
  static const accentFg = Color(0xFF3C1590); //   violeta oscuro de acento
  static const destructive = Color(0xFFEA2126);
  static const success = Color(0xFF00A159);
  static const border = Color(0xFFE1E4EA); //     línea fría discreta
  static const input = Color(0xFFEAEDF2); //      relleno de campo frío

  /// Sombra única de las tarjetas que flotan. Enfriada junto con el fondo
  /// (2026-07-20): una sombra cálida marrón sobre el gris frío se veía turbia;
  /// ahora es una sombra pizarra fría al mismo ~9%. La elevación de la app es
  /// SOLO esta sombra: nada de bordes (doctrina "tarjetas sin borde"). El nombre
  /// `warmShadow` se conserva por no tocar sus usos; ya no es cálida.
  static const warmShadow = Color(0x17263143);

  // ── Oscuro · VIOLETA (PO 2026-07-23: "debe ser violeta, no usamos azul") ───
  // Reemplaza el oscuro "azul viejo" heredado de la web. Neutros tintados de
  // VIOLETA (no azul); el primario es el violeta de marca lo bastante oscuro
  // para que el texto BLANCO del header/botones cumpla contraste (≈5:1), y una
  // escala de superficies con las tarjetas ELEVADAS sobre el fondo — antes
  // `surfaceContainerLowest` caía al mismo color del fondo → tarjetas
  // invisibles en oscuro. El contraste no-textual del ícono inactivo de la
  // navbar (`dMutedFg` sobre `dAccent`) queda en ~5.6:1 (test lo verifica).
  static const dBackground = Color(0xFF141020); //  casi negro violáceo (scaffold)
  static const dForeground = Color(0xFFF3F0F8); //  casi blanco con tinte violeta
  static const dCard = Color(0xFF241C38); //         tarjeta elevada (separa del fondo)
  static const dSurfaceLow = Color(0xFF1B1528);
  static const dPrimary = Color(0xFF845EF5); //      VIOLETA de acción (blanco legible)
  static const dPrimaryFg = Color(0xFFFFFFFF); //    texto/íconos sobre el violeta
  static const dSecondary = Color(0xFF2C2444);
  static const dMutedFg = Color(0xFFA79FB8); //      gris violáceo (texto atenuado)
  static const dAccent = Color(0xFF2E2350); //       lila oscuro de la navbar
  static const dDestructive = Color(0xFFF14E46);
  static const dSuccess = Color(0xFF2BBB71);
  static const dSurfaceHighest = Color(0xFF383052); // relleno de campos / más alto
  static const dBorder = Color(0x1AFFFFFF); //       blanco 10%

  /// Violeta del loader/mascota (`JayaloLoader.tsx`). La web lo hornea fijo en
  /// el SVG, sin cambiarlo en oscuro — aquí igual, para que la mascota sea la
  /// misma en los dos temas.
  static const mascot = Color(0xFF6C3BF5);
}

/// Tinta de los títulos fuertes: el violeta oscuro cálido (`--head`) en claro;
/// en oscuro cae al `onSurface` del esquema (el `head` claro sería invisible
/// sobre fondo oscuro). Úsalo para h2/h3/precios; el cuerpo va en `onSurface`.
Color jayaloHead(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.onSurface
        : JayaloColors.head;

/// Par de colores de un "estado" de la web (`--status-*`): fondo teñido + tinta.
typedef StatusTone = ({Color bg, Color ink});

/// Tokens `--status-*` de la web. Las familias de notificación se pintan con
/// estos para que un "mensaje nuevo" tenga el mismo verde que un contacto
/// desbloqueado en la web, etc.
abstract final class JayaloStatus {
  static const pendingLight = (bg: Color(0xFFF9F1E3), ink: Color(0xFF645235));
  static const pendingDark = (bg: Color(0xFF383227), ink: Color(0xFFDFCBAA));

  static const respondedLight = (bg: Color(0xFFEDEBFF), ink: Color(0xFF4B3B94));
  static const respondedDark = (bg: Color(0xFF332D4F), ink: Color(0xFFC8C2FF));

  static const acceptedLight = (bg: Color(0xFFFFE9CB), ink: Color(0xFF8F4700));
  static const acceptedDark = (bg: Color(0xFF432E14), ink: Color(0xFFFFBD8E));

  /// "Oferta aceptada" = AZUL CLARO (pedido PO 2026-07-21: "el color ámbar no
  /// me gusta" para ese estado). El ámbar (`accepted*`) queda SOLO para
  /// contextos de dinero/espera ("Ya ofertaste", costo del unlock, wallet).
  /// Derivado con la misma receta pastel+tinta de los demás status.
  static const offerAcceptedLight =
      (bg: Color(0xFFDBEDFF), ink: Color(0xFF0D4F8B));
  static const offerAcceptedDark =
      (bg: Color(0xFF16293D), ink: Color(0xFF9CCBFF));

  static const unlockedLight = (bg: Color(0xFFD0FAE6), ink: Color(0xFF005D3F));
  static const unlockedDark = (bg: Color(0xFF103627), ink: Color(0xFF8CE3BE));

  static const completedLight = (bg: Color(0xFFEFF2F5), ink: Color(0xFF5F6469));
  static const completedDark = (bg: Color(0xFF2A2E33), ink: Color(0xFFB9BEC4));

  /// La web no tiene token de reseñas; este rosa se derivó con la MISMA
  /// receta oklch de los demás status sobre el rosa del gradiente de marca.
  static const reviewLight = (bg: Color(0xFFFFE4F2), ink: Color(0xFF8D2661));
  static const reviewDark = (bg: Color(0xFF492537), ink: Color(0xFFFFB3D7));

  /// Requisitos que el CLIENTE exige en su solicitud (comprobante fiscal,
  /// suplidor del Estado, envío, instalación, evaluación previa). Teal propio,
  /// y no uno de los tonos de arriba, porque no es un estado de la oferta del
  /// proveedor: es una condición del cliente. El ámbar en esta app ya significa
  /// dinero o espera ("Ya ofertaste", el costo del desbloqueo, la wallet), y
  /// confundir las dos cosas sería peor que no pintar nada.
  ///
  /// Reutilizado también (PO 2026-08-12, sello "Tienda física") para atributos
  /// AUTODECLARADOS por el PROVEEDOR — misma familia semántica que arriba: "lo
  /// dice alguien, nadie lo comprueba". La web usa el MISMO token `--requisito`
  /// para ambos casos (`DeclaredPill`), así que reusarlo aquí es paridad, no
  /// una improvisación. Sigue estando terminantemente prohibido pintar esto
  /// con `JayaloColors.success`/`Icons.verified`: ese verde es EXCLUSIVO de lo
  /// que Jayalo sí verifica.
  ///
  /// Portado del token `--requisito` de la web: `oklch(0.94 0.06 200)` /
  /// `oklch(0.4 0.12 200)` en claro, `oklch(0.3 0.07 200)` /
  /// `oklch(0.87 0.11 200)` en oscuro. La conversión oklch→sRGB se calibró
  /// contra `--status-pending`, que da exactamente el `pendingLight` de arriba.
  static const requisitoLight = (bg: Color(0xFFBCF8FB), ink: Color(0xFF005961));
  static const requisitoDark = (bg: Color(0xFF00383C), ink: Color(0xFF6FEAF1));
}

/// Esquemas M3 con los roles clave clavados a los tokens de la web. Se parte de
/// `fromSeed` para que TODOS los roles queden poblados (Flutter usa muchos que
/// la web no nombra) y se sobrescriben los que sí tienen equivalente.
ColorScheme jayaloScheme(Brightness b) => b == Brightness.light
    ? ColorScheme.fromSeed(
        seedColor: JayaloColors.primary,
      ).copyWith(
        primary: JayaloColors.primary,
        onPrimary: JayaloColors.primaryFg,
        primaryContainer: JayaloColors.accent,
        onPrimaryContainer: JayaloColors.accentFg,
        secondaryContainer: JayaloColors.secondary,
        onSecondaryContainer: JayaloColors.foreground,
        surface: JayaloColors.background,
        onSurface: JayaloColors.foreground,
        onSurfaceVariant: JayaloColors.mutedFg,
        surfaceContainerLowest: JayaloColors.card,
        surfaceContainerLow: JayaloColors.background,
        surfaceContainer: JayaloColors.secondary,
        surfaceContainerHigh: JayaloColors.muted,
        surfaceContainerHighest: JayaloColors.input,
        outline: JayaloColors.mutedFg,
        outlineVariant: JayaloColors.border,
        error: JayaloColors.destructive,
        onError: Colors.white,
      )
    : ColorScheme.fromSeed(
        seedColor: JayaloColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: JayaloColors.dPrimary,
        onPrimary: JayaloColors.dPrimaryFg,
        primaryContainer: JayaloColors.dAccent,
        onPrimaryContainer: JayaloColors.dForeground,
        secondaryContainer: JayaloColors.dSecondary,
        onSecondaryContainer: JayaloColors.dForeground,
        surface: JayaloColors.dBackground,
        onSurface: JayaloColors.dForeground,
        onSurfaceVariant: JayaloColors.dMutedFg,
        // `surfaceContainerLowest` es EL color de tarjeta del proyecto (en claro
        // es el blanco elevado). En oscuro debe ser una superficie ELEVADA
        // (dCard), no el fondo — antes caía a `dBackground` y las tarjetas se
        // volvían invisibles sobre el scaffold.
        surfaceContainerLowest: JayaloColors.dCard,
        surfaceContainerLow: JayaloColors.dSurfaceLow,
        surfaceContainer: JayaloColors.dSecondary,
        surfaceContainerHigh: JayaloColors.dSecondary,
        surfaceContainerHighest: JayaloColors.dSurfaceHighest,
        outline: JayaloColors.dMutedFg,
        outlineVariant: JayaloColors.dBorder,
        error: JayaloColors.dDestructive,
        onError: Colors.white,
      );
