import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config.dart';
import '../../core/motion.dart';
import '../../core/turnstile.dart';
import '../shared/jayalo_loader.dart';

Future<void> signInWithGoogleNative(BuildContext context) async {
  final google = GoogleSignIn(serverClientId: AppConfig.googleWebClientId);
  final account = await google.signIn();
  if (account == null) throw Exception('Inicio de sesión cancelado');
  final auth = await account.authentication;
  final idToken = auth.idToken;
  if (idToken == null) throw Exception('Google no devolvió idToken');

  final supa = Supabase.instance.client.auth;
  try {
    await supa.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken);
  } on AuthException catch (e) {
    // CAPTCHA global de Supabase (ADR-0028): reintento con token Turnstile.
    if (!e.message.toLowerCase().contains('captcha')) rethrow;
    if (!context.mounted) rethrow;
    final captcha = await getTurnstileToken(context);
    await supa.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
        captchaToken: captcha);
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// Tintas propias del hero de bienvenida (fondo lavanda, no la arena de la app):
// un momento de marca antes de entrar. El titular va en un negro-violáceo muy
// oscuro y "idea" en el violeta de acción.
const _heroInk = Color(0xFF1C1533);
const _heroBgTop = Color(0xFFF0ECFB);
const _heroBgBottom = Color(0xFFFBFAFE);

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;

  // Flotación suave de la mascota (sube y baja ~8px). Se apaga con "reducir
  // animaciones".
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await signInWithGoogleNative(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo iniciar sesión: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_heroBgTop, _heroBgBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Wordmark: el isotipo + "Jayalo".
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const JayaloMascot(size: 26),
                    const SizedBox(width: 8),
                    Text('Jayalo',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: _heroInk)),
                  ],
                ),
                const SizedBox(height: 30),
                // Titular hero — EXCEPCIÓN deliberada a la tipografía ligera de
                // la app: un hero de bienvenida pide peso (mockup del PO).
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Todo empieza\ncon una '),
                    TextSpan(text: 'idea', style: TextStyle(color: cs.primary)),
                    const TextSpan(text: '.'),
                  ]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 40,
                      height: 1.06,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                      color: _heroInk),
                ),
                const SizedBox(height: 14),
                Text(
                  'Describe lo que necesitas y deja que los mejores '
                  'proveedores encuentren la solución.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15.5,
                      height: 1.5,
                      color: _heroInk.withValues(alpha: .62)),
                ),
                // La mascota flotando entre íconos tenues.
                Expanded(child: _Hero(float: _float)),
                FilledButton.icon(
                  onPressed: _busy ? null : _go,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  icon: _busy
                      ? const JayaloSpinner(size: 18, color: Colors.white)
                      : const Icon(Icons.g_mobiledata, size: 26),
                  label: const Text('Continuar con Google'),
                ),
                const SizedBox(height: 12),
                // El registro es NATIVO desde el onboarding (spec 2026-07-16):
                // mandar a jayalo.com sería mentirle al usuario nuevo.
                Text(
                    '¿Primera vez? Entra con Google y creamos tu cuenta al momento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: _heroInk.withValues(alpha: .5))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La mascota grande flotando + su sombra suave, entre íconos de marca muy
/// tenues (chat, ubicación, cámara, maletín, chispa) — como el mockup.
class _Hero extends StatelessWidget {
  const _Hero({required this.float});
  final Animation<double> float;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = JayaloMotion.reduced(context);
    Widget ghost(IconData icon, double size) =>
        Icon(icon, size: size, color: cs.primary.withValues(alpha: .12));

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Stack(
        alignment: Alignment.center,
        children: [
          // Íconos flotantes tenues alrededor de la mascota.
          Positioned(top: box.maxHeight * .10, left: w * .04,
              child: ghost(Icons.chat_bubble_outline, 30)),
          Positioned(top: box.maxHeight * .06, right: w * .10,
              child: ghost(Icons.location_on_outlined, 26)),
          Positioned(top: box.maxHeight * .42, left: 0,
              child: ghost(Icons.photo_camera_outlined, 30)),
          Positioned(top: box.maxHeight * .40, right: 0,
              child: ghost(Icons.work_outline, 28)),
          Positioned(bottom: box.maxHeight * .16, left: w * .16,
              child: ghost(Icons.location_on_outlined, 24)),
          Positioned(bottom: box.maxHeight * .14, right: w * .12,
              child: ghost(Icons.auto_awesome_outlined, 28)),
          // Mascota + sombra.
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: float,
                builder: (context, child) {
                  final dy = reduced ? 0.0 : math.sin(float.value * math.pi) * -8;
                  return Transform.translate(offset: Offset(0, dy), child: child);
                },
                child: const JayaloMascot(size: 168, semanticsLabel: 'Jayalo'),
              ),
              const SizedBox(height: 26),
              // Sombra suave bajo la mascota.
              Container(
                width: 132,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                        color: cs.primary.withValues(alpha: .22),
                        blurRadius: 34,
                        spreadRadius: 2),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}
