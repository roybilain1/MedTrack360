import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pharmacy.dart';
import '../models/review.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/auth_gate.dart';

class PharmacyDetailScreen extends StatelessWidget {
  final Pharmacy pharmacy;

  const PharmacyDetailScreen({super.key, required this.pharmacy});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final reviews = appState.getReviewsForPharmacy(pharmacy.id.toString());

    return Scaffold(
      appBar: AppBar(
        title: Text(pharmacy.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.directions),
            onPressed: () => _openDirections(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPharmacyInfoCard(context),
            const SizedBox(height: 16),
            _buildStockCard(context),
            const SizedBox(height: 24),

            // Reviews section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reviews (${reviews.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.rate_review, size: 18),
                  label: const Text('Write Review'),
                  onPressed: () {
                    if (!appState.isLoggedIn) {
                      showSignInRequiredSheet(
                        context,
                        icon: Icons.rate_review_rounded,
                        title: 'Sign in to write a review',
                        subtitle:
                            'Reviews help other patients find reliable '
                            'pharmacies. Sign in with your MedTrack360 '
                            'account to share your experience.',
                      );
                      return;
                    }
                    _showReviewDialog(context, appState);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (reviews.isEmpty)
              _buildNoReviews()
            else
              ...reviews.map((r) => _buildReviewCard(context, r)),
          ],
        ),
      ),
    );
  }

  Widget _buildPharmacyInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: pharmacy.isOpen
                        ? MedTrackColors.success.withValues(alpha: 0.1)
                        : MedTrackColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.local_pharmacy,
                    size: 30,
                    color: pharmacy.isOpen
                        ? MedTrackColors.success
                        : MedTrackColors.error,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pharmacy.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: pharmacy.isOpen
                              ? MedTrackColors.successLight
                              : MedTrackColors.errorLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          pharmacy.isOpen ? 'Open Now' : 'Closed',
                          style: TextStyle(
                            color: pharmacy.isOpen
                                ? MedTrackColors.success
                                : MedTrackColors.error,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(icon: Icons.location_on, label: pharmacy.location),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.access_time,
              label:
                  'Hours: ${pharmacy.openingHours} - ${pharmacy.closingHours}',
            ),
            const SizedBox(height: 8),
            _DetailRow(icon: Icons.phone, label: pharmacy.phone),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.near_me,
              label: '${pharmacy.distanceKm.toStringAsFixed(1)} km away',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.star,
                  color: MedTrackColors.secondary,
                  size: 22,
                ),
                const SizedBox(width: 4),
                Text(
                  '${pharmacy.rating}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${pharmacy.reviewCount} reviews)',
                  style: const TextStyle(color: MedTrackColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockCard(BuildContext context) {
    final timeFormat = DateFormat('MMM d, h:mm a');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2, color: MedTrackColors.primary),
                SizedBox(width: 8),
                Text(
                  'Current Stock',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (pharmacy.stock.isEmpty)
              const Text('No stock information available')
            else
              ...pharmacy.stock.map((stock) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: stock.inStock
                        ? MedTrackColors.successLight
                        : MedTrackColors.errorLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: stock.inStock
                          ? MedTrackColors.success.withValues(alpha: 0.3)
                          : MedTrackColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              stock.medicationName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: stock.inStock
                                  ? MedTrackColors.success
                                  : MedTrackColors.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              stock.inStock ? 'In Stock' : 'Out of Stock',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pharmacy Price',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: MedTrackColors.textHint,
                                ),
                              ),
                              Text(
                                '\$${stock.currentPrice.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: stock.hasPriceDiscrepancy
                                      ? MedTrackColors.error
                                      : MedTrackColors.success,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Ministry Price',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: MedTrackColors.textHint,
                                ),
                              ),
                              Text(
                                '\$${stock.ministryLockedPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: MedTrackColors.success,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Last Updated',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: MedTrackColors.textHint,
                                ),
                              ),
                              Text(
                                timeFormat.format(stock.lastUpdated),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (stock.hasPriceDiscrepancy) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: MedTrackColors.errorLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                size: 16,
                                color: MedTrackColors.error,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Price is above Ministry-Locked price by \$${(stock.currentPrice - stock.ministryLockedPrice).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: MedTrackColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildNoReviews() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.rate_review_outlined,
                size: 50,
                color: MedTrackColors.divider,
              ),
              const SizedBox(height: 12),
              const Text(
                'No reviews yet',
                style: TextStyle(
                  color: MedTrackColors.textSecondary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Be the first to review!',
                style: TextStyle(color: MedTrackColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewCard(BuildContext context, Review review) {
    final timeFormat = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: MedTrackColors.primary.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        review.userName[0],
                        style: const TextStyle(
                          color: MedTrackColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review.userName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          timeFormat.format(review.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: MedTrackColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (review.hasDiscrepancyReport)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MedTrackColors.errorLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.report_problem,
                          size: 14,
                          color: MedTrackColors.error,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Discrepancy',
                          style: TextStyle(
                            fontSize: 11,
                            color: MedTrackColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _RatingLabel(
                  label: 'Stock Accuracy',
                  rating: review.stockAccuracyRating,
                ),
                const SizedBox(width: 16),
                _RatingLabel(
                  label: 'Service Quality',
                  rating: review.serviceQualityRating,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              review.comment,
              style: const TextStyle(color: MedTrackColors.textSecondary),
            ),
            if (review.hasDiscrepancyReport &&
                review.discrepancyDetails != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MedTrackColors.errorLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: MedTrackColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.report,
                      size: 18,
                      color: MedTrackColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        review.discrepancyDetails!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: MedTrackColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReviewDialog(BuildContext context, AppState appState) {
    double stockAccuracy = 3.0;
    double serviceQuality = 3.0;
    final commentController = TextEditingController();
    bool reportDiscrepancy = false;
    final discrepancyController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Write a Review',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'Stock Accuracy',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    RatingBar.builder(
                      initialRating: stockAccuracy,
                      minRating: 1,
                      allowHalfRating: true,
                      itemSize: 36,
                      itemBuilder: (context, _) => const Icon(
                        Icons.star,
                        color: MedTrackColors.secondary,
                      ),
                      onRatingUpdate: (rating) {
                        stockAccuracy = rating;
                      },
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Service Quality',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    RatingBar.builder(
                      initialRating: serviceQuality,
                      minRating: 1,
                      allowHalfRating: true,
                      itemSize: 36,
                      itemBuilder: (context, _) => const Icon(
                        Icons.star,
                        color: MedTrackColors.secondary,
                      ),
                      onRatingUpdate: (rating) {
                        serviceQuality = rating;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: commentController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Your comment',
                        hintText: 'Share your experience...',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Discrepancy report
                    CheckboxListTile(
                      value: reportDiscrepancy,
                      onChanged: (val) {
                        setSheetState(() => reportDiscrepancy = val ?? false);
                      },
                      title: const Text(
                        'Report a stock discrepancy',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        'The app shows stock that isn\'t physically there',
                        style: TextStyle(fontSize: 12),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),

                    if (reportDiscrepancy) ...[
                      TextField(
                        controller: discrepancyController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Discrepancy details',
                          hintText:
                              'Which medication was listed but not available?',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (commentController.text.trim().isEmpty) return;
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(context);
                          try {
                            await appState.addReview(
                              pharmacyId: pharmacy.id.toString(),
                              stockAccuracy: stockAccuracy,
                              serviceQuality: serviceQuality,
                              comment: commentController.text.trim(),
                              hasDiscrepancy: reportDiscrepancy,
                              discrepancyDetails: reportDiscrepancy
                                  ? discrepancyController.text.trim()
                                  : null,
                            );
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Review submitted! Thank you.'),
                                backgroundColor: MedTrackColors.success,
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
                        child: const Text('Submit Review'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openDirections() async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${pharmacy.latitude},${pharmacy.longitude}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MedTrackColors.textHint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: MedTrackColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingLabel extends StatelessWidget {
  final String label;
  final double rating;

  const _RatingLabel({required this.label, required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: MedTrackColors.textHint),
        ),
        const Icon(Icons.star, size: 14, color: MedTrackColors.secondary),
        Text(
          ' ${rating.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
