import 'package:flutter/material.dart';
import '../../client/request_status_screen.dart' show fmtRD;

/// Disclaimer de bienvenida (1 vez por conversación).
Future<void> showWelcomeDialog(BuildContext context,
    {required String title, required String body, required String buttonLabel}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body, style: const TextStyle(fontSize: 14, height: 1.4))),
      actions: [
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(buttonLabel)),
      ],
    ),
  );
}

/// Hoja "Detalles del acuerdo".
void showAgreementDetails(BuildContext context, Map<String, dynamic> conv,
    {required String? peerName, required bool isProvider}) {
  final price = conv['agreed_price'] != null
      ? fmtRD(conv['agreed_price'] as num)
      : conv['agreed_hourly_rate'] != null
          ? '${fmtRD(conv['agreed_hourly_rate'] as num)}/h'
              '${conv['agreed_estimated_hours'] != null ? ' · ${conv['agreed_estimated_hours']} h estimadas' : ''}'
          : 'Sin precio fijo';
  final status = switch (conv['status'] as String) {
    'abierto' => 'Abierto',
    'cerrado' => 'Completado',
    _ => 'No concretado',
  };
  Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Flexible(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      ]));
  showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Detalles del acuerdo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (conv['product_image_url'] != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(conv['product_image_url'] as String,
                        height: 140, width: double.infinity, fit: BoxFit.cover)),
              const SizedBox(height: 8),
              row('Producto / servicio', conv['product_name'] as String? ?? '—'),
              row('Precio acordado', price),
              if (conv['request_title'] != null) row('Solicitud', conv['request_title'] as String),
              if (peerName != null) row(isProvider ? 'Cliente' : 'Proveedor', peerName),
              row('Estado', status),
              row('Iniciado', (conv['created_at'] as String).substring(0, 10)),
            ]),
          )));
}

/// Confirmación "¿Marcar como completado?". Devuelve true si confirma.
Future<bool> showCompleteDialog(BuildContext context) async =>
    (await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.check_circle_outline, size: 40),
              title: const Text('¿Marcar como completado?', textAlign: TextAlign.center),
              content: const Text(
                  'Al marcar como completado, el cliente podrá calificarte como proveedor. El chat quedará cerrado.',
                  textAlign: TextAlign.center),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Sí, marcar como completado')),
              ],
            ))) ??
    false;

const _reportReasons = [
  ('estafa', 'Estafa o intento de fraude'),
  ('no_cumplio', 'No cumplió con lo acordado'),
  ('acoso', 'Lenguaje ofensivo o acoso'),
  ('spam', 'Spam o publicidad'),
  ('falso', 'Producto/servicio falso o engañoso'),
  ('inapropiado', 'Contenido inapropiado'),
  ('otro', 'Otro'),
];

/// Denunciar cuenta. Devuelve (reason, details) o null si cancela.
Future<(String, String?)?> showReportDialog(BuildContext context, {String? reportedName}) {
  String? reason;
  final details = TextEditingController();
  return showDialog<(String, String?)?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
              title: Text('Denunciar ${reportedName ?? 'cuenta'}'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final (v, label) in _reportReasons)
                  RadioListTile<String>(
                      dense: true,
                      value: v,
                      // ignore: deprecated_member_use
                      groupValue: reason,
                      title: Text(label, style: const TextStyle(fontSize: 13)),
                      // ignore: deprecated_member_use
                      onChanged: (x) => setState(() => reason = x)),
                TextField(
                    controller: details,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: InputDecoration(
                        hintText: reason == 'otro'
                            ? 'Describe el problema (mínimo 10 caracteres)…'
                            : 'Detalles (opcional)…')),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancelar')),
                FilledButton(
                    onPressed: reason == null ||
                            (reason == 'otro' && details.text.trim().length < 10)
                        ? null
                        : () => Navigator.of(ctx).pop((reason!, details.text)),
                    child: const Text('Enviar denuncia')),
              ],
            )),
  );
}
