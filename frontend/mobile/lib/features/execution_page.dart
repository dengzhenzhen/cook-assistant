import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../core/providers.dart';
import '../core/reminders.dart';
import '../data/cooking_session.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../main.dart';
import 'task_completion_button.dart';

class ExecutionPage extends ConsumerStatefulWidget {
  const ExecutionPage({super.key});
  @override
  ConsumerState<ExecutionPage> createState() => _ExecutionPageState();
}

class _ExecutionPageState extends ConsumerState<ExecutionPage>
    with WidgetsBindingObserver {
  CookingSession? session;
  late final ScopedStorage store;
  late final ApiRepository api;
  Timer? timer;
  final reminders = appReminders;
  int version = 0;
  String? mutation, message, schedulingError;
  bool exiting = false;
  bool foreground = true;
  Map<String, dynamic>? conflict;
  bool busy = false, changing = false, replanning = false;
  @override
  void initState() {
    super.initState();
    store = ScopedStorage(ref.read(databaseProvider));
    api = ref.read(repositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      tick();
      sync();
    }
  }

  Future<void> load() async {
    final cache = await store.load('active_session');
    if (cache != null) {
      session = CookingSession(
        Map<String, dynamic>.from(cache['document'] as Map),
      );
      version = cache['version'] as int? ?? 0;
      mutation = cache['mutation'] as String?;
      if (session!.restoreDinnerTarget()) {
        mutation = const Uuid().v4();
        await writeCache();
      }
    }
    try {
      await reminders.initialize(permissions: true);
    } catch (e) {
      message = '系统提醒初始化失败：$e';
    }
    if (!mounted) return;
    setState(() {});
    await tick();
    if (session != null && store.active) {
      try {
        await reminders.update(session!);
      } catch (e) {
        message = '提醒设置失败：$e';
      }
    }
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    await sync();
    if (mounted && session?.json['needs_replan'] == true) {
      await recalculate(silent: true);
    }
  }

  Future<void> persist() async {
    mutation = const Uuid().v4();
    await writeCache();
    try {
      if (store.active) await reminders.update(session!);
    } catch (e) {
      message = '提醒设置失败：$e';
    }
  }

  Future<void> writeCache() => store.save('active_session', {
    'document': session!.json,
    'version': version,
    'mutation': mutation,
  });
  Future<void> tick() async {
    if (!mounted || !foreground || session == null || changing) return;
    changing = true;
    try {
      if (session!.tick(DateTime.now())) await persist();
      if (mounted) setState(() {});
    } finally {
      changing = false;
    }
    if (DateTime.now().second % 10 == 0) await sync();
  }

  Future<void> sync() async {
    if (busy || session == null || conflict != null || !store.active) return;
    busy = true;
    final pending = mutation;
    try {
      if (pending != null) {
        final response = await api.dio.put(
          '/api/v1/sessions/${session!.json['id']}',
          data: {
            'session_id': session!.json['id'],
            'base_version': version,
            'mutation_id': pending,
            'document': cloneJson(session!.json),
          },
        );
        version = response.data['version'] as int;
        if (mutation == pending) mutation = null;
        await writeCache();
      } else if (version > 0) {
        final remote = await api.object(
          '/api/v1/sessions/${session!.json['id']}',
        );
        if (mutation == null && (remote['version'] as int) > version) {
          version = remote['version'] as int;
          session = CookingSession(
            Map<String, dynamic>.from(remote['document'] as Map),
          );
          if (session!.restoreDinnerTarget()) mutation = const Uuid().v4();
          await writeCache();
          if (store.active) await reminders.update(session!);
        }
      }
      message = mutation == null ? '进度已同步' : '新进度等待同步';
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final detail = e.response?.data['detail'];
        conflict = detail is Map
            ? Map<String, dynamic>.from(detail)
            : <String, dynamic>{};
        message = '同步冲突：本地进度已保留，请选择恢复云端或保留为独立会话。';
      } else {
        message = '离线执行中，进度已保存在本机；联网后自动同步。';
      }
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> action(
    VoidCallback change, {
    bool replan = false,
    String? afterTask,
  }) async {
    if (changing) return;
    changing = true;
    try {
      change();
      if (replan) session!.startNext(DateTime.now(), afterTask: afterTask);
      session!.tick(DateTime.now());
      await persist();
    } finally {
      changing = false;
    }
    if (mounted) setState(() {});
    await sync();
    if (replan && mounted) await recalculate(silent: true);
  }

  Future<void> recalculate({bool silent = false}) async {
    if (replanning) return;
    replanning = true;
    if (mounted) setState(() => schedulingError = null);
    try {
      final current = session!, now = current.elapsed(DateTime.now());
      final request = cloneJson(current.request);
      request['now_seconds'] = now;
      request['execution'] = current.states.entries.map((e) {
        final state = e.value as Map;
        final task = current.tasks.firstWhere((t) => t['id'] == e.key);
        return {
          'task_id': e.key,
          'actual_start': state['started'],
          if (state['status'] == 'completed')
            'actual_end': state['ended']
          else
            'remaining_seconds':
                ((state['started'] as int) +
                        (task['duration_seconds'] as int) -
                        now)
                    .clamp(1, 86400),
        };
      }).toList();
      final result = await api.dio.post(
        '/api/v1/plans/recalculate',
        data: request,
      );
      await action(() {
        current.snapshot['plan'] = result.data;
        current.json['needs_replan'] = false;
      });
    } catch (e) {
      if (mounted && (!silent || (e is DioException && e.response != null))) {
        setState(() => schedulingError = '重新安排失败，当前进度仍保留：${errorMessage(e)}');
      }
    } finally {
      replanning = false;
    }
  }

  Future<void> finishAndExit() async {
    if (session == null || !session!.finished || exiting) return;
    setState(() => exiting = true);
    timer?.cancel();
    try {
      await writeCache();
      // Keep the active snapshot too, including any pending sync mutation.
      await store.save('history:${session!.json['id']}', {
        'document': cloneJson(session!.json),
        'version': version,
        'mutation': mutation,
      });
      if (reminders.ready && store.active) await reminders.plugin.cancelAll();
      if (mounted) context.go('/recipes');
    } catch (error) {
      if (mounted) {
        setState(() => exiting = false);
        showError(context, '保存进度失败，请重试：${errorMessage(error)}');
        timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在烹饪'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/plan'),
        ),
      ),
      body: current == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('本机还没有正在执行的计划'),
                  TextButton(
                    onPressed: () async {
                      try {
                        final rows =
                            (await api.dio.get('/api/v1/sessions')).data
                                as List;
                        if (!context.mounted) return;
                        final row = await showDialog<Map>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: const Text('恢复云端会话'),
                            children: [
                              if (rows.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('暂无云端会话'),
                                ),
                              ...rows.map(
                                (r) => SimpleDialogOption(
                                  onPressed: () =>
                                      Navigator.pop(context, r as Map),
                                  child: Text('${r['document']['origin']}'),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (row != null) {
                          session = CookingSession(
                            Map<String, dynamic>.from(row['document'] as Map),
                          );
                          version = row['version'] as int;
                          await writeCache();
                          await tick();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showError(context, errorMessage(e));
                        }
                      }
                    },
                    child: const Text('从云端恢复'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Text(
                  current.finished ? '这顿饭，做好了！' : '一步一步，安心开饭',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '预计 ${TimeOfDay.fromDateTime(DateTime.parse(current.json['origin'] as String).toLocal().add(Duration(seconds: current.snapshot['plan']['finish_seconds'] as int))).format(context)} 开饭',
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value:
                      current.states.values
                          .where((s) => s['status'] == 'completed')
                          .length /
                      current.tasks.length,
                ),
                const SizedBox(height: 12),
                Text(message ?? '进度保存在本机'),
                if (schedulingError != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(schedulingError!),
                    ),
                  ),
                if (current.finished)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: FilledButton.icon(
                      onPressed: exiting ? null : finishAndExit,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(exiting ? '正在保存…' : '完成并返回菜谱'),
                    ),
                  ),
                if (reminders.warning != null)
                  Text(
                    reminders.warning!,
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                if (conflict != null) ...[
                  OutlinedButton(
                    onPressed: () async {
                      // Keep a separate durable recovery copy before replacing any local facts.
                      await store.save(
                        'recovery:${current.json['id']}:${DateTime.now().millisecondsSinceEpoch}',
                        current.json,
                      );
                      final remote = await api.object(
                        '/api/v1/sessions/${current.json['id']}',
                      );
                      session = CookingSession(
                        Map<String, dynamic>.from(remote['document'] as Map),
                      );
                      version = remote['version'] as int;
                      mutation = null;
                      conflict = null;
                      await writeCache();
                      await tick();
                    },
                    child: const Text('保留本地备份，恢复云端进度'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      current.json['id'] = const Uuid().v4();
                      version = 0;
                      conflict = null;
                      await persist();
                      await sync();
                    },
                    child: const Text('将本地进度保存为独立会话'),
                  ),
                ],
                if (!current.finished && current.json['resting'] == true)
                  waitingCard(current),
                const SizedBox(height: 20),
                const Text('当前手动操作 / 明火看管', style: TextStyle(fontSize: 19)),
                ...current.tasks
                    .where(
                      (t) =>
                          current.states[t['id']]?['status'] == 'running' &&
                          !current.automatic(t),
                    )
                    .map(taskCard),
                const SizedBox(height: 15),
                const Text('设备自动进行', style: TextStyle(fontSize: 19)),
                ...current.tasks
                    .where(
                      (t) =>
                          current.states[t['id']]?['status'] == 'running' &&
                          current.automatic(t),
                    )
                    .map(taskCard),
                if (!current.finished) ...[
                  SwitchListTile(
                    title: const Text('暂停安排新步骤'),
                    subtitle: const Text('正在运行的设备和明火继续计时，请实际检查厨房。'),
                    value: current.json['paused'] == true,
                    onChanged: (value) =>
                        action(() => current.json['paused'] = value),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: current.json['auto_seconds'] as int,
                    decoration: const InputDecoration(labelText: '设备到期后自动确认等待'),
                    items: [5, 30, 60, 120, 300, 600]
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text('$s 秒')),
                        )
                        .toList(),
                    onChanged: (s) {
                      if (s != null) {
                        action(() => current.json['auto_seconds'] = s);
                      }
                    },
                  ),
                  TextButton(
                    onPressed: recalculate,
                    child: const Text('根据实际进度重新安排剩余任务'),
                  ),
                ],
                TextButton(onPressed: sync, child: const Text('立即同步')),
                const Divider(),
                const Text('全部步骤'),
                ...current.tasks.map(
                  (t) => ListTile(
                    title: Text(t['name'] as String),
                    subtitle: Text(t['notes'] as String? ?? ''),
                    trailing: Text(
                      current.states[t['id']]?['status'] == 'completed'
                          ? '已完成'
                          : current.states[t['id']]?['status'] == 'running'
                          ? '进行中'
                          : '待开始',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget waitingCard(CookingSession current) {
    final upcoming = current.upcoming();
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final origin = DateTime.parse(current.json['origin'] as String).toLocal();
    final now = DateTime.now();
    final seconds =
        (upcoming.first['start_seconds'] as int) - current.elapsed(now);
    final templates = {for (final t in current.tasks) t['id']: t};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              seconds > 0 ? '等待下一次操作' : '该回厨房了',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              current.needsWatching
                  ? '后续操作会按计划提醒；当前明火或间歇步骤仍需看管。'
                  : '当前无需手动操作，可以暂时休息。到计划时间会提醒你回来。',
            ),
            if (seconds > 0) Text('距离下一次操作约 ${(seconds / 60).ceil()} 分钟'),
            ...upcoming.take(3).map((row) {
              final id = row['task_id'] as String, task = templates[id]!;
              final at = origin.add(
                Duration(seconds: row['start_seconds'] as int),
              );
              final due = (row['start_seconds'] as int) <= current.elapsed(now);
              final ready = current.readyToStart(id, now, allowEarly: true);
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${at.month}月${at.day}日 ${TimeOfDay.fromDateTime(at).format(context)} · ${task['name']}',
                    ),
                    if (!ready) const Text('等待前置步骤完成或设备空闲'),
                    OutlinedButton(
                      onPressed: !ready
                          ? null
                          : () async {
                              if (!due) {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('提前开始这一步？'),
                                    content: const Text(
                                      '将记录实际开始时间并重新安排剩余任务，原定开饭时间保持不变。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('按原计划等待'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('现在开始'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !mounted) return;
                              }
                              await action(
                                () => current.startScheduled(
                                  id,
                                  DateTime.now(),
                                  allowEarly: !due,
                                ),
                                replan: true,
                              );
                            },
                      child: Text(due ? '开始这一步' : '提前开始这一步'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget taskCard(Map<String, dynamic> task) {
    final current = session!,
        remaining = current.due(task) - current.elapsed(DateTime.now());
    final auto = current.automatic(task),
        grace = remaining + (current.json['auto_seconds'] as int);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(task['name'] as String, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 10),
            Text(
              task['notes'] as String? ?? '',
              style: const TextStyle(height: 1.7),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                remaining > 0
                    ? '剩余 ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'
                    : auto
                    ? '${grace.clamp(0, 600)} 秒后自动确认'
                    : '时间到，请检查并确认',
              ),
            ),
            TaskCompletionButton(
              name: task['name'] as String,
              background: task['attention_type'] != 'active',
              remainingSeconds: () =>
                  current.due(task) - current.elapsed(DateTime.now()),
              onComplete: () async {
                if (!mounted ||
                    current.states[task['id']]?['status'] != 'running') {
                  return;
                }
                await action(
                  () => current.complete(
                    task['id'] as String,
                    current.elapsed(DateTime.now()),
                  ),
                  replan: true,
                  afterTask: task['id'] as String,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
