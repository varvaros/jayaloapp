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
  // v2 (2026-08-22): la v1 se marcaba como "vista" sin que nadie la viera —
  // anclaba el botón de enviar, que nace FUERA de la pantalla al final del
  // formulario, y el usuario solo veía el velo oscuro. Arreglado el anclaje
  // (ver `onboarding_guide.dart`), la clave sube para que la guía vuelva a
  // aparecerle a quien la "gastó" en negro.
  'provider.make_offer.v2': [
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
  // Sustituye a `chat.report.v1` (PO 2026-08-22: "botones que no se explican
  // bien"). Aquel copy nombraba SOLO denunciar, y ese ⋮ guarda hasta cinco
  // acciones — entre ellas cerrar el trato. Va por rol porque el menú también
  // cambia por rol: el cliente no ve "completado" ni el perfil de la otra
  // parte.
  'chat.menu.provider.v1': [
    OnboardingStep(
        'Aquí cierras el trato —completado o no concretado—, ves el perfil del cliente y denuncias si algo no cuadra.'),
  ],
  'chat.menu.client.v1': [
    OnboardingStep(
        'Aquí marcas si el trato no se concretó, y denuncias si algo no cuadra.'),
  ],
  // El `+` del chat: hasta ahora no se explicaba, y ahí vive lo que menos se
  // adivina (mandar tu ubicación, tus datos, o bajar el precio de tu oferta).
  'chat.attach.client.v1': [
    OnboardingStep(
        'Aquí adjuntas: una foto, tu ubicación actual o tus datos de contacto.'),
  ],
  'chat.attach.provider.v1': [
    OnboardingStep(
        'Aquí adjuntas: fotos, artículos de tu tienda, la dirección de tu local o una mejora de precio.'),
  ],
  // Formulario de la oferta: los dos controles que el PO señaló como mudos.
  'provider.offer_price_mode.v1': [
    OnboardingStep(
        'Elige cómo cobras: precio fijo, un rango, por hora, o "a evaluar" si necesitas ver el trabajo antes de poner precio.'),
  ],
  'provider.offer_reuse_photos.v1': [
    OnboardingStep(
        'Reusa fotos que ya subiste: las de tu tienda o las de trabajos anteriores. No tienes que volver a fotografiar nada.'),
  ],
  // El avatar del encabezado: no se parece a un menú, y detrás están los
  // ajustes (y, para el proveedor, sus créditos).
  'profile.menu.v1': [
    OnboardingStep(
        'Toca tu foto para abrir tu menú: ahí están tus ajustes y el resto de tu cuenta.'),
  ],
};
