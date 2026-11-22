import 'dart:typed_data';

/// Cross-platform in-memory picked file container shared between Android IO & Web.
class PickedBytesFile {
  final Uint8List bytes;
  final String filename;

  const PickedBytesFile({
    required this.bytes,
    required this.filename,
  });
}
