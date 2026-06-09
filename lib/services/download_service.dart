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

      // Dynamic domain replacement to bypass ISP blocking
      String downloadUrl = url;
      if (downloadUrl.contains('pixeldrain.com')) {
        downloadUrl = downloadUrl.replaceAll('pixeldrain.com', 'pixeldrain.net');
      }

      // Download image to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/temp_download_${DateTime.now().millisecondsSinceEpoch}$extension';

      try {
        // Sử dụng wsrv.nl (Cloudflare CDN) để nén ảnh ở chất lượng 85% và tăng tốc download ở Việt Nam
        final proxyUrl = 'https://wsrv.nl/?url=${Uri.encodeComponent(downloadUrl)}&q=85';
        debugPrint('DownloadService: Đang tải qua CDN proxy: $proxyUrl');
        await _dio.download(
          proxyUrl,
          tempPath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              final percent = (received / total * 100).toStringAsFixed(0);
              onStatusChanged('Đang tải ảnh: $percent%');
            } else {
              onStatusChanged('Đang tải ảnh (${(received / 1024).toStringAsFixed(0)} KB)...');
            }
          },
        );
      } catch (proxyError) {
        debugPrint('DownloadService: Lỗi tải qua proxy ($proxyError). Đang tải trực tiếp từ nguồn...');
        // Fallback: Tải trực tiếp nếu proxy có sự cố
        await _dio.download(
          downloadUrl,
          tempPath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              final percent = (received / total * 100).toStringAsFixed(0);
              onStatusChanged('Đang tải ảnh: $percent%');
            } else {
              onStatusChanged('Đang tải ảnh (${(received / 1024).toStringAsFixed(0)} KB)...');
            }
          },
        );
      }

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
        
        String downloadUrl = url;
        if (downloadUrl.contains('pixeldrain.com')) {
          downloadUrl = downloadUrl.replaceAll('pixeldrain.com', 'pixeldrain.net');
        }

        try {
          final proxyUrl = 'https://wsrv.nl/?url=${Uri.encodeComponent(downloadUrl)}&q=85';
          await _dio.download(proxyUrl, path);
        } catch (_) {
          await _dio.download(downloadUrl, path);
        }
        
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
