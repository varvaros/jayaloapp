import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/brand.dart';
import '../../core/safe_image_picker.dart';
import '../../data/repos.dart';
import '../../domain/catalog.dart';
import '../../domain/contact_info.dart';
import '../../domain/image_pick.dart';
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Tope de fotos por producto — el mismo que la oferta, para que "De mi tienda"
/// nunca traiga más de las que caben en una oferta.
const maxProductPhotos = 5;

/// Presets de color y garantía: los MISMOS que el formulario de oferta
/// (`request_detail_screen.dart`), para que un producto guardado desde una
/// oferta y luego editado aquí no cambie de vocabulario a mitad de camino.
const _colorPresets = <String>[
  'Negro', 'Blanco', 'Gris', 'Rojo', 'Azul', 'Verde',
  'Amarillo', 'Beige', 'Marrón', 'Rosa',
];
const _warrantyPresets = <String>[
  'Sin garantía', '3 días', '7 días', '15 días', '1 mes',
  '3 meses', '6 meses', '1 año', '2 años', '5 años', '10 años',
];
const _conditionOptions = <String>['Nuevo', 'Usado'];

/// Cómo se cotiza el producto. El orden es el de [PillSegmented] en la UI.
enum ProductPriceMode { fijo, rango, consultar }

/// Lo que el formulario devuelve al guardar. Un record (no un mapa suelto) para
/// que el test inyecte `onSave` y compruebe EXACTAMENTE lo que se guardaría sin
/// tocar la red — mismo patrón que `MyBusinessView.onEditWeb`.
typedef ProductEdit = ({
  String name,
  String description,
  String categoryId,
  String color,
  double? price,
  double? priceMin,
  double? priceMax,
  List<String> keptUrls,
  List<XFile> newPhotos,
  String? condition,
  String? brand,
  String? warranty,
  bool offersShipping,
  bool offersInstallation,
  bool requiresEvaluation,
});

/// Editor de un producto/servicio de la tienda (pedido PO 2026-08-08: "debe
/// permitir editar el producto desde la app"). Hasta hoy "Mi negocio" era un
/// escaparate de SOLO LECTURA cuyo único camino de edición era el magic-link
/// que sacaba al proveedor de la app ("Editar en la web").
///
/// La pantalla hace la E/S (cargar, subir fotos, guardar); [EditProductForm]
/// solo dibuja.
class EditProductScreen extends StatefulWidget {
  const EditProductScreen({super.key, required this.productId});
  final String productId;

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  late Future<Map<String, dynamic>?> _load = storeProductForEdit(
    widget.productId,
  );
  bool _busy = false;

  void _refetch() => setState(() {
        _load = storeProductForEdit(widget.productId);
      });

  /// Sube las fotos nuevas y guarda. Devuelve `true` si se guardó, para que el
  /// formulario sepa si puede cerrar.
  Future<bool> _save(ProductEdit edit, Map<String, dynamic> original) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      // Chequeo local ANTES de subir fotos: un JY422 después de subir 5 fotos
      // deja basura en Storage y le cuesta datos al proveedor. `updateStoreProduct`
      // vuelve a barrer el payload entero y el trigger de la BD es la autoridad.
      final vigilados = [
        edit.name,
        edit.description,
        edit.color,
        edit.brand ?? '',
        edit.warranty ?? '',
      ];
      if (vigilados.any(containsContactInfo)) {
        _toast(contactInfoMessage);
        return false;
      }
      final subidas = <String>[];
      for (final x in edit.newPhotos) {
        subidas.add(await uploadProductImage(x.path));
      }
      await updateStoreProduct(
        productId: widget.productId,
        name: edit.name,
        description: edit.description,
        categoryId: edit.categoryId,
        // El tipo NO se edita: mover un producto a servicio (o al revés) lo
        // cambiaría de sección en la tienda y en el catálogo sin que nadie lo
        // pida. Se reenvía el que ya tenía porque el UPDATE escribe la fila.
        kind: original['kind'] as String? ?? 'producto',
        color: edit.color,
        price: edit.price,
        priceMin: edit.priceMin,
        priceMax: edit.priceMax,
        imageUrls: [...edit.keptUrls, ...subidas],
        condition: edit.condition,
        brand: edit.brand,
        warranty: edit.warranty,
        offersShipping: edit.offersShipping,
        offersInstallation: edit.offersInstallation,
        requiresEvaluation: edit.requiresEvaluation,
      );
      return true;
    } catch (e) {
      _toast(isContactInfoError(e)
          ? contactInfoMessage
          : 'No se pudo guardar. Intenta de nuevo.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) showJayaloToast(context, m);
  }

  /// Cierra el editor tras un guardado exitoso. Devuelve `true` a quien lo
  /// abrió ("Mi negocio" y el detalle del producto) para que refresque: acaba
  /// de cambiar el precio o la foto y su `Future` ya cargado tiene la versión
  /// vieja. El `go` es la red de seguridad para cuando esta ruta es la primera
  /// de la pila (deep-link) y no hay a dónde volver.
  void _closeAfterSave() {
    if (!mounted) return;
    _toast('Guardado ✓');
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop(true);
    } else {
      router.go('/provider/business');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          VioletHeader(
            leading: HeaderCircleButton(
              icon: Icons.arrow_back_ios_new,
              tooltip: 'Atrás',
              onTap: () => context.pop(),
            ),
            title: 'Editar',
            titleAlign: HeaderTitleAlign.center,
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorRetry(onRetry: () async => _refetch());
                }
                if (!snap.hasData && snap.connectionState != ConnectionState.done) {
                  return const JayaloLoaderBlock();
                }
                final product = snap.data;
                if (product == null) {
                  return const EmptyState(
                    message: 'No encontramos este producto.\n\n'
                        'Puede que lo hayas eliminado desde la web.',
                  );
                }
                // La RLS ya impide guardar sobre una fila ajena, pero
                // `provider_products` es de lectura PÚBLICA: sin esto, entrar
                // por la URL a un producto de otro abriría un formulario que
                // guarda "bien" sin cambiar nada.
                if (product['user_id'] != supa.auth.currentUser?.id) {
                  return const EmptyState(
                    message: 'Este producto no es tuyo, así que no puedes '
                        'editarlo.',
                  );
                }
                return EditProductForm(
                  product: product,
                  busy: _busy,
                  onSave: (edit) async {
                    final ok = await _save(edit, product);
                    if (ok) _closeAfterSave();
                    return ok;
                  },
                );
              },
            ),
          ),
        ]),
      );
}

/// Solo dibuja. Recibe la fila cruda de `provider_products` y entrega un
/// [ProductEdit] al guardar — sin red, para poder probarlo entero.
class EditProductForm extends StatefulWidget {
  const EditProductForm({
    super.key,
    required this.product,
    required this.onSave,
    this.busy = false,
  });

  final Map<String, dynamic> product;

  /// Guarda. Devuelve `true` si se guardó (el formulario deja de estar sucio).
  final Future<bool> Function(ProductEdit edit) onSave;
  final bool busy;

  @override
  State<EditProductForm> createState() => _EditProductFormState();
}

class _EditProductFormState extends State<EditProductForm> {
  final _scroll = ScrollController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _brand = TextEditingController();

  late ProductPriceMode _mode;
  late String _categoryId;
  String _color = '';
  String _condition = '';
  String _warranty = '';
  bool _offersShipping = false;
  bool _offersInstallation = false;
  bool _requiresEvaluation = false;
  final List<String> _keptUrls = [];
  final List<XFile> _photos = [];

  /// Falta el nombre → no se puede guardar (`name` es NOT NULL y un producto
  /// sin nombre es invisible en el catálogo).
  bool get _valid => _name.text.trim().isNotEmpty;
  bool get _isService => widget.product['kind'] == 'servicio';
  int get _photoCount => _photos.length + _keptUrls.length;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name.text = p['name'] as String? ?? '';
    _description.text = p['description'] as String? ?? '';
    _brand.text = p['brand'] as String? ?? '';
    _categoryId = _validCategory(p['category_id'] as String?);
    _color = p['color'] as String? ?? '';
    _warranty = p['warranty'] as String? ?? '';
    // `condition` viaja en minúsculas en la BD; los chips son capitalizados.
    _condition = switch (p['condition']) {
      'nuevo' => 'Nuevo',
      'usado' => 'Usado',
      _ => '',
    };
    _offersShipping = p['offers_shipping'] == true;
    _offersInstallation = p['offers_installation'] == true;
    _requiresEvaluation = p['requires_evaluation'] == true;
    _keptUrls.addAll(
      ((p['image_urls'] as List?) ?? const []).whereType<String>(),
    );

    final price = p['price'] as num?;
    final min = p['price_min'] as num?;
    final max = p['price_max'] as num?;
    if (price != null) {
      _mode = ProductPriceMode.fijo;
      _price.text = _plain(price);
    } else if (min != null || max != null) {
      _mode = ProductPriceMode.rango;
      _min.text = min == null ? '' : _plain(min);
      _max.text = max == null ? '' : _plain(max);
    } else {
      _mode = ProductPriceMode.consultar;
    }
  }

  /// La categoría guardada puede haber salido del catálogo (la lista es un mock
  /// versionado, no una tabla): en ese caso el desplegable no tendría un ítem
  /// que la respalde y Flutter revienta con un assert. Se cae a la primera.
  static String _validCategory(String? id) =>
      kCategories.any((c) => c.id == id) ? id! : kCategories.first.id;

  /// Un número de la BD tal cual, sin separadores ni `.0` de más: es lo que se
  /// vuelve a parsear al guardar.
  static String _plain(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _scroll.dispose();
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _min.dispose();
    _max.dispose();
    _brand.dispose();
    super.dispose();
  }

  /// Solo la coma de miles molesta al parseo; el resto lo filtra el teclado.
  static double? _num(String s) =>
      double.tryParse(s.replaceAll(',', '').trim());

  ProductEdit _collect() => (
        name: _name.text.trim(),
        description: _description.text.trim(),
        categoryId: _categoryId,
        color: _isService ? '' : _color,
        price: _mode == ProductPriceMode.fijo ? _num(_price.text) : null,
        priceMin: _mode == ProductPriceMode.rango ? _num(_min.text) : null,
        priceMax: _mode == ProductPriceMode.rango ? _num(_max.text) : null,
        keptUrls: List.of(_keptUrls),
        newPhotos: List.of(_photos),
        condition: _isService || _condition.isEmpty
            ? null
            : _condition.toLowerCase(),
        brand: _isService ? null : _brand.text.trim(),
        warranty: _isService ? null : _warranty,
        offersShipping: _isService ? false : _offersShipping,
        offersInstallation: _isService ? false : _offersInstallation,
        requiresEvaluation: _requiresEvaluation,
      );

  Future<void> _pickPhoto(ImageSource source) async {
    final List<XFile> picked;
    if (source == ImageSource.gallery) {
      picked = await guardedPick(
              (p) => p.pickMultiImage(maxWidth: 1200, imageQuality: 85)) ??
          const [];
    } else {
      final one = await guardedPick((p) =>
          p.pickImage(source: source, maxWidth: 1200, imageQuality: 85));
      picked = one == null ? const [] : [one];
    }
    if (picked.isEmpty) return;
    for (final x in picked) {
      final res = validatePickedImage(
        sizeBytes: await x.length(),
        path: x.path,
        currentCount: _photoCount,
        maxCount: maxProductPhotos,
      );
      if (res is ImagePickError) {
        if (mounted) showJayaloToast(context, res.message);
        break;
      }
      if (mounted) setState(() => _photos.add(x));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + navBarReservedSpace(context),
      ),
      children: [
        TextField(
          controller: _name,
          enabled: !busy,
          decoration: filledField(context, 'Nombre'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          enabled: !busy,
          minLines: 3,
          maxLines: 6,
          decoration: filledField(context, 'Descripción'),
        ),
        const SizedBox(height: 18),
        _label('Categoría'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _categoryId,
          decoration: filledField(context, 'Categoría'),
          items: [
            for (final c in kCategories)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged:
              busy ? null : (v) => setState(() => _categoryId = v ?? _categoryId),
        ),
        const SizedBox(height: 18),
        _label('Precio'),
        const SizedBox(height: 8),
        PillSegmented(
          options: const ['Fijo', 'Rango', 'Consultar'],
          index: _mode.index,
          onChanged: busy
              ? (_) {}
              : (i) => setState(() => _mode = ProductPriceMode.values[i]),
        ),
        const SizedBox(height: 10),
        if (_mode == ProductPriceMode.fijo)
          TextField(
            controller: _price,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: filledField(context, 'Precio (RD\$)'),
          )
        else if (_mode == ProductPriceMode.rango)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _min,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: filledField(context, 'Desde (RD\$)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _max,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: filledField(context, 'Hasta (RD\$)'),
              ),
            ),
          ])
        else
          Text(
            'Se mostrará como "Consultar precio".',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (!_isService) ...[
          const SizedBox(height: 18),
          _label('Estado'),
          const SizedBox(height: 8),
          _chips(_conditionOptions, _condition,
              (v) => setState(() => _condition = v)),
          const SizedBox(height: 18),
          _label('Color'),
          const SizedBox(height: 8),
          _chips(_colorPresets, _color, (v) => setState(() => _color = v)),
          const SizedBox(height: 18),
          TextField(
            controller: _brand,
            enabled: !busy,
            decoration: filledField(context, 'Marca (opcional)'),
          ),
          const SizedBox(height: 18),
          _label('Garantía'),
          const SizedBox(height: 8),
          _chips(_warrantyPresets, _warranty,
              (v) => setState(() => _warranty = v)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _offersShipping,
            onChanged:
                busy ? null : (v) => setState(() => _offersShipping = v),
            title: const Text('Ofrezco envío'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _offersInstallation,
            onChanged:
                busy ? null : (v) => setState(() => _offersInstallation = v),
            title: const Text('Ofrezco instalación'),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _requiresEvaluation,
          onChanged:
              busy ? null : (v) => setState(() => _requiresEvaluation = v),
          title: const Text('Requiere evaluación previa'),
        ),
        const SizedBox(height: 12),
        _label('Fotos (hasta $maxProductPhotos)'),
        const SizedBox(height: 8),
        if (_photoCount > 0)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _keptUrls.length; i++) _keptThumb(i),
            for (var i = 0; i < _photos.length; i++) _newThumb(i),
          ]),
        if (_photoCount < maxProductPhotos)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      busy ? null : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería'),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed:
              busy || !_valid ? null : () => widget.onSave(_collect()),
          child: busy
              ? const SizedBox(
                  width: 18, height: 18, child: JayaloSpinner())
              : const Text('Guardar cambios'),
        ),
      ],
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: jayaloHead(context)));

  /// Chips de selección única con des-selección al volver a tocar — el mismo
  /// gesto que el formulario de oferta.
  Widget _chips(
    List<String> options,
    String current,
    ValueChanged<String> onSelect,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        GestureDetector(
          onTap: widget.busy ? null : () => onSelect(current == o ? '' : o),
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

  /// Foto YA publicada (URL de Storage). Quitarla la saca de [_keptUrls]; el
  /// objeto sigue en el bucket (no se borra: otra oferta puede referenciarlo).
  Widget _keptThumb(int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: JayaloNetworkImage(
            _keptUrls[index],
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 76,
              height: 76,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.cancel, size: 22),
            onPressed: widget.busy
                ? null
                : () => setState(() => _keptUrls.removeAt(index)),
          ),
        ),
      ]);

  /// Foto recién elegida, todavía sin subir.
  Widget _newThumb(int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(_photos[index].path),
              width: 76, height: 76, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.cancel, size: 22),
            onPressed: widget.busy
                ? null
                : () => setState(() => _photos.removeAt(index)),
          ),
        ),
      ]);
}
