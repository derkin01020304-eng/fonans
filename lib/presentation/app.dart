import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/models.dart';
import '../services/categorizer.dart';
import 'accounts_page.dart';
import 'app_lock.dart';
import 'assistant_page.dart';
import 'dashboard.dart';
import 'editor.dart';
import 'exports_page.dart';
import 'forms.dart';
import 'goals_page.dart';
import 'integrations_page.dart';
import 'obligations_page.dart';
import 'providers.dart';
import 'settings_page.dart';
import 'statistics_page.dart';
import 'transactions_page.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            FinanceShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsPage(),
          ),
          GoRoute(
            path: '/goals',
            builder: (context, state) => const GoalsPage(),
          ),
          GoRoute(
            path: '/obligations',
            builder: (context, state) => const ObligationsPage(),
          ),
          GoRoute(
            path: '/statistics',
            builder: (context, state) => const StatisticsPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsPage(),
          ),
          GoRoute(
            path: '/integrations',
            builder: (context, state) => const IntegrationsPage(),
          ),
          GoRoute(
            path: '/exports',
            builder: (context, state) => const ExportsPage(),
          ),
          GoRoute(
            path: '/assistant',
            builder: (context, state) => const AssistantPage(),
          ),
        ],
      ),
    ],
  ),
);

class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key, this.lockEnabled = true});
  final bool lockEnabled;
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF237B60),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF101A17)
          : const Color(0xFFF4F6F2),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xFF101A17)
            : const Color(0xFFF4F6F2),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1B2822) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        ),
        indicatorColor: dark
            ? const Color(0xFF294F41)
            : const Color(0xFFD2EBDD),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Дэрк Финансы',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: ref.watch(themeProvider),
    locale: const Locale('ru'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('ru'), Locale('en')],
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => lockEnabled ? AppLock(child: child!) : child!,
  );
}

class FinanceShell extends ConsumerWidget {
  const FinanceShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  static const paths = [
    '/',
    '/transactions',
    '/goals',
    '/obligations',
    '/statistics',
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = paths.indexOf(path);
    final demo = ref.watch(snapshotProvider).valueOrNull?.demo ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Дэрк',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: selected < 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Помощник',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/assistant'),
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (demo)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.tertiaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: const Text(
                  'ДЕМО · Вымышленные данные',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.large(
        tooltip: 'Добавить',
        onPressed: () async {
          final s = await ref.read(snapshotProvider.future);
          if (context.mounted) _quickMenu(context, ref, s);
        },
        child: const Icon(Icons.add, size: 32),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (i) => context.go(paths[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Главная',
          ),
          NavigationDestination(icon: Icon(Icons.swap_vert), label: 'Операции'),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Цели',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            label: 'Обязательства',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Статистика',
          ),
        ],
      ),
    );
  }

  Future<void> _quickMenu(
    BuildContext context,
    WidgetRef ref,
    FinanceSnapshot s,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Быстрое добавление',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            for (final e in const {
              'income': 'Доход',
              'expense': 'Расход',
              'transfer': 'Перевод',
              'debt': 'Долг',
              'savings': 'Накопление',
              'quick': 'Ввести фразой',
            }.entries)
              ListTile(
                title: Text(e.value),
                leading: Icon(
                  e.key == 'income'
                      ? Icons.south_west
                      : e.key == 'expense'
                      ? Icons.north_east
                      : Icons.add,
                ),
                onTap: () => Navigator.pop(context, e.key),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'income':
        await transactionForm(context, ref, s, kind: TransactionKind.income);
      case 'expense':
        await transactionForm(context, ref, s);
      case 'transfer':
        await transactionForm(context, ref, s, kind: TransactionKind.transfer);
      case 'debt':
        await debtForm(context, ref, s);
      case 'savings':
        await savingsForm(context, ref, s);
      case 'quick':
        QuickEntry? entry;
        await showEditor(
          context,
          title: 'Операция одной фразой',
          fields: const [
            FieldSpec(
              'phrase',
              'Сумма и категория',
              hint: '250 еда / +3000 работа / 500 транспорт',
            ),
          ],
          onSave: (v) async {
            entry = QuickEntry.parse(v['phrase'] as String);
          },
        );
        if (context.mounted && entry != null)
          await transactionForm(context, ref, s, quick: entry);
    }
  }
}
