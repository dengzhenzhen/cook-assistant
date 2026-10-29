import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/repository.dart';
import 'providers.dart';
import 'reminders.dart';

final authProvider =
    AsyncNotifierProvider<AuthController, Map<String, dynamic>?>(
      AuthController.new,
    );

class AuthController extends AsyncNotifier<Map<String, dynamic>?> {
  final storage = const FlutterSecureStorage();
  Future<Map<String, dynamic>>? refreshing;
  @override
  Future<Map<String, dynamic>?> build() async {
    final server = await storage.read(key: 'kaifan.server');
    if (server != null) {
      ref.read(repositoryProvider).dio.options.baseUrl = server;
    }
    final raw = await storage.read(key: 'kaifan.auth');
    final value = raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    configure(value);
    ref.invalidate(catalogProvider);
    return value;
  }

  void configure(Map<String, dynamic>? value) {
    final api = ref.read(repositoryProvider);
    ref.read(databaseProvider).namespace =
        value?['user_id'] as String? ?? 'signed-out';
    api.dio.options.headers['Authorization'] = value == null
        ? ''
        : 'Bearer ${value['access_token']}';
    api.dio.interceptors.clear();
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (error.response?.statusCode != 401 ||
              error.requestOptions.extra['retried'] == true ||
              value == null) {
            handler.next(error);
            return;
          }
          try {
            final current = state.value ?? value;
            final Map<String, dynamic> token;
            if (error.requestOptions.headers['Authorization'] !=
                api.dio.options.headers['Authorization']) {
              token = current;
            } else {
              refreshing ??= refresh(current);
              token = await refreshing!;
            }
            error.requestOptions.headers['Authorization'] =
                'Bearer ${token['access_token']}';
            error.requestOptions.extra['retried'] = true;
            handler.resolve(await api.dio.fetch<dynamic>(error.requestOptions));
          } catch (refreshError) {
            if (refreshError is DioException &&
                refreshError.response?.statusCode == 401) {
              await storage.delete(key: 'kaifan.auth');
              configure(null);
              state = const AsyncData(null);
            }
            handler.next(error);
          } finally {
            refreshing = null;
          }
        },
      ),
    );
  }

  Future<Map<String, dynamic>> refresh(Map<String, dynamic> previous) async {
    final dio = Dio(
      BaseOptions(baseUrl: ref.read(repositoryProvider).dio.options.baseUrl),
    );
    final response = await dio.post(
      '/api/v1/auth/refresh',
      data: {'refresh_token': previous['refresh_token']},
    );
    final value = Map<String, dynamic>.from(response.data as Map);
    await storage.write(key: 'kaifan.auth', value: jsonEncode(value));
    state = AsyncData(value);
    configure(value);
    return value;
  }

  Future<void> login(String email, String password, bool register) async {
    final api = ref.read(repositoryProvider);
    final response = await api.dio.post(
      '/api/v1/auth/${register ? 'register' : 'login'}',
      data: {'email': email, 'password': password},
    );
    final value = Map<String, dynamic>.from(response.data as Map);
    await storage.write(key: 'kaifan.auth', value: jsonEncode(value));
    configure(value);
    state = AsyncData(value);
    ref.invalidate(catalogProvider);
  }

  Future<void> setServer(String server) async {
    final uri = Uri.tryParse(server);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入有效的服务器 URL。');
    }
    ref.read(repositoryProvider).dio.options.baseUrl = server.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    await storage.write(key: 'kaifan.server', value: server);
  }

  Future<void> logout() async {
    final value = state.value;
    try {
      await ref
          .read(repositoryProvider)
          .dio
          .post(
            '/api/v1/auth/logout',
            data: {'refresh_token': value?['refresh_token']},
          );
    } catch (_) {}
    try {
      final reminders = appReminders;
      await reminders.initialize();
      if (reminders.ready) await reminders.plugin.cancelAll();
    } catch (_) {}
    await storage.delete(key: 'kaifan.auth');
    configure(null);
    state = const AsyncData(null);
    ref.invalidate(catalogProvider);
  }
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  late final server = TextEditingController(
    text: ref.read(repositoryProvider).dio.options.baseUrl,
  );
  bool register = false, busy = false;
  String? error;
  @override
  void dispose() {
    server.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.soup_kitchen, size: 64),
              const SizedBox(height: 24),
              Text(
                register ? '创建开饭账号' : '欢迎回到开饭',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: server,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  helperText: '手机填写电脑局域网 IP，例如 http://192.168.1.10:8002',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '邮箱'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码（至少 8 位）'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await ref
                              .read(authProvider.notifier)
                              .setServer(server.text.trim());
                          await ref
                              .read(authProvider.notifier)
                              .login(
                                email.text.trim(),
                                password.text,
                                register,
                              );
                        } catch (e) {
                          if (mounted) setState(() => error = errorMessage(e));
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: Text(
                  busy
                      ? '请稍候…'
                      : register
                      ? '注册并登录'
                      : '登录',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => register = !register),
                child: Text(register ? '已有账号，去登录' : '没有账号，去注册'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
