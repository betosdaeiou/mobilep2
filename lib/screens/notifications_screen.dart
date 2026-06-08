import 'package:flutter/material.dart';
import '../api/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  AppNotificationsState createState() => AppNotificationsState();
}

class AppNotificationsState extends State<NotificationsScreen> {
  List<dynamic> notificaciones = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotificaciones();
  }

  Future<void> _loadNotificaciones() async {
    try {
      final list = await ApiService.getMisNotificaciones();
      setState(() {
        notificaciones = list;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      setState(() => isLoading = false);
    }
  }

  Future<void> _marcarComoLeido(int id, int index) async {
    if (notificaciones[index]['estado'] == 'Leída') return;

    try {
      await ApiService.marcarNotificacionLeida(id);
      setState(() {
        notificaciones[index]['estado'] = 'Leída';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al marcar leída: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Notificaciones'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : notificaciones.isEmpty
              ? const Center(child: Text("No tienes notificaciones aún."))
              : ListView.builder(
                  itemCount: notificaciones.length,
                  itemBuilder: (context, index) {
                    final notif = notificaciones[index];
                    final isLeida = notif['estado'] == 'Leída';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      elevation: 2,
                      color: isLeida ? Colors.grey[100] : Colors.white,
                      child: ListTile(
                        leading: Icon(
                          isLeida ? Icons.notifications_none : Icons.notifications_active,
                          color: isLeida ? Colors.grey : Colors.indigo,
                        ),
                        title: Text(
                          notif['titulo'] ?? 'Sin Título',
                          style: TextStyle(
                            fontWeight: isLeida ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 5),
                            Text(notif['descripcion'] ?? ''),
                            const SizedBox(height: 5),
                            Text(
                              notif['fecha'] ?? '',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        onTap: () => _marcarComoLeido(notif['id'], index),
                      ),
                    );
                  },
                ),
    );
  }
}
