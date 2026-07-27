import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../push/push_service.dart';
import '../shared/brand_kit.dart';

/// Selector de rol. Regla dura (lección choose-role.tsx:67-72 de la web):
/// elegir NO escribe account_type — solo el cierre de cada flujo lo persiste.
/// Quien abandona vuelve aquí sin residuo en la BD.
class ChooseRoleScreen extends StatefulWidget {
  const ChooseRoleScreen({super.key});

  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen> {
  bool _signingOut = false;

  /// Correo con el que se entró: lo mostramos arriba para que quien eligió el
  /// email equivocado lo note de una y pueda cambiar de cuenta sin salir a la fuerza.
  String? get _email => Supabase.instance.client.auth.currentUser?.email;

  /// Cambiar de cuenta = cerrar sesión de VERDAD (misma secuencia que Ajustes:
  /// hay que cerrar también la de Google, si no el SDK reutiliza la cuenta en
  /// silencio y no se puede cambiar de usuario). El router redirige a /login al
  /// cerrar la sesión de Supabase.
  Future<void> _changeAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cambiar de cuenta?'),
        content: Text(
            'Cerrarás la sesión${_email != null ? ' de $_email' : ''} y volverás '
            'al inicio para entrar con otra cuenta.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cambiar de cuenta')),
        ],
      ),
    );
    if (ok != true || _signingOut) return;
    setState(() => _signingOut = true);
    await deleteCurrentToken(); // best-effort (ya trae su try/catch)
    try {
      await GoogleSignIn(serverClientId: AppConfig.googleWebClientId).signOut();
    } catch (e) {
      // Si Google falla, la sesión de Supabase debe cerrarse igual.
      debugPrint('GoogleSignIn.signOut falló (no bloqueante): $e');
    }
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      // El signOut local ya limpió la sesión antes de la llamada de red; si esa
      // falla (p.ej. "connection reset" al perder señal) NO es un error real.
      debugPrint('auth.signOut red falló (no bloqueante): $e');
    }
    // El redirect a /login lo dispara el router al detectar el signOut; si por
    // algo seguimos montados (no navegó), soltamos el estado de carga.
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget card(IconData icon, String title, String body, String cta, String route) =>
        JayaloCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(20),
          onTap: _signingOut ? null : () => context.go(route),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 28, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body),
            const SizedBox(height: 12),
            Text('$cta →',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          // Cabecera de sesión: correo actual + cambiar de cuenta. Antes no había
          // salida en esta pantalla si elegías el email equivocado (pedido PO).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.account_circle_outlined,
                  size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _email != null ? 'Estás como $_email' : 'Sesión iniciada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              _signingOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _changeAccount,
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 36)),
                      child: const Text('Cambiar de cuenta'),
                    ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('¿Cómo quieres usar Jayalo?',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Para terminar tu registro, elige cómo vas a usar la plataforma.'),
          const SizedBox(height: 24),
          card(
              Icons.shopping_bag_outlined,
              'Quiero pedir',
              'Pido productos o servicios y recibo ofertas de proveedores cerca de mí.',
              'Continuar como consumidor',
              '/onboarding/consumer'),
          const SizedBox(height: 16),
          card(
              Icons.storefront_outlined,
              'Quiero ofrecer',
              'Tengo un negocio y quiero recibir solicitudes para ofrecer mis productos o servicios.',
              'Continuar como proveedor',
              '/onboarding/provider'),
        ]),
      ),
    );
  }
}
