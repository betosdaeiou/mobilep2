import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();
  
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  ConnectivityService() {
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // In connectivity_plus 7.x, onConnectivityChanged returns a List<ConnectivityResult>
      _updateConnectionStatus(results);
    });
    checkInitialConnection();
  }

  Future<void> checkInitialConnection() async {
    final results = await _connectivity.checkConnectivity();
    _updateConnectionStatus(results);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none)) {
      _isOnline = false;
    } else {
      // Si no es 'none', asumimos conexión (cubre vpn, ethernet, wifi, mobile, other)
      _isOnline = true;
    }
    _connectionStatusController.add(_isOnline);
  }
  
  void dispose() {
    _connectionStatusController.close();
  }
}
