import 'dart:io';
import 'package:flutter/foundation.dart';

class Config {
  /// URL base del backend.
  /// - Web / iOS simulator / desktop: localhost
  /// - Android emulator: 10.0.2.2 (host machine)
  /// - Dispositivo físico: cambiar [_physicalDeviceHost] a la IP de tu PC en la red local
  static const String _physicalDeviceHost = '192.168.1.100';

  static String get apiUrl {
    // Usar la URL de producción (Coolify)
    return 'https://n1z40ygwn1ti8qrrzvep4w0u.137.184.105.96.sslip.io';
  }
}
