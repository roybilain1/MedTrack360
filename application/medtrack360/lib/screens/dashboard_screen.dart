import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'medication_detail_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'pharmacies_list_screen.dart';
import 'pharmacy_detail_screen.dart';

// Dashboard uses MedTrackColors for full palette consistency.

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ─── App Bar (clean white) ───────────────────────
          SliverAppBar(
            floating: true,
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [MedTrackColors.primaryDark, MedTrackColors.teal],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_pharmacy_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                    children: [
                      TextSpan(
                        text: 'Med',
                        style: TextStyle(color: MedTrackColors.textPrimary),
                      ),
                      TextSpan(
                        text: 'Track',
                        style: TextStyle(color: MedTrackColors.primary),
                      ),
                      TextSpan(
                        text: '360',
                        style: TextStyle(
                          color: MedTrackColors.secondary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              const _SyncStatusChip(),
              _NotificationsBellAction(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _navigateToTab(context, 4),
                icon: const Icon(
                  Icons.person_outline,
                  color: MedTrackColors.textSecondary,
                ),
              ),
            ],
          ),

          // ─── Welcome Banner (card style) ─────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1A3A4A),
                      Color(0xFF1B5E4B),
                      Color(0xFF1A7365),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B5E4B).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hello there 👋',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Find your medication,\nanytime.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.medication_rounded,
                                  color: MedTrackColors.secondaryLight,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${appState.medications.length} medications tracked',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.medical_services_rounded,
                        color: Colors.white70,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ─── Search Bar ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: GestureDetector(
                onTap: () {
                  // Navigate to the search tab through parent
                  _navigateToTab(context, 1);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        color: MedTrackColors.textHint,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Search medications by name or category...',
                        style: TextStyle(
                          color: MedTrackColors.textHint,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ─── Quick Actions ───────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: MedTrackColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _QuickAction(
                        icon: Icons.search,
                        label: 'Search\nMedications',
                        color: MedTrackColors.info,
                        onTap: () => _navigateToTab(context, 1),
                      ),
                      const SizedBox(width: 12),
                      _QuickAction(
                        icon: Icons.map_rounded,
                        label: 'Nearby\nPharmacies',
                        color: MedTrackColors.teal,
                        onTap: () => _navigateToTab(context, 2),
                      ),
                      const SizedBox(width: 12),
                      _QuickAction(
                        icon: Icons.bookmark_rounded,
                        label: 'My\nWatchlist',
                        color: MedTrackColors.secondary,
                        onTap: () => _navigateToTab(context, 3),
                      ),
                      const SizedBox(width: 12),
                      _QuickAction(
                        icon: Icons.rate_review_rounded,
                        label: 'Rate\nPharmacy',
                        color: MedTrackColors.purple,
                        onTap: () => _navigateToTab(context, 2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ─── Stats Bar ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      MedTrackColors.indigo.withValues(alpha: 0.06),
                      MedTrackColors.teal.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: MedTrackColors.indigo.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      value: '${appState.medications.length}',
                      label: 'Medications',
                      icon: Icons.medication_rounded,
                      color: MedTrackColors.info,
                      onTap: () => _navigateToTab(context, 1),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: MedTrackColors.divider,
                    ),
                    _StatItem(
                      value: '${appState.pharmacies.length}',
                      label: 'Pharmacies',
                      icon: Icons.local_pharmacy_rounded,
                      color: MedTrackColors.teal,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PharmaciesListScreen(),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: MedTrackColors.divider,
                    ),
                    _StatItem(
                      value: '${appState.watchlist.length}',
                      label: 'Watchlist',
                      icon: Icons.bookmark_rounded,
                      color: MedTrackColors.secondary,
                      onTap: () => _navigateToTab(context, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ─── Popular Medications ─────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Popular Medications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: MedTrackColors.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _navigateToTab(context, 1),
                    child: const Text('See All'),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: SizedBox(
              height: 175,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: appState.medications.length > 6
                    ? 6
                    : appState.medications.length,
                itemBuilder: (context, index) {
                  final med = appState.medications[index];
                  final pharmacyCount = appState
                      .getPharmaciesWithMedication(med.key)
                      .length;
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MedicationDetailScreen(medication: med),
                        ),
                      );
                    },
                    child: Container(
                      width: 155,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: MedTrackColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.medication,
                              color: MedTrackColors.info,
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            med.tradeName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            med.genericName,
                            style: TextStyle(
                              fontSize: 12,
                              color: MedTrackColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '\$${med.mophCeiling.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: MedTrackColors.primaryDark,
                                  fontSize: 14,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: pharmacyCount > 0
                                      ? MedTrackColors.successLight
                                      : MedTrackColors.errorLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$pharmacyCount avail.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: pharmacyCount > 0
                                        ? MedTrackColors.success
                                        : MedTrackColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ─── Nearby Pharmacies Preview ───────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Nearby Pharmacies',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: MedTrackColors.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _navigateToTab(context, 2),
                    child: const Text('View Map'),
                  ),
                ],
              ),
            ),
          ),

          Builder(
            builder: (context) {
              final nearby = appState.nearbyPharmacies;
              final visible = nearby.take(3).toList();
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final pharmacy = visible[index];
                    final inStock = pharmacy.stock
                        .where((s) => s.inStock)
                        .length;
                    final distanceLabel = appState.hasUserLocation
                        ? (pharmacy.distanceKm < 1
                              ? '${(pharmacy.distanceKm * 1000).round()} m'
                              : '${pharmacy.distanceKm.toStringAsFixed(1)} km')
                        : '—';
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PharmacyDetailScreen(pharmacy: pharmacy),
                              ),
                            );
                          },
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: pharmacy.isOpen
                                  ? MedTrackColors.success
                                        .withValues(alpha: 0.1)
                                  : MedTrackColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.local_pharmacy_rounded,
                              color: pharmacy.isOpen
                                  ? MedTrackColors.success
                                  : MedTrackColors.error,
                            ),
                          ),
                          title: Text(
                            pharmacy.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                pharmacy.location,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: MedTrackColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star,
                                    size: 14,
                                    color: MedTrackColors.secondary,
                                  ),
                                  Text(
                                    ' ${pharmacy.rating}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 14,
                                    color: MedTrackColors.textHint,
                                  ),
                                  Text(
                                    ' $inStock in stock',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: MedTrackColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.near_me_rounded,
                                    size: 12,
                                    color: MedTrackColors.info,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    distanceLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PharmacyDetailScreen(
                                        pharmacy: pharmacy,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: MedTrackColors.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Open',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: visible.length,
                ),
              );
            },
          ),

          // ─── Bottom padding ──────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _navigateToTab(BuildContext context, int tabIndex) {
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    homeState?.switchTab(tabIndex);
  }
}

// ─── Quick Action Widget ──────────────────────────────────────
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Stat Item Widget ─────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    this.color = MedTrackColors.primary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: MedTrackColors.textSecondary,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: content,
      ),
    );
  }
}

// Bell icon with an unread-count badge driven by AppState.
class _NotificationsBellAction extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationsBellAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<AppState, int>(
      (s) => s.unreadNotificationCount,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: const Icon(
            Icons.notifications_outlined,
            color: MedTrackColors.textSecondary,
          ),
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: MedTrackColors.error,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Live appbar chip showing the 20s auto-sync state.
//   • While AppState.isSyncing → small spinner + "Syncing"
//   • Otherwise               → sync icon + "Xs ago" / "now"
// Internal 1s ticker keeps the "Xs ago" label fresh between sync events.
class _SyncStatusChip extends StatefulWidget {
  const _SyncStatusChip();

  @override
  State<_SyncStatusChip> createState() => _SyncStatusChipState();
}

class _SyncStatusChipState extends State<_SyncStatusChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _ago(DateTime? t) {
    if (t == null) return '…';
    final s = DateTime.now().difference(t).inSeconds;
    if (s <= 1) return 'now';
    if (s < 60) return '${s}s ago';
    return '${(s ~/ 60)}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final syncing = state.isSyncing;
    final color = syncing ? MedTrackColors.primary : MedTrackColors.success;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: syncing
            ? 'Syncing with Neon…'
            : 'Auto-sync every 20s · last update ${_ago(state.lastSyncedAt)}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (syncing)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              else
                Icon(Icons.cloud_done_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                syncing ? 'Syncing' : _ago(state.lastSyncedAt),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
