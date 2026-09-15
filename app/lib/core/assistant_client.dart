import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Fallo del mando del asistente.
///
/// [cost] y [balance] solo vienen poblados en el 402 de saldo insuficiente; el
/// servidor los manda ahí a propósito, para que la app pueda decir cuánto falta
/// sin una segunda llamada.
class AssistantException implements Exception {
  AssistantException(this.status, this.message, {this.cost, this.balance});

  final int status;
  final String message;
  final int? cost;
  final int? balance;

  /// El único caso que la interfaz trata distinto: en vez de un aviso seco,
  /// lleva a la tienda de créditos.
  bool get sinSaldo => status == 402;

  @override
  String toString() => 'AssistantException($status): $message';
}

/// Estado del asistente en una conversación.
///
/// [enabled] es el interruptor maestro del panel del proveedor (en la WEB). Con
/// él apagado el motor NO responde, así que la barra no puede decir «activo»
/// aunque [active] sea true — ver `assistant_bar_view.dart`.
class AssistantState {
  const AssistantState({
    required this.active,
    required this.paused,
    required this.handoverRequested,
    required this.enabled,
    required this.perChatCost,
  });

  final bool active;
  final bool paused;
  final bool handoverRequested;
  final bool enabled;

  /// Lo que cuesta activar en ESTE chat. Viene del servidor en cada llamada:
  /// el admin lo cambia desde `/admin/assistant` y el APK repartido no se puede
  /// actualizar, así que un literal aquí mentiría para siempre.
  final int perChatCost;
}

class ActivateResult {
  const ActivateResult({
    required this.charged,
    required this.billingMode,
    this.balance,
    this.alreadyActive = false,
  });
  final int charged;
  final String billingMode; // 'per_chat' | 'monthly'
  final int? balance;
  final bool alreadyActive;
}

class ReplyResult {
  const ReplyResult({required this.sent, this.reason});
  final bool sent;
  final String? reason;
}

class SubscriptionInfo {
  const SubscriptionInfo({required this.activeUntil, required this.monthlyCost});
  final DateTime? activeUntil;
  final int monthlyCost;
}

class SubscribeResult {
  const SubscribeResult({required this.charged, required this.expiresAt});
  final int charged;
  final DateTime expiresAt;
}

/// Mando del asistente de ventas. Mismo patrón que `EditorLinkClient`:
/// Origin + Bearer del JWT de sesión, `http.Client` inyectable.
class AssistantClient {
  AssistantClient({http.Client? inner, Duration? timeout})
      : _http = inner ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 25);

  final http.Client _http;

  /// Sin esto, una conexión colgada deja la barra en «cargando» para siempre.
  /// 25 s y no 10: `activate` genera la PRIMERA respuesta del bot antes de
  /// contestar, y eso pasa por el proveedor de IA.
  final Duration _timeout;

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body,
    String accessToken,
  ) async {
    final res = await _http
        .post(
          Uri.parse(AppConfig.assistantEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'Origin': AppConfig.siteUrl,
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    // Un 502 de Cloudflare llega como HTML: decodificarlo a ciegas reventaría
    // con FormatException en vez de con el fallo que de verdad ocurrió.
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      parsed = const {};
    }

    if (res.statusCode != 200) {
      throw AssistantException(
        res.statusCode,
        parsed['error']?.toString() ?? 'No se pudo completar la acción.',
        cost: parsed['cost'] as int?,
        balance: parsed['balance'] as int?,
      );
    }
    return parsed;
  }

  Future<AssistantState> state({
    required String conversationId,
    required String accessToken,
  }) async {
    final m = await _post(
        {'action': 'state', 'conversation_id': conversationId}, accessToken);
    return AssistantState(
      active: m['active'] == true,
      paused: m['paused'] == true,
      handoverRequested: m['handoverRequested'] == true,
      enabled: m['enabled'] == true,
      perChatCost: (m['perChatCost'] as num?)?.toInt() ?? 0,
    );
  }

  Future<ActivateResult> activate({
    required String conversationId,
    required String accessToken,
    String? businessId,
  }) async {
    final m = await _post({
      'action': 'activate',
      'conversation_id': conversationId,
      'business_id': ?businessId,
    }, accessToken);
    return ActivateResult(
      charged: (m['charged'] as num?)?.toInt() ?? 0,
      billingMode: m['billing_mode']?.toString() ?? 'per_chat',
      balance: (m['balance'] as num?)?.toInt(),
      alreadyActive: m['already_active'] == true,
    );
  }

  Future<void> pause({
    required String conversationId,
    required bool paused,
    required String accessToken,
  }) async {
    await _post({
      'action': 'pause',
      'conversation_id': conversationId,
      'paused': paused,
    }, accessToken);
  }

  /// Enciende el interruptor maestro del negocio de esta conversación.
  ///
  /// No cobra: el chat ya se pagó al activarlo. Existe para que el proveedor no
  /// tenga que abrir la web cuando el maestro está apagado.
  Future<void> enable({
    required String conversationId,
    required String accessToken,
  }) async {
    await _post(
        {'action': 'enable', 'conversation_id': conversationId}, accessToken);
  }

  Future<ReplyResult> reply({
    required String conversationId,
    required String accessToken,
  }) async {
    final m = await _post(
        {'action': 'reply', 'conversation_id': conversationId}, accessToken);
    return ReplyResult(
      sent: m['sent'] == true,
      reason: m['reason']?.toString(),
    );
  }

  Future<SubscriptionInfo> subscription({
    required String businessId,
    required String accessToken,
  }) async {
    final m = await _post(
        {'action': 'subscription', 'business_id': businessId}, accessToken);
    final until = m['monthly_active_until']?.toString();
    return SubscriptionInfo(
      activeUntil: until == null ? null : DateTime.parse(until),
      monthlyCost: (m['monthlyCost'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SubscribeResult> subscribe({
    required String businessId,
    required String accessToken,
  }) async {
    final m = await _post(
        {'action': 'subscribe', 'business_id': businessId}, accessToken);
    return SubscribeResult(
      charged: (m['charged'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.parse(m['expires_at'].toString()),
    );
  }
}
