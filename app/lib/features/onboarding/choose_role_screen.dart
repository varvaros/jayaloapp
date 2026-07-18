import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/brand_kit.dart';

/// Selector de rol. Regla dura (lección choose-role.tsx:67-72 de la web):
/// elegir NO escribe account_type — solo el cierre de cada flujo lo persiste.
/// Quien abandona vuelve aquí sin residuo en la BD.
class ChooseRoleScreen extends StatelessWidget {
  const ChooseRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget card(IconData icon, String title, String body, String cta, String route) =>
        JayaloCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(20),
          onTap: () => context.go(route),
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
          const SizedBox(height: 24),
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
