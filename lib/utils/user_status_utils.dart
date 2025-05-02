// lib/utils/user_status_utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserStatusUtils {
  // Check if a user is currently online
  static bool isUserOnline(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    return userData['isOnline'] == true;
  }

  // Format the last seen timestamp into a human-readable string
  static String formatLastSeen(Timestamp? lastSeen) {
    if (lastSeen == null) return 'Never online';

    final now = DateTime.now();
    final lastSeenDate = lastSeen.toDate();
    final difference = now.difference(lastSeenDate);

    // Within the last minute
    if (difference.inSeconds < 60) {
      return 'Baru saja';
    }
    // Within the last hour
    else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'menit' : 'menit'} yang lalu';
    }
    // Within the last day
    else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'jam' : 'jam'} yang lalu';
    }
    // Within the last week
    else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'hari' : 'hari'} yang lalu';
    }
    // More than a week
    else {
      return DateFormat('MMM d, yyyy').format(lastSeenDate);
    }
  }

  // Get online status text
  static String getOnlineStatusText(bool isOnline, Timestamp? lastSeen) {
    if (isOnline) {
      return 'Online';
    } else if (lastSeen != null) {
      return 'Terakhir dilihat ${formatLastSeen(lastSeen)}';
    } else {
      return 'Offline';
    }
  }
}
