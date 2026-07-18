import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../data/repos.dart';
import '../../domain/pricing.dart';
import '../../domain/recharge.dart';
import '../client/request_status_screen.dart' show offerPriceLabel;
import '../notifications/notification_bell.dart';
import '../shared/jayalo_loader.dart';

int estimatedUnlockCost(Map<String, dynamic> o) {
  final c = pointsForOffer(
    price: (o['price'] as num?)?.toDouble(),
    priceMin: (o['price_min'] as num?)?.toDouble(),
    priceMax: (o['price_max'] as num?)?.toDouble(),
    pricingMode: o['pricing_mode'] as String?,
    hourlyRate: (o['hourly_rate'] as num?)?.toDouble(),
    estimatedHours: (o['estimated_hours'] as num?)?.toDouble(),
  );
  return c < 1 ? 1 : c;
}

class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key});
  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _offers = [];
  int? _balance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver del navegador (recarga PayPal), refrescar el saldo (spec §6).
    if (state == AppLifecycleState.resumed) _refetch();
  }

  Future<void> _refetch() async {
    final results = await Future.wait([myOffers(), walletBalance()]);
    if (!mounted) return;
    setState(() {
      _offers = results[0] as List<Map<String, dynamic>>;
      _balance = results[1] as int?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final toUnlock = _offers
        .where((o) => o['status'] == 'accepted' && o['unlocked_at'] == null)
        .toList();
    final pending = _offers.where((o) => o['status'] == 'pending').toList();
    final rest = _offers
        .where((o) =>
            o['status'] == 'rejected' ||
            o['status'] == 'completed' ||
            (o['status'] == 'accepted' && o['unlocked_at'] != null))
        .toList();
    return Scaffold(
      appBar: AppBar(
          title: const Text('Mis ofertas'),
          actions: const [NotificationBell()]),
      body: _loading
          ? const JayaloLoaderBlock()
          : RefreshIndicator(
              onRefresh: _refetch,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text('${_balance ?? '—'} créditos',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: FilledButton.tonal(
                      onPressed: _openWallet,
                      child: const Text('Recargar'),
                    ),
                  ),
                ),
                if (toUnlock.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('🏆 ¡Te aceptaron! Desbloquea el contacto',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final o in toUnlock) _offerCard(o, highlight: true),
                ],
                const SizedBox(height: 16),
                Text('Pendientes (${pending.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                if (pending.isEmpty && toUnlock.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                          'Oferta desde "Solicitudes" — es gratis y te avisamos si te aceptan.')),
                for (final o in pending) _offerCard(o),
                const SizedBox(height: 16),
                if (rest.isNotEmpty)
                  Text('Historial', style: Theme.of(context).textTheme.titleMedium),
                for (final o in rest) _offerCard(o),
              ]),
            ),
    );
  }

  Widget _offerCard(Map<String, dynamic> o, {bool highlight = false}) {
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    final label = switch (st) {
      'accepted' => unlocked ? 'Desbloqueada' : 'ACEPTADA',
      'completed' => 'Completada',
      'rejected' => 'Rechazada',
      _ => 'Pendiente',
    };
    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.amber.shade700, width: 2))
          : null,
      child: ListTile(
        title: Text(o['request_title'] as String? ?? '',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${offerPriceLabel(o)} · $label'),
        trailing: highlight ? const Icon(Icons.lock_open) : null,
        onTap: () => _openOffer(o),
      ),
    );
  }

  void _openOffer(Map<String, dynamic> o) {
    final st = o['status'] as String;
    final unlocked = o['unlocked_at'] != null;
    if (st == 'accepted' && !unlocked) {
      _preUnlockCheck(o);
    } else if (unlocked || st == 'completed') {
      _showContactSheet(o);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

  /// ADR-0031: el pago SIEMPRE ocurre fuera de la app (navegador del sistema).
  /// Intenta abrir con un magic link autenticado (evita el segundo login);
  /// si falla, cae al link plano (el usuario puede necesitar loguearse ahí).
  Future<void> _openWallet() async {
    Uri target = Uri.parse(AppConfig.walletUrl);
    try {
      target = Uri.parse(await createWalletLoginLink());
    } catch (_) {}
    var ok = false;
    try {
      ok = await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      _snack('No se pudo abrir el navegador. Visita jayalo.com para recargar.');
    }
  }

  /// Paridad con la web (ProviderOffersSection.tsx:670): NUNCA cobrar si el
  /// contacto no es revelable (cliente sin WhatsApp verificado u opt-out).
  /// Es la barrera del bug de dinero 2026-07-16.
  Future<void> _preUnlockCheck(Map<String, dynamic> o) async {
    bool revealable;
    try {
      revealable = await canRevealOffer(o['id'] as String);
    } catch (_) {
      _snack('No pudimos comprobar el contacto. Revisa tu conexión e intenta de nuevo.');
      return;
    }
    if (!mounted) return;
    if (!revealable) {
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Contacto aún no disponible',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                    'Este cliente todavía no tiene su WhatsApp verificado, así que no se '
                    'puede desbloquear su contacto (y no se te cobraría nada). '
                    'Te avisaremos si lo confirma.'),
                const SizedBox(height: 16),
                FilledButton.tonal(
                    onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
              ]),
        ),
      );
      return;
    }
    _showUnlockSheet(o);
  }

  void _showUnlockSheet(Map<String, dynamic> o) {
    final cost = estimatedUnlockCost(o);
    final needsRecharge = shouldOfferRecharge(balance: _balance, cost: cost);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Desbloquear contacto',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                  'Costo: $cost crédito${cost == 1 ? '' : 's'} · Tu saldo: ${_balance ?? 0}'),
              const SizedBox(height: 16),
              if (needsRecharge)
                FilledButton(
                  onPressed: _openWallet,
                  child: const Text('Saldo insuficiente — Recargar'),
                )
              else
                _HoldToUnlockButton(onConfirmed: () async {
                  Navigator.pop(ctx);
                  final res = await unlockOffer(o['id'] as String, cost);
                  if (!mounted) return;
                  if (res.ok) {
                    await _refetch();
                    final refreshed = _offers.firstWhere(
                        (x) => x['id'] == o['id'],
                        orElse: () => o);
                    _showContactSheet(refreshed);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('No se pudo desbloquear. Intenta de nuevo.')));
                  }
                }),
            ]),
      ),
    );
  }

  Future<void> _showContactSheet(Map<String, dynamic> o) async {
    ({String? firstName, String? phone}) contact;
    try {
      contact = await unlockedContact(o['id'] as String);
    } catch (_) {
      if (!mounted) return;
      // Derecho YA pagado: jamás presentar un fallo como "no hay contacto"
      // (el catch silencioso aquí era el bug de dinero 2026-07-16).
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('No pudimos cargar el contacto',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Tu desbloqueo está guardado — no se te volverá a cobrar. '
                    'Revisa tu conexión e intenta de nuevo.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showContactSheet(o);
                  },
                  child: const Text('Reintentar'),
                ),
              ]),
        ),
      );
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('✅ Contacto desbloqueado',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(contact.phone != null
                  ? '${contact.firstName ?? 'Cliente'} · ${contact.phone}'
                  : 'El cliente no tiene WhatsApp verificado disponible; '
                      'contáctalo por el chat de jayalo.com.'),
              const SizedBox(height: 16),
              if (contact.phone != null)
                FilledButton.icon(
                  onPressed: () {
                    final digits = contact.phone!.replaceAll(RegExp(r'\D'), '');
                    launchUrl(Uri.parse('https://wa.me/$digits'),
                        mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('Abrir WhatsApp'),
                ),
              const SizedBox(height: 8),
              if (o['purchase_completed'] != true)
                OutlinedButton(
                  onPressed: () async {
                    await markPurchaseCompleted(o['id'] as String);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _refetch();
                  },
                  child: const Text('¿Se concretó la venta? Marcar completada'),
                ),
            ]),
      ),
    );
  }
}

/// Confirmación deliberada: mantener presionado ~1s (equivalente nativo del
/// hold-to-confirm de la web para acciones de dinero).
class _HoldToUnlockButton extends StatefulWidget {
  const _HoldToUnlockButton({required this.onConfirmed});
  final Future<void> Function() onConfirmed;
  @override
  State<_HoldToUnlockButton> createState() => _HoldToUnlockButtonState();
}

class _HoldToUnlockButtonState extends State<_HoldToUnlockButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onConfirmed();
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(alignment: Alignment.center, children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(26)),
          ),
          FractionallySizedBox(
            widthFactor: _c.value.clamp(0.001, 1),
            alignment: Alignment.centerLeft,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                  color: cs.primary, borderRadius: BorderRadius.circular(26)),
            ),
          ),
          IgnorePointer(
            child: Text('Mantén presionado para desbloquear',
                style: TextStyle(
                    color: _c.value > .45 ? cs.onPrimary : cs.onSurface,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}
