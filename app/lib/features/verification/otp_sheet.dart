import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/repos.dart';
import '../shared/jayalo_loader.dart';

/// Hoja compartida de verificación por OTP (spec §6.2). Envía el código al
/// abrir; copy SIEMPRE dice SMS (el canal real es app_settings.otp_channel,
/// hoy 'sms' — no prometer WhatsApp). Devuelve true si quedó verificado.
Future<bool> showOtpSheet(BuildContext context,
    {required String phone, String? businessId}) async {
  if (phone.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tu cuenta no tiene un número de WhatsApp guardado.')));
    return false;
  }
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _OtpSheet(phone: phone, businessId: businessId),
  );
  return ok == true;
}

class _OtpSheet extends StatefulWidget {
  const _OtpSheet({required this.phone, this.businessId});
  final String phone;
  final String? businessId;

  @override
  State<_OtpSheet> createState() => _OtpSheetState();
}

class _OtpSheetState extends State<_OtpSheet> {
  final _code = TextEditingController();
  bool _sending = true;
  bool _verifying = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;
  String _channel = 'sms'; // lo confirma send-otp; el copy lo sigue

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final channel = await sendOtp(phone: widget.phone, businessId: widget.businessId);
      if (mounted) setState(() => _channel = channel);
      _startCountdown();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final res =
          await verifyOtp(code: _code.text.trim(), businessId: widget.businessId);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.businessBadgeVerified
              ? '✓ WhatsApp confirmado — tu negocio ya muestra el sello.'
              : '✓ WhatsApp confirmado.')));
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canVerify =
        !_sending && !_verifying && RegExp(r'^\d{6}$').hasMatch(_code.text.trim());
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirma tu número', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          // El canal lo dice send-otp (app_settings.otp_channel). Con SMS hay
          // que ser EXPLÍCITO: el usuario espera el mensaje en WhatsApp porque
          // lo que verifica es su WhatsApp (feedback del PO en el E2E).
          Text(_sending
              ? 'Enviando el código…'
              : _channel == 'whatsapp'
                  ? 'Te enviamos un código por WhatsApp al ${widget.phone}.'
                  : 'Te enviamos un código por mensaje de texto (SMS) al '
                      '${widget.phone}.\nOjo: llega como SMS, no por WhatsApp.'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            enabled: !_sending,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: '',
              hintText: '······',
              errorText: _error,
              errorMaxLines: 3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) {
              if (canVerify) _verify();
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: canVerify ? _verify : null,
            child: _verifying
                ? const JayaloSpinner(size: 18)
                : const Text('Verificar'),
          ),
          TextButton(
            onPressed: (_resendIn > 0 || _sending) ? null : _send,
            child: Text(_resendIn > 0
                ? 'Reenviar código (${_resendIn}s)'
                : 'Reenviar código'),
          ),
        ],
      ),
    );
  }
}
