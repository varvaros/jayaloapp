/// Paleta de marca de Jayalo — PORTADA DE LA WEB, no inventada aquí.
///
/// Los valores salen de `src/styles.css` de jayalo-main (`:root` y `.dark`),
/// convertidos de oklch a sRGB. Si la web cambia un token, se cambia aquí
/// también: son la misma marca. El violeta primario (`#7147F2`) es exactamente
/// el relleno del isotipo `isojayalo.svg`.
///
/// OJO: en oscuro la web NO usa violeta como primario, se va a un azul
/// (`#3E98FF`). Se respeta tal cual para que app y web se vean igual.
library;

import 'package:flutter/material.dart';

abstract final class JayaloColors {
  // ── Claro ────────────────────────────────────────────────────────────────
  static const background = Color(0xFFF9FAFC);
  static const foreground = Color(0xFF0E1624);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF7147F2);
  static const primaryFg = Color(0xFFFCFCFC);
  static const secondary = Color(0xFFF2F5FB);
  static const muted = Color(0xFFF1F4F7);
  static const mutedFg = Color(0xFF5D646F);
  static const accent = Color(0xFFF0EAFF);
  static const accentFg = Color(0xFF3C1590);
  static const destructive = Color(0xFFEA2126);
  static const success = Color(0xFF00A159);
  static const border = Color(0xFFE1E5EA);
  static const input = Color(0xFFE8EBF1);

  // ── Oscuro ───────────────────────────────────────────────────────────────
  static const dBackground = Color(0xFF080D16);
  static const dForeground = Color(0xFFF3F5F8);
  static const dCard = Color(0xFF121824);
  static const dSurfaceLow = Color(0xFF0D131C);
  static const dPrimary = Color(0xFF3E98FF);
  static const dPrimaryFg = Color(0xFF080D16);
  static const dSecondary = Color(0xFF1E242E);
  static const dMutedFg = Color(0xFF9EA5AE);
  static const dAccent = Color(0xFF142C55);
  static const dDestructive = Color(0xFFF14E46);
  static const dSuccess = Color(0xFF2BBB71);
  static const dSurfaceHighest = Color(0xFF282E38);
  static const dBorder = Color(0x1AFFFFFF); // blanco 10%, como la web

  /// Violeta del loader/mascota (`JayaloLoader.tsx`). La web lo hornea fijo en
  /// el SVG, sin cambiarlo en oscuro — aquí igual, para que la mascota sea la
  /// misma en los dos temas.
  static const mascot = Color(0xFF6C3BF5);
}

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

  static const unlockedLight = (bg: Color(0xFFD0FAE6), ink: Color(0xFF005D3F));
  static const unlockedDark = (bg: Color(0xFF103627), ink: Color(0xFF8CE3BE));

  static const completedLight = (bg: Color(0xFFEFF2F5), ink: Color(0xFF5F6469));
  static const completedDark = (bg: Color(0xFF2A2E33), ink: Color(0xFFB9BEC4));

  /// La web no tiene token de reseñas; este rosa se derivó con la MISMA
  /// receta oklch de los demás status sobre el rosa del gradiente de marca.
  static const reviewLight = (bg: Color(0xFFFFE4F2), ink: Color(0xFF8D2661));
  static const reviewDark = (bg: Color(0xFF492537), ink: Color(0xFFFFB3D7));
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
        surfaceContainerLowest: JayaloColors.dBackground,
        surfaceContainerLow: JayaloColors.dSurfaceLow,
        surfaceContainer: JayaloColors.dCard,
        surfaceContainerHigh: JayaloColors.dSecondary,
        surfaceContainerHighest: JayaloColors.dSurfaceHighest,
        outline: JayaloColors.dMutedFg,
        outlineVariant: JayaloColors.dBorder,
        error: JayaloColors.dDestructive,
        onError: Colors.white,
      );
