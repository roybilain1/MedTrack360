import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/services/inventory_database.dart';

Future<void> _clearInventory() async {
  final db = await InventoryDatabase.instance.db;
  await db.delete('prices');
  await db.delete('inventory');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _clearInventory();
  });

  test('extractOfficialPrice supports canonical regulated minor units', () {
    final canonicalPrice = extractOfficialPrice({
      'regulated_price_minor': 5000,
    });
    final legacyPrice = extractOfficialPrice({'moph_ceiling': 50.0});
    final stringCanonicalPrice = extractOfficialPrice({
      'regulated_price_minor': '5000',
    });
    final stringLegacyPrice = extractOfficialPrice({'moph_ceiling': '50.0'});

    expect(canonicalPrice, 50.0);
    expect(legacyPrice, 50.0);
    expect(stringCanonicalPrice, 50.0);
    expect(stringLegacyPrice, 50.0);
  });

  test(
    'official mapping keeps local price and updates gov ceiling field',
    () async {
      final inventory = InventoryDatabase.instance;

      final inserted = await inventory.insertInventoryItem(
        barcode: '6250000000010',
        name: 'Amoxil',
        dosage: '500 mg',
        category: 'Antibiotic',
        stock: 9,
        expiry: '2027-01-01',
        price: 20.0,
      );
      expect(inserted, isTrue);

      final db = await inventory.db;
      final row = {
        'barcode': '6250000000010',
        'official_name': 'Amoxil',
        'dosage': '500 mg',
        'category': 'Antibiotic',
        'official_code': 'REG-AMOXIL-500',
        'regulated_price_minor': 5000,
      };

      await db.update(
        'inventory',
        {
          'name': resolveOfficialName(row),
          'dosage': row['dosage'],
          'category': row['category'],
          'moph_ceiling': extractOfficialPrice(row),
          'batch_number': resolveOfficialCode(row),
        },
        where: 'barcode = ?',
        whereArgs: [row['barcode']],
      );

      final items = await inventory.searchInventory('Amoxil');
      expect(items, isNotEmpty);
      expect(items.first.price, 20.0);
      expect(items.first.mophCeiling, 50.0);
    },
  );

  test(
    'pricedAboveCeiling falls back to canonical regulated price table',
    () async {
      final inventory = InventoryDatabase.instance;
      final db = await inventory.db;

      final inserted = await inventory.insertInventoryItem(
        barcode: '6250000000099',
        name: 'Amoxil',
        dosage: '500 mg',
        category: 'Antibiotic',
        stock: 4,
        expiry: '2027-01-01',
        price: 1000.0,
      );
      expect(inserted, isTrue);

      await db.update(
        'inventory',
        {'moph_ceiling': null},
        where: 'barcode = ?',
        whereArgs: ['6250000000099'],
      );

      await db.insert('prices', {
        'price_uuid': 'test-price-amoxil-1',
        'barcode': '6250000000099',
        'regulated_price_minor': 10000,
        'local_price_minor': null,
        'currency_code': 'USD',
        'source': 'server',
        'version': 1,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        'deleted_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final overpriced = await inventory.pricedAboveCeiling(limit: 10);
      expect(overpriced.any((item) => item.barcode == '6250000000099'), isTrue);

      final amoxil = overpriced.firstWhere(
        (item) => item.barcode == '6250000000099',
      );
      expect(amoxil.mophCeiling, 100.0);
      expect(amoxil.price - (amoxil.mophCeiling ?? 0), 900.0);
    },
  );
}
