import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ImagePreviewCard extends StatelessWidget {
  final File? localFile;
  final String? networkUrl;
  final int imageSizeBytes;
  final VoidCallback? onRemove;
  final double height;

  const ImagePreviewCard({
    super.key,
    this.localFile,
    this.networkUrl,
    this.imageSizeBytes = 0,
    this.onRemove,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = localFile != null || (networkUrl != null && networkUrl!.isNotEmpty);
    
    // Size formatting
    String sizeText = '';
    bool isOverLimit = false;
    if (imageSizeBytes > 0) {
      final sizeMb = imageSizeBytes / (1024 * 1024);
      sizeText = 'Dung lượng: ${sizeMb.toStringAsFixed(1)} MB';
      if (sizeMb > 15) {
        isOverLimit = true;
      }
    }

    if (!hasImage) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 40, color: Color(0xFF8E8E93)),
              SizedBox(height: 8),
              Text(
                'Chọn ảnh từ máy hoặc chụp ảnh',
                style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: localFile != null
                    ? Image.file(
                        localFile!,
                        fit: BoxFit.cover,
                      )
                    : CachedNetworkImage(
                        imageUrl: networkUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: const Color(0xFFE5E5EA),
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFFE5E5EA),
                          child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                        ),
                      ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            if (sizeText.isNotEmpty)
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sizeText,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
          ],
        ),
        if (isOverLimit) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFEEBA)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ảnh khá nặng, tải lên có thể lâu hơn.',
                    style: TextStyle(color: Colors.brown, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F4FD),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD4EDDA).withOpacity(0.0)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF0288D1), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ảnh có thể chứa thông tin cá nhân, hãy kiểm tra kỹ trước khi gửi.',
                  style: TextStyle(color: Color(0xFF01579B), fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
