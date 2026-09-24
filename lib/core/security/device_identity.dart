import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who this install is. Sent with every request (Auditability NFR) and used
/// by the Security centre to tell "this device" apart from the others.
class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.name});

  factory DeviceIdentity.generate() {
    final random = Random();
    final suffix =
        List.generate(6, (_) => random.nextInt(16).toRadixString(16)).join();
    return DeviceIdentity(id: 'dev-$suffix', name: _platformName());
  }

  final String id;
  final String name;

  static String _platformName() {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android phone',
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.linux => 'Linux PC',
      TargetPlatform.fuchsia => 'Fuchsia device',
    };
  }
}

/// One id per app run. A production app would generate it once and keep it
/// in secure storage.
final deviceIdentityProvider = Provider<DeviceIdentity>(
  (ref) => DeviceIdentity.generate(),
);
