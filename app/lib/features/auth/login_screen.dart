import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/turnstile.dart';
import '../shared/jayalo_loader.dart';
import 'drifting_iso_pattern.dart';

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

// Lavanda del hero y tinta oscura del titular. El texto va en la tipografía de
// la app, sin negritas (w500, como una app a mitad de rediseño cálido). El
// acento es el violeta FIJO de marca (no `cs.primary`, que en modo oscuro se
// iría al azul) — la bienvenida es siempre este hero claro.
const _welcomeBg = Color(0xFFEDE9FA);
const _welcomeInk = Color(0xFF2A2350);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

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
    return Scaffold(
      backgroundColor: _welcomeBg,
      body: Stack(
        children: [
          // Patrón animado de isotipos tenues que deriva despacio.
          const Positioned.fill(child: DriftingIsoPattern(bg: _welcomeBg)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Wordmark.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const JayaloMascot(size: 24),
                      const SizedBox(width: 8),
                      const Text('Jayalo',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: _welcomeInk)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Titular — tipografía de la app, peso medio (nunca bold),
                  // "idea" en el violeta fijo de marca.
                  Text.rich(
                    TextSpan(children: const [
                      TextSpan(text: 'Todo empieza\ncon una '),
                      TextSpan(
                          text: 'idea',
                          style: TextStyle(color: JayaloColors.primary)),
                      TextSpan(text: '.'),
                    ]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 33,
                        height: 1.12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -.2,
                        color: _welcomeInk),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Describe lo que necesitas y deja que los mejores '
                    'proveedores encuentren la solución.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                        color: _welcomeInk.withValues(alpha: .64)),
                  ),
                  // La mascota 3D (recorte transparente) flotando en el centro.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/images/mascot.png', width: 230),
                            const SizedBox(height: 12),
                            Container(
                              width: 150,
                              height: 16,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                      color: JayaloColors.primary
                                          .withValues(alpha: .16),
                                      blurRadius: 34,
                                      spreadRadius: 2),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _go,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: JayaloColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      icon: _busy
                          ? const JayaloSpinner(size: 18, color: Colors.white)
                          : const Icon(Icons.g_mobiledata, size: 26),
                      label: const Text('Continuar con Google'),
                    ),
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
                        fontWeight: FontWeight.w400,
                        color: _welcomeInk.withValues(alpha: .55)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
