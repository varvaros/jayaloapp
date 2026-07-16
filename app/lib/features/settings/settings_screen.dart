import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.person_outline), title: Text(email)),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Términos y privacidad'),
          onTap: () => launchUrl(Uri.parse('https://jayalo.com/terminos'),
              mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          onTap: () => Supabase.instance.client.auth.signOut(),
        ),
      ]),
    );
  }
}
