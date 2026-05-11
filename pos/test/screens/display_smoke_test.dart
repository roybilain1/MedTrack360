import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/screens/alerts/alerts_screen.dart';
import 'package:medtrack_pos/screens/checkout/checkout_screen.dart';
import 'package:medtrack_pos/screens/finances/finances_screen.dart';
import 'package:medtrack_pos/screens/inventory/inventory_screen.dart';
import 'package:medtrack_pos/screens/main_dashboard.dart';
import 'package:medtrack_pos/services/inventory_database.dart';

Future<void> _resetLocalDb() async {
  final db = await InventoryDatabase.instance.db;
  const tables = <String>[
    'inventory',
    'unmapped_barcodes',
    'offline_sale_queue',
    'inventory_movement_queue',
    'sale_items_cache',
    'sync_outbox',
    'sync_conflict_notes',
    'prices',
    'price_history',
    'stock_adjustments',
    'returns',
    'sync_checkpoint',
    'sync_state',
    'loan_customers',
    'loan_repayments',
  ];

  for (final table in tables) {
    try {
      await db.delete(table);
    } catch (_) {
      // Ignore optional tables in smoke tests.
    }
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

Future<void> _pumpScreen(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  await tester.pumpWidget(_wrap(child));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpMainDashboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  await tester.pumpWidget(
    const MaterialApp(home: MainDashboard(autoStartSync: false)),
  );
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _resetLocalDb();
  });

  testWidgets('Main dashboard shell renders indexed navigation', (
    tester,
  ) async {
    await _pumpMainDashboard(tester);

    expect(find.byType(IndexedStack), findsOneWidget);
    expect(find.text('Checkout'), findsWidgets);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.text('Alerts'), findsWidgets);
    expect(find.text('Finances'), findsWidgets);
  });

  testWidgets('Inventory screen smoke render with empty local database', (
    tester,
  ) async {
    await _pumpScreen(tester, const InventoryScreen());

    expect(find.text('Inventory Audit'), findsOneWidget);
    expect(find.text('All Stock'), findsOneWidget);
    expect(find.text('Unmapped'), findsOneWidget);
    expect(find.text('Purchases'), findsOneWidget);
  });

  testWidgets(
    'Alerts screen smoke render without removed pseudo-alert categories',
    (tester) async {
      await _pumpScreen(tester, const AlertsScreen());

      expect(find.text('Alerts'), findsOneWidget);
      expect(find.textContaining('All  '), findsWidgets);
      expect(find.textContaining('Critical  '), findsWidgets);
      expect(find.textContaining('MoH Pricing  '), findsWidgets);
      expect(find.textContaining('Info  '), findsNothing);
      expect(find.textContaining('Warnings  '), findsNothing);
    },
  );

  testWidgets('Finances screen smoke render with navigation controls', (
    tester,
  ) async {
    await _pumpScreen(tester, const FinancesScreen());

    expect(find.text('Financial Dashboard'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('Loan Accounts'), findsOneWidget);
  });

  testWidgets('Checkout screen shell renders without stale state crash', (
    tester,
  ) async {
    await _pumpScreen(tester, const CheckoutScreen());

    expect(find.text('Order Summary'), findsOneWidget);
    expect(find.text('Complete Sale'), findsOneWidget);
    expect(find.text('Void Order'), findsOneWidget);
  });
}
