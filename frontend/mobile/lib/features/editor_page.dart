import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../main.dart';
import 'recipe_text_field.dart';

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, required this.recipe});
  final Recipe recipe;
  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  final form = GlobalKey<FormState>();
  late Map<String, dynamic> draft;
  late TextEditingController ingredients;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    draft = cloneJson(widget.recipe.json);
    ingredients = TextEditingController(
      text: (draft['ingredients'] as List)
          .map((i) => '${i['name']} | ${i['quantity']} | ${i['unit']}')
          .join('\n'),
    );
  }

  @override
  void dispose() {
    ingredients.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get tasks =>
      (draft['tasks'] as List).cast<Map<String, dynamic>>();
  String? nonempty(String? value) =>
      value == null || value.trim().isEmpty ? '请填写内容' : null;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/recipes'),
      ),
      title: Text(draft['confirmed'] == false ? '确认识别结果' : '编辑菜谱'),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (draft['confirmed'] == false)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '以下内容由 DeepSeek 解析，请核对食材、步骤、时长与依赖后保存。AI 估算的时间需要你确认。',
                ),
              ),
            ),
          RecipeTextField(
            initialValue: draft['name'] as String,
            decoration: const InputDecoration(labelText: '菜名'),
            maxLength: 80,
            validator: nonempty,
            onChanged: (v) => draft['name'] = v.trim(),
          ),
          const SizedBox(height: 12),
          RecipeTextField(
            initialValue: '${draft['servings']}',
            decoration: const InputDecoration(labelText: '份数'),
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n != null && n >= 1 && n <= 20 ? null : '请输入 1–20';
            },
            onChanged: (v) => draft['servings'] = int.tryParse(v) ?? 0,
          ),
          const SizedBox(height: 18),
          RecipeTextField(
            controller: ingredients,
            decoration: const InputDecoration(
              labelText: '食材',
              helperText: '每行：名称 | 数量 | 单位，例如 鸡蛋 | 3 | 个',
            ),
            maxLines: 5,
          ),
          const SizedBox(height: 22),
          const Text(
            '烹饪步骤',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          ...tasks.asMap().entries.map((entry) {
            final i = entry.key, t = entry.value;
            final dependencies = (t['dependencies'] as List).cast<String>();
            final resources = Map<String, dynamic>.from(t['resources'] as Map);
            return Card(
              key: ValueKey(t['id']),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '步骤 ${i + 1}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RecipeTextField(
                      initialValue: t['name'] as String,
                      decoration: const InputDecoration(labelText: '操作名称'),
                      validator: nonempty,
                      onChanged: (v) => t['name'] = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    RecipeTextField(
                      initialValue: t['notes'] as String? ?? '',
                      decoration: const InputDecoration(
                        labelText: '操作备注',
                        hintText: '例如：小火翻炒 30 秒，转大火后放盐。',
                      ),
                      maxLength: 4000,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (v) => t['notes'] = v,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: RecipeTextField(
                            initialValue: '${t['duration_seconds']}',
                            decoration: const InputDecoration(
                              labelText: '预计时长（秒）',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final n = int.tryParse(v ?? '');
                              return n == null || n < 1 || n > 86400
                                  ? '请输入 1–86400'
                                  : null;
                            },
                            onChanged: (v) =>
                                t['duration_seconds'] = int.tryParse(v) ?? 0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: t['attention_type'] as String,
                            decoration: const InputDecoration(
                              labelText: '关注方式',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'active',
                                child: Text('持续操作'),
                              ),
                              DropdownMenuItem(
                                value: 'passive',
                                child: Text('设备自动'),
                              ),
                              DropdownMenuItem(
                                value: 'intermittent',
                                child: Text('间歇看管'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => t['attention_type'] = v),
                          ),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('前置步骤'),
                      subtitle: Text(
                        dependencies.isEmpty
                            ? '可独立开始'
                            : '已选 ${dependencies.length} 步',
                      ),
                      children: [
                        Wrap(
                          spacing: 6,
                          children: tasks
                              .where((other) => other['id'] != t['id'])
                              .map(
                                (other) => FilterChip(
                                  label: Text(
                                    other['name'] as String? ?? '未命名',
                                  ),
                                  selected: dependencies.contains(other['id']),
                                  onSelected: (selected) => setState(() {
                                    selected
                                        ? dependencies.add(
                                            other['id'] as String,
                                          )
                                        : dependencies.remove(other['id']);
                                    t['dependencies'] = dependencies;
                                  }),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('本步骤占用厨具'),
                      children: [
                        Wrap(
                          spacing: 6,
                          children: resourceNames.entries
                              .map(
                                (e) => FilterChip(
                                  label: Text(e.value),
                                  selected: resources.containsKey(e.key),
                                  onSelected: (selected) => setState(() {
                                    selected
                                        ? resources[e.key] = 1
                                        : resources.remove(e.key);
                                    t['resources'] = resources;
                                  }),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: saving
                ? null
                : () => setState(
                    () =>
                        tasks.add(Recipe.newTask(draft['recipe_id'] as String)),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('增加独立步骤'),
          ),
          if ((draft['holds'] as List).isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('已保留识别到的跨步骤厨具占用，请勿在单个步骤中重复勾选。'),
            ),
          const SizedBox(height: 15),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '正在保存…' : '确认内容并保存菜谱'),
          ),
        ],
      ),
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    draft['ingredients'] = ingredients.text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final parts = line.split('|').map((s) => s.trim()).toList();
          return {
            'name': parts.first,
            'quantity': parts.length > 1 ? parts[1] : '',
            'unit': parts.length > 2 ? parts[2] : '',
          };
        })
        .toList();
    draft['confirmed'] = true;
    setState(() => saving = true);
    try {
      await ref.read(catalogProvider.notifier).saveRecipe(Recipe(draft));
      await ref.read(databaseProvider).remove('draft:${draft['recipe_id']}');
      if (mounted) context.go('/recipes');
    } catch (e) {
      if (mounted) showError(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

/// Resolve an editor from a durable draft, local catalog, or saved server recipe.
/// URL identity survives Web refresh without depending on a live widget extra.
class RecipeEditorRoute extends ConsumerStatefulWidget {
  const RecipeEditorRoute({super.key, required this.id, this.initial});
  final String id;
  final Recipe? initial;
  @override
  ConsumerState<RecipeEditorRoute> createState() => _RecipeEditorRouteState();
}

class _RecipeEditorRouteState extends ConsumerState<RecipeEditorRoute> {
  Recipe? recipe;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      var resolved = widget.initial;
      if (resolved == null) {
        final database = ref.read(databaseProvider);
        final draft = await database.load('draft:${widget.id}');
        if (draft != null) resolved = Recipe(draft);
        if (resolved == null) {
          final catalog = await database.load('catalog');
          for (final value in (catalog?['recipes'] as List?) ?? []) {
            if (value['recipe_id'] == widget.id) {
              resolved = Recipe(Map<String, dynamic>.from(value as Map));
            }
          }
        }
        resolved ??= Recipe(
          await ref
              .read(repositoryProvider)
              .object('/api/v1/recipes/${widget.id}'),
        );
      }
      if (mounted) setState(() => recipe = resolved);
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (recipe != null) return EditorPage(recipe: recipe!);
    return Scaffold(
      appBar: AppBar(
        title: const Text('打开菜谱'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/recipes'),
        ),
      ),
      body: Center(
        child: error == null ? const CircularProgressIndicator() : Text(error!),
      ),
    );
  }
}
