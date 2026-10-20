import 'dart:async';

/// Injectable scheduling boundary.
///
/// Production code uses real timers through [SystemScheduler]. Tests use a
/// deterministic fake scheduler. This separation allows reconnect, timeout,
/// and retry behavior to be tested without waiting in real time.
abstract class Scheduler {
  DateTime now();

  Timer runDelayed(Duration delay, void Function() callback);

  Timer runPeriodic(Duration interval, void Function() callback);
}

class SystemScheduler implements Scheduler {
  const SystemScheduler();

  @override
  DateTime now() => DateTime.now();

  @override
  Timer runDelayed(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  @override
  Timer runPeriodic(Duration interval, void Function() callback) =>
      Timer.periodic(interval, (_) => callback());
}
