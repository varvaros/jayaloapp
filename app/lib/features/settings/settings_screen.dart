import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/session_state.dart';
import '../../core/theme_store.dart';
import '../../data/repos.dart';
import '../../push/push_service.dart';
import '../chat/widgets/bubbles.dart' show chatPalette;
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';
import '../verification/id_doc_sheet.dart';
import '../verification/otp_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _verified;
  Map<String, dynamic>? _biz;
  bool _hasIdDoc = false;
  bool? _waReveal; // preferencia de contacto (WhatsApp vs solo chat)
  bool _savingWa = false;

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
    try {
      final wa = await whatsappRevealEnabled();
      if (mounted) setState(() => _waReveal = wa);
    } catch (_) {/* best-effort */}
    if (roleStore.value == RoleState.provider) {
      try {
        final biz = await myBusinessForVerification();
        final docs =
            biz != null ? await hasIdDoc(biz['id'] as String) : false;
        if (mounted) {
          setState(() {
            _biz = biz;
            _hasIdDoc = docs;
          });
        }
      } catch (_) {
        // Nudge best-effort: sin red no se muestran las filas de verificación.
      }
    }
  }

  /// Validar negocio (informal/técnico): subir la cédula. Cierra el bloqueo de
  /// `enforce_business_can_offer` — sin cédula no se puede ofertar.
  Future<void> _validateBusiness() async {
    final biz = _biz;
    if (biz == null) return;
    final saved =
        await showIdDocSheet(context, businessId: biz['id'] as String);
    if (saved) _load();
  }

  /// Validar RNC (negocio formal): confirmar/editar el número (decisión PO
  /// 2026-07-20: solo el número, sin documento). Update directo a la tabla.
  Future<void> _validateRnc() async {
    final biz = _biz;
    if (biz == null) return;
    final ctrl = TextEditingController(text: (biz['rnc'] as String?) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validar RNC'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'RNC del negocio'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final rnc = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    if (rnc.isEmpty) {
      _snack('Escribe tu RNC.');
      return;
    }
    try {
      await updateRnc(biz['id'] as String, rnc);
      if (!mounted) return;
      _snack('RNC guardado.');
      _load();
    } catch (_) {
      if (mounted) _snack('No se pudo guardar el RNC.');
    }
  }

  Future<void> _setWaReveal(bool v) async {
    setState(() {
      _waReveal = v;
      _savingWa = true;
    });
    try {
      await setWhatsappRevealEnabled(v);
    } catch (_) {
      if (mounted) {
        setState(() => _waReveal = !v); // revertir
        _snack('No se pudo guardar tu preferencia.');
      }
    } finally {
      if (mounted) setState(() => _savingWa = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      // El signOut local ya limpió la sesión antes de la llamada de red; si esa
      // falla (p.ej. "connection reset" al perder señal) NO es un error real.
      debugPrint('auth.signOut red falló (no bloqueante): $e');
    }
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
      // Fondo lila del chat (pedido PO 2026-07-23): el mismo panel del chat
      // detrás de las tarjetas — se adapta solo a oscuro (chatPalette ya trae
      // su variante). Las tarjetas (JayaloCard) NO cambian.
      backgroundColor: chatPalette(context).panel,
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
        // Validar negocio (cédula) — solo informal/técnico; es lo que destraba
        // el envío de ofertas (enforce_business_can_offer).
        if (isProvider &&
            (_biz?['business_type'] == 'informal' ||
                _biz?['business_type'] == 'tecnico'))
          _hasIdDoc
              ? _SettingsRow(
                  icon: Icons.verified,
                  iconColor: green,
                  title: _biz?['identity_verified_at'] != null
                      ? 'Negocio verificado ✓'
                      : 'Cédula enviada (en revisión)',
                  subtitle: 'Toca para actualizar tu cédula',
                  onTap: _validateBusiness,
                )
              : _SettingsRow(
                  icon: Icons.badge_outlined,
                  title: 'Validar negocio (subir cédula)',
                  subtitle: 'Necesaria para poder enviar ofertas',
                  onTap: _validateBusiness,
                ),
        // Validar RNC — solo negocio formal (confirmar/editar el número).
        if (isProvider && _biz?['business_type'] == 'formal')
          _SettingsRow(
            icon: (_biz?['rnc'] as String?)?.trim().isNotEmpty == true
                ? Icons.verified_user_outlined
                : Icons.badge_outlined,
            iconColor: _biz?['business_verified_at'] != null ? green : null,
            title: 'Validar RNC',
            subtitle: (_biz?['rnc'] as String?)?.trim().isNotEmpty == true
                ? 'RNC: ${_biz!['rnc']} · toca para editar'
                : 'Confirma el RNC de tu negocio',
            onTap: _validateRnc,
          ),
        // Preferencia de contacto (pedido PO 2026-07-22, paridad web): el
        // usuario decide si los proveedores pueden contactarlo por WhatsApp o
        // SOLO por el chat de Jayalo. Con los mismos warnings de la web.
        if (_waReveal != null) ...[
          const SectionHeader(text: 'Cómo quieren contactarte'),
          _WaPreferenceCard(
            enabled: _waReveal!,
            saving: _savingWa,
            onChanged: _savingWa ? null : _setWaReveal,
          ),
        ],
        const SectionHeader(text: 'Apariencia'),
        const _DarkModeRow(),
        const SectionHeader(text: 'Chat'),
        _SettingsRow(
          icon: Icons.quickreply_outlined,
          title: 'Respuestas rápidas',
          subtitle: 'Edita, agrega o reordena tus mensajes predeterminados',
          onTap: () => context.push('/settings/quick-replies'),
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

/// Tarjeta de preferencia de contacto: toggle WhatsApp/chat + el warning de la
/// web según el estado (pedido PO 2026-07-22).
class _WaPreferenceCard extends StatelessWidget {
  const _WaPreferenceCard({
    required this.enabled,
    required this.saving,
    required this.onChanged,
  });
  final bool enabled;
  final bool saving;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final warnBg = dark ? const Color(0x33F2B705) : const Color(0xFFFFF3D6);
    final warnInk = dark ? const Color(0xFFF2CF7A) : const Color(0xFF8A5A00);
    return JayaloCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(enabled ? Icons.chat : Icons.forum_outlined,
                size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contacto por WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    enabled
                        ? 'Los proveedores que aceptes pueden escribirte por WhatsApp.'
                        : 'Los proveedores solo podrán escribirte por el chat de Jayalo.',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: warnBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 16, color: warnInk),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  enabled
                      ? 'Al compartir tu WhatsApp, el proveedor puede escribirte fuera de Jayalo. '
                          'Si prefieres mantener todo dentro de la app, desactívalo.'
                      : 'Con WhatsApp desactivado no se comparte tu número: toda la conversación '
                          'queda en el chat de Jayalo, con respaldo.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: warnInk)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Toggle de modo oscuro (pedido PO 2026-07-23). Misma anatomía del kit que
/// [_SettingsRow] pero con un Switch a la derecha; escucha [themeStore] para
/// reflejar el estado y lo escribe al cambiar (persistencia + repintado global
/// los maneja el store).
class _DarkModeRow extends StatelessWidget {
  const _DarkModeRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return JayaloCard(
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.dark_mode_outlined, size: 20, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Modo oscuro',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('Tema oscuro para toda la app',
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeStore,
          builder: (_, mode, _) => Switch(
            value: mode == ThemeMode.dark,
            onChanged: (v) => themeStore.setDark(v),
          ),
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
