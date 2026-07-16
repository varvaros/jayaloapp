import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/login_screen.dart';
import '../features/client/create_request_screen.dart';
import '../features/client/my_requests_screen.dart';
import '../features/client/request_status_screen.dart';
import '../features/provider/inbox_screen.dart';
import '../features/provider/my_offers_screen.dart';
import '../features/provider/request_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/home_shell.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/client',
      refreshListenable: _AuthNotifier(),
      redirect: (context, state) {
        final loggedIn = Supabase.instance.client.auth.currentSession != null;
        final onLogin = state.matchedLocation == '/login';
        if (!loggedIn) return onLogin ? null : '/login';
        if (onLogin) return '/client';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        ShellRoute(
          builder: (_, _, child) => HomeShell(child: child),
          routes: [
            GoRoute(path: '/client', builder: (_, _) => const MyRequestsScreen()),
            GoRoute(
                path: '/client/create',
                builder: (_, _) => const CreateRequestScreen()),
            GoRoute(
                path: '/client/request/:id',
                builder: (_, s) =>
                    RequestStatusScreen(requestId: s.pathParameters['id']!)),
            GoRoute(
                path: '/provider', builder: (_, _) => const ProviderInboxScreen()),
            GoRoute(
                path: '/provider/request/:id',
                builder: (_, s) => ProviderRequestDetailScreen(
                    requestId: s.pathParameters['id']!)),
            GoRoute(
                path: '/provider/offers', builder: (_, _) => const MyOffersScreen()),
            GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          ],
        ),
      ],
    );

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

