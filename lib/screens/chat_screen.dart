import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../services/fcm_service.dart';

class ChatScreen extends StatefulWidget {
  final int? incidenteId;
  final int? destinatarioId;
  final String tituloChat;
  final String subtituloChat;

  const ChatScreen({
    super.key, 
    this.incidenteId,
    this.destinatarioId,
    this.tituloChat = 'Chat',
    this.subtituloChat = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _mensajes = [];
  bool _isLoading = true;
  bool _isSending = false;
  int? _miUsuarioId;
  StreamSubscription? _refreshSub;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadMessages();
    // Escuchar notificaciones push para refrescar
    _refreshSub = FcmService.onRefresh.listen((_) {
      _loadMessages();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    try {
      final profile = await ApiService.getProfile();
      if (mounted) {
        setState(() {
          _miUsuarioId = profile['Id'] ?? profile['id'];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    if (widget.incidenteId == null && widget.destinatarioId == null) return;
    try {
      final msgs = widget.incidenteId != null
          ? await ApiService.getChatMessages(widget.incidenteId!)
          : await ApiService.getPersonalChat(widget.destinatarioId!);
      if (mounted) {
        setState(() {
          _mensajes = msgs;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    _controller.clear();
    setState(() => _isSending = true);

    try {
      if (widget.incidenteId != null) {
        await ApiService.sendChatMessage(widget.incidenteId!, text);
      } else if (widget.destinatarioId != null) {
        await ApiService.sendPersonalMessage(widget.destinatarioId!, text);
      }
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Color _getRolColor(String? rol) {
    switch (rol) {
      case 'Conductor':
        return const Color(0xFF2196F3);
      case 'Taller':
        return const Color(0xFF4CAF50);
      case 'Mecánico':
      case 'Mecanico':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  String _formatTime(String? fecha) {
    if (fecha == null) return '';
    try {
      final parts = fecha.split(' ');
      if (parts.length >= 2) return parts[1].substring(0, 5);
    } catch (_) {}
    return fecha;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1523),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151C2F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF64B5F6), size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.tituloChat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (widget.subtituloChat.isNotEmpty || widget.incidenteId != null)
                  Text(
                    widget.subtituloChat.isNotEmpty ? widget.subtituloChat : 'Incidente #${widget.incidenteId}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF64B5F6)))
                : _mensajes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white.withOpacity(0.1)),
                            const SizedBox(height: 16),
                            Text(
                              'Sin mensajes aún',
                              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Envía un mensaje para iniciar la conversación',
                              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _mensajes.length,
                        itemBuilder: (ctx, i) => _buildMessageBubble(_mensajes[i]),
                      ),
          ),

          // Input area
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF151C2F),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 8, MediaQuery.of(context).padding.bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2236),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                      ),
                      borderRadius: BorderRadius.circular(23),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF2196F3).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: _isSending
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMe = msg['usuario_id'] == _miUsuarioId;
    final nombre = msg['nombre_usuario'] ?? 'Usuario';
    final rol = msg['rol_usuario'] ?? '';
    final rolColor = _getRolColor(rol);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: rolColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                _getInitials(nombre),
                style: TextStyle(color: rolColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF1E3A5F) : const Color(0xFF1A2236),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: Border.all(
                  color: isMe ? const Color(0xFF2196F3).withOpacity(0.3) : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nombre,
                            style: TextStyle(
                              color: rolColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: rolColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              rol,
                              style: TextStyle(color: rolColor, fontSize: 9, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    msg['contenido'] ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _formatTime(msg['fecha']),
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
