import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ReceiptImageUtils {
  static const int _maxDimension = 1600;
  static const int _jpegQuality = 75;

  static Future<Uint8List?> compress(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final longestSide =
          image.width > image.height ? image.width : image.height;
      if (longestSide > _maxDimension) {
        final scale = _maxDimension / longestSide;
        final resized = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
        return Uint8List.fromList(
          img.encodeJpg(resized, quality: _jpegQuality),
        );
      }

      return Uint8List.fromList(
        img.encodeJpg(image, quality: _jpegQuality),
      );
    } catch (e) {
      print('Error compressing receipt image: $e');
      return null;
    }
  }
}