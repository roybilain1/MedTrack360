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

Future<void> _seedBreachItem() async {
  final dbService = InventoryDatabase.instance;
  final db = await dbService.db;
  await _withDbRetry(() => db.delete('inventory'));
  await _withDbRetry(() => db.delete('prices'));
  await _withDbRetry(() => db.delete('price_history'));

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
    if (find
        .textContaining('MoPH Ceiling Breach: Amoxil')
        .evaluate()
        .isNotEmpty) {
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
    await _seedBreachItem();
  });

  testWidgets('pricing alert renders Apply Price Now button', (tester) async {
    await _pumpAlerts(tester);

    expect(find.text('Apply Price Now'), findsOneWidget);
    expect(find.textContaining('MoPH Ceiling Breach: Amoxil'), findsOneWidget);
  });

  testWidgets('Apply Price Now updates price and clears breach alert', (
    tester,
  ) async {
    await _pumpAlerts(tester);

    await tester.tap(find.text('Apply Price Now'));
    await tester.pump();

    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .textContaining('Applied MoPH ceiling price')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    final items = await InventoryDatabase.instance.searchInventory('Amoxil');
    expect(items, isNotEmpty);
    expect(items.first.price, 20.0);

    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .textContaining('MoPH Ceiling Breach: Amoxil')
          .evaluate()
          .isEmpty) {
        break;
      }
    }

    expect(find.textContaining('MoPH Ceiling Breach: Amoxil'), findsNothing);
  });

  testWidgets('Apply Price Now shows friendly error when item is missing', (
    tester,
  ) async {
    await _pumpAlerts(tester);

    final db = await InventoryDatabase.instance.db;
    await _withDbRetry(
      () => db.delete(
        'inventory',
        where: 'barcode = ?',
        whereArgs: ['6250000000010'],
      ),
    );

    await tester.tap(find.text('Apply Price Now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('Unable to apply price: item was not found.'),
      findsOneWidget,
    );
  });
}
