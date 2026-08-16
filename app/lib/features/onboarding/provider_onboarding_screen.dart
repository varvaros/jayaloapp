import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/session_state.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../../domain/geo.dart';
import '../../domain/onboarding_errors.dart';
import '../../domain/phone.dart';
import '../shared/brand_kit.dart';
import '../shared/violet_header.dart';

/// Alta de proveedor (spec §7): pasos que SOLO recolectan; la única escritura
/// es la RPC atómica `complete_provider_onboarding` al final (ADR-0029) —
/// abandonar en cualquier paso deja cero residuo en la BD. Sin OTP en el flujo
/// (el sello va después). Diseño de la app: header violeta + campos rellenos +
/// tipografía ligera (PO 2026-07-20: "la pantalla de registro debe tener el
/// diseño de la app"). NO pide cédula/foto/logo — eso se completa después con
/// el aviso de "completa tu perfil" (PO 2026-07-20).
class ProviderOnboardingScreen extends StatefulWidget {
  const ProviderOnboardingScreen({super.key});
  @override
  State<ProviderOnboardingScreen> createState() =>
      _ProviderOnboardingScreenState();
}

class _ProviderOnboardingScreenState extends State<ProviderOnboardingScreen> {
  final _page = PageController();
  int _step = 0;
  static const _steps = 4;
  static const _titles = ['Tu negocio', 'Qué vendes y dónde', 'Tu WhatsApp', 'Revisar'];

  // Paso 1 — tu negocio
  late final TextEditingController _first;
  late final TextEditingController _last;
  final _name = TextEditingController();
  final _rnc = TextEditingController();
  String _businessType = 'informal'; // informal | tecnico | formal
  final _profession = TextEditingController(); // solo técnico
  String _offers = 'productos'; // productos | servicios | ambos
  bool _wholesale = false;

  // Paso 2 — qué vendes y dónde
  final List<String> _categories = [];
  final List<String> _rubros = [];
  List<Map<String, dynamic>> _dbRubros = [];
  bool _loadingRubros = false;
  String? _rubrosError;
  final List<String> _cities = [];
  final List<String> _sectors = [];
  final _cityInput = TextEditingController();
  final _sectorInput = TextEditingController();
  final _address = TextEditingController();
  bool _locating = false;
  // Coordenada de "Usar mi ubicación". Ahora se PERSISTE: antes se pedía
  // `ACCESS_FINE_LOCATION`, se usaba solo para rellenar ciudad/sector de texto y
  // se tiraba. Sin ella el negocio no tiene con qué alimentar
  // `get_business_distance_km` y no hay pantalla de edición para corregirlo; y
  // "rellenar un campo de texto" no justifica el permiso ante Google Play. El
  // flujo de consumidor ya las guardaba.
  double? _lat;
  double? _lng;

  // Paso 3 — WhatsApp (chequeo de "ocupado" inmediato, con rebote)
  String _prefix = '809';
  final _local = TextEditingController();
  String? _phoneError;
  bool _checkingPhone = false;
  Timer? _phoneDebounce;

  // Paso 4 — términos
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
      if (ph != null && ph.isNotEmpty && mounted && _local.text.isEmpty) {
        final digits = ph.replaceAll(RegExp(r'\D'), '');
        final tenDigits = digits.length == 11 && digits.startsWith('1')
            ? digits.substring(1)
            : (digits.length == 10 ? digits : null);
        if (tenDigits != null) {
          final p3 = tenDigits.substring(0, 3);
          final rest = tenDigits.substring(3);
          setState(() {
            if (kRdPrefixes.contains(p3)) {
              _prefix = p3;
              _local.text = rest;
            }
          });
          _checkPhone();
        }
      }
    }).catchError((_) => null);
  }

  String get _composedPhone => composeRdWhatsapp(_prefix, _local.text);

  @override
  void dispose() {
    _phoneDebounce?.cancel();
    _page.dispose();
    for (final c in [
      _first, _last, _name, _rnc, _profession,
      _cityInput, _sectorInput, _address, _local,
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
        1 => _categories.isNotEmpty && _cities.isNotEmpty,
        2 => _composedPhone.isNotEmpty && _phoneError == null && !_checkingPhone,
        3 => _terms,
        _ => false,
      };

  void _next() {
    if (!_stepValid(_step)) return;
    _page.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _back() {
    if (_step == 0) {
      context.go('/onboarding');
      return;
    }
    _page.previousPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // ── Categorías / rubros ────────────────────────────────────────────────────

  Future<void> _addCategory(String id) async {
    if (_categories.contains(id) || _categories.length >= 2) return;
    setState(() => _categories.add(id));
    await _loadRubros();
  }

  void _removeCategory(String id) {
    setState(() {
      _categories.remove(id);
      _rubros.removeWhere((r) =>
          _dbRubros.any((d) => d['id'] == r && d['category_id'] == id));
    });
    if (_categories.isEmpty) {
      setState(() {
        _dbRubros = [];
        _rubrosError = null;
      });
    } else {
      _loadRubros();
    }
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
      debugPrint('[onboarding] rubros fallaron: $e');
      if (mounted) {
        setState(() => _rubrosError = 'No pudimos cargar los rubros.');
      }
    } finally {
      if (mounted) setState(() => _loadingRubros = false);
    }
  }

  Future<void> _createRubroDialog() async {
    if (_categories.isEmpty) return;
    final nameCtrl = TextEditingController();
    String catId = _categories.first;
    final ok = await showDialog<bool>(
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
                    DropdownMenuItem(value: id, child: Text(_catName(id))),
                ],
                onChanged: (v) => setLocal(() => catId = v ?? catId),
              ),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nombre del rubro', hintText: 'Ej. Bombas de agua'),
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
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true) return;
    if (name.length < 2) return _snack('Escribe un nombre de rubro válido.');
    try {
      final r = await createProviderRubro(categoryId: catId, name: name);
      final id = r['id'] as String;
      if (!mounted) return;
      setState(() {
        if (!_dbRubros.any((d) => d['id'] == id)) _dbRubros = [..._dbRubros, r];
        if (!_rubros.contains(id)) _rubros.add(id);
      });
    } catch (_) {
      _snack('No se pudo crear el rubro. Intenta de nuevo.');
    }
  }

  String _catName(String id) => kCategories
      .firstWhere((c) => c.id == id, orElse: () => (id: id, name: id))
      .name;

  // ── Ubicación ──────────────────────────────────────────────────────────────

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) _snack('Sin permiso de ubicación — escribe tu ciudad y sector.');
        return;
      }
      // `timeLimit`: sin él, si el GPS no fija el Future no resuelve NUNCA y
      // `_locating` se queda en true — el botón gira para siempre.
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 15)));
      // La coordenada se guarda ANTES del geocoder: si el reverse geocoding
      // falla o no devuelve nada, igual conservamos la ubicación del negocio.
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      // El geocoder va en su PROPIO try (como ya hacía el flujo de consumidor):
      // la coordenada quedó guardada arriba, así que un fallo suyo no debe caer
      // en el catch de afuera, que dice "no pudimos captar tu ubicación" —
      // mentía, y mandaba al usuario a repetir un permiso que ya había dado.
      try {
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
          // Calle Y NÚMERO. Antes era solo `thoroughfare` (el nombre de la
          // calle), así que la dirección del negocio quedaba en "Calle Duarte"
          // mientras el alta de consumidor sí traía el número.
          final street = composeStreetLine(
            thoroughfare: m.thoroughfare,
            subThoroughfare: m.subThoroughfare,
            street: m.street,
          );
          if (street.isNotEmpty && _address.text.trim().isEmpty) {
            _address.text = street;
          }
        });
      } catch (_) {
        // Best-effort: sin geocoder quedan las coordenadas y los campos a mano.
      }
    } catch (_) {
      if (mounted) _snack('No pudimos captar tu ubicación — escribe tu ciudad y sector.');
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

  // ── WhatsApp: chequeo inmediato (rebote de 500 ms) ─────────────────────────

  void _onPhoneChanged(String _) {
    setState(() => _phoneError = null);
    _phoneDebounce?.cancel();
    _phoneDebounce = Timer(const Duration(milliseconds: 500), _checkPhone);
  }

  Future<void> _checkPhone() async {
    if (_local.text.trim().isEmpty) return;
    final composed = _composedPhone;
    if (composed.isEmpty) {
      if (mounted) {
        setState(() => _phoneError = 'Escribe un WhatsApp de 7 dígitos.');
      }
      return;
    }
    setState(() => _checkingPhone = true);
    try {
      final digits = composed.replaceAll(RegExp(r'\D'), '');
      final taken = await isWhatsappTakenRemote(digits);
      if (!mounted) return;
      setState(() => _phoneError = taken
          ? 'Este WhatsApp ya está registrado en otro usuario. Usa otro número.'
          : null);
    } catch (_) {
      // La RPC valida igual al cierre (slug whatsapp_taken).
    } finally {
      if (mounted) setState(() => _checkingPhone = false);
    }
  }

  // ── Cierre ─────────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    final phoneE164 = _composedPhone;
    if (phoneE164.isEmpty) {
      _snack('Escribe un WhatsApp de 7 dígitos.');
      return;
    }
    setState(() => _busy = true);
    try {
      await completeProviderOnboarding(
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
          // Varias ciudades/sectores se guardan unidas por ", " (como la web).
          'city': _cities.join(', '),
          'sector': _sectors.join(', '),
          'address': _address.text.trim(),
          'profession':
              _businessType == 'tecnico' ? _profession.text.trim() : '',
          'experience_years': '',
          'logo_url': '',
          'owner_photo_url': '',
          // Coordenada de "Usar mi ubicación" (puede no haberla: permiso
          // denegado o GPS que no fijó). La RPC ignora un valor vacío o fuera
          // de rango y deja las columnas en NULL, como hasta ahora.
          'lat': _lat?.toString() ?? '',
          'lng': _lng?.toString() ?? '',
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // El botón ATRÁS del sistema debe retroceder de paso, no minimizar la app
    // (con context.go() no hay pila que popear; MIUI mataba el proceso y se
    // perdía lo tecleado — verificado con el PO en device 2026-07-17).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
        body: Column(children: [
          VioletHeader(
            leading: HeaderCircleButton(
                icon: Icons.arrow_back, tooltip: 'Atrás', onTap: _back),
            title: '${_titles[_step]} · ${_step + 1}/$_steps',
            below: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _steps,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _step = i),
              children: [
                _stepBusiness(),
                _stepSell(),
                _stepWhatsapp(),
                _stepConfirm(),
              ],
            ),
          ),
        ]),
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
      ),
    );
  }

  Widget _pad(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(20), children: children);

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: jayaloHead(context))),
      );

  Widget _field(TextEditingController c, String label,
          {String? hint,
          TextInputType? keyboard,
          bool caps = false,
          ValueChanged<String>? onChanged,
          List<TextInputFormatter>? inputFormatters,
          int? maxLength}) =>
      TextField(
        controller: c,
        keyboardType: keyboard,
        textCapitalization:
            caps ? TextCapitalization.words : TextCapitalization.none,
        decoration: filledField(context, label, hint: hint),
        onChanged: onChanged ?? (_) => setState(() {}),
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        buildCounter: maxLength != null
            ? (_, {required currentLength, required isFocused, maxLength}) =>
                null
            : null,
      );

  // ── Paso 1: tu negocio ─────────────────────────────────────────────────────

  Widget _stepBusiness() {
    final nameFormatters = [
      LengthLimitingTextInputFormatter(40),
      FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{M} '\-]", unicode: true)),
    ];
    return _pad([
      _field(_first, 'Tu nombre',
          caps: true, maxLength: 40, inputFormatters: nameFormatters),
      const SizedBox(height: 10),
      _field(_last, 'Tu apellido',
          caps: true, maxLength: 40, inputFormatters: nameFormatters),
      const SizedBox(height: 10),
      _field(_name, 'Nombre del negocio',
          hint: 'Ej. Repuestos El Primo', caps: true),
      const SizedBox(height: 18),
      _sectionTitle('Tipo de negocio'),
      PillSegmented(
        options: const ['Informal', 'Técnico', 'Formal'],
        index: const ['informal', 'tecnico', 'formal'].indexOf(_businessType),
        onChanged: (i) => setState(
            () => _businessType = ['informal', 'tecnico', 'formal'][i]),
      ),
      const SizedBox(height: 6),
      Text(
        switch (_businessType) {
          'formal' => 'Negocio registrado con RNC.',
          'tecnico' => 'Ofreces un oficio o servicio técnico.',
          _ => 'Aún sin RNC — la mayoría empieza así.',
        },
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      if (_businessType == 'formal') ...[
        const SizedBox(height: 10),
        _field(_rnc, 'RNC', keyboard: TextInputType.number),
      ],
      if (_businessType == 'tecnico') ...[
        const SizedBox(height: 10),
        _field(_profession, 'Profesión / oficio (opcional)',
            hint: 'Ej. Plomero, electricista', caps: true),
      ],
      const SizedBox(height: 18),
      _sectionTitle('¿Qué ofreces?'),
      PillSegmented(
        options: const ['Productos', 'Servicios', 'Ambos'],
        index: const ['productos', 'servicios', 'ambos'].indexOf(_offers),
        onChanged: (i) => setState(() {
          _offers = ['productos', 'servicios', 'ambos'][i];
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

  // ── Paso 2: qué vendes y dónde ─────────────────────────────────────────────

  Widget _stepSell() {
    return _pad([
      // Copy pedido PO 2026-07-21: instrucción explícita en vez de etiqueta.
      _sectionTitle('Selecciona hasta 2 categorías'),
      _dropdownAdder(
        hint: _categories.length >= 2
            ? 'Máximo 2 categorías'
            : 'Elige una categoría',
        options: [for (final c in kCategories) (id: c.id, name: c.name)],
        selected: _categories,
        enabled: _categories.length < 2,
        onAdd: _addCategory,
      ),
      if (_categories.isNotEmpty) ...[
        const SizedBox(height: 8),
        _chips(_categories.map((id) => (id: id, label: _catName(id))).toList(),
            onRemove: _removeCategory),
      ],
      const SizedBox(height: 18),
      _sectionTitle('Puedes seleccionar varios rubros'),
      if (_categories.isEmpty)
        _hint('Elige una categoría para ver sus rubros.')
      else if (_loadingRubros)
        const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: JayaloSpinner(size: 22)))
      else if (_rubrosError != null)
        Row(children: [
          Expanded(child: Text(_rubrosError!)),
          TextButton(onPressed: _loadRubros, child: const Text('Reintentar')),
        ])
      else ...[
        _dropdownAdder(
          hint: 'Elige un rubro',
          options: [
            for (final r in _dbRubros)
              (id: r['id'] as String, name: r['name'] as String)
          ],
          selected: _rubros,
          onAdd: (id) => setState(() {
            if (!_rubros.contains(id)) _rubros.add(id);
          }),
        ),
        if (_rubros.isNotEmpty) ...[
          const SizedBox(height: 8),
          _chips(
            _rubros.map((id) {
              final r = _dbRubros.firstWhere((d) => d['id'] == id,
                  orElse: () => {'name': id});
              return (id: id, label: r['name'] as String);
            }).toList(),
            onRemove: (id) => setState(() => _rubros.remove(id)),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _createRubroDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crear un rubro'),
          ),
        ),
      ],
      const Divider(height: 32),
      _sectionTitle('Dónde trabajas'),
      OutlinedButton.icon(
        onPressed: _locating ? null : _useLocation,
        icon: _locating
            ? const JayaloSpinner(size: 16)
            : const Icon(Icons.my_location),
        label: const Text('Usar mi ubicación'),
      ),
      const SizedBox(height: 12),
      _chipField(controller: _cityInput, label: 'Ciudad', list: _cities),
      const SizedBox(height: 10),
      _chipField(
          controller: _sectorInput, label: 'Sector (opcional)', list: _sectors),
      const SizedBox(height: 10),
      _field(_address, 'Dirección (opcional)',
          hint: 'Calle, número, referencia', caps: true),
    ]);
  }

  Widget _hint(String t) => Text(t,
      style: TextStyle(
          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant));

  Widget _dropdownAdder({
    required String hint,
    required List<({String id, String name})> options,
    required List<String> selected,
    required void Function(String id) onAdd,
    bool enabled = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final available = options.where((o) => !selected.contains(o.id)).toList();
    final off = !enabled || available.isEmpty;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: null,
          hint: Text(hint,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
          icon: const Icon(Icons.expand_more),
          items: [
            for (final o in available)
              DropdownMenuItem(
                  value: o.id,
                  child: Text(o.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: off ? null : (v) => v == null ? null : onAdd(v),
        ),
      ),
    );
  }

  Widget _chips(List<({String id, String label})> items,
          {required void Function(String id) onRemove}) =>
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final it in items)
          InputChip(label: Text(it.label), onDeleted: () => onRemove(it.id)),
      ]);

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
            decoration: filledField(context, label),
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
        _chips(list.map((v) => (id: v, label: v)).toList(),
            onRemove: (v) => setState(() => list.remove(v))),
      ],
    ]);
  }

  // ── Paso 3: WhatsApp ───────────────────────────────────────────────────────

  Widget _stepWhatsapp() {
    return _pad([
      _hint('Los clientes te contactan por aquí cuando desbloquean tu oferta.'),
      const SizedBox(height: 14),
      Row(children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _prefix,
              items: [
                for (final p in kRdPrefixes)
                  DropdownMenuItem(value: p, child: Text(p))
              ],
              onChanged: (v) {
                setState(() => _prefix = v ?? '809');
                _onPhoneChanged(_local.text);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _local,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(7),
            ],
            onChanged: _onPhoneChanged,
            decoration: filledField(context, 'WhatsApp del negocio',
                    hint: '5551234')
                .copyWith(
              errorText: _phoneError,
              errorMaxLines: 3,
              suffixIcon: _checkingPhone
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: JayaloSpinner(size: 16))
                  : (_phoneError == null && _composedPhone.isNotEmpty
                      ? Icon(Icons.check_circle,
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? JayaloColors.dSuccess
                              : JayaloColors.success)
                      : null),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      _hint(
          'Después de crear tu negocio podrás confirmarlo por SMS para ganar el sello de verificado.'),
    ]);
  }

  // ── Paso 4: revisar + aviso de completar perfil ────────────────────────────

  Widget _stepConfirm() {
    final cs = Theme.of(context).colorScheme;
    final tone = Theme.of(context).brightness == Brightness.dark
        ? JayaloStatus.pendingDark
        : JayaloStatus.pendingLight;
    return _pad([
      JayaloCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_name.text.trim(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(_categories.map(_catName).join(', ')),
          Text('${_cities.join(', ')}'
              '${_sectors.isEmpty ? '' : ' · ${_sectors.join(', ')}'}'),
          Text('WhatsApp: $_composedPhone'),
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
      // Aviso de "completa tu perfil" (PO 2026-07-20): el registro ya no pide
      // cédula/foto; se completan después para poder ofertar / ganar el sello.
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: tone.bg, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.badge_outlined, size: 20, color: tone.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                _businessType == 'formal'
                    ? 'Después podrás completar tu perfil (foto, descripción) para dar más confianza.'
                    : 'Después completa tu perfil (cédula y foto) para poder enviar ofertas y ganar el sello de verificado.',
                style: TextStyle(fontSize: 13, color: tone.ink)),
          ),
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
      _hint(
          'Empiezas con 0 créditos: ofertar es GRATIS; solo pagas al desbloquear un contacto.'),
    ]);
  }
}
