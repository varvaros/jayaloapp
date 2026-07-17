/// Decisión de recarga (ADR-0031): los créditos son el cobro por acceder a un
/// lead real — la app NUNCA procesa pagos; recargar abre el wallet web en el
/// navegador del sistema (AppConfig.walletUrl).
///
/// `balance == null` = wallet aún no cargada o inexistente → tratar como sin
/// saldo (nunca dejar pasar a un cobro sin saldo confirmado).
bool shouldOfferRecharge({required int? balance, required int cost}) =>
    balance == null || balance < cost;
