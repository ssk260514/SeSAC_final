import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('로그인 (Screen 1)')),
      body: Center(
        child: Text('LoginScreen — placeholder', style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
