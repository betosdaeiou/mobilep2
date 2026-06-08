import os

path = 'lib/api/api_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add new methods at the end of the class, before the last closing brace
new_methods = """
  // ─── COTIZACIONES ───
  static Future<void> aceptarCotizacion(int cotizacionId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    
    final response = await http.post(
      Uri.parse('$baseUrl/incidentes/cotizaciones/$cotizacionId/aceptar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al aceptar cotización');
    }
  }

  // ─── PAGOS STRIPE ───
  static Future<String> crearPagoStripe(int incidenteId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    
    final response = await http.post(
      Uri.parse('$baseUrl/pagos/$incidenteId/stripe'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['checkout_url'];
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al crear pago');
    }
  }
}
"""

# Replace the last closing brace with the new methods
content = content.rstrip()
if content.endswith('}'):
    content = content[:-1] + new_methods

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("api_service.dart patched")
