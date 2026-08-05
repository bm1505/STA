// lib/services/sqflite_stub.dart
// Hili faili linazuia kosa la "MissingPluginException" unapokimbiza app kwenye Chrome (Web)

class ConflictAlgorithm {
  static const replace = 1;
  static const abort = 2;
  static const fail = 3;
  static const ignore = 4;
  static const rollback = 5;
}

Future<dynamic> openDatabase(String path, {int? version, Function? onCreate, Function? onUpgrade}) async {
  // Kwenye Web hatufungui SQLite, tunarudisha null
  return null; 
}

Future<String> getDatabasesPath() async => "";
