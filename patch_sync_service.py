import os

sync_path = 'lib/services/sync_service.dart'

with open(sync_path, 'r', encoding='utf-8') as f:
    sync_content = f.read()

# Update map
old_map = """    final payload = unsynced.map((e) => {
      'coordenadagps': e.coordenadagps,
      'descripcion': e.descripcion,
      'fecha': e.fecha,
      // The backend will generate ID and vehiculoconductor_id from JWT
    }).toList();"""

new_map = """    final payload = unsynced.map((e) => {
      'local_id': e.id.toString(),
      'coordenadagps': e.coordenadagps,
      'descripcion': e.descripcion,
      'fecha': e.fecha,
    }).toList();"""

sync_content = sync_content.replace(old_map, new_map)

# Update post body
old_body = "body: jsonEncode(payload),"
new_body = 'body: jsonEncode({"incidentes": payload}),'
sync_content = sync_content.replace(old_body, new_body)

# Add token header
old_headers = """        headers: {
          'Content-Type': 'application/json',
          // Assuming a token provider here, for demo purposes we just print
        },"""

new_headers = """        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },"""

sync_content = sync_content.replace(old_headers, new_headers)

# Add _getToken method
token_method = """
  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token') ?? '';
  }
}
"""
sync_content = sync_content.replace("}\n", token_method)
sync_content = "import 'package:shared_preferences/shared_preferences.dart';\n" + sync_content

with open(sync_path, 'w', encoding='utf-8') as f:
    f.write(sync_content)

print("sync_service.dart patched")
