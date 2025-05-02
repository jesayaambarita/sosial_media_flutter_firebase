import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationService {
  static const String _serverKey = '293321706733';

  static Future<void> sendNotification({
    required String title,
    required String body,
    required String token,
    Map<String, dynamic>? data,
  }) async {
    const String fcmEndpoint = 'https://fcm.googleapis.com/fcm/send';

    try {
      final response = await http.post(
        Uri.parse(fcmEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$_serverKey',
        },
        body: jsonEncode({
          'to': token,
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
          },
          'data': data ?? {},
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Notifikasi dikirim');
      } else {
        print('❌ Gagal kirim notifikasi: ${response.body}');
      }
    } catch (e) {
      print('❗ Error kirim notifikasi: $e');
    }
  }
}
