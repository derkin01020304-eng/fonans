import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../services/finance_assistant_api.dart';
import 'permissions.dart';

/// Local-only Streamable HTTP (JSON response mode), protocol 2025-06-18.
class FinanceMcpServer {
  FinanceMcpServer(this.api, this.permissions);
  final FinanceAssistantAPI api;
  final PermissionService permissions;
  HttpServer? _server;
  bool get running => _server != null;
  int? get port => _server?.port;
  Future<void> start({int port = 8765}) async {
    if (_server != null) return;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
  }

  Future<void> stop() async {
    permissions.revokeAll();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    Object? rpcId;
    Future<void> send(int status, Object? body) async {
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.headers.set('Cache-Control', 'no-store');
      if (body != null) response.write(jsonEncode(body));
      await response.close();
    }

    try {
      if (request.uri.path != '/mcp') {
        await send(404, {'error': 'Not found'});
        return;
      }
      final host = request.headers.value('host')?.split(':').first;
      if (!['127.0.0.1', 'localhost'].contains(host) ||
          request.headers.value('origin') != null) {
        await send(403, {'error': 'Forbidden origin'});
        return;
      }
      final authorization = request.headers.value('authorization') ?? '';
      if (!authorization.startsWith('Bearer ')) {
        await send(401, {'error': 'Token required'});
        return;
      }
      final token = authorization.substring(7);
      try {
        permissions.authorize(token, '');
      } catch (_) {
        await send(401, {'error': 'Token expired or revoked'});
        return;
      }
      if (request.method != 'POST') {
        await send(405, null);
        return;
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        await send(415, {'error': 'application/json required'});
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) {
          await send(413, {'error': 'Payload too large'});
          return;
        }
      }
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map<String, dynamic> ||
          raw['jsonrpc'] != '2.0' ||
          raw['method'] is! String) {
        await send(400, {
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32600, 'message': 'Invalid request'},
        });
        return;
      }
      rpcId = raw['id'];
      final method = raw['method'] as String;
      final params = Map<String, dynamic>.from(raw['params'] as Map? ?? {});
      if (!raw.containsKey('id')) {
        await send(202, null);
        return;
      }
      Object result;
      switch (method) {
        case 'initialize':
          result = {
            'protocolVersion': '2025-06-18',
            'capabilities': {
              'tools': {'listChanged': false},
            },
            'serverInfo': {'name': 'derk-finance', 'version': '0.1.0'},
            'instructions':
                'Amounts are integer minor units. Writes require requestId and a user-granted scope.',
          };
        case 'ping':
          result = <String, dynamic>{};
        case 'tools/list':
          final grant = permissions.authorize(token, '');
          result = {
            'tools': api.tools
                .where((t) => grant.scopes.contains(t['name']))
                .toList(),
          };
        case 'tools/call':
          try {
            final value = await api.call(
              params['name'] as String,
              Map<String, dynamic>.from(params['arguments'] as Map? ?? {}),
              token: token,
            );
            result = {
              'content': [
                {'type': 'text', 'text': jsonEncode(value)},
              ],
              'structuredContent': value is Map ? value : {'result': value},
              'isError': false,
            };
          } catch (e) {
            final message = e is ArgumentError
                ? e.message.toString()
                : e is FormatException
                ? e.message
                : e is StateError
                ? e.message
                : 'Не удалось выполнить команду';
            result = {
              'content': [
                {'type': 'text', 'text': message},
              ],
              'isError': true,
            };
          }
        default:
          await send(200, {
            'jsonrpc': '2.0',
            'id': rpcId,
            'error': {'code': -32601, 'message': 'Method not found'},
          });
          return;
      }
      await send(200, {'jsonrpc': '2.0', 'id': rpcId, 'result': result});
    } catch (_) {
      try {
        await send(400, {
          'jsonrpc': '2.0',
          'id': rpcId,
          'error': {'code': -32700, 'message': 'Invalid JSON-RPC request'},
        });
      } catch (_) {
        /* Client disconnected. */
      }
    }
  }
}
