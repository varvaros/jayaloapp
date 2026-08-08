import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:jayalo_app/core/play_billing_service.dart';
import 'package:jayalo_app/core/play_verify_client.dart';

/// Doble de `PlayVerifyClient` que registra lo que recibió.
class _FakeVerify implements PlayVerifyClient {
  _FakeVerify(this._result, {this.error});
  final PlayVerifyResult _result;
  final Object? error;
  final List<String> seenTokens = [];

  // `implements` basta: el único miembro PÚBLICO de PlayVerifyClient es
  // `verify` (el campo `_http` es privado de su librería, así que no forma
  // parte de la interfaz). No hace falta noSuchMethod.
  @override
  Future<PlayVerifyResult> verify({
    required String accessToken,
    required String purchaseToken,
    required String productId,
  }) async {
    seenTokens.add(purchaseToken);
    if (error != null) throw error!;
    return _result;
  }
}

class _GatedVerify implements PlayVerifyClient {
  _GatedVerify(this.gate);
  final Future<PlayVerifyResult> gate;
  @override
  Future<PlayVerifyResult> verify({
    required String accessToken,
    required String purchaseToken,
    required String productId,
  }) =>
      gate;
}

/// Doble de `InAppPurchase` para observar los dos parámetros de los que depende
/// que no se pierda dinero: `autoConsume` y la llamada a `restorePurchases`.
class _FakeIap implements InAppPurchase {
  bool? autoConsumeVisto;
  bool restoreLlamado = false;

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    autoConsumeVisto = autoConsume;
    return true;
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      const Stream<List<PurchaseDetails>>.empty();

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreLlamado = true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Compra VIVA: la que el plugin entrega tras un cobro real. Lleva token, y
/// `pendingCompletePurchase` lo pone la capa Android a `!isAcknowledged`.
PurchaseDetails _purchase(String token, PurchaseStatus status) => PurchaseDetails(
      productID: 'creditos_50usd',
      purchaseID: 'p1',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: token,
        source: 'google_play',
      ),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = true;

/// Compra SINTÉTICA: la que fabrica el plugin cuando NO hay compra detrás
/// (cancelación, error previo al cobro). Token y productID vacíos. Es la única
/// forma de "error" en la que consta que no hubo dinero.
PurchaseDetails _sintetica(PurchaseStatus status) => PurchaseDetails(
      productID: '',
      purchaseID: '',
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'google_play',
      ),
      transactionDate: null,
      status: status,
    );

ProductDetails _producto(String id) => ProductDetails(
      id: id,
      title: 'Paquete',
      description: '',
      price: 'RD\$650.00',
      rawPrice: 650,
      currencyCode: 'DOP',
    );

void main() {
  test('una compra purchased se verifica en el servidor y emite éxito', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrían antes de que llegue el evento.
    await pumpEventQueue();

    expect(verify.seenTokens, ['TOK']);
    expect(events.single.kind, CreditPurchaseKind.credited);
    expect(events.single.balance, 65);
    // Terminar (= consumir en Play) SOLO después de que el servidor confirmó.
    expect(finished, hasLength(1));
  });

  test('si la verificación es reintentable NO se termina la compra', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false),
      error: PlayVerifyException(502, 'caído', retryable: true),
    );
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.pending);
    expect(finished, isEmpty, reason: 'la compra debe seguir viva para reintentar');
  });

  test('si la verificación es TERMINAL se termina y se descarta', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false),
      error: PlayVerifyException(409, 'purchase_not_completed', retryable: false),
    );
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.failed);
    expect(finished, hasLength(1));
  });

  // Un fallo que no sea PlayVerifyException (un bug nuestro, un error del
  // parser) NO puede consumir una compra pagada.
  test('un error inesperado se trata como pendiente, no como fallo', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false),
      error: StateError('boom'),
    );
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.pending);
    expect(finished, isEmpty);
  });

  test('sin sesión no se verifica y la compra queda viva', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false));
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => null,
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    await pumpEventQueue();

    expect(verify.seenTokens, isEmpty);
    expect(events.single.kind, CreditPurchaseKind.pending);
    expect(finished, isEmpty);
  });

  test('una compra cancelada por el usuario no llama al servidor', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false));
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_sintetica(PurchaseStatus.canceled)]);
    await pumpEventQueue();

    expect(verify.seenTokens, isEmpty);
    expect(events.single.kind, CreditPurchaseKind.canceled);
    expect(finished, isEmpty);
  });

  test('credited=false (ya acreditada antes) se trata como éxito y se termina',
      () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 0, credited: false));
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.credited);
    expect(finished, hasLength(1));
  });

  // ── Lo que destaparon las revisiones ──────────────────────────────────────

  // C1: `buyConsumable` trae `autoConsume: true` POR DEFECTO, y con ese default
  // el plugin consume el token ANTES de que este servicio vea la compra. Todo
  // el diseño ("no terminar ⇒ la compra sigue viva para reintentar") es
  // ficticio si esta línea se revierte.
  test('comprar NO deja que el plugin consuma antes de verificar', () async {
    final iap = _FakeIap();
    final svc = PlayBillingService(
      verifyClient:
          _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false)),
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
      iap: iap,
    );

    await svc.buy(_producto('creditos_50usd'));

    expect(iap.autoConsumeVisto, isFalse,
        reason: 'con autoConsume:true, un 502 reintentable deja la compra pagada '
            'sin crédito y sin nada que reintentar');
  });

  // C2: en Android `purchaseStream` NO re-entrega nada al suscribirse. Sin
  // `restorePurchases`, TODA rama `retryable` del contrato del servidor
  // desemboca en un reintento que no existe.
  test('start() pide a Play las compras que quedaron a medias', () async {
    final iap = _FakeIap();
    final svc = PlayBillingService(
      verifyClient:
          _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false)),
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
      iap: iap,
    );

    await svc.start();

    expect(iap.restoreLlamado, isTrue,
        reason: 'sin esto, un pago diferido no se acredita nunca');
  });

  // C3: el plugin sobrescribe el status a `error` cuando falla el CONSUMO de
  // una compra YA PAGADA. Anunciarle "no se pudo completar la compra" a quien
  // pagó, y encima reconocerla (lo que apaga el reembolso de los 3 días), es el
  // peor final posible.
  test('un error CON token se verifica, no se anuncia como fallo', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.error)]);
    await pumpEventQueue();

    expect(verify.seenTokens, ['TOK']);
    expect(events.single.kind, CreditPurchaseKind.credited);
    expect(finished, hasLength(1));
  });

  test('un error SIN token sí es un fallo previo al cobro', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false));
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_sintetica(PurchaseStatus.error)]);
    await pumpEventQueue();

    expect(verify.seenTokens, isEmpty);
    expect(events.single.kind, CreditPurchaseKind.failed);
    expect(finished, isEmpty);
  });

  test('un fallo al terminar no degrada el crédito ya confirmado', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (_) async => throw StateError('canal caído'),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    await pumpEventQueue();

    expect(events.map((e) => e.kind), [CreditPurchaseKind.credited],
        reason: 'el servidor ya acreditó: un fallo al consumir no lo vuelve dudoso');
  });

  test('un fallo procesando una compra no se come el resto del lote', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (p) async {
        if (p.verificationData.serverVerificationData == 'A') {
          throw StateError('canal caído');
        }
      },
    );
    svc.events.listen((_) {});

    await svc.handlePurchases([
      _purchase('A', PurchaseStatus.purchased),
      _purchase('B', PurchaseStatus.purchased),
    ]);
    await pumpEventQueue();

    expect(verify.seenTokens, ['A', 'B'],
        reason: 'la compra pagada del final del lote no se puede perder');
  });

  test('el mismo token no se verifica dos veces a la vez', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
    );
    svc.events.listen((_) {});

    // `restorePurchases` solapada con `onPurchasesUpdated`: la misma compra en
    // dos lotes concurrentes.
    await Future.wait([
      svc.handlePurchases([_purchase('TOK', PurchaseStatus.restored)]),
      svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]),
    ]);
    await pumpEventQueue();

    expect(verify.seenTokens, ['TOK']);
  });

  test('emitir tras dispose no lanza ni impide terminar la compra', () async {
    final gate = Completer<PlayVerifyResult>();
    final finished = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: _GatedVerify(gate.future),
      accessToken: () async => 'JWT',
      finishPurchase: (p) async => finished.add(p),
    );
    svc.events.listen((_) {});

    final enVuelo = svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    await pumpEventQueue();
    svc.dispose(); // el usuario sale de la pantalla
    gate.complete(const PlayVerifyResult(balance: 65, points: 55, credited: true));

    await expectLater(enVuelo, completes);
    expect(finished, hasLength(1),
        reason: 'el servidor confirmó: hay que cerrarla con Google igual');
  });
}
