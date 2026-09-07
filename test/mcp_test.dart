import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:derk_finance/data/finance_repository.dart';
import 'package:derk_finance/integrations/mcp/mcp_server.dart';
import 'package:derk_finance/integrations/mcp/permissions.dart';
import 'package:derk_finance/services/finance_assistant_api.dart';
import 'support.dart';

void main() {
  late SqlFinanceRepository repository;
  late FinanceMcpServer server;
  late PermissionService permissions;
  late HttpClient client;
  late String token;
  setUp(() async {
    repository = await testRepository();
    permissions = PermissionService()..unlocked = true;
    final specs =
        (jsonDecode(await File('assets/mcp_tools.json').readAsString()) as List)
            .cast<Map<String, dynamic>>();
    server = FinanceMcpServer(
      LocalFinanceAssistantAPI(repository, permissions, specs),
      permissions,
    );
    await server.start(port: 0);
    token = permissions.grant({'get_balance', 'add_expense'}).token;
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await (repository.db as Database).close();
  });
  Future<(int, Map<String, dynamic>?)> call(
    String method, {
    Map<String, dynamic> params = const {},
    String? bearer,
    String? origin,
    String verb = 'POST',
  }) async {
    final request = await client.openUrl(
      verb,
      Uri.parse('http://127.0.0.1:${server.port}/mcp'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('Authorization', 'Bearer ${bearer ?? token}');
    if (origin != null) request.headers.set('Origin', origin);
    if (verb == 'POST')
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': method,
          'params': params,
        }),
      );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (
      response.statusCode,
      body.isEmpty ? null : jsonDecode(body) as Map<String, dynamic>,
    );
  }

  test(
    'MCP initialization, scoped tool listing and structured results over HTTP',
    () async {
      final init = await call(
        'initialize',
        params: {
          'protocolVersion': '2025-06-18',
          'capabilities': {},
          'clientInfo': {'name': 'test', 'version': '1'},
        },
      );
      expect(init.$1, 200);
      expect((init.$2!['result'] as Map)['protocolVersion'], '2025-06-18');
      final list = await call('tools/list');
      final tools = (list.$2!['result'] as Map)['tools'] as List;
      expect(tools.map((t) => t['name']).toSet(), {
        'get_balance',
        'add_expense',
      });
      expect(tools.every((t) => t['inputSchema']['type'] == 'object'), true);
      final balance = await call(
        'tools/call',
        params: {'name': 'get_balance', 'arguments': {}},
      );
      expect((balance.$2!['result'] as Map)['isError'], false);
      expect(
        ((balance.$2!['result'] as Map)['structuredContent']
            as Map)['balanceMinor'],
        0,
      );
    },
  );
  test(
    'MCP rejects browser origins, missing scopes, expired grants and SSE GET',
    () async {
      expect((await call('ping', origin: 'https://example.com')).$1, 403);
      expect((await call('ping', bearer: 'invalid')).$1, 401);
      expect((await call('ping', verb: 'GET')).$1, 405);
      final result = await call(
        'tools/call',
        params: {'name': 'add_income', 'arguments': {}},
      );
      expect((result.$2!['result'] as Map)['isError'], true);
      permissions.revokeAll();
      expect((await call('ping')).$1, 401);
      expect((await repository.snapshot()).transactions, isEmpty);
    },
  );
  test(
    'MCP write retry returns one transaction and lock revokes access',
    () async {
      final params = {
        'name': 'add_expense',
        'arguments': {
          'requestId': 'mcp-repeat',
          'accountId': 'card',
          'amountMinor': 45000,
          'category': 'Еда',
        },
      };
      final first = await call('tools/call', params: params);
      final second = await call('tools/call', params: params);
      expect((first.$2!['result'] as Map)['isError'], false);
      expect(first.$2!['result'], second.$2!['result']);
      expect((await repository.snapshot()).transactions.length, 1);
      permissions.unlocked = false;
      expect((await call('tools/list')).$1, 401);
    },
  );
}
