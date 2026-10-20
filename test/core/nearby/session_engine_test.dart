import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/link_state.dart';
import 'package:lims/core/nearby/session_engine.dart';

void main() {
  test('connection readiness resets retry state', () {
    final engine = SessionEngine();

    engine.connectionRequested('peer', LinkRole.customer);
    final epoch = engine.snapshot.sessionEpoch;
    engine.physicalConnected('peer', epoch);
    engine.sessionReady('peer', epoch);
    expect(engine.snapshot.state, LinkState.syncing);
    expect(engine.snapshot.retryAttempt, 0);
    engine.dispose();
  });

  test('ignores stale epochs and supports manual stop', () {
    final engine = SessionEngine();
    engine.connectionRequested('peer', LinkRole.customer);
    final staleEpoch = engine.snapshot.sessionEpoch;
    engine.adapterChanged(powered: false);
    engine.physicalConnected('peer', staleEpoch);
    engine.sessionReady('peer', staleEpoch);

    expect(engine.snapshot.state, LinkState.adapterOff);
    engine.manualStop();
    expect(engine.snapshot.state, LinkState.idle);
    engine.dispose();
  });

  test('disconnect preserves the peer for transport recovery', () {
    final engine = SessionEngine();
    engine.connectionRequested('peer', LinkRole.shopkeeper);
    engine.peerDisconnected(engine.snapshot.sessionEpoch);
    expect(engine.snapshot.state, LinkState.idle);
    expect(engine.snapshot.peerId, 'peer');
    engine.dispose();
  });
}
