import 'dart:convert';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../domain/models.dart';
import 'bank_provider.dart';

/// Normalized bank gateway contract, not a claim that any bank exposes these URLs.
/// A bank-specific adapter/backend handles FAPI, mTLS, signatures and pagination.
class OAuthBankConfig {
  const OAuthBankConfig({
    required this.id,
    required this.name,
    required this.clientId,
    required this.discoveryUrl,
    required this.gateway,
    required this.scopes,
    this.redirectUrl = 'app.derk.finance:/oauthredirect',
  });
  final String id, name, clientId, discoveryUrl, redirectUrl;
  final Uri gateway;
  final List<String> scopes;
}

class OAuthBankProvider implements BankProvider {
  OAuthBankProvider(this.config, this.storage, {http.Client? client})
    : client = client ?? http.Client() {
    if (config.gateway.scheme != 'https' ||
        Uri.parse(config.discoveryUrl).scheme != 'https' ||
        config.gateway.host.isEmpty ||
        config.gateway.userInfo.isNotEmpty ||
        config.gateway.hasQuery ||
        config.gateway.hasFragment ||
        !config.gateway.path.endsWith('/')) {
      throw ArgumentError(
        'Нужны HTTPS-адреса; адрес API должен оканчиваться / и не содержать логин, query или fragment',
      );
    }
  }
  final OAuthBankConfig config;
  final FlutterSecureStorage storage;
  final http.Client client;
  final FlutterAppAuth appAuth = const FlutterAppAuth();
  @override
  String get id => config.id;
  @override
  String get name => config.name;
  String get _key => 'bank_oauth_$id';
  @override
  Future<void> authorize() async {
    final response = await appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        config.redirectUrl,
        discoveryUrl: config.discoveryUrl,
        scopes: config.scopes,
      ),
    );
    if (response.accessToken == null) throw StateError('Банк не выдал доступ');
    await storage.write(
      key: _key,
      value: jsonEncode({
        'access': response.accessToken,
        'refresh': response.refreshToken,
        'expires': response.accessTokenExpirationDateTime
            ?.toUtc()
            .toIso8601String(),
      }),
    );
  }

  Future<String> _accessToken() async {
    final raw = await storage.read(key: _key);
    if (raw == null) throw StateError('Подключите банк');
    final tokens = jsonDecode(raw) as Map<String, dynamic>;
    final expiry = DateTime.tryParse(tokens['expires'] as String? ?? '');
    if (expiry == null ||
        expiry.isBefore(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        )) {
      final refresh = tokens['refresh'] as String?;
      if (refresh == null)
        throw StateError('Повторно подтвердите доступ к банку');
      final response = await appAuth.token(
        TokenRequest(
          config.clientId,
          config.redirectUrl,
          discoveryUrl: config.discoveryUrl,
          refreshToken: refresh,
          scopes: config.scopes,
        ),
      );
      if (response.accessToken == null)
        throw StateError('Не удалось обновить доступ');
      tokens['access'] = response.accessToken;
      tokens['refresh'] = response.refreshToken ?? refresh;
      tokens['expires'] = response.accessTokenExpirationDateTime
          ?.toUtc()
          .toIso8601String();
      await storage.write(key: _key, value: jsonEncode(tokens));
    }
    return tokens['access'] as String;
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = config.gateway.resolve(path).replace(queryParameters: query);
    if (uri.origin != config.gateway.origin)
      throw StateError('Недопустимый банковский адрес');
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['Authorization'] = 'Bearer ${await _accessToken()}';
    request.headers['Accept'] = 'application/json';
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200)
      throw StateError('Банк вернул код ${response.statusCode}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<List<BankAccount>> getAccounts() async {
    final data = await _get('accounts');
    return (data['accounts'] as List).map((raw) {
      final a = Map<String, dynamic>.from(raw as Map);
      return BankAccount(
        id: a['id'] as String,
        name: a['name'] as String,
        currency: a['currency'] as String,
        balanceMinor: a['balanceMinor'] as int,
        asOf: DateTime.parse(a['asOf'] as String).toLocal(),
      );
    }).toList();
  }

  @override
  Future<BankPage> getTransactions({String? cursor}) async {
    final data = await _get(
      'transactions',
      cursor == null ? null : {'cursor': cursor},
    );
    return BankPage(
      (data['transactions'] as List).map((raw) {
        final t = Map<String, dynamic>.from(raw as Map);
        return BankOperation(
          id: t['id'] as String,
          accountId: t['accountId'] as String,
          signedMinor: t['signedMinor'] as int,
          date: DateTime.parse(t['date'] as String).toLocal(),
          currency: t['currency'] as String,
          description: t['description'] as String? ?? '',
          merchant: t['merchant'] as String? ?? '',
          mcc: t['mcc'] as String?,
          ownAccountId: t['ownAccountId'] as String?,
          kind: t['kind'] == null
              ? null
              : TransactionKind.values.byName(t['kind'] as String),
        );
      }).toList(),
      nextCursor: data['nextCursor'] as String?,
    );
  }

  @override
  Future<void> disconnect() async {
    // Server must revoke the bank consent; local token deletion only follows success.
    final request = http.Request('DELETE', config.gateway.resolve('consent'))
      ..followRedirects = false;
    request.headers['Authorization'] = 'Bearer ${await _accessToken()}';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 204)
      throw StateError('Банк не подтвердил отзыв доступа');
    await storage.delete(key: _key);
  }
}
