import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/outbox.dart';
import 'dart:async';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final repositoryProvider = Provider<ApiRepository>((ref) => ApiRepository());

class Catalog {
  Catalog({
    required this.recipes,
    this.kitchen,
    required this.selected,
    this.offline = false,
    this.message,
  });
  final List<Recipe> recipes;
  final Kitchen? kitchen;
  final Set<String> selected;
  final bool offline;
  final String? message;
  Map<String, dynamic> toJson() => {
    'recipes': recipes.map((r) => r.json).toList(),
    'kitchen': kitchen?.json,
    'selected': selected.toList(),
  };
}

final catalogProvider = AsyncNotifierProvider<CatalogController, Catalog>(
  CatalogController.new,
);

class CatalogController extends AsyncNotifier<Catalog> {
  Timer? retry;
  bool refreshing = false;
  @override
  Future<Catalog> build() async {
    final db = ref.read(databaseProvider), api = ref.read(repositoryProvider);
    final namespace = db.namespace;
    final cache = await db.load('catalog', scope: namespace);
    retry?.cancel();
    retry = Timer.periodic(const Duration(seconds: 20), (_) {
      if (state.value?.offline == true) refresh();
    });
    ref.onDispose(() => retry?.cancel());
    final selected = ((cache?['selected'] as List?) ?? [])
        .cast<String>()
        .toSet();
    try {
      await Outbox(db, api).flush();
      final results = await Future.wait<Object>([api.recipes(), api.kitchen()]);
      final recipes = results[0] as List<Recipe>;
      final value = Catalog(
        recipes: recipes,
        kitchen: results[1] as Kitchen,
        selected: selected.intersection(recipes.map((r) => r.id).toSet()),
      );
      if (namespace != db.namespace) throw StateError('账号已切换');
      await db.save('catalog', value.toJson());
      return value;
    } catch (e) {
      if (namespace != db.namespace) throw StateError('账号已切换');
      return Catalog(
        recipes: ((cache?['recipes'] as List?) ?? [])
            .map((r) => Recipe(Map<String, dynamic>.from(r as Map)))
            .toList(),
        kitchen: cache?['kitchen'] == null
            ? null
            : Kitchen(Map<String, dynamic>.from(cache!['kitchen'] as Map)),
        selected: selected,
        offline: true,
        message: errorMessage(e),
      );
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      state = await AsyncValue.guard(build);
    } finally {
      refreshing = false;
    }
  }

  Future<void> toggle(String id) async {
    final old = state.requireValue, selected = {...old.selected};
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    final value = Catalog(
      recipes: old.recipes,
      kitchen: old.kitchen,
      selected: selected,
      offline: old.offline,
      message: old.message,
    );
    state = AsyncData(value);
    await ref.read(databaseProvider).save('catalog', value.toJson());
  }

  Future<void> saveRecipe(Recipe recipe) async {
    final catalog = await future;
    final previous = catalog.recipes
        .where((r) => r.id == recipe.id)
        .firstOrNull;
    final db = ref.read(databaseProvider);
    final namespace = db.namespace;
    await Outbox(
      db,
      ref.read(repositoryProvider),
    ).enqueue('recipe', previous?.json, recipe.json);
    if (namespace != db.namespace) return;
    final updated = Catalog(
      recipes: [...catalog.recipes.where((r) => r.id != recipe.id), recipe],
      kitchen: catalog.kitchen,
      selected: catalog.selected,
      offline: true,
      message: '本地编辑等待同步',
    );
    await db.save('catalog', updated.toJson());
    state = AsyncData(updated);
    await refresh();
  }

  Future<void> saveKitchen(Kitchen kitchen) async {
    final catalog = await future;
    final db = ref.read(databaseProvider);
    final namespace = db.namespace;
    await Outbox(
      db,
      ref.read(repositoryProvider),
    ).enqueue('kitchen', catalog.kitchen?.json, kitchen.json);
    if (namespace != db.namespace) return;
    final updated = Catalog(
      recipes: catalog.recipes,
      kitchen: kitchen,
      selected: catalog.selected,
      offline: true,
      message: '厨房配置等待同步',
    );
    await db.save('catalog', updated.toJson());
    state = AsyncData(updated);
    await refresh();
  }

  Future<void> favorite(Recipe recipe) async {
    final updated = cloneJson(recipe.json);
    updated['favorite'] = !recipe.favorite;
    await saveRecipe(Recipe(updated));
  }
}
