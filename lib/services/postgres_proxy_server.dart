import 'dart:io';
import 'dart:typed_data';
import 'package:postgres/postgres.dart';

void main() async {
  print('--- STA PROXY (ULTRA STABLE V20) ---');
  Connection? conn;
  try {
    conn = await Connection.open(
      Endpoint(host: 'localhost', database: 'sta_db', username: 'postgres', password: '150520'),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    print('✅ DB CONNECTED');
  } catch (e) {
    print('❌ DB ERROR: $e');
    return;
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, 3000);
  print('🚀 PROXY RUNNING ON http://localhost:3000');

  await for (HttpRequest request in server) {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');
    request.response.headers.add('Cross-Origin-Resource-Policy', 'cross-origin');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      continue;
    }

    final userId = request.uri.queryParameters['userId']?.trim() ?? "";
    final fileType = request.uri.queryParameters['type']?.trim().toLowerCase() ?? "";

    try {
      if (request.uri.path == '/upload') {
        final bytes = await request.fold<List<int>>([], (p, e) => p..addAll(e));
        final uid = request.headers.value('x-user-id') ?? "";
        final type = request.headers.value('x-file-type') ?? "";
        
        if (uid.isNotEmpty) {
           await conn.execute(
            r"INSERT INTO user_files (user_id, file_type, file_data) VALUES ($1, $2, $3)",
            parameters: [uid, type, Uint8List.fromList(bytes)],
          );
          print('✅ UPLOADED: $uid ($type)');
          request.response.statusCode = 200;
        } else {
          request.response.statusCode = 400;
        }
        await request.response.close();
        continue;
      }

      if (userId.isEmpty) {
        request.response.statusCode = 400;
        await request.response.close();
        continue;
      }

      print('🔍 FETCHING: "$userId" type: "$fileType"');

      // Tumia LOWER() kuhakikisha inapata hata kama kule kwenye DB kuna herufi kubwa
      Result result;
      if (fileType.isNotEmpty) {
        result = await conn.execute(
          r"SELECT file_data FROM user_files WHERE TRIM(user_id) = $1 AND LOWER(file_type) LIKE $2 ORDER BY created_at DESC LIMIT 1",
          parameters: [userId, "%$fileType%"],
        );
      } else {
        result = await conn.execute(
          r"SELECT file_data FROM user_files WHERE TRIM(user_id) = $1 ORDER BY created_at DESC LIMIT 1",
          parameters: [userId],
        );
      }

      if (result.isNotEmpty) {
        final bytes = result.first[0] as Uint8List;
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.headers.contentLength = bytes.length;
        request.response.add(bytes);
        print('✅ SENT: $userId - $fileType (${bytes.length} bytes)');
      } else {
        print('❌ NOT FOUND: $userId - $fileType');
        request.response.statusCode = 404;
      }
    } catch (e) {
      print('❌ ERROR: $e');
      request.response.statusCode = 500;
    }
    await request.response.close();
  }
}
