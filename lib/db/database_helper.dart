import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/incidente_local.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const boolType = 'BOOLEAN NOT NULL';

    await db.execute('''
CREATE TABLE incidentes (
  id $idType,
  coordenadagps $textType,
  descripcion $textNullable,
  fecha $textType,
  estado $textType,
  is_synced $boolType,
  vehiculo_id INTEGER,
  fotos_base64 $textNullable,
  audio_base64 $textNullable
)
''');

    await db.execute('''
CREATE TABLE pending_profile_updates (
  id $idType,
  payload TEXT NOT NULL,
  fecha TEXT NOT NULL,
  is_synced $boolType
)
''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE incidentes ADD COLUMN vehiculo_id INTEGER');
      await db.execute('ALTER TABLE incidentes ADD COLUMN fotos_base64 TEXT');
      await db.execute('ALTER TABLE incidentes ADD COLUMN audio_base64 TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS pending_profile_updates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payload TEXT NOT NULL,
  fecha TEXT NOT NULL,
  is_synced BOOLEAN NOT NULL
)
''');
    }
  }

  Future<IncidenteLocal> create(IncidenteLocal incidente) async {
    final db = await instance.database;
    final id = await db.insert('incidentes', incidente.toMap());
    return incidente.copyWith(id: id);
  }

  Future<List<IncidenteLocal>> readAllUnsyncedIncidentes() async {
    final db = await instance.database;
    final result = await db.query(
      'incidentes',
      where: 'is_synced = ?',
      whereArgs: [0],
    );

    return result.map((json) => IncidenteLocal.fromMap(json)).toList();
  }

  Future<List<IncidenteLocal>> readAllIncidentesLocales() async {
    final db = await instance.database;
    final result = await db.query(
      'incidentes',
      orderBy: 'id DESC',
    );
    return result.map((json) => IncidenteLocal.fromMap(json)).toList();
  }

  Future<int> update(IncidenteLocal incidente) async {
    final db = await instance.database;
    return db.update(
      'incidentes',
      incidente.toMap(),
      where: 'id = ?',
      whereArgs: [incidente.id],
    );
  }

  Future<void> markAsSynced(int id) async {
    final db = await instance.database;
    await db.update(
      'incidentes',
      {
        'is_synced': 1,
        'estado': 'Sincronizado',
        'fotos_base64': null, // Liberar memoria después de sincronizar
        'audio_base64': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteIncidente(int id) async {
    final db = await instance.database;
    await db.delete(
      'incidentes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countUnsyncedIncidentes() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM incidentes WHERE is_synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ─── PROFILE UPDATE QUEUE ─────────────────────────────────────

  Future<int> createPendingProfileUpdate(String payloadJson) async {
    final db = await instance.database;
    return await db.insert('pending_profile_updates', {
      'payload': payloadJson,
      'fecha': DateTime.now().toIso8601String(),
      'is_synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> readUnsyncedProfileUpdates() async {
    final db = await instance.database;
    return await db.query(
      'pending_profile_updates',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
  }

  Future<void> markProfileUpdateSynced(int id) async {
    final db = await instance.database;
    await db.update(
      'pending_profile_updates',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteProfileUpdate(int id) async {
    final db = await instance.database;
    await db.delete(
      'pending_profile_updates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countUnsyncedProfileUpdates() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM pending_profile_updates WHERE is_synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
