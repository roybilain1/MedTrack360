import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/inventory_database.dart';
import '../../theme/app_theme.dart';

// ── Sale view models ──────────────────────────────────────────────────────────

enum _PayMethod { cash, visa, loan }

/// A single line item on a sale receipt.
class _SaleLineItem {
  const _SaleLineItem({
    required this.name,
    required this.dosage,
    required this.qty,
    required this.unitPrice,
  });
  final String name;
  final String dosage;
  final int qty;
  final double unitPrice;
  double get total => qty * unitPrice;
}

class _SaleRecord {
  const _SaleRecord({
    required this.receiptId,
    required this.time,
    required this.method,
    required this.amount,
    required this.lineItems,
    this.createdAt,
    this.customer,
  });
  final String receiptId;
  final String time;
  final _PayMethod method;
  final double amount;
  final List<_SaleLineItem> lineItems;
  final DateTime? createdAt;
  final String? customer;

  int get items => lineItems.length;
}

class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key});

  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  final _db = InventoryDatabase.instance;
  StreamSubscription<int>? _inventorySub;
  bool _weeklyView = false;
  bool _loading = true;
  List<_SaleRecord> _sales = [];
  List<LoanCustomerSummary> _loanSummaries = [];
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSales();
    _inventorySub = _db.inventoryChanges.listen((_) {
      if (!mounted) return;
      _loadSales();
    });
  }

  @override
  void dispose() {
    _inventorySub?.cancel();
    super.dispose();
  }

  Future<void> _loadSales() async {
    final token = ++_loadGeneration;
    if (mounted) {
      setState(() => _loading = true);
    }
    final history = await _db.getSalesHistory(limit: 400);
    final loanSummaries = await _db.getLoanCustomerSummaries();

    final mapped = history.map((sale) {
      _PayMethod method;
      switch (sale.method) {
        case 'VISA':
          method = _PayMethod.visa;
          break;
        case 'LOAN':
          method = _PayMethod.loan;
          break;
        default:
          method = _PayMethod.cash;
      }

      final lineItems = sale.items
          .map(
            (e) => _SaleLineItem(
              name: e.product,
              dosage: e.dosage,
              qty: e.qty,
              unitPrice: e.price,
            ),
          )
          .toList();

      final ts = sale.timestamp;
      final timeStr =
          '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

      return _SaleRecord(
        receiptId: sale.receiptId,
        time: timeStr,
        method: method,
        amount: sale.grandTotal,
        lineItems: lineItems,
        createdAt: ts,
        customer: sale.customer,
      );
    }).toList();

    if (!mounted || token != _loadGeneration) return;
    setState(() {
      _sales = mapped;
      _loanSummaries = loanSummaries;
      _loading = false;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<_SaleRecord> get _periodSales {
    final now = DateTime.now();
    if (_weeklyView) {
      final start = now.subtract(const Duration(days: 6));
      return _sales
          .where((s) => !((s.createdAt ?? now).isBefore(start)))
          .toList();
    }
    return _sales.where((s) => _isSameDay(s.createdAt ?? now, now)).toList();
  }

  Future<void> _exportCsv() async {
    final rows = <String>[
      'receipt_id,timestamp,method,customer,item_count,amount',
      ..._periodSales.map((s) {
        final customer = (s.customer ?? '').replaceAll(',', ' ');
        return '${s.receiptId},${(s.createdAt ?? DateTime.now()).toIso8601String()},${s.method.name.toUpperCase()},$customer,${s.items},${s.amount.toStringAsFixed(2)}';
      }),
    ];
    final csv = rows.join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openLoanAccounts() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LoanAccountsDialog(
        initialSummaries: _loanSummaries,
        onRepaymentRecorded: _loadSales,
      ),
    );
  }

  double get _cashTotal => _periodSales
      .where((s) => s.method == _PayMethod.cash)
      .fold(0, (s, r) => s + r.amount);

  double get _visaTotal => _periodSales
      .where((s) => s.method == _PayMethod.visa)
      .fold(0, (s, r) => s + r.amount);

  double get _outstandingDebtTotal =>
      _loanSummaries.fold<double>(0, (sum, row) => sum + row.outstandingAmount);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Financial Dashboard', style: tt.headlineLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Revenue summary and transaction history.',
                    style: tt.bodyMedium?.copyWith(
                      color: MedTrackColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Daily / Weekly toggle
              Container(
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: MedTrackColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PeriodBtn(
                      label: 'Today',
                      selected: !_weeklyView,
                      onTap: () => setState(() => _weeklyView = false),
                    ),
                    _PeriodBtn(
                      label: 'This Week',
                      selected: _weeklyView,
                      onTap: () => setState(() => _weeklyView = true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _openLoanAccounts,
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                ),
                label: const Text('Loan Accounts'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MedTrackColors.textSecondary,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: const RoundedRectangleBorder(
                    borderRadius: MedTrackShapes.buttonRadius,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── KPI Cards ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  icon: Icons.payments_outlined,
                  iconColor: MedTrackColors.teal,
                  iconBg: const Color(0xFFCCFBF1),
                  label: 'Cash in Drawer',
                  value: '\$${_cashTotal.toStringAsFixed(2)}',
                  trend: _weeklyView ? 'This week' : 'Today',
                  trendUp: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  icon: Icons.credit_card_rounded,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEFF6FF),
                  label: 'Visa Settlements',
                  value: '\$${_visaTotal.toStringAsFixed(2)}',
                  trend: _weeklyView ? 'This week' : 'Today',
                  trendUp: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: MedTrackColors.warning,
                  iconBg: MedTrackColors.warningContainer,
                  label: 'Outstanding Debt',
                  value: '\$${_outstandingDebtTotal.toStringAsFixed(2)}',
                  trend: '${_loanSummaries.length} accounts',
                  trendUp: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Revenue Chart ──────────────────────────────────────────────────
          _RevenueChartCard(sales: _periodSales, weeklyView: _weeklyView),
          const SizedBox(height: 20),

          // ── Sales History Table ────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: MedTrackColors.surface,
                borderRadius: MedTrackShapes.cardRadius,
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: MedTrackShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Table header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text('Sales History', style: tt.titleMedium),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCCFBF1),
                            borderRadius: MedTrackShapes.chipRadius,
                          ),
                          child: Text(
                            '${_periodSales.length} transactions',
                            style: tt.labelSmall?.copyWith(
                              color: MedTrackColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Export stub
                        OutlinedButton.icon(
                          onPressed: _exportCsv,
                          icon: const Icon(Icons.download_rounded, size: 14),
                          label: const Text('Export CSV'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MedTrackColors.textSecondary,
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: MedTrackShapes.buttonRadius,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Column header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    color: MedTrackColors.surfaceVariant,
                    child: Row(
                      children: [
                        _ColHdr('Receipt ID', flex: 3),
                        _ColHdr('Time', flex: 2),
                        _ColHdr('Items', flex: 1),
                        _ColHdr('Method', flex: 2),
                        _ColHdr('Amount', flex: 2),
                        const SizedBox(width: 40), // receipt icon
                      ],
                    ),
                  ),
                  // Rows
                  Expanded(
                    child: ListView.builder(
                      itemCount: _periodSales.length,
                      itemBuilder: (context, i) {
                        final record = _periodSales[i];
                        return _SaleRow(
                          record: record,
                          isLast: i == _periodSales.length - 1,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.trend,
    required this.trendUp,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final String trend;
  final bool trendUp;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        borderRadius: MedTrackShapes.cardRadius,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: MedTrackShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: trendUp
                      ? MedTrackColors.successContainer
                      : MedTrackColors.warningContainer,
                  borderRadius: MedTrackShapes.chipRadius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trendUp
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 12,
                      color: trendUp
                          ? MedTrackColors.success
                          : MedTrackColors.warning,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      trend,
                      style: tt.labelSmall?.copyWith(
                        color: trendUp
                            ? MedTrackColors.success
                            : MedTrackColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: tt.bodySmall?.copyWith(color: MedTrackColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: tt.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: MedTrackColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SaleRow extends StatefulWidget {
  const _SaleRow({required this.record, required this.isLast});
  final _SaleRecord record;
  final bool isLast;

  @override
  State<_SaleRow> createState() => _SaleRowState();
}

class _SaleRowState extends State<_SaleRow> {
  bool _hovered = false;

  String get _methodLabel {
    switch (widget.record.method) {
      case _PayMethod.cash:
        return 'CASH';
      case _PayMethod.visa:
        return 'VISA';
      case _PayMethod.loan:
        return 'LOAN';
    }
  }

  Color get _methodColor {
    switch (widget.record.method) {
      case _PayMethod.cash:
        return MedTrackColors.teal;
      case _PayMethod.visa:
        return const Color(0xFF2563EB);
      case _PayMethod.loan:
        return MedTrackColors.warning;
    }
  }

  Color get _methodBg {
    switch (widget.record.method) {
      case _PayMethod.cash:
        return const Color(0xFFCCFBF1);
      case _PayMethod.visa:
        return const Color(0xFFEFF6FF);
      case _PayMethod.loan:
        return MedTrackColors.warningContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hovered ? const Color(0xFFF0FDFA) : MedTrackColors.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              child: Row(
                children: [
                  // Receipt ID
                  Expanded(
                    flex: 3,
                    child: Text(
                      widget.record.receiptId,
                      style: tt.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ),
                  // Time
                  Expanded(
                    flex: 2,
                    child: Text(widget.record.time, style: tt.bodyMedium),
                  ),
                  // Items
                  Expanded(
                    flex: 1,
                    child: Text('${widget.record.items}', style: tt.bodyMedium),
                  ),
                  // Method chip
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _methodBg,
                        borderRadius: MedTrackShapes.chipRadius,
                      ),
                      child: Text(
                        _methodLabel,
                        style: tt.labelSmall?.copyWith(
                          color: _methodColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  // Amount
                  Expanded(
                    flex: 2,
                    child: Text(
                      '\$${widget.record.amount.toStringAsFixed(2)}',
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: MedTrackColors.textPrimary,
                      ),
                    ),
                  ),
                  // View receipt
                  SizedBox(
                    width: 40,
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 150),
                      child: IconButton(
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        color: MedTrackColors.teal,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'View Receipt',
                        onPressed: () => _showReceipt(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.isLast)
              const Divider(height: 1, indent: 20, endIndent: 20),
          ],
        ),
      ),
    );
  }

  void _showReceipt(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _FullReceiptDialog(record: widget.record),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine(this.label, this.value, {this.secondary = false});
  final String label;
  final String value;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          label,
          style: secondary
              ? tt.bodySmall?.copyWith(color: MedTrackColors.textSecondary)
              : tt.bodyMedium?.copyWith(color: MedTrackColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: secondary
              ? tt.bodySmall?.copyWith(color: MedTrackColors.textSecondary)
              : tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full Receipt Dialog — preserves MoPH receipt format used at checkout
// ─────────────────────────────────────────────────────────────────────────────

class _FullReceiptDialog extends StatelessWidget {
  const _FullReceiptDialog({required this.record});
  final _SaleRecord record;

  static const double _mophRate = 0.03;
  static const double _vatRate = 0.11;

  double get _subtotal => record.lineItems.fold(0.0, (s, e) => s + e.total);
  double get _mophTax => _subtotal * _mophRate;
  double get _vat => _subtotal * _vatRate;

  String get _methodLabel {
    switch (record.method) {
      case _PayMethod.cash:
        return 'CASH';
      case _PayMethod.visa:
        return 'VISA';
      case _PayMethod.loan:
        return 'LOAN';
    }
  }

  Color get _methodColor {
    switch (record.method) {
      case _PayMethod.cash:
        return MedTrackColors.teal;
      case _PayMethod.visa:
        return const Color(0xFF2563EB);
      case _PayMethod.loan:
        return MedTrackColors.warning;
    }
  }

  Color get _methodBg {
    switch (record.method) {
      case _PayMethod.cash:
        return const Color(0xFFCCFBF1);
      case _PayMethod.visa:
        return const Color(0xFFEFF6FF);
      case _PayMethod.loan:
        return MedTrackColors.warningContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: MedTrackColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header banner ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [MedTrackColors.navRailBg, MedTrackColors.teal],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.receiptId,
                        style: tt.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Al-Amin Pharmacy · Feb 24, 2026',
                        style: tt.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: MedTrackShapes.chipRadius,
                    ),
                    child: Text(
                      record.time,
                      style: tt.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Scrollable body ────────────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Licence + payment method
                    Row(
                      children: [
                        const Icon(
                          Icons.store_rounded,
                          size: 13,
                          color: MedTrackColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIC-BEY-0041',
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _methodBg,
                            borderRadius: MedTrackShapes.chipRadius,
                          ),
                          child: Text(
                            _methodLabel,
                            style: tt.labelSmall?.copyWith(
                              color: _methodColor,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (record.customer != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            size: 13,
                            color: MedTrackColors.warning,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Account: ${record.customer}',
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    // Items table
                    Text(
                      'Items Dispensed',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          // Column header
                          Container(
                            color: MedTrackColors.surfaceVariant,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    'PRODUCT',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 38,
                                  child: Text(
                                    'QTY',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                SizedBox(
                                  width: 54,
                                  child: Text(
                                    'UNIT',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                SizedBox(
                                  width: 62,
                                  child: Text(
                                    'TOTAL',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Item rows
                          ...record.lineItems.asMap().entries.map((e) {
                            final i = e.key;
                            final item = e.value;
                            return Column(
                              children: [
                                if (i > 0) const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: tt.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              item.dosage,
                                              style: tt.labelSmall?.copyWith(
                                                color: MedTrackColors
                                                    .textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 38,
                                        child: Text(
                                          '×${item.qty}',
                                          style: tt.bodySmall?.copyWith(
                                            color: MedTrackColors.textSecondary,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 54,
                                        child: Text(
                                          '\$${item.unitPrice.toStringAsFixed(2)}',
                                          style: tt.bodySmall?.copyWith(
                                            color: MedTrackColors.textSecondary,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 62,
                                        child: Text(
                                          '\$${item.total.toStringAsFixed(2)}',
                                          style: tt.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: MedTrackColors.teal,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    // Tax breakdown
                    _ReceiptLine(
                      'Subtotal',
                      '\$${_subtotal.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 6),
                    _ReceiptLine(
                      'MoPH Levy (3%)',
                      '\$${_mophTax.toStringAsFixed(2)}',
                      secondary: true,
                    ),
                    const SizedBox(height: 6),
                    _ReceiptLine(
                      'VAT (11%)',
                      '\$${_vat.toStringAsFixed(2)}',
                      secondary: true,
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'Total Charged',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '\$${record.amount.toStringAsFixed(2)}',
                          style: tt.headlineMedium?.copyWith(
                            color: MedTrackColors.teal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Pharmacy branding
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: MedTrackColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.local_pharmacy_rounded,
                            size: 14,
                            color: MedTrackColors.teal,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Al-Amin Pharmacy  ·  Beirut, LB',
                            style: tt.labelSmall?.copyWith(
                              color: MedTrackColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'MedTrack 360  ·  HW-00423',
                            style: tt.labelSmall?.copyWith(
                              color: MedTrackColors.textDisabled,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
            // ── Actions ────────────────────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Print sent to connected receipt printer',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.print_rounded, size: 14),
                    label: const Text('Print'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MedTrackColors.slateGrey,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: MedTrackColors.teal,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PeriodBtn extends StatelessWidget {
  const _PeriodBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? MedTrackColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: tt.labelMedium?.copyWith(
            color: selected
                ? MedTrackColors.textPrimary
                : MedTrackColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ColHdr extends StatelessWidget {
  const _ColHdr(this.label, {this.flex = 1});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: MedTrackColors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revenue Bar Chart Card
// ─────────────────────────────────────────────────────────────────────────────

class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.sales, required this.weeklyView});

  final List<_SaleRecord> sales;
  final bool weeklyView;
  static const List<String> _weekDayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  List<({String label, double amount})> _buildData() {
    if (weeklyView) {
      final totals = List<double>.filled(7, 0.0);
      for (final s in sales) {
        final dt = s.createdAt ?? DateTime.now();
        totals[dt.weekday - 1] += s.amount;
      }
      return List.generate(7, (i) {
        return (label: _weekDayLabels[i], amount: totals[i]);
      });
    }

    final hourly = <int, double>{};
    for (final s in sales) {
      final dt = s.createdAt ?? DateTime.now();
      hourly.update(dt.hour, (v) => v + s.amount, ifAbsent: () => s.amount);
    }
    final hours = hourly.keys.toList()..sort();
    return hours.map((h) {
      return (label: '${h.toString().padLeft(2, '0')}:00', amount: hourly[h]!);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final data = _buildData();
    final maxAmt = data.fold(0.0, (m, d) => math.max(m, d.amount));
    final totalRevenue = data.fold(0.0, (s, d) => s + d.amount);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        borderRadius: MedTrackShapes.cardRadius,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: MedTrackShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ─────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFBF1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: MedTrackColors.teal,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weeklyView ? 'Weekly Revenue' : 'Hourly Revenue — Today',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    weeklyView
                        ? 'Database transactions for this week'
                        : 'Database transactions for today · ${data.length} points',
                    style: tt.bodySmall?.copyWith(
                      color: MedTrackColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Total chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFBF1),
                  borderRadius: MedTrackShapes.chipRadius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 13,
                      color: MedTrackColors.teal,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '\$${totalRevenue.toStringAsFixed(0)} total',
                      style: tt.labelMedium?.copyWith(
                        color: MedTrackColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Chart ───────────────────────────────────────────────────────────
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _RevenuePainter(data: data, maxAmt: maxAmt),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoanAccountsDialog extends StatefulWidget {
  const _LoanAccountsDialog({
    required this.initialSummaries,
    this.onRepaymentRecorded,
  });

  final List<LoanCustomerSummary> initialSummaries;

  final VoidCallback? onRepaymentRecorded;

  @override
  State<_LoanAccountsDialog> createState() => _LoanAccountsDialogState();
}

class _LoanAccountsDialogState extends State<_LoanAccountsDialog> {
  bool _loading = false;
  late List<LoanCustomerSummary> _summaries;

  @override
  void initState() {
    super.initState();
    _summaries = List<LoanCustomerSummary>.from(widget.initialSummaries);
  }

  Future<void> _openRepaymentDialog(LoanCustomerSummary summary) async {
    final paid = await showDialog<double>(
      context: context,
      builder: (_) => _LoanRepaymentDialog(initialSummary: summary),
    );
    if (paid != null && paid > 0) {
      setState(() {
        _summaries = _summaries
            .map(
              (row) => row.name.toLowerCase() == summary.name.toLowerCase()
                  ? LoanCustomerSummary(
                      name: row.name,
                      phone: row.phone,
                      loanCount: row.loanCount,
                      totalLoanAmount: row.totalLoanAmount,
                      totalRepaidAmount: row.totalRepaidAmount + paid,
                      outstandingAmount: (row.outstandingAmount - paid)
                          .clamp(0.0, double.infinity)
                          .toDouble(),
                      lastLoanAt: row.lastLoanAt,
                      lastRepaymentAt: DateTime.now(),
                    )
                  : row,
            )
            .where((row) => row.outstandingAmount > 0)
            .toList();
      });

      final rows = await InventoryDatabase.instance.getLoanCustomerSummaries();
      if (!mounted) return;
      setState(() {
        _summaries = rows;
      });
      widget.onRepaymentRecorded?.call();
    }
  }

  String _fmtDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: MedTrackShapes.cardRadius),
      child: SizedBox(
        width: 720,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('People With Loans', style: tt.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'List of customer accounts with current outstanding balances.',
                style: tt.bodySmall?.copyWith(
                  color: MedTrackColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (_summaries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'No loan accounts yet.',
                      style: tt.bodyMedium?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.separated(
                      itemCount: _summaries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final row = _summaries[i];
                        return ListTile(
                          title: Text(
                            row.name,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            row.phone.isEmpty
                                ? 'Loans: ${row.loanCount}  •  Last: ${_fmtDate(row.lastLoanAt)}'
                                : '${row.phone}  •  Loans: ${row.loanCount}  •  Last: ${_fmtDate(row.lastLoanAt)}',
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.textSecondary,
                            ),
                          ),
                          onTap: () => _openRepaymentDialog(row),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${row.outstandingAmount.toStringAsFixed(2)}',
                                style: tt.titleSmall?.copyWith(
                                  color: MedTrackColors.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: () => _openRepaymentDialog(row),
                                style: TextButton.styleFrom(
                                  foregroundColor: MedTrackColors.teal,
                                  minimumSize: const Size(0, 0),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Pay Loan'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: MedTrackColors.teal,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoanRepaymentDialog extends StatefulWidget {
  const _LoanRepaymentDialog({required this.initialSummary});

  final LoanCustomerSummary initialSummary;

  @override
  State<_LoanRepaymentDialog> createState() => _LoanRepaymentDialogState();
}

class _LoanRepaymentDialogState extends State<_LoanRepaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _loadingHistory = true;
  bool _saving = false;
  late LoanCustomerSummary _summary;
  List<LoanRepaymentRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    _loadHistory();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await InventoryDatabase.instance
        .getLoanRepaymentsForCustomer(_summary.name, limit: 6);

    if (!mounted) return;
    setState(() {
      _history = history;
      _loadingHistory = false;
    });
  }

  String _fmtDateTime(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd $hh:$min';
  }

  String? _validateAmount(String? value) {
    final raw = (value ?? '').trim();
    final summary = _summary;
    if (raw.isEmpty) return 'Enter a repayment amount.';
    final amount = double.tryParse(raw);
    if (amount == null) return 'Repayment amount must be numeric.';
    if (amount <= 0) return 'Repayment amount must be greater than 0.';
    if (summary != null && amount > summary.outstandingAmount) {
      return 'Amount cannot exceed current outstanding balance.';
    }
    return null;
  }

  Future<void> _submitRepayment() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final summary = _summary;
    if (summary == null) return;

    final amount = double.parse(_amountController.text.trim());
    setState(() => _saving = true);
    try {
      await InventoryDatabase.instance.recordLoanRepayment(
        customerName: summary.name,
        amountPaid: amount,
        note: _noteController.text.trim(),
        paymentMethod: 'CASH',
      );
      if (!mounted) return;
      Navigator.pop(context, amount);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: MedTrackShapes.cardRadius),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Loan Details', style: tt.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                _summary.name,
                style: tt.titleMedium?.copyWith(
                  color: MedTrackColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_summary.phone.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _summary.phone,
                    style: tt.bodySmall?.copyWith(
                      color: MedTrackColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MedTrackColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Outstanding: \$${_summary.outstandingAmount.toStringAsFixed(2)}',
                      style: tt.titleMedium?.copyWith(
                        color: MedTrackColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Loan sales: \$${_summary.totalLoanAmount.toStringAsFixed(2)}  •  Repaid: \$${_summary.totalRepaidAmount.toStringAsFixed(2)}',
                      style: tt.bodySmall?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Loans: ${_summary.loanCount}  •  Last loan: ${_summary.lastLoanAt == null ? '-' : _fmtDateTime(_summary.lastLoanAt!)}',
                      style: tt.bodySmall?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Record Repayment', style: tt.titleMedium),
              const SizedBox(height: 8),
              if (_loadingHistory)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _amountController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount Paid',
                        prefixText: '\$',
                      ),
                      validator: _validateAmount,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _noteController,
                      enabled: !_saving,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Recent Repayments', style: tt.titleSmall),
              const SizedBox(height: 8),
              if (_history.isEmpty)
                Text(
                  'No repayments recorded yet.',
                  style: tt.bodySmall?.copyWith(
                    color: MedTrackColors.textSecondary,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Repayment  \$${item.amountPaid.toStringAsFixed(2)}',
                          style: tt.bodyMedium,
                        ),
                        subtitle: Text(
                          '${item.paymentMethod}  •  ${_fmtDateTime(item.createdAt)}${item.note.trim().isEmpty ? '' : '  •  ${item.note.trim()}'}',
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submitRepayment,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.payments_outlined, size: 16),
                    style: FilledButton.styleFrom(
                      backgroundColor: MedTrackColors.teal,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                    ),
                    label: Text(_saving ? 'Saving...' : 'Confirm Payment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revenue CustomPainter
// ─────────────────────────────────────────────────────────────────────────────

class _RevenuePainter extends CustomPainter {
  const _RevenuePainter({required this.data, required this.maxAmt});

  final List<({String label, double amount})> data;
  final double maxAmt;

  static const double _leftPad = 52;
  static const double _rightPad = 12;
  static const double _topPad = 10;
  static const double _bottomPad = 36;
  static const int _gridLines = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - _leftPad - _rightPad;
    final chartH = size.height - _topPad - _bottomPad;
    final yMax = (maxAmt * 1.20).clamp(1.0, double.infinity);

    _drawGrid(canvas, size, chartW, chartH, yMax);
    _drawBars(canvas, size, chartW, chartH, yMax);
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double chartW,
    double chartH,
    double yMax,
  ) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    for (int i = 0; i <= _gridLines; i++) {
      final y = _topPad + chartH * (1 - i / _gridLines);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(_leftPad + chartW, y),
        gridPaint,
      );
      final val = yMax * i / _gridLines;
      _paintText(
        canvas,
        '\$${val < 1000 ? val.toStringAsFixed(0) : '${(val / 1000).toStringAsFixed(1)}k'}',
        Offset(0, y - 6),
        color: MedTrackColors.slateGreyLight,
        fontSize: 9,
      );
    }
  }

  void _drawBars(
    Canvas canvas,
    Size size,
    double chartW,
    double chartH,
    double yMax,
  ) {
    if (data.isEmpty) return;
    final n = data.length;
    final slotW = chartW / n;
    final barW = (slotW * 0.52).clamp(8.0, 36.0);
    final offsetX = (slotW - barW) / 2;

    for (int i = 0; i < n; i++) {
      final d = data[i];
      final ratio = d.amount / yMax;
      final barH = (chartH * ratio).clamp(4.0, chartH);
      final x = _leftPad + i * slotW + offsetX;
      final y = _topPad + chartH - barH;

      // Gradient bar fill
      final rect = Rect.fromLTWH(x, y, barW, barH);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      final barPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MedTrackColors.tealLight,
            MedTrackColors.teal.withValues(alpha: 0.80),
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, barPaint);

      // Sheen
      final sheenPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent],
        ).createShader(Rect.fromLTWH(x, y, barW, barH * 0.5));
      canvas.drawRRect(rrect, sheenPaint);

      // Value label above bar
      if (barH > 20) {
        _paintText(
          canvas,
          '\$${d.amount.toStringAsFixed(0)}',
          Offset(x + barW / 2 - 14, y - 14),
          color: MedTrackColors.teal,
          fontSize: 8.5,
          bold: true,
        );
      }

      // X-axis label
      _paintText(
        canvas,
        d.label,
        Offset(x + barW / 2 - 10, size.height - _bottomPad + 7),
        color: MedTrackColors.textSecondary,
        fontSize: 9,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset, {
    Color color = MedTrackColors.textSecondary,
    double fontSize = 10,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _RevenuePainter old) =>
      old.data != data || old.maxAmt != maxAmt;
}
