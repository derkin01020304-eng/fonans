import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:derk_finance/presentation/app_lock.dart';
import 'package:derk_finance/presentation/providers.dart';
import 'package:derk_finance/services/android_services.dart';
import 'package:derk_finance/services/security.dart';
import 'support.dart';

class PendingSecurity extends SecurityService {
  Completer<bool> pending = Completer<bool>();
  @override
  Future<bool> hasPin() async => true;
  @override
  Future<bool> verifyPin(String pin) => pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('PIN is salted, verified and changed without storing the PIN', () async {
    final security = SecurityService();
    await security.setPin('812345');
    expect(await security.hasPin(), true);
    final first = await security.storage.read(key: 'pin_verifier_v1');
    expect(first!.contains('812345'), false);
    expect(await security.verifyPin('812345'), true);
    expect(await security.verifyPin('912345'), false);
    await security.setPin('998877');
    expect(await security.verifyPin('812345'), false);
    expect(await security.verifyPin('998877'), true);
    expect(await security.storage.read(key: 'pin_verifier_v1'), isNot(first));
    await expectLater(security.setPin('1234'), throwsFormatException);
  });
  test(
    'Five incorrect PIN attempts block further attempts persistently',
    () async {
      final security = SecurityService();
      await security.setPin('812345');
      for (var i = 0; i < 5; i++) {
        expect(await security.verifyPin('000000'), false);
      }
      await expectLater(
        SecurityService().verifyPin('812345'),
        throwsStateError,
      );
      expect(await security.storage.read(key: 'pin_blocked_until'), isNotNull);
    },
  );
  testWidgets(
    'Backgrounding during PIN verification cannot unlock financial UI',
    (tester) async {
      final repository = await tester.runAsync(testRepository);
      final security = PendingSecurity();
      final container = ProviderContainer(
        overrides: [
          runtimeProvider.overrideWithValue(
            AppRuntime(repository!, security, []),
          ),
        ],
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidServices.channel, (_) async => true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AppLock(child: Text('PRIVATE FINANCES')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE FINANCES'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '812345');
      await tester.tap(find.text('Открыть'));
      await tester.pump();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      security.pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE FINANCES'), findsNothing);
      expect(container.read(permissionsProvider).unlocked, false);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      security.pending = Completer<bool>();
      await tester.enterText(find.byType(TextField).first, '812345');
      await tester.tap(find.text('Открыть'));
      security.pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE FINANCES'), findsOneWidget);
      final permissions = container.read(permissionsProvider);
      final token = permissions.grant({'get_balance'}).token;
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      expect(find.text('PRIVATE FINANCES'), findsNothing);
      expect(
        () => permissions.authorize(token, 'get_balance'),
        throwsStateError,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.runAsync(() => (repository.db as Database).close());
    },
  );
}
