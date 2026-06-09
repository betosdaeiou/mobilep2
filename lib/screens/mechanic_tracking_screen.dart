import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
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

  LatLng? _currentLocation;
  LatLng? _incidentLocation;
  List<LatLng> _routePoints = [];
  bool _isFetchingRoute = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _incidente = Map.from(widget.incidente);
    
    // Parse incident location
    final coordStr = _incidente['coordenadagps']?.toString();
    if (coordStr != null && coordStr.contains(',')) {
      final parts = coordStr.split(',');
      if (parts.length == 2) {
        _incidentLocation = LatLng(double.parse(parts[0]), double.parse(parts[1]));
      }
    }

    if (_incidente['estado'] == 'en camino') {
      _startTracking();
    }
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    if (_isFetchingRoute) return;
    _isFetchingRoute = true;
    try {
      final url = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
          setState(() {
            _routePoints = coordinates.map((c) => LatLng(c[1], c[0])).toList();
          });
        }
      }
    } catch (e) {
      print("Error fetching route: $e");
    } finally {
      _isFetchingRoute = false;
    }
  }

  Future<void> _cambiarEstado(String nuevoEstado) async {
    setState(() => _isLoading = true);
    try {
      // Compatibilidad con el estado backend
      String estadoBackend = nuevoEstado;
      if (nuevoEstado == 'en atención') estadoBackend = 'en reparacion';

      await ApiService.actualizarEstadoIncidente(_incidente['id'], estadoBackend);
      setState(() {
        _incidente['estado'] = estadoBackend;
      });

      if (estadoBackend == 'en camino') {
        _startTracking();
      } else if (estadoBackend == 'en reparacion') {
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

    // Obtener ubicación inicial
    try {
      Position initialPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation = LatLng(initialPos.latitude, initialPos.longitude);
      });
      if (_incidentLocation != null && _currentLocation != null) {
        _fetchRoute(_currentLocation!, _incidentLocation!);
        _mapController.move(_currentLocation!, 15.0);
      }
    } catch (e) {
      print("Error initial location: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
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
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
          });
          
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
    
    String displayState = estado.toString().toUpperCase();
    if (estado == 'en reparacion') displayState = 'EN ATENCIÓN';

    return Scaffold(
      appBar: AppBar(title: Text('Atención #${_incidente['id']}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _incidentLocation ?? LatLng(-17.7833, -63.1821),
                      initialZoom: 14.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.mobile_app',
                      ),
                      PolylineLayer(
                        polylines: [
                          if (_routePoints.isNotEmpty)
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 5.0,
                              color: Colors.blueAccent,
                            ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          if (_incidentLocation != null)
                            Marker(
                              point: _incidentLocation!,
                              width: 50,
                              height: 50,
                              child: const Icon(Icons.location_on, color: Colors.red, size: 50),
                            ),
                          if (_currentLocation != null)
                            Marker(
                              point: _currentLocation!,
                              width: 50,
                              height: 50,
                              child: const Icon(Icons.directions_car, color: Colors.blue, size: 50),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))
                    ],
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Estado Actual:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(displayState, style: const TextStyle(fontSize: 22, color: Colors.blue)),
                      const SizedBox(height: 16),
                      
                      if (estado == 'taller asignado')
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                          onPressed: () => _cambiarEstado('en camino'),
                          child: const Text('Comenzar Viaje (En Camino)', style: TextStyle(fontSize: 18)),
                        ),

                      if (estado == 'en camino') ...[
                        const Text('Transmitiendo ubicación en vivo...', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.green)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.orange),
                          onPressed: () => _cambiarEstado('en atención'),
                          child: const Text('Llegué (En Atención)', style: TextStyle(fontSize: 18, color: Colors.white)),
                        ),
                      ],

                      if (estado == 'en reparacion') ...[
                        const Text('Reparando vehículo en sitio.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.orange)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.green),
                          onPressed: () => _cambiarEstado('finalizado'),
                          child: const Text('Servicio Finalizado', style: TextStyle(fontSize: 18, color: Colors.white)),
                        ),
                      ],

                      if (estado == 'finalizado' || estado == 'resuelto')
                        const Center(child: Text('¡Excelente trabajo! Has completado esta emergencia.', style: TextStyle(fontSize: 18, color: Colors.green), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
