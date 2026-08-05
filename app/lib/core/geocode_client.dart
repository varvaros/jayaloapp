import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/geo.dart';
import 'config.dart';

/// Geocodificacion inversa contra la web (bug PO 2026-08-04). El geocoder
/// nativo de Android no sirve en RD: devuelve la via grande mas cercana.
///
/// NUNCA lanza: rellenar la direccion es una ayuda, no un requisito. Si falla,
/// devuelve `empty` y el usuario escribe la suya — que es justo lo que hacia el
/// `catch (_)` del onboarding viejo.
class GeocodeClient {
  GeocodeClient({http.Client? inner}) : _http = inner ?? http.Client();
  final http.Client _http;

  Future<GeocodedPlace> lookup({
    required double lat,
    required double lng,
    required String accessToken,
  }) async {
    try {
      final res = await _http
          .post(
            Uri.parse(AppConfig.reverseGeocodeEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Origin': AppConfig.siteUrl,
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({'lat': lat, 'lng': lng}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return GeocodedPlace.empty;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return GeocodedPlace.fromJson(j);
    } catch (_) {
      return GeocodedPlace.empty;
    }
  }
}
