import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/medication.dart';
import '../models/pharmacy.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/watchlist_actions.dart';
import 'pharmacy_detail_screen.dart';

class MedicationDetailScreen extends StatelessWidget {
  final Medication medication;

  const MedicationDetailScreen({super.key, required this.medication});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final pharmacies = appState.getPharmaciesWithMedication(medication.key);
    final inWatchlist = appState.isInWatchlist(medication.key);

    return Scaffold(
      appBar: AppBar(
        title: Text(medication.tradeName),
        actions: [
          IconButton(
            icon: Icon(inWatchlist ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => toggleWatchlist(context, medication),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Medication info card
            _buildInfoCard(context),
            const SizedBox(height: 16),

            // National Availability Score
            _buildAvailabilityCard(context),
            const SizedBox(height: 16),

            // Pricing info
            _buildPricingCard(context),
            const SizedBox(height: 24),

            // Available at pharmacies
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Available at ${pharmacies.length} ${pharmacies.length == 1 ? 'Pharmacy' : 'Pharmacies'}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (pharmacies.isNotEmpty)
                  Text(
                    'Sorted by distance',
                    style: TextStyle(
                      fontSize: 12,
                      color: MedTrackColors.textHint,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (pharmacies.isEmpty)
              _buildNoPharmacies(context)
            else
              ...pharmacies.map(
                (p) => _buildPharmacyCard(context, p, appState),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: MedTrackColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.medication,
                    size: 32,
                    color: MedTrackColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication.tradeName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        medication.genericName,
                        style: const TextStyle(
                          fontSize: 16,
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Dosage: ${medication.dosage}, Form: ${medication.form}',
              style: const TextStyle(
                color: MedTrackColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(icon: Icons.category, label: medication.category),
                _InfoChip(icon: Icons.medical_services, label: medication.form),
                _InfoChip(icon: Icons.science, label: medication.dosage),
                _InfoChip(icon: Icons.factory, label: medication.manufacturer),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityCard(BuildContext context) {
    final score = medication.mophCeiling / 100;
    final percent = (score * 100).toInt();
    final color = score >= 0.8
        ? MedTrackColors.success
        : (score >= 0.5 ? MedTrackColors.warning : MedTrackColors.error);
    final label = score >= 0.8
        ? 'Available'
        : (score >= 0.5 ? 'Moderately Available' : 'Rare / Low Stock');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: color),
                const SizedBox(width: 8),
                const Text(
                  'National Availability Score',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: score,
                      minHeight: 12,
                      backgroundColor: MedTrackColors.divider,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified, color: MedTrackColors.success),
                SizedBox(width: 8),
                Text(
                  'Ministry-Locked Price',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '\$${medication.mophCeiling.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: MedTrackColors.success,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MedTrackColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: MedTrackColors.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This is the official price set by the Ministry of Health. Pharmacies should not charge above this price.',
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

  Widget _buildNoPharmacies(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.local_pharmacy_outlined,
                size: 60,
                color: MedTrackColors.divider,
              ),
              const SizedBox(height: 12),
              const Text(
                'No nearby pharmacies have this in stock',
                style: TextStyle(
                  fontSize: 16,
                  color: MedTrackColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add it to your watchlist to be notified',
                style: TextStyle(fontSize: 14, color: MedTrackColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPharmacyCard(
    BuildContext context,
    Pharmacy pharmacy,
    AppState appState,
  ) {
    final stock = appState.getStockForMedication(pharmacy, medication.key);
    final timeFormat = DateFormat('MMM d, h:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PharmacyDetailScreen(pharmacy: pharmacy),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: pharmacy.isOpen
                          ? MedTrackColors.success.withValues(alpha: 0.1)
                          : MedTrackColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.local_pharmacy,
                      color: pharmacy.isOpen
                          ? MedTrackColors.success
                          : MedTrackColors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pharmacy.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          pharmacy.location,
                          style: const TextStyle(
                            fontSize: 13,
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${pharmacy.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            size: 14,
                            color: MedTrackColors.secondary,
                          ),
                          Text(
                            ' ${pharmacy.rating}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              if (stock != null) ...[
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Price',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Row(
                          children: [
                            Text(
                              '\$${stock.currentPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: stock.hasPriceDiscrepancy
                                    ? MedTrackColors.error
                                    : MedTrackColors.success,
                              ),
                            ),
                            if (stock.hasPriceDiscrepancy) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: MedTrackColors.errorLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Above Ministry Price',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: MedTrackColors.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Last Updated',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          timeFormat.format(stock.lastUpdated),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MedTrackColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: MedTrackColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: MedTrackColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
