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
      expect(requirementLabel(Requirement.shipping).chip, 'Requiere envío');
      expect(requirementLabel(Requirement.installation).chip, 'Requiere instalación');
    });
  });

  group('has', () {
    test('cubre las cinco sin lanzar por un case olvidado', () {
      for (final r in Requirement.values) {
        RequestRequirements.none.has(r);
      }
    });
  });
}
