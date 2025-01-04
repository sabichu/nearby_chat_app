import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:device_marketing_names/device_marketing_names.dart';
import 'package:nearby_chat_app/models/device.dart';
import 'package:nearby_chat_app/models/message.dart';
import 'package:nearby_chat_app/models/routing_entry.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nearby_chat_app/services/local_database_service.dart';
import 'package:uuid/uuid.dart';

class NearbyServiceManager {
  static final NearbyServiceManager _instance =
      NearbyServiceManager._internal();
  factory NearbyServiceManager() => _instance;
  NearbyServiceManager._internal();

  final String _localEndpointId = Uuid().v4();
  String get localEndpointId => _localEndpointId;

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final Set<String> _connectedEndpoints = {};
  String? _userInfo;
  Map<String, String> _deviceInfo = {};

  final LocalDatabaseService _databaseService = LocalDatabaseService();

  bool _isInitialized = false;

  final StreamController<Message> _activeChatController =
      StreamController<Message>.broadcast();

  Stream<Message> get activeChatStream => _activeChatController.stream;

  String? _currentChatId;

  void setActiveChat(String chatId) {
    _currentChatId = chatId;

    if (_unreadMessages.containsKey(chatId)) {
      _unreadMessages.remove(chatId);
      _unreadMessagesController.add(Map.from(_unreadMessages));
    }

    _activeChatController.addStream(Stream.empty());
  }

  final StreamController<Map<String, int>> _unreadMessagesController =
      StreamController<Map<String, int>>.broadcast();

  Map<String, int> _unreadMessages = {};

  Stream<Map<String, int>> get unreadMessagesStream =>
      _unreadMessagesController.stream;

  void resetUnreadMessages(String userId) {
    if (_unreadMessages.containsKey(userId)) {
      _unreadMessages[userId] = 0;
      _unreadMessagesController.add(Map.from(_unreadMessages));
    }
  }

  final Set<String> _processedMessageIds = {};
  final Map<String, Timer> _disconnectTimers = {};

  Future<void> initialize({required String userName}) async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _clearAllTables();
    await _initializeDeviceInfo();
    _generateUserInfo(userName);

    if (!await _requestPermissions()) {
      throw Exception('Not all required permits were granted');
    }

    _startAdvertising();
    _startDiscovery();
  }

  Future<void> _clearAllTables() async {
    final db = await _databaseService.database;
    await db.delete('devices');
    await db.delete('messages');
    await db.delete('routing_table');
  }

  void dispose() {
    if (_isInitialized) {
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
      _activeChatController.close();
    }
  }

  void _generateUserInfo(String userName) {
    _userInfo =
        '${localEndpointId}|${userName}|${_deviceInfo['manufacturer']}|${_deviceInfo['name']}';
    print(_userInfo);
  }

  Future<void> _initializeDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final deviceMarketingNames = DeviceMarketingNames();
    final singleDeviceName = await deviceMarketingNames.getSingleName();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      String manufacturer = androidInfo.manufacturer;
      _deviceInfo = {
        'model': androidInfo.model,
        'manufacturer': manufacturer.toString()[0].toUpperCase() +
            manufacturer.toString().substring(1),
      };
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      _deviceInfo = {
        'model': iosInfo.utsname.machine,
        'manufacturer': 'Apple',
      };
    } else {
      _deviceInfo = {'model': 'Unknown', 'manufacturer': 'Unknown'};
    }

    _deviceInfo['name'] = singleDeviceName;
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  void _startAdvertising() async {
    try {
      await Nearby().startAdvertising(
        userInfo,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _connectedEndpoints.add(id);
          }
        },
        onDisconnected: (id) {
          _connectedEndpoints.remove(id);
          _onDisconnected(id);
        },
      );
    } catch (e) {
      print('Error starting Advertising: $e');
    }
  }

  void _startDiscovery() async {
    try {
      await Nearby().startDiscovery(
        userInfo,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          _handleEndpointFound(id, name);
        },
        onEndpointLost: (id) {},
      );
    } catch (e) {
      print('Error starting Discovery: $e');
    }
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) async {
    if (_connectedEndpoints.contains(id)) {
      Nearby().rejectConnection(id);
      return;
    }

    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endid, payload) {
        if (payload.type == PayloadType.BYTES) {
          try {
            Message receivedMessage = Message.fromBytes(payload.bytes!);
            _processReceivedMessage(receivedMessage);
          } catch (e) {
            print('Error processing received message: $e');
          }
        }
      },
    );

    RoutingEntry routingEntry = RoutingEntry(
        destinationId: id,
        nextHopId: id,
        distance: 1,
        lastUpdatedAt: DateTime.now().millisecondsSinceEpoch);

    _databaseService.insertRoutingEntry(routingEntry);

    final localId = info.endpointName.split('|')[0];
    final userName = info.endpointName.split('|')[1];
    final modelName = '${info.endpointName.split('|')[2]} ${info.endpointName.split('|')[3]}';

    Device device = Device(
        deviceId: id,
        localId: localId,
        userName: userName,
        modelName: modelName,
        isIndirect: false,
        lastSeenAt: DateTime.now().millisecondsSinceEpoch);

    await _databaseService.insertDevice(device);

    _broadcastRoutingUpdate(localId, id);
  }

  void _handleEndpointFound(String remoteEndpointId, String remoteUserInfo) {
    final String remoteId = remoteUserInfo.split('|')[0];
    final String localId = userInfo.split('|')[0];

    if (localId.compareTo(remoteId) < 0) {
      _connectToDevice(remoteEndpointId);
    }
  }

  void _connectToDevice(String id) {
    if (_connectedEndpoints.contains(id)) {
      return;
    }

    Nearby().requestConnection(
      userInfo,
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          _connectedEndpoints.add(id);
        }
      },
      onDisconnected: (id) {
        _connectedEndpoints.remove(id);
        _onDisconnected(id);
      },
    );
  }

  void _onDisconnected(String id) async {
    await _databaseService.deleteDevice(id);

    final disconnectUpdate = Message(
      messageId: Uuid().v4(),
      messageType: 'DISCONNECT_UPDATE',
      senderId: localEndpointId,
      receiverId: '',
      content: '$id',
      sentAt: DateTime.now().millisecondsSinceEpoch,
    );

    for (String endpointId in _connectedEndpoints) {
      Nearby().sendBytesPayload(endpointId, disconnectUpdate.toBytes());
    }
  }

  void _processReceivedMessage(Message message) async {
    switch (message.messageType) {
      case 'ROUTING_UPDATE':
        _handleRoutingUpdate(message);
        break;
      case 'DISCONNECT_UPDATE':
        _handleDisconnectUpdate(message);
        break;
      case 'NORMAL':
        _handleNormalMessage(message);
        break;
      case 'ACK':
        _handleAckMessage(message);
        break;
      default:
        print('Unknown type of message: ${message.messageType}');
    }
  }

  void onMessageReceived(Message message) async {
    await _databaseService.insertMessage(message);

    if (_currentChatId != null &&
        (message.senderId == _currentChatId ||
            message.receiverId == _currentChatId)) {
      _activeChatController.add(message);
    } else {
      final userId = message.senderId == localEndpointId
          ? message.receiverId
          : message.senderId;

      _unreadMessages[userId] = (_unreadMessages[userId] ?? 0) + 1;
      _unreadMessagesController.add(Map.from(_unreadMessages));
    }
  }

  void _handleDisconnectUpdate(Message message) async {
    if (await isMessageProcessed(message.messageId)) return;

    _processedMessageIds.add(message.messageId);
    await _databaseService.insertMessage(message);

    final targetDeviceId = message.content;

    message.incrementHops();
    if (message.isExpired()) {
      print('Disconnection message expired. Will not be processed.');
      return;
    }

    final timer = Timer(Duration(seconds: 10), () async {
      print('Expired timer for $targetDeviceId. Propagating disconnection.');
      await _databaseService.deleteDevice(targetDeviceId);

      for (String endpointId in _connectedEndpoints) {
        final senderNearbyId = await _databaseService.getNearbyIdFromLocalId(message.senderId);
        if (endpointId != senderNearbyId) {
          Nearby().sendBytesPayload(endpointId, message.toBytes());
        }
      }
    });

    _disconnectTimers[message.messageId] = timer;

    for (String endpointId in _connectedEndpoints) {
      final senderNearbyId = await _databaseService.getNearbyIdFromLocalId(message.senderId);
      if (endpointId != senderNearbyId) {
        await _sendReachabilityCheck(endpointId, targetDeviceId, message.messageId);
      }
    }
  }

  Future<void> _sendReachabilityCheck(String endpointId, String targetDeviceId, String originalMessageId) async {
    final reachabilityCheck = Message(
      messageId: Uuid().v4(),
      messageType: 'REACHABILITY_CHECK',
      senderId: localEndpointId,
      receiverId: endpointId,
      content: '$targetDeviceId|$originalMessageId',
      sentAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _databaseService.insertMessage(reachabilityCheck);

    try {
      Nearby().sendBytesPayload(endpointId, reachabilityCheck.toBytes());
    } catch (e) {
      print('Error when sending REACHABILITY_CHECK to $endpointId: $e');
    }
  }

  void _handleReachabilityCheck(Message message) async {
    if (await isMessageProcessed(message.messageId)) return;

    _processedMessageIds.add(message.messageId);
    await _databaseService.insertMessage(message);

    final contentParts = message.content.split('|');
    final targetDeviceId = contentParts[0];
    final originalMessageId = contentParts[1];

    if (_connectedEndpoints.contains(targetDeviceId)) {
      print('Direct connection found with device disconnected $targetDeviceId.');

      final reachabilityResponse = Message(
        messageId: Uuid().v4(),
        messageType: 'REACHABILITY_CHECK_RESPONSE',
        senderId: localEndpointId,
        receiverId: message.senderId,
        content: '$targetDeviceId|$originalMessageId',
        sentAt: DateTime.now().millisecondsSinceEpoch,
      );

      final senderNearbyId = await _databaseService.getNearbyIdFromLocalId(message.senderId);
      if (senderNearbyId != null && _connectedEndpoints.contains(senderNearbyId)) {
        Nearby().sendBytesPayload(senderNearbyId, reachabilityResponse.toBytes());
      } else {
        for (String endpointId in _connectedEndpoints) {
          if (endpointId != targetDeviceId) {
            Nearby().sendBytesPayload(endpointId, reachabilityResponse.toBytes());
          }
        }
      }
    } else {
      print('There is no connection with $targetDeviceId. Propagating REACHABILITY_CHECK.');

      for (String endpointId in _connectedEndpoints) {
        final senderNearbyId = await _databaseService.getNearbyIdFromLocalId(message.senderId);
        if (endpointId != senderNearbyId) {
          await _sendReachabilityCheck(endpointId, targetDeviceId, originalMessageId);
        }
      }
    }
  }

  void _handleReachabilityCheckResponse(Message message) async {
    if (await isMessageProcessed(message.messageId)) return;

    _processedMessageIds.add(message.messageId);
    await _databaseService.insertMessage(message);

    final contentParts = message.content.split('|');
    final targetDeviceId = contentParts[0];
    final originalMessageId = contentParts[1];

    if (message.receiverId == localEndpointId) {
      if (_disconnectTimers.containsKey(originalMessageId)) {
        print('Reachability response received for $targetDeviceId. Cancelling timer.');
        _disconnectTimers[originalMessageId]?.cancel();
        _disconnectTimers.remove(originalMessageId);
      }
      return;
    }

    final nextHopId = await _databaseService.getRoutingEntry(message.receiverId);
    if (nextHopId != null) {
      try {
        print('Propagating REACHABILITY_CHECK_RESPONSE to the next hop: ${nextHopId.nextHopId}');
        Nearby().sendBytesPayload(nextHopId.nextHopId, message.toBytes());
      } catch (e) {
        print('Error propagating REACHABILITY_CHECK_RESPONSE: $e');
      }
    } else {
      for (String endpointId in _connectedEndpoints) {
        if (endpointId != message.senderId) {
          Nearby().sendBytesPayload(endpointId, message.toBytes());
        }
      }
    }
  }

  void _handleNormalMessage(Message message) async {
    if (await isMessageProcessed(message.messageId)) return;

    _processedMessageIds.add(message.messageId);
    await _databaseService.insertMessage(message);

    message.incrementHops();
    if (message.isExpired()) {
      print('Expired message: ${message.messageId}. It will not be forwarded.');
      return;
    }

    if (message.receiverId == localEndpointId) {
      onMessageReceived(message);

      final ackMessage = Message(
        messageId: Uuid().v4(),
        messageType: 'ACK',
        senderId: localEndpointId,
        receiverId: message.senderId,
        content: message.messageId,
        sentAt: DateTime.now().millisecondsSinceEpoch,
      );
      await sendMessage(ackMessage);
    } else {
      final senderNearbyId = await _databaseService.getNearbyIdFromLocalId(message.senderId);
      for (String endpointId in _connectedEndpoints) {
        if (endpointId != senderNearbyId) {
          Nearby().sendBytesPayload(endpointId, message.toBytes());
        }
      }
    }
  }

  void _handleAckMessage(Message message) async {
    if (await isMessageProcessed(message.messageId)) return;

    _processedMessageIds.add(message.messageId);
    await _databaseService.insertMessage(message);

    message.incrementHops();
    if (message.isExpired()) {
      print('ACK expired. It will not be processed.');
      return;
    }

    if (message.receiverId == localEndpointId) {
      final originalMessageId = message.content;
      await _databaseService.updateMessageStatus(originalMessageId, 'DELIVERED');
      print('ACK received for the message: $originalMessageId');
    } else {
      final senderNearbyId = await _databaseService.getNearbyIdFromLocalId(message.senderId);
      for (String endpointId in _connectedEndpoints) {
        if (endpointId != senderNearbyId) {
          Nearby().sendBytesPayload(endpointId, message.toBytes());
        }
      }
    }
  }

  Future<void> sendMessage(Message message) async {
    try {
      final route = await _databaseService.getRoutingEntry(message.receiverId);
      if (route == null) {
        for (String endpointId in _connectedEndpoints) {
          Nearby().sendBytesPayload(endpointId, message.toBytes());
        }
      } else {
        final nextHopId = route.nextHopId;
        await Nearby().sendBytesPayload(nextHopId, message.toBytes());
      }

      message.updateStatus('SENT');
      await _databaseService.insertMessage(message);
    } catch (e) {
      message.updateStatus('ERROR');
      await _databaseService.updateMessageStatus(message.messageId, 'ERROR');
    }
  }

  void _broadcastRoutingUpdate(String localId, String nearbyId) {
    final routingUpdate = Message(
      messageId: Uuid().v4(),
      messageType: 'ROUTING_UPDATE',
      senderId: localEndpointId,
      receiverId: '',
      content: '$localId|$nearbyId',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      ttl: 10,
    );

    for (String endpointId in _connectedEndpoints) {
      if (endpointId != nearbyId) {
        Nearby().sendBytesPayload(endpointId, routingUpdate.toBytes());
      }
    }

    _databaseService.insertMessage(routingUpdate);
  }

  void _handleRoutingUpdate(Message message) async {
    if (await isMessageProcessed(message.messageId)) return;

    if (message.isExpired()) {
      print('ROUTING_UPDATE message expired. TTL timed out.');
      return;
    }

    message.incrementHops();
    if (message.isExpired()) {
      print('ROUTING_UPDATE message expired. It will not be processed.');
      return;
    }

    _processedMessageIds.add(message.messageId);
    await _databaseService.insertMessage(message);

    final contentParts = message.content.split('|');
    final localId = contentParts[0];
    final nearbyId = contentParts[1];

    final senderNearbyId = await _databaseService.getNearbyIdFromLocalId(message.senderId);

    final deviceExists = await _databaseService.doesDeviceExist(localId);
    if (!deviceExists) {
      await _databaseService.insertDevice(Device(
        deviceId: nearbyId,
        localId: localId,
        isIndirect: true,
        lastSeenAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    for (String endpointId in _connectedEndpoints) {
      if (endpointId != senderNearbyId) {
        Nearby().sendBytesPayload(endpointId, message.toBytes());
      }
    }
  }

  Future<bool> isMessageProcessed(String messageId) async {
    if (_processedMessageIds.contains(messageId)) {
      return true;
    }

    return await _databaseService.doesMessageExist(messageId);
  }

  String get userInfo => _userInfo ?? 'Unknown user';
  List<String> get connectedEndpoints => List.unmodifiable(_connectedEndpoints);
}
