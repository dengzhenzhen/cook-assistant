import 'dart:convert';

import 'package:uuid/uuid.dart';

Map<String, dynamic> cloneJson(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class Recipe {
  Recipe(this.json);
  final Map<String, dynamic> json;
  String get id => json['recipe_id'] as String;
  String get name => json['name'] as String;
  int get servings => json['servings'] as int? ?? 2;
  bool get favorite => json['favorite'] == true;
  List<Map<String, dynamic>> get tasks => (json['tasks'] as List)
      .map((t) => Map<String, dynamic>.from(t as Map))
      .toList();
  static Recipe empty() {
    final id = const Uuid().v4();
    return Recipe({
      'schema_version': '1.0',
      'recipe_id': id,
      'name': '',
      'servings': 2,
      'ingredients': <Map<String, dynamic>>[],
      'tasks': [newTask(id)],
      'holds': [],
      'max_holding_seconds': 300,
      'favorite': false,
      'confirmed': true,
      'source_type': 'manual',
      'estimated_fields': [],
    });
  }

  static Map<String, dynamic> newTask(String recipeId) => {
    'id': const Uuid().v4(),
    'recipe_id': recipeId,
    'name': '',
    'notes': '',
    'duration_seconds': 60,
    'attention_type': 'active',
    'dependencies': <String>[],
    'resources': <String, dynamic>{},
  };
}

class Kitchen {
  Kitchen(this.json);
  final Map<String, dynamic> json;
  String get id => json['kitchen_id'] as String;
  int get cooks => json['cook_count'] as int;
  Map<String, dynamic> get capacities =>
      Map<String, dynamic>.from(json['capacities'] as Map);
}

const resourceNames = {
  'burner': '灶眼',
  'wok': '炒锅',
  'pot': '汤锅',
  'steamer': '蒸锅',
  'rice_cooker': '电饭煲',
  'oven': '烤箱',
  'microwave': '微波炉',
  'air_fryer': '空气炸锅',
  'board': '菜板',
  'knife': '菜刀',
  'large_bowl': '大碗',
  'bowl': '小碗',
  'plate': '盘子',
};
