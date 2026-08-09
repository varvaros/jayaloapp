import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/brand.dart';
import '../../core/safe_image_picker.dart';
import '../../core/unsaved_guard.dart';
import '../../data/repos.dart';
import '../../domain/image_pick.dart';
import '../../domain/offer_defaults.dart';
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/offer_field_options.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Mismo tope que las fotos de una oferta: estos artículos existen para
/// autocompletar ofertas, no tiene sentido que carguen más que ellas.
const _maxItemPhotos = 5;

/// Copiado TAL CUAL de `request_detail_screen.dart` (`_svcModes`, Task 6): el
/// molde de oferta usa las MISMAS claves, en el MISMO orden — divergir aquí
/// desalinearía el prellenado de la Task 9. No se extrajo a un archivo
/// compartido porque el brief solo pidió eso para garantía/entrega/estado.
const _svcModes = ['fixed', 'range', 'hourly', 'needs_evaluation'];

/// Copiado de `request_detail_screen.dart` (`_colorPresets`, Task 6): paridad
/// de colores entre la oferta y el molde de tienda. Tampoco se extrajo — el
/// brief solo pidió extraer garantía/entrega/estado.
const _colorPresets = <(String, Color)>[
  ('Negro', Color(0xFF111111)),
  ('Blanco', Color(0xFFF5F5F5)),
  ('Gris', Color(0xFF9CA3AF)),
  ('Rojo', Color(0xFFDC2626)),
  ('Azul', Color(0xFF2563EB)),
  ('Verde', Color(0xFF16A34A)),
  ('Amarillo', Color(0xFFFACC15)),
  ('Beige', Color(0xFFE7D4B5)),
  ('Marrón', Color(0xFF7C4A2A)),
  ('Rosa', Color(0xFFEC4899)),
];

/// Convierte lo escrito en el campo de precio ("5,000", "RD$5000") a un
/// número; null si está vacío. Solo dígitos — mismo criterio que el campo de
/// presupuesto de crear solicitud.
num? parseStoreItemPrice(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

/// Alta rápida O EDICIÓN desde la app de un artículo de la tienda (pedido PO
/// 2026-08-05: el agregador de "Mi negocio"; edición Task 6, 2026-08-09).
/// Tres variantes por [kind]: `producto` y `servicio` escriben en
/// `provider_products` (alta: `saveProductToStore`; edición: `updateStoreItem`,
/// vía [initial]); `trabajo` inserta en `provider_portfolio_items` y NUNCA se
/// edita desde aquí (sin `initial`).
///
/// Con [initial] la pantalla precarga TODOS los campos — incluido el molde de
/// oferta (`offer_defaults`) — y "Guardar" hace un `UPDATE` en vez de un
/// `INSERT`. Sigue siendo una PLANTILLA: ningún campo nuevo es obligatorio,
/// solo el nombre lo sigue siendo (paridad con el alta).
class AddStoreItemScreen extends StatefulWidget {
  const AddStoreItemScreen({
    super.key,
    required this.kind,
    required this.businessId,
    this.initial,
    this.saveProduct = saveProductToStore,
    this.updateItem = updateStoreItem,
    this.savePortfolio = savePortfolioItem,
    this.fetchCatRubro = myBusinessCategoryRubro,
  });

  /// 'producto' | 'servicio' | 'trabajo'.
  final String kind;

  /// Viene en la ruta desde "Mi negocio", que ya lo tiene cargado — así esta
  /// pantalla no repite el fetch del perfil.
  final String businessId;

  /// Fila completa de `provider_products` (mismas columnas que
  /// [storeProductCols] + `offer_defaults`) cuando se abre para EDITAR un
  /// ítem propio. `null` = alta nueva.
  final Map<String, dynamic>? initial;

  /// Inyectables para probar sin red — defaults a las implementaciones reales
  /// de `repos.dart` (mismo patrón que `MyBusinessView.updateDescription`).
  final Future<void> Function({
    required String businessId,
    required String name,
    required String description,
    required String categoryId,
    required String rubro,
    required String kind,
    String color,
    double? price,
    double? priceMin,
    double? priceMax,
    List<String> imageUrls,
    String? condition,
    bool offersShipping,
    bool offersInstallation,
    bool requiresEvaluation,
    Map<String, dynamic>? offerDefaults,
  })
  saveProduct;
  final Future<void> Function(String id, Map<String, dynamic> payload)
  updateItem;
  final Future<void> Function({
    required String businessId,
    required String title,
    String? description,
    List<String> imageUrls,
  })
  savePortfolio;
  final Future<({String? categoryId, String? rubro})> Function(
    String businessId,
  )
  fetchCatRubro;

  @override
  State<AddStoreItemScreen> createState() => _AddStoreItemScreenState();
}

class _AddStoreItemScreenState extends State<AddStoreItemScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();

  // Precio: fijo/rango (producto) o los 4 modos (servicio) — molde de la
  // oferta, Task 6.
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _hourly = TextEditingController();
  final _hours = TextEditingController();
  bool _fixed = true;
  int _svcMode = 0;

  // Servicio: disponibilidad + duración.
  final _availability = TextEditingController();
  final _duration = TextEditingController();

  // Producto: envío / instalación / evaluación (paridad con la oferta).
  bool _offersShipping = false;
  final _shipping = TextEditingController();
  bool _offersInstallation = false;
  final _installation = TextEditingController();
  bool _requiresEvaluation = false;
  final _evaluation = TextEditingController();

  // Producto: marca/estado/color/garantía/tiempo de entrega.
  final _brand = TextEditingController();
  final _warranty = TextEditingController();
  final _delivery = TextEditingController();
  String _condition = ''; // 'Nuevo' | 'Usado' | ''
  final List<String> _colors = [];

  final List<XFile> _photos = [];

  /// Fotos YA subidas (edición): URLs de `initial['image_urls']` que se
  /// conservan salvo que el usuario las quite. Mismo patrón que `_keptUrls`
  /// en `request_detail_screen.dart`.
  final List<String> _keptUrls = [];

  /// Ruta local → URL ya subida. Evita re-subir el mismo fichero en cada
  /// reintento del guardado (ver `_save`).
  final Map<String, String> _uploaded = {};
  bool _busy = false;
  bool _saved = false;

  bool get _esTrabajo => widget.kind == 'trabajo';
  bool get _isService => widget.kind == 'servicio';
  bool get _editing => widget.initial != null;
  int get _photoCount => _photos.length + _keptUrls.length;

  /// category_id + rubro del negocio: `provider_products` los exige NOT NULL
  /// y esta pantalla no los pide (el negocio ya los tiene). null mientras
  /// carga; (null, null) si el negocio no los tiene configurados. Solo hace
  /// falta al CREAR — al editar el ítem ya tiene los suyos y esta pantalla no
  /// los toca.
  ({String? categoryId, String? rubro})? _catRubro;

  /// Foto del formulario en su estado "limpio": vacío al crear, o lo que dejó
  /// [_prefill] al editar. La suciedad se decide comparando contra esto, no
  /// contra cadenas vacías — igual que `_cleanSnapshot` en
  /// `request_detail_screen.dart`. Así un campo nuevo prellenado (edición) no
  /// se confunde con un campo tocado por el usuario.
  String _cleanSnapshot = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _prefill(initial);
    _cleanSnapshot = _formSnapshot();
    takeUnsavedGuard(
      owner: this,
      check: _hasUnsavedWork,
      message: 'Perderás lo que escribiste aquí.',
    );
    // Sin negocio no hay nada que dar de alta: sin este corte se subían las
    // fotos a Storage (huérfanas) y el insert reventaba con un 22P02 traducido
    // al genérico "No se pudo guardar".
    if (widget.businessId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _toast('No encontramos tu negocio.');
        context.pop();
      });
      return;
    }
    // Al editar, categoría/rubro ya están en el ítem — no hace falta
    // consultarlos (y `_save` tampoco los toca).
    if (!_esTrabajo && !_editing) {
      widget.fetchCatRubro(widget.businessId).then((v) {
        if (mounted) setState(() => _catRubro = v);
      }).catchError((_) {
        // Se queda en NULL a propósito, no en `(null, null)`: eso significa
        // "todavía no se sabe" y deja que `_save` REINTENTE. Fijarlo a
        // (null, null) convertía un fallo de red pasajero en un "tu negocio no
        // tiene categoría" permanente, sin más salida que cerrar y volver.
      });
    }
  }

  /// Precarga TODO desde la fila de `provider_products` — columnas y
  /// `offer_defaults` (Task 6, modo edición).
  void _prefill(Map<String, dynamic> item) {
    _name.text = (item['name'] as String?) ?? '';
    _desc.text = (item['description'] as String?) ?? '';
    final price = item['price'] as num?;
    final min = item['price_min'] as num?;
    final max = item['price_max'] as num?;
    final defaults =
        (item['offer_defaults'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (_isService) {
      final mode = defaults[OfferDefaults.pricingMode] as String?;
      _svcMode = _svcModes.indexOf(mode ?? '').clamp(0, _svcModes.length - 1);
      if (price != null) _price.text = '$price';
      if (min != null) _min.text = '$min';
      if (max != null) _max.text = '$max';
      final hr = defaults[OfferDefaults.hourlyRate];
      if (hr != null) _hourly.text = '$hr';
      final hrs = defaults[OfferDefaults.estimatedHours];
      if (hrs != null) _hours.text = '$hrs';
      _availability.text = (defaults[OfferDefaults.availability] as String?) ?? '';
      _duration.text = (defaults[OfferDefaults.duration] as String?) ?? '';
    } else {
      // Rango si hay min/max guardados; fijo en cualquier otro caso
      // (incluido "sin precio todavía").
      _fixed = min == null && max == null;
      if (price != null) _price.text = '$price';
      if (min != null) _min.text = '$min';
      if (max != null) _max.text = '$max';
      final cond = item['condition'] as String?;
      _condition = cond == 'nuevo'
          ? 'Nuevo'
          : cond == 'usado'
          ? 'Usado'
          : '';
      _offersShipping = item['offers_shipping'] == true;
      _offersInstallation = item['offers_installation'] == true;
      _requiresEvaluation = item['requires_evaluation'] == true;
      final ship = defaults[OfferDefaults.shippingPrice];
      if (ship != null) _shipping.text = '$ship';
      final inst = defaults[OfferDefaults.installationPrice];
      if (inst != null) _installation.text = '$inst';
      final ev = defaults[OfferDefaults.evaluationPrice];
      if (ev != null) _evaluation.text = '$ev';
      _brand.text = (defaults[OfferDefaults.brand] as String?) ?? '';
      _warranty.text = (defaults[OfferDefaults.warranty] as String?) ?? '';
      _delivery.text = (defaults[OfferDefaults.delivery] as String?) ?? '';
      final cols = (defaults[OfferDefaults.colors] as List?)?.cast<String>();
      if (cols != null && cols.isNotEmpty) {
        _colors.addAll(cols);
      } else {
        final singleColor = item['color'] as String?;
        if (singleColor != null && singleColor.isNotEmpty) {
          _colors.add(singleColor);
        }
      }
    }
    final urls = (item['image_urls'] as List?)?.cast<String>() ?? const [];
    _keptUrls.addAll(urls);
  }

  @override
  void dispose() {
    releaseUnsavedGuard(this);
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _min.dispose();
    _max.dispose();
    _hourly.dispose();
    _hours.dispose();
    _availability.dispose();
    _duration.dispose();
    _shipping.dispose();
    _installation.dispose();
    _evaluation.dispose();
    _brand.dispose();
    _warranty.dispose();
    _delivery.dispose();
    super.dispose();
  }

  /// Serializa TODO lo que el usuario puede cambiar. Cualquier campo nuevo
  /// que se agregue a este editor debe sumarse aquí o el aviso de "salir sin
  /// guardar" no lo verá (mismo contrato que `_formSnapshot` en
  /// `request_detail_screen.dart`).
  String _formSnapshot() => [
    _name.text,
    _desc.text,
    _price.text,
    _min.text,
    _max.text,
    _hourly.text,
    _hours.text,
    _availability.text,
    _duration.text,
    _shipping.text,
    _installation.text,
    _evaluation.text,
    _brand.text,
    _warranty.text,
    _delivery.text,
    _condition,
    _colors.join(','),
    _offersShipping,
    _offersInstallation,
    _requiresEvaluation,
    _fixed,
    _svcMode,
    _photos.length,
    _keptUrls.join(','),
  ].join('|');

  bool _hasUnsavedWork() => !_saved && _formSnapshot() != _cleanSnapshot;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// Cámara = una foto; Galería = varias — mismo patrón que las fotos de una
  /// oferta (`request_detail_screen._pickPhoto`).
  Future<void> _pick(ImageSource source) async {
    if (_photoCount >= _maxItemPhotos) {
      _toast('Ya tienes $_maxItemPhotos fotos');
      return;
    }
    final List<XFile> picked;
    if (source == ImageSource.gallery) {
      picked = await guardedPick(
              (p) => p.pickMultiImage(maxWidth: 1200, imageQuality: 85)) ??
          const [];
    } else {
      final one = await guardedPick(
          (p) => p.pickImage(source: source, maxWidth: 1200, imageQuality: 85));
      picked = one == null ? const [] : [one];
    }
    if (picked.isEmpty) return;
    for (final x in picked) {
      final res = validatePickedImage(
          sizeBytes: await x.length(),
          path: x.path,
          currentCount: _photoCount,
          maxCount: _maxItemPhotos);
      if (res is ImagePickError) {
        _toast(res.message);
        break;
      }
      if (mounted) setState(() => _photos.add(x));
    }
  }

  /// Precio efectivo, según el molde de precio elegido: fijo → `price`;
  /// rango → `price_min`/`price_max`; por hora / a evaluar (solo servicio) →
  /// ninguna columna (esos dos van al `offer_defaults`). MISMA regla que
  /// `request_detail_screen.dart` calcula al armar `p`/`mn`/`mx` para
  /// `makeOffer`/`updateOffer`.
  String get _pricingMode {
    if (_isService) return _svcModes[_svcMode];
    return _fixed ? 'fixed' : 'range';
  }

  double? get _priceForMode =>
      _pricingMode == 'fixed' ? parseStoreItemPrice(_price.text)?.toDouble() : null;
  double? get _minForMode =>
      _pricingMode == 'range' ? parseStoreItemPrice(_min.text)?.toDouble() : null;
  double? get _maxForMode =>
      _pricingMode == 'range' ? parseStoreItemPrice(_max.text)?.toDouble() : null;
  double? get _hourlyValue => parseStoreItemPrice(_hourly.text)?.toDouble();
  num? get _hoursValue => num.tryParse(_hours.text.trim());

  String get _colorColumn =>
      _isService ? '' : (_colors.isEmpty ? '' : _colors.first);

  String? get _conditionColumn => _isService
      ? null
      : (_condition == 'Nuevo' ? 'nuevo' : (_condition == 'Usado' ? 'usado' : null));

  /// Mismo criterio que `offerFields` en `data/repos.dart`: el costo solo
  /// cuenta si el interruptor está activo Y es > 0 (0 = gratis, pero no se
  /// guarda como "costo").
  num? _gatedCost(bool toggle, double? value) =>
      (toggle && (value ?? 0) > 0) ? value : null;

  Map<String, dynamic> _offerDefaultsForSave() => buildOfferDefaults(
    pricingMode: _pricingMode,
    hourlyRate: _pricingMode == 'hourly' ? _hourlyValue : null,
    estimatedHours: _pricingMode == 'hourly' ? _hoursValue : null,
    availability: _isService ? _availability.text : null,
    duration: _isService ? _duration.text : null,
    shippingPrice:
        _isService ? null : _gatedCost(_offersShipping, parseStoreItemPrice(_shipping.text)?.toDouble()),
    installationPrice: _isService
        ? null
        : _gatedCost(_offersInstallation, parseStoreItemPrice(_installation.text)?.toDouble()),
    evaluationPrice: _isService
        ? null
        : _gatedCost(_requiresEvaluation, parseStoreItemPrice(_evaluation.text)?.toDouble()),
    brand: _isService ? null : _brand.text,
    warranty: _isService ? null : _warranty.text,
    delivery: _isService ? null : _delivery.text,
    colors: _isService ? const [] : _colors,
  );

  Future<void> _save() async {
    final nombre = _name.text.trim();
    if (nombre.isEmpty) {
      _toast(_esTrabajo
          ? 'Indica un título para el trabajo.'
          : 'Indica un nombre.');
      return;
    }
    // La compuerta de categoría/rubro solo aplica al CREAR producto/servicio;
    // con la carga aún en vuelo se reintenta aquí en vez de dejar el botón
    // muerto. Al editar no aplica: el ítem ya tiene los suyos.
    if (!_esTrabajo && !_editing) {
      _catRubro ??= await _fetchCatRubroSafely();
      // Los dos motivos por los que aquí puede faltar el dato NO se avisan
      // igual: null = no se pudo consultar (se reintenta al volver a pulsar);
      // (null, null) = el negocio de verdad no los tiene configurados.
      if (_catRubro == null) {
        _toast('No pudimos verificar tu negocio. Revisa tu conexión.');
        return;
      }
      if (_catRubro!.categoryId == null || _catRubro!.rubro == null) {
        _toast(
            'Tu negocio aún no tiene categoría y rubro. Complétalos desde "Editar en la web".');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      // Fotos a Storage ANTES del insert/update — nunca base64 en la BD.
      //
      // Cacheadas por ruta: si el guardado falla y el usuario reintenta (el
      // toast se lo pide), sin esto se volvían a subir los MISMOS ficheros y
      // se acumulaba una copia por intento.
      final newUrls = await Future.wait(_photos.map((x) async =>
          _uploaded[x.path] ??= await (_esTrabajo
              ? uploadPortfolioImage(x.path)
              : uploadStoreProductImage(x.path))));
      final imageUrls = [..._keptUrls, ...newUrls];
      if (_esTrabajo) {
        await widget.savePortfolio(
          businessId: widget.businessId,
          title: nombre,
          description: _desc.text,
          imageUrls: imageUrls,
        );
      } else if (_editing) {
        final defaults = _offerDefaultsForSave();
        await widget.updateItem(widget.initial!['id'] as String, {
          'name': nombre,
          'description': _desc.text.trim(),
          'image_urls': imageUrls,
          'color': _colorColumn,
          'condition': _conditionColumn,
          'price': _priceForMode,
          'price_min': _minForMode,
          'price_max': _maxForMode,
          'offers_shipping': _isService ? false : _offersShipping,
          'offers_installation': _isService ? false : _offersInstallation,
          'requires_evaluation': _isService ? false : _requiresEvaluation,
          if (defaults.isNotEmpty) 'offer_defaults': defaults,
        });
      } else {
        final defaults = _offerDefaultsForSave();
        await widget.saveProduct(
          businessId: widget.businessId,
          name: nombre,
          description: _desc.text.trim(),
          categoryId: _catRubro!.categoryId!,
          rubro: _catRubro!.rubro!,
          kind: widget.kind,
          color: _colorColumn,
          price: _priceForMode,
          priceMin: _minForMode,
          priceMax: _maxForMode,
          imageUrls: imageUrls,
          condition: _conditionColumn,
          offersShipping: _isService ? false : _offersShipping,
          offersInstallation: _isService ? false : _offersInstallation,
          requiresEvaluation: _isService ? false : _requiresEvaluation,
          offerDefaults: defaults.isEmpty ? null : defaults,
        );
      }
      _saved = true;
      releaseUnsavedGuard(this);
      if (!mounted) return;
      _toast(_esTrabajo
          ? 'Trabajo agregado.'
          : (_editing ? 'Cambios guardados.' : 'Agregado a tu tienda.'));
      // `true` = hubo cambio: "Mi negocio" refresca su listado al volver.
      context.pop(true);
    } catch (_) {
      _toast('No se pudo guardar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({String? categoryId, String? rubro})?> _fetchCatRubroSafely() async {
    try {
      return await widget.fetchCatRubro(widget.businessId);
    } catch (_) {
      return null;
    }
  }

  String get _titulo => switch (widget.kind) {
        'servicio' => _editing ? 'Editar servicio' : 'Agregar servicio',
        'trabajo' => 'Agregar trabajo',
        _ => _editing ? 'Editar producto' : 'Agregar producto',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            // Mismo aviso que el atrás del sistema: esta flecha no pasa por
            // BackGuard.
            onTap: () async {
              if (_hasUnsavedWork()) {
                final salir = await confirmDiscard(context);
                if (!salir) return;
                if (!context.mounted) return;
              }
              context.pop();
            },
          ),
          title: _titulo,
          titleAlign: HeaderTitleAlign.center,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 24 + navBarReservedSpace(context)),
            children: [
              if (_keptUrls.isNotEmpty || _photos.isNotEmpty)
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _keptUrls.length + _photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => i < _keptUrls.length
                        ? _keptThumb(_keptUrls[i], i)
                        : _localThumb(_photos[i - _keptUrls.length],
                            i - _keptUrls.length),
                  ),
                ),
              if (_photoCount < _maxItemPhotos)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Cámara'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galería'),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _esTrabajo ? 'Título del trabajo' : 'Nombre',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Descripción (opcional)'),
              ),
              if (!_esTrabajo) ...[
                const SizedBox(height: 12),
                _moldeSection(),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar'),
              ),
              const SizedBox(height: 8),
              Text(
                _esTrabajo
                    ? 'Los trabajos se muestran en tu tienda pública y puedes adjuntarlos a tus ofertas.'
                    : 'Al ofertar podrás elegirlo desde "Mi tienda" y autocompletar la oferta.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _keptThumb(String url, int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: JayaloNetworkImage(url,
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                  width: 88,
                  height: 88,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest)),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: () => setState(() => _keptUrls.removeAt(index)),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ]);

  Widget _localThumb(XFile x, int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(x.path),
              width: 88, height: 88, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: () => setState(() => _photos.removeAt(index)),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ]);

  /// «Detalles para tus ofertas (opcional)»: replica el molde del formulario
  /// de oferta, SIN validación obligatoria (es plantilla). Empieza expandida
  /// — antes de esta tarea el precio siempre estaba visible sin tocar nada;
  /// ocultarlo detrás de un tap sería una regresión.
  Widget _moldeSection() => ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
        title: const Text('Detalles para tus ofertas (opcional)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        children: _isService ? _serviceMoldeFields() : _productMoldeFields(),
      );

  List<Widget> _productMoldeFields() => [
        PillSegmented(
          options: const ['Precio fijo', 'Rango'],
          index: _fixed ? 0 : 1,
          onChanged: (i) => setState(() => _fixed = i == 0),
        ),
        const SizedBox(height: 12),
        if (_fixed)
          _numField(_price, 'Precio (RD\$)', key: const Key('campo-precio'))
        else
          Row(children: [
            Expanded(
                child: _numField(_min, 'Desde (RD\$)',
                    key: const Key('campo-precio-desde'))),
            const SizedBox(width: 8),
            Expanded(
                child: _numField(_max, 'Hasta (RD\$)',
                    key: const Key('campo-precio-hasta'))),
          ]),
        const SizedBox(height: 16),
        _toggleRow(
          title: 'Ofrezco envío',
          value: _offersShipping,
          onChanged: (v) => setState(() => _offersShipping = v),
          cost: _shipping,
          costLabel: 'Costo de envío (RD\$)',
          switchKey: const Key('switch-envio'),
        ),
        _toggleRow(
          title: 'Ofrezco instalación',
          value: _offersInstallation,
          onChanged: (v) => setState(() => _offersInstallation = v),
          cost: _installation,
          costLabel: 'Costo de instalación (RD\$)',
          switchKey: const Key('switch-instalacion'),
        ),
        _toggleRow(
          title: 'Requiere evaluación',
          value: _requiresEvaluation,
          onChanged: (v) => setState(() => _requiresEvaluation = v),
          cost: _evaluation,
          costLabel: 'Costo de evaluación (RD\$)',
          switchKey: const Key('switch-evaluacion'),
        ),
        const SizedBox(height: 8),
        _txtField(_brand, 'Marca', key: const Key('campo-marca')),
        const SizedBox(height: 14),
        _sectionLabel('Estado'),
        const SizedBox(height: 8),
        _chipSelect(
            kConditionOptions, _condition, (v) => setState(() => _condition = v)),
        const SizedBox(height: 14),
        _sectionLabel('Color'),
        const SizedBox(height: 8),
        _colorSwatches(),
        const SizedBox(height: 14),
        _sectionLabel('Garantía'),
        const SizedBox(height: 8),
        _chipSelect(kWarrantyOptions, _warranty.text,
            (v) => setState(() => _warranty.text = v)),
        const SizedBox(height: 14),
        _sectionLabel('Tiempo de entrega'),
        const SizedBox(height: 8),
        _chipSelect(kDeliveryOptions, _delivery.text,
            (v) => setState(() => _delivery.text = v)),
      ];

  List<Widget> _serviceMoldeFields() => [
        PillSegmented(
          options: const ['Fijo', 'Rango', 'Por hora', 'A evaluar'],
          index: _svcMode,
          onChanged: (i) => setState(() => _svcMode = i),
        ),
        const SizedBox(height: 12),
        ..._svcModeFields(),
        const SizedBox(height: 14),
        _sectionLabel('Disponibilidad'),
        const SizedBox(height: 8),
        _txtField(_availability, 'Ej: Fin de semana, a coordinar',
            key: const Key('campo-disponibilidad')),
        const SizedBox(height: 12),
        _txtField(_duration, 'Duración estimada (ej: 2 días)',
            key: const Key('campo-duracion')),
      ];

  List<Widget> _svcModeFields() {
    switch (_svcModes[_svcMode]) {
      case 'fixed':
        return [_numField(_price, 'Precio (RD\$)', key: const Key('campo-precio'))];
      case 'range':
        return [
          Row(children: [
            Expanded(
                child: _numField(_min, 'Desde (RD\$)',
                    key: const Key('campo-precio-desde'))),
            const SizedBox(width: 8),
            Expanded(
                child: _numField(_max, 'Hasta (RD\$)',
                    key: const Key('campo-precio-hasta'))),
          ]),
        ];
      case 'hourly':
        return [
          Row(children: [
            Expanded(
                child: _numField(_hourly, 'RD\$ por hora',
                    key: const Key('campo-precio-hora'))),
            const SizedBox(width: 8),
            Expanded(
                child: _numField(_hours, 'Horas est.',
                    key: const Key('campo-horas-est'))),
          ]),
        ];
      default: // needs_evaluation
        return [
          Text(
            'El precio se define tras revisar en sitio; el cliente lo verá como "a evaluar".',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ];
    }
  }

  Widget _numField(TextEditingController c, String label, {Key? key}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: filledField(context, label),
      );

  Widget _txtField(TextEditingController c, String label, {Key? key}) =>
      TextField(key: key, controller: c, decoration: filledField(context, label));

  Widget _sectionLabel(String t) =>
      Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));

  /// Chips de selección única (garantía, estado, entrega). Tocar el activo lo
  /// deselecciona — igual que en el formulario de oferta.
  Widget _chipSelect(
      List<String> options, String current, ValueChanged<String> onSelect) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        GestureDetector(
          onTap: () => onSelect(current == o ? '' : o),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: current == o ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(o,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: current == o ? cs.onPrimary : cs.onSurface)),
          ),
        ),
    ]);
  }

  /// Círculos de color multi-selección (paridad con el formulario de oferta).
  Widget _colorSwatches() {
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: 12, runSpacing: 10, children: [
      for (final (label, color) in _colorPresets)
        GestureDetector(
          onTap: () => setState(() => _colors.contains(label)
              ? _colors.remove(label)
              : _colors.add(label)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: _colors.contains(label)
                        ? cs.primary
                        : cs.outlineVariant,
                    width: _colors.contains(label) ? 3 : 1),
              ),
              child: _colors.contains(label)
                  ? Icon(Icons.check,
                      size: 16,
                      color: color.computeLuminance() > .6
                          ? Colors.black54
                          : Colors.white)
                  : null,
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant)),
          ]),
        ),
    ]);
  }

  /// Interruptor + costo opcional, con "Gratis" cuando el costo es 0 — mismo
  /// molde que `_toggleRow` de `request_detail_screen.dart`.
  Widget _toggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required TextEditingController cost,
    required String costLabel,
    Key? switchKey,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final free = value && (double.tryParse(cost.text) ?? 0) <= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Switch(
              key: switchKey, value: value, onChanged: _busy ? null : onChanged),
        ]),
        if (value)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(children: [
              Expanded(child: _numField(cost, costLabel)),
              const SizedBox(width: 12),
              if (free)
                Text('Gratis',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? JayaloColors.dSuccess
                            : JayaloColors.success)),
            ]),
          ),
      ]),
    );
  }
}
