import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/data/cooking_session.dart';

void main() {
  final origin = DateTime.utc(2026, 10, 28);
  Map<String, dynamic> task(
    String id,
    String attention,
    Map<String, int> resources, {
    List<String> dependencies = const [],
  }) => {
    'id': id,
    'recipe_id': 'r',
    'name': id,
    'duration_seconds': 10,
    'attention_type': attention,
    'resources': resources,
    'dependencies': dependencies,
  };
  CookingSession create(List<Map<String, dynamic>> tasks) =>
      CookingSession.start(
        {
          'request': {
            'tasks': tasks,
            'capacities': {'rice_cooker': 1, 'burner': 1},
            'cook_count': 1,
            'holds': [],
          },
          'plan': {
            'tasks': tasks
                .map((t) => {'task_id': t['id'], 'start_seconds': 0})
                .toList(),
          },
        },
        'session',
        origin,
      );
  test('manual and device run concurrently; fire never auto confirms', () {
    final s = create([
      task('rice', 'passive', {'rice_cooker': 1}),
      task('fire', 'passive', {'burner': 1}),
    ]);
    s.tick(origin);
    expect(s.states.length, 2);
    s.tick(origin.add(const Duration(seconds: 70)));
    expect(s.states['rice']['status'], 'completed');
    expect(s.states['fire']['status'], 'running');
  });
  test('confirm advances DAG and respects single cook', () {
    final s = create([
      task('first', 'active', {}),
      task('next', 'active', {}, dependencies: ['first']),
      task('independent', 'active', {}),
    ]);
    s.tick(origin);
    expect(s.states.keys, ['first']);
    s.complete('first', 5);
    s.tick(origin.add(const Duration(seconds: 5)));
    expect(s.states['next']['status'], 'running');
    expect(s.states.containsKey('independent'), false);
  });
  test('restore uses wall time; pause does not stop physical timer', () {
    final s = create([
      task('rice', 'passive', {'rice_cooker': 1}),
    ]);
    s.tick(origin);
    s.json['paused'] = true;
    final restored = CookingSession(s.json);
    restored.tick(origin.add(const Duration(seconds: 90)));
    expect(restored.finished, true);
  });
  test('start now aligns first planned task without a long idle offset', () {
    final snapshot = create([
      task('rice', 'passive', {'rice_cooker': 1}),
    ]).snapshot;
    snapshot['plan']['tasks'][0]['start_seconds'] = 2400;
    final session = CookingSession.start(snapshot, 'new', origin);
    session.tick(origin);
    expect(session.states['rice']['status'], 'running');
    expect(session.states['rice']['started'], 2400);
    expect(session.elapsed(origin.add(const Duration(seconds: 5))), 2405);
  });
}
