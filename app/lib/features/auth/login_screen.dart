import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config.dart';
import '../../core/turnstile.dart';

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Jayalo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Pide lo que buscas. Los proveedores te ofertan.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: _busy ? null : _go,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Continuar con Google'),
              ),
              const SizedBox(height: 12),
              Text('¿Cuenta nueva? Regístrate en jayalo.com',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
