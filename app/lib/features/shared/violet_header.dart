/// El header violeta — la firma de marca de la app (doctrina de los mockups
/// 2026-07-19): las pantallas principales abren con un bloque violeta de
/// esquinas inferiores redondeadas que envuelve el buscador y la campana.
///
/// Se usa como PRIMER hijo de un `Column`, con el cuerpo scrollable en un
/// `Expanded` debajo — el header queda fijo y la lista corre por debajo de la
/// barra flotante. Pinta violeta detrás de la barra de estado (usa el inset
/// superior real) y NO lleva borde: la única pantalla sin este header es el
/// detalle de solicitud (panel ámbar con la foto grande).
library;

import 'package:flutter/material.dart';
import 'network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion.dart';
import '../../domain/notifications.dart' show badgeLabel;
import '../notifications/notification_bell.dart' show notifCountStore;
import 'moneda.dart';
import 'profile_avatar_button.dart';
import 'saldo_store.dart';

/// Alineación del título dentro del header.
enum HeaderTitleAlign { start, center, end }

class VioletHeader extends StatelessWidget {
  const VioletHeader({
    super.key,
    this.leading,
    this.title,
    this.titleAlign = HeaderTitleAlign.start,
    this.subtitle,
    this.onTitleTap,
    this.actions = const [],
    this.greeting,
    this.below,
    this.bottomRadius = 30,
    this.titleTrailing,
  });

  /// Ranura izquierda: avatar, botón de atrás, o nada (se rellena con un hueco
  /// del ancho de una acción para que el título centrado quede simétrico).
  final Widget? leading;
  final String? title;
  final HeaderTitleAlign titleAlign;

  /// Subtítulo bajo el título (contexto del pedido en el chat).
  final String? subtitle;

  /// Slot opcional pegado al título (p. ej. un sello de verificación). `null`
  /// por defecto: sin este parámetro la cabecera se pinta EXACTAMENTE como
  /// antes — cero cambios visuales para el resto de pantallas. Cuando viene,
  /// se pinta en un `Row` con `mainAxisSize: MainAxisSize.min` junto al texto
  /// del título (nunca junto al subtítulo, que sigue debajo sin tocar) para
  /// que el título siga truncando con ellipsis y el bloque completo se siga
  /// centrando bien.
  final Widget? titleTrailing;

  /// Si se pasa, el bloque de título+subtítulo es tocable (chat: abre el
  /// detalle del acuerdo).
  final VoidCallback? onTitleTap;
  final List<Widget> actions;

  /// Bloque de saludo grande (home): "Hola, Andreína" + línea de apoyo.
  final Widget? greeting;

  /// Contenido bajo la fila principal: buscador o segmentos.
  final Widget? below;

  /// Las esquinas inferiores. El chat lo pone en 0 (el panel lila calza justo
  /// debajo, sin redondeo intermedio).
  final double bottomRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    final balanced = titleAlign == HeaderTitleAlign.center &&
        (leading == null || actions.isEmpty);

    Widget titleWidget() {
      Widget t = Text(
        title!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: switch (titleAlign) {
          HeaderTitleAlign.start => TextAlign.start,
          HeaderTitleAlign.center => TextAlign.center,
          HeaderTitleAlign.end => TextAlign.end,
        },
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
      );
      // `Flexible` (no `Expanded`) para que el Row se achique a su contenido
      // real (mainAxisSize.min) — así el bloque título+sello se sigue
      // centrando como una unidad, y el texto sigue truncando porque el Row
      // igual le pasa un ancho máximo acotado.
      if (titleTrailing != null) {
        t = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: t),
            const SizedBox(width: 6),
            titleTrailing!,
          ],
        );
      }
      if (subtitle == null) return t;
      return Column(
        crossAxisAlignment: titleAlign == HeaderTitleAlign.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          t,
          const SizedBox(height: 1),
          Text(subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: titleAlign == HeaderTitleAlign.center
                  ? TextAlign.center
                  : TextAlign.start,
              style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: .82))),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    if (leading != null)
                      leading!
                    else if (balanced)
                      const SizedBox(width: 42),
                    if (title != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Align(
                          alignment: switch (titleAlign) {
                            HeaderTitleAlign.start => Alignment.centerLeft,
                            HeaderTitleAlign.center => Alignment.center,
                            HeaderTitleAlign.end => Alignment.centerRight,
                          },
                          child: onTitleTap == null
                              ? titleWidget()
                              : GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onTitleTap,
                                  child: titleWidget(),
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const Spacer(),
                    ...actions,
                    if (balanced && leading != null && actions.isEmpty)
                      const SizedBox(width: 42),
                  ],
                ),
              ),
              ?greeting,
              if (below != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: below!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header violeta que se PLIEGA COMPLETO al navegar la lista (pedido PO
/// 2026-07-21: "se debe esconder todo, hasta la notificación y el avatar,
/// desde el primer swipe — así se ve todo más limpio"). Escondido queda solo
/// una franja violeta fina con la flecha para bajarlo de vuelta. Se usa en
/// Tus solicitudes y en el Catálogo.
class CollapsibleHeader extends StatefulWidget {
  const CollapsibleHeader({
    super.key,
    required this.hidden,
    required this.onReveal,
    required this.child,
  });

  final bool hidden;
  final VoidCallback onReveal;

  /// El [VioletHeader] completo de la pantalla.
  final Widget child;

  @override
  State<CollapsibleHeader> createState() => _CollapsibleHeaderState();
}

class _CollapsibleHeaderState extends State<CollapsibleHeader>
    with SingleTickerProviderStateMixin {
  // value 1 = mostrado, 0 = oculto.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.hidden ? 0 : 1,
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void didUpdateWidget(CollapsibleHeader old) {
    super.didUpdateWidget(old);
    if (widget.hidden != old.hidden) {
      widget.hidden ? _c.reverse() : _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;
    final collapsed = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onReveal,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
        padding: EdgeInsets.only(top: topInset + 2, bottom: 5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .20),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 22),
          ),
        ),
      ),
    );
    // El header SE DESLIZA HACIA ARRIBA y se esconde (pedido PO 2026-07-22: la
    // versión con AnimatedCrossFade parecía un fade). `Align(bottomCenter,
    // heightFactor: t)` ancla el header abajo y recorta desde ARRIBA: al
    // encogerse (t→0) el header sube tras el borde superior. Detrás queda la
    // franja con la flecha, que aparece al plegarse.
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value.clamp(0.0, 1.0);
        return Stack(alignment: Alignment.topCenter, children: [
          if (t < .999)
            Opacity(opacity: (1 - t), child: collapsed),
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: t,
              child: IgnorePointer(ignoring: t < .5, child: widget.child),
            ),
          ),
        ]);
      },
    );
  }
}

/// Saludo grande del home: "Hola, {nombre}" + línea de apoyo, en blanco.
class HeaderGreeting extends StatelessWidget {
  const HeaderGreeting({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.2,
                    color: Colors.white)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: .88))),
            ],
          ],
        ),
      );
}

/// Botón circular del header (atrás, menú, campana): círculo blanco
/// translúcido con ícono blanco, 42×42. `badgeCount` pinta la píldora blanca
/// con el conteo (campana).
class HeaderCircleButton extends StatelessWidget {
  const HeaderCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badgeCount = 0,
    this.solid = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int badgeCount;

  /// Círculo blanco pleno (avatar) en vez de translúcido.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btn = Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: solid ? Colors.white : Colors.white.withValues(alpha: .20),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon,
                size: 20, color: solid ? cs.onPrimaryContainer : Colors.white),
          ),
        ),
      ),
    );
    if (badgeCount <= 0) return btn;
    return Stack(clipBehavior: Clip.none, children: [
      btn,
      Positioned(
        top: -3,
        right: -3,
        child: Container(
          constraints: const BoxConstraints(minWidth: 17),
          height: 17,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(9)),
          child: Text(badgeLabel(badgeCount),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.primary)),
        ),
      ),
    ]);
  }
}

/// Campana del header: mismo `notifCountStore` compartido que la del AppBar,
/// vestida para el fondo violeta. Refresca al montar y al volver del fondo.
class HeaderBell extends StatefulWidget {
  const HeaderBell({super.key});
  @override
  State<HeaderBell> createState() => _HeaderBellState();
}

class _HeaderBellState extends State<HeaderBell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notifCountStore.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) notifCountStore.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: notifCountStore,
        builder: (context, _) => HeaderCircleButton(
          icon: Icons.notifications_outlined,
          tooltip: 'Notificaciones',
          badgeCount: notifCountStore.count,
          onTap: () => context.push('/notifications'),
        ),
      );
}

/// Contador de créditos del header (pedido PO 2026-08-22: «que se vea en todas
/// las pantallas relevantes»): la moneda de la tienda + el saldo, y al tocarlo
/// se abre la recarga.
///
/// Solo en las pantallas del PROVEEDOR: el cliente no gasta créditos y un
/// contador ahí no querría decir nada.
///
/// No se pinta hasta saber el número: en una cabecera, un «0» falso es peor que
/// no enseñar nada.
class HeaderSaldo extends StatefulWidget {
  const HeaderSaldo({super.key});
  @override
  State<HeaderSaldo> createState() => _HeaderSaldoState();
}

class _HeaderSaldoState extends State<HeaderSaldo> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    saldoStore.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Volver del fondo es justo cuando pudo haber comprado créditos fuera.
    if (state == AppLifecycleState.resumed) saldoStore.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: saldoStore,
        builder: (context, _) {
          final saldo = saldoStore.saldo;
          if (saldo == null) return const SizedBox.shrink();
          return Semantics(
            button: true,
            label: 'Tienes $saldo créditos. Recargar.',
            child: ExcludeSemantics(
              child: Material(
                color: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(999),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/tienda-creditos'),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 13, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MonedaJayalo(size: 22),
                        SizedBox(width: 6),
                        _SaldoTexto(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// El número, aparte solo para que la fila de arriba pueda ser `const`.
class _SaldoTexto extends StatelessWidget {
  const _SaldoTexto();

  @override
  Widget build(BuildContext context) => Text('${saldoStore.saldo}',
      style: const TextStyle(
          fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white));
}

/// Avatar del header: foto/inicial sobre círculo blanco; abre el mismo menú de
/// perfil (Estadísticas/Ajustes) que el del AppBar.
class HeaderAvatar extends StatefulWidget {
  const HeaderAvatar({super.key});
  @override
  State<HeaderAvatar> createState() => _HeaderAvatarState();
}

class _HeaderAvatarState extends State<HeaderAvatar> {
  @override
  void initState() {
    super.initState();
    profileStore.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: profileStore,
      builder: (context, _) {
        final url = profileStore.avatarUrl;
        return Semantics(
          button: true,
          label: 'Tu perfil',
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openProfileMenu(context),
              child: SizedBox(
                width: 42,
                height: 42,
                child: url != null
                    ? JayaloNetworkImage(url, fit: BoxFit.cover)
                    : Center(
                        child: Text(profileStore.initial,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimaryContainer)),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Leading auto-ajustable del header violeta: si hay algo apilado que popear
/// (la pantalla se abrió empujada — p. ej. un proveedor entrando a "Mis
/// solicitudes"/"Reputación" desde el menú del avatar) muestra una flecha de
/// atrás; como pestaña raíz muestra el avatar de perfil. Así una misma pantalla
/// sirve de pestaña (avatar) y de sub-pantalla empujada (atrás visible) sin
/// duplicarse. Usa `Navigator.canPop` (no la extensión de go_router) para
/// funcionar también bajo un `Navigator` pelado en los tests de widget.
class HeaderLeading extends StatelessWidget {
  const HeaderLeading({super.key});

  @override
  Widget build(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      return HeaderCircleButton(
        icon: Icons.arrow_back,
        tooltip: 'Atrás',
        onTap: () => Navigator.of(context).maybePop(),
      );
    }
    return const HeaderAvatar();
  }
}

/// Buscador del header: píldora blanca con lupa + hint, y un botón "Filtrar"
/// opcional en violeta oscuro. En Jayalo también se busca; el botón de crear
/// solicitud vive SOLO en el centro de la navbar (doctrina), nunca aquí.
class WarmSearchField extends StatelessWidget {
  const WarmSearchField({
    super.key,
    required this.hint,
    this.onTap,
    this.onFilter,
  });

  final String hint;
  final VoidCallback? onTap;
  final VoidCallback? onFilter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 7, 7, 7),
          child: Row(children: [
            Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5, color: cs.onSurfaceVariant)),
            ),
            if (onFilter != null)
              Material(
                color: cs.onPrimaryContainer,
                borderRadius: BorderRadius.circular(999),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onFilter,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.tune, size: 15, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Filtrar',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Segmentos deslizantes sobre el header violeta (`.vseg`): pista blanca
/// translúcida, el activo va en blanco pleno con tinta violeta oscura. Para
/// los toggles reales del inbox (Para ti/Todas, tipo) y de crear/catálogo.
class HeaderSegmented extends StatelessWidget {
  const HeaderSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
    this.compact = false,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  /// Versión estrecha para convivir en la fila del título con el avatar y la
  /// campana (Catálogo, 2026-09-05): padding 10×4 y fuente 10,5 en vez de 12×5
  /// y 11. Misma pista, mismos colores, mismo tic háptico.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Tic de selección solo al cambiar de verdad de segmento
              // (mismo criterio que la barra flotante).
              onTap: () {
                if (i != index) JayaloHaptics.tabChange();
                onChanged(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: i == index ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  options[i],
                  style: TextStyle(
                    fontSize: compact ? 10.5 : 11,
                    fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                    // Píldora seleccionada = BLANCA en ambos temas → el texto
                    // debe ser oscuro. `onPrimaryContainer` es claro en oscuro
                    // (texto claro sobre blanco = ilegible, bug PO 2026-07-23);
                    // `primary` (violeta) es legible sobre blanco en claro Y
                    // oscuro, igual que HeaderPill.
                    color: i == index
                        ? cs.primary
                        : Colors.white.withValues(alpha: .88),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Píldora blanca de énfasis en el header ("Al por mayor", "3 nuevas").
class HeaderPill extends StatelessWidget {
  const HeaderPill(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
      );
}
