import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/features/task_completion_button.dart';

void main() {
  testWidgets(
    'early background completion requires approval; cancel preserves timer',
    (tester) async {
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCompletionButton(
              name: '低温焖烤',
              background: true,
              remainingSeconds: () => 3600,
              onComplete: () async {
                completed++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('✓ 完成这一步，进入下一步'));
      await tester.pumpAndSettle();
      expect(find.textContaining('预计还剩 60 分钟'), findsOneWidget);
      expect(completed, 0);
      await tester.tap(find.text('继续计时'));
      await tester.pumpAndSettle();
      expect(completed, 0);
      await tester.tap(find.text('✓ 完成这一步，进入下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提前完成'));
      await tester.pumpAndSettle();
      expect(completed, 1);
    },
  );
  for (final scenario in [(true, 0), (false, 30)]) {
    testWidgets(
      'expired background or manual task completes directly $scenario',
      (tester) async {
        var completed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskCompletionButton(
                name: '任务',
                background: scenario.$1,
                remainingSeconds: () => scenario.$2,
                onComplete: () async {
                  completed++;
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('✓ 完成这一步，进入下一步'));
        await tester.pumpAndSettle();
        expect(completed, 1);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
}
