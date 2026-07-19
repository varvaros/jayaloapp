import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

/// Lavanda del fondo horneado en la imagen de bienvenida — se usa como color
/// del Scaffold para que, si el recorte de `cover` deja algún borde, funda con
/// la imagen en vez de mostrar el fondo del tema.
const _welcomeBg = Color(0xFFF0ECFB);
const _welcomeInk = Color(0xFF1C1533);

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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: _welcomeBg,
      body: Stack(
        children: [
          // El hero de bienvenida es la imagen que hizo el PO (wordmark,
          // titular, subtítulo, mascota 3D, íconos y sombra ya horneados). Se
          // ancla arriba para que el titular quede siempre visible; el recorte
          // de `cover` cae en el espacio inferior, donde va el botón.
          Positioned.fill(
            child: Image.asset(
              'assets/images/welcome.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          // Botón de Google sobre el espacio inferior de la imagen.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _go,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        icon: _busy
                            ? const JayaloSpinner(size: 18, color: Colors.white)
                            : const Icon(Icons.g_mobiledata, size: 26),
                        label: const Text('Continuar con Google'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // El registro es NATIVO desde el onboarding (spec
                    // 2026-07-16): mandar a jayalo.com sería mentirle al
                    // usuario nuevo.
                    Text(
                      '¿Primera vez? Entra con Google y creamos tu cuenta al momento.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: _welcomeInk.withValues(alpha: .55)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
