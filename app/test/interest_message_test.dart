import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/interest_message.dart';
import 'package:jayalo_app/domain/profile_address.dart';

/// Paridad EXACTA con `buildMessage()` de
/// `src/components/marketplace/InterestConfirmDialog.tsx` (web): mismos
/// rótulos, mismo orden, mismos textos de urgencia — el proveedor lee este
/// mensaje en la web tal cual, venga de donde venga.
void main() {
  group('buildProductInterestMessage', () {
    test('mínimo: solo cantidad y urgencia', () {
      final msg = buildProductInterestMessage(
          quantity: 1, urgency: InterestUrgency.semana);
      expect(msg, 'Cantidad: 1\nCuándo quiere comprar: Esta semana');
    });

    test('con marca, color y dirección — todas las líneas opcionales', () {
      final msg = buildProductInterestMessage(
        quantity: 3,
        urgency: InterestUrgency.hoy,
        brand: 'Samsung',
        colorKey: 'azul',
        address: 'Calle 5 #10, Piantini, Santo Domingo',
      );
      expect(
        msg,
        'Cantidad: 3\n'
        'Cuándo quiere comprar: Hoy mismo\n'
        'Marca / preferencia: Samsung\n'
        'Color: Azul\n'
        'Dirección de entrega: Calle 5 #10, Piantini, Santo Domingo',
      );
    });

    test('marca en blanco no agrega la línea (se recorta y se descarta)', () {
      final msg = buildProductInterestMessage(
          quantity: 2, urgency: InterestUrgency.mes, brand: '   ');
      expect(msg, 'Cantidad: 2\nCuándo quiere comprar: Este mes');
    });

    test('color inexistente no agrega línea (paridad find() sin match)', () {
      final msg = buildProductInterestMessage(
          quantity: 1,
          urgency: InterestUrgency.flexible,
          colorKey: 'fucsia');
      expect(msg, 'Cantidad: 1\nCuándo quiere comprar: Fecha flexible');
    });

    test('las 4 urgencias tienen el texto EXACTO de la web', () {
      expect(InterestUrgency.hoy.text, 'Hoy mismo');
      expect(InterestUrgency.semana.text, 'Esta semana');
      expect(InterestUrgency.mes.text, 'Este mes');
      expect(InterestUrgency.flexible.text, 'Fecha flexible');
    });
  });

  group('buildServiceInterestMessage', () {
    test('mínimo: qué necesita, cuándo y lugar', () {
      final msg = buildServiceInterestMessage(
        need: 'Mi aire de 24k no enfría, hace ruido al encender.',
        urgency: InterestUrgency.hoy,
        locationText: 'A coordinar',
      );
      expect(
        msg,
        'Qué necesita: Mi aire de 24k no enfría, hace ruido al encender.\n'
        'Cuándo lo necesita: Hoy mismo\n'
        'Lugar: A coordinar',
      );
    });

    test('con preferencias y foto', () {
      final msg = buildServiceInterestMessage(
        need: 'Necesito instalar 2 abanicos de techo en la sala.',
        urgency: InterestUrgency.semana,
        locationText: 'En mi dirección: Calle Duarte 12',
        preferences: 'horario de tarde',
        photoUrl: 'https://cdn.example.com/foto.jpg',
      );
      expect(
        msg,
        'Qué necesita: Necesito instalar 2 abanicos de techo en la sala.\n'
        'Cuándo lo necesita: Esta semana\n'
        'Lugar: En mi dirección: Calle Duarte 12\n'
        'Preferencias: horario de tarde\n'
        'Foto: https://cdn.example.com/foto.jpg',
      );
    });
  });

  group('serviceLocationText', () {
    test('en el local del proveedor', () {
      expect(serviceLocationText(atProvider: true),
          'En el local del proveedor / a coordinar');
      // Ignora la dirección si atProvider es true.
      expect(serviceLocationText(atProvider: true, address: 'Calle X'),
          'En el local del proveedor / a coordinar');
    });

    test('en mi dirección, con dato', () {
      expect(
          serviceLocationText(atProvider: false, address: 'Calle Duarte 12'),
          'En mi dirección: Calle Duarte 12');
    });

    test('sin dirección -> a coordinar', () {
      expect(serviceLocationText(atProvider: false), 'A coordinar');
      expect(serviceLocationText(atProvider: false, address: '   '),
          'A coordinar');
    });
  });

  group('canSubmitServiceInterest', () {
    test('menos de 15 caracteres (tras recortar) no permite enviar', () {
      expect(canSubmitServiceInterest('corto'), isFalse);
      expect(canSubmitServiceInterest('123456789012345'.substring(0, 14)),
          isFalse);
      // Espacios que no cuentan como contenido real.
      expect(canSubmitServiceInterest('  abc  '), isFalse);
    });

    test('exactamente 15 caracteres ya permite enviar', () {
      expect('123456789012345'.length, 15);
      expect(canSubmitServiceInterest('123456789012345'), isTrue);
    });

    test('15+ con espacios alrededor también permite (se recorta antes)', () {
      expect(canSubmitServiceInterest('  123456789012345  '), isTrue);
    });
  });

  group('truncateInterestMessage', () {
    test('mensajes cortos quedan igual', () {
      expect(truncateInterestMessage('hola'), 'hola');
    });

    test('recorta a 1000 caracteres', () {
      final long = 'a' * 1200;
      final truncated = truncateInterestMessage(long);
      expect(truncated.length, 1000);
      expect(truncated, 'a' * 1000);
    });
  });

  group('composeProfileAddress', () {
    test('address completo gana sobre las partes', () {
      expect(
        composeProfileAddress(
          address: 'Calle 5 #10, Piantini',
          street: 'Otra calle',
          streetNumber: '99',
          sector: 'Otro sector',
          city: 'Otra ciudad',
        ),
        'Calle 5 #10, Piantini',
      );
    });

    test('sin address, arma street+número, sector, ciudad', () {
      expect(
        composeProfileAddress(
          street: 'Calle Duarte',
          streetNumber: '12',
          sector: 'Los Prados',
          city: 'Santo Domingo',
        ),
        'Calle Duarte 12, Los Prados, Santo Domingo',
      );
    });

    test('street sin número queda solo (paridad ternario de la web)', () {
      expect(
        composeProfileAddress(street: 'Calle Duarte', city: 'Santo Domingo'),
        'Calle Duarte, Santo Domingo',
      );
    });

    test('sin ningún dato devuelve null', () {
      expect(composeProfileAddress(), isNull);
      expect(composeProfileAddress(address: '   '), isNull);
    });
  });

  group('composeDeliveryAddress', () {
    // La regresión que motiva estos tests: al desglosar la dirección del alta,
    // `profiles.address` pasó a guardar SOLO calle y número. Con la semántica
    // de `composeProfileAddress` (address gana y se ignora el resto) el
    // proveedor recibía "Calle Duarte 45", sin ciudad ni sector: imposible
    // entregar ahí.
    test('añade sector y ciudad a la calle guardada en address', () {
      expect(
        composeDeliveryAddress(
          address: 'Calle Duarte 45',
          sector: 'Villa Olga',
          city: 'Santiago',
        ),
        'Calle Duarte 45, Villa Olga, Santiago',
      );
    });

    test('sin address usa street + número', () {
      expect(
        composeDeliveryAddress(
          street: 'Calle Duarte',
          streetNumber: '45',
          sector: 'Villa Olga',
          city: 'Santiago',
        ),
        'Calle Duarte 45, Villa Olga, Santiago',
      );
    });

    test('un perfil viejo con la dirección entera en address no se repite', () {
      expect(
        composeDeliveryAddress(
          address: 'Calle Duarte 45, Villa Olga, Santiago',
          sector: 'Villa Olga',
          city: 'Santiago',
        ),
        'Calle Duarte 45, Villa Olga, Santiago',
      );
    });

    test('con solo ciudad devuelve la ciudad', () {
      expect(composeDeliveryAddress(city: 'Santiago'), 'Santiago');
    });

    test('sin ningún dato devuelve null', () {
      expect(composeDeliveryAddress(), isNull);
      expect(composeDeliveryAddress(address: '  ', sector: ' '), isNull);
    });
  });
}
