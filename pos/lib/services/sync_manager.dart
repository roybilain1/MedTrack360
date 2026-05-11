import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'inventory_database.dart';

typedef SyncLogFn = void Function(String message);

class SyncBackoffPolicy {
  const SyncBackoffPolicy({
    this.maxExponent = 6,
    this.baseMs = 1000,
    this.maxJitterMs = 500,
  });

  final int maxExponent;
  final int baseMs;
  final int maxJitterMs;

  Duration nextDelay(int failureCount, {int jitterMs = 0}) {
    final exp = min(failureCount, maxExponent);
    final boundedJitter = max(0, min(jitterMs, maxJitterMs));
    final backoffMs = baseMs * (1 << exp);
    return Duration(milliseconds: backoffMs + boundedJitter);
  }
}

enum SyncState {
  idle,
  checkingHealth,
  syncing,
  online,
  offline,
  unauthorized,
  error,
}

class SyncManager extends ChangeNotifier {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  final AppConfig config = AppConfig.current;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<dynamic>? _connectivitySub;
  Timer? _periodicSyncTimer;
  Timer? _retryTimer;
  bool _started = false;
  bool _syncInProgress = false;
  bool _syncQueued = false;
  int _failureCount = 0;
  DateTime? _lastHealthCheckAt;
  DateTime? _lastSyncAt;
  String? _lastError;
  String _statusMessage = 'Idle';
  SyncState _state = SyncState.idle;

  SyncLogFn logger = print;
  SyncConflictHandler? onConflict;
  SyncBackoffPolicy backoffPolicy = const SyncBackoffPolicy();

  SyncState get state => _state;
  String get statusMessage => _statusMessage;
  String get statusDetail {
    final parts = <String>[
      'backend=${config.apiBaseUrl}',
      if (_lastHealthCheckAt != null)
        'health=${_lastHealthCheckAt!.toIso8601String()}',
      if (_lastSyncAt != null) 'synced=${_lastSyncAt!.toIso8601String()}',
      if (_lastError != null && _lastError!.isNotEmpty) 'error=$_lastError',
    ];
    return parts.join(' · ');
  }

  bool get isBusy => _syncInProgress;

  void _setStatus(SyncState state, String message, {String? error}) {
    _state = state;
    _statusMessage = message;
    _lastError = error;
    notifyListeners();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await InventoryDatabase.instance.recoverInProgressOutbox();
    await _runHealthCheck(reason: 'startup');

    _connectivitySub = _connectivity.onConnectivityChanged.listen((event) {
      final online = _eventHasConnectivity(event);
      if (online) {
        _log('Connectivity online. Triggering sync.');
        unawaited(triggerSync());
      } else {
        _log('Connectivity offline. POS stays fully offline-capable.');
      }
    });

    _log('SyncManager started.');
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(config.syncInterval, (_) {
      unawaited(triggerSync());
    });
    await triggerSync();
  }

  Future<void> stop() async {
    _started = false;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _log('SyncManager stopped.');
  }

  Future<void> triggerSync() async {
    if (!_started) return;
    if (_syncInProgress) {
      _syncQueued = true;
      _setStatus(SyncState.syncing, 'Sync queued behind active run');
      return;
    }

    if (!await _runHealthCheck(reason: 'pre-sync')) {
      if (_state != SyncState.unauthorized) {
        _scheduleRetry();
      }
      return;
    }

    _syncInProgress = true;
    try {
      do {
        _syncQueued = false;
        _setStatus(SyncState.syncing, 'Sync in progress');
        await _runSyncCycle();
        _lastSyncAt = DateTime.now();
        _setStatus(SyncState.online, 'Sync complete');
      } while (_syncQueued && _started);
      _failureCount = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (e) {
      _failureCount += 1;
      final message = e.toString();
      _log('Sync cycle failed: $message');
      final isUnauthorized = message.toLowerCase().contains('unauthorized');
      _setStatus(
        isUnauthorized ? SyncState.unauthorized : SyncState.error,
        isUnauthorized ? 'Unauthorized sync key' : 'Sync failed',
        error: message,
      );
      if (!isUnauthorized) {
        _scheduleRetry();
      }
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _runSyncCycle() async {
    var totalPushed = 0;
    Object? pushError;
    try {
      for (var i = 0; i < 20; i += 1) {
        final pushed = await InventoryDatabase.instance.syncUpChunk(
          chunkSize: 100,
        );
        totalPushed += pushed;
        if (pushed == 0) break;
      }
    } catch (e) {
      // Don't let push failures block the pull. Stuck local queue items
      // would otherwise prevent the device from ever receiving server
      // updates (e.g. the authoritative medicines catalog).
      pushError = e;
      _log('Sync push failed (continuing with pull): $e');
    }

    await InventoryDatabase.instance.syncDown(
      limit: 500,
      onConflict: (conflict) async {
        _log(
          'Conflict resolved by server authority: '
          '${conflict.entity}/${conflict.entityId} '
          '${conflict.field} local=${conflict.localValue} server=${conflict.serverValue}',
        );
        if (onConflict != null) {
          await onConflict!(conflict);
        }
      },
    );

    _log('Sync cycle complete. Pushed events: $totalPushed${pushError != null ? " (push had errors)" : ""}');
  }

  Future<bool> _runHealthCheck({required String reason}) async {
    _lastHealthCheckAt = DateTime.now();
    _setStatus(SyncState.checkingHealth, 'Checking backend health');
    try {
      final family = await InventoryDatabase.instance.resolveBackendFamily();
      final healthUri = family == SyncBackendFamily.central
          ? config.centralHealthUri
          : config.proxyHealthUri;
      final resp = await http.get(healthUri).timeout(config.healthTimeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        _setStatus(
          SyncState.unauthorized,
          'Backend rejected sync credentials',
          error: 'health check unauthorized ($reason)',
        );
        return false;
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _setStatus(SyncState.online, 'Backend reachable (${family.name})');
        return true;
      }

      if (resp.statusCode == 404) {
        final fallbackFamily = family == SyncBackendFamily.central
            ? SyncBackendFamily.proxy
            : SyncBackendFamily.central;
        final fallbackUri = fallbackFamily == SyncBackendFamily.central
            ? config.centralHealthUri
            : config.proxyHealthUri;
        final fallbackResp = await http
            .get(fallbackUri)
            .timeout(config.healthTimeout);
        if (fallbackResp.statusCode >= 200 && fallbackResp.statusCode < 300) {
          _log(
            'Health probe switched to ${fallbackFamily.name} backend at $fallbackUri after 404 from $healthUri',
          );
          _setStatus(
            SyncState.online,
            'Backend reachable (${fallbackFamily.name})',
          );
          return true;
        }
      }

      _setStatus(
        SyncState.offline,
        'Backend unhealthy',
        error: 'health status ${resp.statusCode} at $healthUri',
      );
      return false;
    } catch (error) {
      _setStatus(
        SyncState.offline,
        'Backend unreachable',
        error: error.toString(),
      );
      return false;
    }
  }

  bool _eventHasConnectivity(dynamic event) {
    if (event is ConnectivityResult) {
      return event != ConnectivityResult.none;
    }
    if (event is List<ConnectivityResult>) {
      return event.any((e) => e != ConnectivityResult.none);
    }
    return true;
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final jitterCapMs = config.retryBaseDelay.inMilliseconds
        .clamp(1, 500)
        .toInt();
    final jitterMs = Random().nextInt(jitterCapMs);
    final delay = backoffPolicy.nextDelay(_failureCount, jitterMs: jitterMs);
    _log('Scheduling sync retry in ${delay.inMilliseconds}ms');
    _retryTimer = Timer(delay, () {
      unawaited(triggerSync());
    });
  }

  void _log(String message) {
    logger('[SyncManager] $message');
  }
}
