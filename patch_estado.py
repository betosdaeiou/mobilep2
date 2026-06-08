import os

path = 'lib/screens/estado_incidente_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old_cotizacion = """                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(taller['Nombre'] ?? 'Taller', 
                         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Bs. ${cot['monto']}', 
                         style: const TextStyle(color: Color(0xFF42A5F5), fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),"""

new_cotizacion = """                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(taller['Nombre'] ?? 'Taller', 
                         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Bs. ${cot['monto']}', 
                         style: const TextStyle(color: Color(0xFF42A5F5), fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                if (cot['tiempo_estimado'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.timer, color: Colors.white54, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Tiempo estimado: ${cot['tiempo_estimado']}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),"""

content = content.replace(old_cotizacion, new_cotizacion)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("estado_incidente_screen.dart patched")
