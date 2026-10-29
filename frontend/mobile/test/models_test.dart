import 'package:flutter_test/flutter_test.dart';
import 'package:kaifan/data/models.dart';
import 'package:kaifan/data/route_codec.dart';

void main() {
  test(
    'new manual recipe has namespaced tasks and independent dependencies',
    () {
      final recipe = Recipe.empty();
      expect(recipe.tasks.single['recipe_id'], recipe.id);
      expect(recipe.tasks.single['dependencies'], isEmpty);
      final copy = cloneJson(recipe.json);
      (copy['tasks'] as List).first['notes'] = '小火翻炒 30 秒，转大火后放盐。';
      expect(recipe.tasks.single['notes'], '');
      expect(Recipe(copy).tasks.single['notes'], contains('放盐'));
    },
  );
  test(
    'recipe editor route retains typed data through history serialization',
    () {
      final recipe = Recipe.empty();
      const codec = AppExtraCodec();
      final restored = codec.decode(codec.encode(recipe)) as Recipe;
      expect(restored.id, recipe.id);
      expect(restored.tasks.single['recipe_id'], recipe.id);
    },
  );
}
