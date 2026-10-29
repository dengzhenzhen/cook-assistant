import 'package:flutter/material.dart';

/// Background heat/device steps require deliberate confirmation before time is up.
class TaskCompletionButton extends StatelessWidget {
  const TaskCompletionButton({
    super.key,
    required this.name,
    required this.background,
    required this.remainingSeconds,
    required this.onComplete,
  });
  final String name;
  final bool background;
  final int Function() remainingSeconds;
  final Future<void> Function() onComplete;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: () async {
      final remaining = remainingSeconds();
      if (background && remaining > 0) {
        final minutes = (remaining / 60).ceil();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('提前完成这一步？'),
            content: Text(
              '「$name」预计还剩 $minutes 分钟。请确认食物已达到需要的状态，并检查设备或火源，再进入下一步。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续计时'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认提前完成'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }
      await onComplete();
    },
    child: const Text('✓ 完成这一步，进入下一步'),
  );
}
