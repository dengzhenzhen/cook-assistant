import 'cooking_session.dart';

class ReminderIntent {
  const ReminderIntent(this.at, this.title, this.body);
  final DateTime at;
  final String title, body;
}

/// Native alarms are scheduled before the app leaves foreground. Pending starts
/// are reminders only: they never claim that a person or appliance has started.
List<ReminderIntent> reminderIntents(CookingSession session, DateTime now) {
  final origin = DateTime.parse(session.json['origin'] as String);
  final result = <ReminderIntent>[];
  for (final task in session.tasks) {
    if (session.states[task['id']]?['status'] != 'running') continue;
    final at = origin.add(Duration(seconds: session.due(task)));
    if (!at.isAfter(now)) continue;
    result.add(
      ReminderIntent(
        at,
        '${task['name']} · 时间到',
        session.automatic(task) ? '请检查设备；返回应用查看下一步。' : '请检查食物，并确认完成当前步骤。',
      ),
    );
  }
  if (session.json['paused'] != true) {
    final templates = {for (final t in session.tasks) t['id']: t};
    final starts = <ReminderIntent>[];
    for (final row in session.upcoming()) {
      final at = origin.add(Duration(seconds: row['start_seconds'] as int));
      if (!at.isAfter(now)) continue;
      final task = templates[row['task_id']]!;
      starts.add(
        ReminderIntent(at, '该回厨房了：${task['name']}', '计划操作时间到了，请返回应用检查前置步骤并开始。'),
      );
    }
    // iOS permits at most 64 pending local notifications. Preserve running
    // timer alarms first, then the nearest upcoming operations.
    result.addAll(starts.take((63 - result.length).clamp(0, 63)));
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result;
}
