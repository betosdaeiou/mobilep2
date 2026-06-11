import 'package:flutter/material.dart';
import '../api/api_service.dart';
import 'estado_incidente_screen.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';

class HistorialIncidentesScreen extends StatefulWidget {
  final LatLng? gpsReal;

  const HistorialIncidentesScreen({Key? key, this.gpsReal}) : super(key: key);

  @override
  _HistorialIncidentesScreenState createState() =>
      _HistorialIncidentesScreenState();
}

class _HistorialIncidentesScreenState extends State<HistorialIncidentesScreen> {
  late Future<List<dynamic>> _incidentesFuture;
  String _filtroEstado = 'Todos';
  final Map<int, TextEditingController> _reintentarControllers = {};
  bool _isReintentando = false;

  final List<String> _estados = [
    'Todos',
    'Pendiente',
    'Taller Asignado',
    'En Camino',
    'En Reparacion',
    'Resuelto',
    'Cancelado'
  ];

  @override
  void initState() {
    super.initState();
    _incidentesFuture = _loadAllIncidentes();
  }

  void _refresh() {
    setState(() {
      _incidentesFuture = _loadAllIncidentes();
    });
  }

  Future<List<dynamic>> _loadAllIncidentes() async {
    return await ApiService.getMisIncidentes();
  }

  Color _colorEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'taller asignado':
        return const Color(0xFFFB8C00);
      case 'en camino':
        return const Color(0xFF1E88E5);
      case 'en reparacion':
        return const Color(0xFF8E24AA);
      case 'resuelto':
        return const Color(0xFF43A047);
      case 'cancelado':
        return const Color(0xFF78909C);
      case 'pendiente':
      default:
        return const Color(0xFFE53935);
    }
  }

  IconData _iconoEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'taller asignado':
        return Icons.assignment_turned_in;
      case 'en camino':
        return Icons.local_shipping;
      case 'en reparacion':
        return Icons.build;
      case 'resuelto':
        return Icons.check_circle;
      case 'cancelado':
        return Icons.cancel_rounded;
      case 'pendiente':
      default:
        return Icons.report_problem_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.gray50,
      appBar: AppBar(
        title: const Text('Historial de Incidentes',
            style: TextStyle(color: AppTheme.gray900, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.gray900),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── FILTROS DE ESTADO ───
          _buildFiltros(),

          // ─── LISTA DE INCIDENTES ───
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _incidentesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF1E88E5)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text('Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.white54)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _refresh,
                            child: const Text('Reintentar')),
                      ],
                    ),
                  );
                }

                final todos = snapshot.data ?? [];
                final incidentes = _filtroEstado == 'Todos'
                    ? todos
                    : _filtroEstado == 'Pendiente'
                        ? todos.where((i) => i['is_local'] == true || (i['estado'] ?? '').toString().toLowerCase().contains('pendiente')).toList()
                        : todos
                            .where((i) => (i['estado'] ?? '').toString().toLowerCase() == _filtroEstado.toLowerCase())
                            .toList();

                if (todos.isEmpty) {
                  return _buildEmptyState();
                }

                if (incidentes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.filter_list_off,
                            color: Colors.white.withOpacity(0.3), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'No hay incidentes con estado "$_filtroEstado"',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 15),
                        ),
                      ],
                    ),
                  );
                }

                // Stats header
                return Column(
                  children: [
                    _buildStats(todos),
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        itemCount: incidentes.length,
                        itemBuilder: (context, index) =>
                            _buildIncidenteCard(incidentes[index]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── FILTROS ──────────────────────────────────────────────────
  Widget _buildFiltros() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _estados.length,
        itemBuilder: (context, index) {
          final estado = _estados[index];
          final isSelected = _filtroEstado == estado;
          final color =
              estado == 'Todos' ? const Color(0xFF1E88E5) : _colorEstado(estado);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Text(estado),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              backgroundColor: const Color(0xFF1A2236),
              selectedColor: color.withOpacity(0.3),
              side: BorderSide(
                color: isSelected ? color : Colors.white.withOpacity(0.1),
              ),
              checkmarkColor: Colors.white,
              onSelected: (_) {
                setState(() => _filtroEstado = estado);
              },
            ),
          );
        },
      ),
    );
  }

  // ─── STATS MINI ───────────────────────────────────────────────
  Widget _buildStats(List<dynamic> todos) {
    final Map<String, int> conteo = {};
    for (final inc in todos) {
      final e = (inc['estado'] ?? 'Reportado').toString().toLowerCase();
      conteo[e] = (conteo[e] ?? 0) + 1;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2236),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: ['Pendiente', 'Taller Asignado', 'En Reparacion', 'Resuelto', 'Cancelado']
            .map((estado) {
          final count = conteo[estado.toLowerCase()] ?? 0;
          final color = _colorEstado(estado);
          return Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                estado,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ─── CARD DE INCIDENTE ────────────────────────────────────────
  Widget _buildIncidenteCard(Map<String, dynamic> inc) {
    final estado = inc['estado'] ?? 'Pendiente';
    final fecha = inc['fecha'] ?? '';
    final taller = inc['taller'];
    final evidencias = inc['evidencias'] as List<dynamic>? ?? [];
    final descripcion = evidencias.isNotEmpty
        ? evidencias.first['descripcion'] ?? ''
        : '';
    final coordenadas = inc['coordenadagps'] ?? '';
    final color = _colorEstado(estado);
    final icono = _iconoEstado(estado);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2236),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (inc['is_local'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: const [
                      Icon(Icons.cloud_off, color: Colors.white, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('Este reporte está pendiente de sincronización. Se enviará cuando haya internet.'),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.orange.shade700,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                ),
              );
              return;
            }
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EstadoIncidenteScreen(
                  incidente: inc,
                  gpsReal: widget.gpsReal,
                ),
              ),
            );
            if (result == true) _refresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    // Estado icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icono, color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    // Title + date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Incidente #${inc['id']}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  color: Colors.white38, size: 13),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(fecha,
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Estado badge
                    if (inc['is_local'] == true)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.cloud_off, color: Colors.orange, size: 20),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            estado,
                            style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Descripción
                if (descripcion.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      descripcion,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                // Info row: GPS + Taller
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (coordenadas.isNotEmpty) ...[
                      const Icon(Icons.location_on,
                          color: Colors.white30, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          coordenadas,
                          style: const TextStyle(
                              color: Colors.white30, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (taller != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF43A047).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.build,
                                color: Color(0xFF43A047), size: 13),
                            const SizedBox(width: 4),
                            Text(
                              taller['Nombre'] ?? 'Taller',
                              style: const TextStyle(
                                  color: Color(0xFF43A047), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_empty,
                                color: Colors.white38, size: 13),
                            SizedBox(width: 4),
                            Text('Sin taller',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                // ─── ANÁLISIS IA ───────────────────────────
                if (inc['analisis_ia'] != null) ...[ 
                  const SizedBox(height: 12),
                  _buildAnalisisIACard(inc['analisis_ia'], inc['id'] as int),
                ],

                // Mini timeline
                const SizedBox(height: 14),
                _buildMiniTimeline(estado),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── ANÁLISIS IA CARD (compacta o formulario de reintento) ──────
  Widget _buildAnalisisIACard(Map<String, dynamic> analisis, int incidenteId) {
    final esValida = analisis['informacion_valida'] != false; // null → válido

    if (!esValida) {
      // Crear controlador si no existe
      _reintentarControllers.putIfAbsent(incidenteId, () => TextEditingController());
      final ctrl = _reintentarControllers[incidenteId]!;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF7B4A00).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB300), size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Análisis IA — Información insuficiente',
                    style: TextStyle(
                      color: Color(0xFFFFCC80),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              analisis['Resumen'] ?? 'Por favor agrega más información sobre el incidente.',
              style: TextStyle(color: Colors.orange.shade200, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Describe el incidente: tipo de choque, daños, heridos, ubicación...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.black.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: const Color(0xFFFFB300).withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: const Color(0xFFFFB300).withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFFB300)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isReintentando
                    ? null
                    : () async {
                        final texto = ctrl.text.trim();
                        if (texto.isEmpty) return;
                        setState(() => _isReintentando = true);
                        try {
                          await ApiService.reintentarAnalisis(incidenteId, texto);
                          ctrl.clear();
                          _refresh();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isReintentando = false);
                        }
                      },
                icon: _isReintentando
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_isReintentando ? 'Analizando...' : 'Re-analizar con IA'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB300),
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Análisis válido
    final nivel = analisis['NivelPrioridad'] as String?;
    Color nivelColor = const Color(0xFFFFA726);
    if (nivel == 'Alta') nivelColor = const Color(0xFFE53935);
    if (nivel == 'Baja') nivelColor = const Color(0xFF43A047);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF3F51B5).withOpacity(0.18),
            const Color(0xFF3F51B5).withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5C6BC0).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Color(0xFF7986CB), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Análisis Inteligente',
                  style: TextStyle(
                    color: Color(0xFFC5CAE9),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (nivel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: nivelColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: nivelColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(color: nivelColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        nivel,
                        style: TextStyle(color: nivelColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (analisis['Resumen'] != null) ...[
            const SizedBox(height: 8),
            Text(
              analisis['Resumen'],
              style: TextStyle(color: Colors.indigo.shade100.withOpacity(0.8), fontSize: 12, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (analisis['Clasificacion'] != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: const Border(left: BorderSide(color: Color(0xFF7986CB), width: 2.5)),
              ),
              child: Text(
                analisis['Clasificacion'],
                style: const TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── MINI TIMELINE EN CADA CARD ───────────────────────────────
  Widget _buildMiniTimeline(String estadoActual) {
    final pasos = ['Pendiente', 'Taller Asignado', 'En Reparacion', 'Resuelto'];
    int currentIndex = pasos.indexWhere((p) => p.toLowerCase() == estadoActual.toLowerCase());
    if (currentIndex < 0) currentIndex = 0;

    return Row(
      children: List.generate(pasos.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepIndex = i ~/ 2;
          final isActive = stepIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: isActive
                    ? _colorEstado(pasos[stepIndex + 1])
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        } else {
          // Dot
          final stepIndex = i ~/ 2;
          final isActive = stepIndex <= currentIndex;
          final isCurrent = stepIndex == currentIndex;
          final color = _colorEstado(pasos[stepIndex]);

          return Container(
            width: isCurrent ? 14 : 10,
            height: isCurrent ? 14 : 10,
            decoration: BoxDecoration(
              color: isActive ? color : Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              boxShadow: isCurrent
                  ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)]
                  : [],
            ),
          );
        }
      }),
    );
  }

  // ─── EMPTY STATE ──────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.history, color: Colors.white24, size: 64),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sin historial de incidentes',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 18,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Los incidentes que reportes aparecerán aquí',
            style: TextStyle(color: Colors.white30, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
