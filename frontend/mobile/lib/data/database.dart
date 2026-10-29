import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
part 'database.g.dart';

class Snapshots extends Table {
  TextColumn get key => text()();
  TextColumn get body => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Snapshots])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'kaifan',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );
  AppDatabase.forTesting(super.connection);
  @override
  int get schemaVersion => 1;

  String namespace = 'local';

  Future<Map<String, dynamic>?> load(String key, {String? scope}) async {
    final row =
        await (select(snapshots)
              ..where((t) => t.key.equals('${scope ?? namespace}:$key')))
            .getSingleOrNull();
    return row == null ? null : jsonDecode(row.body) as Map<String, dynamic>;
  }

  Future<void> save(
    String key,
    Map<String, dynamic> value, {
    String? scope,
  }) async {
    await into(snapshots).insertOnConflictUpdate(
      SnapshotsCompanion.insert(
        key: '${scope ?? namespace}:$key',
        body: jsonEncode(value),
      ),
    );
  }

  Future<void> remove(String key, {String? scope}) async {
    await (delete(
      snapshots,
    )..where((t) => t.key.equals('${scope ?? namespace}:$key'))).go();
  }
}

class ScopedStorage {
  ScopedStorage(this.db) : scope = db.namespace;
  final AppDatabase db;
  final String scope;
  bool get active => db.namespace == scope;
  Future<Map<String, dynamic>?> load(String key) => db.load(key, scope: scope);
  Future<void> save(String key, Map<String, dynamic> value) =>
      db.save(key, value, scope: scope);
  Future<void> remove(String key) => db.remove(key, scope: scope);
}
