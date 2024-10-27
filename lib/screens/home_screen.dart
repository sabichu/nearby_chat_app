import 'package:flutter/material.dart';
import 'package:nearby_chat_app/widgets/user_card.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String userName = 'User${Random().nextInt(1000)}';
  final Strategy strategy = Strategy.P2P_CLUSTER;
  //final Map<String, ConnectionInfo> endpointMap = {};

  final Map<String, String> discoveredEndpoints = {};
  final Set<String> connectedEndpoints = {};

  StreamSubscription? discoverySubscription;

  @override
  void initState() {
    super.initState();

    _requestPermissions().then((_) {
      _startAdvertising();
      _startDiscovery();
    });
  }

  @override
  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    discoverySubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      //Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      //_showSnackbar('No se concedieron todos los permisos necesarios.');
    }
  }

  void _startAdvertising() async {
    try {
      bool advertising = await Nearby().startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            setState(() {
              connectedEndpoints.add(id);
            });
            //_showSnackbar('Conectado con $id');
          } else {
            //_showSnackbar('Error de conexión con $id: $status');
          }
        },
        onDisconnected: (id) {
          setState(() {
            connectedEndpoints.remove(id);
          });
          //_showSnackbar('Desconectado de $id');
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
        userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          setState(() {
            discoveredEndpoints[id] = name;
          });
          _connectToDevice(id);
        },
        onEndpointLost: (id) {
          setState(() {
            discoveredEndpoints.remove(id);
          });
        },
      );
      //_showSnackbar('Discovery iniciado: $discovering');
    } catch (e) {
      //_showSnackbar('Error al iniciar Discovery: $e');
    }
  }

  void _onConnectionInit(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endid, payload) {
        if (payload.type == PayloadType.BYTES) {
          String message = String.fromCharCodes(payload.bytes!);
          //_showSnackbar('Mensaje de $endid: $message');
        }
      },
      onPayloadTransferUpdate: (endid, payloadTransferUpdate) {
        // Manejar actualizaciones de transferencia de payload si es necesario
      },
    );
  }

  void _connectToDevice(String id) {
    Nearby().requestConnection(
      userName,
      id,
      onConnectionInitiated: _onConnectionInit,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() {
            connectedEndpoints.add(id);
            discoveredEndpoints.remove(id);
          });
          //_showSnackbar('Conectado con $id');
        } else {
          //_showSnackbar('Error de conexión con $id: $status');
        }
      },
      onDisconnected: (id) {
        setState(() {
          connectedEndpoints.remove(id);
        });
        //_showSnackbar('Desconectado de $id');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chats',
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(
                height: 8,
              ),
              Expanded(
                child: ListView(
                  children: [
                    UserCard(
                        userName: 'Sabi Singh', deviceName: 'iPhone 13 Pro Max')
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
