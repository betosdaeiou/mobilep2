import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';
import '../services/connectivity_service.dart';
import '../db/database_helper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _isOffline = false;
  bool _loadedFromCache = false;
  int _pendingProfileUpdates = 0;

  // Controladores de cuenta
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();

  // Controladores de conductor
  final _ciController = TextEditingController();
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  DateTime? _fechaNac;

  bool _showPassword = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPendingCount();
  }

  @override
  void dispose() {
    _correoController.dispose();
    _passwordController.dispose();
    _ciController.dispose();
    _nombreController.dispose();
    _apellidosController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingCount() async {
    final count = await DatabaseHelper.instance.countUnsyncedProfileUpdates();
    if (mounted) setState(() => _pendingProfileUpdates = count);
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
      _loadedFromCache = false;
    });

    // Verificar conectividad
    final connectivity = ConnectivityService();
    await connectivity.checkInitialConnection();
    _isOffline = !connectivity.isOnline;

    try {
      final profile = await ApiService.getProfile();
      // Cachear el perfil para uso offline
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_profile', jsonEncode(profile));

      setState(() {
        _profile = profile;
        _isOffline = false;
        _populateFields();
        _loading = false;
      });
    } catch (e) {
      // Intentar cargar del cache
      final cached = await _loadCachedProfile();
      if (cached != null) {
        setState(() {
          _profile = cached;
          _loadedFromCache = true;
          _isOffline = true;
          _populateFields();
          _loading = false;
        });
      } else {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
          _isOffline = true;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_profile');
    if (cached != null) {
      return Map<String, dynamic>.from(jsonDecode(cached));
    }
    return null;
  }

  void _populateFields() {
    if (_profile == null) return;

    _correoController.text = _profile!['Correo'] ?? '';

    final conductor = _profile!['conductor'];
    if (conductor != null) {
      _ciController.text = conductor['CI'] ?? '';
      _nombreController.text = conductor['Nombre'] ?? '';
      _apellidosController.text = conductor['Apellidos'] ?? '';
      if (conductor['Fechanac'] != null) {
        try {
          _fechaNac = DateTime.parse(conductor['Fechanac']);
        } catch (_) {}
      }
    }
    _hasChanges = false;
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaNac ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4F46E5),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _fechaNac) {
      setState(() {
        _fechaNac = picked;
        _hasChanges = true;
      });
    }
  }

  Map<String, dynamic> _buildPayload() {
    final payload = <String, dynamic>{};

    if (_correoController.text.isNotEmpty &&
        _correoController.text != _profile!['Correo']) {
      payload['Correo'] = _correoController.text.trim();
    }
    if (_passwordController.text.isNotEmpty) {
      payload['Password'] = _passwordController.text;
    }
    if (_ciController.text.isNotEmpty) {
      payload['conductor_ci'] = _ciController.text.trim();
    }
    if (_nombreController.text.isNotEmpty) {
      payload['conductor_nombre'] = _nombreController.text.trim();
    }
    if (_apellidosController.text.isNotEmpty) {
      payload['conductor_apellidos'] = _apellidosController.text.trim();
    }
    if (_fechaNac != null) {
      payload['conductor_fechanac'] =
          '${_fechaNac!.year}-${_fechaNac!.month.toString().padLeft(2, '0')}-${_fechaNac!.day.toString().padLeft(2, '0')}';
    }
    return payload;
  }

  /// Aplica los cambios al perfil cacheado localmente
  void _applyChangesLocally(Map<String, dynamic> payload) {
    if (_profile == null) return;

    if (payload.containsKey('Correo')) {
      _profile!['Correo'] = payload['Correo'];
    }
    final conductor = _profile!['conductor'];
    if (conductor != null) {
      if (payload.containsKey('conductor_ci')) {
        conductor['CI'] = payload['conductor_ci'];
      }
      if (payload.containsKey('conductor_nombre')) {
        conductor['Nombre'] = payload['conductor_nombre'];
      }
      if (payload.containsKey('conductor_apellidos')) {
        conductor['Apellidos'] = payload['conductor_apellidos'];
      }
      if (payload.containsKey('conductor_fechanac')) {
        conductor['Fechanac'] = payload['conductor_fechanac'];
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = _buildPayload();

    // Verificar conectividad
    final connectivity = ConnectivityService();
    await connectivity.checkInitialConnection();

    if (connectivity.isOnline) {
      try {
        final updatedProfile = await ApiService.updateProfile(payload);

        // Actualizar cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_profile', jsonEncode(updatedProfile));

        setState(() {
          _profile = updatedProfile;
          _populateFields();
          _passwordController.clear();
          _saving = false;
          _isOffline = false;
          _loadedFromCache = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Perfil actualizado correctamente'),
                ],
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } catch (e) {
        // Si falla la red, guardar offline
        await _saveProfileOffline(payload);
      }
    } else {
      await _saveProfileOffline(payload);
    }
  }

  Future<void> _saveProfileOffline(Map<String, dynamic> payload) async {
    try {
      // Guardar en la cola de sincronización
      await DatabaseHelper.instance.createPendingProfileUpdate(
        jsonEncode(payload),
      );

      // Aplicar cambios localmente al cache
      _applyChangesLocally(payload);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_profile', jsonEncode(_profile));

      setState(() {
        _populateFields();
        _passwordController.clear();
        _saving = false;
      });

      await _loadPendingCount();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.cloud_off, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sin conexión. Cambios guardados localmente.\nSe sincronizarán al recuperar internet.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Error al guardar localmente: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4F46E5)),
                  SizedBox(height: 16),
                  Text('Cargando perfil...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _error != null && _profile == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadProfile,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfile,
                  color: const Color(0xFF4F46E5),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // ─── OFFLINE BANNER ───
                        if (_isOffline || _loadedFromCache)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.orange.shade700, Colors.orange.shade600],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8),
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
                                        _pendingProfileUpdates > 0
                                            ? 'Datos desde caché. $_pendingProfileUpdates cambio(s) pendiente(s).'
                                            : 'Datos cargados desde caché local.',
                                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_pendingProfileUpdates > 0)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$_pendingProfileUpdates',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                        // Avatar + Info Header
                        _buildProfileHeader(),
                        const SizedBox(height: 20),

                        // Error message
                        if (_error != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                                ),
                              ],
                            ),
                          ),

                        // Sección: Datos de Cuenta
                        _buildSectionCard(
                          icon: Icons.email_outlined,
                          iconColor: const Color(0xFF4F46E5),
                          title: 'Datos de Cuenta',
                          subtitle: 'Correo electrónico y seguridad',
                          children: [
                            _buildTextField(
                              controller: _correoController,
                              label: 'Correo Electrónico',
                              icon: Icons.alternate_email,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _passwordController,
                              label: 'Nueva Contraseña',
                              icon: Icons.lock_outline,
                              hint: 'Dejar vacío si no deseas cambiarla',
                              obscure: !_showPassword,
                              suffix: IconButton(
                                icon: Icon(
                                  _showPassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Sección: Datos Personales
                        _buildSectionCard(
                          icon: Icons.person_outline,
                          iconColor: const Color(0xFF7C3AED),
                          title: 'Datos Personales',
                          subtitle: 'Información de conductor',
                          children: [
                            _buildTextField(
                              controller: _ciController,
                              label: 'Cédula de Identidad',
                              icon: Icons.badge_outlined,
                              keyboardType: TextInputType.text,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _nombreController,
                                    label: 'Nombre',
                                    icon: Icons.person,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextField(
                                    controller: _apellidosController,
                                    label: 'Apellidos',
                                    icon: Icons.people,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            GestureDetector(
                              onTap: _selectDate,
                              child: AbsorbPointer(
                                child: _buildTextField(
                                  controller: TextEditingController(
                                    text: _fechaNac != null
                                        ? '${_fechaNac!.day.toString().padLeft(2, '0')}/${_fechaNac!.month.toString().padLeft(2, '0')}/${_fechaNac!.year}'
                                        : '',
                                  ),
                                  label: 'Fecha de Nacimiento',
                                  icon: Icons.calendar_today,
                                  hint: 'Toca para seleccionar',
                                  suffix: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Botón Guardar
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _saveProfile,
                            icon: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(_isOffline ? Icons.save_outlined : Icons.save_rounded),
                            label: Text(
                              _saving
                                  ? 'Guardando...'
                                  : _isOffline
                                      ? 'Guardar Localmente'
                                      : 'Guardar Cambios',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isOffline ? Colors.orange.shade700 : const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              shadowColor: (_isOffline ? Colors.orange : const Color(0xFF4F46E5)).withOpacity(0.4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildProfileHeader() {
    final correo = _profile?['Correo'] ?? '?';
    final rol = _profile?['rol_nombre'] ?? 'Conductor';
    final conductor = _profile?['conductor'];
    final nombre = conductor?['Nombre'] ?? '';
    final apellidos = conductor?['Apellidos'] ?? '';
    final fullName = '$nombre $apellidos'.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
            ),
            child: Center(
              child: Text(
                correo.isNotEmpty ? correo[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Nombre
          Text(
            fullName.isNotEmpty ? fullName : correo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          // Correo
          if (fullName.isNotEmpty)
            Text(
              correo,
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
            ),
          const SizedBox(height: 10),
          // Badge de rol
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isOffline ? Colors.orange : const Color(0xFF34D399),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isOffline ? '$rol (Offline)' : rol,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // Fields
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onChanged: (_) => _markChanged(),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF8F8FC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
        ),
        labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      ),
    );
  }
}
