import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../services/security.dart';

class PermissionGrant {
  const PermissionGrant(this.token, this.expires, this.scopes);
  final String token;
  final DateTime expires;
  final Set<String> scopes;
}

class PermissionService {
  final Map<String, PermissionGrant> _grants = {};
  bool unlocked = false;
  PermissionGrant grant(
    Set<String> scopes, {
    Duration lifetime = const Duration(minutes: 15),
  }) {
    if (!unlocked) throw StateError('Приложение заблокировано');
    if (lifetime > const Duration(hours: 1))
      throw ArgumentError('Слишком долгий доступ');
    final token = secureToken();
    final grant = PermissionGrant(
      token,
      DateTime.now().add(lifetime),
      Set.unmodifiable(scopes),
    );
    _grants[sha256.convert(utf8.encode(token)).toString()] = grant;
    return grant;
  }

  PermissionGrant authorize(String token, String scope) {
    final digest = sha256.convert(utf8.encode(token)).toString();
    final grant = _grants[digest];
    if (!unlocked ||
        grant == null ||
        !DateTime.now().isBefore(grant.expires) ||
        (scope.isNotEmpty && !grant.scopes.contains(scope))) {
      throw StateError(
        'Доступ отсутствует или истёк. Выдайте разрешение в приложении.',
      );
    }
    return grant;
  }

  void revokeAll() => _grants.clear();
}
