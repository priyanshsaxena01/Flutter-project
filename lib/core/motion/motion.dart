import 'package:flutter/material.dart';

/// Motion helpers that honour the system "remove animations" setting (B8).
class Motion {
  const Motion._();

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Returns [normal], or zero when the user asked for reduced motion.
  static Duration duration(BuildContext context, Duration normal) =>
      reduced(context) ? Duration.zero : normal;

  static const short = Duration(milliseconds: 220);
  static const medium = Duration(milliseconds: 420);
}

/// Purposeful animation #1: a newly arrived alert grows and fades into the
/// inbox, so the eye catches it. Items that were already there render
/// without animation. Reduced motion shows it instantly.
class ArrivalAnimation extends StatefulWidget {
  const ArrivalAnimation({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<ArrivalAnimation> createState() => _ArrivalAnimationState();
}

class _ArrivalAnimationState extends State<ArrivalAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: widget.animate ? 0 : 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else if (_controller.value < 1 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return SizeTransition(
      sizeFactor: curve,
      child: FadeTransition(opacity: curve, child: widget.child),
    );
  }
}

/// Purposeful animation #2: the shield "locks" when a card is blocked,
/// confirming the safety action happened. Reduced motion shows the end state.
class LockConfirmation extends StatefulWidget {
  const LockConfirmation({super.key, required this.color, this.size = 72});

  final Color color;
  final double size;

  @override
  State<LockConfirmation> createState() => _LockConfirmationState();
}

class _LockConfirmationState extends State<LockConfirmation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.4,
        end: 1.15,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 40),
  ]).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else if (_controller.value == 0 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(Icons.lock, size: widget.size, color: widget.color),
    );
  }
}
