import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../config/config.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessageReceived;

  void connect(int tenantId, String roomId, String token) {
    if (_channel != null) {
      _channel!.sink.close();
    }

    final wsUrl = Config.apiUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://');
    final url = '$wsUrl/ws/$tenantId/$roomId?token=$token';

    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channel!.stream.listen(
      (message) {
        if (onMessageReceived != null) {
          final data = jsonDecode(message);
          onMessageReceived!(data);
        }
      },
      onError: (error) {
        print('WebSocket Error: $error');
      },
      onDone: () {
        print('WebSocket connection closed.');
      },
    );
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close(status.goingAway);
      _channel = null;
    }
  }
}
