/// El mensaje con el que el ADMIN le ofrece una solicitud a un proveedor que
/// todavia no esta en Jayalo, desde la pantalla "Reclutar" de la app.
///
/// 🔴 ESPEJO DE `src/lib/requestShareMessage.ts` (repo web). Si uno cambia,
/// cambian los dos. La web ancla la privacidad con dos comprobaciones de TIPOS
/// (`satisfies` + `AssertCovers`) que Dart no puede replicar; aqui la sujeta el
/// test de mutacion `ANCLA: una fila con datos del perfil NO los filtra`.
///
/// PRIVACIDAD (regla dura): este texto sale de la plataforma por WhatsApp, a
/// alguien SIN SESION. Solo puede llevar campos que `/requests/<id>` ya muestra
/// sin sesion. La lista blanca NO es el `GRANT SELECT` de la base, que es mas
/// permisivo y protege la lista equivocada. Nada de lat/lng, nada de contacto, y
/// nada de `city`/`sector`: esos dos no salen en la ruta publica y se copian del
/// PERFIL del cliente junto a su GPS — es el barrio de su casa. `zone` SI, que
/// es columna de la solicitud.
library;

import 'money.dart';
import 'share_links.dart';

/// Lo unico que el MENSAJE puede llevar. Espejo de `SHAREABLE_FIELDS`.
/// (La PANTALLA pide ademas `created_at`; ver `kAdminListCols` en repos.dart.)
const kShareableRequestCols = <String>[
  'id',
  'title',
  'zone',
  'description',
  'budget_min',
  'budget_max',
  'urgency',
  'kind',
];

/// La solicitud tal y como puede salir de la plataforma. `fromRow` lee SOLO
/// claves de `kShareableRequestCols`: aunque la fila traiga mas columnas (y las
/// trae: `created_at`, y el admin podria leer todas), aqui no entran.
class ShareableRequest {
  const ShareableRequest({
    required this.id,
    required this.title,
    required this.zone,
    required this.description,
    required this.budgetMin,
    required this.budgetMax,
    required this.urgency,
    required this.kind,
  });

  final String id;
  final String? title;
  final String? zone;
  final String? description;
  final num? budgetMin;
  final num? budgetMax;
  final String? urgency;
  final String? kind;

  factory ShareableRequest.fromRow(Map<String, dynamic> r) => ShareableRequest(
        id: r['id'] as String,
        title: r['title'] as String?,
        zone: r['zone'] as String?,
        description: r['description'] as String?,
        budgetMin: r['budget_min'] as num?,
        budgetMax: r['budget_max'] as num?,
        urgency: r['urgency'] as String?,
        kind: r['kind'] as String?,
      );
}

/// La descripcion de una solicitud manual es el texto COMPLETO del cliente y
/// puede ser larga: no se manda entera.
const _maxDescripcionCodePoints = 220;

/// 🔴 Por CODE POINTS (`runes`), no por `length`: en Dart `length` cuenta
/// unidades UTF-16 y recortar ahi parte un emoji en dos mitades invalidas. Es
/// el equivalente exacto del `Array.from(...)` de la web.
String? _descripcionRecortada(String? description) {
  final t = description?.trim();
  if (t == null || t.isEmpty) return null;
  final puntos = t.runes.toList();
  if (puntos.length <= _maxDescripcionCodePoints) return t;
  return '${String.fromCharCodes(puntos.take(_maxDescripcionCodePoints))}…';
}

/// 🔴 NO se reusa `requestBudgetLabel` de money.dart: usa " - " y aqui la web
/// manda "–" (guion largo) y ademas el prefijo "Presupuesto: ". Reusarla
/// cambiaria el mensaje en silencio. `fmtRD` si se reusa: su salida
/// ("RD$1,000") es identica a la de `toLocaleString('es-DO')` de la web.
String? _presupuesto(num? min, num? max) {
  if (min != null && max != null) return 'Presupuesto: ${fmtRD(min)} – ${fmtRD(max)}';
  if (min != null) return 'Presupuesto: desde ${fmtRD(min)}';
  if (max != null) return 'Presupuesto: hasta ${fmtRD(max)}';
  return null;
}

/// `zone` es `text NOT NULL DEFAULT ''` y el creador web no la escribe, asi que
/// casi siempre resuelve a null y el mensaje queda sin ubicacion — a proposito,
/// para que se lea natural.
String? _lugar(String? zone) {
  final z = zone?.trim();
  return (z == null || z.isEmpty) ? null : z;
}

String buildRequestShareText(ShareableRequest r) {
  final donde = _lugar(r.zone);
  final titulo = (r.title?.trim().isNotEmpty ?? false) ? r.title!.trim() : 'un trabajo';

  final cabecera = donde != null
      ? 'Hola, tengo un cliente en $donde que busca: $titulo'
      : 'Hola, tengo un cliente que busca: $titulo';

  final bloques = <String>[cabecera];
  final desc = _descripcionRecortada(r.description);
  if (desc != null) bloques.add(desc);
  final pres = _presupuesto(r.budgetMin, r.budgetMax);
  if (pres != null) bloques.add(pres);
  bloques.add('Míralo aquí: ${ShareLinks.request(r.id)}');

  return bloques.join('\n\n');
}

Uri whatsappShareUri(ShareableRequest r) =>
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(buildRequestShareText(r))}');
