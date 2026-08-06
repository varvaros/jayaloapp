import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/safe_image_picker.dart';
import '../../core/unsaved_guard.dart';
import '../../data/repos.dart';
import '../../domain/image_pick.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Mismo tope que las fotos de una oferta: estos artículos existen para
/// autocompletar ofertas, no tiene sentido que carguen más que ellas.
const _maxItemPhotos = 5;

/// Convierte lo escrito en el campo de precio ("5,000", "RD$5000") a un
/// número; null si está vacío. Solo dígitos — mismo criterio que el campo de
/// presupuesto de crear solicitud.
num? parseStoreItemPrice(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

/// Alta rápida desde la app de un artículo de la tienda (pedido PO
/// 2026-08-05: el agregador de "Mi negocio"). Tres variantes por [kind]:
/// `producto` y `servicio` insertan en `provider_products` (el write que ya
/// existía para "¿guardar lo ofertado en mi tienda?"); `trabajo` inserta en
/// `provider_portfolio_items`. La edición completa sigue viviendo en la web —
/// esto solo cubre el alta mínima que hace más rápida una oferta futura.
class AddStoreItemScreen extends StatefulWidget {
  const AddStoreItemScreen({
    super.key,
    required this.kind,
    required this.businessId,
  });

  /// 'producto' | 'servicio' | 'trabajo'.
  final String kind;

  /// Viene en la ruta desde "Mi negocio", que ya lo tiene cargado — así esta
  /// pantalla no repite el fetch del perfil.
  final String businessId;

  @override
  State<AddStoreItemScreen> createState() => _AddStoreItemScreenState();
}

class _AddStoreItemScreenState extends State<AddStoreItemScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final List<XFile> _photos = [];

  /// Ruta local → URL ya subida. Evita re-subir el mismo fichero en cada
  /// reintento del guardado (ver `_save`).
  final Map<String, String> _uploaded = {};
  bool _busy = false;
  bool _saved = false;

  bool get _esTrabajo => widget.kind == 'trabajo';

  /// category_id + rubro del negocio: `provider_products` los exige NOT NULL
  /// y esta pantalla no los pide (el negocio ya los tiene). null mientras
  /// carga; (null, null) si el negocio no los tiene configurados.
  ({String? categoryId, String? rubro})? _catRubro;

  @override
  void initState() {
    super.initState();
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
    if (!_esTrabajo) {
      myBusinessCategoryRubro(widget.businessId).then((v) {
        if (mounted) setState(() => _catRubro = v);
      }).catchError((_) {
        // Se queda en NULL a propósito, no en `(null, null)`: eso significa
        // "todavía no se sabe" y deja que `_save` REINTENTE. Fijarlo a
        // (null, null) convertía un fallo de red pasajero en un "tu negocio no
        // tiene categoría" permanente, sin más salida que cerrar y volver.
      });
    }
  }

  @override
  void dispose() {
    releaseUnsavedGuard(this);
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  bool _hasUnsavedWork() {
    if (_saved) return false;
    return _name.text.trim().isNotEmpty ||
        _desc.text.trim().isNotEmpty ||
        _price.text.trim().isNotEmpty ||
        _photos.isNotEmpty;
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// Cámara = una foto; Galería = varias — mismo patrón que las fotos de una
  /// oferta (`request_detail_screen._pickPhoto`).
  Future<void> _pick(ImageSource source) async {
    if (_photos.length >= _maxItemPhotos) {
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
          currentCount: _photos.length,
          maxCount: _maxItemPhotos);
      if (res is ImagePickError) {
        _toast(res.message);
        break;
      }
      if (mounted) setState(() => _photos.add(x));
    }
  }

  Future<void> _save() async {
    final nombre = _name.text.trim();
    if (nombre.isEmpty) {
      _toast(_esTrabajo
          ? 'Indica un título para el trabajo.'
          : 'Indica un nombre.');
      return;
    }
    // La compuerta de categoría/rubro solo aplica a producto/servicio; con la
    // carga aún en vuelo se reintenta aquí en vez de dejar el botón muerto.
    if (!_esTrabajo) {
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
      // Fotos a Storage ANTES del insert — nunca base64 en la BD.
      //
      // Cacheadas por ruta: si el insert falla y el usuario reintenta (el toast
      // se lo pide), sin esto se volvían a subir los MISMOS ficheros y se
      // acumulaba una copia por intento.
      final urls = await Future.wait(_photos.map((x) async =>
          _uploaded[x.path] ??= await (_esTrabajo
              ? uploadPortfolioImage(x.path)
              : uploadStoreProductImage(x.path))));
      if (_esTrabajo) {
        await savePortfolioItem(
          businessId: widget.businessId,
          title: nombre,
          description: _desc.text,
          imageUrls: urls,
        );
      } else {
        await saveProductToStore(
          businessId: widget.businessId,
          name: nombre,
          description: _desc.text.trim(),
          categoryId: _catRubro!.categoryId!,
          rubro: _catRubro!.rubro!,
          kind: widget.kind,
          price: parseStoreItemPrice(_price.text)?.toDouble(),
          imageUrls: urls,
        );
      }
      _saved = true;
      releaseUnsavedGuard(this);
      if (!mounted) return;
      _toast(_esTrabajo ? 'Trabajo agregado.' : 'Agregado a tu tienda.');
      // `true` = hubo alta: "Mi negocio" refresca su listado al volver.
      context.pop(true);
    } catch (_) {
      _toast('No se pudo guardar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({String? categoryId, String? rubro})?> _fetchCatRubroSafely() async {
    try {
      return await myBusinessCategoryRubro(widget.businessId);
    } catch (_) {
      return null;
    }
  }

  String get _titulo => switch (widget.kind) {
        'servicio' => 'Agregar servicio',
        'trabajo' => 'Agregar trabajo',
        _ => 'Agregar producto',
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
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(_photos[i].path),
                            width: 88, height: 88, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              if (_photos.length < _maxItemPhotos)
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
                TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio en RD\$ (opcional)',
                    helperText: 'Sin precio se muestra "Consultar precio".',
                  ),
                ),
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
}
