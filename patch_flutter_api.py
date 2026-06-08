import os

api_path = 'lib/api/api_service.dart'

with open(api_path, 'r', encoding='utf-8') as f:
    api = f.read()

old_search = """        // Buscar el primer tenant donde sea Conductor
        final conductorTenant = tenants.firstWhere(
          (t) => t['rol'] == 'Conductor', 
          orElse: () => null
        );

        if (conductorTenant == null) {
          throw Exception('Acceso Denegado. Solo Conductores pueden usar esta App.');
        }"""

new_search = """        // Buscar el primer tenant donde sea Conductor o Mecanico
        final targetTenant = tenants.firstWhere(
          (t) => t['rol'] == 'Conductor' || t['rol'] == 'Mecanico', 
          orElse: () => null
        );

        if (targetTenant == null) {
          throw Exception('Acceso Denegado. Solo Conductores o Mecánicos pueden usar esta App.');
        }"""

api = api.replace(old_search, new_search)

old_select = """            'tenant_id': conductorTenant['id']"""
new_select = """            'tenant_id': targetTenant['id']"""
api = api.replace(old_select, new_select)

old_prefs = """      await prefs.setString('access_token', token);
      await prefs.setInt('user_id', user['IdUsuario']);"""

new_prefs = """      await prefs.setString('access_token', token);
      await prefs.setInt('user_id', user['IdUsuario']);
      await prefs.setString('user_role', body['requires_tenant_selection'] == true ? targetTenant['rol'] : (user['Rol'] ?? 'Conductor'));"""

api = api.replace(old_prefs, new_prefs)


with open(api_path, 'w', encoding='utf-8') as f:
    f.write(api)

print("api_service.dart patched")
