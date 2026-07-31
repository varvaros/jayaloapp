/// Avatar de perfil en el AppBar (spec iteración 2 §5): vive junto a la
/// campana en las 6 pantallas raíz. Al tocarlo abre un menú por rol —
/// Ajustes y Estadísticas SALIERON de la barra flotante (ambos roles pierden
/// Ajustes; el proveedor también pierde Estadísticas, spec §4) y viven aquí
/// ahora. Las rutas `/settings` y `/provider/stats` no cambian, solo cómo se
/// llega a ellas.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'network_image.dart';

import '../../core/config.dart';
import '../../core/motion.dart';
import '../../core/safe_image_picker.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart'
    show myProfile, walletBalance, createWalletLoginLink, updateMyAvatar, isAdmin;

/// Foto + nombre cacheados UNA sola vez y compartidos por las 6 instancias
/// del avatar (mismo espíritu que `NotifCountStore` en
/// `notification_bell.dart`): sin este caché cada pantalla dispararía su
/// propia consulta a `profiles` en cada `build`, multiplicando la carga y
/// parpadeando la foto al cambiar de pestaña.
///
/// El constructor NO toca `supa` (a diferencia de `NotifCountStore`, que
/// escucha `onAuthStateChange` en el suyo): así el singleton se puede
/// referenciar desde un test sin que Supabase esté inicializado. La limpieza
/// al cerrar sesión se dispara desde `router.dart`, junto a
/// `roleStore.invalidate()`, que ya es el punto de verdad de "se cerró
/// sesión" en esta app.
class ProfileStore extends ChangeNotifier {
  /// [loader] es inyectable para poder contar/controlar la consulta desde un
  /// test (ver `profile_avatar_button_test.dart`); en la app real siempre es
  /// `myProfile`.
  ProfileStore({this.loader = myProfile});

  final Future<Map<String, dynamic>?> Function() loader;

  String? avatarUrl;
  String? firstName;
  bool _loaded = false;

  /// Fetch en vuelo compartido: si dos pantallas se montan casi a la vez (p.
  /// ej. el `AnimatedSwitcher` de `home_shell.dart`, que mantiene la pantalla
  /// saliente montada junto a la entrante durante toda la transición) ambas
  /// llaman a `refresh()` antes de que la primera consulta a `profiles`
  /// resuelva. Sin esto cada una dispararía su propia consulta real —
  /// benigno en resultado (misma fila) pero duplicado innecesario. Guardar el
  /// `Future` en curso y devolvérselo a quien llegue mientras tanto colapsa
  /// N montajes concurrentes en 1 sola consulta.
  Future<void>? _inFlight;

  /// Se incrementa en `clear()` para invalidar cualquier fetch en vuelo: si
  /// el usuario cierra sesión mientras una consulta del usuario anterior
  /// sigue viajando, esa respuesta no debe "resucitar" datos viejos al
  /// aplicarse después del `clear()`.
  int _generation = 0;

  /// [force] para refrescar tras editar el perfil — no hay pantalla de
  /// edición en la app todavía, así que hoy nunca se pasa `true`; queda listo
  /// para cuando exista. Best-effort: sin red, el avatar cae al ícono/inicial
  /// genérico y se reintenta sola la próxima vez que se monte una pantalla
  /// raíz (nunca queda pegado a un error).
  Future<void> refresh({bool force = false}) {
    if (_loaded && !force) return Future.value();
    return _inFlight ??= _fetch(_generation);
  }

  Future<void> _fetch(int generation) async {
    try {
      final p = await loader();
      if (generation != _generation) return; // invalidado por un clear() de por medio
      avatarUrl = p?['avatar_url'] as String?;
      firstName = p?['first_name'] as String?;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Best-effort: no rompe la pantalla que lo hospeda.
    } finally {
      if (generation == _generation) _inFlight = null;
    }
  }

  /// Al cerrar sesión el avatar no debe arrastrar la foto/nombre del usuario
  /// anterior (se vería en el siguiente login, en el mismo teléfono). También
  /// invalida cualquier fetch en vuelo (ver `_generation`) para que esa
  /// respuesta, si llega tarde, no vuelva a poblar datos del usuario que ya
  /// cerró sesión.
  void clear() {
    avatarUrl = null;
    firstName = null;
    _loaded = false;
    _generation++;
    _inFlight = null;
    notifyListeners();
  }

  String get initial {
    final n = firstName?.trim();
    return (n != null && n.isNotEmpty) ? n[0].toUpperCase() : '?';
  }
}

final profileStore = ProfileStore();

/// Resultado especial del menú: "Recargar créditos" no es una ruta del router
/// sino el wallet EXTERNO (ADR-0031, el pago siempre fuera de la app).
const _kWalletAction = '__wallet__';

/// Abre el menú de perfil (role-aware). Proveedor: encabezado con nombre +
/// saldo de créditos, luego su lado comprador (Reputación, Otros proveedores),
/// su negocio (Estadísticas, Recargar créditos) y Ajustes. "Mis solicitudes"
/// salió de acá el 2026-07-30 — vive en el segmento "Mis pedidos" de la
/// pestaña Mis ofertas.
/// Consumidor: solo Ajustes (ya alcanza el resto por su navbar). Extraído a
/// función suelta para que lo compartan el `ProfileAvatarButton` del AppBar y
/// el avatar del header violeta (`violet_header.dart`) — un solo menú, un solo
/// comportamiento.
///
/// El menú SALE DE LA IZQUIERDA (PO 2026-07-19, tras mover el avatar al leading
/// del header violeta): un panel lateral tipo drawer con esquinas derechas
/// redondeadas que desliza desde el borde izquierdo — el mismo lado donde ahora
/// vive el avatar que lo abre. Con "reducir animaciones" aparece sin
/// movimiento. Curva `emphasized` (easeInOutCubic) a `page` (300 ms): arranque
/// suave, frenada visible antes de asentarse.
///
/// [balanceFetch] es inyectable solo para test; en la app real es null y se usa
/// `walletBalance`.
/// El panel lateral como ruta propia.
///
/// `showGeneralDialog` alcanzaría para todo menos para UNA cosa: no expone
/// `reverseTransitionDuration`, así que la salida hereda la duración de la
/// entrada. Con el frenado de 1.5s de [JayaloMotion.sheetRise] eso significaría
/// segundo y medio para cerrar el menú. Un [PopupRoute] sí permite las dos
/// duraciones por separado — entra frenando, se va rápido.
class _SideMenuRoute<T> extends PopupRoute<T> {
  _SideMenuRoute({required this.pageBuilder, required this.reduced});

  final Widget Function(BuildContext context) pageBuilder;

  /// "Reducir animaciones" del sistema: el panel aparece y desaparece sin
  /// deslizamiento (la duración cero deja el `SlideTransition` en su posición
  /// final desde el primer frame).
  final bool reduced;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Cerrar menú';

  @override
  Color get barrierColor => Colors.black38;

  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : JayaloMotion.sheetRise.duration!;

  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : JayaloMotion.sheetRise.reverseDuration!;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      pageBuilder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: animation,
                // Misma curva que las hojas: quinta potencia — el panel recorre
                // casi todo el camino al principio y el resto del tiempo es
                // una frenada larga hasta asentarse.
                curve: JayaloMotion.sheetRise.curve!,
                reverseCurve: JayaloMotion.sheetRise.reverseCurve!)),
        child: child,
      );
}

Future<void> openProfileMenu(BuildContext context,
    {Future<int?> Function()? balanceFetch}) async {
  final isProvider = roleStore.value == RoleState.provider;
  final fetch = balanceFetch ?? walletBalance;
  // El panel entra deslizando desde la izquierda con el MISMO frenado que las
  // hojas que suben (PO 2026-07-30: "el efecto de frenado lento a las ventanas
  // que se deslizan… y el menú lateral"). Antes tenía su propia receta a mano
  // (480ms easeOutCubic); ahora sale de `sheetRise`.
  //
  // Se usa [_SideMenuRoute] y no `showGeneralDialog` por una sola razón: esa
  // función no expone `reverseTransitionDuration`, así que la salida heredaría
  // los 1.5s de la entrada — y un menú que tarda segundo y medio en QUITARSE
  // del medio se siente roto, no premium.
  final route = await Navigator.of(context, rootNavigator: true)
      .push<String>(_SideMenuRoute<String>(
    reduced: JayaloMotion.reduced(context),
    pageBuilder: (ctx) => Align(
      alignment: Alignment.centerLeft,
      child: Material(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: SizedBox(
            width: 264,
            height: double.infinity,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Encabezado con nombre + saldo de créditos RESALTADO (número
                // grande en violeta con un "+" para recargar): solo proveedor
                // (el consumidor no gasta créditos en este modelo).
                // Foto + nombre editables para AMBOS roles (pedido PO
                // 2026-07-22); la banda de créditos, solo proveedor.
                _ProfileMenuHeader(
                  balanceFetch: isProvider ? fetch : null,
                  onRecharge: isProvider
                      ? () => Navigator.pop(ctx, _kWalletAction)
                      : null,
                ),
                const SizedBox(height: 4),
                // Lado "yo como comprador": pantallas que existen en el router
                // pero que el proveedor no alcanza por su navbar.
                if (isProvider) ...[
                  // "Mis solicitudes" ya NO vive acá (PO 2026-07-30): pasó al
                  // segmento "Mis pedidos" de Mis ofertas, en la barra. Estaba
                  // enterrada en este menú mientras el ＋ de la misma barra
                  // dejaba CREAR solicitudes — se podía crear algo que después
                  // no había dónde encontrar.
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('Reputación'),
                    onTap: () => Navigator.pop(ctx, '/client/reputation'),
                  ),
                  ListTile(
                    // El catálogo del marketplace, renombrado para el
                    // proveedor: lo que ofrecen los DEMÁS (sus propios
                    // productos viven en "Mi negocio").
                    leading: const Icon(Icons.storefront_outlined),
                    title: const Text('Otros proveedores'),
                    onTap: () => Navigator.pop(ctx, '/catalog'),
                  ),
                  const Divider(height: 1),
                  // Lado "mi negocio".
                  ListTile(
                    leading: const Icon(Icons.bar_chart_outlined),
                    title: const Text('Estadísticas'),
                    onTap: () => Navigator.pop(ctx, '/provider/stats'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Recargar créditos'),
                    onTap: () => Navigator.pop(ctx, _kWalletAction),
                  ),
                  const Divider(height: 1),
                ],
                // Solo admin (pedido PO 2026-07-22): registro rápido de
                // proveedores por correo. El item se auto-oculta si no es admin.
                _AdminMenuItem(
                    onSelect: () =>
                        Navigator.pop(ctx, '/admin/quick-register')),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Ajustes'),
                  onTap: () => Navigator.pop(ctx, '/settings'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  ));
  if (route == null || !context.mounted) return;
  if (route == _kWalletAction) {
    await openExternalWallet(context);
    return;
  }
  context.push(route);
}

/// Abre el wallet en el navegador del sistema (ADR-0031: el pago SIEMPRE ocurre
/// fuera de la app). Intenta un enlace de login de un solo uso; si falla, cae a
/// la URL genérica; si el navegador no abre, avisa. Mismo comportamiento que
/// `inbox_screen._openWallet`.
Future<void> openExternalWallet(BuildContext context) async {
  Uri target = Uri.parse(AppConfig.walletUrl);
  try {
    target = Uri.parse(await createWalletLoginLink());
  } catch (_) {}
  var ok = false;
  try {
    ok = await launchUrl(target, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No se pudo abrir el navegador. Visita jayalo.com para recargar.')));
  }
}

/// Encabezado del menú (solo proveedor): foto/inicial + nombre, y debajo el
/// saldo de créditos RESALTADO — número grande en violeta sobre una banda
/// teñida, con un "+" para recargar al lado (los créditos son el core del
/// negocio, por eso se destacan). El saldo se pide al abrir el menú,
/// best-effort: si falla o aún no llega, la banda muestra "Créditos" sin número
/// pero el "+" sigue disponible (recargar nunca queda inalcanzable).
/// Item de menú "Registro rápido" que SOLO aparece si el usuario es admin
/// (consulta `isAdmin()` al montarse; mientras tanto no ocupa espacio).
class _AdminMenuItem extends StatefulWidget {
  const _AdminMenuItem({required this.onSelect});
  final VoidCallback onSelect;
  @override
  State<_AdminMenuItem> createState() => _AdminMenuItemState();
}

class _AdminMenuItemState extends State<_AdminMenuItem> {
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    isAdmin().then((v) => mounted ? setState(() => _admin = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_admin) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Divider(height: 1),
      ListTile(
        leading: Icon(Icons.person_add_alt, color: cs.primary),
        title: const Text('Registro rápido'),
        subtitle: const Text('Registrar un proveedor por correo'),
        onTap: widget.onSelect,
      ),
    ]);
  }
}

class _ProfileMenuHeader extends StatefulWidget {
  const _ProfileMenuHeader({this.balanceFetch, this.onRecharge});

  /// Solo proveedor: si es null, la banda de créditos no se muestra (el
  /// consumidor no gasta créditos), pero la foto + nombre editables sí.
  final Future<int?> Function()? balanceFetch;
  final VoidCallback? onRecharge;

  @override
  State<_ProfileMenuHeader> createState() => _ProfileMenuHeaderState();
}

class _ProfileMenuHeaderState extends State<_ProfileMenuHeader> {
  int? _balance;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    if (widget.balanceFetch != null) _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final b = await widget.balanceFetch!();
      if (mounted) setState(() => _balance = b);
    } catch (_) {
      // Best-effort: sin saldo confirmado la banda va sin número.
    }
  }

  /// Editar la foto de perfil (pedido PO 2026-07-22): elige de la galería,
  /// sube a Storage y refresca el avatar en toda la app.
  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    final picked = await guardedPick((p) => p.pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 85));
    if (picked == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      await updateMyAvatar(picked.path);
      await profileStore.refresh(force: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo actualizar la foto.')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: profileStore,
      builder: (context, _) {
        final url = profileStore.avatarUrl;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar CENTRADO en el tope del menú y 200% más grande (radio
              // 22 → 66, pedido PO 2026-07-21): la foto es la protagonista del
              // panel. Sigue siendo EDITABLE: tocar para cambiarla, con el
              // badge de cámara (escalado acorde). Mientras sube, un spinner.
              Center(
                child: GestureDetector(
                  onTap: _uploadingAvatar ? null : _pickAvatar,
                  child: Stack(clipBehavior: Clip.none, children: [
                    CircleAvatar(
                      radius: 66,
                      backgroundColor: cs.primaryContainer,
                      backgroundImage:
                          url != null ? jayaloAvatarImage(url, 132, context) : null,
                      child: _uploadingAvatar
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(strokeWidth: 3))
                          : (url == null
                              ? Text(profileStore.initial,
                                  style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onPrimaryContainer))
                              : null),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                        child: Icon(Icons.camera_alt,
                            size: 16, color: cs.onPrimary),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Text(profileStore.firstName ?? 'Tu perfil',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              // Sin foto: empuja a subir una (pedido PO: "genera más confianza
              // con tu foto de perfil").
              if (url == null) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _uploadingAvatar ? null : _pickAvatar,
                  child: Text('Genera más confianza con tu foto de perfil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w500)),
                ),
              ],
              if (widget.balanceFetch == null) const SizedBox(height: 4),
              if (widget.balanceFetch != null) ...[
              const SizedBox(height: 12),
              // Banda de créditos: número grande + "+" para recargar. Saldo 0
              // = ROJO (pedido PO 2026-07-22): el proveedor no puede desbloquear
              // contactos, es una advertencia, no algo neutro.
              Builder(builder: (context) {
                final empty = _balance == 0;
                final accent = empty ? cs.error : cs.primary;
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        _balance != null ? '$_balance créditos' : 'Créditos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: accent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Recargar créditos',
                      onPressed: widget.onRecharge,
                      icon: const Icon(Icons.add),
                      style: IconButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: cs.onPrimary,
                      ),
                    ),
                  ]),
                );
              }),
              if (_balance == 0) ...[
                const SizedBox(height: 6),
                Text('Tu saldo llegó a 0 — recarga para desbloquear contactos.',
                    style: TextStyle(fontSize: 11.5, color: cs.error)),
              ],
              ], // cierra el spread `if (widget.balanceFetch != null) ...[`
            ],
          ),
        );
      },
    );
  }
}

/// Botón circular del AppBar. `IconButton` de verdad (no un `Semantics`
/// hecho a mano): así hereda gratis el área de toque mínima de 48×48 y el
/// tooltip como nombre accesible — la iteración 1 dejó un botón invisible a
/// lectores de pantalla al envolver algo en `Semantics(excludeSemantics:
/// true)` sin `onTap`; usar el widget estándar evita repetir esa clase de bug.
class ProfileAvatarButton extends StatefulWidget {
  /// [store] es inyectable solo para test (montar 2+ instancias sobre el
  /// mismo store y contar consultas reales); en la app real siempre usa el
  /// singleton `profileStore`.
  const ProfileAvatarButton({super.key, this.store, this.balanceFetch});

  final ProfileStore? store;

  /// Inyectable solo para test (evita tocar `walletBalance`/red al abrir el
  /// menú); en la app real es null y `openProfileMenu` usa `walletBalance`.
  final Future<int?> Function()? balanceFetch;

  @override
  State<ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<ProfileAvatarButton> {
  late final ProfileStore _store;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? profileStore;
    _store.refresh();
  }

  /// El rol se lee al momento del toque (no en `build`): siempre refleja el
  /// valor vigente de `roleStore` sin necesidad de escucharlo para redibujar
  /// el botón (el rol no cambia durante la sesión, spec §4).
  Future<void> _openMenu() =>
      openProfileMenu(context, balanceFetch: widget.balanceFetch);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final url = _store.avatarUrl;
          return IconButton(
            tooltip: 'Tu perfil',
            onPressed: _openMenu,
            icon: CircleAvatar(
              radius: 16,
              backgroundImage:
                  url != null ? jayaloAvatarImage(url, 32, context) : null,
              child: url == null ? Text(_store.initial) : null,
            ),
          );
        },
      );
}
