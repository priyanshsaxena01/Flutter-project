import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/config/api_config.dart';
import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/utils/validators.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';

/// B1: sign in. The router guard moves on by itself once signed in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerId = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _showPin = false;
  String? _error;

  @override
  void dispose() {
    _customerId.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(_customerId.text, _pin.text);
    } on BankError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = ref.watch(sessionProvider.select((s) => s.expired));
    final useMock = ref.watch(apiConfigProvider).useMock;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.shield,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'FraudShield',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Stop fraud in one tap',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (expired) ...[
                      const InlineMessage(
                        tone: Tone.warning,
                        message:
                            'You were signed out for your security. Please '
                            'sign in again.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _customerId,
                      decoration: const InputDecoration(
                        labelText: 'Customer ID',
                        hintText: 'TEST_CUSTOM',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      validator: Validators.customerId,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pin,
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                          onPressed: () => setState(() => _showPin = !_showPin),
                          icon: Icon(
                            _showPin ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      obscureText: !_showPin,
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => unawaited(_submit()),
                      validator: Validators.pin,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      InlineMessage(message: _error!),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : () => unawaited(_submit()),
                      child:
                          _busy
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text('Sign in'),
                    ),
                    if (useMock) ...[
                      const SizedBox(height: 24),
                      const InlineMessage(
                        tone: Tone.neutral,
                        title: 'Demo bank',
                        message: 'Customer ID TEST_CUSTOM, PIN 0123456789',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
