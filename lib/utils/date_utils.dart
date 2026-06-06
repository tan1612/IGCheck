import 'package:intl/intl.dart';

class AppDateUtils {
  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final DateFormat formatter = DateFormat('dd/MM/yyyy HH:mm');
    return formatter.format(dateTime);
  }

  static String formatTimeOnly(DateTime? dateTime) {
    if (dateTime == null) return '';
    final DateFormat formatter = DateFormat('HH:mm');
    return formatter.format(dateTime);
  }

  static String formatRelative(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays == 1 || (now.day - dateTime.day == 1 && now.month == dateTime.month && now.year == dateTime.year)) {
      return 'Hôm qua lúc ${formatTimeOnly(dateTime)}';
    } else {
      return formatDateTime(dateTime);
    }
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }
}
