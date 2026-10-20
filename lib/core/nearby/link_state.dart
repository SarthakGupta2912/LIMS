/// Authoritative nearby-device link states.
///
/// `connected` means only that a physical nearby peer connection exists.
/// `syncing` means GATT discovery, notification subscription, peer identity,
/// and cursor exchange are complete enough to exchange application deltas.
enum LinkState { adapterOff, scanning, connecting, connected, syncing, idle }

enum LinkRole { none, customer, shopkeeper }

/// Immutable snapshot describing one Nearby session epoch.
class LinkSnapshot {
  const LinkSnapshot({
    required this.state,
    required this.sessionEpoch,
    this.role = LinkRole.none,
    this.adapterPowered = true,
    this.permissionsGranted = false,
    this.peerId,
    this.peerIdentityVerified = false,
    this.gattReady = false,
    this.notifyReady = false,
    this.mtu,
    this.protocolVersion = 2,
    this.retryAttempt = 0,
    this.nextRetryAt,
    this.lastReceiveAt,
    this.lastTransmitAt,
    this.lastAckAt,
    this.outboxDepth = 0,
    this.error,
  });

  final LinkState state;
  final int sessionEpoch;
  final LinkRole role;
  final bool adapterPowered;
  final bool permissionsGranted;
  final String? peerId;
  final bool peerIdentityVerified;
  final bool gattReady;
  final bool notifyReady;
  final int? mtu;
  final int protocolVersion;
  final int retryAttempt;
  final DateTime? nextRetryAt;
  final DateTime? lastReceiveAt;
  final DateTime? lastTransmitAt;
  final DateTime? lastAckAt;
  final int outboxDepth;
  final String? error;

  bool get readyForSync =>
      state == LinkState.syncing &&
      peerId != null &&
      peerIdentityVerified &&
      gattReady &&
      notifyReady;

  LinkSnapshot copyWith({
    LinkState? state,
    int? sessionEpoch,
    LinkRole? role,
    bool? adapterPowered,
    bool? permissionsGranted,
    String? peerId,
    bool? peerIdentityVerified,
    bool? gattReady,
    bool? notifyReady,
    int? mtu,
    int? protocolVersion,
    int? retryAttempt,
    DateTime? nextRetryAt,
    DateTime? lastReceiveAt,
    DateTime? lastTransmitAt,
    DateTime? lastAckAt,
    int? outboxDepth,
    String? error,
  }) => LinkSnapshot(
    state: state ?? this.state,
    sessionEpoch: sessionEpoch ?? this.sessionEpoch,
    role: role ?? this.role,
    adapterPowered: adapterPowered ?? this.adapterPowered,
    permissionsGranted: permissionsGranted ?? this.permissionsGranted,
    peerId: peerId ?? this.peerId,
    peerIdentityVerified: peerIdentityVerified ?? this.peerIdentityVerified,
    gattReady: gattReady ?? this.gattReady,
    notifyReady: notifyReady ?? this.notifyReady,
    mtu: mtu ?? this.mtu,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    retryAttempt: retryAttempt ?? this.retryAttempt,
    nextRetryAt: nextRetryAt,
    lastReceiveAt: lastReceiveAt ?? this.lastReceiveAt,
    lastTransmitAt: lastTransmitAt ?? this.lastTransmitAt,
    lastAckAt: lastAckAt ?? this.lastAckAt,
    outboxDepth: outboxDepth ?? this.outboxDepth,
    error: error,
  );

  LinkSnapshot nextEpoch(
    LinkState state, {
    bool preserveRetry = false,
    bool preservePeer = false,
  }) => LinkSnapshot(
    state: state,
    sessionEpoch: sessionEpoch + 1,
    role: role,
    adapterPowered: adapterPowered,
    permissionsGranted: permissionsGranted,
    peerId: preservePeer ? peerId : null,
    retryAttempt: preserveRetry ? retryAttempt : 0,
  );
}
