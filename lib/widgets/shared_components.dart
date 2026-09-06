import 'package:flutter/material.dart';

/// Shared placeholder widgets used across screens.
///
/// This stage only provides a simple centered placeholder label. Real shared
/// components (buttons, cards, inputs) will be added in later stages.
class ScreenPlaceholder extends StatelessWidget {
  const ScreenPlaceholder({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('Welcome to $title Screen'),
      ),
    );
  }
}
