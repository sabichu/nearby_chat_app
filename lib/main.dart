import 'package:flutter/material.dart';
import 'package:nearby_chat_app/screens/user_name_screen.dart';
import 'package:nearby_chat_app/services/nearby_service_manager.dart';
import 'package:nearby_chat_app/services/local_database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LocalDatabaseService localDatabaseService = LocalDatabaseService();
  await localDatabaseService.database;

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final NearbyServiceManager nearbyServiceManager = NearbyServiceManager();

  /*
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await nearbyServiceManager.initialize();
  }
  */

  @override
  void dispose() {
    nearbyServiceManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nearby Chat App',
      home: UserNameScreen(),
    );
  }
}
