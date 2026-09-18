import 'intro_role_store.dart';

/// Una lámina del intro.
///
/// [shout] es el grito de la reacción («¡Genial!»); solo esa lámina lo tiene.
/// [highlight] es subcadena LITERAL de [headline] y se pinta en violeta.
/// [counter] es el número que cuenta de 0 a n donde [headline] lleva `{n}`.
class IntroSlide {
  const IntroSlide({
    this.shout,
    required this.headline,
    this.highlight,
    required this.sub,
    this.counter,
  });

  final String? shout;
  final String headline;
  final String? highlight;
  final String sub;
  final int? counter;
}

/// Un recuadro de la lámina común.
class IntroRoleCard {
  const IntroRoleCard(this.title, this.sub);
  final String title;
  final String sub;
}

/// Las láminas posibles. La secuencia real la da [introSteps].
enum IntroStep {
  ask,
  react,
  consumerFree,
  providerOffers,
  providerCoin,
  neutralClose,
}

/// Qué láminas ve este usuario, en orden. Pura: la pantalla solo la lee.
///
/// Sin rol el carrusel es de UNA lámina (no se puede deslizar a una lámina
/// que aún no sabe de qué lado está el usuario); al «Saltar» sin elegir se
/// abre un cierre neutro. Con rol, el cliente ve 3 y el proveedor 4 — o 3 si
/// el bono de bienvenida vale 0: el gancho solo se promete si se paga.
List<IntroStep> introSteps({
  required IntroRole? role,
  required bool skipped,
  required int credits,
}) {
  if (role == null) {
    return skipped
        ? const [IntroStep.ask, IntroStep.neutralClose]
        : const [IntroStep.ask];
  }
  return switch (role) {
    IntroRole.consumer => const [
      IntroStep.ask,
      IntroStep.react,
      IntroStep.consumerFree,
    ],
    IntroRole.provider => [
      IntroStep.ask,
      IntroStep.react,
      IntroStep.providerOffers,
      if (credits > 0) IntroStep.providerCoin,
    ],
  };
}

/// ¿La lámina `i` es la de los accesos (el FINAL del carrusel)?
/// Con una sola lámina no hay final: esa única lámina es la de la pregunta.
bool introStepIsAccess(List<IntroStep> steps, int i) =>
    steps.length > 1 && i == steps.length - 1;

const kIntroConsumerCard = IntroRoleCard(
  'Soy un cliente',
  'Busco productos o servicios',
);
const kIntroProviderCard = IntroRoleCard(
  'Soy un proveedor',
  'Vendo productos o servicios',
);

const _ask = IntroSlide(
  headline: 'En Jáyalo conectamos clientes con proveedores.',
  sub: '¿Tú qué eres?',
);

const _reactConsumer = IntroSlide(
  shout: '¡Genial!',
  headline: '',
  sub: 'Aquí haces una solicitud y esperas que proveedores te hagan ofertas.',
);

const _reactProvider = IntroSlide(
  shout: '¡Bien!',
  headline: '',
  sub: 'Aquí encontrarás clientes que buscan exactamente lo que vendes.',
);

const _consumerFree = IntroSlide(
  headline: 'Para ti, todas las funciones son gratis.',
  sub: 'Navega con libertad.',
);

// El apoyo es propuesta (no guion del PO): se quita sin tocar nada más.
const _providerOffers = IntroSlide(
  headline: 'Hacer ofertas es gratis.',
  sub: 'Responde a las solicitudes de tu zona sin gastar ni un crédito.',
);

// El apoyo es propuesta (no guion del PO): se quita sin tocar nada más.
const _neutralClose = IntroSlide(
  headline: 'En Jáyalo conectamos clientes con proveedores.',
  sub: 'Entra y elige tu lado cuando quieras.',
);

/// El copy de una lámina. [role] solo importa en la reacción; [credits] solo
/// en la moneda.
IntroSlide introSlideFor(IntroStep step, {IntroRole? role, int credits = 0}) =>
    switch (step) {
      IntroStep.ask => _ask,
      IntroStep.react =>
        role == IntroRole.provider ? _reactProvider : _reactConsumer,
      IntroStep.consumerFree => _consumerFree,
      IntroStep.providerOffers => _providerOffers,
      IntroStep.providerCoin => IntroSlide(
        headline: 'Tienes {n} créditos de regalo para desbloquear clientes.',
        highlight: '{n}',
        sub: '',
        counter: credits,
      ),
      IntroStep.neutralClose => _neutralClose,
    };
