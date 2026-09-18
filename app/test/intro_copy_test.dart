import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/features/auth/intro_copy.dart';
import 'package:jayalo_app/features/auth/intro_role_store.dart';

void main() {
  group('introSteps', () {
    test('sin rol ni saltar: solo la pregunta', () {
      expect(introSteps(role: null, skipped: false, credits: 5), [
        IntroStep.ask,
      ]);
    });
    test('saltó sin elegir: pregunta y cierre neutro', () {
      expect(introSteps(role: null, skipped: true, credits: 5), [
        IntroStep.ask,
        IntroStep.neutralClose,
      ]);
    });
    test('cliente: tres láminas, la última es la gratis', () {
      expect(introSteps(role: IntroRole.consumer, skipped: false, credits: 5), [
        IntroStep.ask,
        IntroStep.react,
        IntroStep.consumerFree,
      ]);
    });
    test('proveedor con bono: cuatro láminas y la moneda al final', () {
      expect(introSteps(role: IntroRole.provider, skipped: false, credits: 5), [
        IntroStep.ask,
        IntroStep.react,
        IntroStep.providerOffers,
        IntroStep.providerCoin,
      ]);
    });
    test('proveedor SIN bono: la moneda no existe', () {
      expect(introSteps(role: IntroRole.provider, skipped: false, credits: 0), [
        IntroStep.ask,
        IntroStep.react,
        IntroStep.providerOffers,
      ]);
    });
    test(
      'los accesos van SIEMPRE en la última lámina cuando hay más de una',
      () {
        final one = introSteps(role: null, skipped: false, credits: 0);
        expect(introStepIsAccess(one, 0), isFalse);
        final prov = introSteps(
          role: IntroRole.provider,
          skipped: false,
          credits: 0,
        );
        expect(introStepIsAccess(prov, 2), isTrue);
        expect(introStepIsAccess(prov, 1), isFalse);
      },
    );
  });

  group('copy', () {
    test('la pregunta lleva la marca con tilde y bifurca', () {
      final s = introSlideFor(IntroStep.ask);
      expect(s.headline, 'En Jáyalo conectamos clientes con proveedores.');
      expect(s.sub, '¿Tú qué eres?');
      expect(s.shout, isNull);
    });
    test('la reacción grita según el lado', () {
      expect(
        introSlideFor(IntroStep.react, role: IntroRole.consumer).shout,
        '¡Genial!',
      );
      expect(
        introSlideFor(IntroStep.react, role: IntroRole.provider).shout,
        '¡Bien!',
      );
      expect(
        introSlideFor(IntroStep.react, role: IntroRole.consumer).sub,
        'Aquí haces una solicitud y esperas que proveedores te hagan ofertas.',
      );
      expect(
        introSlideFor(IntroStep.react, role: IntroRole.provider).sub,
        'Aquí encontrarás clientes que buscan exactamente lo que vendes.',
      );
    });
    test('solo la reacción grita', () {
      for (final step in IntroStep.values.where((s) => s != IntroStep.react)) {
        expect(
          introSlideFor(step, role: IntroRole.provider, credits: 5).shout,
          isNull,
          reason: '$step',
        );
      }
    });
    test('la moneda lleva el número en el marcador y como contador', () {
      final s = introSlideFor(IntroStep.providerCoin, credits: 5);
      expect(
        s.headline,
        'Tienes {n} créditos de regalo para desbloquear clientes.',
      );
      expect(s.counter, 5);
    });
    test('el realce, cuando existe, es subcadena del titular', () {
      for (final step in IntroStep.values) {
        final s = introSlideFor(step, role: IntroRole.consumer, credits: 5);
        if (s.highlight != null) expect(s.headline, contains(s.highlight));
      }
    });
    test('ningún titular va vacío y solo la moneda va sin apoyo', () {
      for (final step in IntroStep.values) {
        final s = introSlideFor(step, role: IntroRole.provider, credits: 5);
        expect(
          s.headline.isNotEmpty || s.shout != null,
          isTrue,
          reason: '$step',
        );
        if (step != IntroStep.providerCoin) {
          expect(s.sub, isNotEmpty, reason: '$step');
        }
      }
    });
    test('los recuadros dicen quién eres', () {
      expect(kIntroConsumerCard.title, 'Soy un cliente');
      expect(kIntroProviderCard.title, 'Soy un proveedor');
    });
  });
}
