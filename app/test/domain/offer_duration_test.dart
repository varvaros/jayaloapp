import 'package:flutter_test/flutter_test.dart';
import 'package:jayalo_app/domain/offer_duration.dart';
import 'package:jayalo_app/domain/offer_message.dart';

/// Espejo de `src/lib/offerDuration.test.ts` del repo web. La tabla de casos es
/// LA MISMA a propósito: la paridad entre los dos parsers no se razona, se mide
/// (lección de `contact_info_guard_v2`).
void main() {
  group('formatOfferDuration', () {
    test('usa singular con 1 y plural con el resto', () {
      expect(formatOfferDuration(1, OfferDurationUnit.minutos), '1 minuto');
      expect(formatOfferDuration(30, OfferDurationUnit.minutos), '30 minutos');
      expect(formatOfferDuration(1, OfferDurationUnit.horas), '1 hora');
      expect(formatOfferDuration(8, OfferDurationUnit.horas), '8 horas');
      expect(formatOfferDuration(1, OfferDurationUnit.dias), '1 día');
      expect(formatOfferDuration(3, OfferDurationUnit.dias), '3 días');
      expect(formatOfferDuration(1, OfferDurationUnit.semanas), '1 semana');
      expect(formatOfferDuration(2, OfferDurationUnit.semanas), '2 semanas');
    });

    test('acepta el número como cadena (viene de un TextEditingController)', () {
      expect(formatOfferDuration('3', OfferDurationUnit.dias), '3 días');
      expect(formatOfferDuration(' 3 ', OfferDurationUnit.dias), '3 días');
    });

    test('devuelve cadena vacía en vez de inventar, ante entrada inválida', () {
      expect(formatOfferDuration('', OfferDurationUnit.dias), '');
      expect(formatOfferDuration(null, OfferDurationUnit.dias), '');
      expect(formatOfferDuration('abc', OfferDurationUnit.dias), '');
      expect(formatOfferDuration(0, OfferDurationUnit.dias), '');
      expect(formatOfferDuration(-2, OfferDurationUnit.dias), '');
      expect(formatOfferDuration(1.5, OfferDurationUnit.dias), '');
    });

    // No llega por la UI (los inputFormatters solo dejan dígitos), pero la
    // función promete en su documentación que NUNCA lanza — y con infinito
    // lanzaba: `n == n.roundToDouble()` es cierto y `toInt()` explota. El TS
    // devuelve "" aquí, así que además era una divergencia con la web.
    test('no lanza ante infinitos ni NaN, devuelve vacío como el TS', () {
      expect(formatOfferDuration('Infinity', OfferDurationUnit.dias), '');
      expect(formatOfferDuration('-Infinity', OfferDurationUnit.dias), '');
      expect(formatOfferDuration(double.infinity, OfferDurationUnit.dias), '');
      expect(formatOfferDuration(double.nan, OfferDurationUnit.dias), '');
    });

    // La razón de ser del tope: sin él el campo vuelve a poder transportar un
    // número marcable. Ver la cabecera de offer_duration.dart.
    test('rechaza más dígitos de los permitidos', () {
      expect(kOfferDurationMaxDigits, 3);
      expect(formatOfferDuration(999, OfferDurationUnit.dias), '999 días');
      expect(formatOfferDuration(1000, OfferDurationUnit.dias), '');
      expect(formatOfferDuration(5551234, OfferDurationUnit.dias), '');
      expect(formatOfferDuration(8095551234, OfferDurationUnit.dias), '');
    });
  });

  group('parseOfferDuration', () {
    test('da la vuelta a lo que compone formatOfferDuration', () {
      for (final unit in OfferDurationUnit.values) {
        for (final n in [1, 2, 30, 999]) {
          final compuesto = formatOfferDuration(n, unit);
          expect(parseOfferDuration(compuesto), (value: n, unit: unit));
        }
      }
    });

    // Divergencia MEDIDA contra el TS y corregida: la web hace
    // `normalize("NFD")` y acepta las dos formas de «día»; un mapa que solo
    // conociera la precompuesta leía distinto que la web.
    test('lee «días» tanto precompuesto como descompuesto (NFD)', () {
      const precompuesto = '3 d\u00edas'; // i acentuada, U+00ED
      const descompuesto = '3 di\u0301as'; // i + U+0301 combinante
      expect(parseOfferDuration(precompuesto),
          (value: 3, unit: OfferDurationUnit.dias));
      expect(parseOfferDuration(descompuesto),
          (value: 3, unit: OfferDurationUnit.dias));
    });

    test('lee con y sin tilde, y sin importar mayúsculas', () {
      expect(parseOfferDuration('3 dias'),
          (value: 3, unit: OfferDurationUnit.dias));
      expect(parseOfferDuration('3 DÍAS'),
          (value: 3, unit: OfferDurationUnit.dias));
      expect(parseOfferDuration('  1 Hora  '),
          (value: 1, unit: OfferDurationUnit.horas));
    });

    // `null` = "no lo sé leer", nunca "está vacío". Quien llame debe conservar
    // el original: si no, editar una oferta vieja le borra el dato al proveedor.
    test('devuelve null ante los valores históricos que no reconoce', () {
      expect(parseOfferDuration('8 horas (1 día laboral)'), isNull);
      expect(parseOfferDuration('A definir según evaluación'), isNull);
      expect(parseOfferDuration('Más de 1 semana'), isNull);
      expect(parseOfferDuration('d'), isNull); // el valor REAL que hay en prod
      expect(parseOfferDuration(''), isNull);
      expect(parseOfferDuration(null), isNull);
      expect(parseOfferDuration('2 meses'), isNull);
    });
  });

  group('durationForSave', () {
    // Sin contraparte en la web: la web no prellena la duración al editar
    // (su formulario nace siempre vacío), así que este caso es solo de la app.
    test('con el campo vacío gana el legado — NO se borra la duración vieja',
        () {
      expect(
        durationForSave(
          typed: '',
          unit: OfferDurationUnit.dias,
          legacy: '8 horas (1 día laboral)',
        ),
        '8 horas (1 día laboral)',
      );
      expect(
        durationForSave(
          typed: '   ',
          unit: OfferDurationUnit.dias,
          legacy: 'd',
        ),
        'd',
      );
    });

    test('lo tecleado reemplaza al legado', () {
      expect(
        durationForSave(
          typed: '3',
          unit: OfferDurationUnit.semanas,
          legacy: 'A definir según evaluación',
        ),
        '3 semanas',
      );
    });

    test('sin legado y sin número, vacío', () {
      expect(
        durationForSave(
            typed: '', unit: OfferDurationUnit.dias, legacy: ''),
        '',
      );
    });
  });

  // El camino más caro de todo el cambio, y el que no tiene widget test
  // posible: editar una oferta VIEJA sin borrarle la duración al proveedor.
  // Reproduce lo que hace la pantalla: fila → controles → guardado → fila.
  group('ciclo de vida al editar una oferta existente', () {
    String guardarSinTocarLaDuracion(String? filaOriginal) {
      final f = durationFieldsFromRaw(filaOriginal); // _prefillFromOffer
      // El proveedor cambia SOLO el precio: no toca ni el número ni la unidad.
      return durationForSave(typed: f.typed, unit: f.unit, legacy: f.legacy);
    }

    test('una duración ilegible SOBREVIVE al guardado', () {
      for (final historico in const [
        '8 horas (1 día laboral)',
        'A definir según evaluación',
        'Más de 1 semana',
        'd', // el valor REAL que hay en prod
      ]) {
        expect(guardarSinTocarLaDuracion(historico), historico);
      }
    });

    test('una duración legible sobrevive idéntica', () {
      expect(guardarSinTocarLaDuracion('3 días'), '3 días');
      // Se normaliza a la forma canónica, que es lo que se quiere.
      expect(guardarSinTocarLaDuracion('3 dias'), '3 días');
    });

    test('vacío sigue vacío — no inventa una duración', () {
      expect(guardarSinTocarLaDuracion(''), '');
      expect(guardarSinTocarLaDuracion(null), '');
      expect(guardarSinTocarLaDuracion('   '), '');
    });

    test('guardar DOS veces seguidas no degrada el valor', () {
      for (final historico in const ['8 horas (1 día laboral)', 'd', '2 días']) {
        // `updateOffer` devuelve lo escrito y la pantalla parchea
        // `_existingOffer` con ello; reabrir vuelve a prefijar desde ahí.
        final primera = guardarSinTocarLaDuracion(historico);
        final segunda = guardarSinTocarLaDuracion(primera);
        expect(segunda, primera);
      }
    });

    test('teclear un número reemplaza al legado, y quitarlo lo borra', () {
      final f = durationFieldsFromRaw('A definir según evaluación');
      expect(f.legacy, 'A definir según evaluación');
      expect(f.typed, '');
      // Teclear: la pantalla vacía el legado en el `onChanged`.
      expect(durationForSave(typed: '5', unit: f.unit, legacy: ''), '5 días');
      // «Quitar»: legado vacío y campo vacío ⇒ se guarda vacío, a propósito.
      expect(durationForSave(typed: '', unit: f.unit, legacy: ''), '');
    });
  });

  group('no rompe el lector del mensaje de la oferta', () {
    // Regla 1 de la cabecera: ninguna etiqueta puede llevar " · " dentro,
    // porque es el separador con el que se compone y se parte el mensaje.
    test('ninguna etiqueta de unidad contiene el separador', () {
      for (final u in OfferDurationUnit.values) {
        expect(u.label, isNot(contains(' · ')));
        expect(u.singular, isNot(contains(' · ')));
        expect(formatOfferDuration(1, u), isNot(contains(' · ')));
        expect(formatOfferDuration(2, u), isNot(contains(' · ')));
      }
    });

    test('la línea compuesta se tacha entera del texto libre', () {
      for (final u in OfferDurationUnit.values) {
        final dur = formatOfferDuration(2, u);
        final message =
            composeOfferMessage(isService: true, estimatedDuration: dur);
        expect(message, contains('Duración: $dur'));
        expect(freeTextFromOfferMessage(message, {'Duración'}), '');
      }
    });

    // Ida y vuelta por el payload: lo que `updateOffer` devuelve es lo que
    // parchea `_existingOffer` en local, y de ahí sale el prefill al reabrir
    // "Ver mi oferta". Si esa vuelta no cerrara, editar dos veces seguidas
    // perdería la duración en la segunda.
    test('lo guardado se vuelve a leer al reabrir la oferta', () {
      for (final u in OfferDurationUnit.values) {
        final guardado = durationForSave(typed: '4', unit: u, legacy: '');
        final releido = parseOfferDuration(guardado);
        expect(releido, isNotNull);
        expect(releido, (value: 4, unit: u));
      }
    });
  });
}
