import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mechanic_home_screen.dart';
import 'api/api_service.dart';
import 'services/fcm_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';
import 'config/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    // No usamos await aquí para no bloquear runApp, lo cual causa que 
    // el diálogo de permisos se quede oculto tras el Splash Screen.
    FcmService.initialize();
  } catch (e) {
    print('Firebase initialization error. Make sure to download and place google-services.json from Firebase Console: $e');
  }

  // Configurar monitoreo de conectividad para Offline-First Sync
  final connectivityService = ConnectivityService();
  final syncService = SyncService();
  
  connectivityService.connectionStatusStream.listen((isOnline) {
    if (isOnline) {
      print('Dispositivo en línea. Iniciando sincronización...');
      syncService.syncAll();
    }
  });

  runApp(const AppConductores());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class AppConductores extends StatelessWidget {
  const AppConductores({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Conductores',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: FutureBuilder<String?>(
        future: ApiService.isLoggedIn().then((isLogged) async {
          if (!isLogged) return null;
          return await ApiService.getRole();
        }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final role = snapshot.data;
          if (role == null) {
            return LoginScreen();
          } else if (role == 'Mecanico') {
            return MechanicHomeScreen();
          } else {
            return HomeScreen();
          }
        },
      ),
    );
  }
}
