import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/data/repos.dart';

/// Lectura del flag `archived` que la RPC `get_my_conversations_list` resuelve
/// para quien llama. Tolerante a su ausencia: una caché escrita antes de la
/// migración no puede hacer desaparecer conversaciones de la bandeja.
void main() {
  test('archived true/false se lee tal cual', () {
    expect(conversationArchived({'id': 'c1', 'archived': true}), isTrue);
    expect(conversationArchived({'id': 'c1', 'archived': false}), isFalse);
  });

  test('sin la clave, la conversación NO se considera archivada', () {
    expect(conversationArchived({'id': 'c1'}), isFalse);
    expect(conversationArchived({'id': 'c1', 'archived': null}), isFalse);
  });
}
