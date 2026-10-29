import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/auth.dart';
import 'core/keyboard_compatibility.dart';
import 'core/reminders.dart';
import 'features/execution_page.dart';
import 'data/models.dart';
import 'data/route_codec.dart';
import 'features/catalog_pages.dart';
import 'features/editor_page.dart';
import 'features/import_page.dart';
import 'features/plan_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  appReminders.onTap = () => router.go('/execute');
  try {
    await appReminders.initialize();
    if (appReminders.ready &&
        (await appReminders.plugin.getNotificationAppLaunchDetails())
                ?.didNotificationLaunchApp ==
            true) {
      router.go('/execute');
    }
  } catch (_) {
    /* Permission and platform failures are shown on execution page. */
  }
  runApp(const ProviderScope(child: KaifanApp()));
}

final router = GoRouter(
  initialLocation: '/recipes',
  extraCodec: const AppExtraCodec(),
  routes: [
    GoRoute(path: '/execute', builder: (_, _) => const ExecutionPage()),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/recipes', builder: (_, _) => const RecipesPage()),
        GoRoute(path: '/plan', builder: (_, _) => const PlanPage()),
        GoRoute(path: '/mine', builder: (_, _) => const MinePage()),
      ],
    ),
    GoRoute(
      path: '/kitchen',
      builder: (_, state) => KitchenPage(
        returnTo: state.uri.queryParameters['from'] == 'plan'
            ? '/plan'
            : '/mine',
      ),
    ),
    GoRoute(path: '/import', builder: (_, _) => const ImportPage()),
    GoRoute(
      path: '/recipe/new',
      builder: (_, _) => EditorPage(recipe: Recipe.empty()),
    ),
    GoRoute(
      path: '/recipe/edit/:id',
      builder: (_, state) => RecipeEditorRoute(
        id: state.pathParameters['id']!,
        initial: state.extra is Recipe ? state.extra as Recipe : null,
      ),
    ),
    GoRoute(
      path: '/timeline',
      builder: (_, state) =>
          TimelinePage(snapshot: state.extra as Map<String, dynamic>?),
    ),
  ],
);

class KaifanApp extends ConsumerWidget {
  const KaifanApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    builder: (context, child) => KeyboardCompatibility(
      child: ref
          .watch(authProvider)
          .when(
            data: (account) => account == null ? const LoginPage() : child!,
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) =>
                Scaffold(body: Center(child: Text('登录存储不可用：$error'))),
          ),
    ),
    title: '开饭',
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansSC',
      scaffoldBackgroundColor: const Color(0xfff8f6f0),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffcd5430),
        primary: const Color(0xffcd5430),
        secondary: const Color(0xff536f46),
        surface: const Color(0xfffffefa),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff8f6f0),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xfffffefa),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
    ),
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = path == '/plan'
        ? 1
        : path == '/mine'
        ? 2
        : 0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: child,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            context.go(['/recipes', '/plan', '/mine'][i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: '菜谱',
          ),
          NavigationDestination(
            icon: Icon(Icons.soup_kitchen_outlined),
            label: '做饭',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }
}

class CatalogView extends ConsumerWidget {
  const CatalogView({super.key, required this.builder});
  final Widget Function(BuildContext, WidgetRef, Catalog) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(catalogProvider)
      .when(
        data: (value) => builder(context, ref, value),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$e'),
              TextButton(
                onPressed: () => ref.invalidate(catalogProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
}

void showError(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
