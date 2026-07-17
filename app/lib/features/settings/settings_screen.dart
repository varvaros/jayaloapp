import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart';
import '../../push/push_service.dart';
import '../verification/otp_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _verified;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await whatsappVerified();
      if (mounted) setState(() => _verified = v);
    } catch (_) {
      // Sin red: la fila simplemente no se muestra hasta reabrir.
    }
  }

  Future<void> _verifyPersonal() async {
    final p = await myProfile();
    if (!mounted) return;
    final ok = await showOtpSheet(context, phone: (p?['phone'] as String?) ?? '');
    if (ok) _load();
  }

  /// Cerrar sesión de VERDAD: hay que cerrar también la de Google, no solo la
  /// de Supabase. El SDK de Google cachea la cuenta y `signIn()` la reutiliza
  /// en silencio → el siguiente login entraba con la MISMA cuenta y no se podía
  /// cambiar de usuario (en un teléfono compartido, además, "cerrar sesión" no
  /// protegía nada). Verificado en el device 2026-07-17.
  Future<void> _signOut() async {
    await deleteCurrentToken(); // best-effort (ya trae su try/catch)
    try {
      await GoogleSignIn(serverClientId: AppConfig.googleWebClientId).signOut();
    } catch (e) {
      // Si Google falla, la sesión de Supabase debe cerrarse igual.
      debugPrint('GoogleSignIn.signOut falló (no bloqueante): $e');
    }
    await Supabase.instance.client.auth.signOut();
  }

  /// Sello del negocio (spec §7.4): OTP con business_id — espeja el badge si
  /// el número verificado es el público del negocio (semántica web).
  Future<void> _verifyBusiness() async {
    final bizId = await myBusinessId();
    if (bizId == null) return;
    final biz = await supa
        .from('provider_businesses')
        .select('whatsapp')
        .eq('id', bizId)
        .maybeSingle();
    if (!mounted) return;
    await showOtpSheet(context,
        phone: (biz?['whatsapp'] as String?) ?? '', businessId: bizId);
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final isProvider = roleStore.value == RoleState.provider;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.person_outline), title: Text(email)),
        if (_verified == false)
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Confirmar mi cuenta'),
            subtitle: const Text('Te enviamos un código por mensaje de texto (SMS)'),
            onTap: _verifyPersonal,
          ),
        if (_verified == true)
          const ListTile(
            leading: Icon(Icons.verified, color: Colors.green),
            title: Text('WhatsApp confirmado ✓'),
          ),
        if (isProvider)
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Sello de WhatsApp del negocio'),
            subtitle: const Text('Confirma el número que ven tus clientes'),
            onTap: _verifyBusiness,
          ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Términos y privacidad'),
          onTap: () => launchUrl(Uri.parse('https://jayalo.com/terminos'),
              mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          onTap: _signOut,
        ),
      ]),
    );
  }
}
