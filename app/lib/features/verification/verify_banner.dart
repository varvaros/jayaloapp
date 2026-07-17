import 'package:flutter/material.dart';
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
    return MaterialBanner(
      content: const Text(
          'Confirma tu número (te llega un código por SMS): las solicitudes verificadas '
          'generan más confianza y reciben más ofertas.'),
      leading: const Icon(Icons.verified_outlined),
      actions: [
        TextButton(onPressed: _verify, child: const Text('Confirmar ahora')),
        TextButton(
            onPressed: () => setState(() => _dismissed = true),
            child: const Text('Ahora no')),
      ],
    );
  }
}
