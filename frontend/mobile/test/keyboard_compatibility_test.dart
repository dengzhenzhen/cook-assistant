import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/core/keyboard_compatibility.dart';

void main() {
  for (final wsa in [true, false]) {
    testWidgets('clear and retype preserves only new text; WSA=$wsa', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('kaifan/input_compat');
      var resets = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'isWsa') return wsa;
        if (call.method == 'resetAfterClear') resets++;
        return null;
      });
      final controller = TextEditingController(text: 'ABCD');
      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardCompatibility(
            child: Scaffold(body: TextField(controller: controller)),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.pump();
      expect(resets, wsa ? 1 : 0);
      await tester.enterText(find.byType(TextField), 'Z');
      await tester.pump();
      expect(controller.text, 'Z');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
