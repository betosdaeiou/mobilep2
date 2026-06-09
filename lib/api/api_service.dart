import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/login_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/config.dart';
import '../db/database_helper.dart';
import '../models/incidente_local.dart';
class ApiService {

  static Future<void> _handleUnauthorized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('tenant_id');
    
    // Close the session and redirect
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen()),
        (route) => false,
      );
    }
  }
  static String get baseUrl => Config.apiUrl;

  static Future<Map<String, dynamic>> registerConductor(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/registrar-conductor'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error de registro');
    }
  }

  static Future<String?> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': email,
        'password': password,
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      
      // Si el backend pide selección de tenant (usuario multi-tenant)
      if (body['requires_tenant_selection'] == true) {
        final tenants = body['tenants'] as List;
        // Buscar el primer tenant donde sea Conductor o Mecanico
        final targetTenant = tenants.firstWhere(
          (t) => t['rol'] == 'Conductor' || t['rol'] == 'Mecanico', 
          orElse: () => null
        );

        if (targetTenant == null) {
          throw Exception('Acceso Denegado. Solo Conductores o Mecánicos pueden usar esta App.');
        }

        // Hacer la petición de select-tenant
        final tempToken = body['temp_token'];
        final selectResponse = await http.post(
          Uri.parse('$baseUrl/auth/select-tenant'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'temp_token': tempToken,
            'tenant_id': targetTenant['id']
          }),
        );

        if (selectResponse.statusCode == 200) {
          final selectBody = jsonDecode(selectResponse.body);
          return _guardarSesion(selectBody['access_token'], selectBody['role']);
        } else {
          throw Exception('Error al verificar la organización del conductor.');
        }
      }

      // Si es un login directo (1 solo tenant o conductor global)
      final token = body['access_token'];
      final role = body['role'];
      
      if (role != 'Conductor' && role != 'Mecanico') {
         throw Exception('Acceso Denegado. Solo Conductores o Mecánicos pueden usar esta App.');
      }
      
      return _guardarSesion(token, role);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error de credenciales');
    }
  }

  static Future<String> _guardarSesion(String token, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('role', role);
    return token;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('token');
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  // --- Endpoints de Vehículos ---
  static Future<List<dynamic>> getVehiculos() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.get(
      Uri.parse('$baseUrl/vehiculos/mis-vehiculos'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al cargar vehículos');
    }
  }

  static Future<Map<String, dynamic>> addVehiculo(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/vehiculos/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al registrar vehículo');
    }
  }

  // --- Endpoints de Incidentes ---
  static Future<Map<String, dynamic>> reportarIncidente(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    // Comprobar conectividad
    final connectivityResult = await (Connectivity().checkConnectivity());
    bool isOnline = connectivityResult.contains(ConnectivityResult.mobile) || 
                    connectivityResult.contains(ConnectivityResult.wifi) || 
                    connectivityResult.contains(ConnectivityResult.ethernet);

    if (!isOnline) {
      // Guardar localmente
      final localIncidente = IncidenteLocal(
        coordenadagps: data['coordenadagps'],
        descripcion: data['descripcion'],
        fecha: DateTime.now().toIso8601String(),
        estado: 'PENDIENTE',
        isSynced: false,
      );
      final saved = await DatabaseHelper.instance.create(localIncidente);
      return {
        'mensaje': 'Sin conexión. Incidente guardado localmente.',
        'id': saved.id,
        'estado': 'PENDIENTE (Offline)'
      };
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/incidentes/reportar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al reportar incidente');
      }
    } catch (e) {
      // Si falla la petición (ej. no hay internet a pesar de que Connectivity dijo que sí), guardamos local
      final localIncidente = IncidenteLocal(
        coordenadagps: data['coordenadagps'],
        descripcion: data['descripcion'],
        fecha: DateTime.now().toIso8601String(),
        estado: 'PENDIENTE',
        isSynced: false,
      );
      final saved = await DatabaseHelper.instance.create(localIncidente);
      return {
        'mensaje': 'Fallo de red. Incidente guardado localmente.',
        'id': saved.id,
        'estado': 'PENDIENTE (Offline)'
      };
    }
  }

  // --- Endpoints de Gestión de Solicitudes ---
  static Future<List<dynamic>> getMisIncidentes() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.get(
      Uri.parse('$baseUrl/incidentes/mis-incidentes'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al cargar incidentes');
    }
  }

  static Future<List<dynamic>> getTalleresDisponibles(double? lat, double? lng, [int? incidenteId]) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    String url = '$baseUrl/incidentes/talleres-disponibles';
    List<String> queryParams = [];
    if (lat != null && lng != null) {
      queryParams.add('lat=$lat&lng=$lng');
    }
    if (incidenteId != null) {
      queryParams.add('incidente_id=$incidenteId');
    }
    if (queryParams.isNotEmpty) {
      url += '?${queryParams.join('&')}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al cargar talleres');
    }
  }

  static Future<Map<String, dynamic>> asignarTaller(int incidenteId, int tallerId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.patch(
      Uri.parse('$baseUrl/incidentes/$incidenteId/asignar-taller'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'taller_id': tallerId}),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al asignar taller');
    }
  }

  static Future<Map<String, dynamic>> cancelarIncidente(int incidenteId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.patch(
      Uri.parse('$baseUrl/incidentes/$incidenteId/cancelar'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al cancelar incidente');
    }
  }

  static Future<Map<String, dynamic>> solicitarCotizacion(int incidenteId, int tallerId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/incidentes/$incidenteId/solicitar-cotizacion'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'taller_id': tallerId}),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al solicitar cotización');
    }
  }

  static Future<Map<String, dynamic>> aceptarCotizacion(int cotizacionId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/incidentes/cotizaciones/$cotizacionId/aceptar'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al aceptar cotización');
    }
  }

  // --- Endpoints de Notificaciones ---
  static Future<void> updateFcmToken(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) return; // No hacemos tracking si no hay user

    final response = await http.post(
      Uri.parse('$baseUrl/notificaciones/token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'fcm_token': fcmToken}),
    );

    if (response.statusCode != 200) {
      print('Warn: Error al subir FCM token al backend');
    }
  }

  static Future<List<dynamic>> getMisNotificaciones() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.get(
      Uri.parse('$baseUrl/notificaciones/mis-notificaciones'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al cargar notificaciones');
    }
  }

  static Future<void> marcarNotificacionLeida(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/notificaciones/estado/$id'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al actualizar notificacion');
    }
  }

  // --- Endpoints de Perfil ---
  static Future<Map<String, dynamic>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.get(
      Uri.parse('$baseUrl/profile/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al cargar perfil');
    }
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.put(
      Uri.parse('$baseUrl/profile/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al actualizar perfil');
    }
  }

  // --- Endpoints de Pagos ---
  static Future<String> createStripeCheckout(int incidenteId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/pagos/$incidenteId/stripe'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['checkout_url'];
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al crear sesión de pago');
    }
  }

  static Future<Map<String, dynamic>> registrarPagoDirecto(int incidenteId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/pagos/$incidenteId/directo'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al registrar pago directo');
    }
  }

  static Future<Map<String, dynamic>> reintentarAnalisis(int incidenteId, String nuevaDescripcion) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/incidentes/$incidenteId/reintentar-analisis'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'nueva_descripcion': nuevaDescripcion}),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al reintentar análisis');
    }
  }

  // ─── CHAT ───

  static Future<List<Map<String, dynamic>>> getChatMessages(int incidenteId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('No autenticado');

    final response = await http.get(
      Uri.parse('$baseUrl/incidentes/$incidenteId/chat'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al obtener mensajes');
    }
  }

  static Future<Map<String, dynamic>> sendChatMessage(int incidenteId, String contenido) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/incidentes/$incidenteId/chat'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'contenido': contenido}),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al enviar mensaje');
    }
  }

  static Future<List<Map<String, dynamic>>> getMisChats() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('No autenticado');

    final response = await http.get(
      Uri.parse('$baseUrl/chats/mis-chats'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al obtener chats');
    }
  }

  static Future<List<Map<String, dynamic>>> getPersonalChat(int destinatarioId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('No autenticado');

    final response = await http.get(
      Uri.parse('$baseUrl/chats/personal/$destinatarioId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al obtener chat personal');
    }
  }

  static Future<Map<String, dynamic>> sendPersonalMessage(int destinatarioId, String contenido) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) throw Exception('No autenticado');

    final response = await http.post(
      Uri.parse('$baseUrl/chats/personal/$destinatarioId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'contenido': contenido}),
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al enviar mensaje');
    }
  }

  static Future<List<dynamic>> getMantenimientosTaller() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final response = await http.get(
      Uri.parse('$baseUrl/incidentes/mantenimientos'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) { await _handleUnauthorized(); throw Exception('Sesión expirada. Por favor inicia sesión nuevamente.'); }
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al obtener mantenimientos');
    }
  }

  static Future<void> actualizarEstadoIncidente(int incidenteId, String nuevoEstado) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final response = await http.patch(
      Uri.parse('$baseUrl/incidentes/$incidenteId/estado'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'nuevo_estado': nuevoEstado}),
    );

    if (response.statusCode != 200) {
      throw Exception('Error al actualizar estado');
    }
  }


}
