import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:jayalo_app/core/play_billing_service.dart';
import 'package:jayalo_app/core/play_verify_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Session, User;

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
  _FakeIap({this.buyResult = true});

  /// Lo que devuelve `launchBillingFlow`: `false` significa que la hoja de
  /// Google NO se abrió (p. ej. ITEM_ALREADY_OWNED) — el plugin NO lanza.
  final bool buyResult;
  bool? autoConsumeVisto;
  bool restoreLlamado = false;

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    autoConsumeVisto = autoConsume;
    return buyResult;
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

  // Important de la revisión de la tienda: `restorePurchases()` puede
  // entregar una compra VIEJA justo cuando el usuario tiene la hoja de Google
  // abierta para otra. Si su evento es indistinguible del de la compra en
  // curso, la pantalla suelta el spinner y pinta "Listo" detrás de la hoja —
  // y el usuario cancela un pago real creyendo que ya compró. El origen tiene
  // que viajar en el evento.
  group('fromRestore', () {
    test('una compra restaurada acreditada viene marcada', () async {
      final svc = PlayBillingService(
        verifyClient: _FakeVerify(
            const PlayVerifyResult(balance: 65, points: 55, credited: true)),
        accessToken: () async => 'JWT',
        finishPurchase: (_) async {},
      );
      final events = <CreditPurchaseEvent>[];
      svc.events.listen(events.add);

      await svc.handlePurchases([_purchase('TOK', PurchaseStatus.restored)]);
      await pumpEventQueue();

      expect(events.single.kind, CreditPurchaseKind.credited);
      expect(events.single.fromRestore, isTrue);
    });

    // El camino del `pending` pasa por `_verifyAndCredit`, no por el switch
    // de estados: el marcado tiene que sobrevivir también ahí.
    test('una restaurada con verificación reintentable marca el pending', () async {
      final svc = PlayBillingService(
        verifyClient: _FakeVerify(
          const PlayVerifyResult(balance: 0, points: 0, credited: false),
          error: PlayVerifyException(502, 'caído', retryable: true),
        ),
        accessToken: () async => 'JWT',
        finishPurchase: (_) async {},
      );
      final events = <CreditPurchaseEvent>[];
      svc.events.listen(events.add);

      await svc.handlePurchases([_purchase('TOK', PurchaseStatus.restored)]);
      await pumpEventQueue();

      expect(events.single.kind, CreditPurchaseKind.pending);
      expect(events.single.fromRestore, isTrue);
    });

    test('la compra en curso NO viene marcada', () async {
      final svc = PlayBillingService(
        verifyClient: _FakeVerify(
            const PlayVerifyResult(balance: 65, points: 55, credited: true)),
        accessToken: () async => 'JWT',
        finishPurchase: (_) async {},
      );
      final events = <CreditPurchaseEvent>[];
      svc.events.listen(events.add);

      await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(events.single.fromRestore, isFalse,
          reason: 'el desenlace de la compra en curso SÍ debe soltar el '
              'spinner de la tienda');
    });
  });

  // Minor de la revisión de la tarea 10: sin el producto en el evento, el
  // desenlace de un pago DIFERIDO de otra compra (que Google confirma en
  // segundo plano y llega como `purchased`, no como restaurada) soltaría el
  // spinner de la compra que tiene la hoja abierta. La tienda necesita saber
  // DE QUÉ producto es cada evento.
  group('productId en el evento', () {
    test('la compra verificada lleva su productId', () async {
      final svc = PlayBillingService(
        verifyClient: _FakeVerify(
            const PlayVerifyResult(balance: 65, points: 55, credited: true)),
        accessToken: () async => 'JWT',
        finishPurchase: (_) async {},
      );
      final events = <CreditPurchaseEvent>[];
      svc.events.listen(events.add);

      await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(events.single.productId, 'creditos_50usd');
    });

    test('el pending de una verificación reintentable también lo lleva', () async {
      final svc = PlayBillingService(
        verifyClient: _FakeVerify(
          const PlayVerifyResult(balance: 0, points: 0, credited: false),
          error: PlayVerifyException(502, 'caído', retryable: true),
        ),
        accessToken: () async => 'JWT',
        finishPurchase: (_) async {},
      );
      final events = <CreditPurchaseEvent>[];
      svc.events.listen(events.add);

      await svc.handlePurchases([_purchase('TOK', PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(events.single.kind, CreditPurchaseKind.pending);
      expect(events.single.productId, 'creditos_50usd');
    });

    test('los eventos sintéticos (sin compra detrás) van sin productId', () async {
      final svc = PlayBillingService(
        verifyClient: _FakeVerify(
            const PlayVerifyResult(balance: 0, points: 0, credited: false)),
        accessToken: () async => 'JWT',
        finishPurchase: (_) async {},
      );
      final events = <CreditPurchaseEvent>[];
      svc.events.listen(events.add);

      await svc.handlePurchases([_sintetica(PurchaseStatus.canceled)]);
      await pumpEventQueue();

      expect(events.single.productId, isNull,
          reason: 'la cancelación de la hoja es del flujo vivo: la tienda debe '
              'poder soltar el spinner con ella aunque no traiga producto');
    });
  });

  // C-2 de la revisión de la tienda: `buyConsumable` NO lanza cuando
  // `launchBillingFlow` falla — devuelve `false` (el caso típico es
  // ITEM_ALREADY_OWNED, justo el estado que deja una compra sin consumir).
  // Con `buy` tipado `Future<void>` ese `false` se perdía y el spinner de la
  // tienda se quedaba girando para siempre.
  test('buy propaga el false de una hoja de pago que no se abrió', () async {
    final iap = _FakeIap(buyResult: false);
    final svc = PlayBillingService(
      verifyClient:
          _FakeVerify(const PlayVerifyResult(balance: 0, points: 0, credited: false)),
      accessToken: () async => 'JWT',
      finishPurchase: (_) async {},
      iap: iap,
    );

    expect(await svc.buy(_producto('creditos_50usd')), isFalse,
        reason: 'si la hoja no se abre, el stream no va a emitir nada: '
            'la pantalla necesita este false para soltar el spinner');
  });

  // ── C-1 de la revisión de la tienda: la recuperación al arrancar dependía
  // de que `currentSession` ya estuviera recuperada en `initState` (una
  // carrera), y si el usuario iniciaba sesión DESPUÉS de abrir la app, nadie
  // volvía a llamar a `start()`: una compra a medias no se acreditaba hasta
  // que el usuario entrara a la tienda por su cuenta.
  group('watchAuth', () {
    PlayBillingService svcCon(_FakeIap iap) => PlayBillingService(
          verifyClient: _FakeVerify(
              const PlayVerifyResult(balance: 0, points: 0, credited: false)),
          accessToken: () async => 'JWT',
          finishPurchase: (_) async {},
          iap: iap,
        );

    Session sesion() => Session(
          accessToken: 'jwt',
          tokenType: 'bearer',
          user: const User(
            id: 'u1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01T00:00:00Z',
          ),
        );

    test('al iniciar sesión arranca la recuperación de compras', () async {
      final iap = _FakeIap();
      final svc = svcCon(iap);
      final auth = StreamController<AuthState>();
      addTearDown(auth.close);

      svc.watchAuth(auth.stream);
      expect(iap.restoreLlamado, isFalse,
          reason: 'sin sesión todavía no hay a quién acreditar');

      auth.add(AuthState(AuthChangeEvent.signedIn, sesion()));
      await pumpEventQueue();

      expect(iap.restoreLlamado, isTrue,
          reason: 'instalar → abrir sin sesión → iniciar sesión → comprar: '
              'sin este rearranque la compra a medias no se recupera nunca '
              'desde el arranque, solo si el usuario abre la tienda');
    });

    // La carrera del arranque en frío: `Supabase.initialize` no espera a
    // `recoverSession()`, así que el guard de `currentSession == null` salta
    // aunque HAYA sesión guardada. `initialSession` con sesión es el aviso de
    // que la recuperación terminó.
    test('initialSession CON sesión también arranca', () async {
      final iap = _FakeIap();
      final svc = svcCon(iap);
      final auth = StreamController<AuthState>();
      addTearDown(auth.close);

      svc.watchAuth(auth.stream);
      auth.add(AuthState(AuthChangeEvent.initialSession, sesion()));
      await pumpEventQueue();

      expect(iap.restoreLlamado, isTrue);
    });

    test('initialSession SIN sesión no arranca nada', () async {
      final iap = _FakeIap();
      final svc = svcCon(iap);
      final auth = StreamController<AuthState>();
      addTearDown(auth.close);

      svc.watchAuth(auth.stream);
      auth.add(AuthState(AuthChangeEvent.initialSession, null));
      await pumpEventQueue();

      expect(iap.restoreLlamado, isFalse,
          reason: 'restaurar sin sesión solo produce verificaciones que van '
              'a morir en el guard del JWT');
    });

    test('un refresh de token no re-dispara la restauración', () async {
      final iap = _FakeIap();
      final svc = svcCon(iap);
      final auth = StreamController<AuthState>();
      addTearDown(auth.close);

      svc.watchAuth(auth.stream);
      auth.add(AuthState(AuthChangeEvent.tokenRefreshed, sesion()));
      await pumpEventQueue();

      expect(iap.restoreLlamado, isFalse,
          reason: 'el refresh es ~cada hora: restaurar en cada uno haría '
              'reaparecer el aviso de "estamos confirmando" de una compra '
              'atascada una y otra vez');
    });
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
