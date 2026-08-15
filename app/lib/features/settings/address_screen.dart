import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/error_reporter.dart';
import '../../core/geocode_client.dart';
import '../../data/repos.dart';
import '../../domain/geo.dart' show GeocodedPlace;
import '../../domain/locations.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shared/violet_header.dart';

/// Resultado de aplicar un [GeocodedPlace] sobre los valores actuales de los
/// campos que "Detectar mi ubicación" puede pisar. Funcion pura (sin Flutter
/// ni Supabase) para que la ronda de arreglo 1 (hallazgo 1) sea testeable sin
/// GPS ni widget test: un simple test de unidad basta.
class AppliedGeocode {
  const AppliedGeocode({
    required this.address,
    required this.country,
    required this.street,
    required this.streetNumber,
    required this.city,
    required this.sector,
  });
  final String address;
  final String country;
  final String street;
  final String streetNumber;
  final String city;
  final String sector;
}

/// Aplica [place] sobre los valores actuales de direccion/pais/calle/numero/
/// ciudad/sector, campo por campo. CADA campo se reemplaza SOLO si el
/// geocodificador devolvio algo no vacio: un resultado PARCIAL (encuentra la
/// via pero no determina el sector, por ejemplo) NO debe borrar lo que el
/// usuario ya tenia correcto — justo la pantalla cuyo proposito es corregir
/// la direccion no puede ser la que te la rompe. Paridad con `profile.tsx`
/// (web), que hace `if (place.city) setCity(...)` campo por campo.
///
/// La referencia NUNCA se toca aqui — ese campo ni siquiera es parametro de
/// esta funcion; ver el comentario en `_detectLocation`.
AppliedGeocode applyGeocodedPlace({
  required GeocodedPlace place,
  required String currentAddress,
  required String currentCountry,
  required String currentStreet,
  required String currentStreetNumber,
  required String currentCity,
  required String currentSector,
}) {
  return AppliedGeocode(
    address:
        place.addressLine.isNotEmpty ? place.addressLine : currentAddress,
    country: place.country.isNotEmpty ? place.country : currentCountry,
    street: place.street.isNotEmpty ? place.street : currentStreet,
    streetNumber: place.streetNumber.isNotEmpty
        ? place.streetNumber
        : currentStreetNumber,
    city: place.city.isNotEmpty ? place.city : currentCity,
    sector: place.sector.isNotEmpty ? place.sector : currentSector,
  );
}

/// Pantalla para corregir la direccion despues del alta (bug PO 2026-08-04):
/// hasta ahora la direccion solo se podia fijar UNA vez, en el onboarding. Si
/// salia mal ese dia, no habia ninguna forma de arreglarla dentro de la app.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key, this.load, this.save});

  /// Costura de test (patron de `MyRequestsScreen.myFetch`): sustituye la
  /// lectura de Supabase entera, asi el test pasa filas ya formadas.
  final Future<Map<String, dynamic>?> Function()? load;

  /// Recibe el mismo mapa que se manda a `updateMyAddress`.
  final Future<void> Function(Map<String, dynamic>)? save;

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final _address = TextEditingController();
  final _reference = TextEditingController();

  // Ciudad y sector viven en un Autocomplete que no expone su propio
  // controller como parametro: se captura el que Flutter crea internamente
  // via `fieldViewBuilder` para poder pisarlo desde "Detectar mi ubicacion".
  TextEditingController? _cityFieldCtrl;
  TextEditingController? _sectorFieldCtrl;

  // Precarga de ciudad/sector para el PRIMER build del Autocomplete (su
  // `initialValue` solo se lee una vez). Como el formulario solo se pinta
  // tras terminar `_bootstrap`, estos valores ya estan listos a tiempo.
  String _cityInitial = '';
  String _sectorInitial = '';

  // Calle y numero no tienen campo propio en esta pantalla (brief): solo se
  // llenan al detectar ubicacion y viajan intactos al guardar.
  String _street = '';
  String _streetNumber = '';
  double? _lat, _lng;

  // Pais para filtrar el catalogo de `locations.dart`. Republica Dominicana
  // es el unico pais del catalogo hoy; si el geocodificador devuelve otro,
  // se respeta (el Autocomplete acepta texto libre igual).
  String _country = 'República Dominicana';

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;

  // Si la lectura del perfil falla, el formulario queda VACIO — indistinguible
  // de un perfil sin direccion. Guardar sobre ese formulario mandaba
  // `updateMyAddress` con todo en blanco y `city`/`sector`/`street`/
  // `street_number`/`address_reference` se escribian NULL encima de la
  // direccion buena. Con esto el guardado se bloquea hasta que la carga
  // funcione: se pierde un intento de guardar, no la direccion del usuario.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _address.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _defaultLoad() async {
    final uid = supa.auth.currentUser!.id;
    return await supa
        .from('profiles')
        .select(
            'address,city,sector,street,street_number,address_reference,lat,lng')
        .eq('user_id', uid)
        .maybeSingle();
  }

  Future<void> _defaultSave(Map<String, dynamic> m) => updateMyAddress(
        address: (m['address'] as String?) ?? '',
        city: (m['city'] as String?) ?? '',
        sector: (m['sector'] as String?) ?? '',
        street: (m['street'] as String?) ?? '',
        streetNumber: (m['street_number'] as String?) ?? '',
        reference: (m['address_reference'] as String?) ?? '',
        lat: m['lat'] as double?,
        lng: m['lng'] as double?,
      );

  Future<void> _bootstrap() async {
    if (mounted) setState(() => _loading = true);
    _loadFailed = false;
    try {
      final row = await (widget.load ?? _defaultLoad)();
      if (row != null) {
        _address.text = (row['address'] as String?) ?? '';
        _reference.text = (row['address_reference'] as String?) ?? '';
        _cityInitial = (row['city'] as String?) ?? '';
        _sectorInitial = (row['sector'] as String?) ?? '';
        _street = (row['street'] as String?) ?? '';
        _streetNumber = (row['street_number'] as String?) ?? '';
        _lat = (row['lat'] as num?)?.toDouble();
        _lng = (row['lng'] as num?)?.toDouble();
      }
    } catch (e, s) {
      // NO es best-effort: una carga fallida deja el formulario vacio, y
      // guardar ese vacio borra la direccion que si estaba en la BD. Se marca
      // para bloquear el guardado y se reporta (antes se tragaba entero).
      _loadFailed = true;
      unawaited(reportError(e, s));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Sin permiso de ubicación — puedes escribir tu dirección igual.');
        return;
      }
      // `high` (no `medium`) y `timeLimit`: mismo motivo que en el onboarding
      // (consumer_onboarding_screen.dart) — con menor precision el
      // geocodificador puede enganchar la via de al lado, y sin limite el
      // Future puede no resolver nunca bajo techo.
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15)));
      if (!mounted) return;
      final token = supa.auth.currentSession?.accessToken;
      if (token == null) return;
      final place = await GeocodeClient()
          .lookup(lat: pos.latitude, lng: pos.longitude, accessToken: token);
      if (!mounted) return;
      // Pisa direccion, pais, calle, numero, ciudad y sector — CADA UNO solo
      // si el geocodificador trajo algo (ver `applyGeocodedPlace`) — pero
      // NUNCA la referencia (nota humana que ningun geocodificador reproduce;
      // regla ya decidida en la web, profile.tsx:163-169).
      final applied = applyGeocodedPlace(
        place: place,
        currentAddress: _address.text,
        currentCountry: _country,
        currentStreet: _street,
        currentStreetNumber: _streetNumber,
        currentCity: _cityFieldCtrl?.text ?? _cityInitial,
        currentSector: _sectorFieldCtrl?.text ?? _sectorInitial,
      );
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address.text = applied.address;
        _country = applied.country;
        _street = applied.street;
        _streetNumber = applied.streetNumber;
        _cityFieldCtrl?.text = applied.city;
        _sectorFieldCtrl?.text = applied.sector;
      });
    } catch (_) {
      _snack('No pudimos captar tu ubicación — puedes escribir tu dirección igual.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_loadFailed) {
      _snack('No pudimos leer tu dirección actual. Reintenta la carga antes de guardar.');
      return;
    }
    setState(() => _saving = true);
    try {
      final map = <String, dynamic>{
        'address': _address.text.trim(),
        'city': (_cityFieldCtrl?.text ?? _cityInitial).trim(),
        'sector': (_sectorFieldCtrl?.text ?? _sectorInitial).trim(),
        'street': _street,
        'street_number': _streetNumber,
        'address_reference': _reference.text.trim(),
        'lat': _lat,
        'lng': _lng,
      };
      await (widget.save ?? _defaultSave)(map);
      if (!mounted) return;
      _snack('Dirección guardada.');
    } catch (_) {
      if (mounted) _snack('No se pudo guardar tu dirección. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        VioletHeader(
          leading: HeaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Atrás',
            onTap: () => context.pop(),
          ),
          title: 'Mi dirección',
          titleAlign: HeaderTitleAlign.center,
        ),
        Expanded(
          child: _loading
              ? const Center(child: JayaloSpinner(size: 28))
              : _loadFailed
                  ? _loadError(context)
                  : _form(context),
        ),
        // "Guardar" queda FIJO abajo, fuera del scroll: si se metiera dentro
        // del ListView, un formulario largo podria dejarlo fuera de la
        // pantalla inicial sin que el usuario (o un test) supiera que hay que
        // bajar para encontrarlo.
        if (!_loading && !_loadFailed)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const JayaloSpinner(size: 18)
                    : const Text('Guardar'),
              ),
            ),
          ),
      ]),
    );
  }

  // Pantalla de fallo de carga. Se muestra EN LUGAR del formulario a proposito:
  // dejar escribir en un formulario que no se puede guardar sin borrar datos es
  // peor que no mostrarlo. Sin boton "Guardar" (ver el `if` del build).
  Widget _loadError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            const Text(
              'No pudimos cargar tu dirección',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'No la editamos a ciegas para no borrar la que ya tienes guardada. '
              'Revisa tu conexión y vuelve a intentarlo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // Espacio compacto A PROPOSITO: en `flutter test` el texto mide bastante
  // mas alto que en un device real (sin fuentes reales cargadas), asi que un
  // formulario "normal" deja el ultimo campo fuera del viewport del test —
  // menos texto de relleno (labels dentro del propio InputDecoration en vez
  // de un Text aparte encima de cada campo) y menos separacion vertical.
  Widget _form(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      children: [
        OutlinedButton.icon(
          onPressed: _locating ? null : _detectLocation,
          icon: _locating
              ? const JayaloSpinner(size: 16)
              : const Icon(Icons.my_location),
          label: const Text('Detectar mi ubicación'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('campo-direccion'),
          controller: _address,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Dirección',
            hintText: 'Calle, sector, ciudad',
          ),
        ),
        const SizedBox(height: 12),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _cityInitial),
          optionsBuilder: (value) {
            final opts = citiesFor(_country);
            if (value.text.trim().isEmpty) return opts;
            final q = value.text.trim().toLowerCase();
            return opts.where((c) => c.toLowerCase().contains(q));
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            _cityFieldCtrl = controller;
            return TextFormField(
              key: const Key('campo-ciudad'),
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ciudad'),
              onEditingComplete: onSubmitted,
            );
          },
        ),
        const SizedBox(height: 12),
        // Acepta texto libre a proposito: el catalogo de `locations.dart` no
        // tiene TODOS los sectores reales (ej. "Parque del Este") — un
        // dropdown de lista cerrada rompia justo ese caso.
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _sectorInitial),
          optionsBuilder: (value) {
            final city = _cityFieldCtrl?.text ?? _cityInitial;
            final opts = sectorsFor(_country, city);
            if (value.text.trim().isEmpty) return opts;
            final q = value.text.trim().toLowerCase();
            return opts.where((s) => s.toLowerCase().contains(q));
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            _sectorFieldCtrl = controller;
            return TextFormField(
              key: const Key('campo-sector'),
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Sector'),
              onEditingComplete: onSubmitted,
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('campo-referencia'),
          controller: _reference,
          // Una sola linea A PROPOSITO (revision de la tarea 8): el chat
          // detecta el link del mapa por prefijo en la ULTIMA linea del
          // cuerpo del mensaje. Si la referencia fuera multilinea y alguna
          // linea empezara con "https://www.google.com/maps/", el link real
          // quedaria como texto crudo y el falso se pintaria como boton.
          maxLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Referencia',
            hintText: 'Ej. casa azul al lado del colmado',
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
