import os

path = 'lib/screens/reportar_incidente_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add imports
imports_old = "import '../config/theme.dart';"
imports_new = "import '../config/theme.dart';\nimport '../services/connectivity_service.dart';\nimport '../db/database_helper.dart';\nimport '../models/incidente_local.dart';"
content = content.replace(imports_old, imports_new)

# Modify submit
submit_old = """        final resultado = await ApiService.reportarIncidente(payload);
        
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
        }"""

submit_new = """        final connectivity = ConnectivityService();
        await connectivity.checkInitialConnection();
        
        if (connectivity.isOnline) {
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
        } else {
          final dbHelper = DatabaseHelper.instance;
          await dbHelper.create(IncidenteLocal(
            coordenadagps: payload['coordenadagps'] as String,
            descripcion: _descripcionController.text.trim(),
            fecha: DateTime.now().toIso8601String(),
            estado: "Pendiente de Sincronización",
            isSynced: false,
          ));
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sin conexión. Emergencia guardada localmente y se sincronizará luego.'),
                duration: Duration(seconds: 4),
                backgroundColor: Colors.orange,
              ),
            );
            Navigator.pop(context); // Volver al home o mis incidentes
          }
        }"""

content = content.replace(submit_old, submit_new)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("reportar_incidente_screen patched")
