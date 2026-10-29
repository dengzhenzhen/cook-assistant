import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

String get defaultApiUrl => const String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000',
);

class ApiRepository {
  ApiRepository({Dio? client})
    : dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: defaultApiUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
  final Dio dio;
  Future<Map<String, dynamic>> object(String path) async =>
      Map<String, dynamic>.from((await dio.get(path)).data as Map);
  Future<void> syncEdit(Map<String, dynamic> edit) async {
    await dio.post('/api/v1/sync/edit', data: edit);
  }

  Future<List<Recipe>> recipes() async =>
      ((await dio.get('/api/v1/recipes')).data as List)
          .map((r) => Recipe(Map<String, dynamic>.from(r as Map)))
          .toList();
  Future<Kitchen> kitchen() async =>
      Kitchen(await object('/api/v1/kitchens/default'));
  Future<void> saveRecipe(Recipe recipe, {required bool existing}) async {
    if (existing) {
      await dio.put('/api/v1/recipes/${recipe.id}', data: recipe.json);
    } else {
      await dio.post('/api/v1/recipes', data: recipe.json);
    }
  }

  Future<void> deleteRecipe(String id) async {
    await dio.delete('/api/v1/recipes/$id');
  }

  Future<void> saveKitchen(Kitchen kitchen) async {
    await dio.put('/api/v1/kitchens/${kitchen.id}', data: kitchen.json);
  }

  Future<Map<String, dynamic>> plan(
    List<String> ids,
    String kitchen,
    DateTime? target,
  ) async => Map<String, dynamic>.from(
    (await dio.post(
          '/api/v1/plans/from-recipes',
          data: {
            'recipe_ids': ids,
            'kitchen_id': kitchen,
            if (target != null)
              'target_finish_time': target.toUtc().toIso8601String(),
          },
        )).data
        as Map,
  );
  Future<Map<String, dynamic>> importText(String text) async =>
      Map<String, dynamic>.from(
        (await dio.post(
              '/api/v1/recipes/import/text',
              data: {'text': text},
            )).data
            as Map,
      );
  Future<Map<String, dynamic>> importImages(List<MultipartFile> files) async =>
      Map<String, dynamic>.from(
        (await dio.post(
              '/api/v1/recipes/import/image',
              data: FormData.fromMap({'images': files}),
              options: Options(receiveTimeout: const Duration(seconds: 60)),
            )).data
            as Map,
      );
}

String errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return schedulingMessage(data['detail'] as String);
    }
    if (data is Map && data['detail'] is List) {
      return (data['detail'] as List).map((e) => e['msg']).join('；');
    }
    return '无法连接服务，请检查后端地址和网络。';
  }
  return error.toString();
}

String schedulingMessage(String message) {
  final match = RegExp(
    r'insufficient resource (.+): need (\d+), available (\d+)',
  ).firstMatch(message);
  if (match != null) {
    final resource = match.group(1)!;
    return '厨房设备不足：${resourceNames[resource] ?? resource}需要 ${match.group(2)} 个，目前配置 ${match.group(3)} 个。请修改厨房设备数量，或调整菜谱所需设备。';
  }
  if (message == 'infeasible resource/execution constraints') {
    return '当前设备占用或任务执行状态存在冲突，无法生成可行计划。请检查厨房配置及任务依赖。';
  }
  if (message == 'solver could not find a plan within the time limit') {
    return '本次未能及时生成计划，请重试或减少所选菜谱。';
  }
  return message;
}
