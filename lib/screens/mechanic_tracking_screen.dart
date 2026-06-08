import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';
import '../config/config.dart';

class MechanicTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> incidente;

  const MechanicTrackingScreen({Key? key, required this.incidente}) : super(key: key);

  @override
  _MechanicTrackingScreenState createState() => _MechanicTrackingScreenState();
}

class _MechanicTrackingScreenState extends State<MechanicTrackingScreen> {
  late Map<String, dynamic> _incidente;
  WebSocketChannel? _channel;
  Timer? _timer;
  bool _isTracking = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _incidente = Map.from(widget.incidente);
    if (_incidente['estado'] == 'en camino') {
      _startTracking();
    }
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  Future<void> _cambiarEstado(String nuevoEstado) async {
    setState(() => _isLoading = true);
    try {
      await ApiService.actualizarEstadoIncidente(_incidente['id'], nuevoEstado);
      setState(() {
        _incidente['estado'] = nuevoEstado;
      });

      if (nuevoEstado == 'en camino') {
        _startTracking();
      } else if (nuevoEstado == 'en atención') {
        _stopTracking();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startTracking() async {
    if (_isTracking) return;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Habilita el GPS')));
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    final tenantId = _incidente['tenant_id'];
    final roomId = 'incidente_${_incidente['id']}';

    final wsUrl = Config.apiUrl.replaceFirst('http', 'ws');
    final url = '$wsUrl/ws/$tenantId/$roomId?token=$token';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      setState(() => _isTracking = true);

      _timer = Timer.periodic(const Duration(seconds: 4), (timer) async {
        try {
          Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          if (_channel != null) {
            _channel!.sink.add(jsonEncode({
              "action": "telemetria",
              "incidente_id": _incidente['id'],
              "lat": position.latitude,
              "lng": position.longitude,
            }));
          }
        } catch (e) {
          print('Error getting location: $e');
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error WS: $e')));
    }
  }

  void _stopTracking() {
    _timer?.cancel();
    _channel?.sink.close();
    setState(() => _isTracking = false);
  }

  @override
  Widget build(BuildContext context) {
    final estado = _incidente['estado'];

    return Scaffold(
      appBar: AppBar(title: Text('Atención #${_incidente['id']}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Estado Actual:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(estado.toUpperCase(), style: const TextStyle(fontSize: 22, color: Colors.blue)),
                  const SizedBox(height: 32),
                  
                  if (estado == 'taller asignado')
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                      onPressed: () => _cambiarEstado('en camino'),
                      child: const Text('Comenzar Viaje (En Camino)', style: TextStyle(fontSize: 18)),
                    ),

                  if (estado == 'en camino') ...[
                    const Icon(Icons.gps_fixed, size: 64, color: Colors.green),
                    const SizedBox(height: 16),
                    const Text('Transmitiendo ubicación en vivo...', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.green)),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.orange),
                      onPressed: () => _cambiarEstado('en atención'),
                      child: const Text('Llegué (En Atención)', style: TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ],

                  if (estado == 'en atención') ...[
                    const Icon(Icons.build, size: 64, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text('Reparando vehículo en sitio.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.orange)),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.green),
                      onPressed: () => _cambiarEstado('finalizado'),
                      child: const Text('Servicio Finalizado', style: TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ],

                  if (estado == 'finalizado')
                    const Center(child: Text('¡Excelente trabajo! Has completado esta emergencia.', style: TextStyle(fontSize: 18, color: Colors.green), textAlign: TextAlign.center)),
                ],
              ),
            ),
    );
  }
}
