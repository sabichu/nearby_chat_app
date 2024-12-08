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

  @override
  void initState() {
    super.initState();
    _initializeNearbyService();
  }

  Future<void> _initializeNearbyService() async {
    await _nearbyServiceManager.initialize(userName: widget.userName);
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
                  color: Colors.white,
                ),
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
                        Device device = devices[index];

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                      userId: device.localId,
                                      userName: device.userName,
                                    )),
                          ),
                          child: UserCard(
                              userId: device.localId,
                              userName: device.userName,
                              deviceName: device.modelName),
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
