import 'dart:convert';
import 'dart:io';

void main() async {
  const url = 'https://nnuzffushaaaxjmrreiv.supabase.co';
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5udXpmZnVzaGFhYXhqbXJyZWl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1MTM3MzksImV4cCI6MjEwMzA4OTczOX0.QnxiNJfw5-xE45lFZf4V8CPeUyl68cLjSv944zJQ_-c';

  final client = HttpClient();

  // 1. All 30 fragrance variants (15 Men, 15 Women)
  final maleVariants = [
    {'codePrefix': 'A', 'name': 'Bvlgari Extreme', 'brand': 'Bvlgari', 'layer': 'Layer A (Top)', 'slot': 1},
    {'codePrefix': 'B', 'name': 'Bvlgari Aqua', 'brand': 'Bvlgari', 'layer': 'Layer A (Top)', 'slot': 2},
    {'codePrefix': 'C', 'name': 'Clinique Happy Men', 'brand': 'Clinique', 'layer': 'Layer A (Top)', 'slot': 3},
    {'codePrefix': 'D', 'name': 'Christian Dior Sauvage', 'brand': 'Christian Dior', 'layer': 'Layer A (Top)', 'slot': 4},
    {'codePrefix': 'E', 'name': 'Ralph Lauren Polo Black', 'brand': 'Ralph Lauren', 'layer': 'Layer A (Top)', 'slot': 5},
    {'codePrefix': 'F', 'name': 'Davidoff Cool Water', 'brand': 'Davidoff', 'layer': 'Layer A (Top)', 'slot': 6},
    {'codePrefix': 'G', 'name': 'Ralph Lauren Polo Red', 'brand': 'Ralph Lauren', 'layer': 'Layer A (Top)', 'slot': 7},
    {'codePrefix': 'H', 'name': 'Lacoste Black', 'brand': 'Lacoste', 'layer': 'Layer A (Top)', 'slot': 8},
    {'codePrefix': 'J', 'name': 'Hugo Boss', 'brand': 'Hugo Boss', 'layer': 'Layer A (Top)', 'slot': 9},
    {'codePrefix': 'K', 'name': 'Lacoste Essential', 'brand': 'Lacoste', 'layer': 'Layer A (Top)', 'slot': 10},
    // Middle Layer Male Scents
    {'codePrefix': 'A', 'name': 'Lacoste Red', 'brand': 'Lacoste', 'layer': 'Layer B (Middle)', 'slot': 1},
    {'codePrefix': 'B', 'name': 'Lacoste White', 'brand': 'Lacoste', 'layer': 'Layer B (Middle)', 'slot': 2},
    {'codePrefix': 'C', 'name': 'Paco Rabanne Invictus', 'brand': 'Paco Rabanne', 'layer': 'Layer B (Middle)', 'slot': 3},
    {'codePrefix': 'D', 'name': 'Ralph Lauren Polo Sport', 'brand': 'Ralph Lauren', 'layer': 'Layer B (Middle)', 'slot': 4},
    {'codePrefix': 'E', 'name': 'Tommy Boy', 'brand': 'Tommy Hilfiger', 'layer': 'Layer B (Middle)', 'slot': 5},
  ];

  final femaleVariants = [
    // Middle Layer Female Scents
    {'codePrefix': 'F', 'name': 'Chanel Chance', 'brand': 'Chanel', 'layer': 'Layer B (Middle)', 'slot': 6},
    {'codePrefix': 'G', 'name': 'Chanel No.5', 'brand': 'Chanel', 'layer': 'Layer B (Middle)', 'slot': 7},
    {'codePrefix': 'H', 'name': 'Clinique Happy Women', 'brand': 'Clinique', 'layer': 'Layer B (Middle)', 'slot': 8},
    {'codePrefix': 'J', 'name': 'Escada Moon Sparkle', 'brand': 'Escada', 'layer': 'Layer B (Middle)', 'slot': 9},
    {'codePrefix': 'K', 'name': 'DKNY Be Delicious', 'brand': 'DKNY', 'layer': 'Layer B (Middle)', 'slot': 10},
    // Bottom Layer Female Scents
    {'codePrefix': 'A', 'name': 'D&G Light Blue Women', 'brand': 'Dolce & Gabbana', 'layer': 'Layer C (Bottom)', 'slot': 1},
    {'codePrefix': 'B', 'name': 'Elizabeth Arden Green Tea', 'brand': 'Elizabeth Arden', 'layer': 'Layer C (Bottom)', 'slot': 2},
    {'codePrefix': 'C', 'name': 'Chanel Coco', 'brand': 'Chanel', 'layer': 'Layer C (Bottom)', 'slot': 3},
    {'codePrefix': 'D', 'name': 'Estee Lauder Pleasures', 'brand': 'Estee Lauder', 'layer': 'Layer C (Bottom)', 'slot': 4},
    {'codePrefix': 'E', 'name': 'Ferragamo Incanto', 'brand': 'Salvatore Ferragamo', 'layer': 'Layer C (Bottom)', 'slot': 5},
    {'codePrefix': 'F', 'name': 'Jo Malone Mimosa & Cardamom', 'brand': 'Jo Malone', 'layer': 'Layer C (Bottom)', 'slot': 6},
    {'codePrefix': 'G', 'name': 'Ralph Lauren Romance', 'brand': 'Ralph Lauren', 'layer': 'Layer C (Bottom)', 'slot': 7},
    {'codePrefix': 'H', 'name': 'Lancome La Vie Est Belle', 'brand': 'Lancome', 'layer': 'Layer C (Bottom)', 'slot': 8},
    {'codePrefix': 'J', 'name': 'Lanvin Eclat D\'Arpege', 'brand': 'Lanvin', 'layer': 'Layer C (Bottom)', 'slot': 9},
    {'codePrefix': 'K', 'name': 'Tommy Girl', 'brand': 'Tommy Hilfiger', 'layer': 'Layer C (Bottom)', 'slot': 10},
  ];

  final List<Map<String, dynamic>> products = [];
  final List<Map<String, dynamic>> inventory = [];

  // Generate 60 SKUs
  for (final v in [...maleVariants, ...femaleVariants]) {
    final layerCode = (v['layer'] as String).contains('Layer A') ? 'A' : ((v['layer'] as String).contains('Layer B') ? 'B' : 'C');
    final isMale = (v['layer'] as String).contains('Layer A') || ((v['layer'] as String).contains('Layer B') && (v['slot'] as int) <= 5);
    final category = isMale ? 'Men' : 'Women';
    final slotCode = v['codePrefix'] as String;

    // 100ML (Size 1)
    final code100 = '$layerCode${slotCode}1';
    products.add({
      'id': 'prod_$code100',
      'perfume_code': code100,
      'name': '${v['name']} 100ml',
      'brand': v['brand'],
      'category': category,
      'bottle_size': '100ml',
      'price': 0.0,
      'status': 'active',
    });
    inventory.add({
      'id': 'inv_sp_$code100',
      'perfume_code': code100,
      'name': '${v['name']} 100ML',
      'category': category,
      'branch': 'San Pablo',
      'shelf': '${v['layer']} - Slot ${v['slot']}',
      'recorded': 5,
      'detected': 5,
      'status': 'normal',
      'misplacement_details': '',
      'price': 0.0,
      'last_updated': DateTime.now().toIso8601String(),
    });

    // 50ML (Size 2)
    final code50 = '$layerCode${slotCode}2';
    products.add({
      'id': 'prod_$code50',
      'perfume_code': code50,
      'name': '${v['name']} 50ml',
      'brand': v['brand'],
      'category': category,
      'bottle_size': '50ml',
      'price': 0.0,
      'status': 'active',
    });
    inventory.add({
      'id': 'inv_sp_$code50',
      'perfume_code': code50,
      'name': '${v['name']} 50ML',
      'category': category,
      'branch': 'San Pablo',
      'shelf': '${v['layer']} - Slot ${v['slot']}',
      'recorded': 5,
      'detected': 5,
      'status': 'normal',
      'misplacement_details': '',
      'price': 0.0,
      'last_updated': DateTime.now().toIso8601String(),
    });
  }

  // Shelf Regions (3 Cameras)
  final shelfRegions = [
    {
      'id': 'roi_sp_layer_A',
      'code': 'Layer A',
      'assigned_product_id': 'prod_AA1',
      'assigned_product_name': 'Camera 1: Top Shelf (10 Male Scents - Cap Codes AA1 to AK2)',
      'branch': 'San Pablo',
      'left_coord': 0.0,
      'right_coord': 1.0,
      'top_coord': 0.0,
      'bottom_coord': 0.33,
      'status': 'active',
    },
    {
      'id': 'roi_sp_layer_B',
      'code': 'Layer B',
      'assigned_product_id': 'prod_BA1',
      'assigned_product_name': 'Camera 2: Middle Shelf (5 Male + 5 Female - Cap Codes BA1 to BK2)',
      'branch': 'San Pablo',
      'left_coord': 0.0,
      'right_coord': 1.0,
      'top_coord': 0.33,
      'bottom_coord': 0.66,
      'status': 'active',
    },
    {
      'id': 'roi_sp_layer_C',
      'code': 'Layer C',
      'assigned_product_id': 'prod_CA1',
      'assigned_product_name': 'Camera 3: Bottom Shelf (10 Female Scents - Cap Codes CA1 to CK2)',
      'branch': 'San Pablo',
      'left_coord': 0.0,
      'right_coord': 1.0,
      'top_coord': 0.66,
      'bottom_coord': 1.0,
      'status': 'active',
    },
  ];

  Future<void> postUpsert(String table, dynamic payload) async {
    final req = await client.postUrl(Uri.parse('$url/rest/v1/$table'));
    req.headers.set('apikey', anonKey);
    req.headers.set('Authorization', 'Bearer $anonKey');
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Prefer', 'resolution=merge-duplicates');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    print('[$table] HTTP ${res.statusCode}: ${body.isEmpty ? "Success" : body}');
  }

  print('=== RE-SEEDING PRODUCTS (60 SKUs) ===');
  await postUpsert('products', products);

  print('\n=== RE-SEEDING SHELF REGIONS (3 Cameras) ===');
  await postUpsert('shelf_regions', shelfRegions);

  print('\n=== RE-SEEDING INVENTORY RECORDS (60 Records) ===');
  await postUpsert('inventory_records', inventory);

  print('\n✓ Done! Supabase records updated without catalog numbers.');
  exit(0);
}
