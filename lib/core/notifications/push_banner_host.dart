import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/motion/motion.dart';
import 'package:fraud_shield/core/notifications/push_notifications.dart';
import 'package:fraud_shield/core/security/app_lock.dart';

/// Shows push notifications as a banner at the top of the screen.
/// Tapping one opens its deep link. While the app is locked the banner
/// shows no transaction details (Security NFR).
class PushBannerHost extends ConsumerStatefulWidget {
  const PushBannerHost({super.key, required this.onOpen});

  final void Function(String route) onOpen;

  @override
  ConsumerState<PushBannerHost> createState() => _PushBannerHostState();
}

class _PushBannerHostState extends ConsumerState<PushBannerHost> {
  static const _visibleFor = Duration(seconds: 6);

  Timer? _timer;
  String? _timedId;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss(String id) {
    _timer?.cancel();
    _timedId = null;
    ref.read(pushNotificationsProvider.notifier).dismiss(id);
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(pushNotificationsProvider);
    final locked = ref.watch(appLockProvider);
    final notice = notices.isEmpty ? null : notices.first;

    if (notice != null && _timedId != notice.id) {
      _timedId = notice.id;
      _timer?.cancel();
      _timer = Timer(_visibleFor, () => _dismiss(notice.id));
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: Motion.duration(context, Motion.short),
          transitionBuilder:
              (child, animation) => SlideTransition(
                position: Tween(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
          child:
              notice == null
                  ? const SizedBox.shrink()
                  : _Banner(
                    key: ValueKey(notice.id),
                    title: locked ? PushNotice.lockedTitle : notice.title,
                    body: locked ? PushNotice.lockedBody : notice.body,
                    onTap: () {
                      _dismiss(notice.id);
                      widget.onOpen(notice.route);
                    },
                    onClose: () => _dismiss(notice.id),
                  ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.title,
    required this.body,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          elevation: 6,
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const Key('push-banner'),
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                children: [
                  Icon(Icons.shield, color: scheme.onInverseSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: scheme.onInverseSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            body,
                            style: TextStyle(color: scheme.onInverseSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss notification',
                    onPressed: onClose,
                    icon: Icon(Icons.close, color: scheme.onInverseSurface),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
