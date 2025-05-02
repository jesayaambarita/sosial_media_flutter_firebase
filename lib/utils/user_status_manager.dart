import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class UserStatusManager {
  static final UserStatusManager _instance = UserStatusManager._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription? _userStatusSubscription;

  // Factory constructor
  factory UserStatusManager() {
    return _instance;
  }

  // Private constructor
  UserStatusManager._internal();

  // Initialize the user status manager
  void initialize() {
    final user = _auth.currentUser;
    if (user != null) {
      _setUserOnline(user.uid);
    }

    // Listen for authentication state changes
    _userStatusSubscription = _auth.authStateChanges().listen((User? user) {
      if (user != null) {
        _setUserOnline(user.uid);
      }
    });
  }

  // Set user as online
  Future<void> _setUserOnline(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      // Set up a handler to update status when app is closed/minimized
      _setupPresenceListener(userId);
    } catch (e) {
      debugPrint('Error setting user online: $e');
    }
  }

  // Set user as offline
  Future<void> _setUserOffline(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error setting user offline: $e');
    }
  }

  // Setup presence listener for app lifecycle events
  void _setupPresenceListener(String userId) {
    _addAppLifecycleObserver(userId);
  }

  // Add app lifecycle observer
  void _addAppLifecycleObserver(String userId) {
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver(
      onDetached: () => _setUserOffline(userId),
      onInactive: () => _setUserOffline(userId),
      onPaused: () => _setUserOffline(userId),
      onResumed: () => _setUserOnline(userId),
    ));
  }

  // Dispose resources
  void dispose() {
    _userStatusSubscription?.cancel();
    if (_auth.currentUser != null) {
      _setUserOffline(_auth.currentUser!.uid);
    }
  }
}

// Private class for app lifecycle events
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onDetached;
  final VoidCallback onInactive;
  final VoidCallback onPaused;
  final VoidCallback onResumed;

  _AppLifecycleObserver({
    required this.onDetached,
    required this.onInactive,
    required this.onPaused,
    required this.onResumed,
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        onDetached();
        break;
      case AppLifecycleState.inactive:
        onInactive();
        break;
      case AppLifecycleState.paused:
        onPaused();
        break;
      case AppLifecycleState.resumed:
        onResumed();
        break;
      default:
        break;
    }
  }
}
