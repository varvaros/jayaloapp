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
import '../../domain/geo.dart';
import '../../domain/locations.dart';
import '../../domain/onboarding_errors.dart';
import '../../domain/phone.dart';
import '../shared/brand_kit.dart';
import '../shared/searchable_select.dart';
import '../verification/otp_sheet.dart';

/// Alta de consumidor (spec §6): nombre precargado de las claims de Google,
/// WhatsApp verificado por OTP BLOQUEANTE antes de crear la cuenta (§6.1),
/// ubicación GPS opcional + dirección obligatoria, términos. Una sola
/// escritura al final (upsert de profiles, atómico por naturaleza).
///
/// Verificar ANTES de `completeConsumerProfile` ya no es solo "seguro": desde
/// la migración 20260816230658 es lo que RESERVA el número. La RPC del OTP
/// sella `profiles.phone_verified_at` (la fila ya existe, la crea
/// `handle_new_user`) y la unicidad de teléfono aplica solo a números sellados.
/// Al tocar este orden, cuidado: el upsert final debe mandar el MISMO número
/// que se verificó — con otro, el guard `trg_clear_phone_seal_on_number_change`
/// retira el sello y el número deja de estar reservado.
///
/// La dirección va DESGLOSADA en país / ciudad / sector (del catálogo de
/// `domain/locations.dart`, el mismo que la web usa para la zona de cobertura
/// del proveedor) más la calle en texto libre. Antes era un único campo de
/// texto: lo que el cliente escribía no se podía cruzar con la zona declarada
/// por ningún proveedor.
class ConsumerOnboardingScreen extends StatefulWidget {
  const ConsumerOnboardingScreen({super.key});
  @override
  State<ConsumerOnboardingScreen> createState() => _ConsumerOnboardingScreenState();
}

class _ConsumerOnboardingScreenState extends State<ConsumerOnboardingScreen> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  String _prefix = '809';
  final _local = TextEditingController();
  final _address = TextEditingController();
  // País / ciudad / sector salen del catálogo compartido con la web
  // (`domain/locations.dart`), no de texto libre: así la dirección del cliente
  // es comparable con la zona de cobertura que declara un proveedor, en vez de
  // ser una cadena que cada quien escribe a su manera.
  String? _country = kCountries.length == 1 ? kCountries.first : null;
  String? _city;
  String? _sector;
  double? _lat, _lng;
  bool _locating = false;
  bool _terms = false;
  bool _busy = false;
  String? _phoneError;

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
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _local.dispose();
    _address.dispose();
    super.dispose();
  }

  String get _composedPhone => composeRdWhatsapp(_prefix, _local.text);

  Future<void> _checkPhone() async {
    if (_local.text.trim().isEmpty) return;
    final composed = _composedPhone;
    if (composed.isEmpty) {
      setState(() => _phoneError = 'Escribe un WhatsApp de 7 dígitos.');
      return;
    }
    setState(() => _phoneError = null);
    try {
      final digits = composed.replaceAll(RegExp(r'\D'), '');
      if (await isWhatsappTakenRemote(digits) && mounted) {
        setState(() => _phoneError =
            'Este WhatsApp ya está registrado en otra cuenta. Usa otro número o inicia sesión con esa cuenta.');
      }
    } catch (_) {
      // Pre-chequeo de UX: si falla, el upsert final valida igual (23505).
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
        if (mounted) {
          _snack('Sin permiso de ubicación — puedes escribir tu dirección igual.');
        }
        return;
      }
      // `timeLimit` no es opcional en la práctica: sin él, si el GPS no fija
      // (bajo techo, en un pasillo), el Future NO resuelve NUNCA y `_locating`
      // se queda en true — el botón "Usar mi ubicación" gira para siempre en la
      // PRIMERA experiencia de la app. Al expirar lanza y cae al catch de abajo,
      // que ya ofrece escribir la dirección a mano.
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      // Reverse geocoding nativo (gratis). Best-effort, y NO PISA nada que el
      // usuario ya haya elegido o escrito: solo rellena los huecos.
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isEmpty || !mounted) return;
        final m = marks.first;
        // El país solo se deduce si aún no hay uno puesto y el geocoder devuelve
        // uno que EXISTE en el catálogo.
        final country = _country ??
            kCountries.firstWhere(
              (c) => normalizeLoose(c) == normalizeLoose(m.country),
              orElse: () => '',
            );
        final ({String? city, String? sector}) hit = country.isEmpty
            ? (city: null, sector: null)
            : matchLocation(
                country: country,
                locality: m.locality,
                subLocality: m.subLocality,
              );
        // Solo calle y número: ciudad y sector tienen su propio campo, y
        // repetirlos aquí los enseñaría dos veces en la misma pantalla.
        final street = composeStreetLine(
          thoroughfare: m.thoroughfare,
          subThoroughfare: m.subThoroughfare,
          street: m.street,
        );
        setState(() {
          if (_country == null && country.isNotEmpty) _country = country;
          if (_city == null && hit.city != null) _city = hit.city;
          // El sector solo se acepta si pertenece a la ciudad que quedó puesta:
          // si el usuario ya había elegido otra, el sector del GPS no es suyo.
          if (_sector == null && hit.sector != null && _city == hit.city) {
            _sector = hit.sector;
          }
          if (_address.text.trim().isEmpty && street.isNotEmpty) {
            _address.text = street;
          }
        });
      } catch (_) {
        // Sin geocoder quedan las coordenadas; los campos se llenan a mano.
      }
    } catch (_) {
      if (mounted) {
        _snack('No pudimos captar tu ubicación — puedes escribir tu dirección igual.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // El SECTOR queda opcional a propósito: el catálogo trae unos pocos por
  // provincia, así que exigirlo dejaría fuera del registro a quien viva en uno
  // que no está en la lista. País y ciudad sí son obligatorios — son los que
  // usan los proveedores para saber si alguien les queda dentro de su zona.
  bool get _valid =>
      _first.text.trim().isNotEmpty &&
      _composedPhone.isNotEmpty &&
      _phoneError == null &&
      _country != null &&
      _city != null &&
      _address.text.trim().isNotEmpty &&
      _terms;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      // 1) OTP BLOQUEANTE: sin verificar el WhatsApp no se crea la cuenta.
      final verified = await showOtpSheet(context, phone: _composedPhone);
      if (!verified) {
        if (mounted) _snack('Confirma tu WhatsApp para crear la cuenta.');
        return;
      }
      // 2) Recién ahora se persiste el perfil (número ya verificado).
      await completeConsumerProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        whatsapp: _composedPhone,
        address: _address.text.trim(),
        country: _country,
        city: _city,
        sector: _sector,
        lat: _lat,
        lng: _lng,
        termsVersion: AppConfig.termsVersion,
      );
      await roleStore.refresh(); // → redirect a /client
    } catch (e) {
      if (mounted) {
        _snack(onboardingErrorCopy(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Igual que en el alta de proveedor: el ATRÁS del sistema vuelve al
    // selector dentro de la app, no minimiza Jayalo (que con MIUI equivale a
    // perder el formulario).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/onboarding');
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Tu cuenta'),
        leading: BackButton(onPressed: () => context.go('/onboarding')),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Así te llamas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _first,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
            maxLength: 40,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            inputFormatters: [
              LengthLimitingTextInputFormatter(40),
              FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{M} '\-]", unicode: true)),
            ],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Apellido'),
            maxLength: 40,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            inputFormatters: [
              LengthLimitingTextInputFormatter(40),
              FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{M} '\-]", unicode: true)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Tu WhatsApp', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Los proveedores te contactan por aquí cuando aceptas una oferta.'),
          const SizedBox(height: 8),
          Row(children: [
            DropdownButton<String>(
              value: _prefix,
              items: [for (final p in kRdPrefixes) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) => setState(() => _prefix = v ?? '809'),
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
                decoration: InputDecoration(
                  labelText: 'Número de WhatsApp',
                  hintText: '5551234',
                  errorText: _phoneError,
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setState(() => _phoneError = null),
                onEditingComplete: () {
                  FocusScope.of(context).nextFocus();
                  _checkPhone();
                },
                onTapOutside: (_) {
                  FocusScope.of(context).unfocus();
                  _checkPhone();
                },
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Text('Dónde estás', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_lat == null)
            OutlinedButton.icon(
              onPressed: _locating ? null : _useLocation,
              icon: _locating
                  ? const JayaloSpinner(size: 16)
                  : const Icon(Icons.my_location),
              label: const Text('Usar mi ubicación'),
            )
          else
            StatusChip(
              label: 'Ubicación captada ✓',
              icon: Icons.check_circle,
              tone: Theme.of(context).brightness == Brightness.dark
                  ? JayaloStatus.unlockedDark
                  : JayaloStatus.unlockedLight,
            ),
          const SizedBox(height: 12),
          // País solo si hay más de uno que elegir: con un único país el
          // selector no es una decisión, es un trámite. El valor se guarda igual.
          if (kCountries.length > 1) ...[
            SearchableSelectField(
              label: 'País',
              value: _country,
              options: kCountries,
              placeholder: 'Elige tu país',
              onChanged: (v) => setState(() {
                _country = v;
                // Cambiar de país invalida lo de abajo: la ciudad elegida ya no
                // pertenece al árbol nuevo.
                _city = null;
                _sector = null;
              }),
            ),
            const SizedBox(height: 10),
          ],
          SearchableSelectField(
            label: 'Ciudad / Provincia',
            value: _city,
            options: citiesOf(_country),
            placeholder: 'Elige tu ciudad',
            disabledHint: 'Elige primero un país',
            onChanged: (v) => setState(() {
              _city = v;
              _sector = null; // el sector anterior era de otra ciudad
            }),
          ),
          const SizedBox(height: 10),
          SearchableSelectField(
            label: 'Sector (opcional)',
            value: _sector,
            options: sectorsOf(_country, _city),
            placeholder: 'Elige tu sector',
            disabledHint: 'Elige primero una ciudad',
            onChanged: (v) => setState(() => _sector = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Dirección',
                hintText: 'Calle y número — para ofertas cerca de ti'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_valid && !_busy) ? _submit : null,
            child: _busy
                ? const JayaloSpinner(size: 18)
                : const Text('Crear mi cuenta'),
          ),
        ]),
      ),
      ),
    );
  }
}
