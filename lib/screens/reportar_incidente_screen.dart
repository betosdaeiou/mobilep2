import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../api/api_service.dart';
import '../config/theme.dart';
import 'estado_incidente_screen.dart';
import '../models/incidente_local.dart';
import '../db/database_helper.dart';

class ReportarIncidenteScreen extends StatefulWidget {
  final List<dynamic> vehiculosRegistrados;
  final LatLng? gpsReal;

  const ReportarIncidenteScreen({Key? key, required this.vehiculosRegistrados, this.gpsReal}) : super(key: key);

  @override
  _ReportarIncidenteScreenState createState() => _ReportarIncidenteScreenState();
}

class _ReportarIncidenteScreenState extends State<ReportarIncidenteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  int? _vehiculoSeleccionadoId;
  bool _isLoading = false;
  final List<File> _imagenes = [];
  static const int _maxImagenes = 10;

  // Audio Recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _audioPath;
  bool _isRecording = false;
  String _audioBase64 = "";

  Future<void> _tomarFoto() async {
    if (_imagenes.length >= _maxImagenes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Máximo 10 imágenes permitidas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final XFile? foto = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 960,
      imageQuality: 75,
    );

    if (foto != null) {
      setState(() {
        _imagenes.add(File(foto.path));
      });
    }
  }

  Future<void> _seleccionarGaleria() async {
    final espacioDisponible = _maxImagenes - _imagenes.length;
    if (espacioDisponible <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Máximo 10 imágenes permitidas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final List<XFile> fotos = await _picker.pickMultiImage(
      maxWidth: 1280,
      maxHeight: 960,
      imageQuality: 75,
    );

    if (fotos.isNotEmpty) {
      final agregar = fotos.take(espacioDisponible).map((f) => File(f.path)).toList();
      setState(() {
        _imagenes.addAll(agregar);
      });

      if (fotos.length > espacioDisponible) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Solo se agregaron $espacioDisponible de ${fotos.length} imágenes'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _eliminarImagen(int index) {
    setState(() {
      _imagenes.removeAt(index);
    });
  }

  void _verImagenCompleta(File imagen) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(imagen),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _imagenesABase64() {
    if (_imagenes.isEmpty) return "";
    
    final List<String> base64List = [];
    for (final img in _imagenes) {
      final bytes = img.readAsBytesSync();
      base64List.add(base64Encode(bytes));
    }
    return base64List.join('|||');
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/incidente_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig();
        await _audioRecorder.start(config, path: path);

        setState(() {
          _isRecording = true;
          _audioPath = path;
        });
      }
    } catch (e) {
      print("Error al iniciar grabación: $e");
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        final bytes = await File(path).readAsBytes();
        setState(() {
          _isRecording = false;
          _audioBase64 = base64Encode(bytes);
          _audioPath = path;
        });
      }
    } catch (e) {
      print("Error al detener grabación: $e");
    }
  }

  void _eliminarAudio() {
    setState(() {
      _audioPath = null;
      _audioBase64 = "";
    });
  }

  Future<void> _submitIncidente() async {
    if (_vehiculoSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona un vehículo')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      try {
        final fotosEncoded = _imagenesABase64();

        final payload = {
          "coordenadagps": widget.gpsReal != null ? "${widget.gpsReal!.latitude}, ${widget.gpsReal!.longitude}" : "-17.78111, -63.18123",
          "estado": "Reportado",
          "vehiculo_id": _vehiculoSeleccionadoId,
          "evidencia": {
            "descripcion": _descripcionController.text.trim(),
            "fotos": fotosEncoded,
            "audio": _audioBase64
          }
        };

        final resultado = await ApiService.reportarIncidente(payload);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => EstadoIncidenteScreen(
                incidente: resultado,
                gpsReal: widget.gpsReal,
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        
        final errorString = e.toString().toLowerCase();
        final isNetworkError = errorString.contains('socketexception') || 
                               errorString.contains('timeoutexception') || 
                               errorString.contains('failed host lookup') ||
                               errorString.contains('clientexception');

        if (isNetworkError) {
          final incidenteOffline = IncidenteLocal(
            coordenadagps: widget.gpsReal != null ? "${widget.gpsReal!.latitude}, ${widget.gpsReal!.longitude}" : "-17.78111, -63.18123",
            descripcion: _descripcionController.text.trim(),
            fecha: DateTime.now().toIso8601String(),
            estado: 'Reportado',
            isSynced: false,
            vehiculoId: _vehiculoSeleccionadoId,
            fotosBase64: _imagenesABase64(),
            audioBase64: _audioBase64,
          );
          
          await DatabaseHelper.instance.create(incidenteOffline);
          
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sin conexión. El reporte ha sido guardado y se enviará cuando recuperes el internet.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          Navigator.pop(context); // Volver a la pantalla anterior
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Error al reportar', style: TextStyle(color: AppTheme.gray900)),
              content: Text(
                e.toString().replaceFirst('Exception: ', ''),
                style: const TextStyle(color: AppTheme.gray700),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK', style: TextStyle(color: AppTheme.blue600)),
                )
              ],
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _mostrarOpcionesImagen() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppTheme.gray200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Agregar Evidencia Fotográfica',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.gray900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_imagenes.length}/$_maxImagenes imágenes',
                style: const TextStyle(fontSize: 14, color: AppTheme.gray500),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.blue50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt_outlined, color: AppTheme.blue600, size: 24),
                ),
                title: const Text('Tomar Foto', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.gray900)),
                subtitle: const Text('Usar la cámara del dispositivo', style: TextStyle(color: AppTheme.gray500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _tomarFoto();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: Colors.green, size: 24),
                ),
                title: const Text('Elegir de Galería', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.gray900)),
                subtitle: const Text('Seleccionar múltiples imágenes', style: TextStyle(color: AppTheme.gray500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarGaleria();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vehiculosRegistrados.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reportar Emergencia'),
        ),
        body: const Center(child: Text("Debes registrar al menos un vehículo antes de reportar.")),
      );
    }

    return Scaffold(
        appBar: AppBar(
          title: const Text('Reportar Emergencia', style: TextStyle(color: AppTheme.red600, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
        body: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.red50,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppTheme.red500, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Mantén la calma.\nNuestros mecánicos estarán contigo pronto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.red600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Vehículo Afectado',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                  value: _vehiculoSeleccionadoId,
                  items: widget.vehiculosRegistrados.map((v) {
                    return DropdownMenuItem<int>(
                      value: v['Id'],
                      child: Text('${v['Marca']} ${v['Modelo']} - ${v['Placa']}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _vehiculoSeleccionadoId = val;
                    });
                  },
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: '¿Qué sucedió? (Descripción)',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  validator: (v) => v!.isEmpty ? 'Por favor ingresa una descripción' : null,
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.gray200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
                    ]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.photo_camera_outlined, color: AppTheme.blue600, size: 24),
                          const SizedBox(width: 12),
                          const Text('Evidencia Fotográfica', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.gray900)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _imagenes.length >= _maxImagenes ? AppTheme.red50 : AppTheme.blue50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_imagenes.length}/$_maxImagenes',
                              style: TextStyle(
                                color: _imagenes.length >= _maxImagenes ? AppTheme.red600 : AppTheme.blue600,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (_imagenes.isNotEmpty) ...[
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _imagenes.length,
                          itemBuilder: (ctx, index) {
                            return Stack(
                              children: [
                                GestureDetector(
                                  onTap: () => _verImagenCompleta(_imagenes[index]),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image: FileImage(_imagenes[index]),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: IconButton(
                                    icon: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: AppTheme.red500, shape: BoxShape.circle),
                                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                                    ),
                                    onPressed: () => _eliminarImagen(index),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _imagenes.length >= _maxImagenes ? null : _mostrarOpcionesImagen,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(_imagenes.isEmpty ? 'Agregar Fotos' : 'Agregar Más Fotos'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.gray200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
                    ]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.mic_none_outlined, color: AppTheme.red500, size: 24),
                          SizedBox(width: 12),
                          Text('Descripción por Voz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.gray900)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_audioPath == null && !_isRecording)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _startRecording,
                            icon: const Icon(Icons.mic_none_outlined),
                            label: const Text('Grabar Explicación'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.red50,
                              foregroundColor: AppTheme.red600,
                              elevation: 0,
                            ),
                          ),
                        )
                      else if (_isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.red50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.fiber_manual_record, color: AppTheme.red500, size: 16),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('Grabando audio...', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.red600)),
                              ),
                              GestureDetector(
                                onTap: _stopRecording,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.stop, color: AppTheme.red600, size: 20),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('Audio Capturado', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green)),
                              ),
                              GestureDetector(
                                onTap: _eliminarAudio,
                                child: const Icon(Icons.delete_outline, color: AppTheme.red500, size: 24),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.blue50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppTheme.blue600, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ubicación GPS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.gray900)),
                            const SizedBox(height: 2),
                            Text(
                              widget.gpsReal != null
                                  ? '${widget.gpsReal!.latitude.toStringAsFixed(5)}, ${widget.gpsReal!.longitude.toStringAsFixed(5)}'
                                  : 'Capturando ubicación...',
                              style: const TextStyle(fontSize: 13, color: AppTheme.gray600),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        widget.gpsReal != null ? Icons.check_circle : Icons.sync,
                        color: widget.gpsReal != null ? Colors.green : Colors.orange,
                        size: 24,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitIncidente,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.red600,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('ENVIAR REPORTE (S.O.S)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                )
              ],
            ),
          ),
        )));
  }
}
