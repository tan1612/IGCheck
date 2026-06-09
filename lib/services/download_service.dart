import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class DownloadService {
  final Dio _dio = Dio();

  Future<bool> saveImageToGallery(String url, {required Function(String) onStatusChanged}) async {
    try {
      onStatusChanged('Đang tải ảnh...');
      
      // Handle permissions on iOS/Android
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        final status = await Permission.photos.request();
        if (!status.isGranted) {
          onStatusChanged('Không có quyền truy cập thư viện ảnh.');
          return false;
        }
      }

      // Determine file extension from URL or default to .jpg
      String extension = '.jpg';
      try {
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final lastSegment = pathSegments.last.toLowerCase();
          if (lastSegment.contains('.png')) {
            extension = '.png';
          } else if (lastSegment.contains('.jpeg') || lastSegment.contains('.jpg')) {
            extension = '.jpg';
          } else if (lastSegment.contains('.gif')) {
            extension = '.gif';
          }
        }
      } catch (_) {}

      // Download image to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/temp_download_${DateTime.now().millisecondsSinceEpoch}$extension';

      await _dio.download(url, tempPath);

      // Save the file to gallery
      final result = await ImageGallerySaver.saveFile(tempPath);

      // Delete the temporary file after saving
      try {
        final file = File(tempPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}

      if (result != null && result['isSuccess'] == true) {
        onStatusChanged('Đã lưu ảnh gốc vào thư viện.');
        return true;
      } else {
        final errorMsg = result != null ? result['errorMessage'] : 'Lỗi hệ thống';
        onStatusChanged('Không thể lưu ảnh: $errorMsg');
        return false;
      }
    } catch (e) {
      debugPrint('Lỗi tải/lưu ảnh: $e');
      onStatusChanged('Lỗi: $e');
      return false;
    }
  }

  Future<void> shareImageUrl(String url, String username) async {
    try {
      if (kIsWeb) {
        await SharePlus.instance.share(
          ShareParams(
            text: 'Xem hồ sơ IG của $username tại đây: $url',
          ),
        );
      } else {
        // Download temp file first to share the actual file
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/shared_image.jpg';
        
        await _dio.download(url, path);
        
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            text: 'IGCheck: Hồ sơ Instagram $username',
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi chia sẻ: $e');
    }
  }
}
