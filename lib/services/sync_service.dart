import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../db/database_helper.dart';
import '../models/incidente_local.dart';
import '../config/config.dart';
import 'fcm_service.dart';

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();
  factory SyncService() => instance;

  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  static bool _isSyncing = false;

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

  /// Construye el mismo payload que el reporte online para garantizar compatibilidad.
  Map<String, dynamic> _buildReportPayload(IncidenteLocal inc) {
    return {
      'coordenadagps': inc.coordenadagps,
      'estado': 'Reportado',
      'vehiculo_id': inc.vehiculoId,
      'evidencia': {
        'descripcion': inc.descripcion ?? '',
        'fotos': inc.fotosBase64 ?? '',
        'audio': inc.audioBase64 ?? '',
      },
    };
  }

  /// Sincroniza todos los incidentes pendientes con el backend.
  Future<void> syncUnsyncedIncidentes() async {
    final unsynced = await dbHelper.readAllUnsyncedIncidentes();
    if (unsynced.isEmpty) return;

    print('[Sync] Intentando sincronizar ${unsynced.length} incidentes offline...');

    final token = await _getToken();
    if (token.isEmpty) {
      print('[Sync] No hay token de autenticación. Abortando sync.');
      return;
    }

    int exitosos = 0;
    int fallidos = 0;

    for (var inc in unsynced) {
      if (inc.vehiculoId == null) {
        fallidos++;
        print('[Sync] Incidente #${inc.id} sin vehiculo_id. No se puede sincronizar.');
        continue;
      }

      try {
        final payload = _buildReportPayload(inc);

        final response = await http.post(
          Uri.parse('${Config.apiUrl}/incidentes/reportar'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode == 401) {
          print('[Sync] Token expirado. Deteniendo sincronización.');
          return;
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          if (inc.id != null) {
            await dbHelper.deleteIncidente(inc.id!);
          }
          exitosos++;
          print('[Sync] Incidente local #${inc.id} sincronizado exitosamente.');
        } else {
          fallidos++;
          print('[Sync] Falló sync de incidente #${inc.id}: ${response.statusCode} — ${response.body}');
        }
      } catch (e) {
        fallidos++;
        print('[Sync] Error al sincronizar incidente #${inc.id}: $e');
      }
    }

    print('[Sync] Resultado: $exitosos exitosos, $fallidos fallidos de ${unsynced.length} total.');
  }

  /// Sincroniza ediciones de perfil pendientes con el backend.
  Future<void> syncPendingProfileUpdates() async {
    final pending = await dbHelper.readUnsyncedProfileUpdates();
    if (pending.isEmpty) return;

    print('[Sync] Sincronizando ${pending.length} actualizaciones de perfil pendientes...');

    final token = await _getToken();
    if (token.isEmpty) {
      print('[Sync] No hay token. Abortando sync de perfil.');
      return;
    }

    for (var row in pending) {
      try {
        final response = await http.put(
          Uri.parse('${Config.apiUrl}/profile/me'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: row['payload'] as String,
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 401) {
          print('[Sync] Token expirado. Deteniendo sync de perfil.');
          return;
        }

        if (response.statusCode == 200) {
          await dbHelper.markProfileUpdateSynced(row['id'] as int);
          print('[Sync] Perfil update #${row['id']} sincronizado.');
        } else {
          print('[Sync] Perfil update #${row['id']} falló: ${response.statusCode}');
        }
      } catch (e) {
        print('[Sync] Error sync perfil #${row['id']}: $e');
      }
    }
  }

  /// Sincroniza todo: incidentes + perfil
  Future<void> syncAll({bool notify = true}) async {
    if (_isSyncing) {
      print('[Sync] Sincronización en progreso. Ignorando nueva solicitud.');
      return;
    }
    _isSyncing = true;
    try {
      await syncUnsyncedIncidentes();
      await syncPendingProfileUpdates();
      if (notify) {
        FcmService.triggerRefresh();
      }
    } finally {
      _isSyncing = false;
    }
  }
}
