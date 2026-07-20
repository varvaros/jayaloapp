import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:jayalo_app/core/editor_link_client.dart';

void main() {
  test('manda Bearer + Origin y devuelve la url', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response(
          jsonEncode({'url': 'https://jayalo.com/verify?x=1'}), 200);
    });
    final client = EditorLinkClient(inner: mock);
    final url =
        await client.fetchEditorUrl(businessId: 'biz-1', accessToken: 'tok');
    expect(url, 'https://jayalo.com/verify?x=1');
    expect(captured.headers['Authorization'], 'Bearer tok');
    expect(captured.headers['Origin'], 'https://jayalo.com');
    expect(jsonDecode(captured.body)['businessId'], 'biz-1');
  });

  test('lanza EditorLinkException en no-200', () async {
    final mock = MockClient(
        (req) async => http.Response(jsonEncode({'error': 'Forbidden'}), 403));
    final client = EditorLinkClient(inner: mock);
    expect(
      () => client.fetchEditorUrl(businessId: 'biz-1', accessToken: 'tok'),
      throwsA(isA<EditorLinkException>()),
    );
  });
}
