import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/core/motion.dart';

/// Verifica el PULSO QUE SE EMITE, no que el metodo exista. `HapticFeedback`
/// habla por `SystemChannels.platform`, asi que se intercepta el canal y se
/// mira el argumento: es la unica forma de que un cambio de `mediumImpact` a
/// `lightImpact` haga fallar algo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final emitidos = <String>[];

  setUp(() {
    emitidos.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        emitidos.add(call.arguments as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('JayaloHaptics', () {
    test('sent es el pulso mas liviano que se siente', () async {
      JayaloHaptics.sent();
      await Future<void>.delayed(Duration.zero);

      expect(emitidos, ['HapticFeedbackType.lightImpact']);
    });

    test('tabChange es el tic de seleccion, el mas tenue que existe', () async {
      JayaloHaptics.tabChange();
      await Future<void>.delayed(Duration.zero);

      expect(emitidos, ['HapticFeedbackType.selectionClick']);
    });

    // Se consumo algo que importa y que costo dinero o decision: oferta
    // aceptada, contacto desbloqueado, creditos acreditados. Va por encima de
    // `sent` — un envio es rutina, esto es un hito.
    test('success pega mas fuerte que un envio', () async {
      JayaloHaptics.success();
      await Future<void>.delayed(Duration.zero);

      expect(emitidos, ['HapticFeedbackType.mediumImpact']);
    });

    // Un fallo tiene que sentirse DISTINTO de un acierto sin mirar la pantalla.
    test('error es el unico pulso pesado', () async {
      JayaloHaptics.error();
      await Future<void>.delayed(Duration.zero);

      expect(emitidos, ['HapticFeedbackType.heavyImpact']);
    });

    test('los cuatro pulsos son distintos entre si', () async {
      JayaloHaptics.sent();
      JayaloHaptics.tabChange();
      JayaloHaptics.success();
      JayaloHaptics.error();
      await Future<void>.delayed(Duration.zero);

      expect(emitidos.toSet().length, 4);
    });
  });
}
