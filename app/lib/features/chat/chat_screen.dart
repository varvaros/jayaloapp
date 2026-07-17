import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
}
