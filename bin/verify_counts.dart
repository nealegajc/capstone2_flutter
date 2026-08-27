import 'dart:convert';
import 'dart:io';

void main() async {
  const url = 'https://nnuzffushaaaxjmrreiv.supabase.co';
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5udXpmZnVzaGFhYXhqbXJyZWl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1MTM3MzksImV4cCI6MjEwMzA4OTczOX0.QnxiNJfw5-xE45lFZf4V8CPeUyl68cLjSv944zJQ_-c';

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
