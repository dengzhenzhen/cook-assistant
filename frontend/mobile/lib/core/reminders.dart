import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../data/cooking_session.dart';
import '../data/reminder_intents.dart';

final appReminders = Reminders();

class Reminders {
  VoidCallback? onTap;
  final plugin = FlutterLocalNotificationsPlugin();
  bool ready = false, exact = false;
  String? warning;
  Future<void> initialize({bool permissions = false}) async {
    if (kIsWeb) {
      warning = '网页预览不提供手机后台提醒，请安装 APK。';
      return;
    }
    if (!ready) {
      tzdata.initializeTimeZones();
      await plugin.initialize(
        onDidReceiveNotificationResponse: (_) => onTap?.call(),
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_cooking'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      ready = true;
    }
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (permissions) {
      final allowed = await android?.requestNotificationsPermission();
      if (allowed == false) warning = '通知权限未开启，后台无法提醒；请在系统设置中开启。';
      await android?.requestExactAlarmsPermission();
      await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true, badge: true);
    }
    exact = await android?.canScheduleExactNotifications() ?? false;
    if (android != null && !exact && warning == null) {
      warning = '精确闹钟未授权，系统可能延后提醒。';
    }
  }

  Future<void> update(CookingSession session) async {
    await initialize();
    if (!ready) return;
    await plugin.cancelAll();
    var id = 1;
    for (final intent in reminderIntents(session, DateTime.now())) {
      await plugin.zonedSchedule(
        id: id++,
        title: intent.title,
        body: intent.body,
        scheduledDate: tz.TZDateTime.from(intent.at, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'cooking_timers',
            '烹饪计时提醒',
            channelDescription: '正在烹饪的任务计时到期',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
