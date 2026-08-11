import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/turnstile.dart';
import '../shared/jayalo_loader.dart';
import 'portada_animada.dart';

/// El usuario cerró el selector de cuenta de Google. No es un fallo: no hay que
/// enseñarle ningún error.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

Future<void> signInWithGoogleNative(BuildContext context) async {
  final google = GoogleSignIn(serverClientId: AppConfig.googleWebClientId);
  final account = await google.signIn();
  if (account == null) throw const SignInCancelled();
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

/// Entra con correo y contraseña (las cuentas creadas en jayalo.com).
///
/// La app SOLO tenía Google, así que quien se registraba en la web con un
/// correo que no fuera de Google se quedaba fuera (2026-08-10). El registro
/// sigue siendo nativo por Google: esto es únicamente una puerta de entrada
/// para cuentas que ya existen.
///
/// Mismo reintento con Turnstile que el login de Google: el CAPTCHA global de
/// Supabase (ADR-0028) también aplica a esta vía.
Future<void> signInWithPasswordNative(
    BuildContext context, String email, String password) async {
  final supa = Supabase.instance.client.auth;
  try {
    await supa.signInWithPassword(email: email, password: password);
  } on AuthException catch (e) {
    if (!e.message.toLowerCase().contains('captcha')) rethrow;
    if (!context.mounted) rethrow;
    final captcha = await getTurnstileToken(context);
    await supa.signInWithPassword(
        email: email, password: password, captchaToken: captcha);
  }
}

/// Traduce un fallo de [signInWithPasswordNative] a algo accionable. Pura y
/// pública para fijarla en un test: el mensaje crudo de Supabase llega en
/// inglés ("Invalid login credentials") y no le dice al usuario qué hacer.
String passwordLoginError(Object e) {
  final m = e is AuthException ? e.message.toLowerCase() : '';
  if (m.contains('invalid login credentials') || m.contains('invalid_credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (m.contains('email not confirmed')) {
    return 'Confirma tu correo desde el enlace que te enviamos y vuelve a entrar.';
  }
  if (m.contains('too many') || m.contains('rate limit')) {
    return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
  }
  return 'No pudimos entrar. Revisa tu conexión e inténtalo de nuevo.';
}

// Fondo de la bienvenida: el cielo/mar de la portada animada. Los textos van
// en blanco sobre el agua; el CTA mantiene el violeta FIJO de marca (no
// `cs.primary`, que en modo oscuro se iría al azul).
const _welcomeSea = Color(0xFF1B7ECB);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _openPasswordSheet() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: const _PasswordLoginSheet(),
        ),
      );

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await signInWithGoogleNative(context);
    } on SignInCancelled {
      // Sin ruido: cerrar el selector de cuenta es una decisión del usuario.
    } catch (e) {
      // Nada de `$e` crudo: esta es la ÚNICA puerta de entrada de la app, y el
      // usuario leía cosas como `PlatformException(sign_in_failed, ...
      // ApiException: 10...)`, que no le dicen qué hacer. El detalle va al log
      // de desarrollo; a la pantalla va un mensaje accionable.
      if (kDebugMode) debugPrint('[login] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No pudimos iniciar sesión. Revisa tu conexión e inténtalo de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _welcomeSea,
      body: Stack(
        children: [
          // El loop de la isla de Jayi a pantalla completa. El mar bajo la
          // isla viene limpio del mockup a propósito: es la zona de botones.
          const Positioned.fill(child: PortadaAnimada()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                        color: Colors.white.withValues(alpha: .8)),
                  ),
                  // Puerta para las cuentas creadas en jayalo.com con correo y
                  // contraseña: sin esto quedaban fuera de la app si su correo
                  // no era de Google (2026-08-10).
                  TextButton(
                    onPressed: _busy ? null : _openPasswordSheet,
                    child: Text(
                      'Entrar con correo y contraseña',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: .95)),
                    ),
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

/// Hoja de "entrar con correo y contraseña". SOLO inicia sesión: crear cuenta
/// sigue siendo Google + onboarding nativo, así que aquí no hay registro ni
/// se promete uno. Al entrar, el router redirige solo (misma sesión de
/// Supabase que con Google).
class _PasswordLoginSheet extends StatefulWidget {
  const _PasswordLoginSheet();

  @override
  State<_PasswordLoginSheet> createState() => _PasswordLoginSheetState();
}

class _PasswordLoginSheetState extends State<_PasswordLoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _email.text.trim().contains('@') && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signInWithPasswordNative(
          context, _email.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (kDebugMode) debugPrint('[login-password] $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = passwordLoginError(e);
        });
      }
    }
  }

  InputDecoration _field(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF3F1FA),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Entra con tu correo',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: jayaloHead(context))),
          const SizedBox(height: 6),
          Text(
            'Para las cuentas creadas en jayalo.com. Si entraste con Google, '
            'usa el botón de Google.',
            style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: _field('Correo electrónico'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _hide,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: _field(
              'Contraseña',
              suffix: IconButton(
                icon: Icon(_hide
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: (_canSubmit && !_busy) ? _submit : null,
            child: _busy
                ? const JayaloSpinner(size: 18, color: Colors.white)
                : const Text('Entrar'),
          ),
          const SizedBox(height: 10),
          Text(
            '¿Olvidaste tu contraseña? Recupérala en jayalo.com.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
