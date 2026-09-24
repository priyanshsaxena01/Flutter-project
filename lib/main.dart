import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/app/app.dart';

/// FraudShield (Flutter Banking Capstone P10).
///
/// Runs with no setup: the bank server is built into the app.
/// Demo login: customer ID TEST_CUSTOM, PIN 0123456789.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FraudShieldApp()));
}
