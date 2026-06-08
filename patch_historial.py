import os

path = 'lib/screens/historial_incidentes_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add imports
imports_old = "import '../config/theme.dart';"
imports_new = "import '../config/theme.dart';\nimport '../db/database_helper.dart';\nimport '../models/incidente_local.dart';"
content = content.replace(imports_old, imports_new)

# Modify _refresh logic to include local incidentes
refresh_old = """  void _refresh() {
    setState(() {
      _incidentesFuture = ApiService.getMisIncidentes();
    });
  }"""

refresh_new = """  void _refresh() {
    setState(() {
      _incidentesFuture = _loadAllIncidentes();
    });
  }

  Future<List<dynamic>> _loadAllIncidentes() async {
    final remote = await ApiService.getMisIncidentes();
    final dbHelper = DatabaseHelper.instance;
    final locals = await dbHelper.readAllUnsyncedIncidentes();
    
    final List<dynamic> localAsMap = locals.map((l) => {
      'id': l.id,
      'estado': l.estado,
      'fecha': l.fecha,
      'coordenadagps': l.coordenadagps,
      'evidencias': [{'descripcion': l.descripcion}],
      'is_local': true,
    }).toList();
    
    return [...localAsMap, ...remote];
  }"""

content = content.replace(refresh_old, refresh_new)
content = content.replace("ApiService.getMisIncidentes()", "_loadAllIncidentes()")


# Modify card to show cloud_off for local incidents
card_old = """                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),"""

card_new = """                    if (inc['is_local'] == true)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.cloud_off, color: Colors.orange, size: 20),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),"""

content = content.replace(card_old, card_new)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("historial_incidentes_screen patched")
