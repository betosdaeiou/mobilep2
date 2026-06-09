import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_service.dart';
import 'chat_screen.dart';

class MisChatsScreen extends StatefulWidget {
  const MisChatsScreen({super.key});

  @override
  State<MisChatsScreen> createState() => _MisChatsScreenState();
}

class _MisChatsScreenState extends State<MisChatsScreen> {
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getMisChats();
      if (mounted) {
        setState(() {
          _chats = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar chats: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final parts = dateStr.split(' ');
      return parts[0];
    } catch (_) {}
    return dateStr;
  }

  void _openChat(Map<String, dynamic> chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          incidenteId: chat['is_incidente'] ? chat['incidente_id'] : null,
          destinatarioId: !chat['is_incidente'] ? chat['destinatario_id'] : null,
          tituloChat: chat['titulo'] ?? 'Chat',
          subtituloChat: chat['subtitulo'] ?? '',
        ),
      ),
    ).then((_) {
      // Reload on pop
      _loadChats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1523),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151C2F),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mis Chats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadChats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF64B5F6)))
          : _chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 80, color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      Text(
                        'No tienes chats activos',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: ListView.separated(
                    itemCount: _chats.length,
                    separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      final isIncidente = chat['is_incidente'] == true;
                      final unread = chat['no_leidos'] ?? 0;

                      return ListTile(
                        onTap: () => _openChat(chat),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isIncidente ? const Color(0xFFE53935).withOpacity(0.15) : const Color(0xFF2196F3).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isIncidente ? Icons.warning_rounded : Icons.person,
                            color: isIncidente ? const Color(0xFFE53935) : const Color(0xFF2196F3),
                          ),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                chat['titulo'] ?? '',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatDate(chat['fecha_ultimo_mensaje']),
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  chat['ultimo_mensaje'] ?? '',
                                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (unread > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
