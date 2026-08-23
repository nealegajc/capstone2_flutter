import 'package:intl/intl.dart';

extension StringExtensions on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  String toTitleCase() {
    return split(' ').map((word) => word.capitalize()).join(' ');
  }

  String formatStatusName() {
    return replaceAll('_', ' ').toTitleCase();
  }
}

extension DateTimeExtensions on DateTime {
  String formatTimeAgo() {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins min${mins > 1 ? 's' : ''} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hr${hours > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days day${days > 1 ? 's' : ''} ago';
    } else {
      return DateFormat('MMM dd, yyyy').format(this);
    }
  }

  String formatFullDate() {
    return DateFormat('MMM dd, yyyy • hh:mm a').format(this);
  }

  String formatTimeOnly() {
    return DateFormat('hh:mm a').format(this);
  }
}

extension CurrencyExtensions on num {
  String toPhp() {
    final formatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    return formatter.format(this);
  }
}
