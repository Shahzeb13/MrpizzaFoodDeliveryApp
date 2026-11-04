import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';

class PushNotificationSender {
  PushNotificationSender._();
  static final PushNotificationSender instance = PushNotificationSender._();

  Future<bool> sendToAll({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? topic,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'broadcast-push-notification',
        body: {
          'title': title,
          'body': body,
          'data': data ?? {},
          if (topic != null) 'topic': topic,
        },
      );
      if (response.status >= 400) {
        if (kDebugMode) {
          debugPrint('Broadcast push failed: ${response.status} ${response.data}');
        }
        return false;
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Broadcast push error: $e');
      }
      return false;
    }
  }

  Future<bool> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'send-push-notification',
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          'data': data ?? {},
        },
      );
      if (response.status >= 400) {
        if (kDebugMode) {
          debugPrint('Push send failed: ${response.status} ${response.data}');
        }
        return false;
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Push send error: $e');
      }
      return false;
    }
  }
}
