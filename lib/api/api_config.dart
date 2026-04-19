// ─────────────────────────────────────────────────────────────────────────────
// API CONFIG
// Central configuration for backend integration.
// Base URL, timeouts, schema version, and environment-aware endpoints.
// ─────────────────────────────────────────────────────────────────────────────

class ApiConfig {
  ApiConfig._();

  /// Base URL do backend NestJS.
  /// Troque conforme ambiente (dev/staging/prod) via --dart-define em build.
  ///
  /// Exemplos:
  ///   flutter run --dart-define=API_BASE_URL=https://api.envirotrack.com
  ///   flutter run (usa fallback abaixo, útil em emulador Android:
  ///               10.0.2.2 aponta para localhost do host)
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  /// Prefixo versionado da API.
  static const String apiPrefix = '/api/v1';

  /// Schema version enviado no header X-Schema-Version.
  /// Incrementar quando o payload de sync do app mudar de forma não-retrocompatível.
  static const int schemaVersion = 1;

  /// Timeouts padrão.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 60);

  /// Limites de batch — o backend tem limite de 5MB ou 100 itens.
  /// Mantemos folga conservadora.
  static const int maxBatchItems = 80;
  static const int maxBatchBytes = 4 * 1024 * 1024; // 4MB

  /// Intervalos de sync automático.
  static const Duration autoSyncInterval = Duration(minutes: 2);
  static const Duration retryBackoffBase = Duration(seconds: 5);
  static const int maxRetryAttempts = 5;

  // ── Endpoints ──────────────────────────────────────────────────────────────

  static String get login            => '$apiPrefix/auth/login';
  static String get refresh          => '$apiPrefix/auth/refresh';
  static String get me               => '$apiPrefix/auth/me';

  static String get syncBatch        => '$apiPrefix/mobile/sync/batch';
  static String get syncPull         => '$apiPrefix/mobile/sync/pull';

  static String get evidenceUploadUrl=> '$apiPrefix/mobile/evidences/upload-url';
  static String evidenceConfirm(String externalId) =>
      '$apiPrefix/mobile/evidences/$externalId/confirm';
}
