import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../config/theme.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _correoCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _ciCtl = TextEditingController();
  final _nombreCtl = TextEditingController();
  final _apellidosCtl = TextEditingController();
  
  DateTime? _fechaNac;
  bool _isLoading = false;

  void _register() async {
    if (_correoCtl.text.isEmpty || _passwordCtl.text.isEmpty || _ciCtl.text.isEmpty ||
        _nombreCtl.text.isEmpty || _apellidosCtl.text.isEmpty || _fechaNac == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Por favor completa todos los campos')));
      return;
    }

    setState(() => _isLoading = true);
    
    final data = {
      "Correo": _correoCtl.text,
      "Password": _passwordCtl.text,
      "CI": _ciCtl.text,
      "Nombre": _nombreCtl.text,
      "Apellidos": _apellidosCtl.text,
      "Fechanac": _fechaNac!.toIso8601String().split('T')[0]
    };

    try {
      await ApiService.registerConductor(data);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('¡Conductor registrado con éxito!')));
      Navigator.pop(context); // Volver al login
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""))));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _fechaNac) {
      setState(() {
        _fechaNac = picked;
      });
    }
  }

  Widget _buildTextField(String hint, TextEditingController ctl, IconData icon, {bool isObscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: ctl,
        obscureText: isObscure,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppTheme.gray400),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.gray50,
      appBar: AppBar(
        title: const Text('Registro de Conductor'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Crea tu cuenta',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gray900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ingresa tus datos personales para unirte',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.gray500,
                  ),
                ),
                const SizedBox(height: 32),
                _buildTextField('Carnet de Identidad (CI)', _ciCtl, Icons.badge_outlined),
                Row(
                  children: [
                    Expanded(child: _buildTextField('Nombres', _nombreCtl, Icons.person_outline)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTextField('Apellidos', _apellidosCtl, Icons.person_outline)),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppTheme.gray200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(
                      _fechaNac == null ? 'Fecha de Nacimiento' : 'Fecha: ${_fechaNac!.toIso8601String().split('T')[0]}',
                      style: TextStyle(
                        color: _fechaNac == null ? AppTheme.gray400 : AppTheme.gray900,
                        fontSize: 16,
                      ),
                    ),
                    leading: const Icon(Icons.calendar_today, color: AppTheme.gray400),
                    onTap: () => _selectDate(context),
                  ),
                ),
                _buildTextField('Correo electrónico', _correoCtl, Icons.email_outlined),
                _buildTextField('Contraseña', _passwordCtl, Icons.lock_outline, isObscure: true),
                
                const SizedBox(height: 24),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _register,
                        child: const Text('Registrarse'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
