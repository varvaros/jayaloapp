import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../../domain/onboarding_errors.dart';
import '../../domain/phone.dart';
import '../shared/brand_kit.dart';

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
  static const _steps = 7;

  // Paso 1 — tu negocio
  late final TextEditingController _first;
  late final TextEditingController _last;
  final _name = TextEditingController();
  final _rnc = TextEditingController();
  // Tipo de negocio (paridad web): informal | tecnico | formal.
  String _businessType = 'informal';
  final _profession = TextEditingController(); // solo técnico
  String _offers = 'productos'; // productos | servicios | ambos
  bool _wholesale = false;

  // Paso 2 — qué vendes
  final List<String> _categories = [];
  final List<String> _rubros = [];
  List<Map<String, dynamic>> _dbRubros = [];
  bool _loadingRubros = false;
  String? _rubrosError;

  // Paso 3 — dónde trabajas (varias ciudades/sectores, como la web)
  final List<String> _cities = [];
  final List<String> _sectors = [];
  final _cityInput = TextEditingController();
  final _sectorInput = TextEditingController();
  bool _locating = false;

  // Paso 4 — WhatsApp
  final _phone = TextEditingController();
  String? _phoneError;

  // Paso 5 — cédula (solo informal/técnico; el negocio formal la salta)
  final _cedulaNumber = TextEditingController();
  XFile? _cedulaFile;

  // Paso 6 — foto opcional
  String? _logoUrl;
  bool _uploading = false;

  // Paso 7 — términos
  bool _terms = false;
  bool _busy = false;

  bool get _needsCedula => _businessType != 'formal';

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
    for (final c in [
      _first, _last, _name, _rnc, _profession,
      _cityInput, _sectorInput, _phone, _cedulaNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

  bool _stepValid(int s) => switch (s) {
        0 => _name.text.trim().isNotEmpty &&
            (_businessType != 'formal' || _rnc.text.trim().isNotEmpty),
        1 => _categories.isNotEmpty,
        2 => _cities.isNotEmpty,
        3 => isValidPhone(_phone.text) && _phoneError == null,
        // Cédula: el negocio formal la salta; informal/técnico necesita número
        // + foto (la config de prod exige foto — `provider_id_photo.required`).
        4 => !_needsCedula ||
            (_cedulaNumber.text.trim().isNotEmpty && _cedulaFile != null),
        5 => true, // foto de negocio opcional
        6 => _terms,
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
      setState(() {
        _dbRubros = [];
        _rubrosError = null;
      });
      return;
    }
    await _loadRubros();
  }

  Future<void> _loadRubros() async {
    setState(() {
      _loadingRubros = true;
      _rubrosError = null;
    });
    try {
      final rows = await rubrosForCategories(List.of(_categories));
      if (mounted) setState(() => _dbRubros = rows);
    } catch (e) {
      // Antes esto era un catch silencioso: si la consulta fallaba, los rubros
      // simplemente no aparecían y el usuario no tenía forma de saber por qué
      // (el PO reportó "no vi rubro" en el E2E). Ahora se dice y se reintenta.
      debugPrint('[onboarding] rubros fallaron: $e');
      if (mounted) {
        setState(() => _rubrosError = 'No pudimos cargar los rubros.');
      }
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
        final city = m.locality ?? '';
        final sector = m.subLocality ?? '';
        if (city.isNotEmpty && !_cities.contains(city)) _cities.add(city);
        if (sector.isNotEmpty && !_sectors.contains(sector)) {
          _sectors.add(sector);
        }
      });
    } catch (_) {
      _snack('No pudimos captar tu ubicación — escribe tu ciudad y sector.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _addChip(List<String> list, TextEditingController input) {
    final v = input.text.trim();
    if (v.isEmpty || list.contains(v)) {
      input.clear();
      return;
    }
    setState(() {
      list.add(v);
      input.clear();
    });
  }

  Future<void> _pickCedula(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;
    if (mounted) setState(() => _cedulaFile = picked);
  }

  Future<void> _createRubroDialog() async {
    if (_categories.isEmpty) return;
    final nameCtrl = TextEditingController();
    // Si hay 2 categorías, el proveedor elige a cuál pertenece el rubro nuevo.
    String catId = _categories.first;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Crear rubro'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_categories.length > 1)
              DropdownButtonFormField<String>(
                initialValue: catId,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final id in _categories)
                    DropdownMenuItem(
                      value: id,
                      child: Text(kCategories
                          .firstWhere((c) => c.id == id,
                              orElse: () => (id: id, name: id))
                          .name),
                    ),
                ],
                onChanged: (v) => setLocal(() => catId = v ?? catId),
              ),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nombre del rubro',
                  hintText: 'Ej. Bombas de agua'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Crear')),
          ],
        ),
      ),
    );
    if (created != true) {
      nameCtrl.dispose();
      return;
    }
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (name.length < 2) {
      _snack('Escribe un nombre de rubro válido.');
      return;
    }
    try {
      final r = await createProviderRubro(categoryId: catId, name: name);
      final id = r['id'] as String;
      if (!mounted) return;
      setState(() {
        if (!_dbRubros.any((d) => d['id'] == id)) {
          _dbRubros = [..._dbRubros, r];
        }
        if (!_rubros.contains(id)) _rubros.add(id);
      });
    } catch (_) {
      _snack('No se pudo crear el rubro. Intenta de nuevo.');
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
      final businessId = await completeProviderOnboarding(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        phone: phoneE164,
        business: {
          'business_type': _businessType,
          'offers': _offers,
          'category_id': _categories.isNotEmpty ? _categories.first : '',
          'category_ids': _categories,
          'rubros': _rubros,
          'name': _name.text.trim(),
          'is_wholesale': _wholesale,
          'rnc': _businessType == 'formal' ? _rnc.text.trim() : '',
          'description': '',
          'whatsapp': phoneE164,
          'country': 'República Dominicana',
          // Varias ciudades/sectores se guardan unidos por ", " (como la web).
          'city': _cities.join(', '),
          'sector': _sectors.join(', '),
          'address': '',
          'profession':
              _businessType == 'tecnico' ? _profession.text.trim() : '',
          'experience_years': '',
          'logo_url': _logoUrl ?? '',
          'owner_photo_url': '',
        },
        termsVersion: AppConfig.termsVersion,
      );
      // Cédula (informal/técnico): se escribe DESPUÉS de crear el negocio
      // (necesita el business_id). No es atómico con el negocio a propósito; si
      // fallara, el negocio ya existe y la RPC de onboarding no debe revertirse.
      if (_needsCedula && _cedulaNumber.text.trim().isNotEmpty) {
        try {
          var path = '';
          if (_cedulaFile != null) {
            path = await uploadIdDocPhoto(_cedulaFile!.path, businessId);
          }
          await saveIdDoc(
            businessId: businessId,
            idNumber: _cedulaNumber.text.trim(),
            idPhotoPath: path,
          );
        } catch (_) {
          if (mounted) {
            _snack(
                'Negocio creado, pero no pudimos guardar tu cédula. Complétala en Mi negocio para poder ofertar.');
          }
        }
      }
      await roleStore.refresh(); // → redirect a /provider
    } catch (e) {
      if (mounted) _snack(onboardingErrorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // El botón ATRÁS del sistema debe retroceder de paso, no minimizar la app:
    // con context.go() no hay pila que popear, así que Android salía de Jayalo,
    // MIUI mataba el proceso y al reabrir el formulario empezaba de cero
    // (verificado con el PO en el device 2026-07-17). Doctrina del proyecto:
    // nunca perder lo que el usuario ya tecleó.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
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
            _stepCedula(),
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
                      ? const JayaloSpinner(size: 18)
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
      Text('Tipo de negocio', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'informal', label: Text('Informal')),
          ButtonSegment(value: 'tecnico', label: Text('Técnico')),
          ButtonSegment(value: 'formal', label: Text('Formal')),
        ],
        selected: {_businessType},
        onSelectionChanged: (s) => setState(() => _businessType = s.first),
      ),
      const SizedBox(height: 4),
      Text(
        switch (_businessType) {
          'formal' => 'Negocio registrado con RNC.',
          'tecnico' => 'Ofreces un oficio o servicio técnico.',
          _ => 'Aún sin RNC — la mayoría empieza así.',
        },
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (_businessType == 'formal') ...[
        const SizedBox(height: 8),
        TextField(
          controller: _rnc,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'RNC'),
          onChanged: (_) => setState(() {}),
        ),
      ],
      if (_businessType == 'tecnico') ...[
        const SizedBox(height: 8),
        TextField(
          controller: _profession,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Profesión / oficio (opcional)',
              hintText: 'Ej. Plomero, electricista'),
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
      // La sección de rubros SIEMPRE es visible (antes solo aparecía si la
      // consulta traía datos: si el usuario no elegía categoría, o la query
      // fallaba, no había ni rastro de que los rubros existieran).
      const SizedBox(height: 24),
      Text('¿Algo más específico? (opcional)',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('Los rubros ayudan a que te lleguen solicitudes más precisas.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (_categories.isEmpty)
        const Text('Elige una categoría arriba y aquí te mostramos sus rubros.')
      else if (_loadingRubros)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: JayaloSpinner(size: 24)),
        )
      else if (_rubrosError != null)
        Row(children: [
          Expanded(child: Text(_rubrosError!)),
          TextButton(onPressed: _loadRubros, child: const Text('Reintentar')),
        ])
      else if (_dbRubros.isEmpty)
        const Text('Esta categoría no tiene rubros; puedes continuar sin elegir ninguno.')
      else
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
      // Crear un rubro propio si no está en la lista (como la web). Va por la
      // RPC `create_provider_rubro` — RLS bloquea el INSERT directo.
      if (_categories.isNotEmpty) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _createRubroDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crear un rubro'),
          ),
        ),
      ],
    ]);
  }

  Widget _stepLocation() {
    return _pad([
      Text('Dónde trabajas', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Puedes agregar varias ciudades y sectores donde atiendes.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _locating ? null : _useLocation,
        icon: _locating
            ? const JayaloSpinner(size: 16)
            : const Icon(Icons.my_location),
        label: const Text('Usar mi ubicación'),
      ),
      const SizedBox(height: 12),
      _chipField(
        controller: _cityInput,
        label: 'Ciudad',
        list: _cities,
      ),
      const SizedBox(height: 8),
      _chipField(
        controller: _sectorInput,
        label: 'Sector (opcional)',
        list: _sectors,
      ),
    ]);
  }

  /// Campo de texto + "Agregar" que acumula valores como chips removibles
  /// (para las varias ciudades/sectores).
  Widget _chipField({
    required TextEditingController controller,
    required String label,
    required List<String> list,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (_) => _addChip(list, controller),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => _addChip(list, controller),
          child: const Text('Agregar'),
        ),
      ]),
      if (list.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final v in list)
            InputChip(
              label: Text(v),
              onDeleted: () => setState(() => list.remove(v)),
            ),
        ]),
      ],
    ]);
  }

  Widget _stepCedula() {
    if (!_needsCedula) {
      return _pad([
        Text('Identificación', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
            'Tu negocio es formal (con RNC), así que no necesitas registrar tu cédula. Continúa.'),
      ]);
    }
    final cs = Theme.of(context).colorScheme;
    return _pad([
      Text('Tu cédula (privada)', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text(
          'Como proveedor informal o técnico, necesitas registrar tu cédula para poder enviar ofertas. Solo el equipo de Jayalo la ve.'),
      const SizedBox(height: 16),
      TextField(
        controller: _cedulaNumber,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            labelText: 'Número de cédula', hintText: '000-0000000-0'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      Text('Foto de la cédula', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      if (_cedulaFile != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_cedulaFile!.path),
              height: 160, width: double.infinity, fit: BoxFit.cover),
        )
      else
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
              child: Text('Sin foto',
                  style: TextStyle(color: cs.onSurfaceVariant))),
        ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickCedula(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Cámara'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickCedula(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Galería'),
          ),
        ),
      ]),
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
        child: Center(child: JayaloSpinner(size: 24)),
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
      JayaloCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_name.text.trim(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(catNames),
          Text('${_cities.join(', ')}'
              '${_sectors.isEmpty ? '' : ' · ${_sectors.join(', ')}'}'),
          Text('WhatsApp: ${normalizePhone(_phone.text)}'),
          if (_wholesale) ...[
            const SizedBox(height: 8),
            StatusChip(
                label: 'Al por mayor',
                icon: Icons.storefront_outlined,
                tone: Theme.of(context).brightness == Brightness.dark
                    ? JayaloStatus.respondedDark
                    : JayaloStatus.respondedLight),
          ],
        ]),
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
