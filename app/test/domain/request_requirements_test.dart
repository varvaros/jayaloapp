import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/request_requirements.dart';

/// Espejo de `src/lib/requestRequirements.test.ts` de la web. El módulo es puro
/// a propósito: la web dejó su máquina de estados de cotejo sin test y el único
/// bug serio de aquella rama vivía justo ahí.
void main() {
  group('requirementsFromRow', () {
    test('una fila con las cinco en true las marca todas', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'with_installation': true,
        'requires_evaluation': true,
        'requires_fiscal_receipt': true,
        'requires_state_supplier': true,
      });
      expect(r.withShipping, isTrue);
      expect(r.withInstallation, isTrue);
      expect(r.requiresEvaluation, isTrue);
      expect(r.requiresFiscalReceipt, isTrue);
      expect(r.requiresStateSupplier, isTrue);
    });

    test('clave ausente, null y false son lo mismo: no lo pide', () {
      final ausente = requirementsFromRow(<String, dynamic>{});
      final nulo = requirementsFromRow({
        'with_shipping': null,
        'requires_fiscal_receipt': null,
      });
      final falso = requirementsFromRow({
        'with_shipping': false,
        'requires_fiscal_receipt': false,
      });
      for (final r in [ausente, nulo, falso]) {
        expect(activeRequirements(r), isEmpty);
      }
    });

    test('un tipo inesperado no lanza y cae en false', () {
      // PostgREST no debería mandar esto, pero un `== true` es más barato que
      // un crash en la pantalla del proveedor.
      final r = requirementsFromRow({'with_shipping': 'true', 'requires_evaluation': 1});
      expect(r.withShipping, isFalse);
      expect(r.requiresEvaluation, isFalse);
    });
  });

  group('activeRequirements', () {
    test('devuelve los activos en orden canónico', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'with_installation': true,
        'requires_evaluation': true,
        'requires_fiscal_receipt': true,
        'requires_state_supplier': true,
      });
      expect(activeRequirements(r), [
        Requirement.shipping,
        Requirement.installation,
        Requirement.evaluation,
        Requirement.fiscal,
        Requirement.state,
      ]);
    });

    test('un subconjunto salteado conserva el orden', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'requires_state_supplier': true,
      });
      expect(activeRequirements(r), [Requirement.shipping, Requirement.state]);
    });

    test('sin nada activo devuelve lista vacía', () {
      expect(activeRequirements(RequestRequirements.none), isEmpty);
    });

    test('`keys` acota: no devuelve nada fuera del conjunto pedido', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'requires_fiscal_receipt': true,
      });
      expect(
        activeRequirements(r, keys: const [Requirement.fiscal]),
        [Requirement.fiscal],
      );
    });

    test('`keys` desordenado NO altera el orden de salida', () {
      final r = requirementsFromRow({
        'with_shipping': true,
        'requires_state_supplier': true,
      });
      expect(
        activeRequirements(r, keys: const [Requirement.state, Requirement.shipping]),
        [Requirement.shipping, Requirement.state],
        reason: 'el orden lo fija la declaración del enum, no quien llama',
      );
    });
  });

  group('requirementLabel', () {
    test('las cinco tienen los tres textos y ninguno vacío', () {
      for (final r in Requirement.values) {
        final l = requirementLabel(r);
        expect(l.chip, isNotEmpty, reason: '$r sin texto de chip');
        expect(l.short, isNotEmpty, reason: '$r sin texto corto');
        expect(l.hint, isNotEmpty, reason: '$r sin explicación');
      }
    });

    test('los textos son los de la web, literales', () {
      expect(requirementLabel(Requirement.fiscal).chip, 'Requiere comprobante fiscal');
      expect(requirementLabel(Requirement.fiscal).short, 'comprobante fiscal');
      expect(
        requirementLabel(Requirement.fiscal).hint,
        'El proveedor debe poder emitir comprobante fiscal (NCF).',
      );
      expect(requirementLabel(Requirement.state).chip, 'Requiere suplidor del Estado');
      expect(requirementLabel(Requirement.evaluation).chip, 'Requiere evaluación previa');
      expect(requirementLabel(Requirement.shipping).chip, 'Requiere traslado');
      expect(requirementLabel(Requirement.installation).chip, 'Requiere instalación');
    });
  });

  group('has', () {
    test('cada variante mapea a su propio campo y a ningún otro', () {
      // Uno solo en `true` por vuelta: si el `switch` de `has` tuviera un
      // mismapeo (p.ej. `installation` leyendo `requiresFiscalReceipt`),
      // ningún otro test de la suite lo detecta porque nadie enciende
      // `installation` en solitario.
      const casos = <Requirement, RequestRequirements>{
        Requirement.shipping: RequestRequirements(withShipping: true),
        Requirement.installation: RequestRequirements(withInstallation: true),
        Requirement.evaluation: RequestRequirements(requiresEvaluation: true),
        Requirement.fiscal: RequestRequirements(requiresFiscalReceipt: true),
        Requirement.state: RequestRequirements(requiresStateSupplier: true),
      };
      for (final entry in casos.entries) {
        final activo = entry.key;
        final req = entry.value;
        for (final r in Requirement.values) {
          expect(
            req.has(r),
            r == activo,
            reason: r == activo
                ? '$activo debería estar activo'
                : '$r no debería estar activo cuando solo $activo lo está',
          );
        }
      }
    });
  });

  group('unmetRequirements', () {
    const pideTodo = RequestRequirements(
      withShipping: true,
      withInstallation: true,
      requiresEvaluation: true,
      requiresFiscalReceipt: true,
      requiresStateSupplier: true,
    );

    test('una oferta que no cubre nada incumple los cuatro cotejables', () {
      expect(unmetRequirements(pideTodo, OfferCapabilities.none), [
        Requirement.shipping,
        Requirement.installation,
        Requirement.fiscal,
        Requirement.state,
      ]);
    });

    test('la evaluación NUNCA se reporta, aunque el cliente la pida y la oferta no la marque', () {
      // En la solicitud significa "quiero que vengan a ver antes de cotizar";
      // en la oferta, "necesito ir a ver para dar precio". Que el proveedor no
      // la marque significa precio en firme sin visita: favorece al cliente.
      expect(
        unmetRequirements(
          const RequestRequirements(requiresEvaluation: true),
          OfferCapabilities.none,
        ),
        isEmpty,
      );
    });

    test('una oferta que lo cubre todo no incumple nada', () {
      expect(
        unmetRequirements(
          pideTodo,
          const OfferCapabilities(
            offersShipping: true,
            offersInstallation: true,
            hasFiscalReceipt: true,
            isStateSupplier: true,
          ),
        ),
        isEmpty,
      );
    });

    test('ofrecer de más no cuenta como incumplimiento', () {
      expect(
        unmetRequirements(
          const RequestRequirements(requiresFiscalReceipt: true),
          const OfferCapabilities(
            offersShipping: true,
            offersInstallation: true,
            hasFiscalReceipt: true,
            isStateSupplier: true,
          ),
        ),
        isEmpty,
      );
    });

    test('solo reporta lo que el cliente pidió y la oferta no cubre', () {
      expect(
        unmetRequirements(
          const RequestRequirements(
            withShipping: true,
            requiresStateSupplier: true,
          ),
          const OfferCapabilities(offersShipping: true),
        ),
        [Requirement.state],
      );
    });

    test('el resultado sale en orden canónico', () {
      expect(
        unmetRequirements(
          const RequestRequirements(
            requiresStateSupplier: true,
            withShipping: true,
            requiresFiscalReceipt: true,
          ),
          OfferCapabilities.none,
        ),
        [Requirement.shipping, Requirement.fiscal, Requirement.state],
        reason: 'el orden lo fija la declaración del enum, no el de los campos',
      );
    });

    test('sin requisitos activos no hay nada que incumplir', () {
      expect(
        unmetRequirements(RequestRequirements.none, OfferCapabilities.none),
        isEmpty,
      );
    });
  });

  group('verifiableRequirements', () {
    test('son cuatro, en orden canónico, y la evaluación no está', () {
      expect(verifiableRequirements, [
        Requirement.shipping,
        Requirement.installation,
        Requirement.fiscal,
        Requirement.state,
      ]);
      expect(verifiableRequirements, isNot(contains(Requirement.evaluation)));
    });
  });

  group('unmetRequirementsMessage', () {
    test('lista vacía da cadena vacía', () {
      expect(unmetRequirementsMessage(const []), '');
    });

    test('uno solo va suelto', () {
      expect(unmetRequirementsMessage(const [Requirement.shipping]), 'traslado');
    });

    test('dos se unen con "y"', () {
      expect(
        unmetRequirementsMessage(const [Requirement.shipping, Requirement.fiscal]),
        'traslado y comprobante fiscal',
      );
    });

    test('tres llevan coma y la última con "y"', () {
      expect(
        unmetRequirementsMessage(const [
          Requirement.shipping,
          Requirement.fiscal,
          Requirement.state,
        ]),
        'traslado, comprobante fiscal y suplidor del Estado',
      );
    });

    test('usa los textos cortos, no los de chip', () {
      expect(
        unmetRequirementsMessage(const [Requirement.state]),
        isNot(contains('Requiere')),
      );
    });
  });

  group('requirementCoverage', () {
    const pideTodo = RequestRequirements(
      withShipping: true,
      withInstallation: true,
      requiresEvaluation: true,
      requiresFiscalReceipt: true,
      requiresStateSupplier: true,
    );

    test('sin condiciones marcadas no devuelve filas', () {
      expect(
        requirementCoverage(RequestRequirements.none, OfferCapabilities.none),
        isEmpty,
      );
    });

    test('solo evaluación tampoco devuelve filas: no es cotejable', () {
      expect(
        requirementCoverage(
          const RequestRequirements(requiresEvaluation: true),
          OfferCapabilities.none,
        ),
        isEmpty,
      );
    });

    test('conserva las cubiertas y las no cubiertas, no solo los fallos', () {
      final filas = requirementCoverage(
        const RequestRequirements(
          withShipping: true,
          requiresFiscalReceipt: true,
        ),
        const OfferCapabilities(offersShipping: true),
      );
      expect(filas.map((f) => f.key), [Requirement.shipping, Requirement.fiscal]);
      expect(filas.map((f) => f.covered), [true, false]);
    });

    test('las cuatro marcadas y la oferta sin declarar nada: cuatro filas en falso', () {
      final filas = requirementCoverage(pideTodo, OfferCapabilities.none);
      expect(filas.map((f) => f.key), [
        Requirement.shipping,
        Requirement.installation,
        Requirement.fiscal,
        Requirement.state,
      ]);
      expect(filas.every((f) => !f.covered), isTrue);
    });

    test('ofrecer de más no añade filas', () {
      final filas = requirementCoverage(
        const RequestRequirements(requiresFiscalReceipt: true),
        const OfferCapabilities(
          offersShipping: true,
          offersInstallation: true,
          hasFiscalReceipt: true,
          isStateSupplier: true,
        ),
      );
      expect(filas.map((f) => f.key), [Requirement.fiscal]);
      expect(filas.single.covered, isTrue);
    });

    test('el orden lo fija la declaración del enum, no el de los campos', () {
      final filas = requirementCoverage(
        const RequestRequirements(
          requiresStateSupplier: true,
          withShipping: true,
          requiresFiscalReceipt: true,
        ),
        OfferCapabilities.none,
      );
      expect(filas.map((f) => f.key), [
        Requirement.shipping,
        Requirement.fiscal,
        Requirement.state,
      ]);
    });

    test('la etiqueta cubierta empieza en mayúscula y no lleva coletilla', () {
      final filas = requirementCoverage(
        const RequestRequirements(requiresFiscalReceipt: true),
        const OfferCapabilities(hasFiscalReceipt: true),
      );
      expect(filas.single.label, 'Comprobante fiscal');
    });

    test('la etiqueta no cubierta dice "no lo declaró"', () {
      final filas = requirementCoverage(
        const RequestRequirements(requiresStateSupplier: true),
        OfferCapabilities.none,
      );
      expect(filas.single.label, 'Suplidor del Estado — no lo declaró');
    });

    test('el copy NUNCA afirma un negativo sobre el proveedor', () {
      // `false` significa hoy dos cosas: "lo vio y no lo marcó" y "ofertó antes
      // de que la pregunta existiera" — 33 de 34 ofertas son del segundo caso.
      // Decir "no cumple" o "no emite" sería mentir sobre un proveedor real.
      final filas = requirementCoverage(pideTodo, OfferCapabilities.none);
      for (final f in filas) {
        expect(f.label, isNot(contains('no cumple')));
        expect(f.label, isNot(contains('no emite')));
      }
    });

    test('dice exactamente lo mismo que la web', () {
      // El copy es lo único que puede divergir entre los dos frentes, y hasta
      // ahora solo lo vigilaba el test espejo de la web — que por construcción
      // solo detecta deriva de la WEB. `instalación` no lo fijaba nadie de este
      // lado. Si cambias uno, cambia el otro:
      // jayalo-main/src/lib/requestRequirements.test.ts → "dice exactamente lo
      // mismo que la app".
      final filas = requirementCoverage(
        pideTodo,
        const OfferCapabilities(offersShipping: true),
      );
      expect(filas.map((f) => f.label), [
        'Traslado',
        'Instalación — no lo declaró',
        'Comprobante fiscal — no lo declaró',
        'Suplidor del Estado — no lo declaró',
      ]);
    });
  });
}
