import os

path = 'lib/api/api_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix aceptarCotizacion
old_aceptar = """  static Future<void> aceptarCotizacion(int cotizacionId) async {
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
  }"""

new_aceptar = """  static Future<Map<String, dynamic>> aceptarCotizacion(int cotizacionId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    
    final response = await http.post(
      Uri.parse('$baseUrl/incidentes/cotizaciones/$cotizacionId/aceptar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al aceptar cotización');
    }
  }"""

content = content.replace(old_aceptar, new_aceptar)

# Fix Stripe and Directo
old_stripe = """  // ─── PAGOS STRIPE ───
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
  }"""

new_stripe = """  // ─── PAGOS STRIPE ───
  static Future<String> createStripeCheckout(int incidenteId) async {
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
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al crear pago stripe');
    }
  }

  static Future<Map<String, dynamic>> registrarPagoDirecto(int incidenteId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    
    final response = await http.post(
      Uri.parse('$baseUrl/pagos/$incidenteId/directo'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      // Necesitamos recargar el incidente para la UI, o el endpoint ya devuelve el pago.
      // Por consistencia con la UI que espera un incidente actualizado:
      return await _getIncidente(incidenteId, token);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Error al registrar pago');
    }
  }
  
  static Future<Map<String, dynamic>> _getIncidente(int id, String? token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/incidentes/mis-incidentes'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final incidentes = jsonDecode(response.body) as List;
      return incidentes.firstWhere((i) => i['id'] == id);
    }
    throw Exception('Error al obtener incidente actualizado');
  }"""

content = content.replace(old_stripe, new_stripe)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("api_service.dart fixed return types")
