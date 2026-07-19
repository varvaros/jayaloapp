/// Avatar de perfil en el AppBar (spec iteración 2 §5): vive junto a la
/// campana en las 6 pantallas raíz. Al tocarlo abre un menú por rol —
/// Ajustes y Estadísticas SALIERON de la barra flotante (ambos roles pierden
/// Ajustes; el proveedor también pierde Estadísticas, spec §4) y viven aquí
/// ahora. Las rutas `/settings` y `/provider/stats` no cambian, solo cómo se
/// llega a ellas.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  String? avatarUrl;
  String? firstName;
  bool _loaded = false;

  /// [force] para refrescar tras editar el perfil — no hay pantalla de
  /// edición en la app todavía, así que hoy nunca se pasa `true`; queda listo
  /// para cuando exista. Best-effort: sin red, el avatar cae al ícono/inicial
  /// genérico y se reintenta sola la próxima vez que se monte una pantalla
  /// raíz (nunca queda pegado a un error).
  Future<void> refresh({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final p = await myProfile();
      avatarUrl = p?['avatar_url'] as String?;
      firstName = p?['first_name'] as String?;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Best-effort: no rompe la pantalla que lo hospeda.
    }
  }

  /// Al cerrar sesión el avatar no debe arrastrar la foto/nombre del usuario
  /// anterior (se vería en el siguiente login, en el mismo teléfono).
  void clear() {
    avatarUrl = null;
    firstName = null;
    _loaded = false;
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
  const ProfileAvatarButton({super.key});

  @override
  State<ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<ProfileAvatarButton> {
  @override
  void initState() {
    super.initState();
    profileStore.refresh();
  }

  /// El rol se lee al momento del toque (no en `build`): siempre refleja el
  /// valor vigente de `roleStore` sin necesidad de escucharlo para redibujar
  /// el botón (el rol no cambia durante la sesión, spec §4).
  Future<void> _openMenu() async {
    final isProvider = roleStore.value == RoleState.provider;
    final route = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
    );
    if (route != null && mounted) context.push(route);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: profileStore,
        builder: (context, _) {
          final url = profileStore.avatarUrl;
          return IconButton(
            tooltip: 'Tu perfil',
            onPressed: _openMenu,
            icon: CircleAvatar(
              radius: 16,
              backgroundImage: url != null ? NetworkImage(url) : null,
              child: url == null ? Text(profileStore.initial) : null,
            ),
          );
        },
      );
}
