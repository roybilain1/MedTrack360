import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/inventory_database.dart';

// ── MoPH box-authentication status ────────────────────────────────────────────

enum BoxAuthStatus {
  /// Awaiting response from the MoPH Command Center.
  pending,

  /// Box confirmed as coming from an authorised distributor.
  verified,

  /// Box could NOT be traced to an authorised distributor — flag for inspection.
  unverified,
}

// ── Data model ────────────────────────────────────────────────────────────────

class _OrderItem {
  _OrderItem({
    required this.barcode,
    required this.product,
    required this.dosage,
    required this.price,
    this.mophCeiling,
    this.batchNumber = '',
    this.expiry = '',
    this.boxAuth = BoxAuthStatus.pending,
  });

  final String barcode;
  final String product;
  final String dosage;
  final double price;

  /// MoPH official price ceiling for this medication.  Null = not in registry.
  final double? mophCeiling;

  /// Batch / lot number for traceability — recorded at point of sale.
  final String batchNumber;

  /// Expiry date string for traceability — shown on receipt & recorded.
  final String expiry;

  /// Box authentication result from the MoPH Command Center.
  BoxAuthStatus boxAuth;

  int qty = 1;

  double get total => price * qty;

  /// True when selling price exceeds the MoPH ceiling — legal violation.
  bool get exceedsCeiling => mophCeiling != null && price > mophCeiling!;
}

// ── MoPH EAN-13 barcode registry (loaded dynamically from local SQLite) ──

// ── Constants ─────────────────────────────────────────────────────────────────

const double _kMoPHTaxRate = 0.03; // Lebanon MoPH pharmaceutical tax (3 %)
const double _kVatRate = 0.11; // VAT 11 %

// ═════════════════════════════════════════════════════════════════════════════
// Checkout Screen
// ═════════════════════════════════════════════════════════════════════════════

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _listKey = GlobalKey<AnimatedListState>();
  final List<_OrderItem> _items = [];

  // ── USB scanner debounce guard ────────────────────────────────────────────
  String? _lastScannedBarcode;
  DateTime _lastScanTime = DateTime(0);

  // ── Entry point called by both KeyboardListener and onSubmitted ───────────

  void _handleScan(String raw) {
    final barcode = raw.trim();
    if (barcode.isEmpty) return;

    // Debounce: drop exact duplicate fired within 80 ms
    final now = DateTime.now();
    if (barcode == _lastScannedBarcode &&
        now.difference(_lastScanTime).inMilliseconds < 80) {
      _barcodeController.clear();
      _returnFocus();
      return;
    }
    _lastScannedBarcode = barcode;
    _lastScanTime = now;

    _barcodeController.clear();
    _lookupProduct(barcode);
  }

  // ── Product lookup ────────────────────────────────────────────────────────

  Future<void> _lookupProduct(String barcode) async {
    // ── Already in the current order → just increment qty ──────────────────
    final existingIdx = _items.indexWhere((e) => e.barcode == barcode);
    if (existingIdx != -1) {
      setState(() => _items[existingIdx].qty++);
      _returnFocus();
      return;
    }

    // ── Found in local database → add to order ──────────────────────────────
    final dbItems = await InventoryDatabase.instance.searchInventory(barcode);
    final match = dbItems.where((e) => e.barcode == barcode).firstOrNull;

    if (match != null) {
      if (match.isPendingApproval || match.isBlocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${match.name} is awaiting ministry approval and cannot be sold yet.',
              ),
              backgroundColor: MedTrackColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _returnFocus();
        return;
      }
      final item = _OrderItem(
        barcode: match.barcode,
        product: match.name,
        dosage: match.dosage,
        price: match.price,
        mophCeiling: match.mophCeiling,
        batchNumber: match.batchNumber,
        expiry: match.expiry,
        boxAuth: BoxAuthStatus.verified,
      );
      _items.insert(0, item);
      _listKey.currentState?.insertItem(
        0,
        duration: const Duration(milliseconds: 350),
      );
      setState(() {});
      _returnFocus();
      return;
    }

    // ── Not in catalogue → open "New Product Mapping" dialog ─────────────────
    // Focus intentionally leaves the barcode field while the dialog is open.
    // We reclaim focus in the .then() / await continuation regardless of
    // whether the pharmacist confirmed or cancelled.
    if (!mounted) return;
    final newItem = await showDialog<_OrderItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewProductMappingDialog(barcode: barcode),
    );

    if (!mounted) return;

    if (newItem != null) {
      _items.insert(0, newItem);
      _listKey.currentState?.insertItem(
        0,
        duration: const Duration(milliseconds: 350),
      );
      setState(() {});
    }

    // Always return focus after dialog resolves (confirm OR cancel)
    _returnFocus();
  }

  // ── Return focus to barcode field ─────────────────────────────────────────
  //
  // Uses addPostFrameCallback so the focus engine has fully settled before we
  // call requestFocus (important after async gaps and after dialog pops).
  void _returnFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _barcodeFocus.requestFocus();
    });
  }

  void _removeItem(int index) {
    final removed = _items.removeAt(index);
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _OrderItemRow(
        item: removed,
        animation: animation,
        onRemove: () {},
        onQtyChanged: (_) {},
      ),
      duration: const Duration(milliseconds: 280),
    );
    setState(() {});
  }

  void _clearOrder() {
    for (var i = _items.length - 1; i >= 0; i--) {
      _removeItem(i);
    }
  }

  // ── Totals ────────────────────────────────────────────────────────────────

  double get _subtotal => _items.fold(0.0, (sum, e) => sum + e.total);
  double get _mophTax => _subtotal * _kMoPHTaxRate;
  double get _vat => _subtotal * _kVatRate;
  double get _grandTotal => _subtotal + _mophTax + _vat;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Barcode top bar ─────────────────────────────────────────────────
        _BarcodeBar(
          controller: _barcodeController,
          focusNode: _barcodeFocus,
          onScan: _handleScan,
          itemCount: _items.length,
        ),
        // ── Main layout ─────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left 2/3 — order table
                Expanded(
                  flex: 2,
                  child: _OrderTable(
                    listKey: _listKey,
                    items: _items,
                    onRemove: _removeItem,
                    onQtyChanged: (i, qty) =>
                        setState(() => _items[i].qty = qty),
                  ),
                ),
                const SizedBox(width: 20),
                // Right 1/3 — summary
                SizedBox(
                  width: 320,
                  child: _SummaryCard(
                    subtotal: _subtotal,
                    mophTax: _mophTax,
                    vat: _vat,
                    grandTotal: _grandTotal,
                    itemCount: _items.length,
                    items: List.unmodifiable(_items),
                    onCompleteSale: _items.isEmpty ? null : () => _clearOrder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Barcode Top Bar
// ═════════════════════════════════════════════════════════════════════════════
//
// Converted to StatefulWidget so the KeyboardListener's FocusNode is created
// once in initState and disposed correctly — avoids the leak that occurs when
// a FocusNode is constructed inline inside build().
//
// Why both KeyboardListener AND onSubmitted?
//  • onSubmitted  – fires reliably for keyboard Enter on desktop Flutter.
//  • KeyboardListener – catches the Enter KeyDownEvent before the text field
//    can consume it, which covers edge-cases where onSubmitted misfires when
//    the field is inside a Form or the scanner uses a different line-ending.
// The debounce inside _handleScan (80 ms window) silently drops the duplicate.

class _BarcodeBar extends StatefulWidget {
  const _BarcodeBar({
    required this.controller,
    required this.focusNode,
    required this.onScan,
    required this.itemCount,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onScan;
  final int itemCount;

  @override
  State<_BarcodeBar> createState() => _BarcodeBarcodeBarState();
}

class _BarcodeBarcodeBarState extends State<_BarcodeBar> {
  // Owned by this widget; properly disposed. Never create FocusNode inline.
  final FocusNode _klFocusNode = FocusNode(debugLabel: 'BarcodeKL');

  @override
  void dispose() {
    _klFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: MedTrackColors.surface,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // ── Barcode field ─────────────────────────────────────────────────
          Expanded(
            child: KeyboardListener(
              focusNode: _klFocusNode,
              onKeyEvent: (event) {
                // Capture Enter from the USB scanner before onSubmitted fires.
                // onSubmitted will also call onScan; the 80 ms debounce in
                // _CheckoutScreenState._handleScan drops the duplicate.
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  widget.onScan(widget.controller.text);
                }
              },
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: true,
                style: tt.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'Scan barcode or type SKU and press Enter…',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: MedTrackColors.teal,
                      size: 22,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (_, val, __) => val.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: MedTrackColors.slateGrey,
                            onPressed: () => widget.controller.clear(),
                          ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF0FDFA),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: MedTrackShapes.inputRadius,
                    borderSide: const BorderSide(
                      color: MedTrackColors.tealLight,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: MedTrackShapes.inputRadius,
                    borderSide: const BorderSide(
                      color: MedTrackColors.teal,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                // onSubmitted fires on Enter from keyboard / scanner.
                // The 80 ms debounce in _handleScan drops the duplicate that
                // also arrives from the KeyboardListener above.
                onSubmitted: widget.onScan,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // ── Item counter badge ────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: widget.itemCount == 0
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(widget.itemCount),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: MedTrackShapes.buttonRadius,
                      border: Border.all(color: MedTrackColors.tealLight),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.shopping_cart_rounded,
                          size: 16,
                          color: MedTrackColors.teal,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.itemCount} item${widget.itemCount == 1 ? '' : 's'}',
                          style: tt.labelMedium?.copyWith(
                            color: MedTrackColors.teal,
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

// ═════════════════════════════════════════════════════════════════════════════
// New Product Mapping Dialog
// ═════════════════════════════════════════════════════════════════════════════
//
// Opened automatically when the scanner reads a barcode that is not in the
// local catalogue.  The pharmacist fills in the product details and either:
//   • Confirms  → the dialog pops with an _OrderItem (added to the order)
//   • Cancels   → the dialog pops with null   (barcode is skipped)
//
// After the dialog pops, _CheckoutScreenState._returnFocus() fires so the
// barcode field immediately regains focus without any manual click.

class _NewProductMappingDialog extends StatefulWidget {
  const _NewProductMappingDialog({required this.barcode});
  final String barcode;

  @override
  State<_NewProductMappingDialog> createState() =>
      _NewProductMappingDialogState();
}

class _NewProductMappingDialogState extends State<_NewProductMappingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');
  final _expiryCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameFocus.dispose();
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _categoryCtrl.dispose();
    _stockCtrl.dispose();
    _expiryCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final inserted = await InventoryDatabase.instance.insertInventoryItem(
      barcode: widget.barcode,
      name: _nameCtrl.text.trim(),
      dosage: _dosageCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      stock: int.tryParse(_stockCtrl.text.trim()) ?? 0,
      expiry: _expiryCtrl.text.trim(),
      price: double.tryParse(_priceCtrl.text.trim()) ?? 0.00,
    );

    if (!mounted) return;

    if (!inserted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This barcode already exists in inventory.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final item = _OrderItem(
      barcode: widget.barcode,
      product: _nameCtrl.text.trim(),
      dosage: _dosageCtrl.text.trim().isEmpty ? '—' : _dosageCtrl.text.trim(),
      price: double.tryParse(_priceCtrl.text.trim()) ?? 0.00,
      expiry: _expiryCtrl.text.trim(),
    );
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: MedTrackColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 120, vertical: 80),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: MedTrackColors.warningContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.qr_code_rounded,
                        color: MedTrackColors.warning,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Product Mapping', style: tt.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            'Barcode not found. Create a new inventory item to continue.',
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: MedTrackColors.slateGrey,
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Barcode display ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: MedTrackColors.surfaceVariant,
                    borderRadius: MedTrackShapes.inputRadius,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.barcode_reader,
                        size: 16,
                        color: MedTrackColors.slateGrey,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.barcode,
                        style: tt.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: MedTrackColors.teal,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: MedTrackColors.warningContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Unknown',
                          style: tt.labelSmall?.copyWith(
                            color: MedTrackColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Product Name (required) ──────────────────────────────────
                Text(
                  'Product Name *',
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Amoxicillin 500mg Capsules',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  // Move to dosage field on Enter
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Product name is required'
                      : null,
                ),
                const SizedBox(height: 14),

                // ── Category + Stock + Expiry ──────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Category *',
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _categoryCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Antibiotic',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stock *',
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _stockCtrl,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: '0',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              final n = int.tryParse(v.trim());
                              if (n == null || n < 0) return 'Invalid';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expiry Date *',
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _expiryCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Dec 2027',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Dosage + Price side by side ──────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dosage (optional)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dosage',
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _dosageCtrl,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 500 mg',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Unit price
                    SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unit Price (\$) *',
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              hintText: '0.00',
                              prefixText: '\$  ',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _confirm(),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              if (double.tryParse(v.trim()) == null) {
                                return 'Invalid price';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Action buttons ───────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        foregroundColor: MedTrackColors.textSecondary,
                      ),
                      child: const Text('Skip — Don\'t Add'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _saving ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: MedTrackColors.teal,
                        shape: const RoundedRectangleBorder(
                          borderRadius: MedTrackShapes.buttonRadius,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.add_shopping_cart_rounded,
                              size: 16,
                            ),
                      label: Text(
                        _saving ? 'Saving...' : 'Create + Add to Order',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Order Table  (AnimatedList)
// ═════════════════════════════════════════════════════════════════════════════

class _OrderTable extends StatelessWidget {
  const _OrderTable({
    required this.listKey,
    required this.items,
    required this.onRemove,
    required this.onQtyChanged,
  });

  final GlobalKey<AnimatedListState> listKey;
  final List<_OrderItem> items;
  final ValueChanged<int> onRemove;
  final void Function(int index, int qty) onQtyChanged;

  static const _cols = ['Product', 'Dosage', 'Unit Price', 'Qty', 'Total', ''];
  static const _colWidths = [null, 90.0, 100.0, 96.0, 96.0, 40.0];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        borderRadius: MedTrackShapes.cardRadius,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: MedTrackShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Text('Current Order', style: tt.titleLarge),
                const SizedBox(width: 10),
                if (items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${items.length}',
                      style: tt.labelSmall?.copyWith(
                        color: MedTrackColors.teal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Column headers ─────────────────────────────────────────────────
          Container(
            color: MedTrackColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: List.generate(_cols.length, (i) {
                final w = _colWidths[i];
                final cell = Text(
                  _cols[i],
                  style: tt.labelSmall?.copyWith(
                    color: MedTrackColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                );
                return w != null
                    ? SizedBox(width: w, child: cell)
                    : Expanded(child: cell);
              }),
            ),
          ),
          // ── Rows ───────────────────────────────────────────────────────────
          Expanded(
            child: items.isEmpty
                ? _EmptyOrderState(tt: tt)
                : AnimatedList(
                    key: listKey,
                    padding: EdgeInsets.zero,
                    initialItemCount: items.length,
                    itemBuilder: (context, index, animation) {
                      if (index >= items.length) return const SizedBox();
                      return _OrderItemRow(
                        item: items[index],
                        animation: animation,
                        onRemove: () => onRemove(index),
                        onQtyChanged: (qty) => onQtyChanged(index, qty),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyOrderState extends StatelessWidget {
  const _EmptyOrderState({required this.tt});
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.qr_code_scanner_rounded,
            size: 48,
            color: MedTrackColors.textDisabled,
          ),
          const SizedBox(height: 12),
          Text(
            'Scan a barcode to begin',
            style: tt.bodyMedium?.copyWith(color: MedTrackColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'USB barcode scanner or keyboard entry supported',
            style: tt.bodySmall?.copyWith(color: MedTrackColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

// ── Animated order row ────────────────────────────────────────────────────────

class _OrderItemRow extends StatefulWidget {
  const _OrderItemRow({
    required this.item,
    required this.animation,
    required this.onRemove,
    required this.onQtyChanged,
  });

  final _OrderItem item;
  final Animation<double> animation;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChanged;

  @override
  State<_OrderItemRow> createState() => _OrderItemRowState();
}

class _OrderItemRowState extends State<_OrderItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: widget.animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: widget.animation,
          curve: Curves.easeIn,
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: _hovered ? const Color(0xFFF0FDFA) : Colors.transparent,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Product column — name, barcode, box-auth chip, batch/expiry
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.product,
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  widget.item.barcode,
                                  style: tt.labelSmall?.copyWith(
                                    color: MedTrackColors.textDisabled,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _BoxAuthChip(status: widget.item.boxAuth),
                              ],
                            ),
                            if (widget.item.batchNumber.isNotEmpty ||
                                widget.item.expiry.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (widget.item.batchNumber.isNotEmpty) ...[
                                    const Icon(
                                      Icons.inventory_2_outlined,
                                      size: 10,
                                      color: MedTrackColors.textDisabled,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.item.batchNumber,
                                      style: tt.labelSmall?.copyWith(
                                        color: MedTrackColors.textDisabled,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                  if (widget.item.batchNumber.isNotEmpty &&
                                      widget.item.expiry.isNotEmpty)
                                    Text(
                                      '  ·  ',
                                      style: tt.labelSmall?.copyWith(
                                        color: MedTrackColors.textDisabled,
                                        fontSize: 10,
                                      ),
                                    ),
                                  if (widget.item.expiry.isNotEmpty) ...[
                                    const Icon(
                                      Icons.event_outlined,
                                      size: 10,
                                      color: MedTrackColors.textDisabled,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Exp ${widget.item.expiry}',
                                      style: tt.labelSmall?.copyWith(
                                        color: MedTrackColors.textDisabled,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Dosage
                      SizedBox(
                        width: 90,
                        child: Text(
                          widget.item.dosage,
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ),
                      // Unit price — red + ceiling badge if violation
                      SizedBox(
                        width: 100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\$${widget.item.price.toStringAsFixed(2)}',
                              style: tt.bodyMedium?.copyWith(
                                color: widget.item.exceedsCeiling
                                    ? MedTrackColors.error
                                    : null,
                                fontWeight: widget.item.exceedsCeiling
                                    ? FontWeight.w700
                                    : null,
                              ),
                            ),
                            if (widget.item.exceedsCeiling) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.policy_rounded,
                                    size: 10,
                                    color: MedTrackColors.error,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      'Ceil \$${widget.item.mophCeiling!.toStringAsFixed(2)}',
                                      style: tt.labelSmall?.copyWith(
                                        color: MedTrackColors.error,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (widget.item.mophCeiling != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Ceil \$${widget.item.mophCeiling!.toStringAsFixed(2)}',
                                style: tt.labelSmall?.copyWith(
                                  color: MedTrackColors.textDisabled,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Qty stepper
                      SizedBox(
                        width: 96,
                        child: _QtyStepper(
                          qty: widget.item.qty,
                          onChanged: widget.onQtyChanged,
                        ),
                      ),
                      // Row total
                      SizedBox(
                        width: 96,
                        child: Text(
                          '\$${widget.item.total.toStringAsFixed(2)}',
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: MedTrackColors.teal,
                          ),
                        ),
                      ),
                      // Remove button
                      SizedBox(
                        width: 40,
                        child: AnimatedOpacity(
                          opacity: _hovered ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                            ),
                            color: MedTrackColors.error,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Remove item',
                            onPressed: widget.onRemove,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 20, endIndent: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Qty stepper ───────────────────────────────────────────────────────────────

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.qty, required this.onChanged});
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: Icons.remove_rounded,
          onTap: qty > 1 ? () => onChanged(qty - 1) : null,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 28,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: MedTrackColors.textPrimary),
          ),
        ),
        const SizedBox(width: 6),
        _StepBtn(icon: Icons.add_rounded, onTap: () => onChanged(qty + 1)),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: onTap != null
              ? MedTrackColors.surfaceVariant
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Icon(
          icon,
          size: 13,
          color: onTap != null
              ? MedTrackColors.textPrimary
              : MedTrackColors.textDisabled,
        ),
      ),
    );
  }
}

// ── Box-authentication status chip ───────────────────────────────────────────

class _BoxAuthChip extends StatelessWidget {
  const _BoxAuthChip({required this.status});
  final BoxAuthStatus status;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    switch (status) {
      case BoxAuthStatus.verified:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_rounded,
                size: 9,
                color: Color(0xFF16A34A),
              ),
              const SizedBox(width: 2),
              Text(
                'Auth',
                style: tt.labelSmall?.copyWith(
                  color: const Color(0xFF16A34A),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      case BoxAuthStatus.unverified:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: MedTrackColors.errorContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.gpp_bad_rounded,
                size: 9,
                color: MedTrackColors.error,
              ),
              const SizedBox(width: 2),
              Text(
                'Unverified',
                style: tt.labelSmall?.copyWith(
                  color: MedTrackColors.error,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      case BoxAuthStatus.pending:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: MedTrackColors.warningContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 9,
                color: MedTrackColors.warning,
              ),
              const SizedBox(width: 2),
              Text(
                'Checking…',
                style: tt.labelSmall?.copyWith(
                  color: MedTrackColors.warning,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Summary Card — stateful to track payment method selection
// ═════════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({
    required this.subtotal,
    required this.mophTax,
    required this.vat,
    required this.grandTotal,
    required this.itemCount,
    required this.items,
    required this.onCompleteSale,
  });

  final double subtotal;
  final double mophTax;
  final double vat;
  final double grandTotal;
  final int itemCount;
  final List<_OrderItem> items;
  final VoidCallback? onCompleteSale;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  String? _selectedMethod;
  String? _loanCustomer;

  bool get _canComplete =>
      widget.onCompleteSale != null &&
      _selectedMethod != null &&
      (_selectedMethod != 'LOAN' || _loanCustomer != null) &&
      _ceilingViolations == 0 &&
      _unverifiedBoxes == 0;

  int get _ceilingViolations =>
      widget.items.where((e) => e.exceedsCeiling).length;
  int get _unverifiedBoxes =>
      widget.items.where((e) => e.boxAuth == BoxAuthStatus.unverified).length;

  Future<void> _selectLoanCustomer() async {
    final customer = await showDialog<String>(
      context: context,
      builder: (_) => _LoanCustomerDialog(),
    );
    if (customer != null) {
      setState(() => _loanCustomer = customer);
    }
  }

  void _handleCompleteSale() {
    // Generate receipt ID
    final now = DateTime.now();
    final receiptId =
        'RX-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';

    showDialog<void>(
      context: context,
      builder: (_) => _ReceiptDialog(
        receiptId: receiptId,
        subtotal: widget.subtotal,
        mophTax: widget.mophTax,
        vat: widget.vat,
        grandTotal: widget.grandTotal,
        itemCount: widget.itemCount,
        items: widget.items,
        method: _selectedMethod ?? 'CASH',
        customer: _loanCustomer,
      ),
    ).then((_) async {
      if (!mounted) return;
      final selectedMethod = _selectedMethod ?? 'CASH';

      final saleItems = widget.items
          .map(
            (e) => {
              'barcode': e.barcode,
              'product': e.product,
              'dosage': e.dosage,
              'price': e.price,
              'moph_ceiling': e.mophCeiling,
              'batch_number': e.batchNumber,
              'expiry': e.expiry,
              'box_auth': e.boxAuth.name,
              'qty': e.qty,
              'total': e.total,
            },
          )
          .toList();

      await InventoryDatabase.instance.applySaleStockDeductions(
        saleItems,
        referenceId: receiptId,
      );

      if ((_selectedMethod ?? 'CASH') == 'LOAN' &&
          (_loanCustomer ?? '').trim().isNotEmpty) {
        await InventoryDatabase.instance.createLoanCustomer(
          name: _loanCustomer!.trim(),
        );
      }

      // ── Queue sale for MoPH sync acknowledgement ───────────────────────────
      await InventoryDatabase.instance.queueSale(receiptId, {
        'receipt_id': receiptId,
        'timestamp': now.toIso8601String(),
        'method': selectedMethod,
        'customer': _loanCustomer,
        'subtotal': widget.subtotal,
        'moph_tax': widget.mophTax,
        'vat': widget.vat,
        'grand_total': widget.grandTotal,
        'items': saleItems,
      });

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);

      widget.onCompleteSale?.call();
      setState(() {
        _selectedMethod = null;
        _loanCustomer = null;
      });
      messenger?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.inventory_2_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                selectedMethod == 'LOAN'
                    ? 'Sale recorded · Stock deducted'
                    : 'Sale completed · Queued for MoPH sync',
              ),
            ],
          ),
          backgroundColor: MedTrackColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        borderRadius: MedTrackShapes.cardRadius,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: MedTrackShadows.card,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text('Order Summary', style: tt.titleLarge),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          // Line items
          _SummaryLine(label: 'Subtotal', value: widget.subtotal, tt: tt),
          const SizedBox(height: 10),
          _SummaryLine(
            label: 'MoPH Tax (${(_kMoPHTaxRate * 100).toStringAsFixed(0)}%)',
            value: widget.mophTax,
            tt: tt,
            hint: 'Ministry of Public Health pharmaceutical levy',
          ),
          const SizedBox(height: 10),
          _SummaryLine(
            label: 'VAT (${(_kVatRate * 100).toStringAsFixed(0)}%)',
            value: widget.vat,
            tt: tt,
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          // Grand total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: tt.titleMedium),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  '\$${widget.grandTotal.toStringAsFixed(2)}',
                  key: ValueKey(widget.grandTotal.toStringAsFixed(2)),
                  style: tt.headlineMedium?.copyWith(
                    color: MedTrackColors.teal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Payment Method ─────────────────────────────────────────────────
          Text(
            'Payment Method',
            style: tt.labelSmall?.copyWith(color: MedTrackColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PayBtn(
                  label: 'CASH',
                  icon: Icons.payments_outlined,
                  color: MedTrackColors.teal,
                  bg: const Color(0xFFCCFBF1),
                  selected: _selectedMethod == 'CASH',
                  onTap: widget.onCompleteSale == null
                      ? null
                      : () => setState(() {
                          _selectedMethod = 'CASH';
                          _loanCustomer = null;
                        }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PayBtn(
                  label: 'VISA',
                  icon: Icons.credit_card_rounded,
                  color: const Color(0xFF2563EB),
                  bg: const Color(0xFFEFF6FF),
                  selected: _selectedMethod == 'VISA',
                  onTap: widget.onCompleteSale == null
                      ? null
                      : () => setState(() {
                          _selectedMethod = 'VISA';
                          _loanCustomer = null;
                        }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PayBtn(
                  label: 'LOAN',
                  icon: Icons.account_balance_wallet_outlined,
                  color: MedTrackColors.warning,
                  bg: MedTrackColors.warningContainer,
                  selected: _selectedMethod == 'LOAN',
                  onTap: widget.onCompleteSale == null
                      ? null
                      : () async {
                          setState(() => _selectedMethod = 'LOAN');
                          await _selectLoanCustomer();
                        },
                ),
              ),
            ],
          ),
          // Loan customer name
          if (_selectedMethod == 'LOAN' && _loanCustomer != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: MedTrackColors.warning,
                ),
                const SizedBox(width: 5),
                Text(
                  _loanCustomer!,
                  style: tt.labelMedium?.copyWith(
                    color: MedTrackColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    final c = await showDialog<String>(
                      context: context,
                      builder: (_) => _LoanCustomerDialog(),
                    );
                    if (c != null) setState(() => _loanCustomer = c);
                  },
                  child: Text(
                    'Change',
                    style: tt.labelSmall?.copyWith(
                      color: MedTrackColors.teal,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          // ── MoPH compliance banners ────────────────────────────────────────
          if (_ceilingViolations > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MedTrackColors.errorContainer,
                borderRadius: MedTrackShapes.inputRadius,
                border: Border.all(
                  color: MedTrackColors.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.policy_rounded,
                    color: MedTrackColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_ceilingViolations item${_ceilingViolations > 1 ? 's exceed' : ' exceeds'} the MoPH price ceiling. Remove or reprice before completing.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: MedTrackColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_unverifiedBoxes > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MedTrackColors.errorContainer,
                borderRadius: MedTrackShapes.inputRadius,
                border: Border.all(
                  color: MedTrackColors.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.gpp_bad_rounded,
                    color: MedTrackColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_unverifiedBoxes box${_unverifiedBoxes > 1 ? 'es' : ''} failed MoPH authentication. Remove flagged items.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: MedTrackColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Complete Sale button
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _canComplete ? _handleCompleteSale : null,
              style: FilledButton.styleFrom(
                backgroundColor: _canComplete
                    ? MedTrackColors.teal
                    : MedTrackColors.textDisabled,
                shape: const RoundedRectangleBorder(
                  borderRadius: MedTrackShapes.buttonRadius,
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                'Complete Sale',
                style: tt.titleMedium?.copyWith(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Void / clear
          TextButton.icon(
            onPressed: widget.onCompleteSale == null
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: MedTrackShapes.cardRadius,
                        ),
                        title: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: MedTrackColors.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.cancel_outlined,
                                color: MedTrackColors.error,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text('Void Order'),
                          ],
                        ),
                        content: const Text(
                          'This will remove all items from the current order.\n'
                          'Are you sure you want to void the order?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: MedTrackColors.error,
                              shape: const RoundedRectangleBorder(
                                borderRadius: MedTrackShapes.buttonRadius,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Void Order'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true || !mounted) return;

                    widget.onCompleteSale?.call();
                    setState(() {
                      _selectedMethod = null;
                      _loanCustomer = null;
                    });
                    messenger?.showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(
                              Icons.cancel_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text('Order voided — all items removed'),
                          ],
                        ),
                        backgroundColor: MedTrackColors.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.all(16),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Void Order'),
            style: TextButton.styleFrom(foregroundColor: MedTrackColors.error),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    required this.tt,
    this.hint,
  });
  final String label;
  final double value;
  final TextTheme tt;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: tt.bodyMedium?.copyWith(color: MedTrackColors.textSecondary),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            '\$${value.toStringAsFixed(2)}',
            key: ValueKey(value.toStringAsFixed(2)),
            style: tt.bodyMedium,
          ),
        ),
      ],
    );

    if (hint == null) return row;
    return Tooltip(message: hint!, child: row);
  }
}

// ── Payment Button ────────────────────────────────────────────────────────────

class _PayBtn extends StatelessWidget {
  const _PayBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? bg : MedTrackColors.surfaceVariant,
          borderRadius: MedTrackShapes.chipRadius,
          border: Border.all(
            color: selected ? color : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? color : MedTrackColors.slateGrey,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: tt.labelSmall?.copyWith(
                color: selected ? color : MedTrackColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loan Customer Dialog ──────────────────────────────────────────────────────

class _LoanCustomerDialog extends StatefulWidget {
  @override
  State<_LoanCustomerDialog> createState() => _LoanCustomerDialogState();
}

class _LoanCustomerDialogState extends State<_LoanCustomerDialog> {
  String _query = '';
  bool _loading = true;
  List<String> _customers = [];
  final _phoneCtrl = TextEditingController();
  Map<String, String> _phoneByName = {};

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final summaries = await InventoryDatabase.instance
        .getLoanCustomerSummaries();
    final names =
        summaries
            .map((e) => e.name.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final phoneMap = {
      for (final s in summaries)
        if (s.name.trim().isNotEmpty) s.name.trim().toLowerCase(): s.phone,
    };
    if (!mounted) return;
    setState(() {
      _customers = names;
      _phoneByName = phoneMap;
      _loading = false;
    });
  }

  Future<void> _addTypedCustomerAndSelect() async {
    final name = _query.trim();
    if (name.isEmpty) return;
    await InventoryDatabase.instance.createLoanCustomer(
      name: name,
      phone: _phoneCtrl.text.trim(),
    );
    if (!mounted) return;
    Navigator.pop(context, name);
  }

  List<String> get _filtered => _customers
      .where((c) => c.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: MedTrackShapes.cardRadius),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: MedTrackColors.warningContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: MedTrackColors.warning,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Loan Sale', style: tt.titleMedium),
                      Text(
                        'Select customer account',
                        style: tt.bodySmall?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Search field
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search customer…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: MedTrackColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: MedTrackShapes.inputRadius,
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Customer phone number (optional)',
                  prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                  filled: true,
                  fillColor: MedTrackColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: MedTrackShapes.inputRadius,
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Customer list
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No customers found',
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.textSecondary,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final customer = _filtered[i];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: MedTrackColors.warningContainer,
                              child: Text(
                                customer[0],
                                style: const TextStyle(
                                  color: MedTrackColors.warning,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(customer, style: tt.bodyMedium),
                            subtitle:
                                (_phoneByName[customer.toLowerCase()] ?? '')
                                    .trim()
                                    .isEmpty
                                ? null
                                : Text(
                                    _phoneByName[customer.toLowerCase()]!,
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                    ),
                                  ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                            ),
                            onTap: () => Navigator.pop(context, customer),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _query.trim().isEmpty
                        ? null
                        : _addTypedCustomerAndSelect,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text('Add Customer'),
                  ),
                  TextButton(
                    onPressed: _query.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, _query.trim()),
                    child: const Text('Use Typed Name'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
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
// ═════════════════════════════════════════════════════════════════════════════
// Receipt Dialog — shown after every completed sale
// ═════════════════════════════════════════════════════════════════════════════

class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({
    required this.receiptId,
    required this.subtotal,
    required this.mophTax,
    required this.vat,
    required this.grandTotal,
    required this.itemCount,
    required this.items,
    required this.method,
    this.customer,
  });

  final String receiptId;
  final double subtotal;
  final double mophTax;
  final double vat;
  final double grandTotal;
  final int itemCount;
  final List<_OrderItem> items;
  final String method;
  final String? customer;

  Color get _methodColor {
    switch (method) {
      case 'VISA':
        return const Color(0xFF2563EB);
      case 'LOAN':
        return MedTrackColors.warning;
      default:
        return MedTrackColors.teal;
    }
  }

  Color get _methodBg {
    switch (method) {
      case 'VISA':
        return const Color(0xFFEFF6FF);
      case 'LOAN':
        return MedTrackColors.warningContainer;
      default:
        return const Color(0xFFCCFBF1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final dateStr =
        '${_month(now.month)} ${now.day}, ${now.year}  ·  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Dialog(
      backgroundColor: MedTrackColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header banner ──────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [MedTrackColors.navRailBg, MedTrackColors.teal],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sale Complete',
                      style: tt.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      receiptId,
                      style: tt.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Receipt body ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date + payment method chips
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: MedTrackColors.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          dateStr,
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
                            method,
                            style: tt.labelSmall?.copyWith(
                              color: _methodColor,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (customer != null) ...[
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
                            'Account: $customer',
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    // Items sold table
                    Text(
                      'Items Sold',
                      style: tt.labelMedium?.copyWith(
                        color: MedTrackColors.textSecondary,
                        fontWeight: FontWeight.w600,
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
                          // Header row
                          Container(
                            color: MedTrackColors.surfaceVariant,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Product',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    'Qty',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    'Total',
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
                          ...items.asMap().entries.map((e) {
                            final i = e.key;
                            final item = e.value;
                            return Column(
                              children: [
                                if (i > 0) const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.product,
                                              style: tt.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w500,
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
                                        width: 32,
                                        child: Text(
                                          '×${item.qty}',
                                          style: tt.bodySmall?.copyWith(
                                            color: MedTrackColors.textSecondary,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 64,
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
                    const SizedBox(height: 16),
                    _ReceiptRow(
                      'Subtotal',
                      '\$${subtotal.toStringAsFixed(2)}',
                      tt,
                    ),
                    const SizedBox(height: 6),
                    _ReceiptRow(
                      'MoPH Tax (3%)',
                      '\$${mophTax.toStringAsFixed(2)}',
                      tt,
                      secondary: true,
                    ),
                    const SizedBox(height: 6),
                    _ReceiptRow(
                      'VAT (11%)',
                      '\$${vat.toStringAsFixed(2)}',
                      tt,
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
                          '\$${grandTotal.toStringAsFixed(2)}',
                          style: tt.headlineMedium?.copyWith(
                            color: MedTrackColors.teal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // MedTrack branding strip
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: MedTrackColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.local_pharmacy_rounded,
                            size: 16,
                            color: MedTrackColors.teal,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'MedTrack 360 · Beirut Branch #01',
                            style: tt.labelSmall?.copyWith(
                              color: MedTrackColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Thank you for your visit',
                            style: tt.labelSmall?.copyWith(
                              color: MedTrackColors.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              // ── Actions ────────────────────────────────────────────────────
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                      icon: const Icon(Icons.print_rounded, size: 15),
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
                      label: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _month(int m) => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow(this.label, this.value, this.tt, {this.secondary = false});
  final String label;
  final String value;
  final TextTheme tt;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
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
