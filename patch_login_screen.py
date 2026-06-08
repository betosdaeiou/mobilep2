import os

login_path = 'lib/screens/login_screen.dart'

with open(login_path, 'r', encoding='utf-8') as f:
    login = f.read()

# Add imports
import_old = "import 'home_screen.dart';"
import_new = "import 'home_screen.dart';\nimport 'mechanic_home_screen.dart';\nimport 'package:shared_preferences/shared_preferences.dart';"
login = login.replace(import_old, import_new)

# Update nav
nav_old = """      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      }"""

nav_new = """      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? 'Conductor';

      if (mounted) {
        if (role == 'Mecanico') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MechanicHomeScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      }"""

login = login.replace(nav_old, nav_new)

with open(login_path, 'w', encoding='utf-8') as f:
    f.write(login)

print("login_screen.dart patched")
