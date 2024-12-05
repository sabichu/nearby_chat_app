class Device {
  final int? id;
  final String deviceId;
  final String localId;
  final String? userName;
  final String? modelName;
  bool isConnected;
  int lastSeenAt;

  Device({
    this.id,
    required this.deviceId,
    required this.localId,
    this.userName,
    this.modelName,
    this.isConnected = false,
    required this.lastSeenAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'local_id': localId,
      'user_name': userName,
      'model_name': modelName,
      'is_connected': isConnected ? 1 : 0,
      'last_seen_at': lastSeenAt,
    };
  }

  factory Device.fromMap(Map<String, dynamic> map) {
    return Device(
      id: map['id'],
      deviceId: map['device_id'],
      localId: map['local_id'],
      userName: map['user_name'],
      modelName: map['model_name'],
      isConnected: map['is_connected'] == 1,
      lastSeenAt: map['last_seen_at'],
    );
  }
}
