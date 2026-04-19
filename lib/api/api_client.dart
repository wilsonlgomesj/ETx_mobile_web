import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exceptions.dart';
import 'auth_service.dart';
import '../sync/device_info.dart';

// ─────────────────────────────────────────────────────────────────────────────
// API CLIENT
// Thin wrapper over package:http adding:
//   - Automatic Authorization: Bearer <token>
//   - Standard headers (X-Device-Id, X-App-Version, X-Schema-Version)
//   - JSON encoding/decoding
//   - Single-retry on 401 via AuthService.refresh()
//   - Typed errors (ApiException, NetworkException, UpgradeRequiredException)
// ─────────────────────────────────────────────────────────────────────────────

typedef JsonMap = Map<String, dynamic>;

class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  final http.Client _http = http.Client();

  // ── Public API ────────────────────────────────────────────────────────────

  Future<JsonMap> get(String path, {Map<String, String>? query}) async {
    return _requestJson('GET', path, query: query);
  }

  Future<JsonMap> post(String path, {Object? body}) async {
    return _requestJson('POST', path, body: body);
  }

  Future<JsonMap> patch(String path, {Object? body}) async {
    return _requestJson('PATCH', path, body: body);
  }

  Future<JsonMap> delete(String path) async {
    return _requestJson('DELETE', path);
  }

  /// Low-level raw request for non-JSON responses (e.g., file upload PUT).
  Future<http.Response> rawPut(
    String absoluteUrl, {
    required List<int> bytes,
    required String contentType,
  }) async {
    try {
      final res = await _http
          .put(
            Uri.parse(absoluteUrl),
            headers: {'Content-Type': contentType},
            body: bytes,
          )
          .timeout(ApiConfig.receiveTimeout);
      return res;
    } on SocketException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException('Tempo esgotado no upload');
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<JsonMap> _requestJson(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool isRetry = false,
  }) async {
    final uri = _buildUri(path, query);
    final headers = await _buildHeaders();

    http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await _http.get(uri, headers: headers).timeout(ApiConfig.receiveTimeout);
          break;
        case 'POST':
          res = await _http
              .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(ApiConfig.receiveTimeout);
          break;
        case 'PATCH':
          res = await _http
              .patch(uri, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(ApiConfig.receiveTimeout);
          break;
        case 'DELETE':
          res = await _http.delete(uri, headers: headers).timeout(ApiConfig.receiveTimeout);
          break;
        default:
          throw ArgumentError('Método não suportado: $method');
      }
    } on SocketException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException('Tempo esgotado aguardando o servidor');
    }

    // 401: tenta refresh uma única vez, depois propaga.
    if (res.statusCode == 401 && !isRetry) {
      final refreshed = await AuthService.instance.refresh();
      if (refreshed != null) {
        return _requestJson(method, path, query: query, body: body, isRetry: true);
      }
      throw const UnauthorizedException();
    }

    // 426: app precisa atualizar schema — bloqueia sync até atualizar.
    if (res.statusCode == 426) {
      throw UpgradeRequiredException(_extractMsg(res));
    }

    // 409: conflito de dados (duplicidade, etc).
    if (res.statusCode == 409) {
      throw ConflictException(_extractMsg(res), _safeJson(res.body));
    }

    // 422: validação.
    if (res.statusCode == 422) {
      final parsed = _safeJson(res.body);
      final fieldErrors = <String, List<String>>{};
      if (parsed is Map && parsed['errors'] is Map) {
        (parsed['errors'] as Map).forEach((k, v) {
          fieldErrors[k.toString()] =
              (v is List) ? v.map((e) => e.toString()).toList() : [v.toString()];
        });
      }
      throw ValidationException(_extractMsg(res),
          fieldErrors: fieldErrors, body: parsed);
    }

    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _extractMsg(res), _safeJson(res.body));
    }

    if (res.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{'data': decoded};
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final full = path.startsWith('http')
        ? path
        : '${ApiConfig.baseUrl}$path';
    final uri = Uri.parse(full);
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Device-Id': await DeviceInfo.instance.deviceId(),
      'X-App-Version': DeviceInfo.appVersion,
      'X-Schema-Version': ApiConfig.schemaVersion.toString(),
    };
    final token = AuthService.instance.session?.accessToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static String _extractMsg(http.Response res) {
    final parsed = _safeJson(res.body);
    if (parsed is Map) {
      return (parsed['message'] ?? parsed['error'] ?? res.reasonPhrase ?? 'Erro')
          .toString();
    }
    return res.reasonPhrase ?? 'Erro';
  }

  static dynamic _safeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  void dispose() => _http.close();
}
