import 'package:flutter/material.dart';

class ResultReviewScreen extends StatelessWidget {
  const ResultReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('결과 처리 (Screen 6)')),
      body: Center(
        child: Text('ResultReviewScreen — placeholder', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
