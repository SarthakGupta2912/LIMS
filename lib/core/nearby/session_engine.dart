import 'link_state.dart';

/// Deterministic Nearby session and reconnect engine.
///
/// The engine owns connection epochs and stale-event rejection. Hardware and
/// reconnect timing remain behind the transport boundary.
class SessionEngine {
  SessionEngine({LinkSnapshot? initial})
    : snapshot =
          initial ?? const LinkSnapshot(state: LinkState.idle, sessionEpoch: 0);

  LinkSnapshot snapshot;

  void adapterChanged({required bool powered}) {
    snapshot = snapshot.nextEpoch(
      powered ? LinkState.idle : LinkState.adapterOff,
    );
  }

  void scanRequested(LinkRole role) {
    snapshot = snapshot.copyWith(
      state: LinkState.scanning,
      role: role,
      error: null,
    );
  }

  void connectionRequested(String peerId, LinkRole role) {
    snapshot = snapshot
        .nextEpoch(LinkState.connecting)
        .copyWith(
          peerId: peerId,
          role: role,
          peerIdentityVerified: false,
          gattReady: false,
          notifyReady: false,
          error: null,
        );
  }

  void physicalConnected(String peerId, int epoch) {
    if (!_currentEpoch(epoch)) return;
    snapshot = snapshot.copyWith(
      state: LinkState.connected,
      peerId: peerId,
      peerIdentityVerified: false,
      gattReady: false,
      notifyReady: false,
      error: null,
    );
  }

  void sessionReady(String peerId, int epoch) {
    if (!_currentEpoch(epoch) || snapshot.peerId != peerId) return;
    snapshot = snapshot.copyWith(
      state: LinkState.syncing,
      peerIdentityVerified: true,
      gattReady: true,
      notifyReady: true,
      retryAttempt: 0,
      nextRetryAt: null,
      error: null,
    );
  }

  void peerDisconnected(int epoch) {
    if (!_currentEpoch(epoch)) return;
    snapshot = snapshot.nextEpoch(LinkState.idle, preservePeer: true);
  }

  void manualStop() {
    snapshot = snapshot.nextEpoch(LinkState.idle);
  }

  void dispose() {}

  bool _currentEpoch(int epoch) => epoch == snapshot.sessionEpoch;
}
