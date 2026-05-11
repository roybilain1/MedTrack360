import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/sync_manager.dart';
import 'checkout/checkout_screen.dart';
import 'inventory/inventory_screen.dart';
import 'alerts/alerts_screen.dart';
import 'finances/finances_screen.dart';
import 'profile/profile_screen.dart';

// ── Navigation destination model ─────────────────────────────────────────────

class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavDestination> _destinations = [
  _NavDestination(
    label: 'Checkout',
    icon: Icons.shopping_cart_outlined,
    selectedIcon: Icons.shopping_cart_rounded,
  ),
  _NavDestination(
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
  ),
  _NavDestination(
    label: 'Alerts',
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications_rounded,
  ),
  _NavDestination(
    label: 'Finances',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart_rounded,
  ),
  _NavDestination(
    label: 'Profile',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

// ── Main Dashboard ────────────────────────────────────────────────────────────

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key, this.autoStartSync = true});

  final bool autoStartSync;

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _selectedIndex = 0;

  static final List<Widget> _screens = [
    const CheckoutScreen(),
    const InventoryScreen(),
    const AlertsScreen(),
    const FinancesScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Start restart-safe background sync engine.
    if (widget.autoStartSync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SyncManager.instance.start();
      });
    }
  }

  @override
  void dispose() {
    if (widget.autoStartSync) {
      SyncManager.instance.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedTrackColors.background,
      body: Row(
        children: [
          // ── NavigationRail ─────────────────────────────────────────────────
          _MedTrackRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          ),

          // ── Content area ───────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  pageTitle: _destinations[_selectedIndex].label,
                  onOpenAlerts: () => setState(() => _selectedIndex = 2),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom NavigationRail ─────────────────────────────────────────────────────

class _MedTrackRail extends StatelessWidget {
  const _MedTrackRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      decoration: BoxDecoration(
        color: MedTrackColors.navRailBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // ── Logo mark ───────────────────────────────────────────────────
            _LogoBadge(),
            const SizedBox(height: 32),
            // ── Nav items ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                children: List.generate(_destinations.length, (i) {
                  final dest = _destinations[i];
                  final isSelected = i == selectedIndex;
                  return _RailItem(
                    icon: isSelected ? dest.selectedIcon : dest.icon,
                    label: dest.label,
                    isSelected: isSelected,
                    onTap: () => onDestinationSelected(i),
                  );
                }),
              ),
            ),
            // ── Bottom divider + version ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                'v1.0',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: MedTrackColors.teal,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: const Icon(
            Icons.local_pharmacy_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'M360',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.70),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? MedTrackColors.navRailIndicator
                  : Colors.transparent,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.40),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.40),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top App Bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatefulWidget {
  const _TopBar({required this.pageTitle, required this.onOpenAlerts});
  final String pageTitle;
  final VoidCallback onOpenAlerts;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final dateStr =
        '${_weekday(now.weekday)}, ${_month(now.month)} ${now.day}, ${now.year}';

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: MedTrackColors.surface,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          // Breadcrumb
          Text(
            'MedTrack 360',
            style: tt.bodySmall?.copyWith(color: MedTrackColors.textSecondary),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: MedTrackColors.slateGreyLight,
            ),
          ),
          Text(
            widget.pageTitle,
            style: tt.titleMedium?.copyWith(color: MedTrackColors.teal),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: SyncManager.instance,
            builder: (context, _) {
              final sync = SyncManager.instance;
              final color = switch (sync.state) {
                SyncState.online => MedTrackColors.success,
                SyncState.syncing => MedTrackColors.teal,
                SyncState.checkingHealth => MedTrackColors.tealLight,
                SyncState.unauthorized => MedTrackColors.error,
                SyncState.offline => MedTrackColors.warning,
                SyncState.error => MedTrackColors.error,
                SyncState.idle => MedTrackColors.slateGrey,
              };
              final background = switch (sync.state) {
                SyncState.online => MedTrackColors.successContainer,
                SyncState.syncing => const Color(0xFFE0F2FE),
                SyncState.checkingHealth => const Color(0xFFE0F2FE),
                SyncState.unauthorized => MedTrackColors.errorContainer,
                SyncState.offline => MedTrackColors.warningContainer,
                SyncState.error => MedTrackColors.errorContainer,
                SyncState.idle => const Color(0xFFF1F5F9),
              };

              return Tooltip(
                message: sync.statusDetail,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          sync.statusMessage,
                          key: ValueKey(sync.statusMessage),
                          style: tt.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          // Date
          Text(
            dateStr,
            style: tt.bodySmall?.copyWith(color: MedTrackColors.textSecondary),
          ),
          const SizedBox(width: 20),
          // Alert badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: MedTrackColors.slateGrey,
                ),
                onPressed: widget.onOpenAlerts,
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: MedTrackColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          // Avatar
          const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFCCFBF1),
            child: Text(
              'JT',
              style: TextStyle(
                color: MedTrackColors.teal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _weekday(int d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
  String _month(int m) => [
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
