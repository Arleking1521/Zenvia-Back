class ApiConfig {
  /// Production backend по умолчанию.
  ///
  /// Обычная release-сборка:
  /// flutter build apk --release
  ///
  /// При необходимости адрес можно переопределить:
  /// flutter build apk --release \
  ///   --dart-define=API_BASE_URL=https://another.example.com/path/
  static const String _environmentBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.zenvia.kz/',
  );

  /// Dio корректнее работает с backend, размещённым в подпапке (/zenvia/),
  /// когда baseUrl заканчивается на '/', а относительные API-пути не
  /// начинаются с '/'. Поэтому нормализуем URL в одном месте.
  static String get baseUrl => _environmentBaseUrl.endsWith('/')
      ? _environmentBaseUrl
      : '$_environmentBaseUrl/';

  static const String accountPrefix = 'account';
  static const String apiPrefix = '';
  static const String legalPrefix = 'legal';

  static String account(String path) => _join(accountPrefix, path);
  static String api(String path) => _join(apiPrefix, path);
  static String legal(String path) => _join(legalPrefix, path);

  static String _join(String prefix, String path) {
    final cleanPrefix = prefix.endsWith('/')
        ? prefix.substring(0, prefix.length - 1)
        : prefix;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanPrefix/$cleanPath';
  }

  static String absoluteMediaUrl(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final path = value.startsWith('/') ? value : '/$value';
    return '$base$path';
  }
}
