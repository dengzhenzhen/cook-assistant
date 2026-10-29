import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/core/providers.dart';
import 'package:kaifan/data/models.dart';
import 'package:kaifan/data/repository.dart';
import 'package:kaifan/features/plan_page.dart';

class FixedCatalog extends CatalogController {
  @override
  Future<Catalog> build() async {
    final recipe = Recipe.empty();
    return Catalog(
      recipes: [recipe],
      selected: {recipe.id},
      kitchen: Kitchen({'kitchen_id': 'k', 'cook_count': 1, 'capacities': {}}),
    );
  }
}

class ConflictingApi extends ApiRepository {
  final targets = <DateTime?>[];
  @override
  Future<Map<String, dynamic>> plan(
    List<String> ids,
    String kitchen,
    DateTime? target,
  ) async {
    targets.add(target);
    final request = RequestOptions(path: '/plans/from-recipes');
    throw DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 409,
        data: {'detail': 'insufficient resource oven: need 1, available 0'},
      ),
    );
  }
}

void main() {
  testWidgets(
    'target is optional and missing oven error remains visible after dialog closes',
    (tester) async {
      final api = ConflictingApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProvider.overrideWith(FixedCatalog.new),
            repositoryProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: Scaffold(body: PlanPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('希望开饭时间'), findsNothing);
      await tester.ensureVisible(find.text('生成烹饪计划'));
      await tester.tap(find.text('生成烹饪计划'));
      await tester.pumpAndSettle();
      expect(api.targets.single, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('烤箱需要 1 个，目前配置 0 个'), findsWidgets);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('planning-error')), findsOneWidget);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('希望开饭时间'), findsOneWidget);
      await tester.ensureVisible(find.text('生成烹饪计划'));
      await tester.tap(find.text('生成烹饪计划'));
      await tester.pumpAndSettle();
      expect(api.targets.last, isNotNull);
    },
  );
  testWidgets('timeline renders a plan without a target finish time', (
    tester,
  ) async {
    final snapshot = <String, dynamic>{
      'origin': DateTime.now().toUtc().toIso8601String(),
      'recipes': {'r': '米饭'},
      'request': {
        'target_finish_seconds': null,
        'tasks': [
          {'id': 't', 'attention_type': 'passive', 'notes': ''},
        ],
      },
      'plan': {
        'finish_seconds': 30,
        'lateness_seconds': 0,
        'optimal': true,
        'warnings': [],
        'tasks': [
          {
            'task_id': 't',
            'recipe_id': 'r',
            'name': '煮饭',
            'start_seconds': 0,
            'end_seconds': 30,
          },
        ],
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: TimelinePage(snapshot: snapshot)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('开饭'), findsOneWidget);
    expect(find.text('开始烹饪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
