// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final url = env['SUPABASE_URL']!;
  final anonKey = env['SUPABASE_ANON_KEY']!;

  final client = HttpClient();

  for (final table in ['products', 'shelf_regions', 'inventory_records']) {
    final req = await client.getUrl(Uri.parse('$url/rest/v1/$table?select=*'));
    req.headers.set('apikey', anonKey);
    req.headers.set('Authorization', 'Bearer $anonKey');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List;
    print('Table "$table": ${list.length} rows verified in Supabase!');
  }

  exit(0);
}

/// Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the project `.env` file.
Map<String, String> _loadEnv() {
  final file = File('.env');
  if (!file.existsSync()) {
    stderr.writeln('Missing .env file. Run this script from the project root.');
    exit(1);
  }
  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) {
      continue;
    }
    final idx = trimmed.indexOf('=');
    env[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
  }
  for (final key in ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    if (env[key] == null || env[key]!.isEmpty) {
      stderr.writeln('Missing $key in .env');
      exit(1);
    }
  }
  return env;
}
