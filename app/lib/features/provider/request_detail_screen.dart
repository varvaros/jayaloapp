import 'dart:io';
import 'package:flutter/material.dart';
import '../shared/network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../core/brand.dart';
import '../verification/id_doc_sheet.dart';
import '../../core/center_action.dart';
import '../../data/repos.dart';
import '../../core/motion.dart';
import '../../core/safe_image_picker.dart';
import '../../domain/contact_info.dart';
import '../../domain/image_pick.dart';
import '../../domain/money.dart';
import '../../domain/offer_edit.dart';
import '../../domain/offer_form_gate.dart';
import '../../domain/offer_message.dart';
import '../../domain/pricing.dart';
import '../../domain/finalist_slots.dart';
import '../../domain/request_requirements.dart';
import '../../domain/store_product_prefill.dart';
import '../shared/request_requirement_badges.dart';
import '../shared/celebration.dart';
import '../shared/collapsing_photo_panel.dart';
import '../shared/customer_rep_card.dart';
import '../shared/offer_field_options.dart';
import '../shared/onboarding_copy.dart';
import '../shared/onboarding_guide.dart';
import '../shared/section_heading.dart';
import '../shared/wholesale_card.dart';
import '../shell/floating_nav_bar.dart';
import '../shared/brand_kit.dart';
import '../../core/unsaved_guard.dart';
import 'offer_center_menu.dart';
import 'offer_requirements_warning.dart';
import 'unlock_flow.dart';

const _maxOfferPhotos = 5;

// Presets iguales a la web (RequestRespondSection.tsx): color, garantía,
// disponibilidad y estado — para que la oferta de la app calce con la web.
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
// Garantía y estado (Nuevo/Usado) viven en `offer_field_options.dart`
// (`kWarrantyOptions`/`kConditionOptions`, Task 6): las comparte este
// formulario con el editor de ítem de tienda.
const _availabilityDays = <String>[
  'Hoy', 'Mañana', 'Esta semana', 'Fin de semana',
  'Próxima semana', 'A coordinar',
];

class ProviderRequestDetailScreen extends StatefulWidget {
  const ProviderRequestDetailScreen({
    super.key,
    required this.requestId,
    this.editOfferId,
  });
  final String requestId;

  /// Cuando llega desde "Mis ofertas" para EDITAR, es el id de la oferta
  /// pendiente a modificar: el formulario abre prefijado con "Guardar cambios"
  /// y "Eliminar", en vez de crear una oferta nueva.
  final String? editOfferId;
  @override
  State<ProviderRequestDetailScreen> createState() =>
      _ProviderRequestDetailScreenState();
}

class _ProviderRequestDetailScreenState
    extends State<ProviderRequestDetailScreen> {
  Map<String, dynamic>? _req;
  String? _businessId;
  bool _busy = false;

  /// Regla PO: **una sola oferta por solicitud por proveedor**. Si este negocio
  /// ya ofertó, el detalle muestra "Ya ofertaste" en vez del formulario.
  /// `_offerChecked` evita el parpadeo (form → aviso) mientras se consulta.
  Map<String, dynamic>? _existingOffer;
  bool _offerChecked = false;
  // Producto: precio fijo vs rango. Servicio: 4 modos (ver [_svcModes]).
  bool _fixed = true;
  int _svcMode = 0;
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  // Servicio: por hora + disponibilidad/duración.
  final _hourly = TextEditingController();
  final _hours = TextEditingController();
  final _availability = TextEditingController();
  final _duration = TextEditingController();
  // Producto: envío / instalación / evaluación (paridad web).
  bool _offersShipping = false;
  final _shipping = TextEditingController();
  bool _offersInstallation = false;
  final _installation = TextEditingController();
  bool _requiresEvaluation = false;
  final _evaluation = TextEditingController();
  // Capacidades transversales (producto Y servicio): se premarcan con lo que el
  // negocio tenga declarado y el proveedor las ajusta para esta oferta.
  bool _hasFiscalReceipt = false;
  bool _isStateSupplier = false;
  // Producto: detalles (marca/estado/color/garantía/tiempo de entrega) — con
  // selectores tipo web. _warranty/_delivery guardan la etiqueta elegida.
  final _brand = TextEditingController();
  final _warranty = TextEditingController();
  final _delivery = TextEditingController();
  String _condition = ''; // Nuevo | Usado (sin columna: va al mensaje)
  final List<String> _colors = [];
  final List<XFile> _photos = [];
  // Modo edición: fotos YA subidas de la oferta (URLs) que se conservan; el
  // proveedor puede quitarlas o sumar nuevas ([_photos]) hasta el tope.
  final List<String> _keptUrls = [];

  /// Foto del formulario en su estado "limpio": vacio al crear, o lo que dejo
  /// `_prefillFromOffer` al editar. La suciedad se decide comparando contra
  /// esto, no contra cadenas vacias.
  String _cleanSnapshot = '';

  /// Serializa TODO lo que el proveedor puede cambiar. Si se anade un campo
  /// nuevo al formulario, hay que sumarlo aqui o el aviso de salida no lo vera.
  ///
  /// `_hasFiscalReceipt`/`_isStateSupplier` SI cuentan aqui aunque el brief
  /// original no los listaba: son interruptores tocables por el proveedor
  /// (`:1773-1790`), no solo lectura. En edicion estan `enabled: false` y no
  /// se pueden tocar, pero en creacion si.
  String _formSnapshot() => [
        _price.text, _min.text, _max.text, _hourly.text, _hours.text,
        _availability.text, _duration.text,
        _shipping.text, _installation.text, _evaluation.text,
        _brand.text, _warranty.text, _delivery.text,
        _condition,
        '$_fixed', '$_svcMode',
        '$_offersShipping', '$_offersInstallation', '$_requiresEvaluation',
        '$_hasFiscalReceipt', '$_isStateSupplier',
        _colors.join(','),
        _photos.map((x) => x.path).join(','),
        _keptUrls.join(','),
      ].join('\u0000');

  /// Reputación del CLIENTE que hizo la solicitud (pedido PO 2026-07-22): el
  /// proveedor la ve para decidir si le conviene ofertar. No expone contacto.
  Map<String, dynamic>? _custRep;

  /// Sellos de verificación del cliente (PO 2026-07-29).
  PeerBadges? _custBadges;

  /// Identidad real del cliente, GATEADA server-side por desbloqueo (decisión
  /// PO 2026-08-11): `unlocked: false` = la ficha se pinta anónima. Se pide
  /// siempre (best-effort) y es la RPC quien decide si revela.
  ({bool unlocked, String? firstName, String? lastName, String? avatarUrl})?
      _custProfile;

  /// Cuántas ofertas ha recibido esta solicitud (FOMO, pedido PO 2026-07-21):
  /// solo el número, no se pueden ver. 0 = no se muestra.
  int _offerCount = 0;

  /// Id de la oferta en edición. Nace de `widget.editOfferId` (ruta `?edit=`,
  /// desde "Mis ofertas") y TAMBIÉN puede activarse en sitio, desde la tarjeta
  /// "Ya enviaste tu oferta" (pedido PO 2026-08-03). Por eso es estado y no un
  /// getter del widget.
  String? _editOfferId;

  /// True solo cuando la edición se activó desde ESTA pantalla. Distingue las
  /// dos entradas: la de ruta sale a la lista de ofertas al guardar; la de
  /// aquí vuelve a la tarjeta, sin salir de la solicitud.
  bool _editingInPlace = false;

  bool get _editing => _editOfferId != null;

  /// ¿Se está pintando el FORMULARIO de la oferta (y no la tarjeta, el spinner
  /// o el CTA de completar el negocio)?
  ///
  /// Única fuente de verdad de esa decisión: la cadena del `build` la consume y
  /// el registro del menú del botón central también (ver `_syncCenterAction`).
  ///
  /// El guard de `_req != null` NO lo cubre `offerFormVisible`: esa función
  /// pura modela las TRES ramas internas de la cadena (negocio/edición,
  /// chequeo de oferta previa, oferta existente), pero el spinner EXTERIOR
  /// ("todavía no llegó la solicitud", el `if (req == null)` de `build`) es
  /// un cuarto estado que vive fuera de esas tres. `requestById` (en
  /// `initState`) no tiene `catchError`: si falla mientras el resto de la
  /// carga sí termina, `_req` se queda en `null` para siempre pero
  /// `offerChecked` igual llega a `true` — sin este guard, `_syncCenterAction`
  /// registraba el menú y el arco quedaba vivo sobre un spinner permanente.
  bool get _offerFormVisible =>
      _req != null &&
      offerFormVisible(
        editing: _editing,
        businessId: _businessId,
        offerChecked: _offerChecked,
        existingOffer: _existingOffer,
      );

  /// Identidad de esta pantalla ante el store del botón central. Un `Object()`
  /// pelado basta: lo único que se le pide es no ser igual al de nadie más.
  final Object _centerOwner = Object();

  /// La ruta que el shell compara. Se compone de lo que la pantalla ya sabe, sin
  /// leer inherited widgets (`GoRouterState.of` no se puede usar en `initState`).
  /// El shell compara contra `uri.path`, SIN query, así que entrar en edición
  /// con `?edit=<id>` no rompe la igualdad.
  String get _centerRoute => '/provider/request/${widget.requestId}';

  /// Métodos propios, no clausuras guardadas en campos: `CenterMenuItem`
  /// compara sus `onTap` por igualdad, y un `() => _pickPhoto(...)` nuevo en
  /// cada build rompería esa comparación y repintaría la barra con cada
  /// tecla. Dart garantiza que dos tear-offs del MISMO método sobre la MISMA
  /// instancia son `==` entre sí, así que `_pickFromStore`/`_pickFromPortfolio`
  /// se pasan directos (ver más abajo) y solo `_pickPhoto` — que toma un
  /// argumento — necesita un método propio que lo envuelva.
  void _menuCamera() => _pickPhoto(ImageSource.camera);
  void _menuGallery() => _pickPhoto(ImageSource.gallery);

  /// Pone al día el botón central de la barra según el estado de ESTA pantalla.
  ///
  /// ⚠️ Se llama desde `build`, y eso es deliberado. `CreateRequestScreen`
  /// registra en `initState` y suelta en `dispose`, y le basta porque su estado
  /// no cambia. Aquí el formulario aparece y desaparece DENTRO de la misma
  /// pantalla: al enviar la oferta, al entrar en edición en sitio, al
  /// cancelarla, al borrar. Registrar en esos cuatro sitios funciona hoy y se
  /// rompe en silencio la primera vez que alguien añada un quinto camino;
  /// desde `build` no se puede desincronizar.
  ///
  /// Escribir notifiers desde `build` es seguro PRECISAMENTE porque
  /// `_applySafely` (en `core/center_action.dart`) aplaza al final del frame:
  /// ese es el caso para el que se escribió. Y no realimenta: el
  /// `ListenableBuilder` del shell envuelve solo la barra, no el `child` del
  /// Navigator anidado.
  ///
  /// ⚠️ `ModalRoute.of(context)?.isCurrent`: esta misma pantalla puede vivir
  /// APILADA dos veces (A abajo, B al frente — p. ej. "ver la misma solicitud"
  /// abierta desde dos sitios). Un `setState` tardío en A (una carga async que
  /// termina fuera de orden) dispara su `build`, y sin este guard A volvería a
  /// tomar el botón con SU ruta aunque B siga al frente — el shell, al ver que
  /// la ruta activa ya no coincide con `centerActionRoute`, suelta el menú
  /// entero y el ＋ vuelve a su comportamiento de siempre (empujar
  /// crear-solicitud SOBRE la oferta de B: el bug original que esta feature
  /// vino a arreglar). `ModalRoute.of` registra una dependencia de
  /// `InheritedWidget`, así que un cambio de "quién está al frente" SÍ
  /// reconstruye a quien perdió el puesto y este guard se vuelve a evaluar.
  void _syncCenterAction() {
    if (!_offerFormVisible || ModalRoute.of(context)?.isCurrent != true) {
      releaseCenterAction(_centerOwner);
      return;
    }
    takeCenterAction(
      owner: _centerOwner,
      icon: Icons.library_add_outlined,
      label: 'Cargar',
      route: _centerRoute,
      menu: buildOfferCenterMenu(
        busy: _busy,
        photoCount: _photoCount,
        maxPhotos: _maxOfferPhotos,
        onCamera: _menuCamera,
        onGallery: _menuGallery,
        onStore: _pickFromStore,
        onPortfolio: _pickFromPortfolio,
        onCapHit: _photoCapToast,
      ),
    );
  }

  /// Modos de precio del formulario de SERVICIO (paridad web: fijo / rango /
  /// por hora / a evaluar en sitio). El índice es [_svcMode].
  static const _svcModes = ['fixed', 'range', 'hourly', 'needs_evaluation'];

  bool get _isService => _req?['kind'] == 'servicio';
  // Cupos de finalista (modelo de hasta 3): finalistas ya seleccionados y
  // ofertas activas de la solicitud (columnas materializadas en la BD).
  int get _acceptedCount => (_req?['accepted_offers_count'] as num?)?.toInt() ?? 0;
  int get _offersCountLive =>
      (_req?['offers_count'] as num?)?.toInt() ?? _offerCount;
  String get _pricingMode =>
      _isService ? _svcModes[_svcMode] : (_fixed ? 'fixed' : 'range');

  @override
  void initState() {
    super.initState();
    // Antes que nada: `_editing` se consulta más abajo, en esta misma función.
    _editOfferId = widget.editOfferId;
    requestById(widget.requestId).then((r) {
      if (!mounted) return;
      setState(() => _req = r);
      // Reputación del cliente que solicita (best-effort).
      final cid = r?['user_id'] as String?;
      if (cid != null) {
        customerReputation(cid)
            .then((rep) => mounted ? setState(() => _custRep = rep) : null)
            .catchError((_) => null);
        peerVerificationBadges([cid])
            .then((m) => mounted ? setState(() => _custBadges = m[cid]) : null)
            .catchError((_) => null);
        customerPublicProfile(cid)
            .then((p) => mounted ? setState(() => _custProfile = p) : null)
            .catchError((_) => null);
      }
    });
    // FOMO: cuántas ofertas ya tiene esta solicitud (best-effort, solo el
    // número — no se pueden ver las ofertas).
    offerCountsForRequests([widget.requestId])
        .then((m) => mounted
            ? setState(() => _offerCount = m[widget.requestId] ?? 0)
            : null)
        .catchError((_) {});
    // Registro inicial, ANTES de la rama edicion/creacion: si `offerForEdit`
    // (mas abajo) devuelve null o falla, el formulario igual se muestra
    // (compuerta `:1717-1737`, cae al `else` de abajo) pero `_prefillFromOffer`
    // nunca corre, y ese era el UNICO otro registro en la rama de edicion.
    // Sin esto, esa combinacion (fetch fallido + formulario visible) se
    // quedaba sin guard: se podia escribir una oferta completa y salir sin
    // aviso. Instantanea vacia aqui es segura: el formulario esta detras del
    // spinner (`!_offerChecked`) hasta que la carga (la que sea) termine, asi
    // que nada es alcanzable todavia. `_prefillFromOffer` corrige la
    // instantanea cuando la oferta si llega.
    _cleanSnapshot = _formSnapshot();
    takeUnsavedGuard(
      owner: this,
      check: () => _formSnapshot() != _cleanSnapshot,
      message: 'Perderás lo que escribiste en esta oferta.',
    );
    if (_editing) {
      // Modo edición: no hace falta el chequeo "¿ya ofertó?"; traemos la fila
      // COMPLETA de la oferta y prefijamos el formulario.
      // Al editar, el premarcado desde el negocio NO aplica: las dos
      // capacidades son las que quedaron guardadas en la oferta (las fija
      // `_prefillFromOffer`) y su UPDATE está denegado. Aquí se lee el negocio
      // solo por el id — premarcarlas también correría carrera con la carga de
      // la oferta y podría pisar lo guardado.
      myBusinessForOffer()
          .then((b) => mounted ? setState(() => _businessId = b?.id) : null);
      offerForEdit(_editOfferId!).then((o) {
        if (!mounted) return;
        setState(() {
          _existingOffer = o;
          if (o != null) _prefillFromOffer(o);
          _offerChecked = true;
        });
      }).catchError((_) {
        if (mounted) setState(() => _offerChecked = true);
      });
      return;
    }
    myBusinessForOffer().then((b) {
      if (!mounted) return;
      setState(() {
        _businessId = b?.id;
        // Premarcado, NO imposición: el proveedor puede desmarcarlas para
        // esta oferta. Si la lectura falla, `b` es null y quedan apagadas —
        // el default seguro: se avisa de más, nunca se afirma de menos en
        // nombre del proveedor.
        _hasFiscalReceipt = b?.hasFiscalReceipt ?? false;
        _isStateSupplier = b?.isStateSupplier ?? false;
      });
      // Re-fijar la instantanea: el premarcado llega async y no es una
      // edicion del proveedor. El formulario todavia esta detras del spinner
      // (`!_offerChecked`, mas abajo) asi que no hay nada que el proveedor
      // pueda haber tocado todavia.
      _cleanSnapshot = _formSnapshot();
      if (b == null) {
        setState(() => _offerChecked = true);
        return;
      }
      // ¿Este negocio ya ofertó a esta solicitud? (1 oferta por solicitud).
      myOfferForRequest(widget.requestId, b.id).then((o) {
        if (mounted) {
          setState(() {
            _existingOffer = o;
            _offerChecked = true;
          });
        }
      }).catchError((_) {
        // Si el chequeo falla, no bloqueamos: el trigger/constraint del server
        // sigue siendo la última línea. Dejamos ver el formulario.
        if (mounted) setState(() => _offerChecked = true);
      });
    });
  }

  /// Vuelca una oferta existente en los controles del formulario (modo edición).
  /// Los campos se guardan como columnas propias (no solo dentro del mensaje),
  /// asi que la reconstruccion es directa. "Nuevo/Usado" no tiene columna
  /// propia y se recupera del mensaje con `conditionFromOfferMessage`.
  void _prefillFromOffer(Map<String, dynamic> o) {
    final mode = o['pricing_mode'] as String? ?? 'fixed';
    _svcMode = _svcModes.indexOf(mode).clamp(0, _svcModes.length - 1);
    _fixed = mode != 'range';
    String txt(Object? v) => v == null ? '' : '${(v as num)}';
    // Dinero: agrupado en miles, como lo deja el MilesInputFormatter al
    // escribir — el prefill no debe verse distinto de lo tecleado.
    String miles(Object? v) => v == null ? '' : fmtMiles(v as num);
    _price.text = miles(o['price']);
    _min.text = miles(o['price_min']);
    _max.text = miles(o['price_max']);
    _hourly.text = miles(o['hourly_rate']);
    _hours.text = txt(o['estimated_hours']);
    _availability.text = (o['availability_note'] as String?) ?? '';
    _duration.text = (o['estimated_duration'] as String?) ?? '';
    _offersShipping = o['offers_shipping'] == true;
    _shipping.text = miles(o['shipping_price']);
    _offersInstallation = o['offers_installation'] == true;
    _installation.text = miles(o['installation_price']);
    _requiresEvaluation = o['requires_evaluation'] == true;
    _evaluation.text = miles(o['evaluation_price']);
    // Las dos capacidades salen de la oferta, no del negocio: son la foto de lo
    // que se declaró al enviarla y su UPDATE está denegado en la base.
    _hasFiscalReceipt = o['has_fiscal_receipt'] == true;
    _isStateSupplier = o['is_state_supplier'] == true;
    _brand.text = (o['product_brand'] as String?) ?? '';
    _warranty.text = (o['product_warranty'] as String?) ?? '';
    _condition = conditionFromOfferMessage((o['message'] as String?) ?? '');
    _delivery.text = (o['delivery_time'] as String?) ?? '';
    _colors
      ..clear()
      ..addAll(((o['product_colors'] as List?)?.cast<String>()) ?? const []);
    _keptUrls
      ..clear()
      ..addAll(((o['image_urls'] as List?)?.cast<String>() ?? const [])
          .where((u) => u.isNotEmpty));
    // Al final, con TODO ya rellenado: si fuera antes, la instantanea
    // guardaria el formulario vacio y la pantalla naceria sucia.
    _cleanSnapshot = _formSnapshot();
    takeUnsavedGuard(
      owner: this,
      check: () => _formSnapshot() != _cleanSnapshot,
      message: 'Perderás lo que escribiste en esta oferta.',
    );
  }

  @override
  void dispose() {
    // Salir de la pantalla no siempre pasa por un `build` con el formulario ya
    // cerrado. La guarda de identidad del store hace que esto sea inofensivo si
    // la pantalla entrante ya tomó el botón.
    releaseCenterAction(_centerOwner);
    // Antes de super.dispose(): una pantalla desmontada que se quede
    // registrada bloquearia el atras de la SIGUIENTE pantalla que visite el
    // proveedor. La identidad de dueño hace esto inofensivo si otra pantalla
    // (crear-solicitud apilada encima) registró y soltó entre medias.
    releaseUnsavedGuard(this);
    for (final c in [
      _price, _min, _max, _hourly, _hours,
      _availability, _duration, _shipping, _installation, _evaluation,
      _brand, _warranty, _delivery,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _estimatedCost {
    final mode = _pricingMode;
    return pointsForOffer(
      price: mode == 'fixed' ? parseMiles(_price.text)?.toDouble() : null,
      priceMin: mode == 'range' ? parseMiles(_min.text)?.toDouble() : null,
      priceMax: mode == 'range' ? parseMiles(_max.text)?.toDouble() : null,
      pricingMode: mode,
      hourlyRate:
          mode == 'hourly' ? parseMiles(_hourly.text)?.toDouble() : null,
      estimatedHours: mode == 'hourly' ? double.tryParse(_hours.text) : null,
    );
  }

  int get _photoCount => _photos.length + _keptUrls.length;

  /// Toast del tope de fotos para el ítem APAGADO del arco (ver
  /// `offer_center_menu.dart`, `onCapHit`): al tope, tocar Cámara/Galería/
  /// Trabajos avisa por qué en vez de quedar mudo.
  void _photoCapToast() => _toast('Ya tienes 5 fotos');

  /// Cámara = una foto; Galería = VARIAS (pedido PO: permitir seleccionar
  /// varias). Cada una se valida y se corta al llegar al tope.
  Future<void> _pickPhoto(ImageSource source) async {
    // Red DEFENSIVA, no la única: el arco ya apaga estos botones al tope y
    // avisa con `_photoCapToast`, pero este atajo también se llama desde los
    // botones del FORMULARIO (más abajo en `build`), que no pasan por el
    // arco — sin este corte, un toque colado ahí seguiría de largo.
    if (_photoCount >= _maxOfferPhotos) {
      _photoCapToast();
      return;
    }
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
          // Las fotos ya subidas (edición / tienda / portafolio) también cuentan.
          currentCount: _photoCount,
          maxCount: _maxOfferPhotos);
      if (res is ImagePickError) {
        _toast(res.message);
        break;
      }
      if (mounted) setState(() => _photos.add(x));
    }
  }

  /// Suma URLs ya alojadas (tienda / portafolio) al set de fotos conservadas,
  /// respetando el tope y sin duplicar.
  void _addKeptUrls(Iterable<String> urls) {
    setState(() {
      for (final u in urls) {
        if (u.isEmpty || _keptUrls.contains(u)) continue;
        if (_photoCount >= _maxOfferPhotos) break;
        _keptUrls.add(u);
      }
    });
  }

  /// "De mi tienda": elegir un producto/servicio ya publicado — trae sus fotos
  /// y AUTOCOMPLETA los detalles (precio, color, envío, estado…). Todo queda
  /// editable en el formulario (pedido PO 2026-07-21).
  Future<void> _pickFromStore() async {
    final bid = _businessId;
    if (bid == null) return;
    List<Map<String, dynamic>> items;
    try {
      items = await myStoreProducts(bid);
    } catch (_) {
      _toast('No se pudo cargar tu tienda.');
      return;
    }
    if (!mounted) return;
    // Prioriza los del mismo tipo que la solicitud; si no hay, muestra todos.
    final sameKind =
        items.where((p) => (p['kind'] ?? 'producto') == _req?['kind']).toList();
    final list = sameKind.isNotEmpty ? sameKind : items;
    if (list.isEmpty) {
      _toast('Aún no tienes productos en tu tienda.');
      return;
    }
    final chosen = await _pickStoreItemSheet('De mi tienda', list);
    if (chosen == null || !mounted) return;
    _applyStoreProduct(chosen);
  }

  /// "Cargar trabajos anteriores": elige un trabajo del portafolio y trae sus
  /// fotos a la oferta (no autocompleta precio — es evidencia de trabajo).
  Future<void> _pickFromPortfolio() async {
    final bid = _businessId;
    if (bid == null) return;
    List<Map<String, dynamic>> items;
    try {
      items = await myPortfolioItems(bid);
    } catch (_) {
      _toast('No se pudieron cargar tus trabajos.');
      return;
    }
    if (!mounted) return;
    if (items.isEmpty) {
      _toast('Aún no tienes trabajos anteriores en tu portafolio.');
      return;
    }
    final chosen = await _pickStoreItemSheet('Trabajos anteriores', items,
        titleKey: 'title');
    if (chosen == null || !mounted) return;
    _addKeptUrls(
        ((chosen['image_urls'] as List?)?.cast<String>() ?? const <String>[]));
  }

  /// Hoja genérica para elegir un item con foto + nombre (tienda o portafolio).
  Future<Map<String, dynamic>?> _pickStoreItemSheet(
      String title, List<Map<String, dynamic>> items,
      {String titleKey = 'name'}) {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<Map<String, dynamic>>(
      sheetAnimationStyle: JayaloMotion.sheetRise,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: jayaloHead(ctx))),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final it = items[i];
                final urls =
                    (it['image_urls'] as List?)?.cast<String>() ?? const [];
                final first = urls.isEmpty ? null : urls.first;
                return Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, it),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: first == null
                              ? Container(
                                  width: 54,
                                  height: 54,
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(Icons.image_outlined,
                                      color: cs.onSurfaceVariant))
                              : JayaloNetworkImage(first,
                                  width: 54, height: 54, fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                      width: 54,
                                      height: 54,
                                      color: cs.surfaceContainerHighest)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(it[titleKey] as String? ?? 'Sin nombre',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        Text('${urls.length} 📷',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  /// Autocompleta el formulario con los datos de un producto/servicio de la
  /// tienda: precio/color/condición/booleanos de siempre, MÁS el molde
  /// completo (Task 9: marca, garantía, entrega, colores, precios de
  /// envío/instalación/evaluación y, si es servicio, modo de precio + tarifa
  /// + horas + disponibilidad + duración) cuando el ítem trae
  /// `offer_defaults` (Task 6). El cálculo es puro
  /// ([computeStoreProductPrefill], `domain/store_product_prefill.dart`) para
  /// poder probarlo sin montar esta pantalla (que exige una sesión de
  /// Supabase real desde `initState`); aquí solo se vuelca el resultado a los
  /// controllers.
  void _applyStoreProduct(Map<String, dynamic> p) {
    final prefill = computeStoreProductPrefill(
      p,
      isService: _isService,
      svcModes: _svcModes,
      existingColors: _colors,
    );
    // Dinero del molde → agrupado en miles, igual que si se hubiera tecleado
    // con el MilesInputFormatter (y de paso "3000.0" se normaliza vía
    // parseMiles en vez de caer crudo en el campo).
    String miles(String s) {
      final n = parseMiles(s);
      return n == null ? '' : fmtMiles(n);
    }

    setState(() {
      if (prefill.fixed != null) _fixed = prefill.fixed!;
      if (prefill.svcMode != null) _svcMode = prefill.svcMode!;
      if (prefill.price != null) _price.text = miles(prefill.price!);
      if (prefill.priceMin != null) _min.text = miles(prefill.priceMin!);
      if (prefill.priceMax != null) _max.text = miles(prefill.priceMax!);
      _colors.addAll(prefill.colorsToAdd);
      if (prefill.condition != null) _condition = prefill.condition!;
      _offersShipping = prefill.offersShipping;
      _offersInstallation = prefill.offersInstallation;
      _requiresEvaluation = prefill.requiresEvaluation;
      if (prefill.hourlyRate != null) {
        _hourly.text = miles(prefill.hourlyRate!);
      }
      if (prefill.estimatedHours != null) {
        _hours.text = prefill.estimatedHours!;
      }
      if (prefill.availability != null) {
        _availability.text = prefill.availability!;
      }
      if (prefill.duration != null) _duration.text = prefill.duration!;
      if (prefill.shippingPrice != null) {
        _shipping.text = miles(prefill.shippingPrice!);
      }
      if (prefill.installationPrice != null) {
        _installation.text = miles(prefill.installationPrice!);
      }
      if (prefill.evaluationPrice != null) {
        _evaluation.text = miles(prefill.evaluationPrice!);
      }
      if (prefill.brand != null) _brand.text = prefill.brand!;
      if (prefill.warranty != null) _warranty.text = prefill.warranty!;
      if (prefill.delivery != null) _delivery.text = prefill.delivery!;
    });
    _addKeptUrls(
        ((p['image_urls'] as List?)?.cast<String>() ?? const <String>[]));
    _toast('Datos cargados de tu tienda — edítalos si quieres.');
    // Elegir de la tienda NO marca el formulario como sucio (spec Task 9):
    // se recaptura la instantánea DESPUÉS de aplicar el molde, fuera del
    // setState (igual criterio que `_prefillFromOffer`).
    _cleanSnapshot = _formSnapshot();
  }

  Future<void> _submit() async {
    final req = _req!;
    // Gate: no ofertar (oferta NUEVA) si la solicitud ya tiene 3 finalistas
    // (complementa el trigger block_offer_when_full, que bloquea INSERT, no
    // UPDATE). En modo edición NO aplica: editar es un UPDATE permitido.
    if (!_editing && isClosedToOffers(_acceptedCount)) {
      return _toast('Esta solicitud ya completó su selección (3 de 3).');
    }
    final isService = _isService;
    final mode = _pricingMode;

    double? p, mn, mx, hr, hrs;
    switch (mode) {
      case 'fixed':
        p = parseMiles(_price.text)?.toDouble();
        if (p == null || p <= 0) return _toast('Pon el precio en RD\$.');
      case 'range':
        mn = parseMiles(_min.text)?.toDouble();
        mx = parseMiles(_max.text)?.toDouble();
        if (mn == null || mx == null || mx < mn) {
          return _toast('Revisa el rango de precio.');
        }
      case 'hourly':
        hr = parseMiles(_hourly.text)?.toDouble();
        hrs = double.tryParse(_hours.text);
        if (hr == null || hr <= 0) return _toast('Pon la tarifa por hora.');
        if (hrs == null || hrs <= 0) return _toast('Pon las horas estimadas.');
      // 'needs_evaluation' (solo servicio): el precio se define en sitio, sin
      // validación de precio aquí.
    }

    // Solo producto: en servicio estos dos campos ni se envian (ver los
    // `isService ? '' : ...` de composeOfferMessage mas abajo).
    if (!isService) {
      if (_condition.isEmpty) {
        return _toast('Elige si el producto es nuevo o usado.');
      }
      if (_warranty.text.trim().isEmpty) {
        // 'Sin garantia' es uno de los presets: exigir el campo no obliga a
        // nadie a prometer garantia, solo a decirlo.
        return _toast('Elige la garantía.');
      }
    }

    // Cotejo contra lo que el cliente marcó. Solo al CREAR: en edición las dos
    // capacidades están congeladas (su UPDATE está denegado), así que no habría
    // nada que corregir y el aviso solo estorbaría.
    if (!_editing) {
      final unmet = unmetRequirements(
        requirementsFromRow(req),
        OfferCapabilities(
          offersShipping: _offersShipping,
          offersInstallation: _offersInstallation,
          hasFiscalReceipt: _hasFiscalReceipt,
          isStateSupplier: _isStateSupplier,
        ),
      );
      if (unmet.isNotEmpty) {
        final seguir = await showOfferRequirementsWarning(context, unmet);
        if (!mounted) return;
        if (!seguir) return;
      }
    }

    // El mensaje ya no es texto libre: se arma desde los datos (decisión PO).
    final evalOn = isService ? mode == 'needs_evaluation' : _requiresEvaluation;
    final message = composeOfferMessage(
      isService: isService,
      offersShipping: _offersShipping,
      shippingPrice: parseMiles(_shipping.text)?.toDouble(),
      offersInstallation: _offersInstallation,
      installationPrice: parseMiles(_installation.text)?.toDouble(),
      requiresEvaluation: evalOn,
      evaluationPrice: parseMiles(_evaluation.text)?.toDouble(),
      availabilityNote: _availability.text,
      estimatedDuration: _duration.text,
      brand: isService ? '' : _brand.text,
      colors: isService ? const [] : _colors,
      warranty: isService ? '' : _warranty.text,
      deliveryTime: isService ? '' : _delivery.text,
      condition: isService ? '' : _condition,
    );

    // Anti-elusión (PO 2026-07-29): mismo aviso ANTES de subir fotos — que el
    // trigger `enforce_no_contact_info` (JY422) rechace la fila DESPUÉS de
    // subirlas le haría perder trabajo real al proveedor. Se revisan
    // exactamente los valores condicionados que después viajan a
    // makeOffer/updateOffer (ver `offerFields` en data/repos.dart): el
    // mensaje ya compuesto y, según producto/servicio, disponibilidad/
    // duración o marca/garantía/entrega/colores — las mismas columnas que
    // vigila el trigger para `provider_offers`. MANTENIMIENTO: si agregas un
    // campo de texto libre nuevo que llegue a una columna vigilada de
    // `provider_offers`, súmalo también aquí (no hay Map único que enumerar —
    // ver la nota del reporte de la Task 4 sobre por qué es a mano).
    final contactCheckValues = <String>[
      message,
      isService ? _availability.text.trim() : '',
      isService ? _duration.text.trim() : '',
      isService ? '' : _brand.text.trim(),
      isService ? '' : _warranty.text.trim(),
      isService ? '' : _delivery.text.trim(),
      if (!isService) ..._colors,
    ];
    if (contactCheckValues.any(containsContactInfo)) {
      return _toast(contactInfoMessage);
    }

    // Espejo del proveedor de "enviar solicitud": pasados todos los gates, la
    // oferta se va. Mismo criterio que allá — el pulso marca el envío real, no
    // el toque del botón (un `return _toast(...)` de validación no vibra).
    JayaloHaptics.sent();
    setState(() => _busy = true);
    try {
      // Subir las fotos NUEVAS a Storage antes de guardar (nunca base64 en la
      // BD). En edición se combinan con las que se conservan ([_keptUrls]).
      final newUrls =
          await Future.wait(_photos.map((x) => uploadOfferImage(x.path)));
      // Las conservadas (edición) + las de tienda/portafolio ([_keptUrls]) van
      // SIEMPRE, no solo en edición.
      final imageUrls = [..._keptUrls, ...newUrls];
      if (_editing) {
        final written = await updateOffer(
          offerId: _editOfferId!,
          price: p,
          priceMin: mn,
          priceMax: mx,
          message: message,
          imageUrls: imageUrls,
          pricingMode: mode,
          offersShipping: isService ? false : _offersShipping,
          shippingPrice: parseMiles(_shipping.text)?.toDouble(),
          offersInstallation: isService ? false : _offersInstallation,
          installationPrice: parseMiles(_installation.text)?.toDouble(),
          requiresEvaluation: evalOn,
          evaluationPrice: parseMiles(_evaluation.text)?.toDouble(),
          hourlyRate: hr,
          estimatedHours: hrs,
          availabilityNote: isService ? _availability.text.trim() : '',
          estimatedDuration: isService ? _duration.text.trim() : '',
          productBrand: isService ? '' : _brand.text.trim(),
          productColors: isService ? const [] : _colors,
          productWarranty: isService ? '' : _warranty.text.trim(),
          deliveryTime: isService ? '' : _delivery.text.trim(),
        );
        if (!mounted) return;
        _toast('Oferta actualizada');
        // Enviada: lo que hay en el formulario ya esta guardado, ni la
        // navegacion de abajo (ruta) ni quedarse en esta pantalla (en sitio)
        // deben preguntar nada. Cubre las DOS salidas de este brazo.
        releaseUnsavedGuard(this);
        // Entrada en sitio (pedido PO 2026-08-03): no se sale de la solicitud;
        // se vuelve a modo lectura con la tarjeta reflejando lo recién
        // guardado. `_busy` lo repone el `finally` de abajo.
        if (_editingInPlace) {
          // Parcha `_existingOffer` EN LOCAL con los mismos valores que se
          // acaban de pasar a `updateOffer`, en vez de depender de releerlos
          // del servidor con `_reloadOffer` (que traga cualquier error,
          // `:911-918`, y aquí sería el ÚNICO mecanismo mostrando el precio
          // nuevo). Si esa lectura fallara justo después de un guardado
          // correcto: el toast de éxito ya salido quedaría contradicho por un
          // precio VIEJO en la tarjeta, y la siguiente "Ver mi oferta"
          // recargaría esos valores rancios — "Guardar cambios" los
          // reescribiría encima de los nuevos, revirtiendo en silencio una
          // escritura que sí tuvo éxito. Los valores de abajo son los que
          // acabamos de confirmar que se escribieron: no hay red ni lectura
          // que pueda fallar.
          //
          // `written` es el mapa EXACTO que `updateOffer` acaba de mandar a la
          // base, no una recomposición. Recomponerlo aquí a mano divergía en
          // seis campos: `offerFields` anula el costo de envío/instalación/
          // evaluación si su toggle está apagado o el importe no es > 0, y
          // guarda los detalles de producto vacíos como `null`, no como `''`.
          // Esa copia rancia se colaba en la siguiente "Ver mi oferta".
          final patched = {..._existingOffer!, ...written};
          setState(() {
            _existingOffer = patched;
            _editOfferId = null;
            _editingInPlace = false;
            // Las fotos recién elegidas ya subieron a Storage y quedaron
            // dentro de `imageUrls` (arriba) -> la oferta guardada. Sin
            // limpiar esto, la próxima "Ver mi oferta" las mantendría en
            // `_photos` A LA VEZ que `_prefillFromOffer` las vuelve a traer
            // como `_keptUrls` (ya están en `image_urls`): la foto se vería
            // duplicada y un guardado posterior la re-subiría de nuevo. NO se
            // limpia `_condition` aquí: a diferencia de las fotos no se
            // duplica (es un string que se sobrescribe, no una lista que
            // acumula) y borrarlo perdería información que sigue vigente —
            // coincide con lo que el mensaje que se acaba de guardar dice.
            // `_prefillFromOffer` tampoco lo toca al reabrir, así que dejarlo
            // como está es lo consistente.
            _photos.clear();
          });
          return;
        }
        // Entrada por ruta, desde "Mis ofertas": sale a la lista, como siempre.
        context.go('/provider/offers');
        return;
      }
      await makeOffer(
        request: req,
        businessId: _businessId!,
        price: p,
        priceMin: mn,
        priceMax: mx,
        message: message,
        imageUrls: imageUrls,
        pricingMode: mode,
        // Los toggles de logística solo aplican a producto.
        offersShipping: isService ? false : _offersShipping,
        shippingPrice: parseMiles(_shipping.text)?.toDouble(),
        offersInstallation: isService ? false : _offersInstallation,
        installationPrice: parseMiles(_installation.text)?.toDouble(),
        requiresEvaluation: evalOn,
        evaluationPrice: parseMiles(_evaluation.text)?.toDouble(),
        hourlyRate: hr,
        estimatedHours: hrs,
        availabilityNote: isService ? _availability.text.trim() : '',
        estimatedDuration: isService ? _duration.text.trim() : '',
        productBrand: isService ? '' : _brand.text.trim(),
        productColors: isService ? const [] : _colors,
        productWarranty: isService ? '' : _warranty.text.trim(),
        deliveryTime: isService ? '' : _delivery.text.trim(),
        // Solo al crear: en `updateOffer` NO van: su UPDATE está denegado y
        // PostgREST rechazaría la fila entera.
        hasFiscalReceipt: _hasFiscalReceipt,
        isStateSupplier: _isStateSupplier,
      );
      // Enviada: lo que hay en el formulario ya esta guardado, la navegacion
      // que viene (tras la celebracion) no debe preguntar nada.
      releaseUnsavedGuard(this);
      if (!mounted) return;
      // ¿Guardar lo ofertado como producto de la tienda? (pedido PO): antes de
      // la celebración, para reusarlo en futuras ofertas.
      await _maybeSaveToStore(
        isService: isService,
        price: p,
        priceMin: mn,
        priceMax: mx,
        imageUrls: imageUrls,
      );
      if (!mounted) return;
      await showOfferSentCelebration(context); // 🎉 mascota + confeti
      if (!mounted) return;
      context.go('/provider');
    } catch (e) {
      if (mounted) _showSubmitError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tras enviar la oferta, ofrece GUARDAR lo ofertado como producto/servicio
  /// de la tienda para reusarlo (pedido PO 2026-07-21). El nombre se prefija
  /// con el título de la solicitud; el rubro/categoría salen del negocio (son
  /// NOT NULL en `provider_products`). Si el negocio no tiene rubro/categoría,
  /// se omite en silencio (no se puede guardar sin ellos).
  Future<void> _maybeSaveToStore({
    required bool isService,
    double? price,
    double? priceMin,
    double? priceMax,
    required List<String> imageUrls,
  }) async {
    final bid = _businessId;
    if (bid == null) return;
    final nameCtrl = TextEditingController(
        text: (_req?['title'] as String? ?? '').trim());
    final save = await showModalBottomSheet<bool>(
      sheetAnimationStyle: JayaloMotion.sheetRise,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.paddingOf(ctx).bottom +
                20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  isService
                      ? '¿Guardar este servicio en tu tienda?'
                      : '¿Guardar este producto en tu tienda?',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                  'Quedará publicado en tu tienda para reusarlo en próximas '
                  'ofertas — con las mismas fotos y detalles.'),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: filledField(ctx, 'Nombre en la tienda'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar en mi tienda'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Ahora no'),
              ),
            ]),
      ),
    );
    if (save != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final description = (_req?['description'] as String? ?? '').trim();
    final color = isService ? '' : (_colors.isEmpty ? '' : _colors.first);
    // Anti-elusión (PO 2026-07-29): mismas columnas vigiladas por el trigger
    // `enforce_no_contact_info` para `provider_products` — name/description/
    // color. Este chequeo corre al ENVIAR LA OFERTA (aguas abajo de
    // `makeOffer`, en el sheet "¿Guardar en tu tienda?"), así que solo cubre
    // ESTE camino de escritura. `add_store_item_screen.dart` (Task 6,
    // 2026-08-09: alta/edición de ítem de tienda desde "Mi negocio") es OTRO
    // camino de escritura a `provider_products` y NO pasa por este chequeo
    // — lo cubre solo el trigger `enforce_no_contact_info` del lado del
    // servidor (JY422), sin este aviso amigable antes de subir fotos. Si
    // agregas un campo de texto libre nuevo a ESTE guardado que llegue a una
    // columna vigilada, súmalo a esta lista también.
    //
    // La OFERTA ya se envió con éxito en este punto (este método se llama
    // después de `makeOffer`) — lo que se bloquea aquí es solo el guardado en
    // la tienda, así que el aviso no debe leerse como que la oferta se perdió.
    // `contactInfoMessage` no la menciona, y aparece dentro del contexto del
    // propio sheet "Guardar en mi tienda" que el proveedor acaba de tocar.
    if ([name, description, color].any(containsContactInfo)) {
      if (mounted) _toast(contactInfoMessage);
      return;
    }
    ({String? categoryId, String? rubro}) cr;
    try {
      cr = await myBusinessCategoryRubro(bid);
    } catch (_) {
      return;
    }
    if (cr.categoryId == null || cr.rubro == null) {
      if (mounted) {
        _toast('Para guardarlo en tu tienda te falta categoría/rubro en el negocio.');
      }
      return;
    }
    try {
      await saveProductToStore(
        businessId: bid,
        name: name,
        description: description,
        categoryId: cr.categoryId!,
        rubro: cr.rubro!,
        kind: isService ? 'servicio' : 'producto',
        color: color,
        price: price,
        priceMin: priceMin,
        priceMax: priceMax,
        imageUrls: imageUrls,
        condition: isService
            ? null
            : (_condition == 'Nuevo'
                ? 'nuevo'
                : _condition == 'Usado'
                    ? 'usado'
                    : null),
        offersShipping: isService ? false : _offersShipping,
        offersInstallation: isService ? false : _offersInstallation,
        requiresEvaluation: isService ? false : _requiresEvaluation,
      );
      if (mounted) _toast('Guardado en tu tienda ✓');
    } catch (e) {
      // Red de seguridad: si el chequeo de arriba no atrapó algo, el trigger
      // de la BD (JY422) sí lo bloquea — traducirlo al mismo mensaje humano en
      // vez del genérico, sin implicar que la oferta (ya enviada) falló.
      if (mounted) {
        _toast(isContactInfoError(e)
            ? contactInfoMessage
            : 'No se pudo guardar en tu tienda.');
      }
    }
  }

  /// Borra la oferta pendiente (doble confirmación). Solo aparece en edición.
  Future<void> _deleteOffer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tu oferta?'),
        content: const Text(
            'Esta oferta desaparecerá para el cliente. No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await deleteOffer(_editOfferId!);
      if (!mounted) return;
      _toast('Oferta eliminada');
      context.go('/provider/offers');
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('No se pudo eliminar. Intenta de nuevo.');
      }
    }
  }

  /// Nunca esconder el porqué real de un fallo al ofertar. El caso dominante es
  /// el trigger `enforce_business_can_offer` (proveedor informal/técnico sin
  /// cédula → `ID_DOC_REQUIRED`): antes salía un genérico "no se pudo enviar" y
  /// el proveedor no tenía idea de qué le faltaba. Ahora mostramos el motivo y,
  /// para ese caso, un atajo para completar la identidad en la web.
  void _showSubmitError(Object e) {
    // Red de seguridad: si el aviso previo no atrapó algo (p. ej. un dato de
    // contacto colado en una foto guardada de la tienda, no en un campo de
    // texto), el trigger de la BD (JY422) sí lo bloquea — traducir su
    // SQLSTATE al mismo mensaje humano en vez del genérico de abajo.
    if (isContactInfoError(e)) {
      _toast(contactInfoMessage);
      return;
    }
    final msg = e is PostgrestException ? e.message : e.toString();
    if (msg.contains('ID_DOC_REQUIRED')) {
      final reason = msg.replaceFirst(RegExp(r'^ID_DOC_REQUIRED:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(reason),
        // La cedula se registra DENTRO de la app (Ajustes -> "Validar
        // negocio" usa la misma hoja). Sacar al navegador aqui llevaba al
        // panel web, que trae dos botones de "Recargar creditos" con PayPal:
        // un link-out prohibido por la politica de pagos de Play.
        action: SnackBarAction(
          label: 'Completar',
          onPressed: () {
            final id = _businessId;
            if (id != null) showIdDocSheet(context, businessId: id);
          },
        ),
      ));
      return;
    }
    _toast('No se pudo enviar la oferta.');
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Recarga la oferta existente tras una mutación (desbloqueo / venta
  /// marcada) para que la tarjeta refleje el estado nuevo.
  Future<void> _reloadOffer() async {
    final id = _existingOffer?['id'] as String?;
    if (id == null) return;
    try {
      final o = await offerForEdit(id);
      if (mounted && o != null) setState(() => _existingOffer = o);
    } catch (_) {}
    // Tras un desbloqueo, la ficha del cliente pasa de anónima a identidad
    // real sin salir de la pantalla (PO 2026-08-11). Best-effort.
    final cid = _req?['user_id'] as String?;
    if (cid != null) {
      customerPublicProfile(cid)
          .then((p) => mounted ? setState(() => _custProfile = p) : null)
          .catchError((_) => null);
    }
  }

  /// Entra en modo edición SOBRE ESTA MISMA PANTALLA (pedido PO 2026-08-03).
  /// No navega: la ruta de destino (`/provider/request/<id>?edit=<offerId>`)
  /// es la que ya se está mostrando, y apilarla dejaría dos copias.
  ///
  /// No hace falta ninguna consulta: [_existingOffer] viene de
  /// `myOfferForRequest`, que selecciona `offerCols` (`repos.dart:272-289`), y
  /// esas columnas cubren todo lo que lee [_prefillFromOffer].
  void _editInPlace(Map<String, dynamic> o) {
    setState(() {
      _editOfferId = o['id'] as String;
      _editingInPlace = true;
      _prefillFromOffer(o);
    });
  }

  /// Sale del modo edición en sitio SIN guardar y devuelve la tarjeta.
  ///
  /// Limpia lo único que [_prefillFromOffer] no reasigna al volver a entrar:
  /// las fotos recién elegidas y `_condition` (que la oferta no guarda en
  /// columna propia). Sin esto, cancelar y reabrir arrastraría fotos y un
  /// "Nuevo/Usado" que el proveedor creía descartados.
  void _cancelInPlaceEdit() {
    setState(() {
      _editOfferId = null;
      _editingInPlace = false;
      _photos.clear();
      _condition = '';
    });
    // Cancelar YA es la respuesta explicita del proveedor a "¿salir y
    // descartar los cambios?" — no debe preguntar de nuevo. Este metodo no
    // vuelve a correr `_prefillFromOffer` (el formulario ya no se muestra:
    // vuelve la tarjeta), asi que lo que haya quedado escrito en los
    // controladores de texto se toma como el nuevo estado "limpio". La
    // proxima vez que se entre en edicion, `_editInPlace` -> `_prefillFromOffer`
    // vuelve a rellenar todo desde `_existingOffer` (que nunca cambio, porque
    // no se guardo nada) y pisa cualquier resto de este intento cancelado.
    _cleanSnapshot = _formSnapshot();
  }

  /// Tarjeta de la oferta ya enviada, consciente del ESTADO (pedido PO
  /// 2026-07-21): pendiente = aviso "ya ofertaste"; aceptada = "¡Te
  /// aceptaron!" con el botón DESBLOQUEAR (nunca el formulario de edición);
  /// desbloqueada/completada = "Ver contacto"; rechazada = aviso neutro.
  Widget _alreadyOfferedCard(BuildContext context) {
    final o = _existingOffer!;
    final st = o['status'] as String? ?? 'pending';
    final unlocked = o['unlocked_at'] != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label = _offerLabel(o);

    // Pura y evaluada dos veces en el brazo comodín de abajo (copy y acción
    // del CTA tienen que ir emparejados); una sola lectura deja obvio que van
    // juntos.
    final canEdit = canEditOfferInPlace(o);
    final (StatusTone tone, IconData icon, String title, String body,
        String? cta, VoidCallback? onCta) = switch (st) {
      'rejected' => (
          dark ? JayaloStatus.completedDark : JayaloStatus.completedLight,
          Icons.do_not_disturb_on_outlined,
          'El cliente eligió otra oferta',
          'Tu oferta fue $label. Sigue atento a nuevas solicitudes de tu rubro.',
          null,
          null,
        ),
      // `unlocked_at` GANA sobre el status (bug PO 2026-07-23: decía "Ya
      // enviaste tu oferta" con el contacto ya desbloqueado). Cualquier oferta
      // desbloqueada (o completada) muestra "Contacto desbloqueado", sin
      // importar si el status quedó en 'pending'/'accepted'.
      _ when unlocked || st == 'completed' => (
          dark ? JayaloStatus.unlockedDark : JayaloStatus.unlockedLight,
          Icons.check_circle,
          'Contacto desbloqueado',
          'Tu oferta: $label. Ya puedes hablar con el cliente.',
          'Ver contacto',
          () => showOfferContactSheet(context, o, onChanged: _reloadOffer),
        ),
      // Aceptada pero AÚN NO desbloqueada (lo desbloqueado ya lo tomó el arm de
      // arriba). Violeta = el color de "desbloquear" (pedido PO 2026-07-22).
      'accepted' => (
          dark ? JayaloStatus.respondedDark : JayaloStatus.respondedLight,
          Icons.emoji_events_outlined,
          '🏆 ¡Te aceptaron!',
          'El cliente aceptó tu oferta de $label. Desbloquea su contacto '
              'para cerrar el trato.',
          'Desbloquear contacto',
          () => startUnlockFlow(context, o, onChanged: _reloadOffer),
        ),
      _ => (
          dark ? JayaloStatus.acceptedDark : JayaloStatus.acceptedLight,
          Icons.check_circle,
          'Ya enviaste tu oferta',
          'Solo puedes ofertar una vez por solicitud. Tu oferta: $label. '
              'Si el cliente la acepta, te avisaremos para desbloquear el contacto.',
          // Pedido PO 2026-08-03: en singular y a ESA oferta, sin salir de la
          // solicitud. Este brazo es el COMODÍN del switch: si cae aquí una
          // fila que la compuerta de abajo no dejaría editar, se conserva el
          // CTA viejo en vez de ofrecer un botón que no hace nada.
          canEdit ? 'Ver mi oferta' : 'Ver mis ofertas',
          canEdit
              ? () => _editInPlace(o)
              : () => context.go('/provider/offers'),
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: tone.bg, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: tone.ink, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: tone.ink)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(body,
            style: TextStyle(fontSize: 13, height: 1.4, color: tone.ink)),
        if (cta != null) ...[
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: tone.ink, foregroundColor: tone.bg),
            onPressed: onCta,
            child: Text(cta),
          ),
        ],
      ]),
    );
  }

  /// Campo numérico. Por defecto es de DINERO: agrupa miles al escribir
  /// ("12,000", pedido PO 2026-08-10) — el submit parsea con `parseMiles`.
  /// `miles: false` para cantidades que no son precio (horas estimadas).
  Widget _numField(TextEditingController c, String label,
          {bool miles = true}) =>
      TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: miles ? [MilesInputFormatter()] : null,
        onChanged: (_) => setState(() {}),
        decoration: filledField(context, label),
      );

  Widget _textField(TextEditingController c, String label) => TextField(
        controller: c,
        decoration: filledField(context, label),
      );

  /// Campos de precio, ramificados por kind: producto = fijo/rango; servicio =
  /// 4 modos (fijo/rango/por hora/a evaluar), paridad con la web.
  ///
  /// Todo el bloque va dentro de un marco violeta (pedido PO 2026-08-04). El
  /// selector de modo entra en el marco a proposito: elegir "Rango" o "Por
  /// hora" es parte de decir el precio, no un ajuste aparte.
  List<Widget> _pricingFields(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _isService
              ? _servicePricing(context)
              : _productPricing(context),
        ),
      ),
    ];
  }

  List<Widget> _productPricing(BuildContext context) => [
        PillSegmented(
          options: const ['Precio fijo', 'Rango'],
          index: _fixed ? 0 : 1,
          onChanged: (i) => setState(() => _fixed = i == 0),
        ),
        const SizedBox(height: 12),
        if (_fixed)
          _numField(_price, 'Precio (RD\$)')
        else
          Row(children: [
            Expanded(child: _numField(_min, 'Desde (RD\$)')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_max, 'Hasta (RD\$)')),
          ]),
      ];

  List<Widget> _servicePricing(BuildContext context) => [
        PillSegmented(
          options: const ['Fijo', 'Rango', 'Por hora', 'A evaluar'],
          index: _svcMode,
          onChanged: (i) => setState(() => _svcMode = i),
        ),
        const SizedBox(height: 12),
        ..._svcModeFields(context),
      ];

  List<Widget> _svcModeFields(BuildContext context) {
    switch (_svcModes[_svcMode]) {
      case 'fixed':
        return [_numField(_price, 'Precio (RD\$)')];
      case 'range':
        return [
          Row(children: [
            Expanded(child: _numField(_min, 'Desde (RD\$)')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_max, 'Hasta (RD\$)')),
          ]),
        ];
      case 'hourly':
        return [
          Row(children: [
            Expanded(child: _numField(_hourly, 'RD\$ por hora')),
            const SizedBox(width: 8),
            Expanded(child: _numField(_hours, 'Horas est.', miles: false)),
          ]),
        ];
      default: // needs_evaluation
        final cs = Theme.of(context).colorScheme;
        return [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
                'El precio se define tras revisar en sitio; el cliente lo verá como "a evaluar".',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        ];
    }
  }

  /// Toggles de logística de PRODUCTO (envío/instalación/evaluación), cada uno
  /// con su costo opcional y la etiqueta "Gratis" cuando el costo es 0.
  List<Widget> _productExtras(BuildContext context) => [
        _toggleRow(
          title: 'Ofrezco envío',
          subtitle: 'Puedes llevar el producto al cliente.',
          value: _offersShipping,
          onChanged: (v) => setState(() => _offersShipping = v),
          cost: _shipping,
          costLabel: 'Costo de envío (RD\$)',
        ),
        _toggleRow(
          title: 'Ofrezco instalación',
          subtitle: 'Incluyes el servicio de instalación.',
          value: _offersInstallation,
          onChanged: (v) => setState(() => _offersInstallation = v),
          cost: _installation,
          costLabel: 'Costo de instalación (RD\$)',
        ),
        _toggleRow(
          title: 'Requiere evaluación',
          subtitle: 'El precio depende de revisar en sitio.',
          value: _requiresEvaluation,
          onChanged: (v) => setState(() => _requiresEvaluation = v),
          cost: _evaluation,
          costLabel: 'Costo de evaluación (RD\$)',
        ),
      ];

  Widget _txtField(TextEditingController c, String label) =>
      TextField(controller: c, decoration: filledField(context, label));

  Widget _sectionLabel(String t) => Text(t,
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: jayaloHead(context)));

  /// ¿La seccion "Informacion" tiene algo que ensenar? Es exactamente lo que
  /// se dibuja debajo del encabezado: bullets y presupuesto.
  ///
  /// `is_wholesale` NO cuenta desde 2026-08-04: los datos de mayoreo se
  /// mudaron a `WholesaleCard`, arriba con el titulo. Volver a sumarlo aqui
  /// deja "INFORMACION" flotando sobre un divisor sin nada debajo.
  static bool _hasInfo(Map<String, dynamic> req, List<String> bullets) =>
      bullets.isNotEmpty ||
      requestBudgetLabel(req['budget_min'] as num?, req['budget_max'] as num?) !=
          null;

  /// Chips de selección única (garantía, disponibilidad, estado). Tocar el
  /// activo lo deselecciona.
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

  /// Círculos de color multi-selección (paridad web COLOR_PRESETS).
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

  Future<void> _pickDelivery() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)));
    // `showDatePicker` tarda lo que el usuario quiera: sin el guard, el
    // `setState` de abajo corre sobre un widget que pudo desmontarse.
    if (d == null || !mounted) return;
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final days = target.difference(today).inDays;
    setState(() => _delivery.text =
        days <= 0 ? 'Hoy' : (days == 1 ? '1 día' : '$days días'));
  }

  /// Detalles del producto con selectores (paridad web): estado (nuevo/usado),
  /// color (círculos), garantía (chips) y tiempo de entrega (calendario).
  List<Widget> _productDetails(BuildContext context) => [
        _sectionLabel('Detalles del producto'),
        const SizedBox(height: 8),
        _txtField(_brand, 'Marca'),
        const SizedBox(height: 14),
        _sectionLabel('Estado *'),
        const SizedBox(height: 8),
        _chipSelect(kConditionOptions, _condition,
            (v) => setState(() => _condition = v)),
        const SizedBox(height: 14),
        _sectionLabel('Color'),
        const SizedBox(height: 8),
        _colorSwatches(),
        const SizedBox(height: 14),
        _sectionLabel('Garantía *'),
        const SizedBox(height: 8),
        _chipSelect(kWarrantyOptions, _warranty.text,
            (v) => setState(() => _warranty.text = v)),
        const SizedBox(height: 14),
        _sectionLabel('Tiempo de entrega'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _pickDelivery,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(_delivery.text.isEmpty
                ? 'Elegir fecha de entrega'
                : 'Entrega: ${_delivery.text}'),
          ),
        ),
      ];

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    // Sin costo: las capacidades transversales no tienen precio, así que el
    // controlador y su etiqueta son opcionales y el bloque del costo no se
    // pinta. `enabled: false` deja el interruptor en solo lectura (edición).
    TextEditingController? cost,
    String? costLabel,
    bool enabled = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final free = cost != null && (parseMiles(cost.text) ?? 0) <= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (_busy || !enabled) ? null : onChanged,
          ),
        ]),
        if (value && cost != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(children: [
              Expanded(child: _numField(cost, costLabel ?? '')),
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

  Widget _thumb(File file, int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file,
              width: 76, height: 76, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.cancel, size: 22),
            onPressed:
                _busy ? null : () => setState(() => _photos.removeAt(index)),
          ),
        ),
      ]);

  /// Miniatura de una foto YA subida (modo edición): igual que [_thumb] pero
  /// desde la URL de Storage; quitarla la saca de [_keptUrls].
  Widget _keptThumb(String url, int index) => Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: JayaloNetworkImage(url,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                  width: 76,
                  height: 76,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest)),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.cancel, size: 22),
            onPressed:
                _busy ? null : () => setState(() => _keptUrls.removeAt(index)),
          ),
        ),
      ]);

  /// Escalera de FOMO del proveedor: banner de color según finalistas
  /// seleccionados + recencia + ofertas recibidas. Copy exacto en
  /// `providerSlotSignal` (domain/finalist_slots.dart).
  Widget _slotLadder(BuildContext context) {
    final signal = providerSlotSignal(_acceptedCount, _offersCountLive);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = switch (signal.tone) {
      SlotTone.green => const Color(0xFF16A34A),
      SlotTone.yellow => const Color(0xFFCA8A04),
      SlotTone.orange => const Color(0xFFEA580C),
      SlotTone.red => const Color(0xFFE11D48),
    };
    final title = dark ? Color.lerp(base, Colors.white, .4)! : base;
    final offers = _offersCountLive;
    final createdAt = DateTime.tryParse(_req?['created_at'] as String? ?? '');
    String ago = '';
    if (createdAt != null) {
      final d = DateTime.now().difference(createdAt);
      ago = d.inMinutes < 60
          ? 'hace ${d.inMinutes} min'
          : d.inHours < 24
              ? 'hace ${d.inHours} h'
              : 'hace ${d.inDays} d';
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: base.withValues(alpha: dark ? .18 : .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: base.withValues(alpha: .40)),
      ),
      // Mockup aprobado 2026-08-11: los 3 cupos se VEN como asientos (llenos
      // vs libres) y el texto de la escalera los acompaña al lado.
      child: Row(
        children: [
          FinalistSeats(accepted: _acceptedCount, color: base),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(signal.text,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: title)),
                const SizedBox(height: 2),
                Text(
                  '${ago.isEmpty ? '' : '⏱️ Publicada $ago · '}'
                  '$offers oferta${offers == 1 ? '' : 's'} recibida${offers == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncCenterAction();
    final req = _req;
    if (req == null) {
      return Scaffold(
        body: Stack(children: [
          const JayaloLoaderBlock(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 16),
                child: _backButton(context),
              ),
            ),
          ),
        ]),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final bullets = List<String>.from(req['bullets'] as List? ?? const []);
    final images =
        ((req['image_urls'] as List?)?.cast<String>() ?? const <String>[])
            .where((u) => u.isNotEmpty)
            .toList();
    // Con la oferta desbloqueada/completada, el estado + "Ver contacto" viven
    // en un pie ANCLADO fuera del scroll (mockup aprobado 2026-08-11), como el
    // CTA del detalle del cliente: es lo que el proveedor ya pagó y no debe
    // irse de pantalla. El pie carga el hueco de la navbar; el scroll ya no.
    final footer = _offerUnlockedOrDone && !_editing;
    final scroll = CustomScrollView(slivers: [
        // La foto se PLIEGA al bajar (pedido PO 2026-08-01: "que se desplace
        // hacia arriba y casi se oculte, para que la ventana se vea
        // completa"). Antes era un panel de alto fijo con la lista debajo en
        // un `Expanded`, y el formulario de oferta —que es largo— vivía en un
        // tercio de pantalla. El widget se extrajo porque el detalle del
        // interés de producto necesita exactamente el mismo panel.
        CollapsingPhotoPanel(
          images: images,
          fallbackIcon: req['kind'] == 'servicio'
              ? Icons.handyman_outlined
              : Icons.inventory_2_outlined,
          leading: _backButton(context),
          onOpenViewer: (i) =>
              showPhotoViewer(context, images, initialIndex: i),
        ),
        SliverFillRemaining(
          // `hasScrollBody: false`: el contenido decide su alto y, si sobra
          // pantalla, la hoja la rellena igual — que es lo que hacía el
          // `Expanded` de antes.
          hasScrollBody: false,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(22, 22, 22,
                footer ? 16 : 16 + navBarReservedSpace(context)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(req['title'] as String,
                      style: TextStyle(
                          // +2pt (pedido PO 2026-07-22: otro punto).
                          fontSize: 23,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: jayaloHead(context))),
                  if (req['is_wholesale'] == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: WholesaleCard(
                        quantity: (req['wholesale_quantity'] as num?)?.toInt(),
                        split: req['wholesale_split'] as String?,
                        packaging: req['wholesale_packaging'] as String?,
                        note: req['wholesale_note'] as String?,
                      ),
                    ),
                  // Lo que el cliente EXIGE. Va con el título y el chip de
                  // mayoreo, no bajo "Información": es identidad de la
                  // solicitud, y es lo que decide si a este proveedor le
                  // conviene ofertar (orden pedido por el PO 2026-08-01).
                  RequestRequirementBadges(
                    req: requirementsFromRow(req),
                    variant: RequirementBadgeVariant.chips,
                    padding: const EdgeInsets.only(top: 8),
                  ),
                  // FOMO de cupos (modelo de hasta 3 finalistas): escalera de
                  // color + recencia + ofertas recibidas.
                  _slotLadder(context),
                  // ── 1) DATOS DEL CLIENTE ──
                  // Orden pedido por el PO (2026-08-01): datos del cliente →
                  // información → desbloqueo o enviar oferta. Antes la ficha
                  // del cliente iba al final, justo encima del formulario, y
                  // es lo primero que el proveedor mira para decidir si le
                  // conviene ofertar. El título y los chips de estado se
                  // quedan arriba (decisión PO): son la identidad de la
                  // solicitud, no "información".
                  sectionHeading(context, 'Datos del cliente'),
                  CustomerRepCard(
                    customerId: req['user_id'] as String?,
                    reputation: _custRep,
                    badges: _custBadges,
                    // Identidad real SOLO si la RPC dice desbloqueado
                    // (decisión PO 2026-08-11); null = ficha anónima.
                    realName: _custProfile?.unlocked == true
                        ? [_custProfile?.firstName, _custProfile?.lastName]
                            .whereType<String>()
                            .where((s) => s.trim().isNotEmpty)
                            .join(' ')
                        : null,
                    realAvatarUrl: _custProfile?.unlocked == true
                        ? _custProfile?.avatarUrl
                        : null,
                    // La ficha es la PUERTA al perfil (mockup 2026-08-11).
                    onTap: () => context
                        .push('/provider/customer/${req['user_id']}'),
                  ),
                  // ── 2) INFORMACIÓN ──
                  // El encabezado SOLO si hay algo debajo: una solicitud sin
                  // bullets y sin presupuesto dejaba "INFORMACIÓN" flotando
                  // sobre un divisor (visto en device 2026-08-01). Los datos
                  // de mayoreo NO cuentan aquí (ver docstring de `_hasInfo`)
                  // — viven en `WholesaleCard`, arriba con el título. Mismo
                  // criterio que `BusinessDetailsCard`, que no se dibuja si
                  // no tiene filas.
                  if (_hasInfo(req, bullets))
                    sectionHeading(context, 'Información'),
                  if (bullets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Detalles',
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final b in bullets)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(999)),
                          child: Text(b,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurface)),
                        ),
                    ]),
                  ],
                  if (requestBudgetLabel(req['budget_min'] as num?,
                          req['budget_max'] as num?) !=
                      null) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      Icon(Icons.payments_outlined,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                            'Presupuesto estimado: ${requestBudgetLabel(req['budget_min'] as num?, req['budget_max'] as num?)}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: jayaloHead(context))),
                      ),
                    ]),
                  ],
                  // ── 3) DESBLOQUEO O ENVIAR OFERTA ──
                  const Divider(height: 32),
                  if (!_editing && _businessId == null)
          FilledButton(
            // Antes abria jayalo.com/provider en el navegador. Ese panel tiene
            // "Recargar creditos" -> PayPal, asi que era un link-out aunque el
            // boton hablara de completar el negocio: lo que cuenta es donde
            // deja al usuario. El alta vive en la app.
            onPressed: () => context.push('/onboarding/provider'),
            child: const Text('Completa tu negocio para ofertar'),
          )
        else if (!_offerChecked)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: JayaloSpinner()),
          )
        // La tarjeta de estado sustituye al formulario SIEMPRE que hay oferta,
        // salvo edición de una PENDIENTE. Una aceptada nunca se edita (pedido
        // PO): su tarjeta trae el botón Desbloquear.
        // MANTENIMIENTO: `domain/offer_edit.dart` (`canEditOfferInPlace`)
        // reproduce esta condición para decidir si "Ver mi oferta" hace algo;
        // si tocas esta compuerta, actualiza esa regla también o el botón
        // vuelve a quedar muerto.
        else if (_existingOffer != null &&
            (!_editing || _existingOffer!['status'] != 'pending'))
          // Desbloqueada/completada: el estado vive en el pie anclado
          // (`_unlockedFooter`), no en una tarjeta que scrollea.
          (_offerUnlockedOrDone && !_editing
              ? const SizedBox.shrink()
              : _alreadyOfferedCard(context))
        else if (_offerFormVisible) ...[
          Text('Tu oferta', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._pricingFields(context),
          if (_isService) ...[
            const SizedBox(height: 14),
            _sectionLabel('Disponibilidad'),
            const SizedBox(height: 8),
            _chipSelect(_availabilityDays, _availability.text,
                (v) => setState(() => _availability.text = v)),
            const SizedBox(height: 12),
            _textField(_duration, 'Duración estimada (ej: 2 días)'),
          ] else ...[
            const SizedBox(height: 12),
            ..._productExtras(context),
            const SizedBox(height: 18),
            ..._productDetails(context),
          ],
          // Transversales: aplican a producto Y servicio, así que van FUERA del
          // bloque de producto. Meterlas dentro las haría invisibles en
          // servicios, que es la trampa que en la web mordió dos veces con los
          // chips del detalle.
          const SizedBox(height: 14),
          _sectionLabel('Lo que puedes cumplir'),
          const SizedBox(height: 8),
          _toggleRow(
            title: 'Emito comprobante fiscal',
            subtitle: _editing
                ? 'Quedó fijado al enviar tu oferta.'
                : 'Puedes emitir comprobante fiscal (NCF).',
            value: _hasFiscalReceipt,
            onChanged: (v) => setState(() => _hasFiscalReceipt = v),
            enabled: !_editing,
          ),
          _toggleRow(
            title: 'Soy suplidor del Estado',
            subtitle: _editing
                ? 'Quedó fijado al enviar tu oferta.'
                : 'Estás registrado como suplidor del Estado.',
            value: _isStateSupplier,
            onChanged: (v) => setState(() => _isStateSupplier = v),
            enabled: !_editing,
          ),
          const SizedBox(height: 16),
          Text(
              _isService
                  ? 'Fotos de tu trabajo (hasta $_maxOfferPhotos)'
                  : 'Fotos de tu producto (hasta $_maxOfferPhotos)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_keptUrls.isNotEmpty || _photos.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _keptUrls.length; i++)
                  _keptThumb(_keptUrls[i], i),
                for (var i = 0; i < _photos.length; i++)
                  _thumb(File(_photos[i].path), i),
              ],
            ),
          if (_photoCount < _maxOfferPhotos)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Cámara'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                  ),
                ),
              ]),
            ),
          // Reusar lo que el proveedor ya subió a su TIENDA / PORTAFOLIO
          // (pedido PO 2026-07-21): "De mi tienda" trae fotos + autocompleta;
          // "Trabajos anteriores" trae fotos del portafolio.
          if (_businessId != null && _photoCount < _maxOfferPhotos)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFromStore,
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('De mi tienda'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFromPortfolio,
                    icon: const Icon(Icons.collections_bookmark_outlined),
                    label: const Text('Trabajos'),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          if (_estimatedCost > 0)
            Builder(builder: (context) {
              // Ámbar = dinero: el costo del unlock se ve claro ANTES de
              // ofertar, sin asustar (ofertar sigue siendo gratis).
              final tone = Theme.of(context).brightness == Brightness.dark
                  ? JayaloStatus.acceptedDark
                  : JayaloStatus.acceptedLight;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                    'Ofertar es GRATIS. Si te aceptan, desbloquear el contacto '
                    'te costará ~$_estimatedCost crédito${_estimatedCost == 1 ? '' : 's'}.',
                    style: TextStyle(fontSize: 12, color: tone.ink)),
              );
            }),
          const SizedBox(height: 12),
          OnboardingGuide(
            guideKey: 'provider.make_offer.v1',
            steps: onboardingCopy['provider.make_offer.v1']!,
            child: FilledButton(
                onPressed:
                    _busy || (!_editing && isClosedToOffers(_acceptedCount))
                        ? null
                        : _submit,
                child: Text(
                    _editing ? 'Guardar cambios' : 'Enviar oferta (gratis)')),
          ),
          if (_editing) ...[
            // Salida sin guardar. Solo en la entrada EN SITIO: quien llega
            // desde "Mis ofertas" ya tiene su camino de vuelta. No se toca la
            // flecha flotante ni el PopScope de BackGuard.
            const SizedBox(height: 8),
            if (_editingInPlace) ...[
              TextButton(
                onPressed: _busy ? null : _cancelInPlaceEdit,
                child: const Text('Cancelar'),
              ),
              const SizedBox(height: 8),
            ],
            TextButton.icon(
              onPressed: _busy ? null : _deleteOffer,
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              label: Text('Eliminar oferta',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ],
              ]),
            ),
          ),
        ]);
    return Scaffold(
      body: footer
          ? Column(children: [
              Expanded(child: scroll),
              _unlockedFooter(context),
            ])
          : scroll,
    );
  }

  /// ¿La oferta propia ya tiene el contacto pagado (o el trato completado)?
  /// Decide el pie anclado y silencia la tarjeta equivalente del scroll.
  bool get _offerUnlockedOrDone {
    final o = _existingOffer;
    return o != null &&
        (o['unlocked_at'] != null || o['status'] == 'completed');
  }

  /// Pie anclado del estado desbloqueado (mockup 2026-08-11): línea verde con
  /// el precio de la oferta + CTA violeta "Ver contacto" — el violeta es el
  /// color de acción de toda la app; el verde queda como estado.
  Widget _unlockedFooter(BuildContext context) {
    final o = _existingOffer!;
    final cs = Theme.of(context).colorScheme;
    final green = Theme.of(context).brightness == Brightness.dark
        ? JayaloColors.dSuccess
        : JayaloColors.success;
    return ColoredBox(
      color: cs.surfaceContainerLowest,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(16, 10, 16, 12 + navBarReservedSpace(context)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle, size: 15, color: green),
            const SizedBox(width: 6),
            Text('Contacto desbloqueado',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: green)),
            Flexible(
              child: Text(' · Tu oferta: ${_offerLabel(o)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: () =>
                  showOfferContactSheet(context, o, onChanged: _reloadOffer),
              child: const Text('Ver contacto'),
            ),
          ),
        ]),
      ),
    );
  }

  /// Etiqueta de precio de la oferta propia (compartida por la tarjeta del
  /// scroll y el pie anclado — dos copias divergirían solas).
  static String _offerLabel(Map<String, dynamic> o) => o['price'] != null
      ? fmtRD(o['price'] as num)
      : (o['price_min'] != null && o['price_max'] != null)
          ? '${fmtRD(o['price_min'] as num)} – ${fmtRD(o['price_max'] as num)}'
          : (o['pricing_mode'] == 'hourly' && o['hourly_rate'] != null)
              ? '${fmtRD(o['hourly_rate'] as num)}/hora'
              : 'A evaluar';

  /// Atrás flotante sobre el panel (mismo gesto que el detalle del cliente: en
  /// el detalle no hay header violeta, solo el atrás).
  ///
  /// Devuelve el botón PELADO, sin posicionar: va al `leading` de la barra
  /// plegable —donde sigue tocable con el panel encogido— y también al Stack
  /// de la pantalla de carga, que sí necesita colocarlo arriba a la izquierda.
  Widget _backButton(BuildContext context) => Center(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          elevation: 1,
          child: InkWell(
            onTap: () async {
              // Mismo aviso que el atras del sistema: esta flecha no pasa por
              // BackGuard.
              if (hasUnsavedChanges()) {
                final salir = await confirmDiscard(context);
                if (!salir) return;
                if (!context.mounted) return;
              }
              context.pop();
            },
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: jayaloHead(context)),
            ),
          ),
        ),
      );
}

/// Los 3 cupos de finalista como ASIENTOS (mockup aprobado 2026-08-11): los
/// tomados se llenan del color de la escalera FOMO, los libres quedan como
/// aros tenues. Complementa el texto de `providerSlotSignal`, no lo sustituye.
/// Público para poder probarlo sin montar la pantalla (que exige Supabase).
class FinalistSeats extends StatelessWidget {
  const FinalistSeats({super.key, required this.accepted, required this.color});

  /// Finalistas ya seleccionados; se recorta a `[0, kMaxFinalists]` porque
  /// viene de una columna materializada que podría traer cualquier cosa.
  final int accepted;

  /// El color base de la escalera (verde → amarillo → naranja → rojo).
  final Color color;

  @override
  Widget build(BuildContext context) {
    final filled = accepted.clamp(0, kMaxFinalists);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < kMaxFinalists; i++)
        Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? color : Colors.transparent,
              border: i < filled
                  ? null
                  : Border.all(
                      color: color.withValues(alpha: .45), width: 1.6),
            ),
            child: i < filled
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : null,
          ),
        ),
    ]);
  }
}
