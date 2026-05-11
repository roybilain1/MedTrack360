import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notification_item.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/auth_gate.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Refresh once on open so the user sees fresh data even if AppState is stale.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final appState = context.read<AppState>();
    if (!appState.isLoggedIn) return;
    setState(() => _refreshing = true);
    try {
      await appState.loadNotifications();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (!appState.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: Colors.white,
          foregroundColor: MedTrackColors.textPrimary,
          elevation: 0,
        ),
        body: _GuestEmpty(),
      );
    }

    final all = appState.notifications;
    final priceChanges =
        all.where((n) => n.type == NotificationType.priceChange).toList();
    final stockAlerts =
        all.where((n) => n.type == NotificationType.outOfStock).toList();
    final news = all.where((n) => n.type == NotificationType.news).toList();
    final hasUnread = appState.unreadNotificationCount > 0;

    return Scaffold(
      backgroundColor: MedTrackColors.background,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: MedTrackColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => appState.markAllNotificationsRead(),
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: MedTrackColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: MedTrackColors.primary,
          unselectedLabelColor: MedTrackColors.textSecondary,
          indicatorColor: MedTrackColors.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: [
            _CountTab(label: 'All', count: all.length),
            _CountTab(label: 'Price', count: priceChanges.length),
            _CountTab(label: 'Stock', count: stockAlerts.length),
            _CountTab(label: 'News', count: news.length),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: MedTrackColors.primary,
        child: TabBarView(
          controller: _tabController,
          children: [
            _NotificationList(items: all, refreshing: _refreshing),
            _NotificationList(items: priceChanges, refreshing: _refreshing),
            _NotificationList(items: stockAlerts, refreshing: _refreshing),
            _NotificationList(items: news, refreshing: _refreshing),
          ],
        ),
      ),
    );
  }
}

class _CountTab extends StatelessWidget {
  final String label;
  final int count;
  const _CountTab({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: MedTrackColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MedTrackColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  final List<NotificationItem> items;
  final bool refreshing;
  const _NotificationList({required this.items, required this.refreshing});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: _EmptyState(refreshing: refreshing),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _NotificationCard(item: items[i]),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationItem item;
  const _NotificationCard({required this.item});

  ({IconData icon, Color color, String label}) get _meta {
    switch (item.type) {
      case NotificationType.priceChange:
        return (
          icon: Icons.trending_up_rounded,
          color: MedTrackColors.warning,
          label: 'Price change',
        );
      case NotificationType.outOfStock:
        return (
          icon: Icons.inventory_2_outlined,
          color: MedTrackColors.error,
          label: 'Out of stock',
        );
      case NotificationType.news:
        return (
          icon: Icons.campaign_outlined,
          color: MedTrackColors.info,
          label: 'Ministry of Health',
        );
      case NotificationType.other:
        return (
          icon: Icons.notifications_outlined,
          color: MedTrackColors.textSecondary,
          label: 'Update',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: item.isUnread
            ? meta.color.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (item.isUnread) {
              context.read<AppState>().markNotificationRead(item.id);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: item.isUnread
                    ? meta.color.withValues(alpha: 0.35)
                    : MedTrackColors.divider,
                width: item.isUnread ? 1.2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              meta.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: meta.color,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          Text(
                            _formatTime(item.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: MedTrackColors.textHint,
                            ),
                          ),
                          if (item.isUnread) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: meta.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: MedTrackColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  final bool refreshing;
  const _EmptyState({required this.refreshing});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: MedTrackColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 36,
              color: MedTrackColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You\'re all caught up',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: MedTrackColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Price changes, stock alerts and Ministry of Health news will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: MedTrackColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          if (refreshing) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuestEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: MedTrackColors.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Sign in to see notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MedTrackColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get alerts for price changes, out-of-stock medications in your watchlist, and Ministry of Health news.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: MedTrackColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MedTrackColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => showSignInRequiredSheet(
                context,
                icon: Icons.notifications_active_rounded,
                title: 'Sign in to see notifications',
                subtitle:
                    'Notifications follow your watchlist, so they need an account to stay in sync.',
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
