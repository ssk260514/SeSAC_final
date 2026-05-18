import 'package:flutter/material.dart';

class TankLocationScreen extends StatelessWidget {
  const TankLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('탱크/위치 선택 (Screen 2)')),
      body: Center(
        child: Text('TankLocationScreen — placeholder', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
