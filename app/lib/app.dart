import 'package:flutter/material.dart';

const _seed = Color(0xFF7C3AED); // violeta de marca Jayalo

ThemeData jayaloTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      visualDensity: VisualDensity.standard,
    );

class JayaloApp extends StatelessWidget {
  const JayaloApp({super.key, required this.home});
  final Widget home;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Jayalo',
        theme: jayaloTheme(Brightness.light),
        darkTheme: jayaloTheme(Brightness.dark),
        home: home,
      );
}
