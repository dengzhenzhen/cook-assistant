import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/data/cooking_session.dart';
import 'package:kaifan/data/reminder_intents.dart';

void main() {
  final origin = DateTime.utc(2026, 10, 28, 8);
  CookingSession session() => CookingSession.start(
    {
      'origin': origin.toIso8601String(),
      'request': {
        'target_finish_seconds': 10800,
        'cook_count': 1,
        'capacities': {'rice_cooker': 1, 'burner': 1},
        'holds': [],
        'tasks': [
          {
            'id': 'stew',
            'recipe_id': 's',
            'name': '长时间炖煮',
            'duration_seconds': 7200,
            'attention_type': 'passive',
            'resources': {'rice_cooker': 1},
            'dependencies': [],
          },
          {
            'id': 'fry',
            'recipe_id': 'v',
            'name': '炒青菜',
            'duration_seconds': 300,
            'attention_type': 'active',
            'resources': {'burner': 1},
            'dependencies': [],
          },
        ],
      },
      'plan': {
        'finish_seconds': 10800,
        'tasks': [
          {'task_id': 'stew', 'start_seconds': 0, 'end_seconds': 7200},
          {'task_id': 'fry', 'start_seconds': 10500, 'end_seconds': 10800},
        ],
      },
    },
    's',
    origin,
  );
  test(
    'long passive cooking enters rest and never starts vegetables before dinner window',
    () {
      final s = session();
      s.tick(origin);
      expect(s.states['stew']['status'], 'running');
      expect(s.json['resting'], true);
      expect(s.startNext(origin.add(const Duration(hours: 1))), false);
      s.tick(origin.add(const Duration(seconds: 7260)));
      expect(s.states['stew']['status'], 'completed');
      expect(s.states.containsKey('fry'), false);
      s.tick(origin.add(const Duration(seconds: 10600)));
      expect(
        s.states.containsKey('fry'),
        false,
        reason: 'A notification cannot start manual work',
      );
      expect(
        s.startScheduled('fry', origin.add(const Duration(seconds: 10600))),
        true,
      );
      expect(s.states['fry']['started'], 10600);
    },
  );
  test(
    'target keeps original wall clock even if first task is scheduled much later',
    () {
      final snapshot = session().snapshot;
      snapshot['plan']['tasks'][0]['start_seconds'] = 3600;
      final s = CookingSession.start(
        snapshot,
        'late',
        origin.add(const Duration(minutes: 5)),
      );
      expect(s.json['origin'], origin.toIso8601String());
      s.tick(origin.add(const Duration(minutes: 5)));
      expect(s.states, isEmpty);
      expect(s.json['resting'], true);
      expect(
        s.readyToStart('stew', origin.add(const Duration(minutes: 6))),
        false,
      );
      expect(
        s.startScheduled(
          'stew',
          origin.add(const Duration(minutes: 6)),
          allowEarly: true,
        ),
        true,
      );
      expect(s.request['target_finish_seconds'], 10800);
    },
  );
  test(
    'rest alarms include future frying as well as running device completion',
    () {
      final s = session();
      s.tick(origin);
      final intents = reminderIntents(s, origin);
      expect(intents.length, 2);
      expect(intents[0].at, origin.add(const Duration(hours: 2)));
      expect(intents[1].at, origin.add(const Duration(seconds: 10500)));
      expect(intents[1].title, contains('炒青菜'));
      expect(s.states.containsKey('fry'), false);
      s.json['paused'] = true;
      expect(reminderIntents(s, origin).length, 1);
    },
  );
  test('legacy dinner restoration preserves every execution fact', () {
    final s = session();
    s.json.remove('clock_version');
    s.json['origin'] = origin
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    s.json['states'] = {
      'stew': {'status': 'running', 'started': 3600},
    };
    expect(s.restoreDinnerTarget(), true);
    expect(s.request['target_finish_seconds'], 14400);
    expect(s.states['stew']['started'], 3600);
    expect(s.upcoming().single['start_seconds'], 14100);
    expect(s.restoreDinnerTarget(), false);
  });
  test(
    'early device setup hands off to its passive cook without starting later dishes',
    () {
      final s = session();
      final prep = {
        'id': 'prep',
        'recipe_id': 's',
        'name': '放入材料并启动电锅',
        'duration_seconds': 60,
        'attention_type': 'active',
        'resources': <String, int>{},
        'dependencies': <String>[],
      };
      (s.request['tasks'] as List).insert(0, prep);
      (s.request['tasks'] as List)[1]['dependencies'] = ['prep'];
      (s.snapshot['plan']['tasks'] as List).insert(0, {
        'task_id': 'prep',
        'start_seconds': 0,
      });
      (s.snapshot['plan']['tasks'] as List)[1]['start_seconds'] = 3600;
      s.tick(origin);
      expect(s.complete('prep', 30), true);
      expect(
        s.startNext(origin.add(const Duration(seconds: 30)), afterTask: 'prep'),
        true,
      );
      s.tick(origin.add(const Duration(seconds: 30)));
      expect(s.states['stew']['started'], 30);
      expect(s.states.containsKey('fry'), false);
      expect(s.json['resting'], true);
      expect(s.request['target_finish_seconds'], 10800);
    },
  );
}
