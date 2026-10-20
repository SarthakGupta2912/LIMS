import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/nearby_reconnect.dart';

void main() {
  test('backs off exponentially, caps at 30 seconds, and resets', () {
    fakeAsync((async) {
      final reconnect = NearbyReconnect();
      var calls = 0;

      for (final seconds in [1, 2, 4, 8, 16, 30, 30]) {
        reconnect.schedule(() async => calls++);
        async.elapse(Duration(seconds: seconds - 1));
        expect(calls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(calls, 1);
        calls = 0;
      }

      reconnect.reset();
      reconnect.schedule(() async => calls++);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 1);
    });
  });

  test('cancel prevents pending reconnect', () {
    fakeAsync((async) {
      final reconnect = NearbyReconnect();
      var calls = 0;
      reconnect.schedule(() async => calls++);
      reconnect.cancel();
      async.elapse(const Duration(minutes: 1));
      expect(calls, 0);
    });
  });
}
