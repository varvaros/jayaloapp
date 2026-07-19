/// Avatar de perfil en el AppBar (spec iteración 2 §5): vive junto a la
/// campana en las 6 pantallas raíz. Al tocarlo abre un menú por rol —
/// Ajustes y Estadísticas SALIERON de la barra flotante (ambos roles pierden
/// Ajustes; el proveedor también pierde Estadísticas, spec §4) y viven aquí
/// ahora. Las rutas `/settings` y `/provider/stats` no cambian, solo cómo se
/// llega a ellas.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart' show myProfile;

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

/// Botón circular del AppBar. `IconButton` de verdad (no un `Semantics`
/// hecho a mano): así hereda gratis el área de toque mínima de 48×48 y el
/// tooltip como nombre accesible — la iteración 1 dejó un botón invisible a
/// lectores de pantalla al envolver algo en `Semantics(excludeSemantics:
/// true)` sin `onTap`; usar el widget estándar evita repetir esa clase de bug.
class ProfileAvatarButton extends StatefulWidget {
  /// [store] es inyectable solo para test (montar 2+ instancias sobre el
  /// mismo store y contar consultas reales); en la app real siempre usa el
  /// singleton `profileStore`.
  const ProfileAvatarButton({super.key, this.store});

  final ProfileStore? store;

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
  ///
  /// El menú SALE DE LA DERECHA (PO 2026-07-19, revisión visual en device;
  /// antes era `showModalBottomSheet`, desde abajo): un panel lateral tipo
  /// end-drawer con esquinas izquierdas redondeadas que desliza desde el
  /// borde derecho — el mismo lado donde vive el avatar que lo abre. Con
  /// "reducir animaciones" aparece sin movimiento.
  Future<void> _openMenu() async {
    final isProvider = roleStore.value == RoleState.provider;
    final route = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar menú',
      barrierColor: Colors.black38,
      transitionDuration: JayaloMotion.reduced(context)
          ? Duration.zero
          : JayaloMotion.base,
      pageBuilder: (ctx, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: SizedBox(
              width: 264,
              height: double.infinity,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                if (isProvider)
                  ListTile(
                    leading: const Icon(Icons.bar_chart_outlined),
                    title: const Text('Estadísticas'),
                    onTap: () => Navigator.pop(ctx, '/provider/stats'),
                  ),
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
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: anim,
                curve: JayaloMotion.enter,
                reverseCurve: JayaloMotion.exit)),
        child: child,
      ),
    );
    if (route != null && mounted) context.push(route);
  }

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
              backgroundImage: url != null ? NetworkImage(url) : null,
              child: url == null ? Text(_store.initial) : null,
            ),
          );
        },
      );
}
