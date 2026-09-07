import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'widgets.dart';

class AppLock extends ConsumerStatefulWidget {
  const AppLock({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AppLock> createState() => _AppLockState();
}

class _AppLockState extends ConsumerState<AppLock> with WidgetsBindingObserver {
  final pin = TextEditingController(), repeat = TextEditingController();
  bool locked = true,
      ready = false,
      hasPin = false,
      busy = false,
      biometric = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final runtime = ref.read(runtimeProvider);
    final exists = await runtime.security.hasPin();
    final theme = await runtime.security.storage.read(key: 'theme');
    final currency = await runtime.security.storage.read(key: 'currency');
    final reminders = await runtime.security.storage.read(key: 'reminders');
    if (!mounted) return;
    ref.read(themeProvider.notifier).state =
        ThemeMode.values.where((t) => t.name == theme).firstOrNull ??
        ThemeMode.system;
    if (['RUB', 'USD', 'EUR'].contains(currency))
      ref.read(currencyProvider.notifier).state = currency!;
    ref.read(remindersProvider.notifier).state = reminders == 'true';
    setState(() {
      hasPin = exists;
      ready = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    pin.dispose();
    repeat.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!biometric) _lock();
    }
  }

  void _activity() {
    timer?.cancel();
    if (!locked) timer = Timer(const Duration(minutes: 2), _lock);
  }

  void _lock() {
    timer?.cancel();
    final permissions = ref.read(permissionsProvider);
    permissions.unlocked = false;
    permissions.revokeAll();
    ref.read(runtimeProvider).android.setUnlocked(false).catchError((_) {});
    if (mounted)
      setState(() {
        locked = true;
        error = null;
        pin.clear();
        repeat.clear();
      });
  }

  void _unlock() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _lock();
      return;
    }
    ref.read(permissionsProvider).unlocked = true;
    ref.read(runtimeProvider).android.setUnlocked(true).catchError((_) {});
    setState(() {
      locked = false;
      error = null;
      pin.clear();
      repeat.clear();
      hasPin = true;
    });
    _activity();
  }

  Future<void> _submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final security = ref.read(runtimeProvider).security;
      if (!hasPin) {
        if (pin.text != repeat.text) throw ArgumentError('PIN не совпадают');
        await security.setPin(pin.text);
      } else if (!await security.verifyPin(pin.text)) {
        throw StateError('Неверный PIN');
      }
      if (mounted) _unlock();
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _activity(),
    onPointerMove: (_) => _activity(),
    child: Stack(
      children: [
        Offstage(
          offstage: locked,
          child: ExcludeSemantics(excluding: locked, child: widget.child),
        ),
        if (locked)
          Positioned.fill(
            child: Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: mint,
                            size: 56,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Дэрк Финансы',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            hasPin
                                ? 'Введите PIN приложения'
                                : 'Создайте PIN приложения: 6–12 цифр',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 32),
                          if (!ready)
                            const Center(child: CircularProgressIndicator())
                          else ...[
                            TextField(
                              controller: pin,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              maxLength: 12,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'PIN приложения',
                              ),
                              onSubmitted: (_) => _submit(),
                            ),
                            if (!hasPin) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: repeat,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                keyboardType: TextInputType.number,
                                maxLength: 12,
                                decoration: const InputDecoration(
                                  labelText: 'Повторите PIN',
                                ),
                              ),
                            ],
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            FilledButton(
                              onPressed: busy ? null : _submit,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  busy
                                      ? 'Проверка…'
                                      : hasPin
                                      ? 'Открыть'
                                      : 'Создать PIN',
                                ),
                              ),
                            ),
                            if (hasPin)
                              TextButton.icon(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        biometric = true;
                                        final success = await ref
                                            .read(runtimeProvider)
                                            .security
                                            .unlockBiometric();
                                        biometric = false;
                                        if (mounted && success) _unlock();
                                      },
                                icon: const Icon(Icons.fingerprint),
                                label: const Text('Биометрия'),
                              ),
                            if (!hasPin)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: Text(
                                  'Это отдельный PIN приложения. Не используйте PIN банковской карты. Восстановить забытый PIN можно только через переустановку и вашу резервную копию.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
