import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    String label = '';
    Color color = Colors.grey;

    switch (status) {
      case 'pending':
        label = 'Chờ duyệt';
        color = AppTheme.statusPending;
        break;
      case 'uploaded':
        label = 'Đã up';
        color = const Color(0xFF007AFF); // Apple iOS Blue
        break;
      case 'approved':
        label = 'Đã xanh';
        color = AppTheme.statusApproved;
        break;
      case 'rejected':
        label = 'Đã tạch';
        color = AppTheme.statusRejected;
        break;
      case 'needs_update':
        label = 'Cần sửa';
        color = AppTheme.statusNeedsUpdate;
        break;
      case 'updated':
        label = 'Đã cập nhật';
        color = AppTheme.statusUpdated;
        break;
      case 'cancelled':
        label = 'Đã huỷ';
        color = AppTheme.statusCancelled;
        break;
      default:
        label = status;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
