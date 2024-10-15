import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nearby Connections Demo',
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String userName = 'User${Random().nextInt(1000)}';
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final Map<String, ConnectionInfo> endpointMap = {};

  final Map<String, String> discoveredEndpoints = {}; // id: name
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
      Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      _showSnackbar('No se concedieron todos los permisos necesarios.');
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
            _showSnackbar('Conectado con $id');
          } else {
            _showSnackbar('Error de conexión con $id: $status');
          }
        },
        onDisconnected: (id) {
          setState(() {
            connectedEndpoints.remove(id);
          });
          _showSnackbar('Desconectado de $id');
        },
      );
      _showSnackbar('Advertising iniciado: $advertising');
    } catch (e) {
      _showSnackbar('Error al iniciar Advertising: $e');
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
        },
        onEndpointLost: (id) {
          setState(() {
            discoveredEndpoints.remove(id);
          });
        },
      );
      _showSnackbar('Discovery iniciado: $discovering');
    } catch (e) {
      _showSnackbar('Error al iniciar Discovery: $e');
    }
  }

  void _onConnectionInit(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endid, payload) {
        if (payload.type == PayloadType.BYTES) {
          String message = String.fromCharCodes(payload.bytes!);
          _showSnackbar('Mensaje de $endid: $message');
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
          _showSnackbar('Conectado con $id');
        } else {
          _showSnackbar('Error de conexión con $id: $status');
        }
      },
      onDisconnected: (id) {
        setState(() {
          connectedEndpoints.remove(id);
        });
        _showSnackbar('Desconectado de $id');
      },
    );
  }

  void _disconnectFromDevice(String id) {
    Nearby().disconnectFromEndpoint(id);
    setState(() {
      connectedEndpoints.remove(id);
    });
    _showSnackbar('Desconectado de $id');
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildDeviceList() {
    List<Widget> deviceWidgets = [];

    deviceWidgets.add(
      const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          'Dispositivos descubiertos:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
    );

    if (discoveredEndpoints.isEmpty) {
      deviceWidgets.add(const ListTile(
        title: Text('No se han encontrado dispositivos.'),
      ));
    } else {
      discoveredEndpoints.forEach((id, name) {
        deviceWidgets.add(
          ListTile(
            title: Text(name),
            subtitle: Text('ID: $id'),
            trailing: ElevatedButton(
              onPressed: () => _connectToDevice(id),
              child: const Text('Conectar'),
            ),
          ),
        );
      });
    }

    deviceWidgets.add(const Divider());

    deviceWidgets.add(
      const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          'Dispositivos conectados:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
    );

    if (connectedEndpoints.isEmpty) {
      deviceWidgets.add(const ListTile(
        title: Text('No hay dispositivos conectados.'),
      ));
    } else {
      connectedEndpoints.forEach((id) {
        String name = discoveredEndpoints[id] ?? 'Desconocido';
        deviceWidgets.add(
          ListTile(
            title: Text(name),
            subtitle: Text('ID: $id'),
            trailing: ElevatedButton(
              onPressed: () => _disconnectFromDevice(id),
              child: const Text('Desconectar'),
            ),
          ),
        );
      });
    }

    return ListView(children: deviceWidgets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nearby Connections - $userName'),
      ),
      body: _buildDeviceList(),
    );
  }
}
