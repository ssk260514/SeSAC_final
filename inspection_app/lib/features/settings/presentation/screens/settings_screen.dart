import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정 (Screen 7)')),
      body: Center(
        child: Text('SettingsScreen — placeholder', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
