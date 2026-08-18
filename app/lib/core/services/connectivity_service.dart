import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  /// Force connectivity state for tests. Never call from production code.
  @visibleForTesting
  void setOnlineForTest(bool value) {
    _isOnline = value;
  }

  Future<void> initialize() async {
    // Check initial connectivity
    _isOnline = await _checkConnectivity();

    // Listen to connectivity changes
    _connectivity.onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      _updateConnectionStatus(results);
    });
  }

  Future<bool> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasConnection(results);
    } catch (e) {
      return false;
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) =>
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.ethernet);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = _hasConnection(results);

    if (wasOnline != _isOnline) {
      _connectionStatusController.add(_isOnline);
    }
  }

  void dispose() {
    _connectionStatusController.close();
  }
}
