import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:medtrack_pos/services/inventory_database.dart';

Future<void> _clearLoanData() async {
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
      // Ignore optional table differences in local test DBs.
    }
  }
}

Future<void> _seedLoanSale({
  required String receiptId,
  required String customer,
  required double amount,
}) async {
  final db = InventoryDatabase.instance;
  await db.createLoanCustomer(name: customer);
  await db.queueSale(receiptId, {
    'timestamp': DateTime.now().toIso8601String(),
    'method': 'LOAN',
    'customer': customer,
    'subtotal': amount,
    'moph_tax': 0.0,
    'vat': 0.0,
    'grand_total': amount,
    'items': [
      {
        'barcode': 'LOAN-ITEM-1',
        'product': 'Loan Product',
        'dosage': '500mg',
        'qty': 1,
        'price': amount,
        'total': amount,
      },
    ],
  });
}

LoanCustomerSummary _findByName(
  List<LoanCustomerSummary> summaries,
  String name,
) {
  return summaries.firstWhere(
    (row) => row.name.toLowerCase() == name.toLowerCase(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _clearLoanData();
  });

  test('valid repayment is persisted and outstanding decreases', () async {
    final db = InventoryDatabase.instance;
    await _seedLoanSale(
      receiptId: 'LOAN-R-1',
      customer: 'Alice',
      amount: 120.0,
    );

    final before = await db.getLoanCustomerSummaries();
    expect(
      _findByName(before, 'Alice').outstandingAmount,
      closeTo(120.0, 0.0001),
    );

    await db.recordLoanRepayment(
      customerName: 'Alice',
      amountPaid: 20.0,
      note: 'Partial payment',
      paymentMethod: 'CASH',
    );

    final after = await db.getLoanCustomerSummaries();
    final alice = _findByName(after, 'Alice');
    expect(alice.totalLoanAmount, closeTo(120.0, 0.0001));
    expect(alice.totalRepaidAmount, closeTo(20.0, 0.0001));
    expect(alice.outstandingAmount, closeTo(100.0, 0.0001));

    final history = await db.getLoanRepaymentsForCustomer('Alice');
    expect(history, isNotEmpty);
    expect(history.first.amountPaid, closeTo(20.0, 0.0001));
    expect(history.first.note, 'Partial payment');
  });

  test('overpayment is rejected and balance remains unchanged', () async {
    final db = InventoryDatabase.instance;
    await _seedLoanSale(receiptId: 'LOAN-R-2', customer: 'Bob', amount: 50.0);

    await expectLater(
      () => db.recordLoanRepayment(customerName: 'Bob', amountPaid: 60.0),
      throwsStateError,
    );

    final rows = await db.getLoanCustomerSummaries();
    final bob = _findByName(rows, 'Bob');
    expect(bob.totalRepaidAmount, closeTo(0.0, 0.0001));
    expect(bob.outstandingAmount, closeTo(50.0, 0.0001));
  });

  test('zero and non-positive repayments are rejected', () async {
    final db = InventoryDatabase.instance;
    await _seedLoanSale(receiptId: 'LOAN-R-3', customer: 'Carla', amount: 40.0);

    await expectLater(
      () => db.recordLoanRepayment(customerName: 'Carla', amountPaid: 0),
      throwsArgumentError,
    );
    await expectLater(
      () => db.recordLoanRepayment(customerName: 'Carla', amountPaid: -2),
      throwsArgumentError,
    );
  });

  test(
    'full repayment reduces outstanding to zero without corrupting sales history',
    () async {
      final db = InventoryDatabase.instance;
      await _seedLoanSale(
        receiptId: 'LOAN-R-4A',
        customer: 'Dina',
        amount: 30.0,
      );
      await _seedLoanSale(
        receiptId: 'LOAN-R-4B',
        customer: 'Dina',
        amount: 20.0,
      );

      final historyBefore = await db.getSalesHistory(limit: 20);
      final loanSalesBefore = historyBefore
          .where((sale) => sale.method.toUpperCase() == 'LOAN')
          .fold<double>(0, (sum, sale) => sum + sale.grandTotal);

      await db.recordLoanRepayment(customerName: 'Dina', amountPaid: 50.0);

      final outstandingTotal = await db.getOutstandingDebtTotal();
      expect(outstandingTotal, closeTo(0.0, 0.0001));

      final summaries = await db.getLoanCustomerSummaries();
      expect(
        summaries.where((row) => row.name.toLowerCase() == 'dina'),
        isEmpty,
      );

      final historyAfter = await db.getSalesHistory(limit: 20);
      final loanSalesAfter = historyAfter
          .where((sale) => sale.method.toUpperCase() == 'LOAN')
          .fold<double>(0, (sum, sale) => sum + sale.grandTotal);
      expect(historyAfter.length, historyBefore.length);
      expect(loanSalesAfter, closeTo(loanSalesBefore, 0.0001));

      final repayments = await db.getLoanRepaymentsForCustomer('Dina');
      expect(repayments, isNotEmpty);
      expect(repayments.first.amountPaid, closeTo(50.0, 0.0001));
    },
  );
}
