import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart';
import '../../push/push_service.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';
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
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? JayaloColors.dSuccess : JayaloColors.success;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final isProvider = roleStore.value == RoleState.provider;
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            onTap: () => context.pop(),
          ),
          title: 'Ajustes',
          titleAlign: HeaderTitleAlign.center,
        ),
        Expanded(
          child: ListView(
              padding: EdgeInsets.only(
                  top: 8, bottom: 8 + navBarReservedSpace(context)),
              children: [
            const SectionHeader(text: 'Tu cuenta'),
        _SettingsRow(icon: Icons.person_outline, title: email),
        if (_verified == false)
          _SettingsRow(
            icon: Icons.verified_outlined,
            title: 'Confirmar mi cuenta',
            subtitle: 'Te enviamos un código por mensaje de texto (SMS)',
            onTap: _verifyPersonal,
          ),
        if (_verified == true)
          _SettingsRow(
            icon: Icons.verified,
            iconColor: green,
            title: 'WhatsApp confirmado ✓',
          ),
        if (isProvider)
          _SettingsRow(
            icon: Icons.storefront_outlined,
            title: 'Sello de WhatsApp del negocio',
            subtitle: 'Confirma el número que ven tus clientes',
            onTap: _verifyBusiness,
          ),
        const SectionHeader(text: 'Información'),
        _SettingsRow(
          icon: Icons.description_outlined,
          title: 'Términos y privacidad',
          onTap: () => launchUrl(Uri.parse('https://jayalo.com/terminos'),
              mode: LaunchMode.externalApplication),
        ),
        const SectionHeader(text: 'Sesión'),
        _SettingsRow(
          icon: Icons.logout,
          iconColor: cs.error,
          titleColor: cs.error,
          title: 'Cerrar sesión',
          onTap: _signOut,
        ),
          ]),
        ),
      ]),
    );
  }
}

/// Fila de ajustes con la anatomía del kit: ícono en contenedor 40×40 al 14%,
/// título y subtítulo opcionales, todo dentro de una tarjeta neutra.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ic = iconColor ?? cs.primary;
    return JayaloCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ic.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: ic),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: titleColor ?? cs.onSurface)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 20, color: cs.outline),
        ],
      ),
    );
  }
}
