import 'dart:typed_data';

/// Contract used by alternative local OCR backends.
///
/// No fallback returns invented text.
abstract interface class PdfOcrEngine {
  Future<bool> get isAvailable;

  Future<List<PdfOcrRegion>> recognizePage({
    required int pageNumber,
    required Uint8List imageBytes,
    required double imageWidth,
    required double imageHeight,
  });
}

class PdfOcrRegion {
  const PdfOcrRegion({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left, top, right, bottom;
}

/// Integration requirements shared by the importer and native implementation.
class PdfOcrStrategy {
  const PdfOcrStrategy._();

  static const renderDpi = 240;
  static const pagesInParallel = 1;
  static const iosBackend = 'Vision.framework (VNRecognizeTextRequest)';
  static const androidBackend = 'ML Kit Text Recognition v2, bundled model';
  static const unavailableMessage =
      'Aucun texte sélectionnable trouvé. Ce PDF semble être scanné. '
      'La reconnaissance locale n’a pas trouvé de texte exploitable.';
}
