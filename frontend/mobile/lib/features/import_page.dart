import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/providers.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../main.dart';
import 'recipe_text_field.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final text = TextEditingController();
  Timer? timer;
  String? jobId;
  String status = '';
  bool submitting = false, polling = false;
  @override
  void initState() {
    super.initState();
    resume();
  }

  Future<void> resume() async {
    final cached = await ref.read(databaseProvider).load('import');
    if (mounted && cached?['job_id'] != null) {
      setState(() => jobId = cached!['job_id'] as String);
      watch();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    text.dispose();
    super.dispose();
  }

  void watch() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
    poll();
  }

  Future<void> poll() async {
    if (polling || jobId == null) return;
    polling = true;
    try {
      final result = await ref
          .read(repositoryProvider)
          .object('/api/v1/import-jobs/$jobId');
      if (!mounted) return;
      setState(() => status = result['status'] as String);
      if (status == 'completed') {
        timer?.cancel();
        final recipe = Recipe(
          Map<String, dynamic>.from(result['recipe'] as Map),
        );
        await ref
            .read(databaseProvider)
            .save('draft:${recipe.id}', recipe.json);
        await ref.read(databaseProvider).save('import', {});
        if (mounted) context.go('/recipe/edit/${recipe.id}', extra: recipe);
      } else if (status == 'failed') {
        timer?.cancel();
        await ref.read(databaseProvider).save('import', {});
        if (mounted) {
          setState(() => jobId = null);
          showError(context, result['error'] as String? ?? '解析失败。');
        }
      }
    } catch (e) {
      if (mounted) {
        timer?.cancel();
        showError(context, errorMessage(e));
      }
    } finally {
      polling = false;
    }
  }

  Future<void> submit({bool images = false}) async {
    if (submitting) return;
    setState(() => submitting = true);
    try {
      final api = ref.read(repositoryProvider);
      Map<String, dynamic> job;
      if (images) {
        final selected = await ImagePicker().pickMultiImage(
          maxWidth: 2048,
          imageQuality: 85,
        );
        if (selected.isEmpty) return;
        if (selected.length > 5) throw Exception('最多选择 5 张图片。');
        final files = <MultipartFile>[];
        for (final image in selected) {
          final bytes = await image.readAsBytes();
          if (bytes.length > 4 * 1024 * 1024) throw Exception('单张图片最多 4MB。');
          files.add(MultipartFile.fromBytes(bytes, filename: image.name));
        }
        job = await api.importImages(files);
      } else {
        if (text.text.trim().length < 5) {
          showError(context, '请粘贴至少 5 个字符的菜谱内容。');
          return;
        }
        job = await api.importText(text.text.trim());
      }
      await ref.read(databaseProvider).save('import', {
        'job_id': job['job_id'],
      });
      if (mounted) {
        setState(() {
          jobId = job['job_id'] as String;
          status = job['status'] as String;
        });
        watch();
      }
    } catch (e) {
      if (mounted) showError(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('导入你的拿手菜'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/recipes'),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          '让喜欢的味道，变成可执行的步骤。',
          style: TextStyle(fontSize: 23, height: 1.5),
        ),
        const SizedBox(height: 16),
        const Text('文本与图片将发送至 DeepSeek 解析，保存前请确认食材、时长和操作内容。密钥仅保存在服务端。'),
        const SizedBox(height: 22),
        if (jobId != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 15),
                  Text(status == 'pending' ? '正在排队…' : '正在整理食材和步骤…'),
                  TextButton(onPressed: poll, child: const Text('检查解析结果')),
                ],
              ),
            ),
          )
        else ...[
          RecipeTextField(
            controller: text,
            decoration: const InputDecoration(
              labelText: '粘贴菜谱文字',
              hintText: '例如：番茄切块、鸡蛋打散……',
            ),
            minLines: 7,
            maxLines: 12,
            maxLength: 20000,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (mounted) text.text = data?.text ?? '';
              },
              icon: const Icon(Icons.content_paste),
              label: const Text('从剪贴板粘贴'),
            ),
          ),
          FilledButton.icon(
            onPressed: submitting ? null : () => submit(),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(submitting ? '正在提交…' : '解析文字菜谱'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: submitting ? null : () => submit(images: true),
            icon: const Icon(Icons.image_outlined),
            label: const Text('选择菜谱图片（最多 5 张）'),
          ),
        ],
      ],
    ),
  );
}
