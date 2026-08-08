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

/// `pendingCompletePurchase` nace en `false` y lo pone a `true` la capa nativa
/// al entregar la compra. Sin marcarlo, el servicio no llamaría a
/// `completePurchase` y los asserts de "se completó" pasarían por vacío.
PurchaseDetails _purchase(String token, PurchaseStatus status,
        {bool pendingComplete = true}) =>
    PurchaseDetails(
      productID: 'creditos_50usd',
      purchaseID: 'p1',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: token,
        source: 'google_play',
      ),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = pendingComplete;

void main() {
  test('una compra purchased se verifica en el servidor y emite éxito', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(verify.seenTokens, ['TOK']);
    expect(events.single.kind, CreditPurchaseKind.credited);
    expect(events.single.balance, 65);
    // Completar SOLO después de que el servidor confirmó: si se completa antes
    // y la verificación falla, Google da la compra por consumida y el crédito
    // se pierde.
    expect(completed, hasLength(1));
  });

  test('si la verificación es reintentable NO se completa la compra', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false),
      error: PlayVerifyException(502, 'caído', retryable: true),
    );
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.pending);
    expect(completed, isEmpty, reason: 'la compra debe seguir viva para reintentar');
  });

  test('si la verificación es TERMINAL se completa y se descarta', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false),
      error: PlayVerifyException(409, 'purchase_not_completed', retryable: false),
    );
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.failed);
    expect(completed, hasLength(1));
  });

  // Un fallo que no sea PlayVerifyException (un bug nuestro, un error del
  // parser) NO puede consumir una compra pagada ni escapar del listener del
  // stream de Play.
  test('un error inesperado se trata como pendiente, no como fallo', () async {
    final verify = _FakeVerify(
      const PlayVerifyResult(balance: 0, points: 0, credited: false),
      error: StateError('boom'),
    );
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.pending);
    expect(completed, isEmpty);
  });

  test('sin sesión no se verifica y la compra queda viva', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false));
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => null,
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(verify.seenTokens, isEmpty);
    expect(events.single.kind, CreditPurchaseKind.pending);
    expect(completed, isEmpty);
  });

  test('una compra cancelada por el usuario no llama al servidor', () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false));
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (_) async {},
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.canceled)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(verify.seenTokens, isEmpty);
    expect(events.single.kind, CreditPurchaseKind.canceled);
  });

  test('credited=false (ya acreditada antes) se trata como éxito y se completa',
      () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 0, credited: false));
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    final events = <CreditPurchaseEvent>[];
    svc.events.listen(events.add);

    await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(events.single.kind, CreditPurchaseKind.credited);
    expect(completed, hasLength(1));
  });

  test('una compra ya completada por la plataforma no se vuelve a completar',
      () async {
    final verify =
        _FakeVerify(const PlayVerifyResult(balance: 65, points: 55, credited: true));
    final completed = <PurchaseDetails>[];
    final svc = PlayBillingService(
      verifyClient: verify,
      accessToken: () async => 'JWT',
      completePurchase: (p) async => completed.add(p),
    );

    await svc.handlePurchases(
        [_purchase('TOK', PurchaseStatus.purchased, pendingComplete: false)]);
    // El broadcast entrega en un microtask: sin drenar la cola, los asserts
    // sobre la lista de eventos correrian antes de que llegue el evento.
    await pumpEventQueue();

    expect(completed, isEmpty);
  });
}
