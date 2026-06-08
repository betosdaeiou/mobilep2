import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_service.dart';
import '../config/theme.dart';
import '../services/websocket_service.dart';
import '../services/connectivity_service.dart';
import '../db/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'registrar_vehiculo_screen.dart';
import 'reportar_incidente_screen.dart';
import 'historial_incidentes_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<List<dynamic>> _vehiculosFuture;
  LatLng? _currentLocation;
  final MapController _mapController = MapController();
  bool _isLoadingGps = true;
  StreamSubscription<Position>? _positionStreamSubscription;
  final WebSocketService _webSocketService = WebSocketService();
  
  // Offline support
  final ConnectivityService _connectivityService = ConnectivityService();
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isOnline = true;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vehiculosFuture = _loadVehiculos();
    _initMap();
    _initWebSocket();
    _initConnectivity();
    _updatePendingCount();
  }

  Future<List<dynamic>> _loadVehiculos() async {
    try {
      final vehiculos = await ApiService.getVehiculos();
      // Cachear en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_vehiculos', jsonEncode(vehiculos));
      return vehiculos;
    } catch (e) {
      // Si falla (offline), cargar del cache
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_vehiculos');
      if (cached != null) {
        return List<dynamic>.from(jsonDecode(cached));
      }
      return [];
    }
  }

  void _initConnectivity() {
    _isOnline = _connectivityService.isOnline;
    _connectivitySubscription = _connectivityService.connectionStatusStream.listen((isOnline) {
      if (mounted) {
        setState(() => _isOnline = isOnline);
        if (isOnline) {
          _updatePendingCount();
        }
      }
    });
  }

  Future<void> _updatePendingCount() async {
    final count = await DatabaseHelper.instance.countUnsyncedIncidentes();
    if (mounted) {
      setState(() => _pendingCount = count);
    }
  }

  Future<void> _initWebSocket() async {
    try {
      final profile = await ApiService.getProfile();
      final userId = profile['Id'];
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      
      _webSocketService.connect(0, 'conductor_$userId', token);
      
      _webSocketService.onMessageReceived = (message) {
        if (!mounted) return;
        final action = message['action'];
        String msg = "Notificación recibida";
        if (action == 'nueva_cotizacion') {
           msg = "¡Un taller ha ofrecido una cotización!";
        } else if (action == 'incidente_aceptado') {
           msg = "Su incidente ha sido aceptado por el taller.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: const Color(0xFF4F46E5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      };
    } catch (e) {
      print("Error al conectar WS: $e");
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _connectivityService.dispose();
    _webSocketService.disconnect();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _currentLocation == null) {
      _initMap();
    }
  }

  Future<void> _initMap() async {
    if (!mounted) return;
    setState(() => _isLoadingGps = true);

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => _isLoadingGps = false);
      _showLocationServiceDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoadingGps = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => _isLoadingGps = false);
      _showPermissionDeniedDialog();
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoadingGps = false;
      });
      _mapController.move(_currentLocation!, 15.0);
    } catch (e) {
      if (mounted) setState(() {
        // Fallback a La Paz si el emulador falla en dar ubicación
        _currentLocation = const LatLng(-16.5, -68.15); 
        _isLoadingGps = false;
      });
      _mapController.move(const LatLng(-16.5, -68.15), 15.0);
    }

    // Iniciar escucha del GPS en tiempo real
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // actualiza si se mueve 5 metros
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentLocation!, _mapController.camera.zoom);
      }
    });
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('GPS Desactivado', style: TextStyle(color: AppTheme.gray900)),
          ],
        ),
        content: const Text(
          'Los servicios de ubicación están deshabilitados.\n\n'
          'Para poder usar el mapa y reportar incidentes, activa el GPS en la configuración de tu dispositivo.',
          style: TextStyle(color: AppTheme.gray700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.gray500)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Abrir Ajustes'),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.location_disabled, color: AppTheme.red500),
            SizedBox(width: 8),
            Text('Permiso Denegado', style: TextStyle(color: AppTheme.gray900)),
          ],
        ),
        content: const Text(
          'El permiso de ubicación fue denegado permanentemente.\n\n'
          'Ve a Configuración → Aplicaciones → esta app → Permisos → Ubicación y actívalo.',
          style: TextStyle(color: AppTheme.gray700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.gray500)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Abrir Ajustes'),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  void _refreshList() {
    setState(() {
      _vehiculosFuture = _loadVehiculos();
    });
    _updatePendingCount();
  }

  void _mostrarMisVehiculos() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return FutureBuilder<List<dynamic>>(
          future: _vehiculosFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }

            final vehiculos = snapshot.data ?? [];

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mi Garaje', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.gray900, letterSpacing: -0.5)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: AppTheme.blue600, size: 32),
                        onPressed: () async {
                          Navigator.pop(context);
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => RegistrarVehiculoScreen()),
                          );
                          if (result == true) _refreshList();
                          if (mounted) _mostrarMisVehiculos();
                        },
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: vehiculos.isEmpty
                      ? const Center(child: Text("No tienes vehículos registrados", style: TextStyle(color: AppTheme.gray500)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: vehiculos.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: AppTheme.gray100),
                          itemBuilder: (context, index) {
                            final vehiculo = vehiculos[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.blue50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.directions_car, color: AppTheme.blue600),
                              ),
                              title: Text('${vehiculo['Marca']} ${vehiculo['Modelo']}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.gray900)),
                              subtitle: Text('Placa: ${vehiculo['Placa']}', style: const TextStyle(color: AppTheme.gray500)),
                            );
                          },
                        ),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _abrirHistorial() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistorialIncidentesScreen(gpsReal: _currentLocation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Rastreo Activo', style: TextStyle(color: AppTheme.gray900, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        backgroundColor: Colors.white.withOpacity(0.85),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: AppTheme.gray700),
            tooltip: 'Mi Perfil',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppTheme.gray700),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.gray700),
            onPressed: () async {
              await ApiService.logout();
              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
              }
            },
          )
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? const LatLng(-17.7833, -63.1821),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.mobile_app',
              ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 80,
                      height: 80,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.blue600.withOpacity(0.2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.directions_car,
                            color: AppTheme.blue600,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          if (_isLoadingGps)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white, 
                  borderRadius: BorderRadius.circular(16), 
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, spreadRadius: 1)
                  ]
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 16),
                    Text("Buscando tu ubicación...", style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.gray900))
                  ],
                ),
              ),
            ),
          
          // ─── OFFLINE BANNER ───
          if (!_isOnline)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade700, Colors.orange.shade600],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Modo Offline',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          Text(
                            _pendingCount > 0
                                ? '$_pendingCount reporte(s) pendiente(s) de envío'
                                : 'Puedes reportar emergencias sin internet',
                            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (_pendingCount > 0)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_pendingCount',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -5))],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final vehiculos = await _vehiculosFuture;
                          if (mounted) {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReportarIncidenteScreen(
                                  vehiculosRegistrados: vehiculos,
                                  gpsReal: _currentLocation,
                                ),
                              ),
                            );
                            if (result == true) _refreshList();
                          }
                        },
                        icon: const Icon(Icons.warning_amber_rounded, size: 24),
                        label: const Text('S.O.S EMERGENCIA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.red500,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _mostrarMisVehiculos,
                            icon: const Icon(Icons.garage, size: 20),
                            label: const Text('Mi Garaje'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: AppTheme.gray200),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _abrirHistorial,
                            icon: const Icon(Icons.assignment_outlined, size: 20),
                            label: const Text('Solicitudes'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: AppTheme.gray200),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FloatingActionButton(
                          mini: true,
                          elevation: 0,
                          backgroundColor: AppTheme.blue50,
                          child: const Icon(Icons.my_location, color: AppTheme.blue600),
                          onPressed: () {
                            if (_currentLocation != null) {
                              _mapController.move(_currentLocation!, 16.0);
                            } else {
                              _initMap();
                            }
                          },
                        )
                      ],
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
