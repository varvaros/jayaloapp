import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_reporter.dart';
import 'play_verify_client.dart';

enum CreditPurchaseKind {
  /// El servidor confirmó: el saldo de [CreditPurchaseEvent.balance] es el bueno.
  credited,

  /// Pagó, pero no pudimos confirmarlo todavía. Se reintenta al abrir la app.
  /// ⚠️ El copy NUNCA puede decir que el pago falló.
  pending,

  /// El usuario cerró la hoja de Google. Sin ruido.
  canceled,

  /// Play falló ANTES de cobrar, o el servidor dijo que esta compra no va a
  /// acreditar nunca. Solo se emite cuando consta que no hay dinero en juego.
  failed,
}

class CreditPurchaseEvent {
  const CreditPurchaseEvent(this.kind, {this.balance, this.points});
  final CreditPurchaseKind kind;
  final int? balance;
  final int? points;
}

/// Termina una compra en Google. **En Android "terminar" un consumible es
/// CONSUMIRLO**, no `completePurchase`.
///
/// `completePurchase` solo hace `acknowledgePurchase`
/// (`in_app_purchase_android_platform.dart:191-207`): silencia el reloj de 3
/// días, pero deja el SKU marcado como "ya lo tienes" y el usuario no puede
/// volver a comprar el mismo paquete. `consumeAsync` reconoce Y libera.
Future<void> finishPurchaseOnPlay(PurchaseDetails p) async {
  final addition =
      InAppPurchase.instance.getPlatformAddition<InAppPurchaseAndroidPlatformAddition?>();
  if (addition != null) {
    await addition.consumePurchase(p);
    return;
  }
  if (p.pendingCompletePurchase) {
    await InAppPurchase.instance.completePurchase(p);
  }
}

/// Envuelve `in_app_purchase` y le pone encima la regla del proyecto: **el
/// cliente no acredita nada**. Solo transporta el `purchaseToken` al servidor
/// y actúa según lo que el servidor conteste.
///
/// ⚠️ ORDEN QUE NO SE PUEDE INVERTIR, y que no basta con "no llamar a
/// completePurchase" (así estaba, y estaba mal): `buyConsumable` trae
/// `autoConsume: true` POR DEFECTO, y con ese default el plugin consume la
/// compra dentro del `asyncMap` que alimenta `purchaseStream` — o sea ANTES de
/// que este servicio la vea. Una compra consumida deja de estar "owned" para
/// Google: no la devuelve `queryPurchases`, no se puede reintentar, y como
/// consumir implica acknowledge tampoco la reembolsa a los 3 días. Por eso
/// [buy] pasa `autoConsume: false` y el consumo ocurre en [_finish], DESPUÉS
/// del 200 del servidor.
///
/// `finishPurchase` y `accessToken` se inyectan para poder testear todo el
/// flujo sin el canal de plataforma de Play.
class PlayBillingService {
  PlayBillingService({
    required PlayVerifyClient verifyClient,
    required Future<String?> Function() accessToken,
    required Future<void> Function(PurchaseDetails) finishPurchase,
    InAppPurchase? iap,
  })  : _verify = verifyClient,
        _readAccessToken = accessToken,
        _finish = finishPurchase,
        _iapOrNull = iap;

  final PlayVerifyClient _verify;
  final Future<String?> Function() _readAccessToken;
  final Future<void> Function(PurchaseDetails) _finish;

  // PEREZOSO a propósito: `InAppPurchase.instance` toca el canal de
  // plataforma, que en `flutter test` no existe. Si se resolviera en el
  // constructor, los tests de esta clase reventarían sin haber ejercitado
  // nada. `handlePurchases` no lo necesita.
  InAppPurchase? _iapOrNull;
  InAppPurchase get _iap => _iapOrNull ??= InAppPurchase.instance;

  final _events = StreamController<CreditPurchaseEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Tokens con una verificación en vuelo. `purchaseStream` puede entregar la
  /// misma compra en dos lotes (p. ej. una `restorePurchases` solapada con un
  /// `onPurchasesUpdated`); sin esto se verificaría dos veces y el usuario
  /// vería dos avisos de "Listo".
  final _inFlight = <String>{};

  bool _disposed = false;

  Stream<CreditPurchaseEvent> get events => _events.stream;

  void _emit(CreditPurchaseEvent e) {
    if (_disposed || _events.isClosed) return;
    _events.add(e);
  }

  /// Engancha el stream de Play y **recupera lo que quedó a medias**.
  ///
  /// ⚠️ En Android `purchaseStream` NO re-entrega nada al suscribirse: solo
  /// emite lo que llega por `onPurchasesUpdated`. Las compras de un arranque
  /// anterior hay que pedirlas con `restorePurchases()`, que las emite como
  /// `PurchaseStatus.restored`. (El doc del paquete que promete re-entrega
  /// describe StoreKit.) Sin esta llamada, TODA la maquinaria de `retryable`
  /// del servidor — el 202 del pago diferido, el 502 transitorio, el 401 de
  /// sesión vencida — desemboca en un reintento que no existe.
  Future<void> start() async {
    if (_disposed) return;
    _sub ??= _iap.purchaseStream.listen(handlePurchases);
    try {
      await _iap.restorePurchases();
    } catch (e, s) {
      // Que no haya nada que restaurar, o que el BillingClient no conecte, no
      // puede impedir que la pantalla se monte.
      unawaited(reportError(e, s));
    }
  }

  Future<bool> isAvailable() => _iap.isAvailable();

  /// Devuelve la respuesta ENTERA, no solo la lista: la tienda necesita
  /// `notFoundIDs` para no pintar la tarjeta de un producto que Play no conoce.
  Future<ProductDetailsResponse> loadProducts(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  /// `autoConsume: false` es la línea que sostiene todo el diseño — ver el
  /// aviso de la cabecera de la clase.
  Future<void> buy(ProductDetails product) => _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
        autoConsume: false,
      );

  /// Pública a propósito: es lo que se testea.
  Future<void> handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      // Por elemento: un fallo procesando una compra no puede impedir que se
      // procesen las siguientes del mismo lote (y una de ellas puede estar
      // pagada).
      try {
        await _handleOne(p);
      } catch (e, s) {
        unawaited(reportError(e, s));
      }
    }
  }

  Future<void> _handleOne(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;

    switch (p.status) {
      case PurchaseStatus.pending:
        _emit(const CreditPurchaseEvent(CreditPurchaseKind.pending));
        return;

      case PurchaseStatus.canceled:
        _emit(const CreditPurchaseEvent(CreditPurchaseKind.canceled));
        return;

      case PurchaseStatus.error:
        // ⚠️ `error` NO significa siempre "falló antes de cobrar". El plugin
        // sobrescribe el status a `error` cuando falla el CONSUMO de una
        // compra ya pagada (`in_app_purchase_android_platform.dart:259-267`).
        // Un token no vacío es la señal de que hay una compra de verdad
        // detrás: se verifica como cualquier otra. Anunciar "no se pudo
        // completar la compra" a quien ya pagó, y encima reconocerla (lo que
        // apaga el reembolso automático de Google), es el peor final posible.
        if (token.isEmpty) {
          _emit(const CreditPurchaseEvent(CreditPurchaseKind.failed));
          return;
        }
        await _verifyAndCredit(p);
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        await _verifyAndCredit(p);
        return;
    }
  }

  Future<void> _verifyAndCredit(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;
    if (token.isEmpty) return;
    if (!_inFlight.add(token)) return;
    try {
      await _verifyAndCreditInner(p, token);
    } finally {
      _inFlight.remove(token);
    }
  }

  Future<void> _verifyAndCreditInner(PurchaseDetails p, String token) async {
    final jwt = await _readAccessToken();
    if (jwt == null) {
      // Sin sesión no se puede acreditar a nadie. La compra queda VIVA (no se
      // termina) y se recupera con `restorePurchases` cuando vuelva a entrar.
      _emit(const CreditPurchaseEvent(CreditPurchaseKind.pending));
      return;
    }

    PlayVerifyResult? ok;
    var terminal = false;
    try {
      // En Android `serverVerificationData` ES el purchaseToken.
      ok = await _verify.verify(
        accessToken: jwt,
        purchaseToken: token,
        productId: p.productID,
      );
    } on PlayVerifyException catch (e) {
      terminal = !e.retryable;
      if (!terminal) unawaited(reportError(e, StackTrace.current));
    } catch (e, s) {
      // Cualquier otro fallo (un bug nuestro, un error del parser) se trata
      // como reintentable: la compra NO se consume. Solo un "no" explícito del
      // servidor puede descartar una compra pagada. Se reporta: sin esto, un
      // NoSuchMethodError nuestro se ve igual que Google caído.
      unawaited(reportError(e, s));
    }

    if (ok == null && !terminal) {
      // Transitorio: la compra sigue viva en la cola de Play y `start()` la
      // vuelve a traer en el próximo arranque.
      _emit(const CreditPurchaseEvent(CreditPurchaseKind.pending));
      return;
    }

    // Terminar SIEMPRE va FUERA del try de la verificación: si falla el
    // consumo, eso no puede reetiquetar como "pendiente" un crédito que el
    // servidor ya confirmó.
    if (ok != null) {
      // credited=false significa "este token ya se había acreditado", que
      // también es un final feliz: el balance devuelto es el correcto.
      _emit(CreditPurchaseEvent(
        CreditPurchaseKind.credited,
        balance: ok.balance,
        points: ok.points,
      ));
    } else {
      _emit(const CreditPurchaseEvent(CreditPurchaseKind.failed));
    }

    try {
      await _finish(p);
    } catch (e, s) {
      // Si el consumo falla, Play volverá a entregar la compra y el servidor
      // responderá `credited:false` (es idempotente por token): no hay doble
      // crédito, solo un reintento.
      unawaited(reportError(e, s));
    }
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    _events.close();
  }
}

/// Instancia única, VIVA POR ENCIMA DE LAS PANTALLAS.
///
/// No es comodidad: una compra pagada puede llegar (o volver a llegar) cuando
/// la tienda ya se cerró — el usuario paga y sale, o `restorePurchases()`
/// recupera algo del arranque anterior. Con un servicio por pantalla, ese
/// evento caía en el vacío y la verificación en vuelo moría con el
/// `StreamController` cerrado, saltándose el consumo. Nadie la destruye: vive
/// lo que vive el proceso.
PlayBillingService? _singleton;

PlayBillingService get playBilling => _singleton ??= PlayBillingService(
      verifyClient: PlayVerifyClient(),
      accessToken: () async =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      finishPurchase: finishPurchaseOnPlay,
    );

/// Solo para tests: sustituye la instancia global.
@visibleForTesting
set debugPlayBilling(PlayBillingService? s) => _singleton = s;
