import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User card
            _buildUserCard(context, appState),
            const SizedBox(height: 16),

            // Login / Logout button
            _buildAuthButton(context, appState),
            const SizedBox(height: 24),

            // Quick Stats
            _buildStatsRow(context, appState),
            const SizedBox(height: 24),

            // Search history
            _buildSearchHistorySection(context, appState),
            const SizedBox(height: 24),

            // Coming Soon — AI-powered features (replaces Settings)
            _buildComingSoonSection(context),
            const SizedBox(height: 24),

            // About
            _buildAboutSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthButton(BuildContext context, AppState appState) {
    if (appState.isLoggedIn) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Log Out'),
                content: const Text('Are you sure you want to log out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      appState.logout();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logged out successfully'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Text(
                      'Log Out',
                      style: TextStyle(color: MedTrackColors.error),
                    ),
                  ),
                ],
              ),
            );
          },
          icon: Icon(Icons.logout, color: MedTrackColors.textSecondary),
          label: Text(
            'Log Out',
            style: TextStyle(
              color: MedTrackColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: MedTrackColors.border, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    } else {
      return Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              MedTrackColors.primaryDark,
              MedTrackColors.primary,
              MedTrackColors.teal,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: MedTrackColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          icon: const Icon(Icons.login, color: Colors.white),
          label: const Text(
            'Sign In',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildUserCard(BuildContext context, AppState appState) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Gradient banner
          Container(
            width: double.infinity,
            height: 80,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  MedTrackColors.primaryDark,
                  MedTrackColors.primary,
                  MedTrackColors.teal,
                ],
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -35),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Avatar over the banner
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 35,
                      backgroundColor: appState.isLoggedIn
                          ? MedTrackColors.secondary
                          : MedTrackColors.surfaceAlt,
                      child: Icon(
                        appState.isLoggedIn
                            ? Icons.person
                            : Icons.person_outline,
                        size: 36,
                        color: appState.isLoggedIn
                            ? Colors.white
                            : MedTrackColors.textHint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    appState.isLoggedIn ? appState.userName : 'Guest User',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appState.isLoggedIn
                        ? appState.userEmail
                        : 'Sign in to access all features',
                    style: TextStyle(
                      color: MedTrackColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: appState.isLoggedIn
                          ? MedTrackColors.tealLight
                          : MedTrackColors.warningLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          appState.isLoggedIn
                              ? Icons.verified_rounded
                              : Icons.info_outline,
                          size: 14,
                          color: appState.isLoggedIn
                              ? MedTrackColors.teal
                              : MedTrackColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          appState.isLoggedIn ? 'Active Account' : 'Guest Mode',
                          style: TextStyle(
                            color: appState.isLoggedIn
                                ? MedTrackColors.teal
                                : MedTrackColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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

  Widget _buildStatsRow(BuildContext context, AppState appState) {
    return Row(
      children: [
        _StatCard(
          icon: Icons.bookmark,
          label: 'Watchlist',
          value: '${appState.watchlist.length}',
          color: MedTrackColors.indigo,
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: Icons.history,
          label: 'Searches',
          value: '${appState.searchHistory.length}',
          color: MedTrackColors.secondary,
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: Icons.local_pharmacy,
          label: 'Pharmacies',
          value: '${appState.pharmacies.length}',
          color: MedTrackColors.teal,
        ),
      ],
    );
  }

  Widget _buildSearchHistorySection(BuildContext context, AppState appState) {
    final history = appState.searchHistory;
    final timeFormat = DateFormat('MMM d, h:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Search History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (history.isNotEmpty)
              TextButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear History'),
                      content: const Text(
                        'Are you sure you want to clear all search history?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            appState.clearSearchHistory();
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            'Clear',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Clear All'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 40,
                      color: MedTrackColors.divider,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No search history',
                      style: TextStyle(color: MedTrackColors.textHint),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: history.take(10).map((item) {
                return ListTile(
                  leading: const Icon(Icons.search, color: Colors.grey),
                  title: Text(item.query),
                  subtitle: Text(
                    timeFormat.format(item.searchedAt),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        appState.removeFromSearchHistory(item.query),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildComingSoonSection(BuildContext context) {
    final features = [
      (
        icon: Icons.psychology_alt_rounded,
        title: 'AI Symptom Checker',
        subtitle:
            'Describe how you feel and get AI-suggested medications and next steps.',
      ),
      (
        icon: Icons.science_rounded,
        title: 'AI Drug Interaction Scanner',
        subtitle:
            'Spot dangerous combinations across everything in your watchlist.',
      ),
      (
        icon: Icons.alarm_on_rounded,
        title: 'Smart AI Reminders',
        subtitle:
            'Personalised dosing schedules that adapt to your routine.',
      ),
      (
        icon: Icons.document_scanner_rounded,
        title: 'AI Prescription Scanner',
        subtitle:
            'Snap a photo of your prescription and auto-add it to your watchlist.',
      ),
      (
        icon: Icons.insights_rounded,
        title: 'Personalised Health Insights',
        subtitle:
            'AI-generated trends and savings tips from your pharmacy activity.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Coming Soon',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MedTrackColors.primary, MedTrackColors.teal],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'AI-powered features we\'re cooking up next.',
          style: TextStyle(fontSize: 13, color: MedTrackColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < features.length; i++) ...[
                _ComingSoonTile(
                  icon: features[i].icon,
                  title: features[i].title,
                  subtitle: features[i].subtitle,
                ),
                if (i < features.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'About',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            MedTrackColors.primaryDark,
                            MedTrackColors.teal,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.medical_services,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MedTrack360',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Version 1.0.0',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'MedTrack360 helps citizens find medications, compare prices, and locate nearby pharmacies with real-time stock information.',
                  style: TextStyle(
                    color: MedTrackColors.textSecondary,
                    fontSize: 14,
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.15)),
        ),
        color: color.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
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
          ),
        ),
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ComingSoonTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              MedTrackColors.primary.withValues(alpha: 0.18),
              MedTrackColors.teal.withValues(alpha: 0.22),
            ],
          ),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: MedTrackColors.primary, size: 22),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: MedTrackColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'SOON',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: MedTrackColors.warning,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: MedTrackColors.textSecondary,
          ),
        ),
      ),
      trailing: const Icon(
        Icons.auto_awesome,
        size: 18,
        color: MedTrackColors.secondary,
      ),
    );
  }
}
