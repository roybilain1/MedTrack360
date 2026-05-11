import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/screens/finances/finances_screen.dart';
import 'package:medtrack_pos/services/inventory_database.dart';

Future<void> _resetLoanUiData() async {
  final db = await InventoryDatabase.instance.db;
  const tables = <String>[
    'offline_sale_queue',
    'sale_items_cache',
    'loan_customers',
    'loan_repayments',
    'sync_outbox',
  ];
  for (final table in tables) {
    try {
      await db.delete(table);
    } catch (_) {
      // Ignore optional table differences.
    }
  }
}

Future<void> _seedLoanAccount() async {
  final db = InventoryDatabase.instance;
  await db.createLoanCustomer(name: 'Loan UI Customer', phone: '71-000-111');
  await db.queueSale('LOAN-UI-1', {
    'timestamp': DateTime.now().toIso8601String(),
    'method': 'LOAN',
    'customer': 'Loan UI Customer',
    'subtotal': 100.0,
    'moph_tax': 0.0,
    'vat': 0.0,
    'grand_total': 100.0,
    'items': [
      {
        'barcode': 'LOAN-UI-BARCODE',
        'product': 'UI Loan Product',
        'dosage': '50mg',
        'qty': 1,
        'price': 100.0,
        'total': 100.0,
      },
    ],
  });
}

Future<void> _pumpFinances(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: FinancesScreen())),
  );
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump(const Duration(milliseconds: 80));
    if (find.text('Loan Accounts').evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _pumpFor(WidgetTester tester, {int ticks = 12}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var i = 0; i < 40; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _resetLoanUiData();
    await _seedLoanAccount();
  });

  testWidgets('loan account row opens repayment flow and updates balance', (
    tester,
  ) async {
    await _pumpFinances(tester);

    await tester.tap(find.text('Loan Accounts'));
    await _pumpFor(tester);
    await _waitForText(tester, 'People With Loans');

    expect(find.text('People With Loans'), findsOneWidget);
    await _waitForText(tester, 'Loan UI Customer');
    await _waitForText(tester, 'Pay Loan');
    expect(find.text('Loan UI Customer'), findsOneWidget);
    expect(find.text('Pay Loan'), findsOneWidget);

    await tester.tap(find.text('Pay Loan'));
    await _pumpFor(tester);
    await _waitForText(tester, 'Loan Details');

    expect(find.text('Loan Details'), findsOneWidget);
    expect(find.text('Record Repayment'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '25');
    await tester.tap(find.text('Confirm Payment'));
    await _pumpFor(tester, ticks: 16);

    expect(find.text('People With Loans'), findsOneWidget);

    final outstanding = await InventoryDatabase.instance
        .getOutstandingDebtTotal();
    expect(outstanding, closeTo(75.0, 0.0001));
  });

  testWidgets('repayment form rejects overpayment and invalid values', (
    tester,
  ) async {
    await _pumpFinances(tester);

    await tester.tap(find.text('Loan Accounts'));
    await _pumpFor(tester);
    await _waitForText(tester, 'Pay Loan');
    await tester.tap(find.text('Pay Loan'));
    await _pumpFor(tester);
    await _waitForText(tester, 'Loan Details');

    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.tap(find.text('Confirm Payment'));
    await tester.pump();
    expect(
      find.text('Repayment amount must be greater than 0.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).first, '1000');
    await tester.tap(find.text('Confirm Payment'));
    await tester.pump();
    expect(
      find.text('Amount cannot exceed current outstanding balance.'),
      findsOneWidget,
    );
  });
}
