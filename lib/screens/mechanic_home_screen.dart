import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';
import '../services/websocket_service.dart';
import 'mechanic_tracking_screen.dart';
import 'login_screen.dart';

class MechanicHomeScreen extends StatefulWidget {
  @override
  _MechanicHomeScreenState createState() => _MechanicHomeScreenState();
}

class _MechanicHomeScreenState extends State<MechanicHomeScreen> {
  List<dynamic> _incidentes = [];
  bool _isLoading = true;
  final WebSocketService _wsService = WebSocketService();

  @override
  void initState() {
    super.initState();
    _loadIncidentes();
    _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    try {
      final token = await ApiService.getToken();
      final tenantId = await ApiService.getTenantId() ?? 0;
      if (token != null) {
        _wsService.onMessageReceived = (data) {
          if (data['action'] == 'taller_asignado' || data['action'] == 'estado_actualizado' || data['action'] == 'nuevo_incidente') {
            _loadIncidentes();
          }
        };
        _wsService.connect(tenantId, 'mecanicos', token);
      }
    } catch (e) {
      print('WS Error in MechanicHomeScreen: $e');
    }
  }

  @override
  void dispose() {
    _wsService.disconnect();
    super.dispose();
  }

  Future<void> _loadIncidentes() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getMantenimientosTaller();
      final prefs = await SharedPreferences.getInstance();
      final myId = prefs.getInt('user_id');

      setState(() {
        _incidentes = data.where((incidente) {
          final estado = incidente['estado']?.toString().toLowerCase() ?? '';
          final bool isActive = estado == 'taller asignado' ||
              estado == 'en camino' ||
              estado == 'en reparacion' ||
              estado == 'resuelto' ||
              estado == 'finalizado';
          return isActive;
        }).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trabajos Asignados (Mecánico)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadIncidentes),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _incidentes.isEmpty
              ? const Center(child: Text('No tienes emergencias asignadas actualmente.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _incidentes.length,
                  itemBuilder: (context, index) {
                    final incidente = _incidentes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text('Emergencia #${incidente['id']}'),
                        subtitle: Text('Estado: ${incidente['estado']}'),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MechanicTrackingScreen(incidente: incidente),
                            ),
                          ).then((_) => _loadIncidentes());
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
