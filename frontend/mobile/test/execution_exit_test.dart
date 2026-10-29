import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaifan/core/providers.dart';
import 'package:kaifan/data/database.dart';
import 'package:kaifan/data/repository.dart';
import 'package:kaifan/features/execution_page.dart';

void main() {
  testWidgets(
    'completed session exits to recipes and preserves pending offline progress',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final api = ApiRepository();
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          ),
        ),
      );
      await db.save('active_session', {
        'version': 0,
        'mutation': 'pending-final',
        'document': {
          'id': 'finished',
          'origin': DateTime.now().toUtc().toIso8601String(),
          'auto_seconds': 60,
          'paused': false,
          'states': {
            't': {'status': 'completed', 'started': 0, 'ended': 10},
          },
          'snapshot': {
            'request': {
              'tasks': [
                {
                  'id': 't',
                  'name': '装盘',
                  'recipe_id': 'r',
                  'duration_seconds': 10,
                  'attention_type': 'active',
                },
              ],
            },
            'plan': {
              'finish_seconds': 10,
              'tasks': [
                {'task_id': 't', 'start_seconds': 0},
              ],
            },
          },
        },
      });
      final router = GoRouter(
        initialLocation: '/execute',
        routes: [
          GoRoute(path: '/execute', builder: (_, _) => const ExecutionPage()),
          GoRoute(
            path: '/recipes',
            builder: (_, _) => const Scaffold(body: Text('菜谱首页')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            repositoryProvider.overrideWithValue(api),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('完成并返回菜谱'), findsOneWidget);
      await tester.ensureVisible(find.text('完成并返回菜谱'));
      await tester.tap(find.text('完成并返回菜谱'));
      await tester.pumpAndSettle();
      expect(find.text('菜谱首页'), findsOneWidget);
      final history = await db.load('history:finished');
      expect(history!['mutation'], 'pending-final');
      expect(history['document']['states']['t']['status'], 'completed');
      expect((await db.load('active_session'))!['mutation'], 'pending-final');
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await db.close();
    },
  );
}
