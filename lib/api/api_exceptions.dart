// ─────────────────────────────────────────────────────────────────────────────
// API EXCEPTIONS
// Tipos específicos para que o app distinga entre falhas de rede, auth, e
// erros de servidor — cada um tem tratamento diferente (retry, logout, etc).
// ─────────────────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic body;

  const ApiException(this.statusCode, this.message, [this.body]);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Sem conexão com o servidor']);

  @override
  String toString() => 'NetworkException: $message';
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException([String message = 'Não autorizado'])
      : super(401, message);
}

class ConflictException extends ApiException {
  const ConflictException(String message, [dynamic body])
      : super(409, message, body);
}

class ValidationException extends ApiException {
  final Map<String, List<String>> fieldErrors;
  const ValidationException(
    String message, {
    this.fieldErrors = const {},
    dynamic body,
  }) : super(422, message, body);
}

class UpgradeRequiredException implements Exception {
  final String message;
  const UpgradeRequiredException([
    this.message = 'O servidor exige uma versão mais recente do app.',
  ]);

  @override
  String toString() => 'UpgradeRequiredException: $message';
}
