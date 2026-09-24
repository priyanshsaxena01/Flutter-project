import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/app/router.dart';
import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/notifications/push_banner_host.dart';
import 'package:fraud_shield/core/security/app_lock.dart';
import 'package:fraud_shield/core/widgets/biometric_prompt.dart';
import 'package:fraud_shield/features/auth/presentation/lock_screen.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';

class FraudShieldApp extends ConsumerStatefulWidget {
  const FraudShieldApp({super.key});

  @override
  ConsumerState<FraudShieldApp> createState() => _FraudShieldAppState();
}

class _FraudShieldAppState extends ConsumerState<FraudShieldApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// B2: lock when the app goes to the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (ref.read(sessionProvider).isSignedIn) {
        ref.read(appLockProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'FraudShield',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      builder:
          (context, child) => _AppLayers(
            onOpenRoute: router.go,
            child: child ?? const SizedBox.shrink(),
          ),
    );
  }
}

/// Layers above every route: the lock screen, push banners and the
/// fingerprint prompt (top-most, like the system prompt on a phone).
class _AppLayers extends ConsumerWidget {
  const _AppLayers({required this.child, required this.onOpenRoute});

  final Widget child;
  final void Function(String route) onOpenRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockProvider);
    final signedIn = ref.watch(sessionProvider.select((s) => s.isSignedIn));
    final showLock = locked && signedIn;

    // Tooltips and text fields inside these layers need an Overlay.
    return Overlay.wrap(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Nothing under the lock screen can be seen, tapped or read by a
          // screen reader.
          ExcludeSemantics(excluding: showLock, child: child),
          if (showLock) const LockScreen(),
          if (signedIn) PushBannerHost(onOpen: onOpenRoute),
          const BiometricPromptHost(),
        ],
      ),
    );
  }
}
