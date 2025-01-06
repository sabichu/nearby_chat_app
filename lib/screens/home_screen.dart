import 'package:flutter/material.dart';
import 'package:nearby_chat_app/screens/chat_screen.dart';
import 'package:nearby_chat_app/services/local_database_service.dart';
import 'package:nearby_chat_app/services/nearby_service_manager.dart';
import 'package:nearby_chat_app/widgets/user_card.dart';
import 'package:nearby_chat_app/models/device.dart';

class HomeScreen extends StatefulWidget {
  final String userName;

  HomeScreen({required this.userName});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocalDatabaseService _databaseService = LocalDatabaseService();
  final NearbyServiceManager _nearbyServiceManager = NearbyServiceManager();
  Map<String, int> _unreadMessages = {};

  @override
  void initState() {
    super.initState();
    _initializeNearbyService();
    _listenToUnreadMessages();
  }

  Future<void> _initializeNearbyService() async {
    await _nearbyServiceManager.initialize(userName: widget.userName);
  }

  void _listenToUnreadMessages() {
    _nearbyServiceManager.unreadMessagesStream.listen((unreadCounts) {
      setState(() {
        _unreadMessages = unreadCounts;
      });
    });
  }

  Future<void> _restartNearbyServices() async {
    try {
      await _nearbyServiceManager.restartServices();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nearby services restarted'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Chats',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    color: Colors.white,
                    icon: Icon(Icons.restart_alt),
                    iconSize: 32,
                    onPressed: _restartNearbyServices,
                  )
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<List<Device>>(
                  stream: _databaseService.deviceStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'Error loading devices',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    final devices = snapshot.data;

                    if (devices == null || devices.isEmpty) {
                      return const Center(
                        child: Text(
                          'No connected devices',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final unreadCount =
                            _unreadMessages[device.localId] ?? 0;

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                userId: device.localId,
                                userName: device.userName,
                              ),
                            ),
                          ).then((_) {
                            _nearbyServiceManager
                                .resetUnreadMessages(device.localId);
                          }),
                          child: UserCard(
                            userId: device.localId,
                            userName: device.userName,
                            deviceName: device.modelName,
                            unreadMessages: unreadCount,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
