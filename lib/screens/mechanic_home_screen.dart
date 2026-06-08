import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';
import 'mechanic_tracking_screen.dart';
import 'login_screen.dart';

class MechanicHomeScreen extends StatefulWidget {
  @override
  _MechanicHomeScreenState createState() => _MechanicHomeScreenState();
}

class _MechanicHomeScreenState extends State<MechanicHomeScreen> {
  List<dynamic> _incidentes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIncidentes();
  }

  Future<void> _loadIncidentes() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getMantenimientosTaller();
      final prefs = await SharedPreferences.getInstance();
      final myId = prefs.getInt('user_id');

      setState(() {
        // Filtrar los que están asignados a este mecánico
        _incidentes = data.where((incidente) {
          final mecanicos = incidente['mecanicos'] as List<dynamic>? ?? [];
          final bool isMine = mecanicos.any((m) => m['id'] == myId);
          // Mostrar solo los activos
          final bool isActive = incidente['estado'] == 'taller asignado' ||
              incidente['estado'] == 'en camino' ||
              incidente['estado'] == 'en atención';
          return isMine && isActive;
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
