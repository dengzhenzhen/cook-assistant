import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/data/database.dart';

void main() {
  test('cached recipe and kitchen survive database restart', () async {
    final dir = await Directory.systemTemp.createTemp('kaifan-test-');
    final file = File('${dir.path}/cache.sqlite');
    final first = AppDatabase.forTesting(NativeDatabase(file));
    await first.save('catalog', {
      'recipes': [
        {'name': '番茄炒蛋'},
      ],
      'kitchen': {'cook_count': 1},
      'selected': ['a'],
    });
    await first.close();
    final restored = AppDatabase.forTesting(NativeDatabase(file));
    final value = await restored.load('catalog');
    expect((value!['recipes'] as List).single['name'], '番茄炒蛋');
    expect(value['selected'], ['a']);
    await restored.close();
    await dir.delete(recursive: true);
  });
}
