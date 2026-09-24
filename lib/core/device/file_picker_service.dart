import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file chosen as evidence.
class PickedFile {
  PickedFile({
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    Uint8List? bytes,
  }) : _bytes = bytes;

  final String name;
  final int sizeBytes;
  final String mimeType;
  Uint8List? _bytes;

  /// The file content. Demo files are generated on first use.
  Uint8List get bytes => _bytes ??= Uint8List(sizeBytes);
}

/// Picks evidence files (screenshots, invoices, chats).
///
/// The app ships with [DemoFilePickerService], a sheet of sample files, so
/// it works everywhere with no setup and can show the 5-file / 5 MB rules.
/// To use the real file system, implement this with the file_picker
/// package (see README) and override [filePickerServiceProvider].
abstract class FilePickerService {
  Future<List<PickedFile>> pickEvidence(BuildContext context);
}

class DemoFilePickerService implements FilePickerService {
  const DemoFilePickerService();

  static const _mb = 1024 * 1024;

  static final samples = <(String, int, String)>[
    ('order_confirmation.png', (1.2 * _mb).round(), 'image/png'),
    ('invoice_INV-2231.pdf', 655360, 'application/pdf'),
    ('chat_with_seller.jpg', (2.8 * _mb).round(), 'image/jpeg'),
    ('delivery_status.png', 921600, 'image/png'),
    ('bank_statement.pdf', (4.6 * _mb).round(), 'application/pdf'),
    ('photo_of_parcel.jpg', (6.2 * _mb).round(), 'image/jpeg'),
    ('screen_recording.mp4', (18.4 * _mb).round(), 'video/mp4'),
  ];

  @override
  Future<List<PickedFile>> pickEvidence(BuildContext context) async {
    final chosen = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _DemoFileSheet(),
    );
    if (chosen == null) return const [];
    return [
      for (final i in chosen)
        PickedFile(
          name: samples[i].$1,
          sizeBytes: samples[i].$2,
          mimeType: samples[i].$3,
        ),
    ];
  }
}

class _DemoFileSheet extends StatefulWidget {
  const _DemoFileSheet();

  @override
  State<_DemoFileSheet> createState() => _DemoFileSheetState();
}

class _DemoFileSheetState extends State<_DemoFileSheet> {
  final _selected = <int>{};

  static String _size(int bytes) =>
      bytes >= 1024 * 1024
          ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(bytes / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final files = DemoFilePickerService.samples;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Choose files (demo device)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < files.length; i++)
                    CheckboxListTile(
                      value: _selected.contains(i),
                      onChanged:
                          (on) => setState(
                            () =>
                                on == true
                                    ? _selected.add(i)
                                    : _selected.remove(i),
                          ),
                      secondary: Icon(
                        files[i].$3 == 'application/pdf'
                            ? Icons.picture_as_pdf_outlined
                            : files[i].$3.startsWith('video')
                            ? Icons.movie_outlined
                            : Icons.image_outlined,
                      ),
                      title: Text(files[i].$1),
                      subtitle: Text(_size(files[i].$2)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed:
                    _selected.isEmpty
                        ? null
                        : () => Navigator.of(
                          context,
                        ).pop(_selected.toList()..sort()),
                child: Text(
                  _selected.isEmpty
                      ? 'Select files'
                      : 'Attach ${_selected.length} '
                          '${_selected.length == 1 ? 'file' : 'files'}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const DemoFilePickerService(),
);
