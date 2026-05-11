import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/services/inventory_database.dart';

Future<void> _clearPosData() async {
  final db = await InventoryDatabase.instance.db;
  const tables = <String>[
    'inventory',
    'offline_sale_queue',
    'inventory_movement_queue',
    'sale_items_cache',
    'sync_outbox',
    'prices',
    'price_history',
    'stock_adjustments',
    'returns',
    'sync_state',
    'sync_checkpoint',
  ];
  for (final table in tables) {
    try {
      await db.delete(table);
    } catch (_) {
      // Ignore optional tables.
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _clearPosData();
  });

  test('inventory stock changes after queued sale deduction', () async {
    final db = InventoryDatabase.instance;

    final inserted = await db.insertInventoryItem(
      barcode: 'POS-REG-INV-1',
      name: 'Inventory Refresh Med',
      dosage: '500mg',
      category: 'Analgesic',
      stock: 9,
      expiry: '2027-01-01',
      price: 3.2,
    );
    expect(inserted, isTrue);

    await db.queueSale('POS-REG-R1', {
      'timestamp': DateTime.now().toIso8601String(),
      'method': 'CASH',
      'items': [
        {
          'barcode': 'POS-REG-INV-1',
          'product': 'Inventory Refresh Med',
          'dosage': '500mg',
          'qty': 2,
          'price': 3.2,
          'total': 6.4,
        },
      ],
      'grandTotal': 6.4,
    });

    await db.applySaleStockDeductions([
      {
        'barcode': 'POS-REG-INV-1',
        'qty': 2,
        'price': 3.2,
        'batch_number': 'B-1',
      },
    ], referenceId: 'POS-REG-R1');

    final items = await db.searchInventory('Inventory Refresh Med');
    expect(items, isNotEmpty);
    expect(items.first.stock, 7);
  });

  test(
    'alerts and finances backing data reflect pending/synced sales',
    () async {
      final db = InventoryDatabase.instance;

      await db.queueSale('POS-REG-R2', {
        'timestamp': DateTime.now().toIso8601String(),
        'method': 'VISA',
        'customer': 'Regression Customer',
        'subtotal': 12.0,
        'moph_tax': 0.0,
        'vat': 0.0,
        'grandTotal': 12.0,
        'items': [
          {
            'barcode': 'POS-REG-2',
            'product': 'Finances Backing Med',
            'dosage': '10mg',
            'qty': 1,
            'price': 12.0,
            'total': 12.0,
          },
        ],
      });

      final pendingBefore = await db.pendingQueueCount();
      expect(pendingBefore, 1);

      final historyBefore = await db.getSalesHistory(limit: 10);
      expect(historyBefore, isNotEmpty);
      expect(historyBefore.first.receiptId, 'POS-REG-R2');

      final pending = await db.getPendingQueue();
      expect(pending, isNotEmpty);
      await db.markSynced(pending.first.id);

      final synced = await db.syncedSalesCount();
      final pendingAfter = await db.pendingQueueCount();
      expect(synced, 1);
      expect(pendingAfter, 0);
    },
  );
}
