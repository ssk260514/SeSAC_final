import 'package:flutter/material.dart';

class InspectionHistoryScreen extends StatelessWidget {
  const InspectionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('검사 이력 (Screen 4)')),
      body: Center(
        child: Text('InspectionHistoryScreen — placeholder', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
