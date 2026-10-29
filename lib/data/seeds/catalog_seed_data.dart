import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_model.dart';
import '../models/shelf_region_model.dart';
import '../models/inventory_record_model.dart';

class CatalogSeedData {
  /// 30 fragrance variants (15 Male, 15 Female) × 2 sizes (100ML & 50ML) = 60 SKUs
  /// Organized across 3 shelf layers (10 variants per layer) with 6 mounted cameras.
  /// 3-char unambiguous codes printed on caps: [Layer A/B/C][Slot A-K skipping I][Size 1=100ml, 2=50ml]
  static final List<Map<String, dynamic>> _maleTopVariants = [
    {'slotCode': 'A', 'name': 'Bvlgari Extreme', 'brand': 'Bvlgari', 'slot': 1},
    {'slotCode': 'B', 'name': 'Bvlgari Aqua', 'brand': 'Bvlgari', 'slot': 2},
    {
      'slotCode': 'C',
      'name': 'Clinique Happy Men',
      'brand': 'Clinique',
      'slot': 3,
    },
    {
      'slotCode': 'D',
      'name': 'Christian Dior Sauvage',
      'brand': 'Christian Dior',
      'slot': 4,
    },
    {
      'slotCode': 'E',
      'name': 'Ralph Lauren Polo Black',
      'brand': 'Ralph Lauren',
      'slot': 5,
    },
    {
      'slotCode': 'F',
      'name': 'Davidoff Cool Water',
      'brand': 'Davidoff',
      'slot': 6,
    },
    {
      'slotCode': 'G',
      'name': 'Ralph Lauren Polo Red',
      'brand': 'Ralph Lauren',
      'slot': 7,
    },
    {'slotCode': 'H', 'name': 'Lacoste Black', 'brand': 'Lacoste', 'slot': 8},
    {'slotCode': 'J', 'name': 'Hugo Boss', 'brand': 'Hugo Boss', 'slot': 9},
    {
      'slotCode': 'K',
      'name': 'Lacoste Essential',
      'brand': 'Lacoste',
      'slot': 10,
    },
  ];

  static final List<Map<String, dynamic>> _middleVariants = [
    // 5 Male
    {
      'slotCode': 'A',
      'name': 'Lacoste Red',
      'brand': 'Lacoste',
      'category': 'Men',
      'slot': 1,
    },
    {
      'slotCode': 'B',
      'name': 'Lacoste White',
      'brand': 'Lacoste',
      'category': 'Men',
      'slot': 2,
    },
    {
      'slotCode': 'C',
      'name': 'Paco Rabanne Invictus',
      'brand': 'Paco Rabanne',
      'category': 'Men',
      'slot': 3,
    },
    {
      'slotCode': 'D',
      'name': 'Ralph Lauren Polo Sport',
      'brand': 'Ralph Lauren',
      'category': 'Men',
      'slot': 4,
    },
    {
      'slotCode': 'E',
      'name': 'Tommy Boy',
      'brand': 'Tommy Hilfiger',
      'category': 'Men',
      'slot': 5,
    },
    // 5 Female
    {
      'slotCode': 'F',
      'name': 'Chanel Chance',
      'brand': 'Chanel',
      'category': 'Women',
      'slot': 6,
    },
    {
      'slotCode': 'G',
      'name': 'Chanel No.5',
      'brand': 'Chanel',
      'category': 'Women',
      'slot': 7,
    },
    {
      'slotCode': 'H',
      'name': 'Clinique Happy Women',
      'brand': 'Clinique',
      'category': 'Women',
      'slot': 8,
    },
    {
      'slotCode': 'J',
      'name': 'Escada Moon Sparkle',
      'brand': 'Escada',
      'category': 'Women',
      'slot': 9,
    },
    {
      'slotCode': 'K',
      'name': 'DKNY Be Delicious',
      'brand': 'DKNY',
      'category': 'Women',
      'slot': 10,
    },
  ];

  static final List<Map<String, dynamic>> _femaleBottomVariants = [
    {
      'slotCode': 'A',
      'name': 'D&G Light Blue Women',
      'brand': 'Dolce & Gabbana',
      'slot': 1,
    },
    {
      'slotCode': 'B',
      'name': 'Elizabeth Arden Green Tea',
      'brand': 'Elizabeth Arden',
      'slot': 2,
    },
    {'slotCode': 'C', 'name': 'Chanel Coco', 'brand': 'Chanel', 'slot': 3},
    {
      'slotCode': 'D',
      'name': 'Estee Lauder Pleasures',
      'brand': 'Estee Lauder',
      'slot': 4,
    },
    {
      'slotCode': 'E',
      'name': 'Ferragamo Incanto',
      'brand': 'Salvatore Ferragamo',
      'slot': 5,
    },
    {
      'slotCode': 'F',
      'name': 'Jo Malone Mimosa & Cardamom',
      'brand': 'Jo Malone',
      'slot': 6,
    },
    {
      'slotCode': 'G',
      'name': 'Ralph Lauren Romance',
      'brand': 'Ralph Lauren',
      'slot': 7,
    },
    {
      'slotCode': 'H',
      'name': 'Lancome La Vie Est Belle',
      'brand': 'Lancome',
      'slot': 8,
    },
    {
      'slotCode': 'J',
      'name': 'Lanvin Eclat D\'Arpege',
      'brand': 'Lanvin',
      'slot': 9,
    },
    {
      'slotCode': 'K',
      'name': 'Tommy Girl',
      'brand': 'Tommy Hilfiger',
      'slot': 10,
    },
  ];

  static List<ProductModel> get products {
    final List<ProductModel> list = [];

    // Layer A (Top - Men)
    for (final v in _maleTopVariants) {
      final slotCode = v['slotCode'] as String;
      final slot = v['slot'] as int;
      final name = v['name'] as String;
      final brand = v['brand'] as String;

      // 100ml
      list.add(
        ProductModel(
          id: 'prod_A${slotCode}1',
          perfumeCode: 'A${slotCode}1',
          name: name,
          brand: brand,
          category: 'Men',
          bottleSize: '100ml',
          shelfLayer: 'Layer A (Top)',
          slotPosition: slot,
          price: 0.0,
          status: 'active',
        ),
      );
      // 50ml
      list.add(
        ProductModel(
          id: 'prod_A${slotCode}2',
          perfumeCode: 'A${slotCode}2',
          name: name,
          brand: brand,
          category: 'Men',
          bottleSize: '50ml',
          shelfLayer: 'Layer A (Top)',
          slotPosition: slot,
          price: 0.0,
          status: 'active',
        ),
      );
    }

    // Layer B (Middle - Mixed)
    for (final v in _middleVariants) {
      final slotCode = v['slotCode'] as String;
      final slot = v['slot'] as int;
      final name = v['name'] as String;
      final brand = v['brand'] as String;
      final category = v['category'] as String;

      // 100ml
      list.add(
        ProductModel(
          id: 'prod_B${slotCode}1',
          perfumeCode: 'B${slotCode}1',
          name: name,
          brand: brand,
          category: category,
          bottleSize: '100ml',
          shelfLayer: 'Layer B (Middle)',
          slotPosition: slot,
          price: 0.0,
          status: 'active',
        ),
      );
      // 50ml
      list.add(
        ProductModel(
          id: 'prod_B${slotCode}2',
          perfumeCode: 'B${slotCode}2',
          name: name,
          brand: brand,
          category: category,
          bottleSize: '50ml',
          shelfLayer: 'Layer B (Middle)',
          slotPosition: slot,
          price: 0.0,
          status: 'active',
        ),
      );
    }

    // Layer C (Bottom - Women)
    for (final v in _femaleBottomVariants) {
      final slotCode = v['slotCode'] as String;
      final slot = v['slot'] as int;
      final name = v['name'] as String;
      final brand = v['brand'] as String;

      // 100ml
      list.add(
        ProductModel(
          id: 'prod_C${slotCode}1',
          perfumeCode: 'C${slotCode}1',
          name: name,
          brand: brand,
          category: 'Women',
          bottleSize: '100ml',
          shelfLayer: 'Layer C (Bottom)',
          slotPosition: slot,
          price: 0.0,
          status: 'active',
        ),
      );
      // 50ml
      list.add(
        ProductModel(
          id: 'prod_C${slotCode}2',
          perfumeCode: 'C${slotCode}2',
          name: name,
          brand: brand,
          category: 'Women',
          bottleSize: '50ml',
          shelfLayer: 'Layer C (Bottom)',
          slotPosition: slot,
          price: 0.0,
          status: 'active',
        ),
      );
    }

    return list;
  }

  /// 12 Shelf Regions corresponding to the 6 mounted cameras with dedicated 100ML & 50ML ROIs
  static List<ShelfRegionModel> getShelfRegions(String branch) {
    final List<ShelfRegionModel> regions = [];

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

    for (final cam in cameras) {
      final camId = cam['id'] as int;
      final camName = cam['name'] as String;
      final layer = cam['layer'] as String;
      final pos = cam['pos'] as String;
      final node = cam['node'] as String;

      // 100ML (Size 1) ROI Region
      regions.add(
        ShelfRegionModel(
          id: 'roi_${branch}_cam_${camId}_100ml',
          code: '$camName - 100ML',
          assignedProductId: 'prod_100ml_$camId',
          assignedProductName: '$camName (100ML Zone • ${cam['code1']})',
          branch: branch,
          cameraId: camId,
          cameraName: camName,
          layerName: layer,
          cameraPosition: pos,
          deviceNode: node,
          bottleSize: '100ml',
          left: 0.05,
          right: 0.95,
          top: 0.10,
          bottom: 0.48,
        ),
      );

      // 50ML (Size 2) ROI Region
      regions.add(
        ShelfRegionModel(
          id: 'roi_${branch}_cam_${camId}_50ml',
          code: '$camName - 50ML',
          assignedProductId: 'prod_50ml_$camId',
          assignedProductName: '$camName (50ML Zone • ${cam['code2']})',
          branch: branch,
          cameraId: camId,
          cameraName: camName,
          layerName: layer,
          cameraPosition: pos,
          deviceNode: node,
          bottleSize: '50ml',
          left: 0.05,
          right: 0.95,
          top: 0.52,
          bottom: 0.90,
        ),
      );
    }

    return regions;
  }

  /// Initial inventory records for pure inventory tracking (5 recorded, 5 detected initially)
  static List<InventoryRecordModel> getInitialInventory(String branch) {
    final now = DateTime.now();
    return products.map((p) {
      return InventoryRecordModel(
        id: 'inv_${branch}_${p.perfumeCode}',
        perfumeCode: p.perfumeCode,
        name: '${p.name} (${p.bottleSize.toUpperCase()})',
        category: p.category,
        branch: branch,
        shelf: '${p.shelfLayer} - Slot ${p.slotPosition}',
        recorded: 5,
        detected: 5,
        status: 'normal',
        misplacementDetails: '',
        price: 0.0,
        lastUpdated: now,
      );
    }).toList();
  }

  /// Seeds all 60 products, 12 shelf regions (6 cameras × 2 sizes), and inventory records to Supabase
  static Future<void> seedToSupabase(
    SupabaseClient client, {
    String branch = 'San Pablo',
  }) async {
    final productsPayload = products.map((p) => p.toSupabaseMap()).toList();
    await client.from('products').upsert(productsPayload);

    final regions = getShelfRegions(branch);
    final regionsPayload = regions.map((r) => r.toSupabaseMap()).toList();
    await client.from('shelf_regions').upsert(regionsPayload);

    final inventory = getInitialInventory(branch);
    final inventoryPayload = inventory.map((i) => i.toSupabaseMap()).toList();
    await client.from('inventory_records').upsert(inventoryPayload);
  }

  /// Seeds all 60 products, 12 shelf regions (6 cameras × 2 sizes), and inventory records to local SQLite
  static Future<void> seedToSqlite(
    Database db, {
    String branch = 'San Pablo',
  }) async {
    final batch = db.batch();

    for (final p in products) {
      batch.insert(
        'products',
        p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    for (final r in getShelfRegions(branch)) {
      batch.insert(
        'shelf_regions',
        r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    for (final inv in getInitialInventory(branch)) {
      batch.insert(
        'inventory_records',
        inv.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }
}
