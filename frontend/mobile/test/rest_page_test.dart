import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/core/providers.dart';
import 'package:kaifan/data/database.dart';
import 'package:kaifan/data/repository.dart';
import 'package:kaifan/features/execution_page.dart';

void main() {
  testWidgets(
    'rest view shows next operation and early start requires consent without shifting dinner',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final api = ApiRepository();
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.reject(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          ),
        ),
      );
      final origin = DateTime.now().toUtc().toIso8601String();
      await db.save('active_session', {
        'version': 0,
        'mutation': null,
        'document': {
          'id': 'rest',
          'origin': origin,
          'auto_seconds': 60,
          'paused': false,
          'states': {
            'stew': {'status': 'running', 'started': 0},
          },
          'snapshot': {
            'request': {
              'target_finish_seconds': 10800,
              'cook_count': 1,
              'capacities': {'rice_cooker': 1, 'burner': 1},
              'holds': [],
              'tasks': [
                {
                  'id': 'stew',
                  'recipe_id': 's',
                  'name': '电锅慢炖',
                  'duration_seconds': 7200,
                  'attention_type': 'passive',
                  'resources': {'rice_cooker': 1},
                },
                {
                  'id': 'fry',
                  'recipe_id': 'v',
                  'name': '炒青菜',
                  'duration_seconds': 300,
                  'attention_type': 'active',
                  'resources': {'burner': 1},
                },
              ],
            },
            'plan': {
              'finish_seconds': 10800,
              'tasks': [
                {'task_id': 'stew', 'start_seconds': 0},
                {'task_id': 'fry', 'start_seconds': 10500},
              ],
            },
          },
        },
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            repositoryProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(home: ExecutionPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('等待下一次操作'), findsOneWidget);
      expect(find.textContaining('可以暂时休息'), findsOneWidget);
      await tester.ensureVisible(find.text('提前开始这一步'));
      await tester.tap(find.text('提前开始这一步'));
      await tester.pumpAndSettle();
      expect(find.text('提前开始这一步？'), findsOneWidget);
      await tester.tap(find.text('按原计划等待'));
      await tester.pumpAndSettle();
      expect(
        (await db.load('active_session'))!['document']['states']['fry'],
        isNull,
      );
      await tester.tap(find.text('提前开始这一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('现在开始'));
      await tester.pumpAndSettle();
      final cache = (await db.load('active_session'))!['document'];
      expect(cache['states']['fry']['status'], 'running');
      expect(cache['snapshot']['request']['target_finish_seconds'], 10800);
      expect(cache['origin'], origin);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
    },
  );
}
