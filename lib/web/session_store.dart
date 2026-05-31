import 'dart:convert';
import 'dart:math';

class SessionStore {
  static const cookieName = "bnp_session";

  final String adminPassword;
  final bool secureCookies;
  final Map<String, DateTime> _sessions = {};
  final Random _random = Random.secure();

  SessionStore({
    required this.adminPassword,
    required this.secureCookies,
  });

  bool verifyPassword(String password) => password == adminPassword;

  String create() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll("=", "");
    _sessions[token] = DateTime.now().add(const Duration(days: 7));
    return token;
  }

  void destroy(String? token) {
    if (token != null) {
      _sessions.remove(token);
    }
  }

  bool isValid(String? token) {
    if (token == null || token.isEmpty) {
      return false;
    }
    final expiresAt = _sessions[token];
    if (expiresAt == null) {
      return false;
    }
    if (DateTime.now().isAfter(expiresAt)) {
      _sessions.remove(token);
      return false;
    }
    return true;
  }

  String loginCookie(String token) {
    return _cookie(
      "$cookieName=$token; Path=/; Max-Age=604800; HttpOnly; SameSite=Lax",
    );
  }

  String logoutCookie() {
    return _cookie(
      "$cookieName=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax",
    );
  }

  String? readToken(Map<String, String> headers) {
    final cookie = headers["cookie"];
    if (cookie == null) {
      return null;
    }
    for (final part in cookie.split(";")) {
      final pieces = part.trim().split("=");
      if (pieces.length >= 2 && pieces.first == cookieName) {
        return pieces.sublist(1).join("=");
      }
    }
    return null;
  }

  String _cookie(String value) => secureCookies ? "$value; Secure" : value;
}
