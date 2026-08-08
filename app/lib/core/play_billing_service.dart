import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'play_verify_client.dart';

enum CreditPurchaseKind {
  /// El servidor confirmó: el saldo de [CreditPurchaseEvent.balance] es el bueno.
  credited,

  /// Pagó, pero no pudimos confirmarlo todavía. Se reintenta al abrir la app.
  /// ⚠️ El copy NUNCA puede decir que el pago falló.
  pending,

  /// El usuario cerró la hoja de Google. Sin ruido.
  canceled,

  /// Play devolvió error antes de cobrar, o el servidor dijo que esta compra
  /// no va a acreditar nunca.
  failed,
}

class CreditPurchaseEvent {
  const CreditPurchaseEvent(this.kind, {this.balance, this.points});
  final CreditPurchaseKind kind;
  final int? balance;
  final int? points;
}

/// Envuelve `in_app_purchase` y le pone encima la regla del proyecto: **el
/// cliente no acredita nada**. Solo transporta el `purchaseToken` al servidor
/// y actúa según lo que el servidor conteste.
///
/// `completePurchase` y `accessToken` se inyectan para poder testear todo el
/// flujo sin el canal de plataforma de Play.
class PlayBillingService {
  PlayBillingService({
    required PlayVerifyClient verifyClient,
    required Future<String?> Function() accessToken,
    required Future<void> Function(PurchaseDetails) completePurchase,
    InAppPurchase? iap,
  })  : _verify = verifyClient,
        _readAccessToken = accessToken,
        _complete = completePurchase,
        _iapOrNull = iap;

  final PlayVerifyClient _verify;
  final Future<String?> Function() _readAccessToken;
  final Future<void> Function(PurchaseDetails) _complete;

  // PEREZOSO a propósito: `InAppPurchase.instance` toca el canal de
  // plataforma, que en `flutter test` no existe. Si se resolviera en el
  // constructor, los tests de esta clase reventarían sin haber ejercitado
  // nada. `handlePurchases` no lo necesita.
  InAppPurchase? _iapOrNull;
  InAppPurchase get _iap => _iapOrNull ??= InAppPurchase.instance;

  final _events = StreamController<CreditPurchaseEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Stream<CreditPurchaseEvent> get events => _events.stream;

  /// Engancha el stream de Play. Debe llamarse ANTES de comprar: las compras
  /// que quedaron a medias en un arranque anterior se re-entregan aquí.
  Future<void> start() async {
    _sub ??= _iap.purchaseStream.listen(handlePurchases);
  }

  Future<bool> isAvailable() => _iap.isAvailable();

  /// Devuelve la respuesta ENTERA, no solo la lista: la tienda necesita
  /// `notFoundIDs` para no pintar la tarjeta de un producto que Play no conoce.
  Future<ProductDetailsResponse> loadProducts(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  Future<void> buy(ProductDetails product) =>
      _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));

  /// Pública a propósito: es lo que se testea.
  Future<void> handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(const CreditPurchaseEvent(CreditPurchaseKind.pending));
          break;

        case PurchaseStatus.canceled:
          _events.add(const CreditPurchaseEvent(CreditPurchaseKind.canceled));
          if (p.pendingCompletePurchase) await _complete(p);
          break;

        case PurchaseStatus.error:
          _events.add(const CreditPurchaseEvent(CreditPurchaseKind.failed));
          if (p.pendingCompletePurchase) await _complete(p);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndCredit(p);
          break;
      }
    }
  }

  Future<void> _verifyAndCredit(PurchaseDetails p) async {
    final jwt = await _readAccessToken();
    if (jwt == null) {
      // Sin sesión no se puede acreditar a nadie. La compra queda VIVA (no se
      // completa) y se reintenta cuando el usuario vuelva a entrar.
      _events.add(const CreditPurchaseEvent(CreditPurchaseKind.pending));
      return;
    }

    try {
      final res = await _verify.verify(
        accessToken: jwt,
        // En Android `serverVerificationData` ES el purchaseToken.
        purchaseToken: p.verificationData.serverVerificationData,
        productId: p.productID,
      );
      // credited=false significa "este token ya se había acreditado", que
      // también es un final feliz: el balance devuelto es el correcto.
      _events.add(CreditPurchaseEvent(
        CreditPurchaseKind.credited,
        balance: res.balance,
        points: res.points,
      ));
      // Completar SOLO ahora. Antes de la confirmación del servidor,
      // completar consume la compra en Google y el crédito se perdería.
      if (p.pendingCompletePurchase) await _complete(p);
    } on PlayVerifyException catch (e) {
      if (e.retryable) {
        // No se completa: la compra sigue en la cola de Play y se vuelve a
        // entregar al abrir la app.
        _events.add(const CreditPurchaseEvent(CreditPurchaseKind.pending));
      } else {
        _events.add(const CreditPurchaseEvent(CreditPurchaseKind.failed));
        if (p.pendingCompletePurchase) await _complete(p);
      }
    } catch (_) {
      // Cualquier otro fallo (un bug nuestro, un error del parser) se trata
      // como pendiente: la compra NO se consume y el error no escapa del
      // listener de `purchaseStream`, donde nadie lo atraparía. Solo un "no"
      // explícito del servidor puede descartar una compra.
      _events.add(const CreditPurchaseEvent(CreditPurchaseKind.pending));
    }
  }

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
