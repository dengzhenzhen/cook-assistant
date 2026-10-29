import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/core/providers.dart';
import 'package:kaifan/data/database.dart';
import 'package:kaifan/data/models.dart';
import 'package:kaifan/data/repository.dart';

class DelayedRepository extends ApiRepository {
  final ready = Completer<void>();
  Recipe? saved;
  @override
  Future<List<Recipe>> recipes() async {
    await ready.future;
    return saved == null ? [] : [saved!];
  }

  @override
  Future<Kitchen> kitchen() async =>
      Kitchen({'kitchen_id': 'k', 'cook_count': 1, 'capacities': {}});
  @override
  Future<void> syncEdit(Map<String, dynamic> edit) async {
    expect(edit['base'], isNull);
    saved = Recipe(Map<String, dynamic>.from(edit['document'] as Map));
  }
}

void main() {
  test('saving a refreshed editor waits for catalog initialization', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DelayedRepository();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        repositoryProvider.overrideWithValue(repository),
      ],
    );
    final recipe = Recipe.empty();
    final save = container.read(catalogProvider.notifier).saveRecipe(recipe);
    repository.ready.complete();
    await save;
    expect(repository.saved?.id, recipe.id);
    expect(
      container.read(catalogProvider).requireValue.recipes.single.id,
      recipe.id,
    );
    container.dispose();
    await database.close();
  });
}
