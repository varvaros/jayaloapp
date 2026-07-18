import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/conversations_screen.dart';
import '../features/client/create_request_screen.dart';
import '../features/client/my_requests_screen.dart';
import '../features/client/request_status_screen.dart';
import '../features/onboarding/choose_role_screen.dart';
import '../features/onboarding/consumer_onboarding_screen.dart';
import '../features/onboarding/gate_screen.dart';
import '../features/onboarding/provider_onboarding_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/provider/inbox_screen.dart';
import '../features/provider/my_offers_screen.dart';
import '../features/provider/request_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/back_guard.dart';
import '../features/shell/home_shell.dart';
import 'session_state.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/gate',
      refreshListenable: Listenable.merge([_AuthNotifier(), roleStore]),
      redirect: (context, state) {
        final loggedIn = Supabase.instance.client.auth.currentSession != null;
        // Al cerrar sesión, el rol cacheado deja de valer.
        if (!loggedIn && roleStore.value != RoleState.unknown) {
          roleStore.invalidate();
        }
        return redirectTarget(
            loggedIn: loggedIn,
            role: roleStore.value,
            location: state.matchedLocation);
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/gate', builder: (_, _) => const GateScreen()),
        GoRoute(path: '/onboarding', builder: (_, _) => const ChooseRoleScreen()),
        GoRoute(
            path: '/onboarding/consumer',
            builder: (_, _) => const ConsumerOnboardingScreen()),
        GoRoute(
            path: '/onboarding/provider',
            builder: (_, _) => const ProviderOnboardingScreen()),
        ShellRoute(
          builder: (_, _, child) => HomeShell(child: child),
          // BackGuard va DENTRO de cada ruta (no en HomeShell) para que el
          // PopScope se registre en el navigator anidado; ver back_guard.dart.
          routes: [
            GoRoute(
                path: '/client',
                builder: (_, _) => const BackGuard(child: MyRequestsScreen())),
            GoRoute(
                path: '/client/create',
                builder: (_, _) => const BackGuard(child: CreateRequestScreen())),
            GoRoute(
                path: '/client/request/:id',
                builder: (_, s) => BackGuard(
                    child:
                        RequestStatusScreen(requestId: s.pathParameters['id']!))),
            GoRoute(
                path: '/provider',
                builder: (_, _) => const BackGuard(child: ProviderInboxScreen())),
            GoRoute(
                path: '/provider/request/:id',
                builder: (_, s) => BackGuard(
                    child: ProviderRequestDetailScreen(
                        requestId: s.pathParameters['id']!))),
            GoRoute(
                path: '/provider/offers',
                builder: (_, _) => const BackGuard(child: MyOffersScreen())),
            GoRoute(
                path: '/settings',
                builder: (_, _) => const BackGuard(child: SettingsScreen())),
            GoRoute(
                path: '/messages',
                builder: (_, _) => const BackGuard(child: ConversationsScreen())),
            GoRoute(
                path: '/messages/:id',
                builder: (_, s) {
                  // Task I-2: peer_name/avatar llegan por `extra` desde la
                  // lista de conversaciones (evita el RPC agregado). Si no
                  // vienen (deep-link/push futuro), quedan null y ChatScreen
                  // cae al fallback con `conversationsList()`.
                  final x = s.extra;
                  final m = x is Map ? x : null;
                  return BackGuard(
                      child: ChatScreen(
                          conversationId: s.pathParameters['id']!,
                          peerName: m?['peer_name'] as String?,
                          peerAvatarUrl: m?['peer_avatar_url'] as String?));
                }),
            GoRoute(
                path: '/notifications',
                builder: (_, _) =>
                    const BackGuard(child: NotificationsScreen())),
          ],
        ),
      ],
    );

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}
