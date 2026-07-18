import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/notifications_repository.dart';
import '../../data/repos.dart' show supa;
import '../../domain/notifications.dart';

/// Conteo de no-leídas COMPARTIDO entre las 4 campanas (un solo estado, no un
/// fetch por campana). Ciclo de vida (spec §2): refresh al montar la pantalla
/// que la contiene + al resume; optimista vía [add]/[zero] desde la pantalla
/// de notificaciones. SIN socket persistente.
class NotifCountStore extends ChangeNotifier {
  int count = 0;

  NotifCountStore() {
    // Al cerrar sesión el badge no debe arrastrar el conteo del usuario
    // anterior (se vería en la pantalla de login o en el siguiente login).
    supa.auth.onAuthStateChange.listen((e) {
      if (e.event == AuthChangeEvent.signedOut) zero();
    });
  }

  Future<void> refresh() async {
    try {
      final n = await unreadNotificationsCount();
      if (n != count) {
        count = n;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort: el badge nunca rompe la pantalla que lo hospeda.
    }
  }

  void add(int delta) {
    final next = (count + delta).clamp(0, 999);
    if (next != count) {
      count = next;
      notifyListeners();
    }
  }

  void zero() => add(-count);
}

final notifCountStore = NotifCountStore();

/// Campana del AppBar (spec §2): badge rojo con tope 9+, pop elástico al
/// aparecer y pulso al cambiar el conteo. Tap → /notifications.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: notifCountStore,
      builder: (context, _) {
        final c = notifCountStore.count;
        return IconButton(
          tooltip: 'Notificaciones',
          onPressed: () => context.push('/notifications'),
          icon: Stack(clipBehavior: Clip.none, children: [
            const Icon(Icons.notifications_outlined),
            if (c > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  height: 16,
                  constraints: const BoxConstraints(minWidth: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeLabel(c),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onError),
                  ),
                )
                    // La key por valor recrea el Animate en cada cambio de
                    // conteo: pop elástico al aparecer Y pulso al subir.
                    .animate(key: ValueKey(c))
                    .scale(
                        begin: const Offset(.4, .4),
                        end: const Offset(1, 1),
                        duration: 500.ms,
                        curve: Curves.elasticOut),
              ),
          ]),
        );
      },
    );
  }
}
