import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  bool get useFirebase => Firebase.apps.isNotEmpty;

  // Preset list of nice Unsplash image URLs to simulate real user uploads
  static const List<String> _unsplashPlaceholders = [
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?q=80&w=600',
    'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?q=80&w=600',
    'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?q=80&w=600',
    'https://images.unsplash.com/photo-1517841905240-472988babdf9?q=80&w=600',
    'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?q=80&w=600',
    'https://images.unsplash.com/photo-1544005313-94ddf0286df2?q=80&w=600',
  ];

  Future<String> uploadOriginalImage(XFile file, String path) async {
    if (useFirebase) {
      try {
        final ref = FirebaseStorage.instance.ref().child(path);
        final data = await file.readAsBytes();
        final uploadTask = await ref.putData(data);
        return await uploadTask.ref.getDownloadURL();
      } catch (e) {
        debugPrint('Error uploading to Firebase Storage: $e');
        throw Exception('Không thể tải ảnh lên máy chủ. Bạn đã bật Firebase Storage chưa? Lỗi chi tiết: $e');
      }
    } else {
      await Future.delayed(const Duration(seconds: 1));
      final random = Random();
      return _unsplashPlaceholders[random.nextInt(_unsplashPlaceholders.length)];
    }
  }

  Future<String> uploadThumbnail(XFile file, String path) async {
    if (useFirebase) {
      // Typically you'd compress `file` here using flutter_image_compress
      // before uploading to the thumbnail path.
      try {
        final ref = FirebaseStorage.instance.ref().child(path);
        final data = await file.readAsBytes();
        final uploadTask = await ref.putData(data);
        return await uploadTask.ref.getDownloadURL();
      } catch (e) {
        debugPrint('Error uploading thumbnail: $e');
        throw Exception('Không thể tải ảnh thu nhỏ lên máy chủ. Lỗi chi tiết: $e');
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
      final random = Random();
      final base = _unsplashPlaceholders[random.nextInt(_unsplashPlaceholders.length)];
      return '$base&auto=format&fit=crop&w=150';
    }
  }

  Future<void> deleteImageByPath(String path) async {
    if (useFirebase) {
      try {
        await FirebaseStorage.instance.ref().child(path).delete();
      } catch (e) {
        debugPrint('Error deleting image from Firebase Storage: $e');
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 300));
      debugPrint('Mock Storage: Deleted image at $path');
    }
  }

  Future<Map<String, String>> replaceImageSafely({
    required XFile newFile,
    required String oldOriginalPath,
    required String oldThumbnailPath,
    required String newBasePath, // e.g., ig_requests/pairId/requestId
  }) async {
    if (oldOriginalPath.isNotEmpty) {
      await deleteImageByPath(oldOriginalPath);
    }
    if (oldThumbnailPath.isNotEmpty) {
      await deleteImageByPath(oldThumbnailPath);
    }

    final origPath = '$newBasePath/original.jpg';
    final thumbPath = '$newBasePath/thumbnail.jpg';

    final origUrl = await uploadOriginalImage(newFile, origPath);
    final thumbUrl = await uploadThumbnail(newFile, thumbPath);

    return {
      'originalImageUrl': origUrl,
      'thumbnailImageUrl': thumbUrl,
      'originalImagePath': origPath,
      'thumbnailImagePath': thumbPath,
    };
  }
}
