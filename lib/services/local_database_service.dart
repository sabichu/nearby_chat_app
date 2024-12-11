import 'dart:async';
import 'package:nearby_chat_app/models/device.dart';
import 'package:nearby_chat_app/models/message.dart';
import 'package:nearby_chat_app/models/routing_entry.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
  static Database? _database;

  LocalDatabaseService._internal();

  factory LocalDatabaseService() => _instance;

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  Stream<List<Device>> get deviceStream {
    _deviceStreamController.sink.add([]);
    _emitDeviceChanges();
    return _deviceStreamController.stream;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'app_database.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL UNIQUE,
        local_id  TEXT NOT NULL,
        user_name TEXT,
        model_name TEXT,
        is_connected INTEGER NOT NULL CHECK(is_connected IN (0, 1)),
        last_seen_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL UNIQUE,
        message_type TEXT NOT NULL CHECK (message_type IN ('NORMAL', 'ACK', 'ROUTING_UPDATE')),
        sender_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
        receiver_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
        content TEXT NOT NULL,
        hops INTEGER NOT NULL DEFAULT 0,
        ttl INTEGER NOT NULL DEFAULT 10,
        status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'DELIVERED', 'READ', 'FORWARDED')),
        sent_at INTEGER NOT NULL,
        read_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS routing_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        destination_id TEXT NOT NULL,
        next_hop_id TEXT NOT NULL,
        distance INTEGER NOT NULL CHECK (distance >= 0),
        last_updated_at INTEGER NOT NULL,
        FOREIGN KEY(destination_id) REFERENCES devices(device_id),
        FOREIGN KEY(next_hop_id) REFERENCES devices(device_id)
      )
    ''');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _deviceStreamController.close();
  }

  Future<int> insertMessage(Message message) async {
    final db = await database;
    return await db.insert('messages', message.toMap());
  }

  Future<List<Message>> getAllMessages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('messages');
    return List.generate(maps.length, (i) => Message.fromMap(maps[i]));
  }

  Future<List<Message>> loadMessages(String deviceId) async {
    if (_database == null) {
      throw Exception("Database not initialized");
    }

    final result = await _database!.rawQuery(
      '''
      SELECT * FROM messages
      WHERE sender_id = ? OR receiver_id = ?
      ORDER BY sent_at ASC
      ''',
      [deviceId, deviceId],
    );

    return result.map((row) => Message.fromMap(row)).toList();
  }

  Future<Map<String, int>> getUnreadMessagesCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT receiver_id, COUNT(*) as unread_count
      FROM messages
      WHERE status != 'READ'
      GROUP BY receiver_id
    ''');
    
    // Transformar el resultado en un Map<String, int>
    return { 
      for (var row in result) row['receiver_id'] as String: row['unread_count'] as int 
    };
  }

  Future<void> markMessagesAsRead(String deviceId) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': 'READ', 'read_at': DateTime.now().millisecondsSinceEpoch},
      where: 'receiver_id = ? AND status != ?',
      whereArgs: [deviceId, 'READ'],
    );
  }

  Future<int> updateMessageStatus(String messageId, String status) async {
    final db = await database;
    return await db.update(
      'messages',
      {'status': status},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<int> deleteMessage(String messageId) async {
    final db = await database;
    return await db.delete(
      'messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<int> insertRoutingEntry(RoutingEntry entry) async {
    final db = await database;
    return await db.insert('routing_table', entry.toMap());
  }

  Future<List<RoutingEntry>> getAllRoutingEntries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('routing_table');
    return List.generate(maps.length, (i) => RoutingEntry.fromMap(maps[i]));
  }

  Future<RoutingEntry?> getRoutingEntry(String localId) async {
    final nearbyId = await getNearbyIdFromLocalId(localId);

    if (nearbyId == null) {
      print("No se encontró un ID de Nearby para el local ID $localId.");
      return null;
    }

    final db = await database;
    try {
      final List<Map<String, dynamic>> result = await db.query(
        'routing_table',
        where: 'destination_id = ?',
        whereArgs: [nearbyId],
      );

      if (result.isNotEmpty) {
        return RoutingEntry.fromMap(result.first);
      }
      return null;
    } catch (e) {
      print("Error al obtener la ruta para el destino $nearbyId: $e");
      return null;
    }
  }

  Future<int> updateRoutingEntry(
      String destinationId, String nextHopId, int distance) async {
    final db = await database;
    return await db.update(
      'routing_table',
      {'next_hop_id': nextHopId, 'distance': distance},
      where: 'destination_id = ?',
      whereArgs: [destinationId],
    );
  }

  Future<int> deleteRoutingEntry(String destinationId) async {
    final db = await database;
    return await db.delete(
      'routing_table',
      where: 'destination_id = ?',
      whereArgs: [destinationId],
    );
  }

  Future<int> insertDevice(Device device) async {
    final db = await database;
    int result = await db.insert('devices', device.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _emitDeviceChanges();
    return result;
  }

  Future<String?> getNearbyIdFromLocalId(String localId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> result = await db.query(
        'devices',
        columns: ['device_id'],
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      if (result.isNotEmpty) {
        return result.first['device_id'] as String;
      }
      return null;
    } catch (e) {
      print("Error al obtener el ID de Nearby para el local ID $localId: $e");
      return null;
    }
  }

  Future<List<Device>> getAllDevices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('devices');
    return List.generate(maps.length, (i) => Device.fromMap(maps[i]));
  }

  Future<List<Device>> getAllConnectedDevices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query('devices', where: 'is_connected = 1');
    return List.generate(maps.length, (i) => Device.fromMap(maps[i]));
  }

  Future<int> updateDeviceStatus(String deviceId, bool isConnected) async {
    final db = await database;
    int result = await db.update(
      'devices',
      {'is_connected': isConnected ? 1 : 0},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    _emitDeviceChanges();
    return result;
  }

  Future<int> resetAllDeviceStatuses() async {
    final db = await database;
    int result = await db.update(
      'devices',
      {'is_connected': 0},
    );
    _emitDeviceChanges();
    return result;
  }

  Future<int> deleteDevice(String deviceId) async {
    final db = await database;
    int result = await db.delete(
      'devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    _emitDeviceChanges();
    return result;
  }

  void _emitDeviceChanges() async {
    List<Device> connectedDevices = await getAllConnectedDevices();
    _deviceStreamController.add(connectedDevices);
  }
}
