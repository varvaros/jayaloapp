import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../../core/brand.dart';
import '../../core/error_reporter.dart';
import '../../core/safe_image_picker.dart';
import '../../core/unsaved_guard.dart';
import '../../data/portfolio_media.dart' show PortfolioMedia, parseMedia;
import '../../data/repos.dart';
import '../../domain/contact_info.dart' show contactInfoMessage, isContactInfoError;
import '../../domain/image_pick.dart';
import '../../domain/money.dart' show parseMiles;
import '../../domain/offer_defaults.dart';
import '../../domain/video_pick.dart';
import '../shared/brand_kit.dart';
import '../shared/network_image.dart';
import '../shared/offer_field_options.dart';
import '../shared/violet_header.dart';
import '../shell/floating_nav_bar.dart';

/// Mismo tope que las fotos de una oferta: estos artículos existen para
/// autocompletar ofertas, no tiene sentido que carguen más que ellas.
const _maxItemPhotos = 5;

/// Tope de ARCHIVOS de un trabajo del portafolio — espejo de
/// `MAX_PORTFOLIO_PHOTOS` en la web. Más alto que [_maxItemPhotos]: un
/// trabajo terminado suele necesitar más fotos que un producto/servicio de
/// catálogo (antes de la Task 8, `_pick` no distinguía kind y aplicaba el
/// tope de 5 también a trabajo — nunca se imponía el tope correcto).
///
/// Desde la Task 13 (video) el nombre queda corto a propósito: sigue siendo
/// UNA sola constante, pero pasa a contar fotos + videos JUNTOS (8 archivos
/// totales por trabajo, corrección del PO sobre el brief) — ver
/// [_AddStoreItemScreenState._fileCount]. Producto/servicio nunca tienen
/// video, así que ahí sigue significando "fotos" sin más.
const kMaxPortfolioPhotos = 8;

/// Tope de VIDEOS de un trabajo del portafolio (Task 13, corrección del PO
/// sobre el brief original) — distinto del tope de archivos de arriba: un
/// trabajo puede tener hasta 8 archivos, pero como máximo 2 de ellos pueden
/// ser video. El techo de 10 videos por NEGOCIO existe pero es del trigger
/// de la base de datos — no se cuenta aquí.
const kMaxPortfolioVideos = 2;

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

/// Video local recien elegido y comprimido (Task 13): `path` es el archivo
/// YA comprimido (lo que se sube), `posterPath` es la miniatura local (o
/// `null` si `getFileThumbnail` falló — el video se sube igual, la tarjeta
/// degrada al placeholder, NUNCA al .mp4, ver `data/portfolio_media.dart`).
typedef _PickedVideo = ({
  String path,
  String? posterPath,
  int durationSeconds,
});

/// Content-type de una foto por extensión, para [uploadPortfolioMedia] (que
/// a diferencia de `_uploadMarketplaceImage` en `repos.dart` no lo infiere
/// solo — lo decide quien llama). Mismo mapeo que el `_imageContentType`
/// privado de `repos.dart`, pero no se puede importar (es privado a ese
/// fichero) — se duplica aquí, son 3 líneas.
String _imageContentTypeFor(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

/// Convierte lo escrito en el campo de precio ("5,000", "RD$5000",
/// "3000.50") a un número; null si está vacío.
///
/// BUG PO 08-09: la versión anterior descartaba TODO carácter no-dígito, así
/// que "3000.0" (un usuario tipeando con separador decimal) se leía como
/// "30000" — pasó en prod con un paquete real. Los precios RD$ son enteros,
/// así que un punto o coma ÚNICO seguido de 1-2 dígitos AL FINAL del string
/// se trata como separador DECIMAL y se redondea (`round()`, no se trunca:
/// "3000.50" → 3001). Un punto/coma seguido de exactamente 3 dígitos sigue
/// siendo separador de MILES, como ya hacía antes ("3.000"/"1,500" → 3000/
/// 1500) — ese caso, y cualquier otro, cae al camino de solo-dígitos de
/// siempre.
num? parseStoreItemPrice(String s) => parseMiles(s);

/// Alta rápida O EDICIÓN desde la app de un artículo de la tienda (pedido PO
/// 2026-08-05: el agregador de "Mi negocio"; edición producto/servicio Task
/// 6, edición trabajo Task 8, ambas 2026-08-09). Tres variantes por [kind]:
/// `producto` y `servicio` escriben en `provider_products` (alta:
/// `saveProductToStore`; edición: `updateStoreItem`, vía [initial]);
/// `trabajo` escribe en `provider_portfolio_items` (alta: `savePortfolio`;
/// edición: `updatePortfolio`, vía [initial] — Task 8).
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
    this.updatePortfolio = updatePortfolioItem,
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
    String? brand,
    String? warranty,
    Map<String, dynamic>? offerDefaults,
  })
  saveProduct;
  final Future<void> Function(String id, Map<String, dynamic> payload)
  updateItem;
  /// Firma con `media` (Task 13, no `imageUrls`): [savePortfolioItem]
  /// escribe la columna `media` completa Y el espejo `image_urls` (solo
  /// imágenes) a partir de ella — ver `data/repos.dart`.
  final Future<void> Function({
    required String businessId,
    required String title,
    String? description,
    List<PortfolioMedia> media,
  })
  savePortfolio;

  /// Edición de un trabajo propio (Task 8), vía [initial]. Mismo criterio
  /// inyectable que [updateItem]; mismo cambio a `media` que [savePortfolio]
  /// (Task 13).
  final Future<void> Function(
    String id, {
    required String title,
    String? description,
    required List<PortfolioMedia> media,
  })
  updatePortfolio;
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
  /// en `request_detail_screen.dart`. Para trabajo, se prellena desde
  /// `media` (Task 13) — solo la parte imagen, ver [_prefill].
  final List<String> _keptUrls = [];

  /// Videos YA subidos de un trabajo (edición) que se conservan salvo que
  /// el usuario los quite — mismo trato que [_keptUrls] pero con el objeto
  /// completo (necesitamos `poster`/`duration`, no solo la URL). Solo
  /// aplica a `trabajo` (Task 13); producto/servicio nunca tienen video.
  final List<PortfolioMedia> _keptVideos = [];

  /// Videos NUEVOS de un trabajo: ya comprimidos a 720p y con su poster
  /// local (si `getFileThumbnail` no falló), esperando subirse en `_save`.
  final List<_PickedVideo> _newVideos = [];

  /// Ruta local → URL ya subida. Evita re-subir el mismo fichero en cada
  /// reintento del guardado (ver `_save`). Compartida entre fotos y videos
  /// (Task 13): la clave es la ruta local, así que no colisiona.
  final Map<String, String> _uploaded = {};
  bool _busy = false;
  bool _saved = false;

  /// Video eligiéndose/comprimiéndose — deshabilita el botón «Agregar
  /// video» mientras dura (puede tardar varios segundos).
  bool _compressingVideo = false;

  /// Progreso de subida de un trabajo con archivos nuevos (Task 13): `0`
  /// mientras no se está subiendo nada. Antes de esto la subida ocurría a
  /// ciegas — con 10 MB de video por datos móviles son minutos de spinner
  /// sin saber si avanza.
  int _uploadTotal = 0;
  int _uploadDone = 0;
  bool get _uploading => _uploadTotal > 0;

  bool get _esTrabajo => widget.kind == 'trabajo';
  bool get _isService => widget.kind == 'servicio';
  bool get _editing => widget.initial != null;
  int get _photoCount => _photos.length + _keptUrls.length;

  /// Videos de un trabajo, conservados + nuevos. Siempre 0 para
  /// producto/servicio (esos `kind` nunca tienen video) — Task 13.
  int get _videoCount => _keptVideos.length + _newVideos.length;

  /// Archivos TOTALES (fotos + videos) — el tope de 8 de [kMaxPortfolioPhotos]
  /// se aplica a esta suma, no solo a fotos (Task 13). Para producto/servicio
  /// [_videoCount] es siempre 0, así que coincide con [_photoCount] — sin
  /// cambio de comportamiento ahí.
  int get _fileCount => _photoCount + _videoCount;

  /// Tope de fotos según [kind] — [kMaxPortfolioPhotos] para trabajo
  /// (Task 8), [_maxItemPhotos] para producto/servicio.
  int get _maxPhotos => _esTrabajo ? kMaxPortfolioPhotos : _maxItemPhotos;

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

  /// Precarga desde `initial` (Task 6 para producto/servicio, Task 8 para
  /// trabajo). Trabajo tiene su propio camino, MÁS CORTO: `provider_portfolio_items`
  /// no tiene molde de oferta ni ninguna de las columnas de producto —
  /// mezclarlo con el resto del método leería columnas que ese registro
  /// nunca tiene (no revienta, `item['x']` en un `Map` da `null`, pero es
  /// semánticamente incorrecto y confunde a quien lea esto después).
  void _prefill(Map<String, dynamic> item) {
    if (_esTrabajo) {
      _name.text = (item['title'] as String?) ?? '';
      _desc.text = (item['description'] as String?) ?? '';
      // Task 13: `parseMedia` ya sabe reconstruir desde `image_urls` si
      // `media` viene vacío (filas escritas antes de esta migración) — no
      // hay que replicar ese fallback aquí. Se separa por `kind` porque
      // [_keptUrls] (compartido con producto/servicio) solo lleva imágenes.
      for (final m in parseMedia(item['media'], item['image_urls'])) {
        if (m.esVideo) {
          _keptVideos.add(m);
        } else {
          _keptUrls.add(m.url);
        }
      }
      return;
    }
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
      if (mode != null) {
        final idx = _svcModes.indexOf(mode);
        _svcMode = idx < 0 ? 0 : idx;
      } else {
        // Legacy (revisión Fix round 1, Critical 2): ítem de servicio
        // creado antes de la Task 6, sin `offer_defaults`. El modo se
        // perdió, pero min/max sobreviven en las columnas — derivarlo de
        // ahí evita que "Guardar" sin tocar nada borre en silencio un rango
        // ya guardado (asumir 'fixed' a ciegas mandaba
        // price_min/price_max = null en el siguiente save).
        _svcMode = (min != null || max != null) ? 1 : 0;
      }
      if (price != null) _price.text = '$price';
      if (min != null) _min.text = '$min';
      if (max != null) _max.text = '$max';
      final hr = defaults[OfferDefaults.hourlyRate];
      if (hr != null) _hourly.text = '$hr';
      final hrs = defaults[OfferDefaults.estimatedHours];
      if (hrs != null) _hours.text = '$hrs';
      _availability.text = (defaults[OfferDefaults.availability] as String?) ?? '';
      _duration.text = (defaults[OfferDefaults.duration] as String?) ?? '';
      // Hallazgo I-1 (revisión final): `warranty` es columna REAL también
      // para un servicio (paridad con la web) — mismo criterio que la rama
      // de producto de abajo, la columna real gana sobre el jsonb.
      _warranty.text = (item['warranty'] as String?) ??
          (defaults[OfferDefaults.warranty] as String?) ??
          '';
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
      // Fix round 1 (Important 4): `brand`/`warranty` son columnas REALES de
      // `provider_products` (las pinta `productDetail`) — se leen de ahí
      // primero; el jsonb es solo un fallback para el caso raro de un dato
      // que llegó a `offer_defaults` sin su columna gemela.
      _brand.text = (item['brand'] as String?) ??
          (defaults[OfferDefaults.brand] as String?) ??
          '';
      _warranty.text = (item['warranty'] as String?) ??
          (defaults[OfferDefaults.warranty] as String?) ??
          '';
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
    // Limpieza best-effort de los temporales que dejó `video_compress` si el
    // usuario picó un video y salió sin guardar (Task 13) — nunca bloquea el
    // dispose ni se reporta: es higiene, no correctness.
    if (_newVideos.isNotEmpty) {
      unawaited(VideoCompress.deleteAllCache());
    }
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
    // Task 13: video solo existe para trabajo, pero sumarlo aquí sin
    // gatear por `_esTrabajo` es inofensivo (siempre vacío en los otros
    // `kind`) y evita que un cambio futuro lo olvide.
    _keptVideos.map((v) => v.url).join(','),
    _newVideos.length,
  ].join('|');

  bool _hasUnsavedWork() => !_saved && _formSnapshot() != _cleanSnapshot;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// Cámara = una foto; Galería = varias — mismo patrón que las fotos de una
  /// oferta (`request_detail_screen._pickPhoto`).
  ///
  /// El tope se mide en [_fileCount] (Task 13), no en [_photoCount]: para un
  /// trabajo con videos ya cargados, una foto de más también debe rechazarse
  /// si entre las dos se pasa de [_maxPhotos] archivos totales. Para
  /// producto/servicio [_fileCount] == [_photoCount] siempre (nunca tienen
  /// video) — sin cambio de comportamiento ahí.
  Future<void> _pick(ImageSource source) async {
    if (_fileCount >= _maxPhotos) {
      _toast('Máximo $_maxPhotos fotos');
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
          currentCount: _fileCount,
          maxCount: _maxPhotos);
      if (res is ImagePickError) {
        _toast(res.message);
        break;
      }
      if (mounted) setState(() => _photos.add(x));
    }
  }

  /// Botón «Agregar video» (Task 13). El tope de CANTIDAD (2 por trabajo) y
  /// el de ARCHIVOS TOTALES (8) se chequean ANTES de abrir el selector —
  /// evita gastar batería/datos comprimiendo un video que de entrada no
  /// cabe, mismo criterio que [_pick]. La duración se valida DESPUÉS de
  /// elegir (hace falta leer el archivo), el tamaño DESPUÉS de comprimir
  /// (es el archivo real que se sube) — ver `domain/video_pick.dart`.
  Future<void> _pickVideo() async {
    if (_videoCount >= kMaxPortfolioVideos) {
      _toast('Máximo $kMaxPortfolioVideos videos por trabajo.');
      return;
    }
    if (_fileCount >= _maxPhotos) {
      _toast('Máximo $_maxPhotos fotos');
      return;
    }
    final picked = await guardedPick((p) => p.pickVideo(source: ImageSource.gallery));
    if (picked == null) return;
    setState(() => _compressingVideo = true);
    try {
      final info = await VideoCompress.getMediaInfo(picked.path);
      final seconds = ((info.duration ?? 0) / 1000).round();
      if (seconds > maxVideoSeconds) {
        _toast('El video no puede durar más de $maxVideoSeconds segundos.');
        return;
      }
      // Preset elegido: el ÚNICO de este plugin que topa la resolución en
      // 720p sin más ("no pasar de 720p" — corrección PO 2026-08-21). El
      // `frameRate` NO se pasa a propósito: el plugin nativo lo ignora para
      // este preset (solo lo aplica en `HighestQuality`, que no topa
      // resolución) — pasarlo aquí daría una falsa sensación de control.
      // Ver `targetVideoBitrateBps` en `domain/video_pick.dart` para el
      // hueco declarado sobre el bitrate real que sale de este preset.
      final compressed = await VideoCompress.compressVideo(
        picked.path,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final compressedPath = compressed?.path;
      if (compressedPath == null) {
        _toast('No se pudo procesar el video. Intenta de nuevo.');
        return;
      }
      final sizeBytes =
          compressed?.filesize ?? await File(compressedPath).length();
      final res =
          validatePickedVideo(durationSeconds: seconds, sizeBytes: sizeBytes);
      if (res is VideoPickError) {
        _toast(res.message);
        // El comprimido YA se escribió a disco (rechazo por tamaño, no por
        // duración) — nunca entra a `_newVideos`, así que el `dispose()` no
        // lo vería. Limpieza best-effort aquí mismo.
        unawaited(VideoCompress.deleteAllCache());
        return;
      }
      // Póster OBLIGATORIO en el sentido de "se intenta siempre", NUNCA
      // bloqueante: si falla, el video sube igual con poster null — la
      // tarjeta degrada al placeholder, jamás al .mp4 (regla de
      // `data/portfolio_media.dart`).
      String? posterPath;
      try {
        final poster =
            await VideoCompress.getFileThumbnail(compressedPath, quality: 60);
        posterPath = poster.path;
      } catch (_) {
        posterPath = null;
      }
      if (!mounted) return;
      setState(() => _newVideos.add((
            path: compressedPath,
            posterPath: posterPath,
            durationSeconds: seconds,
          )));
    } finally {
      if (mounted) setState(() => _compressingVideo = false);
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

  /// Columnas REALES `brand`/`warranty` (Fix round 1, Important 4): el mismo
  /// dato que entra a `offer_defaults`, pero también en su columna propia —
  /// para que "Marca"/"Garantía" muevan la ficha pública (`productDetail`)
  /// y no solo el molde de oferta. Se calculan de la MISMA fuente
  /// (`_brand.text`/`_warranty.text`) que usa `_offerDefaultsForSave`, EXCEPTO
  /// en un caso desde I-1 (revisión final): un servicio SÍ tiene columna
  /// `warranty` (paridad con la web), pero su `offer_defaults.warranty` sigue
  /// vacío a propósito, igual que ya hacía `request_detail_screen.dart` con
  /// el molde de oferta de un servicio — divergen ahí adrede, no es un bug.
  String? get _brandColumn {
    if (_isService) return null;
    final t = _brand.text.trim();
    return t.isEmpty ? null : t;
  }

  /// Hallazgo I-1 (revisión final): a diferencia de [_brandColumn]
  /// (producto-only, la web tampoco pide marca en servicios), `warranty` SÍ
  /// aplica a servicio — no gatear por `_isService` aquí es justo el fix.
  String? get _warrantyColumn {
    final t = _warranty.text.trim();
    return t.isEmpty ? null : t;
  }

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
        // Sin el botón «Editar en la web» (quitado 2026-08-10) el copy apunta
        // directo al sitio: categoría/rubro aún no se editan en la app.
        _toast(
            'Tu negocio aún no tiene categoría y rubro. Complétalos entrando a jayalo.com.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      // Fotos (y video, Task 13) a Storage ANTES del insert/update — nunca
      // base64 en la BD.
      //
      // Cacheadas por ruta: si el guardado falla y el usuario reintenta (el
      // toast se lo pide), sin esto se volvían a subir los MISMOS ficheros y
      // se acumulaba una copia por intento.
      List<String> imageUrls = const [];
      List<PortfolioMedia> media = const [];
      if (_esTrabajo) {
        media = await _uploadTrabajoMedia();
      } else {
        final newUrls = await Future.wait(_photos.map((x) async =>
            _uploaded[x.path] ??= await uploadStoreProductImage(x.path)));
        imageUrls = [..._keptUrls, ...newUrls];
      }
      if (_esTrabajo && _editing) {
        // Task 8: editar un trabajo propio — mismos archivos conservados +
        // nuevos que el alta, pero UPDATE en vez de INSERT.
        await widget.updatePortfolio(
          widget.initial!['id'] as String,
          title: nombre,
          description: _desc.text,
          media: media,
        );
      } else if (_esTrabajo) {
        await widget.savePortfolio(
          businessId: widget.businessId,
          title: nombre,
          description: _desc.text,
          media: media,
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
          'brand': _brandColumn,
          'warranty': _warrantyColumn,
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
          brand: _brandColumn,
          warranty: _warrantyColumn,
          offerDefaults: defaults.isEmpty ? null : defaults,
        );
      }
      _saved = true;
      releaseUnsavedGuard(this);
      if (!mounted) return;
      _toast(_editing
          ? 'Cambios guardados.'
          : (_esTrabajo ? 'Trabajo agregado.' : 'Agregado a tu tienda.'));
      // `true` = hubo cambio: "Mi negocio" refresca su listado al volver.
      context.pop(true);
    } catch (e, s) {
      // Hallazgo I-3 (revisión final): un `catch (_)` genérico convertía un
      // JY422 del trigger `enforce_no_contact_info` (teléfono/correo pegado
      // en nombre/descripción) en el mismo "No se pudo guardar" de un fallo
      // cualquiera, y el error ni llegaba al reporter — mismo patrón que
      // `package_editor_screen.dart:_save`.
      if (isContactInfoError(e)) {
        _toast(contactInfoMessage);
      } else {
        unawaited(reportError(e, s));
        _toast('No se pudo guardar. Intenta de nuevo.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadTotal = 0;
          _uploadDone = 0;
        });
      }
    }
  }

  /// Sube fotos y videos NUEVOS de un trabajo — secuencial, no
  /// `Future.wait` en paralelo como producto/servicio: así [_uploadDone]
  /// refleja subidas REALES ya terminadas, no un contador decorativo. Con
  /// 10 MB de video por datos móviles, un spinner ciego son minutos sin
  /// saber si avanza (Task 13).
  ///
  /// Reusa la caché [_uploaded] por ruta local (foto, video Y poster
  /// comparten el mismo mapa — la clave es la ruta, no colisiona) para no
  /// volver a subir lo que ya subió un intento fallido anterior.
  Future<List<PortfolioMedia>> _uploadTrabajoMedia() async {
    setState(() {
      _uploadTotal = _photos.length + _newVideos.length;
      _uploadDone = 0;
    });
    final media = <PortfolioMedia>[
      for (final url in _keptUrls) PortfolioMedia(url: url, kind: 'image'),
    ];
    for (final x in _photos) {
      final url = _uploaded[x.path] ??= await uploadPortfolioMedia(x.path,
          contentType: _imageContentTypeFor(x.path));
      media.add(PortfolioMedia(url: url, kind: 'image'));
      if (mounted) setState(() => _uploadDone++);
    }
    media.addAll(_keptVideos);
    for (final v in _newVideos) {
      final url = _uploaded[v.path] ??=
          await uploadPortfolioMedia(v.path, contentType: 'video/mp4');
      String? posterUrl;
      final posterPath = v.posterPath;
      if (posterPath != null) {
        // El póster nunca bloquea el video: si ESTA subida (no la del
        // video, que ya pasó) falla, el video sube igual con poster null.
        try {
          posterUrl = _uploaded[posterPath] ??= await uploadPortfolioMedia(
              posterPath,
              contentType: 'image/jpeg');
        } catch (_) {
          posterUrl = null;
        }
      }
      media.add(PortfolioMedia(
          url: url, kind: 'video', poster: posterUrl, duration: v.durationSeconds));
      if (mounted) setState(() => _uploadDone++);
    }
    if (_newVideos.isNotEmpty) {
      unawaited(VideoCompress.deleteAllCache());
    }
    return media;
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
        'trabajo' => _editing ? 'Editar trabajo' : 'Agregar trabajo',
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
              if (_keptUrls.isNotEmpty ||
                  _photos.isNotEmpty ||
                  _keptVideos.isNotEmpty ||
                  _newVideos.isNotEmpty)
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _keptUrls.length +
                        _photos.length +
                        _keptVideos.length +
                        _newVideos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      if (i < _keptUrls.length) {
                        return _keptThumb(_keptUrls[i], i);
                      }
                      i -= _keptUrls.length;
                      if (i < _photos.length) return _localThumb(_photos[i], i);
                      i -= _photos.length;
                      if (i < _keptVideos.length) {
                        return _keptVideoThumb(_keptVideos[i], i);
                      }
                      i -= _keptVideos.length;
                      return _localVideoThumb(_newVideos[i], i);
                    },
                  ),
                ),
              // Task 13: el tope se mide en archivos totales (fotos + video),
              // no solo fotos — ver [_fileCount].
              if (_fileCount < _maxPhotos)
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
              // Solo trabajo tiene video. El botón sigue visible aunque ya
              // haya 2 videos (tope de [kMaxPortfolioVideos]) — tocarlo
              // rechaza con el toast, no se oculta: solo se oculta al llegar
              // al tope de ARCHIVOS ([_fileCount]), igual que arriba.
              if (_esTrabajo && _fileCount < _maxPhotos)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_busy || _compressingVideo)
                          ? null
                          : _pickVideo,
                      icon: _compressingVideo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.videocam_outlined),
                      label: Text(_compressingVideo
                          ? 'Procesando video…'
                          : 'Agregar video'),
                    ),
                  ),
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
              // Barra de progreso REAL de la subida (Task 13) — sube en
              // pasos con cada archivo que termina de subir
              // ([_uploadTrabajoMedia]), no es una animación decorativa.
              // Solo aparece para trabajo con archivos nuevos por subir.
              if (_uploading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _uploadDone / _uploadTotal,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Subiendo $_uploadDone de $_uploadTotal…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
              ],
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

  /// Gris + ícono de video — mismo trato que un thumb de foto rota, pero
  /// para un video sin póster (Task 13): degradación intencional, NUNCA se
  /// intenta pintar el .mp4 como imagen (regla de `data/portfolio_media.dart`).
  Widget _videoPlaceholder() => Container(
        width: 88,
        height: 88,
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.videocam_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      );

  /// Insignia de "esto es un video" sobre la miniatura — mismo patrón visual
  /// que `tile_carril.dart` (`PortfolioTile`), a menor escala (miniatura de
  /// 88 en vez de la tarjeta del carril).
  Widget _playBadge() => const Positioned.fill(
        child: Center(
          child: CircleAvatar(
            radius: 14,
            backgroundColor: Colors.black54,
            child: Icon(Icons.play_arrow, color: Colors.white, size: 16),
          ),
        ),
      );

  Widget _keptVideoThumb(PortfolioMedia v, int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: v.poster == null
              ? _videoPlaceholder()
              : JayaloNetworkImage(v.poster!,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _videoPlaceholder()),
        ),
        _playBadge(),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: () => setState(() => _keptVideos.removeAt(index)),
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

  Widget _localVideoThumb(_PickedVideo v, int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: v.posterPath == null
              ? _videoPlaceholder()
              : Image.file(File(v.posterPath!),
                  width: 88, height: 88, fit: BoxFit.cover),
        ),
        _playBadge(),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: () => setState(() => _newVideos.removeAt(index)),
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
          title: 'Ofrezco traslado',
          value: _offersShipping,
          onChanged: (v) => setState(() => _offersShipping = v),
          cost: _shipping,
          costLabel: 'Costo del traslado (RD\$)',
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
        const SizedBox(height: 14),
        // Hallazgo I-1 (revisión final): la web permite garantía en
        // servicios (`productOnly: false`), pero este editor solo la
        // mostraba para producto — y el UPDATE mandaba `warranty: null`
        // SIEMPRE en un servicio, borrando en silencio lo que se hubiera
        // puesto desde la web. Mismo chip que en `_productMoldeFields`.
        _sectionLabel('Garantía'),
        const SizedBox(height: 8),
        _chipSelect(kWarrantyOptions, _warranty.text,
            (v) => setState(() => _warranty.text = v)),
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
