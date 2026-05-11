import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'medication_detail_screen.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (!appState.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Medicine Watchlist')),
        body: _buildSignInPrompt(context),
      );
    }

    final watchlist = appState.watchlist;
    final timeFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Medicine Watchlist')),
      body: watchlist.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: watchlist.length,
              itemBuilder: (context, index) {
                final item = watchlist[index];
                final medication = appState.medications
                    .where((m) => m.uuid == item.medicationId)
                    .firstOrNull;
                final pharmaciesWithStock = appState
                    .getPharmaciesWithMedication(item.medicationId);

                return Dismissible(
                  key: Key(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.delete,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  onDismissed: (_) async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await appState.removeFromWatchlist(item.medicationId);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${item.medicationName} removed from watchlist',
                          ),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () {
                              if (medication != null) {
                                appState.addToWatchlist(medication);
                              }
                            },
                          ),
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                          backgroundColor: MedTrackColors.error,
                        ),
                      );
                    }
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: medication != null
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MedicationDetailScreen(
                                    medication: medication,
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: MedTrackColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.medication,
                                    color: MedTrackColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.medicationName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        item.genericName,
                                        style: const TextStyle(
                                          color: MedTrackColors.textSecondary,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Notification toggle
                                Column(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        item.notifyOnAvailable
                                            ? Icons.notifications_active
                                            : Icons.notifications_off,
                                        color: item.notifyOnAvailable
                                            ? MedTrackColors.primary
                                            : MedTrackColors.textHint,
                                      ),
                                      onPressed: () {
                                        appState.toggleWatchlistNotification(
                                          item.id,
                                        );
                                      },
                                    ),
                                    Text(
                                      item.notifyOnAvailable
                                          ? 'Alerts On'
                                          : 'Alerts Off',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: item.notifyOnAvailable
                                            ? MedTrackColors.primary
                                            : MedTrackColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Added ${timeFormat.format(item.addedAt)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: MedTrackColors.textHint,
                                  ),
                                ),
                                if (pharmaciesWithStock.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: MedTrackColors.successLight,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.check_circle,
                                          size: 14,
                                          color: MedTrackColors.success,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${pharmaciesWithStock.length} nearby',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: MedTrackColors.success,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: MedTrackColors.errorLight,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.cancel,
                                          size: 14,
                                          color: MedTrackColors.error,
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Out of stock nearby',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: MedTrackColors.error,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
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
              },
            ),
    );
  }

  Widget _buildSignInPrompt(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 72,
              color: MedTrackColors.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign in to use your Watchlist',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your watchlist is saved to your account so you can access it '
              'from any device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MedTrackColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 80,
              color: MedTrackColors.divider,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Watchlist is Empty',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add medications to your watchlist to receive instant notifications when they become available at nearby pharmacies.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MedTrackColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MedTrackColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tips_and_updates,
                    color: MedTrackColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: const Text(
                      'Tip: Tap the bookmark icon on any medication to add it to your watchlist.',
                      style: TextStyle(
                        fontSize: 13,
                        color: MedTrackColors.primaryDark,
                      ),
                    ),
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
