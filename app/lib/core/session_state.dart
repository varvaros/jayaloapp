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
  // El gate SOLO retiene mientras el rol está sin resolver. Una vez resuelto
  // (cualquier valor) hay que salir de él, o el usuario se queda mirando el
  // spinner para siempre (bug hallado en el device 2026-07-17).
  if (role == RoleState.unknown) return onGate ? null : '/gate';
  if (role == RoleState.needsOnboarding) {
    return inOnboarding ? null : '/onboarding';
  }
  // Rol resuelto: fuera de gate/onboarding se navega libre entre tabs.
  if (inOnboarding || onGate) {
    return role == RoleState.provider ? '/provider' : '/client';
  }
  return null;
}

/// Decide el rol efectivo. Pura para poder testearla sin BD.
///
/// Un `account_type='provider'` SIN negocio es un "proveedor a medias" (dato
/// legacy anterior a la RPC atómica, o un alta abandonada): mandarlo a
/// `/provider` lo deja atrapado en una bandeja vacía donde no puede ofertar ni
/// salir. Debe completar el alta (spec §4). Caso real hallado en el E2E del
/// 2026-07-17.
RoleState roleFrom({String? accountType, required bool hasBusiness}) {
  if (accountType == 'provider') {
    return hasBusiness ? RoleState.provider : RoleState.needsOnboarding;
  }
  if (accountType == 'consumer') return RoleState.consumer;
  return RoleState.needsOnboarding;
}

class RoleStore extends ChangeNotifier {
  RoleState value = RoleState.unknown;

  Future<void> refresh() async {
    // `kDebugMode`: `debugPrint` NO se elimina en release (a diferencia de los
    // asserts) y `avoid_print` tampoco lo cubre, así que estas trazas escribían
    // `account_type` y el estado de sesión a logcat en el binario de producción,
    // donde cualquier app con permiso de lectura de logs las ve.
    if (kDebugMode) debugPrint('[gate] refresh: inicio');
    final p = await myProfile();
    final type = p?['account_type'] as String?;
    if (kDebugMode) debugPrint('[gate] myProfile OK -> account_type=$type');
    // Solo se consulta el negocio si dice ser proveedor (una query de más
    // únicamente en ese caso).
    final hasBusiness = type == 'provider' ? (await myBusinessId()) != null : false;
    if (kDebugMode) debugPrint('[gate] hasBusiness=$hasBusiness');
    value = roleFrom(accountType: type, hasBusiness: hasBusiness);
    if (kDebugMode) debugPrint('[gate] rol resuelto=$value');
    notifyListeners();
  }

  void invalidate() {
    value = RoleState.unknown;
    notifyListeners();
  }
}

final roleStore = RoleStore();
