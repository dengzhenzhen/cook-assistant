import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/auth.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/outbox.dart';
import '../main.dart';

class RecipesPage extends ConsumerStatefulWidget {
  const RecipesPage({super.key});
  @override
  ConsumerState<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends ConsumerState<RecipesPage> {
  bool favorites = false;
  @override
  Widget build(BuildContext context) => CatalogView(
    builder: (context, ref, catalog) => RefreshIndicator(
      onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            '今天，想吃点什么？',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('把喜欢的味道留下，安排一顿刚刚好的饭。'),
          ),
          if (catalog.offline)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('离线查看已保存菜谱'),
                subtitle: Text(catalog.message ?? ''),
                trailing: IconButton(
                  onPressed: () => ref.read(catalogProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          if (catalog.offline)
            TextButton(
              onPressed: resolvePending,
              child: const Text('查看待同步编辑 / 解决冲突'),
            ),
          Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xffe7eadb),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    '锅里有热气，\n日子有滋味。',
                    style: TextStyle(fontSize: 28, height: 1.5),
                  ),
                ),
                Icon(
                  Icons.rice_bowl_outlined,
                  size: 68,
                  color: Color(0xff536f46),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.go('/import'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('导入菜谱'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => context.go('/recipe/new'),
                child: const Text('手动创建'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部菜谱'),
                selected: !favorites,
                onSelected: (_) => setState(() => favorites = false),
              ),
              ChoiceChip(
                label: const Text('我的收藏'),
                selected: favorites,
                onSelected: (_) => setState(() => favorites = true),
              ),
            ],
          ),
          if (catalog.recipes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 45),
              child: Text(
                '还没有菜谱。试试导入一段文字，或手动创建你的拿手菜。',
                textAlign: TextAlign.center,
              ),
            ),
          ...catalog.recipes
              .where((r) => !favorites || r.favorite)
              .map(
                (recipe) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(catalogProvider.notifier)
                                  .favorite(recipe);
                            } catch (e) {
                              if (context.mounted) {
                                showError(context, errorMessage(e));
                              }
                            }
                          },
                          icon: Icon(
                            recipe.favorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: const Color(0xffcd5430),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => context.go(
                              '/recipe/edit/${recipe.id}',
                              extra: recipe,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    recipe.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${recipe.servings} 人份 · ${recipe.tasks.length} 步',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Checkbox(
                          value: catalog.selected.contains(recipe.id),
                          onChanged: (_) => ref
                              .read(catalogProvider.notifier)
                              .toggle(recipe.id),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: catalog.selected.isEmpty
                ? null
                : () => context.go('/plan'),
            child: Text('安排做饭 · 已选 ${catalog.selected.length} 道菜'),
          ),
        ],
      ),
    ),
  );
  Future<void> resolvePending() async {
    final db = ref.read(databaseProvider), api = ref.read(repositoryProvider);
    final items = await Outbox(db, api).entries();
    if (items.isEmpty) {
      if (mounted) showError(context, '没有待同步编辑，联网后下拉刷新即可。');
      return;
    }
    final entry = items.first;
    try {
      final remote = await api.object(
        entry['kind'] == 'recipe'
            ? '/api/v1/recipes/${entry['document']['recipe_id']}'
            : '/api/v1/kitchens/default',
      );
      if (!mounted) return;
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择需要保留的内容'),
          content: const Text(
            '本地编辑和云端内容都将先备份。选择本地会用它替换刚读取的云端版本；若云端再次改变，同步仍会停止。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('采用云端'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('采用本地编辑'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      await db.save('edit_recovery:${DateTime.now().millisecondsSinceEpoch}', {
        'local': entry,
        'remote': remote,
      });
      if (choice) {
        entry['base'] = remote;
        items[0] = entry;
      } else {
        items.removeAt(0);
      }
      await db.save('edit_outbox', {'items': items});
      await ref.read(catalogProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showError(context, errorMessage(e));
    }
  }
}

class MinePage extends ConsumerWidget {
  const MinePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        '我的小厨房',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 25),
      const CircleAvatar(
        radius: 35,
        child: Icon(Icons.person_outline, size: 38),
      ),
      const SizedBox(height: 15),
      const Text(
        '今天也好好吃饭',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20),
      ),
      Text(
        '已登录账号：${ref.watch(authProvider).value?['user_id'] ?? ''}',
        textAlign: TextAlign.center,
      ),
      TextButton(
        onPressed: () => ref.read(authProvider.notifier).logout(),
        child: const Text('退出登录'),
      ),
      const SizedBox(height: 24),
      Card(
        child: ListTile(
          leading: const Icon(Icons.kitchen_outlined),
          title: const Text('我的厨房设备'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/kitchen'),
        ),
      ),
      FutureBuilder(
        future: ref.read(repositoryProvider).object('/api/v1/ai/status'),
        builder: (context, snapshot) {
          final status = snapshot.data;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('DeepSeek 菜谱解析'),
              subtitle: Text(
                status == null
                    ? '连接后查看配额'
                    : '今日已用 ${status['daily_used']} / ${status['daily_limit']} 次\n累计输入 ${status['input_tokens']}、输出 ${status['output_tokens']} token',
              ),
            ),
          );
        },
      ),
    ],
  );
}

class KitchenPage extends ConsumerStatefulWidget {
  const KitchenPage({super.key, this.returnTo = '/mine'});
  final String returnTo;
  @override
  ConsumerState<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends ConsumerState<KitchenPage> {
  Map<String, dynamic>? draft;
  bool saving = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的厨房'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(widget.returnTo),
      ),
    ),
    body: CatalogView(
      builder: (context, ref, catalog) {
        if (catalog.kitchen == null) {
          return const Center(child: Text('请先连接服务以初始化厨房。'));
        }
        draft ??= cloneJson(catalog.kitchen!.json);
        final capacities = draft!['capacities'] as Map<String, dynamic>;
        Widget counter(
          String title,
          int value,
          int min,
          void Function(int) change,
        ) => Card(
          child: ListTile(
            title: Text(title),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: saving || value <= min
                      ? null
                      : () => setState(() => change(value - 1)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$value'),
                IconButton(
                  onPressed: saving || value >= 20
                      ? null
                      : () => setState(() => change(value + 1)),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            counter(
              '一起做饭的人',
              draft!['cook_count'] as int,
              1,
              (n) => draft!['cook_count'] = n,
            ),
            ...resourceNames.entries.map(
              (e) => counter(
                e.value,
                capacities[e.key] as int? ?? 0,
                0,
                (n) => capacities[e.key] = n,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('灶眼和锅具分别计算，没有的设备可设为 0。'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await ref
                            .read(catalogProvider.notifier)
                            .saveKitchen(Kitchen(draft!));
                        await ref.read(catalogProvider.notifier).refresh();
                        if (context.mounted) context.go(widget.returnTo);
                      } catch (e) {
                        if (context.mounted) {
                          showError(context, errorMessage(e));
                        }
                      } finally {
                        if (mounted) setState(() => saving = false);
                      }
                    },
              child: Text(saving ? '正在保存…' : '保存厨房配置'),
            ),
          ],
        );
      },
    ),
  );
}
