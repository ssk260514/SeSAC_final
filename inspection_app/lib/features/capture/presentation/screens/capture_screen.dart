import 'package:flutter/material.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('카메라 (Screen 5)')),
      body: Center(
        child: Text('CaptureScreen — placeholder', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
