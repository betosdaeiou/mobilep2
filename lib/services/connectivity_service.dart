import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Servicio singleton de conectividad compartido por toda la app.
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  factory ConnectivityService() => instance;

  final Connectivity _connectivity = Connectivity();
  StreamController<bool>? _connectionStatusController;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Stream<bool> get connectionStatusStream {
    _connectionStatusController ??= StreamController<bool>.broadcast();
    _ensureInitialized();
    return _connectionStatusController!.stream;
  }

  void _ensureInitialized() {
    if (_connectivitySubscription != null) return;

    _connectionStatusController ??= StreamController<bool>.broadcast();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    checkInitialConnection();
  }

  Future<void> checkInitialConnection() async {
    _ensureInitialized();
    final results = await _connectivity.checkConnectivity();
    _updateConnectionStatus(results);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (_isOnline == online) return;
    _isOnline = online;
    _connectionStatusController?.add(_isOnline);
  }
}
