import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaifan/core/providers.dart';
import 'package:kaifan/data/database.dart';
import 'package:kaifan/data/models.dart';
import 'package:kaifan/data/repository.dart';
import 'package:kaifan/features/editor_page.dart';
import 'package:kaifan/features/import_page.dart';
import 'package:kaifan/features/recipe_text_field.dart';

class CaptureImport extends ApiRepository {
  String? submitted;
  @override
  Future<Map<String, dynamic>> importText(String text) async {
    submitted = text;
    throw StateError('Test stops before AI submission');
  }
}

class CaptureCatalog extends CatalogController {
  Recipe? saved;
  @override
  Future<Catalog> build() async => Catalog(recipes: [], selected: {});
  @override
  Future<void> saveRecipe(Recipe recipe) async {
    saved = recipe;
  }
}

void main() {
  const channel = MethodChannel('kaifan/input_compat');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets(
    'actual import page submits committed native multiline text; cancel retains it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final api = CaptureImport();
      String? response = '番茄炒蛋\n放盐出锅';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'isWsa') return true;
        if (call.method == 'editRecipeText') {
          expect(call.arguments['multiline'], true);
          return response;
        }
        return null;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            repositoryProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: ImportPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, true);
      await tester.tap(find.byType(RecipeTextField));
      await tester.pumpAndSettle();
      expect(find.text('番茄炒蛋\n放盐出锅'), findsOneWidget);
      response = null;
      await tester.tap(find.byType(RecipeTextField));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('解析文字菜谱'));
      await tester.tap(find.text('解析文字菜谱'));
      await tester.pumpAndSettle();
      expect(api.submitted, '番茄炒蛋\n放盐出锅');
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'actual editor saves native replacement without restoring initial name',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final catalog = CaptureCatalog();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'isWsa') return true;
        if (call.method == 'editRecipeText') return 'Z菜谱';
        return null;
      });
      final recipe = Recipe.empty();
      recipe.json['name'] = 'ABCD';
      recipe.json['tasks'][0]['name'] = '搅拌';
      final router = GoRouter(
        initialLocation: '/edit',
        routes: [
          GoRoute(
            path: '/edit',
            builder: (_, _) => EditorPage(recipe: recipe),
          ),
          GoRoute(
            path: '/recipes',
            builder: (_, _) => const Scaffold(body: Text('保存完成')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            catalogProvider.overrideWith(() => catalog),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(RecipeTextField, 'ABCD'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('确认内容并保存菜谱'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认内容并保存菜谱'));
      await tester.pumpAndSettle();
      expect(catalog.saved!.name, 'Z菜谱');
      expect(find.text('保存完成'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await db.close();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('ordinary Android retains inline keyboard input', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => false,
    );
    final controller = TextEditingController(text: 'ABCD');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecipeTextField(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, false);
    await tester.enterText(find.byType(TextFormField), 'Z');
    expect(controller.text, 'Z');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
