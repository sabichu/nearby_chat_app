class RoutingEntry {
  final int? id;
  final String destinationId;
  final String nextHopId;
  int distance;
  int lastUpdatedAt;

  RoutingEntry({
    this.id,
    required this.destinationId,
    required this.nextHopId,
    required this.distance,
    required this.lastUpdatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'destination_id': destinationId,
      'next_hop_id': nextHopId,
      'distance': distance,
      'last_updated_at': lastUpdatedAt,
    };
  }

  factory RoutingEntry.fromMap(Map<String, dynamic> map) {
    return RoutingEntry(
      id: map['id'],
      destinationId: map['destination_id'],
      nextHopId: map['next_hop_id'],
      distance: map['distance'],
      lastUpdatedAt: map['last_updated_at'],
    );
  }
}
