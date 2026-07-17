import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart';
import '../../domain/onboarding_errors.dart';
import '../../domain/phone.dart';

/// Alta de consumidor (spec §6): nombre precargado de las claims de Google,
/// WhatsApp SIN OTP (decisión PO §10.1 — el OTP se dispara después, §6.1),
/// ubicación GPS opcional + dirección obligatoria, términos. Una sola
/// escritura al final (upsert de profiles, atómico por naturaleza).
class ConsumerOnboardingScreen extends StatefulWidget {
  const ConsumerOnboardingScreen({super.key});
  @override
  State<ConsumerOnboardingScreen> createState() => _ConsumerOnboardingScreenState();
}

class _ConsumerOnboardingScreenState extends State<ConsumerOnboardingScreen> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  final _phone = TextEditingController();
  final _address = TextEditingController();
  double? _lat, _lng;
  bool _locating = false;
  bool _terms = false;
  bool _busy = false;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    final meta = supa.auth.currentUser?.userMetadata ?? {};
    final full = ((meta['full_name'] ?? meta['name']) as String? ?? '').trim();
    final parts = full.split(RegExp(r'\s+'));
    _first = TextEditingController(
        text: (meta['given_name'] ?? meta['first_name']) as String? ??
            (parts.isNotEmpty ? parts.first : ''));
    _last = TextEditingController(
        text: (meta['family_name'] ?? meta['last_name']) as String? ??
            (parts.length > 1 ? parts.sublist(1).join(' ') : ''));
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _checkPhone() async {
    final raw = _phone.text.trim();
    if (raw.isEmpty) return;
    if (!isValidPhone(raw)) {
      setState(() => _phoneError = 'Escribe un número válido (ej. 809-555-1234).');
      return;
    }
    setState(() => _phoneError = null);
    try {
      final digits = normalizePhone(raw).replaceAll(RegExp(r'\D'), '');
      if (await isWhatsappTakenRemote(digits) && mounted) {
        setState(() => _phoneError =
            'Este WhatsApp ya está registrado en otra cuenta. Usa otro número o inicia sesión con esa cuenta.');
      }
    } catch (_) {
      // Pre-chequeo de UX: si falla, el upsert final valida igual (23505).
    }
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _snack('Sin permiso de ubicación — puedes escribir tu dirección igual.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {
      _snack('No pudimos captar tu ubicación — puedes escribir tu dirección igual.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool get _valid =>
      _first.text.trim().isNotEmpty &&
      isValidPhone(_phone.text) &&
      _phoneError == null &&
      _address.text.trim().isNotEmpty &&
      _terms;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await completeConsumerProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        whatsapp: normalizePhone(_phone.text),
        address: _address.text.trim(),
        lat: _lat,
        lng: _lng,
        termsVersion: AppConfig.termsVersion,
      );
      await roleStore.refresh(); // → redirect a /client
    } catch (e) {
      if (mounted) {
        _snack(onboardingErrorCopy(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Igual que en el alta de proveedor: el ATRÁS del sistema vuelve al
    // selector dentro de la app, no minimiza Jayalo (que con MIUI equivale a
    // perder el formulario).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/onboarding');
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Tu cuenta'),
        leading: BackButton(onPressed: () => context.go('/onboarding')),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Así te llamas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _first,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Apellido'),
          ),
          const SizedBox(height: 24),
          Text('Tu WhatsApp', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Los proveedores te contactan por aquí cuando aceptas una oferta.'),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Número de WhatsApp',
              hintText: '809-555-1234',
              errorText: _phoneError,
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() => _phoneError = null),
            onEditingComplete: () {
              FocusScope.of(context).nextFocus();
              _checkPhone();
            },
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              _checkPhone();
            },
          ),
          const SizedBox(height: 24),
          Text('Dónde estás', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_lat == null)
            OutlinedButton.icon(
              onPressed: _locating ? null : _useLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: const Text('Usar mi ubicación'),
            )
          else
            Chip(
              avatar: Icon(Icons.check_circle, color: cs.primary, size: 18),
              label: const Text('Ubicación captada ✓'),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Dirección',
                hintText: 'Calle, sector, ciudad — para ofertas cerca de ti'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          CheckboxListTile(
            value: _terms,
            onChanged: (v) => setState(() => _terms = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Wrap(children: [
              const Text('Acepto los '),
              InkWell(
                onTap: () => launchUrl(Uri.parse(AppConfig.termsUrl),
                    mode: LaunchMode.externalApplication),
                child: Text('Términos', style: TextStyle(color: cs.primary)),
              ),
              const Text(' y la '),
              InkWell(
                onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl),
                    mode: LaunchMode.externalApplication),
                child: Text('Privacidad', style: TextStyle(color: cs.primary)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_valid && !_busy) ? _submit : null,
            child: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Crear mi cuenta'),
          ),
        ]),
      ),
      ),
    );
  }
}
