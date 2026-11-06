import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/price_alert.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(
      settings: initializationSettings,
    );

    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();

    await androidImplementation?.requestExactAlarmsPermission();

    await _createNotificationChannels(
      androidImplementation,
    );

    await _createTestNotificationChannel(
      androidImplementation,
    );

    _initialized = true;
  }

  Future<void> _createNotificationChannels(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) {
      return;
    }

    const channel = AndroidNotificationChannel(
      'price_alerts',
      'Price Alerts',
      description: 'هشدارهای رسیدن و عبور قیمت',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await android.createNotificationChannel(
      channel,
    );
  }

  Future<void> _createTestNotificationChannel(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) {
      return;
    }

    const channel = AndroidNotificationChannel(
      'price_alerts_test',
      'Price Alerts Test',
      description: 'اعلان آزمایشی هشدار قیمت',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await android.createNotificationChannel(
      channel,
    );
  }

  Future<void> showPriceAlert({
    required String symbol,
    required double targetPrice,
    required double currentPrice,
    String? title,
    String? note,
    PriceAlert? alert,
  }) async {
    await initialize();

    final notificationTitle = _buildTitle(
      symbol: symbol,
      title: title,
      alert: alert,
    );

    final notificationBody = _buildBody(
      symbol: symbol,
      targetPrice: targetPrice,
      currentPrice: currentPrice,
      note: note,
      alert: alert,
    );

    final androidDetails = _buildAndroidDetails();

    final notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch % 2147483647;

    await _notifications.show(
      id: notificationId,
      title: notificationTitle,
      body: notificationBody,
      notificationDetails: notificationDetails,
    );

    await _playCustomSound(
      alert?.soundPath,
    );
  }

  Future<void> showCustomNotification({
    required String title,
    required String body,
  }) async {
    await initialize();
    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: _buildAndroidDetails()),
    );
  }

  Future<void> showTestNotification() async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'price_alerts_test',
      'Price Alerts Test',
      channelDescription: 'اعلان آزمایشی هشدار قیمت',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch % 2147483647;

    await _notifications.show(
      id: notificationId,
      title: 'تست هشدار قیمت',
      body: 'اگر این پیام را می‌بینی، سیستم اعلان اندروید فعال است.',
      notificationDetails: notificationDetails,
    );
  }

  String _buildTitle({
    required String symbol,
    required String? title,
    required PriceAlert? alert,
  }) {
    if (title != null && title.trim().isNotEmpty) {
      return title.trim();
    }

    if (alert != null && alert.title.trim().isNotEmpty) {
      return alert.title.trim();
    }

    switch (alert?.type) {
      case PriceAlertType.tradeTarget:
        return 'هشدار Target';

      case PriceAlertType.tradeStopLoss:
        return 'هشدار Stop Loss';

      case PriceAlertType.rangeExit:
        return 'هشدار خروج از محدوده';

      case PriceAlertType.multiStage:
        return 'هشدار مرحله‌ای';

      case PriceAlertType.crossing:
        return 'هشدار عبور قیمت';

      case PriceAlertType.target:
      case null:
        return 'هشدار قیمت';
    }
  }

  String _buildBody({
    required String symbol,
    required double targetPrice,
    required double currentPrice,
    required String? note,
    required PriceAlert? alert,
  }) {
    final buffer = StringBuffer();

    buffer.write(
      '$symbol | قیمت فعلی: '
      '${_formatPrice(currentPrice)}',
    );

    if (alert?.type == PriceAlertType.rangeExit) {
      final lower = alert?.lowerPrice;

      final upper = alert?.upperPrice;

      if (lower != null && upper != null) {
        buffer.write(
          ' | محدوده: '
          '${_formatPrice(lower)}'
          ' تا '
          '${_formatPrice(upper)}',
        );
      }
    } else {
      buffer.write(
        ' | قیمت هدف: '
        '${_formatPrice(targetPrice)}',
      );
    }

    final alertNote = note?.trim().isNotEmpty == true
        ? note!.trim()
        : alert?.note.trim() ?? '';

    if (alertNote.isNotEmpty) {
      buffer.write(
        '\n$alertNote',
      );
    }

    return buffer.toString();
  }

  AndroidNotificationDetails _buildAndroidDetails() {
    return const AndroidNotificationDetails(
      'price_alerts',
      'Price Alerts',
      channelDescription: 'هشدارهای رسیدن و عبور قیمت',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
    );
  }

  Future<void> _playCustomSound(
    String? soundPath,
  ) async {
    final path = soundPath?.trim();

    if (path == null || path.isEmpty) {
      return;
    }

    try {
      await _audioPlayer.stop();

      await _audioPlayer.play(
        DeviceFileSource(path),
      );
    } catch (_) {
      // Notification همچنان نمایش داده می‌شود.
    }
  }

  Future<void> stopCustomSound() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
    } catch (_) {}
  }

  String _formatPrice(
    double value,
  ) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value
        .toStringAsFixed(4)
        .replaceFirst(
          RegExp(r'0+$'),
          '',
        )
        .replaceFirst(
          RegExp(r'\.$'),
          '',
        );
  }
}
