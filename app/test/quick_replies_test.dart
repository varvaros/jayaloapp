import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/chat.dart';

/// Contrato de las respuestas rápidas editables (pedido PO): serialización
/// tolerante, caída a defaults, y que el texto de confirmación personalizado
/// viaje en el payload para que lo honre quien contesta.
void main() {
  group('QuickItem toJson/fromJson', () {
    test('round-trip con opciones y replies', () {
      const item = QuickItem('¿Es nuevo o usado?', ['Nuevo', 'Usado'],
          {'Nuevo': 'Es nuevo', 'Usado': 'Es usado'});
      final back = QuickItem.fromJson(item.toJson())!;
      expect(back.question, item.question);
      expect(back.options, item.options);
      expect(back.replies, item.replies);
    });

    test('mensaje simple (sin opciones) omite claves vacías', () {
      const item = QuickItem('¡Gracias por su compra!');
      expect(item.toJson(), {'question': '¡Gracias por su compra!'});
      final back = QuickItem.fromJson(item.toJson())!;
      expect(back.options, isEmpty);
      expect(back.replies, isEmpty);
    });

    test('descarta entradas sin pregunta válida', () {
      expect(QuickItem.fromJson({'options': ['x']}), isNull);
      expect(QuickItem.fromJson({'question': '   '}), isNull);
      expect(QuickItem.fromJson('no es mapa'), isNull);
    });
  });

  group('quickRepliesFromStored', () {
    test('null → defaults del rol', () {
      expect(quickRepliesFromStored(null, provider: false), quickReplies);
      expect(quickRepliesFromStored(null, provider: true), providerReplies);
    });

    test('usa la lista guardada del rol', () {
      final stored = {
        'customer': [
          {'question': 'Mi pregunta'}
        ]
      };
      final list = quickRepliesFromStored(stored, provider: false);
      expect(list.length, 1);
      expect(list.first.question, 'Mi pregunta');
      // El otro rol, sin clave, cae a defaults.
      expect(quickRepliesFromStored(stored, provider: true), providerReplies);
    });

    test('lista vacía o toda inválida → defaults (nunca deja sin nada)', () {
      expect(quickRepliesFromStored({'customer': []}, provider: false),
          quickReplies);
      expect(
          quickRepliesFromStored({
            'customer': [
              {'sin': 'pregunta'}
            ]
          }, provider: false),
          quickReplies);
    });
  });

  group('payload de confirmación personalizada', () {
    test('quickSendBody → parseQuick conserva replies', () {
      const item = QuickItem('¿Color?', ['Rojo', 'Azul'],
          {'Rojo': 'Lo quiero rojo', 'Azul': 'Lo quiero azul'});
      final p = parseQuick(quickSendBody(item))!;
      expect(p.question, '¿Color?');
      expect(p.options, ['Rojo', 'Azul']);
      expect(p.replies['Rojo'], 'Lo quiero rojo');
    });

    test('answerQuickBody conserva replies para re-render', () {
      const item = QuickItem('¿Color?', ['Rojo'], {'Rojo': 'Lo quiero rojo'});
      final p = parseQuick(quickSendBody(item))!;
      final answered = parseQuick(answerQuickBody(p, 'Rojo', 'user-1'))!;
      expect(answered.selected, 'Rojo');
      expect(answered.answeredBy, 'user-1');
      expect(answered.replies['Rojo'], 'Lo quiero rojo');
    });

    test('payload viejo sin replies → replies vacío (no revienta)', () {
      final p = parseQuick('{"question":"¿X?","options":["Sí"]}')!;
      expect(p.replies, isEmpty);
    });
  });
}
