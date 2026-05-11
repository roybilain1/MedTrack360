import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/screens/alerts/alerts_screen.dart';
import 'package:medtrack_pos/services/inventory_database.dart';

Future<void> _withDbRetry(Future<void> Function() action) async {
  Object? lastError;
  for (var attempt = 0; attempt < 25; attempt++) {
    try {
      await action();
      return;
    } catch (error) {
      final msg = error.toString().toLowerCase();
      if (!msg.contains('database is locked')) rethrow;
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
  if (lastError != null) throw lastError;
}

Future<void> _seedAlertsData() async {
  final dbService = InventoryDatabase.instance;
  final db = await dbService.db;

  await _withDbRetry(() => db.delete('inventory'));
  await _withDbRetry(() => db.delete('prices'));
  await _withDbRetry(() => db.delete('price_history'));
  await _withDbRetry(() => db.delete('offline_sale_queue'));
  await _withDbRetry(() => db.delete('loan_repayments'));

  await _withDbRetry(
    () => dbService.insertInventoryItem(
      barcode: '6250000000010',
      name: 'Amoxil',
      dosage: '500 mg',
      category: 'Antibiotic',
      stock: 12,
      expiry: '2027-01-01',
      price: 50.0,
    ),
  );

  await _withDbRetry(
    () => db.update(
      'inventory',
      {'moph_ceiling': 20.0},
      where: 'barcode = ?',
      whereArgs: ['6250000000010'],
    ),
  );

  await _withDbRetry(
    () => dbService.insertInventoryItem(
      barcode: '6250000000011',
      name: 'Paracetamol',
      dosage: '500 mg',
      category: 'Analgesic',
      stock: 8,
      expiry: '2027-01-01',
      price: 2.0,
    ),
  );

  await _withDbRetry(
    () => db.insert('offline_sale_queue', {
      'receipt_id': 'R-1',
      'sale_data': '{}',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'synced': 1,
      'sync_status': 'synced',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'sale_uuid': 'sale-1',
      'device_id': 'HW-00423',
    }),
  );
}

Future<void> _pumpAlerts(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: AlertsScreen())),
  );

  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.textContaining('Low Stock:').evaluate().isNotEmpty) {
      break;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await _seedAlertsData();
  });

  testWidgets(
    'removed pseudo-alerts are not rendered anywhere on Alerts screen',
    (tester) async {
      await _pumpAlerts(tester);

      expect(find.textContaining('Pending Sync Queue'), findsNothing);
      expect(find.text('Database-Driven Monitoring Active'), findsNothing);
      expect(
        find.textContaining('waiting to sync with the government server'),
        findsNothing,
      );
    },
  );

  testWidgets('remaining alerts UI and actions still render', (tester) async {
    await _pumpAlerts(tester);

    expect(find.textContaining('Low Stock:'), findsWidgets);
    expect(find.textContaining('MoH Pricing  '), findsOneWidget);
    expect(find.textContaining('Sync Ack  '), findsOneWidget);
    expect(find.text('Mark All Read'), findsOneWidget);
  });

  testWidgets('removed categories/chips and orphan sections do not remain', (
    tester,
  ) async {
    await _pumpAlerts(tester);

    expect(find.textContaining('Warnings  '), findsNothing);
    expect(find.textContaining('Info  '), findsNothing);
    expect(find.text('Warnings'), findsNothing);
    expect(find.text('Information'), findsNothing);

    expect(find.textContaining('Critical  '), findsOneWidget);
    expect(find.textContaining('MoH Pricing  '), findsOneWidget);
  });

  testWidgets('mark all read clears visible remaining alerts', (tester) async {
    await _pumpAlerts(tester);

    await tester.tap(find.text('Mark All Read'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('No alerts in this category'), findsOneWidget);
  });
}
