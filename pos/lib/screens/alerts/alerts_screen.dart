import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/inventory_database.dart';

enum _AlertSeverity { critical, pricing, syncAck }

class _AlertItem {
  const _AlertItem({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.severity,
    this.batch,
    this.actionLabel,
    this.predictedHours,
    this.newPriceDrug,
    this.newPriceValue,
    this.barcode,
    this.currentPrice,
    this.syncedCount,
  });
  final String title;
  final String subtitle;
  final String time;
  final _AlertSeverity severity;

  /// Batch number — shown as a small tag when present.
  final String? batch;

  /// If set, an action button is rendered inside the tile.
  final String? actionLabel;

  /// Estimated hours until stock-out (null = not a predictive alert).
  final int? predictedHours;

  /// Drug name pattern used when applying a MoPH price decree.
  final String? newPriceDrug;

  /// New MoPH price ceiling to apply when the pharmacist taps "Apply Price Now".
  final double? newPriceValue;

  /// Stable product identity used for direct local price updates.
  final String? barcode;

  /// Local price captured when the alert was generated.
  final double? currentPrice;

  /// Number of sales synced — shown on sync-acknowledgement alerts.
  final int? syncedCount;
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _db = InventoryDatabase.instance;
  StreamSubscription<int>? _inventorySub;
  _AlertSeverity? _filter; // null = All
  List<_AlertItem> _alerts = [];
  bool _loading = true;
  int _loadGeneration = 0;

  List<_AlertItem> get _filtered => _filter == null
      ? _alerts
      : _alerts.where((a) => a.severity == _filter).toList();

  int _count(_AlertSeverity s) => _alerts.where((a) => a.severity == s).length;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _inventorySub = _db.inventoryChanges.listen((_) {
      if (!mounted) return;
      _loadAlerts();
    });
  }

  @override
  void dispose() {
    _inventorySub?.cancel();
    super.dispose();
  }

  String _matchPatternFromName(String name) {
    final base = name.split('(').first.trim();
    if (base.isNotEmpty) return base;
    return name.trim();
  }

  Future<void> _loadAlerts() async {
    final token = ++_loadGeneration;
    if (mounted) {
      setState(() => _loading = true);
    }

    final lowStock = await _db.lowStockItems(limit: 4);
    final overpriced = await _db.pricedAboveCeiling(limit: 4);
    final syncedCount = await _db.syncedSalesCount();

    final alerts = <_AlertItem>[];

    for (final item in lowStock) {
      final predicted = (item.stock * 3).clamp(6, 72);
      alerts.add(
        _AlertItem(
          title: 'Low Stock: ${item.name}',
          subtitle:
              'Only ${item.stock} units remaining. Reorder threshold is 15.',
          time: 'Live',
          severity: _AlertSeverity.critical,
          predictedHours: predicted,
          batch: item.batchNumber.isEmpty ? null : item.batchNumber,
        ),
      );
    }

    for (final item in overpriced) {
      alerts.add(
        _AlertItem(
          title: 'MoPH Ceiling Breach: ${item.name}',
          subtitle:
              'Current price \$${item.price.toStringAsFixed(2)} exceeds ceiling '
              '\$${(item.mophCeiling ?? 0).toStringAsFixed(2)}.',
          time: 'Live',
          severity: _AlertSeverity.pricing,
          actionLabel: 'Apply Price Now',
          newPriceDrug: _matchPatternFromName(item.name),
          newPriceValue: item.mophCeiling,
          barcode: item.barcode,
          currentPrice: item.price,
        ),
      );
    }

    if (syncedCount > 0) {
      alerts.add(
        _AlertItem(
          title:
              'Sync Acknowledged: $syncedCount Sale${syncedCount == 1 ? '' : 's'} Accepted',
          subtitle: 'Transactions acknowledged by the MoPH Command Center.',
          time: 'Now',
          severity: _AlertSeverity.syncAck,
          syncedCount: syncedCount,
        ),
      );
    }

    if (!mounted || token != _loadGeneration) return;
    setState(() {
      _alerts = alerts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final critical = _alerts
        .where((a) => a.severity == _AlertSeverity.critical)
        .toList();
    final pricing = _alerts
        .where((a) => a.severity == _AlertSeverity.pricing)
        .toList();
    final syncAcks = _alerts
        .where((a) => a.severity == _AlertSeverity.syncAck)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alerts', style: tt.headlineLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Stock warnings, expiry notices, MoH price updates.',
                    style: tt.bodyMedium?.copyWith(
                      color: MedTrackColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Mark all read chip
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _alerts = [];
                    _filter = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All alerts marked as read'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.done_all_rounded, size: 15),
                label: const Text('Mark All Read'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MedTrackColors.slateGrey,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: const RoundedRectangleBorder(
                    borderRadius: MedTrackShapes.buttonRadius,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Filter chips row ───────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All  ${_alerts.length}',
                  selected: _filter == null,
                  color: MedTrackColors.teal,
                  bg: const Color(0xFFCCFBF1),
                  borderColor: MedTrackColors.teal,
                  onTap: () => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Critical  ${_count(_AlertSeverity.critical)}',
                  selected: _filter == _AlertSeverity.critical,
                  color: MedTrackColors.error,
                  bg: MedTrackColors.errorContainer,
                  borderColor: MedTrackColors.error,
                  onTap: () =>
                      setState(() => _filter = _AlertSeverity.critical),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'MoH Pricing  ${_count(_AlertSeverity.pricing)}',
                  selected: _filter == _AlertSeverity.pricing,
                  color: const Color(0xFF7C3AED),
                  bg: const Color(0xFFEDE9FE),
                  borderColor: const Color(0xFF7C3AED),
                  onTap: () => setState(() => _filter = _AlertSeverity.pricing),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Sync Ack  ${_count(_AlertSeverity.syncAck)}',
                  selected: _filter == _AlertSeverity.syncAck,
                  color: MedTrackColors.teal,
                  bg: const Color(0xFFCCFBF1),
                  borderColor: MedTrackColors.teal,
                  onTap: () => setState(() => _filter = _AlertSeverity.syncAck),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Alert list ─────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 40,
                          color: MedTrackColors.textDisabled,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No alerts in this category',
                          style: tt.titleSmall?.copyWith(
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      if (_filter == null) ...[
                        ..._section(context, 'Critical', critical),
                        ..._section(context, 'MoH Pricing Updates', pricing),
                        ..._section(context, 'Sync Acknowledgements', syncAcks),
                      ] else ...[
                        ..._filtered.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AlertTile(alert: a),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<_AlertItem> items,
  ) {
    if (items.isEmpty) return [];
    final tt = Theme.of(context).textTheme;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: tt.titleMedium?.copyWith(color: MedTrackColors.textSecondary),
        ),
      ),
      ...items.map(
        (a) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _AlertTile(alert: a),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}

class _AlertTile extends StatefulWidget {
  const _AlertTile({required this.alert});
  final _AlertItem alert;

  @override
  State<_AlertTile> createState() => _AlertTileState();
}

class _AlertTileState extends State<_AlertTile> {
  bool _applied = false;
  bool _applying = false;

  bool get _canApplyPrice {
    final a = widget.alert;
    if (a.severity != _AlertSeverity.pricing) return true;
    if (a.barcode == null || a.barcode!.trim().isEmpty) return false;
    if (a.newPriceValue == null) return false;
    final current = a.currentPrice;
    if (current != null && current <= a.newPriceValue!) return false;
    return true;
  }

  Color get _iconColor {
    switch (widget.alert.severity) {
      case _AlertSeverity.critical:
        return MedTrackColors.error;
      case _AlertSeverity.pricing:
        return const Color(0xFF7C3AED);
      case _AlertSeverity.syncAck:
        return MedTrackColors.teal;
    }
  }

  Color get _bgColor {
    switch (widget.alert.severity) {
      case _AlertSeverity.critical:
        return MedTrackColors.errorContainer;
      case _AlertSeverity.pricing:
        return const Color(0xFFEDE9FE);
      case _AlertSeverity.syncAck:
        return const Color(0xFFCCFBF1);
    }
  }

  IconData get _icon {
    switch (widget.alert.severity) {
      case _AlertSeverity.critical:
        return Icons.error_rounded;
      case _AlertSeverity.pricing:
        return Icons.local_offer_rounded;
      case _AlertSeverity.syncAck:
        return Icons.cloud_done_rounded;
    }
  }

  Future<void> _applyPriceNow() async {
    final a = widget.alert;
    if (!_canApplyPrice) {
      return;
    }
    final barcode = a.barcode!.trim();
    final newPrice = a.newPriceValue!;
    setState(() => _applying = true);
    try {
      final ok = await InventoryDatabase.instance.setPrice(barcode, newPrice);
      if (!mounted) return;
      if (!ok) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to apply price: item was not found.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() {
        _applying = false;
        _applied = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied MoPH ceiling price to ${a.title.replaceFirst('MoPH Ceiling Breach: ', '')}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to apply price. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final a = widget.alert;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        borderRadius: MedTrackShapes.cardRadius,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: MedTrackShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            child: Icon(_icon, color: _iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row + tags
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.title,
                        style: tt.titleSmall?.copyWith(
                          color: MedTrackColors.textPrimary,
                        ),
                      ),
                    ),
                    // Batch tag
                    if (a.batch != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: MedTrackColors.surfaceVariant,
                          borderRadius: MedTrackShapes.chipRadius,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          a.batch!,
                          style: tt.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    // Predictive hours badge
                    if (a.predictedHours != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: a.predictedHours! <= 12
                              ? MedTrackColors.errorContainer
                              : MedTrackColors.warningContainer,
                          borderRadius: MedTrackShapes.chipRadius,
                        ),
                        child: Text(
                          '~${a.predictedHours}h to stock-out',
                          style: tt.labelSmall?.copyWith(
                            color: a.predictedHours! <= 12
                                ? MedTrackColors.error
                                : MedTrackColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(a.subtitle, style: tt.bodySmall),
                // Action button / sync count
                if (a.actionLabel != null) ...[
                  const SizedBox(height: 10),
                  _applied
                      ? Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: MedTrackColors.success,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Applied to inventory',
                              style: tt.labelSmall?.copyWith(
                                color: MedTrackColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : _applying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.icon(
                          onPressed: _canApplyPrice ? _applyPriceNow : null,
                          icon: Icon(
                            a.severity == _AlertSeverity.pricing
                                ? Icons.auto_fix_high_rounded
                                : Icons.add_shopping_cart_rounded,
                            size: 14,
                          ),
                          label: Text(
                            _canApplyPrice ? a.actionLabel! : 'Already Applied',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _iconColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            textStyle: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: MedTrackShapes.buttonRadius,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                ],
                // Sync-ack count badge
                if (a.syncedCount != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.sync_rounded,
                        size: 13,
                        color: MedTrackColors.teal,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${a.syncedCount} transaction${a.syncedCount! > 1 ? 's' : ''} acknowledged by MoPH Command Center',
                        style: tt.labelSmall?.copyWith(
                          color: MedTrackColors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(a.time, style: tt.labelSmall),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.bg,
    required this.borderColor,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final Color bg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? bg : MedTrackColors.surface,
          borderRadius: MedTrackShapes.chipRadius,
          border: Border.all(
            color: selected ? borderColor : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? color : MedTrackColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
