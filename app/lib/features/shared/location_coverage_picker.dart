import 'package:flutter/material.dart';

import '../../domain/locations.dart';

const kAllSectorsLabel = '🗺️ Todos los sectores';

/// Cascada pais -> provincia -> sector para declarar DONDE trabaja un
/// proveedor. Multi-seleccion en provincia y sector, paridad con la web
/// (`ProviderSignupWizard.tsx:1682`).
///
/// **Sin estado propio**: recibe los tres valores y emite los tres en cada
/// cambio. Quien lo monta guarda. Es un widget aparte por la misma razon que
/// `OfferRequirementCoverage`: el alta de proveedor es una pantalla enorme y
/// un test no puede montarla, este si.
class LocationCoveragePicker extends StatelessWidget {
  const LocationCoveragePicker({
    super.key,
    required this.country,
    required this.cities,
    required this.sectors,
    required this.onChanged,
  });

  final String country;
  final List<String> cities;
  final List<String> sectors;
  final void Function({
    required String country,
    required List<String> cities,
    required List<String> sectors,
  }) onChanged;

  /// Sectores que se pueden ofrecer: la union de los de cada provincia
  /// elegida, en orden de catalogo y sin duplicados, MAS los ya seleccionados
  /// que el catalogo no conoce.
  ///
  /// Esa segunda mitad es la que salva el caso "Parque del Este": es un sector
  /// real que el geocodificador devuelve y que `kLocations` no tiene. Si solo
  /// ofrecieramos el catalogo, el valor desapareceria de la pantalla sin que
  /// el proveedor se entere.
  List<String> get availableSectors {
    final delCatalogo = <String>[];
    for (final ciudad in cities) {
      for (final s in sectorsFor(country, ciudad)) {
        if (!delCatalogo.contains(s)) delCatalogo.add(s);
      }
    }
    final extra = sectors.where((s) => !delCatalogo.contains(s));
    return [...delCatalogo, ...extra];
  }

  bool get _todosLosSectores =>
      availableSectors.length > 1 && sectors.length == availableSectors.length;

  void _setCountry(String c) => onChanged(
      country: c, cities: const [], sectors: const []);

  void _addCity(String c) {
    final next = [...cities, c];
    onChanged(country: country, cities: next, sectors: sectors);
  }

  void _removeCity(String c) {
    final next = cities.where((x) => x != c).toList();
    // Los sectores que solo pertenecian a esa provincia se van con ella. Los
    // que estan fuera de catalogo se quedan: no son de ninguna provincia.
    final quedan = <String>{};
    for (final ciudad in next) {
      quedan.addAll(sectorsFor(country, ciudad));
    }
    final delCatalogo = <String>{};
    for (final ciudad in cities) {
      delCatalogo.addAll(sectorsFor(country, ciudad));
    }
    final nextSectors = sectors
        .where((s) => quedan.contains(s) || !delCatalogo.contains(s))
        .toList();
    onChanged(country: country, cities: next, sectors: nextSectors);
  }

  void _addSector(String s) {
    final next = s == kAllSectorsLabel ? availableSectors : [...sectors, s];
    onChanged(country: country, cities: cities, sectors: next);
  }

  void _removeSector(String s) => onChanged(
        country: country,
        cities: cities,
        sectors: sectors.where((x) => x != s).toList(),
      );

  @override
  Widget build(BuildContext context) {
    final sectoresLibres =
        availableSectors.where((s) => !sectors.contains(s)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _adder(
          context,
          hint: 'País',
          // Se dibuja aunque kCountries tenga un solo elemento: paridad con la
          // web y el catalogo puede crecer. Excluir el pais actual (mismo
          // patron que provincia y sector abajo) evita que reelegirlo borre
          // provincias y sectores sin que el usuario haya cambiado nada.
          options: kCountries.where((c) => c != country).toList(),
          onPick: _setCountry,
        ),
        if (country.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _chips([country], onRemove: null),
          ),
        const SizedBox(height: 12),
        _adder(
          context,
          hint: 'Provincia',
          options:
              citiesFor(country).where((c) => !cities.contains(c)).toList(),
          onPick: _addCity,
        ),
        if (cities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _chips(cities, onRemove: _removeCity),
          ),
        const SizedBox(height: 12),
        _adder(
          context,
          hint: 'Sector (opcional)',
          options: [
            if (sectoresLibres.isNotEmpty) kAllSectorsLabel,
            ...sectoresLibres,
          ],
          onPick: _addSector,
        ),
        if (sectors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            // Todos seleccionados: un solo chip resumen en vez de la lista
            // entera, igual que la web.
            child: _todosLosSectores
                ? _chips([kAllSectorsLabel],
                    onRemove: (_) => onChanged(
                        country: country, cities: cities, sectors: const []))
                : _chips(sectors, onRemove: _removeSector),
          ),
      ],
    );
  }

  /// Desplegable que agrega (no que selecciona): al elegir, el valor pasa a
  /// los chips de abajo y sale de la lista.
  Widget _adder(
    BuildContext context, {
    required String hint,
    required List<String> options,
    required ValueChanged<String> onPick,
  }) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: hint,
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: options.isEmpty ? null : (v) => v == null ? null : onPick(v),
    );
  }

  Widget _chips(List<String> values, {required ValueChanged<String>? onRemove}) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            Chip(
              label: Text(v),
              onDeleted: onRemove == null ? null : () => onRemove(v),
              deleteButtonTooltipMessage: 'Quitar $v',
            ),
        ],
      );
}
