import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background/terminated messages are handled by the system by default.
  // This handler is registered to avoid missing message issues on some platforms.
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;

  String? _lastToken;
  String? _currentUserId;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {}

    await _requestPermission();

    _authSub = supabase.auth.onAuthStateChange.listen((state) {
      final user = state.session?.user;

      if (user != null) {
        if (_currentUserId != user.id) {
          _currentUserId = user.id;
          _lastToken = null;
        }
        _registerTokenForCurrentUser();
      } else {
        if (_currentUserId != null) {
          _clearTokenForUser(_currentUserId!);
        }
        _currentUserId = null;
        _lastToken = null;
      }
    });

    try {
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        _lastToken = null;
        _registerTokenForCurrentUser();
      });
    } catch (_) {}

    _onMessageSub?.cancel();
    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('FCM foreground message: ${message.messageId}');
      }
    });

    _onMessageOpenedSub?.cancel();
    _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('FCM notification tapped: ${message.messageId}');
      }
    });

    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null && kDebugMode) {
        debugPrint('FCM initial message: ${initialMessage.messageId}');
      }
    } catch (_) {}

    final sessionUser = supabase.auth.currentUser;
    if (sessionUser != null) {
      _currentUserId = sessionUser.id;
      _registerTokenForCurrentUser();
    }
  }

  Future<void> _requestPermission() async {
    try {
      if (Platform.isIOS) {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      } else {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM permission error: $e');
      }
    }
  }

  Future<void> _registerTokenForCurrentUser() async {
    final userId = _currentUserId ?? supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      String? token;
      try {
        token = await _messaging.getToken();
      } catch (_) {
        return;
      }
      if (token == null || token.isEmpty) return;
      if (_lastToken == token) return;

      final platform = kIsWeb
          ? 'web'
          : Platform.isAndroid
              ? 'android'
              : Platform.isIOS
                  ? 'ios'
                  : 'other';

      await supabase.from('user_fcm_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );

      // Also update profiles for backward compatibility if column exists
      try {
        await supabase.from('profiles').update({
          'fcm_token': token,
        }).eq('id', userId);
      } catch (_) {
        // Ignore if column doesn't exist yet
      }

      _lastToken = token;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM token registration error: $e');
      }
    }
  }

  Future<void> _clearTokenForUser(String userId) async {
    try {
      String? token;
      try {
        token = await _messaging.getToken();
      } catch (_) {
        token = null;
      }
      if (token != null && token.isNotEmpty) {
        await supabase
            .from('user_fcm_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('token', token);
      }
      try {
        await supabase.from('profiles').update({
          'fcm_token': null,
        }).eq('id', userId);
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM token clear error: $e');
      }
    }
  }

  void dispose() {
    _authSub?.cancel();
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _onMessageOpenedSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
    _onMessageSub = null;
    _onMessageOpenedSub = null;
    _initialized = false;
  }
}
