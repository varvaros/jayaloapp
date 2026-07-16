import 'package:supabase_flutter/supabase_flutter.dart';

final supa = Supabase.instance.client;

/// Insert de solicitud — campos EXACTOS de la web (requests/new.tsx L541-570),
/// camino sin fotos (v1). `categories`/`rubros` vienen del turno `routing`.
Future<void> submitRequest({
  required String title,
  required List<String> bullets,
  required String kind, // 'producto' | 'servicio'
  required bool wholesale,
  required List<String> categories,
  required List<String> rubros,
}) async {
  final uid = supa.auth.currentUser!.id;
  final isService = kind == 'servicio';
  await supa.from('customer_requests').insert({
    'user_id': uid,
    'kind': kind,
    'title': title,
    'description': bullets.join(' • '),
    'bullets': bullets,
    'image_url': '',
    'image_urls': <String>[],
    'image_thumb_url': null,
    'with_shipping': false,
    'with_installation': false,
    'requires_evaluation': false,
    'condition': '',
    'urgency': 'normal',
    'status': 'open',
    'target_categories': categories,
    'target_rubros': rubros,
    'service_modality': '',
    'service_event_date': null,
    'urgency_level': '',
    'budget_min': null,
    'budget_max': null,
    'is_recurring': false,
    'recurrence_note': '',
    'is_wholesale': !isService && wholesale,
    'target_business_id': null,
  });
}

Future<bool> isProviderAccount() async {
  final uid = supa.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await supa
      .from('profiles')
      .select('account_type')
      .eq('user_id', uid)
      .maybeSingle();
  return row?['account_type'] == 'provider';
}
