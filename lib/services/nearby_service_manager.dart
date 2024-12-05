import 'dart:async';
import 'dart:io';
import 'dart:math';
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

            //_showSnackbar('Conectado con $id');
          } else {
            //_showSnackbar('Error de conexión con $id: $status');
          }
        },
        onDisconnected: (id) {
          _connectedEndpoints.remove(id);
          //_showSnackbar('Desconectado de $id');
          _onDisconnected(id);
        },
      );
      //_showSnackbar('Advertising iniciado: $advertising');
    } catch (e) {
      //_showSnackbar('Error al iniciar Advertising: $e');
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
      //_showSnackbar('Discovery iniciado: $discovering');
    } catch (e) {
      //_showSnackbar('Error al iniciar Discovery: $e');
    }
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    if (_connectedEndpoints.contains(id)) {
      print("Ya conectado con $id. Rechazando conexión.");
      Nearby().rejectConnection(id);
      return;
    }

    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endid, payload) {
        if (payload.type == PayloadType.BYTES) {
          try {
            Message receivedMessage = Message.fromBytes(payload.bytes!);
            _saveMessageToDatabase(receivedMessage);
          } catch (e) {
            print("Error al procesar el mensaje recibido: $e");
          }
        }
      },
    );

    //if (connectedEndpoints.contains(id)) {
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
    //}
  }

  void _handleEndpointFound(String remoteEndpointId, String remoteUserInfo) {
    final String remoteId = remoteUserInfo.split('|')[0];
    final String localId = userInfo.split('|')[0];

    print('remoto id: ${remoteId}');
    print('local id: ${localId}');

    if (localId.compareTo(remoteId) < 0) {
      print("Este dispositivo inicia la conexión con $remoteEndpointId.");
      _connectToDevice(remoteEndpointId);
    } else {
      print("Esperando que $remoteEndpointId inicie la conexión.");
    }
  }

  void _connectToDevice(String id) {
    if (_connectedEndpoints.contains(id)) {
      print("Ya estamos conectados con $id. Conexión ignorada.");
      return;
    }

    Nearby().requestConnection(
      userInfo,
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          _connectedEndpoints.add(id);
          //_showSnackbar('Conectado con $id');
        } else {
          //_showSnackbar('Error de conexión con $id: $status');
        }
      },
      onDisconnected: (id) {
        _connectedEndpoints.remove(id);
        //_showSnackbar('Desconectado de $id');
        _onDisconnected(id);
      },
    );
  }

  void _onDisconnected(String id) async {
    await _databaseService.updateDeviceStatus(id, false);
  }

  Future<void> _saveMessageToDatabase(Message message) async {
    try {
      await _databaseService.insertMessage(message);
      print("Mensaje recibido y guardado en la base de datos");
    } catch (e) {
      print("Error al guardar el mensaje en la base de datos: $e");
    }
  }

  String get userInfo => _userInfo ?? "User desconocido";
  List<String> get connectedEndpoints => List.unmodifiable(_connectedEndpoints);
  Map<String, String> get discoveredEndpoints =>
      Map.unmodifiable(_discoveredEndpoints);
}
