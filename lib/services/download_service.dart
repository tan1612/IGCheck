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

      // Download image bytes
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null) {
        onStatusChanged('Không thể tải ảnh, dữ liệu trống.');
        return false;
      }

      // Save to gallery
      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(response.data!),
        quality: 100,
        name: 'IGCheck_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (result != null && result['isSuccess'] == true) {
        onStatusChanged('Đã lưu ảnh gốc vào thư viện.');
        return true;
      } else {
        onStatusChanged('Không thể lưu ảnh, vui lòng thử lại.');
        return false;
      }
    } catch (e) {
      print('Lỗi tải/lưu ảnh: $e');
      onStatusChanged('Không thể lưu ảnh, vui lòng thử lại.');
      return false;
    }
  }

  Future<void> shareImageUrl(String url, String username) async {
    try {
      if (kIsWeb) {
        await Share.share('Xem hồ sơ IG của $username tại đây: $url');
      } else {
        // Download temp file first to share the actual file
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/shared_image.jpg';
        
        await _dio.download(url, path);
        
        await Share.shareXFiles(
          [XFile(path)],
          text: 'IGCheck: Hồ sơ Instagram $username',
        );
      }
    } catch (e) {
      print('Lỗi chia sẻ: $e');
    }
  }
}
