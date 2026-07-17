import 'package:flutter/foundation.dart';
import '../data/repos.dart';

enum RoleState { unknown, needsOnboarding, consumer, provider }

/// El gate del spec §4: con account_type NULL no hay ruta del shell alcanzable.
/// Función pura para poder testearla sin router.
String? redirectTarget({
  required bool loggedIn,
  required RoleState role,
  required String location,
}) {
  final inOnboarding = location.startsWith('/onboarding');
  final onLogin = location == '/login';
  final onGate = location == '/gate';
  if (!loggedIn) return onLogin ? null : '/login';
  if (onLogin) return '/gate';
  if (role == RoleState.unknown) return onGate ? null : '/gate';
  if (role == RoleState.needsOnboarding) {
    return (inOnboarding || onGate) ? null : '/onboarding';
  }
  // Rol resuelto: fuera de gate/onboarding se navega libre entre tabs.
  if (inOnboarding || onGate) {
    return role == RoleState.provider ? '/provider' : '/client';
  }
  return null;
}

class RoleStore extends ChangeNotifier {
  RoleState value = RoleState.unknown;

  Future<void> refresh() async {
    final p = await myProfile();
    value = switch (p?['account_type']) {
      'provider' => RoleState.provider,
      'consumer' => RoleState.consumer,
      _ => RoleState.needsOnboarding,
    };
    notifyListeners();
  }

  void invalidate() {
    value = RoleState.unknown;
    notifyListeners();
  }
}

final roleStore = RoleStore();
