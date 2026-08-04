import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jayalo_app/core/geocode_client.dart';

void main() {
  test('parsea la respuesta del endpoint', () async {
    final c = GeocodeClient(inner: MockClient((_) async => http.Response(
        jsonEncode({'city': 'Santo Domingo Este', 'sector': 'Parque del Este'}), 200)));
    final p = await c.lookup(lat: 18.4, lng: -69.8, accessToken: 't');
    expect(p.sector, 'Parque del Este');
  });

  test('devuelve empty y NO lanza si el endpoint falla', () async {
    final c = GeocodeClient(
        inner: MockClient((_) async => http.Response('{"error":"x"}', 502)));
    final p = await c.lookup(lat: 18.4, lng: -69.8, accessToken: 't');
    expect(p.addressLine, '');
  });

  test('devuelve empty si la red revienta', () async {
    final c = GeocodeClient(inner: MockClient((_) async => throw Exception('sin red')));
    final p = await c.lookup(lat: 18.4, lng: -69.8, accessToken: 't');
    expect(p.addressLine, '');
  });
}
