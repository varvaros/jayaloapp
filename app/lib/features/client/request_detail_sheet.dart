import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../domain/chat_time.dart';
import '../../domain/finalist_slots.dart';
import '../../domain/money.dart';
import '../../domain/phase.dart';
import '../../domain/request_requirements.dart';
import '../chat/widgets/rating_form.dart';
import '../shared/brand_kit.dart';
import '../shared/detail_tiles.dart';
import '../shared/onboarding_copy.dart';
import '../shared/onboarding_guide.dart';
import '../shared/request_bullet_tiles.dart';
import '../shared/request_requirement_badges.dart';
import '../shared/section_heading.dart';
import '../shell/floating_nav_bar.dart';
import 'request_status_screen.dart';

/// Copy del héroe de fase, cuerpo. `closedReason` SOLO importa cuando `phase`
/// es `closed` (en cualquier otra fase se ignora): `null` ahí significa razón
/// desconocida o mezclada entre finalistas, no "sin cerrar" — y el genérico es
/// lo correcto porque contar una de las dos razones sería mentir a medias.
///
/// Convertido de mapa `const` a función con `switch` EXHAUSTIVO (antes se leía
/// con `!`): una fase sin copy dejaba de ser un error de compilación y pasaba
/// a ser un crash en runtime (casi ocurre en la Task 6). Al añadir una fase,
/// el compilador ahora obliga a tocar esta función Y `_phaseTitleFor`.
String _phaseCopyFor(RequestPhase phase, ClosedReason? closedReason) =>
    switch (phase) {
      RequestPhase.waiting =>
        'Tu solicitud está publicada. Los proveedores la están viendo.',
      RequestPhase.withOffers => 'Revisa las ofertas: puedes aceptar hasta 3.',
      RequestPhase.accepted => 'El proveedor te contactará pronto.',
      RequestPhase.unlocked => 'Ya puedes hablar con el proveedor.',
      // Sin promesa de calificar aqui: para `closed` no se renderiza ningun
      // panel de resena (gateado en `completed`, y `completedReviewBusinessIds`
      // filtra por ofertas `status == 'completed'`, que aqui por definicion no
      // hay). La calificacion vive en el CHAT, no en esta pantalla.
      RequestPhase.completed =>
        'Califica al proveedor para ayudar a la comunidad.',
      RequestPhase.closed => switch (closedReason) {
          ClosedReason.inactivity => 'Nadie escribió y el chat se cerró solo.',
          ClosedReason.notAgreed => 'El trato se marcó como no concretado.',
          null => 'El chat se cerró sin completarse.',
        },
    };

/// Títulos del héroe de fase (variante D1 elegida por el PO). Mismo motivo de
/// función-en-vez-de-mapa que `_phaseCopyFor`.
String _phaseTitleFor(RequestPhase phase, ClosedReason? closedReason) =>
    switch (phase) {
      RequestPhase.waiting => 'Esperando ofertas',
      RequestPhase.withOffers => 'Con ofertas',
      RequestPhase.accepted => 'Oferta aceptada',
      // "En contacto", no "desbloqueado" (pedido PO 2026-07-23): el CLIENTE
      // nunca desbloquea nada — quien paga es el proveedor; para el cliente
      // la fase es simplemente que ya están en contacto.
      RequestPhase.unlocked => 'En contacto',
      RequestPhase.completed => 'Completada',
      RequestPhase.closed => switch (closedReason) {
          ClosedReason.inactivity => 'Cerrada por inactividad',
          ClosedReason.notAgreed => 'No concretada',
          null => 'Cerrada',
        },
    };

/// Hoja blanca del detalle: título + chip de fase, "Desde", avatares anónimos
/// de proveedores, la sección ESTADO (publicación, copy de fase, cupos) y la
/// sección INFORMACIÓN (chips con los bullets de la IA y el presupuesto).
///
/// SIN scroll propio (decisión PO 2026-08-02, tras un BLOCKED): vive dentro
/// de un `SliverFillRemaining(hasScrollBody: false)` en el `CustomScrollView`
/// de la pantalla, así que es el scroll EXTERNO el que la mueve junto con el
/// panel de foto. Antes tenía su propio `ListView` y ese scroll quedaba
/// aislado del panel — medido en la Task 4: el panel se quedaba fijo en
/// 300.0 mientras el título scrolleaba solo, adentro. Por eso mismo ya NO
/// trae el CTA "Ver N ofertas": se movió a `RequestDetailCta`, que vive FUERA
/// del `CustomScrollView` para seguir anclado abajo.
///
/// CONTRATO DE LAYOUT — todo lo que se agregue aquí debe soportar ALTO
/// INTRÍNSECO. `SliverFillRemaining(hasScrollBody: false)` le pide a su hijo
/// `getMaxIntrinsicHeight`, y hay widgets que no saben responder: un
/// `LayoutBuilder`, un `ListView`/`PageView` anidado, un `AspectRatio` sobre
/// entrada sin acotar. Cualquiera de ellos **lanza en tiempo de layout en la
/// pantalla principal del cliente**, y `flutter analyze` no avisa de nada. Si
/// hace falta uno, envuélvelo en algo de alto fijo (`SizedBox(height: …)`).
class RequestDetailSheet extends StatelessWidget {
  const RequestDetailSheet({
    super.key,
    required this.request,
    required this.phase,
    required this.offers,
    this.closedReason,
  });

  final Map<String, dynamic> request;
  final RequestPhase phase;
  final List<Map<String, dynamic>> offers;

  /// Solo aplica cuando `phase` es `closed`; ver `RequestDetailBody.closedReason`.
  final ClosedReason? closedReason;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bullets =
        ((request['bullets'] as List?)?.cast<String>() ?? const <String>[])
            .where((b) => b.trim().isNotEmpty)
            .toList();
    final createdAt = DateTime.parse(request['created_at'] as String);
    final tone = toneFor(context, phase);
    // "Desde": el total efectivo (precio + envío) más bajo entre las ofertas.
    final cheapest = offers
        .map(offerEffectivePrice)
        .whereType<num>()
        .fold<num?>(null, (a, b) => a == null ? b : (b < a ? b : a));
    // ¿La sección "Información" tiene algo que enseñar? Sin esto, una
    // solicitud sin bullets ni presupuesto dejaba "INFORMACIÓN" flotando
    // sobre nada (mismo hallazgo en device que en el detalle del proveedor,
    // 2026-08-01). ESTADO no necesita el mismo guard: "Publicada …" y el
    // copy de fase se pintan siempre.
    final hayInfo = bullets.isNotEmpty ||
        requestBudgetLabel(
              request['budget_min'] as num?,
              request['budget_max'] as num?,
            ) !=
            null;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  request['title'] as String,
                  style: TextStyle(
                    // +1pt (pedido PO).
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              StatusChip(
                label: _phaseTitleFor(phase, closedReason),
                tone: tone,
              ),
            ],
          ),
          // Pill "Al por mayor" dentro de la solicitud (pedido PO
          // 2026-07-22): chip violeta debajo del estado, no toca la
          // etiqueta de la lista. Solo en productos mayoristas.
          if (request['is_wholesale'] == true) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: StatusChip(
                label: 'Al por mayor',
                icon: Icons.inventory_2_outlined,
                tone: Theme.of(context).brightness == Brightness.dark
                    ? JayaloStatus.respondedDark
                    : JayaloStatus.respondedLight,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                cheapest != null ? 'Desde: ' : 'Aún sin ofertas',
                style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
              ),
              if (cheapest != null)
                Text(
                  fmtRD(cheapest),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: jayaloHead(context),
                  ),
                ),
              const Spacer(),
              _ProviderDots(count: offers.length),
            ],
          ),
          // ── 1) ESTADO ──
          // Orden pactado con el PO (2026-08-02): estado → información. El
          // cliente ya sabe qué pidió (eso es la identidad, arriba); lo que
          // no sabe es cómo va. El precio "Desde" se queda pegado al título
          // como titular, aunque técnicamente también sea estado.
          sectionHeading(context, 'Estado'),
          const SizedBox(height: 18),
          Text(
            'Publicada: ${formatDayLabel(createdAt)} · ${formatTimeHM(createdAt)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            _phaseCopyFor(phase, closedReason),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          // Cupos restantes (modelo de hasta 3 finalistas): el cliente
          // puede aceptar más de una oferta.
          if (offers.isNotEmpty &&
              phase != RequestPhase.completed &&
              phase != RequestPhase.closed) ...[
            const SizedBox(height: 6),
            Text(
              clientSlotsMessage(
                offers
                    .where(
                      (o) =>
                          o['status'] == 'accepted' ||
                          o['status'] == 'completed',
                    )
                    .length,
              ),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
          // Fase completada: cerrar la promesa del copy de `_phaseCopy`
          // ("Califica al proveedor para ayudar a la comunidad"), que
          // hasta ahora no tenía ningún control detrás. Un panel POR
          // NEGOCIO completado (modelo de hasta 3 finalistas: puede
          // haber más de uno), no solo el "primero" entre las ofertas.
          if (phase == RequestPhase.completed)
            for (final bizId in completedReviewBusinessIds(offers))
              BusinessReviewPanel(
                // Key por negocio: si cambian las ofertas completadas,
                // cada panel se re-crea y vuelve a cargar SU reseña sin
                // que Flutter confunda su estado con el de otro.
                key: ValueKey('review-$bizId'),
                businessId: bizId,
              ),
          // ── 2) INFORMACIÓN ──
          // El encabezado SOLO si hay algo debajo (`hayInfo`): una solicitud
          // sin bullets ni presupuesto dejaba "INFORMACIÓN" flotando sobre
          // nada. El rótulo `Text('Detalles')` que había aquí se borra: con
          // INFORMACIÓN encima quedarían dos etiquetas anidadas diciendo casi
          // lo mismo.
          if (hayInfo) sectionHeading(context, 'Información'),
          if (hayInfo) ...[
            // Un solo separador: había DOS apilados (18 + 10), escombro de
            // borrar el `Text('Detalles')` que vivía entre ambos.
            const SizedBox(height: 10),
            // Plantilla aprobada PO 2026-08-11: los bullets «Etiqueta: valor»
            // de la IA se leen como las tarjetas del detalle de oferta y del
            // catálogo; el presupuesto es una tarjeta más del bloque. Sin
            // eyebrow: INFORMACIÓN (arriba) ya titula la sección.
            Builder(builder: (context) {
              final parsed = requestBulletRows(bullets);
              final budget = requestBudgetLabel(
                request['budget_min'] as num?,
                request['budget_max'] as num?,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...detailTileBlock(context, rows: [
                    ...parsed.rows,
                    if (budget != null)
                      (
                        Icons.payments_outlined,
                        'Presupuesto estimado',
                        budget,
                        false
                      ),
                  ]),
                  for (final b in parsed.freeText)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(b,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: cs.onSurfaceVariant)),
                    ),
                ],
              );
            }),
          ],
          // Requisitos en teal con su propio eyebrow, cerrando el bloque
          // (plantilla PO 2026-08-11) — antes eran chips bajo el título.
          RequestRequirementBadges(
            req: requirementsFromRow(request),
            variant: RequirementBadgeVariant.tiles,
            padding: const EdgeInsets.only(top: 16),
          ),
        ],
      ),
    );
  }
}

/// CTA "Ver N ofertas". Vive FUERA del `CustomScrollView`, anclado abajo por
/// el `Column` de la pantalla: si estuviera dentro del scroll se iría de
/// pantalla justo cuando hace falta.
///
/// Se extrajo de `RequestDetailSheet` (decisión PO 2026-08-02): esa hoja
/// perdió su scroll propio para poder participar del scroll externo junto
/// con el panel de foto, y el CTA necesita quedarse fijo abajo en vez de
/// scrollear con el resto del contenido.
class RequestDetailCta extends StatelessWidget {
  const RequestDetailCta({
    super.key,
    required this.offers,
    required this.unreadCount,
    required this.onSeeOffers,
  });

  final List<Map<String, dynamic>> offers;

  /// Ofertas sin abrir: número del badge rojo sobre el botón "Ver N ofertas".
  final int unreadCount;
  final VoidCallback onSeeOffers;

  @override
  Widget build(BuildContext context) =>
      // `ColoredBox` con el mismo tono de la hoja (`surfaceContainerLowest`):
      // este CTA se extrajo de dentro del `Container` de `RequestDetailSheet`
      // (que pintaba ese color de fondo) para vivir fuera del scroll. Sin
      // este envoltorio, la banda del CTA pinta sobre el `Scaffold`
      // (`cs.surface`) en vez de sobre el color de tarjeta de la hoja — dos
      // tokens que `brand.dart` separa a propósito para que las tarjetas se
      // vean elevadas (hallazgo de revisión 2026-08-02: en oscuro quedaba una
      // franja casi negra bajo la hoja).
      ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child:
            // CTA único: "Ver N ofertas" (violeta, solo navega — aceptar vive
            // por oferta en la hoja). El "Volver" se quitó: duplicaba la
            // flecha de atrás flotante del panel (ambos hacían
            // context.pop()). Reserva el alto de la barra flotante para no
            // quedar tapado.
            Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            12 + navBarReservedSpace(context),
          ),
          // Badge rojo con el número de ofertas SIN ABRIR (pedido PO
          // 2026-07-23), en la esquina del botón — la "notificación" que dice
          // cuántas faltan por revisar.
          child: OnboardingGuide(
            guideKey: 'client.view_offers.v1',
            enabled: offers.isNotEmpty,
            steps: onboardingCopy['client.view_offers.v1']!,
            child: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              offset: const Offset(-6, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onSeeOffers,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    offers.isEmpty
                        ? 'Ver ofertas'
                        : 'Ver ${offers.length} oferta${offers.length == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Círculos apilados = cuántos proveedores ofertaron, en el resumen ANTES de
/// abrir la lista. Ya NO son anónimos (PO 2026-07-28: el cliente ve nombre y
/// logo de quien oferta) — siguen siendo un contador genérico aquí porque este
/// resumen no trae `business_id` por tarjeta, solo el total; el avatar real
/// vive en la cabecera de cada `_OfferCard` dentro de la lista.
class _ProviderDots extends StatelessWidget {
  const _ProviderDots({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final shown = count > 3 ? 3 : count;
    return SizedBox(
      width: 28.0 + (shown - 1) * 18,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < shown; i++)
            Positioned(
              left: i * 18.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primaryContainer,
                  border: Border.all(
                    color: cs.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.person,
                  size: 15,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
