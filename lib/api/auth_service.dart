import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'api_exceptions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AUTH SERVICE
// Handles login, token persistence, refresh, and current user state.
// Tokens live in SharedPreferences (OK for MVP; migrate to flutter_secure_storage
// in a hardening pass).
// ─────────────────────────────────────────────────────────────────────────────

class AuthSession {
  final String accessToken;
  final String? refreshToken;
  final String userId;
  final String userEmail;
  final String userName;
  final String? technicianExternalId;
  final List<String> roles;
  final DateTime? expiresAt;

  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    required this.userId,
    required this.userEmail,
    required this.userName,
    this.technicianExternalId,
    this.roles = const [],
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
        'accessToken':          accessToken,
        'refreshToken':         refreshToken,
        'userId':               userId,
        'userEmail':            userEmail,
        'userName':             userName,
        'technicianExternalId': technicianExternalId,
        'roles':                roles,
        'expiresAt':            expiresAt?.toIso8601String(),
      };

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        accessToken:          j['accessToken'] as String,
        refreshToken:         j['refreshToken'] as String?,
        userId:               j['userId'] as String,
        userEmail:            j['userEmail'] as String,
        userName:             j['userName'] as String,
        technicianExternalId: j['technicianExternalId'] as String?,
        roles:                (j['roles'] as List?)?.cast<String>() ?? const [],
        expiresAt: j['expiresAt'] != null
            ? DateTime.parse(j['expiresAt'] as String)
            : null,
      );
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _prefsKey = 'ecoflow.auth_session';

  AuthSession? _session;
  AuthSession? get session => _session;

  bool get isAuthenticated => _session != null && !_session!.isExpired;

  /// Reads a previously persisted session from disk. Call once at boot.
  Future<AuthSession?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      _session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return _session;
    } catch (_) {
      await prefs.remove(_prefsKey);
      return null;
    }
  }

  Future<void> _persist(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(session.toJson()));
  }

  /// POST /auth/login. Stores and returns the new session.
  Future<AuthSession> login(String email, String password) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.login}');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(ApiConfig.connectTimeout);

    if (res.statusCode == 401) {
      throw ApiException(401, 'Credenciais inválidas');
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _extractErrorMessage(res.body));
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final session = AuthSession(
      accessToken:          body['access_token'] as String,
      refreshToken:         body['refresh_token'] as String?,
      userId:               (body['user']?['id'] ?? body['user_id']) as String,
      userEmail:            (body['user']?['email'] ?? email) as String,
      userName:             (body['user']?['name'] ?? email) as String,
      technicianExternalId: body['user']?['technician_external_id'] as String?,
      roles: ((body['user']?['roles'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      expiresAt: body['expires_at'] != null
          ? DateTime.parse(body['expires_at'] as String)
          : null,
    );

    _session = session;
    await _persist(session);
    return session;
  }

  /// POST /auth/refresh — tries to renew the access token.
  /// Returns null if refresh is impossible (user must log in again).
  Future<AuthSession?> refresh() async {
    final current = _session;
    if (current?.refreshToken == null) return null;

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.refresh}');
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': current!.refreshToken}),
          )
          .timeout(ApiConfig.connectTimeout);

      if (res.statusCode != 200) {
        await logout();
        return null;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final next = AuthSession(
        accessToken:          body['access_token'] as String,
        refreshToken:         body['refresh_token'] as String? ?? current.refreshToken,
        userId:               current.userId,
        userEmail:            current.userEmail,
        userName:             current.userName,
        technicianExternalId: current.technicianExternalId,
        roles:                current.roles,
        expiresAt: body['expires_at'] != null
            ? DateTime.parse(body['expires_at'] as String)
            : null,
      );
      _session = next;
      await _persist(next);
      return next;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static String _extractErrorMessage(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return (j['message'] ?? j['error'] ?? 'Erro de autenticação').toString();
    } catch (_) {
      return 'Erro de autenticação';
    }
  }
}
