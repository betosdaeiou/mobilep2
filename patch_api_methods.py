import os

api_path = 'lib/api/api_service.dart'

with open(api_path, 'r', encoding='utf-8') as f:
    api = f.read()

new_methods = """
  static Future<List<dynamic>> getMantenimientosTaller() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final response = await http.get(
      Uri.parse('$baseUrl/incidentes/mantenimientos'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al obtener mantenimientos');
    }
  }

  static Future<void> actualizarEstadoIncidente(int incidenteId, String nuevoEstado) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final response = await http.patch(
      Uri.parse('$baseUrl/incidentes/$incidenteId/estado'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'nuevo_estado': nuevoEstado}),
    );

    if (response.statusCode != 200) {
      throw Exception('Error al actualizar estado');
    }
  }
}
"""

# Replace the last closing brace with the new methods
api = api.rsplit('}', 1)[0] + new_methods

with open(api_path, 'w', encoding='utf-8') as f:
    f.write(api)

print("api_service.dart appended")
