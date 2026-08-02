import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/business_details.dart';

/// Paridad con `src/lib/providerDetails.ts` + `BusinessDetailsCard.tsx` de la
/// web: la app enseñaba tres chips (categoría, zona, mayorista) donde la web
/// tiene una ficha con experiencia, fundación, equipo, cobertura, horario,
/// idiomas, pagos y garantía. Pedido PO 2026-08-01.
void main() {
  const hoy = 2026;

  group('businessDetailRows', () {
    test('negocio sin ningún dato => ninguna fila (la ficha no se dibuja)', () {
      expect(businessDetailRows(const {}, currentYear: hoy), isEmpty);
    });

    test('el orden es el de la web: ventas, experiencia, fundada, equipo, '
        'cobertura, horario, idiomas, pagos, garantía', () {
      final rows = businessDetailRows(const {
        'is_wholesale': true,
        'experience_years': 5,
        'business_type': 'formal',
        'founded_year': 2020,
        'employees_count': '6-10',
        'service_area': 'ambos',
        'service_hours': {
          'mon': {'open': '08:00', 'close': '17:00'},
        },
        'languages': ['es'],
        'payment_methods': ['efectivo'],
        'warranty': '1 año',
      }, currentYear: hoy);

      expect(rows.map((r) => r.label).toList(), [
        'Ventas',
        'Experiencia',
        'Fundada',
        'Equipo',
        'Cobertura',
        'Horario',
        'Idiomas',
        'Pagos',
        'Garantía',
      ]);
    });

    test('experiencia en 0 no se muestra: sería ruido, no un dato', () {
      expect(businessDetailRows(const {'experience_years': 0}, currentYear: hoy),
          isEmpty);
    });

    test('experiencia de 1 año va en singular', () {
      final rows =
          businessDetailRows(const {'experience_years': 1}, currentYear: hoy);
      expect(rows.single.value, '1 año');
    });

    test('la fundación SOLO sale en negocios formales', () {
      expect(
        businessDetailRows(
            const {'business_type': 'tecnico', 'founded_year': 2020},
            currentYear: hoy),
        isEmpty,
      );
      final formal = businessDetailRows(
          const {'business_type': 'formal', 'founded_year': 2020},
          currentYear: hoy);
      expect(formal.single.value, '2020 · 6 años');
    });

    test('una fundación en el futuro no inventa años negativos', () {
      final rows = businessDetailRows(
          const {'business_type': 'formal', 'founded_year': 2030},
          currentYear: hoy);
      expect(rows.single.value, '2030');
    });

    test('equipo de una persona va en singular', () {
      expect(
          businessDetailRows(const {'employees_count': '1'}, currentYear: hoy)
              .single
              .value,
          '1 persona');
      expect(
          businessDetailRows(const {'employees_count': '6-10'},
                  currentYear: hoy)
              .single
              .value,
          '6-10 personas');
    });

    test('los códigos se traducen a etiqueta', () {
      final rows = businessDetailRows(const {
        'service_area': 'a_domicilio',
        'languages': ['es', 'cr'],
        'payment_methods': ['transferencia', 'paypal'],
      }, currentYear: hoy);
      expect(rows[0].value, 'A domicilio');
      expect(rows[1].value, 'Español, Creole');
      expect(rows[2].value, 'Transferencia, PayPal');
    });

    test('un código desconocido se muestra crudo en vez de desaparecer', () {
      final rows = businessDetailRows(const {
        'languages': ['xx'],
      }, currentYear: hoy);
      expect(rows.single.value, 'xx');
    });

    test('una cobertura desconocida no genera fila', () {
      expect(
          businessDetailRows(const {'service_area': 'marte'}, currentYear: hoy),
          isEmpty);
    });

    test('la garantía en blanco no cuenta como dato', () {
      expect(businessDetailRows(const {'warranty': '   '}, currentYear: hoy),
          isEmpty);
    });
  });

  group('summarizeHours', () {
    test('tres días o más seguidos con el mismo horario se agrupan en rango',
        () {
      final s = summarizeHours(const {
        'mon': {'open': '08:00', 'close': '17:00'},
        'tue': {'open': '08:00', 'close': '17:00'},
        'wed': {'open': '08:00', 'close': '17:00'},
        'thu': {'open': '08:00', 'close': '17:00'},
        'fri': {'open': '08:00', 'close': '17:00'},
      });
      expect(s, 'Lunes a viernes 8:00 AM a 5:00 PM');
    });

    test('dos días seguidos se listan por separado, no como rango', () {
      final s = summarizeHours(const {
        'sat': {'open': '09:00', 'close': '13:00'},
        'sun': {'open': '09:00', 'close': '13:00'},
      });
      expect(s, 'Sábado 9:00 AM a 1:00 PM, domingo 9:00 AM a 1:00 PM');
    });

    test('los días cerrados cortan el grupo', () {
      final s = summarizeHours(const {
        'mon': {'open': '08:00', 'close': '12:00'},
        'wed': {'open': '08:00', 'close': '12:00'},
      });
      expect(s, 'Lunes 8:00 AM a 12:00 PM, miércoles 8:00 AM a 12:00 PM');
    });

    test('la nota se pega al final', () {
      final s = summarizeHours(const {
        'mon': {'open': '08:00', 'close': '17:00'},
        'notes': 'Cerramos feriados',
      });
      expect(s, 'Lunes 8:00 AM a 5:00 PM · Cerramos feriados');
    });

    test('solo nota, sin horarios, sigue siendo información útil', () {
      expect(summarizeHours(const {'notes': 'A convenir'}), 'A convenir');
    });

    test('sin nada devuelve null y la fila no aparece', () {
      expect(summarizeHours(null), isNull);
      expect(summarizeHours(const {}), isNull);
    });

    test('medianoche y mediodía no se convierten en 0:00', () {
      final s = summarizeHours(const {
        'mon': {'open': '00:00', 'close': '12:00'},
      });
      expect(s, 'Lunes 12:00 AM a 12:00 PM');
    });
  });
}
