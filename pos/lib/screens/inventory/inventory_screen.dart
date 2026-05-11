import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/inventory_database.dart';
import '../../theme/app_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Inventory Audit Screen
// ═════════════════════════════════════════════════════════════════════════════

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  StreamSubscription<int>? _inventorySub;
  final _searchCtrl = TextEditingController();
  final _db = InventoryDatabase.instance;
  int _loadGeneration = 0;

  List<InventoryItem> _inventory = [];
  List<UnmappedBarcode> _unmapped = [];
  List<PurchaseOrder> _purchases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)..addListener(_handleTabChange);
    unawaited(_load());
    _inventorySub = _db.inventoryChanges.listen((_) {
      if (!mounted) return;
      unawaited(_load());
    });
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _inventorySub?.cancel();
    _tab.removeListener(_handleTabChange);
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _load() async {
    final token = ++_loadGeneration;
    if (mounted) {
      setState(() => _loading = true);
    }

    final query = _searchCtrl.text.trim();
    final inventoryFuture = query.isEmpty
        ? _db.allInventory()
        : _db.searchInventory(query);
    final unmappedFuture = _db.unmappedBarcodes();
    final purchaseFuture = _db.getPurchaseHistory();

    final results = await Future.wait([
      inventoryFuture,
      unmappedFuture,
      purchaseFuture,
    ]);

    if (!mounted || token != _loadGeneration) return;
    setState(() {
      _inventory = results[0] as List<InventoryItem>;
      _unmapped = results[1] as List<UnmappedBarcode>;
      _purchases = results[2] as List<PurchaseOrder>;
      _loading = false;
    });
  }

  void _onSearchChanged() {
    unawaited(_refreshInventoryList());
  }

  Future<void> _refreshInventoryList() async {
    final token = ++_loadGeneration;
    final q = _searchCtrl.text.trim();
    final inv = q.isEmpty
        ? await _db.allInventory()
        : await _db.searchInventory(q);
    if (!mounted || token != _loadGeneration) return;
    setState(() => _inventory = inv);
  }

  // ── Tab 0: All Stock ───────────────────────────────────────────────────────

  Widget _buildAllStock() {
    final tt = Theme.of(context).textTheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_inventory.isEmpty) {
      return _EmptyState(
        icon: Icons.inventory_2_outlined,
        label: 'No products found',
        subtitle: 'Try a different search term or scan a barcode',
        tt: tt,
      );
    }

    return _AppleList(
      itemCount: _inventory.length,
      itemBuilder: (context, i) {
        final item = _inventory[i];
        return _InventoryTile(
          item: item,
          isLast: i == _inventory.length - 1,
          onUpdated: _load,
        );
      },
    );
  }

  // ── Tab 1: Unmapped Barcodes ───────────────────────────────────────────────

  Widget _buildUnmapped() {
    final tt = Theme.of(context).textTheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_unmapped.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline_rounded,
        label: 'All barcodes are mapped',
        subtitle: 'No unrecognised scans in the database',
        tt: tt,
      );
    }

    return _AppleList(
      itemCount: _unmapped.length,
      itemBuilder: (context, i) {
        final item = _unmapped[i];
        return _UnmappedTile(
          item: item,
          isLast: i == _unmapped.length - 1,
          onLink: () => _openMappingModal(item),
          onDismiss: () async {
            await _db.dismissUnmapped(item.barcode);
            _load();
          },
        );
      },
    );
  }

  // ── Mapping Modal ──────────────────────────────────────────────────────────

  Future<void> _openMappingModal(UnmappedBarcode item) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _MappingDialog(
        unmapped: item,
        onConfirm: (drug) async {
          await _db.linkBarcodeToMoPH(item.barcode, drug);
          if (mounted) {
            _load();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${item.barcode} linked to ${drug.tradeName} (${drug.genericName})',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  // ── CSV Import Dialog ──────────────────────────────────────────────────────

  void _showCsvImportDialog(BuildContext ctx) {
    showDialog<void>(context: ctx, builder: (_) => const _CsvImportDialog());
  }

  // ── Add Product Dialog ─────────────────────────────────────────────────────

  Future<void> _showAddProductDialog(BuildContext ctx) async {
    final result = await showDialog<MedicineOnboardingResult>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _AddProductDialog(db: _db),
    );
    if (result != null && mounted) {
      _load();
      final snackColor = switch (result.outcome) {
        MedicineOnboardingOutcome.linked => MedTrackColors.teal,
        MedicineOnboardingOutcome.pending => MedTrackColors.warning,
        MedicineOnboardingOutcome.alreadyPending => MedTrackColors.warning,
        MedicineOnboardingOutcome.rejected => MedTrackColors.error,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: snackColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── Purchase Order Dialog ──────────────────────────────────────────────────

  Future<void> _showPurchaseOrderDialog(BuildContext ctx) async {
    final receiptId = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _PurchaseOrderDialog(db: _db),
    );
    if (receiptId != null && mounted) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.move_to_inbox_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text('Stock received · $receiptId'),
            ],
          ),
          backgroundColor: const Color(0xFF2563EB),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
      // Jump to purchases tab
      _tab.animateTo(2);
    }
  }

  // ── Tab 2: Purchase History ────────────────────────────────────────────────

  Widget _buildPurchases() {
    final tt = Theme.of(context).textTheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_purchases.isEmpty) {
      return _EmptyState(
        icon: Icons.move_to_inbox_outlined,
        label: 'No purchase orders yet',
        subtitle: 'Tap "Receive Stock" to record incoming inventory',
        tt: tt,
      );
    }

    return _AppleList(
      itemCount: _purchases.length,
      itemBuilder: (context, i) {
        final order = _purchases[i];
        return _PurchaseTile(order: order, isLast: i == _purchases.length - 1);
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Top bar ──────────────────────────────────────────────────────────
        _InventoryTopBar(
          searchCtrl: _searchCtrl,
          unmappedCount: _unmapped.length,
          onAddProduct: () => _showAddProductDialog(context),
          onRefresh: _load,
          onCsvImport: () => _showCsvImportDialog(context),
          onReceiveStock: () => _showPurchaseOrderDialog(context),
        ),
        const SizedBox(height: 20),
        // ── Section header + tabs ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Inventory Audit', style: tt.headlineMedium),
                    const SizedBox(height: 2),
                    Text(
                      'Manage stock and resolve unlinked barcodes.',
                      style: tt.bodySmall?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _SegmentedTabs(
                controller: _tab,
                unmappedCount: _unmapped.length,
                purchaseCount: _purchases.length,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── Content ───────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TabBarView(
              controller: _tab,
              children: [_buildAllStock(), _buildUnmapped(), _buildPurchases()],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Top Bar
// ═════════════════════════════════════════════════════════════════════════════

class _InventoryTopBar extends StatelessWidget {
  const _InventoryTopBar({
    required this.searchCtrl,
    required this.unmappedCount,
    required this.onAddProduct,
    required this.onRefresh,
    required this.onCsvImport,
    required this.onReceiveStock,
  });

  final TextEditingController searchCtrl;
  final int unmappedCount;
  final VoidCallback onAddProduct;
  final VoidCallback onRefresh;
  final VoidCallback onCsvImport;
  final VoidCallback onReceiveStock;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: const BoxDecoration(
        color: MedTrackColors.surface,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by drug name, barcode, or category…',
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(
                    Icons.search_rounded,
                    color: MedTrackColors.slateGrey,
                    size: 20,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchCtrl,
                  builder: (_, val, __) => val.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          color: MedTrackColors.slateGrey,
                          onPressed: () => searchCtrl.clear(),
                        ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            color: MedTrackColors.slateGrey,
            onPressed: onRefresh,
          ),
          const SizedBox(width: 8),
          // Unmapped warning badge
          if (unmappedCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: MedTrackColors.warningContainer,
                borderRadius: MedTrackShapes.buttonRadius,
                border: Border.all(color: MedTrackColors.warning),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: MedTrackColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$unmappedCount unmapped',
                    style: tt.labelSmall?.copyWith(
                      color: MedTrackColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          // CSV Import
          OutlinedButton.icon(
            onPressed: onCsvImport,
            style: OutlinedButton.styleFrom(
              foregroundColor: MedTrackColors.slateGrey,
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: const RoundedRectangleBorder(
                borderRadius: MedTrackShapes.buttonRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: const Icon(Icons.upload_file_rounded, size: 15),
            label: const Text('Import CSV'),
          ),
          const SizedBox(width: 8),
          // Receive Stock (Purchase Order)
          OutlinedButton.icon(
            onPressed: onReceiveStock,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              shape: const RoundedRectangleBorder(
                borderRadius: MedTrackShapes.buttonRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: const Icon(Icons.move_to_inbox_rounded, size: 15),
            label: const Text('Receive Stock'),
          ),
          const SizedBox(width: 8),
          // Add product
          FilledButton.icon(
            onPressed: onAddProduct,
            style: FilledButton.styleFrom(
              backgroundColor: MedTrackColors.teal,
              shape: const RoundedRectangleBorder(
                borderRadius: MedTrackShapes.buttonRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add Product'),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Segmented Tab Control
// ═════════════════════════════════════════════════════════════════════════════

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.controller,
    required this.unmappedCount,
    this.purchaseCount = 0,
  });
  final TabController controller;
  final int unmappedCount;
  final int purchaseCount;

  @override
  Widget build(BuildContext context) {
    // Fixed width: 3 tabs × ~120px each, plus a little padding.
    return SizedBox(
      width: 390,
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: MedTrackColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: TabBar(
          controller: controller,
          indicator: BoxDecoration(
            color: MedTrackColors.surface,
            borderRadius: BorderRadius.circular(7),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: MedTrackColors.textPrimary,
          unselectedLabelColor: MedTrackColors.textSecondary,
          labelStyle: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          tabs: [
            const Tab(text: 'All Stock'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Flexible(
                    child: Text('Unmapped', overflow: TextOverflow.ellipsis),
                  ),
                  if (unmappedCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: MedTrackColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$unmappedCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Flexible(
                    child: Text('Purchases', overflow: TextOverflow.ellipsis),
                  ),
                  if (purchaseCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$purchaseCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Apple-style List Container
// ═════════════════════════════════════════════════════════════════════════════

class _AppleList extends StatelessWidget {
  const _AppleList({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        borderRadius: MedTrackShapes.cardRadius,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: MedTrackShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(itemCount: itemCount, itemBuilder: itemBuilder),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Inventory Tile
// ═════════════════════════════════════════════════════════════════════════════

class _InventoryTile extends StatefulWidget {
  const _InventoryTile({
    required this.item,
    required this.isLast,
    required this.onUpdated,
  });
  final InventoryItem item;
  final bool isLast;
  final VoidCallback onUpdated;

  @override
  State<_InventoryTile> createState() => _InventoryTileState();
}

class _InventoryTileState extends State<_InventoryTile> {
  bool _hovered = false;

  Future<void> _deleteItem() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item From Stock'),
        content: Text(
          'Delete "${widget.item.name}" from inventory? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: MedTrackColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await InventoryDatabase.instance.deleteInventoryItem(
      widget.item.barcode,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Item deleted from inventory' : 'Delete failed'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) widget.onUpdated();
  }

  Color get _stockDot {
    if (widget.item.stock <= 10) return MedTrackColors.error;
    if (widget.item.stock <= 30) return MedTrackColors.warning;
    return MedTrackColors.success;
  }

  String get _stockLabel {
    if (widget.item.stock <= 0) return 'Out of stock';
    if (widget.item.stock <= 10) return 'Low';
    if (widget.item.stock <= 30) return 'Medium';
    return 'In Stock';
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  // Drug icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.medication_rounded,
                      size: 18,
                      color: MedTrackColors.teal,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Name + dosage
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.item.dosage,
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Category chip
                  Expanded(flex: 2, child: _Chip(label: widget.item.category)),
                  // Stock — two-line vertical to avoid overflow
                  SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _stockDot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${widget.item.stock} units',
                              style: tt.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _stockLabel,
                          style: tt.labelSmall?.copyWith(
                            color: _stockDot,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Expiry
                  SizedBox(
                    width: 90,
                    child: Text(
                      widget.item.expiry,
                      style: tt.bodySmall?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ),
                  // Price column: current price + MoPH ceiling
                  SizedBox(
                    width: 72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Local: \$${widget.item.price.toStringAsFixed(2)}',
                          style: tt.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: MedTrackColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Builder(
                          builder: (context) {
                            final gov = widget.item.mophCeiling;
                            if (gov == null) return const SizedBox.shrink();
                            final over = widget.item.price > gov;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  over
                                      ? Icons.warning_amber_rounded
                                      : Icons.verified_rounded,
                                  size: 10,
                                  color: over
                                      ? MedTrackColors.error
                                      : MedTrackColors.success,
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    'Gov: \$${gov.toStringAsFixed(2)}',
                                    style: tt.labelSmall?.copyWith(
                                      color: over
                                          ? MedTrackColors.error
                                          : MedTrackColors.success,
                                      fontSize: 9,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Actions menu
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 16,
                      color: MedTrackColors.slateGreyLight,
                    ),
                    tooltip: 'Actions',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (val) async {
                      if (val == 'adjust') {
                        final updated = await showDialog<bool>(
                          context: context,
                          builder: (_) => _AdjustStockDialog(item: widget.item),
                        );
                        if (updated == true) widget.onUpdated();
                      } else if (val == 'price') {
                        final updated = await showDialog<bool>(
                          context: context,
                          builder: (_) => _AdjustPriceDialog(item: widget.item),
                        );
                        if (updated == true) widget.onUpdated();
                      } else if (val == 'custody') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              _ChainOfCustodySheet(item: widget.item),
                        );
                      } else if (val == 'delete') {
                        await _deleteItem();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'adjust',
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 16),
                            SizedBox(width: 10),
                            Text('Adjust Stock'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'price',
                        child: Row(
                          children: [
                            Icon(Icons.attach_money_rounded, size: 16),
                            SizedBox(width: 10),
                            Text('Adjust Price'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'custody',
                        child: Row(
                          children: [
                            Icon(Icons.history_rounded, size: 16),
                            SizedBox(width: 10),
                            Text('Chain of Custody'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_forever_rounded,
                              size: 16,
                              color: MedTrackColors.error,
                            ),
                            SizedBox(width: 10),
                            Text('Delete Item'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!widget.isLast)
              const Divider(height: 1, indent: 70, endIndent: 20),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Unmapped Barcode Tile
// ═════════════════════════════════════════════════════════════════════════════

class _UnmappedTile extends StatefulWidget {
  const _UnmappedTile({
    required this.item,
    required this.isLast,
    required this.onLink,
    required this.onDismiss,
  });
  final UnmappedBarcode item;
  final bool isLast;
  final VoidCallback onLink;
  final VoidCallback onDismiss;

  @override
  State<_UnmappedTile> createState() => _UnmappedTileState();
}

class _UnmappedTileState extends State<_UnmappedTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final date = _dateStr(widget.item.firstSeen);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hovered ? const Color(0xFFFFF7ED) : MedTrackColors.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  // Unknown icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: MedTrackColors.warningContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.qr_code_rounded,
                      size: 18,
                      color: MedTrackColors.warning,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Barcode + meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.barcode,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'First scanned $date · ${widget.item.scanCount} scan${widget.item.scanCount == 1 ? '' : 's'}',
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Unlinked badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: MedTrackColors.warningContainer,
                      borderRadius: MedTrackShapes.chipRadius,
                    ),
                    child: Text(
                      'Unlinked',
                      style: tt.labelSmall?.copyWith(
                        color: MedTrackColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Actions
                  TextButton(
                    onPressed: widget.onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: MedTrackColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.onLink,
                    style: FilledButton.styleFrom(
                      backgroundColor: MedTrackColors.teal,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.link_rounded, size: 15),
                    label: const Text('Link to Master Registry'),
                  ),
                ],
              ),
            ),
            if (!widget.isLast)
              const Divider(height: 1, indent: 70, endIndent: 20),
          ],
        ),
      ),
    );
  }

  String _dateStr(DateTime dt) {
    final months = [
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
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Mapping Dialog — MoPH Master List
// ═════════════════════════════════════════════════════════════════════════════

class _MappingDialog extends StatefulWidget {
  const _MappingDialog({required this.unmapped, required this.onConfirm});
  final UnmappedBarcode unmapped;
  final Future<void> Function(MoPhDrug) onConfirm;

  @override
  State<_MappingDialog> createState() => _MappingDialogState();
}

class _MappingDialogState extends State<_MappingDialog> {
  final _searchCtrl = TextEditingController();
  List<MoPhDrug> _results = kMoPhMasterList;
  MoPhDrug? _selected;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _results = q.isEmpty
          ? kMoPhMasterList
          : kMoPhMasterList
                .where(
                  (d) =>
                      d.tradeName.toLowerCase().contains(q) ||
                      d.genericName.toLowerCase().contains(q) ||
                      d.category.toLowerCase().contains(q) ||
                      d.regNumber.toLowerCase().contains(q),
                )
                .toList();
    });
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    setState(() => _confirming = true);
    await widget.onConfirm(_selected!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: MedTrackColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: SizedBox(
        width: 680,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Dialog header ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: MedTrackColors.teal,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Link to MoPH Master Registry',
                          style: tt.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.textSecondary,
                            ),
                            children: [
                              const TextSpan(text: 'Barcode: '),
                              TextSpan(
                                text: widget.unmapped.barcode,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: MedTrackColors.teal,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: MedTrackColors.slateGrey,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // ── Search field ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText:
                      'Search MoPH registry by trade name, generic, or reg. number…',
                  prefixIcon: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      Icons.search_rounded,
                      color: MedTrackColors.slateGrey,
                      size: 18,
                    ),
                  ),
                  prefixIconConstraints: BoxConstraints(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── Result count ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                '${_results.length} drug${_results.length == 1 ? '' : 's'} found',
                style: tt.labelSmall?.copyWith(
                  color: MedTrackColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // ── Results list ───────────────────────────────────────────────
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        'No matches',
                        style: tt.bodyMedium?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final drug = _results[i];
                        final isSelected = _selected == drug;
                        final isLast = i == _results.length - 1;
                        return _DrugResultTile(
                          drug: drug,
                          isSelected: isSelected,
                          isLast: isLast,
                          onTap: () => setState(() => _selected = drug),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            // ── Footer actions ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 20),
              child: Row(
                children: [
                  if (_selected != null) ...[
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: MedTrackColors.teal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Selected: ${_selected!.tradeName} (${_selected!.dosage})',
                        style: tt.bodySmall?.copyWith(
                          color: MedTrackColors.teal,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Text(
                        'Select a drug from the list above to continue.',
                        style: tt.bodySmall?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _selected != null && !_confirming
                        ? _confirm
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: MedTrackColors.teal,
                      disabledBackgroundColor: MedTrackColors.textDisabled,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    icon: _confirming
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Confirm Link'),
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

// ── Drug result tile ──────────────────────────────────────────────────────────

class _DrugResultTile extends StatefulWidget {
  const _DrugResultTile({
    required this.drug,
    required this.isSelected,
    required this.isLast,
    required this.onTap,
  });
  final MoPhDrug drug;
  final bool isSelected;
  final bool isLast;
  final VoidCallback onTap;

  @override
  State<_DrugResultTile> createState() => _DrugResultTileState();
}

class _DrugResultTileState extends State<_DrugResultTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: widget.isSelected
              ? const Color(0xFFF0FDFA)
              : _hovered
              ? MedTrackColors.surfaceVariant
              : MedTrackColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Row(
            children: [
              // Selection indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isSelected
                      ? MedTrackColors.teal
                      : Colors.transparent,
                  border: Border.all(
                    color: widget.isSelected
                        ? MedTrackColors.teal
                        : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                ),
                child: widget.isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              // Names
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.drug.tradeName,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      widget.drug.genericName,
                      style: tt.bodySmall?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Dosage + form
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.drug.dosage, style: tt.bodySmall),
                    Text(
                      widget.drug.form,
                      style: tt.labelSmall?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Category
              _Chip(label: widget.drug.category),
              const SizedBox(width: 12),
              // Reg number
              Text(
                widget.drug.regNumber,
                style: tt.labelSmall?.copyWith(
                  color: MedTrackColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: MedTrackColors.surfaceVariant,
        borderRadius: MedTrackShapes.chipRadius,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: MedTrackColors.textSecondary),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.tt,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: MedTrackColors.textDisabled),
          const SizedBox(height: 12),
          Text(
            label,
            style: tt.bodyMedium?.copyWith(color: MedTrackColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: tt.bodySmall?.copyWith(color: MedTrackColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Add Product Dialog
// ═════════════════════════════════════════════════════════════════════════════

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog({required this.db});
  final InventoryDatabase db;

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');
  final _expiryCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  bool _saving = false;

  static const _categories = [
    'Antibiotic',
    'Antidiabetic',
    'Antihypertensive',
    'Anti-inflammatory',
    'Antihistamine',
    'Antacid / PPI',
    'Analgesic',
    'Lipid-Lowering',
    'Anticoagulant',
    'Bronchodilator',
    'Other',
  ];

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _categoryCtrl.dispose();
    _stockCtrl.dispose();
    _expiryCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = await widget.db.submitMedicineOnboardingRequest(
      barcode: _barcodeCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      dosage: _dosageCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      stock: int.tryParse(_stockCtrl.text.trim()) ?? 0,
      expiry: _expiryCtrl.text.trim(),
      price: double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
    );
    if (mounted) {
      if (result.outcome == MedicineOnboardingOutcome.rejected) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: MedTrackColors.error,
          ),
        );
      } else {
        Navigator.of(context).pop(result);
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool optional = false,
  }) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          optional ? label : '$label *',
          style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          validator:
              validator ??
              (v) => (!optional && (v == null || v.trim().isEmpty))
                  ? '$label is required'
                  : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: MedTrackColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      child: SizedBox(
        width: 600,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_box_rounded,
                        color: MedTrackColors.teal,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add New Product', style: tt.titleLarge),
                        Text(
                          'Enter product details to add to inventory',
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: MedTrackColors.slateGrey,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(height: 1),
                const SizedBox(height: 20),

                // ── Row 1: Barcode + Name ──────────────────────────────────
                Row(
                  children: [
                    SizedBox(
                      width: 180,
                      child: _field(
                        'Barcode',
                        _barcodeCtrl,
                        hint: 'e.g. 6009705182108',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        'Product Name',
                        _nameCtrl,
                        hint: 'e.g. Amoxil (Amoxicillin)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Row 2: Dosage + Category ───────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'Dosage',
                        _dosageCtrl,
                        hint: 'e.g. 500 mg',
                        optional: true,
                      ),
                    ),
                    const SizedBox(width: 16),
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
                          DropdownButtonFormField<String>(
                            value: _categoryCtrl.text.isEmpty
                                ? null
                                : _categoryCtrl.text,
                            items: _categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                            hint: const Text('Select category'),
                            onChanged: (v) =>
                                setState(() => _categoryCtrl.text = v ?? ''),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Category is required'
                                : null,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Row 3: Stock + Expiry + Price ──────────────────────────
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: _field(
                        'Stock Qty',
                        _stockCtrl,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          if (int.tryParse(v.trim()) == null) {
                            return 'Integer';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        'Expiry',
                        _expiryCtrl,
                        hint: 'e.g. Dec 2027',
                        optional: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 120,
                      child: _field(
                        'Unit Price (\$)',
                        _priceCtrl,
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          if (double.tryParse(v.trim()) == null) {
                            return 'Invalid';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Actions ────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: MedTrackColors.teal,
                        shape: const RoundedRectangleBorder(
                          borderRadius: MedTrackShapes.buttonRadius,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
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
                          : const Icon(Icons.inventory_2_rounded, size: 16),
                      label: Text(_saving ? 'Saving…' : 'Add to Inventory'),
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
// CSV Import Dialog
// ═════════════════════════════════════════════════════════════════════════════

class _CsvImportDialog extends StatefulWidget {
  const _CsvImportDialog();

  @override
  State<_CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<_CsvImportDialog> {
  bool _fileSelected = false;
  bool _importing = false;
  bool _done = false;
  String _fileName = '';

  // Mock preview rows
  static const _preview = [
    ['Barcode', 'Name', 'Dosage', 'Category', 'Stock', 'Expiry', 'Price'],
    [
      '6009705182150',
      'Paracetamol',
      '500mg',
      'Analgesic',
      '120',
      '2027-03',
      '4.50',
    ],
    ['6009705182167', 'Diclofenac', '50mg', 'NSAID', '60', '2026-11', '7.20'],
    [
      '6009705182174',
      'Salbutamol',
      '2.5mg',
      'Bronchodilator',
      '30',
      '2027-01',
      '14.00',
    ],
  ];

  Future<void> _pickFile() async {
    // Stub: in production wire to file_picker package
    setState(() {
      _fileSelected = true;
      _fileName = 'inventory_bulk_import.csv';
    });
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted)
      setState(() {
        _importing = false;
        _done = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: MedTrackShapes.cardRadius),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.upload_file_rounded,
                      color: MedTrackColors.teal,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bulk CSV Import', style: tt.titleLarge),
                      Text(
                        'Upload products from spreadsheet',
                        style: tt.bodySmall?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_done) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MedTrackColors.successContainer,
                    borderRadius: MedTrackShapes.cardRadius,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: MedTrackColors.success,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '3 products imported successfully!',
                        style: tt.bodyMedium?.copyWith(
                          color: MedTrackColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: MedTrackColors.teal,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ] else ...[
                // Drop zone / file select
                GestureDetector(
                  onTap: _pickFile,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: _fileSelected
                          ? const Color(0xFFCCFBF1)
                          : MedTrackColors.surfaceVariant,
                      borderRadius: MedTrackShapes.cardRadius,
                      border: Border.all(
                        color: _fileSelected
                            ? MedTrackColors.teal
                            : const Color(0xFFE2E8F0),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _fileSelected
                              ? Icons.description_rounded
                              : Icons.cloud_upload_outlined,
                          size: 36,
                          color: _fileSelected
                              ? MedTrackColors.teal
                              : MedTrackColors.slateGreyLight,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _fileSelected
                              ? _fileName
                              : 'Click to select a CSV file',
                          style: tt.bodyMedium?.copyWith(
                            color: _fileSelected
                                ? MedTrackColors.teal
                                : MedTrackColors.textSecondary,
                            fontWeight: _fileSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        if (!_fileSelected)
                          Text(
                            'Supports .csv and .xlsx formats',
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.textDisabled,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Preview table
                if (_fileSelected) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Preview (first 3 rows)',
                    style: tt.labelMedium?.copyWith(
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
                    child: Table(
                      border: TableBorder.symmetric(
                        inside: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      children: _preview.asMap().entries.map((e) {
                        final isHeader = e.key == 0;
                        return TableRow(
                          decoration: BoxDecoration(
                            color: isHeader
                                ? MedTrackColors.surfaceVariant
                                : MedTrackColors.surface,
                          ),
                          children: e.value
                              .map(
                                (cell) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    cell,
                                    style: isHeader
                                        ? tt.labelSmall?.copyWith(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: MedTrackColors.textSecondary,
                                            letterSpacing: 0.5,
                                          )
                                        : tt.bodySmall,
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _fileSelected && !_importing ? _import : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: MedTrackColors.teal,
                        shape: const RoundedRectangleBorder(
                          borderRadius: MedTrackShapes.buttonRadius,
                        ),
                      ),
                      icon: _importing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_rounded, size: 16),
                      label: Text(_importing ? 'Importing…' : 'Import'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Adjust Stock Dialog
// ═════════════════════════════════════════════════════════════════════════════

enum _AdjustReason { damaged, return_, correction, loss }

class _AdjustStockDialog extends StatefulWidget {
  const _AdjustStockDialog({required this.item});
  final InventoryItem item;

  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  int _delta = 0;
  _AdjustReason? _reason;
  bool _saved = false;
  bool _saving = false;

  String _reasonLabel(_AdjustReason r) {
    switch (r) {
      case _AdjustReason.damaged:
        return 'Damaged / Spoiled';
      case _AdjustReason.return_:
        return 'Customer Return';
      case _AdjustReason.correction:
        return 'Cycle Count Correction';
      case _AdjustReason.loss:
        return 'Theft / Loss';
    }
  }

  int get _newStock => (widget.item.stock + _delta).clamp(0, 99999);

  Future<void> _saveAdjustment() async {
    setState(() => _saving = true);
    final ok = await InventoryDatabase.instance.setStock(
      widget.item.barcode,
      _newStock,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save stock adjustment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: MedTrackShapes.cardRadius),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                      Icons.edit_rounded,
                      color: MedTrackColors.warning,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adjust Stock', style: tt.titleLarge),
                        Text(
                          widget.item.name,
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_saved) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MedTrackColors.successContainer,
                    borderRadius: MedTrackShapes.cardRadius,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: MedTrackColors.success,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Stock updated: ${widget.item.stock} → $_newStock units',
                          style: tt.bodyMedium?.copyWith(
                            color: MedTrackColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: MedTrackColors.teal,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Done'),
                  ),
                ),
              ] else ...[
                // Current stock
                Row(
                  children: [
                    Text(
                      'Current stock:',
                      style: tt.bodyMedium?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.item.stock} units',
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Delta stepper
                Text(
                  'Adjustment',
                  style: tt.labelMedium?.copyWith(
                    color: MedTrackColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StepBtn2(
                      icon: Icons.remove_rounded,
                      onTap: () => setState(() => _delta--),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 64,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _delta == 0
                            ? MedTrackColors.surfaceVariant
                            : _delta > 0
                            ? const Color(0xFFCCFBF1)
                            : MedTrackColors.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _delta == 0
                              ? const Color(0xFFE2E8F0)
                              : _delta > 0
                              ? MedTrackColors.teal
                              : MedTrackColors.error,
                        ),
                      ),
                      child: Text(
                        _delta >= 0 ? '+$_delta' : '$_delta',
                        textAlign: TextAlign.center,
                        style: tt.titleMedium?.copyWith(
                          color: _delta == 0
                              ? MedTrackColors.textSecondary
                              : _delta > 0
                              ? MedTrackColors.teal
                              : MedTrackColors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _StepBtn2(
                      icon: Icons.add_rounded,
                      onTap: () => setState(() => _delta++),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '→ $_newStock units',
                      style: tt.bodyMedium?.copyWith(
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Reason dropdown
                Text(
                  'Reason *',
                  style: tt.labelMedium?.copyWith(
                    color: MedTrackColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<_AdjustReason>(
                  value: _reason,
                  hint: const Text('Select a reason'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: MedTrackColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: MedTrackShapes.inputRadius,
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: _AdjustReason.values
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(_reasonLabel(r)),
                        ),
                      )
                      .toList(),
                  onChanged: (r) => setState(() => _reason = r),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: (_delta != 0 && _reason != null && !_saving)
                          ? _saveAdjustment
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: MedTrackColors.warning,
                        shape: const RoundedRectangleBorder(
                          borderRadius: MedTrackShapes.buttonRadius,
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
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save Adjustment'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBtn2 extends StatelessWidget {
  const _StepBtn2({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: MedTrackColors.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Icon(icon, size: 16, color: MedTrackColors.textPrimary),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Adjust Price Dialog
// ═════════════════════════════════════════════════════════════════════════════

class _AdjustPriceDialog extends StatefulWidget {
  const _AdjustPriceDialog({required this.item});
  final InventoryItem item;

  @override
  State<_AdjustPriceDialog> createState() => _AdjustPriceDialogState();
}

class _AdjustPriceDialogState extends State<_AdjustPriceDialog> {
  late final TextEditingController _priceCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.item.price.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  double get _newPrice =>
      double.tryParse(_priceCtrl.text.trim()) ?? widget.item.price;
  double? get _govPrice => widget.item.mophCeiling;

  Future<void> _savePrice() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await InventoryDatabase.instance.setPrice(
      widget.item.barcode,
      _newPrice,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save price adjustment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final gov = _govPrice;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: MedTrackShapes.cardRadius),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.attach_money_rounded,
                        color: MedTrackColors.teal,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Adjust Price', style: tt.titleLarge),
                          Text(
                            widget.item.name,
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (_saved) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: MedTrackColors.successContainer,
                      borderRadius: MedTrackShapes.cardRadius,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: MedTrackColors.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Price updated: \$${widget.item.price.toStringAsFixed(2)} → \$${_newPrice.toStringAsFixed(2)}',
                            style: tt.bodyMedium?.copyWith(
                              color: MedTrackColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: MedTrackColors.teal,
                        shape: const RoundedRectangleBorder(
                          borderRadius: MedTrackShapes.buttonRadius,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Done'),
                    ),
                  ),
                ] else ...[
                  // Current price info
                  Row(
                    children: [
                      Text(
                        'Current price:',
                        style: tt.bodyMedium?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '\$${widget.item.price.toStringAsFixed(2)}',
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  // MoPH official price banner
                  if (gov != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: widget.item.price > gov
                            ? MedTrackColors.errorContainer
                            : MedTrackColors.successContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.item.price > gov
                              ? MedTrackColors.error
                              : MedTrackColors.success,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_rounded,
                            size: 16,
                            color: widget.item.price > gov
                                ? MedTrackColors.error
                                : MedTrackColors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MoPH Official Ceiling Price: \$${gov.toStringAsFixed(2)}',
                                  style: tt.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: widget.item.price > gov
                                        ? MedTrackColors.error
                                        : MedTrackColors.success,
                                  ),
                                ),
                                if (widget.item.price > gov)
                                  Text(
                                    'Current price exceeds government ceiling.',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.error,
                                    ),
                                  )
                                else
                                  Text(
                                    'Price is within regulatory limits.',
                                    style: tt.labelSmall?.copyWith(
                                      color: MedTrackColors.success,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.item.price > gov)
                            TextButton(
                              onPressed: () => setState(() {
                                _priceCtrl.text = gov.toStringAsFixed(2);
                              }),
                              style: TextButton.styleFrom(
                                foregroundColor: MedTrackColors.teal,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Apply'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // New price field
                  Text(
                    'New Price (\$) *',
                    style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _priceCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '\$  ',
                      hintText: '0.00',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final val = double.tryParse(v.trim());
                      if (val == null || val < 0) return 'Invalid price';
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),

                  // Warning if above gov price
                  if (gov != null && _newPrice > gov) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: MedTrackColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'New price exceeds MoPH ceiling (\$${gov.toStringAsFixed(2)})',
                          style: tt.labelSmall?.copyWith(
                            color: MedTrackColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _saving ? null : _savePrice,
                        style: FilledButton.styleFrom(
                          backgroundColor: MedTrackColors.teal,
                          shape: const RoundedRectangleBorder(
                            borderRadius: MedTrackShapes.buttonRadius,
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
                            : const Icon(Icons.save_rounded, size: 16),
                        label: Text(_saving ? 'Saving...' : 'Save Price'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// ── Chain of Custody Sheet ──────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────────────────────

class _ChainOfCustodySheet extends StatefulWidget {
  const _ChainOfCustodySheet({required this.item});
  final InventoryItem item;

  @override
  State<_ChainOfCustodySheet> createState() => _ChainOfCustodySheetState();
}

class _ChainOfCustodySheetState extends State<_ChainOfCustodySheet> {
  late final Future<List<_CustodyEvent>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadCustodyEvents();
  }

  Future<List<_CustodyEvent>> _loadCustodyEvents() async {
    final db = InventoryDatabase.instance;
    final events = <_CustodyEvent>[];

    final purchases = await db.getPurchaseHistory();
    for (final order in purchases) {
      for (final line in order.items) {
        if (line.barcode != widget.item.barcode) continue;
        events.add(
          _CustodyEvent(
            timestamp: order.createdAt,
            actor: order.supplierName.isEmpty
                ? 'Unknown Supplier'
                : order.supplierName,
            action: 'Received Into Pharmacy Stock',
            location: 'Receiving / Inventory',
            details:
                'PO ${order.receiptId} · Invoice ${order.invoiceNumber.isEmpty ? 'N/A' : order.invoiceNumber} '
                '· Qty +${line.qty} · Cost \$${line.costPrice.toStringAsFixed(2)}',
            icon: Icons.move_to_inbox_rounded,
            color: const Color(0xFF2563EB),
          ),
        );
      }
    }

    final sales = await db.getSalesHistory(limit: 1500);
    for (final sale in sales) {
      for (final line in sale.items) {
        if (line.barcode != widget.item.barcode) continue;
        events.add(
          _CustodyEvent(
            timestamp: sale.timestamp,
            actor: 'POS Cashier',
            action: 'Dispensed to Customer',
            location: 'Checkout Counter',
            details:
                'Receipt ${sale.receiptId} · Qty -${line.qty} · Method ${sale.method} '
                '· Total \$${line.total.toStringAsFixed(2)}',
            icon: Icons.point_of_sale_rounded,
            color: MedTrackColors.teal,
          ),
        );
      }
    }

    events.add(
      _CustodyEvent(
        timestamp: DateTime.now(),
        actor: 'Inventory System',
        action: 'Current Stock Snapshot',
        location: 'Local SQLite Inventory',
        details:
            'On hand: ${widget.item.stock} units · Expiry: ${widget.item.expiry.isEmpty ? 'N/A' : widget.item.expiry} '
            '· Batch: ${widget.item.batchNumber.isEmpty ? 'N/A' : widget.item.batchNumber}',
        icon: Icons.inventory_2_outlined,
        color: MedTrackColors.success,
      ),
    );

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final item = widget.item;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: MedTrackColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: MedTrackColors.teal,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chain of Custody',
                              style: tt.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Traceability from purchase receipts and POS sales',
                              style: tt.bodySmall?.copyWith(
                                color: MedTrackColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: MedTrackColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _InfoChip(
                              icon: Icons.qr_code_rounded,
                              label: item.barcode,
                            ),
                            const SizedBox(width: 8),
                            _InfoChip(
                              icon: Icons.inventory_2_outlined,
                              label: '${item.stock} in stock',
                            ),
                            const SizedBox(width: 8),
                            _InfoChip(
                              icon: Icons.event_outlined,
                              label:
                                  'Exp: ${item.expiry.isEmpty ? 'N/A' : item.expiry}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<_CustodyEvent>>(
                future: _eventsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final custodyEvents = snapshot.data!;
                  if (custodyEvents.isEmpty) {
                    return Center(
                      child: Text(
                        'No traceability events available yet.',
                        style: tt.bodyMedium?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    itemCount: custodyEvents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (_, i) => _CustodyEventTile(
                      event: custodyEvents[i],
                      isFirst: i == 0,
                      isLast: i == custodyEvents.length - 1,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custody Event Model ──────────────────────────────────────────────────────

class _CustodyEvent {
  const _CustodyEvent({
    required this.timestamp,
    required this.actor,
    required this.action,
    required this.location,
    required this.details,
    required this.icon,
    required this.color,
  });

  final DateTime timestamp;
  final String actor;
  final String action;
  final String location;
  final String details;
  final IconData icon;
  final Color color;
}

// ── Custody Event Tile ───────────────────────────────────────────────────────

class _CustodyEventTile extends StatelessWidget {
  const _CustodyEventTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final _CustodyEvent event;
  final bool isFirst;
  final bool isLast;

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays > 30) {
      return '${dt.day}/${dt.month}/${dt.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: event.color.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(event.icon, color: event.color, size: 18),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          event.color.withValues(alpha: 0.3),
                          const Color(0xFFE2E8F0),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Event content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MedTrackColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.action,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: event.color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formatTimestamp(event.timestamp),
                          style: tt.labelSmall?.copyWith(
                            color: event.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 13,
                        color: MedTrackColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.actor,
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: MedTrackColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.location,
                          style: tt.bodySmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: MedTrackColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: MedTrackColors.slateGrey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            event.details,
                            style: tt.bodySmall?.copyWith(
                              color: MedTrackColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
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

// ── Info Chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: MedTrackColors.slateGrey),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: MedTrackColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Purchase History Tile
// ═════════════════════════════════════════════════════════════════════════════

class _PurchaseTile extends StatefulWidget {
  const _PurchaseTile({required this.order, required this.isLast});
  final PurchaseOrder order;
  final bool isLast;

  @override
  State<_PurchaseTile> createState() => _PurchaseTileState();
}

class _PurchaseTileState extends State<_PurchaseTile> {
  bool _expanded = false;

  String _formatDate(DateTime dt) {
    const months = [
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
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ·  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final order = widget.order;

    return Column(
      children: [
        // ── Summary row ──────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.move_to_inbox_rounded,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 14),
                // Receipt ID + supplier
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.receiptId,
                        style: tt.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                      Text(
                        order.supplierName.isEmpty
                            ? 'Unknown Supplier'
                            : order.supplierName,
                        style: tt.labelSmall?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Date
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatDate(order.createdAt),
                    style: tt.bodySmall?.copyWith(
                      color: MedTrackColors.textSecondary,
                    ),
                  ),
                ),
                // Items count
                Expanded(
                  flex: 1,
                  child: Text('${order.totalUnits} units', style: tt.bodySmall),
                ),
                // Total cost
                Expanded(
                  flex: 2,
                  child: Text(
                    '\$${order.grandTotal.toStringAsFixed(2)}',
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: MedTrackColors.textPrimary,
                    ),
                  ),
                ),
                // Chevron
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: MedTrackColors.slateGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Expanded items ────────────────────────────────────────────────
        if (_expanded)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            decoration: BoxDecoration(
              color: MedTrackColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.invoiceNumber.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 13,
                          color: MedTrackColors.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Invoice: ${order.invoiceNumber}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: MedTrackColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                // Column headers
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'PRODUCT',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: MedTrackColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          'QTY',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: MedTrackColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          'UNIT \$',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: MedTrackColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          'TOTAL',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: MedTrackColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Item rows
                ...order.items.asMap().entries.map((e) {
                  final i = e.key;
                  final item = e.value;
                  return Column(
                    children: [
                      if (i > 0) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  if (item.dosage.isNotEmpty)
                                    Text(
                                      item.dosage,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: MedTrackColors.textSecondary,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '×${item.qty}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                '\$${item.costPrice.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: MedTrackColors.textSecondary,
                                    ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(
                                '\$${item.lineTotal.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF2563EB),
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
        if (!widget.isLast) const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Purchase Order Dialog
// ═════════════════════════════════════════════════════════════════════════════

class _PurchaseOrderDialog extends StatefulWidget {
  const _PurchaseOrderDialog({required this.db});
  final InventoryDatabase db;

  @override
  State<_PurchaseOrderDialog> createState() => _PurchaseOrderDialogState();
}

class _PurchaseOrderDialogState extends State<_PurchaseOrderDialog> {
  final _supplierCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();

  // Item-entry form fields
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  List<InventoryItem> _allInventory = [];
  List<InventoryItem> _filtered = [];
  InventoryItem? _selectedItem;

  List<PurchaseItem> _cartItems = [];

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _invoiceCtrl.dispose();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    final items = await widget.db.allInventory();
    if (!mounted) return;
    setState(() => _allInventory = items);
    _onSearch();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? []
          : _allInventory
                .where(
                  (i) =>
                      i.name.toLowerCase().contains(q) || i.barcode.contains(q),
                )
                .take(6)
                .toList();
      if (q.isEmpty) _selectedItem = null;
    });
  }

  void _selectItem(InventoryItem item) {
    setState(() {
      _selectedItem = item;
      _searchCtrl.text = item.name;
      _filtered = [];
      _priceCtrl.text = item.price.toStringAsFixed(2);
    });
  }

  void _addToCart() {
    if (_selectedItem == null) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    final cost = double.tryParse(_priceCtrl.text) ?? 0.0;
    if (qty <= 0 || cost < 0) return;

    setState(() {
      // Replace if same barcode already in cart
      final existing = _cartItems.indexWhere(
        (e) => e.barcode == _selectedItem!.barcode,
      );
      final newItem = PurchaseItem(
        barcode: _selectedItem!.barcode,
        name: _selectedItem!.name,
        dosage: _selectedItem!.dosage,
        qty: qty,
        costPrice: cost,
      );
      if (existing >= 0) {
        _cartItems[existing] = newItem;
      } else {
        _cartItems.add(newItem);
      }
      // Reset form
      _searchCtrl.clear();
      _qtyCtrl.text = '1';
      _priceCtrl.clear();
      _selectedItem = null;
      _filtered = [];
    });
  }

  Future<void> _confirm() async {
    if (_cartItems.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final receiptId = await widget.db.recordPurchase(
        supplierName: _supplierCtrl.text.trim(),
        invoiceNumber: _invoiceCtrl.text.trim(),
        items: _cartItems,
      );
      if (mounted) Navigator.of(context).pop(receiptId);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final canConfirm = _cartItems.isNotEmpty && !_submitting;
    final grandTotal = _cartItems.fold(0.0, (s, e) => s + e.lineTotal);

    return Dialog(
      backgroundColor: MedTrackColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Color(0xFFBFDBFE))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.move_to_inbox_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receive Stock',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Record incoming inventory from supplier',
                        style: tt.bodySmall?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Body ────────────────────────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Supplier + Invoice row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Supplier Name',
                                style: tt.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _supplierCtrl,
                                decoration: InputDecoration(
                                  hintText: 'e.g. Pharmaline SAL',
                                  filled: true,
                                  fillColor: MedTrackColors.surfaceVariant,
                                  border: OutlineInputBorder(
                                    borderRadius: MedTrackShapes.inputRadius,
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Invoice / Reference  (optional)',
                                style: tt.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _invoiceCtrl,
                                decoration: InputDecoration(
                                  hintText: 'e.g. INV-2026-0441',
                                  filled: true,
                                  fillColor: MedTrackColors.surfaceVariant,
                                  border: OutlineInputBorder(
                                    borderRadius: MedTrackShapes.inputRadius,
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Divider(height: 1),
                    const SizedBox(height: 20),
                    Text(
                      'Add Products',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Item search + qty + price row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search field with dropdown
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  hintText:
                                      'Search product by name or barcode…',
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                  ),
                                  filled: true,
                                  fillColor: MedTrackColors.surfaceVariant,
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        _filtered.isNotEmpty ||
                                            _selectedItem != null
                                        ? const BorderRadius.vertical(
                                            top: Radius.circular(8),
                                          )
                                        : MedTrackShapes.inputRadius,
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                ),
                              ),
                              // Dropdown results
                              if (_filtered.isNotEmpty)
                                Container(
                                  decoration: BoxDecoration(
                                    color: MedTrackColors.surface,
                                    borderRadius: const BorderRadius.vertical(
                                      bottom: Radius.circular(8),
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    children: _filtered.map((item) {
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          item.name,
                                          style: tt.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${item.dosage}  ·  ${item.barcode}',
                                          style: tt.labelSmall?.copyWith(
                                            color: MedTrackColors.textSecondary,
                                          ),
                                        ),
                                        trailing: Text(
                                          'Stock: ${item.stock}',
                                          style: tt.labelSmall?.copyWith(
                                            color: MedTrackColors.textSecondary,
                                          ),
                                        ),
                                        onTap: () => _selectItem(item),
                                      );
                                    }).toList(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Qty
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              labelText: 'Qty',
                              filled: true,
                              fillColor: MedTrackColors.surfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: MedTrackShapes.inputRadius,
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Cost price
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              labelText: 'Cost \$',
                              filled: true,
                              fillColor: MedTrackColors.surfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: MedTrackShapes.inputRadius,
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Add button
                        SizedBox(
                          height: 46,
                          child: FilledButton(
                            onPressed: _selectedItem != null
                                ? _addToCart
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              shape: const RoundedRectangleBorder(
                                borderRadius: MedTrackShapes.buttonRadius,
                              ),
                            ),
                            child: const Text('Add'),
                          ),
                        ),
                      ],
                    ),
                    // Cart
                    if (_cartItems.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            // Header
                            Container(
                              color: MedTrackColors.surfaceVariant,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Order Items  (${_cartItems.length})',
                                    style: tt.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Total: \$${grandTotal.toStringAsFixed(2)}',
                                    style: tt.labelMedium?.copyWith(
                                      color: const Color(0xFF2563EB),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Cart rows
                            ..._cartItems.asMap().entries.map((e) {
                              final i = e.key;
                              final item = e.value;
                              return Column(
                                children: [
                                  if (i > 0) const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.name,
                                                style: tt.bodySmall?.copyWith(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (item.dosage.isNotEmpty)
                                                Text(
                                                  item.dosage,
                                                  style: tt.labelSmall
                                                      ?.copyWith(
                                                        color: MedTrackColors
                                                            .textSecondary,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '×${item.qty}  @  \$${item.costPrice.toStringAsFixed(2)}',
                                          style: tt.bodySmall?.copyWith(
                                            color: MedTrackColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '\$${item.lineTotal.toStringAsFixed(2)}',
                                          style: tt.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF2563EB),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline_rounded,
                                            size: 16,
                                          ),
                                          color: MedTrackColors.error,
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => setState(
                                            () => _cartItems.removeAt(i),
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
                    ],
                  ],
                ),
              ),
            ),
            // ── Actions ─────────────────────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  if (_cartItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '${_cartItems.length} product${_cartItems.length > 1 ? 's' : ''}  ·  '
                        '\$${grandTotal.toStringAsFixed(2)} cost',
                        style: tt.bodySmall?.copyWith(
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: canConfirm ? _confirm : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: canConfirm
                          ? const Color(0xFF2563EB)
                          : MedTrackColors.textDisabled,
                      shape: const RoundedRectangleBorder(
                        borderRadius: MedTrackShapes.buttonRadius,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.move_to_inbox_rounded, size: 16),
                    label: Text(_submitting ? 'Recording…' : 'Confirm Receipt'),
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
