import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/core/providers.dart';
import 'package:kaifan/data/database.dart';
import 'package:kaifan/data/models.dart';
import 'package:kaifan/data/repository.dart';
import 'package:kaifan/features/editor_page.dart';

class OfflineRepository extends ApiRepository {
  @override
  Future<Map<String, dynamic>> object(String path) async =>
      throw StateError('API must not be used for a saved draft');
}

void main() {
  testWidgets(
    'AI confirmation editor restores a draft without route extras or network',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final draft = Recipe.empty();
      draft.json['name'] = '恢复的菜谱';
      draft.json['confirmed'] = false;
      await db.save('draft:${draft.id}', draft.json);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            repositoryProvider.overrideWithValue(OfflineRepository()),
          ],
          child: MaterialApp(home: RecipeEditorRoute(id: draft.id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('确认识别结果'), findsOneWidget);
      expect(find.text('恢复的菜谱'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
    },
  );
}
