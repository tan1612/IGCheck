import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2000, // Reasonable max width for detail photos
        maxHeight: 2000,
        imageQuality: 100, // Keep original quality as requested
      );
      return pickedFile;
    } catch (e) {
      debugPrint('Lỗi chọn ảnh: $e');
      return null;
    }
  }

  Future<int> getImageSize(File file) async {
    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  bool isLargeImage(int sizeInBytes) {
    // 15 MB = 15 * 1024 * 1024 bytes
    const int limit = 15 * 1024 * 1024;
    return sizeInBytes > limit;
  }

  /// In mock mode we return the same file as the thumbnail file, 
  /// but in production we can use flutter_image_compress to create a thumbnail.
  Future<File> createThumbnail(File originalFile) async {
    // Simulating thumbnail creation delay
    await Future.delayed(const Duration(milliseconds: 200));
    // For mock UI, we return the same file since it's just a file reference.
    // In production step, we will implement flutter_image_compress.
    return originalFile;
  }
}
