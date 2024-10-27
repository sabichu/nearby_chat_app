import 'dart:convert';
import 'dart:typed_data';

class RouteInfo {
  final String nextHop;
  final int distance;
  final String userName;
  final String deviceName;

  RouteInfo({
    required this.nextHop,
    required this.distance,
    required this.userName,
    required this.deviceName,
  });
}

class Message {
  final String type;
  final String senderId;
  final String receiverId;
  final String content;
  int hops;
  int ttl;

  Message({
    required this.type,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.hops = 0,
    this.ttl = 10,
  });

  Uint8List toBytes() {
    String jsonString = jsonEncode({
      'type': type,
      'senderId': senderId,
      'recipientId': receiverId,
      'content': content,
      'hops': hops,
      'ttl': ttl,
    });
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  static Message fromBytes(Uint8List bytes) {
    String jsonString = utf8.decode(bytes);
    Map<String, dynamic> jsonMap = jsonDecode(jsonString);
    return Message(
      type: jsonMap['type'],
      senderId: jsonMap['senderId'],
      receiverId: jsonMap['recipientId'],
      content: jsonMap['content'],
      hops: jsonMap['hops'],
      ttl: jsonMap['ttl'],
    );
  }
}