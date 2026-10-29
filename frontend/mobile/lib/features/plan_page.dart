import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../data/repository.dart';
import '../data/cooking_session.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';

class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({super.key});
  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  DateTime target = DateTime.now().add(const Duration(hours: 1));
  bool generating = false, useTarget = false;
  String? planningError;
  @override
  Widget build(BuildContext context) => CatalogView(
    builder: (context, ref, catalog) {
      final selected = catalog.recipes
          .where((r) => catalog.selected.contains(r.id))
          .toList();
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            '今晚的饭，安排一下',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          if (selected.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('先去菜谱页，选择今晚想做的菜。'),
              ),
            ),
          ...selected.map(
            (r) => Card(
              child: ListTile(
                leading: const Icon(Icons.restaurant_outlined),
                title: Text(r.name),
                subtitle: Text('${r.servings} 人份 · ${r.tasks.length} 步'),
              ),
            ),
          ),
          const SizedBox(height: 15),
          ListTile(
            leading: const Icon(Icons.kitchen_outlined),
            title: const Text('我的厨房'),
            subtitle: Text(
              catalog.kitchen == null
                  ? '尚未连接'
                  : '${catalog.kitchen!.cooks} 人 · ${catalog.kitchen!.capacities['burner'] ?? 0} 个灶眼',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/kitchen?from=plan'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('指定开饭时间（可选）'),
            subtitle: const Text('不指定时，按尽快完成安排烹饪。'),
            value: useTarget,
            onChanged: (value) => setState(() => useTarget = value),
          ),
          if (useTarget)
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('希望开饭时间'),
                subtitle: Text(
                  '${target.month}月${target.day}日 ${TimeOfDay.fromDateTime(target).format(context)}',
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: pickTarget,
              ),
            ),
          if (planningError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '无法生成计划',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(planningError!, key: const Key('planning-error')),
                    TextButton(
                      onPressed: () => context.go('/kitchen?from=plan'),
                      child: const Text('修改厨房设备'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: generating || selected.isEmpty || catalog.kitchen == null
                ? null
                : () async {
                    setState(() {
                      generating = true;
                      planningError = null;
                    });
                    try {
                      final plan = await ref
                          .read(repositoryProvider)
                          .plan(
                            selected.map((r) => r.id).toList(),
                            catalog.kitchen!.id,
                            useTarget ? target : null,
                          );
                      await ref
                          .read(databaseProvider)
                          .save('latest_plan', plan);
                      if (context.mounted) {
                        context.go('/timeline', extra: plan);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        setState(() => planningError = errorMessage(e));
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('无法生成计划'),
                            content: Text(planningError!),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('知道了'),
                              ),
                            ],
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => generating = false);
                    }
                  },
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(generating ? '正在安排锅灶和时间…' : '生成烹饪计划'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.go('/execute'),
            child: const Text('继续烹饪 / 恢复云端会话'),
          ),
          OutlinedButton(
            onPressed: () => context.go('/timeline'),
            child: const Text('查看上次保存的计划'),
          ),
        ],
      );
    },
  );
  Future<void> pickTarget() async {
    final date = await showDatePicker(
      context: context,
      initialDate: target,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 6)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(target),
    );
    if (time != null && mounted) {
      setState(
        () => target = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }
}

class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key, this.snapshot});
  final Map<String, dynamic>? snapshot;
  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  Map<String, dynamic>? snapshot;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final value =
        widget.snapshot ?? await ref.read(databaseProvider).load('latest_plan');
    if (mounted) {
      setState(() {
        snapshot = value;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('烹饪计划'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/plan'),
          ),
        ),
        body: const Center(child: Text('还没有保存的计划，先选择菜谱并生成。')),
      );
    }
    final data = snapshot!,
        plan = data['plan'] as Map,
        request = data['request'] as Map;
    final origin = DateTime.parse(data['origin'] as String).toLocal(),
        names = data['recipes'] as Map;
    String time(num seconds) => TimeOfDay.fromDateTime(
      origin.add(Duration(seconds: seconds.toInt())),
    ).format(context);
    final templates = {for (final t in request['tasks'] as List) t['id']: t};
    return Scaffold(
      appBar: AppBar(
        title: const Text('一顿饭的好节奏'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/plan'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            '预计 ${time((plan['finish_seconds'] as num) > ((request['target_finish_seconds'] as num? ?? 0)) ? plan['finish_seconds'] as num : (request['target_finish_seconds'] as num? ?? 0))} 开饭',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(plan['optimal'] == true ? '已找到最优计划' : '已找到可行计划'),
          if ((plan['lateness_seconds'] as num) > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '按当前条件，预计晚 ${((plan['lateness_seconds'] as num) / 60).ceil()} 分钟开饭。',
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始烹饪'),
            onPressed: () async {
              final db = ref.read(databaseProvider);
              final previous = await db.load('active_session');
              if (previous != null) {
                await db.save(
                  'history:${previous['document']['id']}',
                  previous,
                );
              }
              if (previous != null &&
                  !CookingSession(
                    Map<String, dynamic>.from(previous['document'] as Map),
                  ).finished) {
                if (!context.mounted) return;
                final replace = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('已有烹饪进度'),
                    content: const Text('开始新会话会将旧进度保留在本机历史中。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('继续旧会话'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('开始新会话'),
                      ),
                    ],
                  ),
                );
                if (replace != true) {
                  if (context.mounted) context.go('/execute');
                  return;
                }
              }
              final session = CookingSession.start(
                data,
                const Uuid().v4(),
                DateTime.now(),
              );
              session.tick(DateTime.now());
              await db.save('active_session', {
                'document': session.json,
                'version': 0,
                'mutation': const Uuid().v4(),
              });
              if (context.mounted) context.go('/execute');
            },
          ),
          const SizedBox(height: 20),
          ...(plan['tasks'] as List).map((row) {
            final t = templates[row['task_id']] as Map;
            final passive = t['attention_type'] == 'passive';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 58,
                      child: Text(
                        time(row['start_seconds'] as num),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['name'] as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${names[row['recipe_id']]} · ${passive ? '设备自动' : '需要操作或看管'}',
                          ),
                          if ((t['notes'] as String? ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                t['notes'] as String,
                                style: const TextStyle(height: 1.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          ...(plan['warnings'] as List).map(
            (w) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(w as String),
            ),
          ),
        ],
      ),
    );
  }
}
