import 'package:flutter/material.dart'; // Necessário para usar Color
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // Callback ao clicar na notificação
        // O gerenciamento de navegação será feito via GlobalKey ou Listener no main
        print("🔔 Notificação clicada: ${response.payload}");
      },
    );

    // Cria o canal de notificação de alta prioridade
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'threat_alert_channel', // id
      'Alertas de Golpe', // title
      description: 'Notificações críticas sobre SMS maliciosos detectados.', // description
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> showThreatNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'threat_alert_channel',
      'Alertas de Golpe',
      channelDescription: 'Notificações críticas sobre SMS maliciosos detectados.',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Alerta de Segurança',
      color: Color(0xFFFF0000), // Cor Vermelha
      icon: '@mipmap/ic_launcher',
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
        
    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }
}