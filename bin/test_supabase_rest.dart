import 'dart:convert';
import 'dart:io';

void main() async {
  const url = 'https://nnuzffushaaaxjmrreiv.supabase.co';
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5udXpmZnVzaGFhYXhqbXJyZWl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1MTM3MzksImV4cCI6MjEwMzA4OTczOX0.QnxiNJfw5-xE45lFZf4V8CPeUyl68cLjSv944zJQ_-c';

  final client = HttpClient();

  print('1. Checking connection to Supabase /rest/v1/products ...');
  final req = await client.getUrl(Uri.parse('$url/rest/v1/products?select=*&limit=5'));
  req.headers.set('apikey', anonKey);
  req.headers.set('Authorization', 'Bearer $anonKey');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  print('Status code: ${res.statusCode}');
  print('Response: $body');

  print('\n2. Checking table inventory_records ...');
  final req2 = await client.getUrl(Uri.parse('$url/rest/v1/inventory_records?select=*&limit=5'));
  req2.headers.set('apikey', anonKey);
  req2.headers.set('Authorization', 'Bearer $anonKey');
  final res2 = await req2.close();
  final body2 = await res2.transform(utf8.decoder).join();
  print('Status code: ${res2.statusCode}');
  print('Response: $body2');

  print('\n3. Checking table shelf_regions ...');
  final req3 = await client.getUrl(Uri.parse('$url/rest/v1/shelf_regions?select=*&limit=5'));
  req3.headers.set('apikey', anonKey);
  req3.headers.set('Authorization', 'Bearer $anonKey');
  final res3 = await req3.close();
  final body3 = await res3.transform(utf8.decoder).join();
  print('Status code: ${res3.statusCode}');
  print('Response: $body3');

  exit(0);
}
