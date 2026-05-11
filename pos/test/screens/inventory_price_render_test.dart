import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/screens/inventory/inventory_screen.dart';
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

Future<void> _seedInventory() async {
  final dbService = InventoryDatabase.instance;
  final db = await dbService.db;
  await _withDbRetry(() => db.delete('inventory'));

  await _withDbRetry(
    () => dbService.insertInventoryItem(
      barcode: '6250000000010',
      name: 'Amoxil',
      dosage: '500 mg',
      category: 'Antibiotic',
      stock: 12,
      expiry: '2027-01-01',
      price: 20.0,
    ),
  );

  await _withDbRetry(
    () => db.update(
      'inventory',
      {'moph_ceiling': 50.0},
      where: 'barcode = ?',
      whereArgs: ['6250000000010'],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await _seedInventory();
  });

  testWidgets(
    'inventory row renders both local and government prices clearly',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(0.9)),
            child: Scaffold(body: InventoryScreen()),
          ),
        ),
      );

      // Avoid pumpAndSettle hangs from long-lived timers/animations.
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(TextField).evaluate().isNotEmpty) {
          break;
        }
      }

      await tester.enterText(find.byType(TextField).first, 'Amoxil');
      await tester.pump(const Duration(milliseconds: 500));

      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Local: \$20.00').evaluate().isNotEmpty &&
            find.text('Gov: \$50.00').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.text('Local: \$20.00'), findsOneWidget);
      expect(find.text('Gov: \$50.00'), findsOneWidget);
    },
  );
}
