import 'package:flutter/material.dart';
import '../../core/session_state.dart';
import '../shared/jayalo_loader.dart';

/// Splash post-login: resuelve el rol una vez; el redirect del router hace el
/// resto (spec §4). Con error de red: reintentar, nunca dejar pasar sin rol.
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await roleStore.refresh();
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos cargar tu cuenta.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: _error == null
              ? const JayaloLoader()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Reintentar')),
                ]),
        ),
      );
}
