// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final url = env['SUPABASE_URL']!;
  final anonKey = env['SUPABASE_ANON_KEY']!;

  final client = HttpClient();

  // 1. All 30 fragrance variants (15 Men, 15 Women)
  final maleVariants = [
    {
      'codePrefix': 'A',
      'name': 'Bvlgari Extreme',
      'brand': 'Bvlgari',
      'layer': 'Layer A (Top)',
      'slot': 1,
    },
    {
      'codePrefix': 'B',
      'name': 'Bvlgari Aqua',
      'brand': 'Bvlgari',
      'layer': 'Layer A (Top)',
      'slot': 2,
    },
    {
      'codePrefix': 'C',
      'name': 'Clinique Happy Men',
      'brand': 'Clinique',
      'layer': 'Layer A (Top)',
      'slot': 3,
    },
    {
      'codePrefix': 'D',
      'name': 'Christian Dior Sauvage',
      'brand': 'Christian Dior',
      'layer': 'Layer A (Top)',
      'slot': 4,
    },
    {
      'codePrefix': 'E',
      'name': 'Ralph Lauren Polo Black',
      'brand': 'Ralph Lauren',
      'layer': 'Layer A (Top)',
      'slot': 5,
    },
    {
      'codePrefix': 'F',
      'name': 'Davidoff Cool Water',
      'brand': 'Davidoff',
      'layer': 'Layer A (Top)',
      'slot': 6,
    },
    {
      'codePrefix': 'G',
      'name': 'Ralph Lauren Polo Red',
      'brand': 'Ralph Lauren',
      'layer': 'Layer A (Top)',
      'slot': 7,
    },
    {
      'codePrefix': 'H',
      'name': 'Lacoste Black',
      'brand': 'Lacoste',
      'layer': 'Layer A (Top)',
      'slot': 8,
    },
    {
      'codePrefix': 'J',
      'name': 'Hugo Boss',
      'brand': 'Hugo Boss',
      'layer': 'Layer A (Top)',
      'slot': 9,
    },
    {
      'codePrefix': 'K',
      'name': 'Lacoste Essential',
      'brand': 'Lacoste',
      'layer': 'Layer A (Top)',
      'slot': 10,
    },
    // Middle Layer Male Scents
    {
      'codePrefix': 'A',
      'name': 'Lacoste Red',
      'brand': 'Lacoste',
      'layer': 'Layer B (Middle)',
      'slot': 1,
    },
    {
      'codePrefix': 'B',
      'name': 'Lacoste White',
      'brand': 'Lacoste',
      'layer': 'Layer B (Middle)',
      'slot': 2,
    },
    {
      'codePrefix': 'C',
      'name': 'Paco Rabanne Invictus',
      'brand': 'Paco Rabanne',
      'layer': 'Layer B (Middle)',
      'slot': 3,
    },
    {
      'codePrefix': 'D',
      'name': 'Ralph Lauren Polo Sport',
      'brand': 'Ralph Lauren',
      'layer': 'Layer B (Middle)',
      'slot': 4,
    },
    {
      'codePrefix': 'E',
      'name': 'Tommy Boy',
      'brand': 'Tommy Hilfiger',
      'layer': 'Layer B (Middle)',
      'slot': 5,
    },
  ];

  final femaleVariants = [
    // Middle Layer Female Scents
    {
      'codePrefix': 'F',
      'name': 'Chanel Chance',
      'brand': 'Chanel',
      'layer': 'Layer B (Middle)',
      'slot': 6,
    },
    {
      'codePrefix': 'G',
      'name': 'Chanel No.5',
      'brand': 'Chanel',
      'layer': 'Layer B (Middle)',
      'slot': 7,
    },
    {
      'codePrefix': 'H',
      'name': 'Clinique Happy Women',
      'brand': 'Clinique',
      'layer': 'Layer B (Middle)',
      'slot': 8,
    },
    {
      'codePrefix': 'J',
      'name': 'Escada Moon Sparkle',
      'brand': 'Escada',
      'layer': 'Layer B (Middle)',
      'slot': 9,
    },
    {
      'codePrefix': 'K',
      'name': 'DKNY Be Delicious',
      'brand': 'DKNY',
      'layer': 'Layer B (Middle)',
      'slot': 10,
    },
    // Bottom Layer Female Scents
    {
      'codePrefix': 'A',
      'name': 'D&G Light Blue Women',
      'brand': 'Dolce & Gabbana',
      'layer': 'Layer C (Bottom)',
      'slot': 1,
    },
    {
      'codePrefix': 'B',
      'name': 'Elizabeth Arden Green Tea',
      'brand': 'Elizabeth Arden',
      'layer': 'Layer C (Bottom)',
      'slot': 2,
    },
    {
      'codePrefix': 'C',
      'name': 'Chanel Coco',
      'brand': 'Chanel',
      'layer': 'Layer C (Bottom)',
      'slot': 3,
    },
    {
      'codePrefix': 'D',
      'name': 'Estee Lauder Pleasures',
      'brand': 'Estee Lauder',
      'layer': 'Layer C (Bottom)',
      'slot': 4,
    },
    {
      'codePrefix': 'E',
      'name': 'Ferragamo Incanto',
      'brand': 'Salvatore Ferragamo',
      'layer': 'Layer C (Bottom)',
      'slot': 5,
    },
    {
      'codePrefix': 'F',
      'name': 'Jo Malone Mimosa & Cardamom',
      'brand': 'Jo Malone',
      'layer': 'Layer C (Bottom)',
      'slot': 6,
    },
    {
      'codePrefix': 'G',
      'name': 'Ralph Lauren Romance',
      'brand': 'Ralph Lauren',
      'layer': 'Layer C (Bottom)',
      'slot': 7,
    },
    {
      'codePrefix': 'H',
      'name': 'Lancome La Vie Est Belle',
      'brand': 'Lancome',
      'layer': 'Layer C (Bottom)',
      'slot': 8,
    },
    {
      'codePrefix': 'J',
      'name': 'Lanvin Eclat D\'Arpege',
      'brand': 'Lanvin',
      'layer': 'Layer C (Bottom)',
      'slot': 9,
    },
    {
      'codePrefix': 'K',
      'name': 'Tommy Girl',
      'brand': 'Tommy Hilfiger',
      'layer': 'Layer C (Bottom)',
      'slot': 10,
    },
  ];

  final List<Map<String, dynamic>> products = [];
  final List<Map<String, dynamic>> inventory = [];

  // Generate 60 SKUs
  for (final v in [...maleVariants, ...femaleVariants]) {
    final layerCode = (v['layer'] as String).contains('Layer A')
        ? 'A'
        : ((v['layer'] as String).contains('Layer B') ? 'B' : 'C');
    final isMale =
        (v['layer'] as String).contains('Layer A') ||
        ((v['layer'] as String).contains('Layer B') && (v['slot'] as int) <= 5);
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
      'price': 260.0,
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
      'price': 260.0,
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
      'price': 180.0,
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
      'price': 180.0,
      'last_updated': DateTime.now().toIso8601String(),
    });
  }

  // Shelf Regions (6 Mounted Cameras × 2 Bottle Sizes = 12 Regions)
  final cameras = [
    {
      'id': 1,
      'name': 'Cam 1A (left)',
      'layer': 'Layer A (Top)',
      'pos': 'left',
      'node': '/dev/video0',
      'code1': 'AA1-AE1',
      'code2': 'AA2-AE2',
    },
    {
      'id': 2,
      'name': 'Cam 1B (Right)',
      'layer': 'Layer A (Top)',
      'pos': 'right',
      'node': '/dev/video4',
      'code1': 'AF1-AK1',
      'code2': 'AF2-AK2',
    },
    {
      'id': 3,
      'name': 'Cam 2A (left)',
      'layer': 'Layer B (Middle)',
      'pos': 'left',
      'node': '/dev/video6',
      'code1': 'BA1-BE1',
      'code2': 'BA2-BE2',
    },
    {
      'id': 4,
      'name': 'Cam 2B (Right)',
      'layer': 'Layer B (Middle)',
      'pos': 'right',
      'node': '/dev/video8',
      'code1': 'BF1-BK1',
      'code2': 'BF2-BK2',
    },
    {
      'id': 5,
      'name': 'Cam 3A (left)',
      'layer': 'Layer C (Bottom)',
      'pos': 'left',
      'node': '/dev/video10',
      'code1': 'CA1-CE1',
      'code2': 'CA2-CE2',
    },
    {
      'id': 6,
      'name': 'Cam 3B (Right)',
      'layer': 'Layer C (Bottom)',
      'pos': 'right',
      'node': '/dev/video12',
      'code1': 'CF1-CK1',
      'code2': 'CF2-CK2',
    },
  ];

  final List<Map<String, dynamic>> shelfRegions = [];
  for (final cam in cameras) {
    final camId = cam['id'] as int;
    final camName = cam['name'] as String;
    final layer = cam['layer'] as String;
    final pos = cam['pos'] as String;
    final node = cam['node'] as String;

    // 100ML (Size 1) Region
    shelfRegions.add({
      'id': 'roi_San_Pablo_cam_${camId}_100ml',
      'code': '$camName - 100ML',
      'assigned_product_id': 'prod_100ml_$camId',
      'assigned_product_name': '$camName (100ML Zone • ${cam['code1']})',
      'branch': 'San Pablo',
      'camera_id': camId,
      'camera_name': camName,
      'layer_name': layer,
      'camera_position': pos,
      'device_node': node,
      'bottle_size': '100ml',
      'left_coord': 0.05,
      'right_coord': 0.95,
      'top_coord': 0.10,
      'bottom_coord': 0.48,
      'status': 'active',
    });

    // 50ML (Size 2) Region
    shelfRegions.add({
      'id': 'roi_San_Pablo_cam_${camId}_50ml',
      'code': '$camName - 50ML',
      'assigned_product_id': 'prod_50ml_$camId',
      'assigned_product_name': '$camName (50ML Zone • ${cam['code2']})',
      'branch': 'San Pablo',
      'camera_id': camId,
      'camera_name': camName,
      'layer_name': layer,
      'camera_position': pos,
      'device_node': node,
      'bottle_size': '50ml',
      'left_coord': 0.05,
      'right_coord': 0.95,
      'top_coord': 0.52,
      'bottom_coord': 0.90,
      'status': 'active',
    });
  }

  Future<void> postUpsert(String table, dynamic payload) async {
    final req = await client.postUrl(Uri.parse('$url/rest/v1/$table'));
    req.headers.set('apikey', anonKey);
    req.headers.set('Authorization', 'Bearer $anonKey');
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Prefer', 'resolution=merge-duplicates');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    print(
      '[$table] HTTP ${res.statusCode}: ${body.isEmpty ? "Success" : body}',
    );
  }

  print('=== RE-SEEDING PRODUCTS (60 SKUs) ===');
  await postUpsert('products', products);

  print('\n=== RE-SEEDING SHELF REGIONS (12 Regions across 6 Cameras) ===');
  await postUpsert('shelf_regions', shelfRegions);

  print('\n=== RE-SEEDING INVENTORY RECORDS (60 Records) ===');
  await postUpsert('inventory_records', inventory);

  print('\n✓ Done! Supabase records updated.');
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
