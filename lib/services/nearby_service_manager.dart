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

  final Map<String, Timer> _reconnectionTimers = {};

  Future<void> initialize({required String userName}) async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _clearAllTables();
    await _initializeDeviceInfo();
    _generateUserInfo(userName);

    if (!await _requestPermissions()) {
      //throw Exception('Not all required permits were granted');
      print('Not all required permits were granted');
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
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  void _scheduleReconnection(String remoteEndpointId) {
    if (_reconnectionTimers.containsKey(remoteEndpointId)) return;

    final timer = Timer(Duration(seconds: 5), () {
      _reconnectionTimers.remove(remoteEndpointId);
      if (!_connectedEndpoints.contains(remoteEndpointId)) {
        print('Retrying connection with $remoteEndpointId...');
        _connectToDevice(remoteEndpointId);
      }
    });

    _reconnectionTimers[remoteEndpointId] = timer;
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

  Future<void> restartServices() async {
    try {
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();

      await Future.delayed(Duration(milliseconds: 500));
    } catch (_) {
      print('Error while restarting Advertising and Discovery');
    }

    print('Restarting Advertising and Discovery manually');
    _startAdvertising();
    _startDiscovery();
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
            _processReceivedMessage(receivedMessage, endid);
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
    final modelName =
        '${info.endpointName.split('|')[2]} ${info.endpointName.split('|')[3]}';

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
      print('Initiating connection');
      _connectToDevice(remoteEndpointId);
    } else {
      print('Waiting for the other device to start connection');
    }
  }

  void _connectToDevice(String id) {
    print('Connecting');

    if (_connectedEndpoints.contains(id)) {
      return;
    }

    try {
      Nearby().requestConnection(
        userInfo,
        id,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _connectedEndpoints.add(id);
          } else if (status == Status.ERROR) {
            print('Connection error with $id. Scheduling a reconnection.');
            _scheduleReconnection(id);
          }
        },
        onDisconnected: (id) {
          _onDisconnected(id);
        },
      );
    } catch (e) {
      print(
          'requestConnection threw exception: $e. Scheduling reconnection in 5s.');
      _scheduleReconnection(id);
    }
  }

  void _onDisconnected(String id) async {
    _connectedEndpoints.remove(id);
    await _databaseService.deleteRoutingEntry(id);

    final localId = await _databaseService.getLocalIdFromNearbyId(id);

    final disconnectMessage = Message(
      messageId: Uuid().v4(),
      messageType: 'DISCONNECT_UPDATE',
      senderId: localEndpointId,
      receiverId: '',
      content: '$localId',
      sentAt: DateTime.now().millisecondsSinceEpoch,
    );

    await sendMessage(disconnectMessage);

    await _databaseService.updateDeviceVerificationStatus(localId!, true);

    _startDisconnectTimer(
      messageId: disconnectMessage.messageId,
      targetLocalId: localId!,
    );

    final checkMessage = Message(
      messageId: Uuid().v4(),
      messageType: 'REACHABILITY_CHECK',
      senderId: localEndpointId,
      receiverId: localId!,
      content: '$localId|${disconnectMessage.messageId}',
      sentAt: DateTime.now().millisecondsSinceEpoch,
    );

    await sendMessage(checkMessage);
  }

  void _startDisconnectTimer({
    required String messageId,
    required String targetLocalId,
  }) {
    if (_disconnectTimers.containsKey(messageId)) return;

    final timer = Timer(Duration(seconds: 30), () async {
      print(
          '[$localEndpointId] Timer expired, deleting $targetLocalId from DB.');
      await _databaseService.deleteDevice(targetLocalId);
      _disconnectTimers.remove(messageId);
    });

    _disconnectTimers[messageId] = timer;
  }

  void _processReceivedMessage(Message message, String senderNearbyId) async {
    switch (message.messageType) {
      case 'NORMAL':
        _handleNormalMessage(message, senderNearbyId);
        break;
      case 'ACK':
        _handleAckMessage(message, senderNearbyId);
        break;
      case 'ROUTING_UPDATE':
        _handleRoutingUpdate(message, senderNearbyId);
        break;
      case 'DISCONNECT_UPDATE':
        _handleDisconnectUpdate(message, senderNearbyId);
        break;
      case 'REACHABILITY_CHECK':
        _handleReachabilityCheck(message, senderNearbyId);
        break;
      case 'REACHABILITY_CHECK_RESPONSE':
        _handleReachabilityCheckResponse(message, senderNearbyId);
        break;
      default:
        print('Unknown type of message: ${message.messageType}');
    }
  }

  void onMessageReceived(Message message) async {
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

  void _handleNormalMessage(Message message, String senderNearbyId) async {
    if (await isMessageProcessed(message.messageId)) return;
    _processedMessageIds.add(message.messageId);

    if (message.receiverId == localEndpointId) {
      await _databaseService.insertMessage(message);
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
      return;
    }

    message.incrementHops();
    if (message.isExpired()) {
      print('Expired message: ${message.messageId}. It will not be forwarded.');
      return;
    }

    final forwardedMessage = message.copyWith(status: 'FORWARDED');
    await _databaseService.insertMessage(forwardedMessage);

    final excludeNearbyIds = <String>[];
    excludeNearbyIds.add(senderNearbyId);
    final originalSenderNearbyId =
        await _databaseService.getNearbyIdFromLocalId(message.senderId);
    if (originalSenderNearbyId != null) {
      excludeNearbyIds.add(originalSenderNearbyId);
    }

    await sendMessage(
      message,
      excludeNearbyIds: excludeNearbyIds,
    );
  }

  void _handleAckMessage(Message message, String senderNearbyId) async {
    if (await isMessageProcessed(message.messageId)) return;
    _processedMessageIds.add(message.messageId);

    if (message.receiverId == localEndpointId) {
      final originalMessageId = message.content;
      print('ACK received for the message: $originalMessageId');

      await _databaseService.updateMessageStatus(
          originalMessageId, 'DELIVERED');
      return;
    }

    message.incrementHops();
    if (message.isExpired()) {
      print('ACK expired. It will not be processed.');
      return;
    }

    final excludeNearbyIds = <String>[senderNearbyId];
    final originalSenderNearbyId =
        await _databaseService.getNearbyIdFromLocalId(message.senderId);
    if (originalSenderNearbyId != null) {
      excludeNearbyIds.add(originalSenderNearbyId);
    }

    await sendMessage(
      message,
      excludeNearbyIds: excludeNearbyIds,
    );
  }

  void _handleRoutingUpdate(Message message, String senderNearbyId) async {
    if (await isMessageProcessed(message.messageId)) return;
    _processedMessageIds.add(message.messageId);

    await _databaseService.insertMessage(message);

    message.incrementHops();
    if (message.isExpired()) {
      print('ROUTING_UPDATE message expired. It will not be processed.');
      return;
    }

    final contentParts = message.content.split('|');

    if (contentParts.length < 2) {
      print('Invalid ROUTING_UPDATE content');
      return;
    }

    final localId = contentParts[0];
    final nearbyId = contentParts[1];

    final deviceExists = await _databaseService.doesDeviceExist(localId);
    if (!deviceExists) {
      await _databaseService.insertDevice(Device(
        deviceId: nearbyId,
        localId: localId,
        isIndirect: true,
        lastSeenAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    final excludeNearbyIds = <String>[senderNearbyId, nearbyId];
    await sendMessage(
      message,
      excludeNearbyIds: excludeNearbyIds,
    );
  }

  void _handleDisconnectUpdate(Message message, String senderNearbyId) async {
    if (await isMessageProcessed(message.messageId)) return;
    _processedMessageIds.add(message.messageId);

    await _databaseService.insertMessage(message);

    message.incrementHops();
    if (message.isExpired()) {
      print('Disconnection message expired. Will not be processed.');
      return;
    }

    final targetLocalId = message.content;
    final targetNearbyId =
        await _databaseService.getNearbyIdFromLocalId(targetLocalId);
    final isDirectlyConnected = (targetNearbyId != null &&
        _connectedEndpoints.contains(targetNearbyId));

    if (isDirectlyConnected) {
      final response = Message(
        messageId: Uuid().v4(),
        messageType: 'REACHABILITY_CHECK_RESPONSE',
        senderId: localEndpointId,
        receiverId: message.senderId,
        content: '$targetLocalId|${message.messageId}',
        hops: 0,
        ttl: 10,
        sentAt: DateTime.now().millisecondsSinceEpoch,
      );

      final nearbyIdOfSender =
          await _databaseService.getNearbyIdFromLocalId(message.senderId);
      List<String> excludeList = [];
      if (senderNearbyId != nearbyIdOfSender) {
        excludeList.add(senderNearbyId);
      }
      await sendMessage(response, excludeNearbyIds: excludeList);
    } else {
      await _databaseService.updateDeviceVerificationStatus(
          targetLocalId, true);

      _startDisconnectTimer(
        messageId: message.messageId,
        targetLocalId: targetLocalId,
      );

      final checkMsg = Message(
        messageId: Uuid().v4(),
        messageType: 'REACHABILITY_CHECK',
        senderId: localEndpointId,
        receiverId: targetLocalId,
        content: '$targetLocalId|${message.messageId}',
        hops: 0,
        ttl: 10,
        sentAt: DateTime.now().millisecondsSinceEpoch,
      );

      await sendMessage(checkMsg, excludeNearbyIds: [senderNearbyId]);
    }

    await sendMessage(message, excludeNearbyIds: [senderNearbyId]);
  }

  void _handleReachabilityCheck(Message message, String senderNearbyId) async {
    if (await isMessageProcessed(message.messageId)) return;
    _processedMessageIds.add(message.messageId);

    await _databaseService.insertMessage(message);

    message.incrementHops();
    if (message.isExpired()) {
      print('Reachability check message expired. Will not be processed.');
      return;
    }

    final contentParts = message.content.split('|');
    final targetLocalId = contentParts[0];
    final originalMessageId = contentParts[1];

    final targetNearbyId =
        await _databaseService.getNearbyIdFromLocalId(targetLocalId);
    final isDirectlyConnected = (targetNearbyId != null &&
        _connectedEndpoints.contains(targetNearbyId));

    if (isDirectlyConnected) {
      final response = Message(
        messageId: Uuid().v4(),
        messageType: 'REACHABILITY_CHECK_RESPONSE',
        senderId: localEndpointId,
        receiverId: message.senderId,
        content: '$targetLocalId|$originalMessageId',
        hops: 0,
        ttl: 10,
        sentAt: DateTime.now().millisecondsSinceEpoch,
      );

      final nearbyIdOfSender =
          await _databaseService.getNearbyIdFromLocalId(message.senderId);
      List<String> excludeList = [];
      if (senderNearbyId != nearbyIdOfSender) {
        excludeList.add(senderNearbyId);
      }

      await sendMessage(response, excludeNearbyIds: excludeList);
    } else {
      await sendMessage(message, excludeNearbyIds: [senderNearbyId]);
    }
  }

  void _handleReachabilityCheckResponse(
      Message message, String senderNearbyId) async {
    if (await isMessageProcessed(message.messageId)) return;
    _processedMessageIds.add(message.messageId);

    await _databaseService.insertMessage(message);

    message.incrementHops();
    if (message.isExpired()) {
      print(
          'Reachability check response message expired. Will not be processed.');
      return;
    }

    final contentParts = message.content.split('|');
    final targetLocalId = contentParts[0];
    final originalMessageId = contentParts[1];

    if (_disconnectTimers.containsKey(originalMessageId)) {
      print(
          'Reachability response received for $targetLocalId. Cancelling timer.');
      _disconnectTimers[originalMessageId]?.cancel();
      _disconnectTimers.remove(originalMessageId);

      await _databaseService.updateDeviceVerificationStatus(
          targetLocalId, false);
    }
  }

  Future<void> sendMessage(Message message,
      {List<String>? excludeNearbyIds}) async {
    try {
      final route = await _databaseService.getRoutingEntry(message.receiverId);

      if (route != null) {
        await Nearby().sendBytesPayload(route.nextHopId, message.toBytes());
      } else {
        for (String endpointId in _connectedEndpoints) {
          if (excludeNearbyIds == null ||
              !excludeNearbyIds.contains(endpointId)) {
            await Nearby().sendBytesPayload(endpointId, message.toBytes());
          }
        }
      }

      if (message.senderId == localEndpointId) {
        message.updateStatus('SENT');
        await _databaseService.insertMessage(message);
      }
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

    sendMessage(routingUpdate, excludeNearbyIds: [nearbyId]);
  }

  Future<void> _sendReachabilityCheck(String endpointId, String targetDeviceId,
      String originalMessageId) async {
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

  Future<bool> isMessageProcessed(String messageId) async {
    if (_processedMessageIds.contains(messageId)) {
      return true;
    }

    return await _databaseService.doesMessageExist(messageId);
  }

  String get userInfo => _userInfo ?? 'Unknown user';
  List<String> get connectedEndpoints => List.unmodifiable(_connectedEndpoints);
}
