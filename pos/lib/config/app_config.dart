class AppConfig {
  const AppConfig._({
    required this.apiBaseUrl,
    required this.syncApiKey,
    required this.pharmacyId,
    required this.deviceId,
    required this.appVersion,
    required this.branchName,
    required this.licenseNumber,
    required this.region,
    required this.requestTimeout,
    required this.healthTimeout,
    required this.syncInterval,
    required this.retryBaseDelay,
  });

  factory AppConfig.fromEnvironment() {
    return AppConfig._(
      apiBaseUrl: const String.fromEnvironment(
        'MEDTRACK_API_BASE_URL',
        defaultValue: 'http://localhost:3000/api',
      ),
      syncApiKey: const String.fromEnvironment(
        'MEDTRACK_SYNC_API_KEY',
        defaultValue: 'local-dev-sync-key',
      ),
      pharmacyId: const int.fromEnvironment(
        'MEDTRACK_PHARMACY_ID',
        defaultValue: 25,
      ),
      deviceId: const String.fromEnvironment(
        'MEDTRACK_POS_HWID',
        defaultValue: 'HW-00423',
      ),
      appVersion: const String.fromEnvironment(
        'MEDTRACK_POS_APP_VERSION',
        defaultValue: '',
      ),
      branchName: const String.fromEnvironment(
        'MEDTRACK_POS_BRANCH_NAME',
        defaultValue: 'Al-Amin Pharmacy',
      ),
      licenseNumber: const String.fromEnvironment(
        'MEDTRACK_POS_LICENSE_NUMBER',
        defaultValue: 'LIC-BEY-0041',
      ),
      region: const String.fromEnvironment(
        'MEDTRACK_POS_REGION',
        defaultValue: 'Beirut',
      ),
      requestTimeout: Duration(
        seconds: const int.fromEnvironment(
          'MEDTRACK_REQUEST_TIMEOUT_SECONDS',
          defaultValue: 60,
        ),
      ),
      healthTimeout: Duration(
        seconds: const int.fromEnvironment(
          'MEDTRACK_HEALTH_TIMEOUT_SECONDS',
          defaultValue: 15,
        ),
      ),
      syncInterval: Duration(
        seconds: const int.fromEnvironment(
          'MEDTRACK_SYNC_INTERVAL_SECONDS',
          defaultValue: 30,
        ),
      ),
      retryBaseDelay: Duration(
        seconds: const int.fromEnvironment(
          'MEDTRACK_SYNC_RETRY_BASE_SECONDS',
          defaultValue: 1,
        ),
      ),
    );
  }

  static final AppConfig current = AppConfig.fromEnvironment();

  final String apiBaseUrl;
  final String syncApiKey;
  final int pharmacyId;
  final String deviceId;
  final String appVersion;
  final String branchName;
  final String licenseNumber;
  final String region;
  final Duration requestTimeout;
  final Duration healthTimeout;
  final Duration syncInterval;
  final Duration retryBaseDelay;

  Uri get centralHealthUri => serverBaseUri.resolve('/health');

  Uri get proxyHealthUri => serverBaseUri.resolve('/api/health');

  Uri get apiBaseUri => Uri.parse(apiBaseUrl);

  Uri get serverBaseUri {
    final apiUri = apiBaseUri;
    final path = apiUri.path.endsWith('/api')
        ? apiUri.path.substring(0, apiUri.path.length - 4)
        : apiUri.path;
    return apiUri.replace(path: path.isEmpty ? '/' : path);
  }

  Uri get healthUri => serverBaseUri.resolve('/health');

  Uri apiUriFor(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return apiBaseUri.resolve(cleanPath);
  }

  Uri syncUriFor(String path) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$apiBaseUrl/$cleanPath');
  }

  Uri serverUriFor(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return serverBaseUri.resolve(cleanPath);
  }
}
