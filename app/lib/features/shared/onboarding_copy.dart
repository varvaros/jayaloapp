import 'onboarding_guide.dart';

/// Copys de cada guía, en un solo lugar (DRY). El PO puede ajustarlos aquí sin
/// tocar las pantallas. Claves versionadas: subir a `.v2` reaparece la guía.
const Map<String, List<OnboardingStep>> onboardingCopy = {
  // v2 (PO 2026-07-28): el copy nuevo describe el RESULTADO (le llega a los
  // proveedores ideales), no la acción. La clave sube de v1 a v2 a propósito:
  // quien ya vio la v1 la tiene marcada en el backend y sin subir versión el
  // texto nuevo sería invisible para todos los usuarios actuales.
  'client.create_request.v2': [
    OnboardingStep(
        'Aquí creas una solicitud que le llegará a los proveedores ideales.'),
  ],
  'client.view_offers.v1': [
    OnboardingStep(
        'Aquí podrás comparar las ofertas de los proveedores y elegir la que más te convenga.'),
  ],
  'client.chat_reveal.v1': [
    OnboardingStep('Aquí coordinas los detalles con el proveedor antes de cerrar el trato.'),
  ],
  'provider.requests_list.v1': [
    OnboardingStep(
        'Aquí encontrarás personas que están buscando servicios como los que tú ofreces.'),
  ],
  'provider.make_offer.v1': [
    OnboardingStep(
        'Puedes enviar tu oferta gratis. Solo desbloqueas el contacto si el cliente acepta tu propuesta.'),
  ],
  'provider.chat_reveal.v1': [
    OnboardingStep(
        'Aquí coordinas con el cliente. El contacto de WhatsApp se comparte cuando ambos avanzan.'),
  ],
  'wallet.credits.v1': [
    OnboardingStep(
        'Ofertar siempre es gratis. Los créditos solo se usan para desbloquear el contacto de un cliente que aceptó tu oferta.'),
  ],
  'client.plus.v1': [
    OnboardingStep('Aquí creas una nueva solicitud.'),
  ],
  'client.my_requests.v1': [
    OnboardingStep('Aquí se verán tus solicitudes y en qué van.'),
  ],
  'client.others_requests.v1': [
    OnboardingStep('Y aquí ves qué están pidiendo otros usuarios.'),
  ],
  'client.request_kind.v1': [
    OnboardingStep('Aquí eliges si buscas un producto o un servicio.'),
  ],
  'client.request_photo.v1': [
    OnboardingStep('Aquí tomas una foto o subes una imagen de lo que buscas.'),
  ],
  'client.request_wholesale.v1': [
    OnboardingStep('¿Necesitas grandes cantidades? Actívalo aquí.'),
  ],
  'client.catalog.v1': [
    OnboardingStep('Aquí ves productos que los proveedores ofrecen en sus tiendas.'),
  ],
  'provider.offer_menu.v1': [
    OnboardingStep(
        'Mientras redactas tu oferta, este botón abre un menú para añadir fotos: cámara, galería, tu tienda o tus trabajos.'),
  ],
  'chat.quick_replies.v1': [
    OnboardingStep('Aquí eliges mensajes predefinidos para responder rápido.'),
  ],
  'chat.report.v1': [
    OnboardingStep('¿Sientes algo deshonesto? Denúncialo desde aquí.'),
  ],
};
