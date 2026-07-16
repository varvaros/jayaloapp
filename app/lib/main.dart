import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/ai_client.dart';
import 'core/config.dart';
import 'core/turnstile.dart';
import 'features/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey);
  runApp(const JayaloApp(home: _SpikeScreen()));
}

/// Pantalla TEMPORAL de spikes (Tasks 4-6 del plan). Se elimina en Task 7.
class _SpikeScreen extends StatefulWidget {
  const _SpikeScreen();
  @override
  State<_SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<_SpikeScreen> {
  String _status = 'Jayalo v1 — spikes';

  void _set(String s) => setState(() => _status = s);

  Future<void> _testTurnstile() async {
    _set('Obteniendo token Turnstile…');
    try {
      final token = await getTurnstileToken(context);
      _set('SPIKE 1 OK — token: ${token.substring(0, 20)}…');
    } catch (e) {
      _set('SPIKE 1 FALLÓ: $e');
    }
  }

  Future<void> _testLogin() async {
    _set('Login con Google…');
    try {
      await signInWithGoogleNative(context);
      final email = Supabase.instance.client.auth.currentUser?.email;
      _set('SPIKE 2 OK — sesión: $email');
    } catch (e) {
      _set('SPIKE 2 FALLÓ: $e');
    }
  }

  Future<void> _testAi() async {
    _set('Primer turno IA (Turnstile + POST)…');
    try {
      final token = await getTurnstileToken(context);
      final turn = await AiClient().sendTurn(
        messages: const [AiMessage('user', 'Busco una llave de paso de 1/2 pulgada')],
        kind: 'producto',
        turnstileToken: token,
      );
      _set('SPIKE 3 OK — turno: ${turn.runtimeType}');
    } catch (e) {
      _set('SPIKE 3 FALLÓ: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: _testTurnstile,
                  child: const Text('Spike 1: token Turnstile')),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: _testLogin,
                  child: const Text('Spike 2: login Google nativo')),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: _testAi, child: const Text('Spike 3: primer turno IA')),
            ]),
          ),
        ),
      );
}
