import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/security/biometric_service.dart';

/// Draws the demo fingerprint prompt above everything (including the lock
/// screen), like the system prompt of a real phone.
class BiometricPromptHost extends ConsumerWidget {
  const BiometricPromptHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(biometricPromptProvider);
    if (request == null) return const SizedBox.shrink();
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Align(
          alignment: Alignment.bottomCenter,
          child: _PromptCard(key: ObjectKey(request), reason: request.reason),
        ),
      ],
    );
  }
}

class _PromptCard extends ConsumerStatefulWidget {
  const _PromptCard({super.key, required this.reason});

  final String reason;

  @override
  ConsumerState<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends ConsumerState<_PromptCard> {
  bool _usePin = false;
  String _pin = '';
  String? _message;

  void _finish(bool ok) =>
      ref.read(biometricPromptProvider.notifier).resolve(ok);

  void _tapDigit(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _message = null;
    });
    if (_pin.length == 4) {
      if (_pin == DemoBiometricService.demoDevicePin) {
        _finish(true);
      } else {
        setState(() {
          _pin = '';
          _message = 'Wrong PIN. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Confirm it\'s you',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.reason,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (!_usePin) ..._sensor(context) else ..._pinPad(context),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      style: TextStyle(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed:
                          () => setState(() {
                            _usePin = !_usePin;
                            _pin = '';
                            _message = null;
                          }),
                      child: Text(
                        _usePin ? 'Use fingerprint' : 'Use device PIN',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _finish(false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sensor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Semantics(
        button: true,
        label: 'Fingerprint sensor. Tap to scan.',
        child: InkResponse(
          key: const Key('fingerprint-sensor'),
          onTap: () => _finish(true),
          radius: 48,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer,
            ),
            child: Icon(
              Icons.fingerprint,
              size: 56,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text('Touch the sensor', textAlign: TextAlign.center),
      TextButton(
        onPressed:
            () => setState(
              () => _message = 'Fingerprint not recognised. Try again.',
            ),
        child: const Text('Simulate a wrong finger'),
      ),
    ];
  }

  List<Widget> _pinPad(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, String? semantics}) =>
        Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 72,
            height: 56,
            child: Semantics(
              label: semantics,
              child: FilledButton.tonal(onPressed: onTap, child: Text(label)),
            ),
          ),
        );

    return [
      Semantics(
        label: '${_pin.length} of 4 digits entered',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? scheme.primary : null,
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Demo device PIN: ${DemoBiometricService.demoDevicePin}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
            key(d, onTap: () => _tapDigit(d)),
          key(''),
          key('0', onTap: () => _tapDigit('0')),
          key(
            '⌫',
            semantics: 'Delete',
            onTap:
                _pin.isEmpty
                    ? null
                    : () => setState(
                      () => _pin = _pin.substring(0, _pin.length - 1),
                    ),
          ),
        ],
      ),
    ];
  }
}
