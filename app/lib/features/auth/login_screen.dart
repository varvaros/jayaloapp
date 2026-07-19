import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
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

// Lavanda del fondo de la imagen (fallback del Scaffold) y tinta oscura del
// titular. El texto va en la tipografía de la app, sin negritas (w600 máximo,
// como los títulos de la app).
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
    // La bienvenida es SIEMPRE el hero lavanda claro — su acento es el violeta
    // fijo de marca, no `cs.primary` (que en modo oscuro del sistema se va al
    // azul del tema oscuro). Por eso se usa `JayaloColors.primary` directo.
    return Scaffold(
      backgroundColor: _welcomeBg,
      body: Stack(
        children: [
          // Fondo: la imagen del PO (mascota 3D + patrón de isotipos, sin
          // texto). El texto lo pone Flutter encima, en la tipografía de la app.
          Positioned.fill(
            child: Image.asset(
              'assets/images/welcome.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
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
                  const SizedBox(height: 26),
                  // Titular — tipografía de la app, peso semibold (nunca bold),
                  // "idea" en el violeta de acción.
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
                  // La mascota del fondo se ve en este espacio.
                  const Spacer(),
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
