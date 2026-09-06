import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Mock login screen.
///
/// No real auth in this stage. Lets the user pick which role the app behaves
/// as (Customer or Rider), backed by the hardcoded [roleProvider] toggle.
class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mock Login')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome to Login Screen'),
            const SizedBox(height: 24),
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(
                  value: UserRole.customer,
                  label: Text('Customer'),
                  icon: Icon(Icons.person),
                ),
                ButtonSegment(
                  value: UserRole.rider,
                  label: Text('Rider'),
                  icon: Icon(Icons.delivery_dining),
                ),
              ],
              selected: {role},
              onSelectionChanged: (selection) {
                ref.read(roleProvider.notifier).setRole(selection.first);
              },
            ),
          ],
        ),
      ),
    );
  }
}