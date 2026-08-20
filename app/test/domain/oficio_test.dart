import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/oficio.dart';

void main() {
  group('oficiosFromRows', () {
    test('convierte filas completas', () {
      expect(
        oficiosFromRows([
          {'slug': 'plomero', 'name': 'Plomero'},
          {'slug': 'abogado', 'name': 'Abogado'},
        ]),
        const [
          Oficio(slug: 'plomero', name: 'Plomero'),
          Oficio(slug: 'abogado', name: 'Abogado'),
        ],
      );
    });

    test('descarta filas a medias: un chip sin nombre no se puede quitar', () {
      expect(
        oficiosFromRows([
          {'slug': 'plomero', 'name': '  '},
          {'slug': '', 'name': 'Sin slug'},
          {'slug': 'abogado', 'name': 'Abogado'},
        ]),
        const [Oficio(slug: 'abogado', name: 'Abogado')],
      );
    });

    test('lista vacía no revienta', () {
      expect(oficiosFromRows(const []), isEmpty);
    });
  });

  group('approvedOficioNames', () {
    Map<String, dynamic> biz(List<Map<String, dynamic>> rows) => {
      'provider_business_oficios': rows,
    };

    test('devuelve los aprobados, en orden alfabético', () {
      expect(
        approvedOficioNames(
          biz([
            {
              'approved_at': '2026-08-20T00:00:00Z',
              'oficios': {'name': 'Plomero'},
            },
            {
              'approved_at': '2026-08-20T00:00:00Z',
              'oficios': {'name': 'Electricista'},
            },
          ]),
        ),
        ['Electricista', 'Plomero'],
      );
    });

    test('esconde los PENDIENTES: el dueño ve los suyos, el público no', () {
      expect(
        approvedOficioNames(
          biz([
            {
              'approved_at': null,
              'oficios': {'name': 'Plomero'},
            },
          ]),
        ),
        isEmpty,
      );
    });

    test('sin la clave del embebido devuelve vacío', () {
      expect(approvedOficioNames(const {}), isEmpty);
    });

    test('tolera basura en el embebido sin lanzar', () {
      expect(approvedOficioNames({'provider_business_oficios': 'nope'}), isEmpty);
      expect(
        approvedOficioNames(
          biz([
            {'approved_at': '2026-08-20T00:00:00Z', 'oficios': null},
          ]),
        ),
        isEmpty,
      );
    });
  });

  test('el tope es 4, igual que el trigger y la RPC', () {
    expect(kMaxOficios, 4);
  });
}
