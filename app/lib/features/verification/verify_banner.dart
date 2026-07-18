import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../data/repos.dart';
import 'otp_sheet.dart';

/// Banner cerrable (decisión PO 2026-07-16, spec §6.1): nudge de verificación
/// al crear solicitud. NO bloquea. Cerrarlo solo lo oculta en esta pantalla;
/// reaparece en la próxima solicitud (estado local, sin persistir).
class VerifyWhatsappBanner extends StatefulWidget {
  const VerifyWhatsappBanner({super.key});
  @override
  State<VerifyWhatsappBanner> createState() => _VerifyWhatsappBannerState();
}

class _VerifyWhatsappBannerState extends State<VerifyWhatsappBanner> {
  bool _dismissed = false;
  bool? _verified;

  @override
  void initState() {
    super.initState();
    whatsappVerified().then((v) {
      if (mounted) setState(() => _verified = v);
    }).catchError((_) {
      // Con error de red no se molesta al usuario: el banner es un nudge.
      if (mounted) setState(() => _verified = true);
    });
  }

  Future<void> _verify() async {
    final p = await myProfile();
    if (!mounted) return;
    final ok = await showOtpSheet(context, phone: (p?['phone'] as String?) ?? '');
    if (ok && mounted) setState(() => _verified = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _verified != false) return const SizedBox.shrink();
    // Tinte "pendiente" (ámbar suave): es un nudge, no una alerta.
    final tone = Theme.of(context).brightness == Brightness.dark
        ? JayaloStatus.pendingDark
        : JayaloStatus.pendingLight;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_outlined, size: 20, color: tone.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Confirma tu número (te llega un código por SMS): las '
                    'solicitudes verificadas generan más confianza y reciben '
                    'más ofertas.',
                    style: TextStyle(fontSize: 13, color: tone.ink)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => setState(() => _dismissed = true),
                  style: TextButton.styleFrom(foregroundColor: tone.ink),
                  child: const Text('Ahora no')),
              TextButton(
                  onPressed: _verify,
                  style: TextButton.styleFrom(
                      foregroundColor: tone.ink,
                      textStyle:
                          const TextStyle(fontWeight: FontWeight.w700)),
                  child: const Text('Confirmar ahora')),
            ],
          ),
        ],
      ),
    );
  }
}
