import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/features/alerts/presentation/alert_detail_screen.dart';
import 'package:fraud_shield/features/alerts/presentation/alerts_screen.dart';
import 'package:fraud_shield/features/auth/presentation/login_screen.dart';
import 'package:fraud_shield/features/auth/presentation/splash_screen.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/cases/presentation/case_detail_screen.dart';
import 'package:fraud_shield/features/cases/presentation/case_evidence_screen.dart';
import 'package:fraud_shield/features/cases/presentation/case_messages_screen.dart';
import 'package:fraud_shield/features/cases/presentation/cases_screen.dart';
import 'package:fraud_shield/features/disputes/presentation/dispute_evidence_screen.dart';
import 'package:fraud_shield/features/disputes/presentation/dispute_flow_screen.dart';
import 'package:fraud_shield/features/disputes/presentation/dispute_review_screen.dart';
import 'package:fraud_shield/features/disputes/presentation/pick_transaction_screen.dart';
import 'package:fraud_shield/features/home/presentation/home_screen.dart';
import 'package:fraud_shield/features/home/presentation/home_shell.dart';
import 'package:fraud_shield/features/instruments/presentation/block_screen.dart';
import 'package:fraud_shield/features/security/presentation/activity_log_screen.dart';
import 'package:fraud_shield/features/security/presentation/demo_controls_screen.dart';
import 'package:fraud_shield/features/security/presentation/security_screen.dart';

/// Route guard (B3). A pure function so it can be unit-tested.
///
/// * While the session is being restored, show /splash.
/// * Signed out: everything goes to /login, remembering where the user
///   wanted to go (so a push deep link works after signing in).
/// * Signed in: /login and /splash go to the remembered page or /home.
///
/// Logout needs no navigation code: changing the session re-runs this.
String? sessionRedirect(SessionState session, Uri uri, String matchedLocation) {
  final here = uri.toString();
  final from = uri.queryParameters['from'];

  switch (session.status) {
    case SessionStatus.restoring:
      if (matchedLocation == '/splash') return null;
      return '/splash?from=${Uri.encodeComponent(here)}';
    case SessionStatus.signedOut:
      if (matchedLocation == '/login') return null;
      final target = matchedLocation == '/splash' ? from : here;
      final safe = _safeTarget(target);
      return safe == null
          ? '/login'
          : '/login?from=${Uri.encodeComponent(safe)}';
    case SessionStatus.signedIn:
      if (matchedLocation == '/login' || matchedLocation == '/splash') {
        return _safeTarget(from) ?? '/home';
      }
      return null;
  }
}

String? _safeTarget(String? target) {
  if (target == null || !target.startsWith('/')) return null;
  if (target.startsWith('//')) return null; // not another host
  if (target.startsWith('/login') || target.startsWith('/splash')) return null;
  if (target == '/') return null;
  return target;
}

/// Tells GoRouter to re-check the guard whenever the session changes.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen<SessionState>(sessionProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable(ref);

  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect:
        (context, state) => sessionRedirect(
          ref.read(sessionProvider),
          state.uri,
          state.matchedLocation,
        ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),

      // The four tabs, with a bottom navigation bar.
      ShellRoute(
        builder:
            (context, state, child) =>
                HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/alerts',
            // Query parameter: /alerts?status=PENDING
            builder:
                (_, state) => AlertsScreen(
                  filter: AlertFilter.fromQuery(
                    state.uri.queryParameters['status'],
                  ),
                ),
            routes: [
              // Path parameter: /alerts/alt_1004 (push deep links land here).
              GoRoute(
                path: ':id',
                builder:
                    (_, state) =>
                        AlertDetailScreen(alertId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/cases',
            builder: (_, _) => const CasesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder:
                    (_, state) =>
                        CaseDetailScreen(caseId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'messages',
                    builder:
                        (_, state) => CaseMessagesScreen(
                          caseId: state.pathParameters['id']!,
                        ),
                  ),
                  GoRoute(
                    path: 'evidence',
                    builder:
                        (_, state) => CaseEvidenceScreen(
                          caseId: state.pathParameters['id']!,
                        ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/security',
            builder: (_, _) => const SecurityScreen(),
            routes: [
              GoRoute(
                path: 'activity',
                builder: (_, _) => const ActivityLogScreen(),
              ),
            ],
          ),
        ],
      ),

      // Full-screen flows (no bottom bar).
      GoRoute(
        path: '/block',
        builder:
            (_, state) => BlockScreen(
              highlightId: state.uri.queryParameters['instrumentId'],
            ),
      ),
      GoRoute(
        path: '/disputes/new',
        builder: (_, _) => const PickTransactionScreen(),
        routes: [
          // Fixed segments come before ':txnId' so they are not read as ids.
          GoRoute(
            path: 'evidence',
            builder: (_, _) => const DisputeEvidenceScreen(),
          ),
          GoRoute(
            path: 'review',
            builder: (_, _) => const DisputeReviewScreen(),
          ),
          GoRoute(
            path: ':txnId',
            builder:
                (_, state) =>
                    DisputeFlowScreen(txnId: state.pathParameters['txnId']!),
          ),
        ],
      ),
      GoRoute(path: '/demo', builder: (_, _) => const DemoControlsScreen()),
    ],
    errorBuilder:
        (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Not found')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('This page does not exist.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Go home'),
                  ),
                ],
              ),
            ),
          ),
        ),
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
