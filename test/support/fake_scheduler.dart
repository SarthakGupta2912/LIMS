import 'dart:async';

import 'package:lims/core/time/scheduler.dart';

class FakeScheduler implements Scheduler {
  FakeScheduler([DateTime? start]) : _now = start ?? DateTime.utc(2026, 1, 1);

  DateTime _now;
  final List<FakeTimer> timers = [];

  @override
  DateTime now() => _now;

  @override
  Timer runDelayed(Duration delay, void Function() callback) {
    final timer = FakeTimer(_now.add(delay), callback, this);
    timers.add(timer);
    return timer;
  }

  @override
  Timer runPeriodic(Duration interval, void Function() callback) {
    final timer = FakeTimer.periodic(
      _now.add(interval),
      interval,
      callback,
      this,
    );
    timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    final target = _now.add(duration);
    while (true) {
      final due =
          timers
              .where(
                (timer) => timer.isActive && !timer.nextRun.isAfter(target),
              )
              .toList()
            ..sort((a, b) => a.nextRun.compareTo(b.nextRun));
      if (due.isEmpty) break;
      final timer = due.first;
      _now = timer.nextRun;
      timer.fire();
    }
    _now = target;
  }

  int get activeTimers => timers.where((timer) => timer.isActive).length;

  void _remove(FakeTimer timer) => timers.remove(timer);
}

class FakeTimer implements Timer {
  FakeTimer(this.nextRun, this._callback, this._scheduler) : _interval = null;

  FakeTimer.periodic(
    this.nextRun,
    Duration interval,
    this._callback,
    this._scheduler,
  ) : _interval = interval;

  DateTime nextRun;
  final Duration? _interval;
  final void Function() _callback;
  final FakeScheduler _scheduler;
  bool _active = true;

  void fire() {
    if (!_active) return;
    final interval = _interval;
    if (interval == null) {
      _active = false;
      _callback();
    } else {
      _callback();
      if (_active) nextRun = nextRun.add(interval);
    }
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
    _scheduler._remove(this);
  }
}
