import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

String secureToken([int length = 32]) => base64UrlEncode(
  List<int>.generate(length, (_) => Random.secure().nextInt(256)),
);

bool constantTimeEqual(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < max(a.length, b.length); i++) {
    difference |= (i < a.length ? a[i] : 0) ^ (i < b.length ? b[i] : 0);
  }
  return difference == 0;
}

class SecurityService {
  SecurityService({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );
  final FlutterSecureStorage storage;
  final LocalAuthentication biometrics = LocalAuthentication();
  Future<String> databaseKey() async {
    var key = await storage.read(key: 'database_key_v1');
    if (key == null) {
      key = secureToken();
      await storage.write(key: 'database_key_v1', value: key);
    }
    return key;
  }

  Future<bool> hasPin() async =>
      await storage.read(key: 'pin_verifier_v1') != null ||
      await storage.read(key: 'pin_hash') != null;
  Future<List<int>> _hashPin(String pin, List<int> salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );
    return (await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    )).extractBytes();
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw const FormatException('PIN должен содержать от 6 до 12 цифр');
    }
    final salt = base64Url.decode(secureToken(16));
    await storage.write(
      key: 'pin_verifier_v1',
      value: jsonEncode({
        'hash': base64Encode(await _hashPin(pin, salt)),
        'salt': base64Encode(salt),
      }),
    );
    await storage.delete(key: 'pin_hash');
    await storage.delete(key: 'pin_salt');
    await storage.delete(key: 'pin_attempts');
    await storage.delete(key: 'pin_blocked_until');
  }

  Future<bool> verifyPin(String pin) async {
    final blocked = DateTime.tryParse(
      await storage.read(key: 'pin_blocked_until') ?? '',
    );
    if (blocked != null && DateTime.now().isBefore(blocked)) {
      throw StateError('Слишком много попыток. Попробуйте через минуту.');
    }
    final rawVerifier = await storage.read(key: 'pin_verifier_v1');
    final verifier = rawVerifier == null
        ? null
        : jsonDecode(rawVerifier) as Map<String, dynamic>;
    final expected =
        verifier?['hash'] as String? ?? await storage.read(key: 'pin_hash');
    final salt =
        verifier?['salt'] as String? ?? await storage.read(key: 'pin_salt');
    if (expected == null || salt == null) return false;
    final valid = constantTimeEqual(
      await _hashPin(pin, base64Decode(salt)),
      base64Decode(expected),
    );
    var attempts =
        int.tryParse(await storage.read(key: 'pin_attempts') ?? '') ?? 0;
    attempts = valid ? 0 : attempts + 1;
    if (attempts >= 5) {
      await storage.write(
        key: 'pin_blocked_until',
        value: DateTime.now().add(const Duration(minutes: 1)).toIso8601String(),
      );
      attempts = 0;
    }
    await storage.write(key: 'pin_attempts', value: '$attempts');
    return valid;
  }

  Future<bool> unlockBiometric() async {
    try {
      return await biometrics.authenticate(
        localizedReason: 'Открыть финансовый учёт',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
