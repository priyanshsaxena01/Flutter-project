/// Evidence limits (F5): at most 5 files, 5 MB each, images or PDF.
class EvidenceRules {
  const EvidenceRules._();

  static const maxFiles = 5;
  static const maxBytes = 5 * 1024 * 1024;
  static const allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'application/pdf',
  };

  /// Returns why a file cannot be added, or null when it is fine.
  /// [filesSoFar] counts files already uploaded or waiting to upload.
  static String? checkFile({
    required String name,
    required int sizeBytes,
    required String mimeType,
    required int filesSoFar,
  }) {
    if (filesSoFar >= maxFiles) {
      return '$name: you can add up to $maxFiles files.';
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      return '$name: only photos (JPG, PNG) and PDF files can be added.';
    }
    if (sizeBytes > maxBytes) {
      return '$name is ${formatSize(sizeBytes)}. Each file must be 5 MB or '
          'smaller.';
    }
    if (sizeBytes <= 0) return '$name is empty.';
    return null;
  }

  /// 1536 -> "1.5 KB", 5242880 -> "5.0 MB"
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String mimeTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }
}
