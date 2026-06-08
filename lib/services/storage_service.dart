import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dio/dio.dart';

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
        final uploadTask = await ref.putData(data).timeout(const Duration(seconds: 30));
        return await uploadTask.ref.getDownloadURL().timeout(const Duration(seconds: 30));
      } catch (e) {
        debugPrint('Firebase Storage error: $e, falling back to Catbox.moe');
        return await _fallbackUpload(file);
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
        final uploadTask = await ref.putData(data).timeout(const Duration(seconds: 30));
        return await uploadTask.ref.getDownloadURL().timeout(const Duration(seconds: 30));
      } catch (e) {
        debugPrint('Firebase Storage error: $e, falling back to Catbox.moe');
        return await _fallbackUpload(file);
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

  Future<String> _fallbackUpload(XFile file) async {
    // 1. Try Catbox.moe
    try {
      debugPrint('Attempting Catbox.moe upload...');
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final formData = FormData.fromMap({
        'reqtype': 'fileupload',
        'fileToUpload': MultipartFile.fromBytes(
          await file.readAsBytes(),
          filename: file.name.isNotEmpty ? file.name : 'image.jpg',
        ),
      });
      final response = await dio.post('https://catbox.moe/user/api.php', data: formData);
      if (response.statusCode == 200) {
        final url = response.data.toString().trim();
        if (url.startsWith('http')) {
          debugPrint('Catbox.moe upload successful: $url');
          return url;
        }
      }
    } catch (e) {
      debugPrint('Catbox upload failed: $e');
    }

    // 2. Try Tmpfiles.org
    try {
      debugPrint('Attempting Tmpfiles.org upload...');
      final url = await _uploadToTmpfiles(file);
      if (url.startsWith('http')) {
        debugPrint('Tmpfiles.org upload successful: $url');
        return url;
      }
    } catch (e) {
      debugPrint('Tmpfiles upload failed: $e');
    }

    // 3. Try 0x0.st
    try {
      debugPrint('Attempting 0x0.st upload...');
      final url = await _uploadTo0x0(file);
      if (url.startsWith('http')) {
        debugPrint('0x0.st upload successful: $url');
        return url;
      }
    } catch (e) {
      debugPrint('0x0.st upload failed: $e');
    }

    throw Exception('Không thể upload ảnh (Kể cả các máy chủ dự phòng Catbox, Tmpfiles, 0x0.st đều gặp lỗi). Vui lòng kiểm tra lại kết nối mạng hoặc nâng cấp gói Firebase Storage.');
  }

  Future<String> _uploadToTmpfiles(XFile file) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        await file.readAsBytes(),
        filename: file.name.isNotEmpty ? file.name : 'image.jpg',
      ),
    });
    final response = await dio.post('https://tmpfiles.org/api/v1/upload', data: formData);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.data;
      if (data is Map && data['data'] != null && data['data']['url'] != null) {
        final url = data['data']['url'].toString();
        // Replace tmpfiles.org/ with tmpfiles.org/dl/ for direct link
        return url.replaceFirst('https://tmpfiles.org/', 'https://tmpfiles.org/dl/');
      }
    }
    throw Exception('Tmpfiles upload response invalid');
  }

  Future<String> _uploadTo0x0(XFile file) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        await file.readAsBytes(),
        filename: file.name.isNotEmpty ? file.name : 'image.jpg',
      ),
    });
    final response = await dio.post('https://0x0.st', data: formData);
    if (response.statusCode == 200) {
      return response.data.toString().trim();
    }
    throw Exception('0x0.st upload response invalid');
  }
}
