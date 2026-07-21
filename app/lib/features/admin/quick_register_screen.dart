import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repos.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Registro rápido de proveedores (SOLO admin, pedido PO 2026-07-22): el admin
/// pone el correo y opcionalmente el nombre del negocio/WhatsApp/ciudad; se
/// envía una invitación por correo (edge function `admin-invite-provider`, que
/// reproduce el `inviteProvider` de la web). El proveedor completa el resto al
/// abrir el enlace.
class AdminQuickRegisterScreen extends StatefulWidget {
  const AdminQuickRegisterScreen({super.key});
  @override
  State<AdminQuickRegisterScreen> createState() =>
      _AdminQuickRegisterScreenState();
}

class _AdminQuickRegisterScreenState extends State<AdminQuickRegisterScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _whatsapp = TextEditingController();
  final _city = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_email, _name, _whatsapp, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      _toast('Escribe un correo válido.');
      return;
    }
    setState(() => _busy = true);
    try {
      await inviteProviderQuick(
        email: email,
        businessName: _name.text.trim(),
        whatsapp: _whatsapp.text.trim(),
        city: _city.text.trim(),
      );
      if (!mounted) return;
      for (final c in [_email, _name, _whatsapp, _city]) {
        c.clear();
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invitación enviada ✓'),
          content: Text(
              'Le enviamos a $email un correo para completar su registro como '
              'proveedor.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            onTap: () => context.pop(),
          ),
          title: 'Registro rápido',
          titleAlign: HeaderTitleAlign.center,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 16 + navBarReservedSpace(context)),
            children: [
              Text(
                  'Registra un proveedor por correo. Le llegará un enlace para '
                  'completar su negocio; lo demás es opcional.',
                  style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: filledField(context, 'Correo del proveedor *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration:
                    filledField(context, 'Nombre del negocio (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _whatsapp,
                keyboardType: TextInputType.phone,
                decoration: filledField(context, 'WhatsApp (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _city,
                decoration: filledField(context, 'Ciudad (opcional)'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_add_alt),
                label: Text(_busy ? 'Enviando…' : 'Enviar invitación'),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
