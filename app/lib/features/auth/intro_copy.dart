import 'intro_role_store.dart';

/// Una lámina del intro: titular, la palabra que va en violeta, y el apoyo.
///
/// `highlight` es subcadena LITERAL de `headline`; la pantalla la parte y pinta
/// esa parte en `JayaloColors.primary`. Guardarlo así, y no con marcas dentro
/// del texto, deja el copy legible de principio a fin. Precedente en la propia
/// pantalla: «Todo empieza con una idea.» con «idea» en violeta.
class IntroSlide {
  const IntroSlide({
    required this.headline,
    required this.highlight,
    required this.sub,
  });

  final String headline;
  final String highlight;
  final String sub;
}

/// Lámina 1: común a los dos roles. Explica y bifurca en la misma pantalla,
/// para que nadie tenga que elegir su lado antes de saber qué es Jayalo.
const IntroSlide kIntroCommon = IntroSlide(
  headline: 'Jayalo conecta a quien pide con quien vende, cerca de ti.',
  highlight: 'quien pide',
  sub: 'Dime de qué lado estás y te lo cuento en dos pantallas.',
);

/// Láminas 2 y 3, ya según el lado elegido.
const Map<IntroRole, List<IntroSlide>> kIntroSlides = {
  IntroRole.consumer: [
    IntroSlide(
      headline:
          'Pide con una foto y los proveedores cerca de ti compiten por dártelo.',
      highlight: 'compiten por dártelo',
      sub: 'Te llegan varias ofertas con precio, foto y reputación. '
          'Comparas sin compromiso.',
    ),
    IntroSlide(
      headline: '¡Aceptas la oferta que más te convenga!',
      highlight: 'más te convenga',
      sub: 'Tus datos son privados: solo los proveedores que aceptes podrán ver tu contacto.',
    ),
  ],
  IntroRole.provider: [
    IntroSlide(
      headline: 'Hay clientes cerca de ti pidiendo justo lo que tú vendes.',
      highlight: 'clientes cerca de ti',
      sub: 'Ves las solicitudes abiertas de tus rubros y respondes con tu '
          'precio, una foto y en cuánto lo tienes listo.',
    ),
    IntroSlide(
      headline: 'Ofertar es gratis. Solo pagas cuando ya te aceptaron.',
      highlight: 'Ofertar es gratis.',
      sub: 'Cuando el cliente acepta tu oferta, recibes sus datos y cierras la venta.',
    ),
  ],
};
