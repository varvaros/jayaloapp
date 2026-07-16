import 'package:supabase_flutter/supabase_flutter.dart';

final supa = Supabase.instance.client;

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
