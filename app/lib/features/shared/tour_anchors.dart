import 'package:flutter/widgets.dart';

/// Anclas COMPARTIDAS para los recorridos de primera vez: elementos que viven
/// en el shell (el botón `+`, los ítems de la barra flotante) o en el
/// encabezado (la monedita del saldo) y que una guía declarada DENTRO de una
/// pantalla necesita señalar. Las anclas propias de cada pantalla (buscador,
/// píldoras, primera tarjeta, segmentados) van como `GlobalKey` del `State`
/// de esa pantalla, no aquí.
///
/// Invariante: cada key vive en UN solo widget montado a la vez. Hoy se
/// cumple porque solo hay un `HomeShell` vivo (las rutas raíz se sustituyen,
/// no se apilan) y `HeaderSaldo` solo se pinta en las pantallas del proveedor.
abstract final class TourAnchors {
  /// Botón central `+` de la barra flotante (`FloatingNavBar.centerButtonKey`).
  static final GlobalKey plus = GlobalKey(debugLabel: 'tour.plus');

  /// Contador de créditos del encabezado (`HeaderSaldo`). Es `const` porque va
  /// en el valor por defecto de un parámetro (`ProviderInboxView.actions`), y
  /// Dart exige que esos valores sean constantes.
  static const GlobalObjectKey saldo = GlobalObjectKey(#jayaloTourSaldo);

  static final Map<String, GlobalKey> _nav = {};

  /// Ítem lateral de la barra flotante, por `route` del destino.
  static GlobalKey nav(String route) =>
      _nav.putIfAbsent(route, () => GlobalKey(debugLabel: 'tour.nav.$route'));
}
