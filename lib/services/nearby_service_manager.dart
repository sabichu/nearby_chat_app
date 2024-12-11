import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
  final Map<String, String> _discoveredEndpoints = {};
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

  Future<void> initialize({required String userName}) async {
    if (_isInitialized) return;
    _isInitialized = true;

    resetDeviceStatuses();

    await _initializeDeviceInfo();
    _generateUserInfo(userName);

    if (!await _requestPermissions()) {
      throw Exception("No se concedieron todos los permisos necesarios.");
    }

    _startAdvertising();
    _startDiscovery();
  }

  Future<void> resetDeviceStatuses() async {
    await _databaseService.resetAllDeviceStatuses();
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
      bool advertising = await Nearby().startAdvertising(
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
      print('Error al iniciar Advertising: $e');
    }
  }

  void _startDiscovery() async {
    try {
      bool discovering = await Nearby().startDiscovery(
        userInfo,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          _handleEndpointFound(id, name);
        },
        onEndpointLost: (id) {},
      );
    } catch (e) {
      print('Error al iniciar Discovery: $e');
    }
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
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
            onMessageReceived(receivedMessage);
          } catch (e) {
            print("Error al procesar el mensaje recibido: $e");
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

    Device device = Device(
        deviceId: id,
        localId: info.endpointName.split('|')[0],
        userName: info.endpointName.split('|')[1],
        modelName:
            '${info.endpointName.split('|')[2]} ${info.endpointName.split('|')[3]}',
        isConnected: true,
        lastSeenAt: DateTime.now().millisecondsSinceEpoch);

    _databaseService.insertDevice(device);
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
    await _databaseService.updateDeviceStatus(id, false);
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

  Future<void> sendMessage(Message message) async {
    try {
      message.incrementHops();

      if (message.isExpired()) {
        throw Exception("El mensaje ha expirado (TTL agotado).");
      }

      final route = await _databaseService.getRoutingEntry(message.receiverId);
      if (route == null) {
        throw Exception("No se encontró una ruta hacia el destinatario.");
      }

      final nextHopId = route.nextHopId;

      final payloadBytes = message.toBytes();

      await Nearby().sendBytesPayload(nextHopId, payloadBytes);

      print("Mensaje enviado a $nextHopId (destino final: ${message.receiverId})");

      message.updateStatus('SENT');
      await _databaseService.updateMessageStatus(message.messageId, 'SENT');
    } catch (e) {
      print("Error al enviar mensaje: $e");

      message.updateStatus('ERROR');
      await _databaseService.updateMessageStatus(message.messageId, 'ERROR');
    }
  }

  String get userInfo => _userInfo ?? "User desconocido";
  List<String> get connectedEndpoints => List.unmodifiable(_connectedEndpoints);
  Map<String, String> get discoveredEndpoints =>
      Map.unmodifiable(_discoveredEndpoints);
}
