import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/shelf_region_model.dart';
import '../models/inventory_record_model.dart';

class CatalogSeedData {
  /// 30 fragrance variants (15 Male, 15 Female) × 2 sizes (100ML & 50ML) = 60 SKUs
  /// Organized across 3 shelf layers (10 variants per layer) with 3 fixed cameras.
  /// 3-char unambiguous codes printed on caps: [Layer A/B/C][Slot A-K skipping I][Size 1=100ml, 2=50ml]
  static final List<Map<String, dynamic>> _maleTopVariants = [
    {'slotCode': 'A', 'name': 'Bvlgari Extreme', 'brand': 'Bvlgari', 'slot': 1},
    {'slotCode': 'B', 'name': 'Bvlgari Aqua', 'brand': 'Bvlgari', 'slot': 2},
    {'slotCode': 'C', 'name': 'Clinique Happy Men', 'brand': 'Clinique', 'slot': 3},
    {'slotCode': 'D', 'name': 'Christian Dior Sauvage', 'brand': 'Christian Dior', 'slot': 4},
    {'slotCode': 'E', 'name': 'Ralph Lauren Polo Black', 'brand': 'Ralph Lauren', 'slot': 5},
    {'slotCode': 'F', 'name': 'Davidoff Cool Water', 'brand': 'Davidoff', 'slot': 6},
    {'slotCode': 'G', 'name': 'Ralph Lauren Polo Red', 'brand': 'Ralph Lauren', 'slot': 7},
    {'slotCode': 'H', 'name': 'Lacoste Black', 'brand': 'Lacoste', 'slot': 8},
    {'slotCode': 'J', 'name': 'Hugo Boss', 'brand': 'Hugo Boss', 'slot': 9},
    {'slotCode': 'K', 'name': 'Lacoste Essential', 'brand': 'Lacoste', 'slot': 10},
  ];

  static final List<Map<String, dynamic>> _middleVariants = [
    // 5 Male
    {'slotCode': 'A', 'name': 'Lacoste Red', 'brand': 'Lacoste', 'category': 'Men', 'slot': 1},
    {'slotCode': 'B', 'name': 'Lacoste White', 'brand': 'Lacoste', 'category': 'Men', 'slot': 2},
    {'slotCode': 'C', 'name': 'Paco Rabanne Invictus', 'brand': 'Paco Rabanne', 'category': 'Men', 'slot': 3},
    {'slotCode': 'D', 'name': 'Ralph Lauren Polo Sport', 'brand': 'Ralph Lauren', 'category': 'Men', 'slot': 4},
    {'slotCode': 'E', 'name': 'Tommy Boy', 'brand': 'Tommy Hilfiger', 'category': 'Men', 'slot': 5},
    // 5 Female
    {'slotCode': 'F', 'name': 'Chanel Chance', 'brand': 'Chanel', 'category': 'Women', 'slot': 6},
    {'slotCode': 'G', 'name': 'Chanel No.5', 'brand': 'Chanel', 'category': 'Women', 'slot': 7},
    {'slotCode': 'H', 'name': 'Clinique Happy Women', 'brand': 'Clinique', 'category': 'Women', 'slot': 8},
    {'slotCode': 'J', 'name': 'Escada Moon Sparkle', 'brand': 'Escada', 'category': 'Women', 'slot': 9},
    {'slotCode': 'K', 'name': 'DKNY Be Delicious', 'brand': 'DKNY', 'category': 'Women', 'slot': 10},
  ];

  static final List<Map<String, dynamic>> _femaleBottomVariants = [
    {'slotCode': 'A', 'name': 'D&G Light Blue Women', 'brand': 'Dolce & Gabbana', 'slot': 1},
    {'slotCode': 'B', 'name': 'Elizabeth Arden Green Tea', 'brand': 'Elizabeth Arden', 'slot': 2},
    {'slotCode': 'C', 'name': 'Chanel Coco', 'brand': 'Chanel', 'slot': 3},
    {'slotCode': 'D', 'name': 'Estee Lauder Pleasures', 'brand': 'Estee Lauder', 'slot': 4},
    {'slotCode': 'E', 'name': 'Ferragamo Incanto', 'brand': 'Salvatore Ferragamo', 'slot': 5},
    {'slotCode': 'F', 'name': 'Jo Malone Mimosa & Cardamom', 'brand': 'Jo Malone', 'slot': 6},
    {'slotCode': 'G', 'name': 'Ralph Lauren Romance', 'brand': 'Ralph Lauren', 'slot': 7},
    {'slotCode': 'H', 'name': 'Lancome La Vie Est Belle', 'brand': 'Lancome', 'slot': 8},
    {'slotCode': 'J', 'name': 'Lanvin Eclat D\'Arpege', 'brand': 'Lanvin', 'slot': 9},
    {'slotCode': 'K', 'name': 'Tommy Girl', 'brand': 'Tommy Hilfiger', 'slot': 10},
  ];

  static List<ProductModel> get products {
    final List<ProductModel> list = [];

    // Layer A (Top - Camera 1)
    for (final v in _maleTopVariants) {
      final slotCode = v['slotCode'] as String;
      final slot = v['slot'] as int;
      final name = v['name'] as String;
      final brand = v['brand'] as String;

      // 100ml
      list.add(ProductModel(
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
      ));
      // 50ml
      list.add(ProductModel(
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
      ));
    }

    // Layer B (Middle - Camera 2)
    for (final v in _middleVariants) {
      final slotCode = v['slotCode'] as String;
      final slot = v['slot'] as int;
      final name = v['name'] as String;
      final brand = v['brand'] as String;
      final category = v['category'] as String;

      // 100ml
      list.add(ProductModel(
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
      ));
      // 50ml
      list.add(ProductModel(
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
      ));
    }

    // Layer C (Bottom - Camera 3)
    for (final v in _femaleBottomVariants) {
      final slotCode = v['slotCode'] as String;
      final slot = v['slot'] as int;
      final name = v['name'] as String;
      final brand = v['brand'] as String;

      // 100ml
      list.add(ProductModel(
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
      ));
      // 50ml
      list.add(ProductModel(
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
      ));
    }

    return list;
  }

  /// 3 Shelf Regions corresponding to the 3 fixed mounted cameras on the shelf
  static List<ShelfRegionModel> getShelfRegions(String branch) {
    return [
      ShelfRegionModel(
        id: 'roi_${branch}_layer_A',
        code: 'Layer A',
        assignedProductId: 'prod_AA1',
        assignedProductName: 'Top Shelf (10 Male Scents - Codes AA1 to AK2)',
        branch: branch,
        cameraId: 1,
        cameraName: 'Camera 1 (Top Shelf)',
        layerName: 'Layer A (Top)',
        left: 0.0,
        right: 1.0,
        top: 0.0,
        bottom: 0.33,
      ),
      ShelfRegionModel(
        id: 'roi_${branch}_layer_B',
        code: 'Layer B',
        assignedProductId: 'prod_BA1',
        assignedProductName: 'Middle Shelf (5 Male + 5 Female - Codes BA1 to BK2)',
        branch: branch,
        cameraId: 2,
        cameraName: 'Camera 2 (Middle Shelf)',
        layerName: 'Layer B (Middle)',
        left: 0.0,
        right: 1.0,
        top: 0.33,
        bottom: 0.66,
      ),
      ShelfRegionModel(
        id: 'roi_${branch}_layer_C',
        code: 'Layer C',
        assignedProductId: 'prod_CA1',
        assignedProductName: 'Bottom Shelf (10 Female Scents - Codes CA1 to CK2)',
        branch: branch,
        cameraId: 3,
        cameraName: 'Camera 3 (Bottom Shelf)',
        layerName: 'Layer C (Bottom)',
        left: 0.0,
        right: 1.0,
        top: 0.66,
        bottom: 1.0,
      ),
    ];
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

  /// Seeds all 60 products, 3 shelf layers (3 cameras), and inventory records to Supabase
  static Future<void> seedToSupabase(SupabaseClient client, {String branch = 'San Pablo'}) async {
    final productsPayload = products.map((p) => p.toSupabaseMap()).toList();
    await client.from('products').upsert(productsPayload);

    final regions = getShelfRegions(branch);
    final regionsPayload = regions.map((r) => r.toSupabaseMap()).toList();
    await client.from('shelf_regions').upsert(regionsPayload);

    final inventory = getInitialInventory(branch);
    final inventoryPayload = inventory.map((i) => i.toSupabaseMap()).toList();
    await client.from('inventory_records').upsert(inventoryPayload);
  }

  /// Seeds all 60 products, 3 shelf layers (3 cameras), and inventory records to local SQLite
  static Future<void> seedToSqlite(Database db, {String branch = 'San Pablo'}) async {
    final batch = db.batch();

    for (final p in products) {
      batch.insert('products', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (final r in getShelfRegions(branch)) {
      batch.insert('shelf_regions', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (final inv in getInitialInventory(branch)) {
      batch.insert('inventory_records', inv.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }
}
