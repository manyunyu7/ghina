import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

/// Wires app lifecycle, connectivity and a foreground timer to the engine:
/// resume → sync; connectivity regained → sync; every [period] while resumed → sync.
class FlutterSyncTriggers implements SyncTriggerSource {
  FlutterSyncTriggers({
    Connectivity? connectivity,
    this.period = const Duration(seconds: 60),
  }) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final Duration period;

  SyncEngine? _engine;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<List<ConnectivityResult>>? _net;
  Timer? _timer;
  bool _online = true;

  @override
  void attach(SyncEngine engine) {
    _engine = engine;
    _lifecycle = AppLifecycleListener(
      onResume: () {
        engine.requestSync();
        _startTimer();
      },
      onPause: _stopTimer,
      onHide: _stopTimer,
      onDetach: _stopTimer,
    );
    _net = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && !_online) engine.onConnectivityRegained();
      _online = online;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(period, (_) => _engine?.requestSync());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void detach() {
    _stopTimer();
    _lifecycle?.dispose();
    _lifecycle = null;
    _net?.cancel();
    _net = null;
    _engine = null;
  }
}
