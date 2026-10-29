import 'models.dart';

/// All timestamps use a stable plan origin; never a UI tick count.
class CookingSession {
  CookingSession(this.json);
  final Map<String, dynamic> json;
  factory CookingSession.start(
    Map<String, dynamic> snapshot,
    String id,
    DateTime now,
  ) {
    final rows = snapshot['plan']['tasks'] as List;
    final first = rows
        .map((row) => row['start_seconds'] as int)
        .reduce((a, b) => a < b ? a : b);
    final timed = snapshot['request']['target_finish_seconds'] != null;
    return CookingSession({
      'id': id,
      'snapshot': cloneJson(snapshot),
      'origin': timed
          ? (snapshot['origin'] ?? now.toUtc().toIso8601String())
          : now.toUtc().subtract(Duration(seconds: first)).toIso8601String(),
      'started_at': now.toUtc().toIso8601String(),
      'states': <String, dynamic>{},
      'auto_seconds': 60,
      'paused': false,
      'resting': false,
      'clock_version': 2,
    });
  }

  /// Old clients shifted the plan origin to start immediately. Keep recorded
  /// execution offsets unchanged, and recover the original dinner deadline in
  /// that same coordinate system instead of rewriting completed facts.
  bool restoreDinnerTarget() {
    if (json['clock_version'] == 2 ||
        request['target_finish_seconds'] == null ||
        snapshot['origin'] == null) {
      return false;
    }
    final originalTarget = request['target_finish_seconds'] as int;
    final dinner = DateTime.parse(
      snapshot['origin'] as String,
    ).add(Duration(seconds: originalTarget));
    final restored = dinner
        .difference(DateTime.parse(json['origin'] as String))
        .inSeconds
        .clamp(0, 2147483647);
    final shift = restored - originalTarget;
    request['target_finish_seconds'] = restored;
    for (final row in snapshot['plan']['tasks'] as List) {
      if (states.containsKey(row['task_id'])) continue;
      row['start_seconds'] = ((row['start_seconds'] as int) + shift).clamp(
        0,
        2147483647,
      );
      if (row['end_seconds'] != null) {
        row['end_seconds'] = ((row['end_seconds'] as int) + shift).clamp(
          0,
          2147483647,
        );
      }
    }
    if (snapshot['plan']['finish_seconds'] != null) {
      snapshot['plan']['finish_seconds'] =
          ((snapshot['plan']['finish_seconds'] as int) + shift).clamp(
            0,
            2147483647,
          );
    }
    json['clock_version'] = 2;
    json['needs_replan'] = true;
    enterRest();
    return true;
  }

  Map<String, dynamic> get snapshot =>
      (json['snapshot'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get request =>
      (snapshot['request'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get tasks => (request['tasks'] as List)
      .map((t) => (t as Map).cast<String, dynamic>())
      .toList();
  Map<String, dynamic> get states =>
      (json['states'] as Map).cast<String, dynamic>();
  int elapsed(DateTime now) => now
      .difference(DateTime.parse(json['origin'] as String))
      .inSeconds
      .clamp(0, 2147483647);
  bool get finished =>
      tasks.every((t) => states[t['id']]?['status'] == 'completed');
  bool automatic(Map<String, dynamic> task) {
    if (task['attention_type'] != 'passive') return false;
    final resources = <String>{
      ...(task['resources'] as Map? ?? {}).keys.cast<String>(),
    };
    final templates = {for (final t in tasks) t['id']: t};
    Set<String> ancestors(String id) {
      final result = <String>{id};
      for (final dependency in templates[id]?['dependencies'] as List? ?? []) {
        result.addAll(ancestors(dependency as String));
      }
      return result;
    }

    final preceding = ancestors(task['id'] as String);
    for (final h in request['holds'] as List? ?? []) {
      final releasedBefore =
          h['end_task'] != null &&
          h['end_task'] != task['id'] &&
          preceding.contains(h['end_task']);
      if (preceding.contains(h['start_task']) && !releasedBefore) {
        resources.add(h['resource'] as String);
      }
    }
    const appliances = {'rice_cooker', 'oven', 'microwave', 'air_fryer'};
    return resources.isNotEmpty && resources.every(appliances.contains);
  }

  int due(Map<String, dynamic> task) =>
      (states[task['id']]['started'] as int) +
      (task['duration_seconds'] as int);
  bool complete(String id, int now) {
    final state = states[id];
    if (state == null || state['status'] != 'running') return false;
    state['status'] = 'completed';
    state['ended'] = now;
    return true;
  }

  bool tick(DateTime now) {
    final seconds = elapsed(now);
    var changed = false;
    for (final task in tasks) {
      if (states[task['id']]?['status'] == 'running' &&
          automatic(task) &&
          seconds >= due(task) + (json['auto_seconds'] as int)) {
        changed =
            complete(
              task['id'] as String,
              due(task) + (json['auto_seconds'] as int),
            ) ||
            changed;
      }
    }
    if (json['paused'] == true || json['resting'] == true) {
      return changed; // Running physical processes continue.
    }
    if (changed) startNext(now);
    for (final row in (snapshot['plan']['tasks'] as List)) {
      final task = tasks.firstWhere((t) => t['id'] == row['task_id']);
      if (states.containsKey(task['id']) ||
          seconds < (row['start_seconds'] as int)) {
        continue;
      }
      if ((task['dependencies'] as List? ?? []).any(
        (id) => states[id]?['status'] != 'completed',
      )) {
        continue;
      }
      if (!canStart(task)) continue;
      states[task['id'] as String] = {'status': 'running', 'started': seconds};
      changed = true;
    }
    changed = enterRest() || changed;
    return changed;
  }

  bool enterRest() {
    if (finished ||
        tasks.any(
          (t) =>
              states[t['id']]?['status'] == 'running' &&
              t['attention_type'] != 'passive',
        )) {
      return false;
    }
    if (tasks.every((t) => states.containsKey(t['id'])) ||
        json['resting'] == true) {
      return false;
    }
    json['resting'] = true;
    return true;
  }

  /// Pending work is a reminder, never an actual start while the cook is away.
  List<Map<String, dynamic>> upcoming() =>
      (snapshot['plan']['tasks'] as List)
          .where((row) => !states.containsKey(row['task_id']))
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList()
        ..sort(
          (a, b) =>
              (a['start_seconds'] as int).compareTo(b['start_seconds'] as int),
        );

  bool get needsWatching =>
      tasks.any(
        (t) =>
            states[t['id']]?['status'] == 'running' &&
            (t['attention_type'] != 'passive' ||
                (t['resources'] as Map? ?? {}).containsKey('burner')),
      ) ||
      (request['holds'] as List? ?? []).any(
        (h) =>
            h['resource'] == 'burner' &&
            states.containsKey(h['start_task']) &&
            !(h['end_task'] != null &&
                states[h['end_task']]?['status'] == 'completed'),
      );

  bool readyToStart(String id, DateTime now, {bool allowEarly = false}) {
    if (json['paused'] == true || states.containsKey(id)) return false;
    final row = upcoming().where((r) => r['task_id'] == id).firstOrNull;
    if (row == null ||
        (!allowEarly && (row['start_seconds'] as int) > elapsed(now))) {
      return false;
    }
    final task = tasks.firstWhere((t) => t['id'] == id);
    return !(task['dependencies'] as List? ?? []).any(
          (key) => states[key]?['status'] != 'completed',
        ) &&
        canStart(task);
  }

  bool startScheduled(String id, DateTime now, {bool allowEarly = false}) {
    if (!readyToStart(id, now, allowEarly: allowEarly)) return false;
    json['resting'] = false;
    states[id] = {'status': 'running', 'started': elapsed(now)};
    return true;
  }

  bool startNext(DateTime now, {String? afterTask}) {
    if (json['paused'] == true ||
        (json['resting'] == true && afterTask == null)) {
      return false;
    }
    final previous = tasks.where((t) => t['id'] == afterTask).firstOrNull;
    for (final row in snapshot['plan']['tasks'] as List) {
      final task = tasks.firstWhere((t) => t['id'] == row['task_id']);
      if (states.containsKey(task['id'])) continue;
      // Completing a device's setup starts its direct passive phase now.
      // This handoff cannot pull another dish's later manual work forward.
      final handoff =
          previous != null &&
          task['recipe_id'] == previous['recipe_id'] &&
          task['attention_type'] == 'passive' &&
          (task['dependencies'] as List? ?? []).contains(afterTask);
      if (request['target_finish_seconds'] != null &&
          elapsed(now) < (row['start_seconds'] as int) &&
          !handoff) {
        continue;
      }
      if ((task['dependencies'] as List? ?? []).any(
        (id) => states[id]?['status'] != 'completed',
      )) {
        continue;
      }
      if (!canStart(task)) continue;
      json['resting'] = false;
      states[task['id'] as String] = {
        'status': 'running',
        'started': elapsed(now),
      };
      return true;
    }
    return false;
  }

  bool canStart(Map<String, dynamic> candidate) {
    final demand = <String, int>{};
    void add(String name, int count) =>
        demand[name] = (demand[name] ?? 0) + count;
    for (final task in tasks) {
      final active = states[task['id']]?['status'] == 'running';
      if (!active && task['id'] != candidate['id']) continue;
      (task['resources'] as Map? ?? {}).forEach(
        (key, value) => add(key as String, value as int),
      );
      if (task['attention_type'] != 'passive') add('cook', 1);
    }
    for (final hold in request['holds'] as List? ?? []) {
      final acquired =
          states.containsKey(hold['start_task']) ||
          hold['start_task'] == candidate['id'];
      final released =
          hold['end_task'] != null &&
          states[hold['end_task']]?['status'] == 'completed';
      if (acquired && !released) {
        add(hold['resource'] as String, (hold['quantity'] as int?) ?? 1);
      }
    }
    final capacities = {
      ...(request['capacities'] as Map),
      'cook': request['cook_count'] ?? 1,
    };
    return demand.entries.every(
      (e) => e.value <= ((capacities[e.key] as int?) ?? 0),
    );
  }
}
