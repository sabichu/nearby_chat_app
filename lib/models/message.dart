import 'dart:convert';
import 'dart:typed_data';

class Message {
  int? id;
  final String messageId;
  final String messageType;
  final String senderId;
  final String receiverId;
  final String content;
  int hops;
  int ttl;
  String status;
  final int sentAt;
  int? readAt;
  int? dateCreated;

  Message({
    this.id,
    required this.messageId,
    required this.messageType,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.hops = 0,
    this.ttl = 10,
    this.status = 'PENDING',
    required this.sentAt,
    this.readAt,
    this.dateCreated,
  });

  Message copyWith({
    int? id,
    String? messageId,
    String? messageType,
    String? senderId,
    String? receiverId,
    String? content,
    int? hops,
    int? ttl,
    String? status,
    int? sentAt,
    int? readAt,
    int? dateCreated,
  }) {
    return Message(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      messageType: messageType ?? this.messageType,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      hops: hops ?? this.hops,
      ttl: ttl ?? this.ttl,
      status: status ?? this.status,
      sentAt: sentAt ?? this.sentAt,
      readAt: readAt ?? this.readAt,
      dateCreated: dateCreated ?? this.dateCreated,
    );
  }

  Uint8List toBytes() {
    String jsonString = jsonEncode(toMap());
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  static Message fromBytes(Uint8List bytes) {
    String jsonString = utf8.decode(bytes);
    return Message.fromMap(jsonDecode(jsonString));
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'message_id': messageId,
      'message_type': messageType,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'hops': hops,
      'ttl': ttl,
      'status': status,
      'sent_at': sentAt,
      'read_at': readAt,
      'date_created': dateCreated,
    };
  }

  static Message fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      messageId: map['message_id'],
      messageType: map['message_type'],
      senderId: map['sender_id'],
      receiverId: map['receiver_id'],
      content: map['content'],
      hops: map['hops'],
      ttl: map['ttl'],
      status: map['status'],
      sentAt: map['sent_at'],
      readAt: map['read_at'],
      dateCreated: map['date_created'],
    );
  }

  void incrementHops() {
    hops += 1;
    ttl -= 1;
  }

  bool isExpired() {
    return ttl <= 0;
  }

  void updateStatus(String newStatus) {
    status = newStatus;
    if (newStatus == 'READ') {
      readAt = DateTime.now().millisecondsSinceEpoch;
    }
  }
}
