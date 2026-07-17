import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../../domain/onboarding_errors.dart';
import '../../domain/phone.dart';

/// Alta de proveedor (spec §7): 6 pasos que SOLO recolectan; la única
/// escritura es la RPC atómica complete_provider_onboarding al final
/// (ADR-0029) — abandonar en cualquier paso deja cero residuo en la BD.
/// Sin OTP en el flujo (decisión PO §10.2: el sello va después, como la web).
class ProviderOnboardingScreen extends StatefulWidget {
  const ProviderOnboardingScreen({super.key});
  @override
  State<ProviderOnboardingScreen> createState() => _ProviderOnboardingScreenState();
}

class _ProviderOnboardingScreenState extends State<ProviderOnboardingScreen> {
  final _page = PageController();
  int _step = 0;
  static const _steps = 6;

  // Paso 1 — tu negocio
  late final TextEditingController _first;
  late final TextEditingController _last;
  final _name = TextEditingController();
  final _rnc = TextEditingController();
  bool _formal = false;
  String _offers = 'productos'; // productos | servicios | ambos
  bool _wholesale = false;

  // Paso 2 — qué vendes
  final List<String> _categories = [];
  final List<String> _rubros = [];
  List<Map<String, dynamic>> _dbRubros = [];
  bool _loadingRubros = false;

  // Paso 3 — dónde trabajas
  final _city = TextEditingController();
  final _sector = TextEditingController();
  bool _locating = false;

  // Paso 4 — WhatsApp
  final _phone = TextEditingController();
  String? _phoneError;

  // Paso 5 — foto opcional
  String? _logoUrl;
  bool _uploading = false;

  // Paso 6 — términos
  bool _terms = false;
  bool _busy = false;

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
    myProfile().then((p) {
      final ph = p?['phone'] as String?;
      if (ph != null && ph.isNotEmpty && mounted && _phone.text.isEmpty) {
        setState(() => _phone.text = ph);
      }
    }).catchError((_) => null);
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in [_first, _last, _name, _rnc, _city, _sector, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

  bool _stepValid(int s) => switch (s) {
        0 => _name.text.trim().isNotEmpty && (!_formal || _rnc.text.trim().isNotEmpty),
        1 => _categories.isNotEmpty,
        2 => _city.text.trim().isNotEmpty,
        3 => isValidPhone(_phone.text) && _phoneError == null,
        4 => true, // foto opcional
        5 => _terms,
        _ => false,
      };

  void _next() {
    if (!_stepValid(_step)) return;
    _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _back() {
    if (_step == 0) {
      context.go('/onboarding');
      return;
    }
    _page.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _toggleCategory(String id) async {
    setState(() {
      if (_categories.contains(id)) {
        _categories.remove(id);
        _rubros.removeWhere((r) =>
            _dbRubros.any((d) => d['id'] == r && d['category_id'] == id));
      } else if (_categories.length < 2) {
        _categories.add(id);
      }
    });
    if (_categories.isEmpty) {
      setState(() => _dbRubros = []);
      return;
    }
    setState(() => _loadingRubros = true);
    try {
      final rows = await rubrosForCategories(List.of(_categories));
      if (mounted) setState(() => _dbRubros = rows);
    } catch (_) {
      // Rubros son opcionales: sin red se puede seguir sin ellos.
    } finally {
      if (mounted) setState(() => _loadingRubros = false);
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
        _snack('Sin permiso de ubicación — escribe tu ciudad y sector.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (!mounted || marks.isEmpty) return;
      final m = marks.first;
      setState(() {
        if ((m.locality ?? '').isNotEmpty) _city.text = m.locality!;
        if ((m.subLocality ?? '').isNotEmpty) _sector.text = m.subLocality!;
      });
    } catch (_) {
      _snack('No pudimos captar tu ubicación — escribe tu ciudad y sector.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
            'Este WhatsApp ya está registrado en otro usuario. Usa otro número.');
      }
    } catch (_) {
      // La RPC valida igual al cierre (slug whatsapp_taken).
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await uploadBusinessLogo(picked.path);
      if (mounted) setState(() => _logoUrl = url);
    } catch (_) {
      _snack('No pudimos subir la foto. Puedes seguir sin ella y agregarla después.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final phoneE164 = normalizePhone(_phone.text);
    try {
      await completeProviderOnboarding(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        phone: phoneE164,
        business: {
          'business_type': _formal ? 'formal' : 'informal',
          'offers': _offers,
          'category_id': _categories.isNotEmpty ? _categories.first : '',
          'category_ids': _categories,
          'rubros': _rubros,
          'name': _name.text.trim(),
          'is_wholesale': _wholesale,
          'rnc': _formal ? _rnc.text.trim() : '',
          'description': '',
          'whatsapp': phoneE164,
          'country': 'República Dominicana',
          'city': _city.text.trim(),
          'sector': _sector.text.trim(),
          'address': '',
          'profession': '',
          'experience_years': '',
          'logo_url': _logoUrl ?? '',
          'owner_photo_url': '',
        },
        termsVersion: AppConfig.termsVersion,
      );
      await roleStore.refresh(); // → redirect a /provider
    } catch (e) {
      if (mounted) _snack(onboardingErrorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tu negocio (${_step + 1}/$_steps)'),
        leading: BackButton(onPressed: _back),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_step + 1) / _steps),
        ),
      ),
      body: SafeArea(
        child: PageView(
          controller: _page,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _step = i),
          children: [
            _stepBusiness(),
            _stepCategories(),
            _stepLocation(),
            _stepWhatsapp(),
            _stepPhoto(),
            _stepTerms(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: _step == _steps - 1
              ? FilledButton(
                  onPressed: (_stepValid(_step) && !_busy) ? _finish : null,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Crear mi negocio'),
                )
              : FilledButton(
                  onPressed: _stepValid(_step) ? _next : null,
                  child: const Text('Siguiente'),
                ),
        ),
      ),
    );
  }

  Widget _pad(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(20), children: children);

  Widget _stepBusiness() {
    return _pad([
      Text('Tu negocio', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      TextField(
        controller: _first,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Tu nombre'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _last,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Tu apellido'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
            labelText: 'Nombre del negocio', hintText: 'Ej. Repuestos El Primo'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Informal')),
          ButtonSegment(value: true, label: Text('Formal (con RNC)')),
        ],
        selected: {_formal},
        onSelectionChanged: (s) => setState(() => _formal = s.first),
      ),
      const SizedBox(height: 4),
      Text(
        _formal
            ? 'Negocio registrado con RNC.'
            : 'Aún sin RNC — la mayoría empieza así.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (_formal) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _rnc,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'RNC'),
          onChanged: (_) => setState(() {}),
        ),
      ],
      const SizedBox(height: 16),
      Text('¿Qué ofreces?', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'productos', label: Text('Productos')),
          ButtonSegment(value: 'servicios', label: Text('Servicios')),
          ButtonSegment(value: 'ambos', label: Text('Ambos')),
        ],
        selected: {_offers},
        onSelectionChanged: (s) => setState(() {
          _offers = s.first;
          if (_offers == 'servicios') _wholesale = false;
        }),
      ),
      if (_offers != 'servicios')
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vendo al por mayor'),
          value: _wholesale,
          onChanged: (v) => setState(() => _wholesale = v),
        ),
    ]);
  }

  Widget _stepCategories() {
    return _pad([
      Text('Qué vendes', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Elige hasta 2 categorías — así te llegan las solicitudes correctas.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final c in kCategories)
          FilterChip(
            label: Text(c.name),
            selected: _categories.contains(c.id),
            onSelected: (_categories.length < 2 || _categories.contains(c.id))
                ? (_) => _toggleCategory(c.id)
                : null,
          ),
      ]),
      if (_loadingRubros) const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      if (_dbRubros.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('¿Algo más específico? (opcional)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final r in _dbRubros)
            FilterChip(
              label: Text(r['name'] as String),
              selected: _rubros.contains(r['id']),
              onSelected: (_) => setState(() {
                final id = r['id'] as String;
                _rubros.contains(id) ? _rubros.remove(id) : _rubros.add(id);
              }),
            ),
        ]),
      ],
    ]);
  }

  Widget _stepLocation() {
    return _pad([
      Text('Dónde trabajas', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _locating ? null : _useLocation,
        icon: _locating
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location),
        label: const Text('Usar mi ubicación'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _city,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Ciudad'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _sector,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Sector (opcional)'),
      ),
    ]);
  }

  Widget _stepWhatsapp() {
    return _pad([
      Text('Tu WhatsApp', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Los clientes te contactan por aquí cuando desbloquean tu oferta.'),
      const SizedBox(height: 12),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'WhatsApp del negocio',
          hintText: '809-555-1234',
          errorText: _phoneError,
          errorMaxLines: 3,
        ),
        onChanged: (_) => setState(() => _phoneError = null),
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          _checkPhone();
        },
        onEditingComplete: () {
          FocusScope.of(context).unfocus();
          _checkPhone();
        },
      ),
      const SizedBox(height: 8),
      Text(
        'Después de crear tu negocio podrás confirmarlo por SMS para ganar el sello de verificado.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }

  Widget _stepPhoto() {
    return _pad([
      Text('Foto de tu negocio (opcional)', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Un logo o una foto del local da confianza. Puedes agregarla después.'),
      const SizedBox(height: 16),
      if (_logoUrl != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(_logoUrl!, height: 160, fit: BoxFit.cover),
        ),
      if (_uploading) const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : () => _pickPhoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Cámara'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : () => _pickPhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Galería'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Center(
        child: TextButton(onPressed: _next, child: const Text('Después')),
      ),
    ]);
  }

  Widget _stepTerms() {
    final cs = Theme.of(context).colorScheme;
    final catNames = _categories
        .map((id) => kCategories.firstWhere((c) => c.id == id,
            orElse: () => (id: id, name: id)).name)
        .join(', ');
    return _pad([
      Text('Revisa y confirma', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name.text.trim(),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(catNames),
            Text('${_city.text.trim()}'
                '${_sector.text.trim().isEmpty ? '' : ' · ${_sector.text.trim()}'}'),
            Text('WhatsApp: ${normalizePhone(_phone.text)}'),
            if (_wholesale) const Text('Vende al por mayor'),
          ]),
        ),
      ),
      const SizedBox(height: 12),
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
      const SizedBox(height: 4),
      Text('Empiezas con 0 créditos: ofertar es GRATIS; solo pagas al desbloquear un contacto.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
