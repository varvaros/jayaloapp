import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/login_screen.dart';
import '../features/client/create_request_screen.dart';
import '../features/client/my_requests_screen.dart';
import '../features/client/request_status_screen.dart';
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
            GoRoute(path: '/provider', builder: (_, _) => const _Todo('Solicitudes')),
            GoRoute(
                path: '/provider/request/:id',
                builder: (_, s) => _Todo('Solicitud ${s.pathParameters['id']}')),
            GoRoute(
                path: '/provider/offers', builder: (_, _) => const _Todo('Mis ofertas')),
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

/// Placeholder de ruta — cada task de pantallas (8-12) sustituye el suyo.
class _Todo extends StatelessWidget {
  const _Todo(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(label)), body: Center(child: Text(label)));
}
