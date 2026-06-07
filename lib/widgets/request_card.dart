import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ig_request_model.dart';
import '../services/auth_service.dart';
import '../utils/date_utils.dart';
import 'status_chip.dart';

class RequestCard extends StatelessWidget {
  final IGRequestModel request;
  final VoidCallback onTap;

  const RequestCard({
    super.key,
    required this.request,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isSender = request.senderId == authService.currentUser?.uid;
    
    // Look up the other person's name
    final senderName = authService.getUserById(request.senderId)?.name ?? 'Người gửi';
    final receiverName = authService.getUserById(request.receiverId)?.name ?? 'Người nhận';

    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail (if available)
              if (request.thumbnailImageUrl.isNotEmpty || request.originalImageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    request.thumbnailImageUrl.isNotEmpty ? request.thumbnailImageUrl : request.originalImageUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 60,
                      height: 60,
                      color: const Color(0xFFE5E5EA),
                      child: const Icon(Icons.image_not_supported, color: Color(0xFF8E8E93)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, color: Color(0xFF8E8E93)),
                ),
                const SizedBox(width: 12),
              ],
              // Request Information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            request.instagramUsername,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1C1C1E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          AppDateUtils.formatRelative(request.updatedAt ?? request.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                    if (request.displayName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        request.displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF1C1C1E),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      request.note.isNotEmpty ? request.note : '(Không có ghi chú)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isSender ? 'Gửi cho $receiverName' : 'Nhận từ $senderName',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSender ? const Color(0xFFC2185B) : const Color(0xFF0288D1),
                          ),
                        ),
                        StatusChip(status: request.status),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
