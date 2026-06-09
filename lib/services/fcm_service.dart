import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobile_app/api/api_service.dart';

// Este handler tiene que ser top-level func (fuera de cualquier clase)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Inicializamos Firebase y guardamos algo o mostramos data (aunque FlutterLocalNotifications toma cargo
  // usualmente en Android si usamos notificaciones de datos/notification con FCM).
  print("Handling a background message: ${message.messageId}");
}

class FcmService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Stream para notificar a la UI que debe recargar datos
  static final StreamController<String> _refreshController = StreamController<String>.broadcast();
  static Stream<String> get onRefresh => _refreshController.stream;

  static void triggerRefresh() {
    _refreshController.add('refresh');
  }

  static Future<void> initialize() async {
    // 1. Pedir permisos para iOS/Android 13+
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // 2. Configurar Flutter Local Notifications para notificaciones Foreground
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Para iOS sería DarwinInitializationSettings()

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description: 'Este canal se usa para notificaciones importantes.',
      importance: Importance.max,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. Manejo de Background Messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 4. Manejo de Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        _flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: android.smallIcon ?? '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
        // Emitir evento para recargar la interfaz
        _refreshController.add('refresh');
      }
    });

    // 5. Obtener el Token para mandarlo al servidor Backend si está logueado
    bool isLogged = await ApiService.isLoggedIn();
    if (isLogged) {
      await updateTokenOnServer();
    }
  }

  static Future<void> updateTokenOnServer() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        print("FCM Token Obtenido: $token");
        await ApiService.updateFcmToken(token);
      }
    } catch (e) {
      print("Error obteniendo/subiendo el token FCM: $e");
    }
  }
}
