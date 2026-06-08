class IncidenteLocal {
  final int? id;
  final String coordenadagps;
  final String? descripcion;
  final String fecha;
  final String estado;
  final bool isSynced;
  final int? vehiculoId;
  final String? fotosBase64;  // Fotos en base64 separadas por '|||'
  final String? audioBase64;  // Audio completo en base64

  IncidenteLocal({
    this.id,
    required this.coordenadagps,
    this.descripcion,
    required this.fecha,
    required this.estado,
    required this.isSynced,
    this.vehiculoId,
    this.fotosBase64,
    this.audioBase64,
  });

  IncidenteLocal copyWith({
    int? id,
    String? coordenadagps,
    String? descripcion,
    String? fecha,
    String? estado,
    bool? isSynced,
    int? vehiculoId,
    String? fotosBase64,
    String? audioBase64,
  }) {
    return IncidenteLocal(
      id: id ?? this.id,
      coordenadagps: coordenadagps ?? this.coordenadagps,
      descripcion: descripcion ?? this.descripcion,
      fecha: fecha ?? this.fecha,
      estado: estado ?? this.estado,
      isSynced: isSynced ?? this.isSynced,
      vehiculoId: vehiculoId ?? this.vehiculoId,
      fotosBase64: fotosBase64 ?? this.fotosBase64,
      audioBase64: audioBase64 ?? this.audioBase64,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'coordenadagps': coordenadagps,
      'descripcion': descripcion,
      'fecha': fecha,
      'estado': estado,
      'is_synced': isSynced ? 1 : 0,
      'vehiculo_id': vehiculoId,
      'fotos_base64': fotosBase64,
      'audio_base64': audioBase64,
    };
  }

  static IncidenteLocal fromMap(Map<String, Object?> map) {
    return IncidenteLocal(
      id: map['id'] as int?,
      coordenadagps: map['coordenadagps'] as String,
      descripcion: map['descripcion'] as String?,
      fecha: map['fecha'] as String,
      estado: map['estado'] as String,
      isSynced: (map['is_synced'] as int) == 1,
      vehiculoId: map['vehiculo_id'] as int?,
      fotosBase64: map['fotos_base64'] as String?,
      audioBase64: map['audio_base64'] as String?,
    );
  }
}
