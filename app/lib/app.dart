import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _seed = Color(0xFF7C3AED); // violeta de marca Jayalo

ThemeData jayaloTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      visualDensity: VisualDensity.standard,
    );

class JayaloApp extends StatelessWidget {
  const JayaloApp({super.key, required this.router});
  final GoRouter router;
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Jayalo',
        theme: jayaloTheme(Brightness.light),
        darkTheme: jayaloTheme(Brightness.dark),
        routerConfig: router,
      );
}
