import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/services/inventory_database.dart';

Future<void> _clearAll() async {
  final db = await InventoryDatabase.instance.db;
  await db.delete('sync_outbox');
  await db.delete('medicine_onboarding_requests');
  await db.delete('inventory');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _clearAll();
  });

  test('unknown medicine creates pending onboarding request and outbox event', () async {
    final inventory = InventoryDatabase.instance;

    final result = await inventory.submitMedicineOnboardingRequest(
      barcode: '6250000001234',
      name: 'Test Medicine',
      dosage: '500 mg',
      category: 'Antibiotic',
      stock: 5,
      expiry: '2027-01-01',
      price: 4.5,
    );

    expect(result.outcome, MedicineOnboardingOutcome.pending);

    final db = await inventory.db;
    final requestRows = await db.query('medicine_onboarding_requests');
    expect(requestRows.length, 1);
    expect(requestRows.first['barcode'], '6250000001234');
    expect(requestRows.first['request_status'], 'pending_review');

    final inventoryRows = await db.query(
      'inventory',
      where: 'barcode = ?',
      whereArgs: ['6250000001234'],
      limit: 1,
    );
    expect(inventoryRows, isNotEmpty);
    expect(inventoryRows.first['approval_status'], 'pending_approval');
    expect((inventoryRows.first['is_blocked'] as num).toInt(), 1);

    final outboxRows = await db.query(
      'sync_outbox',
      where: 'stream = ?',
      whereArgs: ['medicine_request_submitted'],
      limit: 1,
    );
    expect(outboxRows, isNotEmpty);
  });
}
