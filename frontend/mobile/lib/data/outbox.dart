import 'package:dio/dio.dart';
import 'database.dart';
import 'repository.dart';

/// A single serial queue, persisted before any network request. Acknowledged
/// edits are removed individually, so retries survive process termination.
class Outbox {
  Outbox(this.db, this.api) : store = ScopedStorage(db);
  final AppDatabase db;
  final ScopedStorage store;
  final ApiRepository api;
  Future<List<Map<String, dynamic>>> entries() async =>
      ((await store.load('edit_outbox'))?['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<void> enqueue(
    String kind,
    Map<String, dynamic>? base,
    Map<String, dynamic> document,
  ) async {
    final items = await entries();
    final key = kind == 'recipe' ? 'recipe_id' : 'kitchen_id';
    final index = items.indexWhere(
      (e) => e['kind'] == kind && e['document'][key] == document[key],
    );
    if (index >= 0) {
      items[index]['document'] = document;
    } else {
      items.add({'kind': kind, 'base': base, 'document': document});
    }
    await store.save('edit_outbox', {'items': items});
  }

  Future<void> flush() async {
    var items = await entries();
    while (items.isNotEmpty) {
      if (!store.active) return;
      final current = items.first;
      try {
        await api.syncEdit(current);
      } on DioException {
        rethrow;
      }
      // Preserve edits made while the request was in flight.
      items = await entries();
      if (items.isNotEmpty &&
          items.first['document'].toString() ==
              current['document'].toString()) {
        items.removeAt(0);
      } else if (items.isNotEmpty) {
        items.first['base'] = current['document'];
      }
      await store.save('edit_outbox', {'items': items});
    }
  }
}
