import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/geocode_client.dart';
import '../../data/repos.dart';
import '../../domain/locations.dart';
import '../shared/brand_kit.dart';
import '../shared/jayalo_loader.dart';
import '../shared/violet_header.dart';

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
    } catch (_) {
      // Best-effort: si falla la carga, la pantalla igual se abre vacia y el
      // usuario puede escribir su direccion desde cero.
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
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        // Pisa direccion, ciudad, sector, calle y numero — pero NUNCA la
        // referencia (nota humana que ningun geocodificador reproduce; regla
        // ya decidida en la web, profile.tsx:163-169).
        if (place.addressLine.isNotEmpty) _address.text = place.addressLine;
        if (place.country.isNotEmpty) _country = place.country;
        _street = place.street;
        _streetNumber = place.streetNumber;
        _cityFieldCtrl?.text = place.city;
        _sectorFieldCtrl?.text = place.sector;
      });
    } catch (_) {
      _snack('No pudimos captar tu ubicación — puedes escribir tu dirección igual.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
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
              : _form(context),
        ),
        // "Guardar" queda FIJO abajo, fuera del scroll: si se metiera dentro
        // del ListView, un formulario largo podria dejarlo fuera de la
        // pantalla inicial sin que el usuario (o un test) supiera que hay que
        // bajar para encontrarlo.
        if (!_loading)
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
