import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:derk_finance/data/finance_repository.dart';
import 'package:derk_finance/domain/models.dart';
import 'package:derk_finance/presentation/app.dart';
import 'package:derk_finance/presentation/providers.dart';
import 'package:derk_finance/services/android_services.dart';
import 'package:derk_finance/services/security.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqlFinanceRepository repo;
  late ProviderContainer container;
  final captureKey = GlobalKey();
  setUpAll(() async {
    await initializeDateFormatting('ru');
    final fontDirectory = Platform.environment['PREVIEW_FONTS'] ?? 'test/fonts';
    {
      for (final entry in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        final bytes = await File('$fontDirectory/${entry.value}').readAsBytes();
        await (FontLoader(
          entry.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidServices.channel, (_) async => true);
    repo = await testRepository();
    await repo.seedDemo();
    final specs =
        (jsonDecode(await File('assets/mcp_tools.json').readAsString()) as List)
            .cast<Map<String, dynamic>>();
    container = ProviderContainer(
      overrides: [
        runtimeProvider.overrideWithValue(
          AppRuntime(repo, SecurityService(), specs),
        ),
      ],
    );
    await container.read(snapshotProvider.future);
  });
  tearDown(() async {
    container.read(routerProvider).dispose();
    container.dispose();
    await (repo.db as Database).close();
  });
  Future<void> settle(WidgetTester tester) async {
    // The FFI database runs on a real isolate, outside Flutter's fake clock.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> boot(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: captureKey,
          child: const FinanceApp(lockEnabled: false),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['PREVIEW_DIR'];
    if (directory == null) return;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: captureKey,
          child: KeyedSubtree(
            key: ValueKey(name),
            child: const FinanceApp(lockEnabled: false),
          ),
        ),
      ),
    );
    await settle(tester);
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    boundary.markNeedsPaint();
    await tester.pump();
    try {
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    } finally {
      debugDisableShadows = previousShadows;
    }
  }

  testWidgets(
    'All five destinations and auxiliary pages render on a narrow phone',
    (tester) async {
      await boot(tester, 320);
      expect(find.text('Общий баланс'), findsOneWidget);
      final nav = find.byType(NavigationBar);
      for (final label in [
        'Операции',
        'Цели',
        'Обязательства',
        'Статистика',
        'Главная',
      ]) {
        await tester.tap(find.descendant(of: nav, matching: find.text(label)));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: label);
      }
      for (final path in [
        '/accounts',
        '/integrations',
        '/exports',
        '/assistant',
        '/settings',
      ]) {
        container.read(routerProvider).go(path);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: path);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Quick expense form persists an exact amount in SQLite', (
    tester,
  ) async {
    await boot(tester, 390);
    final before = (await tester.runAsync(repo.snapshot))!.transactions.length;
    await tester.tap(find.byTooltip('Добавить'));
    await settle(tester);
    expect(find.text('Быстрое добавление'), findsOneWidget);
    await tester.tap(find.text('Расход').last);
    await settle(tester);
    expect(find.byType(TextFormField), findsWidgets);
    final amount = find.byType(TextFormField).first;
    await tester.enterText(amount, '450,50');
    await tester.scrollUntilVisible(
      find.text('Сохранить'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Сохранить'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final snapshot = (await tester.runAsync(repo.snapshot))!;
    expect(snapshot.transactions.length, before + 1);
    expect(snapshot.transactions.first.amountMinor, 45050);
    expect(snapshot.transactions.first.kind, TransactionKind.expense);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Dashboard, goals and dark theme render with demo data', (
    tester,
  ) async {
    await boot(tester, 390);
    await capture(tester, 'dashboard_light');
    container.read(routerProvider).go('/goals');
    await settle(tester);
    await capture(tester, 'goals_light');
    container.read(routerProvider).go('/statistics');
    await settle(tester);
    await capture(tester, 'statistics_light');
    container.read(themeProvider.notifier).state = ThemeMode.dark;
    container.read(routerProvider).go('/');
    await settle(tester);
    await capture(tester, 'dashboard_dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
