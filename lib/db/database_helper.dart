import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/detection_event.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'rephone_security.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE detection_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER,
        image_path TEXT,
        video_path TEXT
      )
    ''');
  }

  Future<int> insertEvent(DetectionEvent event) async {
    Database db = await database;
    return await db.insert('detection_events', event.toMap());
  }

  Future<List<DetectionEvent>> getEvents({int? limit, int? offset}) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'detection_events', 
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) {
      return DetectionEvent.fromMap(maps[i]);
    });
  }

  Future<DetectionEvent?> getEventById(int id) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'detection_events',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return DetectionEvent.fromMap(maps.first);
    }
    return null;
  }
}
