import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pharmacy.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'pharmacy_detail_screen.dart';

class PharmaciesListScreen extends StatefulWidget {
  const PharmaciesListScreen({super.key});

  @override
  State<PharmaciesListScreen> createState() => _PharmaciesListScreenState();
}

class _PharmaciesListScreenState extends State<PharmaciesListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Pharmacy> _filter(List<Pharmacy> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.location.toLowerCase().contains(q) ||
          p.region.toLowerCase().contains(q) ||
          p.stock.any((s) => s.medicationName.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final all = appState.nearbyPharmacies; // already sorted by distance when GPS known
    final filtered = _filter(all);

    return Scaffold(
      backgroundColor: MedTrackColors.background,
      appBar: AppBar(
        title: Text(
          'Pharmacies (${all.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: MedTrackColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Material(
              color: Colors.white,
              elevation: 0,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by pharmacy, area, or medication…',
                  hintStyle: const TextStyle(
                    color: MedTrackColors.textHint,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: MedTrackColors.textHint,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: MedTrackColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: MedTrackColors.divider,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: MedTrackColors.divider,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: MedTrackColors.primary,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PharmacyTile(
                      pharmacy: filtered[i],
                      hasUserLocation: appState.hasUserLocation,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PharmacyTile extends StatelessWidget {
  final Pharmacy pharmacy;
  final bool hasUserLocation;
  const _PharmacyTile({required this.pharmacy, required this.hasUserLocation});

  String get _distanceLabel {
    if (!hasUserLocation) return '—';
    if (pharmacy.distanceKm < 1) {
      return '${(pharmacy.distanceKm * 1000).round()} m';
    }
    return '${pharmacy.distanceKm.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final inStock = pharmacy.stock.where((s) => s.inStock).length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PharmacyDetailScreen(pharmacy: pharmacy),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MedTrackColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: pharmacy.isOpen
                      ? MedTrackColors.success.withValues(alpha: 0.12)
                      : MedTrackColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_pharmacy_rounded,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: MedTrackColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (pharmacy.location.isNotEmpty) pharmacy.location,
                        if (pharmacy.region.isNotEmpty) pharmacy.region,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: MedTrackColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 13,
                          color: MedTrackColors.secondary,
                        ),
                        Text(
                          ' ${pharmacy.rating.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 13,
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
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
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
                        _distanceLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
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
                      pharmacy.isOpen ? 'Open' : 'Closed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: pharmacy.isOpen
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
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: MedTrackColors.textHint,
            ),
            SizedBox(height: 12),
            Text(
              'No pharmacies match your search',
              style: TextStyle(
                fontSize: 14,
                color: MedTrackColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
