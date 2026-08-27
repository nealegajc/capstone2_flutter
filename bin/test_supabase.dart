import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  const url = 'https://nnuzffushaaaxjmrreiv.supabase.co';
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5udXpmZnVzaGFhYXhqbXJyZWl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1MTM3MzksImV4cCI6MjEwMzA4OTczOX0.QnxiNJfw5-xE45lFZf4V8CPeUyl68cLjSv944zJQ_-c';

  final supabase = SupabaseClient(url, anonKey);

  print('Testing connection to Supabase...');
  try {
    final res = await supabase.from('products').select().limit(5);
    print('Products in table: ${res.length}');
  } catch (e) {
    print('Error selecting products: $e');
  }

  try {
    print('Trying to insert a test product with basic columns...');
    await supabase.from('products').upsert({
      'id': 'prod_test_AA1',
      'perfume_code': 'AA1',
      'name': 'Bvlgari Extreme',
      'brand': 'Bvlgari',
      'category': 'Men',
      'bottle_size': '100ml',
      'price': 0.0,
      'status': 'active',
    });
    print('Successfully inserted prod_test_AA1!');
  } catch (e) {
    print('Error inserting product: $e');
  }

  try {
    print('Trying to insert with shelf_layer...');
    await supabase.from('products').upsert({
      'id': 'prod_test_AA2',
      'perfume_code': 'AA2',
      'name': 'Bvlgari Extreme',
      'brand': 'Bvlgari',
      'category': 'Men',
      'bottle_size': '50ml',
      'shelf_layer': 'Layer A (Top)',
      'slot_position': 1,
      'catalog_number': '#1',
      'price': 0.0,
      'status': 'active',
    });
    print('Successfully inserted prod_test_AA2 with extra columns!');
  } catch (e) {
    print('Error inserting with extra columns: $e');
  }

  exit(0);
}
