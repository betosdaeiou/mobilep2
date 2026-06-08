import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../db/database_helper.dart';
import '../models/incidente_local.dart';
import '../config/config.dart';

class SyncService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

  /// Sincroniza todos los incidentes pendientes con el backend.
  /// Envía cada uno individualmente con fotos, audio y vehículo completos.
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
      try {
        final payload = {
          'local_id': inc.id.toString(),
          'coordenadagps': inc.coordenadagps,
          'descripcion': inc.descripcion ?? '',
          'fecha': inc.fecha,
          'vehiculo_id': inc.vehiculoId,
          'fotos': inc.fotosBase64 ?? '',
          'audio': inc.audioBase64 ?? '',
        };

        final response = await http.post(
          Uri.parse('${Config.apiUrl}/offline-sync/incidente-completo'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 60)); // timeout generoso para fotos grandes

        if (response.statusCode == 200 || response.statusCode == 201) {
          if (inc.id != null) {
            await dbHelper.markAsSynced(inc.id!);
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
        // No detener el loop; continuar con el siguiente
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
  Future<void> syncAll() async {
    await syncUnsyncedIncidentes();
    await syncPendingProfileUpdates();
  }
}
