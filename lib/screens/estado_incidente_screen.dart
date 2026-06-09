import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_service.dart';
import '../services/fcm_service.dart';
import 'chat_screen.dart';
import '../config/theme.dart';

class EstadoIncidenteScreen extends StatefulWidget {
  final Map<String, dynamic> incidente;
  final LatLng? gpsReal;

  const EstadoIncidenteScreen({
    Key? key,
    required this.incidente,
    this.gpsReal,
  }) : super(key: key);

  @override
  _EstadoIncidenteScreenState createState() => _EstadoIncidenteScreenState();
}

class _EstadoIncidenteScreenState extends State<EstadoIncidenteScreen>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _incidente;
  List<dynamic> _talleres = [];
  bool _isLoadingTalleres = true;
  bool _isAsignando = false;
  bool _isCancelando = false;
  late AnimationController _pulseController;

  final List<_EstadoPaso> _pasos = [
    _EstadoPaso('Pendiente', Icons.report_problem_rounded, Color(0xFFE53935)),
    _EstadoPaso('Taller Asignado', Icons.assignment_turned_in, Color(0xFFFB8C00)),
    _EstadoPaso('En Camino', Icons.local_shipping, Color(0xFF1E88E5)),
    _EstadoPaso('En Reparacion', Icons.build, Color(0xFF8E24AA)),
    _EstadoPaso('Resuelto', Icons.check_circle, Color(0xFF43A047)),
    _EstadoPaso('Pagado', Icons.paid_rounded, Color(0xFF00C853)),
  ];

  bool _isPagando = false;
  late StreamSubscription<String> _fcmSubscription;

  @override
  void initState() {
    super.initState();
    _incidente = widget.incidente;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _cargarTalleres();

    _fcmSubscription = FcmService.onRefresh.listen((_) {
      _recargarIncidente();
    });
  }

  @override
  void dispose() {
    _fcmSubscription.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _cargarTalleres() async {
    try {
      final talleres = await ApiService.getTalleresDisponibles(
        widget.gpsReal?.latitude,
        widget.gpsReal?.longitude,
        widget.incidente['id'],
      );
      if (mounted) {
        setState(() {
          _talleres = talleres;
          _isLoadingTalleres = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTalleres = false);
      }
    }
  }

  Future<void> _solicitarCotizacion(int tallerId) async {
    setState(() => _isAsignando = true);
    try {
      await ApiService.solicitarCotizacion(_incidente['id'], tallerId);
      if (mounted) {
        setState(() => _isAsignando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cotización solicitada exitosamente. Espera la oferta del taller.'),
            backgroundColor: Color(0xFF1E88E5),
          ),
        );
        // Recargar el incidente para ver el estado de las cotizaciones
        _recargarIncidente();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAsignando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _aceptarCotizacion(int cotizacionId) async {
    setState(() => _isAsignando = true);
    try {
      final updated = await ApiService.aceptarCotizacion(cotizacionId);
      if (mounted) {
        setState(() {
          _incidente = updated;
          _isAsignando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cotización aceptada. Taller asignado.'),
            backgroundColor: Color(0xFF43A047),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAsignando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _recargarIncidente() async {
    try {
      final incidentes = await ApiService.getMisIncidentes();
      final updated = incidentes.firstWhere((i) => i['id'] == _incidente['id']);
      if (mounted) {
        setState(() {
          _incidente = updated;
        });
      }
    } catch (e) {
      print('Error al recargar incidente: $e');
    }
  }

  Future<void> _realizarPagoStripe() async {
    setState(() => _isPagando = true);
    try {
      final checkoutUrl = await ApiService.createStripeCheckout(_incidente['id']);
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Abriendo pasarela de pago...'),
              backgroundColor: Color(0xFF673AB7),
            ),
          );
        }
      } else {
        throw 'No se pudo abrir el enlace de pago';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPagando = false);
    }
  }

  Future<void> _pagoDirecto() async {
    setState(() => _isPagando = true);
    try {
      final updated = await ApiService.registrarPagoDirecto(_incidente['id']);
      if (mounted) {
        setState(() {
          _incidente = updated;
          _isPagando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago registrado. Esperando confirmación del taller.'),
            backgroundColor: Color(0xFFFB8C00),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPagando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmarPagoDirecto() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2236),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.money_off_rounded, color: Color(0xFF43A047), size: 28),
            SizedBox(width: 10),
            Text('Pago en Efectivo', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          '¿Confirmas que has realizado el pago directamente al taller en efectivo o transferencia externa?',
          style: TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _pagoDirecto();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF43A047),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sí, Confirmar Pago'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelarIncidente() async {
    setState(() => _isCancelando = true);
    try {
      await ApiService.cancelarIncidente(_incidente['id']);
      if (mounted) {
        setState(() {
          _incidente['estado'] = 'Cancelado';
          _isCancelando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud cancelada exitosamente'),
            backgroundColor: Color(0xFF78909C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmarCancelacion() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2236),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFE53935), size: 28),
            SizedBox(width: 10),
            Text('Cancelar Solicitud',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas cancelar esta solicitud de emergencia? Esta acción no se puede deshacer.',
          style: TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Volver', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cancelarIncidente();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sí, Cancelar'),
          ),
        ],
      ),
    );
  }

  int _getEstadoIndex(String estado) {
    if (estado.toLowerCase() == 'cancelado') return -1;
    for (int i = 0; i < _pasos.length; i++) {
      if (_pasos[i].nombre.toLowerCase() == estado.toLowerCase()) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final estadoActual = _incidente['estado'] ?? 'Pendiente';
    final estadoIndex = _getEstadoIndex(estadoActual);
    final tallerAsignado = _incidente['taller'];
    final bool tieneTaller = tallerAsignado != null && _incidente['taller_id'] != null;
    final bool isCancelado = estadoActual.toLowerCase() == 'cancelado';
    final bool puedeCancelar = !isCancelado && (estadoActual.toLowerCase() == 'pendiente' || estadoActual.toLowerCase() == 'taller asignado');

    return Scaffold(
      backgroundColor: AppTheme.gray50,
      appBar: AppBar(
        title: const Text('Estado de Solicitud',
            style: TextStyle(color: AppTheme.gray900, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.gray900),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, true),
        ),
        actions: [
          if (_incidente['taller_id'] != null && !isCancelado)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF64B5F6), size: 20),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(incidenteId: _incidente['id']),
                  ),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // ─── ESTADO CANCELADO ───
            if (isCancelado) _buildCanceladoBanner(),

            // ─── TIMELINE DE ESTADO ───
            if (!isCancelado) _buildTimeline(estadoIndex),

            const SizedBox(height: 8),

            // ─── ANÁLISIS DE INTELIGENCIA ARTIFICIAL ───
            if (_incidente['analisis_ia'] != null) _buildAnalisisIA(_incidente['analisis_ia']),

            const SizedBox(height: 8),

            // ─── TALLER ASIGNADO ───
            if (tieneTaller && !isCancelado) _buildTallerAsignado(tallerAsignado),

            // ─── SECCIÓN DE PAGO ───
            if (estadoActual == 'Resuelto' && !_tienePagoPendiente()) _buildSeccionPago(),

            // ─── PAGO PENDIENTE CONFIRMACIÓN ───
            if (estadoActual == 'Resuelto' && _tienePagoPendiente()) _buildPagoPendienteBanner(),

            if (estadoActual == 'Pagado') _buildPagadoBanner(),

            // ─── LISTA DE TALLERES DISPONIBLES ───
            if (!tieneTaller && !isCancelado) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.build_circle,
                          color: Color(0xFF1E88E5), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Talleres Disponibles',
                              style: TextStyle(
                                  color: AppTheme.gray900,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text('Selecciona uno para solicitar asistencia',
                              style: TextStyle(
                                  color: Colors.black54, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildListaTalleres(),
            ],

            // ─── COTIZACIONES RECIBIDAS ───
            if (!tieneTaller && !isCancelado && _incidente['cotizaciones'] != null && (_incidente['cotizaciones'] as List).isNotEmpty)
              _buildCotizacionesRecibidas(_incidente['cotizaciones']),

            // ─── BOTÓN CANCELAR SOLICITUD ───
            if (puedeCancelar) _buildCancelButton(),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ─── WIDGET: BANNER CANCELADO ─────────────────────────────────
  Widget _buildCanceladoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF37474F),
            const Color(0xFF263238),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78909C).withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF78909C).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel_rounded,
                color: Color(0xFF90A4AE), size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            'SOLICITUD CANCELADA',
            style: TextStyle(
              color: Color(0xFF90A4AE),
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Esta solicitud de emergencia ha sido cancelada por el conductor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ─── WIDGET: BOTÓN CANCELAR ───────────────────────────────────
  Widget _buildCancelButton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isCancelando ? null : _confirmarCancelacion,
        icon: _isCancelando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFFE53935)),
              )
            : const Icon(Icons.cancel_outlined, size: 20),
        label: Text(_isCancelando ? 'Cancelando...' : 'Cancelar Solicitud'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE53935),
          side: const BorderSide(color: Color(0xFFE53935), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ─── WIDGET: TIMELINE ─────────────────────────────────────────
  Widget _buildTimeline(int estadoIndex) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A2236),
            const Color(0xFF1A2236).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: _pasos[estadoIndex].color.withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Status pill
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _pasos[estadoIndex]
                      .color
                      .withOpacity(0.1 + _pulseController.value * 0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _pasos[estadoIndex].color.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_pasos[estadoIndex].icono,
                        color: _pasos[estadoIndex].color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _pasos[estadoIndex].nombre.toUpperCase(),
                      style: TextStyle(
                        color: _pasos[estadoIndex].color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Timeline steps
          Row(
            children: List.generate(_pasos.length, (index) {
              final isActive = index <= estadoIndex;
              final isCurrent = index == estadoIndex;
              return Expanded(
                child: Column(
                  children: [
                    // Dot + line
                    Row(
                      children: [
                        if (index > 0)
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? _pasos[index].color
                                    : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: isCurrent ? 36 : 24,
                          height: isCurrent ? 36 : 24,
                          decoration: BoxDecoration(
                            color: isActive
                                ? _pasos[index].color
                                : Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: _pasos[index]
                                          .color
                                          .withOpacity(0.4),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : [],
                          ),
                          child: Icon(
                            _pasos[index].icono,
                            size: isCurrent ? 18 : 12,
                            color: isActive
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                          ),
                        ),
                        if (index < _pasos.length - 1)
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: index < estadoIndex
                                    ? _pasos[index + 1].color
                                    : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _pasos[index].nombre,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.35),
                        fontSize: 10,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ─── WIDGET: ANÁLISIS DE INTELIGENCIA ARTIFICIAL ────────────
  Widget _buildAnalisisIA(Map<String, dynamic> analisis) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF3F51B5).withOpacity(0.15),
            const Color(0xFF3F51B5).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5C6BC0).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5C6BC0).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.psychology, color: Color(0xFF3949AB), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Análisis Inteligente',
                  style: TextStyle(
                    color: Color(0xFF1A237E),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (analisis['NivelPrioridad'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F51B5).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF5C6BC0).withOpacity(0.5)),
                  ),
                  child: Text(
                    'Gravedad: ${analisis['NivelPrioridad']}',
                    style: const TextStyle(
                      color: Color(0xFF1A237E),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (analisis['Resumen'] != null) ...[
            const SizedBox(height: 16),
            Text(
              analisis['Resumen'],
              style: TextStyle(color: Colors.indigo.shade900, fontSize: 14, height: 1.4),
            ),
          ],
          if (analisis['Clasificacion'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: const Border(
                  left: BorderSide(color: Color(0xFF3F51B5), width: 3),
                ),
              ),
              child: Text(
                analisis['Clasificacion'],
                style: TextStyle(color: Colors.indigo.shade800, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── WIDGET: TALLER ASIGNADO ──────────────────────────────────
  Widget _buildTallerAsignado(Map<String, dynamic> taller) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF43A047).withOpacity(0.3),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.check_circle, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Taller Asignado',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    SizedBox(height: 2),
                    Text('Asistencia confirmada',
                        style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            taller['Nombre'] ?? 'Taller',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  taller['Direccion'] ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── WIDGET: LISTA DE TALLERES ────────────────────────────────
  Widget _buildListaTalleres() {
    if (_isLoadingTalleres) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
        ),
      );
    }

    if (_talleres.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2236),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: const Column(
          children: [
            Icon(Icons.search_off, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text('No hay talleres disponibles',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            SizedBox(height: 4),
            Text('Intenta más tarde',
                style: TextStyle(color: Colors.white30, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _talleres.length,
      itemBuilder: (context, index) {
        final taller = _talleres[index];
        final cap = taller['Cap'] ?? 0;
        final capmax = taller['Capmax'] ?? 1;
        final distancia = taller['distancia_km'];
        final porcentaje = capmax > 0 ? cap / capmax : 0.0;
        final recomendadoIa = taller['recomendado_ia'] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2236),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: recomendadoIa 
                    ? const Color(0xFF7986CB).withOpacity(0.5) 
                    : Colors.white.withOpacity(0.06),
                width: recomendadoIa ? 1.5 : 1.0,
            ),
            boxShadow: recomendadoIa ? [
              BoxShadow(
                color: const Color(0xFF3F51B5).withOpacity(0.15),
                blurRadius: 10,
                spreadRadius: 1,
              )
            ] : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _isAsignando
                  ? null
                  : () => _confirmarAsignacion(taller),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recomendadoIa)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3F51B5).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF5C6BC0).withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.psychology, color: Color(0xFF9FA8DA), size: 14),
                            SizedBox(width: 6),
                            Text(
                              '✨ RECOMENDADO POR IA',
                              style: TextStyle(
                                color: Color(0xFFC5CAE9),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF1E88E5).withOpacity(0.2),
                                const Color(0xFF1565C0).withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.build_rounded,
                              color: Color(0xFF42A5F5), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                taller['Nombre'] ?? 'Taller',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.white38, size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      taller['Direccion'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (distancia != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E88E5).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${distancia} km',
                              style: const TextStyle(
                                  color: Color(0xFF42A5F5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    // ─── SERVICIOS DEL TALLER ──────────────────────
                    if (taller['servicios'] != null && (taller['servicios'] as List).isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: (taller['servicios'] as List).map((svc) {
                          final nombre = svc['nombre'] as String? ?? '';
                          IconData icono = Icons.build_circle_outlined;
                          Color color = const Color(0xFF42A5F5);
                          if (nombre.contains('Eléctrico') || nombre.contains('Diagnóstico')) {
                            icono = Icons.electrical_services;
                            color = const Color(0xFFFFB300);
                          } else if (nombre.contains('Vulcaniz') || nombre.contains('Llanta')) {
                            icono = Icons.tire_repair;
                            color = const Color(0xFF66BB6A);
                          } else if (nombre.contains('Remolque')) {
                            icono = Icons.fire_truck;
                            color = const Color(0xFFEF5350);
                          } else if (nombre.contains('Chapa') || nombre.contains('Pintura')) {
                            icono = Icons.format_paint;
                            color = const Color(0xFFAB47BC);
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: color.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icono, color: color, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  nombre,
                                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Capacity bar
                    Row(
                      children: [
                        const Icon(Icons.people_alt_outlined,
                            color: Colors.white38, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: porcentaje.toDouble(),
                              backgroundColor: Colors.white.withOpacity(0.08),
                              valueColor: AlwaysStoppedAnimation(
                                porcentaje < 0.7
                                    ? const Color(0xFF43A047)
                                    : porcentaje < 0.9
                                        ? const Color(0xFFFB8C00)
                                        : const Color(0xFFE53935),
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$cap / $capmax',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Select button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isAsignando || _yaSolicitado(taller['Id'])
                            ? null
                            : () => _confirmarAsignacion(taller),
                        icon: Icon(_yaSolicitado(taller['Id']) ? Icons.pending_actions : Icons.handshake, size: 18),
                        label: Text(_yaSolicitado(taller['Id']) ? 'Solicitud Pendiente' : 'Solicitar Cotización'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _yaSolicitado(taller['Id']) ? Colors.white10 : const Color(0xFF1565C0),
                          foregroundColor: _yaSolicitado(taller['Id']) ? Colors.white38 : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmarAsignacion(Map<String, dynamic> taller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2236),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirmar Selección',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Deseas solicitar asistencia al taller "${taller['Nombre']}"?',
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              taller['Direccion'] ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _solicitarCotizacion(taller['Id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  bool _yaSolicitado(int tallerId) {
    if (_incidente['cotizaciones'] == null) return false;
    final cots = _incidente['cotizaciones'] as List;
    return cots.any((c) => c['taller_id'] == tallerId && c['estado'] == 'Solicitada');
  }

  Widget _buildCotizacionesRecibidas(List<dynamic> cotizaciones) {
    final ofrecidas = cotizaciones.where((c) => c['estado'] == 'Ofrecida').toList();
    if (ofrecidas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text(
            'Cotizaciones Recibidas',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        ...ofrecidas.map((cot) {
          final taller = cot['taller'] ?? {};
          final servicios = taller['servicios'] as List? ?? [];
          
          // Lógica simple de recomendación IA
          bool esRecomendado = false;
          final analisisIA = _incidente['analisis_ia'];
          if (analisisIA != null) {
            final resumen = (analisisIA['Resumen'] ?? '').toString().toLowerCase();
            final clasificacion = (analisisIA['Clasificacion'] ?? '').toString().toLowerCase();
            final textoIA = '$resumen $clasificacion';
            
            for (var svc in servicios) {
              final nombreSvc = (svc['nombre'] ?? '').toString().toLowerCase();
              // Si el servicio se menciona en el análisis de la IA, lo recomendamos
              if (nombreSvc.isNotEmpty && textoIA.contains(nombreSvc)) {
                esRecomendado = true;
                break;
              }
              // Mapeo común (ej: 'eléctrico' para 'Auxilio Eléctrico')
              if (nombreSvc.contains('eléctrico') && textoIA.contains('batería')) esRecomendado = true;
              if (nombreSvc.contains('vulcaniz') && textoIA.contains('llanta')) esRecomendado = true;
              if (nombreSvc.contains('remolque') && textoIA.contains('choque')) esRecomendado = true;
            }
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2236),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: esRecomendado ? const Color(0xFFFFB300) : const Color(0xFF1E88E5).withOpacity(0.3),
                width: esRecomendado ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esRecomendado) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.auto_awesome, color: Color(0xFFFFB300), size: 14),
                        SizedBox(width: 6),
                        Text('Recomendado por IA', style: TextStyle(color: Color(0xFFFFB300), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(taller['Nombre'] ?? 'Taller', 
                         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Bs. ${cot['monto']}', 
                         style: const TextStyle(color: Color(0xFF42A5F5), fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                if (cot['tiempo_estimado'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.timer, color: Colors.white54, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Tiempo estimado: ${cot['tiempo_estimado']}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                if (servicios.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: servicios.map((svc) {
                      final nombre = svc['nombre'] as String? ?? '';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E88E5).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.3)),
                        ),
                        child: Text(nombre, style: const TextStyle(color: Color(0xFF64B5F6), fontSize: 10)),
                      );
                    }).toList(),
                  ),
                ],
                if (cot['mensaje'] != null && cot['mensaje'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(cot['mensaje'], style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isAsignando ? null : () => _aceptarCotizacion(cot['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Aceptar Cotización'),
                  ),
                ),
              ],
            ),
          );
        }).toList(),

      ],
    );
  }

  Widget _buildSeccionPago() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A2236),
            const Color(0xFF1A2236).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF42A5F5).withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF42A5F5).withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF42A5F5), size: 48),
          const SizedBox(height: 16),
          const Text(
            'PAGAR SERVICIO',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'El taller ha marcado el servicio como resuelto. Por favor, selecciona un método de pago para finalizar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 24),
          
          // Botón Stripe
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isPagando ? null : _realizarPagoStripe,
              icon: const Icon(Icons.credit_card_rounded),
              label: const Text('Pagar con Tarjeta (Stripe)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF673AB7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Botón Pago Directo
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isPagando ? null : _confirmarPagoDirecto,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Pago Directo en Taller'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF43A047),
                side: const BorderSide(color: Color(0xFF43A047), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          
          if (_isPagando)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: CircularProgressIndicator(color: Color(0xFF42A5F5)),
            ),
        ],
      ),
    );
  }

  bool _tienePagoPendiente() {
    final pagos = _incidente['pagos'] as List<dynamic>? ?? [];
    return pagos.any((p) => p['estado'] == 'Pendiente Confirmación' && p['metodo'] == 'Directo');
  }

  Widget _buildPagoPendienteBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF57F17).withOpacity(0.15),
            const Color(0xFFF57F17).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFB8C00).withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFB8C00).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFFFFA726), size: 40),
          ),
          const SizedBox(height: 14),
          const Text(
            'ESPERANDO CONFIRMACIÓN',
            style: TextStyle(
              color: Color(0xFFFFCC80),
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tu pago en efectivo ha sido registrado. El taller debe confirmar que recibió el dinero para finalizar el servicio.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildPagadoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1B5E20).withOpacity(0.2),
            const Color(0xFF1B5E20).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF43A047).withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF43A047).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            'SERVICIO FINALIZADO',
            style: TextStyle(
              color: Color(0xFF81C784),
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'El pago ha sido procesado correctamente y el incidente está cerrado. ¡Gracias por usar nuestro servicio!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _EstadoPaso {
  final String nombre;
  final IconData icono;
  final Color color;

  const _EstadoPaso(this.nombre, this.icono, this.color);
}
