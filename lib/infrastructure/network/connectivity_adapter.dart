import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../domain/services/connectivity_service.dart';

/// Infrastructure adapter for network connectivity monitoring.
///
/// Uses connectivity_plus to track online/offline state.
class ConnectivityAdapter implements ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  bool _isOnline = true;
  late final StreamController<bool> _controller;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityAdapter() {
    _controller = StreamController<bool>.broadcast();
    _init();
  }

  void _init() {
    _subscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(online);
      }
    });

    // Check initial state
    _connectivity.checkConnectivity().then((results) {
      _isOnline = results.any((r) => r != ConnectivityResult.none);
    });
  }

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
