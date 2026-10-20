import 'dart:async';

class NearbyReconnect {
  Timer? _timer;
  int _attempt = 0;

  void reset() {
    _attempt = 0;
    _timer?.cancel();
  }

  void cancel() => _timer?.cancel();

  void schedule(Future<void> Function() reconnect) {
    _timer?.cancel();
    final seconds = (1 << _attempt.clamp(0, 5)).clamp(1, 30);
    _attempt++;
    _timer = Timer(Duration(seconds: seconds), reconnect);
  }
}
