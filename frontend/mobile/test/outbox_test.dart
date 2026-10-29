import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/data/database.dart';
import 'package:kaifan/data/outbox.dart';
import 'package:kaifan/data/repository.dart';

class SyncRepository extends ApiRepository {
  bool online = false;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> syncEdit(Map<String, dynamic> edit) async {
    if (!online) {
      throw DioException(requestOptions: RequestOptions(path: '/sync'));
    }
    sent.add(edit);
  }
}

void main() {
  test(
    'offline queue keeps original base, retries latest edit, and isolates accounts',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final api = SyncRepository(), outbox = Outbox(db, SyncRepository());
      await outbox.enqueue(
        'recipe',
        {'recipe_id': 'r', 'name': 'original'},
        {'recipe_id': 'r', 'name': 'first'},
      );
      await outbox.enqueue(
        'recipe',
        {'recipe_id': 'r', 'name': 'first'},
        {'recipe_id': 'r', 'name': 'second'},
      );
      final restored = Outbox(db, api);
      await expectLater(restored.flush(), throwsA(isA<DioException>()));
      expect((await restored.entries()).length, 1);
      api.online = true;
      await restored.flush();
      expect(api.sent.single['base']['name'], 'original');
      expect(api.sent.single['document']['name'], 'second');
      expect(await restored.entries(), isEmpty);
      await restored.enqueue('recipe', null, {'recipe_id': 'private'});
      db.namespace = 'other-account';
      expect(await Outbox(db, api).entries(), isEmpty);
      await restored.flush();
      expect(api.sent.length, 1);
      db.namespace = 'local';
      expect((await restored.entries()).length, 1);
      await db.close();
    },
  );
}
