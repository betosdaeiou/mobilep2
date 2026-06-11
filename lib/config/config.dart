import 'dart:io';
import 'package:flutter/foundation.dart';

class Config {
  /// URL base del backend.
  /// - Web / iOS simulator / desktop: localhost
  /// - Android emulator: 10.0.2.2 (host machine)
  /// - Dispositivo físico: cambiar [_physicalDeviceHost] a la IP de tu PC en la red local
  static const String _physicalDeviceHost = '192.168.1.100';

  static String get apiUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (Platform.isAndroid) {
      // En emulador Android, 10.0.2.2 apunta al localhost del host
      // En dispositivo físico, usar la IP de la máquina donde corre el backend
      return 'http://10.0.2.2:8000';
      // Para dispositivo físico descomentar:
      // return 'http://$_physicalDeviceHost:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
