import 'package:flutter/services.dart';

import '../domain/sello_build.dart';

/// El puente al sello que Gradle horneó en el manifest. La lógica interpretable
/// vive en `domain/sello_build.dart`; aquí solo está la llamada.
///
/// Se cachea porque el valor no cambia mientras la app vive: es una propiedad
/// del binario, no del estado.
class SelloBuildCanal {
  static const _canal = MethodChannel('com.jayalo.app/sello_build');
  static SelloBuild? _cache;

  /// Nunca lanza. En iOS, en los tests o en un build viejo sin el canal, el
  /// `MissingPluginException` cae aquí y se responde «desconocido» — que es la
  /// verdad, y una pantalla de Ajustes no se rompe por un dato informativo.
  static Future<SelloBuild> leer() async {
    final cacheado = _cache;
    if (cacheado != null) return cacheado;
    try {
      final m = await _canal.invokeMethod<Map<Object?, Object?>>('leer');
      return _cache = SelloBuild.desdeMapa(m);
    } catch (_) {
      return _cache = SelloBuild.desconocido;
    }
  }
}
