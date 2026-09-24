import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/security/app_lock.dart';
import 'package:fraud_shield/core/security/biometric_service.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';

/// B2: shown above every screen when the app comes back from the
/// background. Unlock with fingerprint (PIN fallback) or log out instead.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _message;

  Future<void> _unlock() async {
    final ok = await ref
        .read(biometricServiceProvider)
        .confirm('Unlock FraudShield');
    if (!mounted) return;
    if (ok) {
      ref.read(appLockProvider.notifier).unlock();
    } else {
      setState(() => _message = 'Not unlocked. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = ref.watch(sessionProvider.select((s) => s.firstName));
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'FraudShield is locked',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  name.isEmpty
                      ? 'Unlock to continue.'
                      : 'Welcome back, $name. Unlock to continue.',
                  textAlign: TextAlign.center,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => unawaited(_unlock()),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed:
                      () => unawaited(
                        ref.read(sessionProvider.notifier).logout(),
                      ),
                  child: const Text('Log out instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
